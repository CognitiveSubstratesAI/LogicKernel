# ORIGINAL: the integer ranges pl-comp.c chooses instructions by — PLMINTAGGEDINT/PLMAXTAGGEDINT (pl-incl.h) against a live swipl's tagged-integer flags, and is_portable_smallint (pl-comp.c) under the portable_vmi flag; upstream has no unit for them.
# test/compile/test_portable_smallint_swipl.jl — Q1's instruction-choice helper (user, 2026-10-03):
# the term interface gives a number's SEMANTIC kind and value; whether an integer becomes an inline
# operand (H_SMALLINT, A_ADD_FC) is upstream's own `is_portable_smallint`, separately.
using Test, LogicKernel
using LogicKernel: is_portable_smallint, PLMINTAGGEDINT, PLMAXTAGGEDINT, PL_local_data

@testset "is_portable_smallint (pl-comp.c)" begin
    ld = PL_local_data{DefaultTerm}()
    @test ld.prolog_flag_portable_vmi                  # swipl's default, checked live below
    i32lo, i32hi = Int64(typemin(Int32)), Int64(typemax(Int32))
    # portable_vmi = true: tagged AND within int32, so the code runs on 32-bit VMs too
    for (i, want) in
        ((0, true), (-1, true), (i32hi, true), (i32lo, true), (i32hi + 1, false),
        (i32lo - 1, false), (PLMAXTAGGEDINT, false), (PLMINTAGGEDINT, false))
        @test is_portable_smallint(ld, i) == want
    end
    # portable_vmi = false: any tagged integer
    ld.prolog_flag_portable_vmi = false
    @test is_portable_smallint(ld, PLMAXTAGGEDINT) &&
        is_portable_smallint(ld, PLMINTAGGEDINT)
    @test is_portable_smallint(ld, i32hi + 1)
    @test !is_portable_smallint(ld, PLMAXTAGGEDINT + 1) &&
        !is_portable_smallint(ld, PLMINTAGGEDINT - 1)
    @test !is_portable_smallint(ld, typemax(Int64)) &&
        !is_portable_smallint(ld, typemin(Int64))
end

const _PSWIPL = Sys.which("swipl")
const _PSWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

if _PSWIPL !== nothing
    @testset "the tagged range and the portable_vmi default are swipl's" begin
        out = read(
            `swipl -g "current_prolog_flag(min_tagged_integer,N), current_prolog_flag(max_tagged_integer,M), current_prolog_flag(portable_vmi,P), format('~w ~w ~w~n',[N,M,P])" -t halt`,
            String
        )
        lo, hi, pv = split(strip(out))
        @test parse(Int64, lo) == PLMINTAGGEDINT
        @test parse(Int64, hi) == PLMAXTAGGEDINT
        @test pv == "true" && PL_local_data{DefaultTerm}().prolog_flag_portable_vmi
    end
elseif _PSWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the tagged-range check would be skipped"
    )
else
    @info "UPSTREAM DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "swipl check skipped only where it is not required" begin
        @test !_PSWIPL_REQUIRED
    end
end
