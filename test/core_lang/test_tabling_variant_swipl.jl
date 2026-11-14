# ORIGINAL: a LIVE differential of the variant tables of pl-tabling.c (TAB1 TB1; audit D-0477) against swipl at the pin
# (swipl-devel 18168e62, 10.1.20): `'$tbl_existing_variant_table'/5`, `'$tbl_table_status'/2,4`, `'$tbl_table_pi'/2`,
# `'$is_answer_trie'/2`, `'$tbl_local_variant_table'/1`, `'$tbl_global_variant_table'/1`, `'$tbl_variant_table'/1`,
# `'$tbl_implementation'/2`, `'$tnot_implementation'/2` (pl-tabling.c:6057-6200, :7302-7392). Groups: tvb = before any table,
# tvv = `$tbl_existing_variant_table`, tvs = the status, tvp = the predicate indicator, tvt = the trie, tvl = the variant table
# (the local and the global one), tvi = `$tbl_implementation`, tvn = `$tnot_implementation`.
#   * swipl makes its tables by calling a tabled predicate (`:- table tv_p/1`, then `tv_p(1)` and `tv_p(_)` called); the kernel has no
#     `start_tabling` (the create path of `$tbl_variant_table/6` is refused by name, owner TB2): it marks `tv_p/1` tabled and the
#     TEST makes the two tables white-box (`get_answer_table` with `AT_CREATE`, then `TRIE_COMPLETE`): the same variant tries and
#     answer tries, so every row below reads the same state in both. A trie is never printed (the blob's address differs).
#   * Cases `t_<id>(R)` run in order in one database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is
#     test_tabling_min_swipl.jl's (`enc`oded answers). The tvb rows run BEFORE the tables are made (a database without a variant table).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, two byte-identical runs; evidence/TB1/tv_gen.py makes this file from
#     tv_template.jl); with `swipl` on PATH the live answers are compared with the pins too.
#   * Rows left out: `'$tbl_existing_variant_table'(0, _, ...)` with an unbound variant and `'$tbl_table_pi'/2` of the variant
#     table itself: the pin gives no answer there, so there is nothing to pin.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TV = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tvs(x) = lk_sym(_TV, Symbol(x))

