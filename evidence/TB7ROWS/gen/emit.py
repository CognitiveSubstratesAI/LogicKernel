# emits the Julia constants (programs, cases, pins, groups) of test_tabling_tb7rows_swipl.jl from the swipl runs; asserts two identical runs
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run import run
import groups
out, grp, pins_txt = [], [], []
for key, label, prog, cases in groups.G:
    g = dict(key=key, program=prog, cases=cases)
    o1, e1 = run(g); o2, e2 = run(g)
    assert o1 == o2 and not e1.strip(), key
    lines = [l for l in o1.split("\n") if l]
    assert len(lines) == len(cases) + 1 and lines[0] == "ok", key
    for l in lines: assert '"' not in l and "$" not in l
    assert '"""' not in prog and "\\" not in prog and '"' not in label and "\\" not in label, key
    for i, goal in cases: assert '"' not in goal and "\\" not in goal
    out.append('const _T7_PROG_%s = raw"""%s"""\n' % (key, prog))
    out.append("const _T7_CASES_%s = [\n%s\n]\n" % (key, ",\n".join('    ("%s", raw"%s")' % (i, goal) for i, goal in cases)))
    out.append("const _T7_PINS_%s = [\n%s\n]\n" % (key, ",\n".join('    "%s"' % l for l in lines)))
    grp.append('    (\n        key="%s",\n        label=raw"%s",\n        program=_T7_PROG_%s,\n        cases=_T7_CASES_%s,\n        pins=_T7_PINS_%s\n    )' % (key, label, key, key, key))
    pins_txt.append("== %s IDENTICAL (two swipl runs)\n%s\n" % (key, o1))
out.append("const _T7_GROUPS = [\n%s\n]\n" % ",\n".join(grp))
open(sys.argv[1], "w").write("\n".join(out))
open(sys.argv[2], "w").write("\n".join(pins_txt))
