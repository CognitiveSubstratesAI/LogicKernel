# RD1 rows: the program + cases of test/core_text/test_read_stream_swipl.jl, written as _rt_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/RD1, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_text/test_read_stream_swipl.jl          # writes rt_rows.pl, rt_driver.pl, the scratch dir rt_tmp
#   LC_ALL=C swipl -q rt_driver.pl < /dev/null 2>/dev/null > rt_rows.out        # run twice, the two outputs must be byte-identical
#   python3 gen_rows.py ../../test/core_text/test_read_stream_swipl.jl --fill   # puts rt_rows.out into _RT_PINNED
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _RT_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'\(\s*"(rt\d{2,3})",\s*raw"""(.*?)"""\s*(?:,\s*"[^"]*"\s*)?\)', src, re.S)
drv = re.search(r'const _RT_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
ids = [i for i, _ in cases]
assert len(set(ids)) == len(ids), "duplicate ids"
if "--fill" in sys.argv:
    lines = [l for l in pathlib.Path("rt_rows.out").read_text().split("\n") if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _RT_PINNED = [\n" + ",\n".join('    "%s"' % l.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$") for l in lines) + "\n]\n"
    new, n = re.subn(r"const _RT_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
tmp = pathlib.Path("rt_tmp").resolve()
tmp.mkdir(exist_ok=True)
text = prog.replace("@RTDIR@", str(tmp)) + "".join(f"t_{i}(R) :- catch(({g}), error(SsuE, _), R = raised(SsuE)).\n" for i, g in cases)
pathlib.Path("rt_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i in ids)
here = pathlib.Path("rt_rows.pl").resolve()
pathlib.Path("rt_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
print(len(cases), "cases")
