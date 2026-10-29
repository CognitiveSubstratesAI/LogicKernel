# ORIGINAL: the driver of tools/pkgtest_way.sh (audit D-0222, 2026-10-29) — no swipl-devel counterpart.
#
#   julia --project=. --startup-file=no tools/pkgtest_way.jl FILE      # prints `pkgtest-way: PASS <file>`, exit 0
#
# ONE test file as Pkg.test runs it: a fresh module (test/runtests.jl), the unit's closing assertion that the
# shared empty child vector is still empty, and test/inert_testset_guard.jl over the result. The process
# is a fresh one with the standard streams and the environment tools/pkgtest_way.sh gives it (no swipl, stdin
# from /dev/null, stdout and stderr to files).
using Test
# START FROM THE LAST CACHE, as the warm daemon does (tools/warm_session.jl): a plain `using` of a checkout whose cache
# is stale re-precompiles LogicKernel (18 min measured in a fresh worktree); Revise's `stale_load` loads the most recent
# cache and revises it up to the current source. LOGICKERNEL_PKGTEST_WAY_NO_STALE=1 loads normally.
if get(ENV, "LOGICKERNEL_PKGTEST_WAY_NO_STALE", "") != "1"
    try
        using Revise
        Revise.stale_load("LogicKernel"; throw=true)
    catch e
        println(
            stderr,
            "pkgtest-way: stale_load not possible (",
            sprint(showerror, e),
            ") — loading normally"
        )
    end
end
using LogicKernel

Base.include(Main, joinpath(@__DIR__, "..", "test", "inert_testset_guard.jl"))

length(ARGS) == 1 || (println(stderr, "usage: pkgtest_way.jl FILE"); exit(2))
file = abspath(ARGS[1])
isfile(file) || (println(stderr, "pkgtest-way: no such file: $file"); exit(2))

ok = try
    ts = Test.DefaultTestSet("pkgtest-way: " * basename(file); verbose=true)
    Test.@with_testset ts begin
        m = Core.eval(Main, Expr(:module, true, gensym(:LKPkgTestWay), Expr(:block)))
        @testset "$(basename(file))" begin
            Base.include(m, file)
            @test isempty(LogicKernel._no_children(LogicKernel.DefaultTerm))
        end
    end
    Test.finish(ts)                        # throws on any failure or error
    Main.assert_no_inert_testsets(ts)      # throws on a testset that asserted nothing
    true
catch e
    showerror(stderr, e)
    println(stderr)
    false
end
if ok
    println("pkgtest-way: PASS ", basename(file))
    exit(0)
end
exit(1)
