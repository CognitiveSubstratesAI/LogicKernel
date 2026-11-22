#!/usr/bin/env python3
"""B1 row generator: runs test/core_lang/test_b1_preds_swipl.jl's cases against swipl twice, checks the two runs are
byte-identical, and with --fill rewrites the file's `_B1_PINNED` block with swipl's lines.
The swipl is the EXPLICIT pin binary ~/.local/swipl-pin1-18168e62/bin/swipl (version 10.1.20), run in a capped systemd scope.
Usage: python3 -I evidence/B1/gen_rows.py [--fill]   (from the repository root)"""
import os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEST = os.path.join(ROOT, "test/core_lang/test_b1_preds_swipl.jl")
SWIPL = os.path.expanduser("~/.local/swipl-pin1-18168e62/bin/swipl")
src = open(TEST).read()

driver = re.search(r'const _B1_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
# a case is `("mNN", raw"...")`, on one line or (as the formatter lays it out) on four
block = re.search(r'const _B1_CASES = \[\n(.*?)\n\]\n', src, re.S).group(1)
cases = re.findall(r'\(\s*"([a-z]+\d+)",\s*raw"(.*?)"\s*\)(?=,\s*\n|\s*$)', block + "\n", re.S)
cases = [(i, g.replace('\\"', '"')) for i, g in cases]       # raw"..." keeps `\"` as the quote
assert len(cases) > 30, len(cases)
ids = [i for i, _ in cases]
assert len(set(ids)) == len(ids)

text = "".join(
    "t_%s(R) :- catch((%s), error(SsuE, _), R = raised(SsuE)).\n" % (i, g) for i, g in cases)
names = ["t_" + i for i in ids]

def run_once() -> str:
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "b1_preds.pl")
        open(f, "w").write(text)
        drv = os.path.join(d, "drv.pl")
        open(drv, "w").write(driver + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (f, ",".join(names)))
        cmd = ["systemd-run", "--user", "--scope", "-q", "-p", "MemoryMax=2G", "-p", "MemorySwapMax=0",
               "-p", "TasksMax=64", SWIPL, "-q", drv]
        r = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, check=True)
        return r.stdout.decode()

ver = subprocess.run([SWIPL, "--version"], stdout=subprocess.PIPE, check=True).stdout.decode().strip()
assert "10.1.20" in ver, ver
a, b = run_once(), run_once()
assert a == b, "the two swipl runs differ"
lines = [l for l in a.split("\n") if l]
assert len(lines) == len(cases) + 1, (len(lines), len(cases))
assert lines[0] == "ok"
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "b1_preds_rows.out"), "w").write(a)
if "--fill" in sys.argv:
    block = "const _B1_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]"
    new, n = re.subn(r'const _B1_PINNED = \[\n(?:    ".*",?\n)*\]', lambda m: block, src, count=1)
    assert n == 1
    open(TEST, "w").write(new)
print("ok: %d lines, two runs identical (%s)" % (len(lines), ver))
