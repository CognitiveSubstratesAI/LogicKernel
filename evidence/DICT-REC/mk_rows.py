# DICT-REC rows: writes test/core_lang/test_dictrec_swipl.jl from cases.py (this directory); the encoder, driver and kernel runner
# are test_dict_preds_swipl.jl's with _DP/_dp renamed _DR/_dr (one extractor, both sides). Modelled on evidence/DICT/mk_rows.py.
# Usage (cwd = evidence/DICT-REC, repo = the worktree root):
#   python3 -I mk_rows.py                 # writes dictrec_rows.pl, dictrec_driver.pl and ../../test/core_lang/test_dictrec_swipl.jl
#   systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=0 -p TasksMax=64 \
#       ~/.local/bin/swipl -q dictrec_driver.pl < /dev/null > dictrec_rows.out     # swipl 10.1.20 (the pin binary), twice: byte-identical
#   python3 -I mk_rows.py                 # again: the pins (_DR_PINNED) are filled from dictrec_rows.out when it exists
import re, pathlib
here = pathlib.Path(__file__).resolve().parent
repo = here.parent.parent
ns = {}
exec((here / "cases.py").read_text(), ns)
flat, bounds, n = [], [], 0
for gname, goals in ns["GROUPS"]:
    first = n + 1
    for goal in goals:
        n += 1
        assert '"' not in goal, goal
        flat.append(("dr%02d" % n, goal))
    bounds.append((gname, first, n))
src = (repo / "test/core_lang/test_dict_preds_swipl.jl").read_text()


def take(start, end):
    i = src.index(start)
    j = src.index(end, i)
    return src[i:j]


def rename(s):
    return s.replace("_DP", "_DR").replace("_dp", "_dr").replace("dictpreds", "dictrec")


enc = rename(take('_dp_codes(s::String)', '# the swipl side'))
driver = rename(take('# the swipl side', '# the program'))
filekernel = rename(take('function _dp_file()', '@testset "dict-predicate rows'))
PROGRAM = """dpairs(D, Ps) :- findall(K-V, get_dict(K, D, V), Ps0), msort(Ps0, Ps).
"""
drv_src = re.search(r'const _DR_DRIVER = raw"""\n(.*?)"""', driver, re.S).group(1)
prog_text = PROGRAM + "".join(f"t_{i}(R) :- catch(({g}), error(SsuE, _), R = raised(SsuE)).\n" for i, g in flat)
(here / "dictrec_rows.pl").write_text(prog_text)
names = ",".join(f"t_{i}" for i, _ in flat)
(here / "dictrec_driver.pl").write_text(
    drv_src + f":- initialization((fz_run('{here / 'dictrec_rows.pl'}', [{names}]), halt)).\n")
out = here / "dictrec_rows.out"
pinned = [l for l in out.read_text().split("\n") if l] if out.exists() else []
if pinned:
    assert len(pinned) == len(flat) + 1, (len(pinned), len(flat))
pins = "const _DR_PINNED = [\n" + ",\n".join('    "%s"' % l for l in pinned) + "\n]\n"
cs = ",\n".join(f'    ("{i}", raw"{g}")' for i, g in flat)
grp = "".join(f"# {a}-{b}: {name}\n" for name, f, l in bounds for a, b in [("dr%02d" % f, "dr%02d" % l)])
nonvac = (here / "nonvac.jl.txt").read_text() if (here / "nonvac.jl.txt").exists() else ""
last = flat[-1][0]
text = f"""# ORIGINAL: a LIVE differential of DICT-REC's predicates against swipl at the pin (pl-dict.c, pl-btree.c, pl-write.c) — rows
# dr01-{last}: b_set_dict/3, nb_set_dict/3, nb_link_dict/3, $btree_find_node/5 and $needs_quotes/1:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver and the term encoder are test_dict_preds_swipl.jl's (one extractor, both sides).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, the pin binary ~/.local/bin/swipl, evidence/DICT-REC/dictrec_rows.out, two
#     byte-identical runs); with `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
#   * Dicts are built by dict_create/3 only and never appear in an answer: a row observes one through `dpairs/2` (get_dict/3 findall, msort).
#   * $btree_find_node/5 rows keep every position INSIDE the node (kp, lp, rp < arity): a position one past the last argument is a
#     DIVERGES (src/pl-btree.jl: a type error here, an out-of-bounds read upstream), so no row pins it.
#   * LK-ONLY rows (not comparable with swipl): the REFUSED owner rows ($atom_references/2, $atom_completions/2, malloc_property/1,
#     wait_for_input/3) — what they are and which step refused them; see the last testset.
{grp}using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the predicates ride the term layer through the dict cells and callProlog; every type in CI
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _DR = lk_term_type(Union{{Int64, Float64, String, BigInt, Rational{{BigInt}}}})
_drs(x) = lk_sym(_DR, Symbol(x))

{enc}{driver}
# the program: dpairs/2 observes a dict
const _DR_PROGRAM = raw\"\"\"
{PROGRAM}\"\"\"

const _DR_CASES = [
{cs}
]

# swipl 10.1.20's answers to the program and cases above (the driver's lines; evidence/DICT-REC/dictrec_rows.out)
{pins}
{filekernel}{nonvac}"""
tf = repo / "test/core_lang/test_dictrec_swipl.jl"
tf.write_text(text)
print(len(flat), "cases", len(pinned), "pins")
