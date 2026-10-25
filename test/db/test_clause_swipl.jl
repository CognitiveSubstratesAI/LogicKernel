# ORIGINAL: a LIVE differential of clause/2 (pl-comp.c; registered by NF2 as a NON-DETERMINISTIC foreign predicate, audit D-0136)
# test/db/test_clause_swipl.jl — clause/2 against swipl at the pin, through a PROGRAM (the pattern of test/db/test_retractall_swipl.jl
# and test/core_lang/test_between_swipl.jl): each case is a predicate `t_<id>(R)`; the kernel consults the program and enumerates
# every solution of every t_<id>/1, swipl does the same through a driver, and the answers are compared as lines. EVERY expected
# value is swipl's own answer (the driver runs live); the few hand-written values are in the white-box testsets, each with its
# reason. The rows are the channel's evidence/nf/rows.pl c01–c09 (swipl 10.1.18's rows.out) and NF2 prep's m-rows (swipl
# 10.1.19's new_rows.out). After EVERY case the pools of the states (`live_states`) are empty and `ld.predicate_references` is
# back where the load left it. clause/3 (a clause REFERENCE: rows c10, m02, m07–m10) is NOT here: the kernel has no clause
# references as terms and no erase/1. The occurs-check testset is S10's clause/2 half through the VM: clause/2 goes on past
# the error of a head's unification, and I_FEXITNDET clears it as a false alarm when an answer follows (pl-vmi.c).
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

# the kernel's lines; after EACH case the live states (`live_states`) and the predicate access references
# (`ld.predicate_references`: pushed by clause's first call, popped by its last answer or its FRG_CUTTED).
# `occurs_error`: the `occurs_check` flag is `error` from the first query on (set_prolog_flag/2 is not ported).
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
# q(1..3) after `reset`; st/1 STATIC (m05); `left/1` reports what q/1 holds
const _PROGRAM = """
:- dynamic q/1, r/1, s/2, d/0, u/1.
reset :- retractall(q(_)), retractall(r(_)), retractall(s(_,_)),
         assertz(q(1)), assertz(q(2)), assertz(q(3)).
left(L) :- findall(X, q(X), L).
st(a).
st(b).
"""

# (id, goal). A row that reports an error catches it and returns its formal term, as rows.out printed it (`raised(E)`).
const _CL_CASES = [
    (
        "c01",
        "reset, assertz((r(X) :- q(X))), assertz((r(0) :- true)), findall(H-B, clause(r(H), B), R)"
    ),   # a rule body; a variable answer
    ("c02", "reset, findall(X-B, clause(q(X), B), R)"),
    ("c03", "catch(( clause(_, true), R = no ), error(E, _), R = E)"),                         # GP_FIND: an unbound head
    ("c04", "catch(( clause(3, _), R = no ), error(E, _), R = E)"),                            # GP_FIND: a non-callable head
    # c05 is `clause(atom_length(_, _), B)`: atom_length/2 is not a kernel built-in; m11 (is/2) and m12 (true/0) take the
    # same path (protected_predicate: a foreign predicate)
    ("c06", "clause(undefined_pred_y(_), B), R = B"),                                          # not found: fails, no error
    ("c07", "reset, clause(q(X), true), !, R = X"),                                            # FRG_CUTTED by a cut
    (
        "c08",
        "reset, findall(X, ( clause(q(X), true), ( X == 1 -> assertz(q(8)) ; true ) ), R)"
    ),   # the logical update view
    ("c09", "clause(reset, B), B = (A, _), R = A"),                                            # an atom head: argv NULL
    # c10 `clause(q(X), true, Ref), erase(Ref), …`: clause/3 and erase/1 are not ported
    # ---- NF2 prep's rows (new_rows.pl's m-rows without a clause reference)
    ("m01", "reset, assertz(s(a, c)), assertz(s(d, b)), clause(s(X, b), true), R = X"),         # the failed head's binding is undone
    ("m03", "reset, clause(user:reset, B), B = (A, _), R = A"),                                # qualified, arity 0: unify_head's strip
    ("m04", "reset, findall(X-B, clause(user:q(X), B), L), R = L"),                            # qualified, three answers
    ("m05", "clause(st(X), B), R = X-B"),                                                      # a STATIC predicate is readable
    ("m06", "reset, findall(X, ( clause(q(X), true), X >= 2, ! ), L), R = L"),                 # a cut inside findall
    ("m11", "catch(( clause(is(_, _), B), R = B ), error(E, _), R = E)"),                      # permission_error(access, private_procedure, PI)
    ("m12", "catch(( clause(true, B), R = B ), error(E, _), R = E)"),
    # NF2's own row (answered by the live swipl only; not in rows.out or new_rows.out): a zero-arity compound head `z0()`
    # against the decompiled atom `z0` — unify_atom_compound's second arm (pl-comp.c:7280-7285)
    ("m13", "assertz(z0), ( clause(z0(), B) -> R = B ; R = no )"),
    # m02, m07–m10: clause/3 with a reference (and erase/1) — not ported
    # ---- NF2 prep's probe (§4: swipl instantiation_error)
    ("p01", "catch(( clause(_, _), R = no ), error(E, _), R = E)")
]

