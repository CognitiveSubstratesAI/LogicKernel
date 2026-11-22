# ORIGINAL: a differential of directed rounding in arithmetic COMPILED under `optimise` (pl-vmi.c A_ENTER .. A_IS / A_LT .., A_ROUNDTOWARDS_A/V, A_FUNC2 roundtoward) against swipl at the pin
# test/core_lang/test_arith_roundopt_swipl.jl — AR1's rows for the mode the compiled arithmetic reads (`_vmi_a_*!` of src/pl-wam.jl), through a
# PROGRAM (the pattern of test_arith_wakeup_swipl.jl): test_arith_roundopt_swipl.pl holds the rows, each a predicate `tN(R)`, compiled
# under `:- set_prolog_flag(optimise, true)`, so `X is Expr` is `A_ENTER .. A_IS`; the kernel consults it and enumerates every
# solution of every tN/1, its lines are compared with test_arith_roundopt_swipl.out — the pin's own swipl (10.1.20, 18168e62: two
# byte-identical runs). When `swipl` is on PATH the .out is checked against a live run as well, so it cannot go stale.
# KNOWN DIFFERENCES (rows k0, k1; the project's known-difference rule: the exact current answer of the kernel AND swipl's, a checklist line
# in docs/architecture.md): after a THROW inside a nested `roundtoward` the pin's AR_CLEANUP puts back the mode before the LAST roundtoward that
# ran (the outer's mode), so the pin LEAKS the outer mode: a later `1/3.0` prints 0.33333333333333337 (to_positive) with the flag still to_nearest.
# The kernel sets the mode per evaluation in A_ENTER and restores the entry mode at every end: its later `1/3.0` is 0.3333333333333333.
# Assumed until Shivaji rules: a DIVERGES (behavioural, corner case, pinned both ways).
# UNTESTED on the kernel: written without a compile, the gate decides
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
        # the kernel's own float writer (write/1 and ~w: format_float(f, 3, 'e'), pl-write.c format_float) = the pin's
        # format("f~w"): Julia's string(::Float64) prints 1.7976931348623157e308 where swipl prints ...e+308 (HARNESS-DIFFERS)
        v isa AbstractFloat && return "f" * LK.format_float(Float64(v), 3, 'e')
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end


const _RO_PL = joinpath(@__DIR__, "test_arith_roundopt_swipl.pl")
const _RO_OUT = joinpath(@__DIR__, "test_arith_roundopt_swipl.out")

# the rows' names, in the order of the program
_ro_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_RO_PL, String))])

# the solutions of the row `name`/1, as `enc` lines (a Julia exception, a refusal included, is not caught here)
function _ro_row(gd, ld, name::String)::Vector{String}
    proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
    if proc === nothing || !LK.isDefinedProcedure(gd, proc)
        return String["$name undefined"]
    end
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    try
        n = 0
        while (n += 1) <= 100
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
    finally
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return String["$name" * join(" " .* sols)]
end

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for name in names
        append!(out, _ro_row(gd, ld, name))
    end
    return out
end

# the driver swipl runs to print its lines (the .out is its output)
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
    catch(findnsols(100, G, G, Gs), _, Gs = [exception]),
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
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


# the pin's lines of the two known-difference rows (swipl 10.1.20, 18168e62, two identical runs): the leaked to_positive shows as
# 0.33333333333333337 in Y. The kernel's answer is the same lines with 0.3333333333333333.
const _RO_PIN_K = [
    "k0 c[107,48]/1(c[45]/2(c[45]/2(c[101,118,97,108,117,97,116,105,111,110,95,101,114,114,111,114]/1(a[122,101,114,111,95,100,105,118,105,115,111,114]),f0.33333333333333337),f-0.3333333333333333))",
    "k1 c[107,49]/1(c[45]/2(c[45]/2(c[101,118,97,108,117,97,116,105,111,110,95,101,114,114,111,114]/1(a[122,101,114,111,95,100,105,118,105,115,111,114]),f0.33333333333333337),f-0.3333333333333333))"
]
_ro_kernel_k(l::String) = replace(l, "f0.33333333333333337" => "f0.3333333333333333")

# the clause of the predicate `name`/`arity` (its first clause's code)
function _ro_codes(gd, name::String, arity::Int)
    proc = LK.isCurrentProcedure(sym_key(_tls(name)), arity, LK.MODULE_user(gd))
    proc === nothing && return nothing
    return proc.definition.impl_clauses.first_clause.clause.codes
end

