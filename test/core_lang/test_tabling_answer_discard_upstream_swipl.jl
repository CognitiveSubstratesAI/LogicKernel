# ORIGINAL: the UPSTREAM tests/tabling/test_answer_discard.pl (swipl-devel 18168e62, 10.1.20) as kernel rows (TAB1 TB8: lazy compilation and
# discarding of answer tries: the flag `table_compile_threshold`, `compiled_size`/`node_count`/`value_count` of `trie_property/2`,
# `trie_gen/2` and `trie_lookup/3` on a discarded trie; moded, subsumptive, incremental and conditional tables; they reach the answer
# restraints' neighbours in tbl_add_answer and `table_complete_all`). One row `t_<id>(R)` per upstream unit (23): the body with the unit's
# plunit option folded into R (`Compiled == false`, `N == 1`, `L == L0` as `equal`, `true(N > 1)`, no option as `ok`).
#   * Every pinned line is swipl's (swipl 10.1.20, two byte-identical runs, evidence/TAB1/w1_verify.md) AND equals the answer the upstream
#     unit expects (`_TZ_UPSTREAM`): the testset "the pins are the upstream expectations" compares both.
#   * DIVERGES from the file: the module `test_answer_discard` is `user`; plunit is not used; `L == L0` rows also need `L0 \== []`.
#   * Left to TH1 (threads; the units use `condition(threads)`): `flag_inherit`, `flag_thread_local`, `shared`. Left to GC (atom garbage
#     collection: `garbage_collect_atoms/0`, `current_atom/1`, `set_prolog_gc_thread/1`, `garbage_collect_clauses/0`): `atom_gc`,
#     `atom_keep_discarded`, `atom_keep_deep`, `atom_keep_reeval`. Pinned and checked live against swipl, not run on the kernel.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.


using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TZ = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tzs(x) = lk_sym(_TZ, Symbol(x))

