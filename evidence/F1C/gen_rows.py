# Generator of the pins of test/core_lang/test_debug_flag_swipl.jl: builds the program and cases file EXACTLY as the test's _db_file does
# (every case followed by the reset of debug and debugger_show_context), runs swipl 10.1.19 with the test's own driver twice (one process per
# run, LC_ALL=C, every swipl call under timeout 20), requires the two runs to be byte-identical, writes evidence/F1C/debug_rows.out and puts the
# lines between the PINS-BEGIN/PINS-END markers of the test file. The cases are read from the test file (a case may be on one line or wrapped by the
# formatter); a double quote in a goal would need the Julia raw-string escape, so a goal has none.
# Usage (from the worktree root): LC_ALL=C python3 -I evidence/F1C/gen_rows.py
import re, subprocess, tempfile, os, sys
T = "test/core_lang/test_debug_flag_swipl.jl"
s = open(T).read()
def raw(name):
    m = re.search(r"const %s = raw\"\"\"\n(.*?)\"\"\"" % name, s, re.S)
    return m.group(1)
program, driver = raw("_DB_PROGRAM"), raw("_DB_DRIVER")
cases = re.findall(r'\(\s*"(db\d+)",\s*raw"((?:[^"\\]|\\.)*)"\s*\)', s)
cases = [(i, g.replace('\\"', '"')) for i, g in cases]    # a Julia raw string: \" is a quote
assert len(cases) >= 30, len(cases)
assert len({i for i, _ in cases}) == len(cases)
text = program + "".join("t_%s(R) :- catch((%s), error(SfE, _), R = raised(SfE)), set_prolog_flag(debug, false), set_prolog_flag(debugger_show_context, false).\n" % (i, g) for i, g in cases)
names = ["t_" + i for i, _ in cases]
env = {"PATH": os.environ["PATH"], "HOME": os.environ["HOME"], "LC_ALL": "C"}    # named variables only
def run():
    with tempfile.TemporaryDirectory() as d:
        pl = os.path.join(d, "debugflag.pl"); open(pl, "w").write(text)
        drv = os.path.join(d, "drv.pl")
        open(drv, "w").write(driver + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (pl, ",".join(names)))
        r = subprocess.run(["timeout", "20", "swipl", "-q", drv], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=40, env=env)
        return r.stdout.decode()
a, b = run(), run()
assert a == b, "two swipl runs differ"
lines = [l for l in a.split("\n") if l]
assert len(lines) == len(cases) + 1, (len(lines), len(cases))
assert lines[0] == "ok", lines[0]
open("evidence/F1C/debug_rows.out", "w").write(a)
pins = "".join('    "%s"%s\n' % (l.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$"), "," if k < len(lines) - 1 else "") for k, l in enumerate(lines))
s2 = re.sub(r"# PINS-BEGIN\n.*?# PINS-END\n", lambda m: "# PINS-BEGIN\n" + pins + "# PINS-END\n", s, flags=re.S)
open(T, "w").write(s2)
print("pins:", len(lines))