_tv_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tv_enc(t::_TV, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tv_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tv_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tv_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tv_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TV_DRIVER = raw"""
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

function _tv_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TV_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

const _TV_COMMON = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tm_same(A, B, R) :- ( A == B -> R = same ; R = diff ).
tv_p(1).
tv_p(2).
tv_q(1).
:- dynamic tv_d/1.
tv_tab(V, T) :- '$tbl_existing_variant_table'(0, V, T, _, _).
tv_variants(K, T) :- '$tbl_variant_table'(VT), trie_gen(VT, K, T).
"""
# the kernel marks `tv_p/1` tabled (`is_tabled`); the tables are made by `_tv_tables!`
const _TV_KERNEL = raw"""
:- '$set_predicate_attribute'(tv_p(_), tabled, true).
"""
const _TV_SWIPL = raw"""
:- table tv_p/1.
:- tv_p(1), tv_p(_).
"""
const _TV_SWIPL_PRE = _TV_COMMON * ":- table tv_p/1.\n"

const _TV_PRE_CASES = [
    ("tvb01", raw"tm_yn('$tbl_local_variant_table'(_), R)"),
    ("tvb02", raw"tm_yn('$tbl_global_variant_table'(_), R)"),
    ("tvb03", raw"tm_yn('$tbl_variant_table'(_), R)"),
    ("tvb04", raw"tm_yn('$tbl_existing_variant_table'(0, user:tv_p(1), _, _, _), R)"),
    ("tvb05", raw"tm_yn('$tbl_local_variant_table'(_), R)"),
    ("tvb06", raw"'$tbl_local_variant_table'(V), tm_yn(is_trie(V), R)")
]
const _TV_CASES = [
    ("tvv01", raw"'$tbl_existing_variant_table'(0, user:tv_p(1), _, S, Sk), R = r(S, Sk)"),
    ("tvv02", raw"'$tbl_existing_variant_table'(0, user:tv_p(_), _, S, Sk), R = r(S, Sk)"),
    ("tvv03", raw"tm_yn('$tbl_existing_variant_table'(0, user:tv_p(7), _, _, _), R)"),
    (
        "tvv04",
        raw"tm_yn('$tbl_existing_variant_table'(user:tv_p(_), user:tv_p(2), _, _, _), R)"
    ),
    ("tvv05", raw"tm_yn('$tbl_existing_variant_table'(0, user:tv_p(_), _, _, _), R)"),
    ("tvv06", raw"tm_yn('$tbl_existing_variant_table'(0, user:tv_q(1), _, _, _), R)"),
    ("tvs01", raw"tv_tab(user:tv_p(1), T), '$tbl_table_status'(T, S), R = S"),
    ("tvs02", raw"tv_tab(user:tv_p(_), T), '$tbl_table_status'(T, S), R = S"),
    (
        "tvs03",
        raw"tv_tab(user:tv_p(1), T), '$tbl_table_status'(T, S, W, Sk), R = r(S, W, Sk)"
    ),
    (
        "tvs04",
        raw"tv_tab(user:tv_p(_), T), '$tbl_table_status'(T, S, W, Sk), R = r(S, W, Sk)"
    ),
    ("tvs05", raw"'$tbl_table_status'(a, _), R = ok"),
    ("tvs06", raw"'$tbl_table_status'(_, _), R = ok"),
    ("tvs07", raw"'$tbl_table_status'(a, _, _, _), R = ok"),
    ("tvs08", raw"'$tbl_variant_table'(VT), '$tbl_table_status'(VT, S), R = S"),
    ("tvp01", raw"tv_tab(user:tv_p(1), T), '$tbl_table_pi'(T, PI), R = PI"),
    ("tvp02", raw"tv_tab(user:tv_p(_), T), '$tbl_table_pi'(T, PI), R = PI"),
    ("tvp03", raw"'$tbl_table_pi'(a, _), R = ok"),
    ("tvp04", raw"tv_tab(user:tv_p(1), T), tm_yn('$tbl_table_pi'(T, user:tv_p/1), R)"),
    ("tvp05", raw"tv_tab(user:tv_p(1), T), tm_yn('$tbl_table_pi'(T, user:tv_p/2), R)"),
    ("tvt01", raw"tv_tab(user:tv_p(1), T), tm_yn(is_trie(T), R)"),
    ("tvt02", raw"tv_tab(user:tv_p(1), T), '$is_answer_trie'(T, X), R = X"),
    ("tvt03", raw"tm_yn('$is_answer_trie'(a, _), R)"),
    ("tvt04", raw"tm_yn('$is_answer_trie'(_, _), R)"),
    ("tvt05", raw"'$tbl_variant_table'(VT), tm_yn('$is_answer_trie'(VT, _), R)"),
    ("tvt06", raw"'$tbl_variant_table'(VT), tm_yn(is_trie(VT), R)"),
    ("tvt07", raw"tv_tab(user:tv_p(1), T), tv_tab(user:tv_p(1), T2), tm_same(T, T2, R)"),
    ("tvt08", raw"tv_tab(user:tv_p(1), T), tv_tab(user:tv_p(_), T2), tm_same(T, T2, R)"),
    ("tvl01", raw"tm_yn('$tbl_local_variant_table'(_), R)"),
    ("tvl02", raw"tm_yn('$tbl_global_variant_table'(_), R)"),
    ("tvl03", raw"tm_yn('$tbl_variant_table'(_), R)"),
    (
        "tvl04",
        raw"'$tbl_local_variant_table'(V1), '$tbl_variant_table'(V2), tm_same(V1, V2, R)"
    ),
    ("tvl05", raw"'$tbl_local_variant_table'(V), tm_yn(is_trie(V), R)"),
    (
        "tvl06",
        raw"findall(K-S, (tv_variants(K, T), '$tbl_table_status'(T, S)), L0), msort(L0, L), R = L"
    ),
    ("tvl07", raw"findall(K, tv_variants(K, _), L0), length(L0, N), R = N"),
    ("tvi01", raw"'$tbl_implementation'(user:tv_p(_), G), R = G"),
    ("tvi02", raw"'$tbl_implementation'(user:tv_q(_), G), R = G"),
    ("tvi03", raw"'$tbl_implementation'(user:tv_nope(_), G), R = G"),
    ("tvi04", raw"'$tbl_implementation'(tv_p(_), G), R = G"),
    ("tvi05", raw"'$tbl_implementation'(user:tv_d(_), G), R = G"),
    ("tvi06", raw"'$tbl_implementation'(1, _), R = ok"),
    ("tvi07", raw"'$tbl_implementation'(_, _), R = ok"),
    ("tvi08", raw"'$tbl_implementation'(tv_p(1), tv_p(2)), R = ok"),
    ("tvn01", raw"'$tnot_implementation'(user:tv_p(_), G), R = G"),
    ("tvn02", raw"'$tnot_implementation'(tv_p(_), G), R = G"),
    ("tvn03", raw"'$tnot_implementation'(user:tv_q(_), _), R = ok"),
    ("tvn04", raw"'$tnot_implementation'(tv_q(_), _), R = ok"),
    ("tvn05", raw"'$tnot_implementation'(user:tv_nope(_), _), R = ok"),
    ("tvn06", raw"'$tnot_implementation'(user:tv_d(_), _), R = ok"),
    ("tvn07", raw"'$tnot_implementation'(a, _), R = ok")
]

const _TV_PRE_PINNED = [
    "ok",
    "t_tvb01 c[116,95,116,118,98,48,49]/1(a[110,111])",
    "t_tvb02 c[116,95,116,118,98,48,50]/1(a[110,111])",
    "t_tvb03 c[116,95,116,118,98,48,51]/1(a[110,111])",
    "t_tvb04 c[116,95,116,118,98,48,52]/1(a[110,111])",
    "t_tvb05 c[116,95,116,118,98,48,53]/1(a[121,101,115])",
    "t_tvb06 c[116,95,116,118,98,48,54]/1(a[121,101,115])"
]
const _TV_PINNED = [
    "ok",
    "t_tvv01 c[116,95,116,118,118,48,49]/1(c[114]/2(a[99,111,109,112,108,101,116,101],a[114,101,116]))",
    "t_tvv02 c[116,95,116,118,118,48,50]/1(c[114]/2(a[99,111,109,112,108,101,116,101],c[114,101,116]/1(V0)))",
    "t_tvv03 c[116,95,116,118,118,48,51]/1(a[110,111])",
    "t_tvv04 c[116,95,116,118,118,48,52]/1(a[110,111])",
    "t_tvv05 c[116,95,116,118,118,48,53]/1(a[121,101,115])",
    "t_tvv06 c[116,95,116,118,118,48,54]/1(a[110,111])",
    "t_tvs01 c[116,95,116,118,115,48,49]/1(a[99,111,109,112,108,101,116,101])",
    "t_tvs02 c[116,95,116,118,115,48,50]/1(a[99,111,109,112,108,101,116,101])",
    "t_tvs03 c[116,95,116,118,115,48,51]/1(c[114]/3(a[99,111,109,112,108,101,116,101],c[58]/2(a[117,115,101,114],c[116,118,95,112]/1(i1)),a[114,101,116]))",
    "t_tvs04 c[116,95,116,118,115,48,52]/1(c[114]/3(a[99,111,109,112,108,101,116,101],c[58]/2(a[117,115,101,114],c[116,118,95,112]/1(V0)),c[114,101,116]/1(V0)))",
    "t_tvs05 c[116,95,116,118,115,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,114,105,101],a[97])))",
    "t_tvs06 c[116,95,116,118,115,48,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tvs07 c[116,95,116,118,115,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,114,105,101],a[97])))",
    "t_tvs08 c[116,95,116,118,115,48,56]/1(a[102,114,101,115,104])",
    "t_tvp01 c[116,95,116,118,112,48,49]/1(c[58]/2(a[117,115,101,114],c[47]/2(a[116,118,95,112],i1)))",
    "t_tvp02 c[116,95,116,118,112,48,50]/1(c[58]/2(a[117,115,101,114],c[47]/2(a[116,118,95,112],i1)))",
    "t_tvp03 c[116,95,116,118,112,48,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[116,114,105,101],a[97])))",
    "t_tvp04 c[116,95,116,118,112,48,52]/1(a[121,101,115])",
    "t_tvp05 c[116,95,116,118,112,48,53]/1(a[110,111])",
    "t_tvt01 c[116,95,116,118,116,48,49]/1(a[121,101,115])",
    "t_tvt02 c[116,95,116,118,116,48,50]/1(a[110,111,114,109,97,108])",
    "t_tvt03 c[116,95,116,118,116,48,51]/1(a[110,111])",
    "t_tvt04 c[116,95,116,118,116,48,52]/1(a[110,111])",
    "t_tvt05 c[116,95,116,118,116,48,53]/1(a[110,111])",
    "t_tvt06 c[116,95,116,118,116,48,54]/1(a[121,101,115])",
    "t_tvt07 c[116,95,116,118,116,48,55]/1(a[115,97,109,101])",
    "t_tvt08 c[116,95,116,118,116,48,56]/1(a[100,105,102,102])",
    "t_tvl01 c[116,95,116,118,108,48,49]/1(a[121,101,115])",
    "t_tvl02 c[116,95,116,118,108,48,50]/1(a[110,111])",
    "t_tvl03 c[116,95,116,118,108,48,51]/1(a[121,101,115])",
    "t_tvl04 c[116,95,116,118,108,48,52]/1(a[115,97,109,101])",
    "t_tvl05 c[116,95,116,118,108,48,53]/1(a[121,101,115])",
    "t_tvl06 c[116,95,116,118,108,48,54]/1(c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[116,118,95,112]/1(V0)),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[58]/2(a[117,115,101,114],c[116,118,95,112]/1(i1)),a[99,111,109,112,108,101,116,101]),nil)))",
    "t_tvl07 c[116,95,116,118,108,48,55]/1(i2)",
    "t_tvi01 c[116,95,116,118,105,48,49]/1(c[58]/2(a[117,115,101,114],c[116,118,95,112]/1(V0)))",
    "t_tvi02 c[116,95,116,118,105,48,50]/1(c[58]/2(a[117,115,101,114],c[116,118,95,113]/1(V0)))",
    "t_tvi03 c[116,95,116,118,105,48,51]/1(c[58]/2(a[117,115,101,114],c[116,118,95,110,111,112,101]/1(V0)))",
    "t_tvi04 c[116,95,116,118,105,48,52]/1(c[116,118,95,112]/1(V0))",
    "t_tvi05 c[116,95,116,118,105,48,53]/1(c[58]/2(a[117,115,101,114],c[116,118,95,100]/1(V0)))",
    "t_tvi06 c[116,95,116,118,105,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,97,108,108,97,98,108,101],i1)))",
    "t_tvi07 c[116,95,116,118,105,48,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_tvi08",
    "t_tvn01 c[116,95,116,118,110,48,49]/1(c[58]/2(a[117,115,101,114],c[116,118,95,112]/1(V0)))",
    "t_tvn02 c[116,95,116,118,110,48,50]/1(c[116,118,95,112]/1(V0))",
    "t_tvn03 c[116,95,116,118,110,48,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[116,110,111,116],a[110,111,110,95,116,97,98,108,101,100,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[116,118,95,113],i1))))",
    "t_tvn04 c[116,95,116,118,110,48,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[116,110,111,116],a[110,111,110,95,116,97,98,108,101,100,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[116,118,95,113],i1))))",
    "t_tvn05 c[116,95,116,118,110,48,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[116,110,111,116],a[110,111,110,95,116,97,98,108,101,100,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[116,118,95,110,111,112,101],i1))))",
    "t_tvn06 c[116,95,116,118,110,48,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[116,110,111,116],a[110,111,110,95,116,97,98,108,101,100,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[116,118,95,100],i1))))",
    "t_tvn07 c[116,95,116,118,110,48,55]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[116,110,111,116],a[110,111,110,95,116,97,98,108,101,100,95,112,114,111,99,101,100,117,114,101],c[47]/2(a[97],i0))))"
]

"The program text with the cases of `cases` appended."
_tv_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _tv_load(program::String)
    f = joinpath(mktempdir(), "tabling_variant.pl")
    write(f, _tv_text(program, vcat(_TV_PRE_CASES, _TV_CASES)))
    gd = LK.PL_global_data{_TV}()
    ld = LK.PL_local_data{_TV}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tv_enc(ball::_TV))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _tv_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tvs(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TV, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _tv_enc(mk_expr(_TV, _TV[_tvs(pred), lk_answers(ld, (a:a)...)...])))
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
function _tv_def(gd, name::String, arity::Int=1)
    proc = LK.isCurrentProcedure(sym_key(_tvs(name)), arity, LK.MODULE_user(gd))
    @assert proc !== nothing
    return proc.definition
