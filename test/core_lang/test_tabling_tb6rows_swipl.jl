# ORIGINAL: LIVE kill rows for the incremental dependency graph (IDG) of pl-tabling.c / pl-idgset.c (TAB1 TB6-ROWS) against swipl at the pin
# (swipl-devel 18168e62, 10.1.20). They carry the DEFERRED KILLS of tools/mutants/TB6.py (TB6-S6, TB6-C4, TB6-Q5, TB6-P14, TB6-V5, TB6-V6) and the
# rows of TB3 that only an IDG can show (TB3-F4, TB3-T2, TB3-C2): tools/mutants/TB6R.py names each kill by group and case. One program text per
# group, each group in a FRESH database:
#   * CHAIN     cq over cp over the dynamic cd, all incremental: `'$idg_edge'/3` with an UNBOUND direction (Q5), the node space after the
#               graph is built, 3 nodes 2 edges 752 bytes = 512 (the registry block of 64 slots) + 3 * 80 (C4), the falsecounts and
#               statuses after `assertz`, `'$idg_false_edge'/3`, re-evaluation and a retract.
#   * REEVAL    rt over rd(1), rd(2): an answer list re-evaluated after `assertz` (the IDG_DELETED flag of a re-found answer: F4).
#   * SINGLE    a one-answer incremental table has no compiled clause (the trie symbol: T2, C2); a one-answer NON-incremental one has.
#   * FALSECOUNT `'$idg_set_falsecount'/2`: 4294967296 raises representation_error(falsecount) (P14), 4294967295 is taken, the error terms.
#   * ABOLISH   what abolishing tables does to the graph (node count, edge count, bytes, statuses).
#   * EXPAND    six incremental tables over one dynamic: the edge set grows its block with a dead entry in it (S6).
#   * DYNERR / DYNOK  table_space tuned so that the dynamic-call edge raises resource_error(private_table_space) (V5) / just fits.
#   * INCRPROP  predicate_property(_, incremental) of dynamic/2-declared and assertz-created predicates (the control of V6).
#   * TRIEKEYS  the IDG keys of `'$trie_property'/2` (invalidated, reevaluated, idg_affected_count, idg_dependent_count, idg_size).
# `'$trie_property'/2` is read directly, not `trie_property/2`: the Prolog predicate (boot/syspred.pl:1306) needs current_blob/2 (owner Q10; D-0713 item 2).
# Cases `t_<id>(R)` run in order in ONE database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is
# test_tabling_variant_swipl.jl's (`enc`oded answers), the program text the same on both sides. Every answer line is swipl's, PINNED (swipl
# 10.1.20, two byte-identical runs, evidence/TB6ROWS/pins.txt, generators evidence/TB6ROWS/gen/); with `swipl` on PATH the live answers are
# compared with the pins too. A trie blob is never printed.
# ROWS THE KERNEL CANNOT ANSWER YET are `@test_broken <the same comparison>`, never skipped, never weakened (`_T6_BROKEN`, an owner each): a row that
# passes unexpectedly is an Unexpected Pass error, the owner then deletes its entry.
# The V6 white-box row: swipl cannot answer it (PL_CREATE_INCREMENTAL reaches assert_term only through the C function PL_assert), so its two
# `yes` expectations are hand-written, with the C reference at the row.
# UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the verifier runs each row against its mutant.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - these built-ins ride the term layer through the FLI (unify, get, the table pool)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _T6_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_T6_sym(x) = lk_sym(_T6_T, Symbol(x))

