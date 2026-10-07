# ORIGINAL: no-Any and concrete-field gates; no swipl-devel counterpart.
# test/test_type_discipline.jl — no `Any` in src, no abstractly typed struct field. Runs EVERYWHERE
# (no external tools needed), so CI's plain test job enforces it too. Each rule is first run on a
# fixture that plants the defect, so a gate that sees nothing cannot pass by default.
using Test, LogicKernel

include(joinpath(@__DIR__, "static_analysis_gates.jl"))

# Fixtures are built from STRINGS: the defects they plant must not be code in this file.
const _TD_ANY_FIXTURE = """
\"\"\"A docstring that says Any is fine to mention.\"\"\"
k(x) = x
f(x::Any) = x                 # flagged (line 3)
const V = Vector{Any}()       # flagged (line 4)
g(x) = x                      # Any in a comment is not code
h(x) = Base.Any               # flagged, qualified (line 6)
"""

const _TD_FIELD_FIXTURE = """
module TDFieldFixture
struct Bad1; a::Any; end
struct Bad2; b::Real; end
struct Bad3; c::Vector; end
struct Bad4; d::Union{Int, Float64, String, Symbol, Char}; end
struct Good; e::Int; f::Union{Nothing, Int}; g::Vector{Int}; h::Union{Int, Float64, String}; end
struct Param{T}; x::T; y::Vector{T}; z::Union{Nothing, T}; end
end
"""

const _TD_UNCHECKED_FIXTURE = """
\"\"\"Mentions @inbounds and unsafe_load in a docstring: not code.\"\"\"
f(v, i) = @inbounds v[i]                          # line 2
g(p) = unsafe_load(p)                             # line 3
h(v) = (Base.@propagate_inbounds; v)              # line 4
k(x) = x  # @inbounds in a comment
m(d, s, n) = unsafe_copyto!(d, s, n)              # line 6
c() = ccall(:jl_gc_collect, Cvoid, ())            # line 7
"""

# The term-type rule's fixture (R1c): three methods build terms on a `T` bound only by term
# arguments (a bare `T`, a `Union`, a `Tuple`); four bind it exactly or build nothing.
const _TD_TERMTYPE_FIXTURE = """
bad1(a::T) where {T} = mk_sym(T, :x)
bad2(a::Union{Nothing, T}, b::Int)::Int where {T} = (T[]; 1)
good1(ld::PL_local_data{T}, a::T) where {T} = mk_sym(T, :x)
good2(::Type{T}, a::T) where {T} = mk_sym(T, :x)
good3(a::T) where {T} = sym_key(a)
function bad3(op::Tuple{T, Int})::T where {T}
    return mk_nil(T)
end
good4(v::Vector{T}, a::T)::T where {T} = mk_expr(T, T[a])
"""

# The ALLOWLIST of unchecked constructs in src/ (user, 2026-10-04): `"file construct" => (count,
# reason)`. A new one fails the rule until it is listed here with a measured reason; a listed one
# that is gone fails it too — so the list cannot go stale.
const _TD_UNCHECKED_ALLOWED = Dict(
    "pl-termhash.jl @inbounds" => (
        1,
        "sha1_hf!: the SHA-1 message schedule; `w` is the 16-word `wbuf` and every index is " *
        "`& 15` or below 16 (pl-termhash.c `hf`)"
    ),
    "pl-termhash.jl unsafe_copyto!" => (
        1,
        "_sha1_memcpy!: upstream's memcpy into `wbuf`'s bytes (4 ns against 15 ns, measured); " *
        "its byte range is CHECKED first, so it cannot write outside `wbuf` or read outside `data`"
    ),
    "pl-read.jl ccall" => (
        1,
        "_strtod (R1c): the C library's strtod, as upstream's ascii_to_double calls it, for its " *
        "rounding and its errno (ERANGE drives the float_overflow/underflow rules); the text is " *
        "copied into a 0-terminated vector held by GC.@preserve, so strtod reads only that copy"
    )
)

