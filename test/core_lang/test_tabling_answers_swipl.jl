# ORIGINAL: a LIVE differential of the answers of a table (TAB1 TB3; audit D-0477) against swipl at the pin (swipl-devel 18168e62,
# 10.1.20): `'$tbl_answer'/3`, `'$tbl_answer_c'/4`, `'$tbl_wkl_add_answer'/4` and the answer subsumption of a moded table
# (pl-tabling.c:4729-5554, :6269, :7061-7157): `max`, `min`, `first`, `last`, `lattice(PI)`, `po(PI)` and two moded arguments.
# Groups: taq = the predicates (registered, errors, an empty trie), taa = the answers of a completed table, tas = the moded tables.
#   * RUNS ONCE TB2 AND TB5 ARE STACKED (the taa and tas rows evaluate a tabled program: `start_tabling/3`, completion of an SCC, and
#     with the delays TB4 `answer_is_conditional`; on wip/tb3 alone the taa and tas rows cannot run). The taq rows need TB3 and TB2's
#     `get_worklist` only. The program text is ONE text: swipl and the kernel consult the same file (no white-box table).
#   * Cases `t_<id>(R)` run in order in one database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is
#     test_tabling_min_swipl.jl's (`enc`oded answers). A trie is never printed (the blob's address differs): a row reads the trie of a
#     variant (`ta_tab`), its answers (`ta_answers`: `'$tbl_answer'/3`; `ta_moded`: `trie_gen` + `'$tbl_answer_c'/4`) and sorts them.
#   * The moded variant is `'$ta_max$1'(_)` (the wrapper without the moded arguments), as tabling.pl makes it in both systems.
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs; evidence/TB3/gen/ta_gen.py makes the pins); with
#     `swipl` on PATH the live answers are compared with the pins too. `po(ta_lt/2)` keeps 1 of 1,3,2,5: swipl's own answer, pinned
#     as it is (not derived from the documentation of `po/1`; the cause is read at `update_subsuming_answer`, pl-tabling.c:5088).
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

