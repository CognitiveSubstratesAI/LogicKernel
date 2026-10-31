# MOD3b rows: the program + cases of test/core_lang/test_at_body_swipl.jl, written as _ab_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/MOD3b, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_lang/test_at_body_swipl.jl          # writes mod3b_rows.pl, mod3b_driver.pl
#   swipl -q mod3b_driver.pl < /dev/null > mod3b_rows.out
#   python3 gen_rows.py ../../test/core_lang/test_at_body_swipl.jl --fill   # puts mod3b_rows.out into _AB_PINNED
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _AB_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'\("(a\d\d)",\s*raw"(.*?)"\)', src, re.S)
drv = re.search(r'const _AB_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
if "--fill" in sys.argv:
    lines = pathlib.Path("mod3b_rows.out").read_text().split("\n")
    lines = [l for l in lines if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _AB_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _AB_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
text = prog + "".join(f"t_{i}(R) :- catch(({g}), error(SsuE, _), R = raised(SsuE)).\n" for i, g in cases)
pathlib.Path("mod3b_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("mod3b_rows.pl").resolve()
pathlib.Path("mod3b_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
print(len(cases), "cases")
