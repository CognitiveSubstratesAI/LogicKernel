# RDDICT rows: writes test/core_lang/test_read_dict_swipl.jl from cases.py (this directory), the swipl side's programs and drivers, and
# (when the .out files exist) the pins. Modelled on evidence/DICT/mk_rows.py (the encoder and the driver are test_dict_preds_swipl.jl's).
# Usage (cwd = evidence/RDDICT, repo = the worktree root; LC_ALL=C):
#   python3 mk_rows.py                                   # writes rdd_rows.pl, rdd_mode_<m>.pl, rdd_driver.pl, rdd_mode_driver_<m>.pl
#   for f in rdd_driver rdd_mode_driver_dict ...; swipl -q $f.pl < /dev/null > ${f/driver/rows}.out   # TWICE, byte-identical (run_swipl.sh)
#   python3 mk_rows.py                                   # again: the pins are filled from the .out files when they exist
import re, sys, pathlib
here = pathlib.Path(__file__).resolve().parent
repo = here.parent.parent
ns = {}
exec((here / "cases.py").read_text(), ns)
flat, bounds, n = [], [], 0
for gname, goals in ns["GROUPS"]:
    first = n + 1
    for goal in goals:
        n += 1
        flat.append(("rd%02d" % n, goal))
    bounds.append((gname, first, n))
modes = ns["MODES"]
mflat = [("rm%02d" % (i + 1), g) for i, g in enumerate(ns["MODE_CASES"])]
mfile = {"dict": "dict", "error": "error", "warning": "warning", "attvar": "attvar", "#": "dyndict"}
dp = (repo / "test/core_lang/test_dict_preds_swipl.jl").read_text()


def take(start, end):
    i = dp.index(start)
    j = dp.index(end, i)
    return dp[i:j]


def rename(s):
    return s.replace("_DP", "_RDD").replace("_dp", "_rdd").replace("dictpreds", "readdict")


enc = rename(take('_dp_codes(s::String)', '# the swipl side'))
driver = rename(take('# the swipl side', 'function _dp_swipl_lines'))
swl = rename(take('function _dp_swipl_lines', '# the program'))
drv_src = re.search(r'const _RDD_DRIVER = raw"""\n(.*?)"""', driver, re.S).group(1)
kern = rename(take('"The kernel\'s lines for', '@testset "dict-predicate rows'))
a = "function _rdd_kernel(path::String, names::Vector{String})"
assert kern.count(a) == 1
kern = kern.replace(a, "function _rdd_kernel(path::String, names::Vector{String}; mode::Union{Nothing, String}=nothing)")
b = "    ld = LK.PL_local_data{_RDD}(gd)\n"
assert kern.count(b) == 1
kern = kern.replace(b, b + """    if mode !== nothing      # the module's var_tag, as `set_prolog_flag(var_tag, Mode)` sets it (F1b writes that arm): setVarTagFlag on the module's flags
        user = LK.MODULE_user(gd)
        user.flags = LK.setVarTagFlag(ld, _rdds(mode), user.flags)::UInt32
    end
""")
PROGRAM, BODIES = ns["PROGRAM"], ns["BODIES"]


def clauses(cs):
    return "".join(f"t_{i}(R) :- catch(({g}), error(SsuE, _), R = raised(SsuE)).\n" for i, g in cs)


def drv_text(prog_file, cs):
    names = ",".join(f"t_{i}" for i, _ in cs)
    return drv_src + f":- initialization((fz_run('{prog_file}', [{names}]), halt)).\n"


(here / "rdd_rows.pl").write_text(PROGRAM + BODIES + clauses(flat))
(here / "rdd_driver.pl").write_text(drv_text(here / "rdd_rows.pl", flat))
for m in modes:
    f = here / f"rdd_mode_{mfile[m]}.pl"
    f.write_text(f":- set_prolog_flag(var_tag, '{m}').\n" + PROGRAM + clauses(mflat))
    (here / f"rdd_mode_driver_{mfile[m]}.pl").write_text(drv_text(f, mflat))


def pins(path, count, name):
    out = here / path
    lines = [l for l in out.read_text().split("\n") if l] if out.exists() else []
    if lines:
        assert len(lines) == count + 1, (path, len(lines), count)
    return "const %s = [\n" % name + ",\n".join('    "%s"' % l for l in lines) + "\n]\n", lines


def esc(g):
    return g.replace('"', '\\"')


main_pins, mainl = pins("rdd_rows.out", len(flat), "_RDD_PINNED")
mode_pins, model = "", {}
for m in modes:
    txt, ls = pins(f"rdd_mode_rows_{mfile[m]}.out", len(mflat), "_RDD_MODE_%s" % mfile[m].upper())
    mode_pins += txt
    model[m] = ls
cs = ",\n".join(f'    ("{i}", raw"{esc(g)}")' for i, g in flat)
mcs = ",\n".join(f'    ("{i}", raw"{esc(g)}")' for i, g in mflat)
grp = "".join(f"# rd{f:02d}-rd{l:02d}: {name}\n" for name, f, l in bounds)
modelist = ", ".join('"%s"' % m for m in modes)
modedict = ", ".join('"%s" => _RDD_MODE_%s' % (m, mfile[m].upper()) for m in modes)


def code(t):
    return "[" + ",".join(str(ord(c)) for c in t) + "]"


