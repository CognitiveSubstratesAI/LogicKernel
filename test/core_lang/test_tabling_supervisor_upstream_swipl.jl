# ORIGINAL: the UPSTREAM tests/tabling/test_tabled_supervisor.pl (swipl-devel 18168e62, 10.1.20), all 33 tests of the one unit
# `tabled_supervisor`, as kernel rows (TAB1, TABTEST-S). One row `t_s<NN>(R)` per upstream test: `abolish_all_tables, pu_supervisor:test(<name>),
# abolish_all_tables`, R = ok / failed / raised(E).
#   * Comments matching the D-0164 terms are elided from the embedded text; no code differs.
#   * The unit text is upstream's, verbatim: the file's helper predicates (all/3, inferences/2 and their meta_predicate declaration) and the text
#     between `begin_tests` and `end_tests`, as module `pu_supervisor` (plunit gives the unit a module), with the pin's helper library
#     test/core_lang/tabling_testlib_upstream.pl as `tabling_testlib`.
#   * DIVERGES from the file: plunit is not used (`pu_supervisor:test(Name)` is called directly); `:- discontiguous test/1, test/2.` is added
#     (the tests with options in their head are plain test/2 clauses here); the `condition(..)`, `setup(..)`, `cleanup(..)` options are folded
#     by hand (ROW_FOLD in gen_supervisor.py: outer_wrapper's wrap_predicate setup/unwrap cleanup, incremental/monotonic/retable's cleanup,
#     ssu_complete_fails's `[F1,..] == [true,..]` option called after the body). The 4 thread conditions are NOT folded: the body runs.
#   * THREAD-BOUND: fast_path_shared, thread_cache, shared_abolish, shared_thread (`condition(current_prolog_flag(threads, true))`; threads, and
#     `table sh/1 as shared`) are pinned on swipl in their own testset "thread-bound: expected refusal on the kernel": a kernel line that
#     differs from the pin is recorded as @test_broken (visible in the summary), one that equals it passes. The unit text keeps `:- table sh/1
#     as shared` for ALL rows (test `supervisor` asserts on sh/1): a load refusal of that directive would turn the load status into `exc ...`
#     and leave every row undefined; if so move sh/1 and the 4 tests into their own module, never weaken a pin.
#   * Expected refusals / divergences on the kernel (by reading, unverified): the tests that count inferences (fast_path*, repeated_vars,
#     abolish_pinned, abolish_reuse, abolish_all_cache, slow_path_debug: S_TABLED supervisor, statistics(inferences)), `'$get_predicate_attribute'(_,
#     tabled_variant, 1)` (supervisor, retable), table(M:Spec)/untable(M:Spec) at run time (retable), library(prolog_wrap) wrap_predicate/unwrap_predicate
#     (outer_wrapper), SSU rules tabled after their clauses (ssu_complete_fails), call_delays/2 (wfs), `table (..) as incremental/monotonic/subsumptive`.
#     Every row stays pinned on swipl (the pin is not weakened).
#   * Every pinned line is swipl's (swipl 10.1.20, two identical runs, evidence/TAB1/tabgap_tools/pins_s.txt, which also holds the plunit run) AND
#     equals the answer plunit expects (`_TT_UPSTREAM`: each test passes, so `ok`).
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

"The pin's helper library, verbatim (tests/tabling/tabling_testlib.pl)."
const _TT_TESTLIB = joinpath(@__DIR__, "tabling_testlib_upstream.pl")