end

"""
The two tables swipl makes by calling `tv_p(1)` and `tv_p(_)`: `user:tv_p(1)` (no variable: the answer table's worklist is
`WL_GROUND`, the skeleton `ret`) and `user:tv_p(_)` (skeleton `ret(V)`), both complete. The answer tries, in that order.
"""
function _tv_tables!(gd, ld)
    def = _tv_def(gd, "tv_p")
    tries = []
    for ground in (true, false)
        fid = LK.PL_open_foreign_frame(ld)
        t = LK.PL_new_term_refs(ld, 2)
        arg = ground ? lk_gnd(_TV, 1) : mk_var(_TV, LK.fresh_var_keys!(1))
        v = mk_expr(_TV, _TV[_tvs(":"), _tvs("user"), mk_expr(_TV, _TV[_tvs("tv_p"), arg])])
        LK.putSlotValue!(ld, t + 1, v, LK.PutVarMap())
        atrie = LK.get_answer_table(ld, def, t, t + 1, Int(LK.AT_CREATE))
        @assert atrie !== nothing
        atrie.flags |= LK.TRIE_COMPLETE
        push!(tries, atrie)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return tries
end

@testset "variant tables as swipl's (tvb, tvv, tvs, tvp, tvt, tvl, tvi, tvn)" begin
    gd, ld, st = _tv_load(_TV_COMMON * _TV_KERNEL)
    @test st == "ok"
    kl = String[st]
    for (id, _) in _TV_PRE_CASES
        push!(kl, _tv_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_TV_PRE_PINNED)
    for (k, p) in zip(kl, _TV_PRE_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end

    # white-box state: the tables the rows below read
    @test ld.tabling.variant_table != 0                       # the lookups of the rows above made the variant table
    atries = _tv_tables!(gd, ld)
    variants = LK.variant_table(ld, false)
    @test variants === gd.tries[ld.tabling.variant_table]
    @test (variants.flags & LK.TRIE_ISVARIANT) != 0
    @test variants.value_count == 2
    @test all(tr.serial >= 1 for tr in gd.tries)             # every table trie is registered (DV_DELETED is -1, TB1)
    for atrie in atries
        @test (atrie.flags & (LK.TRIE_ISTABLE | LK.TRIE_ISSET | LK.TRIE_COMPLETE)) ==
            (LK.TRIE_ISTABLE | LK.TRIE_ISSET | LK.TRIE_COMPLETE)
        @test atrie.registry === gd.tries
        @test atrie.variant != 0
        w = variants.nodes[atrie.variant].value
        @test LK.isTriePtrValue(w)
        @test LK.valueTriePtr(gd.tries, w) === atrie
        @test LK.value_trie(gd, w) === atrie
        @test LK.is_variant_trie(atrie) == false
    end
    @test LK.is_variant_trie(variants)
    @test atries[1].worklist == LK.WL_GROUND                  # no variable in the call: the ground answer table
    @test atries[2].worklist === nothing

    kl = String[]
    for (id, _) in _TV_CASES
        push!(kl, _tv_ask(gd, ld, "t_$id"))
    end
    @test length(kl) + 1 == length(_TV_PINNED)
    for (k, p) in zip(kl, _TV_PINNED[2:end])
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the variant table rows are not vacuous" begin
    @test _TV_PRE_PINNED[1] == "ok" && _TV_PINNED[1] == "ok"
    @test length(_TV_PRE_PINNED) == length(_TV_PRE_CASES) + 1
    @test length(_TV_PINNED) == length(_TV_CASES) + 1
    for pre in ("tvv", "tvs", "tvp", "tvt", "tvl", "tvi", "tvn")
        ids = [id for (id, _) in _TV_CASES if startswith(id, pre)]
        @test !isempty(ids)
        # a row with no solution is its name alone (tvi08: swipl fails it)
        @test length([
            l for l in _TV_PINNED if any(id -> l == "t_$id" || startswith(l, "t_$id "), ids)
        ]) ==
            length(ids)
    end
    line(pins, id) = only(filter(l -> startswith(l, "t_$id "), pins))
    ans(pins, id) = split(line(pins, id), " "; limit=2)[2]
    @test ans(_TV_PRE_PINNED, "tvb01") != ans(_TV_PRE_PINNED, "tvb05")   # no variant table yet, then one made by the failed lookup
    @test ans(_TV_PINNED, "tvv01") != ans(_TV_PINNED, "tvv02")          # skeleton `ret` against `ret(V)`
    @test ans(_TV_PINNED, "tvv01") != ans(_TV_PINNED, "tvv03")          # a table found, a variant with no table
    @test ans(_TV_PINNED, "tvs01") != ans(_TV_PINNED, "tvs08")          # complete answer table, fresh variant table
    @test ans(_TV_PINNED, "tvt07") != ans(_TV_PINNED, "tvt08")          # one variant, one table; two variants, two tables
    @test ans(_TV_PINNED, "tvn01") != ans(_TV_PINNED, "tvn03")          # tabled: the goal; not tabled: permission_error
    @test ans(_TV_PINNED, "tvi01") != ans(_TV_PINNED, "tvi04")          # a qualified goal is answered qualified, a plain one plain
end

# DEFKILL3 rows (white-box, no swipl: each premise is asserted, so a wrong premise is a plain failure). They kill the TB1 mutants that
# were DEFERRED KILL: R2, V5, G9, T3, F5, F6, L1, L4, N2, N3. Expectations are the C control flow of pl-tabling.c at the pin
# (18168e62) and pl-trie.h:201-211, with the kernel's line on the other side in each comment.
@testset "TB1 white-box rows: the tag, the pool, the nodes, the status, the release, the start nodes (DEFKILL3)" begin
    gd, ld, st = _tv_load(_TV_COMMON * _TV_KERNEL)
    @test st == "ok"

    # TB1-R2: pl-trie.h:201-211 `TRIE_PTR_TAG` is 0x7 (kernel src/pl-tabling.jl: `const TRIE_PTR_TAG = UInt64(0x7)`); the value
    # round trip alone holds for any tag, so the literal and the low bits of a registered value are read.
    @test LK.TRIE_PTR_TAG == 0x7
    atries = _tv_tables!(gd, ld)
    variants = LK.variant_table(ld, false)
    @test all(a -> (variants.nodes[a.variant].value & 0x7) == 0x7, atries)

    # TB1-V5: pl-tabling.c:2605 `variant_table()` makes LD->tabling.node_pool "private_table_space" when it is NULL (kernel
    # src/pl-tabling.jl:3157-3159); the lookups above made it.
    @test ld.tabling.node_pool isa LK.alloc_pool
    @test ld.tabling.node_pool.name == "private_table_space"
    @test ld.tabling.node_pool.limit == gd.options.tableSpace

    # TB1-G9: a lookup without AT_CREATE of a variant that has no table creates no node (pl-tabling.c:3125 get_answer_table:
    # `trie_lookup_abstract(..., (flags&AT_CREATE), ...)`, kernel src/pl-tabling.jl:3442-3444); `tv_p(2)` was never looked up.
    def = _tv_def(gd, "tv_p")
    n0, v0 = variants.node_count, variants.value_count
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 2)
    v = mk_expr(_TV, _TV[_tvs(":"), _tvs("user"), mk_expr(_TV, _TV[_tvs("tv_p"), lk_gnd(_TV, 2)])])
    LK.putSlotValue!(ld, t + 1, v, LK.PutVarMap())
    @test LK.get_answer_table(ld, def, t, t + 1, 0) === nothing
    @test (variants.node_count, variants.value_count) == (n0, v0)
    LK.PL_close_foreign_frame(ld, fid)

    # TB1-T3: unify_trie_ret (pl-tabling.c:2984) puts the I-th variable in the I-th argument of `ret(V1, V2)`; the kernel's loop is
    # `ld.gstack[p + i] = makeRefG(vp)` (src/pl-tabling.jl:3311-3313). Every other row has one variable; here a call with two.
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 4)
    k0 = LK.fresh_var_keys!(2)
    v = mk_expr(
        _TV,
        _TV[_tvs(":"), _tvs("user"), mk_expr(_TV, _TV[_tvs("tv_p"), mk_var(_TV, k0), mk_var(_TV, k0 + UInt64(1))])]
    )
    LK.putSlotValue!(ld, t + 1, v, LK.PutVarMap())
    a2 = LK.get_answer_table(ld, def, t, t + 1, Int(LK.AT_CREATE))
    @test a2 !== nothing
    @test LK._PL_get_arg(ld, 1, t + 1, t + 2)
    @test LK._PL_get_arg(ld, 2, t + 1, t + 3)
    @test LK.PL_is_variable(ld, t + 2) && LK.PL_is_variable(ld, t + 3)
    @test LK.PL_compare(ld, t + 2, t + 3) != 0               # two distinct variables, not V1 twice
    LK.PL_close_foreign_frame(ld, fid)
