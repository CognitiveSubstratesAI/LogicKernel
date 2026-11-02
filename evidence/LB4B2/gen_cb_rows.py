# Generates the swipl pins of test/core_lang/test_cont_boot_swipl.jl: reads the file's raw strings,
# writes the program + cases exactly as _cb_file() does and the driver as _cb_swipl_lines() does,
# runs swipl (LC_ALL=C) and prints the driver's output.  usage: python3 -I gen_cb_rows.py <test file> <outdir>
import re, subprocess, sys, os
src = open(sys.argv[1]).read()
out = sys.argv[2]
def raw_block(name):
    m = re.search(r'const ' + name + r' = raw"""\n(.*?)"""', src, re.S)
    return m.group(1)
program = raw_block('_CB_PROGRAM')
driver = raw_block('_CB_DRIVER')
def cases(name):
    body = re.search(r'const ' + name + r' = \[\n(.*?)\n\]\n', src, re.S).group(1)
    return re.findall(r'\(\s*"([a-z_0-9]+)",\s*raw"((?:[^"\\]|\\.)*)"', body)
allc = cases('_CB_CASES') + cases('_CB_CONT1')
names = ['t_' + i for i, _ in allc]
text = program + ''.join('t_%s(R) :- catch((%s), error(SsuE, _), R = raised(SsuE)).\n' % (i, g) for i, g in allc)
pl = os.path.join(out, 'contboot.pl')
open(pl, 'w').write(text)
drv = os.path.join(out, 'drv.pl')
open(drv, 'w').write(driver + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (pl, ','.join(names)))
env = {'LC_ALL': 'C', 'PATH': os.environ['PATH'], 'HOME': os.environ['HOME']}
r = subprocess.run(['swipl', '-q', drv], stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdout=subprocess.PIPE, env=env, timeout=120)
sys.stdout.write(r.stdout.decode())
print(len(allc), file=sys.stderr)