const _TA_PROGRAM = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
:- table ta_p/1.
ta_p(1).
ta_p(2).
ta_p(3).
:- table ta_pair/2.
ta_pair(1, a).
ta_pair(1, b).
ta_pair(2, c).
:- table ta_max(_, max).
ta_max(a, 1).
ta_max(a, 3).
ta_max(a, 2).
ta_max(b, 5).
ta_max(c, 2).
ta_max(c, 2).
:- table ta_min(_, min).
ta_min(a, 4).
ta_min(a, 3).
ta_min(a, 9).
ta_min(b, 5).
:- table ta_first(_, first).
ta_first(a, x).
ta_first(a, y).
ta_first(b, z).
:- table ta_last(_, last).
ta_last(a, x).
ta_last(a, y).
ta_last(b, z).
:- table ta_lat(_, lattice(ta_join/3)).
ta_join(A, B, C) :- ord_union(A, B, C).
ta_lat(a, [1]).
ta_lat(a, [3]).
ta_lat(a, [2]).
ta_lat(b, [7]).
:- table ta_po(_, po(ta_lt/2)).
ta_lt(O, N) :- N > O.
ta_po(a, 1).
ta_po(a, 3).
ta_po(a, 2).
ta_po(a, 5).
ta_po(b, 0).
:- table ta_two(_, max, min).
ta_two(a, 1, 9).
ta_two(a, 3, 7).
ta_two(a, 2, 8).
:- table ta_udl(_, max).
ta_udl(a, 1) :- '$tbl_set_delay_list'(foo).
ta_udl(a, 3).
ta_vars(K, T) :- '$tbl_variant_table'(VT), trie_gen(VT, K, T).
ta_tab(K0, T) :- ta_vars(user:K, T), K =@= K0.
ta_answers(K, L) :- findall(S-C, (ta_tab(K, T), '$tbl_answer'(T, S, C)), L0), msort(L0, L).
ta_moded(K, L) :- findall(S-M-C, (ta_tab(K, T), trie_gen(T, S), '$tbl_answer_c'(T, S, M, C)), L0), msort(L0, L).
ta_all(G, L) :- findall(G, G, L0), msort(L0, L).
"""

const _TA_CASES = [
    ("taq01", raw"'$tbl_answer'(a, _, _), R = ok"),
    ("taq02", raw"'$tbl_answer'(_, _, _), R = ok"),
    ("taq03", raw"'$tbl_answer_c'(a, _, _, _), R = ok"),
    ("taq04", raw"'$tbl_answer_c'(_, _, _, _), R = ok"),
    ("taq05", raw"tm_yn('$tbl_wkl_add_answer'(a, x, [], _), R)"),
    ("taq06", raw"tm_yn('$tbl_wkl_add_answer'(_, x, [], _), R)"),
    ("taq07", raw"trie_new(T), tm_yn('$tbl_answer'(T, _, _), R)"),
    ("taq08", raw"trie_new(T), tm_yn('$tbl_answer_c'(T, f, _, _), R)"),
    (
        "taq09",
        raw"tm_yn('$get_predicate_attribute'(system:'$tbl_answer'(_, _, _), defined, 1), R)"
    ),
    (
        "taq10",
        raw"tm_yn('$get_predicate_attribute'(system:'$tbl_answer_c'(_, _, _, _), defined, 1), R)"
    ),
    (
        "taq11",
        raw"tm_yn('$get_predicate_attribute'(system:'$tbl_wkl_add_answer'(_, _, _, _), defined, 1), R)"
    ),
    (
        "taq12",
        raw"tm_yn('$get_predicate_attribute'(system:'$tbl_answer'(_, _, _), foreign, 1), R)"
    ),
    (
        "taq13",
        raw"tm_yn('$get_predicate_attribute'(system:'$tbl_wkl_add_answer'(_, _, _, _), foreign, 1), R)"
    ),
    ("taa01", raw"ta_all(ta_p(_), _), ta_answers(ta_p(_), R)"),
    ("taa02", raw"ta_all(ta_p(2), _), ta_answers(ta_p(2), R)"),
    ("taa03", raw"ta_all(ta_p(9), _), ta_answers(ta_p(9), R)"),
    ("taa04", raw"ta_all(ta_pair(1, _), _), ta_answers(ta_pair(1, _), R)"),
    ("taa05", raw"ta_all(ta_pair(_, _), _), ta_answers(ta_pair(_, _), R)"),
    (
        "taa06",
        raw"ta_all(ta_p(_), _), ta_tab(ta_p(_), T), findall(S, '$tbl_answer'(T, S, _), L), length(L, R)"
    ),
    (
        "taa07",
        raw"ta_all(ta_p(_), _), ta_tab(ta_p(_), T), '$tbl_answer'(T, ret(2), C), R = C"
    ),
    (
        "taa08",
        raw"ta_all(ta_p(_), _), ta_tab(ta_p(_), T), tm_yn('$tbl_answer'(T, ret(7), _), R)"
    ),
    (
        "taa09",
        raw"ta_all(ta_p(_), _), ta_tab(ta_p(_), T), tm_yn(once('$tbl_answer'(T, _, _)), R)"
    ),
    (
        "taa10",
        raw"ta_all(ta_p(_), _), ta_tab(ta_p(_), T), '$tbl_answer'(T, S, C), S = ret(3), R = C"
    ),
    ("taa11", raw"ta_all(ta_p(_), L), R = L"),
    ("tas01", raw"ta_all(ta_max(_, _), R)"),
    ("tas02", raw"ta_moded('$ta_max$1'(_), R)"),
    ("tas03", raw"ta_all(ta_min(_, _), R)"),
    ("tas04", raw"ta_moded('$ta_min$1'(_), R)"),
    ("tas05", raw"ta_all(ta_first(_, _), R)"),
    ("tas06", raw"ta_moded('$ta_first$1'(_), R)"),
    ("tas07", raw"ta_all(ta_last(_, _), R)"),
    ("tas08", raw"ta_moded('$ta_last$1'(_), R)"),
    ("tas09", raw"ta_all(ta_lat(_, _), R)"),
    ("tas10", raw"ta_moded('$ta_lat$1'(_), R)"),
    ("tas11", raw"ta_all(ta_po(_, _), R)"),
    ("tas12", raw"ta_moded('$ta_po$1'(_), R)"),
    ("tas13", raw"ta_all(ta_two(_, _, _), R)"),
    ("tas14", raw"ta_moded('$ta_two$2'(_), R)"),
    ("tas15", raw"ta_max(a, X), R = X"),
    ("tas16", raw"ta_min(b, X), R = X"),
    ("tas17", raw"ta_max(c, X), R = X"),
    ("tas18", raw"tm_yn(ta_max(a, 3), R)"),
    ("tas19", raw"tm_yn(ta_max(a, 1), R)"),
    ("tas20", raw"tm_yn(ta_max(z, _), R)"),
    (
        "tas21",
        raw"ta_all(ta_max(_, _), _), ta_tab('$ta_max$1'(_), T), '$tbl_table_status'(T, S), R = S"
    ),
    (
        "tas22",
        raw"ta_all(ta_max(_, _), _), ta_tab('$ta_max$1'(_), T), tm_yn('$is_answer_trie'(T, _), R)"
    ),
    (
        "tas23",
        raw"ta_all(ta_max(_, _), _), ta_tab('$ta_max$1'(_), T), findall(S, trie_gen(T, S), L), length(L, R)"
    ),
    # tas24: the body of ta_udl(a, 1) sets the global delay list to a non-list (the Prolog error is the observable answer): the call raises.
    # This route reaches add_subsuming_answer through `'$tbl_reset'`, whose caller reads only the complete/not-complete result and the pending
    # exception is thrown either way: tas24 pins the raise but does NOT tell TB3-S9 apart; the kill rows of TB3-S9 are tbw01-tbw03 (the
    # testset "TB3-S9: ..." below), which call `'$tbl_wkl_add_answer'/4` as a predicate.
    # LAST: the delay list stays `-foo` after the raise, no later row may run in this program.
    ("tas24", raw"ta_all(ta_udl(_, _), R)")
]

const _TA_PINNED = [
    "ok",
    "t_taq01 c[116,95,116,97,113,48,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,114,105,101],a[97])))",
    "t_taq02 c[116,95,116,97,113,48,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_taq03 c[116,95,116,97,113,48,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,114,105,101],a[97])))",
    "t_taq04 c[116,95,116,97,113,48,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_taq05 c[116,95,116,97,113,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[119,111,114,107,108,105,115,116],a[97])))",
    "t_taq06 c[116,95,116,97,113,48,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_taq07 c[116,95,116,97,113,48,55]/1(a[110,111])",
    "t_taq08 c[116,95,116,97,113,48,56]/1(a[110,111])",
    "t_taq09 c[116,95,116,97,113,48,57]/1(a[121,101,115])",
    "t_taq10 c[116,95,116,97,113,49,48]/1(a[121,101,115])",
    "t_taq11 c[116,95,116,97,113,49,49]/1(a[121,101,115])",
    "t_taq12 c[116,95,116,97,113,49,50]/1(a[121,101,115])",
    "t_taq13 c[116,95,116,97,113,49,51]/1(a[121,101,115])",
    "t_taa01 c[116,95,116,97,97,48,49]/1(c[91,124,93]/2(c[45]/2(c[114,101,116]/1(i1),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(i2),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(i3),a[116,114,117,101]),nil))))",
    "t_taa02 c[116,95,116,97,97,48,50]/1(c[91,124,93]/2(c[45]/2(a[114,101,116],a[116,114,117,101]),nil))",
    "t_taa03 c[116,95,116,97,97,48,51]/1(nil)",
    "t_taa04 c[116,95,116,97,97,48,52]/1(c[91,124,93]/2(c[45]/2(c[114,101,116]/1(a[97]),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[114,101,116]/1(a[98]),a[116,114,117,101]),nil)))",
    "t_taa05 c[116,95,116,97,97,48,53]/1(c[91,124,93]/2(c[45]/2(c[114,101,116]/2(i1,a[97]),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[114,101,116]/2(i1,a[98]),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[114,101,116]/2(i2,a[99]),a[116,114,117,101]),nil))))",
    "t_taa06 c[116,95,116,97,97,48,54]/1(i3)",
    "t_taa07 c[116,95,116,97,97,48,55]/1(a[116,114,117,101])",
    "t_taa08 c[116,95,116,97,97,48,56]/1(a[110,111])",
    "t_taa09 c[116,95,116,97,97,48,57]/1(a[121,101,115])",
    "t_taa10 c[116,95,116,97,97,49,48]/1(a[116,114,117,101])",
    "t_taa11 c[116,95,116,97,97,49,49]/1(c[91,124,93]/2(c[116,97,95,112]/1(i1),c[91,124,93]/2(c[116,97,95,112]/1(i2),c[91,124,93]/2(c[116,97,95,112]/1(i3),nil))))",
    "t_tas01 c[116,95,116,97,115,48,49]/1(c[91,124,93]/2(c[116,97,95,109,97,120]/2(a[97],i3),c[91,124,93]/2(c[116,97,95,109,97,120]/2(a[98],i5),c[91,124,93]/2(c[116,97,95,109,97,120]/2(a[99],i2),nil))))",
    "t_tas02 c[116,95,116,97,115,48,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),i3),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[98]),i5),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[99]),i2),a[116,114,117,101]),nil))))",
    "t_tas03 c[116,95,116,97,115,48,51]/1(c[91,124,93]/2(c[116,97,95,109,105,110]/2(a[97],i3),c[91,124,93]/2(c[116,97,95,109,105,110]/2(a[98],i5),nil)))",
    "t_tas04 c[116,95,116,97,115,48,52]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),i3),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[98]),i5),a[116,114,117,101]),nil)))",
    "t_tas05 c[116,95,116,97,115,48,53]/1(c[91,124,93]/2(c[116,97,95,102,105,114,115,116]/2(a[97],a[120]),c[91,124,93]/2(c[116,97,95,102,105,114,115,116]/2(a[98],a[122]),nil)))",
    "t_tas06 c[116,95,116,97,115,48,54]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),a[120]),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[98]),a[122]),a[116,114,117,101]),nil)))",
    "t_tas07 c[116,95,116,97,115,48,55]/1(c[91,124,93]/2(c[116,97,95,108,97,115,116]/2(a[97],a[121]),c[91,124,93]/2(c[116,97,95,108,97,115,116]/2(a[98],a[122]),nil)))",
    "t_tas08 c[116,95,116,97,115,48,56]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),a[121]),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[98]),a[122]),a[116,114,117,101]),nil)))",
    "t_tas09 c[116,95,116,97,115,48,57]/1(c[91,124,93]/2(c[116,97,95,108,97,116]/2(a[97],c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil)))),c[91,124,93]/2(c[116,97,95,108,97,116]/2(a[98],c[91,124,93]/2(i7,nil)),nil)))",
    "t_tas10 c[116,95,116,97,115,49,48]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil)))),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[98]),c[91,124,93]/2(i7,nil)),a[116,114,117,101]),nil)))",
    "t_tas11 c[116,95,116,97,115,49,49]/1(c[91,124,93]/2(c[116,97,95,112,111]/2(a[97],i1),c[91,124,93]/2(c[116,97,95,112,111]/2(a[98],i0),nil)))",
    "t_tas12 c[116,95,116,97,115,49,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),i1),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[98]),i0),a[116,114,117,101]),nil)))",
    "t_tas13 c[116,95,116,97,115,49,51]/1(c[91,124,93]/2(c[116,97,95,116,119,111]/3(a[97],i3,i7),nil))",
    "t_tas14 c[116,95,116,97,115,49,52]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),c[115]/2(i3,i7)),a[116,114,117,101]),nil))",
    "t_tas15 c[116,95,116,97,115,49,53]/1(i3)",
    "t_tas16 c[116,95,116,97,115,49,54]/1(i5)",
    "t_tas17 c[116,95,116,97,115,49,55]/1(i2)",
    "t_tas18 c[116,95,116,97,115,49,56]/1(c[114,97,105,115,101,100]/1(c[117,110,105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]/1(i3)))",
    "t_tas19 c[116,95,116,97,115,49,57]/1(c[114,97,105,115,101,100]/1(c[117,110,105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]/1(i1)))",
    "t_tas20 c[116,95,116,97,115,50,48]/1(a[110,111])",
    "t_tas21 c[116,95,116,97,115,50,49]/1(a[99,111,109,112,108,101,116,101])",
    "t_tas22 c[116,95,116,97,115,50,50]/1(a[121,101,115])",
    "t_tas23 c[116,95,116,97,115,50,51]/1(i3)",
    "t_tas24 c[116,95,116,97,115,50,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,101,108,97,121,95,108,105,115,116],c[45]/1(a[102,111,111]))))"
]

"The program text with the cases appended."
_ta_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _ta_load(program::String, cases=_TA_CASES)
    f = joinpath(mktempdir(), "tabling_answers.pl")
    write(f, _ta_text(program, cases))
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

"Every row of the file, asked of one kernel in order: `(program loaded line, row lines)`."
function _ta_kernel_lines()
    gd, ld, st = _ta_load(_TA_PROGRAM)
    return st, String[_ta_ask(gd, ld, "t_$id") for (id, _) in _TA_CASES]
end
const _TA_CACHE = Ref{Any}(nothing)
"The kernel's lines, computed once (inside the first testset, so a load error is a test failure)."
_ta_kernel() = (_TA_CACHE[] === nothing && (_TA_CACHE[] = _ta_kernel_lines()); _TA_CACHE[])

"The rows of group `grp` (`taq`, `taa`, `tas`): `(kernel line, pinned line)`."
function _ta_group(grp::String)
    ids = [id for (id, _) in _TA_CASES]
    return [
        (_ta_kernel()[2][i], _TA_PINNED[i + 1]) for
        i in eachindex(ids) if startswith(ids[i], grp)
    ]
end

@testset "the answer predicates as swipl's (taq: registered, errors, an empty trie)" begin
    @test _ta_kernel()[1] == "ok"
    @test length(_ta_kernel()[2]) + 1 == length(_TA_PINNED)
    rows = _ta_group("taq")
    @test length(rows) == 13
    for (k, p) in rows
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # white-box: the registration table (pl-tabling.c:12749, :12790-12791), upstream's flags
    ext = Dict((e.predicate_name, e.arity) => e for e in LK.PL_predicates_from_tabling)
    @test haskey(ext, ("\$tbl_wkl_add_answer", 4))
    @test haskey(ext, ("\$tbl_answer", 3))
    @test haskey(ext, ("\$tbl_answer_c", 4))
    @test (ext[("\$tbl_answer", 3)].flags & LK.PL_FA_NONDETERMINISTIC) != 0
    @test (ext[("\$tbl_answer_c", 4)].flags & LK.PL_FA_NONDETERMINISTIC) != 0
    @test (ext[("\$tbl_wkl_add_answer", 4)].flags & LK.PL_FA_NONDETERMINISTIC) == 0
end

# RUNS ONCE TB2 AND TB5 ARE STACKED (header)
@testset "the answers of a completed table as swipl's (taa: '\$tbl_answer'/3)" begin
    rows = _ta_group("taa")
    @test length(rows) == 11
    for (k, p) in rows
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

# RUNS ONCE TB2 AND TB5 ARE STACKED (header)
@testset "answer subsumption as swipl's (tas: max, min, first, last, lattice, po, two moded arguments)" begin
    rows = _ta_group("tas")
    @test length(rows) == 24
    for (k, p) in rows
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

# TB3K-S (kills TB3-S15; audit D-0635): the action `done` of `'$tabling':update/7`. boot/tabling.pl:837-860 (the only clauses of `update/7`)
# bind the action to `delete` or `keep`, so `done` ("stop the update process", :831) never arises from a table that uses the boot code: the
# mutant that no longer recognises `done` (replace instead of stop) cannot differ on `ta_max` and its kin. This program redefines
# `'$tabling':update/7` in system mode (`abolish`, `assertz`; swipl 10.1.20 accepts it, probed) to a user predicate that picks the action,
# so the kernel's branch for `done` is run. A SEPARATE program (its own kernel and its own swipl run): the redefinition is global.
# `s15`: every later answer meets the stored one with `done` (Next = the new value): the stored answer stays (a, 1); a mutant that does not
# recognise `done` replaces it each time (a, 2).
# TB3-S17 (DONE stops the map of the secondary nodes; the mutant goes on): `s17` first stores p, then q with `keep` (two secondary nodes
# p and q below the root a: the po table of the handoff keeps one answer, `ta_po`, so the update/7 of this program makes the two nodes);
# the answer r meets the nodes: the FIRST call of update/7 for r answers `done`, the second `keep` (a global flag, so the row does not
# depend on the order in which the trie visits the two nodes). Stopping at `done` leaves {p, q}. NOTE (audit, evidence/TAB1/s17_read.md):
# with GROUND moded values (p, q) tbk03/tbk04 do NOT tell the walk that goes on from the one that stops: the argument block of
# update_subsuming_answers is built once and the old-moded-arguments slot (av+3) is UNIFIED with the first node and keeps that binding,
# so the second node (q) fails to unify, update/7 is never called for it and both walks end with {p, q}. tbk09 (s17v, below) is the row
# that kills TB3-S17: the first node holds a VARIABLE (f(_)), the stale slot still unifies with the next node and update/7 is called.
# UNVERIFIED on the kernel (written without a Julia run): the redefinition route (`'$tabling':abolish/1` + `assertz/1` at access level
# system) is the first thing the verifier checks; the pins are swipl's.
const _TBK_PROGRAM = raw"""
% The redefinition is scoped to a row: `tb3k_run/1` saves the original clauses of `'$tabling':update/7` and the access level, redefines
% the predicate, runs the goal and puts the original clauses and the level back in a CLEANUP, so it runs on success, on failure and on an
% exception. The save is the SETUP (safe steps only, once per program: `nb_current` guards a second save from copying the redefinition);
% the redefinition is inside the guarded goal, so a half-done redefinition is undone as well. tbk05-tbk08 (a second group, below) prove the original is back.
tb3k_save(Old) :-
    current_prolog_flag(access_level, Old),
    (   nb_current(tb3k_saved, _)
    ->  true
    ;   set_prolog_flag(access_level, system),
        setup_call_cleanup(true, tb3k_clauses(L), set_prolog_flag(access_level, Old)),
        nb_setval(tb3k_saved, L)
    ).