"The units' text, verbatim between begin_tests and end_tests: `(short name, begin_tests directive, text)`."
const _TT_UNITS = [
    ("supervisor", "begin_tests(tabled_supervisor)", raw"""
:- use_module(library(lists)).
:- use_module(library(prolog_wrap)).
:- discontiguous test/1, test/2.
:- meta_predicate
    all(?, 0, -),
    inferences(0, -).

all(T, G, L) :- findall(T, G, L0), msort(L0, L).

%   inferences(:Goal, -Count) is semidet.
%
%   Count is the number of inferences for once(Goal), compensated
%   for the overhead.  A call that is answered by S_TABLED costs
%   one inference, the same as a call to a fact.

inferences(G, N) :-
    statistics(inferences, I0),
    once(G),
    statistics(inferences, I1),
    statistics(inferences, I2),
    N is (I1-I0)-(I2-I1).


:- dynamic
    counter/1,
    d/1 as incremental,
    md/1 as monotonic.

fact(a).

:- table
    f/2, g/1, e/1, z/0, nz/0, pa/2, big/3, lv/1, gc/1,
    w/0, nw/0, wrapped/1, cnt/1.

f(N, X) :- between(1, N, X).
g(a).
e(_) :- fail.
z.
nz :- fail.
pa(a, 1).
pa(a, 2).
pa(b, f(_)).
big(X, s(Y), L) :- between(1, 3, X), Y = X, numlist(1, 1000, L).
gc(L) :- between(1, 100, X), length(L0, X), L = [X|L0].
w :- tnot(nw).
nw :- tnot(w).
wrapped(X) :- between(1, 3, X).
cnt(X) :- flag(cnt, N, N+1), X = N.

lv(Y) :- f(3, X), Y = X.               % X is a local variable

:- table (ip/1, iq/1) as incremental.
ip(X) :- d(X).
iq(X) :- ip(X).

:- table (mp/1, mq/1) as monotonic.
mp(X) :- md(X).
mq(X) :- mp(X).

:- table sh/1 as shared.
sh(X) :- between(1, 3, X).

:- table rv/2, ind/2, mix/2.
rv(X, Y) :- member(X-Y, [1-1, 1-2, _-_]).
ind(X, Y) :- member(X-Y, [1.5-float, "str"-string, 100000000000000000000-big,
                          a-atom, 1-int]).
mix(X, Y) :- member(X-Y, [f(1)-c1, f(_)-c2, [a]-list, a-atom]).

:- table only/1, only0/0, other/1.
other(other).
only(X) :- flag(only, N, N+1), X = N.
only0 :- flag(only, N, N+1), N >= 0.

:- table mo(_,max).
mo(a, 1).
mo(a, 3).
mo(a, 2).

:- table su/1 as subsumptive.
su(X) :- between(1, 3, X).

%   SSU predicates tabled after their clauses: S_SSU_DET runs before
%   S_TABLED, so failing from a complete table must not raise an
%   existence error for the rules.

ssu(X) => X == a.
ssm(X) => member(X, [a,b]).
:- table ssu/1, ssm/1.

test(supervisor) :-
    assertion('$get_predicate_attribute'(f(_,_), tabled_variant, 1)),
    assertion('$get_predicate_attribute'(sh(_), tabled_variant, 1)),
    assertion(\+ '$get_predicate_attribute'(mo(_,_), tabled_variant, 1)),
    assertion(\+ '$get_predicate_attribute'(su(_), tabled_variant, 1)).
test(fast_path) :-
    g(a),
    inferences(fact(a), N0),
    inferences(g(a), N1),
    assertion(N0 == N1).
test(fast_path_shared, condition(current_prolog_flag(threads, true))) :-
    all(X, sh(X), _),
    inferences(sh(_), N0),
    inferences(fact(_), N1),
    assertion(N0 == N1).
test(fast_path_nonground) :-
    all(X, f(3, X), _),
    inferences(f(3, _), N0),
    inferences(fact(_), N1),
    assertion(N0 == N1).
test(fast_path_indirect) :-
    forall(member(K, [1.5, "str", 100000000000000000000]),
           ( all(T, ind(K, T), _),
             inferences(ind(K, _), N0),
             inferences(fact(_), N1),
             assertion(N0 == N1)
           )).
test(repeated_vars) :-
    all(X-Y, rv(X, Y), L0),             % create both variant tables
    all(X, rv(X, X), L1),
    all(X-Y, rv(X, Y), L2),
    all(X, rv(X, X), L3),
    assertion(L0 =@= L2),
    assertion(L1 =@= L3),
    assertion(length(L1, 2)),
    inferences(rv(_, _), N0),
    inferences(rv(Z, Z), N1),
    inferences(fact(_), N2),
    assertion(N0 == N2),
    assertion(N1 == N2),
    assertion((var(Z) ; Z == 1)).       % first answer; order is unspecified
test(indirect) :-
    forall(member(K-T, [1.5-float, "str"-string, 100000000000000000000-big,
                        a-atom, 1-int]),
           ( all(T1, ind(K, T1), L0),
             all(T1, ind(K, T1), L1),
             assertion(L0 == [T]),
             assertion(L1 == L0)
           )),
    assertion(\+ ind(2.5, _)),
    assertion(\+ ind(2.5, _)),
    assertion(\+ ind("nostr", _)),
    assertion(\+ ind("nostr", _)).
test(compound_arg) :-
    all(T, mix(f(1), T), L0), all(T, mix(f(1), T), L1),
    assertion(L0 == [c1,c2]), assertion(L1 == L0),
    all(T, mix(f(_), T), L2), all(T, mix(f(_), T), L3),
    assertion(L2 == [c1,c2]), assertion(L3 == L2),
    all(X-T, mix(X, T), L4), all(X-T, mix(X, T), L5),
    assertion(length(L4, 4)), assertion(L5 =@= L4).
test(attvar_arg) :-                    % generic path; same as wrapper
    freeze(X, true),
    findall(X, f(3, X), L0),
    findall(X, f(3, X), L1),
    setup_call_cleanup(debug, findall(X, f(3, X), L2), nodebug),
    assertion(L0 == L1),
    assertion(L1 == L2).
test(abolish_pinned) :-                % abolish the only table of only/1
    flag(only, _, 0),
    only(X0),
    abolish_table_subgoals(only(_)),
    only(X1),                           % recomputed below the pinned node
    only(X2),                           % fast path
    assertion(X1 \== X0),
    assertion(X2 == X1),
    inferences(only(_), N0),
    inferences(fact(_), N1),
    assertion(N0 == N1),
    only0,
    abolish_table_subgoals(only0),
    only0, only0,
    inferences(only0, N2),
    assertion(N2 == N1).
test(abolish_reuse) :-                 % freed nodes are reused by other/1
    abolish_all_tables,
    flag(only, _, 0),
    only(_), only(_),                   % cache the start node
    abolish_table_subgoals(only(_)),
    abolish_table_subgoals(other(_)),
    other(O),
    only(X1),
    only(X2),
    assertion(O == other),
    assertion(integer(X1)),
    assertion(X2 == X1),
    inferences(only(_), N0),            % still uses the start node
    inferences(fact(_), N1),
    assertion(N0 == N1).
test(abolish_all_cache) :-
    abolish_all_tables,
    flag(only, _, 0),
    only(X0),
    abolish_all_tables,                 % frees the private variant table
    only(X1),
    abolish_all_tables,
    all(Y, f(4, Y), L),
    only(X2),
    assertion(X0 \== X1),
    assertion(X1 \== X2),
    assertion(L == [1,2,3,4]),
    inferences(only(_), N0),
    inferences(fact(_), N1),
    assertion(N0 == N1).
test(thread_cache, condition(current_prolog_flag(threads, true))) :-
    all(Y, f(4, Y), L0),
    forall(between(1, 5, _),
           ( thread_create(( all(Y, f(4, Y), L1),
                             all(Y, f(4, Y), L2),
                             assertion(L1 == L0),
                             assertion(L2 == L0)
                           ), Id),
             thread_join(Id, Status),
             assertion(Status == true)
           )),
    all(Y, f(4, Y), L3),
    assertion(L3 == L0).
test(shared_abolish, condition(current_prolog_flag(threads, true))) :-
    all(X, sh(X), L0),
    abolish_table_subgoals(sh(_)),
    all(X, sh(X), L1),
    all(X, sh(X), L2),
    assertion(L0 == [1,2,3]),
    assertion(L1 == L0),
    assertion(L2 == L0).
test(slow_path_debug) :-
    g(a),
    setup_call_cleanup(debug, inferences(g(a), N), nodebug),
    assertion(N > 1).
test(answers) :-
    all(X, f(5, X), L0), all(X, f(5, X), L1),
    assertion(L0 == [1,2,3,4,5]),
    assertion(L1 == L0),
    once(f(5, Y)),
    setup_call_cleanup(debug, once(f(5, Y1)), nodebug),
    assertion(Y == Y1),                 % same order as the wrapper
    assertion(f(5, 3)),
    assertion(\+ f(5, 6)).
test(partial) :-
    all(X-Y, pa(X, Y), _),
    assertion(all(Y, pa(a, Y), [1,2])),
    assertion(all(Y, pa(a, Y), [1,2])),
    assertion(\+ pa(c, _)),
    pa(b, T), assertion(T = f(V)), assertion(var(V)).
test(ground) :-
    g(a), g(a),
    assertion(\+ g(b)), assertion(\+ g(b)).
test(empty) :-
    assertion(\+ e(_)), assertion(\+ e(_)),
    assertion(\+ nz), assertion(\+ nz).
test(arity0) :-
    z, z.
test(local_var) :-
    all(Y, lv(Y), L0),
    all(Y, lv(Y), L1),
    assertion(L0 == [1,2,3]),
    assertion(L1 == L0).
test(big) :-
    all(X-Y, big(X, s(Y), _), _),
    all(X-Y-N, (big(X, s(Y), L), length(L, N)), R),
    assertion(R == [1-1-1000, 2-2-1000, 3-3-1000]),
    big(2, Z, _), assertion(Z == s(2)).
test(gc) :-
    all(L, gc(L), _),
    forall(gc(L), (garbage_collect, L = [X|T], length(T, X))).
test(no_reeval) :-
    flag(cnt, _, 0),
    cnt(X), cnt(Y),
    assertion(X == Y),
    abolish_all_tables,
    cnt(Z),
    assertion(Z \== X).
test(wfs) :-
    call_delays(w, D0),
    assertion(D0 \== true),
    call_delays(w, D1),
    assertion(D1 =@= D0).
test(outer_wrapper,
     [ setup(wrap_predicate(wrapped(X), outer, W,
                            (flag(outer, N, N+1), W))),
       cleanup(unwrap_predicate(wrapped/1, outer))
     ]) :-
    flag(outer, _, 0),
    all(X, wrapped(X), L0),
    all(X, wrapped(X), L1),
    assertion(L0 == [1,2,3]),
    assertion(L1 == L0),
    flag(outer, C, C),
    assertion(C == 2).
test(incremental, [cleanup((retractall(d(_)), abolish_all_tables))]) :-
    retractall(d(_)), abolish_all_tables,
    assertz(d(1)),
    all(X, ip(X), [1]),                 % complete ip/1 first
    assertion(all(X, iq(X), [1])),      % iq/1 calls complete ip/1
    assertz(d(2)),
    assertion(all(X, iq(X), [1,2])),
    retract(d(1)),
    assertion(all(X, iq(X), [2])).
test(monotonic, [cleanup((retractall(md(_)), abolish_all_tables))]) :-
    retractall(md(_)), abolish_all_tables,
    assertz(md(1)),
    all(X, mp(X), [1]),
    assertion(all(X, mq(X), [1])),
    assertz(md(2)),
    assertion(all(X, mq(X), [1,2])),
    assertion(all(X, mp(X), [1,2])).
test(shared_thread, condition(current_prolog_flag(threads, true))) :-
    all(X, sh(X), L0),
    thread_create(all(X, sh(X), L), Id),
    thread_join(Id, Status),
    assertion(Status == true),
    assertion(L0 == [1,2,3]),
    var(L).
test(moded) :-
    all(X, mo(a, X), [3]),
    all(X, mo(a, X), [3]).
test(ssu_complete_fails, [ [F1,F2,A,M1,M2] == [true,true,true,true,true]
                          ]) :-
    abolish_all_tables,
    (\+ ssu(b) -> F1 = true ; F1 = false),
    (\+ ssu(b) -> F2 = true ; F2 = false),
    (ssu(a) -> A = true ; A = false),
    all(X, ssm(X), [a,b]),
    (\+ ssm(c) -> M1 = true ; M1 = false),
    (\+ ssm(c) -> M2 = true ; M2 = false).
test(subsumptive) :-
    all(X, su(X), [1,2,3]),
    assertion(su(2)),
    assertion(\+ su(4)).
test(retable,
     [ cleanup(abolish_all_tables)
     ]) :-
    M = test_tabled_supervisor,
    retractall(M:rt(_,_)),
    assertz(M:rt(a, 1)), assertz(M:rt(a, 3)), assertz(M:rt(a, 2)),
    compile_predicates([M:rt/2]),
    table(M:rt/2),
    assertion('$get_predicate_attribute'(M:rt(_,_), tabled_variant, 1)),
    assertion(all(Y, M:rt(a, Y), [1,2,3])),
    untable(M:rt/2),
    table(M:rt(_,max)),
    assertion(\+ '$get_predicate_attribute'(M:rt(_,_), tabled_variant, 1)),
    assertion(all(Y, M:rt(a, Y), [3])),
    assertion(all(Y, M:rt(a, Y), [3])).

"""),
]

