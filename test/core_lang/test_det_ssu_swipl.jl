# ORIGINAL: the `det/1` declaration and its `S_DET` supervisor prefix (SSU1b: pl-vmi.c S_DET, pl-proc.c setDetDefinition, pl-supervisor.c
# chainPredicateSupervisor, pl-wrap.c skipWrapperPrefix) against swipl at the pin. It holds the `det_decl` unit of upstream's
# tests/core_lang/test_det_decl.pl (cases det, cdet, cdet2, nondet_1..3, fail_1..3) and the tabled SSU case `ssu_complete_fails` of
# tests/tabling/test_tabled_supervisor.pl (:135-137 the program, :364-372 the case); its `det_guard` and `det_goal` units are rows of
# test/core_lang/test_det_swipl.jl.
# test/core_lang/test_det_ssu_swipl.jl — rows `dd_*` (the `det_decl` unit, upstream test names in the ids), `ex_*` (beyond the unit: the
# attribute read and written through '$set_predicate_attribute'/3, det with SSU rules in both declaration orders, a dynamic predicate, a
# predicate with no clauses), `tt_*` (det on a tabled predicate, both orders), `sc_*` (`ssu_complete_fails`), then white-box testsets:
# the supervisor codes (`def.codes[1] == S_DET`, `[S_SSU_DET, S_DET]`), the setter, the `FR_DET` frame flag, `skipWrapperPrefix`.
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; swipl's driver prints the same readable lines (`enc/1`).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20 at the pin, two byte-identical runs, command and output in
#     evidence/TAB1/ssu1b_verify.md); with `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when this file was written): every kernel answer and every white-box row; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these rows ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _DS = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_dss(x) = lk_sym(_DS, Symbol(x))

"A term as the driver's `enc/1` writes it: `_` for a variable, atoms and numbers as `write/1`, a compound as `name(args)`."
function _ds_enc(t::_DS)::String
    k = kind(t)
    if k === VAR
        return "_"
    elseif k === SYM
        return is_nil(t) ? "[]" : sym_text(t)
    elseif k === GND
        return string(lk_value(t))
    end
    h = child(t, 1)
    return (is_nil(h) ? "[]" : sym_text(h)) * "(" *
           join([_ds_enc(child(t, i)) for i in 2:nchildren(t)], ",") * ")"
end

const _DS_DRIVER = raw"""
enc(T) :- var(T), !, write('_').
enc(T) :- atomic(T), !, write(T).
enc(T) :- compound_name_arguments(T, N, As), write(N), write('('), encs(As), write(')').
encs([]) :- !.
encs([A]) :- !, enc(A).
encs([A|As]) :- enc(A), write(','), encs(As).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""

function _ds_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _DS_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# The program, in the user module. Section 1 is test_det_decl.pl:55-98 (the `det_decl` unit) with `with_debug/1` from :200-205; section 2
# is test_tabled_supervisor.pl:135-137 with its `all/3` (:50); the rest is ours. The white-box predicates wb*, fr* are never called by a row.
const _DS_PROGRAM = raw"""
:- det((p1/1, p2/1, np/1, cdet/0, cdet2/0)).
p1(1).
p1(2).
p1(2).
p2(X) :- sp2(X).
sp2(1).
np(X) :- np1(X).
np1(X) :- np2(X).
np2(1).
np2(2).
cdet :- np2(_), !.
cdet2 :- np2(X), !, np2(X).
:- meta_predicate with_debug(0).
with_debug(Goal) :-
    current_prolog_flag(debug, Old),
    setup_call_cleanup(set_prolog_flag(debug, true), Goal, set_prolog_flag(debug, Old)).
