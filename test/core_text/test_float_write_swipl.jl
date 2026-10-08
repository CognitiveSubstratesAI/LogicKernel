# ORIGINAL: R1e's float gate — format_float (src/pl-write.jl: Ryu's shortest digits in pl-write.c's layout) against swipl 10.1.16 (dtoa), on hundreds of thousands of floats.
# test/core_text/test_float_write_swipl.jl — the float writer's gate (user, 2026-10-07/08: "the
# LARGE float differential … the gate that matters most; that's where Ryu and dtoa could differ"):
#   * THE TEXT: every float written by the kernel (`format_float(f, 3, 'e')`, what write/1,
#     writeq/1, term_to_atom/2 write) is swipl's text of the same float, character for character —
#     on 400,000 random bit patterns (every finite float equally likely by its bits: subnormals,
#     huge and tiny exponents), 100,000 random "short" decimals (few significant digits, where the
#     shortest-digits choice is tightest), and the edge cases: ±0.0, the smallest subnormal and the
#     largest subnormal, the smallest normal, the largest finite, every power of ten and of two in
#     range, 2^53 and its neighbours, 1e22 and 1e23, 0.1 0.2 0.3, the integers whose digits fill
#     17 places; ±Inf and NaN texts read then written (a NaN term is canonical: pl-alloc.c
#     put_double). The float crosses to swipl as Julia's shortest text,
#     which reads back to the same bits (asserted), and swipl writes it with write/1;
#   * THE ROUND TRIP: the kernel reads its own text back to the same bits (a NaN: the canonical
#     one; format_float's payload text, as writeNaN writes it, checked at the function);
#   * THE CALLERS: write/1 of a float through PL_write_term, term_to_atom/2 both ways (a float for
#     the atom: pl-text.c's CVT_FLOAT text), `- 1.0` and `- -0.0`, atom_number/2.
using Test, LogicKernel, Random
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _FW = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_fws(x) = lk_sym(_FW, Symbol(x))
_fw_var() = mk_var(_FW, LK.fresh_var_keys!(1))

const _FW_SWIPL = Sys.which("swipl")
const _FW_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"
const _FW_GD = LK.PL_global_data{_FW}()
const _FW_LD = LK.PL_local_data{_FW}()