def cnt(ls, pred):
    return sum(1 for l in ls if pred(l))


rows = mainl[1:]
nv = ""
if mainl:
    nv = f"""
@testset "the read-dict rows are not vacuous (rd01-rd{len(flat):02d})" begin
    rows = _RDD_PINNED[2:end]                                                      # the driver's first line is `ok`
    @test _RDD_PINNED[1] == "ok"
    @test length(rows) == length(_RDD_CASES) == {len(flat)}
    code(t) = "[" * join(Int.(collect(t)), ",") * "]"
    # rows that fail have no answer after the name; rows whose reader raised (raised(…): an error the row did not catch itself)
    @test count(l -> occursin(r"^t_rd\\d+$", l), rows) == {cnt(rows, lambda l: re.match(r"^t_rd\d+$", l))}
    @test count(l -> occursin(code("raised"), l), rows) == {cnt(rows, lambda l: code("raised") in l)}
    # rds rows: syn(Id, CharNo) answers, read answers (the text read without an error)
    @test count(l -> occursin(code("syn") * "/2", l), rows) == {cnt(rows, lambda l: code("syn") + "/2" in l)}
    @test count(l -> endswith(l, "(a" * code("read") * ")"), rows) == {cnt(rows, lambda l: l.endswith("(a" + code("read") + ")"))}
    # rdd/rdv/rda observations: d(Tag, Pairs) answers (var tags answer `var`), and rdd's nodict(T)
    @test count(l -> occursin(code("d") * "/2(", l), rows) == {cnt(rows, lambda l: code("d") + "/2(" in l)}
    @test count(l -> occursin(code("nodict") * "/1(", l), rows) == {cnt(rows, lambda l: code("nodict") + "/1(" in l)}
    @test count(l -> occursin(code("var"), l), rows) == {cnt(rows, lambda l: code("var") in l)}
    # rdx answers hold the functor of the term read: `.`/2 (code 46) for the dict-dot rows
    @test count(l -> occursin("c[46]/2(", l) || occursin(code("-") * "/2(c[45]/2(a[46]", l), rows) == {cnt(rows, lambda l: "c[46]/2(" in l or code("-") + "/2(c[45]/2(a[46]" in l)}
    # rdp rows: dict_position/5 answers and the key_value_position/7 elements of their last argument
    @test count(l -> occursin(code("dict_position") * "/5(", l), rows) == {cnt(rows, lambda l: code("dict_position") + "/5(" in l)}
    @test count(l -> occursin(code("key_value_position") * "/7(", l), rows) == {cnt(rows, lambda l: code("key_value_position") + "/7(" in l)}
    # the duplicate-key errors are syn(duplicate_key(Key), _)
    @test count(l -> occursin(code("duplicate_key") * "/1", l), rows) == {cnt(rows, lambda l: code("duplicate_key") + "/1" in l)}
    # no answer holds a dict (a dict is a compound named `dict`)
    @test !any(l -> occursin(code("dict") * "/", l), _RDD_PINNED)
end
"""
mnv = ""
if all(model.values()) and mainl:
    mnv = f"""
@testset "the var_tag mode rows are not vacuous (rm01-rm{len(mflat):02d} in {len(modes)} modes)" begin
    code(t) = "[" * join(Int.(collect(t)), ",") * "]"
    for (m, pins) in zip(_RDD_MODES, [{", ".join("_RDD_MODE_" + mfile[m].upper() for m in modes)}])
        @test pins[1] == "ok" && length(pins) == length(_RDD_MODE_CASES) + 1
    end
    # `error`: a variable tag is syn(var_tag, _); `attvar`: the answer is the atom `attvar`; `#` and `warning`: the tag answers `#`
    @test count(l -> occursin(code("var_tag"), l), _RDD_MODE_ERROR) == {cnt(model["error"], lambda l: code("var_tag") in l)}
    @test count(l -> occursin(code("attvar"), l), _RDD_MODE_ATTVAR) == {cnt(model["attvar"], lambda l: code("attvar") in l)}
    @test count(l -> occursin("a[35]", l), _RDD_MODE_DYNDICT) == {cnt(model["#"], lambda l: "a[35]" in l)}
    @test count(l -> occursin("a[35]", l), _RDD_MODE_WARNING) == {cnt(model["warning"], lambda l: "a[35]" in l)}
    @test count(l -> occursin("a[35]", l), _RDD_MODE_DICT) == 0
end
"""

text = open(here / "template.jl.in").read()
for k, v in {
    "@@GROUPS@@": grp, "@@N@@": "%02d" % len(flat), "@@M@@": "%02d" % len(mflat), "@@ENC@@": enc, "@@DRIVER@@": driver, "@@SWL@@": swl, "@@KERNEL@@": kern,
    "@@PROGRAM@@": PROGRAM, "@@BODIES@@": BODIES, "@@CASES@@": cs, "@@MCASES@@": mcs, "@@PINS@@": main_pins, "@@MPINS@@": mode_pins,
    "@@MODES@@": modelist, "@@MODEDICT@@": modedict, "@@NONVAC@@": nv + mnv,
}.items():
    assert k in text, k
    text = text.replace(k, v)
(repo / "test/core_lang/test_read_dict_swipl.jl").write_text(text)
print(len(flat), "cases", len(mflat), "mode cases", len(mainl), "pins")