tb3k_clauses(L) :-
    findall((update(A, B, C, D, E, F, G) :- Bd), '$tabling':clause(update(A, B, C, D, E, F, G), Bd), L).
tb3k_redef :-
    set_prolog_flag(access_level, system),
    '$tabling':abolish(update/7),
    '$tabling':assertz((update(_, W, _, Agg, New, Next, Act) :- user:tb3k_upd(W, Agg, New, Next, Act))).
tb3k_restore(Old) :-
    nb_getval(tb3k_saved, L),
    set_prolog_flag(access_level, system),
    setup_call_cleanup(true, tb3k_put_back(L), set_prolog_flag(access_level, Old)).
tb3k_put_back(L) :-
    '$tabling':abolish(update/7),
    forall(member(Cl, L), '$tabling':assertz(Cl)).
tb3k_run(G) :-
    setup_call_cleanup(tb3k_save(Old), (tb3k_redef, G), tb3k_restore(Old)).
:- discontiguous tb3k_upd/5.
tb3k_upd(s15(_, _), _, New, New, done).
:- table s15(_, max).
s15(a, 1).
s15(a, 3).
s15(a, 2).
tb3k_upd(s17(_, _), p, q, q, keep) :- !.
:- dynamic tb3k_seen/0.
tb3k_upd(s17(_, _), _, r, r, Act) :-
    (   tb3k_seen
    ->  Act = keep
    ;   assertz(tb3k_seen), Act = done
    ).