_tz_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tz_enc(t::_TZ, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tz_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tz_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tz_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tz_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TZ_DRIVER = raw"""
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

function _tz_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TZ_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


const _TZ_PROGRAM = raw"""
assertion(G) :- ( \+ \+ G -> true ; throw(assertion_failed) ).

:- use_module(library(lists)).
:- use_module(library(debug)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module(library(wfs)).
:- meta_predicate
    all(?, 0, -).

all(T, G, L) :- findall(T, G, L0), msort(L0, L).

answer_trie(G, T) :-                    % enumerate: also finds shared
    current_table(user:V, T),
    V =@= G,
    !.

nodes(G, N) :-
    answer_trie(G, T),
    trie_property(T, node_count(N)).

compiled(G) :-
    answer_trie(G, T),
    trie_property(T, compiled_size(_)).

call_twice(G, L) :-
    all(G, user:G, _),
    all(G, user:G, L).

add_d(X) :- assertz(d(X)).
del_d(X) :- retract(d(X)).

:- table p/1, mix/1, ng/1, tz/0, tp/0, gen/1, deep/1.
p(X) :- between(1, 100, X).
mix(X) :- member(X, [a, 1, 1.5, "str", 100000000000000000000, f(a,g(b)),
                     [x,y], -3]).
ng(X) :- member(X, [f(_), g(_,_), h(A,A)]).
tz :- fail.
tp.
gen(X) :- between(1, 1000, I), atom_concat(discard_test_, I, X).
deep(L) :- numlist(1, 100, L).

with_compile_threshold(N, G) :-
    current_prolog_flag(table_compile_threshold, Old),
    setup_call_cleanup(
        set_prolog_flag(table_compile_threshold, N),
        G,
        set_prolog_flag(table_compile_threshold, Old)).

:- table und/1, und0/0.
und(X) :- member(X, [1,2]), tnot(und0).
und0 :- tnot(und0).

:- dynamic([d/1], [incremental(true)]).
:- table ip/1 as incremental.
d(1).
ip(X) :- d(X).

:- table mo(_,max).
mo(a, 1).
mo(a, 3).
mo(a, 2).

:- table su/1 as subsumptive.
su(X) :- between(1, 10, X).
"""

"Left to another owner: needs `thread_create`/threads; run against swipl only."
const _TZ_LEFT_PROGRAM = raw"""

% threads (TH1) and atom GC (GC): live against swipl only
threads :-
    current_prolog_flag(threads, true).
thread_join_true(G) :-
    thread_create(G, Id),
    thread_join(Id, Status),
    Status == true.
:- table ga/1, gal/1.
:- table gi/1 as incremental.
:- dynamic([di/1], [incremental(true)]).
ga(X) :- between(1, 1000, I), atom_concat(borrow_a_, I, X).
gal(L) :- findall(X, (between(1, 100, I), atom_concat(borrow_l_, I, X)), L).
gi(X) :- di(I), atom_concat(borrow_i_, I, X).
atom_count(Prefix, N) :-
    garbage_collect_atoms,
    aggregate_all(count,
                  ( current_atom(A),
                    sub_atom(A, 0, _, After, Prefix),
                    After > 0
                  ), N).
set_di(N) :- retractall(di(_)), forall(between(1, N, I), assertz(di(I))).
add_di(I) :- assertz(di(I)).
stop_gc_thread(Old) :-
    current_prolog_flag(gc_thread, Old),
    set_prolog_gc_thread(false).
abolish_and_gc :-
    abolish_all_tables,
    assertz(di(-1)), retract(di(-1)),
    garbage_collect_clauses.
ga_ok :-
    findall(X, ga(X), L),
    length(L, 1000),
    forall(member(X, L), sub_atom(X, 0, _, _, borrow_a_)).
:- table sh/1 as shared.
sh(X) :- between(1, 10, X).
"""

const _TZ_CASES = [
    (
        "ad01",
        "answer_discard:lazy",
        raw"""
abolish_all_tables, all(X, p(X), L), assertion(length(L, 100)), ( compiled(p(_)) -> Compiled = true ; Compiled = false ), R = Compiled"""
    ),
    (
        "ad02",
        "answer_discard:lazy_deep",
        raw"""
abolish_all_tables, all(X, deep(X), [_]), nodes(deep(_), N), R = N"""
    ),
    (
        "ad03",
        "answer_discard:lazy_deep_flag",
        raw"""
abolish_all_tables, with_compile_threshold(1000000, all(X, deep(X), [_])), ( compiled(deep(_)) -> Compiled = true ; Compiled = false ), R = Compiled"""
    ),
    (
        "ad04",
        "answer_discard:lazy_flag_zero",
        raw"""
abolish_all_tables, with_compile_threshold(0, all(X, p(X), L)), assertion(length(L, 100)), nodes(p(_), N), R = N"""
    ),
    (
        "ad07",
        "answer_discard:discard",
        raw"""
abolish_all_tables, call_twice(p(_), L), assertion(length(L, 100)), answer_trie(p(_), T), assertion(trie_property(T, value_count(100))), nodes(p(_), N), all(p(X), p(X), L2), assertion(L2 == L), R = N"""
    ),
    (
        "ad08",
        "answer_discard:restore",
        raw"""
abolish_all_tables, call_twice(p(_), L0), answer_trie(p(_), T), all(p(X), trie_gen(T, ret(X)), L), assertion(trie_property(T, value_count(100))), nodes(p(_), N), assertion(N > 1), all(p(X), p(X), L2), assertion(L2 == L0), ( L == L0, L0 \== [] -> R = equal ; R = differ )"""
    ),
    (
        "ad09",
        "answer_discard:restore_lookup",
        raw"""
abolish_all_tables, call_twice(p(_), _), answer_trie(p(_), T), assertion(trie_lookup(T, ret(42), _)), assertion(\+ trie_lookup(T, ret(142), _)), R = ok"""
    ),
    (
        "ad10",
        "answer_discard:kinds",
        raw"""
abolish_all_tables, all(X, mix(X), L0), call_twice(mix(_), _), assertion(nodes(mix(_), 1)), all(X, mix(X), L1), assertion(L1 == L0), answer_trie(mix(_), T), all(X, trie_gen(T, ret(X)), L), ( L == L0, L0 \== [] -> R = equal ; R = differ )"""
    ),
    (
        "ad11",
        "answer_discard:nonground",
        raw"""
abolish_all_tables, call_twice(ng(_), _), assertion(nodes(ng(_), 1)), findall(X, ng(X), L), assertion(length(L, 3)), memberchk(h(A,B), L), assertion(A == B), R = ok"""
    ),
    (
        "ad13",
        "answer_discard:tnot",
        raw"""
abolish_all_tables, call_twice(tz, _), call_twice(tp, _), assertion(tnot(tz)), assertion(\+ tnot(tp)), R = ok"""
    ),
    (
        "ad14",
        "answer_discard:abolish",
        raw"""
abolish_all_tables, call_twice(p(_), L0), abolish_all_tables, all(p(X), p(X), L), ( L == L0, L0 \== [] -> R = equal ; R = differ )"""
    ),
    (
        "ad15",
        "answer_discard:conditional",
        raw"""
abolish_all_tables, call_twice(und(_), _), nodes(und(_), N), call_delays(und(1), Delays), assertion(Delays \== true), ( N > 1 -> R = ok ; R = bad(N) )"""
    ),
    (
        "ad16",
        "answer_discard:incremental",
        raw"""
abolish_all_tables, call_twice(ip(_), _), nodes(ip(_), N), assertion(N > 1), add_d(2), all(X, ip(X), L), del_d(2), R = L"""
    ),
    (
        "ad17",
        "answer_discard:incremental_single",
        raw"""
abolish_all_tables, call_twice(ip(_), _), ( compiled(ip(_)) -> C1 = true ; C1 = false ), ip(X), deterministic(Det), add_d(2), call_twice(ip(_), L), ( compiled(ip(_)) -> C2 = true ; C2 = false ), del_d(2), call_twice(ip(_), [ip(1)]), R = r(C1, X, Det, L, C2)"""
    ),
    (
        "ad19",
        "answer_discard:moded",
        raw"""
abolish_all_tables, call_twice(mo(_,_), _), nodes(mo(_,_), N), assertion(N > 1), all(X-Y, mo(X,Y), L), R = L"""
    ),
    (
        "ad20",
        "answer_discard:subsumptive",
        raw"""
abolish_all_tables, call_twice(su(_), _), nodes(su(_), N), assertion(N > 1), all(su(3), su(3), L), R = L"""
    )
]

"Left to an owner (id, upstream unit, goal, owner): pinned and live-checked, not run on the kernel."
const _TZ_LEFT = [
    ("ad05", "answer_discard:flag_inherit",
        raw"""
threads, with_compile_threshold(1000000, thread_join_true(( all(X, deep(X), [_]), \+ compiled(deep(_)) ))), R = ok""",
        "TH1"),
    ("ad06", "answer_discard:flag_thread_local",
        raw"""
threads, current_prolog_flag(table_compile_threshold, Old), thread_join_true(set_prolog_flag(table_compile_threshold, 7)), current_prolog_flag(table_compile_threshold, V), ( V == Old -> R = same ; R = changed )""",
        "TH1"),
    ("ad12", "answer_discard:atom_gc",
        raw"""
abolish_all_tables, findall(X, (between(1, 1000, I), atom_concat(discard_test_, I, X)), L0), \+ \+ call_twice(gen(_), _), assertion(nodes(gen(_), 1)), garbage_collect_atoms, findall(X, gen(X), L), ( L == L0, L0 \== [] -> R = equal ; R = differ )""",
        "GC"),
    ("ad18", "answer_discard:shared",
        raw"""
threads, abolish_all_tables, call_twice(sh(_), _), call_twice(sh(_), _), nodes(sh(_), N), ( N > 1 -> R = ok ; R = bad(N) )""",
        "TH1"),
    ("ad21", "answer_discard:atom_keep_discarded",
        raw"""
setup_call_cleanup(stop_gc_thread(Old), ( abolish_and_gc, \+ \+ call_twice(ga(_), _), assertion(nodes(ga(_), 1)), atom_count(borrow_a_, N), assertion(N == 1000), assertion(ga_ok), abolish_and_gc, atom_count(borrow_a_, N1), assertion(N1 == 0) ), set_prolog_gc_thread(Old)), R = ok""",
        "GC"),
    ("ad22", "answer_discard:atom_keep_deep",
        raw"""
setup_call_cleanup(stop_gc_thread(Old), ( abolish_and_gc, \+ \+ gal(_), assertion(nodes(gal(_), 1)), atom_count(borrow_l_, N), assertion(N == 100), \+ \+ ( gal(L), length(L, 100) ), abolish_and_gc, atom_count(borrow_l_, N1), assertion(N1 < 10) ), set_prolog_gc_thread(Old)), R = ok""",
        "GC"),
    ("ad23", "answer_discard:atom_keep_reeval",
        raw"""
setup_call_cleanup(stop_gc_thread(Old), ( abolish_and_gc, set_di(200), \+ \+ call_twice(gi(_), _), add_di(201), \+ \+ call_twice(gi(_), _), abolish_and_gc, set_di(0), atom_count(borrow_i_, N0), assertion(N0 == 0), set_di(200), \+ \+ call_twice(gi(_), _), add_di(201), garbage_collect_clauses, atom_count(borrow_i_, N), assertion(N == 200), \+ \+ ( findall(X, gi(X), L), length(L, 201) ), set_di(0), abolish_and_gc, atom_count(borrow_i_, N1), assertion(N1 == 0) ), set_prolog_gc_thread(Old)), R = ok""",
        "GC")
]

const _TZ_PINNED = [
    "ok",
    "t_ad01 c[116,95,97,100,48,49]/1(a[102,97,108,115,101])",
    "t_ad02 c[116,95,97,100,48,50]/1(i1)",
    "t_ad03 c[116,95,97,100,48,51]/1(a[102,97,108,115,101])",
    "t_ad04 c[116,95,97,100,48,52]/1(i1)",
    "t_ad07 c[116,95,97,100,48,55]/1(i1)",
    "t_ad08 c[116,95,97,100,48,56]/1(a[101,113,117,97,108])",
    "t_ad09 c[116,95,97,100,48,57]/1(a[111,107])",
    "t_ad10 c[116,95,97,100,49,48]/1(a[101,113,117,97,108])",
    "t_ad11 c[116,95,97,100,49,49]/1(a[111,107])",
    "t_ad13 c[116,95,97,100,49,51]/1(a[111,107])",
    "t_ad14 c[116,95,97,100,49,52]/1(a[101,113,117,97,108])",
    "t_ad15 c[116,95,97,100,49,53]/1(a[111,107])",
    "t_ad16 c[116,95,97,100,49,54]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_ad17 c[116,95,97,100,49,55]/1(c[114]/5(a[102,97,108,115,101],i1,a[116,114,117,101],c[91,124,93]/2(c[105,112]/1(i1),c[91,124,93]/2(c[105,112]/1(i2),nil)),a[116,114,117,101]))",
    "t_ad19 c[116,95,97,100,49,57]/1(c[91,124,93]/2(c[45]/2(a[97],i3),nil))",
    "t_ad20 c[116,95,97,100,50,48]/1(c[91,124,93]/2(c[115,117]/1(i3),nil))"
]

"The answer the UPSTREAM test expects, run in swipl (`x_<id>(R) :- R = Expected`), as the driver encodes it."
const _TZ_UPSTREAM = [
    "a[102,97,108,115,101]",
    "i1",
    "a[102,97,108,115,101]",
    "i1",
    "i1",
    "a[101,113,117,97,108]",
    "a[111,107]",
    "a[101,113,117,97,108]",
    "a[111,107]",
    "a[111,107]",
    "a[101,113,117,97,108]",
    "a[111,107]",
    "c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))",
    "c[114]/5(a[102,97,108,115,101],i1,a[116,114,117,101],c[91,124,93]/2(c[105,112]/1(i1),c[91,124,93]/2(c[105,112]/1(i2),nil)),a[116,114,117,101])",
    "c[91,124,93]/2(c[45]/2(a[97],i3),nil)",
    "c[91,124,93]/2(c[115,117]/1(i3),nil)"
]

const _TZ_LEFT_PINNED = [
    "t_ad05 c[116,95,97,100,48,53]/1(a[111,107])",
    "t_ad06 c[116,95,97,100,48,54]/1(a[115,97,109,101])",
    "t_ad12 c[116,95,97,100,49,50]/1(a[101,113,117,97,108])",
    "t_ad18 c[116,95,97,100,49,56]/1(a[111,107])",
    "t_ad21 c[116,95,97,100,50,49]/1(a[111,107])",
    "t_ad22 c[116,95,97,100,50,50]/1(a[111,107])",
    "t_ad23 c[116,95,97,100,50,51]/1(a[111,107])"
]

const _TZ_LEFT_UPSTREAM = [
    "a[111,107]",
    "a[115,97,109,101]",
    "a[101,113,117,97,108]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]"
]

"The program text with the cases appended."
_tz_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- ( catch(($g), error(SsuE, _), R = raised(SsuE)) -> true ; R = failed ).\n"
        for (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tz_load(program::String)
    f = joinpath(mktempdir(), "tabling_upstream.pl")
    write(f, _tz_text(program, [(id, g) for (id, _, g) in _TZ_CASES]))
    gd = LK.PL_global_data{_TZ}()
    ld = LK.PL_local_data{_TZ}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tz_enc(ball::_TZ))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tz_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tzs(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TZ, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _tz_enc(mk_expr(_TZ, _TZ[_tzs(pred), lk_answers(ld, (a:a)...)...])))
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


"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_TZ_UPSTREAM` holds it."
function _tz_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_tz_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

@testset "upstream test_answer_discard.pl: lazy compilation and discarding of answer tries" begin
    gd, ld, st = _tz_load(_TZ_PROGRAM)
    @test st == "ok"
    kl = String[st]
    for (id, _, _) in _TZ_CASES
        push!(kl, _tz_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TZ_PINNED)
    for (k, pn) in zip(kl, _TZ_PINNED)
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line (the comparison can fail)
    @test length(kl) > 1
    @test kl[2] != _tz_corrupt(_TZ_PINNED[2])
end

@testset "the pins are the upstream expectations (no swipl needed)" begin
    @test length(_TZ_PINNED) == length(_TZ_CASES) + 1
    @test length(_TZ_UPSTREAM) == length(_TZ_CASES)
    @test !isempty(_TZ_UPSTREAM) && all(!isempty, _TZ_UPSTREAM)
    for (pn, up) in zip(_TZ_PINNED[2:end], _TZ_UPSTREAM)
        @test _tz_answer(pn) == up
    end
    @test length(_TZ_LEFT_PINNED) == length(_TZ_LEFT) == length(_TZ_LEFT_UPSTREAM)
    for (pn, up) in zip(_TZ_LEFT_PINNED, _TZ_LEFT_UPSTREAM)
        @test _tz_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _tz_answer(_tz_corrupt(_TZ_PINNED[2])) != _TZ_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f = joinpath(mktempdir(), "ts_upstream_swipl.pl")
        all_cases = vcat(
            [(id, g) for (id, _, g) in _TZ_CASES], [(id, g) for (id, _, g, _) in _TZ_LEFT]
        )
        write(f, _tz_text(_TZ_PROGRAM * _TZ_LEFT_PROGRAM, all_cases))
        got = _tz_swipl_lines(f, ["t_$id" for (id, _) in all_cases])
        @test !isempty(got) && got == vcat(_TZ_PINNED, _TZ_LEFT_PINNED)
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _tz_corrupt(_TZ_PINNED[2])
    end
end
