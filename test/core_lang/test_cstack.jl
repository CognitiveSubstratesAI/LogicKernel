# ORIGINAL: the unit test of the pl-cstack.c port (src/os/pl-cstack.jl); upstream prints a real C backtrace, so no swipl row exists.
# test/core_lang/test_cstack.jl — the fallback block of os/pl-cstack.c (`#ifndef BTRACE_DONE`). UNTESTED when written (lane F, edit-only,
# nothing compiled). The expected values are the fallback's own: empty bodies return nothing, the two printers add one message with
# upstream's text, sigCrashHandler and CStackSize are named refusals (NotPortedError, step CSTACK1).
# TERM TYPES PER CHUNK: print_backtrace(_named), sigCrashHandler and CStackSize take the local data or the type; every type in CI.
using Test, LogicKernel
const LK = LogicKernel

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CS = lk_term_type(Union{Int64, Float64, String})

@testset "pl-cstack.c: the fallbacks with an empty body return nothing" begin
    @test LK.save_backtrace("why") === nothing
    @test LK.btrace_destroy(nothing) === nothing
    @test LK.print_c_backtrace("why") === nothing
    @test LK.initBackTrace() === nothing
end

@testset "pl-cstack.c: print_backtrace and print_backtrace_named print the fallback's message" begin
    gd = LK.PL_global_data{_CS}()
    ld = LK.PL_local_data{_CS}(gd)
    n0 = length(ld.messages)
    @test LK.print_backtrace(ld, 1) === nothing
    @test length(ld.messages) == n0 + 1
    @test ld.messages[end][1] == :error
    @test occursin("C-stack dumps are not supported on this platform", String(lk_name(ld.messages[end][2])))
    @test occursin("pl-cstack.c:943", String(lk_name(ld.messages[end][2])))
    @test LK.print_backtrace_named(ld, "why") === nothing
    @test length(ld.messages) == n0 + 2
    @test occursin("pl-cstack.c:949", String(lk_name(ld.messages[end][2])))
    @test occursin("C-stack dumps are not supported on this platform", String(lk_name(ld.messages[end][2])))
end

@testset "pl-cstack.c: sigCrashHandler and CStackSize are named refusals" begin
    gd = LK.PL_global_data{_CS}()
    ld = LK.PL_local_data{_CS}(gd)
    e1 = try
        LK.sigCrashHandler(_CS, 11)
        nothing
    catch e
        e
    end
    @test e1 isa LK.NotPortedError
    @test e1.step == "CSTACK1"
    @test occursin("fatal-signal handler", e1.what)
    e2 = try
        LK.CStackSize(ld)
        nothing
    catch e
        e
    end
    @test e2 isa LK.NotPortedError
    @test e2.step == "CSTACK1"
    @test occursin("C stack", e2.what)
end
