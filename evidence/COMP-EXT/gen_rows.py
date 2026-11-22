# COMP-EXT rows: the program + wrapper + cases + driver of test/core_lang/test_compext_swipl.jl, written as _cx_file() writes them,
# run through the driver (fz_run) in swipl TWICE with the EXPLICIT pin binary (capped scope), the two outputs compared; the answer lines
# are written into `_CX_PINNED` of the test file. Output (current directory): cx_rows.pl, cx_driver.pl, cx_rows.out, cx_rows.out2.
# usage: python3 -I gen_rows.py <path to test_compext_swipl.jl>   (the test file is rewritten in place)
import re, subprocess, sys, pathlib

SWIPL = str(pathlib.Path.home() / ".local/bin/swipl")
CAP = ["systemd-run", "--user", "--scope", "-q", "-p", "MemoryMax=2G", "-p", "MemorySwapMax=0", "-p", "TasksMax=64", "timeout", "300"]
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
prog = re.search(r'const _CX_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
drv = re.search(r'const _CX_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
wrap = re.search(r'const _CX_WRAP = raw"(.*?)" \*\s*\n\s*"\\n"', src, re.S).group(1) + "\n"
cases = re.findall(r'\(\s*"(cx\d\d)",\s*raw"(.*?)"\s*\),?\n', src, re.S)
assert len(cases) == 64, len(cases)
text = prog + "".join(wrap.replace("@ID@", i).replace("@GOAL@", g) for i, g in cases)
pathlib.Path("cx_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("cx_rows.pl").resolve()
pathlib.Path("cx_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")

def run():
    r = subprocess.run(CAP + [SWIPL, "-q", "cx_driver.pl"], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True)
    return [l for l in r.stdout.split("\n") if l]

v = subprocess.run([SWIPL, "--version"], capture_output=True, text=True, check=True).stdout.strip()
print(v)
a = run()
b = run()
pathlib.Path("cx_rows.out").write_text("\n".join(a) + "\n")
pathlib.Path("cx_rows.out2").write_text("\n".join(b) + "\n")
assert a == b, "the two swipl runs differ"
assert len(a) == len(cases) + 1, (len(a), len(cases))
body = ",\n".join('    "' + l.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$") + '"' for l in a)
new = "const _CX_PINNED = [\n" + body + "\n]\n"
s2, n = re.subn(r"const _CX_PINNED = (?:String\[\]|\[.*?\n\])\n", lambda m: new, src, count=1, flags=re.S)
assert n == 1
tf.write_text(s2)
print(len(cases), "cases,", len(a), "answer lines, two runs identical")
