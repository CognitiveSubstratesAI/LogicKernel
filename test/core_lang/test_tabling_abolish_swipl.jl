# ORIGINAL: a LIVE differential of the abolish and reclaim paths of pl-tabling.c (TAB1 TB5; audit D-0477) against swipl at the pin
# (swipl-devel 18168e62, 10.1.20): `abolish_all_tables/0`, `abolish_private_tables/0`, `abolish_shared_tables/0`,
# `abolish_table_subgoals/1`, `abolish_module_tables/1` (boot/tabling.pl:1120-1181), `'$tbl_destroy_table'/1` (pl-tabling.c abolish_table),
# `'$tbl_abolish_local_tables'/0` (clear_variant_table, clearThreadTablingData) and `untable/1` (tabling.pl:250-295). Groups: aba =
# abolish_all_tables, abp = abolish_private_tables, abs = abolish_shared_tables, abg = abolish_table_subgoals, abm = abolish_module_tables,
# abd = `$tbl_destroy_table`, abl = `$tbl_abolish_local_tables`, abw = that call from inside an evaluation, abu = untable.
#   * swipl makes its tables by calling a tabled predicate (`ab_mk`: `ab_p(1)`, `ab_p(_)`, `ab_q(1)`: three variant tables, all complete);
#     every case starts with `ab_mk`, so every case starts from the same three tables. The kernel has no `start_tabling` (the create path
#     is TB2): the TEST makes the three tables white-box before each case (`get_answer_table` with `AT_CREATE`, then `TRIE_COMPLETE`, as
#     test_tabling_variant_swipl.jl does) and `ab_mk` is a no-op there. A trie is never printed (the blob's address differs).
#   * Cases `t_<id>(R)` run in order in one database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is
#     test_tabling_min_swipl.jl's (`enc`oded answers). The abolish predicates are boot/tabling.pl's Prolog, so a row reads the ported
#     `$tbl_destroy_table`/`$tbl_abolish_local_tables`, the variant table and `current_table/2` together.
#   * abw: `'$tbl_abolish_local_tables'` from inside a tabled evaluation fails silently (a scheduling component exists). swipl runs it
#     inside `ab_w`; the kernel sets `has_scheduling_component` white-box around the call and checks that no table was touched.
#   * abu: `untable/1` unwraps the predicate (`unwrap_predicate(M:Name/Arity, table)`): it needs the wrapper `:- table` makes, which the
#     kernel has once TAB1's pl-wrap.jl lands. The kernel runs the abu rows only when `$wrap_predicate/5` is defined; until then the rows are
#     pinned and the live swipl check runs, and an @info says so.
#   * Answer discard (test_answer_discard.pl) and the incomplete-table rows (test_abolish_active_table.pl, test_abolish_depending_table.pl,
#     test_abolish_delay_deps.pl, test_abolish_bulk.pl) read answers, compiled tries and running evaluations: their create paths are TB2/TB3/TB4,
#     the IDG rows TB6, the shared tables TH1. Nothing here pins them; the direct white-box checks below cover `delayed_destroy_table` only on
#     a complete table.
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs; evidence/TB5/gen/ab_gen.py makes this file from
#     ab_template.jl); with `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _AB = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_abs(x) = lk_sym(_AB, Symbol(x))

