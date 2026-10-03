# ORIGINAL: the suite driver Julia's Pkg.test requires (swipl-devel's counterpart is tests/test.pl, a Prolog driver).
# test/runtests.jl — LogicKernel's suite.
#
# DISCOVERY, NOT A LIST. Every `test_*.jl` anywhere under `test/` runs; nothing has to be registered
# here, so a new subsystem's tests cannot be written and then silently never run. Other `.jl` files
# (helpers, fixtures, the conformance suite's library files) are NOT run on their own.
#
# ONE FRESH MODULE PER FILE. A suite that `include`s every file into one module lets two files'
# helpers collide by name — the later definition silently replaces the earlier, and a file passes
# alone and fails in the suite — a failure that is expensive to diagnose because every theory about
# the code is wrong; the cause is the suite's shape. Each file therefore starts with its own
# `using Test, LogicKernel` and owns its names.
#
# THE INERT GUARD runs last: a leaf testset that passed zero assertions fails the suite, so a test
# that degraded to skips — an absent `swipl` for the compare/3 differential, say — cannot read as green.
#
# TERM-GENERIC FILES RUN ONCE PER TERM IMPLEMENTATION. A file that includes test/term_under_test.jl
# reaches the kernel only through the term interface, so it runs on the reference type AND on the
# deliberately different second implementation (`LK_TERM_IMPLS`); the second run's test set is
# named `<file> [alt]`.
using Test
using LogicKernel

include("inert_testset_guard.jl")
include("term_under_test.jl")         # LK_TERM_IMPLS — the one list of implementations

const LK_TEST_DIR = @__DIR__
const LK_TEST_FILES = sort!([
    joinpath(dir, f) for (dir, _, files) in walkdir(LK_TEST_DIR) for
    f in files if startswith(f, "test_") && endswith(f, ".jl")
])
const LK_TERM_GENERIC_RX = r"^include\(joinpath\(@__DIR__, \"\.\.\", \"term_under_test\.jl\"\)\)"m
lk_term_generic(f::String)::Bool = occursin(LK_TERM_GENERIC_RX, read(f, String))

# Visibility: what each subsystem folder contributes, zeros included.
for d in sort!(filter(isdir, readdir(LK_TEST_DIR; join=true)))
    n = count(f -> startswith(f, d * "/"), LK_TEST_FILES)
    println("  test/", basename(d), ": ", n, " file(s)")
end

# THE ROOT TEST SET IS OPENED BY HAND, not with `@testset`, so its results can be written as JUnit
# XML (Codecov Test Analytics) EVEN WHEN SOMETHING FAILED — a top-level `@testset` throws before
# anyone can read its tree. `Test.finish` below then prints the summary and throws exactly as before.
include("junit_report.jl")
const LK_JUNIT = get(ENV, "LOGICKERNEL_JUNIT", "")
const LK_TS = Test.DefaultTestSet("LogicKernel")
# Julia 1.13's test-set stack is a ScopedValue: `Test.@with_testset` (there is no push_testset).
Test.@with_testset LK_TS begin
    # Positive control on discovery itself: an empty file list would make every check below vacuous.
    @testset "discovery found the package-level files" begin
        rel = [relpath(f, LK_TEST_DIR) for f in LK_TEST_FILES]
        @test "test_package.jl" in rel
        @test "test_lint_globals.jl" in rel
    end
    # …and on the term-generic files: the conformance suite itself must be one of them, or the
    # second implementation is never checked against it.
    @testset "discovery found the term-generic files" begin
        generic = [relpath(f, LK_TEST_DIR) for f in LK_TEST_FILES if lk_term_generic(f)]
        @test "core_lang/test_term_interface.jl" in generic
        @test "core_lang/test_unify.jl" in generic
        @test length(generic) >= 19
        @test length(LK_TERM_IMPLS) >= 2
    end
    for f in LK_TEST_FILES
        rel = relpath(f, LK_TEST_DIR)
        for impl in (lk_term_generic(f) ? LK_TERM_IMPLS : ("",))
            label = impl in ("", "reference") ? rel : "$rel [$impl]"
            @testset "$label" begin
                # A `module … end` expression, not `Module(name)`: only the former defines the
                # module's own `include`/`eval`, which a test file calling `include(...)` needs.
                name = Symbol("LKTest_", replace(label, r"[^A-Za-z0-9]" => "_"))
                m = Core.eval(Main, Expr(:module, true, name, Expr(:block)))
                if isempty(impl)
                    Base.include(m, f)
                else
                    withenv(() -> Base.include(m, f), "LOGICKERNEL_TERM" => impl)
                end
            end
        end
    end
    # …and the `[alt]` runs really ran the second implementation: its intern table fills only when
    # an `AltTerm` symbol is built, so a selector that fell back to `Term{G}` — running the
    # reference twice, green — leaves it empty.
    @testset "the second implementation was exercised" begin
        @test length(Main.LKAltTerm._NAMES) > 0
    end
end

isempty(LK_JUNIT) || println("  JUnit report: ", write_junit(LK_TS, LK_JUNIT))
Test.finish(LK_TS)                    # prints the summary; throws if anything failed or errored
assert_no_inert_testsets(LK_TS)
