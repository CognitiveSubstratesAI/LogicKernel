#!/usr/bin/env python3
# tools/mutate_drive.py — the mutation driver, the same for every chunk (Tooling 1, 2026-10-11).
# Started by tools/mutate.sh, never by hand; a chunk keeps only its mutant list.
#
#   mutate_drive.py TREE MUTANTS.py TARGET… [-- ID…]    run the mutants (under `tools/warm.sh locked`)
#   mutate_drive.py --sync ROOT WORKTREE                copy ROOT's uncommitted work over WORKTREE
#
# THE RUN. TREE is where mutants are applied and judged: the mutant worktree (tools/mutate.sh run)
# or the main tree (run-in-tree). MUTANTS.py defines MUTANTS, a list of dicts:
#     id      "A3 what it breaks" — the first word is the name used on the command line and in logs
#     file    the file to mutate, relative to the tree
#     old     the text to replace — it must occur EXACTLY once, or the mutant is BADMATCH
#     new     the replacement
#     expect  optional, "hang": a mutant that must time out (it is then "caught (hang)")
#     equivalent  optional, the REASON (file:line) a mutant cannot be told apart from the original —
#             recorded in the chunk's mutation memo first; such a mutant must SURVIVE ("EQUIVALENT
#             (declared)"); if a target catches it, the claim was wrong and that blocks
#     targets optional: this mutant's own targets, in place of the command line's
# Each TARGET is a test file, run whole in the tree's warm daemon (`tools/warm.sh file`, on the term
# implementation MUTATE_IMPL, default `reference`) — or `sh:<command>`, a shell command run in the
# tree and judged by its exit code alike (the warm lane's own tests, `sh:tools/test_warm.sh rss`,
# which no test file can run). The targets must pass on the unmutated tree
# first (the baseline) and again after the last mutant (the closing baseline: a daemon that
# degraded mid-run would turn every later mutant red for a reason of its own).
# THE VERDICT, from the exit code first: a target exits 1 = caught; every target exits 0 = SURVIVED;
# a target that runs past the limit = TIMEOUT (its own outcome, never caught — user, 2026-10-12; the
# daemon is restarted after one), unless the mutant expects a hang; anything else = INVALID. AN EXIT 1
# IS CAUGHT ONLY WHEN A TEST FAILED (D-0050, 2026-10-20; `judge`): the code did not parse or load
# (NOT_LOADED: ParseError, REVISE FAILED, a LoadError other than "Some tests did not pass") = NO
# VERDICT (does not load); a test file that exits 1 with no failing test line = NO VERDICT (no
# failing test). MEASURED 2026-10-19 (A-0035): a mutant that broke parsing was booked killed.
# SURVIVED, TIMEOUT, INVALID and NO VERDICT BLOCK a commit until the mutant is rerun to a verdict:
# killed by a test, or declared `equivalent` with its reason. The driver exits 0 only when both
# baselines are green AND no mutant blocks; 1 when a mutant blocks; 2 when the final baseline is not
# green. Every non-caught mutant is listed, and its output kept beside the mutant list (MUTATE_OUT
# overrides the directory); every verdict, with a caught one's first failing test line, goes to
# verdicts.tsv there.
# WHILE A MUTANT IS APPLIED, .warm/MUTATION_IN_PROGRESS in the tree names it and
# .warm/MUTATION_ORIGINAL holds the file as it was (`tools/mutate.sh recover`); SIGTERM restores
# the file first. MUTATE_LIMIT_S (240) is the limit per target.
import hashlib
import os
import re
import re
import runpy
import shutil
import signal
import subprocess
import sys
import tempfile

# The does-not-load signature: "Some tests did not pass" is the one LoadError a failed test raises;
# the warm daemon's refusal (tools/warm_session.jl) exits 1 as a failed test does.
NOT_LOADED = re.compile(r"ParseError|REVISE FAILED|LoadError: (?!Some tests did not pass)")
FAILED_TEST = re.compile(r"(?:Test Failed|Error During Test) at \S+")


def judge(target, rc, out, root):
    """One target's result: 1 (a test failed), "noload", "notest", or `rc` unchanged — and the
    line that shows it (a caught one's first failing test line, `root` made relative)."""
    if rc != 1:
        return rc, ""
    lines = out.splitlines()

    def shown(pat):
        hit = next((ln for ln in lines if pat.search(ln)), None)
        return hit and hit.replace(root.rstrip("/") + "/", "").strip()[:200]

    why = shown(NOT_LOADED)
    if why:
        return "noload", why
    why = shown(FAILED_TEST)
    if why:
        return 1, why
    if target.startswith("sh:"):                       # a shell target: its exit code is the verdict
        return 1, next((ln.strip()[:200] for ln in reversed(lines) if ln.strip()), "(exit 1, no output)")
    return "notest", ""


