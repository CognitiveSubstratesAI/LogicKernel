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
#     targets optional: this mutant's own targets, in place of the command line's
# Each TARGET is a test file, run whole in the tree's warm daemon (`tools/warm.sh file`, on the term
# implementation MUTATE_IMPL, default `reference`) — or `sh:<command>`, a shell command run in the
# tree and judged by its exit code alike (the warm lane's own tests, `sh:tools/test_warm.sh rss`,
# which no test file can run). The targets must pass on the unmutated tree
# first (the baseline) and again after the last mutant (the closing baseline: a daemon that
# degraded mid-run would turn every later mutant red for a reason of its own).
# THE VERDICT, at the level of the exit code, never of a message: a target exits 1 = caught; every
# target exits 0 = SURVIVED; anything else = INVALID (a timeout is INVALID unless expected: the
# daemon is restarted after one). The driver exits 0 only when both baselines are green — whatever
# the mutants did — and prints the summary; a survivor or an invalid mutant is listed, and its
# output kept beside the mutant list (MUTATE_OUT overrides the directory).
# WHILE A MUTANT IS APPLIED, .warm/MUTATION_IN_PROGRESS in the tree names it and
# .warm/MUTATION_ORIGINAL holds the file as it was (`tools/mutate.sh recover`); SIGTERM restores
# the file first. MUTATE_LIMIT_S (240) is the limit per target.
import hashlib
import os
import runpy
import shutil
import signal
import subprocess
import sys


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
        return rc, out

    def run(tgts):
        """Every target: 1 if one is red (caught), "hang", another code (invalid), else 0."""
        rcs, outs = [], []
        for t in tgts:
            rc, out = run1(t)
            rcs.append(rc)
            outs.append("=== %s: exit %s\n%s" % (t, rc, out))
            if rc == 1:
                break                                   # caught: the other targets add nothing
        out = "\n".join(outs)
        if 1 in rcs:
            return 1, out
        if "hang" in rcs:
            return "hang", out
        bad = [r for r in rcs if r != 0]
        return (bad[0] if bad else 0), out

    def keep(name, out):
        with open(os.path.join(out_dir, name), "w") as f:
            f.write(out)

    rc, out = run(targets)
    print("baseline exit", rc, flush=True)
    if rc != 0:
        keep("baseline.log", out)
        print("BASELINE NOT GREEN")
        return 2

    results = []
    for m in mutants:
        name = m["id"].split()[0]
        if only and name not in only:
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
            rc, out = run(m.get("targets", targets))
        finally:
            with open(p, "w") as f:
                f.write(s)
            os.remove(sentinel)                         # first the sentinel, then the copy
            os.remove(saved)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        if rc == "hang":
            v = "caught (hang)" if m.get("expect") == "hang" else "INVALID(timeout)"
        else:
            v = "caught" if rc == 1 else ("SURVIVED" if rc == 0 else "INVALID(%s)" % rc)
        if v != "caught":
            keep("mutant_%s.log" % name, out)
        results.append((m["id"], v))
        print(m["id"], v, flush=True)

    rc, out = run(targets)
    print("final baseline exit", rc, flush=True)
    if rc != 0:
        keep("final_baseline.log", out)
        print("FINAL BASELINE NOT GREEN — the verdicts above prove nothing")
        return 2
    print("SUMMARY", sum(1 for _, v in results if v.startswith("caught")), "of", len(results), "caught")
    for mid, v in results:
        if not v.startswith("caught"):
            print("  ", mid, v)
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--sync":
        sync(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 4:
        sys.exit(main(sys.argv))
    else:
        sys.exit("usage: mutate_drive.py TREE MUTANTS.py TARGET… [-- ID…]  |  --sync ROOT WORKTREE")
