# ORIGINAL: LIVE kill rows of the TB4 mutants that need TB5's builtin `'$tbl_destroy_table'/1` (audit D-0646 item 2), against swipl at the pin
# (swipl-devel 18168e62, 10.1.20). The rows were written for batch 3 (test_tabling_tb4rows_swipl.jl R9, R10 and test_tabling_tb4rows2_swipl.jl g13a,
# g13b) and moved out of it: each runs ANSWER COMPLETION to its end (a positive loop with a conditional answer), and boot/tabling.pl
# `answer_completion/2` ends with `call_cleanup(..., abolish_table_subgoals(eval_subgoal_in_residual(_,_)))`, which calls `'$tbl_destroy_table'/1`
# (pl-tabling.c:4931-4938; docs/r2_owners.tsv: owner TAB1, step TB5). Where the builtin is missing the nested cleanup raises an existence_error and the
# engine breaks (`tabling(unexpected_result(user:rf,!))`, `newChoice: BFR is not older`). They run where TB5's port is present (wip/tb7m, wip/tab-int).
#   * R9, R10 (group SIMP): simplification of a conditional answer to false (the stale-delay program of tests/tabling/test_wfs_stale_delay.pl, which
#     needs several passes of simplify_component, and `sa :- tnot(sb). sb :- tnot(sa). sb.`) and to true (`k10 :- tnot(n10).` with n10 ending
#     without an answer): mutants TB4-S1, S3, S4.
#   * A2, A3 (groups G13A, G13B): a prolog_wrap counter on `'$tabling':answer_completion/2` (nb_setval/nb_getval, since flag/3's read form calls
#     get_flag/2, FL1's): ONE call for the program of G13A, ZERO for the all-negative program of G13B (rows r1301-r1304): mutants TB4-A2, TB4-A3.
#   * Cases `t_<id>(R)` run in order in ONE database per group, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is
#     test_tabling_variant_swipl.jl's (`enc`oded answers), the program text the same on both sides.
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs); with `swipl` on PATH the live answers are compared with the
#     pins too. A trie blob is never printed.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the delay list)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TR_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_TR_sym(x) = lk_sym(_TR_T, Symbol(x))

