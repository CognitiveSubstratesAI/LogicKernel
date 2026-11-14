# ORIGINAL: LIVE kill rows for the PER-PREDICATE size and answer-count options of tabling (TAB1 TB8-ROWS2) against swipl at the pin (swipl-devel
# 18168e62, 10.1.20), and a white-box row for `drop_intermediate_tables`. They carry the kills of the mutants TB8-R1 .. TB8-R11 and TB8-T9 of
# tools/mutants/TB8.py: the options `answer_abstract(N)`, `max_answers(N)` and `subgoal_abstract(N)` as CONSUMED (`pred_max_table_subgoal_size`,
# `pred_max_table_answer_size`, `tripwire_answers_for_subgoal`, the `-1` tests of `get_answer_table` and `tbl_add_answer_found`), which no row of
# the TB8 files exercised (the ac rows use subgoal_abstract(0) only, TAB1MIN tma18/19 only SET the attributes). One program text per group,
# each group in a FRESH database:
#   * ANSABS   a0/a1/a3 (`answer_abstract(0/1/3)`) and fa (none) under the flags max_table_answer_size(_action) (default, 1 + bounded_rationality,
#              1 + fail, 3 + fail, 3 + error, 0 + fail, 9 + error): the per-predicate limit wins, `abstract`/`bounded_rationality`/`fail` act per answer.
#   * MAXANS   m0/m2/m3/mi/m9 (`max_answers(0/2/3/infinite/9)`) and mp (none) under max_answers_for_subgoal(_action) (`call_delays/2`, library(wfs)):
#              the per-predicate limit is `>=` and ALWAYS bounded_rationality (the general answer `A-(user:m2(A))` after 1, 2 answers), `infinite` is
#              ignored (-1), the per-predicate limit wins over the flag, the flag trips for mp.
#   * SUBABS   s0/s1/s2/s9 (`subgoal_abstract(0/1/2/9)`) and sv (none) under max_table_subgoal_size(_action): `sr/2` returns trip(W) or
#              ans(Answers, Tables of that predicate); the default action `error` trips s0-s2, the action `abstract` abstracts the calls with
#              a per-predicate limit, sv (no limit) trips under flag 1 + abstract, s9 (limit 9) is not abstracted by flag 1.
# Cases `t_<id>(R)` run in order in ONE database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is
# test_tabling_tb6rows_swipl.jl's (`enc`oded answers), the program text the same on both sides. Every answer line is swipl's, PINNED (swipl
# 10.1.20, two byte-identical runs, evidence/TAB1/tb8rows_gen/: spec.py the programs and cases, run.py the generator); with `swipl` on PATH the live
# answers are compared with the pins too. ROWS THE KERNEL CANNOT ANSWER YET are `@test_broken <the same comparison>`, never skipped, never weakened
# (`_T8_BROKEN`, an owner each): a row that passes unexpectedly is an Unexpected Pass error, the owner then deletes its entry.
# The T9 white-box testset: no Prolog route builds `recompute == factor * own` (the kernel's inference counter is not swipl's), so its three
# scenarios are hand-written from pl-tabling.c:6374-6422 at the pin, with the C reference at the row.
# UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the verifier runs each row against its mutant.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - these built-ins ride the term layer through the FLI (unify, get, the table pool)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _T8_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_T8_sym(x) = lk_sym(_T8_T, Symbol(x))