:- table s17(_, max).
s17(a, p).
s17(a, q).
s17(a, r).
% tbk09 (kills TB3-S17): the FIRST secondary node has a variable moded argument, f(_). f(b) meets it and `keep`s (two nodes f(_), f(b));
% f(c) meets a node: the first call of update/7 for f(c) answers `done` (flag), every later call `keep`. Stopping at `done` leaves
% {f(_), f(b)} (count 2); a walk that goes on reaches the other node (the stale old-arguments slot still unifies: f(V), V := b), gets `keep`
% and adds f(c) (count 3). The same text runs in swipl (pin), the count is 2 there.
:- dynamic tb3k_seenv/0.
tb3k_upd(s17v(_, _), _, f(b), f(b), keep) :- !.
tb3k_upd(s17v(_, _), _, f(c), f(c), Act) :-
    (   tb3k_seenv -> Act = keep ; assertz(tb3k_seenv), Act = done ).
:- table s17v(_, max).
s17v(a, f(_)).
s17v(a, f(b)).
s17v(a, f(c)).
tb3k_cntv(N) :- findall(x, s17v(_, _), L), length(L, N).
% the rows after the redefinitions (tbk05-tbk08): the guard ran on failure and on an exception too; a plain moded table whose update/7 is the
% BOOT code (`max`: both answers unconditional, the first clause, Act = delete) gives max again; the clauses of update/7 are the saved ones
% (non-empty list, 4 clauses: boot/tabling.pl:837, :844, :852, :859); the access level is back.
tb3k_guard(F-X) :-
    (   tb3k_run(fail) -> F = yes ; F = no ),
    catch(tb3k_run(throw(tb3k_x)), tb3k_x, X = caught).
