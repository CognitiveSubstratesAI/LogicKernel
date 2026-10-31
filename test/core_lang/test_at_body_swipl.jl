# ORIGINAL: MOD3b's gate (lk-channel evidence/r2/design/modules.md §7) — `Goal@Module` in a clause body and `call/1` of `Goal@Module`, against swipl 10.1.19; the rows are tests/core_lang/test_qcall.pl's at / vat / atv / atvv / atvvv cases (written as the canonical `@(Goal, Module)`: the term is the same as with `:- op(900, xfx, @)`), plus the shapes around them, as clauses of a consulted program (plunit and module files need the loader).
# test/core_lang/test_at_body_swipl.jl — the at context of the body compiler (pl-comp.c `getTargetModule` with `at_context`, `compileBody`'s
# `CB_ATSIGN`, `compileSubClause`'s `O_CALL_AT_MODULE` call selection and meta-call wrapper, `callatm`, `callatmv`), the run loop's
# `I_CALLATM`, `I_DEPARTATM`, `I_CALLATMV`, `I_DEPARTATMV` (pl-vmi.c), `call/1` of `Goal@Module` (`i_metacall_common` +
# pl-wam.c `checkCallAtContextInstantiation`), and the decompiler's `Goal@Module` (pl-comp.c decompileBody):
#   * A PROGRAM consulted by the kernel's loader — user clauses with `Goal@Module` bodies — and cases `t_<id>(R)` run IN ORDER
#     in one database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`.
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, this program and test_colon_body_swipl.jl's driver, 2026-10-31,
#     lk-channel evidence/MOD3b/mod3b_rows.out in the MOD3b branch); with `swipl` on PATH the live answers are compared with the pins too.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the at context (src/pl-comp.jl, src/pl-wam.jl), built on the term layer; every type in CI and at milestones
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

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
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
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: `qm`'s transparent qm/1 through directives (as MOD3a's rows, test_colon_body_swipl.jl), the clauses under test as the file's
const _AB_PROGRAM = raw"""
:- assertz(qm:(qm(C) :- context_module(C))).
:- '$set_predicate_attribute'(qm:qm(_), transparent, true).
m(qm).
m2(qm2).
g(A, qm(A)).
utp(M) :- context_module(M).
:- '$set_predicate_attribute'(utp(_), transparent, true).
p(1).
p(2).
p(3).
at(C) :- @(qm:qm(C), qm2).
atnl(C) :- @(qm:qm(C), qm2), true.
atu(C) :- @(utp(C), qm2).
atunl(C) :- @(utp(C), qm2), true.
vat(C) :- m(M), @(M:qm(C), qm2).
atv(C) :- m2(QC), @(qm:qm(C), QC).
atvn(C) :- m2(QC), @(qm:qm(C), QC), true.
atvu(C) :- m2(QC), @(utp(C), QC).
atvcp(C) :- m2(QC), between(1, 2, _), @(qm:qm(C), QC).
atvv(C) :- m(M), m2(QC), @(M:qm(C), QC).
atvvv(C) :- m(M), m2(QC), g(C, G), @(M:G, QC).
atvvc(C) :- m(M), m2(QC), g(C, G), @(M:(G, true), QC).
atg(C) :- G = utp(C), @(G, qm2).
atrestore(C1, C2) :- @(utp(C1), qm2), utp(C2).
atnest(C) :- @(@(utp(C), qm2), qm).
atctl(X) :- @((true -> X = 1 ; X = 2), qm2).
atctx(C) :- @((utp(C), true), qm2).
atunify(X) :- @(X = a, qm2).
atcut :- @(!, qm2).
atcalln(C) :- @(call(utp, C), qm2).
rt(M, R) :- @(utp(R), M).
rtn(M, R) :- @(utp(R), M), true.
lcm(N, U, M) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, @(lcm(N1, U, M), M) ).
lca(N, U) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, @(lca(N1, U), qm2) ).
lcpm(N, U, M) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, between(1, 2, _), @(lcpm(N1, U, M), M) ).
lcpa(N, U) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, between(1, 2, _), @(lcpa(N1, U), qm2) ).
atcpx(C0, C) :- m2(QC), between(1, 2, _), utp(C0), @(qm:qm(C), QC).
atcpa(C0, C) :- between(1, 2, _), utp(C0), @(utp(C), qm2).
atnest2(C1, C2) :- @((@(utp(C1), qm2), utp(C2)), qm).
"""

