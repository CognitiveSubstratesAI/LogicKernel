# Builds test/core_lang/test_push_flag_swipl.jl from the case table (the pins are filled by gen_push_rows.py).
# Usage: python3 -I evidence/F2/build_push_test.py <cases.json> <out.jl>
import json, sys
cases = json.load(open(sys.argv[1]))
head = open(__file__.replace("build_push_test.py", "push_template.jl")).read()
body = "".join('    ("%s", raw"%s"),\n' % (i, g.replace('"', '\\"')) for i, g in cases).rstrip(",\n") + "\n"
open(sys.argv[2], "w").write(head.replace("@@CASES@@", body))
