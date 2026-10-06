# UPSTREAM: swipl-devel tests/rational/test_ieee754.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Author:        Rick Workman
#
# The parts of swipl-devel's test_ieee754.pl that are about IDENTITY and the STANDARD ORDER of
# IEEE floats — what the kernel's `compareStandard` (src/pl-prims.jl) and the reference type's
# `atomic_compare` decide, and so what unification of floats follows (`0.0 = -0.0` fails because
# `0.0 \== -0.0`; a NaN unifies with an identical NaN because `nan == nan`). `1.5NaN` is the quiet
# NaN Julia writes `NaN`.
#
# DIVERGES (file-wide): `ieee_cmp` keeps only its two identity assertions (`0.0 \== -0.0`, `nan == nan`); the
# rest of it is arithmetic comparison (`=:=`, `<`, …), which the kernel does not have. `ieee_tcmp`'s
# `sort/2` assertion is run as a sort by the standard order (`sort/2` itself is not ported).
#
# NOT PORTED, and why: ieee_flags, ieee_excp, and every arithmetic unit (ieee_minus … ieee_pow) —
# float flags and arithmetic are not part of the kernel.
using Test, LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _IT = lk_term_type(Union{Int64, Float64, String})
_ig(x) = lk_gnd(_IT, x)
_ilt(a, b) = compareStandard(_ig(a), _ig(b)) == -1         # a @< b
_igt(a, b) = compareStandard(_ig(a), _ig(b)) == 1          # a @> b

@testset "ieee754" begin
    # PORT: test_ieee754.pl ieee_cmp
    @testset "ieee_cmp" begin
        @test compareStandard(_ig(0.0), _ig(-0.0)) != 0     # 0.0 \== -0.0
        @test compareStandard(_ig(NaN), _ig(NaN)) == 0      # nan == nan
    end
    # PORT: test_ieee754.pl ieee_tcmp
    @testset "ieee_tcmp" begin                              # placement in standard term order
        @test _ilt(NaN, -Inf) && _ilt(-Inf, -0.0) && _ilt(-0.0, 0.0) && _ilt(0.0, Inf)
        @test _igt(Inf, 0.0) && _igt(0.0, -0.0) && _igt(-0.0, -Inf) && _igt(-Inf, NaN)
        @test _ilt(NaN, -Inf) && _ilt(-Inf, 0) && _ilt(0, Inf)
        @test _igt(Inf, 0) && _igt(0, -Inf) && _igt(-Inf, NaN)
        @test compareStandard(_ig(NaN), _ig(0.0)) == compareStandard(_ig(NaN), _ig(0))
        sorted = sort(
            _ig.([Inf, 0.0, -0.0, -Inf, NaN]); lt=(a, b) -> compareStandard(a, b) < 0
        )
        @test all(
            compareStandard(a, b) == 0 for
            (a, b) in zip(sorted, _ig.([NaN, -Inf, -0.0, 0.0, Inf]))
        )
    end
end
