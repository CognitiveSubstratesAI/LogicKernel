# ORIGINAL: the vendored boot/ and library/ (R2 LB4 chunk a, audit D-0286 item 1) — vendor/swipl-devel holds SWI-Prolog/swipl-devel's boot/ and library/ at the pin's `commit:`, UNCHANGED; no swipl-devel counterpart.
# test/test_vendored_swipl.jl — every vendored file is upstream's blob, none is added or missing,
# and the pinned commit is the one tools/SWIPL_VERSION records. Same shape as test/test_vendored_plunit.jl.
#
# NO EDIT OF A VENDORED FILE, EVER: the kernel loads upstream's boot files as they are (they are the system), so a fix belongs in
# the port, or in a D-entry naming the upstream change. Each file is held to the blob id git gives it upstream
# (tools/swipl_vendor_blobs.txt, written by tools/vendor_swipl.sh from `git ls-tree -r` at the pinned commit): a changed byte changes
# the id. The five INDEX.pl files (tools/gen_library_index.sh: the oracle at the pin runs make_library_index/1) are not in upstream's
# tree; they are held to their own blob lines below the manifest's GENERATED marker, and each entry of one names a file that is there.
# With an upstream checkout (`~/dev-zone/swipl-devel`, or LOGICKERNEL_UPSTREAM_SWIPL_DEVEL — in CI, ALWAYS: the workflows check
# swipl-devel out at the pin) the list itself is checked against `git ls-tree` of the pinned commit.
using Test

const _VS_ROOT = joinpath(@__DIR__, "..")
const _VS_DIR = joinpath(_VS_ROOT, "vendor", "swipl-devel")
# src/CMakeLists.txt:120-121 SWIPL_DATA_INDEXED_DIRS — the directories upstream's build gives an INDEX.pl
const _VS_INDEXED = [
    "library", "library/clp", "library/dcg", "library/unicode", "library/lynx"
]

"A pin-file line `key: value` of `path`, or `\"\"`."
function _vs_key(path::String, key::String)::String
    for l in eachline(path)
        startswith(l, key * ":") && return String(strip(l[(length(key) + 2):end]))
    end
    return ""
end
_vs_pin(key::String)::String = _vs_key(joinpath(_VS_ROOT, "tools", "SWIPL_VERSION"), key)

"tools/swipl_vendor_blobs.txt: the commit its header names, upstream's `path => blob id`, and the generated ones."
function _vs_manifest()::Tuple{String, Dict{String, String}, Dict{String, String}}
    commit = ""
    upstream = Dict{String, String}()
    generated = Dict{String, String}()
    in_generated = false
    for l in eachline(joinpath(_VS_ROOT, "tools", "swipl_vendor_blobs.txt"))
        if startswith(l, "#")
            m = match(r"swipl-devel ([0-9a-f]{40})", l)
            m === nothing || (commit = m[1])
            startswith(l, "# GENERATED") && (in_generated = true)
            continue
        end
        m = match(r"^100644 blob ([0-9a-f]{40})\t(.+)$", l)
        m === nothing && error("tools/swipl_vendor_blobs.txt: an unexpected line: $l")
        (in_generated ? generated : upstream)[m[2]] = m[1]
    end
    return (commit, upstream, generated)
end

"Git's blob id of each of `paths` (SHA-1 of `blob <size>\\0<content>`, as `git hash-object` gives it), `\"\"` for a file that is not there."
function _vs_blobs(paths::Vector{String})::Vector{String}
    there = filter(isfile, paths)
    ids = isempty(there) ? String[] : readlines(`git hash-object --no-filters $there`)
    @assert length(ids) == length(there)
    byfile = Dict(zip(there, ids))
    return String[get(byfile, p, "") for p in paths]
end

"Every file under vendor/swipl-devel, relative to it."
function _vs_present()::Vector{String}
    present = String[]
    for (d, _, files) in walkdir(_VS_DIR), f in files
        push!(present, relpath(joinpath(d, f), _VS_DIR))
    end
    return sort!(present)
end

