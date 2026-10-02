# ORIGINAL: runs the conformance suite on the reference term type.
# test/core_lang/test_term_interface.jl — the conformance suite against the REFERENCE type.
#
# The payload union holds every host value the suite plants (TermConformance.HOST_VALUES), custom
# `==` type included. It is wider than a production `G` would be — this run checks MEANING; the
# zero-dispatch property is checked on production-shaped `G`s in test/test_static_analysis.jl.
using Test, LogicKernel

include(joinpath(@__DIR__, "term_interface_testlib.jl"))
using .TermConformance: run_term_conformance, CustomEq

const _CG = Union{Int64, Float64, Float32, Rational{Int64}, String, Bool, Char,
    Vector{Float64},
    Tuple{Float64, Int64}, ComplexF64, Missing, CustomEq}
const _CT = Term{_CG}

run_term_conformance(_CT; mksym=s -> sym_term(_CT, s), mkgnd=v -> gnd_term(_CT, v),
    label="Term (the reference implementation)")
