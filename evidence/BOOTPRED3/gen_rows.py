# BOOTPRED3 rows: the program + cases of test/core_lang/test_bootpred3_swipl.jl, written as _b3_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/BOOTPRED3, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_lang/test_bootpred3_swipl.jl          # writes bp3_rows.pl, bp3_driver.pl
#   swipl -q bp3_driver.pl < /dev/null > bp3_rows.out              # run twice, the two outputs must be byte-identical
#   python3 gen_rows.py ../../test/core_lang/test_bootpred3_swipl.jl --fill   # puts bp3_rows.out into _B3_PINNED
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _B3_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'\(\s*"(bp3[a-z]\d{2})",\s*raw"(.*?)"\s*\)', src, re.S)
drv = re.search(r'const _B3_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
if "--fill" in sys.argv:
    lines = pathlib.Path("bp3_rows.out").read_text().split("\n")
    lines = [l for l in lines if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _B3_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _B3_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
text = prog + "".join(f"t_{i}(R) :- catch(({g}), error(SsuE, _), R = raised(SsuE)).\n" for i, g in cases)
pathlib.Path("bp3_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("bp3_rows.pl").resolve()
pathlib.Path("bp3_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
print(len(cases), "cases")