end

@testset "TB1 white-box rows: a ground call marks the worklist ground (DEFKILL3: G3)" begin
    gd, ld, st = _tv_load(_TV_COMMON * _TV_KERNEL)
    @test st == "ok"
    atries = _tv_tables!(gd, ld)
    def = _tv_def(gd, "tv_p")
    a = atries[1]                                     # tv_p(1), the ground table
    # pl-tabling.c:3199 get_answer_table: `atrie->data.worklist->ground = true` (kernel
    # src/pl-tabling.jl:3491-3496). Premise: a worklist object that is not ground yet (new_worklist sets `ground` only for WL_GROUND).
    a.worklist = nothing
    wl = LK.new_worklist(ld, a)
    @test a.worklist === wl && !wl.ground
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 2)
    v = mk_expr(_TV, _TV[_tvs(":"), _tvs("user"), mk_expr(_TV, _TV[_tvs("tv_p"), lk_gnd(_TV, 1)])])
    LK.putSlotValue!(ld, t + 1, v, LK.PutVarMap())
    @test LK.get_answer_table(ld, def, t, t + 1, 0) === a
    @test wl.ground                                   # TB1-G3
    LK.PL_close_foreign_frame(ld, fid)
end

@testset "TB1 white-box rows: the status of a table (DEFKILL3: F5, F6)" begin
    gd, ld, st = _tv_load(_TV_COMMON * _TV_KERNEL)
    @test st == "ok"
    atries = _tv_tables!(gd, ld)
    def = _tv_def(gd, "tv_p")
    atrie = atries[2]
    status(a) = begin
        fid = LK.PL_open_foreign_frame(ld)
        t = LK.PL_new_term_ref(ld)
        @test LK.unify_table_status(ld, t, a, def, false)
        r = sym_text(LK.PL_get_atom(ld, t))
        LK.PL_close_foreign_frame(ld, fid)
        return r
    end
    # TB1-F6: pl-tabling.c:4351 table_status: a COMPLETE trie answers complete (complete_or_invalid_status, no IDG: complete), an
    # incomplete one without worklist fresh, one with WL_DYNAMIC dynamic (kernel src/pl-tabling.jl:3584-3597).
    @test (atrie.flags & LK.TRIE_COMPLETE) != 0 && atrie.IDG === nothing
    @test sym_text(LK.table_status(ld, atrie)) == "complete"
    atrie.flags &= ~LK.TRIE_COMPLETE
    @test atrie.worklist === nothing
    @test sym_text(LK.table_status(ld, atrie)) == "fresh"
    atrie.worklist = LK.WL_DYNAMIC
    @test sym_text(LK.table_status(ld, atrie)) == "dynamic"
    # TB1-F5: pl-tabling.c:4318 unify_table_status: a dynamic table is `dynamic` (kernel src/pl-tabling.jl:3573-3575)
    @test status(atrie) == "dynamic"
    atrie.worklist = nothing
    @test status(atrie) == "fresh"
    atrie.flags |= LK.TRIE_COMPLETE
    @test status(atrie) == "complete"