"The file's common tail (lines `before :- ...` to the end), verbatim."
const _TT_TAIL = raw"""
"""

"The rows: `(id, unit, goal)`; the goal is the plunit test with its options folded by hand."
const _TT_CASES = [
    ("s01", "supervisor", "pu_supervisor:test(supervisor)"),
    ("s02", "supervisor", "pu_supervisor:test(fast_path)"),
    ("s03", "supervisor", "pu_supervisor:test(fast_path_shared, _)"),
    ("s04", "supervisor", "pu_supervisor:test(fast_path_nonground)"),
    ("s05", "supervisor", "pu_supervisor:test(fast_path_indirect)"),
    ("s06", "supervisor", "pu_supervisor:test(repeated_vars)"),
    ("s07", "supervisor", "pu_supervisor:test(indirect)"),
    ("s08", "supervisor", "pu_supervisor:test(compound_arg)"),
    ("s09", "supervisor", "pu_supervisor:test(attvar_arg)"),
    ("s10", "supervisor", "pu_supervisor:test(abolish_pinned)"),
    ("s11", "supervisor", "pu_supervisor:test(abolish_reuse)"),
    ("s12", "supervisor", "pu_supervisor:test(abolish_all_cache)"),
    ("s13", "supervisor", "pu_supervisor:test(thread_cache, _)"),
    ("s14", "supervisor", "pu_supervisor:test(shared_abolish, _)"),
    ("s15", "supervisor", "pu_supervisor:test(slow_path_debug)"),
    ("s16", "supervisor", "pu_supervisor:test(answers)"),
    ("s17", "supervisor", "pu_supervisor:test(partial)"),
    ("s18", "supervisor", "pu_supervisor:test(ground)"),
    ("s19", "supervisor", "pu_supervisor:test(empty)"),
    ("s20", "supervisor", "pu_supervisor:test(arity0)"),
    ("s21", "supervisor", "pu_supervisor:test(local_var)"),
    ("s22", "supervisor", "pu_supervisor:test(big)"),
    ("s23", "supervisor", "pu_supervisor:test(gc)"),
    ("s24", "supervisor", "pu_supervisor:test(no_reeval)"),
    ("s25", "supervisor", "pu_supervisor:test(wfs)"),
    ("s26", "supervisor", "setup_call_cleanup(pu_supervisor:wrap_predicate(pu_supervisor:wrapped(_), outer, W, (flag(outer, N, N+1), W)), pu_supervisor:test(outer_wrapper, _), pu_supervisor:unwrap_predicate(pu_supervisor:wrapped/1, outer))"),
    ("s27", "supervisor", "setup_call_cleanup(true, pu_supervisor:test(incremental, _), (pu_supervisor:retractall(d(_)), abolish_all_tables))"),
    ("s28", "supervisor", "setup_call_cleanup(true, pu_supervisor:test(monotonic, _), (pu_supervisor:retractall(md(_)), abolish_all_tables))"),
    ("s29", "supervisor", "pu_supervisor:test(shared_thread, _)"),
    ("s30", "supervisor", "pu_supervisor:test(moded)"),
    ("s31", "supervisor", "pu_supervisor:test(ssu_complete_fails, [Chk]), call(Chk)"),
    ("s32", "supervisor", "pu_supervisor:test(subsumptive)"),
    ("s33", "supervisor", "setup_call_cleanup(true, pu_supervisor:test(retable, _), abolish_all_tables)"),
]


