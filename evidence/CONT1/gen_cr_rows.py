# Generates the swipl pins of test/core_lang/test_cont_run_swipl.jl: reads the file's raw strings, writes the program + cases
# exactly as _cr_file() does and the driver as _cr_swipl_lines() does, runs swipl (LC_ALL=C) TWICE, asserts the two outputs are
# byte-identical and prints the driver's output (the committed evidence/CONT1/cr_rows.out).
# usage: python3 -I gen_cr_rows.py <test file> <outdir>     (swipl 10.1.19)
import re, subprocess, sys, os
src = open(sys.argv[1]).read()
out = sys.argv[2]
def raw_block(name):
    m = re.search(r'const ' + name + r' = raw"""\n(.*?)"""', src, re.S)
    return m.group(1)
program = raw_block('_CR_PROGRAM')
driver = raw_block('_CR_DRIVER')
body = re.search(r'const _CR_CASES = \[\n(.*?)\n\]\n', src, re.S).group(1)
cases = re.findall(r'\(\s*"([a-z_0-9]+)",\s*raw"((?:[^"\\]|\\.)*)"', body)
names = ['t_' + i for i, _ in cases]
text = program + ''.join('t_%s(R) :- catch((%s), error(SsuE, _), R = raised(SsuE)).\n' % (i, g) for i, g in cases)
pl = os.path.join(out, 'contrun.pl')
open(pl, 'w').write(text)
drv = os.path.join(out, 'drv.pl')
open(drv, 'w').write(driver + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (pl, ','.join(names)))
env = {'LC_ALL': 'C', 'PATH': os.environ['PATH'], 'HOME': os.environ['HOME']}
def run():
    r = subprocess.run(['swipl', '-q', drv], stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       stdout=subprocess.PIPE, env=env, timeout=120)
    return r.stdout.decode()
a = run()
b = run()
assert a == b, 'two swipl runs differ'
assert len(a.strip().split('\n')) == len(cases) + 1, 'one line per case plus ok'
sys.stdout.write(a)
print(len(cases), file=sys.stderr)
