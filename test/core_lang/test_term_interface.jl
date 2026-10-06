# ORIGINAL: runs the conformance suite on every implementation of the term interface.
# test/core_lang/test_term_interface.jl — the conformance suite, TERM-GENERIC: runtests.jl runs it
# on the reference type `Term{G}` and on the second implementation `AltTerm`
# (test/core_lang/alt_term.jl); see test/term_under_test.jl.
#
# For the reference type, the payload union holds every host value the suite plants (TermConformance.HOST_VALUES), custom
# `==` type included. It is wider than a production `G` would be — this run checks MEANING; the
# zero-dispatch property is checked on production-shaped `G`s in test/test_static_analysis.jl.
using Test, LogicKernel

include(joinpath(@__DIR__, "term_interface_testlib.jl"))
using .TermConformance: run_term_conformance, CustomEq

const _CG = Union{Int64, BigInt, Float64, Float32, BigFloat, Rational{Int64},
    Rational{BigInt},
    String, Bool, Char,
    Vector{Float64},
    Tuple{Float64, Int64}, ComplexF64, Missing, CustomEq}
# TERM TYPES PER CHUNK: ALL — the term layer: src/term_interface.jl, src/default_term.jl
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CT = lk_term_type(_CG)

run_term_conformance(_CT; mksym=s -> lk_sym(_CT, s), mkgnd=v -> lk_gnd(_CT, v),
    label=LK_TERM_IMPL)
