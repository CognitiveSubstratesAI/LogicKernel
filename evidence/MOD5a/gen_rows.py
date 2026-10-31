# MOD5a rows: the program + cases of test/core_lang/test_export_import_swipl.jl, written as _mx_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/MOD5a, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_lang/test_export_import_swipl.jl          # writes mx_rows.pl, mx_driver.pl, mx_f5_rows.pl, mx_f5_driver.pl
#   swipl -q mx_driver.pl < /dev/null > mx_rows.out ; swipl -q mx_f5_driver.pl < /dev/null > mx_f5.out
#   python3 gen_rows.py ../../test/core_lang/test_export_import_swipl.jl --fill   # puts the .out lines into _MX_PINNED and _MX_F5_SWIPL
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _MX_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
f5 = re.search(r'const _MX_F5_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'\(\s*"([a-z]\d\d)",\s*raw"(.*?)"\s*\)', src, re.S)
drv = re.search(r'const _MX_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
if "--fill" in sys.argv:
    lines = [l for l in pathlib.Path("mx_rows.out").read_text().split("\n") if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _MX_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _MX_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    f5l = [l for l in pathlib.Path("mx_f5.out").read_text().split("\n") if l]
    assert len(f5l) == 2 and f5l[0] == "ok", f5l
    new, n = re.subn(r'const _MX_F5_SWIPL = "[^"]*"', lambda m: 'const _MX_F5_SWIPL = "%s"' % f5l[1], new, count=1)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
text = prog + "".join(f"t_{i}(R) :- catch(({g}), error(F, _), R = raised(F)).\n" for i, g in cases)
pathlib.Path("mx_rows.pl").write_text(text)
pathlib.Path("mx_f5_rows.pl").write_text(f5)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("mx_rows.pl").resolve()
pathlib.Path("mx_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
here5 = pathlib.Path("mx_f5_rows.pl").resolve()
pathlib.Path("mx_f5_driver.pl").write_text(drv + f":- initialization((fz_run('{here5}', [t_f5]), halt)).\n")
print(len(cases), "cases")
