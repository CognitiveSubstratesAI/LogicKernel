# S2a rows: the program + cases of test/core_lang/test_s2a_swipl.jl, written as _s2_file() writes them (data and output paths substituted),
# then run through the test file's own driver (fz_run) in swipl 10.1.19, TWICE (the two outputs must be byte-identical). Usage
# (cwd = evidence/S2A, repo = the worktree root; the data directory is a throwaway dir given as argument 2):
#   python3 gen_rows.py ../../test/core_lang/test_s2a_swipl.jl /tmp/dir       # writes s2a_rows.pl, s2a_driver.pl, s2a_rows.out, s2a_rows.out2
#   python3 gen_rows.py ../../test/core_lang/test_s2a_swipl.jl /tmp/dir --fill   # puts the .out lines into _S2_PINNED
import re, sys, pathlib, subprocess
tf = pathlib.Path(sys.argv[1])
d = pathlib.Path(sys.argv[2]).resolve()
d.mkdir(parents=True, exist_ok=True)
src = tf.read_text()
prog = re.search(r'const _S2_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
cases = re.findall(r'\(\s*"(s\d\d\d)",\s*raw"(.*?)"\s*\)', src, re.S)
drv = re.search(r'const _S2_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
data = re.search(r'const _S2_DATA = "(.*?)"\n', src).group(1).encode().decode("unicode_escape")
if "--fill" in sys.argv:
    lines = [l for l in pathlib.Path("s2a_rows.out").read_text().split("\n") if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    block = "const _S2_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _S2_PINNED = \[\n(?:    [^\n]*\n)*\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
(d / "data.txt").write_text(data)
prog = prog.replace("@DATA@", str(d / "data.txt")).replace("@OUT@", str(d / "out.txt"))
text = prog + "".join(
    f"t_{i}(R) :- catch(({g}), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).\n" for i, g in cases
)
pathlib.Path("s2a_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("s2a_rows.pl").resolve()
pathlib.Path("s2a_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
for out in ("s2a_rows.out", "s2a_rows.out2"):
    r = subprocess.run(["swipl", "-q", "s2a_driver.pl"], stdin=subprocess.DEVNULL, capture_output=True, text=True)
    pathlib.Path(out).write_text(r.stdout)
    if out == "s2a_rows.out":
        pathlib.Path("s2a_rows.err").write_text(r.stderr)
print(len(cases), "cases; identical runs:", pathlib.Path("s2a_rows.out").read_text() == pathlib.Path("s2a_rows.out2").read_text())
