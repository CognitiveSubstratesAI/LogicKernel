# ORIGINAL: the commit-message rule's git hook (tools/githooks/commit-msg) and its contract; no swipl-devel counterpart.
# test/test_commit_msg_hook.jl — every LogicKernel commit message starts with SWI's categories (user,
# 2026-10-03). The rule is enforced by git's own commit-msg hook, which receives the final message
# FILE however the message was given; these cases are its contract, BOTH sides, so a hook that can
# never pass or never refuse fails here. tools/run_tests.sh separately refuses a full run when the
# hook is not installed (core.hooksPath), so an uninstalled hook cannot pass silently either.
using Test

const _CMH_HOOK = joinpath(@__DIR__, "..", "tools", "githooks", "commit-msg")

"Run the hook on a message file holding `msg`: true when it accepts the message."
function _cmh_accepts(msg::String)::Bool
    return mktemp() do path, io
        write(io, msg)
        close(io)
        success(pipeline(`python3 $_CMH_HOOK $path`; stdout=devnull, stderr=devnull))
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