end

@testset "TB1 white-box rows: the release of a variant table node (DEFKILL3: L1, L4)" begin
    gd, ld, st = _tv_load(_TV_COMMON * _TV_KERNEL)
    @test st == "ok"
    atries = _tv_tables!(gd, ld)
    variants = LK.variant_table(ld, false)
    # pl-tabling.c:2679 release_variant_table_node -> :2642 reset_answer_table (no worklist, not complete) and `atrie->data.variant = NULL`
    # (kernel src/pl-tabling.jl:3190-3250); the ground table has WL_GROUND, the other none.
    @test atries[1].worklist == LK.WL_GROUND && atries[2].worklist === nothing
    for atrie in atries
        nid = atrie.variant
        @test nid != 0 && (atrie.flags & LK.TRIE_COMPLETE) != 0
        LK.release_variant_table_node(gd, variants, nid)
        @test (atrie.flags & LK.TRIE_COMPLETE) == 0          # TB1-L1 (reset_answer_table)
        @test atrie.worklist === nothing
        @test atrie.variant == 0                             # TB1-L4
    end
end

@testset "TB1 white-box rows: the start node cache (DEFKILL3: N2, N3)" begin
    gd, ld, st = _tv_load(_TV_COMMON * _TV_KERNEL)
    @test st == "ok"
    atries = _tv_tables!(gd, ld)
    variants = LK.variant_table(ld, false)
    nid = atries[1].variant
    # pl-tabling.c:12423 set_start_node: the array grows, the entries between are NULL, and the node is pinned (TN_PINNED)
    # (kernel src/pl-tabling.jl:3079-3094). Premise: the cache starts empty; get_start_node of an id past the end is 0.
    @test ld.tabling.start_nodes === nothing && LK.get_start_node(nothing, 3) == 0
    @test variants.nodes[nid].flags & LK.TN_PINNED == 0
    LK.set_start_node(ld, variants, 5, nid)
    a = ld.tabling.start_nodes
    @test LK.get_start_node(a, 5) == nid
    @test variants.nodes[nid].flags & LK.TN_PINNED != 0         # TB1-N2
    @test LK.get_start_node(a, 3) == 0 && LK.get_start_node(a, 6) == 0
    # TB1-N3: `resize!` of a Vector{Int} does not clear what a shrink left behind; the grown entries must be 0 by the `fill!`
    a[1:5] .= (11, 12, 13, 14, 15)
    resize!(a, 1)
    LK.set_start_node(ld, variants, 4, nid)
    @test ld.tabling.start_nodes === a
    @test a[2] == 0 && a[3] == 0 && a[4] == nid
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB1 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        for (cases, pins) in ((_TV_PRE_CASES, _TV_PRE_PINNED), (_TV_CASES, _TV_PINNED))
            @test pins[1] == "ok"
            @test [first(split(l, " ")) for l in pins[2:end]] ==
                ["t_$id" for (id, _) in cases]
        end
    else
        for (program, cases, pins) in (
            (_TV_SWIPL_PRE, _TV_PRE_CASES, _TV_PRE_PINNED),
            (_TV_COMMON * _TV_SWIPL, _TV_CASES, _TV_PINNED)
        )
            f = joinpath(mktempdir(), "tv_swipl.pl")
            write(f, _tv_text(program, cases))
            @test _tv_swipl_lines(f, ["t_$id" for (id, _) in cases]) == pins
        end
    end
