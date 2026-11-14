# ORIGINAL: the UPSTREAM tests/tabling/test_incr_dyn_nodes.pl (swipl-devel 18168e62, 10.1.20), unit incr_dyn_nodes (4 tests), as
# kernel rows (TAB1, TABTEST-ID). One row `t_id<NN>(R)` per upstream test: `abolish_all_tables, <goal>, abolish_all_tables`, R = ok / failed /
# raised(E). Reclaiming the IDG nodes of incremental dynamic predicates: abolishing tables per subgoal or per module must reclaim the dynamic
# pseudo tables of calls whose last dependent table is gone (counted with the private '$tbl_local_variant_table'/1 and '$tbl_table_status'/2).
#   * No comment was elided: the file has no line matching the D-0164 term list.
#   * Layout as plunit's: the module of the file, `test_incr_dyn_nodes` (the file's text between its run_tests clause and begin_tests: `dynamic p/1, r/1, key/1, val/1 as incremental`, `table q/1, s/1, kv/1 as incremental`, their clauses, dyn_nodes/1, fill/0, reeval_kv/1),
#     and the unit as its own module `plunit_incr_dyn_nodes` with `:- set_module(base(test_incr_dyn_nodes))` (plunit's default import module of a unit; the
#     test text between `begin_tests` and `end_tests` verbatim). The unit loads with `catch(use_module(..), _, true)`, so a unit the kernel
#     refuses leaves only ITS rows undefined (the pin loads it, status ok).
#   * DIVERGES from the file: plunit is not used (a row calls the unit's test/2 clause directly). The options are folded by hand: the options `N == 10`, `N == 0` and `true(N < 2000)` are called after the body (the variables are shared with the clause: the row binds the
#     option to `C` and calls it); the option `[cleanup(Cl)]` of still_incremental: the row calls the clause with an unbound option list O and runs the Cl of O as the cleanup
#     of its setup_call_cleanup (the retractall pair). reeval runs 5000 evaluations, each an assert + a tabled call: slow on a kernel that does not
#     reclaim nodes cheaply.
#   * Expected refusals on the kernel (by reading, unverified): `:- dynamic .. as incremental` with `:- table .. as incremental` (expected to load), the private predicates
#     '$tbl_local_variant_table'/1 and '$tbl_table_status'/2 (dyn_nodes/1: tests subgoals, module and reeval; the kernel may leave them undefined), trie_gen/3 on the
#     variant table, abolish_table_subgoals/1 and abolish_module_tables/1 reclaiming the dynamic nodes (tests subgoals, module), and the permission
#     refusals of the tests still_incremental. Should the kernel leave the private predicates undefined, rows 1, 2 and 4 raise or fail. Every row stays pinned on swipl.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_id.txt, which also holds the plunit
#     run: 4 of 4 tests passed, none failed or hung on the pin) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
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
    ("incr_dyn_nodes", "begin_tests(incr_dyn_nodes)", raw"""
test(subgoals, N == 10) :-
    fill,
    abolish_table_subgoals(q(_)),       % r(I) are still used by s/1
    dyn_nodes(N).
test(module, N == 0) :-
    fill,
    abolish_module_tables(test_incr_dyn_nodes),
    dyn_nodes(N).
test(still_incremental,
     [ cleanup(( retractall(test_incr_dyn_nodes:p(_)),
                 retractall(test_incr_dyn_nodes:r(_)) ))
     ]) :-
    fill,
    abolish_table_subgoals(q(_)),
    assertz(test_incr_dyn_nodes:r(5)),  % invalidates s(5) through a kept node
    s(5),
    assertz(test_incr_dyn_nodes:p(5)),
    q(5),
    abolish_module_tables(test_incr_dyn_nodes),
    retract(test_incr_dyn_nodes:r(5)),
    \+ q(5),
    \+ s(5).
test(reeval, true(N < 2000)) :-
    reeval_kv(5000),
    dyn_nodes(N).
"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
:- dynamic p/1 as incremental.
:- dynamic r/1 as incremental.
:- table q/1 as incremental.
:- table s/1 as incremental.

q(X) :- p(X), r(X).
s(X) :- r(X).

:- dynamic key/1 as incremental.
:- dynamic val/1 as incremental.
:- table kv/1 as incremental.

kv(K) :- key(K), val(K).                % each reevaluation calls a new val(K)

%   The number of dynamic pseudo tables in this thread's variant table.

dyn_nodes(N) :-
    '$tbl_local_variant_table'(VTrie),
    aggregate_all(count,
                  ( trie_gen(VTrie, _, T),
                    '$tbl_table_status'(T, dynamic)
                  ),
                  N).

fill :-
    abolish_all_tables,
    forall(between(1, 10, I), ( ignore(q(I)), ignore(s(I)) )).

reeval_kv(Count) :-
    abolish_all_tables,
    forall(between(1, Count, I),
           ( retractall(key(_)),
             assertz(key(I)),
             ignore(kv(_))
           )),
    retractall(key(_)).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("id01", "incr_dyn_nodes", "setup_call_cleanup(true, (plunit_incr_dyn_nodes:test(subgoals, C), call(C)), true)"),
    ("id02", "incr_dyn_nodes", "setup_call_cleanup(true, (plunit_incr_dyn_nodes:test(module, C), call(C)), true)"),
    ("id03", "incr_dyn_nodes", "setup_call_cleanup(true, plunit_incr_dyn_nodes:test(still_incremental, O), (memberchk(cleanup(Cl), O), call(Cl)))"),
    ("id04", "incr_dyn_nodes", "setup_call_cleanup(true, (plunit_incr_dyn_nodes:test(reeval, true(C)), call(C)), true)"),
]

const _TT_PINNED = [
    "ok",
    "t_id01 c[116,95,105,100,48,49]/1(a[111,107])",
    "t_id02 c[116,95,105,100,48,50]/1(a[111,107])",
    "t_id03 c[116,95,105,100,48,51]/1(a[111,107])",
    "t_id04 c[116,95,105,100,48,52]/1(a[111,107])",
]

"The answer plunit expects of every row: the test passes, `R = ok` (run in swipl by gen_tabling.py pin, plunit part of pins file)."
const _TT_UPSTREAM = [
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
]

"The files of the program in a fresh directory: the parent module file, one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    write(joinpath(d, "test_incr_dyn_nodes.pl"), ":- module(test_incr_dyn_nodes, []).\n" * _TT_TAIL)
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "plunit_$short.pl"),
            ":- module(plunit_$short, []).\n:- set_module(base(test_incr_dyn_nodes)).\n" * text
        )
    end
    main = ":- use_module('$d/test_incr_dyn_nodes').\n" * join([":- catch(use_module('$d/plunit_$short'), _, true).\n" for (short, _, _) in _TT_UNITS])
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

@testset "upstream test_incr_dyn_nodes.pl: the kernel answers every row as swipl does" begin
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