_T8_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _T8_enc(t::_T8_T, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _T8_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _T8_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _T8_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_T8_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _T8_DRIVER = raw"""
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

function _T8_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _T8_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
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
_T8_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _T8_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_tb8rows.pl")
    write(f, _T8_text(program, cases))
    gd = LK.PL_global_data{_T8_T}()
    ld = LK.PL_local_data{_T8_T}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _T8_enc(ball::_T8_T))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _T8_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_T8_sym(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_T8_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _T8_enc(mk_expr(_T8_T, _T8_T[_T8_sym(pred), lk_answers(ld, (a:a)...)...]))
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

"`_T8_ask`, a Julia exception (a NotPortedError of a built-in) answering as the line `<pred> THROWN <type>`."
function _T8_ask_safe(gd, ld, pred::String)::String
    try
        return _T8_ask(gd, ld, pred)
    catch e
        return "$pred THROWN $(typeof(e))"
    end
end
const _T8_PROG_ANSABS = raw"""
:- table a0/1 as answer_abstract(0).
:- table a1/1 as answer_abstract(1).
:- table a3/1 as answer_abstract(3).
:- table fa/1.
a0(f(f(f(a)))).
a0(g(a)).
a0(h).
a1(f(f(f(a)))).
a1(g(a)).
a1(h).
a3(f(f(f(a)))).
a3(g(a)).
a3(h).
fa(f(f(f(a)))).
fa(g(a)).
fa(h).
ans(G, R) :-
    catch(findall(G, G, L), error(resource_error(tripwire(W, _)), _), L = tripped(W)),
    R = L.
all(R) :- ans(fa(_), F), ans(a0(_), A0), ans(a1(_), A1), ans(a3(_), A3), R = r(F, A0, A1, A3).
wa(Size, Act, Goal) :-
    abolish_all_tables,
    setup_call_cleanup(( set_prolog_flag(max_table_answer_size, Size), set_prolog_flag(max_table_answer_size_action, Act) ),
        Goal,
        ( set_prolog_flag(max_table_answer_size, infinite), set_prolog_flag(max_table_answer_size_action, error), abolish_all_tables )).
"""

const _T8_CASES_ANSABS = [
    ("a01", raw"abolish_all_tables, all(R)"),
    ("a02", raw"wa(1, bounded_rationality, all(R))"),
    ("a03", raw"wa(1, fail, all(R))"),
    ("a04", raw"wa(3, fail, all(R))"),
    ("a05", raw"wa(3, error, all(R))"),
    ("a06", raw"wa(0, fail, all(R))"),
    ("a07", raw"wa(9, error, all(R))")
]

const _T8_PINS_ANSABS = [
    "ok",
    "t_a01 c[116,95,97,48,49]/1(c[114]/4(c[91,124,93]/2(c[102,97]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[102,97]/1(c[103]/1(a[97])),c[91,124,93]/2(c[102,97]/1(a[104]),nil))),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,116,97,98,108,101,95,97,110,115,119,101,114,95,115,105,122,101]),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,116,97,98,108,101,95,97,110,115,119,101,114,95,115,105,122,101]),c[91,124,93]/2(c[97,51]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[97,51]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,51]/1(a[104]),nil)))))",
    "t_a02 c[116,95,97,48,50]/1(c[114]/4(c[91,124,93]/2(c[102,97]/1(c[102]/1(c[102]/1(V0))),c[91,124,93]/2(c[102,97]/1(c[103]/1(a[97])),c[91,124,93]/2(c[102,97]/1(a[104]),nil))),c[91,124,93]/2(c[97,48]/1(c[102]/1(V1)),c[91,124,93]/2(c[97,48]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,48]/1(a[104]),nil))),c[91,124,93]/2(c[97,49]/1(c[102]/1(c[102]/1(V2))),c[91,124,93]/2(c[97,49]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,49]/1(a[104]),nil))),c[91,124,93]/2(c[97,51]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[97,51]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,51]/1(a[104]),nil)))))",
    "t_a03 c[116,95,97,48,51]/1(c[114]/4(c[91,124,93]/2(c[102,97]/1(c[103]/1(a[97])),c[91,124,93]/2(c[102,97]/1(a[104]),nil)),c[91,124,93]/2(c[97,48]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,48]/1(a[104]),nil)),c[91,124,93]/2(c[97,49]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,49]/1(a[104]),nil)),c[91,124,93]/2(c[97,51]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[97,51]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,51]/1(a[104]),nil)))))",
    "t_a04 c[116,95,97,48,52]/1(c[114]/4(c[91,124,93]/2(c[102,97]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[102,97]/1(c[103]/1(a[97])),c[91,124,93]/2(c[102,97]/1(a[104]),nil))),c[91,124,93]/2(c[97,48]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,48]/1(a[104]),nil)),c[91,124,93]/2(c[97,49]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,49]/1(a[104]),nil)),c[91,124,93]/2(c[97,51]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[97,51]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,51]/1(a[104]),nil)))))",
    "t_a05 c[116,95,97,48,53]/1(c[114]/4(c[91,124,93]/2(c[102,97]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[102,97]/1(c[103]/1(a[97])),c[91,124,93]/2(c[102,97]/1(a[104]),nil))),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,116,97,98,108,101,95,97,110,115,119,101,114,95,115,105,122,101]),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,116,97,98,108,101,95,97,110,115,119,101,114,95,115,105,122,101]),c[91,124,93]/2(c[97,51]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[97,51]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,51]/1(a[104]),nil)))))",
    "t_a06 c[116,95,97,48,54]/1(c[114]/4(c[91,124,93]/2(c[102,97]/1(c[103]/1(a[97])),c[91,124,93]/2(c[102,97]/1(a[104]),nil)),c[91,124,93]/2(c[97,48]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,48]/1(a[104]),nil)),c[91,124,93]/2(c[97,49]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,49]/1(a[104]),nil)),c[91,124,93]/2(c[97,51]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[97,51]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,51]/1(a[104]),nil)))))",
    "t_a07 c[116,95,97,48,55]/1(c[114]/4(c[91,124,93]/2(c[102,97]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[102,97]/1(c[103]/1(a[97])),c[91,124,93]/2(c[102,97]/1(a[104]),nil))),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,116,97,98,108,101,95,97,110,115,119,101,114,95,115,105,122,101]),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,116,97,98,108,101,95,97,110,115,119,101,114,95,115,105,122,101]),c[91,124,93]/2(c[97,51]/1(c[102]/1(c[102]/1(c[102]/1(a[97])))),c[91,124,93]/2(c[97,51]/1(c[103]/1(a[97])),c[91,124,93]/2(c[97,51]/1(a[104]),nil)))))"
]

const _T8_PROG_MAXANS = raw"""
:- use_module(library(wfs)).
:- table m0/1 as max_answers(0).
:- table m2/1 as max_answers(2).
:- table m3/1 as max_answers(3).
:- table mi/1 as max_answers(infinite).
:- table m9/1 as max_answers(9).
:- table mp/1.
m0(X) :- between(1, 5, X).
m2(X) :- between(1, 5, X).
m3(X) :- between(1, 5, X).
mi(X) :- between(1, 5, X).
m9(X) :- between(1, 5, X).
mp(X) :- between(1, 5, X).
cd(P, R) :-
    catch(findall(X-D, call_delays(call(P, X), D), R0), error(resource_error(tripwire(W, _)), _), R0 = tripped(W)),
    R = R0.
allm(R) :- cd(m0, A), cd(m2, B), cd(m3, C), cd(mi, D), cd(m9, E), cd(mp, F), R = r(A, B, C, D, E, F).
wm(Limit, Act, Goal) :-
    abolish_all_tables,
    setup_call_cleanup(( set_prolog_flag(max_answers_for_subgoal, Limit), set_prolog_flag(max_answers_for_subgoal_action, Act) ),
        Goal,
        ( set_prolog_flag(max_answers_for_subgoal, infinite), set_prolog_flag(max_answers_for_subgoal_action, error), abolish_all_tables )).
"""

const _T8_CASES_MAXANS = [
    ("m01", raw"abolish_all_tables, allm(R)"),
    ("m02", raw"wm(3, error, allm(R))"),
    ("m03", raw"wm(3, bounded_rationality, allm(R))"),
    ("m04", raw"wm(1, error, allm(R))"),
    ("m05", raw"wm(9, error, allm(R))")
]

const _T8_PINS_MAXANS = [
    "ok",
    "t_m01 c[116,95,109,48,49]/1(c[114]/6(c[91,124,93]/2(c[45]/2(V0,c[58]/2(a[117,115,101,114],c[109,48]/1(V0))),nil),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V1,c[58]/2(a[117,115,101,114],c[109,50]/1(V1))),nil))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V2,c[58]/2(a[117,115,101,114],c[109,51]/1(V2))),nil)))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i4,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i5,a[116,114,117,101]),nil))))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i4,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i5,a[116,114,117,101]),nil))))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i4,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i5,a[116,114,117,101]),nil)))))))",
    "t_m02 c[116,95,109,48,50]/1(c[114]/6(c[91,124,93]/2(c[45]/2(V0,c[58]/2(a[117,115,101,114],c[109,48]/1(V0))),nil),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V1,c[58]/2(a[117,115,101,114],c[109,50]/1(V1))),nil))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V2,c[58]/2(a[117,115,101,114],c[109,51]/1(V2))),nil)))),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,97,110,115,119,101,114,115,95,102,111,114,95,115,117,98,103,111,97,108]),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i4,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i5,a[116,114,117,101]),nil))))),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,97,110,115,119,101,114,115,95,102,111,114,95,115,117,98,103,111,97,108])))",
    "t_m03 c[116,95,109,48,51]/1(c[114]/6(c[91,124,93]/2(c[45]/2(V0,c[58]/2(a[117,115,101,114],c[109,48]/1(V0))),nil),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V1,c[58]/2(a[117,115,101,114],c[109,50]/1(V1))),nil))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V2,c[58]/2(a[117,115,101,114],c[109,51]/1(V2))),nil)))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V3,c[58]/2(a[117,115,101,114],c[109,105]/1(V3))),nil)))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i4,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i5,a[116,114,117,101]),nil))))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V4,c[58]/2(a[117,115,101,114],c[109,112]/1(V4))),nil))))))",
    "t_m04 c[116,95,109,48,52]/1(c[114]/6(c[91,124,93]/2(c[45]/2(V0,c[58]/2(a[117,115,101,114],c[109,48]/1(V0))),nil),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V1,c[58]/2(a[117,115,101,114],c[109,50]/1(V1))),nil))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V2,c[58]/2(a[117,115,101,114],c[109,51]/1(V2))),nil)))),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,97,110,115,119,101,114,115,95,102,111,114,95,115,117,98,103,111,97,108]),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i4,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i5,a[116,114,117,101]),nil))))),c[116,114,105,112,112,101,100]/1(a[109,97,120,95,97,110,115,119,101,114,115,95,102,111,114,95,115,117,98,103,111,97,108])))",
    "t_m05 c[116,95,109,48,53]/1(c[114]/6(c[91,124,93]/2(c[45]/2(V0,c[58]/2(a[117,115,101,114],c[109,48]/1(V0))),nil),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V1,c[58]/2(a[117,115,101,114],c[109,50]/1(V1))),nil))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V2,c[58]/2(a[117,115,101,114],c[109,51]/1(V2))),nil)))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i4,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i5,a[116,114,117,101]),nil))))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i4,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i5,a[116,114,117,101]),nil))))),c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i4,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i5,a[116,114,117,101]),nil)))))))"
]

const _T8_PROG_SUBABS = raw"""
:- table s0/2 as subgoal_abstract(0).
:- table s1/2 as subgoal_abstract(1).
:- table s2/2 as subgoal_abstract(2).
:- table s9/2 as subgoal_abstract(9).
:- table sv/2.
s0(X, X).
s1(X, X).
s2(X, X).
s9(X, X).
sv(X, X).
sr(P, Res) :-
    G =.. [P, f(f(f(1))), Y],
    functor(T, P, 2),
    catch(( findall(Y, G, As), findall(T, current_table(user:T, _), Ts), Res = ans(As, Ts) ),
          error(resource_error(tripwire(W, _)), _), Res = trip(W)).
alls(R) :- sr(s0, A), sr(s1, B), sr(s2, C), sr(s9, D), sr(sv, E), R = r(A, B, C, D, E).
ws(Size, Act, Goal) :-
    abolish_all_tables,
    setup_call_cleanup(( set_prolog_flag(max_table_subgoal_size, Size), set_prolog_flag(max_table_subgoal_size_action, Act) ),
        Goal,
        ( set_prolog_flag(max_table_subgoal_size, infinite), set_prolog_flag(max_table_subgoal_size_action, error), abolish_all_tables )).
"""

const _T8_CASES_SUBABS = [
    ("u01", raw"abolish_all_tables, alls(R)"),
    ("u02", raw"ws(infinite, abstract, alls(R))"),
    ("u03", raw"ws(1, abstract, alls(R))"),
    ("u04", raw"ws(1, warning, alls(R))"),
    ("u05", raw"ws(1, error, alls(R))"),
    ("u06", raw"ws(9, abstract, alls(R))")
]

const _T8_PINS_SUBABS = [
    "ok",
    "t_u01 c[116,95,117,48,49]/1(c[114]/5(c[116,114,105,112]/1(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101]),c[116,114,105,112]/1(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101]),c[116,114,105,112]/1(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101]),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil)))",
    "t_u02 c[116,95,117,48,50]/1(c[114]/5(c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),c[91,124,93]/2(c[115,48]/2(V0,V1),nil)),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil)))",
    "t_u03 c[116,95,117,48,51]/1(c[114]/5(c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),c[91,124,93]/2(c[115,48]/2(V0,V1),nil)),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[116,114,105,112]/1(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101])))",
    "t_u04 c[116,95,117,48,52]/1(c[114]/5(c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil)))",
    "t_u05 c[116,95,117,48,53]/1(c[114]/5(c[116,114,105,112]/1(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101]),c[116,114,105,112]/1(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101]),c[116,114,105,112]/1(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101]),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[116,114,105,112]/1(a[109,97,120,95,116,97,98,108,101,95,115,117,98,103,111,97,108,95,115,105,122,101])))",
    "t_u06 c[116,95,117,48,54]/1(c[114]/5(c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),c[91,124,93]/2(c[115,48]/2(V0,V1),nil)),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil),c[97,110,115]/2(c[91,124,93]/2(c[102]/1(c[102]/1(c[102]/1(i1))),nil),nil)))"
]

const _T8_GROUPS = [
    (
        key="ANSABS",
        label=raw"ANSABS: `answer_abstract(N)` of a table vs the flag max_table_answer_size(_action) (kills TB8-R3 a01, TB8-R4 a02, TB8-R10 a01 a06)",
        program=_T8_PROG_ANSABS,
        cases=_T8_CASES_ANSABS,
        pins=_T8_PINS_ANSABS
    ),
    (
        key="MAXANS",
        label=raw"MAXANS: `max_answers(N)` of a table vs the flag max_answers_for_subgoal(_action) (kills TB8-R5 R6 m01, TB8-R7 R8 m02, TB8-R9 m01)",
        program=_T8_PROG_MAXANS,
        cases=_T8_CASES_MAXANS,
        pins=_T8_PINS_MAXANS
    ),
    (
        key="SUBABS",
        label=raw"SUBABS: `subgoal_abstract(N)` of a table vs the flag max_table_subgoal_size(_action) (kills TB8-R1 u01, TB8-R2 u03 u05, TB8-R11 u01 u02)",
        program=_T8_PROG_SUBABS,
        cases=_T8_CASES_SUBABS,
        pins=_T8_PINS_SUBABS
    )
]

# Rows whose kernel side cannot answer yet: `GROUP/case => owner`. Each is `@test_broken` below, the same comparison as its neighbours. EMPTY: no row
# is known to be unanswerable (nothing was compiled when these rows were written); add `GROUP/id => owner` if the first kernel run shows one.
const _T8_BROKEN = Dict{String, String}()

@testset "TB8 rows as swipl's: $(g.label)" for g in _T8_GROUPS
    gd, ld, st = _T8_load(g.program, g.cases)
    @test st == "ok"
    @test !isempty(g.cases)                                   # both sides non-empty, through the ONE extractor `_T8_ask`
    kl = String[st]
    for (id, _) in g.cases
        push!(kl, _T8_ask_safe(gd, ld, "t_$id"))
    end
    @test length(kl) == length(g.pins) == length(g.cases) + 1
    for ((id, _), k, p) in zip(g.cases, kl[2:end], g.pins[2:end])
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        if haskey(_T8_BROKEN, "$(g.key)/$id")
            @test_broken k == p                               # $(_T8_BROKEN[...]) above; an unexpected pass is an error
        else
            @test k == p
        end
    end
end

# THE T9 WHITE-BOX TESTSET (kills TB8-T9: `recompute >= factor * own` for `recompute > factor * own` in `drop_intermediate_tables`).
# swipl CANNOT answer it: the kernel's inference counter is not swipl's, and no Prolog route builds `recompute == factor * own`. Hand-written from
# pl-tabling.c:6374-6422 at the pin (`drop_intermediate_tables`): for each completed component `c`, children first,
#   below     = the sum of the `inferences` of its completed children        own = c.inferences - below (0 if negative)
#   recompute = the sum of the `drop.recompute` of its completed children + own
#   keep      = the table is gone || drop.size < TABLE_DROP_MIN_SIZE || gen_call grew || recompute > factor * own      (STRICTLY greater)
#   c->drop.recompute = keep ? 0 : recompute
# A dropped table is observed by `drop_recompute` (nonzero) because `ld.tabling.variant_table` is 0 here: nothing is `trie_delete`d.
# The scenarios (factor 2, c2 the child of c, c the child of the root; c2 own 10, recompute 10 = 1 * own, dropped, in every scenario):
#   EQUALITY c.inferences 20: own 10, recompute 10 + 10 = 20 = 2 * 10: NOT greater, so c is DROPPED (c.drop_recompute 20); `>=` keeps it (0)
#   KEEP     c.inferences 15: own 5, recompute 10 + 5 = 15 > 10: kept (0)
#   DROP     c.inferences 25: own 15, recompute 10 + 15 = 25 < 30: dropped (25)
#   SMALL    the equality numbers with `drop_size` below TABLE_DROP_MIN_SIZE: kept (0): the control that the other conditions are live
const _T8_CT = LK.tbl_component{_T8_T}
const _T8_CS = LK.component_set{_T8_CT}
"""
    _T8_drop(factor, c2_inferences, c_inferences; size=LK.TABLE_DROP_MIN_SIZE) -> NamedTuple

Run `LK.drop_intermediate_tables` on root -> c -> c2 (all completed, each with its own empty answer trie registered by `droppable_table`, its
`drop_size` set to `size`) and return what it left: `drop_recompute` and `drop_symbol` of c2 and c, and whether both were armed before.
"""
function _T8_drop(
    factor::Int, c2_inferences::Int, c_inferences::Int; size::Int=LK.TABLE_DROP_MIN_SIZE
)
    gd = LK.PL_global_data{_T8_T}()
    ld = LK.PL_local_data{_T8_T}(gd)
    ld.GD = gd                                       # `_query_gd(ld)`: the database of the running query
    root, c, c2 = _T8_CT(), _T8_CT(), _T8_CT()
    c.status = LK.SCC_COMPLETED
    c2.status = LK.SCC_COMPLETED
    root.children = _T8_CS([c])
    c.children = _T8_CS([c2])
    c2.inferences = Int64(c2_inferences)
    c.inferences = Int64(c_inferences)
    for x in (c, c2)
        LK.droppable_table(ld, x, LK.trie_create(_T8_T))
        x.drop_size = size                           # an empty trie is smaller than TABLE_DROP_MIN_SIZE: it would be kept
    end
    armed = c.drop_symbol !== nothing && c2.drop_symbol !== nothing
    ld.table_flags_drop_intermediate = factor
    LK.drop_intermediate_tables(ld, root)
    return (
        armed=armed,
        c2=c2.drop_recompute,
        c=c.drop_recompute,
        c2_symbol=c2.drop_symbol,
        c_symbol=c.drop_symbol
    )
end

@testset "TB8 T9 white-box: a table is kept only when recompute is STRICTLY greater than factor * own (kills TB8-T9)" begin
    eq = _T8_drop(2, 10, 20)
    @test eq.armed
    @test eq.c2 == 10                                # own 10, recompute 10 <= 2 * 10: dropped
    @test eq.c == 20                                 # EQUALITY: recompute 20 == 2 * 10: dropped (T9's `>=` keeps it: 0)
    @test eq.c_symbol === nothing && eq.c2_symbol === nothing      # the symbol is cleared either way
    keep = _T8_drop(2, 10, 15)
    @test keep.armed
    @test keep.c2 == 10
    @test keep.c == 0                                # KEEP: recompute 15 > 2 * 5
    @test keep.c_symbol === nothing && keep.c2_symbol === nothing
    drop = _T8_drop(2, 10, 25)
    @test drop.armed
    @test drop.c2 == 10
    @test drop.c == 25                               # DROP: recompute 25 < 2 * 15
    @test drop.c_symbol === nothing && drop.c2_symbol === nothing
    small = _T8_drop(2, 10, 20; size=LK.TABLE_DROP_MIN_SIZE - 1)
    @test small.armed
    @test small.c2 == 0 && small.c == 0              # SMALL: drop.size < TABLE_DROP_MIN_SIZE keeps both
    # not vacuous: the equality is told from the keep result (T9's mutant makes the first the second) and from the drop result
    @test eq.c != keep.c
    @test eq.c != small.c
    @test eq.c != 0 && drop.c != 0 && keep.c == 0
end

"The atoms (`a[codes]`) of a pinned answer line, in order."
function _T8_atoms(line::AbstractString)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"a\[([0-9,]+)\]", line)
    ]
end
"The functor names (`c[codes]/n(`) of a pinned answer line, in order."
function _T8_names(line::AbstractString)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"c\[([0-9,]+)\]/", line)
    ]
end
"The number of variables (`V<i>`) of a pinned answer line."
_T8_nvars(line::AbstractString) = length(collect(eachmatch(r"V[0-9]+", line)))

_T8_group(key) = only(filter(g -> g.key == key, _T8_GROUPS))
"The answer part of the pinned line of case `id` in group `key`."
function _T8_ans(key, id)
    g = _T8_group(key)
    return split(only(filter(l -> startswith(l, "t_$id "), g.pins)), " "; limit=2)[2]
end
"The answer of `key`/`id` as the line's part after the case name (the case name differs between rows)."
_T8_body(key, id) = split(_T8_ans(key, id), "("; limit=2)[2]

@testset "the TB8 rows are not vacuous" begin
    for g in _T8_GROUPS
        @test g.pins[1] == "ok"
        @test length(g.pins) == length(g.cases) + 1
        @test all(!isempty, g.pins)
        for (id, goal) in g.cases
            @test !isempty(goal)
            @test count(l -> startswith(l, "t_$id "), g.pins) == 1
        end
    end
    for k in keys(_T8_BROKEN)                                  # a broken row names a case that exists
        key, id = split(k, "/")
        @test any(==(id), first.(_T8_group(key).cases))
    end
    # ANSABS: the number of answers of each predicate (a0, a1: the f(f(f(a))) answer is dropped under `fail`, abstracted to f(V) / f(f(V)) under
    # bounded_rationality, `tripped` under the default `error`; a3 is never touched; fa is touched by the FLAG only)
    cnt(id, p) = count(==(p), _T8_names(_T8_ans("ANSABS", id)))
    tripped(id) = count(==("max_table_answer_size"), _T8_atoms(_T8_ans("ANSABS", id)))
    for id in ("a01", "a02", "a03", "a04", "a05", "a06", "a07")
        @test cnt(id, "a3") == 3
    end
    @test [tripped(id) for id in ("a01", "a02", "a03", "a04", "a05", "a06", "a07")] ==
        [2, 0, 0, 0, 2, 0, 2]
    @test [cnt(id, "a0") for id in ("a01", "a02", "a03", "a04", "a05", "a06", "a07")] ==
        [0, 3, 2, 2, 0, 2, 0]
    @test [cnt(id, "a1") for id in ("a01", "a02", "a03", "a04", "a05", "a06", "a07")] ==
        [0, 3, 2, 2, 0, 2, 0]
    @test [cnt(id, "fa") for id in ("a01", "a02", "a03", "a04", "a05", "a06", "a07")] ==
        [3, 3, 2, 3, 3, 2, 3]
    @test [
        _T8_nvars(_T8_ans("ANSABS", id)) for
        id in ("a01", "a02", "a03", "a04", "a05", "a06", "a07")
    ] ==
        [0, 3, 0, 0, 0, 0, 0]                                    # the general answers a0(f(V)), a1(f(f(V))), fa(f(f(V)))
    @test _T8_body("ANSABS", "a01") == _T8_body("ANSABS", "a05") ==
        _T8_body("ANSABS", "a07")
    @test _T8_body("ANSABS", "a03") == _T8_body("ANSABS", "a06")
    @test _T8_body("ANSABS", "a01") != _T8_body("ANSABS", "a02")
    @test _T8_body("ANSABS", "a02") != _T8_body("ANSABS", "a03")
    @test _T8_body("ANSABS", "a03") != _T8_body("ANSABS", "a04")   # fa: flag 3 keeps f(f(f(a))), flag 0 drops it
    @test _T8_body("ANSABS", "a04") != _T8_body("ANSABS", "a01")
    # MAXANS: m0 and m2 and m3 give the general answer after 0, 2, 3 answers (`user` is the module of the residual `user:m<N>(A)`), mi and m9 give all 5;
    # the flag 3 trips mi and mp under `error` (m02), makes mi and mp general under bounded_rationality (m03)
    users(id) = count(==("user"), _T8_atoms(_T8_ans("MAXANS", id)))
    trips(id) = count(==("max_answers_for_subgoal"), _T8_atoms(_T8_ans("MAXANS", id)))
    @test [users(id) for id in ("m01", "m02", "m03", "m04", "m05")] == [3, 3, 5, 3, 3]
    @test [trips(id) for id in ("m01", "m02", "m03", "m04", "m05")] == [0, 2, 0, 2, 0]
    @test [
        _T8_nvars(_T8_ans("MAXANS", id)) for id in ("m01", "m02", "m03", "m04", "m05")
    ] ==
        [6, 6, 10, 6, 6]
    @test _T8_body("MAXANS", "m01") == _T8_body("MAXANS", "m05")  # a flag of 9 is never reached by 5 answers
    @test _T8_body("MAXANS", "m02") == _T8_body("MAXANS", "m04")
    @test _T8_body("MAXANS", "m01") != _T8_body("MAXANS", "m02")
    @test _T8_body("MAXANS", "m02") != _T8_body("MAXANS", "m03")
    @test _T8_body("MAXANS", "m01") != _T8_body("MAXANS", "m03")
    # SUBABS: the calls of the default run trip under `error` (s0 s1 s2), the action `abstract` abstracts s0 (a table s0(A,B) is left), the flag 1 trips
    # sv (no per-predicate limit) and spares s9 (limit 9), warning trips nothing, the flag 9 trips nothing
    trip(id) = count(==("max_table_subgoal_size"), _T8_atoms(_T8_ans("SUBABS", id)))
    tabs(id) = count(==("s0"), _T8_names(_T8_ans("SUBABS", id)))
    @test [trip(id) for id in ("u01", "u02", "u03", "u04", "u05", "u06")] ==
        [3, 0, 1, 0, 4, 0]
    @test [tabs(id) for id in ("u01", "u02", "u03", "u04", "u05", "u06")] ==
        [0, 1, 1, 0, 0, 1]
    @test _T8_body("SUBABS", "u02") == _T8_body("SUBABS", "u06")
    @test _T8_body("SUBABS", "u01") != _T8_body("SUBABS", "u05")
    @test _T8_body("SUBABS", "u01") != _T8_body("SUBABS", "u02")
    @test _T8_body("SUBABS", "u02") != _T8_body("SUBABS", "u03")
    @test _T8_body("SUBABS", "u03") != _T8_body("SUBABS", "u04")
end

@testset "the TB8 pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB8 ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        for g in _T8_GROUPS
            @test g.pins[1] == "ok"
            @test [first(split(l, " ")) for l in g.pins[2:end]] ==
                ["t_$id" for (id, _) in g.cases]
        end
    else
        for g in _T8_GROUPS
            f = joinpath(mktempdir(), "tb8rows_swipl.pl")
            write(f, _T8_text(g.program, g.cases))
            @test _T8_swipl_lines(f, ["t_$id" for (id, _) in g.cases]) == g.pins
        end
    end
end
