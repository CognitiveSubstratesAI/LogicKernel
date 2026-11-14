# ORIGINAL: LIVE rows for PLAIN SUBSUMPTIVE tabling (`:- table p/1 as subsumptive`) against swipl at the pin (swipl-devel 18168e62,
# 10.1.20): TAB1 TB3 rows SUB-01..SUB-14 of evidence/TAB1/subsumptive.md (plan section 6). The pin implements the mode in PROLOG
# (boot/tabling.pl `start_subsumptive_tabling/3` :467-487, `table_options` :1401, `more_general_table/2` :2346) over C builtins that
# the kernel has ported (`$tbl_existing_variant_table/5`, `$tbl_table_status/4`, `$tbl_answer_update_dl/2`, `$tbl_wkl_add_suspension/3`
# with the instance filter and the keyed suspension index): the gap was TESTS, no row ran a subsumptive table.
# Groups (one program text, one fresh database each, so a refusal in one leaves only its rows undefined): BASE = p, q, r, s, path (SUB-01
# to SUB-06, SUB-14 on p); REC = pp/pv, sp/kv, kk (SUB-07, 08, 09: an instance called while the general table is incomplete); GEN = g/2
# (SUB-10, SUB-14 on g); MODED = `m(_,max) as subsumptive` (SUB-11); FLAG = the flag `table_subsumptive` (SUB-12); OPT = an unknown
# table option (SUB-13).
#   * Cases `t_<id>(R)` run in order in ONE database per group, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver
#     is test_tabling_tb4rows_swipl.jl's (`enc`oded answers, helpers copied with the prefix `_SUB_`). Every case starts with
#     `abolish_all_tables`. An answer LIST is `msort`ed (`srt/3`): the order of a table's answers is not what these rows read. The table
#     list `tabs/1` is `msort` of `Goal-Status` of every `current_table(user:G, T)` with `'$tbl_table_status'(T, S)`: the number of tables
#     is the observable of the subsumption (ONE table when an instance is answered from the general one, TWO when a variant call came first).
#   * SUB-06 records the clause bodies with `assertz(sbody(X))` instead of printing (the kernel driver captures no output); the same text
#     runs on both sides.
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, the SAME driver text run twice, `cmp` byte-identical); with `swipl` on PATH the live
#     answers are compared with the pins too. A trie blob is never printed.
#   * SUB-11 pins a PIN QUIRK: `as subsumptive` on a MODED table is recorded (`tabled(subsumptive)`) but runs the variant machinery
#     (boot/tabling.pl `'$moded_wrap_tabled'` :733-743 always wraps with `start_moded_tabling`): two tables, not one.
#   * KILLS (tools/mutants/TB2.py, deferred kills of TB3 landed here): TB2-P4 (`$tbl_wkl_add_suspension/3`, pl-tabling.c:5273-5290) by SUB-07,
#     SUB-08, SUB-09 (every instance call against an incomplete general table suspends with the /3 form); TB2-S1 (`sindex_candidates`, the keyed
#     index) by SUB-08 and SUB-09 (several suspensions with an instance in ONE worklist). Rows SUB-15 (`(subsumptive,incremental)`, P12) is TB6's,
#     `(subsumptive,monotonic)` TB7's: not here.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the verifier runs each row
#     against its mutant.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, the answer lists)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _SUB_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_SUB_sym(x) = lk_sym(_SUB_T, Symbol(x))

