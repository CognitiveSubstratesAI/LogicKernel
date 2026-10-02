# tools/jet_report.jl — JET static analysis of LogicKernel, on demand.
#
#   julia --project=. tools/jet_report.jl
#
# NOT part of the suite: JET comes from the global env (it is not a dependency), and its first load
# precompiles for minutes. `report_package` is the periodic sweep. As entry points land, add
# `@report_call` probes on CONCRETE argument types below it — narrower, but they analyse the code
# paths that actually run, which is what PathMap's tools/jet_report.jl found the useful half to be.
using JET, LogicKernel

r = JET.report_package(LogicKernel; target_modules=(LogicKernel,))
n = length(JET.get_reports(r))
show(IOContext(stdout, :limit => false), r)
println("\n=== JET report_package(LogicKernel): ", n, " report(s) ===")
