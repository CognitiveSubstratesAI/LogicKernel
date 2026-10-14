# ORIGINAL: the vendored plunit (user, 2026-10-14) — packages/plunit holds SWI-Prolog/packages-plunit at the pin's `plunit:` commit, UNCHANGED; no swipl-devel counterpart.
# test/test_vendored_plunit.jl — every vendored file is upstream's blob, none is added or missing,
# and the pinned commit is the one swipl-devel's pin records as its submodule.
#
# READ-ONLY means nobody edits packages/plunit: the kernel loads upstream's plunit as it is, and a
# fix belongs upstream (or in the kernel). So each file is held to the blob id git gives it
# upstream (tools/plunit_blobs.txt, written from `git ls-tree -r` at the pinned commit): a changed
# byte changes the id. With an upstream checkout (`~/dev-zone/swipl-devel`, or
# LOGICKERNEL_UPSTREAM_SWIPL_DEVEL — in CI, ALWAYS: the workflows check swipl-devel out at the pin)
# the list itself is checked against the package's commit, and that commit against the gitlink of
# the pinned swipl-devel.
using Test

const _VP_ROOT = joinpath(@__DIR__, "..")
const _VP_DIR = joinpath(_VP_ROOT, "packages", "plunit")

"The pin file's value for `key`, or `\"\"`."
function _vp_pin(key::String)::String
    for l in eachline(joinpath(_VP_ROOT, "tools", "SWIPL_VERSION"))
        startswith(l, key * ":") && return String(strip(l[(length(key) + 2):end]))
    end
    return ""
end

"tools/plunit_blobs.txt: the commit its header names, and `path => blob id`."
function _vp_manifest()::Tuple{String, Dict{String, String}}
    commit = ""
    blobs = Dict{String, String}()
    for l in eachline(joinpath(_VP_ROOT, "tools", "plunit_blobs.txt"))
        if startswith(l, "#")
            m = match(r"packages-plunit ([0-9a-f]{40})", l)
            m === nothing || (commit = m[1])
            continue
        end
        m = match(r"^100644 blob ([0-9a-f]{40})\t(.+)$", l)
        m === nothing && error("tools/plunit_blobs.txt: an unexpected line: $l")
        blobs[m[2]] = m[1]
    end
    return (commit, blobs)
end

"Git's blob id of `path`'s bytes: SHA-1 of `blob <size>\\0<content>`, as `git hash-object` gives it."
_vp_blob(path::String)::String = readchomp(`git hash-object --no-filters $path`)

@testset "packages/plunit is SWI-Prolog/packages-plunit at the pinned commit, unchanged" begin
    commit, blobs = _vp_manifest()
    @test occursin(r"^[0-9a-f]{40}$", _vp_pin("plunit"))
    @test commit == _vp_pin("plunit")
    @test !isempty(blobs) && haskey(blobs, "plunit.pl")
    for (rel, id) in sort!(collect(blobs))
        f = joinpath(_VP_DIR, rel)
        @test isfile(f) && _vp_blob(f) == id
    end
    present = String[]
    for (d, _, files) in walkdir(_VP_DIR), f in files
        push!(present, relpath(joinpath(d, f), _VP_DIR))
    end
    @test sort!(present) == sort!(collect(keys(blobs)))      # nothing added, nothing missing
end

# THE GITLINK (user, 2026-10-14): no silently inert test in CI. CI's jobs check out swipl-devel at
# the pinned commit with its submodules (.github/workflows: `LOGICKERNEL_UPSTREAM_SWIPL_DEVEL`), so
# there (`CI=true`) this testset FAILS when the checkout, or plunit at the pinned commit in it, is
# missing. Only a LOCAL run without a checkout skips it, and says so; a testset that ran and
# asserted nothing would fail the suite anyway (test/inert_testset_guard.jl).
const _VP_UP = get(
    ENV,
    "LOGICKERNEL_UPSTREAM_SWIPL_DEVEL",
    joinpath(homedir(), "dev-zone", "swipl-devel")
)
const _VP_CI = get(ENV, "CI", "") == "true"
if _VP_CI || isdir(joinpath(_VP_UP, ".git"))
    @testset "the pinned plunit is the submodule commit of the pinned swipl-devel" begin
        up = _VP_UP
        have_up = isdir(joinpath(up, ".git"))
        have_up ||
            @error "test_vendored_plunit: CI must check out swipl-devel at the pinned " *
                "commit (LOGICKERNEL_UPSTREAM_SWIPL_DEVEL = $up): none there"
        @test have_up
        if have_up
            pin = _vp_pin("commit")
            link = split(readchomp(`git -C $up ls-tree $pin packages/plunit`))
            @test length(link) >= 3 && link[2] == "commit" && link[3] == _vp_pin("plunit")
            sub = joinpath(up, "packages", "plunit")
            have_sub =
                isdir(sub) &&
                success(`git -C $sub cat-file -e $(_vp_pin("plunit"))^\{commit\}`)
            if have_sub || _VP_CI
                have_sub ||
                    @error "test_vendored_plunit: CI must check out packages/plunit at " *
                        "$(_vp_pin("plunit")) in $up (submodules: true): it is not there"
                @test have_sub
                if have_sub
                    listed = readlines(`git -C $sub ls-tree -r $(_vp_pin("plunit"))`)
                    _, blobs = _vp_manifest()
                    @test sort!(listed) ==
                        sort!(["100644 blob $id\t$rel" for (rel, id) in blobs])
                end
            else
                @info "test_vendored_plunit: the local checkout $up has no packages/plunit at " *
                    "$(_vp_pin("plunit")) — the blob list is not checked against it (it is in CI)"
            end
        end
    end
else
    @info "test_vendored_plunit: no swipl-devel checkout here (a local run) — the blob ids are " *
        "checked, the gitlink is not (it is in CI)"
end
