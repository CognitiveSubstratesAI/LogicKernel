# ORIGINAL: MOD4's gate — meta-argument qualification, against swipl 10.1.19; tests/core_lang/test_meta_predicate.pl (qualify×6, alias, alias2, backtrack) and tests/db/test_module.pl (mqual) need plunit and `:- meta_predicate` directives in a loaded file (setMetapredicateSource, LB2), so their rows are driven here through meta_predicate/1 called at QUERY time.
# test/core_lang/test_meta_predicate_swipl.jl — the meta-argument supervisors (pl-supervisor.c `chainPredicateSupervisor`;
# pl-vmi.c `S_MQUAL`, `S_LMQUAL`), the qualification of an argument (pl-wam.c `m_qualify_argument`), the declarations
# (pl-proc.c `meta_predicate`, `meta_declaration`, `setMetapredicateMask`, `isTransparentMetamask`, `PL_meta_predicate`) and
# the stand-ins' declarations (`_boot_meta!`: call/1..8, bagof/setof's `^`):
#   * A PROGRAM consulted by the kernel's loader: user's predicates `k*` (one per mask kind), `up/3`, upstream's `m/2`, `m/3`,
#     `m2/3` (here `mm2/3`), `mq/1`, `kt/2` (two `0` arguments), `pcc/2` (a clause running `'$call_cleanup'`); module `m2`'s callers through directives (assertz/1). Row d00 DECLARES the masks with
#     meta_predicate/1 at query time, before the first call of any of them (a built supervisor is not reset by a later
#     declaration: upstream's setMetapredicateMask does not either), then the cases `t_<id>(R)` run IN ORDER in one database,
#     each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`.
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, this program and test_context_module_swipl.jl's driver,
#     2026-10-29); with `swipl` on PATH the live answers are compared with the pins too.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — frames, supervisors and modules (src/pl-wam.jl, src/pl-supervisor.jl, src/pl-proc.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_mps(x) = lk_sym(_MP, Symbol(x))

