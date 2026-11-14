# ORIGINAL: the UPSTREAM tests/tabling/test_abstract_completion.pl (swipl-devel 18168e62, 10.1.20) as kernel rows (TAB1 TB8: the completion
# of recursive `subgoal_abstract(0)` and `subsumptive` tables with the flag `max_table_subgoal_size_action` = `abstract`: get_answer_table's
# retry after tbl_pred_tripwire, site 3 of TB8). One row `t_<id>(R)` per upstream unit (first_bound, second_bound, both_bound, deep_bound,
# none_bound, open_answers, node_shapes, random_shapes, bound_read, subsumptive, undefined): the unit's `forall(seed(S))` (seeds 1..8,
# random_shapes 1..64) is folded into one list `[equal, ...]`, one element per seed, `equal` where `Abstract == Variant` held AND the relation is non-empty.
#   * Every pinned line is swipl's (swipl 10.1.20, two byte-identical runs, evidence/TAB1/w1_verify.md) AND equals the answer the upstream
#     unit expects (`_TA_UPSTREAM`: all `equal`): the testset "the pins are the upstream expectations" compares both.
#   * DIVERGES from the file: the module `test_abstract_completion` is `user`; plunit is not used (the group's setup/cleanup is
#     `with_abstract/1`); the random graphs are NOT regenerated: upstream's `graph(Seed)` (set_random(seed(Seed)), random_between/3) is
#     replaced by the graphs it draws, dumped from the pinned swipl into test_tabling_abstract_graphs.pl (`gdata/5`, seeds 1..64);
#     the non-emptiness of the compared relations is an addition (a guard that cannot pass on two empty answers).
#   * Nothing is left to another owner by design: a kernel answer other than `equal` names the tabling feature that is missing.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.


using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TA = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tas(x) = lk_sym(_TA, Symbol(x))

