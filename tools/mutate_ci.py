#!/usr/bin/env python3
# ORIGINAL: the mutation battery's CI side (user, 2026-10-13) — no swipl-devel counterpart.
# tools/mutate_ci.py — what .github/workflows/mutation.yml calls. The LOCAL
# driver is tools/mutate_drive.py (a warm daemon, one mutant after another); here every mutant is a
# CI job of its own, so the three steps are separate commands. THE MUTANT LIST AND THE VERDICT RULES
# ARE THE SAME (see mutate_drive.py's header): `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `expect: "hang"`, `equivalent: <reason>`, `targets`.
#
#   mutate_ci.py plan MUTANTS.py [ID…]            print `matrix=…`, `count=…` and `targets=…` (the
#                                                 list's own `TARGETS`, space-separated; empty when
#                                                 it names none) for $GITHUB_OUTPUT
#   mutate_ci.py baseline LIMIT_S TARGET…         the targets on the unmutated tree → baseline.json
#   mutate_ci.py one MUTANTS.py ID LIMIT_S TARGET…   apply ID, run the targets → <ID>.json, <ID>.log
#   mutate_ci.py collect MUTANTS.py COUNT [ID…]   the verdict table (stdout, verdicts.md); exit 0/1
#   mutate_ci.py annotate                         verdicts.md as notice annotations (stdout): a check
#                                                 run's annotations are readable through the API
#                                                 without a token, its job summary and logs are not
#
# A TARGET is a test file, run in a FRESH process on the reference term type
# (`julia --project=. <file>`, LOGICKERNEL_TERM=reference) — or `sh:<command>`.
# THE VERDICT, from exit codes first: a target exits 1 = caught; every target exits 0 = SURVIVED; a
# target past LIMIT_S = TIMEOUT (never "caught", unless the mutant expects a hang); another code =
# INVALID. An exit 1 is caught only when a test failed — mutate_drive.py's `judge`, the one
# classifier of both drivers (D-0050): code that did not parse or load = NO VERDICT (does not load);
# a test file with no failing test line = NO VERDICT (no failing test). A mutant declared
# `equivalent` must SURVIVE ("EQUIVALENT (declared)"); caught, its claim was wrong ("EQUIVALENT
# REFUTED"). BLOCKING: SURVIVED, TIMEOUT, INVALID, BADMATCH, EQUIVALENT REFUTED, NO VERDICT (either
# kind, or a missing verdict file), a baseline that is not green. Every record keeps the deciding
# line (`first_failure`: a caught one's first failing test line); the table shows it.
import json
import os
import runpy
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True     # no tools/__pycache__: an untracked file voids the evidence marker
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mutate_drive import judge, noload_hint, run_targets as _run_targets  # noqa: E402 — one classifier, two drivers

OUT = "mutation-out"
BLOCKING = ("SURVIVED", "TIMEOUT", "INVALID", "BADMATCH", "EQUIVALENT REFUTED", "NO VERDICT")


def load(path, only):
    mutants = runpy.run_path(path)["MUTANTS"]
    names = [m["id"].split()[0] for m in mutants]
    if len(set(names)) != len(names):
        sys.exit("mutate_ci: two mutants share a name in %s" % path)
    unknown = set(only) - set(names)
    if unknown:
        sys.exit("mutate_ci: no such mutant: %s" % ", ".join(sorted(unknown)))
    return [m for m in mutants if not only or m["id"].split()[0] in only]


def run_target(target, limit):
    """(exit code or "hang", output) of one target in a fresh process GROUP: past the limit the whole
    group is killed — a test's own children (swipl) hold the output pipe open otherwise, and the
    read would wait for them."""
    env = dict(os.environ, LOGICKERNEL_TERM="reference")
    cmd = ["julia", "--project=.", "--startup-file=no", target]
    if target.startswith("sh:"):
        cmd = ["bash", "-c", target[3:]]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         env=env, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=limit)
        return p.returncode, out
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, _ = p.communicate()
        return "hang", out


def run_targets(targets, limit):
    """mutate_drive.py's `run_targets`, each target in a fresh process: (result, log, line)."""
    def run1(t):
        rc, out = run_target(t, limit)
        return judge(t, rc, out, os.getcwd())[0], out
    return _run_targets(targets, run1, os.getcwd())


def write(name, record, log):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(record, f)
    with open(os.path.join(OUT, name + ".log"), "w") as f:
        f.write(log)


def plan(argv):
    mutants = load(argv[0], argv[1:])
    if not mutants:
        sys.exit("mutate_ci: the plan is empty")
    matrix = {"include": [{"name": m["id"].split()[0]} for m in mutants]}
    print("matrix=" + json.dumps(matrix))
    print("count=%d" % len(mutants))
    # the list's own targets: what a run started by a push (no inputs) uses
    targets = runpy.run_path(argv[0]).get("TARGETS", [])
    if any(" " in t or "\n" in t for t in targets):
        sys.exit("mutate_ci: a target of TARGETS holds a blank")
    print("targets=" + " ".join(targets))
    return 0


def baseline(argv):
    limit, targets = int(argv[0]), argv[1:]
    if not targets:
        sys.exit("mutate_ci: no target")
    t0 = time.time()
    rc, log, _ = run_targets(targets, limit)
    write("baseline", {"name": "baseline", "exit": rc, "seconds": round(time.time() - t0)}, log)
    print("baseline exit", rc)
    return 0 if rc == 0 else 1