@testset "clause/2 == live swipl, through a program; no state leaked" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "CLAUSE DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        names = ["t_$(id)" for (id, _) in _CL_CASES]
        text = _PROGRAM * join(["t_$(id)(R) :- ($g).\n" for (id, g) in _CL_CASES])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = swipl_lines(f, names)
        kl, lives, refs, refs0 = kernel_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test kl == sw
        # not a vacuous agreement: each kind of answer is in swipl's own lines (one extractor, `count` on them)
        @test count(l -> occursin("114,114,111,114", l), sw) >= 5        # an `…rror` atom: c03, c04, m11, m12, p01
        @test count(l -> occursin("c[91,124,93]/2", l), sw) >= 4         # a list: c01, c02, c08, m04, m06
        @test any(l -> startswith(l, "t_m05 ") && count(==(' '), l) == 2, sw)        # a two-answer row
        @test any(==("t_c06"), sw)                                                    # swipl's FAIL is a bare name
        @test length(lives) == length(names) && length(refs) == length(names)
        for (i, n) in enumerate(lives)
            @test (names[i], n) == (names[i], 0)
        end
        for (i, n) in enumerate(refs)
            @test (names[i], n) == (names[i], refs0)
        end
    end
end

# S10's clause/2 half (prep §1.5, swipl 10.1.19 probed `oc.pl`: [a], no error): under `occurs_check=error` the head
# `q(A, f(A))` raises against `q(Y, Y)` in `unify_head`, which does not stop the scan (pl-comp.c:7486-7488 stops only for an error
# of `decompile`); `q(a, f(a))` answers last, so clause/2 returns true with the error pending, and I_FEXITNDET clears it as a
# false alarm. (The sink `pl_clause!` leaves it pending: test_clause_variables.jl, its own protocol.)
const _OC_PROGRAM = """
:- dynamic q/2.
q(Y, Y).
q(a, f(a)).
"""
const _OC_CASES = [
    ("e03", "findall(A, clause(q(A, f(A)), true), R)"),
    (
        "e04",
        "catch(( clause(q(A, f(A)), true), R = A ), error(E, _), ( functor(E, N, _), R = N ))"
    )
]

@testset "clause/2 under occurs_check=error: the error of a head is a false alarm when an answer follows" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "CLAUSE OCCURS-CHECK DIFFERENTIAL NOT RUN: `swipl` is not on PATH here."
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
        @test any(l -> startswith(l, "t_e03 ") && occursin("a[97]", l), sw)   # `[a]`: an answer, not an error (not vacuous)
        for (i, n) in enumerate(lives)
            @test (names[i], n) == (names[i], 0)
        end
        for (i, n) in enumerate(refs)
            @test (names[i], n) == (names[i], refs0)
        end
    end