_mp_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _mp_enc(t::_MP, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _mp_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _mp_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _mp_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_mp_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_context_module_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _MP_DRIVER = raw"""
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
function _mp_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _MP_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# user's meta-predicates (declared by row d00), upstream's test predicates, m2's callers (assertz/1 directives)
const _MP_PROGRAM = raw"""
k0(A, X) :- X = A.
k1(A, X) :- X = A.
k9(A, X) :- X = A.
kh(A, X) :- X = A.
kd(A, X) :- X = A.
kc(A, X) :- X = A.
kq(A, X) :- X = A.
kp(A, X) :- X = A.
km(A, X) :- X = A.
up(A, X, C) :- X = A, context_module(C).
m(In, Out) :- Out = In.
m(_, X, X).
mm2(X, _, X).
mq(T) :- assertz(mqseen(T)), fail.
tb(V) :- mq(V).
tb(V) :- var(V).
kt(_, _).
pcc(_G, _C) :- '$call_cleanup'.
:- assertz(m2:(q0(A, X) :- k0(A, X))).
:- assertz(m2:(q1(X) :- k1(foo, X))).
:- assertz(m2:(q9(X) :- k9(foo, X))).
:- assertz(m2:(qh(X) :- kh(V^foo(V), X))).
:- assertz(m2:(qd(X) :- kd(foo, X))).
:- assertz(m2:(qc(X) :- kc(foo, X))).
:- assertz(m2:(qq(X) :- kq(foo, X))).
:- assertz(m2:(qp(X) :- kp(foo, X))).
:- assertz(m2:(qm(X) :- km(_, X))).
:- assertz(m2:(cup(X, C) :- up(foo, X, C))).
:- assertz(m2:(tp(X) :- context_module(X))).
:- '$set_predicate_attribute'(m2:tp(_), transparent, true).
:- assertz(m2:(cn1(M) :- G = call(tp(M)), call(G))).
:- assertz(m2:(cn2(M) :- G = call(tp, M), call(G))).
:- assertz(m2:tq(1, a)).
:- assertz(m2:tq(2, b)).
:- assertz(m2:(bg2(L) :- bagof(X, Y^tq(X, Y), L))).
:- assertz(m2:(sf2(L) :- setof(X, Y^tq(X, Y), L))).
:- assertz(m2:(bg3(Y-L) :- bagof(X, tq(X, Y), L))).
"""

# (id, goal), run IN ORDER
const _MP_CASES = [
    # d00: the declarations, at query time (a `:- meta_predicate` directive in the consulted file is setMetapredicateSource's,
    # LB2): meta_predicate/1's `,` loop (pl-proc.c meta_predicate), each spec in user (the transparent built-in's context)
    (
        "d00",
        raw"meta_predicate((k0(0,?), k1(1,?), k9(9,?), kh(^,?), kd(//,?), kc(:,?), kq(?,?), kp(+,?), km(-,?), up(0,?,?), m(:,-), m(:,+,-), mm2(+,:,-), mq(:), kt(0,0))), R = ok"
    ),
    # a01-a09: one row per mask kind, called from a clause of m2: `0..9`, `^`, `//`, `:` qualify with the caller's context
    # (S_MQUAL / S_LMQUAL, MA_NEEDS_TRANSPARENT); `?`, `+`, `-` do not (P_META without P_TRANSPARENT: no S_MQUAL)
    ("a01", raw"call(m2:q0(foo, X)), R = X"),
    ("a02", raw"call(m2:q1(R))"),
    ("a03", raw"call(m2:q9(R))"),
    ("a04", raw"call(m2:qh(R))"),
    ("a05", raw"call(m2:qd(R))"),
    ("a06", raw"call(m2:qc(R))"),
    ("a07", raw"call(m2:qq(R))"),
    ("a08", raw"call(m2:qp(R))"),
    ("a09", raw"call(m2:qm(R))"),
    # a10: S_LMQUAL sets the frame's context to its predicate's module: up/3 (user) called from m2 sees user
    ("a10", raw"call(m2:cup(X, C)), R = X-C"),
    # a11: from user: the qualifier is user
    ("a11", raw"k0(foo, R)"),
    # a12-a16: an already qualified argument (m_qualify_argument's `else`): kept; `a:b:g` to the innermost atom link
    # `b:g`; a non-atom module kept (upstream's "do not check module-type"); a variable qualifier stops the walk
    ("a12", raw"call(m2:q0(m1:x, R))"),
    ("a13", raw"call(m2:q0(m2:m1:x, R))"),
    ("a14", raw"call(m2:q0(m2:42:x, R))"),
    ("a15", raw"call(m2:q0(V:m1:x, R))"),
    ("a16", raw"call(m2:q0(a:b:c:g, R))"),
    # a17: an unbound argument: `Context:V`, the caller's variable shared
    ("a17", raw"call(m2:q0(V, X)), R = X-V"),
    # a18: an attributed variable under a qualifier (upstream's `freeze(Y, fail)` row): kept
    (
        "a18",
        raw"freeze(Y, fail), call(m2:q0(m1:Y, X)), ( X == m1:Y -> R = same ; R = other )"
    ),
    # a19: a cyclic qualifier chain: the depth check (every 100 links) raises type_error(acyclic_term, _) (test_module.pl mqual)
    (
        "a19",
        raw"T = a:T, catch(call(m2:q0(T, _)), error(type_error(E, _), _), true), R = E"
    ),
    # a20, a21: upstream's alias rows: m(:, +, -) and m2(+, :, -) with one shared variable
    ("a20", raw"m(X, X, Out), R = X-Out"),
    ("a21", raw"mm2(X, X, Out), R = X-Out"),
    # a22: upstream's first qualify row
    ("a22", raw"m(x, R)"),
    # a23: upstream's backtrack row: mq(:) saw `user:V`, and V is unbound again in the next clause
    ("a23", raw"tb(V), findall(S, mqseen(S), R)"),
    # a24: S_MQUAL's own throw: a cyclic chain in the FIRST of two meta arguments, kt(0,0) (a19's is S_LMQUAL's)
    ("a24", raw"T = a:T, catch(kt(T, true), error(type_error(E, _), _), true), R = E"),
    # a25: mustBeCallable's `_:_` test (pl-wam.c:920-947): a user clause running '$call_cleanup' (I_CALLCLEANUP) has no
    # meta declaration, so its cleanup argument arrives unqualified
    ("a25", raw"catch(pcc(true, true), error(type_error(E, C), _), true), R = E-C"),
    # b01, b02: call/1 and call/2 called AS PREDICATES (I_USERCALL0 of `call(...)`): the stand-in's S_LMQUAL qualifies
    # the goal with m2 and runs the clause in system
    ("b01", raw"call(m2:cn1(R))"),
    ("b02", raw"call(m2:cn2(R))"),
    # b03-b05: bagof/setof's `^` argument arrives as `m2:(Y^G)` ('$free_variable_set''s `:` branch)
    ("b03", raw"call(m2:bg2(R))"),
    ("b04", raw"call(m2:sf2(R))"),
    ("b05", raw"findall(P, call(m2:bg3(P)), R)"),
    # e01-e12: meta_declaration's checks (pl-proc.c): `PL_cvt_i_uint`, `> 9`, the atoms, the non-atoms, mode/1's
    # domain, get_procedure's
    ("e01", raw"meta_predicate(m2:e1(10)), R = ok"),
    ("e02", raw"meta_predicate(m2:e2(foo)), R = ok"),
    ("e03", raw"meta_predicate(m2:e3(f(x))), R = ok"),
    ("e04", raw"meta_predicate(m2:e4(-1)), R = ok"),
    ("e05", raw"meta_predicate(m2:e5(_)), R = ok"),
    ("e06", raw"meta_predicate(m2:e6(1.5)), R = ok"),
    ("e07", raw"mode(m2:e7(0)), R = ok"),
    ("e08", raw"mode(m2:e8(:)), R = ok"),
    ("e09", raw"mode(m2:e9(+,-,?)), R = ok"),
    ("e10", raw"meta_predicate(_), R = ok"),
    ("e11", raw"meta_predicate(m2:e11(0,*)), R = ok"),
    ("e12", raw"meta_predicate(m2:e12(99999999999999999999)), R = ok")
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines)
const _MP_PINNED = [
    "ok",
    "t_d00 c[116,95,100,48,48]/1(a[111,107])",
    "t_a01 c[116,95,97,48,49]/1(c[58]/2(a[109,50],a[102,111,111]))",
    "t_a02 c[116,95,97,48,50]/1(c[58]/2(a[109,50],a[102,111,111]))",
    "t_a03 c[116,95,97,48,51]/1(c[58]/2(a[109,50],a[102,111,111]))",
    "t_a04 c[116,95,97,48,52]/1(c[58]/2(a[109,50],c[94]/2(V0,c[102,111,111]/1(V0))))",
    "t_a05 c[116,95,97,48,53]/1(c[58]/2(a[109,50],a[102,111,111]))",
    "t_a06 c[116,95,97,48,54]/1(c[58]/2(a[109,50],a[102,111,111]))",
    "t_a07 c[116,95,97,48,55]/1(a[102,111,111])",
    "t_a08 c[116,95,97,48,56]/1(a[102,111,111])",
    "t_a09 c[116,95,97,48,57]/1(V0)",
    "t_a10 c[116,95,97,49,48]/1(c[45]/2(c[58]/2(a[109,50],a[102,111,111]),a[117,115,101,114]))",
    "t_a11 c[116,95,97,49,49]/1(c[58]/2(a[117,115,101,114],a[102,111,111]))",
    "t_a12 c[116,95,97,49,50]/1(c[58]/2(a[109,49],a[120]))",
    "t_a13 c[116,95,97,49,51]/1(c[58]/2(a[109,49],a[120]))",
    "t_a14 c[116,95,97,49,52]/1(c[58]/2(i42,a[120]))",
    "t_a15 c[116,95,97,49,53]/1(c[58]/2(V0,c[58]/2(a[109,49],a[120])))",
    "t_a16 c[116,95,97,49,54]/1(c[58]/2(a[99],a[103]))",
    "t_a17 c[116,95,97,49,55]/1(c[45]/2(c[58]/2(a[109,50],V0),V0))",
    "t_a18 c[116,95,97,49,56]/1(a[115,97,109,101])",
    "t_a19 c[116,95,97,49,57]/1(a[97,99,121,99,108,105,99,95,116,101,114,109])",
    "t_a20 c[116,95,97,50,48]/1(c[45]/2(V0,V0))",
    "t_a21 c[116,95,97,50,49]/1(c[45]/2(V0,V0))",
    "t_a22 c[116,95,97,50,50]/1(c[58]/2(a[117,115,101,114],a[120]))",
    "t_a23 c[116,95,97,50,51]/1(c[91,124,93]/2(c[58]/2(a[117,115,101,114],V0),nil))",
    "t_a24 c[116,95,97,50,52]/1(a[97,99,121,99,108,105,99,95,116,101,114,109])",
    "t_a25 c[116,95,97,50,53]/1(c[45]/2(a[99,97,108,108,97,98,108,101],a[116,114,117,101]))",
    "t_b01 c[116,95,98,48,49]/1(a[109,50])",
    "t_b02 c[116,95,98,48,50]/1(a[109,50])",
    "t_b03 c[116,95,98,48,51]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_b04 c[116,95,98,48,52]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_b05 c[116,95,98,48,53]/1(c[91,124,93]/2(c[45]/2(a[97],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[98],c[91,124,93]/2(i2,nil)),nil)))",
    "t_e01 c[116,95,101,48,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,101,116,97,95,97,114,103,117,109,101,110,116,95,115,112,101,99,105,102,105,101,114],i10)))",
    "t_e02 c[116,95,101,48,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,101,116,97,95,97,114,103,117,109,101,110,116,95,115,112,101,99,105,102,105,101,114],a[102,111,111])))",
    "t_e03 c[116,95,101,48,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,116,97,95,97,114,103,117,109,101,110,116,95,115,112,101,99,105,102,105,101,114],c[102]/1(a[120]))))",
    "t_e04 c[116,95,101,48,52]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[117,105,110,116])))",
    "t_e05 c[116,95,101,48,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_e06 c[116,95,101,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,116,97,95,97,114,103,117,109,101,110,116,95,115,112,101,99,105,102,105,101,114],f1.5)))",
    "t_e07 c[116,95,101,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,101],i0)))",
    "t_e08 c[116,95,101,48,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[109,111,100,101],a[58])))",
    "t_e09 c[116,95,101,48,57]/1(a[111,107])",
    "t_e10 c[116,95,101,49,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_e11 c[116,95,101,49,49]/1(a[111,107])",
    "t_e12 c[116,95,101,49,50]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[117,105,110,116])))"
]

"The program and cases as one file; the case predicates' names."
function _mp_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _MP_CASES]
    text =
        _MP_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _MP_CASES
        ])
    f = joinpath(mktempdir(), "mod4.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _mp_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_MP}()
    ld = LK.PL_local_data{_MP}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _mp_enc(ball::_MP)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_mps(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_MP, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _mp_enc(mk_expr(_MP, _MP[_mps(name), lk_answers(ld, (a:a)...)...]))
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

@testset "meta-argument qualification as swipl's (d00, a01-a25, b01-b05, e01-e12)" begin
    f, names = _mp_file()
    kl, gd, _ = _mp_kernel(f, names)
    @test length(kl) == length(_MP_PINNED)
    for (k, p) in zip(kl, _MP_PINNED)
        @test k == p
    end
    # not vacuous: the qualifier m2 appears in the answers, user's too, and the error rows raised
    m2q = "c[58]/2(a[109,50],"                          # m2:_
    userq = "c[58]/2(a[117,115,101,114],"               # user:_
    @test count(l -> occursin(m2q, l), _MP_PINNED) >= 7
    @test count(l -> occursin(userq, l), _MP_PINNED) >= 3
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _MP_PINNED) >= 8   # raised(_)
    # white-box: the declarations' flags (setMetapredicateMask, isTransparentMetamask)
    u = LK.MODULE_user(gd)
    for (name, arity, transparent) in (
        ("k0", 2, true), ("kh", 2, true), ("kd", 2, true), ("kc", 2, true),
        ("kq", 2, false),
        ("kp", 2, false), ("km", 2, false), ("mm2", 3, true)
    )
        p = LK.isCurrentProcedure(sym_key(_mps(name)), arity, u)
        @test p !== nothing && (p.definition.flags & LK.P_META) != 0
        @test ((p.definition.flags & LK.P_TRANSPARENT) != 0) == transparent
    end
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_MP_PINNED) == length(_MP_CASES) + 1
    if swipl === nothing
        @info "MOD4 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _mp_file()
        @test _mp_swipl_lines(f, names) == _MP_PINNED
    end
end