_SUB_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _SUB_enc(t::_SUB_T, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _SUB_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _SUB_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _SUB_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_SUB_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _SUB_DRIVER = raw"""
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

function _SUB_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _SUB_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The program text with the cases of `cases` appended."
_SUB_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _SUB_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_subsumptive.pl")
    write(f, _SUB_text(program, cases))
    gd = LK.PL_global_data{_SUB_T}()
    ld = LK.PL_local_data{_SUB_T}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _SUB_enc(ball::_SUB_T))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _SUB_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_SUB_sym(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_SUB_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _SUB_enc(
                    mk_expr(_SUB_T, _SUB_T[_SUB_sym(pred), lk_answers(ld, (a:a)...)...])
                )
            )
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

"The helpers every group's program starts with."
const _SUB_HELP = raw"""
tabs(M) :- findall(G-S, ( current_table(user:G, T), '$tbl_table_status'(T, S) ), L), msort(L, M).
srt(G, X, L) :- findall(X, G, L0), msort(L0, L).
props(N, A, N-Ps) :- functor(H, N, A), findall(P, ( predicate_property(H, P), ( P = tabled(_) ; P = tabled ) ), Ps0), msort(Ps0, Ps).
"""

const _SUB_PROG_BASE =
    _SUB_HELP * raw"""
:- dynamic sbody/1.
:- table p/1 as subsumptive.
p(X) :- member(X, [1,2,3]).
:- table q/1 as variant.
q(X) :- member(X, [1,2,3]).
:- table r/1.
r(X) :- member(X, [1,2,3]).
:- table s/1 as subsumptive.
s(X) :- member(X, [1,2,3]), assertz(sbody(X)).
edge(a, b).
edge(b, c).
:- table path/2 as subsumptive.
path(X, Y) :- edge(X, Y).
path(X, Y) :- path(X, Z), edge(Z, Y).
"""

const _SUB_CASES_BASE = [
    (
        "sub01",
        raw"abolish_all_tables, srt(p(X1), X1, L1), tabs(T1), srt(p(2), a, L2), tabs(T2), srt((p(Z), Z > 1), Z, L3), srt(p(4), a, L4), tabs(T3), srt(p(X2), X2, L5), tabs(T4), R = r(L1, T1, L2, T2, L3, L4, T3, L5, T4)"
    ),
    (
        "sub02",
        raw"abolish_all_tables, srt(p(2), a, L1), tabs(T1), srt(p(X), X, L2), tabs(T2), R = r(L1, T1, L2, T2)"
    ),
    (
        "sub03",
        raw"abolish_all_tables, srt(q(X1), X1, A1), srt(q(2), a, A2), tabs(T1), abolish_all_tables, srt(r(X2), X2, B1), srt(r(2), a, B2), tabs(T2), R = r(A1, A2, T1, B1, B2, T2)"
    ),
    (
        "sub04",
        raw"findall(P, ( member(N-A, [p-1, q-1, r-1, s-1, path-2, edge-2]), props(N, A, P) ), R)"
    ),
    (
        "sub05a",
        raw"abolish_all_tables, srt(p(X1), X1, _), tabs(T1), abolish_all_tables, tabs(T2), srt(p(X2), X2, _), tabs(T3), abolish_all_tables, tabs(T4), R = r(T1, T2, T3, T4)"
    ),
    (
        "sub05b",
        raw"abolish_all_tables, srt(p(X), X, _), abolish_table_subgoals(p(_)), tabs(T), R = r(T)"
    ),
    (
        "sub05c",
        raw"abolish_all_tables, srt(p(2), a, _), srt(p(X), X, _), abolish_module_tables(user), tabs(T), R = r(T)"
    ),
    (
        "sub06a",
        raw"abolish_all_tables, retractall(sbody(_)), srt(s(2), a, L1), findall(B, sbody(B), B1), srt(s(X), X, L2), findall(B, sbody(B), B2), tabs(T), R = r(L1, B1, L2, B2, T)"
    ),
    (
        "sub06b",
        raw"abolish_all_tables, retractall(sbody(_)), srt(s(X), X, L1), findall(B, sbody(B), B1), srt(s(2), a, L2), findall(B, sbody(B), B2), tabs(T), R = r(L1, B1, L2, B2, T)"
    ),
    (
        "sub14a",
        raw"abolish_all_tables, srt(p(X), X, _), findall(V, ( current_table(user:p(_), T), trie_property(T, value_count(V)) ), R)"
    )
]

const _SUB_PINS_BASE = [
    "ok",
    "t_sub01 c[116,95,115,117,98,48,49]/1(c[114]/9(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(c[45]/2(c[112]/1(V0),a[99,111,109,112,108,101,116,101]),nil),c[91,124,93]/2(a[97],nil),c[91,124,93]/2(c[45]/2(c[112]/1(V1),a[99,111,109,112,108,101,116,101]),nil),c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil)),nil,c[91,124,93]/2(c[45]/2(c[112]/1(V2),a[99,111,109,112,108,101,116,101]),nil),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(c[45]/2(c[112]/1(V3),a[99,111,109,112,108,101,116,101]),nil)))",
    "t_sub02 c[116,95,115,117,98,48,50]/1(c[114]/4(c[91,124,93]/2(a[97],nil),c[91,124,93]/2(c[45]/2(c[112]/1(i2),a[99,111,109,112,108,101,116,101]),nil),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(c[45]/2(c[112]/1(V0),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[112]/1(i2),a[99,111,109,112,108,101,116,101]),nil))))",
    "t_sub03 c[116,95,115,117,98,48,51]/1(c[114]/6(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(a[97],nil),c[91,124,93]/2(c[45]/2(c[113]/1(V0),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[113]/1(i2),a[99,111,109,112,108,101,116,101]),nil)),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(a[97],nil),c[91,124,93]/2(c[45]/2(c[114]/1(V1),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[114]/1(i2),a[99,111,109,112,108,101,116,101]),nil))))",
    "t_sub04 c[116,95,115,117,98,48,52]/1(c[91,124,93]/2(c[45]/2(a[112],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[115,117,98,115,117,109,112,116,105,118,101]),nil))),c[91,124,93]/2(c[45]/2(a[113],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[118,97,114,105,97,110,116]),nil))),c[91,124,93]/2(c[45]/2(a[114],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[118,97,114,105,97,110,116]),nil))),c[91,124,93]/2(c[45]/2(a[115],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[115,117,98,115,117,109,112,116,105,118,101]),nil))),c[91,124,93]/2(c[45]/2(a[112,97,116,104],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[115,117,98,115,117,109,112,116,105,118,101]),nil))),c[91,124,93]/2(c[45]/2(a[101,100,103,101],nil),nil)))))))",
    "t_sub05a c[116,95,115,117,98,48,53,97]/1(c[114]/4(c[91,124,93]/2(c[45]/2(c[112]/1(V0),a[99,111,109,112,108,101,116,101]),nil),nil,c[91,124,93]/2(c[45]/2(c[112]/1(V1),a[99,111,109,112,108,101,116,101]),nil),nil))",
    "t_sub05b c[116,95,115,117,98,48,53,98]/1(c[114]/1(nil))",
    "t_sub05c c[116,95,115,117,98,48,53,99]/1(c[114]/1(nil))",
    "t_sub06a c[116,95,115,117,98,48,54,97]/1(c[114]/5(c[91,124,93]/2(a[97],nil),c[91,124,93]/2(i2,nil),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(i2,c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil)))),c[91,124,93]/2(c[45]/2(c[115]/1(V0),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[115]/1(i2),a[99,111,109,112,108,101,116,101]),nil))))",
    "t_sub06b c[116,95,115,117,98,48,54,98]/1(c[114]/5(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(a[97],nil),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),c[91,124,93]/2(c[45]/2(c[115]/1(V0),a[99,111,109,112,108,101,116,101]),nil)))",
    "t_sub14a c[116,95,115,117,98,49,52,97]/1(c[91,124,93]/2(i3,nil))"
]

const _SUB_PROG_REC =
    _SUB_HELP * raw"""
:- table pp/1 as subsumptive.
pp(X) :- member(X, [1,2,3]).
pp(X) :- pp(2), X = 9.
:- table pv/1 as variant.
pv(X) :- member(X, [1,2,3]).
pv(X) :- pv(2), X = 9.
:- table sp/1 as subsumptive.
sp(X) :- member(X, [1,2,3,4]).
sp(X) :- sp(1), X = 10.
sp(X) :- sp(2), X = 20.
sp(X) :- sp(3), X = 30.
sp(X) :- sp(Y), Y >= 10, Y < 30, X is Y + 1.
:- table kv/1 as variant.
kv(X) :- member(X, [1,2,3,4]).
kv(X) :- kv(1), X = 10.
kv(X) :- kv(2), X = 20.
kv(X) :- kv(3), X = 30.
:- table kk/1 as subsumptive.
kk(f(a, 1)).
kk(f(b, 2)).
kk(f(c, 3)).
kk(g(X)) :- kk(f(b, X)).
kk(h(X, Y)) :- kk(f(X, Y)).
kk(i(X)) :- kk(f(c, X)), kk(f(a, _)).
"""

const _SUB_CASES_REC = [
    ("sub07a", raw"abolish_all_tables, srt(pp(X), X, L), tabs(T), R = r(L, T)"),
    ("sub07b", raw"abolish_all_tables, srt(pv(X), X, L), tabs(T), R = r(L, T)"),
    (
        "sub08a",
        raw"abolish_all_tables, srt(sp(X1), X1, L1), length(L1, N1), tabs(T), srt(sp(X2), X2, L2), length(L2, N2), R = r(L1, N1, T, L2, N2)"
    ),
    (
        "sub08b",
        raw"abolish_all_tables, srt(kv(X1), X1, L1), length(L1, N1), tabs(T), srt(kv(X2), X2, L2), length(L2, N2), R = r(L1, N1, T, L2, N2)"
    ),
    (
        "sub09",
        raw"abolish_all_tables, srt(kk(X), X, L1), tabs(T1), srt(kk(f(a, Y)), Y, L2), tabs(T2), R = r(L1, T1, L2, T2)"
    )
]

const _SUB_PINS_REC = [
    "ok",
    "t_sub07a c[116,95,115,117,98,48,55,97]/1(c[114]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i9,nil)))),c[91,124,93]/2(c[45]/2(c[112,112]/1(V0),a[99,111,109,112,108,101,116,101]),nil)))",
    "t_sub07b c[116,95,115,117,98,48,55,98]/1(c[114]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i9,nil)))),c[91,124,93]/2(c[45]/2(c[112,118]/1(V0),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[112,118]/1(i2),a[99,111,109,112,108,101,116,101]),nil))))",
    "t_sub08a c[116,95,115,117,98,48,56,97]/1(c[114]/5(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i10,c[91,124,93]/2(i11,c[91,124,93]/2(i12,c[91,124,93]/2(i13,c[91,124,93]/2(i14,c[91,124,93]/2(i15,c[91,124,93]/2(i16,c[91,124,93]/2(i17,c[91,124,93]/2(i18,c[91,124,93]/2(i19,c[91,124,93]/2(i20,c[91,124,93]/2(i21,c[91,124,93]/2(i22,c[91,124,93]/2(i23,c[91,124,93]/2(i24,c[91,124,93]/2(i25,c[91,124,93]/2(i26,c[91,124,93]/2(i27,c[91,124,93]/2(i28,c[91,124,93]/2(i29,c[91,124,93]/2(i30,nil))))))))))))))))))))))))),i25,c[91,124,93]/2(c[45]/2(c[115,112]/1(V0),a[99,111,109,112,108,101,116,101]),nil),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i10,c[91,124,93]/2(i11,c[91,124,93]/2(i12,c[91,124,93]/2(i13,c[91,124,93]/2(i14,c[91,124,93]/2(i15,c[91,124,93]/2(i16,c[91,124,93]/2(i17,c[91,124,93]/2(i18,c[91,124,93]/2(i19,c[91,124,93]/2(i20,c[91,124,93]/2(i21,c[91,124,93]/2(i22,c[91,124,93]/2(i23,c[91,124,93]/2(i24,c[91,124,93]/2(i25,c[91,124,93]/2(i26,c[91,124,93]/2(i27,c[91,124,93]/2(i28,c[91,124,93]/2(i29,c[91,124,93]/2(i30,nil))))))))))))))))))))))))),i25))",
    "t_sub08b c[116,95,115,117,98,48,56,98]/1(c[114]/5(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i10,c[91,124,93]/2(i20,c[91,124,93]/2(i30,nil))))))),i7,c[91,124,93]/2(c[45]/2(c[107,118]/1(V0),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[107,118]/1(i1),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[107,118]/1(i2),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[107,118]/1(i3),a[99,111,109,112,108,101,116,101]),nil)))),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i10,c[91,124,93]/2(i20,c[91,124,93]/2(i30,nil))))))),i7))",
    "t_sub09 c[116,95,115,117,98,48,57]/1(c[114]/4(c[91,124,93]/2(c[103]/1(i2),c[91,124,93]/2(c[105]/1(i3),c[91,124,93]/2(c[102]/2(a[97],i1),c[91,124,93]/2(c[102]/2(a[98],i2),c[91,124,93]/2(c[102]/2(a[99],i3),c[91,124,93]/2(c[104]/2(a[97],i1),c[91,124,93]/2(c[104]/2(a[98],i2),c[91,124,93]/2(c[104]/2(a[99],i3),nil)))))))),c[91,124,93]/2(c[45]/2(c[107,107]/1(V0),a[99,111,109,112,108,101,116,101]),nil),c[91,124,93]/2(i1,nil),c[91,124,93]/2(c[45]/2(c[107,107]/1(V1),a[99,111,109,112,108,101,116,101]),nil)))"
]

const _SUB_PROG_GEN =
    _SUB_HELP * raw"""
:- table g/2 as subsumptive.
g(X, Y) :- member(X-Y, [1-a, 1-b, 2-c, f(3)-d]).
"""

const _SUB_CASES_GEN = [
    (
        "sub10",
        raw"abolish_all_tables, srt(g(1, Y1), Y1, L1), tabs(T1), srt(g(_, Y2), Y2, L2), srt(g(f(_), Y3), Y3, L3), srt(g(f(3), Y4), Y4, L4), srt(g(2, c), a, L5), tabs(T2), R = r(L1, T1, L2, L3, L4, L5, T2)"
    ),
    (
        "sub14b",
        raw"abolish_all_tables, srt(g(X, Y), X-Y, _), findall(V, ( current_table(user:g(_, _), T), trie_property(T, value_count(V)) ), R)"
    )
]

const _SUB_PINS_GEN = [
    "ok",
    "t_sub10 c[116,95,115,117,98,49,48]/1(c[114]/7(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil)),c[91,124,93]/2(c[45]/2(c[103]/2(i1,V0),a[99,111,109,112,108,101,116,101]),nil),c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],c[91,124,93]/2(a[100],nil)))),c[91,124,93]/2(a[100],nil),c[91,124,93]/2(a[100],nil),c[91,124,93]/2(a[97],nil),c[91,124,93]/2(c[45]/2(c[103]/2(V1,V2),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[103]/2(i1,V3),a[99,111,109,112,108,101,116,101]),nil))))",
    "t_sub14b c[116,95,115,117,98,49,52,98]/1(c[91,124,93]/2(i4,nil))"
]

const _SUB_PROG_MODED =
    _SUB_HELP * raw"""
:- table m(_, max) as subsumptive.
m(a, 1).
m(a, 5).
m(b, 2).
"""

const _SUB_CASES_MODED = [
    (
    "sub11",
    raw"abolish_all_tables, srt(m(a, X1), X1, L1), srt(m(X2, Y2), X2-Y2, L2), tabs(T), props(m, 2, P), R = r(L1, L2, T, P)"
)
]

const _SUB_PINS_MODED = [
    "ok",
    "t_sub11 c[116,95,115,117,98,49,49]/1(c[114]/4(c[91,124,93]/2(i5,nil),c[91,124,93]/2(c[45]/2(a[97],i5),c[91,124,93]/2(c[45]/2(a[98],i2),nil)),c[91,124,93]/2(c[45]/2(c[109]/2(V0,V1),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[109]/2(a[97],V2),a[99,111,109,112,108,101,116,101]),nil)),c[45]/2(a[109],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[115,117,98,115,117,109,112,116,105,118,101]),nil)))))"
]

const _SUB_PROG_FLAG =
    _SUB_HELP * raw"""
:- dynamic flag0/1.
:- current_prolog_flag(table_subsumptive, V), assertz(flag0(V)).
:- table a1/1.
a1(X) :- member(X, [1,2]).
:- set_prolog_flag(table_subsumptive, true).
:- table a2/1.
a2(X) :- member(X, [1,2]).
:- table a3/1 as variant.
a3(X) :- member(X, [1,2]).
:- table a4/1 as (subsumptive, variant).
a4(X) :- member(X, [1,2]).
:- table a6/1 as (variant, subsumptive).
a6(X) :- member(X, [1,2]).
"""

const _SUB_CASES_FLAG = [
    (
        "sub12a",
        raw"flag0(V0), current_prolog_flag(table_subsumptive, V1), findall(P, ( member(N, [a1, a2, a3, a4, a6]), props(N, 1, P) ), Ps), R = r(V0, V1, Ps)"
    ),
    (
        "sub12b",
        raw"abolish_all_tables, srt(a2(X1), X1, L1), srt(a2(1), a, L2), tabs(T1), abolish_all_tables, srt(a3(X2), X2, L3), srt(a3(1), a, L4), tabs(T2), R = r(L1, L2, T1, L3, L4, T2)"
    )
]

const _SUB_PINS_FLAG = [
    "ok",
    "t_sub12a c[116,95,115,117,98,49,50,97]/1(c[114]/3(a[102,97,108,115,101],a[116,114,117,101],c[91,124,93]/2(c[45]/2(a[97,49],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[118,97,114,105,97,110,116]),nil))),c[91,124,93]/2(c[45]/2(a[97,50],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[115,117,98,115,117,109,112,116,105,118,101]),nil))),c[91,124,93]/2(c[45]/2(a[97,51],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[118,97,114,105,97,110,116]),nil))),c[91,124,93]/2(c[45]/2(a[97,52],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[118,97,114,105,97,110,116]),nil))),c[91,124,93]/2(c[45]/2(a[97,54],c[91,124,93]/2(a[116,97,98,108,101,100],c[91,124,93]/2(c[116,97,98,108,101,100]/1(a[115,117,98,115,117,109,112,116,105,118,101]),nil))),nil)))))))",
    "t_sub12b c[116,95,115,117,98,49,50,98]/1(c[114]/6(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(a[97],nil),c[91,124,93]/2(c[45]/2(c[97,50]/1(V0),a[99,111,109,112,108,101,116,101]),nil),c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(a[97],nil),c[91,124,93]/2(c[45]/2(c[97,51]/1(V1),a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(c[97,51]/1(i1),a[99,111,109,112,108,101,116,101]),nil))))"
]

const _SUB_PROG_OPT = _SUB_HELP

const _SUB_CASES_OPT = [
    ("sub13", raw"catch(table(a5/1 as foo), error(E, _), true), R = E")
]

const _SUB_PINS_OPT = [
    "ok",
    "t_sub13 c[116,95,115,117,98,49,51]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[116,97,98,108,101,95,111,112,116,105,111,110],a[102,111,111]))"
]

"The row of each case: what it reads and which mutants it kills."
const _SUB_ROWS = Dict(
    "sub01" => "SUB-01: p(_), p(2), p(_) answer from ONE complete general table (case 2, `\$tbl_answer_update_dl`)",
    "sub02" => "SUB-02: p(2) first, then p(_): TWO tables (case 1 and case 4 of `start_subsumptive_tabling`)",
    "sub03" => "SUB-03: variant and default tables: two tables each (the contrast)",
    "sub04" => "SUB-04: `predicate_property` tabled(subsumptive) / tabled(variant) (`'\$tabled'/2`, syspred `table_flag`)",
    "sub05a" => "SUB-05a: `abolish_all_tables` empties the tables of a subsumptive predicate",
    "sub05b" => "SUB-05b: `abolish_table_subgoals(p(_))`",
    "sub05c" => "SUB-05c: `abolish_module_tables(user)` over p(2) and p(_)",
    "sub06a" => "SUB-06a: s(2) runs the body for 2 only, then s(_) runs 1,2,3 (answers from the table, not the clauses)",
    "sub06b" => "SUB-06b: s(_) then s(2): no body runs for the instance",
    "sub14a" => "SUB-14a: the answer count of p(_)'s trie is 3 (`trie_property value_count`)",
    "sub07a" => "SUB-07a: an instance called while the general table is incomplete: ONE table, 4 answers (kills TB2-P4: the /3 suspension, `call_info/3`, `unify_subsumptive`)",
    "sub07b" => "SUB-07b: the variant contrast of SUB-07a (two tables)",
    "sub08a" => "SUB-08a: four suspensions with an instance in ONE worklist, 25 answers (kills TB2-S1 the keyed index `sindex_candidates`, TB2-P4)",
    "sub08b" => "SUB-08b: the variant contrast of SUB-08a (four tables)",
    "sub09" => "SUB-09: compound instances (sindex keys beyond depth 1), then an instance from the complete table (kills TB2-S1, TB2-P4, `suspension_matches`)",
    "sub10" => "SUB-10: `more_general_table` with partial instantiation, `is_most_general_term` (two tables)",
    "sub14b" => "SUB-14b: the answer count of g(_,_)'s trie is 4",
    "sub11" => "SUB-11: PIN QUIRK, moded `as subsumptive` is recorded but runs variant (two tables)",
    "sub12a" => "SUB-12a: the flag `table_subsumptive` and the property of a1, a2, a3, a4 (subsumptive,variant), a6 (variant,subsumptive)",
    "sub12b" => "SUB-12b: with the flag set a plain `:- table` is subsumptive (one table), `as variant` is variant (two)",
    "sub13" => "SUB-13: an unknown table option is `domain_error(table_option, foo)`"
)

const _SUB_GROUPS = [
    (
        key="BASE",
        label="BASE: p, q, r, s, path (SUB-01 to SUB-06, SUB-14a)",
        program=_SUB_PROG_BASE,
        cases=_SUB_CASES_BASE,
        pins=_SUB_PINS_BASE
    ),
    (
        key="REC",
        label="REC: pp/pv, sp/kv, kk (SUB-07, SUB-08, SUB-09; kills TB2-P4 TB2-S1)",
        program=_SUB_PROG_REC,
        cases=_SUB_CASES_REC,
        pins=_SUB_PINS_REC
    ),
    (
        key="GEN",
        label="GEN: g/2 (SUB-10, SUB-14b)",
        program=_SUB_PROG_GEN,
        cases=_SUB_CASES_GEN,
        pins=_SUB_PINS_GEN
    ),
    (
        key="MODED",
        label="MODED: m(_,max) as subsumptive (SUB-11)",
        program=_SUB_PROG_MODED,
        cases=_SUB_CASES_MODED,
        pins=_SUB_PINS_MODED
    ),
    (
        key="FLAG",
        label="FLAG: table_subsumptive (SUB-12)",
        program=_SUB_PROG_FLAG,
        cases=_SUB_CASES_FLAG,
        pins=_SUB_PINS_FLAG
    ),
    (
        key="OPT",
        label="OPT: an unknown table option (SUB-13)",
        program=_SUB_PROG_OPT,
        cases=_SUB_CASES_OPT,
        pins=_SUB_PINS_OPT
    )
]

@testset "plain subsumptive tabling as swipl's: $(g.label)" for g in _SUB_GROUPS
    gd, ld, st = _SUB_load(g.program, g.cases)
    @test st == "ok"
    kl = String[st]
    for (id, _) in g.cases
        push!(kl, _SUB_ask(gd, ld, "t_$id"))
    end
    @test !isempty(g.cases)                                   # both sides non-empty, through the ONE extractor `_SUB_ask`
    @test length(kl) == length(g.pins) == length(g.cases) + 1
    for ((id, _), k, p) in zip(g.cases, kl[2:end], g.pins[2:end])
        @testset "$(_SUB_ROWS[id])" begin
            k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
            @test k == p
        end
    end
    @test kl[1] == g.pins[1]
end

"The atoms (`a[codes]`) of a pinned answer line, in order."
function _SUB_atoms(line::AbstractString)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"a\[([0-9,]+)\]", line)
    ]
end

_SUB_group(key) = only(filter(g -> g.key == key, _SUB_GROUPS))
"The answer part of the pinned line of case `id` in group `key`."
function _SUB_ans(key, id)
    g = _SUB_group(key)
    return split(only(filter(l -> startswith(l, "t_$id "), g.pins)), " "; limit=2)[2]
end
"How many tables (`-complete` entries) the table list of the pinned answer names: the `complete` atoms."
_SUB_ncomplete(ans) = count(==("complete"), _SUB_atoms(ans))

@testset "the subsumptive rows are not vacuous" begin
    for g in _SUB_GROUPS
        @test g.pins[1] == "ok"
        @test length(g.pins) == length(g.cases) + 1
        @test all(!isempty, g.pins)
        for (id, goal) in g.cases
            @test !isempty(goal)
            @test count(l -> startswith(l, "t_$id "), g.pins) == 1
            @test haskey(_SUB_ROWS, id)
        end
    end
    @test sort(collect(keys(_SUB_ROWS))) ==
        sort([id for g in _SUB_GROUPS for (id, _) in g.cases])
    # the two mutants this file kills are read through rows whose pins differ from what the mutated code would answer:
    # SUB-07a is ONE table where the variant contrast SUB-07b has two, SUB-08a one where SUB-08b has four, SUB-09 one table before and after
    @test _SUB_ncomplete(_SUB_ans("REC", "sub07a")) == 1
    @test _SUB_ncomplete(_SUB_ans("REC", "sub07b")) == 2
    @test _SUB_ncomplete(_SUB_ans("REC", "sub08a")) == 1
    @test _SUB_ncomplete(_SUB_ans("REC", "sub08b")) == 4
    @test _SUB_ans("REC", "sub07a") != _SUB_ans("REC", "sub07b")
    @test _SUB_ans("REC", "sub08a") != _SUB_ans("REC", "sub08b")
    @test _SUB_ncomplete(_SUB_ans("BASE", "sub01")) == 4       # p(_) is the one table after each of the four steps
    @test _SUB_ncomplete(_SUB_ans("BASE", "sub02")) == 3       # [p(2), p(_)] then [p(2), p(_)]: first one table, then two
    @test _SUB_ncomplete(_SUB_ans("BASE", "sub03")) == 4
    @test _SUB_ncomplete(_SUB_ans("BASE", "sub06a")) == 2      # s(2) first: [s(_), s(2)]
    @test _SUB_ncomplete(_SUB_ans("BASE", "sub06b")) == 1      # s(_) first: s(2) is answered from it
    @test _SUB_ans("BASE", "sub06a") != _SUB_ans("BASE", "sub06b")
    @test occursin("i3", _SUB_ans("BASE", "sub14a"))
    @test occursin("i4", _SUB_ans("GEN", "sub14b"))
    @test _SUB_ncomplete(_SUB_ans("GEN", "sub10")) == 3       # g(1,_) alone, then g(_,_) and g(1,_)
    @test _SUB_ncomplete(_SUB_ans("MODED", "sub11")) == 2
    @test "subsumptive" in _SUB_atoms(_SUB_ans("MODED", "sub11"))
    @test _SUB_atoms(_SUB_ans("OPT", "sub13")) == ["table_option", "foo"]
end

@testset "the subsumptive pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "SUBSUMPTIVE ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        for g in _SUB_GROUPS
            @test g.pins[1] == "ok"
            @test [first(split(l, " ")) for l in g.pins[2:end]] ==
                ["t_$id" for (id, _) in g.cases]
        end
    else
        for g in _SUB_GROUPS
            f = joinpath(mktempdir(), "subsumptive_swipl.pl")
            write(f, _SUB_text(g.program, g.cases))
            @test _SUB_swipl_lines(f, ["t_$id" for (id, _) in g.cases]) == g.pins
        end
    end
end
