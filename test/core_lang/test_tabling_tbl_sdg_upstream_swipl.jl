# ORIGINAL: the UPSTREAM tests/tabling/test_tbl_sdg.pl (swipl-devel 18168e62, 10.1.20) as kernel rows (TAB1 TB8: units tbl_sdg, tbl_incomplete,
# tbl_tripwires; the restraint tripwires `max_incomplete_subgoals` and `max_scc_subgoals` of pl-tabling.c tripwire_incomplete_subgoals /
# tripwire_scc_subgoals reach tbl_pred_tripwire / tbl_wl_tripwire). One row `t_<id>(R)` per upstream unit: the body with the unit's plunit
# option folded into R (`true(...)`, `Var == Val`, `error(...)`, `fail`); `assertion/1` is defined in the program prelude as `\+ \+ G`.
#   * Every pinned line is swipl's (swipl 10.1.20, two byte-identical runs, evidence/TAB1/w1_verify.md) AND equals the answer the upstream
#     unit expects (`_TU_UPSTREAM`, the expected term run in swipl): the testset "the pins are the upstream expectations" compares both.
#   * DIVERGES from the file: the module `test_tbl_sdg` is `user` (the tripwire error names `user:ch(_)`); plunit is not used (a row folds
#     the unit's option into R); `tripwire(max_scc_subgoals, Table)`: the Table is a trie blob, the row reads its kind (`blob(T, trie)`).
#   * Left to TH1 (threads): units `hidden`, `other_thread` of tbl_sdg and `other_thread` of tbl_incomplete (`thread_create`, `call_in_thread`):
#     pinned and checked live against swipl, not run on the kernel.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.


using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TU = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tus(x) = lk_sym(_TU, Symbol(x))

