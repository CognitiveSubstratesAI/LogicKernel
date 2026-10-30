# ORIGINAL: MOD3a's gate (lk-channel evidence/r2/design/modules.md §7, M5/M6) — `M:Goal` in a clause body and `M:Head :- Body`, against swipl 10.1.19; the rows are tests/core_lang/test_qcall.pl's colon cases and tests/db/test_module.pl's cross/qcontrol, as clauses of a consulted program (plunit and module files need the loader).
# test/core_lang/test_colon_body_swipl.jl — the colon context of the body compiler (pl-comp.c `getTargetModule`, `pushTargetModule`,
# `compileBody`'s `CB_COLON`, `compileSubClause`'s meta-call and call selection, `mcall`), the clause's body module (pl-comp.c
# compileClause's `P_MFCONTEXT` + `I_CONTEXT`), the run loop's `I_CONTEXT`, `I_CALLM`, `I_DEPARTM` and `mcall_cont`'s resolution of
# an undefined definition (pl-vmi.c), and the decompiler's `M:Goal` / `M:Body` (pl-comp.c decompile, decompileBody):
#   * A PROGRAM consulted by the kernel's loader — user clauses with `M:Goal` bodies, `qm:Head :- Body` clauses, a multifile
#     predicate with a clause whose body module is another (test_module.pl's `cross`) — and cases `t_<id>(R)` run IN ORDER
#     in one database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`.
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, this program and test_ssu_swipl.jl's driver, 2026-10-29,
#     stable over two runs; lk-channel evidence/MOD3a/); with `swipl` on PATH the live answers are compared with the pins too.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the colon context (src/pl-comp.jl, src/pl-wam.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CB = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_cbs(x) = lk_sym(_CB, Symbol(x))