_ta_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _ta_enc(t::_TA, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ta_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ta_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ta_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ta_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TA_DRIVER = raw"""
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

function _ta_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TA_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


const _TA_PROGRAM = replace(
    raw"""
assertion(G) :- ( \+ \+ G -> true ; throw(assertion_failed) ).

:- use_module(library(lists)).
:- use_module(library(wfs)).
:- ensure_loaded('@GRAPHFILE@').
:- dynamic edge/2, hub/1, loop/1, link/2, node_term/2, term_link/2.

:- table path/1 as subgoal_abstract(0).
:- table rpath/1 as subgoal_abstract(0).
:- table mpath/1 as subgoal_abstract(0).
:- table dpath/1 as subgoal_abstract(0).
:- table hpath/1 as subgoal_abstract(0).
:- table wpath/1 as subgoal_abstract(0).
:- table xpath/1 as subgoal_abstract(0).
:- table tpath/1 as subgoal_abstract(0).
:- table upath/1 as subgoal_abstract(0).
:- table spath/2 as subsumptive.
:- table vpath/2, vrpath/2, vhpath/2, vwpath/2, vxpath/2, vtpath/2, vupath/2.

path(args(X, Y)) :- edge(X, Y).
path(args(X, Z)) :- edge(X, Y), path(args(Y, Z)).      % binds the first

rpath(args(X, Y)) :- edge(X, Y).
rpath(args(X, Z)) :- edge(Y, Z), rpath(args(X, Y)).    % binds the second

mpath(args(X, Y)) :- edge(X, Y).
mpath(args(X, Z)) :- edge(X, Y), mpath(args(Y, Z)).    % binds the first
mpath(args(X, Z)) :- edge(Y, Z), mpath(args(X, Y)).    % and the second

dpath(args(n(X), n(Y))) :- edge(X, Y).
dpath(args(n(X), n(Z))) :- edge(X, Y), dpath(args(n(Y), n(Z))).

hpath(args(X, Y)) :- edge(X, Y).
hpath(args(X, Z)) :- edge(X, Y), hpath(args(Y, Z)).
hpath(args(X, Z)) :- hub(X), hpath(args(_, Z)).        % binds neither

wpath(args(X, Y)) :- edge(X, Y).
wpath(args(X, _)) :- hub(X).                            % open at the second
wpath(args(X, Z)) :- edge(Y, Z), wpath(args(X, Y)).

xpath(args(X, Y)) :- link(X, Y).
xpath(args(X, Z)) :- link(X, Y), xpath(args(Y, Z)).

tpath(args(X, Y)) :- term_link(X, Y).
tpath(args(X, Z)) :- term_link(X, Y), tpath(args(Y, Z)).

upath(args(X, Y)) :- edge(X, Y).
upath(args(X, Z)) :- edge(X, Y), upath(args(Y, Z)).
upath(args(X, X)) :- loop(X), undefined.

spath(X, Y) :- edge(X, Y).
spath(X, Z) :- edge(X, Y), spath(Y, Z).                 % a subsumed call

vpath(X, Y) :- edge(X, Y).
vpath(X, Z) :- edge(X, Y), vpath(Y, Z).

vrpath(X, Y) :- edge(X, Y).
vrpath(X, Z) :- edge(Y, Z), vrpath(X, Y).

vhpath(X, Y) :- edge(X, Y).
vhpath(X, Z) :- edge(X, Y), vhpath(Y, Z).
vhpath(X, Z) :- hub(X), vhpath(_, Z).

vwpath(X, Y) :- edge(X, Y).
vwpath(X, _) :- hub(X).
vwpath(X, Z) :- edge(Y, Z), vwpath(X, Y).

vxpath(X, Y) :- link(X, Y).
vxpath(X, Z) :- link(X, Y), vxpath(Y, Z).

vtpath(X, Y) :- term_link(X, Y).
vtpath(X, Z) :- term_link(X, Y), vtpath(Y, Z).

vupath(X, Y) :- edge(X, Y).
vupath(X, Z) :- edge(X, Y), vupath(Y, Z).
vupath(X, X) :- loop(X), undefined.

abstract_subgoals :-
    current_prolog_flag(max_table_subgoal_size_action, Action),
    nb_setval(abstract_completion_action, Action),
    set_prolog_flag(max_table_subgoal_size_action, abstract).

restore_subgoal_action :-
    nb_getval(abstract_completion_action, Action),
    set_prolog_flag(max_table_subgoal_size_action, Action).

with_abstract(Goal) :-
    setup_call_cleanup(abstract_subgoals, Goal, restore_subgoal_action).

% graph(+Seed): upstream's graph/1 reads its random graph from gdata/5 (pinned from swipl 10.1.20; see the data file).
graph(Seed) :-
    abolish_all_tables,
    retractall(edge(_,_)),
    retractall(hub(_)),
    retractall(loop(_)),
    retractall(link(_,_)),
    retractall(node_term(_,_)),
    retractall(term_link(_,_)),
    gdata(Seed, Edges, Hubs, Loops, NodeTerms),
    forall(member(X-Y, Edges),
           ( assertz(edge(X, Y)),
             shape(X, SX),
             shape(Y, SY),
             assertz(link(SX, SY)) )),
    forall(member(H, Hubs), assertz(hub(H))),
    forall(member(L, Loops), assertz(loop(L))),
    forall(member(N-T, NodeTerms), assertz(node_term(N, T))),
    forall(edge(X, Y),
           ( node_term(X, TX), node_term(Y, TY), assertz(term_link(TX, TY)) )).

shape(N, k(k(k(k(N))))) :- N mod 7 =:= 0, !.
shape(N, N) :- N mod 5 =:= 0, !.
shape(N, n(N)).

pairs(Template, Goal, Pairs) :-
    findall(Template, Goal, List),
    sort(List, Pairs).

node_pairs(Goal, X, Y, Pairs) :-
    pairs(X-Y, ( Goal, between(1, 30, X), between(1, 30, Y) ), Pairs).

truth(true, true) :- !.
truth(_, undefined).

% The plunit option `true(Abstract == Variant)`: `equal`; the row also needs a non-empty relation, else `differ`.
verdict(A, V, Res) :- ( A == V, A \== [] -> Res = equal ; Res = differ ).

seed_results(Seeds, Pred, R) :-
    findall(Res, ( member(S, Seeds), ( call(Pred, S, Res0) -> Res = Res0 ; Res = failed ) ), R).

ac_first_bound(Seed, Res) :-
    graph(Seed),
    pairs(X-Y, path(args(X, Y)), Abstract),
    pairs(X-Y, vpath(X, Y), Variant),
    verdict(Abstract, Variant, Res).
ac_second_bound(Seed, Res) :-
    graph(Seed),
    pairs(X-Y, rpath(args(X, Y)), Abstract),
    pairs(X-Y, vrpath(X, Y), Variant),
    verdict(Abstract, Variant, Res).
ac_both_bound(Seed, Res) :-
    graph(Seed),
    pairs(X-Y, mpath(args(X, Y)), Abstract),
    pairs(X-Y, vpath(X, Y), Variant),
    verdict(Abstract, Variant, Res).
ac_deep_bound(Seed, Res) :-
    graph(Seed),
    pairs(X-Y, dpath(args(n(X), n(Y))), Abstract),
    pairs(X-Y, vpath(X, Y), Variant),
    verdict(Abstract, Variant, Res).
ac_none_bound(Seed, Res) :-
    graph(Seed),
    pairs(X-Y, hpath(args(X, Y)), Abstract),
    pairs(X-Y, vhpath(X, Y), Variant),
    verdict(Abstract, Variant, Res).
ac_open_answers(Seed, Res) :-
    graph(Seed),
    node_pairs(wpath(args(X, Y)), X, Y, Abstract),
    node_pairs(vwpath(X, Y), X, Y, Variant),
    verdict(Abstract, Variant, Res).
ac_node_shapes(Seed, Res) :-
    graph(Seed),
    pairs(X-Y, xpath(args(X, Y)), Abstract),
    pairs(X-Y, vxpath(X, Y), Variant),
    verdict(Abstract, Variant, Res).
ac_random_shapes(Seed, Res) :-
    graph(Seed),
    pairs(X-Y, tpath(args(X, Y)), Abstract),
    pairs(X-Y, vtpath(X, Y), Variant),
    verdict(Abstract, Variant, Res).
ac_bound_read(Seed, Res) :-
    graph(Seed),
    pairs(X-Y, ( between(1, 30, X), path(args(X, Y)) ), Abstract),
    pairs(X-Y, vpath(X, Y), Variant),
    verdict(Abstract, Variant, Res).
ac_subsumptive(Seed, Res) :-
    graph(Seed),
    pairs(X-Y, spath(X, Y), Subsumptive),
    pairs(X-Y, vpath(X, Y), Variant),
    verdict(Subsumptive, Variant, Res).
ac_undefined(Seed, Res) :-
    graph(Seed),
    pairs(X-Y-T, ( call_delays(upath(args(X, Y)), D), truth(D, T) ), Abstract),
    pairs(X-Y-T, ( call_delays(vupath(X, Y), D), truth(D, T) ), Variant),
    verdict(Abstract, Variant, Res).
""", "@GRAPHFILE@" => joinpath(@__DIR__, "test_tabling_abstract_graphs.pl"))

const _TA_LEFT_PROGRAM = ""

const _TA_CASES = [
    (
        "ac01",
        "abstract_completion:first_bound",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_first_bound, R) ))"""
    ),
    (
        "ac02",
        "abstract_completion:second_bound",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_second_bound, R) ))"""
    ),
    (
        "ac03",
        "abstract_completion:both_bound",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_both_bound, R) ))"""
    ),
    (
        "ac04",
        "abstract_completion:deep_bound",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_deep_bound, R) ))"""
    ),
    (
        "ac05",
        "abstract_completion:none_bound",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_none_bound, R) ))"""
    ),
    (
        "ac06",
        "abstract_completion:open_answers",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_open_answers, R) ))"""
    ),
    (
        "ac07",
        "abstract_completion:node_shapes",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_node_shapes, R) ))"""
    ),
    (
        "ac08",
        "abstract_completion:random_shapes",
        raw"""
with_abstract(( numlist(1, 64, Seeds), seed_results(Seeds, ac_random_shapes, R) ))"""
    ),
    (
        "ac09",
        "abstract_completion:bound_read",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_bound_read, R) ))"""
    ),
    (
        "ac10",
        "abstract_completion:subsumptive",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_subsumptive, R) ))"""
    ),
    (
        "ac11",
        "abstract_completion:undefined",
        raw"""
with_abstract(( numlist(1, 8, Seeds), seed_results(Seeds, ac_undefined, R) ))"""
    )
]