"The thread-bound rows (upstream `condition(current_prolog_flag(threads, true))`): pinned on swipl; the kernel's line is compared to the pin, and a line that differs is @test_broken, never a silent pass."
const _TT_THREAD_IDS = ["s03", "s13", "s14", "s29"]
const _TT_KL = Ref{Vector{String}}(String[])


const _TT_PINNED = [
    "ok",
    "t_s01 c[116,95,115,48,49]/1(a[111,107])",
    "t_s02 c[116,95,115,48,50]/1(a[111,107])",
    "t_s03 c[116,95,115,48,51]/1(a[111,107])",
    "t_s04 c[116,95,115,48,52]/1(a[111,107])",
    "t_s05 c[116,95,115,48,53]/1(a[111,107])",
    "t_s06 c[116,95,115,48,54]/1(a[111,107])",
    "t_s07 c[116,95,115,48,55]/1(a[111,107])",
    "t_s08 c[116,95,115,48,56]/1(a[111,107])",
    "t_s09 c[116,95,115,48,57]/1(a[111,107])",
    "t_s10 c[116,95,115,49,48]/1(a[111,107])",
    "t_s11 c[116,95,115,49,49]/1(a[111,107])",
    "t_s12 c[116,95,115,49,50]/1(a[111,107])",
    "t_s13 c[116,95,115,49,51]/1(a[111,107])",
    "t_s14 c[116,95,115,49,52]/1(a[111,107])",
    "t_s15 c[116,95,115,49,53]/1(a[111,107])",
    "t_s16 c[116,95,115,49,54]/1(a[111,107])",
    "t_s17 c[116,95,115,49,55]/1(a[111,107])",
    "t_s18 c[116,95,115,49,56]/1(a[111,107])",
    "t_s19 c[116,95,115,49,57]/1(a[111,107])",
    "t_s20 c[116,95,115,50,48]/1(a[111,107])",
    "t_s21 c[116,95,115,50,49]/1(a[111,107])",
    "t_s22 c[116,95,115,50,50]/1(a[111,107])",
    "t_s23 c[116,95,115,50,51]/1(a[111,107])",
    "t_s24 c[116,95,115,50,52]/1(a[111,107])",
    "t_s25 c[116,95,115,50,53]/1(a[111,107])",
    "t_s26 c[116,95,115,50,54]/1(a[111,107])",
    "t_s27 c[116,95,115,50,55]/1(a[111,107])",
    "t_s28 c[116,95,115,50,56]/1(a[111,107])",
    "t_s29 c[116,95,115,50,57]/1(a[111,107])",
    "t_s30 c[116,95,115,51,48]/1(a[111,107])",
    "t_s31 c[116,95,115,51,49]/1(a[111,107])",
    "t_s32 c[116,95,115,51,50]/1(a[111,107])",
    "t_s33 c[116,95,115,51,51]/1(a[111,107])",
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

"The files of the program in a fresh directory: testlib, one module file per unit, the main file with the rows; returns the main file."
function _tt_materialize()::String
    d = realpath(mktempdir())
    cp(_TT_TESTLIB, joinpath(d, "tabling_testlib.pl"))
    for (short, _, text) in _TT_UNITS
        write(
            joinpath(d, "pu_$short.pl"),
            ":- module(pu_$short, []).\n:- use_module('$d/tabling_testlib').\n" * text * "\n" * _TT_TAIL
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

@testset "upstream test_tabled_supervisor.pl: the kernel answers every non-thread row as swipl does" begin
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

@testset "thread-bound: expected refusal on the kernel (upstream tests with condition(current_prolog_flag(threads, true)))" begin
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
