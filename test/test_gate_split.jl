# ORIGINAL: the gate split's own tests (user, 2026-10-06): the declarations (test/term_scope.jl), the
# term types a chunk's local gate runs, and the CI verdict that stops a gate cycle
# (tools/ci_status.sh, tools/lib_evidence.sh `_ci_gate`) with its one way past a red push, the
# declared fix; and the mutation lane (tools/mutate.sh): the worktree, its guard, the recovery.
# Each guard is judged by its VERDICT.
using Test, SHA

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

    # user, 2026-10-16: a file that includes term_under_test.jl in another form would run on the
    # reference type only, silently — it stops the suite instead
    @testset "an include of term_under_test.jl in another form stops the suite" begin
        inc = "include(joinpath(@__DIR__, \"..\", \"term_under_test.jl\"))\n"
        flat = "include(joinpath(@__DIR__, \"term_under_test.jl\"))\n"        # a file directly in test/
        deep = "include(joinpath(@__DIR__, \"..\", \"..\", \"term_under_test.jl\"))\n"
        @test lk_term_include_check("f", inc) === nothing
        @test lk_term_include_check("f", "include(\"x.jl\")\n") === nothing
        @test_throws ErrorException lk_term_include_check("f", flat)
        @test_throws ErrorException lk_term_include_check("f", deep)
        mktempdir() do d                                   # … and the scan of a tree uses it
            write(joinpath(d, "test_flat.jl"), flat)
            @test_throws ErrorException lk_term_scopes(d)
        end
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

    @testset "_pool_usable: a pool worker is used only if ready, for this tree, and ALIVE" begin
        # MEASURED 2026-10-09: after a reboot, dead workers with `ready` files and the tree's
        # fingerprint were handed the evidence run's shards
        lib = joinpath(_GS_ROOT, "tools", "lib_evidence.sh")
        mktempdir() do d
            usable(fp, alive) =
                withenv("LOGICKERNEL_UNIT_ACTIVE" => alive ? "true" : "false") do
                    run(
                        pipeline(ignorestatus(`bash -c ". $lib; _pool_usable $d $fp"`);
                            stdout=devnull, stderr=devnull)
                    ).exitcode
                end
            write(joinpath(d, "fp"), "abc123\n")
            write(joinpath(d, "unit"), "lk-pool-x-1\n")
            @test usable("abc123", true) == 1                       # not ready yet
            write(joinpath(d, "ready"), "4242")
            @test usable("abc123", true) == 0                       # ready, this tree, alive
            @test usable("abc123", false) == 1                      # DEAD (the reboot case)
            @test usable("def456", true) == 1                       # another tree
            rm(joinpath(d, "unit"))
            @test usable("abc123", true) == 1                       # no unit named
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
            # (never under a real declared fix, never on this repository's own record)
            gate(f, wait) = exitof(
                `bash -c ". $lib; _ci_gate $(_GS_ROOT) $wait $sha"`,
                "LOGICKERNEL_CI_FIXTURE" => f, "LOGICKERNEL_CI_POLL_S" => "1",
                "LOGICKERNEL_CI_FIX" => nothing,
                "LOGICKERNEL_CI_FIX_FILE" => joinpath(d, "CI_FIX")
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

    @testset "the sync's expected-mismatch list exists exactly while a sync lasts" begin
        # (user, 2026-10-11) test/sync_expected_mismatch.jl: there while tools/SWIPL_VERSION has a
        # `sync-from:` line, each entry naming a test file that checks it for staleness and the
        # upstream fix that clears it; and no test file uses it without an entry. It is EMPTY once
        # every fix is ported, and the sync's last commit deletes it. (The 2026-10-11 sync's list
        # and its functions are in the repository's history, last at 5b0c136: a new sync starts
        # from that file.)
        list = joinpath(_GS_ROOT, "test", "sync_expected_mismatch.jl")
        pin = read(joinpath(_GS_ROOT, "tools", "SWIPL_VERSION"), String)
        syncing = occursin(r"^sync-from:\s*[0-9a-f]{40}\s*$"m, pin)
        @test isfile(list) == syncing
        testdir = joinpath(_GS_ROOT, "test")
        users = [
            relpath(f, testdir) for f in lk_test_files(testdir) if
            basename(f) != "test_gate_split.jl" &&
                occursin("sync_expected_mismatch.jl", read(f, String))
        ]
        if syncing && isfile(list)
            m = Module(:GSSync)
            Base.include(m, list)
            entries = copy(Base.invokelatest(() -> m.SYNC_EXPECTED))
            files = unique(first.(entries))
            for f in files
                text =
                    isfile(joinpath(testdir, f)) ? read(joinpath(testdir, f), String) : ""
                @test occursin("const _SYNC_FILE = \"$f\"", text)
                @test occursin("sync_stale(_SYNC_FILE)", text)
            end
            @test Set(users) == Set(files)          # no use of the list without an entry
            @test all(e -> occursin(r"^[0-9a-f]{7,40}(\+[0-9a-f]{7,40})*$", e[3]), entries)
            @test allunique([(e[1], e[2]) for e in entries])
            # the list's own functions, on an entry made HERE (in this test's own copy of the
            # list, which may hold no other): a case that is not listed is not
            # expected; a listed one is, once; and until it has mismatched it is stale — WHERE
            # THERE IS A swipl. Without one the differentials do not run, so nothing is stale
            # there (CI's `test` jobs have none: run 38156167094 was red on that, and run
            # 38159492161 on THIS test, which then asked for staleness with whatever PATH it had).
            # Both sides are therefore asked on a PATH this test makes.
            file, case = "gate_split/an_entry_made_by_this_test.jl", "a listed case"
            call(f, args...) = Base.invokelatest(getfield(m, f), args...)
            call(:sync_cases, file, "0123abc", [case])
            @test Base.invokelatest(() -> length(m.SYNC_EXPECTED)) == length(entries) + 1
            mktempdir() do d
                none, with = joinpath(d, "none"), joinpath(d, "with")
                mkpath(none)
                mkpath(with)
                write(joinpath(with, "swipl"), "#!/bin/sh\nexit 0\n")
                chmod(joinpath(with, "swipl"), 0o755)
                stale(path) = withenv(() -> call(:sync_stale, file), "PATH" => path)
                @test call(:sync_mismatch, file, "a case that is not on the list") == false
                @test case in stale(with)                       # not hit yet: stale
                @test isempty(stale(none))                      # …but not where nothing ran
                @test call(:sync_unexpected, file, [case, "another mismatch"]) ==
                    ["another mismatch"]
                @test !(case in stale(with))                    # hit: no longer stale
                @test call(:sync_mismatch, "no/such_file.jl", case) == false
            end
        else
            @test isempty(users)
        end
    end

    @testset "the oracle: the pinned version, BUILT FROM the pinned commit" begin
        # (user, 2026-10-11) tools/lib_evidence.sh `_check_swipl_pin` and tools/swipl_pin.jl hold
        # the swipl on PATH to tools/SWIPL_VERSION: its version, and a `version_git` flag naming
        # the pinned commit — a release binary, or a build of another commit, is refused
        commit, other = "0123456789abcdef0123456789abcdef01234567", "f"^40
        lib = joinpath(_GS_ROOT, "tools", "lib_evidence.sh")
        pinmod = Module(:GSPin)
        Base.include(pinmod, joinpath(_GS_ROOT, "tools", "swipl_pin.jl"))
        mktempdir() do d
            mkpath(joinpath(d, "tools"))
            mkpath(joinpath(d, "bin"))
            pin(text) = write(joinpath(d, "tools", "SWIPL_VERSION"), text)
            # a `swipl` that answers the three questions the checks ask: its version, its
            # version_git, and where its library(plunit) is (`plunit_at`, or none)
            function fake(version, version_git; plunit_at=nothing)
                f = joinpath(d, "bin", "swipl")
                write(
                    f,
                    "#!/bin/sh\ncase \"\$1\" in\n  --version) echo \"SWI-Prolog version " *
                    "$version for x86_64-linux\" ;;\n  *) case \"\$2\" in\n" *
                    "    *'library(plunit)'*) " *
                    (plunit_at === nothing ? "exit 1" : "echo \"$plunit_at\"") *
                    " ;;\n    *) " *
                    (version_git === nothing ? "exit 1" : "echo \"$version_git\"") *
                    " ;;\n  esac ;;\nesac\n"
                )
                return chmod(f, 0o755)
            end
            path = joinpath(d, "bin") * ":" * ENV["PATH"]
            sh() = withenv("PATH" => path) do
                run(
                    pipeline(
                        ignorestatus(`bash -c ". $lib; _check_swipl_pin $d test"`);
                        stdout=devnull, stderr=devnull)
                ).exitcode
            end
            jl() = withenv("PATH" => path) do
                Base.invokelatest(pinmod.swipl_pin_refusal, d) === nothing ? 0 : 1
            end
            both() = (sh(), jl())
            pin("# the pin\nversion: 9.9.9\ncommit: $commit\n")
            fake("9.9.9", "9.9.9-46-g" * commit[1:9])
            @test both() == (0, 0)                              # the oracle
            fake("9.9.9", "9.9.9-46-g" * other[1:9])
            @test both() == (1, 1)                              # a build of another commit
            fake("9.9.9", nothing)
            @test both() == (1, 1)                              # a release: no version_git
            fake("9.9.9", "9.9.9")
            @test both() == (1, 1)                              # a version_git naming no commit
            fake("9.9.9", "9.9.9-46-g" * commit[1:4])
            @test both() == (1, 1)                              # too short to name one
            fake("9.9.8", "9.9.8-46-g" * commit[1:9])
            @test both() == (1, 1)                              # another version of that commit
            fake("9.9.9", "9.9.9-46-g" * commit[1:9])
            pin("version: 9.9.9\n")
            @test both() == (1, 1)                              # a pin that names no commit
            pin("commit: $commit\n")
            @test both() == (1, 1)                              # …or no version
            # (user, 2026-10-14) a pin that names `plunit:` holds the oracle's library(plunit) to
            # the vendored packages/plunit/plunit.pl, byte for byte; a pin without it (above) does
            # not ask
            pin("version: 9.9.9\ncommit: $commit\nplunit: $other\n")
            mkpath(joinpath(d, "packages", "plunit"))
            mkpath(joinpath(d, "oracle"))
            mine = joinpath(d, "packages", "plunit", "plunit.pl")
            theirs = joinpath(d, "oracle", "plunit.pl")
            write(mine, ":- module(plunit, []).\n")
            write(theirs, ":- module(plunit, []).\n")
            fake("9.9.9", "9.9.9-46-g" * commit[1:9]; plunit_at=theirs)
            @test both() == (0, 0)                              # the oracle, with the pinned plunit
            write(theirs, ":- module(plunit, [run_tests/0]).\n")
            @test both() == (1, 1)                              # another plunit
            fake("9.9.9", "9.9.9-46-g" * commit[1:9])
            @test both() == (1, 1)                              # an oracle without plunit
            fake(
                "9.9.9",
                "9.9.9-46-g" * commit[1:9];
                plunit_at=joinpath(d, "oracle", "gone.pl")
            )
            @test both() == (1, 1)                              # …or naming a file that is not there
            write(theirs, "")
            write(mine, "")
            fake("9.9.9", "9.9.9-46-g" * commit[1:9]; plunit_at=theirs)
            @test both() == (1, 1)                              # empty equals empty: refused
            write(theirs, ":- module(plunit, []).\n")
            rm(mine)
            @test both() == (1, 1)                              # no vendored plunit
        end
    end

    @testset "_ci_gate: a declared fix passes ONE red commit, and nothing else" begin
        # (user, 2026-10-11) LOGICKERNEL_CI_FIX=<sha>: RED on exactly that commit passes, and is
        # recorded for the commit-msg hook; while the variable is set, a green push, one with no
        # verdict, an unreadable answer and another commit all FAIL
        sha, other = "0123456789abcdef0123456789abcdef01234567", "f"^40
        lib = joinpath(_GS_ROOT, "tools", "lib_evidence.sh")
        runs(status, conclusion) =
            "{\"workflow_runs\":[{\"head_sha\":\"$sha\",\"name\":\"CI\"," *
            "\"status\":\"$status\",\"conclusion\":$conclusion,\"html_url\":\"https://x/1\"}]}"
        red, green = runs("completed", "\"failure\""), runs("completed", "\"success\"")
        pending = runs("in_progress", "null")
        mktempdir() do d
            rec, f = joinpath(d, "CI_FIX"), joinpath(d, "f.json")
            function gate(json, fix; wait=0)
                write(f, json)
                return withenv(
                    "LOGICKERNEL_CI_FIXTURE" => f, "LOGICKERNEL_CI_POLL_S" => "1",
                    "LOGICKERNEL_CI_FIX_FILE" => rec, "LOGICKERNEL_CI_FIX" => fix,
                    "LOGICKERNEL_CI_CHECK" => nothing
                ) do
                    run(
                        pipeline(
                            ignorestatus(
                                `bash -c ". $lib; _ci_gate $(_GS_ROOT) $wait $sha"`
                            );
                            stdout=devnull, stderr=devnull)
                    ).exitcode
                end
            end
            @test gate(red, nothing) == 1 && !isfile(rec)       # red, nothing declared
            @test gate(red, sha) == 0                           # the declared fix…
            @test strip(read(rec, String)) == sha               # …recorded
            @test gate(red, sha[1:7]) == 1                      # a short SHA this repo lacks
            @test gate(red, other) == 1                         # another commit named
            @test gate(green, sha) == 1                         # nothing to fix: a stale variable
            @test gate(pending, sha) == 1                       # no verdict yet, at a cycle's start…
            @test gate(pending, sha; wait=2) == 1               # …and after the wait
            @test gate("<html>rate limited</html>", sha) == 1   # unreadable fails closed
            # a cycle with no fix declared removes an earlier cycle's record
            @test isfile(rec)
            @test gate(green, nothing) == 0 && !isfile(rec)
        end
    end

    @testset "the two lanes: an evidence run and a mutation run are told apart" begin
        # (Tooling 1) tools/run_tests.sh refuses a full run while mutants run in the worktree, and
        # tools/mutate.sh refuses to start them during an evidence run: both read a HELD lane lock
        lib = joinpath(_GS_ROOT, "tools", "lib_evidence.sh")
        mktempdir() do d
            main, wt = joinpath(d, "main"), joinpath(d, "wt")
            mkpath(joinpath(main, ".warm"))
            mkpath(joinpath(wt, ".warm"))
            # `held`: the tree whose lane lock the shell takes before it asks
            function ask(fn, held)
                hold = held === nothing ? "" : "exec 8>$held/.warm/run.lock; flock 8; "
                return withenv("LOGICKERNEL_MUTANTS_DIR" => wt) do
                    run(
                        pipeline(
                            ignorestatus(`bash -c ". $lib; $hold$fn $main"`);
                            stdout=devnull, stderr=devnull)
                    ).exitcode
                end
            end
            write(joinpath(wt, ".warm", "MUTANT_WORKTREE"), main * "\n")
            @test ask("_mutants_running", wt) == 0              # a run holds the worktree's lane
            @test ask("_mutants_running", nothing) == 1         # the lane is free
            @test ask("_mutants_running", main) == 1            # the MAIN lane is not the worktree's
            write(joinpath(wt, ".warm", "MUTANT_WORKTREE"), "/another/tree\n")
            @test ask("_mutants_running", wt) == 1              # another repository's worktree
            write(joinpath(main, ".warm", "run.kind"), "evidence\n")
            @test ask("_evidence_running", main) == 0
            @test ask("_evidence_running", nothing) == 1        # the kind of a run that ended
            write(joinpath(main, ".warm", "run.kind"), "preflight\n")
            @test ask("_evidence_running", main) == 1           # a preflight holds it: mutants may run
        end
    end

    @testset "tools/mutate.sh recover: restores from the saved copy, then lifts the sentinel" begin
        # (user, 2026-10-08) a killed mutation driver leaves .warm/MUTATION_IN_PROGRESS, which the
        # commit hook refuses on; deleting it by hand would let a leftover mutation through
        tool = joinpath(_GS_ROOT, "tools", "mutate.sh")
        sha(s) = bytes2hex(sha256(s))
        mktempdir() do d
            mkpath(joinpath(d, ".warm"))
            mkpath(joinpath(d, "src"))
            f = joinpath(d, "src", "x.jl")
            sentinel = joinpath(d, ".warm", "MUTATION_IN_PROGRESS")
            saved = joinpath(d, ".warm", "MUTATION_ORIGINAL")
            original = "f(x) = x + 1\n# the chunk's own uncommitted work\n"
            recover() = withenv("MUTATE_ROOT" => d) do
                run(pipeline(ignorestatus(`$tool recover`); stdout=devnull, stderr=devnull)).exitcode
            end
            setup(file_now; copy=original, sha_of=original) = begin
                write(f, file_now)
                copy === nothing ? rm(saved; force=true) : write(saved, copy)
                write(sentinel, "file=src/x.jl\nsha256=$(sha(sha_of))\nmutant=W3 test\n")
            end
            # a mutation left behind: restored from the copy (not from HEAD), then lifted
            setup("f(x) = x - 1\n# the chunk's own uncommitted work\n")
            @test recover() == 0
            @test read(f, String) == original && !isfile(sentinel) && !isfile(saved)
            # the file intact: lifted, the file untouched
            setup(original)
            @test recover() == 0
            @test read(f, String) == original && !isfile(sentinel) && !isfile(saved)
            # the copy missing: REFUSED, the sentinel and the mutated file kept
            setup("broken\n"; copy=nothing)
            @test recover() == 1
            @test isfile(sentinel) && read(f, String) == "broken\n"
            # the copy not the one the sentinel records: REFUSED
            setup("broken\n"; copy="something else\n")
            @test recover() == 1
            @test isfile(sentinel) && read(f, String) == "broken\n"
            # a sentinel naming no file: REFUSED
            write(sentinel, "mutant=W3 test\n")
            @test recover() == 1
            @test isfile(sentinel)
            # no sentinel: nothing to recover; a stray copy is removed
            rm(sentinel)
            write(saved, original)
            @test recover() == 0
            @test !isfile(saved)
        end
    end

    @testset "tools/mutate.sh: the mutant worktree holds the chunk's tree, and never commits" begin
        # (Tooling 1, 2026-10-11) a second worktree on a detached HEAD, the chunk's uncommitted
        # work copied over it; REFUSED unless both trees hold the same content
        tool = joinpath(_GS_ROOT, "tools", "mutate.sh")
        quiet(cmd) = pipeline(cmd; stdout=devnull, stderr=devnull)
        git(dir, args...) = readchomp(
            pipeline(
                setenv(`git -c user.name=t -c user.email=t@t.invalid $args`; dir=dir);
                stderr=devnull)
        )
        mktempdir() do d
            main, wt = joinpath(d, "main"), joinpath(d, "wt")
            mkpath(joinpath(main, "src"))
            mkpath(joinpath(main, "tools"))
            cp(joinpath(_GS_ROOT, "tools", "githooks"), joinpath(main, "tools", "githooks"))
            write(joinpath(main, ".gitignore"), ".warm/\nManifest.toml\n")
            for n in ("a", "b", "gone")
                write(joinpath(main, "src", "$n.jl"), "$n = 1\n")
            end
            git(main, "init", "-q")
            git(main, "config", "core.hooksPath", "tools/githooks")
            git(main, "add", "-A")
            git(main, "commit", "-q", "-m", "ADDED: the fixture")
            # the chunk's uncommitted work: an edit, a STAGED edit, a deletion, an untracked file,
            # and an ignored file that decides what loads
            write(joinpath(main, "src", "a.jl"), "a = 2\n")
            write(joinpath(main, "src", "b.jl"), "b = 2\n")
            git(main, "add", "src/b.jl")
            rm(joinpath(main, "src", "gone.jl"))
            write(joinpath(main, "src", "new.jl"), "n = 1\n")
            write(joinpath(main, "Manifest.toml"), "m = 1\n")
            mut(args...; dir=wt, fault=nothing) = withenv(
                "MUTATE_ROOT" => main, "LOGICKERNEL_MUTANTS_DIR" => dir,
                "MUTATE_FAULT_FP" => fault
            ) do
                run(quiet(ignorestatus(`$tool $args`))).exitcode
            end
            same(f) = read(joinpath(main, f)) == read(joinpath(wt, f))
            @test mut("setup") == 0
            @test same("src/a.jl") && same("src/b.jl") && same("src/new.jl")
            @test same("Manifest.toml") && !isfile(joinpath(wt, "src", "gone.jl"))
            @test git(wt, "rev-parse", "--abbrev-ref", "HEAD") == "HEAD"     # detached
            @test git(wt, "rev-parse", "HEAD") == git(main, "rev-parse", "HEAD")
            @test strip(read(joinpath(wt, ".warm", "MUTANT_WORKTREE"), String)) == main
            # it never commits or pushes: git's own hooks refuse THERE, and nowhere else
            commits(dir) = success(
                quiet(
                    setenv(
                        `git -c user.name=t -c user.email=t@t.invalid commit -q --allow-empty -m "TEST: x"`;
                        dir=dir)
                )
            )
            pushes(dir) = success(
                quiet(setenv(`$(joinpath(dir, "tools", "githooks", "pre-push"))`; dir=dir))
            )
            @test !commits(wt) && commits(main)
            @test !pushes(wt) && pushes(main)
            # a later state of the chunk: `setup` again brings the worktree to it
            write(joinpath(main, "src", "a.jl"), "a = 3\n")
            rm(joinpath(main, "src", "new.jl"))
            @test mut("setup") == 0
            @test same("src/a.jl") && !isfile(joinpath(wt, "src", "new.jl"))
            # THE GUARD: trees that do not hold the same content are REFUSED
            @test mut("setup"; fault="0"^40) == 1
            # a directory that is not this repository's mutant worktree is REFUSED, and left alone
            other = joinpath(d, "other")
            mkpath(other)
            write(joinpath(other, "keep"), "x")
            @test mut("setup"; dir=other) == 1 && isfile(joinpath(other, "keep"))
            # …and so is another worktree of this repository that is not marked as the mutants'
            # — its own edits and untracked files are left as they are
            plain = joinpath(d, "plain")
            git(main, "worktree", "add", "-q", "--detach", plain)
            write(joinpath(plain, "src", "a.jl"), "a = :someone_elses_work\n")
            write(joinpath(plain, "untracked.jl"), "u = 1\n")
            @test mut("setup"; dir=plain) == 1
            @test read(joinpath(plain, "src", "a.jl"), String) ==
                "a = :someone_elses_work\n"
            @test isfile(joinpath(plain, "untracked.jl"))
            # a mutation left in the WORKTREE: setup refuses; recover restores it there
            f = joinpath(wt, "src", "a.jl")
            original = read(f, String)
            sentinel = joinpath(wt, ".warm", "MUTATION_IN_PROGRESS")
            write(joinpath(wt, ".warm", "MUTATION_ORIGINAL"), original)
            write(
                sentinel,
                "file=src/a.jl\nsha256=$(bytes2hex(sha256(original)))\nmutant=W1 test\n"
            )
            write(f, "a = 99\n")
            @test mut("setup") == 1 && read(f, String) == "a = 99\n"
            @test mut("recover") == 0
            @test read(f, String) == original && !isfile(sentinel)
            # the chunk ends: the worktree goes, the main tree keeps its work
            @test mut("remove") == 0
            @test !isdir(wt) && read(joinpath(main, "src", "a.jl"), String) == "a = 3\n"
            @test mut("remove") == 0                                         # nothing left to remove
        end
    end

    @testset "tools/ci_status.sh: a short SHA gives the full SHA's answer, never a silent 'no run'" begin
        # MEASURED 2026-10-07: `ci_status.sh b615e51` said "no CI run yet" while the run was in
        # progress — the API's head_sha filter, and the verdict's own match, need the FULL SHA
        tool = joinpath(_GS_ROOT, "tools", "ci_status.sh")
        full = readchomp(`git -C $(_GS_ROOT) rev-parse HEAD`)
        short = full[1:7]
        out(cmd, env...) =
            withenv(env...) do
                o = IOBuffer()
                p = run(pipeline(ignorestatus(cmd); stdout=o, stderr=devnull))
                (p.exitcode, String(take!(o)))
            end
        mktempdir() do d
            for (status, conclusion, want) in
                (("completed", "\"success\"", 0), ("completed", "\"failure\"", 1),
                ("in_progress", "null", 3))
                f = joinpath(d, "f.json")
                write(
                    f,
                    "{\"workflow_runs\":[{\"head_sha\":\"$full\",\"name\":\"CI\"," *
                    "\"status\":\"$status\",\"conclusion\":$conclusion," *
                    "\"html_url\":\"https://x/1\"}]}"
                )
                a = out(`$tool $full`, "LOGICKERNEL_CI_FIXTURE" => f)
                b = out(`$tool $short`, "LOGICKERNEL_CI_FIXTURE" => f)
                c = out(`$tool HEAD`, "LOGICKERNEL_CI_FIXTURE" => f)
                @test a[1] == want                      # the fixture's verdict…
                @test b == a && c == a                  # …the same, text included, for each name
                @test occursin(full[1:7], b[2]) && !occursin("no CI run", b[2])
            end
            # a short SHA the repository does not have: unreadable (exit 2), not "no run" (3)
            f = joinpath(d, "e.json")
            write(f, "{\"workflow_runs\":[]}")
            @test out(`$tool 0000000`, "LOGICKERNEL_CI_FIXTURE" => f)[1] == 2
        end
    end
    # THE PUSH GATE (user, 2026-10-13): `main` takes only a commit the evidence workflow judged
    # green. Every answer is PLANTED (LOGICKERNEL_CI_FIXTURE), and the hook runs in a repository
    # of its own — a copy of the two scripts — so nothing here depends on this checkout's state.
    @testset "tools/githooks/pre-push: main only on a green evidence run of exactly that commit" begin
        # REAL commits (user, 2026-10-14): the hook reads the identity of every pushed commit not
        # yet on the remote (its refusal 3.), so a pushed SHA must exist — the noreply identity
        noreply = "11524260+sivaji1012@users.noreply.github.com"
        gs_dir = mktempdir()
        repo = joinpath(gs_dir, "repo")
        mkpath(joinpath(repo, "tools", "githooks"))
        run(pipeline(`git -C $repo init -q`; stdout=devnull, stderr=devnull))
        "A new empty commit by `author` and `committer` (emails) in the fixture; its SHA."
        function gs_commit(author::String, committer::String)::String
            withenv(
                "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => author,
                "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => committer
            ) do
                run(
                    pipeline(
                        `git -C $repo commit -q --allow-empty -m x`; stdout=devnull,
                        stderr=devnull
                    )
                )
            end
            return readchomp(`git -C $repo rev-parse HEAD`)
        end
        sha = gs_commit(noreply, noreply)
        ev = "Evidence (three term types)"
        @test occursin(
            "name: $ev\n",
            read(
                joinpath(_GS_ROOT, ".github", "workflows", "evidence.yml"), String
            )
        )                                              # the hook asks for the workflow BY NAME
        run_(name, status, conclusion; s=sha) =
            "{\"head_sha\":\"$s\",\"name\":\"$name\",\"status\":\"$status\"," *
            "\"conclusion\":$(conclusion === nothing ? "null" : "\"$conclusion\"")," *
            "\"html_url\":\"https://x/1\"}"
        green(n) = run_(n, "completed", "success")
        # (what the API answered, what the tool must say under --require, whether main may move)
        cases = [
            (
                "the evidence run green, CI green",
                "[" * green("CI") * "," * green(ev) * "]",
                0,
                true
            ),
            ("NO RUN FOUND", "[]", 3, false),
            ("CI green, but no evidence run", "[" * green("CI") * "]", 3, false),
            ("the evidence run still going",
                "[" * green("CI") * "," * run_(ev, "in_progress", nothing) * "]", 3, false),
            ("the evidence run queued", "[" * run_(ev, "queued", nothing) * "]", 3, false),
            ("the evidence run red",
                "[" * green("CI") * "," * run_(ev, "completed", "failure") * "]", 1, false),
            (
                "the evidence run cancelled",
                "[" * run_(ev, "completed", "cancelled") * "]",
                1,
                false
            ),
            ("the evidence run green, CI red",
                "[" * run_("CI", "completed", "failure") * "," * green(ev) * "]", 1, false),
            ("a green evidence run of ANOTHER commit",
                "[" * run_(ev, "completed", "success"; s="f" ^ 40) * "]", 3, false)
        ]
        mktempdir() do d
            for f in ("ci_status.sh", joinpath("githooks", "pre-push"))
                cp(joinpath(_GS_ROOT, "tools", f), joinpath(repo, "tools", f))
            end
            tool = joinpath(repo, "tools", "ci_status.sh")
            hook = joinpath(repo, "tools", "githooks", "pre-push")
            fx = joinpath(d, "f.json")
            exitof(cmd, env...) =
                withenv(env...) do
                    run(pipeline(ignorestatus(cmd); stdout=devnull, stderr=devnull)).exitcode
                end
            "The hook's exit for one pushed ref, `LOCAL_SHA → remote_ref`."
            push_(local_sha, remote_ref, env...) = exitof(
                pipeline(
                    IOBuffer("refs/heads/x $local_sha $remote_ref $("0" ^ 40)\n"),
                    Cmd(`bash $hook origin https://x`; dir=repo)
                ),
                "LOGICKERNEL_CI_FIXTURE" => fx,
                "LOGICKERNEL_PUSH_LOCAL_EVIDENCE" => nothing,
                env...
            )
            for (name, runs, want, may) in cases
                write(fx, "{\"workflow_runs\":" * runs * "}")
                @testset "$name" begin
                    @test exitof(
                        `$tool --require $ev $sha`, "LOGICKERNEL_CI_FIXTURE" => fx
                    ) == want
                    @test push_(sha, "refs/heads/main") == (may ? 0 : 1)
                    # any other branch is not this hook's: a gate branch is pushed BEFORE its run
                    @test push_(sha, "refs/heads/gate/x") == 0
                end
            end
            # without --require the same "CI green, no evidence run" answer IS green: the option,
            # not the tool's old verdict, is what refuses it
            write(fx, "{\"workflow_runs\":[" * green("CI") * "]}")
            @test exitof(`$tool $sha`, "LOGICKERNEL_CI_FIXTURE" => fx) == 0
            # unreadable: fails closed
            write(fx, "<html>rate limited</html>")
            @test push_(sha, "refs/heads/main") == 1
            # deleting main, whatever CI says
            write(fx, "{\"workflow_runs\":[" * green("CI") * "," * green(ev) * "]}")
            @test push_("0" ^ 40, "refs/heads/main") == 1
            # the declared fallback must name the pushed commit, and this checkout must BE it
            write(fx, "{\"workflow_runs\":[]}")
            @test push_(
                sha, "refs/heads/main", "LOGICKERNEL_PUSH_LOCAL_EVIDENCE" => "f" ^ 40
            ) == 1
            @test push_(sha, "refs/heads/main", "LOGICKERNEL_PUSH_LOCAL_EVIDENCE" => sha) ==
                1
            # two refs in one push: a refused main refuses the push
            @test exitof(
                pipeline(
                    IOBuffer(
                        "refs/heads/x $sha refs/heads/gate/x $("0" ^ 40)\n" *
                        "refs/heads/x $sha refs/heads/main $("0" ^ 40)\n"
                    ),
                    Cmd(`bash $hook origin https://x`; dir=repo)
                ),
                "LOGICKERNEL_CI_FIXTURE" => fx, "LOGICKERNEL_PUSH_LOCAL_EVIDENCE" =>
                    nothing
            ) == 1
            # 3. THE IDENTITY, on ANY ref (gate branches too): every commit not yet on the remote
            @testset "the noreply identity on every new commit" begin
                @test push_(sha, "refs/heads/gate/x") == 0                  # noreply: allowed
                bad = gs_commit("someone@gmail.example", "someone@gmail.example")
                @test push_(bad, "refs/heads/gate/x") == 1                  # another author
                badc = gs_commit(noreply, "someone@gmail.example")
                @test push_(badc, "refs/heads/gate/x") == 1                 # another committer
                # already on the remote: passes — main may move over commits a gate branch carried
                run(`git -C $repo update-ref refs/remotes/origin/gate/old $badc`)
                @test push_(badc, "refs/heads/gate/x") == 0
                @test push_(gs_commit(noreply, noreply), "refs/heads/gate/x") == 0   # new, on top
                @test push_("e"^40, "refs/heads/gate/x") == 1               # unknown: fails closed
            end
            # 4. A wip/ BRANCH NEVER PUSHES (user, 2026-10-16): its commits carry no evidence
            @testset "a wip/ branch never pushes" begin
                @test push_(sha, "refs/heads/wip/l1d") == 1                # to a wip/ name
                wip_push(local_ref, remote_ref) = exitof(
                    pipeline(
                        IOBuffer("$local_ref $sha $remote_ref $("0" ^ 40)\n"),
                        Cmd(`bash $hook origin https://x`; dir=repo)
                    ),
                    "LOGICKERNEL_CI_FIXTURE" => fx,
                    "LOGICKERNEL_PUSH_LOCAL_EVIDENCE" => nothing
                )
                @test wip_push("refs/heads/wip/l1d", "refs/heads/gate/x") == 1   # FROM a wip/ branch
                @test wip_push("refs/heads/gate/x", "refs/heads/gate/x") == 0    # the control
            end
        end
        rm(gs_dir; recursive=true)
    end
    # CI's EVIDENCE RUN IS THREE JOBS, ONE PER TERM TYPE (user, 2026-10-13): tools/evidence_ci.py
    # judges them together. Planted unit lists: a job that skipped a unit, ran another job's, or
    # died must not read as green.
    @testset "tools/evidence_ci.py: three green jobs that do not PARTITION the suite are not green" begin
        tool = joinpath(_GS_ROOT, "tools", "evidence_ci.py")
        all_ = ["a.jl", "g.jl", "g.jl [alt]", "g.jl [alt_interned]"]
        good = Dict(
            "reference" => ["a.jl", "g.jl"], "alt" => ["g.jl [alt]"],
            "alt_interned" => ["g.jl [alt_interned]"]
        )
        "The tool's exit over planted lists; `rows`: term → verdict row, absent = no row."
        function verdict(ran; alls=Dict(t => all_ for t in keys(ran)), rows=nothing)
            mktempdir() do d
                for (t, r) in ran
                    open(joinpath(d, "units_$t.tsv"), "w") do io
                        foreach(u -> println(io, "all\t", u), alls[t])
                        foreach(u -> println(io, "ran\t", u), r)
                    end
                end
                for t in ("reference", "alt", "alt_interned")
                    row = rows === nothing ? "| $t | passed | 1 s |" : get(rows, t, nothing)
                    row === nothing || write(joinpath(d, "row_$t.md"), row * "\n")
                end
                run(
                    pipeline(
                        ignorestatus(`python3 $tool $d`); stdout=devnull, stderr=devnull
                    )
                ).exitcode
            end
        end
        @test verdict(good) == 0                                    # the positive control
        @test verdict(merge(good, Dict("alt" => String[]))) == 1    # a unit run by no job
        @test verdict(merge(good, Dict("alt" => ["g.jl [alt]", "g.jl"]))) == 1      # by two jobs
        @test verdict(merge(good, Dict("alt" => ["g.jl [alt]", "x.jl"]))) == 1      # not in the suite
        @test verdict(
            good; alls=Dict(
                "reference" => all_, "alt" => all_[1:3], "alt_interned" => all_
            )
        ) == 1                                                     # the jobs enumerated two suites
        @test verdict(
            Dict(t => String[] for t in keys(good));
            alls=Dict(
                t => String[] for t in keys(good)
            )
        ) == 1                                                     # an EMPTY suite is not a pass
        @test verdict(delete!(copy(good), "alt")) == 1              # a job left no unit list
        @test verdict(
            good;
            rows=Dict(
                "reference" => "| reference | passed | 1 s |",
                "alt" => "| alt | **FAILED** | — |",
                "alt_interned" => "| alt_interned | passed | 1 s |"
            )
        ) == 1                                                     # a job failed
        @test verdict(
            good;
            rows=Dict(
                "reference" => "| reference | passed | 1 s |",
                "alt_interned" => "| alt_interned | passed | 1 s |"
            )
        ) == 1                                                     # a job died without a row
    end
    # CI's MUTATION BATTERY (user, 2026-10-13): tools/mutate_ci.py gives each mutant the local
    # driver's verdict from its targets' EXIT CODES. Planted targets (`sh:` commands) and a planted
    # list, in a directory of their own.
    @testset "tools/mutate_ci.py: a verdict per mutant, and what blocks" begin
        tool = joinpath(_GS_ROOT, "tools", "mutate_ci.py")
        mktempdir() do d
            write(joinpath(d, "f.txt"), "alpha\nbeta\nbeta\n")
            write(
                joinpath(d, "m.py"),
                """
MUTANTS = [
    dict(id="K1 caught by its target", file="f.txt", old="alpha", new="ALPHA"),
    dict(id="K2 no target sees it", file="f.txt", old="alpha", new="alpha "),
    dict(id="K3 its text occurs twice", file="f.txt", old="beta", new="BETA"),
    dict(id="K4 declared equivalent, and survives", file="f.txt", old="alpha",
         new="alpha ", equivalent="f.txt:1 nothing reads the blank"),
    dict(id="K5 declared equivalent, but caught", file="f.txt", old="alpha",
         new="ALPHA", equivalent="a wrong claim"),
    dict(id="K6 hangs", file="f.txt", old="alpha", new="HANG"),
    dict(id="K7 hangs, as expected", file="f.txt", old="alpha", new="HANG",
         expect="hang"),
    dict(id="K8 its target breaks otherwise", file="f.txt", old="alpha", new="ODD"),
]
"""
            )
            # exit 1 when the file holds ALPHA; hang on HANG; exit 7 on ODD; else exit 0
            target = "sh:grep -q ALPHA f.txt && exit 1; grep -q HANG f.txt && sleep 30; grep -q ODD f.txt && exit 7; exit 0"
            sh(args...) = run(
                pipeline(
                    ignorestatus(Cmd(`python3 $tool $args`; dir=d)); stdout=devnull,
                    stderr=devnull
                )
            ).exitcode
            out(args...) = read(ignorestatus(Cmd(`python3 $tool $args`; dir=d)), String)
            @test occursin("count=8", out("plan", "m.py"))
            # the list's own targets, for a run started by a push: none named → an empty line;
            # named → space-separated; a target with a blank in it is refused
            @test occursin("targets=\n", out("plan", "m.py"))
            write(
                joinpath(d, "mt.py"),
                read(joinpath(d, "m.py"), String) * "TARGETS = [\"a.jl\", \"b.jl\"]\n"
            )
            @test occursin("targets=a.jl b.jl\n", out("plan", "mt.py"))
            write(
                joinpath(d, "mb.py"),
                read(joinpath(d, "m.py"), String) * "TARGETS = [\"a.jl b.jl\"]\n"
            )
            @test sh("plan", "mb.py") != 0
            @test occursin("\"name\": \"K3\"", out("plan", "m.py"))
            @test occursin("count=1", out("plan", "m.py", "K2"))
            @test sh("plan", "m.py", "K9") != 0                     # no such mutant
            @test sh("baseline", "3", target) == 0
            want = Dict(
                "K1" => "caught", "K2" => "SURVIVED", "K3" => "BADMATCH",
                "K4" => "EQUIVALENT (declared)", "K5" => "EQUIVALENT REFUTED",
                "K6" => "TIMEOUT",
                "K7" => "caught (hang)", "K8" => "INVALID"
            )
            for k in sort!(collect(keys(want)))
                write(joinpath(d, "f.txt"), "alpha\nbeta\nbeta\n")     # each job: a fresh checkout
                @test sh("one", "m.py", k, "3", target) == 0        # the verdict is data
                rec = read(joinpath(d, "mutation-out", "$k.json"), String)
                @test occursin("\"verdict\": \"$(want[k])\"", rec)
            end
            table = out("collect", "m.py", "8")
            @test sh("collect", "m.py", "8") == 1                   # five of the eight block
            @test occursin("blocking: K2, K3, K5, K6, K8", table)
            # only the decided ones: green
            @test sh("collect", "m.py", "3", "K1", "K4", "K7") == 0
            # a planned mutant whose job left no verdict blocks…
            rm(joinpath(d, "mutation-out", "K1.json"))
            @test sh("collect", "m.py", "3", "K1", "K4", "K7") == 1
            @test occursin("NO VERDICT", out("collect", "m.py", "3", "K1", "K4", "K7"))
            # …and so does a baseline that is not green, whatever the mutants say
            @test sh("collect", "m.py", "2", "K4", "K7") == 0
            write(joinpath(d, "f.txt"), "ALPHA\n")
            @test sh("baseline", "3", target) == 1
            @test sh("collect", "m.py", "2", "K4", "K7") == 1
            rm(joinpath(d, "mutation-out", "baseline.json"))
            @test sh("collect", "m.py", "2", "K4", "K7") == 1       # no baseline at all
            # AN EXIT 1 IS CAUGHT ONLY WHEN A TEST FAILED (D-0050): real julia targets, run as the
            # job runs them. A mutant that does not load is no kill; a caught one keeps its line.
            write(joinpath(d, "f.txt"), "alpha\n")
            write(
                joinpath(d, "t.jl"),
                "using Test\n@testset \"t\" begin\n    @test !occursin(\"ALPHA\", read(\"f.txt\", String))\nend\n"
            )
            write(
                joinpath(d, "e.jl"),
                "exit(occursin(\"ALPHA\", read(\"f.txt\", String)) ? 1 : 0)\n"
            )
            write(
                joinpath(d, "n.py"),
                """
MUTANTS = [
    dict(id="L1 a test fails", file="f.txt", old="alpha", new="ALPHA", targets=["t.jl"]),
    dict(id="L2 does not load", file="f.txt", old="alpha", new="ALPHA",
         targets=["sh:grep -q ALPHA f.txt && echo 'ERROR: LoadError: ParseError:' && exit 1; exit 0"]),
    dict(id="L3 exits 1, no test failed", file="f.txt", old="alpha", new="ALPHA", targets=["e.jl"]),
]
"""
            )
            want = Dict(
                "L1" => "caught", "L2" => "NO VERDICT (does not load)",
                "L3" => "NO VERDICT (no failing test)"
            )
            for k in sort!(collect(keys(want)))
                write(joinpath(d, "f.txt"), "alpha\n")
                @test sh("one", "n.py", k, "300", "t.jl") == 0
                rec = read(joinpath(d, "mutation-out", "$k.json"), String)
                @test occursin("\"verdict\": \"$(want[k])\"", rec)
            end
            @test occursin(
                "\"first_failure\": \"t: Test Failed at t.jl:3\"",
                read(joinpath(d, "mutation-out", "L1.json"), String)
            )
            @test occursin(
                "ParseError", read(joinpath(d, "mutation-out", "L2.json"), String)
            )
            write(joinpath(d, "f.txt"), "alpha\n")
            @test sh("baseline", "300", "t.jl") == 0
            table = out("collect", "n.py", "3")
            @test sh("collect", "n.py", "3") == 1
            @test occursin("blocking: L2, L3", table)
            @test occursin("| L1 | caught |", table) &&
                occursin("Test Failed at t.jl:3 |", table)
            # the table as annotations, readable without a token: one workflow command per part,
            # its newlines and percent signs escaped, every row in it
            ann = out("annotate")
            @test sh("annotate") == 0
            @test count(==('\n'), ann) == 1 &&
                startswith(ann, "::notice title=verdicts 1/1::")
            @test occursin("%0A| L1 | caught |", ann) && occursin("%0A| L3 |", ann)
            write(joinpath(d, "mutation-out", "verdicts.md"), "a 100%\n" * "x"^4000 * "\n")
            ann = out("annotate")
            @test occursin("::notice title=verdicts 1/2::a 100%25\n", ann)
            @test occursin("::notice title=verdicts 2/2::" * "x"^4000 * "\n", ann)
        end
    end
    # the local driver's verdict table and its judge on REAL julia output, both ways
    @testset "tools/mutate_drive.py --selftest: no kill without a failed test" begin
        tool = joinpath(_GS_ROOT, "tools", "mutate_drive.py")
        jl = joinpath(Sys.BINDIR, Base.julia_exename())
        @test success(addenv(`python3 $tool --selftest`, "JULIA" => jl))
    end
    # THE RUNNER IMAGE IS PINNED (CI.yml's note above `jobs:`): no job, no matrix entry on a moving
    # `-latest` image; the oracle's cache key names the image. The scan must see every `runs-on`.
    @testset "the CI runner images are pinned, never -latest" begin
        wf = joinpath(_GS_ROOT, ".github", "workflows")
        moving, runs_on = String[], 0
        for f in filter(endswith(".yml"), readdir(wf; join=true)), (i, l) in enumerate(eachline(f))
            runs_on += occursin(r"^\s*runs-on:", l)
            occursin(r"^\s*(runs-on:|-)\s*[\w.-]+-latest\b", l) && push!(moving, "$(basename(f)):$i")
        end
        @test runs_on >= 9 && isempty(moving)
        action = read(joinpath(_GS_ROOT, ".github", "actions", "oracle", "action.yml"), String)
        @test occursin(raw"key=${ImageOS:?", action)
    end
    # A WHOLE-SUITE mutation target (tools/mutate_suite.sh) needs swipl-devel at the pin in the lane:
    # test/test_vendored_plunit.jl fails in CI without it, and the battery's baseline with it
    @testset "the mutation lane checks swipl-devel out for a whole-suite target" begin
        mut = read(joinpath(_GS_ROOT, ".github", "workflows", "mutation.yml"), String)
        @test count("'mutate_suite'", mut) == 2 && count("path: .upstream/swipl-devel", mut) == 2
        @test occursin("LOGICKERNEL_UPSTREAM_SWIPL_DEVEL:", mut)
        suite = joinpath(_GS_ROOT, "tools", "mutate_suite.sh")
        @test isfile(suite) && (filemode(suite) & 0o111) != 0
        @test occursin("test/runtests.jl", read(suite, String))
    end
end
