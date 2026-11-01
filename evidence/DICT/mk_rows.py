# DICT rows: writes test/core_lang/test_dict_preds_swipl.jl from cases.py (this directory) and test_bootpred_swipl.jl's helpers, and the
# swipl side's program and driver, as test_dict_preds_swipl.jl's _dp_file()/_DP_DRIVER write them. Modelled on evidence/BOOTPRED/gen_rows.py.
# Usage (cwd = evidence/DICT, repo = the worktree root):
#   python3 mk_rows.py                      # writes dict_rows.pl, dict_driver.pl and ../../test/core_lang/test_dict_preds_swipl.jl
#   swipl -q dict_driver.pl < /dev/null > dict_rows.out      # run twice: the two outputs must be byte-identical
#   python3 mk_rows.py                      # again: the pins (_DP_PINNED) are filled from dict_rows.out when it exists
import re, sys, pathlib
here = pathlib.Path(__file__).resolve().parent
repo = here.parent.parent
ns = {}
exec((here / "cases.py").read_text(), ns)
# numbered flat list with the group boundaries
flat, bounds, n = [], [], 0
for gname, goals in ns["GROUPS"]:
    first = n + 1
    for goal in goals:
        n += 1
        assert '"' not in goal, goal
        flat.append(("dp%02d" % n, goal))
    bounds.append((gname, first, n))
bp = (repo / "test/core_lang/test_bootpred_swipl.jl").read_text()


def take(start, end):
    i = bp.index(start)
    j = bp.index(end, i)
    return bp[i:j]


def rename(s):
    return s.replace("_BP", "_DP").replace("_bp", "_dp").replace("bootpred", "dictpreds")


enc = rename(take('_bp_codes(s::String)', '# the swipl side'))
driver = rename(take('# the swipl side', '# the program'))
filekernel = rename(take('function _bp_file()', '@testset "thread_self'))
PROGRAM = """dpairs(D, Ps) :- findall(K-V, get_dict(K, D, V), Ps0), msort(Ps0, Ps).
dp_mem(X, [X|_]).
dp_mem(X, [_|T]) :- dp_mem(X, T).
"""
drv_src = re.search(r'const _DP_DRIVER = raw"""\n(.*?)"""', driver, re.S).group(1)
prog_text = PROGRAM + "".join(f"t_{i}(R) :- catch(({g}), error(SsuE, _), R = raised(SsuE)).\n" for i, g in flat)
(here / "dict_rows.pl").write_text(prog_text)
names = ",".join(f"t_{i}" for i, _ in flat)
(here / "dict_driver.pl").write_text(
    drv_src + f":- initialization((fz_run('{here / 'dict_rows.pl'}', [{names}]), halt)).\n")
out = here / "dict_rows.out"
pinned = [l for l in out.read_text().split("\n") if l] if out.exists() else []
if pinned:
    assert len(pinned) == len(flat) + 1, (len(pinned), len(flat))
pins = "const _DP_PINNED = [\n" + ",\n".join('    "%s"' % l for l in pinned) + "\n]\n"
cs = ",\n".join(f'    ("{i}", raw"{g}")' for i, g in flat)
grp = "".join(f"# {a}-{b}: {name}\n" for name, f, l in bounds for a, b in [("dp%02d" % f, "dp%02d" % l)])
nonvac = (here / "nonvac.jl.txt").read_text() if (here / "nonvac.jl.txt").exists() else ""
text = f"""# ORIGINAL: a LIVE differential of BOOTPRED-dict against swipl at the pin (pl-dict.c) — DICT's rows
# test/core_lang/test_dict_preds_swipl.jl — the pl-dict.c predicates written for R2b (D-0290; the wip/dict stack): $get_dict_ex/3,
# get_dict/5, put_dict/4, dict_pairs/3, del_dict/4, :</2, >:</2, dict_same_keys/2 and $get_dict_kv/4,6,8 (dp01-dp{n:02d}) against swipl 10.1.19:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver and the term encoder are test_bootpred_swipl.jl's (one extractor, both sides).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, evidence/DICT/dict_rows.out in the wip/dict branch, two byte-identical
#     runs); with `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
#   * Dicts are built by dict_create/3 and put_dict/3 only (the reader refuses dicts, the writer has no dict arm) and never appear in an
#     answer: a row observes a dict through dict_pairs/3, `dpairs/2` (get_dict/3 findall, msort) or a single lookup.
#   * b_set_dict/3, nb_set_dict/3 and nb_link_dict/3 are left to the SETARG follow-up, which adds their rows.
{grp}using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the predicates ride the term layer through the dict cells and callProlog; every type in CI
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _DP = lk_term_type(Union{{Int64, Float64, String, BigInt, Rational{{BigInt}}}})
_dps(x) = lk_sym(_DP, Symbol(x))

{enc}{driver}
# the program: dpairs/2 observes a dict, dp_mem/2 stands for member/2 (library(lists) is not loaded by the kernel yet; LB4)
const _DP_PROGRAM = raw\"\"\"
{PROGRAM}\"\"\"

const _DP_CASES = [
{cs}
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; evidence/DICT/dict_rows.out in the wip/dict branch)
{pins}
{filekernel}{nonvac}"""
tf = repo / "test/core_lang/test_dict_preds_swipl.jl"
tf.write_text(text)
print(len(flat), "cases", len(pinned), "pins")
