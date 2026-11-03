# PR1 rows: the program + cases of test/core_lang/test_pr1_swipl.jl, written as _pr_file() writes them, then run through the
# test file's own driver (fz_run) in swipl 10.1.19. Usage (cwd = evidence/PR1, repo = the worktree root):
#   python3 gen_rows.py ../../test/core_lang/test_pr1_swipl.jl          # writes pr1_rows.pl, pr1_driver.pl
#   swipl -q pr1_driver.pl < /dev/null > pr_rows.out                     # run twice, the two outputs must be byte-identical
#   python3 gen_rows.py ../../test/core_lang/test_pr1_swipl.jl --fill   # puts pr_rows.out into _PR_PINNED
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1])
src = tf.read_text()
if "--rd" in sys.argv:
    # PR1b: the two-file rows (_PR_RD_A, _PR_RD_B, _PR_RD_NAMES): consult([A, B]) in swipl, twice, byte-identical, then _PR_RD_PINNED
    import subprocess, tempfile, os
    ra = re.search(r'const _PR_RD_A = raw"""\n(.*?)"""', src, re.S).group(1)
    rb = re.search(r'const _PR_RD_B = raw"""\n(.*?)"""', src, re.S).group(1)
    names = re.search(r'const _PR_RD_NAMES = \[(.*?)\]', src, re.S).group(1).replace('"', '').replace(' ', '')
    drv = re.search(r'const _PR_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
    d = tempfile.mkdtemp(dir=os.getcwd())
    fa, fb = os.path.join(d, "pr1_rd_a.pl"), os.path.join(d, "pr1_rd_b.pl")
    pathlib.Path(fa).write_text(ra); pathlib.Path(fb).write_text(rb)
    pathlib.Path(d, "drv.pl").write_text(drv + f":- initialization((fz_run(['{fa}','{fb}'], [{names}]), halt)).\n")
    outs = [subprocess.run(["swipl", "-q", os.path.join(d, "drv.pl")], stdin=subprocess.DEVNULL, capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"}).stdout for _ in range(2)]
    assert outs[0] == outs[1], "two runs differ"
    lines = [l for l in outs[0].split("\n") if l]
    assert not any(c in l for l in lines for c in '"$\\'), "a pinned line needs escaping"
    assert len(lines) == len(names.split(",")) + 1
    block = "const _PR_RD_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    if "RDPINNED_PLACEHOLDER" in src:
        src = src.replace("RDPINNED_PLACEHOLDER\n", block)
    else:
        src, n = re.subn(r"const _PR_RD_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
        assert n == 1
    tf.write_text(src)
    import shutil; shutil.rmtree(d)
    print("rd rows", len(lines))
    sys.exit(0)
prog = re.search(r'const _PR_PROGRAM = raw"""\n(.*?)"""', src, re.S).group(1)
body = re.search(r'const _PR_CASES = \[\n(.*?)\n\]\n', src, re.S).group(1)
cases = re.findall(r'\(\s*"(pr\d{2,3})",\s*raw"(.*)"\s*,?\s*\)\s*,?\s*$', body, re.M)
drv = re.search(r'const _PR_DRIVER = raw"""\n(.*?)"""', src, re.S).group(1)
assert len(cases) == len(re.findall(r'"pr\d{2,3}",', body)), "a case was not parsed"
ids = [i for i, _ in cases]
assert len(set(ids)) == len(ids) and ids == ["pr%02d" % k for k in range(1, len(ids) + 1)], "ids must run pr01.. in order"
if "--fill" in sys.argv:
    lines = [l for l in pathlib.Path("pr_rows.out").read_text().split("\n") if l]
    assert len(lines) == len(cases) + 1, (len(lines), len(cases))
    assert not any(c in l for l in lines for c in '"$\\'), "a pinned line needs escaping"
    block = "const _PR_PINNED = [\n" + ",\n".join('    "%s"' % l for l in lines) + "\n]\n"
    new, n = re.subn(r"const _PR_PINNED = \[\n(?:.*?\n)?\]\n", lambda m: block, src, count=1, flags=re.S)
    assert n == 1
    tf.write_text(new)
    print("filled", len(lines), "lines")
    sys.exit(0)
text = prog + "".join(f"t_{i}(R) :- catch(({g}), error(E, _), R = raised(E)).\n" for i, g in cases)
pathlib.Path("pr1_rows.pl").write_text(text)
names = ",".join(f"t_{i}" for i, _ in cases)
here = pathlib.Path("pr1_rows.pl").resolve()
pathlib.Path("pr1_driver.pl").write_text(drv + f":- initialization((fz_run('{here}', [{names}]), halt)).\n")
print(len(cases), "cases")