_TR_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _TR_enc(t::_TR_T, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _TR_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _TR_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _TR_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_TR_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TR_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""

function _TR_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TR_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The program text with the cases of `cases` appended."
_TR_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _TR_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_tb4_tb5.pl")
    write(f, _TR_text(program, cases))
    gd = LK.PL_global_data{_TR_T}()
    ld = LK.PL_local_data{_TR_T}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _TR_enc(ball::_TR_T))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _TR_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_TR_sym(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TR_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _TR_enc(mk_expr(_TR_T, _TR_T[_TR_sym(pred), lk_answers(ld, (a:a)...)...]))
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

const _TR_PROG_SIMP = raw"""
:- use_module(library(wfs)).
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tr_truth(G, T) :- ( call_delays(G, Delays) -> ( Delays == true -> T = true ; T = undefined ) ; T = false ).
:- table ra/0, rb/0, rc/0, rd/0, re/0, rf/0.
ra :- rf.
rb :- rc.
rc :- rd, rc.
rd :- re.
re :- tnot(ra), tnot(rb).
re :- rd.
rf :- tnot(rc).
:- table sa/0, sb/0.
sa :- tnot(sb).
sb :- tnot(sa).
sb.
:- table k10/0, n10/0.
k10 :- tnot(n10).
n10 :- k10, fail.
"""

const _TR_CASES_SIMP = [
    (
        "r09a",
        raw"rf, findall(G=T, (member(G, [ra, rb, rc, rd, re, rf]), tr_truth(G, T)), M), R = M"
    ),
    ("r09b", raw"tm_yn(sa, R)"),
    ("r09c", raw"tm_yn(sb, R)"),
    ("r09d", raw"call_delays(sb, D), R = D"),
    ("r10a", raw"call_delays(k10, D), R = D"),
    ("r10b", raw"tm_yn(call_delays(k10, true), R)"),
    ("r10c", raw"tm_yn(n10, R)")
]

const _TR_PINS_SIMP = [
    "ok",
    "t_r09a c[116,95,114,48,57,97]/1(c[91,124,93]/2(c[61]/2(a[114,97],a[116,114,117,101]),c[91,124,93]/2(c[61]/2(a[114,98],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[114,99],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[114,100],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[114,101],a[102,97,108,115,101]),c[91,124,93]/2(c[61]/2(a[114,102],a[116,114,117,101]),nil)))))))",
    "t_r09b c[116,95,114,48,57,98]/1(a[110,111])",
    "t_r09c c[116,95,114,48,57,99]/1(a[121,101,115])",
    "t_r09d c[116,95,114,48,57,100]/1(a[116,114,117,101])",
    "t_r10a c[116,95,114,49,48,97]/1(a[116,114,117,101])",
    "t_r10b c[116,95,114,49,48,98]/1(a[121,101,115])",
    "t_r10c c[116,95,114,49,48,99]/1(a[110,111])"
]

const _TR_PROG_G13A = raw"""
:- use_module(library(wfs)).
:- use_module(library(prolog_wrap)).
:- nb_setval(acc13, 0).
:- wrap_predicate('$tabling':answer_completion(_, _), cnt13, W,
       ( nb_current(inac13, true) -> W
       ; nb_getval(acc13, N0), N is N0+1, nb_setval(acc13, N), nb_setval(inac13, true), call_cleanup(W, nb_setval(inac13, false)) )).
:- table a13/0, b13/0, c13/0, d13/0, e13/0, f13/0.
a13 :- c13, a13.
a13 :- tnot(a13), f13.
b13.
c13 :- tnot(e13), tnot(a13).
d13.
e13 :- a13, tnot(d13).
f13 :- tnot(a13).
"""

const _TR_CASES_G13A = [
    ("r1301", raw"call_delays(a13, D), nb_getval(acc13, N), R = N-D"),
    ("r1302", raw"call_delays(c13, D), nb_getval(acc13, N), R = N-D")
]

const _TR_PINS_G13A = [
    "ok",
    "t_r1301 c[116,95,114,49,51,48,49]/1(c[45]/2(i1,a[97,49,51]))",
    "t_r1302 c[116,95,114,49,51,48,50]/1(c[45]/2(i1,a[99,49,51]))"
]

const _TR_PROG_G13B = raw"""
:- use_module(library(wfs)).
:- use_module(library(prolog_wrap)).
:- nb_setval(acc13, 0).
:- wrap_predicate('$tabling':answer_completion(_, _), cnt13, W,
       ( nb_current(inac13, true) -> W
       ; nb_getval(acc13, N0), N is N0+1, nb_setval(acc13, N), nb_setval(inac13, true), call_cleanup(W, nb_setval(inac13, false)) )).
:- table a13/0, b13/0, c13/0, d13/0, e13/0, f13/0.
a13 :- tnot(a13), f13.
b13.
c13 :- tnot(e13), tnot(a13).
d13.
e13 :- a13, tnot(d13).
f13 :- tnot(a13).
"""

const _TR_CASES_G13B = [
    ("r1303", raw"call_delays(a13, D), nb_getval(acc13, N), R = N-D"),
    ("r1304", raw"call_delays(c13, D), nb_getval(acc13, N), R = N-D")
]

const _TR_PINS_G13B = [
    "ok",
    "t_r1303 c[116,95,114,49,51,48,51]/1(c[45]/2(i0,a[97,49,51]))",
    "t_r1304 c[116,95,114,49,51,48,52]/1(c[45]/2(i0,a[99,49,51]))"
]


const _TR_GROUPS = [
    (
        key="SIMP",
        label="R9, R10: simplification to false and to true (S1, S3, S4)",
        program=_TR_PROG_SIMP,
        cases=_TR_CASES_SIMP,
        pins=_TR_PINS_SIMP
    ),
    (
        key="G13A",
        label="A2: answer completion called once for a program with a positive delay (g13a)",
        program=_TR_PROG_G13A,
        cases=_TR_CASES_G13A,
        pins=_TR_PINS_G13A
    ),
    (
        key="G13B",
        label="A3: answer completion not called for a program of negative delays only (g13b)",
        program=_TR_PROG_G13B,
        cases=_TR_CASES_G13B,
        pins=_TR_PINS_G13B
    )
]


@testset "TB4 rows needing '\$tbl_destroy_table' as swipl's: $(g.label)" for g in _TR_GROUPS
    gd, ld, st = _TR_load(g.program, g.cases)
    @test st == "ok"
    kl = String[st]
    for (id, _) in g.cases
        push!(kl, _TR_ask(gd, ld, "t_$id"))
    end
    @test !isempty(g.cases)                                   # both sides non-empty, through the ONE extractor `_TR_ask`
    @test length(kl) == length(g.pins) == length(g.cases) + 1
    for (k, p) in zip(kl, g.pins)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

"The atoms (`a[codes]`) of a pinned answer line, in order."
function _TR_atoms(line::AbstractString)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"a\[([0-9,]+)\]", line)
    ]
