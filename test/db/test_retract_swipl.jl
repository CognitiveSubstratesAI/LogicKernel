# ORIGINAL: a LIVE differential of retract/1 (pl-proc.c; registered by NF2 as a NON-DETERMINISTIC foreign predicate, audit D-0136)
# test/db/test_retract_swipl.jl — retract/1 against swipl at the pin, through a PROGRAM (the pattern of test/db/test_retractall_swipl.jl
# and test/core_lang/test_between_swipl.jl): each case is a predicate `t_<id>(R)`; the kernel consults the program and enumerates
# every solution of every t_<id>/1, swipl does the same through a driver, and the answers are compared as lines. EVERY expected
# value is swipl's own answer (the driver runs live); the few hand-written values are in the white-box testsets, each with its
# reason. The rows are the channel's evidence/nf/rows.pl r01–r12 (swipl 10.1.18's rows.out) and NF2 prep's n01–n10 (swipl
# 10.1.19's new_rows.out). After EVERY case the pools of the states (`live_states`, D-0136 Q8) are empty and
# `ld.predicate_references` is back where the load left it: a missing FRG_CUTTED (a cut, an exception after a redo, a query
# closed with a state live) shows as a count, named by its case. The occurs-check testset raises an error INSIDE a redo
# (design H8, D-0136 Q4(a), D-0141 item 2): the context must be cleared before the throw, or the unwind calls FRG_CUTTED on a
# freed state. The white-box side of the sink `pl_retract!` (generations, the bindings undone) is test_clause_variables.jl
# and test/db/index_*.jl.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_TL, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the kernel's lines; after EACH case the live states of the non-deterministic built-ins (`live_states`) and the predicate
# access references (`ld.predicate_references`: pushed by retract's first call, popped by its last answer or its FRG_CUTTED).
# `occurs_error`: the `occurs_check` flag is `error` from the first query on (set_prolog_flag/2 is not ported: the flag is
# the local data's field, as test_clause_variables.jl sets it); the driver sets swipl's the same way.
function kernel_lines(
    path::String, names::Vector{String}; occurs_error::Bool=false
)::Tuple{Vector{String}, Vector{Int}, Vector{Int}, Int}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    occurs_error && (ld.prolog_flag_occurs_check = LK.OCCURS_CHECK_ERROR)
    refs0 = length(ld.predicate_references)
    lives = Int[]
    refs = Int[]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(_TL, _TL[_tls(name), lk_answers(ld, (a:a)...)...]))
                    catch e
                        "export-error " * first(sprint(showerror, e), 80)
                    end
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
        push!(lives, LK.live_states(ld))
        push!(refs, length(ld.predicate_references))
    end
    return out, lives, refs, refs0
end

const DRIVER = raw"""
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
# `prelude`: driver directives run before the program is consulted (the occurs-check testset's flag)
function swipl_lines(
    path::String, names::Vector{String}; prelude::String=""
)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * prelude * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program shared by both sides (rows.pl's helpers, with new_rows.pl's u/1 and st/1): q/1, r/1, s/2, d/0 and u/1 dynamic,
# q(1..3) after `reset`; st/1 STATIC (n04); `left/1` reports what q/1 holds; `callzz1/0` calls the undefined zz1/0 (n11)
const _PROGRAM = """
:- dynamic q/1, r/1, s/2, d/0, u/1, w/1, v/1.
reset :- retractall(q(_)), retractall(r(_)), retractall(s(_,_)),
         assertz(q(1)), assertz(q(2)), assertz(q(3)).
