# ORIGINAL: guards the bounds-checked CI run; no swipl-devel counterpart.
# test/test_check_bounds.jl — the BOUNDS-CHECKED run (user, 2026-10-04). Until Julia 1.12, Pkg.test
# ran with --check-bounds=yes; since 1.13 the test process inherits the parent's mode. CI's `test`
# job passes it explicitly (julia-runtest's `check_bounds: 'yes'`, .github/workflows/CI.yml) and
# sets LOGICKERNEL_REQUIRE_CHECK_BOUNDS=1, so this file fails that job if bounds checking is not
# really on — a default changed upstream cannot drop it silently. Elsewhere (the local runs, CI's
# analysis job) it is not required, and the file says so.
using Test

const _CB_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_CHECK_BOUNDS", "") == "1"
"An out-of-range read inside `@inbounds`: a `BoundsError` only when bounds checking is forced."
_cb_read(v::Vector{Int}, i::Int) = @inbounds v[i]

if _CB_REQUIRED
    @testset "bounds checking is ON where it is required" begin
        @test Base.JLOptions().check_bounds == 1                  # --check-bounds=yes
        @test_throws BoundsError _cb_read([1, 2], 3)               # …and it reaches @inbounds code
    end
else
    @testset "bounds checking not required here" begin
        @test !_CB_REQUIRED
    end
end
