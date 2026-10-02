# ORIGINAL: the module-state lint and its fixture; no swipl-devel counterpart.
# test/test_lint_globals.jl — the module-state lint, run on LogicKernel AND proven able to fail.
#
# A lint that cannot fail reports exactly what a passing one does. So before trusting its verdict on
# LogicKernel, this file runs it over a FIXTURE module that plants every violation the lint exists to
# catch next to clean look-alikes, and asserts the reported set is EXACTLY the planted set — every
# bad binding caught, no clean one flagged. That is a proof at VERDICT level, not by message.
using Test, LogicKernel

include(joinpath(@__DIR__, "..", "tools", "lint_globals.jl"))

module LintFixture
# ── planted violations ──
const D = Dict{Int, Int}()
const S = Set{Int}()                      # immutable struct around a Dict: caught by recursion
const V = Int[]
const R = Ref(0)
const NESTED = (1, Int[])                 # immutable tuple holding a mutable vector
const CLOSURE = let r = Ref(0)            # a closure that captured a Ref
    () -> r[]
end
x = 1                                     # non-const global
g = nothing                               # non-const, even though the VALUE is immutable
function late!()                          # `global` inside a function: Julia 1.13 declares the
    global LATE = Dict{Int, Int}()        # binding at DEFINITION, so it is caught even though
    return nothing                        # `late!` is never called (measured 2026-10-02)
end
const ALLOWED = Dict{Symbol, Int}()       # allowlisted below, so NOT reported
module Sub
    const INNER = Dict{String, Int}()     # caught in a submodule
end
# ── clean look-alikes ──
const N = 3
const NAME = "name"
const SYM = :sym
const TUP = (1, :a, "b", 2.0)
@enum Colour RED GREEN
struct Point
    a::Int
end
const ORIGIN = Point(0)
abstract type Shape end
"a documented function — the docstring creates Julia's own `#…`/META bindings"
f(y) = y + 1
"a documented CONSTANT — leaves a `#N#val` temporary holding a frozen copy: exempt"
const DOCUMENTED = 3
"a documented MUTABLE constant — flagged itself, AND its `#N#val` temporary is flagged"
const DOC_MUT = Int[]
end

const EXPECTED = Set([
    "LintFixture.D",
    "LintFixture.S",
    "LintFixture.V",
    "LintFixture.R",
    "LintFixture.NESTED",
    "LintFixture.CLOSURE",
    "LintFixture.x",
    "LintFixture.g",
    "LintFixture.LATE",
    "Sub.INNER",
    "LintFixture.DOC_MUT"
])
_lint_names(vs) = Set(first(split(v, ": ")) for v in vs)

@testset "lint_globals" begin
    @testset "LogicKernel has no module-level mutable state" begin
        r = lint_globals(LogicKernel)
        @test r.inspected > 0                       # a scan of nothing proves nothing
        isempty(r.violations) || foreach(v -> println(stderr, "  lint: ", v), r.violations)
        @test isempty(r.violations)
    end

    @testset "fixture: reports exactly the planted violations" begin
        r = lint_globals(
            LintFixture; allow=("LintFixture.ALLOWED" => "fixture: allowlist works",)
        )
        @test r.inspected > length(EXPECTED)
        got = _lint_names(r.violations)
        gen = Set(n for n in got if startswith(n, "LintFixture.#"))   # generated names: N varies
        @test setdiff(got, gen) == EXPECTED     # every bad one caught, no clean one flagged
        @test length(gen) == 1                  # DOC_MUT's temporary; DOCUMENTED's frozen one is not
    end

    @testset "fixture: without the allowlist the allowed binding IS reported" begin
        r = lint_globals(LintFixture; allow=())
        @test "LintFixture.ALLOWED" in _lint_names(r.violations)
    end

    @testset "allowlist: a stale entry is a violation, an empty reason an error" begin
        r = lint_globals(LintFixture; allow=("LintFixture.NO_SUCH" => "stale",))
        @test any(v -> startswith(v, "LintFixture.NO_SUCH: STALE"), r.violations)
        @test_throws ErrorException lint_globals(
            LintFixture; allow=("LintFixture.D" => " ",)
        )
    end
end
