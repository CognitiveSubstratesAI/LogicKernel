# ORIGINAL: the commit-message rule's git hook (tools/githooks/commit-msg) and its contract; no swipl-devel counterpart.
# test/test_commit_msg_hook.jl — every LogicKernel commit message starts with SWI's categories (user,
# 2026-10-03). The rule is enforced by git's own commit-msg hook, which receives the final message
# FILE however the message was given; these cases are its contract, BOTH sides, so a hook that can
# never pass or never refuse fails here. tools/run_tests.sh separately refuses a full run when the
# hook is not installed (core.hooksPath), so an uninstalled hook cannot pass silently either.
using Test

const _CMH_HOOK = joinpath(@__DIR__, "..", "tools", "githooks", "commit-msg")

"""
Run the hook on a message file holding `msg`: true when it accepts the message. `dir`: the
repository it runs in; `record`: the declared-fix record it reads (none by default — never this
repository's own, which exists while a real fix cycle runs); `fixture`: the CI answer.
"""
function _cmh_accepts(
    msg::String;
    dir::String=pwd(),
    record::String=joinpath(tempdir(), "no-such-ci-fix-record"),
    fixture::Union{Nothing, String}=nothing
)::Bool
    return mktemp() do path, io
        write(io, msg)
        close(io)
        withenv("LOGICKERNEL_CI_FIX_FILE" => record, "LOGICKERNEL_CI_FIXTURE" => fixture) do
            success(
                pipeline(
                    setenv(`python3 $_CMH_HOOK $path`; dir=dir); stdout=devnull,
                    stderr=devnull
                )
            )
        end
    end
end

@testset "commit-msg hook: categories pass, everything else is refused" begin
    @test isfile(_CMH_HOOK)
    @test Sys.isexecutable(_CMH_HOOK)              # git runs a hook only if it is executable
    accepted = [
        "ADDED: x", "FIXED: x", "ENHANCED: x", "MODIFIED: x", "DOC: x", "TEST: x",
        "CLEANUP: x",
        "UPSTREAM: pl-wam.c PL_open_query/PL_next_solution (swipl-devel bae881a2)",
        "UPSTREAM: tabling.pl x (scryer-prolog 97b85690)",
        "DOC: subject\n\nbody\n\nCo-Authored-By: someone",
        "# a comment line git strips\n\nFIXED: after the comment",   # the editor's template
        "\n\nTEST: after blank lines"
    ]
    refused = [
        "", "\n\n", "# only a comment",
        "fixed: lower case", "FIXED:no space", "FIXED:",
        "PORT: pl-wam.c x (swipl-devel bae881a2)",
        "Fix the thing", "doc x\n\nDOC: the category only in the body",
        "UPSTREAM: something", "UPSTREAM: pl-wam.c x (swipl-devel)",
        "UPSTREAM: no file here (swipl-devel bae881a2)"
    ]
    for m in accepted
        @test _cmh_accepts(m)
    end
    for m in refused
        @test !_cmh_accepts(m)
    end
end

@testset "commit-msg hook: a CI-Fix trailer names the RED parent, recorded by a gate cycle, once" begin
    # (user, 2026-10-11) tools/lib_evidence.sh `_ci_fix_gate` lets a gate cycle pass one red push
    # and records it; the one commit made on it carries `CI-Fix: <sha>`, checked here both ways
    mktempdir() do d
        g(args...) = readchomp(
            pipeline(
                setenv(`git -c user.name=t -c user.email=t@t.invalid $args`; dir=d);
                stderr=devnull)
        )
        g("init", "-q")
        write(joinpath(d, "x"), "1")
        g("add", "x")
        g("commit", "-q", "-m", "ADDED: x")
        head = g("rev-parse", "HEAD")
        rec, fx = joinpath(d, "CI_FIX"), joinpath(d, "f.json")
        ci(status, conclusion) = write(
            fx,
            "{\"workflow_runs\":[{\"head_sha\":\"$head\",\"name\":\"CI\"," *
            "\"status\":\"$status\",\"conclusion\":$conclusion,\"html_url\":\"https://x/1\"}]}"
        )
        ok(msg) = _cmh_accepts(msg; dir=d, record=rec, fixture=fx)
        fix(sha) = "FIXED: CI\n\nwhy\n\nCI-Fix: $sha\n"
        ci("completed", "\"failure\"")
        # no gate cycle recorded a declared fix: an ordinary commit passes, a trailer is refused
        @test ok("FIXED: x") && !ok(fix(head))
        write(rec, head * "\n")
        @test ok(fix(head)) && ok(fix(head[1:7]))             # the red parent, full or short
        @test !ok("FIXED: x")                                 # …and it MUST be named
        @test !ok(fix("f"^40))                                # another commit
        @test !ok(fix("xyz")) && !ok(fix(""))                 # not a SHA
        @test !ok(fix(head) * "CI-Fix: $head\n")              # two trailers
        ci("completed", "\"success\"")
        @test !ok(fix(head))                                  # the parent's CI is green
        ci("in_progress", "null")
        @test !ok(fix(head))                                  # …or has no verdict yet
        write(fx, "<html>rate limited</html>")
        @test !ok(fix(head))                                  # …or cannot be read
        ci("completed", "\"failure\"")
        @test ok(fix(head))
        # ONE use: the commit made, the post-commit hook removes the record
        post = joinpath(dirname(_CMH_HOOK), "post-commit")
        withenv("LOGICKERNEL_CI_FIX_FILE" => rec) do
            run(pipeline(setenv(`$post`; dir=d); stdout=devnull, stderr=devnull))
        end
        @test !isfile(rec) && !ok(fix(head)) && ok("FIXED: x")
        # the trailer is for the commit made ON the red push: with another parent it is refused
        write(rec, head * "\n")
        g("commit", "-q", "--allow-empty", "-m", "ADDED: y")
        @test !ok(fix(head))
    end
end
