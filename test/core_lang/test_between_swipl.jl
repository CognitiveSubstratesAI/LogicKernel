# ORIGINAL: a LIVE differential of between/3 (pl-arith.c; registered by NF1, the first non-deterministic built-in, audit D-0136)
# test/core_lang/test_between_swipl.jl — between/3 against swipl at the pin, through a PROGRAM (the pattern of
# test/db/test_retractall_swipl.jl): each case is a predicate `tN(R)`; the kernel consults the program and enumerates every
# solution of every tN/1, swipl does the same through a driver, and the answers are compared as lines. The rows are
# evidence/nf/rows.pl's b01–b13 (the int64 edge b11 crosses 2^63, so `REDO_PTR`'s state carries a big integer), and two of
# NF1's: the deterministic `Low == High` answer and a cut by an if-then-else. After EVERY case the pool of between/3's states
# is empty again (`live_states`, D-0136 Q8): a missing `FRG_CUTTED` — at a cut, an exception after a redo or a query closed
# with a state live — shows as a count, named by its case. The last testset opens a query on between/3 itself: its retry
# arrives at `shallow_backtrack` with the foreign frame as `FR`, which no program reaches.
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

# b01–b13: evidence/nf/rows.pl (an error row reports its formal term); then NF1's own rows
const _BT_CASES = [
    "findall(X, between(1, 4, X), R)",                                         # b01
    "findall(X, between(3, 1, X), R)",                                         # b02
    "between(1, inf, X), X > 3, !, R = X",                                     # b03: a cut
    "between(1, infinite, X), X > 2, !, R = X",                                # b04
    "( between(2, 2, 2) -> R = yes ; R = no )",                                # b05
    "( between(1, 3, 5) -> R = yes ; R = no )",                                # b06
    "catch(( between(a, 3, _), R = no ), error(E, _), R = E)",                 # b07
    "catch(( between(_, 3, _), R = no ), error(E, _), R = E)",                 # b08
    "catch(( between(1, 3, a), R = no ), error(E, _), R = E)",                 # b09
    "catch(( between(1, 3, 1.0), R = no ), error(E, _), R = E)",               # b10
    "findall(X, between(9223372036854775806, 9223372036854775808, X), R)",    # b11: across 2^63
    "catch(( between(1, 5, X), X == 3, throw(stop(X)) ), stop(Y), R = Y)",    # b12: exception after a redo
    "findall(X-Y, ( between(1, 2, X), between(1, 2, Y) ), R)",                 # b13: nested
    "findall(X, between(0, 0, X), R)",                                         # Low == High: no state
    "( between(1, 3, X), X > 1 -> R = X ; R = none )",                         # a cut by ->
    "between(1, 3, R)",                                                        # every answer, by the query's retry
    "between(1, inf, R), R > 2"                                                # the query closed with a state live
]

@testset "between/3 == live swipl, through a program; no state leaked" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "BETWEEN DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        names = ["t$(i - 1)" for i in eachindex(_BT_CASES)]
        text = join(["t$(i - 1)(R) :- ($g).\n" for (i, g) in enumerate(_BT_CASES)])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = swipl_lines(f, names)
        kl, lives = kernel_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test kl == sw
        # not a vacuous agreement: an error row, the big integer and a three-answer row are in swipl's own lines
        @test any(l -> occursin("i9223372036854775808", l), sw)
        @test count(l -> occursin("114,114,111,114", l), sw) >= 4      # an `…rror` atom: b07–b10
        @test any(l -> startswith(l, "t15 ") && count(==(' '), l) == 3, sw)
        @test length(lives) == length(names)
        for (i, n) in enumerate(lives)
            @test (names[i], n) == (names[i], 0)
        end
    end
end

@testset "between/3 queried directly: the retry backtracks into the foreign frame itself" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    proc = LK.isCurrentProcedure(sym_key(_tls("between")), 3, LK.MODULE_system(gd))
    @test proc !== nothing
    pvm = LK.PutVarMap()
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 3)
    LK.putSlotValue!(ld, a + 1, mk_gnd(_TL, Int64(1)), pvm)
    LK.putSlotValue!(ld, a + 2, mk_gnd(_TL, Int64(3)), pvm)
    LK.putSlotValue!(ld, a + 3, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    # the supervisor is upstream's five words (pl-supervisor.c), the operand between/3's dispatch index
    d = proc.definition
    @test d.codes == [
        LK.I_FOPENNDET,
        LK.I_FCALLNDETVA,
        LK.code(d.impl_foreign_function),
        LK.I_FEXITNDET,
        LK.I_FREDO
    ]
    got = Any[]
    rcs = Int[]
    jumps = Tuple{Int, Int}[]                   # after each non-last answer: the jump choice's (value_pc, frame)
    while length(got) < 10
        rc = LK.PL_next_solution(gd, ld, qid)
        push!(rcs, rc)
        (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
        push!(got, lk_value(lk_answers(ld, a + 2)[1]))
        rc == LK.PL_S_LAST && break
        c = ld.choices[ld.BFR]
        @test c.type == LK.CHP_JUMP
        push!(jumps, (c.value_pc, c.frame))
        @test ld.frames[c.frame].fctx != 0 &&
            (ld.frames[c.frame].fctx & LK.FRG_REDO_MASK) == LK.REDO_PTR
        @test LK.live_states(ld) == 1
    end
    # the choice point resumes at the I_FREDO word (PC+3 from I_FCALLNDETVA), in the foreign frame
    @test length(jumps) == 2 && all(j -> j[1] == 5, jumps) && jumps[1][2] == jumps[2][2]
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test got == [1, 2, 3]
    @test rcs == [LK.PL_S_TRUE, LK.PL_S_TRUE, LK.PL_S_LAST]      # swipl: the last answer is deterministic
    @test LK.live_states(ld) == 0
end
