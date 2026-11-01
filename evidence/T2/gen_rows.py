# T2 rows: the programs of test/core_lang/test_string_swipl.jl, written as the test writes them, then run through the test file's own
# driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/T2, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_lang/test_string_swipl.jl          # writes t2_rows.pl, t2_rows2.pl, t2_driver.pl, t2_driver2.pl
#   swipl -q t2_driver.pl  < /dev/null > t2_rows.out  2>/dev/null          # twice (t2_rows_b.out): the two runs must be byte-identical
#   swipl -q t2_driver2.pl < /dev/null > t2_rows2.out 2>/dev/null
#   python3 gen_rows.py ../../test/core_lang/test_string_swipl.jl --fill   # puts the .out files into _ST_PINNED and _ST_PINNED2
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
drv = re.search(r'const _ST_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
progs = [("t2_rows", "_ST_PROGRAM", "_ST_PINNED", "t2_driver"),
         ("t2_rows2", "_ST_PROGRAM2", "_ST_PINNED2", "t2_driver2")]
for base, pname, pinname, dname in progs:
    prog = re.search(r'const %s = raw"""\n(.*?)"""' % pname, src, re.S).group(1)
    names = re.findall(r"^((?:st|su)\d+)\(R\) :-", prog, re.M)
    if "--fill" in sys.argv:
        lines = [l for l in pathlib.Path(base + ".out").read_text().split("\n") if l]
        assert len(lines) == len(names) + 1, (base, len(lines), len(names))
        block = "const %s = [\n" % pinname + ",\n".join('    "%s"' % l.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$") for l in lines) + "\n]\n"
        src, n = re.subn(r"const %s = \[\n(?:    \".*\n)*\]\n" % pinname, lambda m: block, src, count=1)
        assert n == 1
        print("filled", pinname, len(lines), "lines")
        continue
    pathlib.Path(base + ".pl").write_text(prog)
    here = pathlib.Path(base + ".pl").resolve()
    pathlib.Path(dname + ".pl").write_text(drv + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (here, ",".join(names)))
    print(base, len(names), "rows")
if "--fill" in sys.argv:
    tf.write_text(src)
