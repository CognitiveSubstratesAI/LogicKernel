#!/usr/bin/env julia
# tools/repl.jl — development REPL: Revise, then LogicKernel.
#
#   julia --project=. -i tools/repl.jl
#
# Revise, JET, JuliaFormatter, BenchmarkTools and the other dev tools are NOT dependencies of this
# package. They come from the global environment (`~/.julia/environments/v1.13`), which Julia stacks
# under `--project=.` via LOAD_PATH ("@", "@v#.#", "@stdlib"). `Pkg.test` builds an isolated env that
# does NOT stack it — so nothing under `test/` may use them.
#
# 🔴 To RUN THE TESTS use `tools/run_tests.sh`, never a pipe into this REPL: `julia -i` with piped
# stdin always exits 0, so a red suite reports success.

try
    using Revise
catch
    @warn "Revise unavailable from the global env — edits will not reload"
end

using LogicKernel

"Run the whole suite in this session (Revise-aware). For a real exit code use tools/run_tests.sh."
t(path=joinpath(@__DIR__, "..", "test", "runtests.jl")) = include(path)