_ab_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _ab_enc(t::_AB, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ab_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ab_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ab_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ab_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _AB_DRIVER = raw"""
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

function _ab_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _AB_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

const _AB_COMMON = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tm_same(A, B, R) :- ( A == B -> R = same ; R = diff ).
ab_p(1).
ab_p(2).
ab_q(1).
ab_vt(VT) :- '$tbl_variant_table'(VT).
ab_n(N) :- findall(K, (ab_vt(VT), trie_gen(VT, K, _)), L), length(L, N).
ab_list(L) :- findall(K-S, (ab_vt(VT), trie_gen(VT, K, T), '$tbl_table_status'(T, S)), L0), msort(L0, L).
ab_tab(V, T) :- '$tbl_existing_variant_table'(0, V, T, _, _).
"""
# the kernel marks the predicates tabled (`is_tabled`); the tables are made by `_ab_tables!`
const _AB_KERNEL = raw"""
:- '$set_predicate_attribute'(ab_p(_), tabled, true).
:- '$set_predicate_attribute'(ab_q(_), tabled, true).
ab_mk.
ab_inside(R) :- ( '$tbl_abolish_local_tables' -> R = yes ; R = no ).
"""
const _AB_SWIPL = raw"""
:- table ab_p/1, ab_q/1, ab_w/0.
ab_mk :- forall(ab_p(1), true), forall(ab_p(_), true), forall(ab_q(1), true).
ab_w :- ( '$tbl_abolish_local_tables' -> R = yes ; R = no ), nb_setval(ab_wr, R).
ab_inside(R) :- ab_w, nb_getval(ab_wr, R).
"""
const _AB_COMMON_U = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
ab_u1(1).
ab_u1(2).
ab_u2(1).
ab_u2(2).
ab_vt(VT) :- '$tbl_variant_table'(VT).
ab_n(N) :- findall(K, (ab_vt(VT), trie_gen(VT, K, _)), L), length(L, N).
ab_list(L) :- findall(K-S, (ab_vt(VT), trie_gen(VT, K, T), '$tbl_table_status'(T, S)), L0), msort(L0, L).
"""
const _AB_KERNEL_U = raw"""
:- '$set_predicate_attribute'(ab_u1(_), tabled, true).
:- '$set_predicate_attribute'(ab_u2(_), tabled, true).
:- wrap_predicate(ab_u1(_), table, W1, call(W1)).
:- wrap_predicate(ab_u2(_), table, W2, call(W2)).
"""
const _AB_SWIPL_U = raw"""
:- table ab_u1/1, ab_u2/1.
:- forall(ab_u2(1), true).
"""

const _AB_CASES = [
    ("aba01", raw"ab_n(N0), abolish_all_tables, ab_n(N1), R = r(N0, N1)"),
    ("aba02", raw"abolish_all_tables, tm_yn(current_table(user:_, _), R)"),
    ("aba03", raw"abolish_all_tables, abolish_all_tables, ab_n(N), R = N"),
    ("aba04", raw"abolish_all_tables, ab_list(L), R = L"),
    ("aba05", raw"abolish_all_tables, '$tbl_variant_table'(V), tm_yn(is_trie(V), R)"),
    ("aba06", raw"ab_tab(user:ab_p(1), T), abolish_all_tables, tm_yn(is_trie(T), R)"),
    ("aba07", raw"findall(T, current_table(user:_, T), Ts), length(Ts, N), R = N"),
    (
        "aba08",
        raw"abolish_all_tables, findall(T, current_table(user:_, T), Ts), length(Ts, N), R = N"
    ),
    ("abp01", raw"abolish_private_tables, ab_n(N), R = N"),
    ("abp02", raw"abolish_private_tables, ab_list(L), R = L"),
    (
        "abp03",
        raw"abolish_private_tables, '$tbl_local_variant_table'(V), tm_yn(is_trie(V), R)"
    ),
    ("abp04", raw"abolish_private_tables, abolish_private_tables, ab_n(N), R = N"),
    ("abs01", raw"abolish_shared_tables, ab_n(N), R = N"),
    ("abs02", raw"abolish_shared_tables, ab_list(L), R = L"),
    ("abg01", raw"abolish_table_subgoals(ab_p(1)), ab_n(N), R = N"),
    ("abg02", raw"abolish_table_subgoals(ab_p(1)), ab_list(L), R = L"),
    ("abg03", raw"abolish_table_subgoals(ab_p(_)), ab_list(L), R = L"),
    ("abg04", raw"abolish_table_subgoals(ab_q(2)), ab_n(N), R = N"),
    ("abg05", raw"abolish_table_subgoals(ab_nope(_)), ab_n(N), R = N"),
    ("abg06", raw"abolish_table_subgoals(user:ab_q(_)), ab_list(L), R = L"),
    ("abg07", raw"abolish_table_subgoals(1), R = ok"),
    ("abg08", raw"abolish_table_subgoals(_), R = ok"),
    (
        "abg09",
        raw"abolish_table_subgoals(ab_p(1)), abolish_table_subgoals(ab_p(1)), ab_n(N), R = N"
    ),
    (
        "abg10",
        raw"abolish_table_subgoals(ab_q(_)), abolish_table_subgoals(ab_p(_)), ab_n(N), R = N"
    ),
    ("abm01", raw"abolish_module_tables(user), ab_n(N), R = N"),
    ("abm02", raw"abolish_module_tables(ab_nomod), ab_n(N), R = N"),
    ("abm03", raw"abolish_module_tables(system), ab_n(N), R = N"),
    ("abm04", raw"abolish_module_tables(1), R = ok"),
    ("abm05", raw"abolish_module_tables(_), R = ok"),
    ("abd01", raw"ab_tab(user:ab_p(1), T), '$tbl_destroy_table'(T), ab_n(N), R = N"),
    (
        "abd02",
        raw"ab_tab(user:ab_p(1), T), '$tbl_destroy_table'(T), '$tbl_destroy_table'(T), R = ok"
    ),
    ("abd03", raw"ab_tab(user:ab_p(1), T), '$tbl_destroy_table'(T), tm_yn(is_trie(T), R)"),
    ("abd04", raw"ab_tab(user:ab_p(1), T), '$tbl_destroy_table'(T), ab_list(L), R = L"),
    ("abd05", raw"'$tbl_destroy_table'(a), R = ok"),
    ("abd06", raw"'$tbl_destroy_table'(_), R = ok"),
    ("abd07", raw"'$tbl_variant_table'(VT), tm_yn('$tbl_destroy_table'(VT), R)"),
    ("abd08", raw"'$tbl_variant_table'(VT), '$tbl_destroy_table'(VT), ab_n(N), R = N"),
    (
        "abd09",
        raw"ab_tab(user:ab_p(1), T), '$tbl_destroy_table'(T), tm_yn('$tbl_table_status'(T, _), R)"
    ),
    (
        "abd10",
        raw"ab_tab(user:ab_p(1), T), ab_tab(user:ab_p(_), U), '$tbl_destroy_table'(T), '$tbl_destroy_table'(U), ab_list(L), R = L"
    ),
    (
        "abd11",
        raw"ab_tab(user:ab_p(1), T), '$tbl_destroy_table'(T), ab_tab(user:ab_p(1), U), tm_yn(U == T, R)"
    ),
    ("abl01", raw"tm_yn('$tbl_abolish_local_tables', R)"),
    ("abl02", raw"'$tbl_abolish_local_tables', ab_n(N), R = N"),
    (
        "abl03",
        raw"'$tbl_abolish_local_tables', '$tbl_abolish_local_tables', ab_n(N), R = N"
    ),
    (
        "abl04",
        raw"'$tbl_abolish_local_tables', findall(T, current_table(user:_, T), Ts), length(Ts, N), R = N"
    ),
    (
        "abl05",
        raw"ab_tab(user:ab_p(1), T), '$tbl_abolish_local_tables', tm_yn(is_trie(T), R)"
    ),
    (
        "abl06",
        raw"'$tbl_abolish_local_tables', '$tbl_local_variant_table'(V), tm_yn(is_trie(V), R)"
    ),
    ("abw01", raw"ab_inside(R0), R = R0")
]
const _AB_CASES_U = [
    (
        "abu01",
        raw"untable(ab_u1/1), tm_yn('$get_predicate_attribute'(user:ab_u1(_), tabled, 1), R)"
    ),
    ("abu02", raw"ab_n(N0), untable(ab_u2/1), ab_n(N1), R = r(N0, N1)"),
    ("abu03", raw"untable(ab_u2/1), untable(ab_u2/1), R = ok"),
    ("abu04", raw"untable(_), R = ok"),
    ("abu05", raw"untable(1), R = ok"),
    ("abu06", raw"untable(ab_u1/1), findall(X, ab_u1(X), L), R = L"),
    ("abu07", raw"untable((ab_u1/1, ab_nope/2)), R = ok"),
    ("abu08", raw"untable(user:ab_u1/1), '$tbl_implementation'(user:ab_u1(_), G), R = G"),
    ("abu09", raw"untable(ab_u2/1), ab_list(L), R = L")
]

const _AB_PINNED = [
    "ok",
    "t_aba01 c[116,95,97,98,97,48,49]/1(c[114]/2(i3,i0))",
    "t_aba02 c[116,95,97,98,97,48,50]/1(a[110,111])",
    "t_aba03 c[116,95,97,98,97,48,51]/1(i0)",
    "t_aba04 c[116,95,97,98,97,48,52]/1(nil)",
    "t_aba05",
    "t_aba06 c[116,95,97,98,97,48,54]/1(a[121,101,115])",
    "t_aba07 c[116,95,97,98,97,48,55]/1(i3)",
    "t_aba08 c[116,95,97,98,97,48,56]/1(i0)",
    "t_abp01 c[116,95,97,98,112,48,49]/1(i0)",
    "t_abp02 c[116,95,97,98,112,48,50]/1(nil)",
    "t_abp03",
    "t_abp04 c[116,95,97,98,112,48,52]/1(i0)",
    "t_abs01 c[116,95,97,98,115,48,49]/1(i3)",
    "t_abs02 c[116,95,97,98,115,48,50]/1(c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,112]/1(V0)),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,112]/1(i1)),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,113]/1(i1)),a[99,111,109,112,108,101,116,101]),nil))))",
    "t_abg01 c[116,95,97,98,103,48,49]/1(i1)",
    "t_abg02 c[116,95,97,98,103,48,50]/1(c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,113]/1(i1)),a[99,111,109,112,108,101,116,101]),nil))",
    "t_abg03 c[116,95,97,98,103,48,51]/1(c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,113]/1(i1)),a[99,111,109,112,108,101,116,101]),nil))",
    "t_abg04 c[116,95,97,98,103,48,52]/1(i3)",
    "t_abg05 c[116,95,97,98,103,48,53]/1(i3)",
    "t_abg06 c[116,95,97,98,103,48,54]/1(c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,112]/1(V0)),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,112]/1(i1)),a[99,111,109,112,108,101,116,101]),nil)))",
    "t_abg07 c[116,95,97,98,103,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],c[58]/2(a[117,115,101,114],i1))))",
    "t_abg08 c[116,95,97,98,103,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],c[58]/2(a[117,115,101,114],V0))))",
    "t_abg09 c[116,95,97,98,103,48,57]/1(i1)",
    "t_abg10 c[116,95,97,98,103,49,48]/1(i0)",
    "t_abm01 c[116,95,97,98,109,48,49]/1(i0)",
    "t_abm02 c[116,95,97,98,109,48,50]/1(i3)",
    "t_abm03 c[116,95,97,98,109,48,51]/1(i3)",
    "t_abm04 c[116,95,97,98,109,48,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_abm05 c[116,95,97,98,109,48,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_abd01 c[116,95,97,98,100,48,49]/1(i2)",
    "t_abd02 c[116,95,97,98,100,48,50]/1(a[111,107])",
    "t_abd03 c[116,95,97,98,100,48,51]/1(a[121,101,115])",
    "t_abd04 c[116,95,97,98,100,48,52]/1(c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,112]/1(V0)),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,113]/1(i1)),a[99,111,109,112,108,101,116,101]),nil)))",
    "t_abd05 c[116,95,97,98,100,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,114,105,101],a[97])))",
    "t_abd06 c[116,95,97,98,100,48,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_abd07 c[116,95,97,98,100,48,55]/1(a[121,101,115])",
    "t_abd08 c[116,95,97,98,100,48,56]/1(i3)",
    "t_abd09 c[116,95,97,98,100,48,57]/1(a[121,101,115])",
    "t_abd10 c[116,95,97,98,100,49,48]/1(c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[97,98,95,113]/1(i1)),a[99,111,109,112,108,101,116,101]),nil))",
    "t_abd11",
    "t_abl01 c[116,95,97,98,108,48,49]/1(a[121,101,115])",
    "t_abl02 c[116,95,97,98,108,48,50]/1(i0)",
    "t_abl03 c[116,95,97,98,108,48,51]/1(i0)",
    "t_abl04 c[116,95,97,98,108,48,52]/1(i0)",
    "t_abl05 c[116,95,97,98,108,48,53]/1(a[121,101,115])",
    "t_abl06",
    "t_abw01 c[116,95,97,98,119,48,49]/1(a[110,111])"
]
const _AB_PINNED_U = [
    "ok",
    "t_abu01 c[116,95,97,98,117,48,49]/1(a[110,111])",
    "t_abu02 c[116,95,97,98,117,48,50]/1(c[114]/2(i1,i0))",
    "t_abu03 c[116,95,97,98,117,48,51]/1(a[111,107])",
    "t_abu04 c[116,95,97,98,117,48,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_abu05 c[116,95,97,98,117,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,97,98,108,101,95,100,101,99,108,97,114,97,116,105,111,110],i1)))",
    "t_abu06 c[116,95,97,98,117,48,54]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_abu07 c[116,95,97,98,117,48,55]/1(a[111,107])",
    "t_abu08 c[116,95,97,98,117,48,56]/1(c[58]/2(a[117,115,101,114],c[97,98,95,117,49]/1(V0)))",
    "t_abu09 c[116,95,97,98,117,48,57]/1(nil)"
]

"The program text with the cases of `cases` appended; `mk`: each case starts with `ab_mk`."
_ab_text(program::String, cases, mk::Bool) =
    program * join([
        "t_$(id)(R) :- $(mk ? "ab_mk, " : "")catch(($g), error(SsuE, _), R = raised(SsuE)).\n"
        for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _ab_load(program::String, cases, mk::Bool)
    f = joinpath(mktempdir(), "tabling_abolish.pl")
    write(f, _ab_text(program, cases, mk))
    gd = LK.PL_global_data{_AB}()
    ld = LK.PL_local_data{_AB}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _ab_enc(ball::_AB))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _ab_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_abs(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_AB, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _ab_enc(mk_expr(_AB, _AB[_abs(pred), lk_answers(ld, (a:a)...)...])))
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

"The definition of `name/arity` in the user module of `gd`."
function _ab_def(gd, name::String, arity::Int=1)
    proc = LK.isCurrentProcedure(sym_key(_abs(name)), arity, LK.MODULE_user(gd))
    @assert proc !== nothing
    return proc.definition
end

"""
The three tables swipl's `ab_mk` makes: `user:ab_p(1)` (no variable: the answer table's worklist is `WL_GROUND`), `user:ab_p(_)` and
`user:ab_q(1)`, all complete; an existing table is found again. The answer tries, in that order.
"""
function _ab_tables!(gd, ld)
    tries = []
    for (name, ground) in (("ab_p", true), ("ab_p", false), ("ab_q", true))
        def = _ab_def(gd, name)
        fid = LK.PL_open_foreign_frame(ld)
        t = LK.PL_new_term_refs(ld, 2)
        arg = ground ? lk_gnd(_AB, 1) : mk_var(_AB, LK.fresh_var_keys!(1))
        v = mk_expr(_AB, _AB[_abs(":"), _abs("user"), mk_expr(_AB, _AB[_abs(name), arg])])
        LK.putSlotValue!(ld, t + 1, v, LK.PutVarMap())
        atrie = LK.get_answer_table(ld, def, t, t + 1, Int(LK.AT_CREATE))
        @assert atrie !== nothing
        atrie.flags |= LK.TRIE_COMPLETE
        push!(tries, atrie)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return tries
end

"The one table `ab_u2(1)` swipl's `:- forall(ab_u2(1), true)` makes (the abu rows)."
function _ab_tables_u!(gd, ld)
    def = _ab_def(gd, "ab_u2")
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 2)
    v = mk_expr(
        _AB,
        _AB[_abs(":"), _abs("user"), mk_expr(_AB, _AB[_abs("ab_u2"), lk_gnd(_AB, 1)])]
    )
    LK.putSlotValue!(ld, t + 1, v, LK.PutVarMap())
    atrie = LK.get_answer_table(ld, def, t, t + 1, Int(LK.AT_CREATE))
    @assert atrie !== nothing
    atrie.flags |= LK.TRIE_COMPLETE
    LK.PL_close_foreign_frame(ld, fid)
    return atrie
end

"Whether the pin line `l` is the row `id` (a case that fails is the bare `t_<id>`)."
_ab_row(l::String, id::String) = l == "t_$id" || startswith(l, "t_$id ")

function _ab_compare(kl, pins)
    @test length(kl) == length(pins)
    for (k, p) in zip(kl, pins)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "abolish as swipl's (aba, abp, abs, abg, abm, abd, abl, abw)" begin
    gd, ld, st = _ab_load(_AB_COMMON * _AB_KERNEL, _AB_CASES, true)
    @test st == "ok"
    kl = String[st]
    for (id, _) in _AB_CASES
        atries = _ab_tables!(gd, ld)
        variants = gd.tries[ld.tabling.variant_table]
        if id == "abw01"
            ld.tabling.has_scheduling_component = true
            push!(kl, _ab_ask(gd, ld, "t_$id"))
            ld.tabling.has_scheduling_component = false
            @test variants.value_count == 3           # nothing was touched
            @test all(a -> a.variant != 0, atries)
        else
            push!(kl, _ab_ask(gd, ld, "t_$id"))
        end
    end
    _ab_compare(kl, _AB_PINNED)
end

@testset "untable as swipl's (abu)" begin
    gd, ld, st = _ab_load(_AB_COMMON_U, _AB_CASES_U, false)
    @test st == "ok"
    wrap = LK.isCurrentProcedure(sym_key(_abs("\$wrap_predicate")), 5, LK.MODULE_system(gd))
    if wrap === nothing || !LK.isDefinedProcedure(gd, wrap)
        @info "TB5 UNTABLE ROWS NOT RUN on the kernel: `\$wrap_predicate/5` is not defined (owner TAB1, pl-wrap.jl); the pins are checked live."
    else
        gd, ld, st = _ab_load(_AB_COMMON_U * _AB_KERNEL_U, _AB_CASES_U, false)
        @test st == "ok"
        _ab_tables_u!(gd, ld)
        kl = String[st]
        for (id, _) in _AB_CASES_U
            push!(kl, _ab_ask(gd, ld, "t_$id"))
        end
        _ab_compare(kl, _AB_PINNED_U)
    end
end

@testset "abolish, direct on the tries (white-box)" begin
    gd, ld, st = _ab_load(_AB_COMMON * _AB_KERNEL, _AB_CASES[1:1], true)
    @test st == "ok"
    atries = _ab_tables!(gd, ld)
    variants = gd.tries[ld.tabling.variant_table]
    @test variants.value_count == 3
    @test LK.DYN_ORPHAN_SWEEP_MIN == 1024
    @test LK.get_trie_from_node(ld, atries[1]) === variants
    # a complete table is not scheduled for destruction on completion
    for a in atries
        @test LK.delayed_destroy_table(a) == false
        @test (a.flags & LK.TRIE_ABOLISH_ON_COMPLETE) == 0
        @test LK.orphan_dynamic_table(a) == false   # a complete table is not `WL_DYNAMIC`
        @test LK.collect_dynamic_children(ld, a) == typeof(a)[]   # no IDG node: no dependents
    end
    # the sweep does nothing below DYN_ORPHAN_SWEEP_MIN lost dependents
    ld.tabling.dyn_orphan_events = 5
    @test LK.sweep_orphan_dynamic_tables(ld) === nothing
    @test ld.tabling.dyn_orphan_events == 5
    @test variants.value_count == 3
    # the answer trie of a table leaves the variant table
    @test LK.destroy_answer_trie(ld, atries[1])
    @test variants.value_count == 2
    @test LK.abolish_table(ld, atries[2])
    @test variants.value_count == 1
    @test LK.abolish_table(ld, atries[3])
    @test variants.value_count == 0
    # the thread's variant table: clear_variant_table drops it and the start node cache
    atries = _ab_tables!(gd, ld)
    @test LK.clear_variant_table(ld) === nothing
    @test ld.tabling.variant_table == 0
    @test ld.tabling.start_nodes === nothing
    @test LK.get_trie_from_node(ld, atries[1]) === nothing
    # a new table makes a new variant table
    atries = _ab_tables!(gd, ld)
    @test ld.tabling.variant_table != 0
    @test gd.tries[ld.tabling.variant_table].value_count == 3
end

# The IDG branch of `reset_answer_table` (pl-tabling.c:2654-2662) with the engine: `destroy_answer_trie` and `abolish_table` run it
# (`reset_answer_table_idg`) BEFORE `trie_delete`, because the release chain carries only `gd` (DIVERGES, dispatcher ruling, option (c)).
# LK-only white-box rows; the graph is built by hand as test_tabling_idg_swipl.jl's idg12 does. A caller that did not run the branch
# would reach the chain's named refusal (NotPortedError) and fail these rows; an `idg_destroy` that left the edge would fail the
# `dependent` rows. UNVERIFIED on the kernel (nothing was compiled when these rows were written): the gate decides.
@testset "abolish: the IDG node goes with the table (reset_answer_table's IDG branch before trie_delete)" begin
    gd, ld, st = _ab_load(_AB_COMMON * _AB_KERNEL, _AB_CASES[1:1], true)
    @test st == "ok"
    atries = _ab_tables!(gd, ld)
    variants = gd.tries[ld.tabling.variant_table]
    nodes = [LK.idg_new(ld, a) for a in atries]
    @test all(n -> n !== nothing, nodes)
    for (a, n) in zip(atries, nodes)
        a.IDG = n
    end
    live(set) = begin
        out = LK.idg_node{_AB}[]
        e = LK.idg_set_enum_init(set)
        while (p = LK.idg_set_next(e)) !== nothing
            push!(out, p)
        end
        out
    end
    @test LK.idg_add_child(ld, nodes[1], nodes[2], 0, 0)       # nodes[2] depends on nodes[1]: it is in nodes[1].dependent
    @test LK.idg_add_child(ld, nodes[1], nodes[3], 0, 0)
    @test length(live(nodes[1].dependent)) == 2
    @test variants.value_count == 3
    # destroy_answer_trie: the node of atries[2] is destroyed with its table, its half of the edge leaves nodes[1].dependent
    @test LK.destroy_answer_trie(ld, atries[2])
    @test atries[2].IDG === nothing
    @test variants.value_count == 2
    @test length(live(nodes[1].dependent)) == 1
    @test live(nodes[1].dependent)[1] === nodes[3]
    # abolish_table: the same for atries[3]
    @test LK.abolish_table(ld, atries[3])
    @test atries[3].IDG === nothing
    @test variants.value_count == 1
    @test isempty(live(nodes[1].dependent))
    # and the table that is the parent of no edge any more
    @test LK.abolish_table(ld, atries[1])
    @test atries[1].IDG === nothing
    @test variants.value_count == 0
end

# `clear_variant_table` -> `empty_variant_table` -> `reset_table_bulk` with IDG nodes (pl-tabling.c:2783-2795, :2885-2913): the thread's
# registry is detached before the resets and released after (`idg_registry_release_n(registry, idg_nodes + 1)`), every node of the tables
# is destroyed with its table, a node with `concurrent` set is unlinked first (`idg_unlink_concurrent_table`). LK-only white-box rows;
# UNVERIFIED on the kernel (nothing was compiled when these rows were written): the gate decides.
@testset "clear_variant_table: the IDG nodes of the tables go with them (reset_table_bulk, the registry)" begin
    gd, ld, st = _ab_load(_AB_COMMON * _AB_KERNEL, _AB_CASES[1:1], true)
    @test st == "ok"
    atries = _ab_tables!(gd, ld)
    nodes = [LK.idg_new(ld, a) for a in atries]
    @test all(n -> n !== nothing, nodes)
    for (a, n) in zip(atries, nodes)
        a.IDG = n
    end
    @test LK.idg_add_child(ld, nodes[1], nodes[2], 0, 0)
    reg = ld.tabling.idg_registry
    @test reg !== nothing
    @test all(n -> n.registry === reg, nodes)
    nodes[2].concurrent = true
    ld.tabling.concurrent_idg_nodes = 1
    LK.clear_variant_table(ld)
    @test ld.tabling.variant_table == 0
    @test ld.tabling.idg_registry === nothing                  # detached before the resets
    @test all(a -> a.IDG === nothing && a.variant == 0, atries)
    @test ld.tabling.concurrent_idg_nodes == 0
    @test ld.tabling.dyn_orphan_events == 0
end

@testset "the abolish rows are not vacuous" begin
    @test _AB_PINNED[1] == "ok" && _AB_PINNED_U[1] == "ok"
    @test length(_AB_PINNED) == length(_AB_CASES) + 1
    @test length(_AB_PINNED_U) == length(_AB_CASES_U) + 1
    for pre in ("aba", "abp", "abs", "abg", "abm", "abd", "abl", "abw")
        ids = [id for (id, _) in _AB_CASES if startswith(id, pre)]
        @test !isempty(ids)
        @test length([l for l in _AB_PINNED if any(id -> _ab_row(l, id), ids)]) ==
            length(ids)
    end
    ids = [id for (id, _) in _AB_CASES_U]
    @test length([l for l in _AB_PINNED_U if any(id -> _ab_row(l, id), ids)]) == length(ids)
    line(pins, id) = only(filter(l -> startswith(l, "t_$id "), pins))
    ans(pins, id) = split(line(pins, id), " "; limit=2)[2]
    @test ans(_AB_PINNED, "aba01") != ans(_AB_PINNED, "aba03")          # three tables, then none
    @test ans(_AB_PINNED, "abp01") != ans(_AB_PINNED, "abs01")          # private tables are cleared, shared ones are not
    @test ans(_AB_PINNED, "abg01") != ans(_AB_PINNED, "abg04")          # the variant ab_p(1) is destroyed, ab_q(2) matches none
    @test ans(_AB_PINNED, "abg02") != ans(_AB_PINNED, "abg03")          # one table gone, two tables gone
    @test ans(_AB_PINNED, "abd01") != ans(_AB_PINNED, "abd05")          # a destroyed table, a type error
    @test ans(_AB_PINNED, "abl02") != ans(_AB_PINNED, "abd01")          # all tables of the thread, one table
    @test ans(_AB_PINNED_U, "abu01") != ans(_AB_PINNED_U, "abu04")      # a no, an instantiation error
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB5 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        for (program, cases, pins, mk) in (
            (_AB_COMMON * _AB_SWIPL, _AB_CASES, _AB_PINNED, true),
            (_AB_COMMON_U * _AB_SWIPL_U, _AB_CASES_U, _AB_PINNED_U, false)
        )
            f = joinpath(mktempdir(), "ab_swipl.pl")
            write(f, _ab_text(program, cases, mk))
            @test _ab_swipl_lines(f, ["t_$id" for (id, _) in cases]) == pins
        end
    end
end