# (id, goal), run IN ORDER
const _AB_CASES = [
    # a01-a04: test_qcall's `at` (`qm:qm(C)@qm2`: procedure-module qm, context qm2) as the clause's last goal (I_DEPARTATM, a01)
    # and not (I_CALLATM, a02); the same with no colon (the procedure-module operand 0): a03, a04. Transparent: the context is qm2.
    ("a01", raw"at(R)"),
    ("a02", raw"atnl(R)"),
    ("a03", raw"atu(R)"),
    ("a04", raw"atunl(R)"),
    # a05: test_qcall's `vat` (`M:qm(C)@qm2`): a variable colon module is a TM_VAR meta-call, wrapped `@(M:qm(C), qm2)`
    ("a05", raw"vat(R)"),
    # a06-a08: test_qcall's `atv` (`qm:qm(C)@QC`, QC a variable bound at run time): I_DEPARTATMV (a06), I_CALLATMV (a07), and with no colon (a08)
    ("a06", raw"atv(R)"),
    ("a07", raw"atvn(R)"),
    ("a08", raw"atvu(R)"),
    # a09: I_DEPARTATMV with a choice point left (BFR > FR): I_CALLATMV's path, both answers
    ("a09", raw"findall(C, atvcp(C), R)"),
    # a10-a12: test_qcall's `atvv`, `atvvv` (`M:G@QC`, a variable goal), and the second `atvvv` (`M:(G,true)@QC`)
    ("a10", raw"atvv(R)"),
    ("a11", raw"atvvv(R)"),
    ("a12", raw"atvvc(R)"),
    # a13: a variable goal with an atom module (a meta-call of `@(G, qm2)`)
    ("a13", raw"atg(R)"),
    # a14: the at context is restored after the goal (CB_ATSIGN): the goal after it runs in the clause's module
    ("a14", raw"atrestore(C1, C2), R = C1-C2"),
    # a15: a nested at: the inner context wins (swipl's clause/2 of it shows only the inner `@`)
    ("a15", raw"atnest(R)"),
    # a16-a19: control constructs, `=/2` and `!` under an at context: the context applies to the calls only
    ("a16", raw"findall(X, atctl(X), R)"),
    ("a17", raw"atctx(R)"),
    ("a18", raw"atunify(R)"),
    ("a19", raw"atcut, R = yes"),
    # a20: call/N under an at context is compiled as a call of call/2 (the call/N gate), not inline
    ("a20", raw"atcalln(R)"),
    # a21-a27: the run-time errors of I_CALLATMV / I_DEPARTATMV: an unbound module (instantiation_error), a number, a compound
    # (type_error(module, _)), and a module created by name (foo); last goal (a21-a24) and not (a25-a27)
    ("a21", raw"rt(_, R)"),
    ("a22", raw"rt(1, R)"),
    ("a23", raw"rt(foo, R)"),
    ("a24", raw"rt(f(x), R)"),
    ("a25", raw"rtn(_, R)"),
    ("a26", raw"rtn(1, R)"),
    ("a27", raw"rtn(foo, R)"),
    # a28-a29: call/1 of `Goal@Module` (a goal clause, i_metacall_common's checkCallAtContextInstantiation passes)
    ("a28", raw"call(@(utp(R), qm2))"),
    ("a29", raw"call(@(qm:qm(R), qm2))"),
    # a30-a35: checkCallAtContextInstantiation's errors: an unbound module, an unbound goal, an unbound module of the goal's
    # qualification, an unbound goal under a module, a number module, a compound module of the goal
    ("a30", raw"call(@(utp(_), _)), R = ok"),
    ("a31", raw"call(@(_, qm2)), R = ok"),
    ("a32", raw"call(@(_:utp(_), qm2)), R = ok"),
    ("a33", raw"call(@(qm:_, qm2)), R = ok"),
    ("a34", raw"call(@(utp(_), 1)), R = ok"),
    ("a35", raw"call(@(f(x):utp(_), qm2)), R = ok"),
    # a36-a38: call/1 of `p(X)@user`, nondeterministic (1, 2, 3) with a module in a variable (a37), and a stacked qualification (a38)
    ("a36", raw"findall(X, call(@(p(X), user)), R)"),
    ("a37", raw"findall(X, (m2(Q), @(p(X), Q)), R)"),
    ("a38", raw"call(@(user:qm:utp(R), qm2))"),
    # a39: a cyclic goal: swipl FAILS (p/1 has only 1, 2, 3); the kernel may raise representation_error(cyclic_term) from the goal
    # clause's compile instead — UNVERIFIED on the kernel: gate decides (a mismatch is traced, not re-pinned)
    ("a39", raw"( G = p(G), call(@(G, user)) -> R = yes ; R = no )"),
    # a40-a54: clause/2 (the decompiler): `qm:qm(_)@qm2`, `utp(_)@qm2`, with a variable module (ATMV), the TM_VAR meta-calls,
    # the at that vanishes over a control construct, `=/2` and `!`
    ("a40", raw"findall(B, clause(at(_), B), R)"),
    ("a41", raw"findall(B, clause(atnl(_), B), R)"),
    ("a42", raw"findall(B, clause(atu(_), B), R)"),
    ("a43", raw"findall(B, clause(atunl(_), B), R)"),
    ("a44", raw"findall(B, clause(atv(_), B), R)"),
    ("a45", raw"findall(B, clause(atvn(_), B), R)"),
    ("a46", raw"findall(B, clause(atvcp(_), B), R)"),
    ("a47", raw"findall(B, clause(vat(_), B), R)"),
    ("a48", raw"findall(B, clause(atvvc(_), B), R)"),
    ("a49", raw"findall(B, clause(atnest(_), B), R)"),
    ("a50", raw"findall(B, clause(atctl(_), B), R)"),
    ("a51", raw"findall(B, clause(atcalln(_), B), R)"),
    ("a52", raw"findall(B, clause(rt(_, _), B), R)"),
    ("a53", raw"findall(B, clause(rtn(_, _), B), R)"),
    ("a54", raw"findall(B, clause(atrestore(_, _), B), R)"),
    # a55-a59: getTargetModule's errors at assert time with the at context — a void module, a number, a compound, a variable met
    # first (instantiation_error), and a variable met before (accepted: a meta-call)
    ("a55", raw"assertz((e1 :- @(foo, _))), R = ok"),
    ("a56", raw"assertz((e2 :- @(foo, 1))), R = ok"),
    ("a57", raw"assertz((e3 :- @(foo, f(x)))), R = ok"),
    ("a58", raw"assertz((e4 :- @(foo, M), bar(M))), R = ok"),
    ("a59", raw"assertz((e5(M, R0) :- @(utp(R0), M))), findall(B, clause(e5(_, _), B), R)"),
    # a60-a61: asserted clauses with an at: the module set before (ATMV) and an atom module (ATM) not last; run-time of a59's clause
    ("a60", raw"assertz((e6(M) :- bar(M), @(foo, M))), findall(B, clause(e6(_), B), R)"),
    ("a61", raw"assertz((e7 :- @(foo, qm2), true)), findall(B, clause(e7, B), R)"),
    ("a62", raw"e5(qm2, R)"),
    ("a63", raw"e5(_, R)"),
    # a64-a69: goal clauses (call/1 of a conjunction, islocal): test_qcall's shapes under `call/1` — the at module in a variable
    # (always TM_VAR), an atom module, an unbound and a number module met at run time, the context restored after the at
    ("a64", raw"call((m2(QC), @(qm:qm(C), QC))), R = QC-C"),
    ("a65", raw"call((true, @(utp(_), _X))), R = ok"),
    ("a66", raw"call((true, @(utp(_), 1))), R = ok"),
    ("a67", raw"call((true, @(utp(C), qm2))), R = C"),
    ("a68", raw"call((@(utp(C1), qm2), utp(C2))), R = C1-C2"),
    ("a69", raw"call((m(M), m2(Q), @(M:qm(C), Q))), R = C"),
    # a70-a73 (the shape of test_colon_body_swipl.jl's b45/b46): the frame reuse of I_DEPARTATM / I_DEPARTATMV, white-box.
    # `statistics(localused, U)` is `8 * ld.lTop` (src/pl-prims.jl `_used_stack`), read at the deepest call. The last goal
    # `@(lcm(N1, U, M), M)` is I_DEPARTATMV (a70) and `@(lca(N1, U), qm2)` I_DEPARTATM (a71); with no choice point above the
    # frame they depart (LCO): lTop at depth 1000 and at depth 2000 is the SAME. `lcpm`/`lcpa` (a72, a73) leave between/3's
    # choice point above the frame, so the call takes I_CALLATMV's / I_CALLATM's path: lTop GROWS with the depth.
    # Each call is `( G -> true )`, not once/1 (the kernel has no once/1); same answers in swipl.
    (
        "a70",
        raw"( lcm(1000, U1, qm2) -> true ), ( lcm(2000, U2, qm2) -> true ), ( U1 == U2 -> R = same ; R = differ(U1, U2) )"
    ),
    (
        "a71",
        raw"( lca(1000, U1) -> true ), ( lca(2000, U2) -> true ), ( U1 == U2 -> R = same ; R = differ(U1, U2) )"
    ),
    (
        "a72",
        raw"( lcpm(1000, U1, qm2) -> true ), ( lcpm(2000, U2, qm2) -> true ), ( U2 > U1 -> R = grows ; R = flat(U1, U2) )"
    ),
    (
        "a73",
        raw"( lcpa(1000, U1) -> true ), ( lcpa(2000, U2) -> true ), ( U2 > U1 -> R = grows ; R = flat(U1, U2) )"
    ),
    # a74, a75: a choice point above the frame forbids the departure: the frame's own context is NOT set by the at call (it is
    # retried: its transparent `utp(C0)` still answers user the second time), with a variable module (a74) and an atom (a75)
    ("a74", raw"findall(C0-C, atcpx(C0, C), R)"),
    ("a75", raw"findall(C0-C, atcpa(C0, C), R)"),
    # a76: a nested at restores the OUTER context after the inner goal (CB_ATSIGN's saved context): C2 is qm, not user
    ("a76", raw"atnest2(C1, C2), R = C1-C2"),
    # a77: the clause/2 of it: the outer at is gone, each goal carries its own
    ("a77", raw"findall(B, clause(atnest2(_, _), B), R)")
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; lk-channel evidence/MOD3b/mod3b_rows.out)
const _AB_PINNED = [
    "ok",
    "t_a01 c[116,95,97,48,49]/1(a[113,109,50])",
    "t_a02 c[116,95,97,48,50]/1(a[113,109,50])",
    "t_a03 c[116,95,97,48,51]/1(a[113,109,50])",
    "t_a04 c[116,95,97,48,52]/1(a[113,109,50])",
    "t_a05 c[116,95,97,48,53]/1(a[113,109,50])",
    "t_a06 c[116,95,97,48,54]/1(a[113,109,50])",
    "t_a07 c[116,95,97,48,55]/1(a[113,109,50])",
    "t_a08 c[116,95,97,48,56]/1(a[113,109,50])",
    "t_a09 c[116,95,97,48,57]/1(c[91,124,93]/2(a[113,109,50],c[91,124,93]/2(a[113,109,50],nil)))",
    "t_a10 c[116,95,97,49,48]/1(a[113,109,50])",
    "t_a11 c[116,95,97,49,49]/1(a[113,109,50])",
    "t_a12 c[116,95,97,49,50]/1(a[113,109,50])",
    "t_a13 c[116,95,97,49,51]/1(a[113,109,50])",
    "t_a14 c[116,95,97,49,52]/1(c[45]/2(a[113,109,50],a[117,115,101,114]))",
    "t_a15 c[116,95,97,49,53]/1(a[113,109,50])",
    "t_a16 c[116,95,97,49,54]/1(c[91,124,93]/2(i1,nil))",
    "t_a17 c[116,95,97,49,55]/1(a[113,109,50])",
    "t_a18 c[116,95,97,49,56]/1(a[97])",
    "t_a19 c[116,95,97,49,57]/1(a[121,101,115])",
    "t_a20 c[116,95,97,50,48]/1(a[113,109,50])",
    "t_a21 c[116,95,97,50,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a22 c[116,95,97,50,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],i1)))",
    "t_a23 c[116,95,97,50,51]/1(a[102,111,111])",
    "t_a24 c[116,95,97,50,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],c[102]/1(a[120]))))",
    "t_a25 c[116,95,97,50,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a26 c[116,95,97,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],i1)))",
    "t_a27 c[116,95,97,50,55]/1(a[102,111,111])",
    "t_a28 c[116,95,97,50,56]/1(a[113,109,50])",
    "t_a29 c[116,95,97,50,57]/1(a[113,109,50])",
    "t_a30 c[116,95,97,51,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a31 c[116,95,97,51,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a32 c[116,95,97,51,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a33 c[116,95,97,51,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a34 c[116,95,97,51,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],i1)))",
    "t_a35 c[116,95,97,51,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],c[102]/1(a[120]))))",
    "t_a36 c[116,95,97,51,54]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))))",
    "t_a37 c[116,95,97,51,55]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))))",
    "t_a38 c[116,95,97,51,56]/1(a[113,109,50])",
    "t_a39 c[116,95,97,51,57]/1(a[110,111])",
    "t_a40 c[116,95,97,52,48]/1(c[91,124,93]/2(c[64]/2(c[58]/2(a[113,109],c[113,109]/1(V0)),a[113,109,50]),nil))",
    "t_a41 c[116,95,97,52,49]/1(c[91,124,93]/2(c[44]/2(c[64]/2(c[58]/2(a[113,109],c[113,109]/1(V0)),a[113,109,50]),a[116,114,117,101]),nil))",
    "t_a42 c[116,95,97,52,50]/1(c[91,124,93]/2(c[64]/2(c[117,116,112]/1(V0),a[113,109,50]),nil))",
    "t_a43 c[116,95,97,52,51]/1(c[91,124,93]/2(c[44]/2(c[64]/2(c[117,116,112]/1(V0),a[113,109,50]),a[116,114,117,101]),nil))",
    "t_a44 c[116,95,97,52,52]/1(c[91,124,93]/2(c[44]/2(c[109,50]/1(V0),c[64]/2(c[58]/2(a[113,109],c[113,109]/1(V1)),V0)),nil))",
    "t_a45 c[116,95,97,52,53]/1(c[91,124,93]/2(c[44]/2(c[109,50]/1(V0),c[44]/2(c[64]/2(c[58]/2(a[113,109],c[113,109]/1(V1)),V0),a[116,114,117,101])),nil))",
    "t_a46 c[116,95,97,52,54]/1(c[91,124,93]/2(c[44]/2(c[109,50]/1(V0),c[44]/2(c[98,101,116,119,101,101,110]/3(i1,i2,V1),c[64]/2(c[58]/2(a[113,109],c[113,109]/1(V2)),V0))),nil))",
    "t_a47 c[116,95,97,52,55]/1(c[91,124,93]/2(c[44]/2(c[109]/1(V0),c[99,97,108,108]/1(c[64]/2(c[58]/2(V0,c[113,109]/1(V1)),a[113,109,50]))),nil))",
    "t_a48 c[116,95,97,52,56]/1(c[91,124,93]/2(c[44]/2(c[109]/1(V0),c[44]/2(c[109,50]/1(V1),c[44]/2(c[103]/2(V2,V3),c[44]/2(c[99,97,108,108]/1(c[64]/2(c[58]/2(V0,V3),V1)),a[116,114,117,101])))),nil))",
    "t_a49 c[116,95,97,52,57]/1(c[91,124,93]/2(c[64]/2(c[117,116,112]/1(V0),a[113,109,50]),nil))",
    "t_a50 c[116,95,97,53,48]/1(c[91,124,93]/2(c[59]/2(c[45,62]/2(a[116,114,117,101],c[61]/2(V0,i1)),c[61]/2(V0,i2)),nil))",
    "t_a51 c[116,95,97,53,49]/1(c[91,124,93]/2(c[64]/2(c[99,97,108,108]/2(a[117,116,112],V0),a[113,109,50]),nil))",
    "t_a52 c[116,95,97,53,50]/1(c[91,124,93]/2(c[64]/2(c[117,116,112]/1(V0),V1),nil))",
    "t_a53 c[116,95,97,53,51]/1(c[91,124,93]/2(c[44]/2(c[64]/2(c[117,116,112]/1(V0),V1),a[116,114,117,101]),nil))",
    "t_a54 c[116,95,97,53,52]/1(c[91,124,93]/2(c[44]/2(c[64]/2(c[117,116,112]/1(V0),a[113,109,50]),c[117,116,112]/1(V1)),nil))",
    "t_a55 c[116,95,97,53,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a56 c[116,95,97,53,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],i1)))",
    "t_a57 c[116,95,97,53,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],c[102]/1(a[120]))))",
    "t_a58 c[116,95,97,53,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a59 c[116,95,97,53,57]/1(c[91,124,93]/2(c[64]/2(c[117,116,112]/1(V0),V1),nil))",
    "t_a60 c[116,95,97,54,48]/1(c[91,124,93]/2(c[44]/2(c[98,97,114]/1(V0),c[64]/2(a[102,111,111],V0)),nil))",
    "t_a61 c[116,95,97,54,49]/1(c[91,124,93]/2(c[44]/2(c[64]/2(a[102,111,111],a[113,109,50]),a[116,114,117,101]),nil))",
    "t_a62 c[116,95,97,54,50]/1(a[113,109,50])",
    "t_a63 c[116,95,97,54,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a64 c[116,95,97,54,52]/1(c[45]/2(a[113,109,50],a[113,109,50]))",
    "t_a65 c[116,95,97,54,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_a66 c[116,95,97,54,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],i1)))",
    "t_a67 c[116,95,97,54,55]/1(a[113,109,50])",
    "t_a68 c[116,95,97,54,56]/1(c[45]/2(a[113,109,50],a[117,115,101,114]))",
    "t_a69 c[116,95,97,54,57]/1(a[113,109,50])",
    "t_a70 c[116,95,97,55,48]/1(a[115,97,109,101])",
    "t_a71 c[116,95,97,55,49]/1(a[115,97,109,101])",
    "t_a72 c[116,95,97,55,50]/1(a[103,114,111,119,115])",
    "t_a73 c[116,95,97,55,51]/1(a[103,114,111,119,115])",
    "t_a74 c[116,95,97,55,52]/1(c[91,124,93]/2(c[45]/2(a[117,115,101,114],a[113,109,50]),c[91,124,93]/2(c[45]/2(a[117,115,101,114],a[113,109,50]),nil)))",
    "t_a75 c[116,95,97,55,53]/1(c[91,124,93]/2(c[45]/2(a[117,115,101,114],a[113,109,50]),c[91,124,93]/2(c[45]/2(a[117,115,101,114],a[113,109,50]),nil)))",
    "t_a76 c[116,95,97,55,54]/1(c[45]/2(a[113,109,50],a[113,109]))",
    "t_a77 c[116,95,97,55,55]/1(c[91,124,93]/2(c[44]/2(c[64]/2(c[117,116,112]/1(V0),a[113,109,50]),c[64]/2(c[117,116,112]/1(V1),a[113,109])),nil))"
]

