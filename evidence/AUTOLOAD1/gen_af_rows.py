# Generator of the pins of test/core_lang/test_autoload_flag_swipl.jl: builds the program and cases file EXACTLY as the test's _af_file does,
# runs swipl 10.1.19 with the test's own driver twice (every swipl call under timeout 20), requires the two runs to be byte-identical,
# writes evidence/AUTOLOAD1/af_rows.out and puts the lines between the PINS-BEGIN/PINS-END markers of the test file.
# Usage (from the worktree root): python3 -I evidence/AUTOLOAD1/gen_af_rows.py
import re, subprocess, tempfile, os, sys
T = "test/core_lang/test_autoload_flag_swipl.jl"
s = open(T).read()
def raw(name):
    m = re.search(r"const %s = raw\"\"\"\n(.*?)\"\"\"" % name, s, re.S)
    return m.group(1)
program, driver = raw("_AF_PROGRAM"), raw("_AF_DRIVER")
cases = re.findall(r'^    \(\s*"(af\d+)",\s*raw"(.*?)"\s*\),?$', s, re.M)   # JuliaFormatter splits a long entry over lines
cases = [(i, g.replace('\\"', '"')) for i, g in cases]    # a Julia raw string: \" is a quote
assert len(cases) >= 25, len(cases)
text = program + "".join("t_%s(R) :- catch((%s), error(AfE, _), R = raised(AfE)).\n" % (i, g) for i, g in cases)
names = ["t_" + i for i, _ in cases]
def run():
    with tempfile.TemporaryDirectory() as d:
        pl = os.path.join(d, "autoloadflag.pl"); open(pl, "w").write(text)
        drv = os.path.join(d, "drv.pl")
        open(drv, "w").write(driver + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (pl, ",".join(names)))
        r = subprocess.run(["timeout", "20", "swipl", "-q", drv], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=40)
        return r.stdout.decode()
a, b = run(), run()
assert a == b, "two swipl runs differ"
lines = [l for l in a.split("\n") if l]
assert len(lines) == len(cases) + 1, (len(lines), len(cases))
open("evidence/AUTOLOAD1/af_rows.out", "w").write(a)
pins = "".join('    "%s"%s\n' % (l.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$"), "," if k < len(lines) - 1 else "") for k, l in enumerate(lines))
s2 = re.sub(r"# PINS-BEGIN\n.*?# PINS-END\n", lambda m: "# PINS-BEGIN\n" + pins + "# PINS-END\n", s, flags=re.S)
open(T, "w").write(s2)
print("pins:", len(lines))
