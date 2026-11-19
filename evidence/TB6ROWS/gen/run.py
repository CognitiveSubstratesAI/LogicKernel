import subprocess, sys, hashlib, os, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
def run(g, extra_after=""):
    drv = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "driver.pl")).read()
    text = g["program"] + "".join("t_%s(R) :- catch((%s), error(SsuE, _), R = raised(SsuE)).\n" % (i, goal) for i, goal in g["cases"])
    d = tempfile.mkdtemp(dir=os.path.dirname(os.path.abspath(__file__)))
    pf = os.path.join(d, "prog.pl"); open(pf, "w").write(text)
    names = ",".join("t_%s" % i for i, _ in g["cases"])
    df = os.path.join(d, "drv.pl")
    open(df, "w").write(drv + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (pf, names))
    env = dict(os.environ, LC_ALL="C")
    out = subprocess.run(["swipl", "-q", df], stdin=subprocess.DEVNULL, capture_output=True, text=True, env=env, timeout=120)
    return out.stdout, out.stderr
if __name__ == "__main__":
    import importlib
    mod = importlib.import_module(sys.argv[1])
    keys = sys.argv[2:]
    for g in mod.G:
        if keys and g["key"] not in keys: continue
        o1, e1 = run(g); o2, e2 = run(g)
        print("== ", g["key"], "IDENTICAL" if o1 == o2 else "DIFFERENT")
        print(o1); 
        if e1.strip(): print("STDERR:", e1[:500])