end

_TR_group(key) = only(filter(g -> g.key == key, _TR_GROUPS))
"The answer part of the pinned line of case `id` in group `key`."
function _TR_ans(key, id)
    g = _TR_group(key)
    return split(only(filter(l -> startswith(l, "t_$id "), g.pins)), " "; limit=2)[2]
end

@testset "the TB4/TB5 rows are not vacuous" begin
    for g in _TR_GROUPS
        @test g.pins[1] == "ok"
        @test length(g.pins) == length(g.cases) + 1
        @test all(!isempty, g.pins)
        for (id, goal) in g.cases
            @test !isempty(goal)
            @test count(l -> startswith(l, "t_$id "), g.pins) == 1
        end
    end
    # R9: the model of the stale-delay program, the sa/sb pair; R10: a goal that turns true
    @test _TR_atoms(_TR_ans("SIMP", "r09a")) ==
        [
        "ra",
        "true",
        "rb",
        "false",
        "rc",
        "false",
        "rd",
        "false",
        "re",
        "false",
        "rf",
        "true"
    ]
    @test _TR_atoms(_TR_ans("SIMP", "r09b")) == ["no"]
    @test _TR_atoms(_TR_ans("SIMP", "r09c")) == ["yes"]
    @test _TR_atoms(_TR_ans("SIMP", "r09d")) == ["true"]
    @test _TR_atoms(_TR_ans("SIMP", "r10a")) == ["true"]
    @test _TR_atoms(_TR_ans("SIMP", "r10b")) == ["yes"]
    @test _TR_atoms(_TR_ans("SIMP", "r10c")) == ["no"]
    @test _TR_ans("SIMP", "r09b") != _TR_ans("SIMP", "r09c")  # false then true
    # A2, A3: the number of answer completions of the two programs (the counter `acc13`), one against none
    @test _TR_atoms(_TR_ans("G13A", "r1301")) == ["a13"]
    @test _TR_atoms(_TR_ans("G13A", "r1302")) == ["c13"]
    @test occursin("i1,", _TR_ans("G13A", "r1301")) && occursin("i1,", _TR_ans("G13A", "r1302"))
    @test occursin("i0,", _TR_ans("G13B", "r1303")) && occursin("i0,", _TR_ans("G13B", "r1304"))
    @test _TR_ans("G13A", "r1301") != _TR_ans("G13A", "r1302")
    @test _TR_ans("G13B", "r1303") != _TR_ans("G13B", "r1304")
    @test _TR_ans("G13A", "r1301") != _TR_ans("G13B", "r1303")   # the count differs: 1 against 0
end

@testset "the TB4/TB5 pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB4/TB5 ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        for g in _TR_GROUPS
            @test g.pins[1] == "ok"
            @test [first(split(l, " ")) for l in g.pins[2:end]] ==
                ["t_$id" for (id, _) in g.cases]
        end
    else
        for g in _TR_GROUPS
            f = joinpath(mktempdir(), "tb4_tb5_swipl.pl")
            write(f, _TR_text(g.program, g.cases))
            @test _TR_swipl_lines(f, ["t_$id" for (id, _) in g.cases]) == g.pins
        end
    end
end
