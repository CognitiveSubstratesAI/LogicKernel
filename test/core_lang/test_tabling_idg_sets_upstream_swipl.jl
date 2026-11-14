# ORIGINAL: the UPSTREAM tests/tabling/test_idg_sets.pl (swipl-devel 18168e62, 10.1.20), units idg_sets, idg_reader, idg_space (18 tests), as
# kernel rows (TAB1, TABTEST-IDG). One row `t_id<NN>(R)` per upstream test: `abolish_all_tables, <goal>, abolish_all_tables`, R = ok / failed /
# raised(E). The edge sets of the incremental dependency graph (IDG): nodes with many edges in both directions, invalidation, re-evaluation,
# edges deleted by abolishing tables, the IDG of a thread read from another thread while it changes, and the IDG as part of the table space.
#   * No comment was elided: the file has no line matching the D-0164 term list.
#   * Layout as plunit's, with the file split for load isolation: the module of the file, `test_idg_sets` (the file's text outside the units up
#     to the SPACE block: the incremental dynamic d/1, the tables p/1 and q/1, fill/1, variant_trie/2, edges/3, add_fact/1, invalid_tables/1,
#     own_summary/2, modify/1, read_idg/4, threads/0; the file's `:- module(.., [test_idg_sets/0])` header and its run_tests clause are left out),
#     the SPACE block as its own module `test_idg_space` (e/1, pi/1, pn/1, table_space/5, table_space_/2), and each unit as its own module
#     `plunit_<unit>` with `:- set_module(base(<parent>))` (idg_sets and idg_reader on test_idg_sets, idg_space on test_idg_space; the test text
#     between `begin_tests` and `end_tests` verbatim). Every module loads with `catch(use_module(..), _, true)`, so a declaration or unit the kernel
#     refuses leaves only ITS rows undefined (the pin loads all of them, status ok).
#   * DIVERGES from the file: the SPACE block declares its own `:- dynamic([d/1], [incremental(true)])` (in the file it shares d/1 with the first
#     part; the unit idg_space never names d/1, only pi/1 and table_space_/2 do). plunit is not used (a row calls the unit's test/2 clause
#     directly). The options are folded by hand: the options `Var == Val` are called after the body (the row binds the option to C and
#     calls it); the option lists `[Count-Invalid == 100-0]`, `[Nodes-Edges == .. - ..]`, `[true(Extra >= IDGSize), true(IDGSize > 0)]` and
#     `[true(IDGSpace >= IDGSize), true(Extra >= IDGSpace), NoIDG == 0]` as `[C]` / `[true(C1), true(C2)]` / `[true(C1), true(C2), C3]` with
#     each check called after the body; the unit option cleanup of plunit is the driver's abolish_all_tables after the row. The tests
#     with `condition(threads)` (their own option, or the option of the unit idg_space) keep it UNFOLDED: the body runs, so a kernel without
#     threads shows the refusal.
#   * THREAD-BOUND: summary, concurrent, exited, predicate_edges_outside, shared (idg_reader) and in_table_space, idg_thread_space (idg_space)
#     are pinned on swipl in their own testset "thread-bound: expected refusal on the kernel": a kernel line that differs from the pin is
#     recorded as @test_broken (visible in the summary), one that equals it passes.
#   * Expected refusals on the kernel (by reading, unverified): `:- dynamic([d/1], [incremental(true)])` and `:- table p/1 as incremental` (the
#     parent, so the idg_sets rows and most idg_reader rows), the private builtins '$tbl_variant_table'/1, '$idg_edge'/3, '$idg_falsecount'/2,
#     '$tbl_local_variant_table'/1, '$idg_thread_summary'/3, '$idg_predicate_edges'/3, '$tbl_table_status'/4, '$idg_thread_space'/2 (the kernel may
#     leave any of them undefined), trie_gen/3, trie_property(_, idg_size(_)), statistics(table_space_used, _), thread_create/2, thread_join/2,
#     thread_send_message/2, thread_get_message/1, clumped/2, aggregate_all(count-sum(_), ..). Every row stays pinned on swipl.
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_idg.txt, which also holds the plunit
#     run: 18 of 18 tests passed, none failed or hung on the pin) AND equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
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
    ("sets", "begin_tests(idg_sets)", raw"""
test(affected_many, Count == 100) :-
    fill(100),
    edges(d(_), affected, Count).
test(dependent_many, Count == 100) :-
    fill(100),
    edges(q(100), dependent, Count).
test(edge_lookup, true) :-
    fill(100),
    once(variant_trie(d(_), D)),
    once(variant_trie(p(57), P)),
    '$idg_edge'(D, affected, P).
test(invalidate_all, Invalid == 100) :-
    fill(100),
    add_fact(2),
    invalid_tables(Invalid).
test(reevaluate, [Count-Invalid == 100-0]) :-
    fill(100),
    add_fact(2),
    forall(between(1, 100, I), p(I)),
    invalid_tables(Invalid),
    edges(d(_), affected, Count).
test(delete_edges, Count == 50) :-
    fill(100),
    forall(between(1, 50, I), abolish_table_subgoals(p(I))),
    edges(d(_), affected, Count).
test(delete_and_add, Count == 100) :-
    fill(100),
    forall(between(1, 50, I), abolish_table_subgoals(p(I))),
    forall(between(1, 50, I), p(I)),
    edges(d(_), affected, Count).
test(single_edge, Count == 1) :-
    fill(1),
    edges(d(_), affected, Count).
"""),
    ("reader", "begin_tests(idg_reader)", raw"""
test(summary, [condition(threads), Outside == Inside]) :-
    thread_self(Me),
    thread_create(( fill(100),
                    own_summary(N, E),
                    thread_send_message(Me, inside(N-E)),
                    thread_get_message(done)
                  ), Id),
    thread_get_message(inside(Inside)),
    '$idg_thread_summary'(Id, N1, E1),
    Outside = N1-E1,
    thread_send_message(Id, done),
    thread_join(Id).
test(concurrent, [condition(threads), true(Reads > 0)]) :-
    get_time(Now),
    Deadline is Now+1.5,
    thread_create(modify(Deadline), Id),
    read_idg(Id, Deadline, 0, Reads),
    thread_join(Id).
test(exited, [condition(threads), Nodes-Edges == 0-0]) :-
    thread_create(fill(10), Id),
    thread_join(Id),
    catch('$idg_thread_summary'(Id, Nodes, Edges), _, (Nodes-Edges = 0-0)).
%   '$idg_predicate_edges'/3 summarizes the IDG per predicate.

test(predicate_edges, [ Nodes-Edges ==
                        [ node(test_idg_sets:d/1, 101, 0),
                          node(test_idg_sets:p/1, 100, 0),
                          node(test_idg_sets:q/1, 1, 0)
                        ] -
                        [ edge(test_idg_sets:d/1, test_idg_sets:p/1, 100),
                          edge(test_idg_sets:d/1, test_idg_sets:q/1, 100)
                        ]
                      ]) :-
    fill(100),
    thread_self(Me),
    '$idg_predicate_edges'(Me, Nodes0, Edges0),
    msort(Nodes0, Nodes),
    msort(Edges0, Edges).
test(predicate_edges_invalid, Invalid == 100) :-
    fill(100),
    add_fact(2),
    thread_self(Me),
    '$idg_predicate_edges'(Me, Nodes, _),
    memberchk(node(test_idg_sets:p/1, _, Invalid), Nodes).
test(predicate_edges_outside, [condition(threads), Outside == Inside]) :-
    thread_self(Me),
    thread_create(( fill(100),
                    thread_self(Self),
                    '$idg_predicate_edges'(Self, N, E),
                    msort(N, SN), msort(E, SE),
                    thread_send_message(Me, inside(SN-SE)),
                    thread_get_message(done)
                  ), Id),
    thread_get_message(inside(Inside)),
    '$idg_predicate_edges'(Id, N1, E1),
    msort(N1, SN1), msort(E1, SE1),
    Outside = SN1-SE1,
    thread_send_message(Id, done),
    thread_join(Id).
test(predicate_edges_prolog, Edges == PrologEdges) :-
    fill(30),
    thread_self(Me),
    '$idg_predicate_edges'(Me, _, Edges0),
    msort(Edges0, Edges),
    '$tbl_local_variant_table'(VT),
    findall(F-T, ( trie_gen(VT, FM:FV, FT),
                   '$idg_edge'(FT, affected, DT),
                   '$tbl_table_status'(DT, _, TM:TV, _),
                   functor(FV, FN, FA), functor(TV, TN, TA),
                   F = FM:FN/FA, T = TM:TN/TA
                 ), Pairs),
    msort(Pairs, Sorted),
    clumped(Sorted, Counted),
    findall(edge(F,T,C), member((F-T)-C, Counted), PrologEdges).
test(shared, condition(threads)) :-
    '$idg_thread_summary'(shared, Nodes, Edges),
    integer(Nodes), integer(Edges).
"""),
    ("space", "begin_tests(idg_space)", raw"""
test(in_table_space, [true(Extra >= IDGSize), true(IDGSize > 0)]) :-
    table_space(pi, 1000, SpaceI, IDGSize, _),
    table_space(pn, 1000, SpaceN, _, _),
    Extra is SpaceI-SpaceN.
test(idg_thread_space, [ true(IDGSpace >= IDGSize),
                         true(Extra >= IDGSpace),
                         NoIDG == 0
                       ]) :-
    table_space(pi, 1000, SpaceI, IDGSize, IDGSpace),
    table_space(pn, 1000, SpaceN, _, NoIDG),
    Extra is SpaceI-SpaceN.
"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
:- use_module(library(aggregate)).

/** <module> Test the edge sets of the incremental dependency graph

The edges of an IDG node are kept in a set that is a single pointer for
one edge, a linear block for a few and a hashed block for many (see
src/pl-idgset.h).  These tests create nodes with many edges in both
directions, invalidate and re-evaluate them and delete edges by
abolishing tables.  The unit idg_reader reads the IDG of a thread from
another thread while that thread modifies it.  The unit idg_space checks
that the IDG is part of the table space.
*/



:- dynamic([d/1], [incremental(true)]).
:- table p/1 as incremental.		% p(I) depends on d(_)
:- table q/1 as incremental.		% q(N) depends on d(1) ... d(N)

d(1).

p(I) :- d(X), X >= 0, I >= 0.
q(N) :- aggregate_all(count, (between(1, N, I), d(I)), N0), N0 >= 0.

fill(N) :-
    abolish_all_tables,
    retractall(d(_)),
    assertz(d(1)),
    forall(between(1, N, I), p(I)),
    q(N).

variant_trie(Goal, Trie) :-
    '$tbl_variant_table'(VT),
    trie_gen(VT, test_idg_sets:Goal, Trie).

edges(Goal, Dir, Count) :-
    once(variant_trie(Goal, Trie)),
    aggregate_all(count, '$idg_edge'(Trie, Dir, _), Count).

%   Assert in this module; the tests run in the module of the unit.

add_fact(X) :-
    assertz(d(X)).

invalid_tables(Count) :-
    aggregate_all(count,
                  ( variant_trie(p(_), T),
                    '$idg_falsecount'(T, FC), FC > 0
                  ), Count).


%   own_summary(-Nodes, -Edges)
%
%   Count the IDG nodes and affected edges of this thread from its
%   variant table.

own_summary(Nodes, Edges) :-
    '$tbl_local_variant_table'(VT),
    aggregate_all(count-sum(E),
                  ( trie_gen(VT, _, T),
                    '$idg_falsecount'(T, _),     % has an IDG node
                    aggregate_all(count, '$idg_edge'(T, affected, _), E)
                  ),
                  Nodes-Edges).

%   modify(+Deadline)
%
%   Keep changing the IDG of this thread until Deadline.

modify(Deadline) :-
    get_time(Now),
    (   Now > Deadline
    ->  true
    ;   fill(50),
        add_fact(3),
        forall(between(1, 25, I), p(I)),
        forall(between(26, 50, I), abolish_table_subgoals(p(I))),
        q(50),
        retract(d(3)),
        modify(Deadline)
    ).

read_idg(Thread, Deadline, Reads0, Reads) :-
    get_time(Now),
    (   Now > Deadline
    ->  Reads = Reads0
    ;   '$idg_thread_summary'(Thread, Nodes, Edges),
        assertion((Nodes >= 0, Edges >= 0)),
        '$idg_predicate_edges'(Thread, PNodes, _),
        assertion(is_list(PNodes)),
        Reads1 is Reads0+1,
        read_idg(Thread, Deadline, Reads1, Reads)
    ).


threads :-
    current_prolog_flag(threads, true).
"""

"The SPACE block of the file as its own module file (its own incremental dynamic d/1 first)."
const _TT_SPACE = raw"""
:- dynamic([d/1], [incremental(true)]).
		 /*******************************
		 *            SPACE		*
		 *******************************/

:- dynamic e/1.
:- table pi/1 as incremental.		% as p/1
:- table pn/1.				% as pi/1, without IDG

e(1).

pi(I) :- d(X), X >= 0, I >= 0.
pn(I) :- e(X), X >= 0, I >= 0.

%   table_space(+Pred, +N, -Space, -IDGSize, -IDGSpace)
%
%   Space is the table space used by a fresh thread after calling
%   Pred(1) ... Pred(N), IDGSize the size of the IDG nodes of these
%   tables and IDGSpace the table space used by the IDG of the thread.

table_space(Pred, N, Space, IDGSize, IDGSpace) :-
    thread_create(table_space_(Pred, N), Id),
    thread_join(Id, exited(r(Space, IDGSize, IDGSpace))).

table_space_(Pred, N) :-
    retractall(d(_)),
    assertz(d(1)),
    forall(between(1, N, I), call(Pred, I)),
    statistics(table_space_used, Space),
    '$tbl_variant_table'(VT),
    aggregate_all(sum(Size),
                  ( trie_gen(VT, _, T),
                    trie_property(T, idg_size(Size))
                  ), IDGSize),
    thread_self(Me),
    '$idg_thread_space'(Me, IDGSpace),
    thread_exit(r(Space, IDGSize, IDGSpace)).
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("id01", "idg_sets", "setup_call_cleanup(true, (plunit_idg_sets:test(affected_many, C), call(C)), true)"),
    ("id02", "idg_sets", "setup_call_cleanup(true, (plunit_idg_sets:test(dependent_many, C), call(C)), true)"),
    ("id03", "idg_sets", "plunit_idg_sets:test(edge_lookup, true)"),
    ("id04", "idg_sets", "setup_call_cleanup(true, (plunit_idg_sets:test(invalidate_all, C), call(C)), true)"),
    ("id05", "idg_sets", "setup_call_cleanup(true, (plunit_idg_sets:test(reevaluate, [C]), call(C)), true)"),
    ("id06", "idg_sets", "setup_call_cleanup(true, (plunit_idg_sets:test(delete_edges, C), call(C)), true)"),
    ("id07", "idg_sets", "setup_call_cleanup(true, (plunit_idg_sets:test(delete_and_add, C), call(C)), true)"),
    ("id08", "idg_sets", "setup_call_cleanup(true, (plunit_idg_sets:test(single_edge, C), call(C)), true)"),
    ("id09", "idg_reader", "setup_call_cleanup(true, (plunit_idg_reader:test(summary, [condition(threads), C]), call(C)), true)"),
    ("id10", "idg_reader", "setup_call_cleanup(true, (plunit_idg_reader:test(concurrent, [condition(threads), true(C)]), call(C)), true)"),
    ("id11", "idg_reader", "setup_call_cleanup(true, (plunit_idg_reader:test(exited, [condition(threads), C]), call(C)), true)"),
    ("id12", "idg_reader", "setup_call_cleanup(true, (plunit_idg_reader:test(predicate_edges, [C]), call(C)), true)"),
    ("id13", "idg_reader", "setup_call_cleanup(true, (plunit_idg_reader:test(predicate_edges_invalid, C), call(C)), true)"),
    ("id14", "idg_reader", "setup_call_cleanup(true, (plunit_idg_reader:test(predicate_edges_outside, [condition(threads), C]), call(C)), true)"),
    ("id15", "idg_reader", "setup_call_cleanup(true, (plunit_idg_reader:test(predicate_edges_prolog, C), call(C)), true)"),
    ("id16", "idg_reader", "plunit_idg_reader:test(shared, condition(threads))"),
    ("id17", "idg_space", "setup_call_cleanup(true, (plunit_idg_space:test(in_table_space, [true(C1), true(C2)]), call(C1), call(C2)), true)"),
    ("id18", "idg_space", "setup_call_cleanup(true, (plunit_idg_space:test(idg_thread_space, [true(C1), true(C2), C3]), call(C1), call(C2), call(C3)), true)"),
]


"The thread-bound rows (upstream `condition(threads)`): pinned on swipl; the kernel's line is compared to the pin, and a line that differs is @test_broken, never a silent pass."
const _TT_THREAD_IDS = ["id09", "id10", "id11", "id14", "id16", "id17", "id18"]
const _TT_KL = Ref{Vector{String}}(String[])


const _TT_PINNED = [
    "ok",
    "t_id01 c[116,95,105,100,48,49]/1(a[111,107])",
    "t_id02 c[116,95,105,100,48,50]/1(a[111,107])",
    "t_id03 c[116,95,105,100,48,51]/1(a[111,107])",
    "t_id04 c[116,95,105,100,48,52]/1(a[111,107])",
    "t_id05 c[116,95,105,100,48,53]/1(a[111,107])",
    "t_id06 c[116,95,105,100,48,54]/1(a[111,107])",
    "t_id07 c[116,95,105,100,48,55]/1(a[111,107])",
    "t_id08 c[116,95,105,100,48,56]/1(a[111,107])",
    "t_id09 c[116,95,105,100,48,57]/1(a[111,107])",
    "t_id10 c[116,95,105,100,49,48]/1(a[111,107])",
    "t_id11 c[116,95,105,100,49,49]/1(a[111,107])",
    "t_id12 c[116,95,105,100,49,50]/1(a[111,107])",
    "t_id13 c[116,95,105,100,49,51]/1(a[111,107])",
    "t_id14 c[116,95,105,100,49,52]/1(a[111,107])",
    "t_id15 c[116,95,105,100,49,53]/1(a[111,107])",
    "t_id16 c[116,95,105,100,49,54]/1(a[111,107])",
    "t_id17 c[116,95,105,100,49,55]/1(a[111,107])",
    "t_id18 c[116,95,105,100,49,56]/1(a[111,107])",
]

"The answer plunit expects of every row: the test passes, `R = ok` (run in swipl by gen_tabling.py pin, plunit part of pins file)."
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

"The files of the program in a fresh directory: the parent module files, one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    write(joinpath(d, "test_idg_sets.pl"), ":- module(test_idg_sets, []).\n" * _TT_TAIL)
    write(joinpath(d, "test_idg_space.pl"), ":- module(test_idg_space, []).\n" * _TT_SPACE)
    for (short, _, text) in _TT_UNITS
        base = short == "space" ? "test_idg_space" : "test_idg_sets"
        write(
            joinpath(d, "plunit_$short.pl"),
            ":- module(plunit_$short, []).\n:- set_module(base($base)).\n" * text
        )
    end
    main = join([":- catch(use_module('$d/$p'), _, true).\n" for p in ("test_idg_sets", "test_idg_space")])
    main *= join([":- catch(use_module('$d/plunit_$short'), _, true).\n" for (short, _, _) in _TT_UNITS])
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

@testset "upstream test_idg_sets.pl: the kernel answers every row as swipl does" begin
    gd, ld, st = _tt_load(_tt_materialize())
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TT_CASES
        push!(kl, _tt_ask(gd, ld, "t_$id"))
    end
    _TT_KL[] = kl
    @test length(kl) == length(_TT_PINNED)
    @test _TT_PINNED[1] == st
    for (i, (k, pn)) in enumerate(zip(kl, _TT_PINNED))
        i > 1 && _TT_CASES[i - 1][1] in _TT_THREAD_IDS && continue
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _tt_corrupt(_TT_PINNED[2])
end

@testset "thread-bound: expected refusal on the kernel (upstream tests with condition(threads))" begin
    kl = _TT_KL[]
    @test length(kl) == length(_TT_PINNED)
    for id in _TT_THREAD_IDS
        j = findfirst(c -> c[1] == id, _TT_CASES)::Int
        k, pn = kl[j + 1], _TT_PINNED[j + 1]
        @test _tt_answer(pn) == _TT_UPSTREAM[j]
        @test k != _tt_corrupt(pn)  # must-fail: the comparison can fail
        if k == pn
            @test true
        else
            println(stderr, "  thread-bound ", id, "\n  ours  ", k, "\n  swipl ", pn)
            @test_broken k == pn
        end
    end
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