left(L) :- findall(X, q(X), L).
st(a).
st(b).
callzz1 :- zz1.
"""

# (id, goal). A row that reports an error catches it and returns its formal term, as rows.out printed it (`raised(E)`).
const _RT_CASES = [
    ("r01", "reset, findall(X, retract(q(X)), L), left(Left), R = L-Left"),
    ("r02", "reset, retract(q(X)), X >= 2, !, left(Left), R = X-Left"),                          # FRG_CUTTED by a cut
    ("r03", "reset, ( retract(q(X)), assertz(q(9)), fail ; true ), left(L), R = L"),            # the logical update view
    ("r04", "reset, retract(q(2)), left(R)"),
    ("r05", "reset, ( retract(q(7)) -> R = yes ; R = no )"),
    ("r06", "reset, retract(q(X)), X == 3, R = X"),
    (
        "r07",
        "assertz((r(X) :- X > 1, q(X))), assertz(r(5)), findall(B, retract((r(_) :- B)), R)"
    ),   # a rule's body
    ("r08", "catch(( retract(_), R = no ), error(E, _), R = E)"),
    # r09 is `retract(foo:undefined_pred_x(_))`: a module other than system and user is NotPortedError until R2
    # (lookupModule, src/pl-modul.jl); r09u is the same row in `user` (new_rows.pl's probe: swipl fails)
    ("r09u", "retract(undefined_pred_x(_)), R = no"),
    # r10 is `retract(atom_length(_, _))`: atom_length/2 is not a kernel built-in, so the row would ask about a user predicate;
    # is/2 and assertz/1 take the same path (isCurrentProcedure in `user` fails, checkModifySystemProc raises)
    ("r10i", "catch(( retract(is(_, _)), R = no ), error(E, _), R = E)"),
    ("r10a", "catch(( retract(assertz(_)), R = no ), error(E, _), R = E)"),
    ("r11", "catch(( retract(3), R = no ), error(E, _), R = E)"),
    (
        "r12",
        "reset, catch(( retract(q(X)), X == 2, throw(boom(X)) ), boom(Y), true), left(L), R = Y-L"
    ),   # an exception after a redo
    # ---- NF2 prep's rows (new_rows.pl n01–n10; each kills a mutant the r-rows do not)
    (
        "n01",
        "reset, findall(X, ( retract(q(X)), ( X == 1 -> retract(q(2)) ; true ) ), L), left(Left), R = L-Left"
    ),   # a redo answers an erased clause
    ("n02", "reset, assertz(s(a, c)), assertz(s(d, b)), retract(s(X, b)), R = X"),                # the failed head's binding is undone
    ("n03", "reset, assertz(d), retract(d), ( d -> R = still ; R = gone )"),                      # an atom head: argv NULL
    ("n04", "catch(( retract(st(_)), R = no ), error(E, _), R = E)"),                             # a static predicate
    ("n05", "retract(u(_)), R = no"),                                                             # dynamic, no clauses: fails
    (
        "n06",
        "reset, findall(X-Y, ( retract(q(X)), between(1, 2, Y) ), L), left(Left), R = L-Left"
    ),   # nested with between/3
    ("n07", "reset, retract(q(X)), !, left(Left), R = X-Left"),
    ("n08", "reset, findall(X, ( retract(q(X)), X >= 2, ! ), L), left(Left), R = L-Left"),
    ("n09", "reset, assertz(s(a, c)), retract((s(X, Y) :- true)), R = X-Y"),
    ("n10", "reset, retract(user:q(X)), R = X"),                                                  # three answers, module-qualified
    # a failed attempt is REWOUND before the next clause (pl-proc.c retract: PL_rewind_foreign_frame) — rows the
    # index cannot decide: the body fails after the head bound X, and a nested argument fails after X (NF2-R5)
    (
        "n12",
        "retractall(w(_)), assertz((w(1) :- st(a))), assertz((w(2) :- st(b))), retract((w(X) :- st(b))), R = X"
    ),
    (
        "n13",
        "retractall(v(_)), assertz(v(f(1, c))), assertz(v(f(2, b))), retract(v(f(X, b))), R = X"
    ),
    # NF2's own row (answered by the live swipl only; not in rows.out or new_rows.out): `zz1/0` exists — `callzz1/0`'s body
    # calls it — but is neither dynamic nor defined, so retract/1 makes it dynamic and fails (pl-proc.c:3168-3173); the
    # call then fails where it would have raised existence_error
    (
        "n11",
        "( retract(zz1) -> true ; true ), catch(( callzz1 -> R = yes ; R = no ), error(E, _), R = E)"
    ),
    # ---- NF2 prep's probes (§4: swipl instantiation_error / fail) and a second sweep
    ("p01", "catch(( retract((_ :- true)), R = no ), error(E, _), R = E)"),
    ("p02", "( retract((foo :- _)) -> R = yes ; R = no )"),
    ("p03", "reset, findall(X, retract(q(X)), L), findall(Y, retract(q(Y)), M), R = L-M")
]

@testset "retract/1 == live swipl, through a program; no state leaked" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "RETRACT DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        names = ["t_$(id)" for (id, _) in _RT_CASES]
        text = _PROGRAM * join(["t_$(id)(R) :- ($g).\n" for (id, g) in _RT_CASES])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = swipl_lines(f, names)
        kl, lives, refs, refs0 = kernel_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test kl == sw
        # not a vacuous agreement: each kind of answer is in swipl's own lines (one extractor, `count` on them)
        @test count(l -> occursin("114,114,111,114", l), sw) >= 5        # an `…rror` atom: r08, r10i, r10a, r11, n04, p01
        @test count(l -> occursin("c[91,124,93]/2", l), sw) >= 5         # a list: r01, r03, r04, r07, r12, n01, n06, n08, p03
        @test any(l -> startswith(l, "t_n10 ") && count(==(' '), l) == 3, sw)        # a three-answer row
        @test any(l -> startswith(l, "t_r05 ") && length(l) > 6, sw)                  # r05 answered (`no`), not FAILED
        @test any(==("t_r09u"), sw) && any(==("t_n05"), sw)                           # swipl's FAILs are bare names
        @test length(lives) == length(names) && length(refs) == length(names)
        for (i, n) in enumerate(lives)
            @test (names[i], n) == (names[i], 0)
        end
        for (i, n) in enumerate(refs)
            @test (names[i], n) == (names[i], refs0)
        end
    end
end

# The occurs check raises inside retract/1 (prep §1.5, the S10 clauses; design H8): under `occurs_check=error`, at the FIRST
# call (e02: `q(Y, Y)` first — nothing retracted) and INSIDE A REDO (e01: `q2(Z, f(Z))` answers, then `q2(Y, Y)` raises on the
# redo). I_FEXITNDET clears the frame's context before it throws (pl-vmi.c), so the unwind finds no context to cut; with it
# left set, FRG_CUTTED runs on the freed state and `popPredicateAccess!` or `free_foreign_state!` asserts. Only the ball's
# name is compared: its variables are not what this row is about.
const _OC_PROGRAM = """
:- dynamic q/2, q2/2.
q(Y, Y).
q(a, f(a)).
q2(Z, f(Z)).
q2(Y, Y).
"""
const _OC_CASES = [
    (
        "e01",
        "catch(( retract(q2(A, f(A))), fail ), error(E, _), true), functor(E, N, _), findall(X-Y, q2(X, Y), L), R = N-L"
    ),
    (
        "e02",
        "catch(retract(q(A, f(A))), error(E, _), true), functor(E, N, _), findall(X-Y, q(X, Y), L), R = N-L"
    )
]

@testset "retract/1 under occurs_check=error: the error at the first call and inside a redo; no state leaked" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "RETRACT OCCURS-CHECK DIFFERENTIAL NOT RUN: `swipl` is not on PATH here."
        @test true
    else
        names = ["t_$(id)" for (id, _) in _OC_CASES]
        text = _OC_PROGRAM * join(["t_$(id)(R) :- ($g).\n" for (id, g) in _OC_CASES])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = swipl_lines(f, names; prelude=":- set_prolog_flag(occurs_check, error).\n")
        kl, lives, refs, refs0 = kernel_lines(f, names; occurs_error=true)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test kl == sw
        @test count(l -> occursin(_codes("occurs_check"), l), sw) == 2     # both rows raised (not a vacuous agreement)
        for (i, n) in enumerate(lives)
            @test (names[i], n) == (names[i], 0)
        end
        for (i, n) in enumerate(refs)
            @test (names[i], n) == (names[i], refs0)
        end
    end
end

# ---- WHITE-BOX: retract/1 queried directly; the retry backtracks into the foreign frame itself (the last testset of
# test_between_swipl.jl). The answers are swipl's (r01: q(1), q(2), q(3)); the STATUS (`PL_S_LAST` on the last answer) and the
# access reference kept between answers cannot be observed through swipl's driver — hand-written from upstream: the
# deterministic exit (pl-proc.c:3214-3218) frees the state and returns true, `ForeignRedoPtr` (3229) pops nothing.
function _rt_open()
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    f = joinpath(mktempdir(), "p.pl")
    write(f, ":- dynamic q/1.\nq(1).\nq(2).\nq(3).\n")
    st, _, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    return gd, ld
end

function _rt_query(gd, ld)
    proc = LK.isCurrentProcedure(sym_key(_tls("retract")), 1, LK.MODULE_system(gd))
    @test proc !== nothing
    pvm = LK.PutVarMap()
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(
        ld, a + 1, mk_expr(_TL, _TL[_tls("q"), mk_var(_TL, LK.fresh_var_keys!(1))]), pvm
    )
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    return proc, a, qid, fid
end

@testset "retract/1 queried directly: every answer, then the deterministic last one" begin
    gd, ld = _rt_open()
    refs0 = length(ld.predicate_references)
    proc, a, qid, fid = _rt_query(gd, ld)
    d = proc.definition
    @test d.codes == [
        LK.I_FOPENNDET,
        LK.I_FCALLNDETVA,
        LK.code(d.impl_foreign_function),
        LK.I_FEXITNDET,
        LK.I_FREDO
    ]
    got = String[]
    rcs = Int[]
    while length(got) < 10
        rc = LK.PL_next_solution(gd, ld, qid)
        push!(rcs, rc)
        (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
        push!(got, enc(lk_answers(ld, a)[1]))                          # the argument: retract's term reference `a`
        rc == LK.PL_S_LAST && break
        c = ld.choices[ld.BFR]
        @test c.type == LK.CHP_JUMP &&
            (ld.frames[c.frame].fctx & LK.FRG_REDO_MASK) == LK.REDO_PTR
        @test LK.live_states(ld) == 1                                  # the state of the pending retry
        @test length(ld.predicate_references) == refs0 + 1             # the access reference stays pushed (pl-proc.c:3229)
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test got == [enc(mk_expr(_TL, _TL[_tls("q"), mk_gnd(_TL, Int64(i))])) for i in 1:3]
    @test rcs == [LK.PL_S_TRUE, LK.PL_S_TRUE, LK.PL_S_LAST]
    @test LK.live_states(ld) == 0
    @test length(ld.predicate_references) == refs0                     # popped by the deterministic exit
end

@testset "retract/1 queried directly: a query closed with a state live is a cut" begin
    gd, ld = _rt_open()
    refs0 = length(ld.predicate_references)
    proc, a, qid, fid = _rt_query(gd, ld)
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE
    @test LK.live_states(ld) == 1
    @test length(ld.predicate_references) == refs0 + 1
    LK.PL_close_query(ld, qid)                                         # FRG_CUTTED: frees the state, pops the reference
    LK.PL_close_foreign_frame(ld, fid)
    @test LK.live_states(ld) == 0
    @test length(ld.predicate_references) == refs0
end

# NOT HERE, and why:
#   * r09 `retract(foo:undefined_pred_x(_))`: a module other than system and user (R2); r09u stands in.
#   * r10 `retract(atom_length(_, _))`: atom_length/2 is not ported; r10i / r10a take the same path.
