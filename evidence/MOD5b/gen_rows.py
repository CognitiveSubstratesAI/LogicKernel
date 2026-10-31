# MOD5b rows: the program + cases of test/core_lang/test_declare_destroy_swipl.jl, written as _mb_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/MOD5b, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_lang/test_declare_destroy_swipl.jl          # writes mb_rows.pl, mb_driver.pl, mb_q7_rows.pl, mb_q7_driver.pl
#   swipl -q mb_driver.pl < /dev/null > mb_rows.out 2> mb_rows.err ; swipl -q mb_q7_driver.pl < /dev/null > mb_q7.out 2> mb_q7.err
#   python3 gen_rows.py ../../test/core_lang/test_declare_destroy_swipl.jl --fill   # puts the .out lines into _MB_PINNED and _MB_Q7_SWIPL
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _MB_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
q7 = re.search(r'const _MB_Q7_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'\(\s*"([a-z]\d\d)",\s*raw"(.*?)"\s*\)', src, re.S)
drv = re.search(r'const _MB_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
if "--fill" in sys.argv:
    lines = [l for l in pathlib.Path("mb_rows.out").read_text().split("\n") if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _MB_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _MB_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    ql = [l for l in pathlib.Path("mb_q7.out").read_text().split("\n") if l]
    assert len(ql) == 3 and ql[0] == "ok", ql
    qblock = "const _MB_Q7_SWIPL = [\n" + ",\n".join('    "%s"' % l for l in ql[1:]) + "\n]\n"
    new, n = re.subn(r"const _MB_Q7_SWIPL = \[\n(?:.*?\n)?\]\n", lambda m: qblock, new, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
text = prog + "".join(f"t_{i}(R) :- catch(({g}), error(F, _), R = raised(F)), mb_done.\n" for i, g in cases)
pathlib.Path("mb_rows.pl").write_text(text)
pathlib.Path("mb_q7_rows.pl").write_text(q7)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("mb_rows.pl").resolve()
pathlib.Path("mb_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
here7 = pathlib.Path("mb_q7_rows.pl").resolve()
pathlib.Path("mb_q7_driver.pl").write_text(drv + f":- initialization((fz_run('{here7}', [t_q7a, t_q7b]), halt)).\n")
print(len(cases), "cases")