"The program and cases as one file; the case predicates' names."
function _ab_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _AB_CASES]
    text =
        _AB_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _AB_CASES
        ])
    f = joinpath(mktempdir(), "mod3b.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _ab_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_AB}()
    ld = LK.PL_local_data{_AB}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _ab_enc(ball::_AB)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_abs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
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
                push!(
                    sols,
                    _ab_enc(mk_expr(_AB, _AB[_abs(name), lk_answers(ld, (a:a)...)...]))
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
        push!(out, "$name" * join(" " .* sols))
    end
    return out, gd, ld
end

@testset "Goal@Module in a body and call/1 of it as swipl's (a01-a77)" begin
    f, names = _ab_file()
    kl, _, _ = _ab_kernel(f, names)
    @test length(kl) == length(_AB_PINNED)
    for (k, p) in zip(kl, _AB_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the at rows answer qm2 (the context), the error rows raised, clause/2 rows hold an `@`, the nondeterministic rows
    # three answers; the pins hold both kinds of answer, so the comparison can pass and can fail
    qm2 = "a[113,109,50]"                               # qm2
    @test count(l -> endswith(l, "/1($qm2)"), _AB_PINNED) >= 20
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _AB_PINNED) >= 16      # raised(…)
    @test count(l -> occursin("c[64]/2(", l), _AB_PINNED) >= 15                        # @/2
    @test count(l -> occursin("c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil)))", l), _AB_PINNED) == 2    # [1,2,3]
    @test any(l -> startswith(l, "t_a39 ") && endswith(l, "(a[110,111])"), _AB_PINNED)    # the cyclic goal fails in swipl
    # a70-a73: the LCO rows answer `same`, the choice-point rows `grows`
    @test _AB_PINNED[end - 7] == "t_a70 c[116,95,97,55,48]/1(a[115,97,109,101])"
    @test _AB_PINNED[end - 6] == "t_a71 c[116,95,97,55,49]/1(a[115,97,109,101])"
    @test _AB_PINNED[end - 5] == "t_a72 c[116,95,97,55,50]/1(a[103,114,111,119,115])"
    @test _AB_PINNED[end - 4] == "t_a73 c[116,95,97,55,51]/1(a[103,114,111,119,115])"
    # a74, a75: both retried answers have the clause's own context (user) for C0
    @test count(l -> occursin("c[45]/2(a[117,115,101,114],a[113,109,50])", l), _AB_PINNED) == 2
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_AB_PINNED) == length(_AB_CASES) + 1
    if swipl === nothing
        @info "MOD3b LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _ab_file()
        @test _ab_swipl_lines(f, names) == _AB_PINNED
    end
end
