#!/usr/bin/env python3
# Generator of the O1A3 rows f100-f106 (audit D-0322 item 3: the kill rows for the survivors of mutants/O1A2): the pins come FROM
# swipl 10.1.19 (two byte-identical runs of the driver of gen_rows.py), and are inserted into test/core_lang/test_format_swipl.jl
# between t_e24 and t_e25 (cases and pins). Usage: python3 -I gen_rows3.py <worktree>   (idempotent: refuses when f100 is there)
import os, subprocess, sys
WT = sys.argv[1]
EV = os.path.join(WT, "evidence", "O1A")
T = os.path.join(WT, "test", "core_lang", "test_format_swipl.jl")
src = open(os.path.join(EV, "gen_rows.py"), encoding="utf-8").read()
PROGRAM = src.split('PROGRAM = r"""')[1].split('"""')[0]
DRIVER = src.split("DRIVER = r'''")[1].split("'''")[0]

NEW = [
 # A1 (outchr, a code point 0x80-0xff with a fill point pending): two Latin-1 characters whose bytes read as one UTF-8 character
 ("f100", r'''format(atom(R), "~t~w~10|", ['Ã©'])''', "two Latin-1 characters that form a UTF-8 sequence, right aligned"),
 # A5 (outstring buffers `len` characters), A6 (outstring advances the column): a code list is a Latin-1 text and takes outstring
 ("f101", r'''format(atom(R), "~t~s~t~10|~a", [[97,98], cd])''', "s of a code list between two fill points"),
 ("f102", r'''format(atom(R), "~s~t~10|~a", [[97,98], cd])''', "s of a code list moves the column"),
 # D7 (~Ns cuts a Latin-1 text): a string and an atom are not Latin-1 texts on the kernel, a code list is
 ("f103", r'''format(atom(R), "~1s|~5s|~0s|~3s", [[104,105],[104,105],[104,105],[104,105,106,107]])''', "s of a code list with a count: cut and padded"),
 # I2 (the default digits of ~h): 1.0e5 and 1.0e-5 are on the exponent threshold of 3 and not of 6
 ("f104", r'''format(atom(R), "~h|~h|~h|~h", [1.0e5, 1.0e-5, 123456.0, 1.0e6])''', "h default threshold"),
 # J6 (the fixed form of ~g): the digit after the last significant one is not zero
 ("f105", r'''format(atom(R), "~g|~2g|~g|~g", [0.123456789, 123.456, 1234.5678, 1.0e-4])''', "g fixed form keeps the significant digits only"),
 # K4 (a call-back that wrote straight to a stream other than the current output hands the current output back)
 ("f106", r'''with_output_to(atom(R), (open('/dev/null', write, S), format(S, "a~@b", [hello_out]), write(x), format(S, "~w", [y]), write(z), close(S)))''', "current output after a call-back on another stream"),
]
text = open(T, encoding="utf-8").read()
assert '("f100"' not in text, "already inserted"

def run(path):
    return subprocess.run(["swipl", "-q", path], stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, check=False).stdout.decode("utf-8")

prog = PROGRAM + "".join("t_%s(R) :- catch((%s), error(SsuE, _), R = raised(SsuE)).\n" % (i, g) for (i, g, _) in NEW)
pf = os.path.join(EV, "o1a3_rows.pl")
open(pf, "w", encoding="utf-8").write(prog)
drv = DRIVER + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (pf, ",".join("t_" + i for (i, _, _) in NEW))
df = os.path.join(EV, "driver3.pl")
open(df, "w", encoding="utf-8").write(drv)
a, b = run(df), run(df)
assert a == b, "two swipl runs differ"
open(os.path.join(EV, "o1a3_rows.out"), "w", encoding="utf-8").write(a)
lines = a.split("\n")[:-1]
assert lines[0] == "ok" and len(lines) == len(NEW) + 1, lines
pins = lines[1:]

case_src = "\n".join('    ("%s", raw"""%s"""),  # %s' % (i, g, c) for (i, g, c) in NEW) + "\n"
pin_src = "\n".join('    "%s",' % p for p in pins) + "\n"
mark_c = '    ("e25", raw"""'
mark_p = '    "t_e25 '
assert text.count(mark_c) == 1 and text.count(mark_p) == 1
text = text.replace(mark_c, case_src + mark_c).replace(mark_p, pin_src + mark_p)
open(T, "w", encoding="utf-8").write(text)
print("inserted", len(NEW), "rows")
for p in pins: print(p)