end

# DEFKILL5 rows for TB1-P7 (`'$tbl_variant_table'/6` hands the table back in its Trie argument). Pins: swipl 10.1.20-1-g18168e62 (18168e62), the
# program of _TV_COMMON * _TV_SWIPL (`:- table tv_p/1`, `tv_p(1)` and `tv_p(_)` called), the cases below through the driver, LC_ALL=C, two byte-identical
# runs. The call is the one start_tabling makes with Closure 0 on a variant that has a COMPLETE table: no table is created (pl-tabling.c tbl_variant_table
# finds it, src/pl-tabling.jl:3885 `pl_tbl_variant_table6_va`), the Trie argument is the table `$tbl_existing_variant_table` finds, and a non-variable that
# is not that table does not unify (tvw03: the mutant that drops `unify_trie` answers yes).
const _TV_P7_CASES = [
    (
        "tvw01",
        raw"'$tbl_variant_table'(0, user:tv_p(1), T, S, Sk, M), tv_tab(user:tv_p(1), T2), tm_same(T, T2, E), R = r(S, Sk, M, E)"
    ),
    (
        "tvw02",
        raw"'$tbl_variant_table'(0, user:tv_p(_), T, S, Sk, M), tv_tab(user:tv_p(_), T2), tm_same(T, T2, E), R = r(S, Sk, M, E)"
    ),
    ("tvw03", raw"tm_yn('$tbl_variant_table'(0, user:tv_p(1), a, _, _, _), R)"),
    ("tvw04", raw"'$tbl_variant_table'(0, user:tv_p(1), T, _, _, _), tm_yn(is_trie(T), R)")
]
const _TV_P7_PINNED = [
    "ok",
    "t_tvw01 c[116,95,116,118,119,48,49]/1(c[114]/4(a[99,111,109,112,108,101,116,101],a[114,101,116],V0,a[115,97,109,101]))",
    "t_tvw02 c[116,95,116,118,119,48,50]/1(c[114]/4(a[99,111,109,112,108,101,116,101],c[114,101,116]/1(V0),V1,a[115,97,109,101]))",
    "t_tvw03 c[116,95,116,118,119,48,51]/1(a[110,111])",
    "t_tvw04 c[116,95,116,118,119,48,52]/1(a[121,101,115])"
]