const _TA_LEFT = Tuple{String, String, String, String}[]

const _TA_PINNED = [
    "ok",
    "t_ac01 c[116,95,97,99,48,49]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))",
    "t_ac02 c[116,95,97,99,48,50]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))",
    "t_ac03 c[116,95,97,99,48,51]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))",
    "t_ac04 c[116,95,97,99,48,52]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))",
    "t_ac05 c[116,95,97,99,48,53]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))",
    "t_ac06 c[116,95,97,99,48,54]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))",
    "t_ac07 c[116,95,97,99,48,55]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))",
    "t_ac08 c[116,95,97,99,48,56]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))",
    "t_ac09 c[116,95,97,99,48,57]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))",
    "t_ac10 c[116,95,97,99,49,48]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))",
    "t_ac11 c[116,95,97,99,49,49]/1(c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil)))))))))"
]

"The answer the UPSTREAM test expects, run in swipl (`x_<id>(R) :- R = Expected`), as the driver encodes it."
const _TA_UPSTREAM = [
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))",
    "c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],c[91,124,93]/2(a[101,113,117,97,108],nil))))))))"
]

const _TA_LEFT_PINNED = String[]

const _TA_LEFT_UPSTREAM = String[]

"The program text with the cases appended."
_ta_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- ( catch(($g), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n"
        for (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _ta_load(program::String)
    f = joinpath(mktempdir(), "tabling_upstream.pl")
    write(f, _ta_text(program, [(id, g) for (id, _, g) in _TA_CASES]))
    gd = LK.PL_global_data{_TA}()
    ld = LK.PL_local_data{_TA}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _ta_enc(ball::_TA))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _ta_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tas(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TA, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _ta_enc(mk_expr(_TA, _TA[_tas(pred), lk_answers(ld, (a:a)...)...])))
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


"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_TA_UPSTREAM` holds it."
function _ta_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_ta_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "upstream test_abstract_completion.pl: completion of abstracted and subsumptive tables against variant tables" begin
    gd, ld, st = _ta_load(_TA_PROGRAM)
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TA_CASES
        push!(kl, _ta_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TA_PINNED)
    for (k, pn) in zip(kl, _TA_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _ta_corrupt(_TA_PINNED[2])
end

@testset "the pins are the upstream expectations (no swipl needed)" begin
    @test length(_TA_PINNED) == length(_TA_CASES) + 1
    @test length(_TA_UPSTREAM) == length(_TA_CASES)
    @test !isempty(_TA_UPSTREAM) && all(!isempty, _TA_UPSTREAM)
    for (pn, up) in zip(_TA_PINNED[2:end], _TA_UPSTREAM)
        @test _ta_answer(pn) == up
    end
    @test length(_TA_LEFT_PINNED) == length(_TA_LEFT) == length(_TA_LEFT_UPSTREAM)
    for (pn, up) in zip(_TA_LEFT_PINNED, _TA_LEFT_UPSTREAM)
        @test _ta_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _ta_answer(_ta_corrupt(_TA_PINNED[2])) != _TA_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f = joinpath(mktempdir(), "ts_upstream_swipl.pl")
        all_cases = vcat(
            [(id, g) for (id, _, g) in _TA_CASES], [(id, g) for (id, _, g, _) in _TA_LEFT]
        )
        write(f, _ta_text(_TA_PROGRAM * _TA_LEFT_PROGRAM, all_cases))
        got = _ta_swipl_lines(f, ["t_$id" for (id, _) in all_cases])
        @test !isempty(got) && got == vcat(_TA_PINNED, _TA_LEFT_PINNED)
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _ta_corrupt(_TA_PINNED[2])
    end
end