def sync(root, wt):
    """Copy ROOT's uncommitted work over WT: what differs from HEAD, what is untracked, and the two
    ignored files that decide what loads. A file gone from ROOT is removed from WT. Prints the count."""
    root, wt = os.path.realpath(root), os.path.realpath(wt)
    if not os.path.isdir(os.path.join(wt, ".warm")) or root == wt or wt == "/":
        sys.exit("mutate: sync: %s is not a prepared worktree" % wt)

    def names(*cmd):
        out = subprocess.run(cmd, cwd=root, capture_output=True, check=True).stdout
        return [n.decode() for n in out.split(b"\0") if n]

    changed = names("git", "diff", "--name-only", "-z", "HEAD")
    changed += names("git", "ls-files", "-z", "-o", "--exclude-standard")
    n = 0
    for rel in sorted(set(changed)) + ["Manifest.toml", "LocalPreferences.toml"]:
        src, dst = os.path.join(root, rel), os.path.realpath(os.path.join(wt, rel))
        if os.path.commonpath([wt, dst]) != wt:
            sys.exit("mutate: sync: %s leaves the worktree" % rel)
        if os.path.isfile(src):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
        elif os.path.isfile(dst):
            os.remove(dst)
        n += rel in changed
    print(n)


def main(argv):
    tree, mutants_path = os.path.realpath(argv[1]), os.path.realpath(argv[2])
    rest = argv[3:]
    only = set()
    if "--" in rest:
        k = rest.index("--")
        rest, only = rest[:k], set(rest[k + 1:])
    targets = rest
    if not targets:
        sys.exit("mutate_drive: no target")
    mutants = runpy.run_path(mutants_path)["MUTANTS"]
    out_dir = os.environ.get("MUTATE_OUT") or os.path.dirname(mutants_path)
    limit = int(os.environ.get("MUTATE_LIMIT_S", "240"))
    impl = os.environ.get("MUTATE_IMPL", "reference")
    sentinel = os.path.join(tree, ".warm", "MUTATION_IN_PROGRESS")
    saved = os.path.join(tree, ".warm", "MUTATION_ORIGINAL")

    def run1(target):
        env = dict(os.environ, WARM_TIMEOUT_S=str(limit))
        cmd = ["tools/warm.sh", "file", target, impl]
        if target.startswith("sh:"):
            cmd = ["bash", "-c", target[3:]]
        try:
            r = subprocess.run(cmd, cwd=tree,
                               capture_output=True, text=True, timeout=limit + 120, env=env)
            rc, out = r.returncode, r.stdout + r.stderr
        except subprocess.TimeoutExpired:
            rc, out = -9, ""
        if rc == -9 or (rc == 2 and cmd[0] != "bash"):  # timed out: the daemon is still busy
            subprocess.run(["tools/warm.sh", "restart"], cwd=tree, capture_output=True)
            return "hang", out
        return judge(target, rc, out, tree)[0], out

    def run(tgts):
        """Every target (`run_targets`), each one in the tree's warm daemon."""
        return run_targets(tgts, run1, tree)

    def keep(name, out):
        with open(os.path.join(out_dir, name), "w") as f:
            f.write(out)

    rc, out, _ = run(targets)
    print("baseline exit", rc, flush=True)
    if rc != 0:
        keep("baseline.log", out)
        print("BASELINE NOT GREEN")
        return 2

    results = []
    shard = parse_shard(os.environ.get("MUTATE_SHARD", ""))
    nsel = 0
    for m in mutants:
        name = m["id"].split()[0]
        if only and name not in only:
            continue
        nsel += 1
        if not in_shard(nsel, shard):
            continue
        p = os.path.join(tree, m["file"])
        with open(p) as f:
            s = f.read()
        n = s.count(m["old"])
        if n != 1:
            results.append((m["id"], "BADMATCH(%d)" % n))
            print(m["id"], "BADMATCH", n, flush=True)
            continue

        def restore(*_):
            with open(p, "w") as f:
                f.write(s)
            for x in (sentinel, saved):
                if os.path.exists(x):
                    os.remove(x)
            sys.exit(3)

        signal.signal(signal.SIGTERM, restore)
        with open(saved, "w") as f:                     # first the copy, then the sentinel naming it
            f.write(s)
        with open(sentinel, "w") as f:
            f.write("file=%s\nsha256=%s\nmutant=%s\n" %
                    (m["file"], hashlib.sha256(s.encode()).hexdigest(), m["id"]))
        with open(p, "w") as f:
            f.write(s.replace(m["old"], m["new"]))
        try:
            rc, out, why = run(m.get("targets", targets))
        finally:
            with open(p, "w") as f:
                f.write(s)
            os.remove(sentinel)                         # first the sentinel, then the copy
            os.remove(saved)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        v = verdict(rc, m)
        if v != "caught":
            keep("mutant_%s.log" % name, out)
        results.append((m["id"], v, why))
        print(m["id"], v, "—", why or "-", flush=True)

    keep("verdicts.tsv", "".join("%s\t%s\t%s\n" % (mid.split()[0], v, why) for mid, v, why in results))
    rc, out, _ = run(targets)
    print("final baseline exit", rc, flush=True)
    if rc != 0:
        keep("final_baseline.log", out)
        print("FINAL BASELINE NOT GREEN — the verdicts above prove nothing")
        return 2
    print("SUMMARY", sum(1 for _, v, _ in results if v.startswith("caught")), "of", len(results), "caught;",
          sum(1 for _, v, _ in results if blocks(v)), "blocking")
    for mid, v, _ in results:
        if not v.startswith("caught"):
            print("  ", mid, v)
    return 1 if any(blocks(v) for _, v, _ in results) else 0


