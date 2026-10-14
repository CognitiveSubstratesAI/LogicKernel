# ORIGINAL: the vendored plunit (user, 2026-10-14) — packages/plunit holds SWI-Prolog/packages-plunit at the pin's `plunit:` commit, UNCHANGED; no swipl-devel counterpart.
# test/test_vendored_plunit.jl — every vendored file is upstream's blob, none is added or missing,
# and the pinned commit is the one swipl-devel's pin records as its submodule.
#
# READ-ONLY means nobody edits packages/plunit: the kernel loads upstream's plunit as it is, and a
# fix belongs upstream (or in the kernel). So each file is held to the blob id git gives it
# upstream (tools/plunit_blobs.txt, written from `git ls-tree -r` at the pinned commit): a changed
# byte changes the id. Where an upstream checkout is found (`~/dev-zone/swipl-devel`, or
# LOGICKERNEL_UPSTREAM_SWIPL_DEVEL, as tools/port_check.jl finds it) the list itself is checked
# against the package's commit, and that commit against the gitlink of the pinned swipl-devel.
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

@testset "the pinned plunit is the submodule commit of the pinned swipl-devel" begin
    up = get(
        ENV,
        "LOGICKERNEL_UPSTREAM_SWIPL_DEVEL",
        joinpath(homedir(), "dev-zone", "swipl-devel")
    )
    if isdir(joinpath(up, ".git"))
        pin = _vp_pin("commit")
        link = split(readchomp(`git -C $up ls-tree $pin packages/plunit`))
        @test length(link) >= 3 && link[2] == "commit" && link[3] == _vp_pin("plunit")
        sub = joinpath(up, "packages", "plunit")
        if isdir(sub) && success(`git -C $sub cat-file -e $(_vp_pin("plunit"))^\{commit\}`)
            listed = readlines(`git -C $sub ls-tree -r $(_vp_pin("plunit"))`)
            _, blobs = _vp_manifest()
            @test sort!(listed) == sort!(["100644 blob $id\t$rel" for (rel, id) in blobs])
        end
    else
        @info "test_vendored_plunit: no swipl-devel checkout here — the blob ids are checked, the gitlink is not"
    end
end
