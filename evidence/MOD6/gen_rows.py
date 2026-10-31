# MOD6 rows: the program + cases of test/core_lang/test_module_enum_swipl.jl, written as _mm_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/MOD6, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_lang/test_module_enum_swipl.jl          # writes mm_rows.pl, mm_driver.pl
#   swipl -q mm_driver.pl < /dev/null > mm_rows.out 2> mm_rows.err
#   python3 gen_rows.py ../../test/core_lang/test_module_enum_swipl.jl --fill   # puts the .out lines into _MM_PINNED
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _MM_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'\(\s*"([a-z]\d\d)",\s*raw"(.*?)"\s*\)', src, re.S)
drv = re.search(r'const _MM_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
if "--fill" in sys.argv:
    lines = [l for l in pathlib.Path("mm_rows.out").read_text().split("\n") if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _MM_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _MM_PINNED = \[\n(?:    [^\n]*\n)*\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
text = prog + "".join(f"t_{i}(R) :- catch(({g}), error(F, _), R = raised(F)), mme_done.\n" for i, g in cases)
pathlib.Path("mm_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("mm_rows.pl").resolve()
pathlib.Path("mm_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
print(len(cases), "cases")