:- meta_predicate all(?, 0, -).
all(T, G, L) :- findall(T, G, L0), msort(L0, L).
ssu(X) => X == a.
ssm(X) => member(X, [a,b]).
:- table ssu/1, ssm/1.
:- det(dk/1).
dk(1).
dk(2).
dl(1).
dl(2).
:- det(de/1).
de(a) => true.
de(b) => fail.
ds(a) => true.
ds(b) => fail.
:- det(ds/1).
:- dynamic dy/1.
:- det(dy/1).
:- det(a1/1).
:- det(tdt/1).
:- table tdt/1.
tdt(1).
:- table tdn/1.
:- det(tdn/1).
tdn(1).
tdn(2).
:- det(tdm/1).
:- table tdm/1.
tdm(1).
tdm(2).
wb1(1).
wb1(2).
:- det(wb2/1).
wb2(1).
wb2(2).
wb3(a) => true.
:- det(wb3/1).
fr1(1).
fr1(2).
:- det(fr2/1).
fr2(1).
fr2(2).
"""

# (id, goal): the case `t_<id>(R)`; the id carries upstream's test name for the `dd_` and `sc_` rows.
const _DS_CASES = [
    ("dd_det", raw"p1(1), R = ok"),
    ("dd_cdet", raw"cdet, R = ok"),
    ("dd_cdet2", raw"cdet2, R = ok"),
    ("dd_nondet_1", raw"p1(2), R = ok"),
    ("dd_nondet_2", raw"np(_), R = ok"),
    ("dd_nondet_3", raw"with_debug(np(_)), R = ok"),
    ("dd_fail_1", raw"p1(3), R = ok"),
    ("dd_fail_2", raw"np(3), R = ok"),
    ("dd_fail_3", raw"with_debug(np(3)), R = ok"),
    ("ex_p2_1", raw"p2(1), R = ok"),
    ("ex_p2_2", raw"p2(2), R = ok"),
    ("ex_p2_3", raw"with_debug(p2(2)), R = ok"),
    ("ex_get_1", raw"( '$get_predicate_attribute'(p1(_), det, V) -> R = V ; R = none )"),
    ("ex_get_2", raw"( '$get_predicate_attribute'(sp2(_), det, V) -> R = V ; R = none )"),
    ("ex_dk1", raw"dk(_), R = ok"),
    ("ex_dk2", raw"'$set_predicate_attribute'(dk(_), det, false), findall(X, dk(X), R)"),
    ("ex_dk3", raw"( '$get_predicate_attribute'(dk(_), det, V) -> R = V ; R = none )"),
    ("ex_dk4", raw"'$set_predicate_attribute'(dk(_), det, true), dk(_), R = ok"),
    ("ex_dk5", raw"( '$get_predicate_attribute'(dk(_), det, V) -> R = V ; R = none )"),
    (
        "ex_dl",
        raw"findall(X, dl(X), L), '$set_predicate_attribute'(dl(_), det, true), ( catch(dl(_), error(E, _), true) -> R = L-E ; R = L-failed )"
    ),
    ("ex_de1", raw"de(a), R = ok"),
    ("ex_de2", raw"de(b), R = ok"),
    ("ex_de3", raw"de(c), R = ok"),
    ("ex_ds1", raw"ds(a), R = ok"),
    ("ex_ds2", raw"ds(b), R = ok"),
    ("ex_ds3", raw"ds(c), R = ok"),
    ("ex_dy1", raw"assertz(dy(1)), assertz(dy(2)), dy(1), R = ok"),
    ("ex_dy2", raw"dy(_), R = ok"),
    ("ex_dy3", raw"dy(3), R = ok"),
    ("ex_a1", raw"a1(1), R = ok"),
    ("tt_det_table", raw"tdt(1), tdt(1), tdt(1), R = ok"),
    ("tt_table_det", raw"tdn(_), R = ok"),
    ("tt_det_table_nd", raw"tdm(_), R = ok"),
    (
        "sc_ssu_complete_fails",
        raw"abolish_all_tables, ( \+ ssu(b) -> F1 = true ; F1 = false ), ( \+ ssu(b) -> F2 = true ; F2 = false ), ( ssu(a) -> A = true ; A = false ), all(X, ssm(X), Ls), ( \+ ssm(c) -> M1 = true ; M1 = false ), ( \+ ssm(c) -> M2 = true ; M2 = false ), R = r(F1, F2, A, Ls, M1, M2)"
    ),
    ("sc_ssu_answers", raw"abolish_all_tables, all(X, ssu(X), R)"),
    ("sc_ssm_answers", raw"abolish_all_tables, ssm(b), all(X, ssm(X), R)")
]

# >>> PINNED (generated by evidence/TAB1/ssu1b_pins.py from the cases above; do not edit by hand)
const _DS_PINNED = String[
    "ok",
    "t_dd_det t_dd_det(ok)",
    "t_dd_cdet t_dd_cdet(ok)",
    "t_dd_cdet2 t_dd_cdet2(ok)",
    "t_dd_nondet_1 t_dd_nondet_1(raised(determinism_error(/(p1,1),det,nondet,property)))",
    "t_dd_nondet_2 t_dd_nondet_2(raised(determinism_error(/(np2,1),det,nondet,property)))",
    "t_dd_nondet_3 t_dd_nondet_3(raised(determinism_error(/(np,1),det,nondet,property)))",
    "t_dd_fail_1 t_dd_fail_1(raised(determinism_error(/(p1,1),det,fail,property)))",
    "t_dd_fail_2 t_dd_fail_2(raised(determinism_error(/(np2,1),det,fail,property)))",
    "t_dd_fail_3 t_dd_fail_3(raised(determinism_error(/(np,1),det,fail,property)))",
    "t_ex_p2_1 t_ex_p2_1(ok)",
    "t_ex_p2_2 t_ex_p2_2(raised(determinism_error(/(sp2,1),det,fail,property)))",
    "t_ex_p2_3 t_ex_p2_3(raised(determinism_error(/(p2,1),det,fail,property)))",
    "t_ex_get_1 t_ex_get_1(1)",
    "t_ex_get_2 t_ex_get_2(0)",
    "t_ex_dk1 t_ex_dk1(raised(determinism_error(/(dk,1),det,nondet,property)))",
    "t_ex_dk2 t_ex_dk2([|](1,[|](2,[])))",
    "t_ex_dk3 t_ex_dk3(0)",
    "t_ex_dk4 t_ex_dk4(raised(determinism_error(/(dk,1),det,nondet,property)))",
    "t_ex_dk5 t_ex_dk5(1)",
    "t_ex_dl t_ex_dl(-([|](1,[|](2,[])),determinism_error(/(dl,1),det,nondet,property)))",
    "t_ex_de1 t_ex_de1(ok)",
    "t_ex_de2 t_ex_de2(raised(determinism_error(/(de,1),det,fail,property)))",
    "t_ex_de3 t_ex_de3(raised(existence_error(matching_rule,de(c))))",
    "t_ex_ds1 t_ex_ds1(ok)",
    "t_ex_ds2 t_ex_ds2(raised(determinism_error(/(ds,1),det,fail,property)))",
    "t_ex_ds3 t_ex_ds3(raised(existence_error(matching_rule,ds(c))))",
    "t_ex_dy1 t_ex_dy1(ok)",
    "t_ex_dy2 t_ex_dy2(raised(determinism_error(/(dy,1),det,nondet,property)))",
    "t_ex_dy3 t_ex_dy3(raised(determinism_error(/(dy,1),det,fail,property)))",
    "t_ex_a1 t_ex_a1(raised(existence_error(procedure,/(a1,1))))",
    "t_tt_det_table t_tt_det_table(ok)",
    "t_tt_table_det t_tt_table_det(raised(determinism_error(/(tdn,1),det,nondet,property)))",
    "t_tt_det_table_nd t_tt_det_table_nd(raised(determinism_error(/(tdm,1),det,nondet,property)))",
    "t_sc_ssu_complete_fails t_sc_ssu_complete_fails(r(true,true,true,[|](a,[|](b,[])),true,true))",
    "t_sc_ssu_answers t_sc_ssu_answers([])",
    "t_sc_ssm_answers t_sc_ssm_answers([|](a,[|](b,[])))"
]
# <<< PINNED

function _ds_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _DS_CASES]
    text =
        _DS_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _DS_CASES
        ])
    f = joinpath(mktempdir(), "det_ssu.pl")
    write(f, text)
    return f, names
end

"A fresh kernel with the file consulted: `(gd, ld, first line of the driver's output)`."
function _ds_load(path::String)
    gd = LK.PL_global_data{_DS}()
    ld = LK.PL_local_data{_DS}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * _ds_enc(ball::_DS))
end

"The definition of `name/arity` in the user module of `gd`."
function _ds_def(gd, name::String, arity::Int=1)
    proc = LK.isCurrentProcedure(sym_key(_dss(name)), arity, LK.MODULE_user(gd))
    @assert proc !== nothing
    return proc.definition
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _ds_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_dss(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_DS, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols, _ds_enc(mk_expr(_DS, _DS[_dss(pred), lk_answers(ld, (a:a)...)...]))
            )
            rc == LK.PL_S_LAST && break
        elseif rc == LK.PL_S_EXCEPTION
            push!(sols, "exception")
            break
        else
            break
        end
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return pred * join(" " .* sols)
end

"The kernel's lines for `names` after consulting `path`: `(lines, gd, ld)`."
function _ds_kernel(path::String, names::Vector{String})
    gd, ld, st = _ds_load(path)
    out = [st]
    for name in names
        push!(out, _ds_ask(gd, ld, name))
    end
    return out, gd, ld
end

"The answer part of a line (`t_id t_id(...)`): the same extractor for the kernel's lines and for the pins."
_ds_ans(line::String)::String = String(split(line, " "; limit=2)[2])

@testset "det/1 and the tabled SSU case as swipl's (dd, ex, tt, sc rows)" begin
    f, names = _ds_file()
    kl, gd, ld = _ds_kernel(f, names)
    @test length(kl) == length(_DS_PINNED) == length(_DS_CASES) + 1
    for (k, p) in zip(kl, _DS_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # the comparison can fail: one pinned line altered must not equal the kernel's lines (corruption row)
    bad = copy(_DS_PINNED)
    bad[2] *= "x"
    @test kl != bad
    # both sides non-empty, through ONE extractor: the lines that carry a determinism error
    ours_err = [l for l in kl[2:end] if occursin("determinism_error(", _ds_ans(l))]
    pins_err = [l for l in _DS_PINNED[2:end] if occursin("determinism_error(", _ds_ans(l))]
    @test length(ours_err) == length(pins_err) >= 12
    @test !isempty([l for l in kl[2:end] if !occursin("raised(", _ds_ans(l))])
    # upstream's `det_decl` verdicts, by name: det, cdet, cdet2 succeed; the others raise the property error
    ans(id) = _ds_ans(only(filter(l -> startswith(l, "t_$(id) "), kl)))
    for id in ("dd_det", "dd_cdet", "dd_cdet2")
        @test ans(id) == "t_$(id)(ok)"
    end
    for id in ("dd_nondet_1", "dd_nondet_2", "dd_nondet_3")
        @test occursin(",det,nondet,property)", ans(id))
    end
    for id in ("dd_fail_1", "dd_fail_2", "dd_fail_3")
        @test occursin(",det,fail,property)", ans(id))
    end
    # `ssu_complete_fails`: every verdict true, both answers of ssm
    @test occursin("r(true,true,true,", ans("sc_ssu_complete_fails"))
    @test endswith(ans("sc_ssu_complete_fails"), ",true,true))")
end

@testset "the det/1 pins are swipl's (live, when swipl is on PATH)" begin
    @test length(_DS_PINNED) == length(_DS_CASES) + 1
    @test _DS_PINNED[1] == "ok"
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "SSU1B LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _ds_file()
        @test _ds_swipl_lines(f, names) == _DS_PINNED
    end
end

@testset "supervisor codes: S_DET from P_DET, [S_SSU_DET, S_DET] with both (chainPredicateSupervisor, LK-only)" begin
    f, _ = _ds_file()
    gd, ld, st = _ds_load(f)
    @test st == "ok"
    plain = _ds_def(gd, "wb1")
    det = _ds_def(gd, "wb2")
    both = _ds_def(gd, "wb3")
    @test (plain.flags & LK.P_DET) == 0
    @test (det.flags & LK.P_DET) != 0 && (det.flags & LK.P_SSU_DET) == 0
    @test (both.flags & LK.P_DET) != 0 && (both.flags & LK.P_SSU_DET) != 0
    for d in (plain, det, both)
        @test LK.setDefaultSupervisor(gd, d)               # what S_VIRGIN installs on the first call
    end
    @test plain.codes[1] != LK.S_DET                       # the control: the same two clauses without det
    @test det.codes[1] == LK.S_DET
    @test det.codes[2] != LK.S_DET
    @test both.codes[1:2] == LK.code[LK.S_SSU_DET, LK.S_DET]   # pl-supervisor.c:383-392 order
    # the two supervisors differ in the one prefix word
    @test length(det.codes) == length(plain.codes) + 1
    # the det predicate's own clauses are untouched
    @test det.impl_clauses.number_of_clauses == plain.impl_clauses.number_of_clauses == 2
end

@testset "setDetDefinition!: the flag, the reset to S_VIRGIN, and the early return (pl-proc.c setDetDefinition, LK-only)" begin
    f, _ = _ds_file()
    gd, ld, st = _ds_load(f)
    @test st == "ok"
    d = _ds_def(gd, "wb2")                                 # declared det by the program
    @test LK.setDefaultSupervisor(gd, d)
    installed = d.codes
    @test installed !== d.code_data.virgin && installed[1] == LK.S_DET
    # already det: nothing changes, the installed supervisor stays
    @test LK.setDetDefinition!(gd, d, true)
    @test d.codes === installed
    # det --> nondet: the flag drops and the supervisor is reset to the shared S_VIRGIN
    @test LK.setDetDefinition!(gd, d, false)
    @test (d.flags & LK.P_DET) == 0
    @test d.codes === d.code_data.virgin
    @test d.codes[1] == LK.S_VIRGIN
    @test LK.setDefaultSupervisor(gd, d)
    @test d.codes[1] != LK.S_DET
    after_clear = d.codes
    # already not det: nothing changes
    @test LK.setDetDefinition!(gd, d, false)
    @test d.codes === after_clear
    # nondet --> det: the flag is set and the supervisor is reset, then the next install chains S_DET in
    @test LK.setDetDefinition!(gd, d, true)
    @test (d.flags & LK.P_DET) != 0
    @test d.codes === d.code_data.virgin
    @test LK.setDefaultSupervisor(gd, d)
    @test d.codes[1] == LK.S_DET
    # the same through the attribute entry point of '$set_predicate_attribute'/3
    p = _ds_def(gd, "wb1")
    @test LK.setDefaultSupervisor(gd, p)
    @test p.codes[1] != LK.S_DET
    @test LK.setAttrDefinition(ld, p, LK.P_DET, true)
    @test (p.flags & LK.P_DET) != 0
    @test p.codes === p.code_data.virgin
    @test LK.setDefaultSupervisor(gd, p)
    @test p.codes[1] == LK.S_DET
    @test LK.setAttrDefinition(ld, p, LK.P_DET, false)
    @test (p.flags & LK.P_DET) == 0
    @test p.codes === p.code_data.virgin
    # the discriminating pair (a corruption of either row above flips this one)
    @test (d.codes[1] == LK.S_DET) != (p.codes[1] == LK.S_DET)
end

"`(PL_next_solution's result, the flags of every frame)` at the first answer of `name/1` called with an unbound argument."
function _ds_first_answer_frames(gd, ld, name::String)
    proc = LK.isCurrentProcedure(sym_key(_dss(name)), 1, LK.MODULE_user(gd))
    @assert proc !== nothing
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_DS, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    flags = [ld.frames[i].flags for i in 1:(ld.nframes)]
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return rc, flags
end

# White box (pl-vmi.c:3749 `setLocal(FR, FR_DET)`): the frame of a det predicate carries FR_DET. Under `determinism_error = silent` the first answer of
# a two-clause predicate leaves its choice point, so its frame is still on the stack at the answer (under `error` the exit raises instead).
@testset "S_DET sets FR_DET in the frame of a det predicate (LK-only)" begin
    f, _ = _ds_file()
    gd, ld, st = _ds_load(f)
    @test st == "ok"
    LK.current_prolog_flag(gd, "determinism_error").a = LK.mk_sym(_DS, :silent)
    rc_plain, fl_plain = _ds_first_answer_frames(gd, ld, "fr1")
    rc_det, fl_det = _ds_first_answer_frames(gd, ld, "fr2")
    @test rc_plain == LK.PL_S_TRUE && rc_det == LK.PL_S_TRUE     # an answer with a choice point left
    @test !isempty(fl_plain) && !isempty(fl_det)                 # one extractor, both sides non-empty
    n_det(fl) = count(x -> (x & LK.FR_DET) != 0, fl)
    @test n_det(fl_plain) == 0
    @test n_det(fl_det) >= 1
    @test n_det(fl_det) != n_det(fl_plain)                       # the corruption row: the two sides differ
    @test ld.query == 0 && ld.nqueries == 0
end

@testset "skipWrapperPrefix steps over S_DET, alone and among the other prefixes (pl-wrap.c skipWrapperPrefix, LK-only)" begin
    c(x...) = LK.code[x...]
    @test LK.skipWrapperPrefix(c(LK.S_DET, LK.S_CALLWRAPPER, 1, 0, 0)) == 2
    @test LK.skipWrapperPrefix(c(LK.S_DET, LK.S_TABLED, 1, 0, 0)) == 2
    @test LK.skipWrapperPrefix(c(LK.S_DET, LK.S_VIRGIN)) == 2
    @test LK.skipWrapperPrefix(c(LK.S_SSU_DET, LK.S_DET, LK.S_CALLWRAPPER, 1, 0, 0)) == 3
    @test LK.skipWrapperPrefix(
        c(LK.S_MQUAL, 7, LK.S_SSU_DET, LK.S_DET, LK.S_CALLWRAPPER, 1, 0, 0)
    ) == 5
    @test LK.skipWrapperPrefix(c(LK.S_LMQUAL, 7, LK.S_DET, LK.S_TABLED, 1, 0, 0)) == 4
    @test LK.skipWrapperPrefix(c(LK.S_DET, LK.S_DET, LK.S_CALLWRAPPER, 1, 0, 0)) == 3
    # the pc argument: the prefix is skipped from any start
    @test LK.skipWrapperPrefix(c(LK.S_MQUAL, 7, LK.S_DET, LK.S_CALLWRAPPER, 1, 0, 0), 3) == 4
    # the control: without S_DET the first instruction after the prefix is the same one
    @test LK.skipWrapperPrefix(c(LK.S_CALLWRAPPER, 1, 0, 0)) == 1
    @test LK.skipWrapperPrefix(c(LK.S_DET, LK.S_CALLWRAPPER, 1, 0, 0)) !=
          LK.skipWrapperPrefix(c(LK.S_CALLWRAPPER, 1, 0, 0))
    # a det predicate that was tabled after its det declaration (`:- det(tdt/1). :- table tdt/1.`): the wrapper chain starts with S_DET
    f, _ = _ds_file()
    gd, ld, st = _ds_load(f)
    @test st == "ok"
    t = _ds_def(gd, "tdt")
    @test (t.flags & LK.P_DET) != 0
    @test t.codes[1] == LK.S_DET
    i = LK.skipWrapperPrefix(t.codes)
    @test i == 2
    @test LK.isCallWrapper(t.codes[i])
    # the prefix does not change what `freeCodesDefinition!` sees: a wrapped predicate is still recognised behind S_DET
    @test LK.isCallWrapper(t.codes[LK.skipWrapperPrefix(t.codes)])
end
