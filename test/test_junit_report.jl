# ORIGINAL: the JUnit writer's own test; no swipl-devel counterpart.
# test/test_junit_report.jl — the JUnit XML Codecov Test Analytics reads must report failures and
# errors truthfully. A fixture tree with one passing, one failing and one erroring test set is built
# OFF the suite's own tree (pushed and popped by hand, printing disabled), so its planted failures
# never reach the real result.
using Test, LogicKernel

include(joinpath(@__DIR__, "junit_report.jl"))

function _jr_fixture()
    fx = Test.DefaultTestSet("fixture <root>")
    # Julia 1.13: the test-set stack and the print switch are ScopedValues.
    Base.ScopedValues.@with Test.TESTSET_PRINT_ENABLE => false begin
        Test.@with_testset fx begin
            @testset "file <a & b>" begin
                @testset "passes" begin
                    @test true
                end
                @testset "fails" begin
                    @test 1 == 2
                end
                @testset "errors" begin
                    @test error("boom")
                end
            end
        end
    end
    return fx
end

@testset "junit report" begin
    mktempdir() do d
        xml = read(write_junit(_jr_fixture(), joinpath(d, "j.xml")), String)
        @test startswith(xml, "<?xml")
        @test occursin(
            "<testsuites name=\"fixture &lt;root&gt;\" tests=\"3\" failures=\"1\" errors=\"1\"",
            xml
        )
        @test occursin(
            "<testsuite name=\"file &lt;a &amp; b&gt;\" tests=\"3\" failures=\"1\" errors=\"1\"",
            xml
        )
        @test count("<testcase ", xml) == 3
        @test occursin(r"name=\"file &lt;a &amp; b&gt; › fails\"[^>]*>\s*<failure", xml)
        @test occursin(r"name=\"file &lt;a &amp; b&gt; › errors\"[^>]*>\s*<error", xml)
        @test occursin(r"name=\"file &lt;a &amp; b&gt; › passes\"[^>]*></testcase>", xml)
        @test count("<failure", xml) == 1 && count("<error", xml) == 1
    end
end