_cb_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _cb_enc(t::_CB, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _cb_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _cb_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _cb_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_cb_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _CB_DRIVER = raw"""
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
function _cb_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _CB_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: `qm`'s predicates through directives (as MOD2's rows), the clauses under test as the file's
const _CB_PROGRAM = raw"""
:- assertz(qm:(qm(C) :- context_module(C))).
:- '$set_predicate_attribute'(qm:qm(_), transparent, true).
:- assertz(qm:(ntp(C) :- context_module(C))).
m(qm).
me(1=qm).
utp(M) :- context_module(M).
:- '$set_predicate_attribute'(utp(_), transparent, true).
colon(C) :- qm:qm(C).
colonc(C) :- qm:(qm(C), true).
colonv(C) :- m(M), M:qm(C).
coloncv(C) :- m(M), M:(true, qm(C)).
colonnl(C) :- qm:qm(C), true.
colondn(C) :- qm:ntp(C).
coloncp(C) :- between(1, 2, _), qm:qm(C).
colonu(C) :- qm:utp(C), true.
colonud(C) :- qm:utp(C).
qcall(C) :- qm:call(qm(C)).
mg(M, G) :- M:G.
qmg(G) :- qm:G.
qcontrol(X) :- qm:(true -> X = 1 ; X = 2).
qunify(X) :- qm:(X = a, qm(_)).
qcut :- qm:!.
quser :- user:m(_).
qm:ctx1(C) :- context_module(C).
qm:ctx2(C) :- context_module(C).
:- '$set_predicate_attribute'(qm:ctx2(_), transparent, true).
qm:ctx3(C) :- m(C).
:- '$set_predicate_attribute'(cross(_), multifile, true).
qm2:(user:cross(_) :- nono).
qm2:(nono :- fail).
qm2:(user:cross(M) :- context_module(M)).
cross(M) :- context_module(M).
qm:lco(N, U) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, qm:lco(N1, U) ).
qm:lcp(N, U) :- ( N =:= 0 -> statistics(localused, U) ; N1 is N-1, between(1, 2, _), qm:lcp(N1, U) ).
"""

# (id, goal), run IN ORDER
const _CB_CASES = [
    # b01-b06: test_qcall's colon/colonc/colonv/coloncv and two more: a transparent `qm:qm/1` called from a user clause
    # takes the context `qm` — I_DEPARTM (b01, LCO), CB_COLON + I_CALLM (b02, b05), the TM_VAR meta-call (b03, b04);
    # a non-transparent predicate of qm runs in qm (b06)
    ("b01", raw"colon(R)"),
    ("b02", raw"colonc(R)"),
    ("b03", raw"colonv(R)"),
    ("b04", raw"coloncv(R)"),
    ("b05", raw"colonnl(R)"),
    ("b06", raw"colondn(R)"),
    # b07: I_DEPARTM with a choice point left (BFR > FR): I_CALLM's path
    ("b07", raw"findall(C, coloncp(C), R)"),
    # b08: I_CALLM of `qm:utp/1`, undefined in qm, resolved to user's transparent utp/1 by mcall_cont BEFORE the
    # transparency test (pl-vmi.c:5703-5726) — the context is qm; b09 the same as the last call (I_DEPARTM, no LCO)
    ("b08", raw"colonu(R)"),
    ("b09", raw"colonud(R)"),
    # b10: `qm:call(G)` — call/1 of system (lookupBodyProcedure's ISO branch), I_DEPARTM, the goal resolved in qm
    ("b10", raw"qcall(R)"),
    # b11, b12: `M:G` with both variables (TM_VAR meta-call of a variable goal) and `qm:G` (TM_MODULE, variable goal)
    ("b11", raw"mg(qm, qm(R))"),
    ("b12", raw"qmg(qm(R))"),
    # b13: test_module's qcontrol — a control construct under `qm:` (CB_COLON around if-then-else)
    ("b13", raw"findall(X, qcontrol(X), R)"),
    # b14-b16: =/2 compiled inline under a colon context; `qm:!` is the clause's cut; `user:G` in user is a plain call
    ("b14", raw"qunify(R)"),
    ("b15", raw"qcut, R = yes"),
    ("b16", raw"quser, R = yes"),
    # b17-b19: `qm:Head :- Body` consulted in user: I_CONTEXT user — non-transparent ctx1 runs in user; transparent ctx2
    # skips it (the context of its call, qm); ctx3's body goal m/1 is user's (the body module)
    ("b17", raw"qm:ctx1(R)"),
    ("b18", raw"qm:ctx2(R)"),
    ("b19", raw"qm:ctx3(R)"),
    # b20: test_module's cross — a multifile predicate: every rule gets I_CONTEXT of its body module (qm2's clauses, then
    # user's)
    ("b20", raw"findall(M, cross(M), R)"),
    # b21-b29: clause/2 (the decompiler, design H7): I_DEPARTM/I_CALLM → `M:G`, the meta-calls → call/1, I_CONTEXT → `M:Body`
    ("b21", raw"findall(B, clause(colon(_), B), R)"),
    ("b22", raw"findall(B, clause(colonc(_), B), R)"),
    ("b23", raw"findall(B, clause(colonv(_), B), R)"),
    ("b24", raw"findall(B, clause(qm:ctx1(_), B), R)"),
    ("b25", raw"findall(B, clause(cross(_), B), R)"),
    ("b26", raw"findall(B, clause(qcall(_), B), R)"),
    ("b27", raw"findall(B, clause(qunify(_), B), R)"),
    ("b28", raw"findall(B, clause(qmg(_), B), R)"),
    ("b29", raw"findall(B, clause(colonnl(_), B), R)"),
    # b30-b34: getTargetModule's errors at assert time — a void module, a variable met first, a number, a compound; and a
    # variable met before (TM_VAR): the clause is a meta-call
    ("b30", raw"assertz((e1 :- _:foo)), R = ok"),
    ("b31", raw"assertz((e2 :- M:foo, bar(M))), R = ok"),
    ("b32", raw"assertz((e3 :- 1:foo)), R = ok"),
    ("b33", raw"assertz((e4 :- f(x):foo)), R = ok"),
    ("b34", raw"assertz((e5(M) :- M:foo)), findall(B, clause(e5(_), B), R)"),
    # b35-b41: goal clauses (call/1 of a control construct, islocal): test_qcall's localv ×2 and local_argvar ×2 (TM_VAR
    # always under islocal: link_local_var), a module atom (I_CALLM in a goal clause), an unbound and a number module
    ("b35", raw"call((m(M), M:qm(C))), R = M-C"),
    ("b36", raw"call((me(1=M), M:qm(C))), R = M-C"),
    ("b37", raw"call((m(M), M:(qm(C), qm(C)))), R = M-C"),
    ("b38", raw"call((m(M), M:(call(qm(C)), qm(C)))), R = M-C"),
    ("b39", raw"call((qm:qm(C), true)), R = C"),
    ("b40", raw"call((true, _X:qm(_))), R = ok"),
    ("b41", raw"call((true, 1:qm(_))), R = ok"),
    # b42-b44: asserted: `qm:H :- B` from user gets I_CONTEXT user; `qm:(H :- B)` none (one module); clause/2 of the first
    ("b42", raw"assertz((qm:actx(C) :- context_module(C))), qm:actx(R)"),
    ("b43", raw"assertz(qm:(actx2(C) :- context_module(C))), qm:actx2(R)"),
    ("b44", raw"findall(B, clause(qm:actx(_), B), R)"),
    # b45, b46 (audit D-0229): I_DEPARTM's frame reuse, white-box. `statistics(localused, U)` is `8 * ld.lTop`
    # (src/pl-prims.jl `_used_stack`), read at the deepest call. `qm:lco/2`'s last goal `qm:lco(N1, U)` is I_DEPARTM
    # (body module user, `I_CONTEXT user`); with no choice point above the frame it departs (LCO): lTop at depth
    # 1000 and at depth 2000 is the SAME (b45). `qm:lcp/2`'s last goal is I_DEPARTM too, but between/3 leaves a choice point above the
    # frame, so I_DEPARTM takes I_CALLM's path (pl-vmi.c:2126-2137): a new frame per level, lTop GROWS with the depth (b46).
    # Each call is `( G -> true )`, not once/1: the kernel has no once/1 (swipl's is boot/init.pl's); same answers in swipl.
    (
        "b45",
        raw"( qm:lco(1000, U1) -> true ), ( qm:lco(2000, U2) -> true ), ( U1 == U2 -> R = same ; R = differ(U1, U2) )"
    ),
    (
        "b46",
        raw"( qm:lcp(1000, U1) -> true ), ( qm:lcp(2000, U2) -> true ), ( U2 > U1 -> R = grows ; R = flat(U1, U2) )"
    )
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; lk-channel evidence/MOD3a/mod3a_rows.out;
# b45/b46 added 2026-10-30, the whole table re-run twice, b01-b44 unchanged: evidence/MOD3a/mod3a_rows_d0229.out)
const _CB_PINNED = [
    "ok",
    "t_b01 c[116,95,98,48,49]/1(a[113,109])",
    "t_b02 c[116,95,98,48,50]/1(a[113,109])",
    "t_b03 c[116,95,98,48,51]/1(a[113,109])",
    "t_b04 c[116,95,98,48,52]/1(a[113,109])",
    "t_b05 c[116,95,98,48,53]/1(a[113,109])",
    "t_b06 c[116,95,98,48,54]/1(a[113,109])",
    "t_b07 c[116,95,98,48,55]/1(c[91,124,93]/2(a[113,109],c[91,124,93]/2(a[113,109],nil)))",
    "t_b08 c[116,95,98,48,56]/1(a[113,109])",
    "t_b09 c[116,95,98,48,57]/1(a[113,109])",
    "t_b10 c[116,95,98,49,48]/1(a[113,109])",
    "t_b11 c[116,95,98,49,49]/1(a[113,109])",
    "t_b12 c[116,95,98,49,50]/1(a[113,109])",
    "t_b13 c[116,95,98,49,51]/1(c[91,124,93]/2(i1,nil))",
    "t_b14 c[116,95,98,49,52]/1(a[97])",
    "t_b15 c[116,95,98,49,53]/1(a[121,101,115])",
    "t_b16 c[116,95,98,49,54]/1(a[121,101,115])",
    "t_b17 c[116,95,98,49,55]/1(a[117,115,101,114])",
    "t_b18 c[116,95,98,49,56]/1(a[113,109])",
    "t_b19 c[116,95,98,49,57]/1(a[113,109])",
    "t_b20 c[116,95,98,50,48]/1(c[91,124,93]/2(a[113,109,50],c[91,124,93]/2(a[117,115,101,114],nil)))",
    "t_b21 c[116,95,98,50,49]/1(c[91,124,93]/2(c[58]/2(a[113,109],c[113,109]/1(V0)),nil))",
    "t_b22 c[116,95,98,50,50]/1(c[91,124,93]/2(c[44]/2(c[58]/2(a[113,109],c[113,109]/1(V0)),a[116,114,117,101]),nil))",
    "t_b23 c[116,95,98,50,51]/1(c[91,124,93]/2(c[44]/2(c[109]/1(V0),c[99,97,108,108]/1(c[58]/2(V0,c[113,109]/1(V1)))),nil))",
    "t_b24 c[116,95,98,50,52]/1(c[91,124,93]/2(c[58]/2(a[117,115,101,114],c[99,111,110,116,101,120,116,95,109,111,100,117,108,101]/1(V0)),nil))",
    "t_b25 c[116,95,98,50,53]/1(c[91,124,93]/2(c[58]/2(a[113,109,50],a[110,111,110,111]),c[91,124,93]/2(c[58]/2(a[113,109,50],c[99,111,110,116,101,120,116,95,109,111,100,117,108,101]/1(V0)),c[91,124,93]/2(c[58]/2(a[117,115,101,114],c[99,111,110,116,101,120,116,95,109,111,100,117,108,101]/1(V1)),nil))))",
    "t_b26 c[116,95,98,50,54]/1(c[91,124,93]/2(c[58]/2(a[113,109],c[99,97,108,108]/1(c[113,109]/1(V0))),nil))",
    "t_b27 c[116,95,98,50,55]/1(c[91,124,93]/2(c[44]/2(c[61]/2(V0,a[97]),c[58]/2(a[113,109],c[113,109]/1(V1))),nil))",
    "t_b28 c[116,95,98,50,56]/1(c[91,124,93]/2(c[99,97,108,108]/1(c[58]/2(a[113,109],V0)),nil))",
    "t_b29 c[116,95,98,50,57]/1(c[91,124,93]/2(c[44]/2(c[58]/2(a[113,109],c[113,109]/1(V0)),a[116,114,117,101]),nil))",
    "t_b30 c[116,95,98,51,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_b31 c[116,95,98,51,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_b32 c[116,95,98,51,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],i1)))",
    "t_b33 c[116,95,98,51,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],c[102]/1(a[120]))))",
    "t_b34 c[116,95,98,51,52]/1(c[91,124,93]/2(c[99,97,108,108]/1(c[58]/2(V0,a[102,111,111])),nil))",
    "t_b35 c[116,95,98,51,53]/1(c[45]/2(a[113,109],a[113,109]))",
    "t_b36 c[116,95,98,51,54]/1(c[45]/2(a[113,109],a[113,109]))",
    "t_b37 c[116,95,98,51,55]/1(c[45]/2(a[113,109],a[113,109]))",
    "t_b38 c[116,95,98,51,56]/1(c[45]/2(a[113,109],a[113,109]))",
    "t_b39 c[116,95,98,51,57]/1(a[113,109])",
    "t_b40 c[116,95,98,52,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_b41 c[116,95,98,52,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,111,100,117,108,101],i1)))",
    "t_b42 c[116,95,98,52,50]/1(a[117,115,101,114])",
    "t_b43 c[116,95,98,52,51]/1(a[113,109])",
    "t_b44 c[116,95,98,52,52]/1(c[91,124,93]/2(c[58]/2(a[117,115,101,114],c[99,111,110,116,101,120,116,95,109,111,100,117,108,101]/1(V0)),nil))",
    "t_b45 c[116,95,98,52,53]/1(a[115,97,109,101])",
    "t_b46 c[116,95,98,52,54]/1(a[103,114,111,119,115])"
]

"The program and cases as one file; the case predicates' names."
function _cb_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _CB_CASES]
    text =
        _CB_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _CB_CASES
        ])
    f = joinpath(mktempdir(), "mod3a.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _cb_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_CB}()
    ld = LK.PL_local_data{_CB}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _cb_enc(ball::_CB)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_cbs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_CB, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _cb_enc(mk_expr(_CB, _CB[_cbs(name), lk_answers(ld, (a:a)...)...]))
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

@testset "M:Goal in a body as swipl's (b01-b46)" begin
    f, names = _cb_file()
    kl, _, _ = _cb_kernel(f, names)
    @test length(kl) == length(_CB_PINNED)
    for (k, p) in zip(kl, _CB_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the context rows answer qm and user, the error rows raised, clause/2 rows hold a `:`
    qm = "a[113,109]"                                   # qm
    user = "a[117,115,101,114]"                         # user
    @test count(l -> endswith(l, "/1($qm)"), _CB_PINNED) >= 15
    @test count(l -> endswith(l, "/1($user)"), _CB_PINNED) >= 2
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _CB_PINNED) >= 6     # raised(…)
    @test count(l -> occursin("c[58]/2(", l), _CB_PINNED) >= 9                       # :/2
    # b45/b46 (D-0229): the LCO row answers `same`, the choice-point row `grows`
    @test _CB_PINNED[end - 1] == "t_b45 c[116,95,98,52,53]/1(a[115,97,109,101])"
    @test _CB_PINNED[end] == "t_b46 c[116,95,98,52,54]/1(a[103,114,111,119,115])"
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_CB_PINNED) == length(_CB_CASES) + 1
    if swipl === nothing
        @info "MOD3a LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _cb_file()
        @test _cb_swipl_lines(f, names) == _CB_PINNED
    end
end