tb3k_restored(N-Same) :-
    nb_getval(tb3k_saved, L0),
    current_prolog_flag(access_level, Old),
    set_prolog_flag(access_level, system),
    setup_call_cleanup(true, tb3k_clauses(L1), set_prolog_flag(access_level, Old)),
    length(L1, N),
    N > 0,
    (   L0 =@= L1 -> Same = true ; Same = false ).
:- table p15(_, max).
p15(a, 1).
p15(a, 3).
p15(a, 2).
ta_vars(K, T) :- '$tbl_variant_table'(VT), trie_gen(VT, K, T).
ta_tab(K0, T) :- ta_vars(user:K, T), K =@= K0.
ta_moded(K, L) :- findall(S-M-C, (ta_tab(K, T), trie_gen(T, S), '$tbl_answer_c'(T, S, M, C)), L0), msort(L0, L).
ta_all(G, L) :- findall(G, G, L0), msort(L0, L).
"""

const _TBK_CASES = [
    ("tbk01", raw"tb3k_run(ta_all(s15(_, _), R))"),
    ("tbk02", raw"ta_moded('$s15$1'(_), R)"),
    ("tbk03", raw"tb3k_run(ta_all(s17(_, _), R))"),
    ("tbk04", raw"ta_moded('$s17$1'(_), R)"),
    ("tbk05", raw"tb3k_guard(R)"),
    ("tbk06", raw"ta_all(p15(_, _), R)"),
    ("tbk07", raw"tb3k_restored(R)"),
    ("tbk08", raw"current_prolog_flag(access_level, R)"),
    ("tbk09", raw"tb3k_run(tb3k_cntv(R))")
]

const _TBK_PINNED = [
    "ok",
    "t_tbk01 c[116,95,116,98,107,48,49]/1(c[91,124,93]/2(c[115,49,53]/2(a[97],i1),nil))",
    "t_tbk02 c[116,95,116,98,107,48,50]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),i1),a[116,114,117,101]),nil))",
    "t_tbk03 c[116,95,116,98,107,48,51]/1(c[91,124,93]/2(c[115,49,55]/2(a[97],a[112]),c[91,124,93]/2(c[115,49,55]/2(a[97],a[113]),nil)))",
    "t_tbk04 c[116,95,116,98,107,48,52]/1(c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),a[112]),a[116,114,117,101]),c[91,124,93]/2(c[45]/2(c[45]/2(c[114,101,116]/1(a[97]),a[113]),a[116,114,117,101]),nil)))",
    "t_tbk05 c[116,95,116,98,107,48,53]/1(c[45]/2(a[110,111],a[99,97,117,103,104,116]))",
    "t_tbk06 c[116,95,116,98,107,48,54]/1(c[91,124,93]/2(c[112,49,53]/2(a[97],i3),nil))",
    "t_tbk07 c[116,95,116,98,107,48,55]/1(c[45]/2(i4,a[116,114,117,101]))",
    "t_tbk08 c[116,95,116,98,107,48,56]/1(a[117,115,101,114])",
    "t_tbk09 c[116,95,116,98,107,48,57]/1(i2)"
]

const _TBK_CACHE = Ref{Any}(nothing)
"The kernel's lines of the TB3K-S program: `(program loaded line, one line per case)`, computed once."
function _tbk_kernel()
    if _TBK_CACHE[] === nothing
        gd, ld, st = _ta_load(_TBK_PROGRAM, _TBK_CASES)
        _TBK_CACHE[] = (st, String[_ta_ask(gd, ld, "t_$id") for (id, _) in _TBK_CASES])
    end
    return _TBK_CACHE[]
end

@testset "TB3K-S: the action `done` of update/7 stops the update (kills TB3-S15, TB3-S17)" begin
    @test _tbk_kernel()[1] == "ok"
    @test length(_tbk_kernel()[2]) + 1 == length(_TBK_PINNED)
    @test !isempty(_tbk_kernel()[2])
    for (i, (id, _)) in enumerate(_TBK_CASES)
        k, p = _tbk_kernel()[2][i], _TBK_PINNED[i + 1]
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    pin(id) = only(filter(l -> startswith(l, "t_$id "), _TBK_PINNED))
    # not vacuous: `done` kept the FIRST answer (1); `max`, or the mutant's replace, would give 3 or 2
    @test endswith(pin("tbk01"), "(a[97],i1),nil))")
    @test !occursin("i3", pin("tbk01")) && !occursin("i2", pin("tbk01"))
    # S17: two secondary nodes below the root (the `keep` of q), and the answer r was refused (`done` stopped the walk)
    @test count("c[114,101,116]/1(a[97])", pin("tbk04")) == 2
    @test !occursin("a[114]", pin("tbk03")) && !occursin("a[114]", pin("tbk04"))
    @test occursin("a[112]", pin("tbk03")) && occursin("a[113]", pin("tbk03"))
    # S17, the row that kills it (tbk09: the first secondary node holds a variable): the answer f(c) was refused, the table holds f(_) and
    # f(b), 2 answers (swipl's); the walk that goes on (the mutant) adds f(c): 3. Both sides non-empty, and the corruption (2 -> 3, what
    # the mutant returns) differs from the pin, so a kernel line with 3 cannot pass `k == p` above.
    @test endswith(pin("tbk09"), "/1(i2)")
    @test !isempty(_tbk_kernel()[2][findfirst(==("tbk09"), first.(_TBK_CASES))])
    s17(l) = replace(l, "/1(i2)" => "/1(i3)"; count=1)
    @test s17(pin("tbk09")) != pin("tbk09") && endswith(s17(pin("tbk09")), "/1(i3)")
end

# TB3K-S restore (audit D-0641 item 3): the rows tbk01/tbk03 redefine `'$tabling':update/7`; these four run AFTER them and prove the boot
# definition is back: tbk05 the guard ran on a failing and on a throwing goal, tbk06 a plain `max` table (boot update/7, first clause, delete)
# gives max again, tbk07 the clauses of update/7 are the saved ones (4 clauses: boot/tabling.pl:837, :844, :852, :859), tbk08 the access level.
@testset "TB3K-S: update/7 is back after the redefinitions (call-cleanup restore)" begin
    pin(id) = only(filter(l -> startswith(l, "t_$id "), _TBK_PINNED))
    @test [id for (id, _) in _TBK_CASES] == ["tbk0$i" for i in 1:9]
    ids = ["tbk05", "tbk06", "tbk07", "tbk08"]
    rows = [
        (_tbk_kernel()[2][findfirst(==(id), first.(_TBK_CASES))], pin(id)) for id in ids
    ]
    @test length(rows) == 4 && all(!isempty(k) && !isempty(p) for (k, p) in rows)
    for (k, p) in rows
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: failure and exception both left the guard (`no`, `caught`); max is 3 (a mutant that does not put the clauses back gives
    # 1 here: tb3k_upd has no clause for p15); the saved list has 4 clauses and equals the current one; the level is `user`
    @test occursin("a[110,111],a[99,97,117,103,104,116]", pin("tbk05"))
    @test endswith(pin("tbk06"), "(a[97],i3),nil))")
    @test endswith(pin("tbk07"), "c[45]/2(i4,a[116,114,117,101]))")
    @test endswith(pin("tbk08"), "a[117,115,101,114])")
end

# TB3-S9 (kills the mutant that drops the `update_delay_list(...) == UDL_FALSE` refusal in add_subsuming_answer, pl-tabling.c:5053-5056,
# kernel src/pl-tabling.jl :4374-4375). Every row that reaches add_subsuming_answer through `'$tbl_reset'` (tas24) cannot see it: the caller
# `tbl_reset_add_answer` reads only `rcadd == TBL_ANSWER_COMPLETE` and the pending exception is thrown either way. The caller that can is
# `'$tbl_wkl_add_answer'/4` called AS A PREDICATE (pl-tabling.c:4886-4899): it returns `!!rc`; with the refusal rc = 0, FALSE with the type
# error pending, so the call RAISES; without it rc = TBL_ANSWER_NEW, TRUE with the error pending, and `I_FEXITDET` clears it ("false alarm",
# pl-vmi.c:4515-4518): the call SUCCEEDS and the error is swallowed. The rows call it on the worklist of a FRESH moded table, from an outermost
# wrapper (`'$c_wrap_predicate'/5`, as test_tabling_min_swipl.jl:96-99 tm_wrapb does) built from `'$tbl_moded_variant_table'/6`, with a delay
# list `foo` (not a list) set. tbw01 = first answer (path 1 of add_subsuming_answer, :5242-5251); tbw02 = a clean first answer, then the
# delay list `foo` and a second answer 7 (the update path: update_subsuming_answers -> update_subsuming_answer -> add_subsuming_answer, :5128);
# tbw03 = the control: a clean answer succeeds (`ok(_)`, delay list `[]`). Each row has its OWN key (k1, k2, k3): the wrapper leaves the fresh
# table incomplete (the shape of the probe run in swipl), so a key is used once. Its own program and kernel: the wrapper is global.
const _TBW_PROGRAM = raw"""
:- dynamic ta_s9_res/2.
:- table ta_wq(_, max).
ta_wq(_, 1).
ta_s9_steps(k1, [foo-5]).
ta_s9_steps(k2, [[]-5, foo-7]).
ta_s9_steps(k3, [[]-5]).
ta_s9_add(K, Closure) :-
    '$tbl_moded_variant_table'(Closure, ta_wq(K), Trie, Status, Skel, _Mono),
    (   Status = fresh(_SCC, WL)
    ->  ta_s9_steps(K, Steps),
        ta_s9_job(Steps, WL, Skel, Rs),
        '$tbl_delay_list'(DL),
        '$tbl_set_delay_list'([]),
        findall(S-V, '$tbl_answer'(Trie, S, V, _), L),
        assertz(ta_s9_res(K, r(Rs, DL, L)))
    ;   assertz(ta_s9_res(K, notfresh))
    ).