def parse_shard(text):
    """`k/n` from MUTATE_SHARD (PARALLEL RUNS, D-0077 item 6): this worker takes every n-th selected mutant,
    from the k-th. Empty is the whole list, (1, 1); anything else malformed is an error."""
    if not text:
        return (1, 1)
    m = re.fullmatch(r"([1-9][0-9]*)/([1-9][0-9]*)", text)
    if not m or int(m.group(1)) > int(m.group(2)):
        sys.exit("mutate_drive: MUTATE_SHARD=%r: expected k/n with 1 <= k <= n" % text)
    return (int(m.group(1)), int(m.group(2)))


def in_shard(i, shard):
    """Whether the i-th (1-based) selected mutant belongs to shard (k, n)."""
    return (i - 1) % shard[1] == shard[0] - 1


def merge(mutants_path, out_dir, worker_dirs):
    """The verdicts of the workers' shards, in the mutant list's order, into OUT_DIR/verdicts.tsv; prints the
    summary the serial driver prints. Exit code: 1 if any verdict blocks, 2 if a worker wrote no verdicts (it
    did not finish) or two workers decided one mutant, else 0. Run it on the shards of ONE parallel run."""
    names = [m["id"].split()[0] for m in runpy.run_path(mutants_path)["MUTANTS"]]
    seen, rows = {}, []
    for d in worker_dirs:
        path = os.path.join(d, "verdicts.tsv")
        if not os.path.isfile(path):
            print("merge: no verdicts.tsv in %s — that worker did not finish" % d)
            return 2
        for line in open(path):
            f = line.rstrip("\n").split("\t")
            if f[0] in seen:
                print("merge: mutant %s decided by two workers" % f[0])
                return 2
            seen[f[0]] = f
    rows = [seen[n] for n in names if n in seen]
    with open(os.path.join(out_dir, "verdicts.tsv"), "w") as io:
        io.write("".join("\t".join(r) + "\n" for r in rows))
    print("SUMMARY (merged from %d workers)" % len(worker_dirs), sum(1 for r in rows if r[1].startswith("caught")),
          "of", len(rows), "caught;", sum(1 for r in rows if blocks(r[1])), "blocking")
    for r in rows:
        if not r[1].startswith("caught"):
            print("  ", r[0], r[1])
    return 1 if any(blocks(r[1]) for r in rows) else 0


def run_targets(targets, run1, root):
    """Every target through `run1` (target → (judged result, output)), stopping at the first that
    decides: (1 if a test failed, "noload", "notest", "hang", another code, else 0; the log; the
    deciding line). mutate_ci.py runs its fresh processes through this, too."""
    rcs, outs, why = [], [], ""
    for t in targets:
        rc, out = run1(t)
        rcs.append(rc)
        outs.append("=== %s: exit %s\n%s" % (t, rc, out))
        if rc in (1, "noload", "notest"):
            why = judge(t, 1, out, root)[1]
            break                                       # decided: the other targets add nothing
    log = "\n".join(outs)
    for decided in (1, "noload", "notest", "hang"):
        if decided in rcs:
            return decided, log, why
    bad = [r for r in rcs if r != 0]
    return (bad[0] if bad else 0), log, why


