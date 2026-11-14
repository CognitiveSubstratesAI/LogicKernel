# ORIGINAL: the UPSTREAM tests/tabling/test_incr_answer_subsumption.pl (swipl-devel 18168e62, 10.1.20), units 1..3 of 3 (incr_answer_subsumption_1, mono_answer_subsumption_1, mono_answer_subsumption_lazy_1),
# as kernel rows (TAB1, TABTEST-M). One row `t_<id>(R)` per upstream test: `abolish_all_tables, <unit>:test(<name>), abolish_all_tables`, R = ok / failed / raised(E).
#   * The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus the file's shared code outside the units (the meta_predicate
#     block and the TEST HELPERS block: init/1, cleanup/1,2, expect/3, expect_valid/1, expect_invalid/1, queued_answers/3, unqualify/3,
#     expect_queued_answers/2; plunit's units see their parent's predicates), and the libraries the file loads (all but plunit); each unit is its own
#     module `pu_<unit>` (plunit gives each unit a module). No helper library.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_m.txt, which also holds the plunit
#     run of the same units) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
#   * DIVERGES from the file: plunit is not used (`pu_<unit>:test(Name, _)` is called directly), the unit modules are `pu_<unit>` not `plunit_<unit>`.
#     Folded by hand: every test's `cleanup(cleanup([d/1]))` is `setup_call_cleanup(true, Test, pu_<unit>:cleanup([d/1]))`; the Options of test/2 stay unbound.
#     Tests with a DUPLICATE name (mono_answer_subsumption_1 `reeval` x2, mono_answer_subsumption_lazy_1 `update` x2) are test/2 clauses of one
#     predicate: the second of each is reached by `nth_clause/3` + `clause/3` + `call/1` on that clause, the first by name.
#   * A row whose program the kernel refuses stays a row pinned on swipl (the pin is not weakened); none is known for these units.
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
    ("incr_answer_subsumption_1", ":- begin_tests(incr_answer_subsumption_1).", raw"""

:- dynamic d/1 as incremental.
:- table p(max) as incremental.
:- table p2/1 as incremental.

p(X) :- d(X).
p2(X) :- p(X).

                                        % Verify normal update
test(update, [cleanup(cleanup([d/1]))]) :-
    init(p(_)),
    assertz(d(1)),
    expect_invalid(p(_)),
    expect(X, p(X), [1]),
    expect_valid(p(_)),
    assertz(d(2)),
    expect_invalid(p(_)),
    expect(X, p(X), [2]),
    expect_valid(p(_)).
                                        % Verify non-changing update
test(keep, [cleanup(cleanup([d/1]))]) :-
    init(p(_)),
    assertz(d(1)),
    expect_invalid(p(_)),
    expect(X, p(X), [1]),
    expect_valid(p(_)),
    assertz(d(0)),
    expect_invalid(p(_)),
    expect(X, p(X), [1]),
    expect_valid(p(_)).
                                        % Verify falsecount propagation
test(reeval, [cleanup(cleanup([d/1]))]) :-
    init(p2(_)),
    assertz(d(1)),
    expect_invalid(p(_)),
    expect_invalid(p2(_)),
    expect(X, p(X), [1]),
    expect_valid(p(_)),
    expect_invalid(p2(_)),
    expect(X, p2(X), [1]),
    assertz(d(0)),
    expect_invalid(p(_)),
    expect_invalid(p2(_)),
    expect(X, p(X), [1]),
    expect_valid(p(_)),
    expect_valid(p2(_)).

"""),
    ("mono_answer_subsumption_1", ":- begin_tests(mono_answer_subsumption_1).", raw"""

:- dynamic d/1 as monotonic.
:- table p(max) as monotonic.
:- table p2/1 as incremental.

p(X) :- d(X).
p2(X) :- p(X).

                                        % Verify normal update
test(update, [cleanup(cleanup([d/1]))]) :-
    init(p(_)),
    assertz(d(1)),
    expect(X, p(X), [1]),
    expect_valid(p(_)),
    assertz(d(2)),
    expect(X, p(X), [2]),
    expect_valid(p(_)).
                                        % Verify non-changing update
test(keep, [cleanup(cleanup([d/1]))]) :-
    init(p(_)),
    assertz(d(1)),
    expect(X, p(X), [1]),
    expect_valid(p(_)),
    assertz(d(0)),
    expect(X, p(X), [1]),
    expect_valid(p(_)).
                                        % Verify falsecount propagation
test(reeval, [cleanup(cleanup([d/1]))]) :-
    init(p2(_)),
    assertz(d(1)),
    expect(X, p(X), [1]),
    expect_valid(p(_)),
    expect_invalid(p2(_)),
    expect(X, p2(X), [1]),
    assertz(d(0)),
    expect_valid(p2(_)),
    expect(X, p2(X), [1]).

test(reeval, [cleanup(cleanup([d/1]))]) :-
    init(p2(_)),
    assertz(d(1)),
    expect(X, p(X), [1]),
    expect_valid(p(_)),
    expect_invalid(p2(_)),
    expect(X, p2(X), [1]),
    assertz(d(2)),
    expect_invalid(p2(_)),
    expect(X, p2(X), [2]),
    expect_valid(p(_)).

"""),
    ("mono_answer_subsumption_lazy_1", ":- begin_tests(mono_answer_subsumption_lazy_1).", raw"""

:- dynamic d/1 as monotonic.
:- table p(max) as (monotonic,lazy).
:- table p2/1 as incremental.

p(X) :- d(X).
p2(X) :- p(X).

test(update, [cleanup(cleanup([d/1]))]) :-
    init(p2(_)),
    assertz(d(1)),
    expect_invalid(p(_)),
    expect_invalid(p2(_)),
    expect(X, p(X), [1]),
    expect_invalid(p2(_)),
    expect(X, p2(X), [1]),
    assertz(d(2)),
    expect_invalid(p(_)),
    expect_invalid(p2(_)),
    expect(X, p2(X), [2]),
    expect_valid(p2(_)).

test(update, [cleanup(cleanup([d/1]))]) :-
    init(p2(_)),
    assertz(d(1)),
    expect_invalid(p(_)),
    expect_invalid(p2(_)),
    expect(X, p(X), [1]),
    expect_invalid(p2(_)),
    expect(X, p2(X), [1]),
    assertz(d(2)),
    expect_invalid(p(_)),
    expect_invalid(p2(_)),
    expect(X, p(X), [2]),
    expect_invalid(p2(_)),
    expect(X, p2(X), [2]),
    expect_valid(p2(_)).

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
:- meta_predicate
    init(0),
    cleanup(:),
    queued_answers(:,-,-),
    expect(?, 0, +),
    expect_valid(0),
    expect_invalid(0),
    expect_queued_answers(:, +).

		 /*******************************
		 *         TEST HELPERS		*
		 *******************************/

init(P) :-
    forall(P, true).

cleanup(M:List) :-
    abolish_all_tables,
    maplist(cleanup(M), List).

cleanup(M, PI) :-
    pi_head(PI, Head),
    retractall(M:Head).

expect(Templ, Goal, Answer) :-
    findall(Templ, Goal, R0),
    sort(R0, R),
    sort(Answer, Answer1),
    assertion(Answer1 == R).

expect_valid(Goal) :-
    assertion(\+ incr_is_invalid(Goal)).

expect_invalid(Goal) :-
    assertion(incr_is_invalid(Goal)).

queued_answers(To, From, Count) :-
    get_calls(To, DstTrie, _Ret),
    '$idg_mono_affects_lazy'(DstTrie, SrcTrie, _Dep, Answers),
    '$tbl_table_status'(SrcTrie, _Status, From0, _Skeleton),
    unqualify(To, From0, From),
    length(Answers, Count).

unqualify(M:_, M:From, From) :- !.
unqualify(_, From, From).


expect_queued_answers(To, Expected0) :-
    findall(From-Count, queued_answers(To, From, Count), Pairs1),
    sort(Pairs1, Found),
    sort(Expected0, Expected),
    assertion(Found =@= Expected).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("tt01a", "incr_answer_subsumption_1", "setup_call_cleanup(true, pu_incr_answer_subsumption_1:test(update, _), pu_incr_answer_subsumption_1:cleanup([d/1]))"),
    ("tt01b", "incr_answer_subsumption_1", "setup_call_cleanup(true, pu_incr_answer_subsumption_1:test(keep, _), pu_incr_answer_subsumption_1:cleanup([d/1]))"),
    ("tt01c", "incr_answer_subsumption_1", "setup_call_cleanup(true, pu_incr_answer_subsumption_1:test(reeval, _), pu_incr_answer_subsumption_1:cleanup([d/1]))"),
    ("tt02a", "mono_answer_subsumption_1", "setup_call_cleanup(true, pu_mono_answer_subsumption_1:test(update, _), pu_mono_answer_subsumption_1:cleanup([d/1]))"),
    ("tt02b", "mono_answer_subsumption_1", "setup_call_cleanup(true, pu_mono_answer_subsumption_1:test(keep, _), pu_mono_answer_subsumption_1:cleanup([d/1]))"),
    ("tt02c", "mono_answer_subsumption_1", "setup_call_cleanup(true, pu_mono_answer_subsumption_1:test(reeval, _), pu_mono_answer_subsumption_1:cleanup([d/1]))"),
    ("tt02d", "mono_answer_subsumption_1", "setup_call_cleanup(true, (nth_clause(pu_mono_answer_subsumption_1:test(_, _), 4, CRef), clause(pu_mono_answer_subsumption_1:test(_, _), CBody, CRef), call(pu_mono_answer_subsumption_1:CBody)), pu_mono_answer_subsumption_1:cleanup([d/1]))"),
    ("tt03a", "mono_answer_subsumption_lazy_1", "setup_call_cleanup(true, pu_mono_answer_subsumption_lazy_1:test(update, _), pu_mono_answer_subsumption_lazy_1:cleanup([d/1]))"),
    ("tt03b", "mono_answer_subsumption_lazy_1", "setup_call_cleanup(true, (nth_clause(pu_mono_answer_subsumption_lazy_1:test(_, _), 2, CRef), clause(pu_mono_answer_subsumption_lazy_1:test(_, _), CBody, CRef), call(pu_mono_answer_subsumption_lazy_1:CBody)), pu_mono_answer_subsumption_lazy_1:cleanup([d/1]))"),
]

const _TT_PINNED = [
    "ok",
    "t_tt01a c[116,95,116,116,48,49,97]/1(a[111,107])",
    "t_tt01b c[116,95,116,116,48,49,98]/1(a[111,107])",
    "t_tt01c c[116,95,116,116,48,49,99]/1(a[111,107])",
    "t_tt02a c[116,95,116,116,48,50,97]/1(a[111,107])",
    "t_tt02b c[116,95,116,116,48,50,98]/1(a[111,107])",
    "t_tt02c c[116,95,116,116,48,50,99]/1(a[111,107])",
    "t_tt02d c[116,95,116,116,48,50,100]/1(a[111,107])",
    "t_tt03a c[116,95,116,116,48,51,97]/1(a[111,107])",
    "t_tt03b c[116,95,116,116,48,51,98]/1(a[111,107])",
]

"The answer plunit expects of every row: the test passes, `R = ok` (run in swipl by gen_reeval.py pin, plunit part of pins file)."
const _TT_UPSTREAM = [
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
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
            ":- module(pu_$short, []).\n:- use_module(library(increval)).\n:- use_module(library(tables)).\n:- use_module(library(apply)).\n:- use_module(library(debug)).\n:- use_module(library(prolog_code)).\n" * text * "\n" * _TT_TAIL
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

@testset "upstream test_incr_answer_subsumption.pl units 1..3: the kernel answers every row as swipl does" begin
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
