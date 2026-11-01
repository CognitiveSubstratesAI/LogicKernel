#!/usr/bin/env python3
"""P2 row generator: runs test/core_lang/test_p2_swipl.jl's cases against swipl twice, checks the two runs are
byte-identical, and with --fill rewrites the file's `_P2_PINNED` block with swipl's lines.
Usage: python3 -I evidence/P2/gen_rows.py [--fill]   (from the repository root; swipl 10.1.19 on PATH)"""
import os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEST = os.path.join(ROOT, "test/core_lang/test_p2_swipl.jl")
src = open(TEST).read()

driver = re.search(r'const _P2_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
program = re.search(r'const _P2_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'^\s*\("(p\d+)", raw"(.*)"\),\s*$', src, re.M)
assert len(cases) > 60, len(cases)
ids = [i for i, _ in cases]
assert len(set(ids)) == len(ids)

text = program + "".join(
    "t_%s(R) :- catch((%s), error(SsuE, _), R = raised(SsuE)).\n" % (i, g) for i, g in cases)
names = ["t_" + i for i in ids]

def run_once() -> str:
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "p2_text.pl")
        open(f, "w").write(text)
        drv = os.path.join(d, "drv.pl")
        open(drv, "w").write(driver + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (f, ",".join(names)))
        r = subprocess.run(["swipl", "-q", drv], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, check=True)
        return r.stdout.decode()

a, b = run_once(), run_once()
assert a == b, "the two swipl runs differ"
lines = [l for l in a.split("\n") if l]
assert len(lines) == len(cases) + 1, (len(lines), len(cases))
assert lines[0] == "ok"
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "p2_rows.out"), "w").write(a)
if "--fill" in sys.argv:
    block = "const _P2_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]"
    new, n = re.subn(r'const _P2_PINNED = \[\n(?:    ".*",?\n)*\]', lambda m: block, src, count=1)
    assert n == 1
    open(TEST, "w").write(new)
print("ok: %d lines, two runs identical" % len(lines))
