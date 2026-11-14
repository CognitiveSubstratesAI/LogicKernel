#!/usr/bin/env python3
# ORIGINAL: no swipl-devel counterpart. THE RUNNER for R2 acceptance item (c) (audit D-0624/D-0625): a MEASURED count of
# the swipl-devel test files that run and pass through the kernel (X of N), with the rest listed and, for each
# file that does not pass, a guess at the owner of what it lacks.
#
#   tools/swipl_tests_run.sh [--list TSV] [--timeout S] [--nice N] [--redo] [--only RE] [--limit N] [--summary]
#
# WHAT IT DOES. The test sources are read ONLY from the pin (`git archive <tools/SWIPL_VERSION commit> tests`
# from the swipl-devel checkout: LOGICKERNEL_UPSTREAM_SWIPL_DEVEL or ~/dev-zone/swipl-devel, whatever its working tree
# holds) into <repo>/.warm/swipl_tests/src (untracked). Each listed file runs in its OWN kernel process, one at a
# time, in the file's own directory, under a wall limit (default 120 s, LK_TESTS_TIMEOUT or --timeout), and the
# process group is killed at the limit. WHY A PROCESS PER FILE and not the warm daemon: a file that loops or
# overruns can only be stopped by killing its process (the daemon answers a timeout with exit 2 and keeps running
# the job); state of one file cannot leak into the next (flags, modules, files opened); a boot costs seconds per
# file but nothing is shared with a gate's daemon (two daemons at most, D-0114: this runner starts none).
#
# THE KERNEL COMMAND. KERNEL_CMD (a shell-split string; the test file's absolute path is appended as the last
# argument) defaults to `tools/julia_pin.sh run julia --project=<repo> tools/swipl_tests_kernel.jl`. The command prints
# `LK-RESULT <kind> <text>` lines on stdout (tools/swipl_tests_harness.pl); this driver reads nothing else.
#
# CLASSES (the TSV's class column): PASS · FAIL(n tests) · ERROR(load) · ERROR(run) · TIMEOUT · NOT-RUNNABLE(reason).
# RESUMABLE: a file already in the TSV is skipped unless --redo (every file) or --only RE --redo (the files matching).
# THE TSV: file, class, passed, failed, seconds, first_error, owner_guess. owner_guess is read from the error text
# against docs/r2_owners.tsv (a procedure `name/N` -> its `pred:` row, a flag name -> `flag:`, a kernel refusal's message
# -> `refusal:`); with none of those, from evidence/r2/tests_needs.tsv's static list of C predicates the file calls
# that the kernel lacks (`static:` prefix: a weaker guess); else `unknown`.
#
# UNVERIFIED until a lane runs it: written without a kernel (a WRITER step). tools/test_swipl_tests_run.sh tests the
# classifier and the bookkeeping over a fake kernel command.
import argparse
import csv
import os
import re
import shlex
import signal
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANNEL_EVIDENCE = os.path.expanduser("~/code/lk-channel/evidence/r2")
HEADER = ["file", "class", "passed", "failed", "seconds", "first_error", "owner_guess"]
RESULT_RE = re.compile(r"LK-RESULT (\S+)(?: (.*))?$")
KV_RE = re.compile(r"(\w+)=(\d+)")
PROC_RE = re.compile(r"(?<![\w$])'?([A-Za-z_$][\w$]*)'?/(\d+)\b")
FLAG_RE = re.compile(r"[Ff]lag[^A-Za-z0-9_\n]{1,4}'?([a-z_][a-z0-9_]*)")


def pin_commit():
    """The pinned swipl-devel commit: LK_TESTS_PIN, else tools/SWIPL_VERSION's `commit:` line."""
    if os.environ.get("LK_TESTS_PIN"):
        return os.environ["LK_TESTS_PIN"]
    with open(os.path.join(ROOT, "tools", "SWIPL_VERSION")) as f:
        for line in f:
            if line.startswith("commit:"):
                return line.split(":", 1)[1].strip()
    sys.exit("swipl_tests_run: tools/SWIPL_VERSION holds no commit: line")