_T6_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _T6_enc(t::_T6_T, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _T6_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _T6_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _T6_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_T6_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _T6_DRIVER = raw"""
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

function _T6_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _T6_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
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
_T6_text(program::String, cases) =
    program * join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
        (id, g) in cases
    ])

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _T6_load(program::String, cases)
    f = joinpath(mktempdir(), "tabling_tb6rows.pl")
    write(f, _T6_text(program, cases))
    gd = LK.PL_global_data{_T6_T}()
    ld = LK.PL_local_data{_T6_T}(gd)
    st, ball = LK.load_file!(gd, ld, f)
    return gd, ld, (st === :ok ? "ok" : "exc " * _T6_enc(ball::_T6_T))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _T6_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_T6_sym(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_T6_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _T6_enc(mk_expr(_T6_T, _T6_T[_T6_sym(pred), lk_answers(ld, (a:a)...)...]))
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

"`_T6_ask`, a Julia exception (a NotPortedError of a built-in) answering as the line `<pred> THROWN <type>`."
function _T6_ask_safe(gd, ld, pred::String)::String
    try
        return _T6_ask(gd, ld, pred)
    catch e
        return "$pred THROWN $(typeof(e))"
    end
end

# The pins below are PRINTED BY swipl 10.1.20 (the generators: evidence/TB6ROWS/gen/emit.py), not typed.
const _T6_PROG_CHAIN = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table cp/1 as incremental.
:- table cq/1 as incremental.
:- dynamic([cd/1], [incremental(true)]).
cd(1).
cp(X) :- cd(X).
cq(X) :- cp(X).
"""

const _T6_CASES_CHAIN = [
    ("c01", raw"findall(X, cq(X), L), R = L"),
    (
        "c02",
        raw"tp(cp(_), T), findall(Dir-S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), R)"
    ),
    (
        "c03",
        raw"dirs(cq(_), affected, A1), dirs(cq(_), dependent, D1), dirs(cp(_), affected, A2), dirs(cp(_), dependent, D2), dirs(cd(_), affected, A3), dirs(cd(_), dependent, D3), R = r(A1, D1, A2, D2, A3, D3)"
    ),
    (
        "c04",
        raw"'$idg_thread_summary'(main, N, E), '$idg_thread_space'(main, B), R = r(N, E, B)"
    ),
    (
        "c05",
        raw"assertz(cd(2)), fcn(cd(_), F3), fcn(cp(_), F2), fcn(cq(_), F1), ts(cd(_), S3), ts(cp(_), S2), ts(cq(_), S1), R = r(f(F3, F2, F1), s(S3, S2, S1))"
    ),
    (
        "c06",
        raw"tp(cq(_), T), findall(S, '$idg_false_edge'(T, _, S), L1), tp(cp(_), T2), findall(S, '$idg_false_edge'(T2, _, S), L2), R = r(L1, L2)"
    ),
    (
        "c07",
        raw"findall(X, cq(X), L0), msort(L0, L), fcn(cp(_), F2), fcn(cq(_), F1), ts(cp(_), S2), ts(cq(_), S1), R = r(L, f(F2, F1), s(S2, S1))"
    ),
    (
        "c08",
        raw"retract(cd(1)), findall(X, cq(X), L0), msort(L0, L), fcn(cq(_), F1), ts(cq(_), S1), R = r(L, F1, S1)"
    ),
    (
        "c09",
        raw"'$idg_thread_summary'(main, N, E), '$idg_thread_space'(main, B), R = r(N, E, B)"
    )
]

const _T6_PINS_CHAIN = [
    "ok",
    "t_c01 c[116,95,99,48,49]/1(c[91,124,93]/2(i1,nil))",
    "t_c02 c[116,95,99,48,50]/1(c[91,124,93]/2(c[45]/2(a[97,102,102,101,99,116,101,100],a[99,111,109,112,108,101,116,101]),c[91,124,93]/2(c[45]/2(a[100,101,112,101,110,100,101,110,116],a[100,121,110,97,109,105,99]),nil)))",
    "t_c03 c[116,95,99,48,51]/1(c[114]/6(nil,c[91,124,93]/2(a[99,111,109,112,108,101,116,101],nil),c[91,124,93]/2(a[99,111,109,112,108,101,116,101],nil),c[91,124,93]/2(a[100,121,110,97,109,105,99],nil),c[91,124,93]/2(a[99,111,109,112,108,101,116,101],nil),nil))",
    "t_c04 c[116,95,99,48,52]/1(c[114]/3(i3,i2,i752))",
    "t_c05 c[116,95,99,48,53]/1(c[114]/2(c[102]/3(i1,i1,i1),c[115]/3(a[100,121,110,97,109,105,99],a[105,110,118,97,108,105,100],a[105,110,118,97,108,105,100])))",
    "t_c06 c[116,95,99,48,54]/1(c[114]/2(c[91,124,93]/2(a[105,110,118,97,108,105,100],nil),c[91,124,93]/2(a[100,121,110,97,109,105,99],nil)))",
    "t_c07 c[116,95,99,48,55]/1(c[114]/3(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[102]/2(i0,i0),c[115]/2(a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101])))",
    "t_c08 c[116,95,99,48,56]/1(c[114]/3(c[91,124,93]/2(i2,nil),i0,a[99,111,109,112,108,101,116,101]))",
    "t_c09 c[116,95,99,48,57]/1(c[114]/3(i3,i2,i752))"
]

const _T6_PROG_REEVAL = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table rt/1 as incremental.
:- dynamic([rd/1], [incremental(true)]).
rd(1).
rd(2).
rt(X) :- rd(X).
tv(G, N) :- tp(G, T), '$trie_property'(T, value_count(N)).
"""

const _T6_CASES_REEVAL = [
    ("f01", raw"findall(X, rt(X), L0), msort(L0, L), tv(rt(_), N), R = r(L, N)"),
    (
        "f02",
        raw"assertz(rd(3)), fcn(rt(_), F), ts(rt(_), S), findall(X, rt(X), L0), msort(L0, L), tv(rt(_), N), fcn(rt(_), F1), ts(rt(_), S1), R = r(F, S, L, N, F1, S1)"
    ),
    (
        "f03",
        raw"retract(rd(2)), findall(X, rt(X), L0), msort(L0, L), tv(rt(_), N), R = r(L, N)"
    ),
    (
        "f04",
        raw"tp(rt(_), T), '$idg_thread_summary'(main, Nn, E), '$tbl_reeval_wait'(T, W), R = r(Nn, E, W)"
    ),
    ("f05", raw"findall(X, rt(X), L0), msort(L0, L), tv(rt(_), N), R = r(L, N)")
]

const _T6_PINS_REEVAL = [
    "ok",
    "t_f01 c[116,95,102,48,49]/1(c[114]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),i2))",
    "t_f02 c[116,95,102,48,50]/1(c[114]/6(i1,a[105,110,118,97,108,105,100],c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),i3,i0,a[99,111,109,112,108,101,116,101]))",
    "t_f03 c[116,95,102,48,51]/1(c[114]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil)),i2))",
    "t_f04 c[116,95,102,48,52]/1(c[114]/3(i2,i1,a[99,111,109,112,108,101,116,101]))",
    "t_f05 c[116,95,102,48,53]/1(c[114]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i3,nil)),i2))"
]

const _T6_PROG_SINGLE = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table s1/1 as incremental.
:- table s2/1 as incremental.
:- table s3/1.
:- dynamic([sd1/1, sd2/1], [incremental(true)]).
sd1(1).
sd2(1).
sd2(2).
s1(X) :- sd1(X).
s2(X) :- sd2(X).
s3(X) :- member(X, [1]).
hascl(G, R) :- tp(G, T), tm_yn('$trie_property'(T, compiled_size(_)), R).
"""

const _T6_CASES_SINGLE = [
    (
        "s01",
        raw"findall(X, s1(X), L1), findall(X, s1(X), L2), hascl(s1(_), C), R = r(L1, L2, C)"
    ),
    (
        "s02",
        raw"findall(X, s2(X), L0), msort(L0, L1), findall(X, s2(X), L2), msort(L2, L3), hascl(s2(_), C), R = r(L1, L3, C)"
    ),
    (
        "s03",
        raw"findall(X, s3(X), L1), findall(X, s3(X), L2), hascl(s3(_), C), R = r(L1, L2, C)"
    ),
    (
        "s04",
        raw"assertz(sd1(9)), findall(X, s1(X), L0), msort(L0, L1), findall(X, s1(X), L2), msort(L2, L3), hascl(s1(_), C), R = r(L1, L3, C)"
    )
]

const _T6_PINS_SINGLE = [
    "ok",
    "t_s01 c[116,95,115,48,49]/1(c[114]/3(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i1,nil),a[110,111]))",
    "t_s02 c[116,95,115,48,50]/1(c[114]/3(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),a[121,101,115]))",
    "t_s03 c[116,95,115,48,51]/1(c[114]/3(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i1,nil),a[121,101,115]))",
    "t_s04 c[116,95,115,48,52]/1(c[114]/3(c[91,124,93]/2(i1,c[91,124,93]/2(i9,nil)),c[91,124,93]/2(i1,c[91,124,93]/2(i9,nil)),a[121,101,115]))"
]

const _T6_PROG_FALSECOUNT = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table fp/1 as incremental.
:- dynamic([fd/1], [incremental(true)]).
fd(1).
fp(X) :- fd(X).
"""

const _T6_CASES_FALSECOUNT = [
    (
        "p01",
        raw"findall(X, fp(X), L), tp(fp(_), T), '$idg_set_falsecount'(T, 4294967296), R = L"
    ),
    (
        "p02",
        raw"tp(fp(_), T), '$idg_set_falsecount'(T, 4294967295), '$idg_falsecount'(T, F), ts(fp(_), S), '$idg_set_falsecount'(T, 0), '$idg_falsecount'(T, F0), ts(fp(_), S0), R = r(F, S, F0, S0)"
    ),
    ("p03", raw"tp(fp(_), T), '$idg_set_falsecount'(T, -1), R = ok"),
    ("p04", raw"tp(fp(_), T), '$idg_set_falsecount'(T, _), R = ok"),
    ("p05", raw"tp(fp(_), T), '$idg_set_falsecount'(T, a), R = ok"),
    ("p06", raw"tp(fp(_), T), '$idg_set_falsecount'(T, 4294967297), R = ok"),
    ("p07", raw"tp(fp(_), T), '$idg_set_falsecount'(T, 18446744073709551616), R = ok"),
    ("p08", raw"tp(fp(_), T), '$idg_falsecount'(T, F), R = F")
]

const _T6_PINS_FALSECOUNT = [
    "ok",
    "t_p01 c[116,95,112,48,49]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[102,97,108,115,101,99,111,117,110,116])))",
    "t_p02 c[116,95,112,48,50]/1(c[114]/4(i4294967295,a[105,110,118,97,108,105,100],i0,a[99,111,109,112,108,101,116,101]))",
    "t_p03 c[116,95,112,48,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_p04 c[116,95,112,48,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_p05 c[116,95,112,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_p06 c[116,95,112,48,54]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[102,97,108,115,101,99,111,117,110,116])))",
    "t_p07 c[116,95,112,48,55]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))",
    "t_p08 c[116,95,112,48,56]/1(i0)"
]

const _T6_PROG_ABOLISH = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table ap/1 as incremental.
:- table aq/1 as incremental.
:- table an/1.
:- dynamic([ad/1], [incremental(true)]).
ad(1).
ap(X) :- ad(X).
aq(X) :- ap(X).
an(X) :- member(X, [1, 2]).
summ(r(N, E, B)) :- '$idg_thread_summary'(main, N, E), '$idg_thread_space'(main, B).
alls(r(Sd, Sp, Sq, Sn)) :- ts(ad(_), Sd), ts(ap(_), Sp), ts(aq(_), Sq), ts(an(_), Sn).
"""

const _T6_CASES_ABOLISH = [
    (
        "a01",
        raw"findall(X, aq(X), L), findall(X, an(X), L1), summ(S), alls(A), R = r(L, L1, S, A)"
    ),
    ("a02", raw"abolish_all_tables, summ(S), alls(A), R = r(S, A)"),
    ("a03", raw"findall(X, aq(X), L), summ(S), alls(A), R = r(L, S, A)"),
    ("a04", raw"abolish_module_tables(user), summ(S), alls(A), R = r(S, A)"),
    (
        "a05",
        raw"findall(X, aq(X), L), findall(X, an(X), L1), abolish_table_subgoals(ap(_)), summ(S), alls(A), R = r(L, L1, S, A)"
    ),
    (
        "a06",
        raw"findall(X, aq(X), L), abolish_nonincremental_tables, summ(S), alls(A), R = r(L, S, A)"
    ),
    ("a07", raw"abolish_module_tables(nosuchmodule), summ(S), alls(A), R = r(S, A)"),
    ("a08", raw"abolish_table_subgoals(aq(_)), summ(S), alls(A), R = r(S, A)")
]

const _T6_PINS_ABOLISH = [
    "ok",
    "t_a01 c[116,95,97,48,49]/1(c[114]/4(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[114]/3(i3,i2,i752),c[114]/4(a[100,121,110,97,109,105,99],a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101])))",
    "t_a02 c[116,95,97,48,50]/1(c[114]/2(c[114]/3(i0,i0,i0),c[114]/4(a[110,111,110,101],a[110,111,110,101],a[110,111,110,101],a[110,111,110,101])))",
    "t_a03 c[116,95,97,48,51]/1(c[114]/3(c[91,124,93]/2(i1,nil),c[114]/3(i3,i2,i752),c[114]/4(a[100,121,110,97,109,105,99],a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101],a[110,111,110,101])))",
    "t_a04 c[116,95,97,48,52]/1(c[114]/2(c[114]/3(i0,i0,i512),c[114]/4(a[110,111,110,101],a[110,111,110,101],a[110,111,110,101],a[110,111,110,101])))",
    "t_a05 c[116,95,97,48,53]/1(c[114]/4(c[91,124,93]/2(i1,nil),c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[114]/3(i1,i0,i592),c[114]/4(a[110,111,110,101],a[110,111,110,101],a[99,111,109,112,108,101,116,101],a[99,111,109,112,108,101,116,101])))",
    "t_a06 c[116,95,97,48,54]/1(c[114]/3(c[91,124,93]/2(i1,nil),c[114]/3(i1,i0,i592),c[114]/4(a[110,111,110,101],a[110,111,110,101],a[99,111,109,112,108,101,116,101],a[110,111,110,101])))",
    "t_a07 c[116,95,97,48,55]/1(c[114]/2(c[114]/3(i1,i0,i592),c[114]/4(a[110,111,110,101],a[110,111,110,101],a[99,111,109,112,108,101,116,101],a[110,111,110,101])))",
    "t_a08 c[116,95,97,48,56]/1(c[114]/2(c[114]/3(i0,i0,i512),c[114]/4(a[110,111,110,101],a[110,111,110,101],a[110,111,110,101],a[110,111,110,101])))"
]

const _T6_PROG_EXPAND = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table t1/1 as incremental.
:- table t2/1 as incremental.
:- table t3/1 as incremental.
:- table t4/1 as incremental.
:- table t5/1 as incremental.
:- table t6/1 as incremental.
:- dynamic([xd/1], [incremental(true)]).
xd(1).
t1(X) :- xd(X).
t2(X) :- xd(X).
t3(X) :- xd(X).
t4(X) :- xd(X).
t5(X) :- xd(X).
t6(X) :- xd(X).
summ(r(N, E)) :- '$idg_thread_summary'(main, N, E).
nedge(N) :- tp(xd(_), T), findall(D, '$idg_edge'(T, affected, D), L), length(L, N).
"""

const _T6_CASES_EXPAND = [
    (
        "x01",
        raw"findall(X, t1(X), _), findall(X, t2(X), _), findall(X, t3(X), _), findall(X, t4(X), _), summ(S), nedge(N), R = r(S, N)"
    ),
    ("x02", raw"abolish_table_subgoals(t3(_)), summ(S), nedge(N), R = r(S, N)"),
    ("x03", raw"findall(X, t5(X), _), summ(S), nedge(N), R = r(S, N)"),
    ("x04", raw"findall(X, t6(X), _), summ(S), nedge(N), R = r(S, N)"),
    (
        "x05",
        raw"assertz(xd(2)), tp(t1(_), T1), tp(t5(_), T5), '$idg_falsecount'(T1, F1), '$idg_falsecount'(T5, F5), ts(t3(_), S3), R = r(F1, F5, S3)"
    )
]

const _T6_PINS_EXPAND = [
    "ok",
    "t_x01 c[116,95,120,48,49]/1(c[114]/2(c[114]/2(i5,i4),i4))",
    "t_x02 c[116,95,120,48,50]/1(c[114]/2(c[114]/2(i4,i3),i3))",
    "t_x03 c[116,95,120,48,51]/1(c[114]/2(c[114]/2(i5,i4),i4))",
    "t_x04 c[116,95,120,48,52]/1(c[114]/2(c[114]/2(i6,i5),i5))",
    "t_x05 c[116,95,120,48,53]/1(c[114]/3(i1,i1,a[110,111,110,101]))"
]

const _T6_PROG_DYNERR = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table vp/1 as incremental.
:- dynamic([vd/1], [incremental(true)]).
vd(1).
vp(X) :- vd(X).
"""

const _T6_CASES_DYNERR = [
    ("v01", raw"set_prolog_flag(table_space, 1508), findall(X, vp(X), L), R = L"),
    (
        "v02",
        raw"'$idg_thread_summary'(main, N, E), ts(vp(_), S1), ts(vd(_), S2), R = r(N, E, S1, S2)"
    ),
    (
        "v03",
        raw"set_prolog_flag(table_space, 1000000000), findall(X, vp(X), L), '$idg_thread_summary'(main, N, E), ts(vp(_), S1), ts(vd(_), S2), R = r(L, N, E, S1, S2)"
    )
]

const _T6_PINS_DYNERR = [
    "ok",
    "t_v01 c[116,95,118,48,49]/1(c[114,97,105,115,101,100]/1(c[114,101,115,111,117,114,99,101,95,101,114,114,111,114]/1(a[112,114,105,118,97,116,101,95,116,97,98,108,101,95,115,112,97,99,101])))",
    "t_v02 c[116,95,118,48,50]/1(c[114]/4(i1,i0,a[110,111,110,101],a[100,121,110,97,109,105,99]))",
    "t_v03 c[116,95,118,48,51]/1(c[114]/5(c[91,124,93]/2(i1,nil),i2,i1,a[99,111,109,112,108,101,116,101],a[100,121,110,97,109,105,99]))"
]

const _T6_PROG_DYNOK = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table vp/1 as incremental.
:- dynamic([vd/1], [incremental(true)]).
vd(1).
vp(X) :- vd(X).
"""

const _T6_CASES_DYNOK = [
    ("v01", raw"set_prolog_flag(table_space, 1516), findall(X, vp(X), L), R = L"),
    (
        "v02",
        raw"'$idg_thread_summary'(main, N, E), ts(vp(_), S1), ts(vd(_), S2), R = r(N, E, S1, S2)"
    ),
    (
        "v03",
        raw"set_prolog_flag(table_space, 1000000000), findall(X, vp(X), L), '$idg_thread_summary'(main, N, E), ts(vp(_), S1), ts(vd(_), S2), R = r(L, N, E, S1, S2)"
    )
]

const _T6_PINS_DYNOK = [
    "ok",
    "t_v01 c[116,95,118,48,49]/1(c[91,124,93]/2(i1,nil))",
    "t_v02 c[116,95,118,48,50]/1(c[114]/4(i2,i1,a[99,111,109,112,108,101,116,101],a[100,121,110,97,109,105,99]))",
    "t_v03 c[116,95,118,48,51]/1(c[114]/5(c[91,124,93]/2(i1,nil),i2,i1,a[99,111,109,112,108,101,116,101],a[100,121,110,97,109,105,99]))"
]

const _T6_PROG_INCRPROP = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table ip/1 as incremental.
:- dynamic([id/1], [incremental(true)]).
:- dynamic(plain/1).
id(1).
ip(X) :- id(X).
inc_prop(G, R) :- tm_yn(predicate_property(G, incremental), R).
dyn_prop(G, R) :- tm_yn(predicate_property(G, dynamic), R).
"""

const _T6_CASES_INCRPROP = [
    (
        "i01",
        raw"assertz(wb_plain(1)), inc_prop(wb_plain(_), I), dyn_prop(wb_plain(_), D), R = r(I, D)"
    ),
    (
        "i02",
        raw"inc_prop(id(_), I), dyn_prop(id(_), D), inc_prop(plain(_), I2), dyn_prop(plain(_), D2), inc_prop(ip(_), I3), R = r(I, D, I2, D2, I3)"
    )
]

const _T6_PINS_INCRPROP = [
    "ok",
    "t_i01 c[116,95,105,48,49]/1(c[114]/2(a[110,111],a[121,101,115]))",
    "t_i02 c[116,95,105,48,50]/1(c[114]/5(a[121,101,115],a[121,101,115],a[110,111],a[121,101,115],a[121,101,115]))"
]

const _T6_PROG_TRIEKEYS = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
tp(G, T) :- '$tbl_existing_variant_table'(0, user:G, T, _, _).
ts(G, S) :- ( tp(G, T) -> '$tbl_table_status'(T, S) ; S = none ).
fcn(G, F) :- ( tp(G, T) -> '$idg_falsecount'(T, F) ; F = none ).
dirs(G, Dir, L) :- tp(G, T), findall(S, ('$idg_edge'(T, Dir, D), '$tbl_table_status'(D, S)), L).

:- table cp/1 as incremental.
:- table cq/1 as incremental.
:- dynamic([cd/1], [incremental(true)]).
cd(1).
cp(X) :- cd(X).
cq(X) :- cp(X).
tk(G, K, V) :- tp(G, T), K =.. [_, V], ( '$trie_property'(T, K) -> true ; V = none ).
keys(G, r(A, D, S, I, R)) :- tk(G, idg_affected_count(A), _), tk(G, idg_dependent_count(D), _), tk(G, idg_size(S), _), tk(G, invalidated(I), _), tk(G, reevaluated(R), _).
"""

const _T6_CASES_TRIEKEYS = [
    (
        "k01",
        raw"findall(X, cq(X), _), keys(cp(_), K1), keys(cq(_), K2), keys(cd(_), K3), R = r(K1, K2, K3)"
    ),
    (
        "k02",
        raw"assertz(cd(2)), keys(cp(_), K1), keys(cq(_), K2), keys(cd(_), K3), R = r(K1, K2, K3)"
    ),
    (
        "k03",
        raw"findall(X, cq(X), _), keys(cp(_), K1), keys(cq(_), K2), keys(cd(_), K3), R = r(K1, K2, K3)"
    )
]

const _T6_PINS_TRIEKEYS = [
    "ok",
    "t_k01 c[116,95,107,48,49]/1(c[114]/3(c[114]/5(i1,i1,i80,i0,i0),c[114]/5(i0,i1,i80,i0,i0),c[114]/5(i1,i0,i80,i0,i0)))",
    "t_k02 c[116,95,107,48,50]/1(c[114]/3(c[114]/5(i1,i1,i80,i1,i0),c[114]/5(i0,i1,i80,i1,i0),c[114]/5(i1,i0,i80,i1,i0)))",
    "t_k03 c[116,95,107,48,51]/1(c[114]/3(c[114]/5(i1,i1,i80,i1,i1),c[114]/5(i0,i1,i80,i1,i1),c[114]/5(i1,i0,i80,i1,i0)))"
]

const _T6_GROUPS = [
    (
        key="CHAIN",
        label=raw"CHAIN: `'$idg_edge'/3` with a free direction, the node space, falsecounts through a chain (kills TB6-Q5 c02, TB6-C4 c04 c09)",
        program=_T6_PROG_CHAIN,
        cases=_T6_CASES_CHAIN,
        pins=_T6_PINS_CHAIN
    ),
    (
        key="REEVAL",
        label=raw"REEVAL: re-found answers of a re-evaluated table keep their place (kills TB3-F4 f02)",
        program=_T6_PROG_REEVAL,
        cases=_T6_CASES_REEVAL,
        pins=_T6_PINS_REEVAL
    ),
    (
        key="SINGLE",
        label=raw"SINGLE: a one-answer incremental table has no compiled clause (kills TB3-T2, TB3-C2: s01 with TR4, partner s02-s04)",
        program=_T6_PROG_SINGLE,
        cases=_T6_CASES_SINGLE,
        pins=_T6_PINS_SINGLE
    ),
    (
        key="FALSECOUNT",
        label=raw"FALSECOUNT: `'$idg_set_falsecount'/2` and its 32-bit range (kills TB6-P14 p01 p06)",
        program=_T6_PROG_FALSECOUNT,
        cases=_T6_CASES_FALSECOUNT,
        pins=_T6_PINS_FALSECOUNT
    ),
    (
        key="ABOLISH",
        label=raw"ABOLISH: the graph after abolish_all_tables, abolish_module_tables, abolish_table_subgoals, abolish_nonincremental_tables (owner TB5 + TB6: the IDG half of the destroy)",
        program=_T6_PROG_ABOLISH,
        cases=_T6_CASES_ABOLISH,
        pins=_T6_PINS_ABOLISH
    ),
    (
        key="EXPAND",
        label=raw"EXPAND: an edge set grown with a dead entry in its block (kills TB6-S6 x03 once TB5 lands: x02-x05 need abolish_table_subgoals; the white-box testset below kills it now)",
        program=_T6_PROG_EXPAND,
        cases=_T6_CASES_EXPAND,
        pins=_T6_PINS_EXPAND
    ),
    (
        key="DYNERR",
        label=raw"DYNERR: resource_error(private_table_space) at the dynamic-call edge (kills TB6-V5 v01 v02)",
        program=_T6_PROG_DYNERR,
        cases=_T6_CASES_DYNERR,
        pins=_T6_PINS_DYNERR
    ),
    (
        key="DYNOK",
        label=raw"DYNOK: the same program with a limit that just fits (control of DYNERR, kills TB6-V5 with it)",
        program=_T6_PROG_DYNOK,
        cases=_T6_CASES_DYNOK,
        pins=_T6_PINS_DYNOK
    ),
    (
        key="INCRPROP",
        label=raw"INCRPROP: `incremental` of dynamic/2-declared, plain and assertz-created predicates (control of TB6-V6)",
        program=_T6_PROG_INCRPROP,
        cases=_T6_CASES_INCRPROP,
        pins=_T6_PINS_INCRPROP
    ),
    (
        key="TRIEKEYS",
        label=raw"TRIEKEYS: the IDG keys of `'$trie_property'/2` (ported: pl-trie.jl `pl_trie_property2_va`, pl-trie.c:4326-4345)",
        program=_T6_PROG_TRIEKEYS,
        cases=_T6_CASES_TRIEKEYS,
        pins=_T6_PINS_TRIEKEYS
    )
]

# Rows whose kernel side cannot answer yet: `GROUP/case => owner`. Each is `@test_broken` below, the same comparison as its neighbours.
const _T6_BROKEN = Dict{String, String}(
    # UPDATED (TB6-HAND): the owner builtin of every entry below is NOW ON this branch (wip/tb6p2), so each row is EXPECTED TO PASS. The entries stay
    # `@test_broken` until the kernel run shows the unexpected passes (an unexpected pass is an error by design: the run decides); the dispatcher then
    # flips the rows to `@test` and deletes the entries. The old owner text follows in each entry after `was:`.
    # TABM-DIAG2: the lane-2 run of 2026-11-14 (tb6rows, after b222a5a9) passed SINGLE s02-s04, ABOLISH a02-a03 and EXPAND x02-x05 unexpectedly: their entries are
    # deleted (the rows are `@test` now). ABOLISH a04-a08 still differ from swipl's pins in that run and stay below.
    "ABOLISH/a04" => "owner builtins PRESENT: abolish_module_tables/1 (boot/tabling.pl:1133) calls the same two; expected to pass",
    "ABOLISH/a05" => "owner builtin PRESENT: `'\$tbl_destroy_table'/1` (pl-tabling.jl:9773); abolish_table_subgoals/1 (boot/tabling.pl:1158-1168, vendored) calls it; expected to pass",
    "ABOLISH/a06" => "owner builtin PRESENT: `'\$tbl_destroy_table'/1`; abolish_nonincremental_tables/0 (boot/tabling.pl:1187) calls it; expected to pass",
    "ABOLISH/a07" => "owner builtins PRESENT: abolish_module_tables/1; expected to pass",
    "ABOLISH/a08" => "owner builtin PRESENT: abolish_table_subgoals/1 (vendored boot/tabling.pl:1158); expected to pass",
    # TABM-PREP (audit D-0736 (2)): the lane-2 runs of 2026-11-14 (397efdd3) show a04-a08 still differing (TABM-DIAG2: a04/a05 raise a refusal,
    # a06-a08 leave IDG nodes after the abolish; undiagnosed, owner TAB1). DYNERR v01/v02: the kernel charges no trie memory to `table_space`
    # (upstream pl-trie.c:238, :772, :1087, :1105, :1113 charge; :257, :269, :729, :1200, :1268, :1389 release), so the limit 1508 is never
    # reached: owner TRIE-CHARGE (wip/trie-charge). The pins stay swipl's.
    "DYNERR/v01" => "owner TRIE-CHARGE: trie memory is not charged to table_space yet (pl-trie.c:238 etc.); the dynamic-call edge then fits",
    "DYNERR/v02" => "owner TRIE-CHARGE: same cause as v01 (the table completes instead of staying `none`)"
)

@testset "TB6 rows as swipl's: $(g.label)" for g in _T6_GROUPS
    gd, ld, st = _T6_load(g.program, g.cases)
    @test st == "ok"
    @test !isempty(g.cases)                                   # both sides non-empty, through the ONE extractor `_T6_ask`
    kl = String[st]
    for (id, _) in g.cases
        push!(kl, _T6_ask_safe(gd, ld, "t_$id"))
    end
    @test length(kl) == length(g.pins) == length(g.cases) + 1
    for ((id, _), k, p) in zip(g.cases, kl[2:end], g.pins[2:end])
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        if haskey(_T6_BROKEN, "$(g.key)/$id")
            @test_broken k == p                               # $(_T6_BROKEN[...]) above; an unexpected pass is an error
        else
            @test k == p
        end
    end
end

# THE V6 WHITE-BOX ROW. swipl CANNOT answer it: `PL_CREATE_INCREMENTAL` reaches `assert_term` only through the C function `PL_assert`
# (pl-comp.c:9241, which passes it on; assert/1, asserta/1 and assertz/1 pass 0: pl-comp.c:5078, :5086, :5107, :5121), where it makes a procedure that is
# not yet defined incremental (`flags && !isDefinedProcedure(def)`, pl-comp.c:4915-4917). So the expectations `yes` are hand-written from that C text:
#   wb_inc   new predicate, flag set       -> incremental yes, dynamic yes
#   wb_plain2 new predicate, flags 0       -> incremental no,  dynamic yes (the control: assertz makes it dynamic only)
#   wb_def   defined first with flags 0, then asserted again with the flag -> incremental no (the flag applies only to a not yet defined procedure)
const _T6_PROG_WB = raw"""
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
inc_prop(G, R) :- tm_yn(predicate_property(G, incremental), R).
dyn_prop(G, R) :- tm_yn(predicate_property(G, dynamic), R).
"""
const _T6_CASES_WB = [
    ("w01", raw"inc_prop(wb_inc(_), I), dyn_prop(wb_inc(_), D), R = r(I, D)"),
    ("w02", raw"inc_prop(wb_plain2(_), I), dyn_prop(wb_plain2(_), D), R = r(I, D)"),
    ("w03", raw"inc_prop(wb_def(_), I), dyn_prop(wb_def(_), D), R = r(I, D)")
]

_T6_fw(ld, name, n) = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _T6_sym(name)), n)
_T6_gw(p) = LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
"Lay compound `name/length(args)` out on the global stack, argument `i` the word `args[i]`; its position."
function _T6_lay!(ld, name, args...)
    p = LK._alloc_compound!(ld, _T6_fw(ld, name, length(args)), length(args))
    for (i, w) in enumerate(args)
        ld.gstack[p + i] = w
    end
    return p
end
"`assert_term!` of the fact `name(a)` at the end, with `flags` (the call `PL_assert` makes)."
function _T6_assert!(gd, ld, name::String, flags::Integer)   # PL_CREATE_INCREMENTAL is a UInt16
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_ref(ld)
    p = _T6_lay!(ld, name, LK._atom_word!(ld, _T6_sym("a")))
    ld.slots[t + 1] = _T6_gw(p)
    c = LK.assert_term!(gd, ld, t, 0, LK.CL_END, nothing, nothing, Int(flags))
    LK.PL_close_foreign_frame(ld, fid)
    return c
end
"The pinned-style line of case `id`: `t_<id>` answering r(a, b)."
_T6_expect(id, a, b) =
    "t_$id " * _T6_enc(
        mk_expr(
            _T6_T,
            _T6_T[
                _T6_sym("t_$id"),
                mk_expr(_T6_T, _T6_T[_T6_sym("r"), _T6_sym(a), _T6_sym(b)])
            ]
        )
    )

@testset "TB6 V6 white-box: PL_CREATE_INCREMENTAL makes a new procedure incremental (kills TB6-V6)" begin
    gd, ld, st = _T6_load(_T6_PROG_WB, _T6_CASES_WB)
    @test st == "ok"
    @test _T6_assert!(gd, ld, "wb_inc", LK.PL_CREATE_INCREMENTAL) !== nothing
    @test _T6_assert!(gd, ld, "wb_plain2", 0) !== nothing
    @test _T6_assert!(gd, ld, "wb_def", 0) !== nothing
    @test _T6_assert!(gd, ld, "wb_def", LK.PL_CREATE_INCREMENTAL) !== nothing
    @test _T6_ask(gd, ld, "t_w01") == _T6_expect("w01", "yes", "yes")
    @test _T6_ask(gd, ld, "t_w02") == _T6_expect("w02", "no", "yes")
    @test _T6_ask(gd, ld, "t_w03") == _T6_expect("w03", "no", "yes")
    # not vacuous: the row differs from its control exactly where the mutant's inverted test would differ
    @test _T6_expect("w01", "yes", "yes") != _T6_expect("w02", "no", "yes")
end

# THE S6 WHITE-BOX ROW (kills TB6-S6 without TB5). Hand-written from the C text, not from swipl (no Prolog route reaches an edge set with a dead entry until
# abolish exists): grow_block copies the dead count into the new block (`nb->dead = b->dead`, pl-idgset.c:250 at the pin), so after one delete in a full block of 4
# and the add that grows it to 8 the set counts 4 live entries (`idg_set_size` = count - dead, pl-idgset.c:387) and the block still carries dead = 1.
const _T6N = LK.idg_node{_T6_T}
"A fresh complete answer trie with its IDG node (`idg_new`, the node attached as `idg_init_variant` does)."
function _T6_node(ld)
    tr = LK.trie_create(_T6_T)
    tr.flags |= LK.TRIE_COMPLETE
    n = LK.idg_new(ld, tr)::_T6N
    tr.IDG = n
    return n
end
"The live entries of an edge set, in enumeration order."
function _T6_live(set)::Vector{_T6N}
    out = _T6N[]
    e = LK.idg_set_enum_init(set)
    while (p = LK.idg_set_next(e)) !== nothing
        push!(out, p)
    end
    return out
end

@testset "TB6 S6 white-box: grow_block carries the dead count of a block (kills TB6-S6)" begin
    gd = LK.PL_global_data{_T6_T}()
    ld = LK.PL_local_data{_T6_T}(gd)
    nodes = [_T6_node(ld) for _ in 1:6]
    set = LK.idg_set{_T6N}()
    add(p) = LK.idg_set_add(ld, set, p, nothing, nothing)
    for i in 1:4
        @test add(nodes[i]) == 1
    end
    @test set.block.capacity == 4 && set.block.dead == 0
    @test LK.idg_set_delete(set, nodes[3], nothing, nothing)
    @test set.block.dead == 1 && LK.idg_set_size(set) == 3
    @test add(nodes[5]) == 1 && set.block.capacity == 8                # the grow: the block is a new one
    @test set.block.dead == 1                                          # carried over (S6's mutant: 0)
    @test LK.idg_set_size(set) == 4                                    # count 5 - dead 1 (S6's mutant: 5)
    @test _T6_live(set) == nodes[[1, 2, 4, 5]]
    @test !LK.idg_set_contains(set, nodes[3])
    @test add(nodes[3]) == 1 && set.block.dead == 0 && LK.idg_set_size(set) == 5   # the dead entry revived in place
end

"The atoms (`a[codes]`) of a pinned answer line, in order."
function _T6_atoms(line::AbstractString)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"a\[([0-9,]+)\]", line)
    ]
end
"The integers (`i<n>`) of a pinned answer line, in order."
function _T6_ints(line::AbstractString)::Vector{BigInt}
    return [parse(BigInt, m.captures[1]) for m in eachmatch(r"(?<![a-z])i(-?[0-9]+)", line)]
end

_T6_group(key) = only(filter(g -> g.key == key, _T6_GROUPS))
"The answer part of the pinned line of case `id` in group `key`."
function _T6_ans(key, id)
    g = _T6_group(key)
    return split(only(filter(l -> startswith(l, "t_$id "), g.pins)), " "; limit=2)[2]
end

@testset "the TB6 rows are not vacuous" begin
    for g in _T6_GROUPS
        @test g.pins[1] == "ok"
        @test length(g.pins) == length(g.cases) + 1
        @test all(!isempty, g.pins)
        for (id, goal) in g.cases
            @test !isempty(goal)
            @test count(l -> startswith(l, "t_$id "), g.pins) == 1
        end
    end
    for k in keys(_T6_BROKEN)                                  # a broken row names a case that exists
        key, id = split(k, "/")
        @test any(==(id), first.(_T6_group(key).cases))
    end
    # CHAIN: cp has a parent (affected) AND a child (dependent) in one enumeration with a free direction (Q5's mutant stops after the first set)
    @test _T6_atoms(_T6_ans("CHAIN", "c02")) ==
        ["affected", "complete", "dependent", "dynamic"]
    @test _T6_atoms(_T6_ans("CHAIN", "c03")) ==
        ["complete", "complete", "dynamic", "complete"]
    # the node space: 3 nodes, 2 edges, 752 bytes = 512 + 3 * 80 (C4's 72 gives 728), the same after the re-evaluation
    @test _T6_ints(_T6_ans("CHAIN", "c04")) == [3, 2, 752]
    @test _T6_ans("CHAIN", "c04") ==
        replace(_T6_ans("CHAIN", "c09"), "c[116,95,99,48,57]" => "c[116,95,99,48,52]")
    @test 512 + 3 * 80 == 752
    @test _T6_ints(_T6_ans("CHAIN", "c05")) == [1, 1, 1]
    @test _T6_atoms(_T6_ans("CHAIN", "c05")) == ["dynamic", "invalid", "invalid"]
    @test _T6_ints(_T6_ans("CHAIN", "c07")) == [1, 2, 0, 0]
    # REEVAL: the answers 1 and 2 re-found at the re-evaluation are kept: three answers, value_count 3 (F4's flag left set deletes them)
    @test _T6_ints(_T6_ans("REEVAL", "f02")) == [1, 1, 2, 3, 3, 0]
    @test _T6_atoms(_T6_ans("REEVAL", "f02")) == ["invalid", "complete"]
    @test _T6_ans("REEVAL", "f01") != _T6_ans("REEVAL", "f02")
    # SINGLE: the single-answer incremental table has no compiled clause, the others have (a mutant compiling the first, or not the others, differs)
    @test _T6_atoms(_T6_ans("SINGLE", "s01")) == ["no"]
    for id in ("s02", "s03", "s04")
        @test _T6_atoms(_T6_ans("SINGLE", id)) == ["yes"]
    end
    @test _T6_ans("SINGLE", "s01") != _T6_ans("SINGLE", "s02")
    # FALSECOUNT: 2^32 is refused, 2^32 - 1 is taken (P14's mutant takes both)
    @test _T6_atoms(_T6_ans("FALSECOUNT", "p01")) == ["falsecount"]
    @test _T6_atoms(_T6_ans("FALSECOUNT", "p06")) == ["falsecount"]
    @test _T6_ints(_T6_ans("FALSECOUNT", "p02")) == [4294967295, 0]
    @test _T6_ans("FALSECOUNT", "p01") != _T6_ans("FALSECOUNT", "p02")
    @test _T6_atoms(_T6_ans("FALSECOUNT", "p07")) == ["size_t"]
    # ABOLISH: a graph, then each kind of abolish takes its part away
    @test _T6_ints(_T6_ans("ABOLISH", "a01")) == [1, 1, 2, 3, 2, 752]
    @test _T6_ints(_T6_ans("ABOLISH", "a02")) == [0, 0, 0]
    @test _T6_ans("ABOLISH", "a01") != _T6_ans("ABOLISH", "a02")
    @test _T6_ints(_T6_ans("ABOLISH", "a05")) == [1, 1, 2, 1, 0, 592]
    # EXPAND: after the dead slot (x02) the fifth table x03 revives it: 4 edges as before the abolish, x04 grows the set past 8: 5 edges
    @test _T6_ints(_T6_ans("EXPAND", "x01")) == [5, 4, 4]
    @test _T6_ints(_T6_ans("EXPAND", "x02")) == [4, 3, 3]
    @test _T6_ints(_T6_ans("EXPAND", "x03")) == [5, 4, 4]
    @test _T6_ints(_T6_ans("EXPAND", "x04")) == [6, 5, 5]
    @test _T6_ans("EXPAND", "x03") != _T6_ans("EXPAND", "x04")
    @test _T6_ans("EXPAND", "x03") != _T6_ans("EXPAND", "x02")
    # DYNERR / DYNOK: the same program, only the limit differs
    @test _T6_atoms(_T6_ans("DYNERR", "v01")) == ["private_table_space"]
    @test _T6_ints(_T6_ans("DYNERR", "v02")) == [1, 0]
    @test _T6_atoms(_T6_ans("DYNERR", "v02")) == ["none", "dynamic"]
    @test _T6_ints(_T6_ans("DYNOK", "v02")) == [2, 1]
    @test _T6_atoms(_T6_ans("DYNOK", "v02")) == ["complete", "dynamic"]
    @test _T6_ans("DYNERR", "v01") != _T6_ans("DYNOK", "v01")
    @test _T6_ans("DYNERR", "v02") != _T6_ans("DYNOK", "v02")
    @test _T6_ans("DYNERR", "v03") == _T6_ans("DYNOK", "v03")
    # INCRPROP
    @test _T6_atoms(_T6_ans("INCRPROP", "i01")) == ["no", "yes"]
    @test _T6_atoms(_T6_ans("INCRPROP", "i02")) == ["yes", "yes", "no", "yes", "yes"]
    # TRIEKEYS (the handler is ported: pl-trie.jl `pl_trie_property2_va`, pl-trie.c:4326-4345): every key has a number (a failing key would print `none`), idg_size 80 on all three nodes
    for id in ("k01", "k02", "k03")
        @test "none" ∉ _T6_atoms(_T6_ans("TRIEKEYS", id))
        @test count(==(80), _T6_ints(_T6_ans("TRIEKEYS", id))) == 3
    end
    @test _T6_ans("TRIEKEYS", "k01") != _T6_ans("TRIEKEYS", "k02")
    @test _T6_ans("TRIEKEYS", "k02") != _T6_ans("TRIEKEYS", "k03")
end

@testset "the TB6 pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TB6 ROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        # without swipl the pins are all there is: the load line `ok`, then one `t_<id> answer` line per case, in order
        for g in _T6_GROUPS
            @test g.pins[1] == "ok"
            @test [first(split(l, " ")) for l in g.pins[2:end]] ==
                ["t_$id" for (id, _) in g.cases]
        end
    else
        for g in _T6_GROUPS
            f = joinpath(mktempdir(), "tb6rows_swipl.pl")
            write(f, _T6_text(g.program, g.cases))
            @test _T6_swipl_lines(f, ["t_$id" for (id, _) in g.cases]) == g.pins
        end
    end
end