end

# ---- WHITE-BOX 1: clause/2 of an unknown predicate creates nothing. Hand-written: the kernel has no current_predicate/1 to
# ask the swipl question with; upstream's get_procedure(GP_FIND) (pl-proc.c:772-777, 796-799) creates nothing.
@testset "clause/2 of an unknown predicate creates nothing" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    f = joinpath(mktempdir(), "p.pl")
    write(f, "t_c06(R) :- clause(undefined_pred_y(_), B), R = B.\n")
    st, _, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    proc = LK.isCurrentProcedure(sym_key(_tls("t_c06")), 1, LK.MODULE_user(gd))
    @test proc !== nothing
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_FALSE
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test LK.isCurrentProcedure(
        sym_key(_tls("undefined_pred_y")), 1, LK.MODULE_user(gd)
    ) ===
        nothing
end

# ---- WHITE-BOX 2: clause/2 queried directly (the retry backtracks into the foreign frame itself). The answers are swipl's (c02:
# q(1)-true, q(2)-true, q(3)-true); the status and the access reference kept between answers are hand-written from upstream:
# the deterministic last answer (pl-comp.c:7471-7474) frees the state and pops the access; `ForeignRedoPtr` (7480) pops nothing.
function _cl_open()
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    f = joinpath(mktempdir(), "p.pl")
    write(f, ":- dynamic q/1.\nq(1).\nq(2).\nq(3).\n")
    st, _, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    return gd, ld
end

function _cl_query(gd, ld)
    proc = LK.isCurrentProcedure(sym_key(_tls("clause")), 2, LK.MODULE_system(gd))
    @test proc !== nothing
    pvm = LK.PutVarMap()
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(
        ld, a + 1, mk_expr(_TL, _TL[_tls("q"), mk_var(_TL, LK.fresh_var_keys!(1))]), pvm
    )
    LK.putSlotValue!(ld, a + 2, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    return proc, a, qid, fid
end

@testset "clause/2 queried directly: every answer, then the deterministic last one" begin
    gd, ld = _cl_open()
    refs0 = length(ld.predicate_references)
    proc, a, qid, fid = _cl_query(gd, ld)
    d = proc.definition
    @test d.codes == [
        LK.I_FOPENNDET,
        LK.I_FCALLNDETVA,
        LK.code(d.impl_foreign_function),
        LK.I_FEXITNDET,
        LK.I_FREDO
    ]
    got = Tuple{String, String}[]
    rcs = Int[]
    while length(got) < 10
        rc = LK.PL_next_solution(gd, ld, qid)
        push!(rcs, rc)
        (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
        # the head is clause's term reference `a`, the body `a + 1`
        push!(got, (enc(lk_answers(ld, a)[1]), enc(lk_answers(ld, a + 1)[1])))
        rc == LK.PL_S_LAST && break
        @test LK.live_states(ld) == 1
        @test length(ld.predicate_references) == refs0 + 1             # pushed by the first call (pl-comp.c:7408)
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test got == [
        (enc(mk_expr(_TL, _TL[_tls("q"), mk_gnd(_TL, Int64(i))])), enc(_tls("true"))) for
        i in 1:3
    ]
    @test rcs == [LK.PL_S_TRUE, LK.PL_S_TRUE, LK.PL_S_LAST]
    @test LK.live_states(ld) == 0
    @test length(ld.predicate_references) == refs0
end

@testset "clause/2 queried directly: a query closed with a state live is a cut" begin
    gd, ld = _cl_open()
    refs0 = length(ld.predicate_references)
    proc, a, qid, fid = _cl_query(gd, ld)
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE
    @test LK.live_states(ld) == 1
    @test length(ld.predicate_references) == refs0 + 1
    LK.PL_close_query(ld, qid)                                         # FRG_CUTTED: pops the access, frees the state
    LK.PL_close_foreign_frame(ld, fid)
    @test LK.live_states(ld) == 0
    @test length(ld.predicate_references) == refs0
end
