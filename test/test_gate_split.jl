# ORIGINAL: the gate split's own tests (user, 2026-10-06): the declarations (test/term_scope.jl), the
# term types a chunk's local gate runs, and the CI verdict that stops a gate cycle
# (tools/ci_status.sh, tools/lib_evidence.sh `_ci_gate`) with its one way past a red push, the
# declared fix; and the mutation lane (tools/mutate.sh): the worktree, its guard, the recovery.
# Each guard is judged by its VERDICT.
using Test, SHA

include(joinpath(@__DIR__, "term_scope.jl"))

const _GS_ROOT = abspath(joinpath(@__DIR__, ".."))

# Run CMD with stdout AND stderr into ONE open file (a shared offset): two `=path` redirects are two open
# file descriptions at offset 0 and the later writer overwrites the earlier one's text.
function _gs_run_merged(cmd::Cmd)
    out = tempname()
    code = open(out, "w") do io
        run(pipeline(ignorestatus(cmd); stdin=devnull, stdout=io, stderr=io)).exitcode
    end
    txt = read(out, String)
    rm(out; force=true)
    return (code=code, out=txt)
end

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

    # audit D-0206 item 4 (2026-10-29): BLOB's test_blob.jl declared `ALL` and named no src/ file; the
    # branch-gate and `warm.sh check` passed it and CI's Pkg.test stopped on it (A-0140). The check now
    # lives in tools/term_scopes_check.jl, one extractor with this file's `lk_term_scopes`, and runs
    # first in `warm.sh check` (so in the preflight and the branch-gate). Each guard is judged by its
    # VERDICT, on a planted tree, and both of its sides must be non-empty: a check that passes on
    # nothing, or on another tree than the runner reads, would be a guard that cannot fail.
    @testset "tools/term_scopes_check.jl: a bad declaration fails the fast check, locally" begin
        inc = "include(joinpath(@__DIR__, \"..\", \"term_under_test.jl\"))\n"
        all_ok = "# TERM TYPES PER CHUNK: ALL — the term layer: src/real.jl\n" * inc
        ref_ok = "# TERM TYPES PER CHUNK: REFERENCE — built on the term layer\n" * inc
        script = joinpath(_GS_ROOT, "tools", "term_scopes_check.jl")
        # a planted package root: src/real.jl, and test/core_lang/<name> for each (name => text)
        function planted(f, files::Pair{String, String}...)
            mktempdir() do d
                mkpath(joinpath(d, "src"))
                write(joinpath(d, "src", "real.jl"), "# a source file\n")
                mkpath(joinpath(d, "test", "core_lang"))
                for (name, text) in files
                    write(joinpath(d, "test", "core_lang", name), text)
                end
                f(d)
            end
        end
        function run_check(d)
            out, err = tempname(), tempname()
            cmd = `$(Base.julia_cmd()) --startup-file=no $script $d`
            p = run(pipeline(ignorestatus(cmd); stdin=devnull, stdout=out, stderr=err))
            r = (code=p.exitcode, out=read(out, String), err=read(err, String))
            rm(out; force=true)
            rm(err; force=true)
            return r
        end
        # the control: a valid tree passes, and the pass line counts what it read
        planted("test_a.jl" => all_ok, "test_b.jl" => ref_ok) do d
            r = run_check(d)
            @test r.code == 0
            @test occursin("2 term-generic files: 1 ALL, 1 REFERENCE", r.out)
        end
        # the real tree passes, and its count is the in-process extractor's own (ONE extractor)
        r = run_check(_GS_ROOT)
        @test r.code == 0
        nscopes = length(lk_term_scopes(joinpath(_GS_ROOT, "test")))
        @test nscopes >= 20 && occursin("($nscopes term-generic files:", r.out)
        # the planted defects, each alone in a tree that is otherwise valid: exit 1, and the message
        # names the file and the rule (not merely "something failed")
        for (what, text, rule) in (
            (
                "an ALL declaration that names no src/ file",
                "# TERM TYPES PER CHUNK: ALL — the term layer, no file named\n" * inc,
                "names the source files"
            ),
            (
                "an ALL declaration naming a src/ file that does not exist",
                "# TERM TYPES PER CHUNK: ALL — src/nope.jl\n" * inc,
                "src/nope.jl, which does not exist"
            ),
            ("no declaration at all", inc, "found 0"),
            ("two declarations", all_ok * ref_ok, "found 2"),
            (
                "an unknown kind",
                "# TERM TYPES PER CHUNK: SOME — x\n" * inc,
                "unknown term types per chunk"
            ),
            (
                "an include that would run on the reference type only",
                "# TERM TYPES PER CHUNK: ALL — src/real.jl\n" *
                "include(joinpath(@__DIR__, \"term_under_test.jl\"))\n",
                "reference type ONLY"
            )
        )
            planted("test_good.jl" => all_ok, "test_bad.jl" => text) do d
                r = run_check(d)
                @test r.code == 1
                @test occursin("TERM SCOPES INVALID", r.err) && occursin(rule, r.err)
                @test occursin("test_bad.jl", r.err)                     # …and the file, never the good one
                @test !occursin("test_good.jl", r.err)
                @test !occursin("term scopes valid", r.out)
            end
        end
        # …a check that looked at nothing is a failure, not a pass (the non-empty sides)
        mktempdir() do d
            r = run_check(d)                                              # no test/ directory
            @test r.code == 1 && occursin("is not a directory", r.err)
            mkpath(joinpath(d, "test"))
            r = run_check(d)
            @test r.code == 1 && occursin("nothing was checked", r.err)   # no test_*.jl file
        end
        planted("test_plain.jl" => "@test true\n") do d                   # no term-generic file
            r = run_check(d)
            @test r.code == 1 && occursin("matched nothing", r.err)
        end
        planted("test_ref.jl" => ref_ok) do d                             # no ALL file: no source checked
            r = run_check(d)
            @test r.code == 1 && occursin("no ALL declaration", r.err)
        end
        # the declaration is read from `test_*.jl` files only, under test/ only: a bad one elsewhere is
        # not the runner's, so it is not this check's (the same tree, the same files)
        planted(
            "test_a.jl" => all_ok, "helper.jl" => "# TERM TYPES PER CHUNK: ALL —\n" * inc
        ) do d
            @test run_check(d).code == 0
        end
    end

    @testset "tools/warm.sh term-scopes: the verdict is the exit code, and fails closed" begin
        warm = joinpath(_GS_ROOT, "tools", "warm.sh")
        inc = "include(joinpath(@__DIR__, \"..\", \"term_under_test.jl\"))\n"
        function run_warm(root, args...; fault="")
            env = Dict(
                "LOGICKERNEL_TERM_SCOPES_COLD" => "1",        # a plain julia process, no daemon
                "LOGICKERNEL_TERM_SCOPES_ROOT" => root,
                "LOGICKERNEL_PREFLIGHT_FAULT" => fault
            )
            return _gs_run_merged(addenv(`bash $warm term-scopes $args`, env))
        end
        for (what, text, want) in (
            ("a valid tree", "# TERM TYPES PER CHUNK: ALL — src/real.jl\n" * inc, 0),
            (
                "an ALL declaration naming no src/ file",
                "# TERM TYPES PER CHUNK: ALL — nothing\n" * inc,
                1
            )
        )
            mktempdir() do d
                mkpath(joinpath(d, "src"))
                write(joinpath(d, "src", "real.jl"), "# s\n")
                mkpath(joinpath(d, "test", "core_lang"))
                write(joinpath(d, "test", "core_lang", "test_probe.jl"), text)
                r = run_warm(d)
                @test r.code == want
                # a Bool, not `@test occursin(.., r.out)`: a failing @test prints its arguments, and the output of a
                # mutated check holds "LoadError", which the mutation driver reads as "did not load" (TT6, TT16: NO
                # VERDICT in CI, 2026-10-29). The output is shown, masked, when the check fails.
                shown = occursin(
                    want == 0 ? "preflight: term scopes valid" : "TERM SCOPES INVALID",
                    r.out
                )
                shown || println(
                    stderr,
                    "term-scopes output: ",
                    replace(r.out, "LoadError" => "Load-Error")
                )
                @test shown
                if want == 0                                  # fail closed: a pass must SHOW its line
                    for fault in ("scopes-empty", "scopes-cut")
                        rf = run_warm(d; fault=fault)
                        @test rf.code == 4 && occursin("NO VERDICT", rf.out)
                    end
                end
            end
        end
        # the real tree: valid, so the check is one a clean branch passes
        @test run_warm(_GS_ROOT).code == 0
        # `check` runs it: the call is in `_checks_fresh`, BEFORE the formatter (so one run names every
        # failure), its status is returned when the others pass, and `check`, the branch-gate and the
        # preflight all go through `_checks_fresh`. (The behaviour — `check` FAILS on a planted bad
        # declaration — is tools/test_warm.sh's `fast` mode, which runs a real daemon.)
        script = read(warm, String)
        body = match(r"(?s)\n_checks_fresh\(\) \{\n(.*?)\n\}\n", script)[1]
        @test occursin(
            r"(?m)^    _term_scopes_check +#[^\n]*\n    ts=\$\?\n    _meta_check\n", body
        )
        @test occursin(
            r"(?m)^    _meta_check\n    mt=\$\?\n    _inert_check \"[^\n]*\"\n    ic=\$\?\n    _format_port_check\n",
            body
        )
        # every step's status is returned: the format status first, then scopes, meta, inert
        @test occursin(
            r"(?m)^    \[ \"\$rc\" -eq 0 \] \|\| return \"\$rc\"\n    \[ \"\$ts\" -eq 0 \] \|\| return \"\$ts\"\n    \[ \"\$mt\" -eq 0 \] \|\| return \"\$mt\"\n    return \"\$ic\"$",
            body
        )
        @test occursin(r"(?m)^        _checks_fresh\n        _ck_rc=\$\?", script)                 # `check`
        @test occursin(r"_checks_fresh \|\| \{ echo \"branch-gate: FAIL", script)                 # branch-gate
        @test occursin(r"(?m)^    _checks_fresh\n    rc=\$\?\n", script)                          # preflight
    end

    # audit D-0206 item 4b: a `file` run of the static-analysis file takes 32 min (SSU1) against the
    # 1800 s client default; 3600 s for that file ALONE. Judged on what `warm.sh file` would send under:
    # the send seam prints the timeout and sends nothing (a daemon is neither needed nor touched).
    @testset "tools/warm.sh file: the static-analysis file's timeout is 3600 s, the others' 1800 s" begin
        warm = joinpath(_GS_ROOT, "tools", "warm.sh")
        function file_timeout(file; env=String[])
            e = Dict("LOGICKERNEL_WARM_SEND_PROBE" => "1", "WARM_TIMEOUT_S" => "")
            for kv in env
                e[first(kv)] = last(kv)
            end
            # TWO arguments (an implementation named): a one-argument run records the file's time
            txt = _gs_run_merged(addenv(`bash $warm file $file reference`, e)).out
            m = match(r"(?m)^send: timeout (\d+)s$", txt)
            return m === nothing ? nothing : parse(Int, m[1])
        end
        @test file_timeout("test/test_static_analysis.jl") == 3600
        @test file_timeout(joinpath(_GS_ROOT, "test", "test_static_analysis.jl")) == 3600
        @test file_timeout("test/test_gate_split.jl") == 1800
        @test file_timeout("test/static_analysis_fast.jl") == 1800        # the fast pre-check: seconds
        # an explicit WARM_TIMEOUT_S wins (tools/mutate_drive.py sets one per mutant), for either file
        @test file_timeout(
            "test/test_static_analysis.jl"; env=["WARM_TIMEOUT_S" => "90"]
        ) == 90
        @test file_timeout("test/test_gate_split.jl"; env=["WARM_TIMEOUT_S" => "90"]) == 90
        # …and a plain `send` of any snippet keeps the default: the 3600 s is the static FILE's
        script = read(warm, String)
        @test occursin(r"(?m)^WARM_DEFAULT_TIMEOUT_S=1800$", script)
        @test occursin(r"(?m)^WARM_STATIC_TIMEOUT_S=3600$", script)
        @test count("\${WARM_TIMEOUT_S:-1800}", script) == 0      # no second place for the number
        # the two seams that send nothing to the daemon (the send probe, the cold term-scopes snippet) skip the
        # lane check — these tests run INSIDE the branch-gate, which holds the lane — and nothing else does
        @test occursin(
            r"(?m)^        if \[ \"\$\{LOGICKERNEL_WARM_SEND_PROBE:-\}\" != 1 \] && \[ \"\$\{LOGICKERNEL_TERM_SCOPES_COLD:-\}\" != 1 \]; then\n            _lane_check \|\| exit 5\n        fi$",
            script
        )
        @test count("_lane_check || exit 5", script) == 1
        # the wait loop's deadline and its TIMEOUT message both read the timeout the send was given
        @test occursin(
            "deadline=\$(( \$(date +%s) + \${WARM_TIMEOUT_S:-\$WARM_DEFAULT_TIMEOUT_S} ))",
            script
        )
        @test occursin(
            "TIMEOUT after \${WARM_TIMEOUT_S:-\$WARM_DEFAULT_TIMEOUT_S}s on seq", script
        )
    end

    # audit D-0214 finding 1 (2026-10-29): the CI-only checks that are cheap moved into `warm.sh check`. The
    # steps run here with the send seam (nothing is sent: each file "has no verdict", which is how a ran
    # file shows) and a planted times table; what passes in a real daemon is tools/test_warm.sh's `fast`.
    @testset "tools/warm.sh check: the meta files, the inert guard, the formatter pin, the unit assertion" begin
        warm = joinpath(_GS_ROOT, "tools", "warm.sh")
        function run_step(args...; env=Pair{String, String}[], times="")
            tf = tempname()
            write(tf, times)
            e = Pair{String, String}[
                "LOGICKERNEL_WARM_SEND_PROBE" => "1", "LOGICKERNEL_FILE_TIMES" => tf
            ]
            m = _gs_run_merged(addenv(`bash $warm $args`, e..., env...))
            r = (code=m.code, out=m.out, times=read(tf, String))
            rm(tf; force=true)
            return r
        end
        script = read(warm, String)
        # the meta files: every listed file runs (each one is the probe's "no verdict"), its time is recorded,
        # a listed file that is gone and an empty list FAIL (a check that ran nothing is no pass)
        r = run_step("meta-check")
        metas = split(match(r"(?m)^WARM_META_FILES=\"([^\"]*)\"$", script)[1])
        @test length(metas) >= 3 && "test/test_package.jl" in metas
        @test r.code == 1
        for f in metas
            @test occursin("meta test file FAILED — $f", r.out)
            @test occursin("$f\t", r.times)
            @test isfile(joinpath(_GS_ROOT, f))
        end
        r = run_step("meta-check"; env=["LOGICKERNEL_META_FILES" => "test/nope.jl"])
        @test r.code == 1 &&
            occursin("test/nope.jl is listed in tools/warm.sh and does not exist", r.out)
        r = run_step("meta-check"; env=["LOGICKERNEL_META_FILES" => ""])
        @test r.code == 1 && occursin("nothing was checked", r.out)
        # The Pkg.test-way run of a changed test file (tools/pkgtest_way.sh): a STUB julia records how it was
        # started — environment, stdin, stdout, stderr — and answers as told (pass, fail, or exit 0 silent)
        stubdir = mktempdir()
        stub = joinpath(stubdir, "julia")
        write(
            stub,
            """#!/usr/bin/env bash
o1=\$([ -p /proc/\$\$/fd/1 ] && echo yes || echo no); o2=\$([ -p /proc/\$\$/fd/2 ] && echo yes || echo no)
{ echo "NO_SWIPL=\${LOGICKERNEL_NO_SWIPL-unset}"; echo "REQ_SWIPL=\${LOGICKERNEL_REQUIRE_SWIPL-unset}"
  echo "REQ_TOOLS=\${LOGICKERNEL_REQUIRE_TOOLS-unset}"; echo "TERM_=\${LOGICKERNEL_TERM-unset}"
  echo "stdin=\$(readlink /proc/self/fd/0)"; echo "stdout_pipe=\$o1"
  echo "stderr_pipe=\$o2"; echo "args=\$*"; } > "\$STUB_RECORD"
case "\$STUB_MODE" in
    pass) echo "pkgtest-way: PASS stub" ;;
    fail) echo "boom" >&2; exit 1 ;;
    failout) echo "planted: Test Failed at x.jl:1"; echo "  Expression: 1 + 1 == 3"; echo "boom" >&2; exit 1 ;;
    silent) : ;;
esac
"""
        )
        chmod(stub, 0o755)
        function way(args...; mode="pass", extra=Pair{String, String}[])
            rec, outd = joinpath(stubdir, "record"), mktempdir()
            rm(rec; force=true)
            env = Pair{String, String}[
                "LOGICKERNEL_PKGTEST_WAY_JULIA" => stub, "STUB_MODE" => mode,
                "STUB_RECORD" => rec,
                "LOGICKERNEL_PKGTEST_WAY_OUT" => outd,
                "LOGICKERNEL_PKGTEST_WAY_LOCK" => joinpath(stubdir, "lock"),
                # what a daemon-shaped parent has set: the run must not inherit it
                "LOGICKERNEL_REQUIRE_SWIPL" => "1", "LOGICKERNEL_REQUIRE_TOOLS" => "1",
                "LOGICKERNEL_TERM" => "alt"
            ]
            o = tempname()
            p = run(
                pipeline(
                    ignorestatus(
                        addenv(
                            `bash $(joinpath(_GS_ROOT, "tools", "pkgtest_way.sh")) $args`,
                            env...,
                            extra...
                        )
                    );
                    stdin=IOBuffer(""), stdout=o, stderr=o         # a pipe, so /dev/null is the script's own doing
                )
            )
            txt = read(o, String)
            rm(o; force=true)
            return (
                code=p.exitcode, out=txt, rec=isfile(rec) ? read(rec, String) : "",
                outd=outd
            )
        end
        r = way("test/test_package.jl")
        @test r.code == 0 && occursin("passed the way Pkg.test runs it", r.out)
        @test occursin("NO_SWIPL=1\n", r.rec)                               # no swipl
        @test occursin("REQ_SWIPL=unset\n", r.rec) && occursin("REQ_TOOLS=unset\n", r.rec)
        @test occursin("TERM_=unset\n", r.rec)
        @test occursin("stdin=/dev/null\n", r.rec)                          # stdin from /dev/null
        # stdout and stderr are PIPES like CI's julia-runtest (audit D-0247), not files the child opens; a logger
        # writes them to the two log files, each stream apart
        @test occursin("stdout_pipe=yes\n", r.rec) && occursin("stderr_pipe=yes\n", r.rec)
        @test occursin(
            "pkgtest-way: PASS stub", read(joinpath(r.outd, "test_package.out"), String)
        )
        @test !occursin(
            "pkgtest-way: PASS", read(joinpath(r.outd, "test_package.err"), String)
        )
        @test occursin("--startup-file=no", r.rec) &&
            occursin("tools/pkgtest_way.jl", r.rec)
        @test occursin("test/test_package.jl", r.rec)
        r = way("test/test_package.jl"; mode="fail")
        @test r.code == 1 && occursin("FAILED (exit 1)", r.out) && occursin("boom", r.out)
        # the child's exit status survives the pipes, and its stderr is in .err, not in .out
        @test occursin("boom", read(joinpath(r.outd, "test_package.err"), String)) &&
            !occursin("boom", read(joinpath(r.outd, "test_package.out"), String))
        # the failing test's own report is on the child's STDOUT: it must come out with the failure (CI, 2026-10-29)
        r = way("test/test_package.jl"; mode="failout")
        @test r.code == 1 && occursin("planted: Test Failed at x.jl:1", r.out) &&
            occursin("Expression: 1 + 1 == 3", r.out) && occursin("boom", r.out)
        r = way("test/test_package.jl"; mode="silent")                      # exit 0 without the pass line
        @test r.code == 4 && occursin("NO VERDICT", r.out)
        r = way("test/nope.jl")
        @test r.code == 2 && occursin("no such file", r.out)
        # the inert-check step runs it for each changed test file, within its budget (estimate = 3 x the warm time)
        stubenv(mode) = [
            "LOGICKERNEL_PKGTEST_WAY_JULIA" => stub, "STUB_MODE" => mode,
            "STUB_RECORD" => joinpath(stubdir, "record2"),
            "LOGICKERNEL_PKGTEST_WAY_OUT" => joinpath(stubdir, "out"),
            "LOGICKERNEL_PKGTEST_WAY_LOCK" => joinpath(stubdir, "lock")
        ]
        inert(args...; files="test/test_package.jl", times="", mode="pass") = run_step(
            "inert-check", args...;
            env=["LOGICKERNEL_INERT_FILES" => files, stubenv(mode)...], times=times
        )
        r = inert()
        @test r.code == 0 && occursin("Pkg.test-way run clean (1 changed test files", r.out)
        r = inert(; mode="fail")
        @test r.code == 1 &&
            occursin("Pkg.test-way run FAILED — test/test_package.jl", r.out)
        r = inert(; mode="failout")                                        # the preflight shows the file's own failure
        @test r.code == 1 && occursin("planted: Test Failed at x.jl:1", r.out)
        r = inert(; mode="silent")
        @test r.code == 1 && occursin("NO VERDICT", r.out)
        # the heavy tooling files and the static-analysis file are never run here (WARM_INERT_SKIP): a stub that
        # would FAIL is not started for them
        for skipped in (
            "test/test_static_analysis.jl", "test/test_gate_split.jl",
            "test/test_port_check.jl"
        )
            @test isfile(joinpath(_GS_ROOT, skipped))
            r = inert(; files=skipped, mode="fail")
            @test r.code == 0 && occursin("no changed test file", r.out) &&
                !occursin("FAILED", r.out)
        end
        r = inert(; files="")
        @test r.code == 0 && occursin("no changed test file", r.out)
        r = inert(; files="test/nope.jl")                                  # a deleted file is not run
        @test r.code == 0 && occursin("no changed test file", r.out)
        # the budget: a file whose estimate is over it is named and left to the branch-gate, one within runs
        r = inert("100"; times="test/test_package.jl\t500\n", mode="fail")
        @test r.code == 0 && occursin("over budget (estimate 1500s > 100s)", r.out)
        @test occursin("  test/test_package.jl", r.out) && !occursin("FAILED", r.out)
        r = inert("1500"; times="test/test_package.jl\t500\n", mode="fail")
        @test r.code == 1 && occursin("FAILED", r.out) && !occursin("over budget", r.out)
        r = inert("5")                                                      # no recorded time: 3 x the 20 s default
        @test occursin("over budget (estimate 60s > 5s)", r.out)
        # the formatter pin is CI.yml's own, one value
        ci = read(joinpath(_GS_ROOT, ".github", "workflows", "CI.yml"), String)
        pin = match(r"name=\"JuliaFormatter\", version=\"([0-9]+\.[0-9]+\.[0-9]+)\"", ci)[1]
        r = run_step("fmt-pin")
        @test r.code == 0 && strip(r.out) == pin
        @test occursin(
            r"(?m)^let pin = raw\"\$fmt_pin\", have = string\(pkgversion\(JuliaFormatter\)\)$",
            script
        )
        @test occursin("have == pin || error(", script) &&
            occursin("isempty(pin) && error(", script)
        # every unit closes as test/runtests.jl closes it: the shared empty child vector is still empty
        @test occursin(
            r"withenv\(\(\) -> Base\.include\(m, f\), env\.\.\.\)\n(\s+#[^\n]*\n){2}\s+@test isempty\(LogicKernel\._no_children\(LogicKernel\.DefaultTerm\)\)\n\s+end",
            script
        )
        # the branch-gate gives the inert guard a larger budget than `check`'s, for the same files
        @test occursin(
            "LOGICKERNEL_INERT_BUDGET_S=\"\${LOGICKERNEL_INERT_BUDGET_S:-600}\" _checks_fresh || {",
            script
        )
        # the tooling job's trigger files: a change under tools/ or .github/ brings in the two tooling tests
        bgf = match(r"(?s)\n_branch_gate_files\(\) \{\n(.*?)\n\}\n", script)[1]
        @test occursin(
            r"grep -qE '\^\(tools/\|\\\.github/\)'; then\n\s+printf '%s\\n' test/test_gate_split\.jl test/test_port_check\.jl\n\s+fi",
            bgf
        )
        tj = ci[findfirst("git diff --name-only \"\$base\" HEAD --", ci).start:end]
        @test occursin(
            "-- tools .github test/test_port_check.jl test/test_gate_split.jl", tj
        )
    end

    # D-0242 item 2 (A-0148: BP2's second daemon was OOM-killed by its 6G slice with a Pkg.test-way process in it).
    # The Pkg.test-way runs go ONE AT A TIME, each in its OWN scope with a memory ceiling NESTED in the lane's
    # slice, so a runaway test process is killed — named, with its peak — and the daemon, a sibling in that slice,
    # survives; every run's PEAK memory is printed (the branch-gate log carries it) and appended to peaks.tsv. A STUB
    # test process allocates; the "daemon" is a `sleep` unit in the same slice. The scope and cap cases need user
    # systemd (CI's tooling job requires one); the sequence case does not.
    @testset "tools/pkgtest_way.sh: one at a time, each run in its own capped scope inside the lane's slice" begin
        sh = joinpath(_GS_ROOT, "tools", "pkgtest_way.sh")
        have_systemd = success(
            pipeline(
                `systemd-run --user --scope --quiet true`; stdout=devnull, stderr=devnull
            )
        )
        have_systemd ||
            @warn "no user systemd here: the scope, cap and kill cases did not run"
        dir = mktempdir()
        outd = mktempdir()
        stub = joinpath(dir, "julia")
        write(
            stub,
            """#!/usr/bin/env bash
case "\$STUB_MODE" in
    hog)
        python3 -I -c 'import sys
b = bytearray(int(sys.argv[1]) << 20)
for i in range(0, len(b), 4096):
    b[i] = 1' "\$STUB_MB" || exit \$? ;;
    where)
        cg=\$(sed -n 's/^0:://p' /proc/self/cgroup)
        { echo "cgroup=\$cg"; echo "max=\$(cat /sys/fs/cgroup\$cg/memory.max)"
          echo "swap=\$(cat /sys/fs/cgroup\$cg/memory.swap.max)"; } > "\$STUB_RECORD" ;;
    times)
        s=\$(date +%s%N); sleep "\${STUB_SLEEP:-1}"; e=\$(date +%s%N)
        echo "\$s \$e" >> "\$STUB_TIMES" ;;
esac
echo "pkgtest-way: PASS stub"
"""
        )
        chmod(stub, 0o755)
        function wayenv(
            mode;
            mb="1", lock=joinpath(dir, "lock"), times=joinpath(dir, "times"),
            extra=Pair{String, String}[]
        )
            return Pair{String, String}[
                "LOGICKERNEL_PKGTEST_WAY_JULIA" => stub,
                "LOGICKERNEL_PKGTEST_WAY_OUT" => outd,
                "LOGICKERNEL_PKGTEST_WAY_LOCK" => lock,
                "STUB_MODE" => mode, "STUB_MB" => mb,
                "STUB_RECORD" => joinpath(dir, "record"), "STUB_TIMES" => times, extra...
            ]
        end
        # whatever cap or slice the caller exported does not reach the run (unset BEFORE the case's own env is
        # added: an `env -u` in the command would also remove the case's values), so the defaults are judged
        way_cmd(file, env) = addenv(
            `bash $sh $file`,
            "LOGICKERNEL_INERT_MEM_MAX" => nothing,
            "LOGICKERNEL_INERT_SLICE" => nothing,
            env...
        )
        way(file, env) = _gs_run_merged(way_cmd(file, env))
        peaks() = [split(l, '\t') for l in eachline(joinpath(outd, "peaks.tsv"))]
        unit_active(u) = success(`systemctl --user is-active --quiet $u`)
        pid = getpid()
        slice = "lkgs-memcap-$pid.slice"
        sib = "lkgs-memcap-sib-$pid"
        if have_systemd
            try
                # the stand-in daemon: a process in the lane's slice, beside the test process's scope
                run(
                    `systemd-run --user --unit=$sib --collect --quiet --slice=$slice sleep 600`
                )
                @test unit_active(sib)
                # the scope: its own ceiling (3G by default), no swap, NESTED in the slice it was given
                rm(joinpath(dir, "record"); force=true)
                r = way(
                    "test/test_package.jl",
                    wayenv("where"; extra=["LOGICKERNEL_INERT_SLICE" => slice])
                )
                rec = read(joinpath(dir, "record"), String)
                @test r.code == 0
                @test occursin("max=3221225472\n", rec)
                @test occursin("swap=0\n", rec)
                @test occursin("/$slice/run-", rec) && occursin(".scope\n", rec)
                r = way(
                    "test/test_package.jl",
                    wayenv(
                        "where";
                        extra=[
                            "LOGICKERNEL_INERT_MEM_MAX" => "1G",
                            "LOGICKERNEL_INERT_SLICE" => slice
                        ]
                    )
                )
                @test occursin("max=1073741824\n", read(joinpath(dir, "record"), String))
                # a run without a slice is still its own scope, outside this one
                r = way("test/test_package.jl", wayenv("where"))
                @test r.code == 0
                @test !occursin("/$slice/", read(joinpath(dir, "record"), String))
                # the peak of a run is printed, and kept in peaks.tsv
                rm(joinpath(outd, "peaks.tsv"); force=true)
                r = way("test/test_package.jl", wayenv("hog"; mb="64"))
                m = match(r"peak (\d+) MiB \(cap 3G, oom_kill 0\)", r.out)
                @test r.code == 0 && m !== nothing
                peak = m === nothing ? 0 : parse(Int, m[1])
                # the 64 MiB it touched, and not 3 GiB
                @test 64 <= peak <= 200
                pk = peaks()
                @test length(pk) == 1 &&
                    pk[1][2:end] == ["test_package.jl", string(peak), "3G", "0", "0"]
                # THE KILL: 256 MiB under a 64 MiB cap. The process is killed, named, with its peak; the exit code
                # is the kill's; the sibling in the slice (the daemon) is alive before and after.
                # control: the same hog, default cap
                r = way("test/test_package.jl", wayenv("hog"; mb="256"))
                @test r.code == 0 && !occursin("KILLED", r.out)
                r = way(
                    "test/test_package.jl",
                    wayenv(
                        "hog"; mb="256",
                        extra=[
                            "LOGICKERNEL_INERT_MEM_MAX" => "64M",
                            "LOGICKERNEL_INERT_SLICE" => slice
                        ]
                    )
                )
                @test r.code == 137
                @test occursin(
                    "KILLED — test_package.jl hit its memory cap (64M): peak ", r.out
                )
                m = match(r"peak (\d+) MiB \(cap 64M, oom_kill 1\)", r.out)
                @test m !== nothing && 32 <= parse(Int, m[1]) <= 64
                @test occursin("FAILED (exit 137)", r.out)
                @test occursin("not the daemon", r.out)
                # the daemon survives
                @test unit_active(sib)
                @test peaks()[end][2:end] ==
                    ["test_package.jl", m === nothing ? "" : m[1], "64M", "1", "137"]
            finally
                run(ignorestatus(`systemctl --user stop $sib`))
                run(ignorestatus(`systemctl --user stop $slice`))
            end
        end
        # NEVER CONCURRENTLY: two runs started together run one after the other (a lock, .warm/pkgtest_way.lock).
        # The control: with a lock apiece the same two runs DO overlap, so the assertion can fail.
        function overlapped(l1, l2)
            tf = joinpath(dir, "times_$(basename(l1))_$(basename(l2))")
            rm(tf; force=true)
            jobs = []
            for (file, lock) in
                (("test/test_package.jl", l1), ("test/test_commit_msg_hook.jl", l2))
                o = joinpath(dir, "seq_$(basename(file))_$(basename(lock)).log")
                io = open(o, "w")
                p = run(
                    pipeline(
                        ignorestatus(
                            way_cmd(
                                file,
                                wayenv(
                                    "times"; lock=lock, times=tf,
                                    extra=["STUB_SLEEP" => "1"]
                                )
                            )
                        );
                        stdin=devnull, stdout=io, stderr=io
                    ); wait=false
                )
                push!(jobs, (p, io, o))
            end
            foreach(j -> wait(j[1]), jobs)
            foreach(j -> close(j[2]), jobs)
            iv = sort([parse.(Int, split(l)) for l in eachline(tf)]; by=first)
            logs = join([read(j[3], String) for j in jobs])
            return (iv=iv, logs=logs, codes=[j[1].exitcode for j in jobs])
        end
        seq = overlapped(joinpath(dir, "lock_a"), joinpath(dir, "lock_a"))
        @test seq.codes == [0, 0] && length(seq.iv) == 2
        # the first ended before the second began
        @test seq.iv[1][2] <= seq.iv[2][1]
        @test occursin("another Pkg.test-way run holds", seq.logs)
        par = overlapped(joinpath(dir, "lock_b"), joinpath(dir, "lock_c"))
        @test par.codes == [0, 0] && length(par.iv) == 2
        @test par.iv[1][2] > par.iv[2][1]                        # the control overlaps
        @test !occursin("another Pkg.test-way run holds", par.logs)
        # warm.sh's step runs the files one after the other in its own process, hands the lane's slice on, prints the
        # peak, and finishes before the branch-gate's first file: nothing of it runs beside the daemon's own file run
        warm = read(joinpath(_GS_ROOT, "tools", "warm.sh"), String)
        ie = match(r"(?s)\n_inert_check\(\) \{\n(.*?)\n\}\n", warm)[1]
        @test occursin(
            "        LOGICKERNEL_INERT_SLICE=\"\$(_lane_slice)\" \"\$ROOT/tools/pkgtest_way.sh\" \"\$f\" > \"\$log\" 2>&1\n        prc=\$?",
            ie
        )
        @test occursin("grep -h '^pkgtest_way: .* peak ' \"\$log\"", ie)
        @test !occursin(r"(?m)&\s*$", ie) && !occursin(r"(?m)^\s*wait\b", ie)
        ls = match(r"(?s)\n_lane_slice\(\) \{\n(.*?)\n\}\n", warm)[1]
        @test occursin("elif [ -f \"\$DIR/second\" ]; then echo lk-warm2.slice", ls)
        @test occursin("else echo lk-warm.slice; fi", ls)
        bg = match(r"(?s)\n_branch_gate\(\) \{\n(.*?)\n\}\n", warm)[1]
        @test findfirst("_checks_fresh ||", bg).start <
            findfirst("_file \"\$f\" > \"\$log\"", bg).start
        cf = match(r"(?s)\n_checks_fresh\(\) \{\n(.*?)\n\}\n", warm)[1]
        @test !occursin(r"(?m)&\s*$", cf)
        if have_systemd
            # …and through the real step: the slice a second-daemon lane names carries the run's scope
            try
                rm(joinpath(dir, "record"); force=true)
                tf = tempname()
                write(tf, "")
                inert_env(slice_, budget) = Pair{String, String}[
                    "LOGICKERNEL_WARM_SEND_PROBE" => "1",
                    "LOGICKERNEL_FILE_TIMES" => tf,
                    "LOGICKERNEL_INERT_FILES" => "test/test_package.jl",
                    "LOGICKERNEL_SHARED_BUDGET" => budget,
                    "LOGICKERNEL_SLICE" => slice_,
                    wayenv("where")...
                ]
                step(env) = _gs_run_merged(
                    addenv(
                        `bash $(joinpath(_GS_ROOT, "tools", "warm.sh")) inert-check`,
                        env...
                    )
                )
                r = step(inert_env(slice, "1"))
                @test r.code == 0
                @test occursin("Pkg.test-way run clean (1 changed test files", r.out)
                @test occursin(
                    r"pkgtest_way: test_package\.jl peak \d+ MiB \(cap 3G, oom_kill 0\)",
                    r.out
                )
                @test occursin("/$slice/", read(joinpath(dir, "record"), String))
                rm(joinpath(dir, "record"); force=true)
                # no shared budget (CI): no slice named
                r = step(inert_env(slice, "0"))
                @test r.code == 0
                @test !occursin("/$slice/", read(joinpath(dir, "record"), String))
                rm(tf; force=true)
            finally
                run(ignorestatus(`systemctl --user stop $slice`))
            end
        end
    end

    @testset "tools/ci_status.sh and _ci_gate judge the previous push" begin
        sha = "0123456789abcdef0123456789abcdef01234567"
        run_(name, status, conclusion; s=sha, branch="main", at="", wid=name) =
            "{\"head_sha\":\"$s\",\"name\":\"$name\",\"status\":\"$status\"," *
            "\"conclusion\":$(conclusion === nothing ? "null" : "\"$conclusion\"")," *
            "\"head_branch\":\"$branch\",\"created_at\":\"$at\",\"workflow_id\":\"$wid\"," *
            "\"html_url\":\"https://x/1\"}"
        fixtures = [
            ("green", "[" * run_("CI", "completed", "success") * "]", 0),
            ("red", "[" * run_("CI", "completed", "failure") * "]", 1),
            ("cancelled", "[" * run_("CI", "completed", "cancelled") * "]", 1),
            # a CANCELLED run is superseded only by a LATER green run of the SAME workflow on the
            # SAME ref (MEASURED 2026-10-20: a re-pushed tag cancelled the first tag push's CI)
            (
                "cancelled, then re-run green",
                "[" * run_("CI", "completed", "cancelled"; at="2026-10-20T16:24:21Z") *
                "," *
                run_("CI", "completed", "success"; at="2026-10-20T16:41:36Z") * "]",
                0
            ),
            (
                "cancelled AFTER the green run",
                "[" * run_("CI", "completed", "cancelled"; at="2026-10-20T17:00:00Z") *
                "," *
                run_("CI", "completed", "success"; at="2026-10-20T16:41:36Z") * "]",
                1
            ),
            (
                "cancelled, a green run of another workflow",
                "[" * run_("CI", "completed", "cancelled"; at="2026-10-20T16:24:21Z") *
                "," *
                run_("Other", "completed", "success"; at="2026-10-20T16:41:36Z") * "]",
                1
            ),
            (
                "cancelled, a green run on another ref",
                "[" * run_("CI", "completed", "cancelled"; at="2026-10-20T16:24:21Z") *
                "," *
                run_("CI", "completed", "success"; branch="v1", at="2026-10-20T16:41:36Z") *
                "]",
                1
            ),
            (
                "cancelled, a later green run of ANOTHER commit on the same ref (D-0071 1)",
                "[" * run_("CI", "completed", "cancelled"; at="2026-10-20T16:24:21Z") *
                "," *
                run_("CI", "completed", "success"; s="f" ^ 40, at="2026-10-20T16:41:36Z") *
                "]",
                1
            ),
            (
                "cancelled, a later green run of a workflow with the same name but another id",
                "[" *
                run_("CI", "completed", "cancelled"; at="2026-10-20T16:24:21Z", wid="1") *
                "," *
                run_("CI", "completed", "success"; at="2026-10-20T16:41:36Z", wid="2") *
                "]",
                1
            ),
            (
                "cancelled, the later run only 'neutral' (D-0071: success alone supersedes)",
                "[" * run_("CI", "completed", "cancelled"; at="2026-10-20T16:24:21Z") *
                "," *
                run_("CI", "completed", "neutral"; at="2026-10-20T16:41:36Z") * "]",
                1
            ),
            [
                (
                    "$c, then re-run green (D-0071 2: only `cancelled` is superseded)",
                    "[" * run_("CI", "completed", c; at="2026-10-20T16:24:21Z") * "," *
                    run_("CI", "completed", "success"; at="2026-10-20T16:41:36Z") * "]",
                    1
                ) for c in ("timed_out", "startup_failure", "action_required", "stale")
            ]...,
            (
                "failed, then re-run green (a failure is never superseded)",
                "[" * run_("CI", "completed", "failure"; at="2026-10-20T16:24:21Z") * "," *
                run_("CI", "completed", "success"; at="2026-10-20T16:41:36Z") * "]",
                1
            ),
            (
                "cancelled without a timestamp, a green run",
                "[" * run_("CI", "completed", "cancelled") * "," *
                run_("CI", "completed", "success"; at="2026-10-20T16:41:36Z") * "]",
                1
            ),
            (
                "cancelled, a later run still going",
                "[" * run_("CI", "completed", "cancelled"; at="2026-10-20T16:24:21Z") *
                "," *
                run_("CI", "in_progress", nothing; at="2026-10-20T16:41:36Z") * "]",
                1
            ),
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

    # CISTATUS (audit D-0262, cause A-0168): three `Mutation battery` workflow_dispatch runs of
    # 09c9f07 failed at their Plan step (no mutant ran) and made the commit read RED for good. The
    # fixture's `jobs` maps a run id to the answer of GET <jobs_url>; the shapes are the real ones
    # (job names Plan / Baseline (unmutated) / matrix.name / Verdict table, measured 2026-10-31).
    @testset "tools/ci_status.sh: a dispatch that failed at its Plan step is no verdict (CISTATUS)" begin
        sha = "09c9f0715768c51265b4a2f459a40bcea9a9fb1e"
        run_(id, name, event, conclusion; at="2026-10-30T20:38:33Z") =
            "{\"id\":$id,\"head_sha\":\"$sha\",\"name\":\"$name\",\"event\":\"$event\"," *
            "\"status\":\"completed\",\"conclusion\":\"$conclusion\",\"head_branch\":\"main\"," *
            "\"created_at\":\"$at\",\"workflow_id\":\"$name\",\"html_url\":\"https://x/$id\"," *
            "\"jobs_url\":\"https://x/$id/jobs\"}"
        job_(name, conclusion) = "{\"name\":\"$name\",\"status\":\"completed\",\"conclusion\":\"$conclusion\"}"
        jobs_(js...) = "{\"jobs\":[" * join([job_(n, c) for (n, c) in js], ",") * "]}"
        # what the three real runs showed: Plan failed, Verdict table failed after it, the rest skipped
        planfail = jobs_(
            "Plan" => "failure", "Verdict table" => "failure",
            "Baseline (unmutated)" => "skipped", "matrix.name" => "skipped"
        )
        # a REAL battery failure: Plan passed, a mutant job and the table are red
        realfail = jobs_(
            "Plan" => "success", "Verdict table" => "failure",
            "Baseline (unmutated)" => "success", "S1" => "failure"
        )
        # Plan failed but something ELSE also ran and failed: not a pure Plan failure
        mixed = jobs_(
            "Plan" => "failure", "Verdict table" => "failure",
            "Baseline (unmutated)" => "failure", "matrix.name" => "skipped"
        )
        three = [
            run_(41124826803, "Mutation battery", "workflow_dispatch", "failure"),
            run_(41124901359, "Mutation battery", "workflow_dispatch", "failure"),
            run_(41124983027, "Mutation battery", "workflow_dispatch", "failure")
        ]
        threejobs = join(
            ["\"$id\":$planfail" for id in (41124826803, 41124901359, 41124983027)], ","
        )
        green = [
            run_(41126115441, "Mutation battery", "workflow_dispatch", "success"),
            run_(41108160669, "CI", "push", "success"),
            run_(41104264503, "Evidence (three term types)", "push", "success")
        ]
        tool = joinpath(_GS_ROOT, "tools", "ci_status.sh")
        mktempdir() do d
            status(runs, jobs) = begin
                f = joinpath(d, "f.json")
                write(
                    f,
                    "{\"workflow_runs\":[" * join(runs, ",") * "],\"jobs\":{" * jobs * "}}"
                )
                outp = IOBuffer()
                p = run(
                    pipeline(
                        ignorestatus(addenv(`$tool $sha`, "LOGICKERNEL_CI_FIXTURE" => f));
                        stdout=outp, stderr=devnull
                    )
                )
                (p.exitcode, String(take!(outp)))
            end
            # the three known Plan failures beside the green runs: GREEN, and printed as ignored
            code, text = status([three; green], threejobs)
            @test code == 0
            @test count("dispatch failed at Plan: no verdict", text) == 3
            # a real battery failure (Plan green) is still RED
            @test status(
                [
                    green;
                    run_(41200000001, "Mutation battery", "workflow_dispatch", "failure")
                ],
                "\"41200000001\":$realfail"
            )[1] == 1
            # a Plan failure with another failed job beside it is still RED
            @test status(
                [
                    green;
                    run_(41200000002, "Mutation battery", "workflow_dispatch", "failure")
                ],
                "\"41200000002\":$mixed"
            )[1] == 1
            # one real failure among the three ignored ones: RED
            @test status(
                [
                    three;
                    green;
                    run_(41200000001, "Mutation battery", "workflow_dispatch", "failure")
                ],
                threejobs * ",\"41200000001\":$realfail"
            )[1] == 1
            # a failed PUSH-triggered run is RED even with the same job shape (CI, Evidence)
            @test status(
                [green; run_(41200000003, "CI", "push", "failure")],
                "\"41200000003\":$planfail"
            )[1] == 1
            @test status(
                [
                    green;
                    run_(41200000004, "Evidence (three term types)", "push", "failure")
                ],
                "\"41200000004\":$planfail"
            )[1] == 1
            # a dispatch whose jobs cannot be read (no entry in the fixture) stays RED
            @test status(
                [
                    green;
                    run_(41200000005, "Mutation battery", "workflow_dispatch", "failure")
                ],
                ""
            )[1] == 1
            # a Plan failure that is only 'cancelled' (not failure) is not excused either
            @test status(
                [
                    green;
                    run_(41200000006, "Mutation battery", "workflow_dispatch", "cancelled")
                ],
                "\"41200000006\":" *
                jobs_("Plan" => "cancelled", "matrix.name" => "skipped")
            )[1] == 1
            # pending stays 3: an ignored Plan failure does not turn an in-progress run into a verdict
            f = joinpath(d, "p.json")
            write(
                f,
                "{\"workflow_runs\":[" * join(three, ",") * "," *
                replace(
                    run_(41200000007, "CI", "push", "x"),
                    "\"status\":\"completed\",\"conclusion\":\"x\"" => "\"status\":\"in_progress\",\"conclusion\":null"
                ) *
                "],\"jobs\":{" * threejobs * "}}"
            )
            @test run(
                pipeline(
                    ignorestatus(addenv(`$tool $sha`, "LOGICKERNEL_CI_FIXTURE" => f));
                    stdout=devnull
                )
            ).exitcode == 3
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
            # (BP2, audit D-0221) a pin with `backports:` is judged against the build WITH them, which `oracle:`
            # names: that build's version_git, not the pin's `commit:`; backports without an `oracle:`, or an
            # `oracle:` without backports, names no build at all
            orc = "89abcdef0123456789abcdef0123456789abcdef"
            pin(
                "version: 9.9.9\ncommit: $commit\nbackports: $other $commit\noracle: $orc\n"
            )
            fake("9.9.9", "9.9.9-3-g" * orc[1:9])
            @test both() == (0, 0)                              # the oracle with its backports
            fake("9.9.9", "9.9.9-1-g" * commit[1:9])
            @test both() == (1, 1)                              # the pin's commit alone: backports missing
            fake("9.9.9", "9.9.9-3-g" * other[1:9])
            @test both() == (1, 1)                              # a build of another commit
            pin("version: 9.9.9\ncommit: $commit\nbackports: $other\n")
            fake("9.9.9", "9.9.9-2-g" * commit[1:9])
            @test both() == (1, 1)                              # backports, no oracle:
            pin("version: 9.9.9\ncommit: $commit\noracle: $orc\n")
            fake("9.9.9", "9.9.9-1-g" * orc[1:9])
            @test both() == (1, 1)                              # an oracle:, no backports
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
                # a push BY URL (git hands the URL as $1) reads the remote configured with that
                # URL (the v0.1.0-pre.2 tag push, 2026-10-23: `--remotes=<URL>` matched nothing)
                run(`git -C $repo remote add up https://tok@example.invalid/lk.git`)
                run(`git -C $repo update-ref refs/remotes/up/gate/old $badc`)
                ontop = gs_commit(noreply, noreply)
                by(url, s) = exitof(
                    pipeline(
                        IOBuffer("refs/tags/t $s refs/tags/t $("0" ^ 40)\n"),
                        Cmd(`bash $hook $url $url`; dir=repo)
                    ),
                    "LOGICKERNEL_CI_FIXTURE" => fx,
                    "LOGICKERNEL_PUSH_LOCAL_EVIDENCE" => nothing
                )
                @test by("https://example.invalid/lk.git", ontop) == 0       # mapped, credential stripped
                @test by("up", ontop) == 0                                   # by its name
                @test by("https://example.invalid/other.git", ontop) == 1    # no such remote: all new
                @test by(
                    "https://example.invalid/lk.git",
                    gs_commit("someone@gmail.example", noreply)
                ) ==
                    1                                                        # a new bad commit still refused
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
            # 5. A mutants/<name> BRANCH NEEDS tools/mutants/<name>.py IN THE PUSHED COMMIT
            # (user, 2026-10-24): mutation.yml reads its list from the branch name
            @testset "a mutants/ branch needs its list file" begin
                @test push_(sha, "refs/heads/mutants/MutX") == 1           # no list file: refused
                # the earlier testsets left a refused (non-noreply) commit in HEAD's history: mark
                # everything so far as already on the remote, so only this rule decides below
                run(`git -C $repo update-ref refs/remotes/origin/gate/mut HEAD`)
                mkpath(joinpath(repo, "tools", "mutants"))
                write(joinpath(repo, "tools", "mutants", "MutX.py"), "MUTANTS = []\n")
                run(`git -C $repo add tools/mutants/MutX.py`)
                no_targets = gs_commit(noreply, noreply)
                @test push_(no_targets, "refs/heads/mutants/MutX") == 1    # no TARGETS: refused
                run(`git -C $repo update-ref refs/remotes/origin/gate/mut HEAD`)
                write(
                    joinpath(repo, "tools", "mutants", "MutX.py"),
                    "TARGETS = [\"t.jl\"]\nMUTANTS = []\n"
                )
                run(`git -C $repo add tools/mutants/MutX.py`)
                with_list = gs_commit(noreply, noreply)
                @test push_(with_list, "refs/heads/mutants/MutX") == 0     # list file with TARGETS
                @test push_(with_list, "refs/heads/mutants/MutY") == 1     # another name: refused
                @test push_(with_list, "refs/heads/gate/MutY") == 0        # not a mutants/ ref
                @test push_("0" ^ 40, "refs/heads/mutants/MutY") == 0      # a delete is allowed
            end
        end
        rm(gs_dir; recursive=true)
    end
    # CI'S EVIDENCE RUN IS SPREAD OVER JOBS (user, 2026-10-13; sharded, D-0059 2026-10-20): term type ×
    # file group, and the static analysis in shards of its own; tools/evidence_ci.py judges them
    # together. Planted unit lists and counts: a job that skipped a unit, ran another job's, ran as the
    # wrong slice, analysed nothing or died must not read as green.
    @testset "tools/evidence_ci.py: green jobs that do not PARTITION the suite are not green" begin
        tool = joinpath(_GS_ROOT, "tools", "evidence_ci.py")
        sa_l = "test_static_analysis.jl"
        impls = Dict(
            "a.jl" => "reference", "b.jl" => "reference", sa_l => "reference",
            "g.jl" => "reference", "g.jl [alt]" => "alt",
            "g.jl [alt_interned]" => "alt_interned", "h.jl" => "reference",
            "h.jl [alt]" => "alt", "h.jl [alt_interned]" => "alt_interned"
        )
        all_ = sort!(collect(keys(impls)))
        # two file groups per type: {a.jl, g.jl} and {b.jl, h.jl}; two static-analysis shards
        good = Dict(
            "reference_g1" => ["a.jl", "g.jl"], "reference_g2" => ["b.jl", "h.jl"],
            "alt_g1" => ["g.jl [alt]"], "alt_g2" => ["h.jl [alt]"],
            "alt_interned_g1" => ["g.jl [alt_interned]"],
            "alt_interned_g2" => ["h.jl [alt_interned]"],
            "sa_1" => [sa_l], "sa_2" => [sa_l]
        )
        slice(job) =
            if startswith(job, "sa_")
                "sa_shard\t$(job[end])\t2\treference"
            elseif startswith(job, "julia-")
                "file_group\t$(job[end])\t2\t"
            else
                "file_group\t$(job[end])\t2\t$(job[1:(end - 3)])"
            end
        stats(job) =
            if startswith(job, "alt_interned")
                "0\t5\t2"
            else
                (
                    if startswith(job, "alt")
                        "7\t0\t0"
                    else
                        (startswith(job, "julia-") ? "7\t5\t2" : "0\t0\t0")
                    end
                )
            end
        sa_counts(k) =
            "shard\t$k\t2\nparts\taqua,controls\npart\t$(k == 1 ? "aqua" : "controls")\n" *
            "dispatch\t$(k == 1 ? 3 : 2)\t5\nalloc\t1\t2\n"
        "The tool's exit, output and unit_costs.tsv over planted files: `edit(files)` changes the good set."
        function vrun(
            edit=identity; mode=["verdict", "2", "2"], ran=good, suite=all_, ci=nothing
        )
            files = Dict{String, String}()
            for (job, r) in ran
                files["units_$job.tsv"] =
                    "slice\t$(slice(job))\n" *
                    join(["all\t$u\t$(impls[u])\n" for u in suite]) *
                    join(["ran\t$u\t3\t0\t1.5\n" for u in r]) * "stats\t$(stats(job))\n"
                files["row_$job.md"] = "| $job | passed | 1 s |\n"
            end
            any(startswith("sa_"), keys(ran)) &&
                foreach(k -> files["sa_$k.tsv"] = sa_counts(k), 1:2)
            edit(files)
            mktempdir() do d
                foreach(((n, t),) -> write(joinpath(d, n), t), files)
                out = joinpath(d, "stdout.txt")
                code = withenv("GITHUB_ACTIONS" => ci) do
                    run(
                        pipeline(
                            ignorestatus(`python3 $tool $(mode[1]) $d $(mode[2:end])`);
                            stdout=out, stderr=devnull
                        )
                    ).exitcode
                end
                costs = joinpath(d, "unit_costs.tsv")
                (
                    code=code,
                    out=read(out, String),
                    costs=isfile(costs) ? read(costs, String) : ""
                )
            end
        end
        verdict(args...; kw...) = vrun(args...; kw...).code
        drop(n) = fs -> delete!(fs, n)
        put(n, t) = fs -> (fs[n] = t)
        @test verdict() == 0                                       # the positive control
        @test verdict(; ran=merge(good, Dict("alt_g2" => String[]))) == 1     # run by no job
        @test verdict(; ran=merge(good, Dict("alt_g2" => ["h.jl [alt]", "g.jl [alt]"]))) ==
            1  # by two
        @test verdict(; ran=merge(good, Dict("alt_g2" => ["h.jl [alt]", "h.jl"]))) == 1  # another type's
        @test verdict(; ran=merge(good, Dict("reference_g2" => ["b.jl", "h.jl", sa_l]))) ==
            1 # the SA in a group
        @test verdict(; ran=merge(good, Dict("sa_2" => [sa_l, "a.jl"]))) == 1  # a shard ran more
        @test verdict(drop("row_alt_g2.md")) == 1                  # a job died without a row
        @test verdict(
            fs -> (delete!(fs, "row_alt_g2.md"); delete!(fs, "units_alt_g2.tsv"))
        ) == 1 # a DROPPED job
        @test verdict(put("row_alt_g1.md", "| alt_g1 | **FAILED** | — |\n")) == 1   # a job failed
        @test verdict(
            fs -> (
                fs["units_alt_g1.tsv"] = replace(
                    fs["units_alt_g1.tsv"], "\t1\t2\talt" => "\t2\t2\talt"
                )
            )
        ) == 1                                                     # ran as the wrong slice
        @test verdict(
            fs -> (
                fs["units_alt_g1.tsv"] = replace(
                    fs["units_alt_g1.tsv"], "all\th.jl\treference\n" => ""
                )
            )
        ) == 1                                                     # enumerated a different suite
        @test verdict(put("units_alt_interned_g2.tsv", "")) == 1  # an empty unit list
        @test verdict(; suite=String[], ran=Dict(j => String[] for j in keys(good))) == 1 # an EMPTY suite
        @test verdict(
            fs -> foreach(
                j -> (
                    fs["units_$j.tsv"] = replace(
                        fs["units_$j.tsv"], "stats\t0\t5\t2" => "stats\t0\t5\t0"
                    )
                ),
                ("alt_interned_g1", "alt_interned_g2")
            )
        ) == 1                                                     # the interned type shared nothing
        # the static analysis's shards
        @test verdict(
            fs -> (
                delete!(fs, "sa_2.tsv");
                delete!(fs, "row_sa_2.md");
                delete!(fs, "units_sa_2.tsv")
            )
        ) == 1
        @test verdict(drop("sa_2.tsv")) == 1                       # a shard wrote no counts
        @test verdict(
            put("sa_2.tsv", replace(sa_counts(2), "dispatch\t2\t5" => "dispatch\t0\t5"))
        ) == 1 # analysed nothing
        @test verdict(
            put("sa_2.tsv", replace(sa_counts(2), "dispatch\t2\t5" => "dispatch\t1\t5"))
        ) == 1 # sum short
        @test verdict(
            put("sa_2.tsv", replace(sa_counts(2), "alloc\t1\t2" => "alloc\t1\t3"))
        ) == 1  # two totals
        @test verdict(
            put("sa_2.tsv", replace(sa_counts(2), "part\tcontrols" => "part\taqua"))
        ) == 1 # a part twice, one never
        @test verdict(
            put("sa_2.tsv", replace(sa_counts(2), "shard\t2\t2" => "shard\t1\t2"))
        ) == 1  # the wrong shard
        @test verdict(; mode=["verdict", "2", "3"]) == 1           # a shard of three never ran
        @test verdict(; mode=["verdict", "3", "2"]) == 1           # a group of three never ran
        # one term type's gather, and the static analysis's alone
        @test verdict(; mode=["term", "alt", "2"]) == 0
        @test verdict(drop("units_alt_g2.tsv"); mode=["term", "alt", "2"]) == 1
        @test verdict(drop("units_reference_g2.tsv"); mode=["term", "alt", "2"]) == 0  # not alt's
        @test verdict(; mode=["sa", "2"]) == 0
        @test verdict(drop("sa_1.tsv"); mode=["sa", "2"]) == 1
        # CI.yml's Pkg.test groups: every type in each, the static analysis in none
        pk = Dict(
            "julia-1_g1" => ["a.jl", "g.jl", "g.jl [alt]", "g.jl [alt_interned]"],
            "julia-1_g2" => ["b.jl", "h.jl", "h.jl [alt]", "h.jl [alt_interned]"]
        )
        @test verdict(; mode=["pkgtest", "1", "2"], ran=pk) == 0
        @test verdict(;
            mode=["pkgtest", "1", "2"],
            ran=merge(pk, Dict("julia-1_g2" => ["b.jl", "h.jl"]))
        ) == 1
        # THE MESSAGE, NOT ONLY THE EXIT (Tooling4's battery, 2026-10-20): a check whose problem is
        # also raised by another check cannot be told apart by an exit code. Each case below asserts
        # the problem the check alone names.
        let r = vrun(; suite=String[], ran=Dict(j => String[] for j in keys(good)))
            @test r.code == 1 && occursin("the full unit list is EMPTY", r.out)
        end
        let r = vrun(drop("units_alt_g2.tsv"))        # a row, but no unit list
            @test r.code == 1 && occursin("alt_g2: no unit list", r.out)
        end
        let r = vrun(
                put("sa_2.tsv", replace(sa_counts(2), "dispatch\t2\t5" => "dispatch\t0\t5"))
            )
            @test r.code == 1 && occursin("sa_2: dispatch analysed NOTHING", r.out)
        end
        let r = vrun(
                put("sa_2.tsv", replace(sa_counts(2), "part\tcontrols" => "part\taqua"))
            )
            @test r.code == 1 && occursin("part aqua ran 2 times", r.out)      # twice
            @test occursin("part controls ran 0 times", r.out)                  # never
        end
        let r = vrun(drop("sa_2.tsv"))
            @test r.code == 1 && occursin("sa_2: no counts", r.out)
        end
        let r = vrun(
                put(
                    "sa_2.tsv",
                    replace(sa_counts(2), "parts\taqua,controls" => "parts\tcontrols,aqua")
                )
            )
            @test r.code == 1 && occursin("sa_2: a different list of parts", r.out)
        end
        let r = vrun(; mode=["sa", "0"])               # no shard at all: no full count
            @test r.code == 1 && occursin("a full count is zero or missing", r.out)
        end
        let r = vrun(
                fs -> (
                    fs["units_alt_g1.tsv"] = replace(
                        fs["units_alt_g1.tsv"], r"stats\t[^\n]*\n" => ""
                    )
                )
            )
            @test r.code == 1 && occursin("alt: a slice wrote no AltTerm counts", r.out)
        end
        let r = vrun(; suite=filter(!=(sa_l), all_))
            @test r.code == 1 && occursin("the suite has no $sa_l", r.out)
        end
        let r = vrun(; ci="true")   # in CI the costs are also ONE annotation (readable without a token)
            n = filter(startswith("::notice title=unit-costs::"), split(r.out, '\n'))
            @test r.code == 0 && length(n) == 1
            @test occursin("a.jl=1.5;", n[1]) && occursin("h.jl=4.5", n[1])
            @test !occursin(sa_l, n[1])
            @test isempty(
                filter(startswith("::notice title=unit-costs::"), split(vrun().out, '\n'))
            )
        end
        let r = vrun()          # the unit costs: every file with its seconds, the SA in none
            @test r.code == 0 && occursin("a.jl\t", r.costs) && occursin("h.jl\t", r.costs)
            @test !occursin(sa_l, r.costs)
        end
        @test verdict(; mode=["pkgtest", "min", "2"], ran=pk) == 1  # another version's jobs
    end
    # THE SLICES THEMSELVES (test/ci_slices.jl): a total, deterministic, balanced assignment
    @testset "test/ci_slices.jl: the file groups and the slice variable" begin
        cs = Module(:GSSlices)
        Base.include(cs, joinpath(_GS_ROOT, "test", "ci_slices.jl"))
        files = ["f$i.jl" for i in 1:9]
        costs = Dict("f1.jl" => 90.0, "f2.jl" => 60.0, "f3.jl" => 50.0, "f4.jl" => 40.0,
            "f5.jl" => 10.0)                                       # f6…f9: the median, 50
        g = cs.lk_file_groups(files, 3, costs)
        @test sort!(collect(keys(g))) == sort(files)               # every file, one group
        @test all(in(1:3), values(g)) && length(unique(values(g))) == 3
        @test g == cs.lk_file_groups(reverse(files), 3, costs)     # independent of the order
        load = [sum(get(costs, f, 50.0) for f in files if g[f] == k) for k in 1:3]
        @test maximum(load) - minimum(load) <= 40                  # LPT: within the smallest job
        @test cs.lk_file_groups(files, 1, costs) == Dict(f => 1 for f in files)
        @test cs.lk_file_groups(files, 3, Dict{String, Float64}()) ==
            cs.lk_file_groups(files, 3, Dict{String, Float64}())
        @test [count(i -> cs.lk_in_slice(i, (k, 4)), 1:10) for k in 1:4] == [3, 3, 2, 2]
        sl(v) = withenv(() -> cs.lk_slice("GS_SLICE"), "GS_SLICE" => v)
        @test sl(nothing) == (1, 1) && sl("") == (1, 1) && sl("3/8") == (3, 8)
        for bad in ("0/2", "3/2", "2", "a/b", "1/0", " 1/2")
            @test_throws ErrorException sl(bad)
        end
        tbl = cs.lk_unit_costs(joinpath(_GS_ROOT, "test", "unit_costs.tsv"))
        # (a MEASURED 0.0 is a real cost: test_check_bounds.jl takes under 50 ms)
        @test !isempty(tbl) && all(>=(0), values(tbl)) && any(>(0), values(tbl))   # it reads
        @test all(f -> isfile(joinpath(_GS_ROOT, "test", f)), keys(tbl))   # …and names real files
    end
    # THE PKG.TEST COST TABLE (D-0091 item 3): the pkgtest gather's `unit-costs` annotation becomes
    # test/pkgtest_costs.tsv, which balances CI.yml's `test` groups (Evidence's costs, measured without
    # coverage, left the `Julia 1` groups at 1004 / 483 / 559 s). The table is validated before it is
    # written, the API is read from planted answers, and the python balance equals ci_slices.jl's.
    @testset "tools/pkgtest_costs.py: the notice becomes the table the Pkg.test groups are balanced by" begin
        tool = joinpath(_GS_ROOT, "tools", "pkgtest_costs.py")
        pk(args...; stdin=devnull, env=Pair{String, Any}[]) = mktempdir() do d
            out = joinpath(d, "out.txt")
            code = withenv(env...) do
                run(
                    pipeline(
                        ignorestatus(`python3 $tool $args`); stdin=stdin, stdout=out,
                        stderr=devnull
                    )
                ).exitcode
            end
            (code=code, out=read(out, String))
        end
        parse_(text; extra=String[]) = mktempdir() do d
            f = joinpath(d, "notice.txt")
            write(f, text)
            o = joinpath(d, "table.tsv")
            res = pk("parse", f, o, extra...)          # (not `r`: the closure would assign the testset's)
            (code=res.code, msg=res.out, table=isfile(o) ? read(o, String) : "")
        end
        good = "b/test_b.jl=2.5;a.jl=10.0;c.jl=0.0"
        r = parse_("::notice title=unit-costs::$good\n", extra=["--source", "SRC-TEXT"])
        @test r.code == 0 && occursin("wrote", r.msg) && occursin("(3 entries)", r.msg)
        rows = [l for l in split(r.table, '\n') if !isempty(l) && l[1] != '#']
        @test rows == ["a.jl\t10.0", "b/test_b.jl\t2.5", "c.jl\t0.0"]     # sorted, one decimal
        @test occursin("# Measured: SRC-TEXT", r.table) &&
            occursin("Pkg.test WITH COVERAGE", r.table)
        let alone = parse_(good)                                         # the message alone
            @test alone.code == 0 &&
                filter(!startswith("#"), split(alone.table, '\n')) ==
                  filter(!startswith("#"), split(r.table, '\n'))
        end
        # a half-read or wrong annotation is refused, each for its own reason
        for (text, why) in (
            ("::notice title=other::$good", "not unit-costs"),
            ("", "empty"),
            ("a.jl=1.0;a.jl=2.0", "listed twice"),
            ("a.jl=fast", "not a number"),
            ("a.jl=-1.0", "non-negative"),
            ("a.jl=NaN", "non-negative"),
            ("a.jl=Infinity", "non-negative"),
            ("a.jl=1.0;", "not a file=seconds"),
            ("a.jl=1.0;b.jl", "not a file=seconds"),
            ("a.jl=1.0;b.txt=2.0", "not a test file name"),
            ("a.jl=1.0;test_static_analysis.jl=900.0", "static analysis"),
            ("a.jl=1.0;core_lang/test_static_analysis.jl=900.0", "static analysis")
        )
            r = parse_(text)
            @test r.code == 1 && occursin(why, r.msg) && r.table == ""
        end
        @test pk("parse").code == 2 && pk("nonsense").code == 2 && pk().code == 2
        mktempdir() do d                                                 # …or from stdin
            f = joinpath(d, "in.txt")
            write(f, "::notice title=unit-costs::a.jl=1.5")
            r = pk("parse", "-"; stdin=f)
            @test r.code == 0 && occursin("a.jl\t1.5\n", r.out)
        end
        # `fetch` from planted API answers (LOGICKERNEL_GH_FIXTURE): the gather job of the Julia version
        job(id, name, conclusion) = """{"id": $id, "name": "$name", "conclusion": "$conclusion", "head_sha": "0123456789abcdef"}"""
        ann(title, msg) = """{"title": "$title", "message": "$msg"}"""
        function fetch_(jobs, anns; args=["fetch", "777"])
            mktempdir() do d
                write(joinpath(d, "jobs.json"), """{"jobs": [$(join(jobs, ","))]}""")
                write(joinpath(d, "annotations.json"), "[$(join(anns, ","))]")
                o = joinpath(d, "table.tsv")
                res = pk(args..., o; env=["LOGICKERNEL_GH_FIXTURE" => d])   # (not `r`: see parse_)
                (code=res.code, msg=res.out, table=isfile(o) ? read(o, String) : "")
            end
        end
        jobs = [
            job(11, "Julia 1 - ubuntu-24.04", "success"),
            job(12, "Julia min - ubuntu-24.04", "success"),
            job(13, "Julia 1 · files 1/3", "success")
        ]
        anns = [
            ann("unit-costs", good), ann("Julia 1 — Pkg.test, 3 file groups", "3 units")
        ]
        r = fetch_(jobs, anns)
        @test r.code == 0 && occursin("(3 entries)", r.msg)
        @test occursin(
            "# Measured: run 777 (0123456), Julia 1 - ubuntu-24.04, job 11", r.table
        )
        r = fetch_(jobs, anns; args=["fetch", "777", "--version", "min"])
        @test r.code == 0 && occursin("job 12", r.table)
        r = fetch_(jobs, anns; args=["fetch", "777", "--version", "2"])    # no such gather job
        @test r.code == 1 && occursin("0 job(s) named", r.msg)
        r = fetch_([job(11, "Julia 1 - ubuntu-24.04", "failure")], anns)   # a red gather: no measurement
        @test r.code == 1 && occursin("not success", r.msg) && r.table == ""
        r = fetch_(jobs, [ann("Other", "x")])                                # no notice at all
        @test r.code == 1 && occursin("0 unit-costs annotation(s)", r.msg)
        r = fetch_(jobs, [ann("unit-costs", good), ann("unit-costs", good)])  # ambiguous
        @test r.code == 1 && occursin("2 unit-costs annotation(s)", r.msg)
        r = fetch_(jobs, [ann("unit-costs", "a.jl=oops")])                   # an invalid notice
        @test r.code == 1 && occursin("not a number", r.msg) && r.table == ""
        r = fetch_(jobs, anns; args=["fetch", "--job", "11"])
        @test r.code == 0 && occursin("# Measured: job 11", r.table)
        # `balance` gives ci_slices.jl's loads: the python and the julia assignment, on the committed table
        cs = Module(:GSPkgSlices)
        Base.include(cs, joinpath(_GS_ROOT, "test", "ci_slices.jl"))
        tbl = joinpath(_GS_ROOT, "test", "pkgtest_costs.tsv")
        costs = cs.lk_unit_costs(tbl)
        @test !isempty(costs) && all(>=(0), values(costs)) && any(>(0), values(costs))
        @test all(f -> isfile(joinpath(_GS_ROOT, "test", f)), keys(costs))
        files = sort!(collect(keys(costs)))
        g = cs.lk_file_groups(files, 3, costs)
        load = [sum(costs[f] for f in files if g[f] == k) for k in 1:3]
        r = pk("balance", tbl, "3")
        want = join(["  group $k: $(round(load[k]; digits=1)) s" for k in 1:3], "\n")
        @test r.code == 0 && occursin(want, r.out)          # the python assignment IS the julia one
        # …and it is balanced (the point of the table): no group over 3 % above the mean
        @test maximum(load) <= 1.03 * sum(load) / 3
        # a planted table: files with no cost count as the median; --tests reads the directory's files
        mktempdir() do d
            mkpath(joinpath(d, "sub"))
            for f in (
                "test_a.jl",
                "test_b.jl",
                "sub/test_c.jl",
                "test_static_analysis.jl",
                "helper.jl"
            )
                write(joinpath(d, f), "")
            end
            write(joinpath(d, "t.tsv"), "# c\ntest_a.jl\t10.0\ntest_b.jl\t30.0\n")
            r = pk("balance", joinpath(d, "t.tsv"), "2", "--tests", d)
            # test_c.jl has no cost: the median of {10, 30} (the lower one, 10) → loads 30 | 10 + 10
            @test r.code == 0 && occursin("3 files over 2 groups (1 without a cost", r.out)
            @test occursin("group 1: 30.0 s", r.out) && occursin("group 2: 20.0 s", r.out)
            @test pk("balance", joinpath(d, "t.tsv"), "0").code == 2
            @test pk(
                "balance", joinpath(d, "t.tsv"), "2", "--tests", joinpath(d, "sub", "x")
            ).code == 1
        end
        # test/ci_slices.jl `lk_costs_path`: the named table, never a silent fall back to the other
        td = joinpath(_GS_ROOT, "test")
        cp_(v) = withenv(() -> cs.lk_costs_path(td), "LOGICKERNEL_COSTS_TABLE" => v)
        @test cp_(nothing) == joinpath(td, "unit_costs.tsv") &&
            cp_("") == joinpath(td, "unit_costs.tsv")
        @test cp_("pkgtest_costs.tsv") == tbl
        for bad in ("../unit_costs.tsv", "sub/x.tsv", "unit_costs", "nosuch.tsv", "x.tsv ")
            @test_throws ErrorException cp_(bad)
        end
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
            # CISTATUS: a bare step name is not a list; the error names the expected form (a path)
            # and the exit is non-zero, no traceback; an empty COUNT (a failed Plan) is said plainly
            errout(args...) = begin
                e = IOBuffer()
                p = run(
                    pipeline(
                        ignorestatus(Cmd(`python3 $tool $args`; dir=d));
                        stdout=devnull,
                        stderr=e
                    )
                )
                (p.exitcode, String(take!(e)))
            end
            code, msg = errout("plan", "m")
            @test code != 0
            @test occursin("tools/mutants/<step>.py", msg) &&
                occursin("not a bare step name", msg)
            @test !occursin("Traceback", msg)
            code, msg = errout("collect", "m.py", "")
            @test code != 0
            @test occursin("Plan step gave no mutant count", msg) &&
                !occursin("Traceback", msg)
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
    # THE TOOLING SHARDS (D-0059, 2026-10-20): tools/test_warm.sh is run as `shard NAME` jobs;
    # tools/evidence_ci.py `warm` judges what they wrote, and the declaration, the matrix of CI.yml and
    # the script's own modes must agree — a mode in no shard would be a suite that silently stopped running
    @testset "the tooling shards: declared, in CI.yml's matrix, covering every mode, and gathered" begin
        shards_tsv = joinpath(_GS_ROOT, "tools", "test_warm_shards.tsv")
        rows = [split(l, '\t') for l in eachline(shards_tsv) if !isempty(l) && l[1] != '#']
        declared = [(String(r[2]), split(r[3])) for r in rows if r[1] == "shard"]
        total = only([parse(Int, r[2]) for r in rows if r[1] == "total"])
        names = first.(declared)
        @test length(names) >= 2 && length(unique(names)) == length(names) && total > 0
        # the matrix of CI.yml: the shard list under `tooling:`
        ci = read(joinpath(_GS_ROOT, ".github", "workflows", "CI.yml"), String)
        m = match(r"\n  tooling:\n.*?\n        shard:\n((?:          - \S+\n)+)"s, ci)
        @test m !== nothing
        matrix = if m === nothing
            String[]
        else
            [strip(l)[3:end] for l in split(m[1], '\n') if !isempty(l)]
        end
        @test matrix == names
        # every mode of the script is in exactly one shard (`main` too), and no shard names another
        script = read(joinpath(_GS_ROOT, "tools", "test_warm.sh"), String)
        modes = [m[1] for m in eachmatch(r"(?m)^#   tools/test_warm.sh (\w+)\s", script)]
        expected = sort!(setdiff(unique(modes), ["shard"]))
        in_shards = sort!(vcat([collect(String, mo) for (_, mo) in declared]...))
        @test "main" in expected && length(expected) >= 13
        @test in_shards == expected
        # the gather, on planted shard results
        tool = joinpath(_GS_ROOT, "tools", "evidence_ci.py")
        results = Dict(n => "test_warm (shard $n): 10 passed, 0 failed\n" for n in names)
        function warm(edit=identity; tot=length(names) * 10, shards=declared, ci=nothing)
            r = copy(results)
            edit(r)
            mktempdir() do d
                foreach(((n, t),) -> write(joinpath(d, "warm_$n.txt"), t), r)
                decl = joinpath(d, "decl.tsv")
                write(
                    decl,
                    join(["shard\t$n\t$(join(mo, ' '))\n" for (n, mo) in shards]) *
                    "total\t$tot\n"
                )
                out = joinpath(d, "out.txt")
                code = withenv("GITHUB_ACTIONS" => ci) do
                    run(
                        pipeline(ignorestatus(`python3 $tool warm $d $decl`); stdout=out)
                    ).exitcode
                end
                (code=code, out=read(out, String))
            end
        end
        r = warm()
        @test r.code == 0 && occursin("$(length(names)) shards", r.out)         # the control
        # PER-SHARD COUNTS (D-0091 item 4): each shard's passes, in the declared order, in the report and
        # in the annotation (readable without a token); distinct counts, so a swapped pair shows
        let counts = Dict(n => 10 + i for (i, n) in enumerate(names))
            r = warm(
                x -> foreach(
                    n -> x[n] = "test_warm (shard $n): $(counts[n]) passed, 0 failed\n",
                    names
                );
                tot=sum(values(counts)), ci="true"
            )
            want = join(["$n=$(counts[n])" for n in names], ", ")
            total = sum(values(counts))
            @test r.code == 0 && occursin("($want; the whole run: $total)", r.out)
            notice = filter(startswith("::notice title=Tooling suites"), split(r.out, '\n'))
            @test length(notice) == 1 && occursin(want, notice[1])
        end
        r = warm(x -> delete!(x, names[2]))
        @test r.code == 1 && occursin("shard $(names[2]): no result", r.out)      # a DROPPED shard
        r = warm(
            x -> (x[names[1]] = "test_warm (shard $(names[1])): 10 passed, 1 failed\n")
        )
        @test r.code == 1 && occursin("shard $(names[1]): 1 case(s) failed", r.out)
        r = warm(x -> (x[names[1]] = "test_warm (shard $(names[1])): 0 passed, 0 failed\n"))
        @test r.code == 1 && occursin("shard $(names[1]) ran no case", r.out)
        r = warm(x -> (x[names[1]] = "garbage\n"))
        @test r.code == 1 && occursin("shard $(names[1]): unreadable", r.out)
        r = warm(
            x -> (x[names[1]] = "test_warm (shard $(names[2])): 10 passed, 0 failed\n")
        )
        @test r.code == 1 && occursin("shard $(names[1]): unreadable", r.out)   # another shard's line
        r = warm(; tot=length(names) * 10 + 1)
        @test r.code == 1 && occursin("the whole run passes", r.out)             # the sum is off
        r = warm(; tot=length(names) * 10 - 1)
        @test r.code == 1 && occursin("the whole run passes", r.out)             # …a surplus too
        r = warm(; shards=typeof(declared)())     # a declaration without a shard
        @test r.code == 1 && occursin("declares no shards", r.out)
        r = warm(x -> foreach(n -> x[n] = "skipped\n", names))
        @test r.code == 0 && occursin("every shard skipped", r.out)               # no tooling change
        r = warm(x -> (x[names[1]] = "skipped\n"))
        @test r.code == 1 && occursin("were skipped but", r.out)                  # some skipped, some ran
        # the script's own dispatcher refuses a shard it does not declare
        sh = joinpath(_GS_ROOT, "tools", "test_warm.sh")
        @test run(
            pipeline(ignorestatus(`bash $sh shard nosuch`); stdout=devnull, stderr=devnull)
        ).exitcode == 2
        # `main` skips the cases that are modes of their own, every other run keeps them: the
        # script's two lines, run as they are, and no such case called bare in the default flow
        flag_line = match(r"(?m)^MAIN_ONLY=0; [^#\n]*", script).match
        skip_line = match(r"(?m)^_unless_main\(\) \{.*\}$", script).match
        for (arg, runs) in (("main", false), ("rss", true), ("", true))
            body = "set -- $arg; $flag_line; $skip_line; _unless_main echo ran"
            @test occursin("ran", read(`bash -c $body`, String)) == runs
        end
        @test isempty(collect(eachmatch(r"(?m)^_[a-z]+_cases\s*(#.*)?$", script)))
        # …and sums the totals of a shard's modes: a PLANTED runner and declaration (the test seams)
        mktempdir() do d
            runner = joinpath(d, "runner.sh")
            write(
                runner,
                "#!/usr/bin/env bash\n" *
                "case \"\$1\" in\n" *
                "    alpha) echo \"test_warm (alpha): 3 passed, 0 failed\";;\n" *
                "    beta) echo \"test_warm: 4 passed, 0 failed\";;\n" *
                "    red) echo \"test_warm (red): 2 passed, 1 failed\"; exit 1;;\n" *
                "    mute) echo \"no totals here\"; exit 1;;\n" *
                "    lying) echo \"test_warm (lying): 5 passed, 0 failed\"; exit 1;;\n" *
                "esac\n"
            )
            chmod(runner, 0o755)
            decl = joinpath(d, "decl.tsv")
            write(
                decl,
                "shard\tgood\talpha beta\nshard\tred\talpha red\n" *
                "shard\tmute\talpha mute\nshard\tlying\tlying\n"
            )
            function shard(name)
                out = joinpath(d, "out.txt")
                code = withenv(
                    "LOGICKERNEL_TEST_WARM_RUNNER" => runner,
                    "LOGICKERNEL_TEST_WARM_SHARDS" => decl
                ) do
                    run(pipeline(ignorestatus(`bash $sh shard $name`); stdout=out)).exitcode
                end
                (code=code, out=read(out, String))
            end
            r = shard("good")
            @test r.code == 0 &&
                occursin("test_warm (shard good): 7 passed, 0 failed", r.out)
            r = shard("red")
            @test r.code == 1 &&
                occursin("test_warm (shard red): 5 passed, 1 failed", r.out)
            r = shard("mute")        # a mode that printed no totals is a failure, never a pass
            @test r.code == 1 && occursin("mode mute printed no totals", r.out)
            @test occursin("test_warm (shard mute): 3 passed, 1 failed", r.out)
            r = shard("lying")       # a nonzero exit with no failed case is a failure too
            @test r.code == 1 &&
                occursin("test_warm (shard lying): 5 passed, 1 failed", r.out)
        end
    end
    # PARALLEL MUTANT RUNS (D-0077 item 6, 2026-10-21): tools/mutate.sh run-parallel splits a mutant list over
    # 2-3 worktrees (MUTATE_SHARD=k/n) and merges the verdicts. Proved on `sh:` targets, which the driver runs
    # in the tree without a daemon: two workers run AT ONCE, each mutant is applied in its own worker's tree
    # only, the merged verdicts equal a serial run's, a malformed shard and a bad worker count are refused,
    # and the memory rule refuses a machine without the headroom
    @testset "tools/mutate.sh run-parallel: shards isolated, verdicts equal a serial run's, memory rule" begin
        drive = joinpath(_GS_ROOT, "tools", "mutate_drive.py")
        mutate = joinpath(_GS_ROOT, "tools", "mutate.sh")
        mktempdir() do d
            list = joinpath(d, "mutants.py")
            write(
                list,
                """
MUTANTS = [
    dict(id="P1 one", file="src/x.txt", old="BASE", new="ONE"),
    dict(id="P2 two", file="src/x.txt", old="BASE", new="TWO"),
    dict(id="P3 same", file="src/x.txt", old="BASE", new="BASE", equivalent="x.txt - the same text"),
    dict(id="P4 unread", file="src/y.txt", old="YYY", new="ZZZ"),
    dict(id="P5 five", file="src/x.txt", old="BASE", new="FIVE"),
]
"""
            )
            function tree(name)
                t = joinpath(d, name)
                mkpath(joinpath(t, ".warm"))
                mkpath(joinpath(t, "src"))
                write(joinpath(t, "src", "x.txt"), "BASE")
                write(joinpath(t, "src", "y.txt"), "YYY")
                return t
            end
            # the target: record what x.txt holds, hold it for a moment (the workers overlap), pass iff BASE
            target = "sh:echo \"\$(cat src/x.txt)\" >> seen.log; sleep 0.4; [ \"\$(cat src/x.txt)\" = BASE ]"
            function driver(t, out; shard="")
                mkpath(out)
                cmd = setenv(
                    `python3 $drive $t $list $target`,
                    "MUTATE_OUT" => out, "MUTATE_SHARD" => shard,
                    "PATH" => ENV["PATH"]
                )
                return run(
                    pipeline(
                        ignorestatus(cmd);
                        stdout=joinpath(out, "driver.log"),
                        stderr=joinpath(out, "driver.err")
                    )
                )
            end
            verdicts(out) = Dict(
                split(l, '\t')[1] => split(l, '\t')[2] for
                l in eachline(joinpath(out, "verdicts.tsv"))
            )
            # the serial run
            ts = tree("serial")
            driver(ts, joinpath(d, "out_serial"))
            serial = verdicts(joinpath(d, "out_serial"))
            @test serial == Dict(
                "P1" => "caught", "P2" => "caught", "P3" => "EQUIVALENT (declared)",
                "P4" => "SURVIVED", "P5" => "caught"
            )
            # the parallel run: two workers, two trees, at once
            ta, tb = tree("wa"), tree("wb")
            pa = run(
                pipeline(
                    ignorestatus(
                        setenv(
                            `python3 $drive $ta $list $target`,
                            "MUTATE_OUT" => (
                                mkpath(joinpath(d, "out", "par1"));
                                joinpath(d, "out", "par1")
                            ),
                            "MUTATE_SHARD" => "1/2", "PATH" => ENV["PATH"]
                        )
                    );
                    stdout=devnull
                ); wait=false
            )
            pb = run(
                pipeline(
                    ignorestatus(
                        setenv(
                            `python3 $drive $tb $list $target`,
                            "MUTATE_OUT" => (
                                mkpath(joinpath(d, "out", "par2"));
                                joinpath(d, "out", "par2")
                            ),
                            "MUTATE_SHARD" => "2/2", "PATH" => ENV["PATH"]
                        )
                    );
                    stdout=devnull
                ); wait=false
            )
            wait(pa)
            wait(pb)
            seen(t) = Set(readlines(joinpath(t, "seen.log")))
            # shard 1/2 = P1, P3, P5; shard 2/2 = P2, P4: a tree only ever held ITS mutants' text
            @test seen(ta) == Set(["BASE", "ONE", "FIVE"])
            @test seen(tb) == Set(["BASE", "TWO"])
            @test read(joinpath(ta, "src", "x.txt"), String) == "BASE"             # restored
            @test read(joinpath(tb, "src", "y.txt"), String) == "YYY"
            @test !ispath(joinpath(ta, ".warm", "MUTATION_IN_PROGRESS"))
            @test !ispath(joinpath(tb, ".warm", "MUTATION_IN_PROGRESS"))
            # the merge: the list's order, a serial run's verdicts
            out = joinpath(d, "out")
            m = run(
                pipeline(
                    ignorestatus(
                        `python3 $drive --merge $list $out $(joinpath(out, "par1")) $(joinpath(out, "par2"))`
                    );
                    stdout=joinpath(d, "merge.log")
                )
            )
            @test m.exitcode == 1                         # P4 SURVIVED: it blocks, as in the serial run
            # a merge of verdicts none of which blocks (shard 1/2: P1 caught, P3 declared equivalent, P5 caught)
            nb = run(
                pipeline(
                    ignorestatus(
                        `python3 $drive --merge $list $(mkpath(joinpath(d, "out_nb"))) $(joinpath(out, "par1"))`
                    );
                    stdout=devnull
                )
            )
            @test nb.exitcode == 0
            @test verdicts(out) == serial
            @test first.(split.(readlines(joinpath(out, "verdicts.tsv")), '\t')) ==
                ["P1", "P2", "P3", "P4", "P5"]
            # a worker that never finished, and a mutant decided twice, are not a merge
            mkpath(joinpath(d, "out3"))
            @test run(
                pipeline(
                    ignorestatus(
                        `python3 $drive --merge $list $(joinpath(d, "out3")) $(joinpath(out, "par1")) $(joinpath(d, "nodir"))`
                    );
                    stdout=devnull
                )
            ).exitcode == 2
            @test run(
                pipeline(
                    ignorestatus(
                        `python3 $drive --merge $list $(joinpath(d, "out3")) $(joinpath(out, "par1")) $(joinpath(out, "par1"))`
                    );
                    stdout=devnull
                )
            ).exitcode == 2
            # a malformed shard is refused, never read as the whole list
            for bad in ("0/2", "3/2", "2", "a/b")
                r = driver(
                    tree("bad_$(replace(bad, '/' => '_'))"),
                    joinpath(d, "out_bad");
                    shard=bad
                )
                @test r.exitcode != 0
                # …by the shard's own refusal: reading it as the whole list would also exit 1 here (P4 survives)
                @test occursin(
                    "expected k/n", read(joinpath(d, "out_bad", "driver.err"), String)
                )
            end
            # mutate.sh: the worker count and the memory rule
            fixture = tree("main")
            function par(args...; env...)
                cmd = setenv(
                    `bash $mutate run-parallel $args`,
                    "MUTATE_ROOT" => fixture, "PATH" => ENV["PATH"],
                    [String(k) => String(v) for (k, v) in env]...
                )
                return run(pipeline(ignorestatus(cmd); stdout=devnull, stderr=devnull)).exitcode
            end
            @test par("1", list, target) == 2 && par("4", list, target) == 2   # 2 or 3, no other
            @test par("2", joinpath(d, "nolist.py"), target) == 2
            @test par(
                "2", list, target;
                LOGICKERNEL_MUTANTS_AVAIL_MB="1000", LOGICKERNEL_MUTANTS_TOTAL_MB="8000"
            ) == 4                                          # 2 x 2500 + 25 % of 8000 = 7000 MB wanted
            @test par(
                "3", list, target;
                LOGICKERNEL_MUTANTS_AVAIL_MB="9499", LOGICKERNEL_MUTANTS_TOTAL_MB="8000"
            ) == 4                                          # 3 x 2500 + 2000 = 9500: one MB short
            @test par(
                "3", list, target;
                LOGICKERNEL_MUTANTS_AVAIL_MB="9500", LOGICKERNEL_MUTANTS_TOTAL_MB="8000"
            ) != 4                                          # exactly enough: it goes on (and stops at the
            # fixture, which is no git repository)
        end
    end
    # THE MUTATION DRIVER'S FOUR DEFECTS (A-0083 item 3, A-0084 item 5; D-0131, D-0132), each on a tree of its own
    # (`sh:` targets run in the tree without a daemon): (a) a BADMATCH mutant no longer crashes the end of the run,
    # (c) the default limit per target is 900 s, (d) a deletion that does not load says why, (b) a merged
    # parallel run leaves no worker directories
    @testset "tools/mutate_drive.py, mutate.sh: BADMATCH, the 900 s default, the deletion hint, the parallel leftovers" begin
        drive = joinpath(_GS_ROOT, "tools", "mutate_drive.py")
        mutate = joinpath(_GS_ROOT, "tools", "mutate.sh")
        mktempdir() do d
            function tree(name)
                t = joinpath(d, name)
                mkpath(joinpath(t, ".warm"))
                mkpath(joinpath(t, "src"))
                write(joinpath(t, "src", "x.txt"), "BASE")
                return t
            end
            function drive_run(name, mutants, target; env=())
                t = tree(name)
                list = joinpath(d, name * ".py")
                write(list, "MUTANTS = [\n" * mutants * "]\n")
                out = mkpath(joinpath(d, name * "_out"))
                cmd = addenv(
                    `python3 $drive $t $list $target`,
                    "MUTATE_OUT" => out, "PATH" => ENV["PATH"], env...
                )
                r = run(
                    pipeline(
                        ignorestatus(cmd);
                        stdout=joinpath(out, "driver.log"),
                        stderr=joinpath(out, "driver.err")
                    )
                )
                tsv = joinpath(out, "verdicts.tsv")
                return (
                    code=r.exitcode, log=read(joinpath(out, "driver.log"), String),
                    err=read(joinpath(out, "driver.err"), String),
                    rows=if isfile(tsv)
                        [split(l, '\t') for l in eachline(tsv)]
                    else
                        Vector{SubString{String}}[]
                    end
                )
            end
            pass_iff_base = "sh:[ \"\$(cat src/x.txt)\" = BASE ]"
            # (a) BADMATCH: booked with three fields like every verdict, blocking, and the run ends with its summary
            r = drive_run(
                "badmatch",
                """
    dict(id="B1 no such text", file="src/x.txt", old="NOWHERE", new="X"),
    dict(id="B2 real", file="src/x.txt", old="BASE", new="OTHER"),
""",
                pass_iff_base
            )
            @test !occursin("Traceback", r.err) && !occursin("ValueError", r.err)
            @test r.code == 1                                  # BADMATCH blocks, and nothing crashed
            @test occursin("SUMMARY 1 of 2 caught; 1 blocking", r.log)
            @test [(row[1], row[2]) for row in r.rows] ==
                [("B1", "BADMATCH(0)"), ("B2", "caught")]
            @test occursin("`old` occurs 0 times in src/x.txt", r.rows[1][3])
            # (c) the default limit (WARM_TIMEOUT_S is the limit handed to every target); a set one still wins
            lim(n) = "sh:[ \"\$WARM_TIMEOUT_S\" = $n ]"
            r = drive_run("limit_default", "", lim(900); env=("MUTATE_LIMIT_S" => nothing,))
            @test r.code == 0 && occursin("baseline exit 0", r.log)
            r = drive_run("limit_240", "", lim(240); env=("MUTATE_LIMIT_S" => nothing,))
            @test r.code == 2 && occursin("BASELINE NOT GREEN", r.log)    # the guard can fail: 240 is no longer it
            r = drive_run("limit_set", "", lim(7); env=("MUTATE_LIMIT_S" => "7",))
            @test r.code == 0
            # (d) a deletion that leaves the file unloadable carries the hint; a replacement does not
            # the signature is built here, never written whole: a failing @test below prints its expression, and the
            # judge (NOT_LOADED) would read that line as a file that does not load
            sig = "Parse" * "Error: unexpected )"
            noload = "sh:grep -q BASE src/x.txt || { echo '$sig'; exit 1; }"
            r = drive_run(
                "hint",
                """
    dict(id="H1 deleted", file="src/x.txt", old="BASE", new=""),
    dict(id="H2 replaced", file="src/x.txt", old="BASE", new="("),
""",
                noload
            )
            @test [(row[1], row[2]) for row in r.rows] ==
                [
                ("H1", "NO VERDICT (does not load)"), ("H2", "NO VERDICT (does not load)")
            ]
            @test occursin(sig, r.rows[1][3]) &&
                occursin("replace the entry, do not delete its line", r.rows[1][3])
            @test occursin(sig, r.rows[2][3]) &&
                !occursin("do not delete", r.rows[2][3])
            # (b) the leftovers of a merged parallel run
            out = mkpath(joinpath(d, "par_out"))
            for k in 1:2
                w = mkpath(joinpath(out, "par$k"))
                write(joinpath(w, "verdicts.tsv"), "P$k\tcaught\t-\n")
                write(joinpath(w, "driver.log"), "driver $k\n")
                write(joinpath(w, "baseline.log"), "baseline $k\n")
            end
            write(joinpath(out, "par1", "mutant_P1.log"), "mutant P1\n")
            write(joinpath(out, "verdicts.tsv"), "P1\tcaught\t-\nP2\tcaught\t-\n")
            write(joinpath(out, "par2", "notes.txt"), "not ours\n")
            err = joinpath(d, "par_err.txt")
            r = run(
                pipeline(
                    ignorestatus(`bash $mutate par-cleanup $out 2`); stderr=err,
                    stdout=devnull
                )
            )
            @test r.exitcode == 0
            @test !ispath(joinpath(out, "par1"))                                  # emptied and removed
            @test isdir(joinpath(out, "par2")) &&
                readdir(joinpath(out, "par2")) == ["notes.txt"]
            @test occursin("par2 is not empty", read(err, String))                # what is not ours stays, said
            @test read(joinpath(out, "mutant_P1.log"), String) == "mutant P1\n"
            @test read(joinpath(out, "par1-driver.log"), String) == "driver 1\n"
            @test read(joinpath(out, "par2-baseline.log"), String) == "baseline 2\n"
            @test read(joinpath(out, "verdicts.tsv"), String) ==
                "P1\tcaught\t-\nP2\tcaught\t-\n"
            @test !isfile(joinpath(out, "par2", "verdicts.tsv"))
        end
    end
    # THE RUNNER IMAGE IS PINNED (CI.yml's note above `jobs:`): no job, no matrix entry on a moving
    # `-latest` image; the oracle's cache key names the image. The scan must see every `runs-on`.
    @testset "the CI runner images are pinned, never -latest" begin
        wf = joinpath(_GS_ROOT, ".github", "workflows")
        moving, runs_on = String[], 0
        for f in filter(endswith(".yml"), readdir(wf; join=true)),
            (i, l) in enumerate(eachline(f))

            runs_on += occursin(r"^\s*runs-on:", l)
            occursin(r"^\s*(runs-on:|-)\s*[\w.-]+-latest\b", l) &&
                push!(moving, "$(basename(f)):$i")
        end
        @test runs_on >= 9 && isempty(moving)
        action = read(
            joinpath(_GS_ROOT, ".github", "actions", "oracle", "action.yml"), String
        )
        @test occursin(raw"key=${ImageOS:?", action)
    end
    # UNDER CI A MISSING ANALYSIS TOOL IS AN ERROR (test/test_static_analysis.jl's header): the real file
    # in a fresh process with the global environment off the load path (so JET, Aqua, AllocCheck are
    # missing) — CI without the opt-out fails with an ::error, the named opt-out skips with a ::warning,
    # and a local run that is not required skips without an annotation
    @testset "test_static_analysis.jl: under CI a missing tool fails, the pkg-test opt-out warns" begin
        f = joinpath(_GS_ROOT, "test", "test_static_analysis.jl")
        jl = joinpath(Sys.BINDIR, Base.julia_exename())
        function sa(env...)
            cmd = addenv(
                `$jl --project=$_GS_ROOT --startup-file=no $f`,
                "JULIA_LOAD_PATH" => "@:@stdlib",
                "LOGICKERNEL_REQUIRE_TOOLS" => "",
                "LOGICKERNEL_STATIC_ANALYSIS_OPTOUT" => "", env...
            )
            out = IOBuffer()
            p = run(pipeline(ignorestatus(cmd); stdout=out, stderr=out))
            return p.exitcode, String(take!(out))
        end
        rc, out = sa("CI" => "true")
        @test rc == 1 &&
            occursin("::error title=static analysis::REQUIRED but missing: JET", out)
        rc, out = sa("CI" => "true", "LOGICKERNEL_STATIC_ANALYSIS_OPTOUT" => "pkg-test")
        @test rc == 0 && occursin("::warning title=static analysis::SKIPPED", out)
        rc, out = sa("CI" => "")
        @test rc == 0 && !occursin("::", out)
        rc, out = sa("CI" => "", "LOGICKERNEL_REQUIRE_TOOLS" => "1")      # the local requirement as before
        @test rc == 1 && occursin("is required here", out)
    end
    # A WHOLE-SUITE mutation target (tools/mutate_suite.sh) needs swipl-devel at the pin in the lane:
    # test/test_vendored_plunit.jl fails in CI without it, and the battery's baseline with it
    @testset "the mutation lane checks swipl-devel out for a whole-suite target" begin
        mut = read(joinpath(_GS_ROOT, ".github", "workflows", "mutation.yml"), String)
        # the checkout and the analysis tools, in the baseline and the mutant job each
        @test count("'mutate_suite'", mut) == 4 &&
            count("path: .upstream/swipl-devel", mut) == 2
        @test occursin("LOGICKERNEL_UPSTREAM_SWIPL_DEVEL:", mut)
        suite = joinpath(_GS_ROOT, "tools", "mutate_suite.sh")
        @test isfile(suite) && (filemode(suite) & 0o111) != 0
        @test occursin("test/runtests.jl", read(suite, String))
    end
end

# D-0249 item 1: the Pkg.test-way run's stale load refuses a precompile cache of ANOTHER checkout (MOD2, 2026-10-29: a
# run in lk-mod2 executed lk-s1's code). A pair of stub packages under a scratch directory, a REAL julia (and Revise) on
# them, no LogicKernel compile: tools/pkgtest_way_load.jl is the code under test.
@testset "pkgtest_way: a cache from another checkout is refused, this checkout's own is built (D-0249)" begin
    work = mktempdir()
    depot = joinpath(work, "depot")                        # a private first depot: the stub caches stay out of ~/.julia
    mkpath(depot)
    coA, coB = joinpath(work, "checkoutA"), joinpath(work, "checkoutB")
    function mkstub(dir, marker, extra)
        mkpath(joinpath(dir, "src"))
        write(
            joinpath(dir, "Project.toml"),
            "name = \"PkgDirStub\"\nuuid = \"6b1f2a1e-5d3c-4e8a-9a41-7c0d2f3b9e11\"\nversion = \"0.1.0\"\n"
        )
        write(
            joinpath(dir, "src", "PkgDirStub.jl"),
            "module PkgDirStub\nmarker() = \"$marker\"\n$extra\nend\n"
        )
    end
    mkstub(coA, "A", "function nomethod end")
    mkstub(coB, "B", "function nomethod end\nonly_in_b() = true")                 # a function that only checkout B has
    driver = joinpath(work, "driver.jl")
    write(
        driver,
        """
include(joinpath(ENV["PKGDIR_TOOLS"], "pkgtest_way_load.jl"))
root, mode = ARGS[1], ARGS[2]
kind = if mode == "raw"                                     # the stale load alone, no guard: what the tool did before
    revise = Base.require(Main, :Revise)
    Base.invokelatest(revise.stale_load, "PkgDirStub"; throw=true)
    :raw
elseif mode in ("guarded", "guardedfail")
    pkgtest_way_load("PkgDirStub", root, :marker, @__FILE__, ARGS)
else
    :plain
end
using PkgDirStub
if mode == "redef"    # the package from checkout A, its probe method then redefined from a file under the root (B)
    include_string(PkgDirStub, string("marker() = ", repr("A")), joinpath(root, "src", "PkgDirStub.jl"))
end
why = pkgtest_way_foreign(PkgDirStub, root, :marker)
println("WHYTEXT ", why)
println("WHY ", why === nothing ? "none" : "foreign")
println("WHYEMPTY ", pkgtest_way_foreign(PkgDirStub, root, :nomethod) === nothing ? "none" : "foreign")
println("WHYUNDEF ", pkgtest_way_foreign(PkgDirStub, root, :nothing_here) === nothing ? "none" : "foreign")
anon = Module(:PkgDirAnon)                                   # a module that is no package: its directory is unknown
include_string(anon, string("marker() = ", repr("A")), joinpath(root, "src", "PkgDirStub.jl"))
println("WHYANON ", pkgtest_way_foreign(anon, root, :marker))
println("RESULT ", kind, " ", PkgDirStub.marker(), " ", isdefined(PkgDirStub, :only_in_b), " ", pkgdir(PkgDirStub))
mode == "guardedfail" && exit(3)
"""
    )
    sep = Sys.iswindows() ? ";" : ":"
    # the private first depot hides the default environment (@v#.#) where Revise is installed: name it on the load path
    defenv = dirname(Base.load_path_expand("@v#.#"))
    depots = join([depot; Base.DEPOT_PATH], sep)               # the caller's depots stay behind it (Revise)
    defproj = joinpath(defenv, "Project.toml")
    if !(isfile(defproj) && occursin(r"(?m)^Revise\s*=", read(defproj, String)))
        # CI jobs that run the whole suite (Pkg.test, the mutation battery) have no Revise in the default environment: this
        # test provides its own, in the scratch directory (the private depot takes the download and the cache)
        defenv = joinpath(work, "reviseenv")
        mkpath(defenv)
        pk = addenv(
            `$(Base.julia_cmd()) --project=$defenv --startup-file=no -e "using Pkg; Pkg.add(\"Revise\")"`,
            "JULIA_DEPOT_PATH" => depots, "JULIA_LOAD_PATH" => "@" * sep * "@stdlib"
        )
        r = _gs_run_merged(pk)
        @test r.code == 0 || (println(r.out); false)
    end
    loadpath = "@" * sep * defenv * sep * "@stdlib"
    function pd(checkout, mode; nostale="", root=checkout)
        cmd = addenv(
            `$(Base.julia_cmd()) --project=$checkout --startup-file=no $driver $root $mode`,
            "JULIA_DEPOT_PATH" => depots,
            "JULIA_LOAD_PATH" => loadpath,
            "LOGICKERNEL_PKGTEST_WAY_NO_STALE" => nostale,
            "PKGDIR_TOOLS" => joinpath(_GS_ROOT, "tools")
        )
        r = _gs_run_merged(cmd)
        m = match(r"(?m)^RESULT (\S+) (\S+) (\S+) (.*)$", r.out)
        w = match(r"(?m)^WHY (\S+)$", r.out)
        wt = match(r"(?m)^WHYTEXT (.*)$", r.out)
        return (
            code=r.code, out=r.out,
            kind=m === nothing ? "" : String(m[1]),
            marker=m === nothing ? "" : String(m[2]),
            onlyb=m === nothing ? "" : String(m[3]), dir=m === nothing ? "" : String(m[4]),
            why=w === nothing ? "" : String(w[1]),
            whytext=wt === nothing ? "" : String(wt[1]),
            refused=occursin("REFUSED the last cache of ANOTHER checkout", r.out)
        )
    end
    # 1. checkout A builds its cache; judged against its own checkout the loaded package is not foreign
    r = pd(coA, "plain")
    @test r.code == 0 && r.marker == "A" && r.onlyb == "false" && r.why == "none"
    # a probe with no method, and one that is not defined, are not "this checkout's" either: an empty list must not pass
    @test occursin(r"(?m)^WHYEMPTY foreign$", r.out) &&
        occursin(r"(?m)^WHYUNDEF foreign$", r.out)
    # a module that is no package has no directory: it is not this checkout's even with its method under the root
    @test occursin(r"(?m)^WHYANON .*is unknown$", r.out)
    r = pd(coA, "raw")                                       # the newest cache is A's own: nothing to refuse
    @test r.code == 0 && r.kind == "raw" && r.marker == "A" && r.why == "none"
    # 2. THE BUG, the control that gives the test its power: checkout B, the stale load alone, runs A's code
    r = pd(coB, "raw")
    @test r.code == 0 && r.kind == "raw"
    @test r.marker == "A" && r.onlyb == "false"              # A's code in B's run
    @test r.why == "foreign"                                 # …which the check names
    # 2b. the package directory is judged on its own: the package of A, its probe method redefined from a file under B
    # (the loaded directory is A's, the methods are B's: only the directory comparison can name it)
    r = pd(coA, "redef"; root=coB)
    @test r.code == 0 && r.marker == "A" && r.why == "foreign" &&
        occursin("package directory", r.whytext)
    # 3. the guarded run in B must not execute A's code: it falls back to a fresh process and builds B's own cache
    r = pd(coB, "guarded")
    @test r.code == 0 && r.refused
    @test r.kind == "normal" && r.marker == "B" && r.onlyb == "true" && r.why == "none"
    @test realpath(r.dir) == realpath(coB)
    # 4. B now has the newest cache: it is used as it is (the start from the last cache stays), not refused
    r = pd(coB, "guarded")
    @test r.code == 0 && !r.refused
    @test r.kind == "stale" && r.marker == "B" && r.onlyb == "true" && r.why == "none"
    # 5. and the other way round: the newest cache is B's now, so a run in A is refused and keeps A's code
    r = pd(coA, "guarded")
    @test r.code == 0 && r.refused
    @test r.kind == "normal" && r.marker == "A" && r.onlyb == "false" && r.why == "none"
    # the child's exit code is the run's own: a failing run in the fresh process fails the refused one (A's cache is
    # the newest now, so B's run is refused)
    r = pd(coB, "guardedfail")
    @test r.code == 3 && r.refused && r.marker == "B"
    # 6. LOGICKERNEL_PKGTEST_WAY_NO_STALE=1 stays the explicit override: no stale load is even tried (the newest
    # newest cache is one checkout's: in the OTHER one a stale load WOULD be refused and say so)
    other, otherm = pd(coA, "raw").why == "foreign" ? (coA, "A") : (coB, "B")
    @test pd(other, "raw").why == "foreign"                  # the control: this checkout's stale load runs foreign code
    r = pd(other, "guarded"; nostale="1")
    @test r.code == 0 && !r.refused && !occursin("stale_load not possible", r.out)
    @test r.kind == "normal" && r.marker == otherm && r.why == "none"
    # 7. the tool itself starts from the guard (and from nothing else)
    drv = read(joinpath(_GS_ROOT, "tools", "pkgtest_way.jl"), String)
    @test occursin("include(joinpath(@__DIR__, \"pkgtest_way_load.jl\"))\n", drv) &&
        occursin(
            "\npkgtest_way_load(\"LogicKernel\", joinpath(@__DIR__, \"..\"), :_no_children, @__FILE__, ARGS)\n",
            drv
        ) && !occursin("Revise.stale_load", drv)
    rm(work; recursive=true, force=true)
end
