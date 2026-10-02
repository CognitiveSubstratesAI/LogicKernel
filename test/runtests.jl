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
# that degraded to skips — an absent `swipl` under test/oracle/, say — cannot read as green.
using Test
using LogicKernel

include("inert_testset_guard.jl")

const LK_TEST_DIR = @__DIR__
const LK_TEST_FILES = sort!([
    joinpath(dir, f) for (dir, _, files) in walkdir(LK_TEST_DIR) for
    f in files if startswith(f, "test_") && endswith(f, ".jl")
])

# Visibility: what each subsystem folder contributes, zeros included.
for d in sort!(filter(isdir, readdir(LK_TEST_DIR; join=true)))
    n = count(f -> startswith(f, d * "/"), LK_TEST_FILES)
    println("  test/", basename(d), ": ", n, " file(s)")
end

const LK_TS = @testset "LogicKernel" begin
    # Positive control on discovery itself: an empty file list would make every check below vacuous.
    @testset "discovery found the package-level files" begin
        rel = [relpath(f, LK_TEST_DIR) for f in LK_TEST_FILES]
        @test "test_package.jl" in rel
        @test "test_lint_globals.jl" in rel
    end
    for f in LK_TEST_FILES
        rel = relpath(f, LK_TEST_DIR)
        @testset "$rel" begin
            # A `module … end` expression, not `Module(name)`: only the former defines the module's
            # own `include`/`eval`, which a test file calling `include(...)` needs.
            name = Symbol("LKTest_", replace(rel, r"[^A-Za-z0-9]" => "_"))
            m = Core.eval(Main, Expr(:module, true, name, Expr(:block)))
            Base.include(m, f)
        end
    end
end

assert_no_inert_testsets(LK_TS)
