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

@testset "type discipline" begin
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
