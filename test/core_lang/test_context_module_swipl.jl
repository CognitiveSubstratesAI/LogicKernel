# ORIGINAL: MOD2's gate (lk-channel evidence/r2/design/modules.md §7, M4) — the context module, against swipl 10.1.19; tests/core_lang/test_qcall.pl needs `M:G` in a body (MOD3a) and plunit, so the rows are the design's, driven through call/1.
# test/core_lang/test_context_module_swipl.jl — the context module of a frame (pl-wam.c `contextModule`, `setContextModule`), the
# four transparent branches (pl-vmi.c `I_DEPART`, `I_LCALL`, `mcall_cont`; pl-wam.c `PL_open_query`), the goal clause's context
# (pl-comp.c compileClause), the cleanup handler's module (pl-wam.c `callCleanupHandler`), the strip functions (pl-modul.c
# `stripModule`, pl-fli.c `PL_strip_module`/`PL_strip_module_ex`, pl-proc.c `get_module`), strip_module/3 and context_module/1:
#   * A PROGRAM (the directives assert the predicates of module `m2` and make some transparent with
#     `'$set_predicate_attribute'/3`: module_transparent/1 is boot Prolog) consulted by the kernel's loader, and cases
#     `t_<id>(R)` run IN ORDER in one database (c16 reads what c15 asserted, c17 removes it), each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`. `M:G` in a clause body is MOD3a's, so a goal runs in `m2` through
#     call/1 (`I_CALL1`: i_metacall_common strips the qualifier, mcall_cont sets the context).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, this program and test_ssu_swipl.jl's driver, 2026-10-29,
#     stable over two runs); with `swipl` on PATH the live answers are compared with the pins too.
#   * White-box at the query API: `PL_open_query`'s three context branches.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — frames and modules (src/pl-wam.jl, src/pl-modul.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CM = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_cms(x) = lk_sym(_CM, Symbol(x))