def verdict(rc, m):
    """A mutant's outcome from its targets' result (`run`: 1, 0, "hang" or another exit code)."""
    if rc == "hang":
        return "caught (hang)" if m.get("expect") == "hang" else "TIMEOUT"
    if rc == "noload":
        return "NO VERDICT (does not load)"
    if rc == "notest":
        return "NO VERDICT (no failing test)"
    if rc == 1:
        return "CAUGHT BUT DECLARED EQUIVALENT" if m.get("equivalent") else "caught"
    if rc == 0:
        return "EQUIVALENT (declared)" if m.get("equivalent") else "SURVIVED"
    return "INVALID(%s)" % rc


def blocks(v):
    """Whether outcome `v` blocks a commit: everything but caught and a declared equivalent."""
    return not (v.startswith("caught") or v == "EQUIVALENT (declared)")


def selftest():
    """The verdict table, each row the decision it encodes, and `judge` on REAL output both ways: a
    file that does not parse or load is no kill, a failed test is (run: mutate_drive.py --selftest;
    JULIA overrides the julia on PATH)."""
    plain, hang, eq = {}, {"expect": "hang"}, {"equivalent": "x.jl:1 — never read"}
    table = [((1, plain), "caught", False), ((0, plain), "SURVIVED", True),
             (("hang", plain), "TIMEOUT", True), (("hang", hang), "caught (hang)", False),
             ((5, plain), "INVALID(5)", True), ((0, eq), "EQUIVALENT (declared)", False),
             ((1, eq), "CAUGHT BUT DECLARED EQUIVALENT", True),
             (("noload", plain), "NO VERDICT (does not load)", True),
             (("noload", eq), "NO VERDICT (does not load)", True),
             (("noload", hang), "NO VERDICT (does not load)", True),
             (("notest", plain), "NO VERDICT (no failing test)", True)]
    for (rc, m), want, blocking in table:
        got = verdict(rc, m)
        assert got == want, (rc, m, got, want)
        assert blocks(got) == blocking, (got, blocks(got), blocking)
    # the warm daemon's refusal: the signature must name what tools/warm_session.jl prints
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "warm_session.jl")) as f:
        assert '"REVISE FAILED' in f.read(), "warm_session.jl no longer prints REVISE FAILED"
    assert judge("t.jl", 1, "x\nREVISE FAILED — refusing to run this snippet:\n", "/r")[0] == "noload"
    assert judge("t.jl", 0, "LoadError: ParseError", "/r") == (0, "")       # exit 0: nothing to judge
    assert judge("sh:false", 1, "", "/r") == (1, "(exit 1, no output)")
    # real julia: each file's judged result, and the line kept (a caught one's names the test)
    test = "using Test\n@testset \"t\" begin\n    @test %s\nend\n"
    files = {"parse": (test % "1 == (1", "noload", "ParseError"),
             "load": ("using Test\nnot_defined_anywhere()\n" + test % "true", "noload", "UndefVarError"),
             "fail": (test % "1 == 2", 1, "Test Failed at fail.jl:3"),
             "throws": (test % "not_defined_anywhere() == 1", 1, "Error During Test at throws.jl:3"),
             "exit": ("exit(1)\n", "notest", ""),
             "pass": (test % "1 == 1", 0, "")}
    julia = os.environ.get("JULIA") or shutil.which("julia")
    assert julia, "selftest: no julia (set JULIA)"
    with tempfile.TemporaryDirectory() as d:
        for name, (code, want, line) in files.items():
            with open(os.path.join(d, name + ".jl"), "w") as f:
                f.write(code)
            r = subprocess.run([julia, "--startup-file=no", name + ".jl"], cwd=d,
                               capture_output=True, text=True, timeout=300)
            got, why = judge(name + ".jl", r.returncode, r.stdout + r.stderr, d)
            assert got == want and line in why, (name, r.returncode, got, why, r.stdout + r.stderr)
    print("mutate_drive selftest: %d verdict rows, %d live files ok" % (len(table), len(files)))
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    elif len(sys.argv) == 4 and sys.argv[1] == "--sync":
        sync(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 5 and sys.argv[1] == "--merge":
        sys.exit(merge(sys.argv[2], sys.argv[3], sys.argv[4:]))
    elif len(sys.argv) >= 4:
        sys.exit(main(sys.argv))
    else:
        sys.exit("usage: mutate_drive.py TREE MUTANTS.py TARGET… [-- ID…]  |  --sync ROOT WORKTREE  |  --merge MUTANTS.py OUTDIR WORKERDIR…")
