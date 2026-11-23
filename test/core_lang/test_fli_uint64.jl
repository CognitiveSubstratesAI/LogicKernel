# ORIGINAL: PKG2-5 step 1 - pl-error.c pl_get_uint64 / PL_get_uint64_ex and pl-fli.c PL_get_uint64 (src/pl-error.jl, src/pl-fli.jl). NO oracle:
# every expected value is read off the C text of pl-error.c (swipl-devel 18168e62, lines ~1229-1295): the tagged-int branch, the V_INTEGER branch,
# the V_MPZ branch (`mpz_to_uint64` -1 / 0 / 1) and the final type_error(integer, T). Each row names the branch it exercises. The terms are read
# from text with PL_put_term_from_chars. Nothing here has run (written edit-only): BLIND RISKS the lane settles are the reader's answer for the
# integers past Int64 (a BigInt) and the culprit of an unbound variable (PL_error makes it instantiation_error, as PL_get_size_ex's comment says).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _U6_LD = _rdb(Tuple{_R, Union{Nothing, _R}}[]).ld

function _u6_term(ld, text::String)::Int
    t = LK.PL_new_term_ref(ld)
    b = Vector{UInt8}(codeunits(text))
    LK.PL_put_term_from_chars(ld, t, LK.CVT_EXCEPTION | LK.REP_UTF8, b, length(b)) ||
        error("the text does not read: $text")
    return t
end

# The pending error(Formal, _) as (Formal's name, [its arguments: an atomic's text, a compound's name/arity]); clears it.
function _u6_exc(ld)
    ex = LK.PL_exception(ld, 0)
    ex == 0 && return nothing
    f = LK.PL_new_term_ref(ld)
    a = LK.PL_new_term_ref(ld)
    r = nothing
    if LK._PL_get_arg(ld, 1, ex, f)
        na = LK.PL_get_name_arity(ld, f)
        if na !== nothing
            args = String[]
            for i in 1:na[2]
                LK._PL_get_arg(ld, i, f, a)
                txt = LK.PL_get_text(ld, a, LK.CVT_ATOMIC)
                if txt !== nothing
                    push!(args, LK.text_string(txt))
                else
                    nb = LK.PL_get_name_arity(ld, a)
                    push!(
                        args, nb === nothing ? "?" : string(LK.sym_text(nb[1]), "/", nb[2])
                    )
                end
            end
            r = (LK.sym_text(na[1]), args)
        end
    end
    LK.PL_clear_exception(ld)
    return r
end

# (the value, the error) of reading `text` with `PL_get_uint64_ex`, and (the value, the error) with `PL_get_uint64`.
function _u6_read(text::String)
    ld = _U6_LD
    fid = LK.PL_open_foreign_frame(ld)
    t = _u6_term(ld, text)
    vex = LK.PL_get_uint64_ex(ld, t)
    eex = _u6_exc(ld)
    vplain = LK.PL_get_uint64(ld, t)
    eplain = _u6_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (vex, eex, vplain, eplain)
end

@testset "PL_get_uint64(_ex): integers in range (pl-error.c: the tagged-int and V_INTEGER branches, V_MPZ status 0)" begin
    for (txt, v) in (
        ("0", UInt64(0)),                              # tagged int, v >= 0
        ("1", UInt64(1)),
        ("42", UInt64(42)),
        ("9223372036854775807", UInt64(typemax(Int64))),     # V_INTEGER or tagged, the largest
        ("9223372036854775808", UInt64(1) << 63),            # V_MPZ, status 0: first past Int64
        ("18446744073709551615", typemax(UInt64))           # V_MPZ, status 0: the largest uint64
    )
        r = _u6_read(txt)
        @test r == (v, nothing, v, nothing)
        @test r[1] isa UInt64 && r[3] isa UInt64
    end
end

@testset "PL_get_uint64(_ex): negative integers (domain_error(not_less_than_zero, T); plain: fails, no error)" begin
    for txt in (
        "-1", "-5", "-9223372036854775808", "-9223372036854775809", "-18446744073709551616"
    )
        v, e, vp, ep = _u6_read(txt)
        @test v === nothing
        @test e == ("domain_error", ["not_less_than_zero", txt])
        @test vp === nothing
        @test ep === nothing
    end
end

@testset "PL_get_uint64(_ex): past uint64 (V_MPZ status 1: representation_error(uint64_t))" begin
    for txt in ("18446744073709551616", "36893488147419103232", "100000000000000000000000")
        v, e, vp, ep = _u6_read(txt)
        @test v === nothing
        @test e == ("representation_error", ["uint64_t"])
        @test vp === nothing
        @test ep === nothing
    end
end

@testset "PL_get_uint64(_ex): not an integer (type_error(integer, T); an unbound culprit is instantiation_error)" begin
    for (txt, arg) in (("a", "a"), ("1.5", "1.5"), ("f(x)", "f/1"), ("\"s\"", "s"))
        v, e, vp, ep = _u6_read(txt)
        @test v === nothing
        @test e == ("type_error", ["integer", arg])
        @test vp === nothing
        @test ep === nothing
    end
    v, e, vp, ep = _u6_read("X")
    @test v === nothing
    @test e !== nothing && e[1] == "instantiation_error"
    @test vp === nothing && ep === nothing
end
