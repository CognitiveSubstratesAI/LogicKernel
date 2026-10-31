# D2 rows: the program + cases of test/db/test_record_swipl.jl, written as _rc_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/D2, repo = the worktree root):
#   python3 gen_rows.py ../../test/db/test_record_swipl.jl          # writes d2_rows.pl, d2_driver.pl
#   swipl -q d2_driver.pl < /dev/null > d2_rows.out                 # twice: the two outputs must be byte-identical
#   python3 gen_rows.py ../../test/db/test_record_swipl.jl --fill   # puts d2_rows.out into _RC_PINNED
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _RC_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'\(\s*"(r\d\d)",\s*raw"(.*?)"\s*\)', src, re.S)
drv = re.search(r'const _RC_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
if "--fill" in sys.argv:
    lines = pathlib.Path("d2_rows.out").read_text().split("\n")
    lines = [l for l in lines if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _RC_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _RC_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
text = prog + "".join(f"t_{i}(R) :- rset, catch(({g}), error(RcE, _), R = raised(RcE)).\n" for i, g in cases)
pathlib.Path("d2_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("d2_rows.pl").resolve()
pathlib.Path("d2_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
print(len(cases), "cases")
