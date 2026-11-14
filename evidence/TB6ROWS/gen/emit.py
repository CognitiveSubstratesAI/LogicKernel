# emits the Julia constants (programs, cases, pins) of test_tabling_tb6rows_swipl.jl from the swipl runs; asserts two identical runs
import sys, os, importlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run import run
order = [("groups","CHAIN"),("groups2","REEVAL"),("groups2","SINGLE"),("groups2","FALSECOUNT"),("groups2","ABOLISH"),("groups2","EXPAND"),("groups3","DYNERR"),("groups3","DYNOK"),("groups3","INCRPROP"),("groups4","TRIEKEYS")]
out = []
pins_txt = []
for mod, key in order:
    g = [x for x in importlib.import_module(mod).G if x["key"] == key][0]
    o1, e1 = run(g); o2, e2 = run(g)
    assert o1 == o2 and not e1.strip(), key
    lines = [l for l in o1.split("\n") if l]
    assert len(lines) == len(g["cases"]) + 1 and lines[0] == "ok", key
    for l in lines: assert '"' not in l and "$" not in l
    assert '"""' not in g["program"] and "\\" not in g["program"], key
    out.append('const _T6_PROG_%s = raw"""%s"""\n' % (key, g["program"]))
    out.append("const _T6_CASES_%s = [\n%s\n]\n" % (key, ",\n".join('    ("%s", raw"%s")' % (i, goal) for i, goal in g["cases"])))
    out.append("const _T6_PINS_%s = [\n%s\n]\n" % (key, ",\n".join('    "%s"' % l for l in lines)))
    pins_txt.append("== %s IDENTICAL (two swipl runs)\n%s\n" % (key, o1))
    for i, goal in g["cases"]: assert '"' not in goal
open(sys.argv[1], "w").write("\n".join(out))
open(sys.argv[2], "w").write("\n".join(pins_txt))
