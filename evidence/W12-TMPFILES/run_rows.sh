#!/bin/bash
# ORIGINAL (W12-TMPFILES): the driver that makes test/files/test_tmp_files_swipl.out with swipl 10.1.20 — the rows
# (test/files/test_tmp_files_swipl.pl), the test's own DRIVER text (cut out of test/files/test_tmp_files_swipl.jl), `timeout 20` on
# every swipl call, LC_ALL=C, two runs in two fresh working directories, byte-identical or no .out.
# Usage: bash evidence/W12-TMPFILES/run_rows.sh <scratch-dir> (from the repository root; <scratch-dir> is new or empty)
set -eu
root=$(pwd)
scr=$1
mkdir -p "$scr"
python3 -I - "$root/test/files/test_tmp_files_swipl.jl" "$root/test/files/test_tmp_files_swipl.pl" "$scr/drv.pl" <<'PY'
import re, sys
jl, rows, out = sys.argv[1:4]
src = open(jl).read()
i = src.index('const DRIVER = raw"""') + len('const DRIVER = raw"""')
driver = src[i:src.index('"""', i)]
names = re.findall(r'^(t\d+)\(R\) :-', open(rows).read(), re.M)
names = list(dict.fromkeys(names))
open(out, 'w').write(driver + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (rows, ",".join(names)))
PY
for k in 1 2; do
  d="$scr/run$k"
  mkdir "$d"
  (cd "$d" && LC_ALL=C timeout 20 swipl -q "$scr/drv.pl" < /dev/null > "$scr/out$k.txt" 2> "$scr/err$k.txt")
done
cmp "$scr/out1.txt" "$scr/out2.txt"
cp "$scr/out1.txt" "$root/test/files/test_tmp_files_swipl.out"
wc -l "$scr/out1.txt"