def read_list(path):
    """The test files, in the list's order: column 1 of a TSV; a header line (a first column not ending in .pl) is skipped."""
    files = []
    with open(path) as f:
        for line in f:
            col = line.rstrip("\n").split("\t")[0].strip()
            if col and not col.startswith("#") and col.endswith(".pl") and col not in files:
                files.append(col)
    return files


def read_owners(path):
    """docs/r2_owners.tsv as {key: owner}."""
    owners = {}
    if path and os.path.isfile(path):
        with open(path) as f:
            for line in f:
                if line.startswith("#") or not line.strip():
                    continue
                cols = line.rstrip("\n").split("\t")
                if len(cols) >= 2:
                    owners[cols[0]] = cols[1]
    return owners


def read_static(path):
    """tests_needs.tsv as {file: [name/N, ...]}: column top_c_missing_in_kernel (the file's C predicates the kernel lacks)."""
    out = {}
    if path and os.path.isfile(path):
        with open(path) as f:
            rows = csv.reader(f, delimiter="\t")
            head = next(rows, [])
            if "top_c_missing" not in head:
                return out
            i = head.index("top_c_missing")
            for r in rows:
                if len(r) > i and r[0]:
                    out[r[0]] = r[i].split()
    return out


def materialise(work, commit):
    """The pin's tests/ tree under <work>/src, once per commit; returns its path. git archive reads the commit, never a working tree."""
    src = os.path.join(work, "src")
    stamp = os.path.join(work, "src.commit")
    if os.path.isfile(stamp) and open(stamp).read().strip() == commit and os.path.isdir(os.path.join(src, "tests")):
        return src
    repo = os.environ.get("LOGICKERNEL_UPSTREAM_SWIPL_DEVEL") or os.path.expanduser("~/dev-zone/swipl-devel")
    os.makedirs(src, exist_ok=True)
    arc = subprocess.run(["git", "-C", repo, "archive", commit, "tests"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if arc.returncode != 0:
        sys.exit("swipl_tests_run: git archive %s in %s failed: %s" % (commit, repo, arc.stderr.decode(errors="replace").strip()))
    tar = subprocess.run(["tar", "-x", "-C", src], input=arc.stdout, stderr=subprocess.PIPE)
    if tar.returncode != 0:
        sys.exit("swipl_tests_run: tar failed: " + tar.stderr.decode(errors="replace").strip())
    with open(stamp, "w") as f:
        f.write(commit + "\n")
    return src


def default_kernel_cmd():
    return "%s run julia --project=%s %s" % (
        os.path.join(ROOT, "tools", "julia_pin.sh"),
        ROOT,
        os.path.join(ROOT, "tools", "swipl_tests_kernel.jl"),
    )


def parse_results(text):
    """The LK-RESULT lines of a run's stdout as [(kind, rest)]."""
    out = []
    for line in text.splitlines():
        m = RESULT_RE.search(line)
        if m:
            out.append((m.group(1), (m.group(2) or "").strip()))
    return out


def one_line(s, n=200):
    return re.sub(r"\s+", " ", s).strip()[:n]


def classify(results, rc, timed_out):
    """(class, passed, failed) from a run's result lines, the exit status and the wall-limit flag."""
    if timed_out:
        return "TIMEOUT", 0, 0
    kinds = [k for k, _ in results]
    for k, rest in results:
        if k == "not-runnable":
            return "NOT-RUNNABLE(%s)" % one_line(rest, 80), 0, 0
    if "load-error" in kinds or "load-failed" in kinds or "harness-error" in kinds:
        return "ERROR(load)", 0, 0
    if not results:
        return "ERROR(load)", 0, 0  # the kernel gave no verdict at all: it did not get as far as the file's tests
    if "run-error" in kinds:
        return "ERROR(run)", 0, 0
    passed = failed = tests = 0
    for k, rest in results:
        if k == "summary":
            d = {a: int(b) for a, b in KV_RE.findall(rest)}
            passed += d.get("passed", 0)
            failed += d.get("failed", 0) + d.get("timeout", 0)
            tests += d.get("passed", 0) + d.get("failed", 0) + d.get("timeout", 0) + d.get("blocked", 0) + d.get("fixme", 0)
        elif k == "script":
            tests += 1
            if rest == "passed":
                passed += 1
            else:
                failed += 1
    if failed > 0:
        return "FAIL(%d tests)" % failed, passed, failed
    if tests == 0:
        return "NOT-RUNNABLE(no tests)", 0, 0
    return "PASS", passed, 0


def first_error(results, stdout, stderr):
    """The first error line: a result line's error text, else the first stderr line that reads as an error, else its last line."""
    for k, rest in results:
        if k in ("load-error", "run-error", "harness-error", "load-failed", "not-runnable"):
            return one_line(k + " " + rest)
    lines = [l for l in stderr.splitlines() if l.strip()]
    for l in lines:
        if re.search(r"\b(ERROR|error|Error)\b|existence_error|Unknown procedure|not ported", l):
            return one_line(l)
    if lines:
        return one_line(lines[-1])
    return ""


def guess_owner(text, owners, static_list):
    """Who owns what the error text names: a procedure, a flag, a refusal message; else the static list's first owned predicate; else unknown."""
    for m in PROC_RE.finditer(text):
        key = "pred:%s/%s" % (m.group(1), m.group(2))
        if key in owners:
            return "%s (%s)" % (owners[key], key)
    for m in FLAG_RE.finditer(text):
        key = "flag:" + m.group(1)
        if key in owners:
            return "%s (%s)" % (owners[key], key)
    for key, owner in owners.items():
        if key.startswith("refusal:"):
            msg = key.split("::")[-1]
            if len(msg) >= 8 and msg in text:
                return "%s (refusal)" % owner
    for name in static_list:
        key = "pred:" + name
        if key in owners:
            return "static:%s (%s)" % (owners[key], key)
    return "unknown"


def run_one(cmd, cwd, path, limit, nice, logbase):
    """Run the kernel command on `path`; returns (stdout, stderr, rc, timed_out, seconds). The process group is killed at the limit."""
    full = shlex.split(cmd) + [path]
    if nice:
        full = ["nice", "-n", str(nice)] + full
    out = open(logbase + ".out", "w+b")
    err = open(logbase + ".err", "w+b")
    t0 = time.monotonic()
    timed_out = False
    try:
        p = subprocess.Popen(full, cwd=cwd, stdin=subprocess.DEVNULL, stdout=out, stderr=err, start_new_session=True)
    except OSError as e:
        out.close()
        err.close()
        return "", "kernel command did not start: %s" % e, 127, False, 0.0
    try:
        rc = p.wait(timeout=limit)
    except subprocess.TimeoutExpired:
        timed_out = True
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(p.pid, sig)
            except ProcessLookupError:
                break
            try:
                p.wait(timeout=5)
                break
            except subprocess.TimeoutExpired:
                continue
        rc = -9
    secs = time.monotonic() - t0
    texts = []
    for fh in (out, err):
        fh.seek(0)
        texts.append(fh.read(4 << 20).decode("utf-8", errors="replace"))
        fh.close()
    return texts[0], texts[1], rc, timed_out, secs


def read_tsv(path):
    rows = {}
    if os.path.isfile(path):
        with open(path) as f:
            for r in csv.reader(f, delimiter="\t"):
                if r and r[0] != "file" and len(r) >= 7:
                    rows[r[0]] = r[:7]
    return rows


def write_tsv(path, order, rows):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(HEADER)
        for name in order:
            if name in rows:
                w.writerow(rows[name])
    os.replace(tmp, path)


def family(cls):
    return cls.split("(")[0]


def summary_text(order, rows, tsv_path):
    n = len(order)
    cnt = {}
    for name in order:
        c = family(rows[name][1]) if name in rows else "not-run"
        cnt[c] = cnt.get(c, 0) + 1
    owners = {}
    for name in order:
        if name in rows and rows[name][1] != "PASS":
            o = rows[name][6].split(" ")[0] if rows[name][6] else "unknown"
            owners[o] = owners.get(o, 0) + 1
    lines = ["swipl-devel test files through the kernel: %d of %d pass" % (cnt.get("PASS", 0), n)]
    lines.append("  " + " | ".join("%s %d" % (k, v) for k, v in sorted(cnt.items())))
    if owners:
        top = sorted(owners.items(), key=lambda kv: (-kv[1], kv[0]))[:14]
        lines.append("  owner guess of the rest: " + ", ".join("%s %d" % kv for kv in top))
    lines.append("  list: " + tsv_path)
    return "\n".join(lines)


def main(argv):
    ap = argparse.ArgumentParser(description="Run the pinned swipl-devel test files through the kernel, one process per file.")
    ap.add_argument("--list", default=os.environ.get("LK_TESTS_LIST") or os.path.join(CHANNEL_EVIDENCE, "tests_by_fewest_missing.tsv"))
    ap.add_argument("--work", default=os.environ.get("LK_TESTS_WORK") or os.path.join(ROOT, ".warm", "swipl_tests"))
    ap.add_argument("--tsv", default=None)
    ap.add_argument("--owners", default=os.environ.get("LK_TESTS_OWNERS") or os.path.join(ROOT, "docs", "r2_owners.tsv"))
    ap.add_argument("--needs", default=os.environ.get("LK_TESTS_NEEDS") or os.path.join(CHANNEL_EVIDENCE, "tests_needs.tsv"))
    ap.add_argument("--timeout", type=float, default=float(os.environ.get("LK_TESTS_TIMEOUT", "120")))
    ap.add_argument("--nice", type=int, default=int(os.environ.get("LK_TESTS_NICE", "0")))
    ap.add_argument("--redo", action="store_true", help="run files already in the TSV again (with --only: the matching ones)")
    ap.add_argument("--only", default=None, help="a regex on the file's path: run only those")
    ap.add_argument("--limit", type=int, default=0, help="run at most N files this time")
    ap.add_argument("--summary", action="store_true", help="print the summary of the TSV and run nothing")
    a = ap.parse_args(argv)

    os.makedirs(a.work, exist_ok=True)
    tsv = a.tsv or os.path.join(a.work, "results.tsv")
    if not os.path.isfile(a.list):
        sys.exit("swipl_tests_run: the list %s is not readable (--list FILE)" % a.list)
    order = read_list(a.list)
    rows = read_tsv(tsv)
    if a.summary:
        print(summary_text(order, rows, tsv))
        return 0
    cmd = os.environ.get("KERNEL_CMD") or default_kernel_cmd()
    commit = pin_commit()
    src = materialise(a.work, commit)
    owners = read_owners(a.owners)
    static = read_static(a.needs)
    logdir = os.path.join(a.work, "logs")
    os.makedirs(logdir, exist_ok=True)
    only = re.compile(a.only) if a.only else None
    done = 0
    for name in order:
        if only and not only.search(name):
            continue
        if name in rows and not a.redo:
            continue
        if a.limit and done >= a.limit:
            break
        path = os.path.join(src, name)
        if not os.path.isfile(path):
            rows[name] = [name, "NOT-RUNNABLE(not in pin)", "0", "0", "0.0", "the file is not in tests/ at " + commit[:8], "unknown"]
        else:
            logbase = os.path.join(logdir, name.replace("/", "__"))
            so, se, rc, timed_out, secs = run_one(cmd, os.path.dirname(path), path, a.timeout, a.nice, logbase)
            results = parse_results(so)
            cls, passed, failed = classify(results, rc, timed_out)
            err = first_error(results, so, se)
            if not results and not timed_out:
                err = one_line("no verdict from the kernel, exit %d: %s" % (rc, err))
            if cls == "TIMEOUT":
                err = "wall limit %gs" % a.timeout
            text = "\n".join(rest for k, rest in results if k != "summary") + "\n" + se[-65536:]
            owner = "" if cls == "PASS" else guess_owner(text, owners, static.get(name, []))
            rows[name] = [name, cls, str(passed), str(failed), "%.1f" % secs, err, owner]
        write_tsv(tsv, order, rows)
        done += 1
        print("[%d] %s: %s" % (done, name, rows[name][1]), flush=True)
    write_tsv(tsv, order, rows)
    text = summary_text(order, rows, tsv)
    with open(os.path.join(a.work, "summary.txt"), "w") as f:
        f.write(text + "\n")
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
