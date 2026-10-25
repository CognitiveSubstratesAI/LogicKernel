# ORIGINAL: a LIVE differential of repeat/0 (pl-prims.c; registered by NF4, the first non-deterministic built-in of the
# `a1, a2, …` convention, audit D-0149 item 3)
# test/core_lang/test_repeat_swipl.jl — repeat/0 against swipl at the pin, through a PROGRAM (test_between_swipl.jl's
# harness): each case is a predicate `tN(R)`; the kernel and swipl enumerate up to 50 solutions of each, compared as lines.
# repeat/0 keeps no state (an integer retry context, `REDO_INT`), so the white-box testsets read the context itself: the
# query's `FNDET_CONTEXT` after a redo (I_FREDO's arithmetic decode, pl-vmi.c:4773) and after a discard (discardForeignFrame's
# unsigned decode, pl-wam.c), and the supervisor `I_FOPENNDET, I_FCALLNDET0 f, I_FEXITNDET, I_FREDO` (pl-supervisor.c).
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
        v isa AbstractFloat && return "f$(v)"                       # (b10's culprit `1.0`)
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the kernel's lines, and between/3's live states after each case (0 everywhere when no state leaked)
function kernel_lines(
    path::String, names::Vector{String}
)::Tuple{Vector{String}, Vector{Int}}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    lives = Int[]
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
    end
    return out, lives
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
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

const _RP_PROGRAM = """
:- dynamic c/1.
"""

const _RP_CASES = [
    "repeat, !, R = once",                                                                      # a cut ends it
    "findall(X, ( between(1, 3, X), repeat, ! ), R)",                                          # the cut reaches between/3
    "retractall(c(_)), assertz(c(0)), repeat, retract(c(N)), N1 is N+1, assertz(c(N1)), N1 >= 3, !, R = N1",  # three redos
    "( repeat -> R = yes ; R = no )",                                                           # a cut by ->
    "retractall(c(_)), assertz(c(0)), catch(( repeat, retract(c(N)), N1 is N+1, assertz(c(N1)), N1 >= 2, throw(s(N1)) ), s(V), R = V)",  # an exception after a redo
    "\\+ \\+ repeat, R = ok",                                                                 # inside a double negation
    "findall(N1, ( retractall(c(_)), assertz(c(0)), repeat, retract(c(N)), N1 is N+1, assertz(c(N1)), ( N1 >= 3 -> ! ; fail ) ), R)",  # a cut in a then-branch
    "repeat, R = live"                                                                          # 50 answers; the query closed with the frame live
]

@testset "repeat/0 == live swipl, through a program" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "REPEAT DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        names = ["t$(i - 1)" for i in eachindex(_RP_CASES)]
        text =
            _RP_PROGRAM *
            join(["t$(i - 1)(R) :- ($g).\n" for (i, g) in enumerate(_RP_CASES)])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = swipl_lines(f, names)
        kl, _ = kernel_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test kl == sw
        # not a vacuous agreement: the counter row answers 3, the endless row gives 50 answers
        @test any(l -> startswith(l, "t2 ") && occursin("i3", l), sw)
        @test any(l -> startswith(l, "t7 ") && count(==(' '), l) == 50, sw)
    end
end

"An open query on system:repeat/0 (no arguments), and its definition."
function _rp_query(gd, ld)
    proc = LK.isCurrentProcedure(sym_key(_tls("repeat")), 0, LK.MODULE_system(gd))
    @test proc !== nothing
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, 0
    )
    return qid, proc.definition
end

@testset "repeat/0 queried directly: the a1 supervisor, the REDO_INT context, decoded at redo and at discard" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    fid = LK.PL_open_foreign_frame(ld)
    qid, d = _rp_query(gd, ld)
    @test d.codes == [
        LK.I_FOPENNDET,
        LK.I_FCALLNDET0,
        LK.code(d.impl_foreign_function),
        LK.I_FEXITNDET,
        LK.I_FREDO
    ]
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE          # never PL_S_LAST: a retry context
    c = ld.choices[ld.BFR]
    @test c.type == LK.CHP_JUMP
    fr = c.frame
    @test (ld.frames[fr].fctx & LK.FRG_REDO_MASK) == LK.REDO_INT
    @test (ld.frames[fr].fctx >> LK.FRG_REDO_BITS) == 2             # ForeignRedoInt(2L)
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE          # the redo, through I_FREDO
    ctx = ld.queries[ld.query].fndet_context
    @test ctx.control == LK.FRG_REDO && ctx.context == 2            # I_FREDO's decode
    LK.discardFrame(ld, ld.choices[ld.BFR].frame)                   # FRG_CUTTED through _fcall_ndet, every argument 0
    @test ctx.control == LK.FRG_CUTTED && ctx.context == 2          # discardForeignFrame's decode
    @test ld.frames[fr].fctx == 0
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end
