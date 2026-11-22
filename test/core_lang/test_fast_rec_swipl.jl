# ORIGINAL: a differential of fast_term_serialized/2 (pl-rec.c) against swipl at the pin; test/core_lang/test_dwim_swipl.jl's harness
# test/core_lang/test_fast_rec_swipl.jl — fast_term_serialized/2, through a PROGRAM (the pattern of
# test/core_lang/test_dwim_swipl.jl): test_fast_rec_swipl.pl holds the rows, each a predicate `tN(R)` / `rN(R)`; the kernel
# consults the program and enumerates every solution of every row, and its lines are compared with test_fast_rec_swipl.out —
# swipl 10.1.20's own, printed by the driver below (`ok`, then one line per row: its name and every solution). When `swipl` is
# on PATH the .out is checked against a live run as well, so it cannot go stale.
# Rows t0-t66 are the encoder (term to string: the bytes of the record, as the code list R). Rows t0-t6 are ALSO pinned as
# literal byte vectors below, so the bytes of the layouts are in this file and not only in the .out. Rows r0-r12 are the decoder
# side (string to term): each against the .out (FAST-2c, the decoder), one fresh kernel run per row.
# One row stays `@test_broken` among the encoder's, with its owner:
#   t30       a rational at the root: pending a named DIVERGES (audit ruling).
# (t18, t34, an integer with |N| >= 2^56 inside a compound, are real rows: addExternalIndirect writes PL_REC_MPZ for it, as the pin.)
# No row carries a size, an offset, a variable number or a length in 256..383, 512..639 ...: rows for those ranges follow the
# land of wip/rec-sizeint.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
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

const _FR_PL = joinpath(@__DIR__, "test_fast_rec_swipl.pl")
const _FR_OUT = joinpath(@__DIR__, "test_fast_rec_swipl.out")

