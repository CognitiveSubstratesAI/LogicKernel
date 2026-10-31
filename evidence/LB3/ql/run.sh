#!/bin/bash
cd "$(dirname "$0")"
cat drv.pl > full.pl
echo ":- initialization((fz_run('$PWD/prog.pl', [t_q01,t_q02,t_q03]), halt))." >> full.pl
swipl -q full.pl < /dev/null 2>/dev/null