@testset "type discipline" begin
    @testset "a method that builds terms binds T from the term type, not from a term (R1c)" begin
        hits = term_type_from_term_arg_uses(joinpath(pkgdir(LogicKernel), "src"))
        isempty(hits) || foreach(
            h -> println(stderr, "  T bound only by a term argument: src/", h), hits
        )
        @test isempty(hits)
        fx = mktempdir() do d
            write(joinpath(d, "fixture.jl"), _TD_TERMTYPE_FIXTURE)
            term_type_from_term_arg_uses(d)
        end
        @test fx == ["fixture.jl:1 bad1", "fixture.jl:2 bad2", "fixture.jl:6 bad3"]
    end

    @testset "no Any in LogicKernel's src" begin
        hits = any_uses(joinpath(pkgdir(LogicKernel), "src"))
        isempty(hits) || foreach(h -> println(stderr, "  Any at src/", h), hits)
        @test isempty(hits)
    end

    @testset "no abstractly typed struct field in LogicKernel" begin
        bad = nonconcrete_fields(LogicKernel)
        isempty(bad) || foreach(b -> println(stderr, "  abstract field: ", b), bad)
        @test isempty(bad)
    end

    @testset "no unchecked memory access in src beyond the allowlist" begin
        found = Dict{String, Int}()
        for u in unchecked_uses(joinpath(pkgdir(LogicKernel), "src"))
            file_line, construct = split(u, ' '; limit=2)
            k = first(split(file_line, ':')) * " " * construct
            found[k] = get(found, k, 0) + 1
        end
        want = Dict(k => v[1] for (k, v) in _TD_UNCHECKED_ALLOWED)
        for k in sort!(collect(setdiff(keys(found), keys(want))))
            println(
                stderr, "  unchecked access NOT on the allowlist: ", k, " (", found[k], ")"
            )
        end
        @test found == want
        @test all(v -> length(v[2]) > 20, values(_TD_UNCHECKED_ALLOWED))   # every entry says why
    end

    @testset "the allowlisted unsafe_copyto! checks its own range" begin
        ctx, data = LogicKernel.sha1_ctx(), collect(UInt8(1):UInt8(80))
        @test LogicKernel._sha1_memcpy!(ctx, 60, data, 0, 4) === nothing      # exactly to the end
        @test_throws BoundsError LogicKernel._sha1_memcpy!(ctx, 60, data, 0, 8) # past wbuf
        @test_throws BoundsError LogicKernel._sha1_memcpy!(ctx, 0, data, 76, 8) # past data
        @test_throws BoundsError LogicKernel._sha1_memcpy!(ctx, -1, data, 0, 4)
    end

    @testset "fixture: the unchecked scan finds exactly the planted uses" begin
        mktempdir() do d
            write(joinpath(d, "fx.jl"), _TD_UNCHECKED_FIXTURE)
            @test unchecked_uses(d) == [
                "fx.jl:2 @inbounds", "fx.jl:3 unsafe_load", "fx.jl:4 @propagate_inbounds",
                "fx.jl:6 unsafe_copyto!", "fx.jl:7 ccall"
            ]
        end
    end

    @testset "fixture: the Any scan finds exactly the planted uses" begin
        mktempdir() do d
            write(joinpath(d, "fx.jl"), _TD_ANY_FIXTURE)
            @test any_uses(d) == ["fx.jl:3", "fx.jl:4", "fx.jl:6"]
        end
    end

    @testset "fixture: the field check finds exactly the planted fields" begin
        fx = Base.include_string(Module(:TDHost), _TD_FIELD_FIXTURE)
        @test nonconcrete_fields(fx) == [
            "Bad1.a::Any", "Bad2.b::Real", "Bad3.c::Vector",
            "Bad4.d::Union{Char, Float64, Int64, String, Symbol}"
        ]
    end
end
