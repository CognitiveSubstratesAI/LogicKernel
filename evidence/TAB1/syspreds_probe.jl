# TAB1-SYSPREDS probe (not a gate test): when does the module '$syspreds' come into being in the kernel?
using Test, LogicKernel
const LK = LogicKernel
include(joinpath(@__DIR__, "..", "..", "test", "term_under_test.jl"))
const _PT = lk_term_type(Union{Int64, Float64, String})
@testset "syspreds probe" begin
    gd = LK.setupProlog(_PT)
    names() = [String(lk_name(m.atom)) for m in gd.modules]
    println("PROBE unbooted modules: ", names(), " n=", length(gd.modules))
    println("PROBE drun_undo1 arity before first run_undo_hooks: ", gd.procedures_drun_undo1.definition.arity)
    ld = LK.PL_local_data{_PT}(gd)
    rc = try
        LK.run_undo_hooks(gd, ld)
    catch e
        "threw " * string(typeof(e))
    end
    println("PROBE run_undo_hooks rc: ", rc)
    println("PROBE modules after first run_undo_hooks: ", names(), " n=", length(gd.modules))
    println("PROBE drun_undo1 arity after: ", gd.procedures_drun_undo1.definition.arity)
    @test true
end