ta_s9_job([], _, _, []).
ta_s9_job([D-V|Ss], WL, Skel, [R|Rs]) :-
    '$tbl_set_delay_list'(D),
    catch(( '$tbl_wkl_add_answer'(WL, (Skel/V), [], C), R = ok(C) ), E, R = ex(E)),
    ta_s9_job(Ss, WL, Skel, Rs).
:- '$c_wrap_predicate'(user:ta_wq(_, _), ta_s9_w, Closure, _W,
       user:('$wrap$ta_wq'(K, _) :- ta_s9_add(K, Closure))).
ta_s9_run(K, R) :- ( ta_wq(K, _) -> true ; true ), ta_s9_res(K, R).
"""

const _TBW_CASES = [
    ("tbw01", raw"ta_s9_run(k1, R)"),
    ("tbw02", raw"ta_s9_run(k2, R)"),
    ("tbw03", raw"ta_s9_run(k3, R)")
]

# swipl 18168e62 (10.1.20), `LC_ALL=C swipl -q`, the file's driver, two byte-identical runs (evidence/TAB1/s9_row_notes.md)
const _TBW_PINNED = [
    "ok",
    "t_tbw01 c[116,95,116,98,119,48,49]/1(c[114]/3(c[91,124,93]/2(c[101,120]/1(c[101,114,114,111,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,101,108,97,121,95,108,105,115,116],c[45]/1(a[102,111,111])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[36,116,98,108,95,119,107,108,95,97,100,100,95,97,110,115,119,101,114],i4)),V0))),nil),a[102,111,111],c[91,124,93]/2(c[45]/2(a[114,101,116],i5),nil)))",
    "t_tbw02 c[116,95,116,98,119,48,50]/1(c[114]/3(c[91,124,93]/2(c[111,107]/1(V0),c[91,124,93]/2(c[101,120]/1(c[101,114,114,111,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,101,108,97,121,95,108,105,115,116],c[45]/1(a[102,111,111])),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[36,116,98,108,95,119,107,108,95,97,100,100,95,97,110,115,119,101,114],i4)),V1))),nil)),a[102,111,111],c[91,124,93]/2(c[45]/2(a[114,101,116],i5),c[91,124,93]/2(c[45]/2(a[114,101,116],i7),nil))))",
    "t_tbw03 c[116,95,116,98,119,48,51]/1(c[114]/3(c[91,124,93]/2(c[111,107]/1(V0),nil),nil,c[91,124,93]/2(c[45]/2(a[114,101,116],i5),nil)))"
]

const _TBW_CACHE = Ref{Any}(nothing)
"The kernel's lines of the TB3-S9 program: `(program loaded line, one line per case)`, computed once."
function _tbw_kernel()
    if _TBW_CACHE[] === nothing
        gd, ld, st = _ta_load(_TBW_PROGRAM, _TBW_CASES)
        _TBW_CACHE[] = (st, String[_ta_ask(gd, ld, "t_$id") for (id, _) in _TBW_CASES])
    end
    return _TBW_CACHE[]
end

@testset "TB3-S9: '\$tbl_wkl_add_answer'/4 with a pending delay-list type error refuses (raises), not swallows (kills TB3-S9)" begin
    @test _tbw_kernel()[1] == "ok"
    @test length(_tbw_kernel()[2]) + 1 == length(_TBW_PINNED)
    @test !isempty(_tbw_kernel()[2])
    for (i, (id, _)) in enumerate(_TBW_CASES)
        k, p = _tbw_kernel()[2][i], _TBW_PINNED[i + 1]
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    pin(id) = only(filter(l -> startswith(l, "t_$id "), _TBW_PINNED))
    # the delay-list error in the encoding: ex(error(type_error(delay_list, -(foo)), context(system:'\$tbl_wkl_add_answer'/4, _)))
    err = "c[101,120]/1(c[101,114,114,111,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,101,108,97,121,95,108,105,115,116],c[45]/1(a[102,111,111]))"
    ok1 = "c[111,107]/1("
    # not vacuous: tbw01 is the raised error and NOT an `ok`; tbw02 is `ok` for the clean answer, the error for the one with `foo`;
    # tbw03 (the control) is `ok` and no error; the delay list stays `foo` after the refusal, the answers are in the trie in both
    @test occursin(err, pin("tbw01")) && !occursin(ok1, pin("tbw01"))
    @test occursin(err, pin("tbw02")) && count(ok1, pin("tbw02")) == 1
    @test occursin("c[114]/3(c[91,124,93]/2(c[111,107]/1(", pin("tbw02"))      # the clean one comes FIRST, the error second
    @test occursin(ok1, pin("tbw03")) && !occursin(err, pin("tbw03"))
    @test occursin("a[102,111,111],c[91,124,93]/2(c[45]/2(a[114,101,116],i5)", pin("tbw01"))
    # the MUST-FAIL corruptions (what TB3-S9 returns: the error replaced by `ok(_)`): the corrupted line differs from the pin, so a kernel
    # line that swallowed the error cannot pass `k == p`
    s9(l) = replace(l, "c[101,120]/1(" => "c[111,107]/1("; count=1)
    @test s9(pin("tbw01")) != pin("tbw01")
    @test s9(pin("tbw02")) != pin("tbw02")
    @test s9(pin("tbw03")) == pin("tbw03")      # the control has nothing to corrupt: it is `ok` under the mutant too
    @test occursin(ok1, s9(pin("tbw01"))) && !occursin(err, s9(pin("tbw01")))
end

@testset "TB3-S9: the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB3-S9 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test _TBW_PINNED[1] == "ok"
        @test [first(split(l, " ")) for l in _TBW_PINNED[2:end]] ==
            ["t_$id" for (id, _) in _TBW_CASES]
    else
        f = joinpath(mktempdir(), "tbw_swipl.pl")
        write(f, _ta_text(_TBW_PROGRAM, _TBW_CASES))
        @test _ta_swipl_lines(f, ["t_$id" for (id, _) in _TBW_CASES]) == _TBW_PINNED
    end
end

# TB3K-1 (WHITE-BOX; kills TB3-C7, TB3-V2, TB3-V3; audit D-0635). None of the taa/tas rows can see these three: the answer list of the
# second call is the same under each mutant (the compiled clause reads its key from argument 1, `S_TABLED` uses the local `st_clref`,
# and the frame's predicate and the first choice point's position are read by no answer). So the row reads the frame itself, the way
# test_context_module_swipl.jl and test_rules_swipl.jl read `ld.frames[q.frame]`. The Prolog route is not usable (no
# `prolog_frame_attribute/3` here), so there is no swipl line for it: the expected values are `pl-vmi.c` S_TABLED/TRUST_CLAUSE as written.
# UNVERIFIED on the kernel when written (no Julia was run): the first run decides the V2 formula (the alternative is in the handoff).
# BOUNDED (audit D-0661 item 1): under TB3-V2/TB3-V3 this row once hung the daemon (a TIMEOUT is not a kill). The state is read FIRST and ONLY
# into plain Bool/Int values (a failing `@test` of a struct would print the whole kernel), the choice-chain walk has an iteration cap, the
# query is closed only when every check passed (a mutant leaves a frame that must not be walked further), and the whole body runs in a task
# with a DEADLINE: a mutant that hangs fails `@test finished` in `_TB3K1_DEADLINE_S` seconds instead of the driver's TIMEOUT.
const _TB3K1_DEADLINE_S = 30
function _tb3k1_state!(st::Dict{Symbol, Any})
    st[:stage] = 0
    gd, ld, ld_st = _ta_load(_TA_PROGRAM)
    st[:load] = ld_st == "ok"
    first_line = _ta_ask(gd, ld, "ta_p")                  # the first call runs the table to completion (3 answers)
    st[:first] = first_line != "ta_p undefined" && count(' ', first_line) >= 3
    proc = LK.isCurrentProcedure(sym_key(_tas("ta_p")), 1, LK.MODULE_user(gd))
    st[:proc] = proc !== nothing
    st[:stage] = 1
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TA, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    q = ld.queries[LK.QueryFromQid(ld, qid)]
    st[:rc] = LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE    # one answer of three: a choice point is left
    fr = ld.frames[q.frame]
    tgc = gd.procedures_trie_gen_compiled2.definition
    st[:pred] = fr.predicate !== nothing && fr.predicate === tgc  # V3: setFramePredicate(FR, DEF)
    w = ld.slots[LK._frame_arg_slot(ld, q.frame, 0)]              # C7: *argFrameP(FR, 0) = the clause atom
    st[:atom] = LK.isAtomW(w)
    cl = st[:atom] ? LK.clause_clref(gd, LK._atom_value(ld, w)) : nothing
    st[:clause] = cl !== nothing && cl.predicate === tgc          # the atom names a clause of trie_gen_compiled/2
    st[:stage] = 2
    # V2: TRUST_CLAUSE sets lTop = ARGP + clause.variables (pl-vmi.c), so the oldest choice point of this frame sits there
    ch = ld.BFR
    steps = 0
    while steps < 1000 && ld.choices[ch].parent != 0 &&
          ld.choices[ld.choices[ch].parent].frame == q.frame
        ch = ld.choices[ch].parent
        steps += 1
    end
    st[:capped] = steps >= 1000
    st[:chfr] = ld.choices[ch].frame == q.frame
    st[:base] =
        cl !== nothing &&
        ld.choices[ch].base == LK.argFrameP(fr.base, 0) + Int(cl.variables)
    st[:stage] = 3
    if all(
        st[k] === true for
        k in (:load, :first, :proc, :rc, :pred, :atom, :clause, :chfr, :base)
    ) && !st[:capped]
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    st[:stage] = 4
    return nothing
end

@testset "TB3K-1 white-box: the frame of the second call of a complete table runs trie_gen_compiled/2 (S_TABLED)" begin
    st = Dict{Symbol, Any}(:stage => -1)
    task = Threads.@spawn try
        _tb3k1_state!(st)
    catch e
        st[:error] = sprint(showerror, e)
    end
    finished = timedwait(() -> istaskdone(task), Float64(_TB3K1_DEADLINE_S)) === :ok
    @test finished                      # a hang is a FAILURE of this row within the deadline, not a driver TIMEOUT
    @test !haskey(st, :error)
    for k in (:load, :first, :proc, :rc)
        @test get(st, k, false) === true
    end
    @test get(st, :pred, false) === true       # V3
    @test get(st, :atom, false) === true       # C7
    @test get(st, :clause, false) === true     # C7
    @test get(st, :capped, true) === false     # the chain walk ended inside its cap
    @test get(st, :chfr, false) === true       # V2: the oldest choice point of the frame ...
    @test get(st, :base, false) === true       # ... sits at argFrameP(FR, 0) + clause.variables
    @test get(st, :stage, -1) == 4
end

@testset "the answer rows are not vacuous" begin
    @test _TA_PINNED[1] == "ok"
    @test length(_TA_PINNED) == length(_TA_CASES) + 1
    for pre in ("taq", "taa", "tas")
        ids = [id for (id, _) in _TA_CASES if startswith(id, pre)]
        @test !isempty(ids)
        @test length([l for l in _TA_PINNED if any(id -> startswith(l, "t_$id "), ids)]) ==
            length(ids)
    end
    line(id) = only(filter(l -> startswith(l, "t_$id "), _TA_PINNED))
    ans(id) = split(line(id), "/1("; limit=2)[2]   # the answer, not the row's name
    @test ans("tas01") != ans("tas03")      # max keeps 3 of 1,3,2; min keeps 3 of 4,3,9 for `a` but 5 for `b`: different tables
    @test ans("tas05") != ans("tas07")      # first keeps x, last keeps y
    @test ans("tas11") != ans("tas01")      # po(ta_lt/2) is not max
    @test ans("tas09") != ans("tas01")      # lattice(ord_union) joins the lists
    @test ans("tas02") != ans("tas01")      # '$tbl_answer_c'/4: skeleton, moded value, condition
    @test ans("taa01") != ans("taa02")      # ret(V) answers against the ground call's `ret`
    @test ans("taa02") != ans("taa03")      # one answer, none
    @test ans("taa07") == ans("taa10")      # a condition `true`
    @test ans("tas18") != ans("tas15")      # a bound moded argument: uninstantiation_error, not an answer
    # tas24 is the raised error of the delay list, not an answer list (pinned through '$tbl_reset'; TB3-S9 is killed by tbw01-tbw03)
    @test startswith(ans("tas24"), "c[114,97,105,115,101,100]/1(")
    @test !occursin("c[91,124,93]", ans("tas24"))
    @test ans("tas24") != ans("tas19")
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB3 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        @test _TA_PINNED[1] == "ok"
        @test [first(split(l, " ")) for l in _TA_PINNED[2:end]] ==
            ["t_$id" for (id, _) in _TA_CASES]
        @test _TBK_PINNED[1] == "ok"
        @test [first(split(l, " ")) for l in _TBK_PINNED[2:end]] ==
            ["t_$id" for (id, _) in _TBK_CASES]
    else
        f = joinpath(mktempdir(), "ta_swipl.pl")
        write(f, _ta_text(_TA_PROGRAM, _TA_CASES))
        @test _ta_swipl_lines(f, ["t_$id" for (id, _) in _TA_CASES]) == _TA_PINNED
        g = joinpath(mktempdir(), "tbk_swipl.pl")
        write(g, _ta_text(_TBK_PROGRAM, _TBK_CASES))
        @test _ta_swipl_lines(g, ["t_$id" for (id, _) in _TBK_CASES]) == _TBK_PINNED
    end
end