_cm_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _cm_enc(t::_CM, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _cm_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _cm_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _cm_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_cm_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _CM_DRIVER = raw"""
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
function _cm_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _CM_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the predicates under test: m2's through directives (assertz/1, '$set_predicate_attribute'/3), user's as clauses
const _CM_PROGRAM = raw"""
:- assertz(m2:(tp(X) :- context_module(X))).
:- '$set_predicate_attribute'(m2:tp(_), transparent, true).
:- assertz(m2:(ntp(X) :- context_module(X))).
:- assertz(m2:(lc(X) :- tp(X))).
:- assertz(m2:(tpf(f(X)) :- context_module(X))).
:- '$set_predicate_attribute'(m2:tpf(_), transparent, true).
:- assertz(m2:(nd(X) :- tpf(f(X)))).
:- assertz(m2:(tpt :- context_module(C), throw(ctx(C)))).
:- '$set_predicate_attribute'(m2:tpt, transparent, true).
:- assertz(m2:(sc(M) :- catch(setup_call_cleanup(true, true, tpt), ctx(M), true))).
:- assertz(m2:(ap :- assertz(fact(1)))).
:- assertz(m2:(rc :- retractall(fact(_)))).
:- assertz(m2:(fa(L) :- findall(M, tp(M), L))).
:- assertz(m2:(fa1(L) :- findall(M, tp(M), L, []))).
:- assertz(m2:(bg(L) :- bagof(M, tp(M), L))).
:- assertz(m2:(ct(M) :- catch(tp(M), _, true))).
:- assertz(m2:(ct2(M) :- catch(throw(x), _, tp(M)))).
:- assertz(m2:(cn(M) :- call(tp, M))).
:- assertz(m2:(fz(X, M) :- freeze(X, tp(M)))).
:- assertz(m2:(cr(M) :- call_residue_vars(tp(M), _))).
:- assertz(m2:(wh(M) :- when(nonvar(a), tp(M)))).
:- assertz(m2:(scg(M) :- setup_call_cleanup(true, tp(M), true))).
:- assertz(m2:(cu(M) :- utp(M))).
:- assertz(m2:(sus(X) :- '$suspend'(X, when, tp(_)))).
:- assertz(m2:(cl(B) :- clause(tp(_), B))).
utp(M) :- context_module(M).
:- assertz(m2:(tpa :- context_module(C), assertz(seen(C)))).
:- '$set_predicate_attribute'(m2:tpa, transparent, true).
:- assertz(m2:(scx :- setup_call_cleanup(true, findall(_, atom_length(_, _), _), tpa))).
:- assertz(m2:(pw :- write_term(user_error, x, [portray(true)]))).
portray(x) :- context_module(M), assertz(pseen(M)), fail.
:- assertz(m2:(scu(M) :- setup_call_cleanup(true, C = context_module(M), C))).
:- assertz(m3:(tpa3 :- context_module(C), assertz(seen3(C)))).
:- '$set_predicate_attribute'(m3:tpa3, transparent, true).
:- assertz(m2:(sq :- setup_call_cleanup(true, findall(_, atom_length(_, _), _), m3:tpa3))).
:- '$set_predicate_attribute'(portray(_), transparent, true).
:- '$set_predicate_attribute'(utp(_), transparent, true).
ut(M) :- unt(M).
:- '$set_predicate_attribute'(ut(_), transparent, true).
unt(M) :- context_module(M).
:- assertz(m2:(tpb :- context_module(C), assertz(seenb(C)))).
:- '$set_predicate_attribute'(m2:tpb, transparent, true).
:- assertz(m2:gen(1)), assertz(m2:gen(2)), assertz(m2:gen3(1)), assertz(m2:gen3(2)), assertz(m2:gen3(3)).
:- assertz(m2:(fsc(L) :- findall(X, setup_call_cleanup(true, gen(X), tpb), L))).
:- assertz(m2:(fasc :- \+ (setup_call_cleanup(true, gen(_), tpb), \+ true))).
:- assertz(m2:(nsc :- \+ \+ setup_call_cleanup(true, gen(_), tpb))).
:- assertz(m2:(fsc3(L) :- findall(X, setup_call_cleanup(true, (gen3(X), X < 3), tpb), L))).
"""

# (id, goal), run IN ORDER
const _CM_CASES = [
    # c01: a user clause's context: its predicate's module (contextModule's non-transparent branch)
    ("c01", raw"context_module(R)"),
    # c02: context_module/1 called in m2 through call/1: mcall_cont sets the transparent frame's context
    ("c02", raw"call(m2:context_module(R))"),
    # c03: a transparent predicate of m2 metacalled: mcall_cont (pl-vmi.c:5725)
    ("c03", raw"call(m2:tp(R))"),
    # c04: a non-transparent predicate of m2: its own module
    ("c04", raw"call(m2:ntp(R))"),
    # c05: I_LCALL into a transparent predicate: ctx0 read BEFORE setFramePredicate (design H4)
    ("c05", raw"call(m2:lc(R))"),
    # c06: I_DEPART's last-call reuse into a transparent predicate: the context read BEFORE setFramePredicate (H4)
    ("c06", raw"call(m2:nd(R))"),
    # c07: a control construct under call/1 in m2: the goal clause's frame gets the module (pl-comp.c:2266)
    ("c07", raw"call(m2:(tp(R), true))"),
    # c08: the cleanup handler's goal runs in contextModule(fr) (pl-wam.c:928; the goal qualified by S_MQUAL since MOD4) and PL_open_query's ctx
    ("c08", raw"call(m2:sc(R))"),
    # c09: strip_module/3: the innermost atom qualifier
    ("c09", raw"strip_module(a:b:c, M, P), R = M-P"),
    # c10: strip_module/3 of an unqualified term: the context module, user
    ("c10", raw"strip_module(foo, M, P), R = M-P"),
    # c11: strip_module/3 called in m2: m2 (transparent)
    ("c11", raw"call(m2:strip_module(foo, M, P)), R = M-P"),
    # c12: strip_module/3: a variable qualifier stays
    ("c12", raw"strip_module(_:foo, M, P), R = M-P"),
    # c13: strip_module/3: a non-atom qualifier stays
    ("c13", raw"strip_module(1:foo, M, P), R = M-P"),
    # c14: strip_module/3 of a variable
    ("c14", raw"strip_module(_, M, P), R = M-P"),
    # c15: assertz/1 from a clause of m2 asserts into m2 (H6: a transparent built-in sees the caller's module)
    ("c15", raw"call(m2:ap), call(m2:fact(R))"),
    # c16: ... and not into user
    ("c16", raw"fact(R)"),
    # c17: retractall/1 from a clause of m2 (transparent since MOD2: pl-ext.c:397)
    ("c17", raw"call(m2:rc), findall(X, m2:fact(X), R)"),
    # c18: findall/3 from m2: the stand-ins' transparency and findall/4's qualified goal
    ("c18", raw"call(m2:fa(R))"),
    # c19: bagof/3 from m2
    ("c19", raw"call(m2:bg(R))"),
    # c20: catch/3's goal from m2
    ("c20", raw"call(m2:ct(R))"),
    # c21: catch/3's recovery from m2
    ("c21", raw"call(m2:ct2(R))"),
    # c22: call/2 (I_CALLN) from a clause of m2: i_metacall_common strips to the environment frame's context
    ("c22", raw"call(m2:cn(R))"),
    # c23: freeze/2 from m2: the goal qualified with the context module, run at the wakeup
    ("c23", raw"call(m2:fz(X, R)), X = 1"),
    # c24: ... the frozen goal as stored
    ("c24", raw"call(m2:fz(X, _)), get_attr(X, freeze, R)"),
    # c25: call_residue_vars/2 from m2
    ("c25", raw"call(m2:cr(R))"),
    # c26: when/2 from m2
    ("c26", raw"call(m2:wh(R))"),
    # c27: setup_call_cleanup/3's goal from m2
    ("c27", raw"call(m2:scg(R))"),
    # c28: I_LCALL into an undefined procedure of m2 resolved to user's transparent definition: the context m2
    ("c28", raw"call(m2:cu(R))"),
    # c29: a transparent predicate's last call into a non-transparent one clears FR_CONTEXT (design H5): user
    ("c29", raw"call(m2:ut(R))"),
    # c30: findall/4 by I_DEPART from m2
    ("c30", raw"call(m2:fa1(R))"),
    # c31: the transparent predicate from user: user
    ("c31", raw"ut(R)"),
    # c32: a transparent predicate from user: user
    ("c32", raw"utp(R)"),
    # c33: '$suspend'/3 from m2 qualifies its goal with the context module (pl-attvar.c:1139)
    ("c33", raw"call(m2:sus(X)), get_attr(X, when, R)"),
    # c34: clause/2 from m2: get_procedure's GP_FIND module is the context module (pl-proc.c:727)
    ("c34", raw"call(m2:cl(R))"),
    # c35: a cleanup run while an exception unwinds (atom_length/2's error inside findall_loop/4: the handler's environment
    # a system frame) runs in the cleanup frame's context (the goal qualified by S_MQUAL, MOD4); the error stays
    (
        "c35",
        raw"catch(call(m2:scx), error(E, _), true), findall(C, m2:seen(C), L), R = E-L"
    ),
    # c36: PL_open_query's saved-environment branch — callPortray (pl-write.c) calls a transparent user:portray/1 with ctx
    # NULL while write_term/3 runs from m2: the portray frame takes write_term's context (pl-wam.c:3096)
    ("c36", raw"call(m2:pw), findall(M, m2:pseen(M), R)"),
    # c37 (D-0212): a cleanup unbound at the call, bound during Goal — swipl refuses it at the call (setup_call_cleanup/3's
    # instantiation error, before Goal runs), so the binding is never reached; since MOD4 S_MQUAL makes it `m2:_` and
    # mustBeCallable's second `isVar` raises it (pl-wam.c:941)
    ("c37", raw"call(m2:scu(R))"),
    # c38 (D-0212): a cleanup already qualified with a third module, run while an exception unwinds — m_qualify_argument leaves
    # it alone (`_:_`, pl-wam.c:1785-1847): it runs and asserts in m3
    (
        "c38",
        raw"catch(call(m2:sq), error(E, _), true), findall(C, m3:seen3(C), L), R = E-L"
    ),
    # c39-c42 (D-0233, mutant MOD2-H2): an unqualified m2-local cleanup `tpb` run from m2 when the goal ends or its
    # choice points are cut: under findall/3 (system code), under forall/2's body `\+ (G, \+ true)` (forall/2 and
    # member/2 are library predicates the kernel does not have: m2-local gen/1, gen3/1 instead), under `\+ \+`, and
    # under findall/3 over a goal left nondeterministic (X < 3 fails on the third answer). swipl: tpb runs in m2 (S_MQUAL
    # qualified it at the call). White-box probe (D-0233 item 2, evidence/MOD2/h2_probe.txt): at the handler's entry the
    # environment frame's context equals contextModule(fr) in every cleanup of c01-c42, so these rows pin the module but
    # cannot kill MOD2-H2; test_cleanup_swipl.jl:295 does (the query's goal is the cleanup frame: D-0237, wrap kept)
    (
        "c39",
        raw"retractall(m2:seenb(_)), call(m2:fsc(L)), findall(C, m2:seenb(C), S), R = L-S"
    ),
    ("c40", raw"retractall(m2:seenb(_)), call(m2:fasc), findall(C, m2:seenb(C), R)"),
    ("c41", raw"retractall(m2:seenb(_)), call(m2:nsc), findall(C, m2:seenb(C), R)"),
    (
        "c42",
        raw"retractall(m2:seenb(_)), call(m2:fsc3(L)), findall(C, m2:seenb(C), S), R = L-S"
    )
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines)
const _CM_PINNED = [
    "ok",
    "t_c01 c[116,95,99,48,49]/1(a[117,115,101,114])",
    "t_c02 c[116,95,99,48,50]/1(a[109,50])",
    "t_c03 c[116,95,99,48,51]/1(a[109,50])",
    "t_c04 c[116,95,99,48,52]/1(a[109,50])",
    "t_c05 c[116,95,99,48,53]/1(a[109,50])",
    "t_c06 c[116,95,99,48,54]/1(a[109,50])",
    "t_c07 c[116,95,99,48,55]/1(a[109,50])",
    "t_c08 c[116,95,99,48,56]/1(a[109,50])",
    "t_c09 c[116,95,99,48,57]/1(c[45]/2(a[98],a[99]))",
    "t_c10 c[116,95,99,49,48]/1(c[45]/2(a[117,115,101,114],a[102,111,111]))",
    "t_c11 c[116,95,99,49,49]/1(c[45]/2(a[109,50],a[102,111,111]))",
    "t_c12 c[116,95,99,49,50]/1(c[45]/2(a[117,115,101,114],c[58]/2(V0,a[102,111,111])))",
    "t_c13 c[116,95,99,49,51]/1(c[45]/2(a[117,115,101,114],c[58]/2(i1,a[102,111,111])))",
    "t_c14 c[116,95,99,49,52]/1(c[45]/2(a[117,115,101,114],V0))",
    "t_c15 c[116,95,99,49,53]/1(i1)",
    "t_c16 c[116,95,99,49,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[102,97,99,116],i1))))",
    "t_c17 c[116,95,99,49,55]/1(nil)",
    "t_c18 c[116,95,99,49,56]/1(c[91,124,93]/2(a[109,50],nil))",
    "t_c19 c[116,95,99,49,57]/1(c[91,124,93]/2(a[109,50],nil))",
    "t_c20 c[116,95,99,50,48]/1(a[109,50])",
    "t_c21 c[116,95,99,50,49]/1(a[109,50])",
    "t_c22 c[116,95,99,50,50]/1(a[109,50])",
    "t_c23 c[116,95,99,50,51]/1(a[109,50])",
    "t_c24 c[116,95,99,50,52]/1(c[58]/2(a[109,50],c[116,112]/1(V0)))",
    "t_c25 c[116,95,99,50,53]/1(a[109,50])",
    "t_c26 c[116,95,99,50,54]/1(a[109,50])",
    "t_c27 c[116,95,99,50,55]/1(a[109,50])",
    "t_c28 c[116,95,99,50,56]/1(a[109,50])",
    "t_c29 c[116,95,99,50,57]/1(a[117,115,101,114])",
    "t_c30 c[116,95,99,51,48]/1(c[91,124,93]/2(a[109,50],nil))",
    "t_c31 c[116,95,99,51,49]/1(a[117,115,101,114])",
    "t_c32 c[116,95,99,51,50]/1(a[117,115,101,114])",
    "t_c33 c[116,95,99,51,51]/1(c[99,97,108,108]/1(c[58]/2(a[109,50],c[116,112]/1(V0))))",
    "t_c34 c[116,95,99,51,52]/1(c[99,111,110,116,101,120,116,95,109,111,100,117,108,101]/1(V0))",
    "t_c35 c[116,95,99,51,53]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[91,124,93]/2(a[109,50],nil)))",
    "t_c36 c[116,95,99,51,54]/1(c[91,124,93]/2(a[109,50],nil))",
    "t_c37 c[116,95,99,51,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_c38 c[116,95,99,51,56]/1(c[45]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],c[91,124,93]/2(a[109,51],nil)))",
    "t_c39 c[116,95,99,51,57]/1(c[45]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(a[109,50],nil)))",
    "t_c40 c[116,95,99,52,48]/1(c[91,124,93]/2(a[109,50],nil))",
    "t_c41 c[116,95,99,52,49]/1(c[91,124,93]/2(a[109,50],nil))",
    "t_c42 c[116,95,99,52,50]/1(c[45]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(a[109,50],nil)))"
]

"The program and cases as one file; the case predicates' names."
function _cm_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _CM_CASES]
    text =
        _CM_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _CM_CASES
        ])
    f = joinpath(mktempdir(), "mod2.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _cm_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_CM}()
    ld = LK.PL_local_data{_CM}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _cm_enc(ball::_CM)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_cms(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_CM, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _cm_enc(mk_expr(_CM, _CM[_cms(name), lk_answers(ld, (a:a)...)...]))
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

@testset "the context module as swipl's (c01-c42)" begin
    f, names = _cm_file()
    kl, _, _ = _cm_kernel(f, names)
    @test length(kl) == length(_CM_PINNED)
    for (k, p) in zip(kl, _CM_PINNED)
        @test k == p
    end
    # not vacuous: both modules answer, and the error row raised
    m2 = "a[109,50]"                                    # m2
    user = "a[117,115,101,114]"                         # user
    @test count(l -> endswith(l, "/1($m2)"), _CM_PINNED) >= 15
    @test count(l -> endswith(l, "/1($user)"), _CM_PINNED) >= 4
    @test any(
        l -> startswith(l, "t_c16 ") && occursin("c[114,97,105,115,101,100]", l), _CM_PINNED
    )
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_CM_PINNED) == length(_CM_CASES) + 1
    if swipl === nothing
        @info "MOD2 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _cm_file()
        @test _cm_swipl_lines(f, names) == _CM_PINNED
    end
end

# ---- white-box: PL_open_query's context branches (pl-wam.c:3092-3099). A transparent predicate opened with a module gets
# it (`ctx`); with none and no environment frame, `user`. swipl 10.1.19: `?- m2:context_module(M).` answers `M = m2` and
# `?- context_module(M).` `M = user` (probed 2026-10-29) — the query API's `M:G` is PL_call's (pl-pro.c callProlog), so the
# rows are these toplevel answers.
@testset "PL_open_query: ctx, else user (the query API and a bare query)" begin
    gd = LK.PL_global_data{_CM}()
    ld = LK.PL_local_data{_CM}(gd)
    k = LK.fresh_var_keys!(2)
    a = LK.query_answers(
        ld,
        mk_expr(
            _CM,
            _CM[
                _cms(":"),
                _cms("m2"),
                mk_expr(_CM, _CM[_cms("context_module"), mk_var(_CM, k)])
            ]
        )
    )
    @test length(a) == 1 && compareStandard(child(child(a[1], 3), 2), _cms("m2")) == 0
    b = LK.query_answers(ld, mk_expr(_CM, _CM[_cms("context_module"), mk_var(_CM, k + 1)]))
    @test length(b) == 1 && compareStandard(child(b[1], 2), _cms("user")) == 0
    # ctx === nothing, no environment frame: the third branch (MODULE_user); the frame's context is read back
    proc = LK.isCurrentProcedure(sym_key(_cms("context_module")), 1, LK.MODULE_system(gd))
    @test proc !== nothing && (proc.definition.flags & LK.P_TRANSPARENT) != 0
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, t + 1, mk_var(_CM, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION, proc, t)
    q = ld.queries[LK.QueryFromQid(ld, qid)]
    f = ld.frames[q.frame]
    @test (f.flags & LK.FR_CONTEXT) != 0 && f.context == LK.MODULE_user(gd).index
    @test LK.PL_next_solution(gd, ld, qid) != 0
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end