def one(argv):
    path, name, limit, targets = argv[0], argv[1], int(argv[2]), argv[3:]
    (m,) = load(path, [name])
    targets = m.get("targets") or targets
    if not targets:
        sys.exit("mutate_ci: no target")
    with open(m["file"]) as f:
        src = f.read()
    record = {"name": name, "id": m["id"], "equivalent": m.get("equivalent", "")}
    if src.count(m["old"]) != 1:
        record.update(verdict="BADMATCH", seconds=0,
                      note="`old` occurs %d times in %s" % (src.count(m["old"]), m["file"]))
        write(name, record, "")
        print(name, "BADMATCH")
        return 0
    with open(m["file"], "w") as f:
        f.write(src.replace(m["old"], m["new"]))
    t0 = time.time()
    rc, log, why = run_targets(targets, limit)
    declared = bool(m.get("equivalent"))
    if rc == "noload":
        verdict = "NO VERDICT (does not load)"
    elif rc == "notest":
        verdict = "NO VERDICT (no failing test)"
    elif rc == 1:
        verdict = "EQUIVALENT REFUTED" if declared else "caught"
    elif rc == "hang":
        verdict = "caught (hang)" if m.get("expect") == "hang" else "TIMEOUT"
    elif rc == 0:
        verdict = "EQUIVALENT (declared)" if declared else "SURVIVED"
    else:
        verdict = "INVALID"
    why = "; ".join(x for x in (why, noload_hint(m, verdict)) if x)
    record.update(verdict=verdict, exit=rc, seconds=round(time.time() - t0), first_failure=why)
    write(name, record, log)
    print(name, verdict, "—", why or "-")
    return 0                                            # the verdict is data: `collect` judges


def collect(argv):
    path, count, only = argv[0], int(argv[1]), argv[2:]
    mutants = load(path, only)
    if len(mutants) != count:
        sys.exit("mutate_ci: the plan had %d mutants, the list now gives %d" % (count, len(mutants)))
    rows, blocked = [], []

    def read(name):
        p = os.path.join(OUT, name + ".json")
        if not os.path.isfile(p):
            return None
        with open(p) as f:
            return json.load(f)

    base = read("baseline")
    base_ok = base is not None and base.get("exit") == 0
    for m in mutants:
        name = m["id"].split()[0]
        r = read(name) or {"verdict": "NO VERDICT", "seconds": 0}
        v = r["verdict"]
        if v.startswith(BLOCKING) or not base_ok:
            blocked.append(name)
        what = m["id"][len(name):].strip()
        if m.get("equivalent"):
            what += " — declared equivalent, pending audit: " + m["equivalent"]
        rows.append("| %s | %s | %s s | %s | %s |" % (name, v, r.get("seconds", 0), what.replace("|", "\\|"),
                                                   (r.get("first_failure") or "").replace("|", "\\|")))
    lines = ["## Mutation battery — %s" % path, "",
             "Baseline (unmutated targets): **%s**%s" % (
                 "green" if base_ok else "NOT GREEN — no verdict below counts",
                 "" if base is None else ", %s s" % base.get("seconds", 0)), "",
             "| mutant | verdict | time | what it breaks | first failing test line |",
             "|---|---|---|---|---|"] + rows + [""]
    n = len(mutants)
    lines.append("**%d of %d decided; blocking: %s**" % (
        n - len(blocked), n, ", ".join(blocked) if blocked else "none"))
    text = "\n".join(lines) + "\n"
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "verdicts.md"), "w") as f:
        f.write(text)
    sys.stdout.write(text)
    return 1 if blocked or not base_ok else 0


ANNOTATIONS_MAX, ANNOTATION_CHARS = 10, 4000          # GitHub: 10 notices per step; a short message


def annotate(argv):
    """verdicts.md as `::notice` workflow commands, the rows packed in order into at most
    ANNOTATIONS_MAX messages of at most ANNOTATION_CHARS characters each, numbered "verdicts i/n";
    a row that does not fit is cut, and every annotation is printed — none dropped."""
    with open(os.path.join(OUT, "verdicts.md")) as f:
        rows = [ln[:ANNOTATION_CHARS] for ln in f.read().splitlines() if ln.strip()]
    parts, cur = [], ""
    for ln in rows:
        if cur and len(cur) + 1 + len(ln) > ANNOTATION_CHARS:
            parts.append(cur)
            cur = ""
        cur = ln if not cur else cur + "\n" + ln
    parts.append(cur)
    if len(parts) > ANNOTATIONS_MAX:
        print("mutate_ci: annotate: %d parts, GitHub shows %d" % (len(parts), ANNOTATIONS_MAX), file=sys.stderr)
    esc = lambda t: t.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    for i, part in enumerate(parts, 1):
        print("::notice title=verdicts %d/%d::%s" % (i, len(parts), esc(part)))
    return 0 if len(parts) <= ANNOTATIONS_MAX else 1


if __name__ == "__main__":
    commands = {"plan": plan, "baseline": baseline, "one": one, "collect": collect, "annotate": annotate}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit("usage: mutate_ci.py plan|baseline|one|collect|annotate … (see the header)")
    sys.exit(commands[sys.argv[1]](sys.argv[2:]))
