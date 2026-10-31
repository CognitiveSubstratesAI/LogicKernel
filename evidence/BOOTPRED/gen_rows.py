# BOOTPRED rows: the program + cases of test/core_lang/test_bootpred_swipl.jl, written as _bp_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/BOOTPRED, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_lang/test_bootpred_swipl.jl          # writes bootpred_rows.pl, bootpred_driver.pl
#   swipl -q bootpred_driver.pl < /dev/null > bootpred_rows.out              # run twice, the two outputs must be byte-identical
#   python3 gen_rows.py ../../test/core_lang/test_bootpred_swipl.jl --fill   # puts bootpred_rows.out into _BP_PINNED
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _BP_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'\(\s*"(bp\d\d)",\s*raw"(.*?)"\s*\)', src, re.S)
drv = re.search(r'const _BP_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
if "--fill" in sys.argv:
    lines = pathlib.Path("bootpred_rows.out").read_text().split("\n")
    lines = [l for l in lines if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _BP_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _BP_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
text = prog + "".join(f"t_{i}(R) :- catch(({g}), error(SsuE, _), R = raised(SsuE)).\n" for i, g in cases)
pathlib.Path("bootpred_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("bootpred_rows.pl").resolve()
pathlib.Path("bootpred_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
print(len(cases), "cases")