"Run `name` on `args` through the query API: `(rc, answers)`."
function _fw_call(name::String, args::Vector{_FW})
    gd, ld = _FW_GD, _FW_LD
    proc = LK.isCurrentProcedure(sym_key(_fws(name)), length(args), LK.MODULE_system(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    for (i, x) in enumerate(args)
        ld.slots[a + i] = x
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    ans = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        [LK.resolve_term(ld, ld.slots[a + i]) for i in 1:length(args)]
    else
        _FW[]
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return (rc, ans)
end

# The floats: edge cases, then random bits, then short decimals (seeded).
function _fw_floats()::Vector{Float64}
    fs = Float64[0.0, -0.0, 5.0e-324, -5.0e-324, prevfloat(floatmin(Float64)),
        floatmin(Float64),
        floatmax(Float64), -floatmax(Float64), 1.0, -1.0, 0.1, 0.2, 0.3, 1 / 3, 2 / 3,
        1.0e22, 1.0e23,
        9.007199254740992e15, prevfloat(9.007199254740992e15),
        nextfloat(9.007199254740992e15),
        123456789012345678.0, 12345678901234567890.0, 0.001, 0.0001, 1.0e-5, 100.0, 1000.0,
        1.5e300, 2.5e-7, 4.35, 0.3e-307, 1.7e-308]
    for k in -323:308                               # powers of ten, as the literals read them
        push!(fs, parse(Float64, "1.0e$k"))
    end
    for k in -1074:1023                             # powers of two
        push!(fs, ldexp(1.0, k))
    end
    for d in 1:17                                   # integers that fill d places
        push!(fs, parse(Float64, "9"^d), parse(Float64, "1" * "0"^(d - 1) * "1"))
    end
    rng = MersenneTwister(20261008)
    n = 0
    while n < 400_000                               # random bit patterns, finite only
        f = reinterpret(Float64, rand(rng, UInt64))
        isfinite(f) || continue
        push!(fs, f)
        n += 1
    end
    for _ in 1:100_000                              # short decimals: d digits, exponent e
        d = rand(rng, 1:17)
        m = rand(rng, 1:(10 ^ min(d, 18) - 1))
        e = rand(rng, -330:310)
        x = tryparse(Float64, string(m) * "e" * string(e))   # (overflows to Inf: dropped below)
        x === nothing || push!(fs, x)
    end
    return filter(isfinite, fs)
end

# The swipl program that reads each line's float and writes it with write/1.
const _FW_DRIVER = raw"""
loop(In) :- read_term(In, X, []), ( X == end_of_file -> true ; write(X), nl, loop(In) ).
"""

"swipl's write/1 text of each float, the float read from Julia's shortest text."
function _fw_swipl(texts::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "floats.txt")
        open(f, "w") do io
            for t in texts
                println(io, t, ".")
            end
        end
        p = joinpath(d, "w.pl")
        # allow-docstring-interp: not a docstring — this Prolog program interpolates the file path
        write(
            p,
            _FW_DRIVER * ":- initialization((open('" * f *
            "', read, In), loop(In), close(In), halt)).\n"
        )
        read(pipeline(`swipl -q $p`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'))
end

if _FW_SWIPL !== nothing
    @testset "format_float == swipl's write/1, on half a million floats" begin
        fs = _fw_floats()
        texts = [repr(f) for f in fs]
        @test all(i -> parse(Float64, texts[i]) === fs[i], eachindex(fs))   # the crossing is exact
        ours = [LK.format_float(f, 3, 'e') for f in fs]
        theirs = _fw_swipl(texts)
        @test length(theirs) == length(fs)
        bad = [i for i in 1:min(length(ours), length(theirs)) if ours[i] != theirs[i]]
        for i in bad[1:min(end, 15)]
            println(stderr, "  DIVERGES: ", repr(fs[i]), " bits ",
                string(reinterpret(UInt64, fs[i]); base=16),
                "\n    kernel ", ours[i], "\n    swipl  ", theirs[i])
        end
        @test isempty(bad)
        println(stderr, "  floats compared: ", length(fs), ", diverging: ", length(bad))
    end

    @testset "infinities and NaNs, read then written: swipl's texts (a NaN term is canonical)" begin
        # every NaN a term holds is SWI's canonical 1.5NaN (pl-alloc.c put_double: "SWI-Prolog
        # canonical 1.5NaN"), so a payload written in a NaN's text does not survive a READ, in
        # swipl or the kernel: each text below reads as 1.5NaN, Inf as 1.0Inf
        texts = ["1.0Inf", "-1.0Inf", "1.5NaN", "1.75NaN", "1.5000000000000002NaN",
            "1.9999999999999998NaN", "-1.5NaN", "1.0e+22", "-0.0"]
        ours = String[]
        for t in texts
            rc, ans = _fw_call("term_to_atom", _FW[_fw_var(), _fws(t)])
            rc2, ans2 = _fw_call("term_to_atom", _FW[ans[1], _fw_var()])
            push!(ours, sym_text(ans2[2]))
        end
        theirs = _fw_swipl(texts)
        ours == theirs ||
            println(stderr, "  specials: kernel ", ours, "\n            swipl  ", theirs)
        @test ours == theirs
        @test ours[3:7] == fill("1.5NaN", 5) && ours[1:2] == ["1.0Inf", "-1.0Inf"]
    end
elseif _FW_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the float differential would be skipped"
    )
else
    @info "FLOAT DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "float differential skipped only where it is not required" begin
        @test !_FW_SWIPL_REQUIRED
    end
end

@testset "the kernel reads its own float text back, bit for bit" begin
    fs = _fw_floats()
    rng = MersenneTwister(7)
    sample = vcat(fs[1:2500], fs[rand(rng, 2501:length(fs), 20_000)])
    bad = 0
    for f in sample
        rc, ans = _fw_call("term_to_atom", _FW[_fw_var(), _fws(LK.format_float(f, 3, 'e'))])
        ok = rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        g = ok ? lk_value(ans[1]) : nothing
        (g isa Float64 && reinterpret(UInt64, g) == reinterpret(UInt64, f)) || (bad += 1)
    end
    @test bad == 0
    # format_float writes a NaN's payload (writeNaN: its float with the exponent replaced) — reached
    # only by a host value, as a NaN term is canonical; read back, the text is the canonical NaN
    for (p, text) in ((0x0, "1.5NaN"), (0x1, "1.5000000000000002NaN"),
        (0x4000000000000, "1.75NaN"), (0x123456789abcd, "1.571111111111111NaN"))
        f = reinterpret(Float64, 0x7ff8000000000000 | p)
        @test LK.format_float(f, 3, 'e') == text
        rc, ans = _fw_call("term_to_atom", _FW[_fw_var(), _fws(text)])
        @test reinterpret(UInt64, Float64(lk_value(ans[1]))) ==
            reinterpret(UInt64, LK.PL_nan())
    end
end

@testset "the callers: the writer, term_to_atom/2, atom_number/2" begin
    w(t, flags) = begin
        fid = LK.PL_open_foreign_frame(_FW_LD)
        r = LK.PL_new_term_refs(_FW_LD, 1)
        _FW_LD.slots[r + 1] = t
        bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
        sizep = Ref(0)
        s = LK.Sopenmem(bufp, sizep, "w")
        LK.PL_write_term(_FW_GD, _FW_LD, s, r, 1200, flags)
        LK.Sclose(s)
        LK.PL_close_foreign_frame(_FW_LD, fid)
        sizep[] == 0 ? "" : String(bufp[][1:sizep[]])
    end
    q = LK.PL_WRT_QUOTED | LK.PL_WRT_NUMBERVARS
    @test w(lk_gnd(_FW, 1.0e22), q) == "1.0e+22"
    @test w(mk_expr(_FW, _FW[_fws("-"), lk_gnd(_FW, 1.5)]), q) == "- 1.5"
    @test w(mk_expr(_FW, _FW[_fws("-"), lk_gnd(_FW, -1.5)]), q) == "- -1.5"
    @test w(mk_expr(_FW, _FW[_fws("f"), lk_gnd(_FW, -0.0), lk_gnd(_FW, Inf)]), q) ==
        "f(-0.0,1.0Inf)"
    @test w(mk_expr(_FW, _FW[_fws("-"), _fws("a"), lk_gnd(_FW, -2.5e-7)]), q) ==
        "a- -2.5e-07"
    rc, ans = _fw_call("term_to_atom", _FW[lk_gnd(_FW, 0.1), _fw_var()])
    @test sym_text(ans[2]) == "0.1"
    rc, ans = _fw_call("atom_number", _FW[_fw_var(), lk_gnd(_FW, 1.0e-5)])
    @test sym_text(ans[1]) == "1.0e-05"
    @test w(mk_expr(_FW, _FW[_fws("-"), lk_gnd(_FW, -0.0)]), q) == "- -0.0"   # swipl: `- -0.0`
    # after a symbol char, a NEGATIVE float is separated — by its sign bit, so -0.0 too (swipl)
    @test w(mk_expr(_FW, _FW[_fws("-"), _fws("a"), lk_gnd(_FW, -0.0)]), q) == "a- -0.0"
    @test w(mk_expr(_FW, _FW[_fws("-"), _fws("a"), lk_gnd(_FW, 0.0)]), q) == "a-0.0"
    # term_to_atom/2 with a float for the atom: its text (pl-text.c, CVT_FLOAT) read back, as swipl
    for f in (Inf, -Inf, NaN, 1.0e22, -0.0, 2.5e-7)
        rc, ans = _fw_call("term_to_atom", _FW[_fw_var(), lk_gnd(_FW, f)])
        g = isempty(ans) ? nothing : lk_value(ans[1])
        @test g isa Float64 &&
            reinterpret(UInt64, g) == reinterpret(UInt64, isnan(f) ? LK.PL_nan() : f)
    end
end