@testset "vendor/swipl-devel is swipl-devel's boot/ and library/ at the pinned commit, unchanged" begin
    commit, upstream, generated = _vs_manifest()
    @test occursin(r"^[0-9a-f]{40}$", _vs_pin("commit"))
    @test commit == _vs_pin("commit")
    # NON-VACUITY: both sides of every comparison below are the real thing — boot is 26 files, library is 210, the LICENSE is kept
    @test count(startswith("boot/"), keys(upstream)) == 26
    @test count(startswith("library/"), keys(upstream)) == 210
    @test haskey(upstream, "boot/init.pl") && haskey(upstream, "boot/load.pl") &&
        haskey(upstream, "library/lists.pl")
    @test haskey(upstream, "LICENSE")
    @test sort!(collect(keys(generated))) == sort!([d * "/INDEX.pl" for d in _VS_INDEXED])
    @test isempty(intersect(keys(upstream), keys(generated)))
    all_blobs = merge(upstream, generated)
    paths = sort!(collect(keys(all_blobs)))
    got = _vs_blobs(String[joinpath(_VS_DIR, p) for p in paths])
    for (p, g) in zip(paths, got)
        @test g == all_blobs[p]                       # a missing file gives "" and fails here too
    end
    @test _vs_present() == sort!(vcat(paths, ["PIN"]))   # nothing added, nothing missing
    # PIN names the commit the files were copied from
    @test _vs_key(joinpath(_VS_DIR, "PIN"), "commit") == _vs_pin("commit")
    @test _vs_key(joinpath(_VS_DIR, "PIN"), "version") == _vs_pin("version")
end

@testset "each INDEX.pl entry names a vendored file (no stale entry)" begin
    _, _, generated = _vs_manifest()
    @test !isempty(generated)
    for d in _VS_INDEXED
        index = joinpath(_VS_DIR, d, "INDEX.pl")
        entries = [
            match(r"^index\((.+), ([A-Za-z0-9_']+), ([A-Za-z0-9_']+)\)\.$", l) for
            l in eachline(index) if startswith(l, "index(")
        ]
        @test !isempty(entries)
        @test all(!isnothing, entries)
        for m in entries
            isnothing(m) && continue
            @test isfile(joinpath(_VS_DIR, d, m[3] * ".pl"))     # no stale entry
        end
    end
end

# THE UPSTREAM CHECKOUT (as test/test_vendored_plunit.jl): CI's jobs check out swipl-devel at the pinned commit
# (.github/workflows: `LOGICKERNEL_UPSTREAM_SWIPL_DEVEL`), so there (`CI=true`) this testset FAILS when the checkout is missing.
# Only a LOCAL run without a checkout skips it, and says so.
const _VS_UP = get(
    ENV,
    "LOGICKERNEL_UPSTREAM_SWIPL_DEVEL",
    joinpath(homedir(), "dev-zone", "swipl-devel")
)
const _VS_CI = get(ENV, "CI", "") == "true"
if _VS_CI || isdir(joinpath(_VS_UP, ".git"))
    @testset "the manifest is upstream's tree of boot/, library/ and LICENSE at the pinned commit" begin
        have_up = isdir(joinpath(_VS_UP, ".git"))
        have_up ||
            @error "test_vendored_swipl: CI must check out swipl-devel at the pinned " *
                "commit (LOGICKERNEL_UPSTREAM_SWIPL_DEVEL = $_VS_UP): none there"
        @test have_up
        if have_up
            pin = _vs_pin("commit")
            @test success(`git -C $_VS_UP cat-file -e $pin^\{commit\}`)
            _, upstream, generated = _vs_manifest()
            listed = readlines(`git -C $_VS_UP ls-tree -r $pin boot library LICENSE`)
            @test !isempty(listed)
            @test sort!(listed) ==
                sort!(["100644 blob $id\t$rel" for (rel, id) in upstream])
            # the generated indexes are NOT upstream's files
            for rel in keys(generated)
                @test isempty(readlines(`git -C $_VS_UP ls-tree $pin $rel`))
            end
        end
    end
else
    @info "test_vendored_swipl: no swipl-devel checkout here (a local run) — the blob ids are " *
        "checked, the manifest is not compared with upstream's tree (it is in CI)"
end