@testset "TB1-P7: `\$tbl_variant_table/6` of an existing table, as swipl (tvw rows, DEFKILL5)" begin
    gd, ld, st = _tv_load(_TV_COMMON * _TV_KERNEL * _tv_text("", _TV_P7_CASES))
    @test st == "ok"
    _tv_tables!(gd, ld)
    kl = String[_tv_ask(gd, ld, "t_$id") for (id, _) in _TV_P7_CASES]
    @test length(kl) + 1 == length(_TV_P7_PINNED)
    for (k, p) in zip(kl, _TV_P7_PINNED[2:end])
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # both sides non-empty, one extractor: the Trie argument answers differ in the pins (found: same / yes; a non-table: no)
    @test occursin("a[115,97,109,101]", _TV_P7_PINNED[2]) && occursin("a[115,97,109,101]", _TV_P7_PINNED[3])
    @test _TV_P7_PINNED[4] != _TV_P7_PINNED[5]
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl !== nothing
        f = joinpath(mktempdir(), "tv_p7_swipl.pl")
        write(f, _tv_text(_TV_COMMON * _TV_SWIPL, _TV_P7_CASES))
        @test _tv_swipl_lines(f, ["t_$id" for (id, _) in _TV_P7_CASES]) == _TV_P7_PINNED
    end
end
