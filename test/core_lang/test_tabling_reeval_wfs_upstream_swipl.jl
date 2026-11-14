# ORIGINAL: the UPSTREAM tests/tabling/test_reeval_wfs.pl (swipl-devel 18168e62, 10.1.20), units 1..2 of 2 (reeval_wfs, reeval_wfs_stale),
# as kernel rows (TAB1, TABTEST-R2). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <unit>:test(<name>), abolish_all_tables`, R = ok / failed / raised(E).
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests` (the file has no shared code outside its units); each unit is its
#     own module `pu_<unit>` (plunit gives each unit a module); library(wfs) is loaded explicitly (upstream gets it by autoload), no helper library.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_rw.txt, which also holds the plunit
#     run of the same units: 6 of 6 passed) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
#   * DIVERGES from the file: plunit is not used (`pu_<unit>:test(Name)` is called directly), the unit modules are `pu_<unit>` not `plunit_<unit>`.
#     The row adds abolish_all_tables before and after (the tests abolish tables themselves; nothing else).
#   * A row whose program the kernel refuses stays a row pinned on swipl (the pin is not weakened); none is known for these units.
#   * Rows with plunit options folded by hand (ROW_FOLD in gen_reeval.py, from the unit text): reeval_wfs, reeval_wfs_stale: `test(Name, Options)` is called with Options unbound and the option (`Var = Value`, `Var == Value`, `cleanup(G)` as setup_call_cleanup) read after the call.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.

using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tts(x) = lk_sym(_TT, Symbol(x))

_tt_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tt_enc(t::_TT, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tt_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tt_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tt_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tt_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TT_DRIVER = raw"""
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

"The units' text, verbatim between begin_tests and end_tests: `(short name, begin_tests directive, text)`."
const _TT_UNITS = [
    ("reeval_wfs", ":- begin_tests(reeval_wfs).", raw"""

:- dynamic d/1 as incremental.
:- dynamic blk/1 as incremental.
:- table q/1 as incremental.
:- table u/1 as incremental.

%  q(X) and u(X) are a negative loop, so both are undefined -- unless
%  blk(X) makes u(X) definitely false, which makes q(X) definitely true.

q(X) :- d(X), tnot(u(X)).
u(X) :- d(X), tnot(q(X)), \+ blk(X).

goals([q(1), q(2), q(3), u(1), u(2), u(3)]).

truth(Goal, Truth) :-
    (   call_delays(Goal, Delays)
    ->  (   Delays == true
        ->  Truth = true
        ;   Truth = undefined
        )
    ;   Truth = false
    ).

truths(Truths) :-
    goals(Goals),
    findall(G-T, (member(G, Goals), truth(G, T)), Truths).

%!  incremental_vs_fresh(+Updates, -Incremental, -Fresh)
%
%   Query the program, apply Updates, query again  and collect the truth
%   values.  Then discard all tables  and collect them again, now from a
%   clean slate.

incremental_vs_fresh(Updates, Incremental, Fresh) :-
    abolish_all_tables,
    retractall(d(_)), retractall(blk(_)),
    forall(member(X, [1,2,3]), assertz(d(X))),
    forall(q(_), true),
    forall(member(U, Updates), assertz(U)),
    forall(q(_), true),
    truths(Incremental),
    abolish_all_tables,
    forall(q(_), true),
    truths(Fresh).

test(one_table_becomes_false, Incremental == Fresh) :-
    incremental_vs_fresh([blk(1)], Incremental, Fresh).
test(two_tables_become_false, Incremental == Fresh) :-
    incremental_vs_fresh([blk(1), blk(3)], Incremental, Fresh).
test(all_tables_become_false, Incremental == Fresh) :-
    incremental_vs_fresh([blk(1), blk(2), blk(3)], Incremental, Fresh).

%  ... and the values themselves: the blocked ones are true, the others
%  stay undefined because their negative loop is intact.

test(truth_values, Truths == [ q(1)-true,      q(2)-undefined, q(3)-true,
                               u(1)-false,     u(2)-undefined, u(3)-false
                             ]) :-
    incremental_vs_fresh([blk(1), blk(3)], Truths, _).

"""),
    ("reeval_wfs_stale", ":- begin_tests(reeval_wfs_stale).", raw"""

:- dynamic base/1 as incremental.
:- table (a/0, b/0) as incremental.

a :- tnot(b).
b :- a, b.
b :- base(b).

truth(Goal, Truth) :-
    findall(Delays, call_delays(Goal, Delays), List),
    (   memberchk(true, List)
    ->  Truth = true
    ;   List == []
    ->  Truth = false
    ;   Truth = undefined
    ).

test(retract, [A0-B0 == false-true, A1-B1 == true-false]) :-
    abolish_all_tables,
    retractall(base(_)),
    assertz(base(b)),
    truth(a, A0), truth(b, B0),
    retract(base(b)),
    truth(a, A1), truth(b, B1).
test(residual, Program == []) :-
    abolish_all_tables,
    retractall(base(_)),
    assertz(base(b)),
    forall(a, true),
    retract(base(b)),
    call_delays(a, Delays),
    delays_residual_program(Delays, Program).

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("tt01a", "reeval_wfs", "(pu_reeval_wfs:test(one_table_becomes_false, O), O = (A == B), A == B)"),
    ("tt01b", "reeval_wfs", "(pu_reeval_wfs:test(two_tables_become_false, O), O = (A == B), A == B)"),
    ("tt01c", "reeval_wfs", "(pu_reeval_wfs:test(all_tables_become_false, O), O = (A == B), A == B)"),
    ("tt01d", "reeval_wfs", "(pu_reeval_wfs:test(truth_values, O), O = (A == B), A == B)"),
    ("tt02a", "reeval_wfs_stale", "(pu_reeval_wfs_stale:test(retract, O), O = [(A0 == B0), (A1 == B1)], A0 == B0, A1 == B1)"),
    ("tt02b", "reeval_wfs_stale", "(pu_reeval_wfs_stale:test(residual, O), O = (A == B), A == B)"),
]

const _TT_PINNED = [
    "ok",
    "t_tt01a c[116,95,116,116,48,49,97]/1(a[111,107])",
    "t_tt01b c[116,95,116,116,48,49,98]/1(a[111,107])",
    "t_tt01c c[116,95,116,116,48,49,99]/1(a[111,107])",
    "t_tt01d c[116,95,116,116,48,49,100]/1(a[111,107])",
    "t_tt02a c[116,95,116,116,48,50,97]/1(a[111,107])",
    "t_tt02b c[116,95,116,116,48,50,98]/1(a[111,107])",
]

"The answer plunit expects of every row: the test passes, `R = ok` (run in swipl by gen_reeval.py pin, plunit part of pins file)."
const _TT_UPSTREAM = [
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
]

"The files of the program in a fresh directory: one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "pu_$short.pl"),
            ":- module(pu_$short, []).\n:- use_module(library(debug)).\n:- use_module(library(wfs)).\n" * text * "\n" * _TT_TAIL
        )
    end
    main = join([":- use_module('$d/pu_$short').\n" for (short, _, _) in _TT_UNITS])
    main *= join([
        "t_$(id)(R) :- ( catch((abolish_all_tables, $g, abolish_all_tables, R = ok), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n"
        for (id, _, g) in _TT_CASES
    ])
    write(joinpath(d, "main.pl"), main)
    return joinpath(d, "main.pl")
end

function _tt_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(f, _TT_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") * "]), halt)).\n")
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tt_load(main::String)
    gd = LK.PL_global_data{_TT}()
    ld = LK.PL_local_data{_TT}(gd)
    st, ball = LK.load_file!(gd, ld, main)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tt_enc(ball::_TT))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tt_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tts(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TT, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a)
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _tt_enc(mk_expr(_TT, _TT[_tts(pred), lk_answers(ld, (a:a)...)...])))
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

"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_TT_UPSTREAM` holds it."
function _tt_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_tt_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "upstream test_reeval_wfs.pl units 1..2: the kernel answers every row as swipl does" begin
    gd, ld, st = _tt_load(_tt_materialize())
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TT_CASES
        push!(kl, _tt_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TT_PINNED)
    for (k, pn) in zip(kl, _TT_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _tt_corrupt(_TT_PINNED[2])
end

@testset "the pins are the upstream (plunit) expectations (no swipl needed)" begin
    @test length(_TT_PINNED) == length(_TT_CASES) + 1
    @test length(_TT_UPSTREAM) == length(_TT_CASES)
    @test !isempty(_TT_UPSTREAM) && all(!isempty, _TT_UPSTREAM)
    @test _TT_PINNED[1] == "ok"
    for (pn, up) in zip(_TT_PINNED[2:end], _TT_UPSTREAM)
        @test _tt_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _tt_answer(_tt_corrupt(_TT_PINNED[2])) != _TT_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        got = _tt_swipl_lines(_tt_materialize(), ["t_$id" for (id, _, _) in _TT_CASES])
        @test !isempty(got) && got == _TT_PINNED
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _tt_corrupt(_TT_PINNED[2])
    end
end