@testset "AR1: directed rounding in arithmetic compiled under optimise reads the mode as swipl does" begin
    names = _ro_names()
    expected = String.(readlines(_RO_OUT))
    # not a vacuous agreement: a line per row, the rows' own evidence is in it (a mode that rounds up, one that rounds down, the throw)
    @test length(names) == 26
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test count(l -> occursin("f0.33333333333333337", l), expected) >= 6      # to_positive rounds 1/3.0 up
    # t24/t25 (the flag to_positive, the compound read by A_VAR inside roundtoward): the roundtoward's mode, never the flag's, so no row rounds up
    @test !occursin("f0.33333333333333337", expected[25]) &&
        !occursin("f0.33333333333333337", expected[26])
    @test count(l -> occursin("f-0.33333333333333337", l), expected) >= 2     # to_negative rounds -1/3.0 down
    @test count(l -> occursin(_codes("zero_divisor"), l), expected) == 5      # the five throw rows t15..t19

    # the rows are compiled to the arithmetic instructions (else they would test is/2 as a call, not the instructions)
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, _ = LK.load_file!(gd, ld, _RO_PL)
    @test st === :ok
    for i in 0:14
        cd = _ro_codes(gd, "t$i", 1)
        @test cd !== nothing
        cd === nothing && continue
        @test LK.A_ENTER in cd
    end
    for i in 0:11
        cd = _ro_codes(gd, "t$i", 1)
        cd === nothing && continue
        @test (LK.A_IS in cd) || (LK.A_FIRSTVAR_IS in cd)
    end
    for (name, op) in (("t12", LK.A_EQ), ("t13", LK.A_LT), ("t14", LK.A_GT))
        cd = _ro_codes(gd, name, 1)
        @test cd !== nothing
        cd === nothing && continue
        @test op in cd
    end
    for name in ("t4", "t5")
        cd = _ro_codes(gd, name, 1)
        @test cd !== nothing && (LK.A_ROUNDTOWARDS_A in cd)
    end
    for name in ("rt", "rtv")
        cd = _ro_codes(gd, name, 2)
        @test cd !== nothing && (LK.A_ROUNDTOWARDS_V in cd)
    end
    # t24/t25: a variable bound to a compound is evaluated by A_VAR inside the roundtoward (the walk without the flag's mode)
    let cd = _ro_codes(gd, "t24", 1)
        @test cd !== nothing && (LK.A_ROUNDTOWARDS_A in cd) && (LK.A_VAR in cd)
    end
    let cd = _ro_codes(gd, "rtx", 3)
        @test cd !== nothing && (LK.A_ROUNDTOWARDS_V in cd) && (LK.A_VAR in cd)
    end
    # the rows that follow a leaked mode: the compiled is/2 (A_IS: a head variable; A_FIRSTVAR_IS: a first occurrence) and a comparison
    let cd = _ro_codes(gd, "lead_is", 1)
        @test cd !== nothing && (LK.A_IS in cd)
    end
    let cd = _ro_codes(gd, "lead_fv", 1)
        @test cd !== nothing && (LK.A_FIRSTVAR_IS in cd)
    end
    let cd = _ro_codes(gd, "lead_cmp", 0)
        @test cd !== nothing && (LK.A_GT in cd)
    end
    for i in 0:6
        cd = _ro_codes(gd, "h$i", 0)
        @test cd !== nothing
        cd === nothing && continue
        @test LK.A_ENTER in cd
        @test (LK.A_IS in cd) || (LK.A_FIRSTVAR_IS in cd)
    end

    kl = kernel_lines(_RO_PL, names)
    @test length(kl) == length(expected)
    for i in eachindex(expected)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "AR1 ROUNDING UNDER OPTIMISE DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        sw = swipl_lines(_RO_PL, names)
        @test sw == expected                                       # the .out is swipl's, still
    end
end

@testset "AR1: KNOWN DIFFERENCE: a throw inside a nested roundtoward leaves no mode behind in the kernel (the pin leaks the outer mode)" begin
    # the kernel's exact answer: the pin's lines with the leaked 0.33333333333333337 read 0.3333333333333333 (the entry mode is back)
    @test length(_RO_PIN_K) == 2
    kk = kernel_lines(_RO_PL, ["k0", "k1"])
    @test length(kk) == 3 && kk[1] == "ok"
    for i in 1:2
        @test (i, kk[i + 1]) == (i, _ro_kernel_k(_RO_PIN_K[i]))
        @test kk[i + 1] != _RO_PIN_K[i]
        # the line is the throw row's (the same error and the same Z as the pin), only Y differs
        @test occursin(_codes("zero_divisor"), kk[i + 1]) &&
            occursin("f-0.3333333333333333", kk[i + 1])
    end
    # a row without the leak is the pin's, byte for byte (the single roundtoward row t15 of the .out)
    expected = String.(readlines(_RO_OUT))
    @test occursin("f0.3333333333333333),f-0.3333333333333333", expected[17])
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "AR1 KNOWN-DIFFERENCE ROWS: `swipl` is not on PATH here (the pinned lines in this file were checked against the kernel's)."
    else
        sw = swipl_lines(_RO_PL, ["k0", "k1"])
        @test sw == vcat(["ok"], _RO_PIN_K)                        # swipl's answer, the leak, so this comment cannot go stale
    end
end
