# P1 rows: the program + cases of test/core_lang/test_p1_swipl.jl, written as _p1_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/P1, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_lang/test_p1_swipl.jl          # writes p1_rows.pl, p1_driver.pl
#   swipl -q p1_driver.pl < /dev/null > p1_rows.out              # run twice, the two outputs must be byte-identical
#   python3 gen_rows.py ../../test/core_lang/test_p1_swipl.jl --fill   # puts p1_rows.out into _P1_PINNED
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _P1_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
body = re.search(r'const _P1_CASES = \[\n(.*?)\n\]\n', src, re.S).group(1)
cases = re.findall(r'\(\s*"(p\d{3})",\s*raw"""(.*?)"""\s*\)', body, re.S)
drv = re.search(r'const _P1_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
if "--fill" in sys.argv:
    lines = pathlib.Path("p1_rows.out").read_text().split("\n")
    lines = [l for l in lines if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _P1_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _P1_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
ids = [i for i, _ in cases]
assert len(set(ids)) == len(ids) and ids == ["p%03d" % k for k in range(1, len(ids) + 1)], "ids must run p001.. in order"
text = prog + "".join(f"t_{i}(R) :- catch(({g}), error(SsuE, _), R = raised(SsuE)).\n" for i, g in cases)
pathlib.Path("p1_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("p1_rows.pl").resolve()
pathlib.Path("p1_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
print(len(cases), "cases")
