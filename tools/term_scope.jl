#!/usr/bin/env julia
# ORIGINAL: the gate split's decision for tools/run_tests.sh (user, 2026-10-06; test/term_scope.jl).
#
#   julia --startup-file=no tools/term_scope.jl        # prints `<all|chunk>\t<why>`
#
# What a chunk changed: every path that differs from `origin/main` — the commits not yet pushed and
# the working tree, untracked files included. A trigger among them, LOGICKERNEL_FULL=1 (a milestone),
# or no `origin/main` to compare with means `all`; otherwise `chunk`. It loads no package: the
# declarations are read by test/term_scope.jl, the runner's own extractor.
include(joinpath(@__DIR__, "..", "test", "term_scope.jl"))

const ROOT = abspath(joinpath(@__DIR__, ".."))

"The paths that differ from `origin/main`, or `nothing` when there is no `origin/main`."
function changed_paths(root::String)::Union{Nothing, Vector{String}}
    git(args...) = Cmd(`git -C $root $args`)
    success(
        pipeline(git("rev-parse", "--verify", "--quiet", "origin/main"); stdout=devnull)
    ) ||
        return nothing
    diff = readlines(git("diff", "--name-only", "origin/main"))
    untracked = readlines(git("ls-files", "--others", "--exclude-standard"))
    return sort!(unique!([diff; untracked]))
end

let full = get(ENV, "LOGICKERNEL_FULL", "") == "1", changed = changed_paths(ROOT)
    types, why = if changed === nothing && !full
        ("all", "no origin/main to compare with")
    else
        lk_term_types(lk_term_triggers(ROOT), something(changed, String[]); full=full)
    end
    println(types, '\t', why)
end
