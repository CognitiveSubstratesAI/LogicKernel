import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run import run
import groups
for key, label, prog, cases in groups.G:
    if len(sys.argv) > 1 and key not in sys.argv[1:]: continue
    g = dict(key=key, program=prog, cases=cases)
    o1, e1 = run(g); o2, e2 = run(g)
    print("==", key, "IDENTICAL" if o1 == o2 else "DIFFERENT")
    print(o1)
    if e1.strip(): print("STDERR:", e1[:600])