_tu_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tu_enc(t::_TU, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tu_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tu_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tu_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tu_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TU_DRIVER = raw"""
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

function _tu_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TU_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


const _TU_PROGRAM = raw"""
assertion(G) :- ( \+ \+ G -> true ; throw(assertion_failed) ).

:- use_module(library(lists)).
:- use_module(library(yall)).
:- dynamic snapshot/1.
take :- '$tbl_sdg'(Components, Tables, Edges), assertz(snapshot(sdg(Components, Tables, Edges))).
sdg(Goal, Components, Tables, Edges) :-
    retractall(snapshot(_)), abolish_all_tables, ignore(Goal),
    snapshot(sdg(Cs, Ts, Es)), !, retractall(snapshot(_)),
    maplist(table_variant, Ts, Map),
    maplist(component(Cs, Map), Cs, Components0),
    maplist(table(Cs), Ts, Tables0),
    maplist(edge(Map), Es, Edges0),
    msort(Components0, Components), msort(Tables0, Tables), msort(Edges0, Edges).
table_variant(table(Trie, Variant, _, _, _), Trie-V) :- strip(Variant, V).
strip(_:G0, G) :- !, copy_term(G0, G), numbervars(G, 0, _).
strip(G, G).
component(Cs, Map, scc(SCC, _, Leader), Depth-L) :- depth(Cs, SCC, Depth), memberchk(Leader-L, Map).
depth(Cs, SCC, Depth) :- memberchk(scc(SCC, Parent, _), Cs),
    (   Parent == null -> Depth = 0 ; depth(Cs, Parent, Depth0), Depth is Depth0+1 ).
table(Cs, table(_, Variant, SCC, Answers, Flags0), table(V, Depth, Answers, Flags)) :-
    strip(Variant, V), depth(Cs, SCC, Depth), msort(Flags0, Flags).
edge(Map, edge(From, To, Sign, Count), edge(F, T, Sign, Count)) :- memberchk(From-F, Map), memberchk(To-T, Map).
:- table p/1, q/1.
p(X) :- q(X).
p(1).
q(X) :- p(X).
q(2) :- take.
:- table r/0, s/0.
r :- tnot(s).
s :- tnot(r), take.
s :- tnot(r).
:- table c1/1, c2/1.
c1(X) :- c2(X), c1(X).
c1(2).
c2(X) :- c2(X).
c2(1) :- take.
counts(Tables, SCCs) :- thread_self(Me), '$tbl_incomplete'(Me, Tables, SCCs).
:- dynamic counted/2.
count :- counts(T, S), '$tbl_sdg'(Cs, Ts, _), length(Cs, NC), length(Ts, NT), assertz(counted(T-S, NT-NC)).
counted_in(Goal, Counts) :-
    retractall(counted(_, _)), abolish_all_tables, ignore(Goal),
    findall(C-SDG, retract(counted(C, SDG)), Counts).
:- table cp/1, cq/1, cr/0, cs/0, cc1/1, cc2/1, ce/1.
cp(X) :- cq(X).
cp(1).
cq(X) :- cp(X).
cq(2) :- count.
cr :- tnot(cs).
cs :- tnot(cr), count.
cs :- tnot(cr).
cc1(X) :- cc2(X), cc1(X).
cc1(2).
cc2(X) :- cc2(X).
cc2(1) :- count.
ce(X) :- ce(X).
ce(1) :- throw(oops).
:- table ch/1, lp/1.
ch(N) :- N < 10, N1 is N+1, ch(N1).
ch(10).
lp(N) :- N < 10, N1 is N+1, lp(N1).
lp(_) :- lp(0).
with_restraint(Flag, Limit, Goal) :-
    atom_concat(Flag, '_action', ActionFlag),
    setup_call_cleanup(( set_prolog_flag(Flag, Limit), set_prolog_flag(ActionFlag, error) ),
                       Goal, set_prolog_flag(Flag, infinite)).
"""

"Left to another owner: needs `thread_create`/threads; run against swipl only."
const _TU_LEFT_PROGRAM = raw"""

:- use_module(library(thread)).
:- table a/1, b/1.
a(X) :- b(X).
b(X) :- a(X).
b(1) :- break.
in_break(Goal) :-
    open_string("take.\n", In), set_stream(In, alias(user_input)),
    open_null_stream(Null), set_stream(Null, alias(user_output)), set_stream(Null, alias(user_error)),
    call(Goal).
:- table w/1.
w(X) :- w(X).
w(1) :- thread_get_message(go).
wait_for_table(Id, Tries, Cs, Ts, Es) :-
    call_in_thread(Id, '$tbl_sdg'(Cs0, Ts0, Es0)),
    (   Ts0 \== [] ->  Cs = Cs0, Ts = Ts0, Es = Es0
    ;   Tries > 0 ->  sleep(0.1), Tries1 is Tries-1, wait_for_table(Id, Tries1, Cs, Ts, Es) ).
"""

const _TU_CASES = [
    (
        "sdg01",
        "tbl_sdg:none",
        raw"""
'$tbl_sdg'(Cs, Ts, Es), R = Cs-Ts-Es"""
    ),
    (
        "sdg02",
        "tbl_sdg:positive",
        raw"""
sdg(p(_), Cs, Ts, Es), R = r(Cs, Ts, Es)"""
    ),
    (
        "sdg03",
        "tbl_sdg:negative",
        raw"""
sdg(r, _, Ts, Es), include([edge(_,_,Sign,_)]>>(Sign == negative), Es, Neg), R = r(Ts, Neg)"""
    ),
    (
        "sdg04",
        "tbl_sdg:child",
        raw"""
sdg(c1(_), Cs, Ts, _), R = r(Cs, Ts)"""
    ),
    (
        "inc01",
        "tbl_incomplete:positive",
        raw"""
counted_in(cp(_), Counts), R = Counts"""
    ),
    (
        "inc02",
        "tbl_incomplete:negative",
        raw"""
counted_in(cr, Counts), R = Counts"""
    ),
    (
        "inc03",
        "tbl_incomplete:child",
        raw"""
counted_in(cc1(_), Counts), R = Counts"""
    ),
    (
        "inc04",
        "tbl_incomplete:completed",
        raw"""
counted_in(cp(_), _), counts(T, S), R = T-S"""
    ),
    (
        "inc05",
        "tbl_incomplete:exception",
        raw"""
abolish_all_tables, catch(ce(_), oops, true), counts(T, S), R = T-S"""
    ),
    (
        "trw01",
        "tbl_tripwires:incomplete",
        raw"""
abolish_all_tables, with_restraint(max_incomplete_subgoals, 3, ch(0)), R = no_error"""
    ),
    (
        "trw02",
        "tbl_tripwires:incomplete_below",
        raw"""
abolish_all_tables, with_restraint(max_incomplete_subgoals, 11, ch(0)), R = ok"""
    ),
    (
        "trw03",
        "tbl_tripwires:incomplete_clean",
        raw"""
abolish_all_tables, catch(with_restraint(max_incomplete_subgoals, 3, ch(0)), _, true), counts(T, S), ch(0), R = T-S"""
    ),
    (
        "trw04",
        "tbl_tripwires:scc",
        raw"""
abolish_all_tables, catch(with_restraint(max_scc_subgoals, 5, lp(0)), error(resource_error(tripwire(W, T)), _), true), ( var(W) -> R = no_error ; blob(T, trie) -> R = raised(W, trie) ; R = raised(W, other) )"""
    ),
    (
        "trw05",
        "tbl_tripwires:scc_below",
        raw"""
abolish_all_tables, ( with_restraint(max_scc_subgoals, 11, lp(0)) -> R = succeeded ; R = failed )"""
    ),
    (
        "trw06",
        "tbl_tripwires:scc_clean",
        raw"""
abolish_all_tables, catch(with_restraint(max_scc_subgoals, 5, lp(0)), _, true), counts(T, S), \+ lp(0), R = T-S"""
    ),
    (
        "trw07",
        "tbl_tripwires:flags",
        raw"""
setup_call_cleanup(( set_prolog_flag(max_scc_subgoals_action, warning), set_prolog_flag(max_scc_subgoals, 7) ), ( current_prolog_flag(max_scc_subgoals_action, Action), current_prolog_flag(max_scc_subgoals, Limit) ), ( set_prolog_flag(max_scc_subgoals_action, error), set_prolog_flag(max_scc_subgoals, infinite) )), R = Action-Limit"""
    )
]

"Left to an owner (id, upstream unit, goal, owner): pinned and live-checked, not run on the kernel."
const _TU_LEFT = [
    ("sdg05", "tbl_sdg:hidden", raw"""
sdg(( thread_create(in_break(a(_)), Id), thread_join(Id) ), _, Ts, _), R = Ts""", "TH1"),
    ("sdg06", "tbl_sdg:other_thread",
        raw"""
abolish_all_tables, thread_create(w(_), Id), wait_for_table(Id, 50, Cs, [table(_, V0, _, _, _)], Es), thread_send_message(Id, go), thread_join(Id), strip(V0, V), length(Cs, NC), Es = [edge(A, B, Sg, Ct)], ( A == B -> Same = same ; Same = diff ), R = r(NC, V, Sg, Ct, Same)""",
        "TH1"),
    ("inc06", "tbl_incomplete:other_thread",
        raw"""
abolish_all_tables, thread_create(w(_), Id), wait_for_table(Id, 50, _, _, _), '$tbl_incomplete'(Id, T, S), thread_send_message(Id, go), thread_join(Id), R = T-S""",
        "TH1")
]

const _TU_PINNED = [
    "ok",
    "t_sdg01 c[116,95,115,100,103,48,49]/1(c[45]/2(c[45]/2(nil,nil),nil))",
    "t_sdg02 c[116,95,115,100,103,48,50]/1(c[114]/3(c[91,124,93]/2(c[45]/2(i0,c[112]/1(c[36,86,65,82]/1(i0))),nil),c[91,124,93]/2(c[116,97,98,108,101]/4(c[112]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),c[91,124,93]/2(c[116,97,98,108,101]/4(c[113]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),nil)),c[91,124,93]/2(c[101,100,103,101]/4(c[113]/1(c[36,86,65,82]/1(i0)),c[112]/1(c[36,86,65,82]/1(i0)),a[112,111,115,105,116,105,118,101],i1),nil)))",
    "t_sdg03 c[116,95,115,100,103,48,51]/1(c[114]/2(c[91,124,93]/2(c[116,97,98,108,101]/4(a[114],i0,i1,c[91,124,93]/2(a[100,101,108,97,121,115],c[91,124,93]/2(a[110,101,103,97,116,105,118,101],nil))),c[91,124,93]/2(c[116,97,98,108,101]/4(a[115],i0,i1,c[91,124,93]/2(a[100,101,108,97,121,115],c[91,124,93]/2(a[110,101,103,97,116,105,118,101],c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)))),nil)),c[91,124,93]/2(c[101,100,103,101]/4(a[114],a[115],a[110,101,103,97,116,105,118,101],i1),c[91,124,93]/2(c[101,100,103,101]/4(a[115],a[114],a[110,101,103,97,116,105,118,101],i2),nil))))",
    "t_sdg04 c[116,95,115,100,103,48,52]/1(c[114]/2(c[91,124,93]/2(c[45]/2(i0,c[99,49]/1(c[36,86,65,82]/1(i0))),c[91,124,93]/2(c[45]/2(i1,c[99,50]/1(c[36,86,65,82]/1(i0))),nil)),c[91,124,93]/2(c[116,97,98,108,101]/4(c[99,49]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),c[91,124,93]/2(c[116,97,98,108,101]/4(c[99,50]/1(c[36,86,65,82]/1(i0)),i1,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),nil))))",
    "t_inc01 c[116,95,105,110,99,48,49]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i2,i1),c[45]/2(i2,i1)),nil))",
    "t_inc02 c[116,95,105,110,99,48,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i2,i1),c[45]/2(i2,i1)),nil))",
    "t_inc03 c[116,95,105,110,99,48,51]/1(c[91,124,93]/2(c[45]/2(c[45]/2(i2,i2),c[45]/2(i2,i2)),c[91,124,93]/2(c[45]/2(c[45]/2(i3,i3),c[45]/2(i3,i3)),nil)))",
    "t_inc04 c[116,95,105,110,99,48,52]/1(c[45]/2(i0,i0))",
    "t_inc05 c[116,95,105,110,99,48,53]/1(c[45]/2(i0,i0))",
    "t_trw01 c[116,95,116,114,119,48,49]/1(c[114,97,105,115,101,100]/1(c[114,101,115,111,117,114,99,101,95,101,114,114,111,114]/1(c[116,114,105,112,119,105,114,101]/2(a[109,97,120,95,105,110,99,111,109,112,108,101,116,101,95,115,117,98,103,111,97,108,115],c[58]/2(a[117,115,101,114],c[99,104]/1(V0))))))",
    "t_trw02 c[116,95,116,114,119,48,50]/1(a[111,107])",
    "t_trw03 c[116,95,116,114,119,48,51]/1(c[45]/2(i0,i0))",
    "t_trw04 c[116,95,116,114,119,48,52]/1(c[114,97,105,115,101,100]/2(a[109,97,120,95,115,99,99,95,115,117,98,103,111,97,108,115],a[116,114,105,101]))",
    "t_trw05 c[116,95,116,114,119,48,53]/1(a[102,97,105,108,101,100])",
    "t_trw06 c[116,95,116,114,119,48,54]/1(c[45]/2(i0,i0))",
    "t_trw07 c[116,95,116,114,119,48,55]/1(c[45]/2(a[119,97,114,110,105,110,103],i7))"
]

"The answer the UPSTREAM test expects, run in swipl (`x_<id>(R) :- R = Expected`), as the driver encodes it."
const _TU_UPSTREAM = [
    "c[45]/2(c[45]/2(nil,nil),nil)",
    "c[114]/3(c[91,124,93]/2(c[45]/2(i0,c[112]/1(c[36,86,65,82]/1(i0))),nil),c[91,124,93]/2(c[116,97,98,108,101]/4(c[112]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),c[91,124,93]/2(c[116,97,98,108,101]/4(c[113]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),nil)),c[91,124,93]/2(c[101,100,103,101]/4(c[113]/1(c[36,86,65,82]/1(i0)),c[112]/1(c[36,86,65,82]/1(i0)),a[112,111,115,105,116,105,118,101],i1),nil))",
    "c[114]/2(c[91,124,93]/2(c[116,97,98,108,101]/4(a[114],i0,i1,c[91,124,93]/2(a[100,101,108,97,121,115],c[91,124,93]/2(a[110,101,103,97,116,105,118,101],nil))),c[91,124,93]/2(c[116,97,98,108,101]/4(a[115],i0,i1,c[91,124,93]/2(a[100,101,108,97,121,115],c[91,124,93]/2(a[110,101,103,97,116,105,118,101],c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)))),nil)),c[91,124,93]/2(c[101,100,103,101]/4(a[114],a[115],a[110,101,103,97,116,105,118,101],i1),c[91,124,93]/2(c[101,100,103,101]/4(a[115],a[114],a[110,101,103,97,116,105,118,101],i2),nil)))",
    "c[114]/2(c[91,124,93]/2(c[45]/2(i0,c[99,49]/1(c[36,86,65,82]/1(i0))),c[91,124,93]/2(c[45]/2(i1,c[99,50]/1(c[36,86,65,82]/1(i0))),nil)),c[91,124,93]/2(c[116,97,98,108,101]/4(c[99,49]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),c[91,124,93]/2(c[116,97,98,108,101]/4(c[99,50]/1(c[36,86,65,82]/1(i0)),i1,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),nil)))",
    "c[91,124,93]/2(c[45]/2(c[45]/2(i2,i1),c[45]/2(i2,i1)),nil)",
    "c[91,124,93]/2(c[45]/2(c[45]/2(i2,i1),c[45]/2(i2,i1)),nil)",
    "c[91,124,93]/2(c[45]/2(c[45]/2(i2,i2),c[45]/2(i2,i2)),c[91,124,93]/2(c[45]/2(c[45]/2(i3,i3),c[45]/2(i3,i3)),nil))",
    "c[45]/2(i0,i0)",
    "c[45]/2(i0,i0)",
    "c[114,97,105,115,101,100]/1(c[114,101,115,111,117,114,99,101,95,101,114,114,111,114]/1(c[116,114,105,112,119,105,114,101]/2(a[109,97,120,95,105,110,99,111,109,112,108,101,116,101,95,115,117,98,103,111,97,108,115],c[58]/2(a[117,115,101,114],c[99,104]/1(V0)))))",
    "a[111,107]",
    "c[45]/2(i0,i0)",
    "c[114,97,105,115,101,100]/2(a[109,97,120,95,115,99,99,95,115,117,98,103,111,97,108,115],a[116,114,105,101])",
    "a[102,97,105,108,101,100]",
    "c[45]/2(i0,i0)",
    "c[45]/2(a[119,97,114,110,105,110,103],i7)"
]

const _TU_LEFT_PINNED = [
    "t_sdg05 c[116,95,115,100,103,48,53]/1(c[91,124,93]/2(c[116,97,98,108,101]/4(c[97]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),c[91,124,93]/2(c[116,97,98,108,101]/4(c[98]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),nil)))",
    "t_sdg06 c[116,95,115,100,103,48,54]/1(c[114]/5(i1,c[119]/1(c[36,86,65,82]/1(i0)),a[112,111,115,105,116,105,118,101],i1,a[115,97,109,101]))",
    "t_inc06 c[116,95,105,110,99,48,54]/1(c[45]/2(i1,i1))"
]

const _TU_LEFT_UPSTREAM = [
    "c[91,124,93]/2(c[116,97,98,108,101]/4(c[97]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),c[91,124,93]/2(c[116,97,98,108,101]/4(c[98]/1(c[36,86,65,82]/1(i0)),i0,i0,c[91,124,93]/2(a[112,101,110,100,105,110,103],nil)),nil))",
    "c[114]/5(i1,c[119]/1(c[36,86,65,82]/1(i0)),a[112,111,115,105,116,105,118,101],i1,a[115,97,109,101])",
    "c[45]/2(i1,i1)"
]

"The program text with the cases appended."
_tu_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- ( catch(($g), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n"
        for (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tu_load(program::String)
    f = joinpath(mktempdir(), "tabling_upstream.pl")
    write(f, _tu_text(program, [(id, g) for (id, _, g) in _TU_CASES]))
    gd = LK.PL_global_data{_TU}()
    ld = LK.PL_local_data{_TU}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tu_enc(ball::_TU))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tu_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tus(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TU, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _tu_enc(mk_expr(_TU, _TU[_tus(pred), lk_answers(ld, (a:a)...)...])))
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


"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_TU_UPSTREAM` holds it."
function _tu_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_tu_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "upstream test_tbl_sdg.pl: the subgoal dependency graph, the incomplete counts, the tripwires" begin
    gd, ld, st = _tu_load(_TU_PROGRAM)
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TU_CASES
        push!(kl, _tu_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TU_PINNED)
    for (k, pn) in zip(kl, _TU_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _tu_corrupt(_TU_PINNED[2])
end

@testset "the pins are the upstream expectations (no swipl needed)" begin
    @test length(_TU_PINNED) == length(_TU_CASES) + 1
    @test length(_TU_UPSTREAM) == length(_TU_CASES)
    @test !isempty(_TU_UPSTREAM) && all(!isempty, _TU_UPSTREAM)
    for (pn, up) in zip(_TU_PINNED[2:end], _TU_UPSTREAM)
        @test _tu_answer(pn) == up
    end
    @test length(_TU_LEFT_PINNED) == length(_TU_LEFT) == length(_TU_LEFT_UPSTREAM)
    for (pn, up) in zip(_TU_LEFT_PINNED, _TU_LEFT_UPSTREAM)
        @test _tu_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _tu_answer(_tu_corrupt(_TU_PINNED[2])) != _TU_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f = joinpath(mktempdir(), "ts_upstream_swipl.pl")
        all_cases = vcat(
            [(id, g) for (id, _, g) in _TU_CASES], [(id, g) for (id, _, g, _) in _TU_LEFT]
        )
        write(f, _tu_text(_TU_PROGRAM * _TU_LEFT_PROGRAM, all_cases))
        got = _tu_swipl_lines(f, ["t_$id" for (id, _) in all_cases])
        @test !isempty(got) && got == vcat(_TU_PINNED, _TU_LEFT_PINNED)
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _tu_corrupt(_TU_PINNED[2])
    end
end
