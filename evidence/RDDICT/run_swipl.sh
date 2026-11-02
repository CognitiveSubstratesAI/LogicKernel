#!/bin/bash
# Runs swipl 10.1.19 over the RDDICT drivers TWICE (LC_ALL=C), checks the two runs byte-identical and writes the .out pins.
# Usage (cwd = evidence/RDDICT): bash run_swipl.sh      (then python3 mk_rows.py to fill the pins)
set -e
export LC_ALL=C
cd "$(dirname "$0")"
pairs="rdd_driver:rdd_rows"
for m in dict error warning attvar dyndict; do pairs="$pairs rdd_mode_driver_$m:rdd_mode_rows_$m"; done
for p in $pairs; do
  d=${p%%:*}; o=${p##*:}
  swipl -q "$d.pl" < /dev/null > "$o.out" 2>/dev/null
  swipl -q "$d.pl" < /dev/null > "$o.out2" 2>/dev/null
  cmp "$o.out" "$o.out2" && rm "$o.out2"
  echo "$o: $(wc -l < "$o.out") lines"
done
