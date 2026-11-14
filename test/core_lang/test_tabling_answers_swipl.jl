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
    )
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
    "t_tas23 c[116,95,116,97,115,50,51]/1(i3)"
]

"The program text with the cases appended."
_ta_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _ta_load(program::String)
    f = joinpath(mktempdir(), "tabling_answers.pl")
    write(f, _ta_text(program, _TA_CASES))
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
    @test length(rows) == 23
    for (k, p) in rows
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
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
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB3 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        @test _TA_PINNED[1] == "ok"
        @test [first(split(l, " ")) for l in _TA_PINNED[2:end]] ==
            ["t_$id" for (id, _) in _TA_CASES]
    else
        f = joinpath(mktempdir(), "ta_swipl.pl")
        write(f, _ta_text(_TA_PROGRAM, _TA_CASES))
        @test _ta_swipl_lines(f, ["t_$id" for (id, _) in _TA_CASES]) == _TA_PINNED
    end
end