# the rows' names, in the order of the program: t0-t66 (the encoder), then r0-r12 (the decoder side)
_fr_names() =
    unique([String(m[1]) for m in eachmatch(r"^([tr]\d+)\(R\) :-"m, read(_FR_PL, String))])

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(
    ::Type{T}, path::String, names::Vector{String}
)::Vector{String} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::T)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        notported = false
        while (n += 1) <= 100
            rc = try
                LK.PL_next_solution(gd, ld, qid)
            catch e
                e isa LK.NotPortedError || rethrow()
                notported = true
                break
            end
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(T, T[_tls(T, name), lk_answers(ld, (a:a)...)...]))
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
        if notported
            push!(out, "$name notported")    # the run's ld is thrown away: the query stays open
            return out
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
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
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the line of the row `name` in `lines` (every line starts with its row's name and a space), or a marker when there is none
function _fr_row(lines::Vector{String}, name::String)::String
    i = findfirst(l -> startswith(l, name * " "), lines)
    return i === nothing ? "(no line of $name)" : lines[i]
end

# ONE extractor for both sides: the integers of a line, in order (a record's bytes are the code list `R` of a row)
_fr_bytes(line::String)::Vector{Int} = [parse(Int, m[1]) for m in eachmatch(r"i(-?\d+)", line)]

# the pinned layouts: the bytes swipl 10.1.20 writes (rows t0-t6 of the program), as literals
const _FR_PINS = Dict(
    # f("abc"): a Latin-1 string, its storage tag B (66) then the characters
    "t0" => [114, 11, 5, 13, 1, 11, 1, 102, 6, 4, 66, 97, 98, 99],
    # f("αβ"): a wide string, W (87) 0 0 0 then 4 little-endian bytes a character
    "t1" => [114, 19, 6, 13, 1, 11, 1, 102, 6, 12, 87, 0, 0, 0, 177, 3, 0, 0, 178, 3, 0, 0],
    # f("é"): Latin-1, B then the one byte
    "t2" => [114, 9, 5, 13, 1, 11, 1, 102, 6, 2, 66, 233],
    # f(1r3, X, X) with X = g(a): the mpq's cells put the shared subterm at offset 10
    "t3" => [
        114, 26, 12, 13, 3, 11, 1, 102, 19, 0, 0, 0, 1, 0, 0, 0, 1, 1, 3, 13, 1, 11, 1, 103, 11, 1, 97,
        17, 10
    ],
    # f(10^20, X, X): the mpz's cells (2 limbs) put it at offset 9
    "t4" => [
        114, 29, 11, 13, 3, 11, 1, 102, 18, 0, 0, 0, 9, 5, 107, 199, 94, 45, 99, 16, 0, 0, 13, 1, 11, 1,
        103, 11, 1, 97, 17, 9
    ],
    # f(1.5, X, X): the float's cells put it at offset 7
    "t5" => [
        114, 24, 9, 13, 3, 11, 1, 102, 14, 0, 0, 0, 0, 0, 0, 248, 63, 13, 1, 11, 1, 103, 11, 1, 97, 17, 7
    ],
    # f("abc", X, X): the string's cells put it at offset 7
    "t6" => [
        114, 21, 9, 13, 3, 11, 1, 102, 6, 4, 66, 97, 98, 99, 13, 1, 11, 1, 103, 11, 1, 97, 17, 7
    ]
)

# encoder rows the kernel answers differently from the pin today, each `@test_broken` with its owner
const _FR_BROKEN_RULING = ["t30"]             # a rational at the root: pending a named DIVERGES (audit ruling)

@testset "FAST1: fast_term_serialized/2 term to string == swipl's bytes (the .out), through a program" begin
    names = _fr_names()
    tnames = ["t$i" for i in 0:66]
    rnames = ["r$i" for i in 0:12]
    expected = String.(readlines(_FR_OUT))
    # not a vacuous agreement: the .out has a line per row, each with at least one solution
    @test length(names) == 80 && names == vcat(tnames, rnames)
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(
        i -> startswith(expected[i + 1], names[i] * " ") && length(expected[i + 1]) > length(names[i]) + 1,
        eachindex(names)
    )
    # the pins: the literal bytes equal swipl's (the .out) through one extractor, and every pin is a real record
    @test sort(collect(keys(_FR_PINS))) == ["t$i" for i in 0:6]
    for (n, bytes) in _FR_PINS
        @test _fr_bytes(_fr_row(expected, n)) == bytes
        @test length(bytes) >= 12 && bytes[1] == 114                     # the header byte of a ground record
    end
    # the broken rows are rows of the program
    @test all(n -> n in tnames, _FR_BROKEN_RULING)

    # ---- the encoder: one kernel run over t0-t66, one line per row against the .out ----
    kl = kernel_lines(_TL, _FR_PL, tnames)
    @test length(kl) == length(tnames) + 1 && kl[1] == "ok"
    for (n, bytes) in _FR_PINS
        @test _fr_bytes(_fr_row(kl, n)) == bytes
    end
    for n in tnames
        n in _FR_BROKEN_RULING && continue
        @test (n, _fr_row(kl, n)) == (n, _fr_row(expected, n))
    end
    for n in _FR_BROKEN_RULING                                          # pending a named DIVERGES (audit ruling)
        @test_broken (n, _fr_row(kl, n)) == (n, _fr_row(expected, n))
    end

    # ---- the decoder side: one FRESH kernel run per row (a refusal by name ends a run), against the .out ----
    for n in rnames
        rl = kernel_lines(_TL, _FR_PL, [n])
        @test rl[1] == "ok"
        got = _fr_row(rl, n)
        want = _fr_row(expected, n)
        @test !endswith(got, " notported") && !endswith(got, " undefined")   # not the named stop, not a missing row
        @test got == want                                               # the decoder: the row's answer, as swipl's
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "FAST1 DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_FR_PL, names) == expected                    # the .out is swipl's, still
    end
end
