# ORIGINAL: the gate split's own tests (user, 2026-10-06): the declarations (test/term_scope.jl), the
# term types a chunk's local gate runs, and the CI verdict that stops a gate cycle
# (tools/ci_status.sh, tools/lib_evidence.sh `_ci_gate`). Each guard is judged by its VERDICT.
using Test

include(joinpath(@__DIR__, "term_scope.jl"))

const _GS_ROOT = abspath(joinpath(@__DIR__, ".."))

@testset "the gate split: declarations, term types, the CI condition" begin
    @testset "every term-generic file declares its term types per chunk" begin
        scopes = lk_term_scopes(joinpath(_GS_ROOT, "test"))      # throws on a missing or bad one
        @test length(scopes) >= 20                                 # the term-generic files exist
        all_files = [
            relpath(f, joinpath(_GS_ROOT, "test")) for (f, v) in scopes if v[1] === :all
        ]
        # the conformance suite runs on every implementation, every chunk
        @test "core_lang/test_term_interface.jl" in all_files
        @test 1 <= length(all_files) < length(scopes)              # a split, not all or nothing
        for (f, (scope, srcs)) in scopes
            scope === :all || continue
            @test all(s -> isfile(joinpath(_GS_ROOT, s)), srcs)
        end
    end

    @testset "a declaration is exactly one line of a known kind" begin
        inc = "include(joinpath(@__DIR__, \"..\", \"term_under_test.jl\"))\n"
        ok_all =
            "# TERM TYPES PER CHUNK: ALL — the term layer: src/pl-prims.jl, src/a-b.jl\n" *
            inc
        ok_ref = "# TERM TYPES PER CHUNK: REFERENCE — built on the term layer\n" * inc
        @test lk_term_generic(ok_all) && !lk_term_generic("include(\"x.jl\")\n")
        @test lk_term_scope("f", ok_all) == (:all, ["src/pl-prims.jl", "src/a-b.jl"])
        @test lk_term_scope("f", ok_ref) == (:reference, String[])
        @test_throws ErrorException lk_term_scope("f", inc)                     # none
        @test_throws ErrorException lk_term_scope("f", ok_all * ok_ref)         # two
        @test_throws ErrorException lk_term_scope(
            "f", "# TERM TYPES PER CHUNK: ALL — no sources\n" * inc
        )
        @test_throws ErrorException lk_term_scope(
            "f", "# TERM TYPES PER CHUNK: SOME — x\n" * inc
        )
    end

    @testset "the term types: a trigger or a milestone runs all, anything else a chunk" begin
        triggers = lk_term_triggers(_GS_ROOT)
        @test all(in(triggers), LK_TERM_LAYER) && all(in(triggers), LK_TERM_GATE_LOGIC)
        @test "src/pl-prims.jl" in triggers                          # named by an ALL file
        types(changed; full=false) = lk_term_types(triggers, changed; full=full)[1]
        @test types(String[]) == "chunk"
        @test types(["src/pl-comp.jl", "docs/architecture.md"]) == "chunk"
        @test types(["src/default_term.jl"]) == "all"                # the term layer
        @test types(["test/core_lang/alt_term.jl"]) == "all"
        @test types(["src/pl-comp.jl", "src/pl-prims.jl"]) == "all"  # a source behind an ALL file
        @test types(["tools/run_tests.sh"]) == "all"                 # the gate's own logic
        @test types(["src/pl-comp.jl"]; full=true) == "all"          # a milestone
        # an unknown named source is refused, not silently never matched
        mktempdir() do d
            mkpath(joinpath(d, "test"))
            write(joinpath(d, "test", "test_x.jl"),
                "# TERM TYPES PER CHUNK: ALL — src/nope.jl\n" *
                "include(joinpath(@__DIR__, \"..\", \"term_under_test.jl\"))\n")
            @test_throws ErrorException lk_term_triggers(d)
        end
    end

    @testset "the units: a REFERENCE file runs on the reference type alone in a chunk" begin
        impls = ("reference", "alt", "alt_interned")
        @test lk_units_impls(:reference, "chunk", impls) == ("reference",)
        @test lk_units_impls(:all, "chunk", impls) == impls
        @test lk_units_impls(:reference, "all", impls) == impls
        @test_throws ErrorException lk_units_impls(:all, "some", impls)
    end

    @testset "_check_run: every shard ran the term types the run decided" begin
        lib = joinpath(_GS_ROOT, "tools", "lib_evidence.sh")
        mktempdir() do d
            function fixture(types_line)
                rm(d; recursive=true, force=true)
                mkpath(joinpath(d, "claims", "1"))
                mkpath(joinpath(d, "claims", "2"))
                write(joinpath(d, "units_total"), "2\n")
                write(joinpath(d, "seq_1.tsv"), "1\tu1\t1.0\n2\tu2\t1.0\n")
                write(joinpath(d, "stats_1"), "5 6 7\n")
                types_line === nothing || write(joinpath(d, "types_1"), types_line * "\n")
            end
            check(want) = withenv("LOGICKERNEL_TERM_TYPES" => want) do
                run(
                    pipeline(ignorestatus(`bash -c ". $lib; _check_run $d"`);
                        stdout=devnull, stderr=devnull)
                ).exitcode
            end
            fixture("chunk")
            @test check("chunk") == 0
            @test check("all") == 1                                  # the shard ran another
            fixture(nothing)
            @test check("all") == 1                                  # a shard that wrote none
            fixture("all")
            @test check("all") == 0
        end
    end

    @testset "tools/term_scope.jl prints one decision" begin
        out = read(
            pipeline(
                `$(Base.julia_cmd()) --startup-file=no $(joinpath(_GS_ROOT, "tools", "term_scope.jl"))`;
                stdin=devnull), String)
        @test occursin(r"^(all|chunk)\t\S", out)
    end

    @testset "tools/ci_status.sh and _ci_gate judge the previous push" begin
        sha = "0123456789abcdef0123456789abcdef01234567"
        run_(name, status, conclusion; s=sha) =
            "{\"head_sha\":\"$s\",\"name\":\"$name\",\"status\":\"$status\"," *
            "\"conclusion\":$(conclusion === nothing ? "null" : "\"$conclusion\"")," *
            "\"html_url\":\"https://x/1\"}"
        fixtures = [
            ("green", "[" * run_("CI", "completed", "success") * "]", 0),
            ("red", "[" * run_("CI", "completed", "failure") * "]", 1),
            ("cancelled", "[" * run_("CI", "completed", "cancelled") * "]", 1),
            ("in progress", "[" * run_("CI", "in_progress", nothing) * "]", 3),
            ("no run", "[]", 3),
            (
                "another commit's run only",
                "[" * run_("CI", "completed", "failure"; s="f" ^ 40) * "]",
                3
            ),
            ("green and red",
                "[" * run_("A", "completed", "success") * "," *
                run_("B", "completed", "failure") * "]", 1),
            ("green and running",
                "[" * run_("A", "completed", "success") * "," *
                run_("B", "queued", nothing) * "]", 3)
        ]
        tool = joinpath(_GS_ROOT, "tools", "ci_status.sh")
        lib = joinpath(_GS_ROOT, "tools", "lib_evidence.sh")
        mktempdir() do d
            exitof(cmd, env...) =
                withenv(env...) do
                    run(pipeline(ignorestatus(cmd); stdout=devnull, stderr=devnull)).exitcode
                end
            gate(f, wait) = exitof(
                `bash -c ". $lib; _ci_gate $(_GS_ROOT) $wait $sha"`,
                "LOGICKERNEL_CI_FIXTURE" => f, "LOGICKERNEL_CI_POLL_S" => "1"
            )
            for (name, runs, want) in fixtures
                f = joinpath(d, "f.json")
                write(f, "{\"workflow_runs\":" * runs * "}")
                @test exitof(`$tool $sha`, "LOGICKERNEL_CI_FIXTURE" => f) == want
                # the gate: green passes; red fails; no verdict passes at a cycle's start (0 s)
                # and fails after waiting for one (2 s)
                @test gate(f, 0) == (want == 1 ? 1 : 0)
                @test gate(f, 2) == (want == 0 ? 0 : 1)
            end
            garbage = joinpath(d, "g.json")
            write(garbage, "<html>rate limited</html>")
            @test exitof(`$tool $sha`, "LOGICKERNEL_CI_FIXTURE" => garbage) == 2
            @test gate(garbage, 0) == 1                              # unreadable fails CLOSED
            @test exitof(`bash -c ". $lib; _ci_gate $(_GS_ROOT) 0 $sha"`,
                "LOGICKERNEL_CI_FIXTURE" => garbage, "LOGICKERNEL_CI_CHECK" => "off") == 0
        end
    end
end
