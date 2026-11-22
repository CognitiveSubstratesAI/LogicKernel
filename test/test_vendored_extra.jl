# ORIGINAL: the extra vendored swipl-devel classes (R2 upstream reuse, 2026-11-22) — vendor/swipl-devel-extra holds upstream's tests/, app/, customize/, demo/, bench and the pure-Prolog packages UNCHANGED; no swipl-devel counterpart.
# test/test_vendored_extra.jl — every vendored file of every class is upstream's blob, none is added or
# missing, the modes are upstream's, and the pinned commits are the ones swipl-devel's pin records.
# Same shape as test/test_vendored_plunit.jl, over every manifest tools/swipl_extra_blobs/<class>.txt
# (written by `tools/vendor_swipl.sh extra <class>`, checked by `tools/vendor_swipl.sh verify-extra`).
#
# ONE checking function (`_ve_problems`) reads a manifest and the vendored tree and returns every
# problem it finds; the testsets call it on the real manifests (it must return nothing) and on
# deliberately broken copies of one manifest (it must name each break: the guard can fail).
# With an upstream checkout (`~/dev-zone/swipl-devel`, or LOGICKERNEL_UPSTREAM_SWIPL_DEVEL — in CI,
# ALWAYS: the workflows check swipl-devel out at the pin, with its submodules) each manifest is also
# held to upstream's own `git ls-tree -r`.
using Test

const _VE_ROOT = joinpath(@__DIR__, "..")
const _VE_DIR = joinpath(_VE_ROOT, "vendor", "swipl-devel-extra")
const _VE_MANIFESTS = joinpath(_VE_ROOT, "tools", "swipl_extra_blobs")

"The classes the tree must carry (a manifest deleted together with its files is a failure)."
const _VE_CLASSES = [
    "bench", "pkg-chr", "pkg-clpqr", "pkg-cql", "pkg-paxos", "pkg-pldoc", "tests", "top",
]

"The pin file's value for `key`, or `\"\"`."
function _ve_pin(key::String)::String
    for l in eachline(joinpath(_VE_ROOT, "tools", "SWIPL_VERSION"))
        startswith(l, key * ":") && return String(strip(l[(length(key) + 2):end]))
    end
    return ""
end

"The manifest's rows `(mode, blob id, path)`, its header commit, its `# source:` words, and the lines it cannot read."
function _ve_read(manifest::String)
    commit = ""
    source = String[]
    rows = Tuple{String, String, String}[]
    bad = String[]
    for l in eachline(manifest)
        if startswith(l, "#")
            m = match(r"^# SWI-Prolog/swipl-devel ([0-9a-f]{40}) class (\S+) ", l)
            m === nothing || (commit = m[1])
            m = match(r"^# source: (.+)$", l)
            m === nothing || (source = String.(split(m[1])))
            continue
        end
        m = match(r"^(100644|100755) blob ([0-9a-f]{40})\t([A-Za-z0-9_./+-]+)$", l)
        m === nothing ? push!(bad, l) : push!(rows, (m[1], m[2], m[3]))
    end
    return (; commit, source, rows, bad)
end

"The roots (relative to the extra tree) a class owns, from its `# source:` words, or `nothing` when they are malformed."
function _ve_roots(source::Vector{String})::Union{Nothing, Vector{String}}
    if length(source) >= 3 && source[1] == "super"
        return sort!(source[3:end])
    elseif length(source) == 3 && source[1] == "sub"
        return [source[2]]
    end
    return nothing
end

"The git blob ids of `files` (one `git hash-object --no-filters --stdin-paths` run), in order."
function _ve_blobs(files::Vector{String})::Vector{String}
    isempty(files) && return String[]
    return mktemp() do list, io
        foreach(f -> println(io, f), files)
        close(io)
        readlines(
            pipeline(
                Cmd(`git hash-object --no-filters --stdin-paths`; dir = _VE_ROOT);
                stdin = list
            )
        )
    end
end

"""
Every problem of `manifest` against the vendored tree `dir` and the pin commit `pin`: the header
commit, the `# source:` line against the class name, each file's blob id and mode, files present
under the class's roots that the manifest does not list, and listed files that are not there.
"""
function _ve_problems(manifest::String, dir::String, pin::String)::Vector{String}
    probs = String[]
    cls = replace(basename(manifest), r"\.txt$" => "")
    m = _ve_read(manifest)
    for l in m.bad
        push!(probs, "unexpected manifest line: $l")
    end
    m.commit == pin || push!(probs, "header commit $(m.commit) is not the pin $pin")
    isempty(m.rows) && push!(probs, "no file rows")
    roots = _ve_roots(m.source)
    if roots === nothing
        push!(probs, "malformed `# source:` line: $(join(m.source, ' '))")
        roots = String[]
    else
        want =
            cls == "tests" ? (:super, ["tests"]) :
            cls == "top" ? (:super, ["app", "customize", "demo"]) :
            cls == "bench" ? (:sub, ["bench"]) :
            startswith(cls, "pkg-") ? (:sub, ["packages/" * cls[5:end]]) : (:none, String[])
        (Symbol(m.source[1]), roots) == want ||
            push!(probs, "class $cls does not match its source line: $(join(m.source, ' '))")
        m.source[1] == "super" && m.source[2] != pin &&
            push!(probs, "source commit $(m.source[2]) is not the pin $pin")
        for r in m.rows
            any(root -> startswith(r[3], root * "/"), roots) ||
                push!(probs, "$(r[3]) is outside the roots $roots")
        end
    end
    paths = [r[3] for r in m.rows]
    length(unique(paths)) == length(paths) || push!(probs, "a path is listed twice")
    there = [p for p in paths if isfile(joinpath(dir, p))]
    for p in setdiff(paths, there)
        push!(probs, "MISSING: $p")
    end
    ids = _ve_blobs([joinpath(dir, p) for p in there])
    got = Dict(zip(there, ids))
    for (mode, id, p) in m.rows
        haskey(got, p) || continue
        got[p] == id || push!(probs, "DIFFERS: $p ($(got[p]), manifest $id)")
        exe = (stat(joinpath(dir, p)).mode & 0o111) != 0
        (mode == "100755") == exe ||
            push!(probs, "MODE: $p is $(exe ? "executable" : "not executable"), manifest $mode")
    end
    present = String[]
    for r in roots, (d, _, files) in walkdir(joinpath(dir, r)), f in files
        push!(present, relpath(joinpath(d, f), dir))
    end
    for p in setdiff(present, paths)
        push!(probs, "ADDED: $p")
    end
    return probs
end

"The manifest paths of every class and every file present under the extra tree."
_ve_all_manifests() = sort!(filter(f -> endswith(f, ".txt"), readdir(_VE_MANIFESTS; join = true)))

@testset "vendor/swipl-devel-extra is swipl-devel at the pin, unchanged: every class" begin
    pin = _ve_pin("commit")
    @test occursin(r"^[0-9a-f]{40}$", pin)
    manifests = _ve_all_manifests()
    classes = [replace(basename(f), r"\.txt$" => "") for f in manifests]
    @test issubset(_VE_CLASSES, classes)
    for f in manifests
        @test _ve_problems(f, _VE_DIR, pin) == String[]
    end
    # no file outside the manifests, and no file in two of them (a file of the extra tree is
    # listed by exactly one class)
    listed = String[]
    for f in manifests
        append!(listed, [r[3] for r in _ve_read(f).rows])
    end
    @test length(unique(listed)) == length(listed) && !isempty(listed)
    present = String[]
    for (d, _, files) in walkdir(_VE_DIR), f in files
        push!(present, relpath(joinpath(d, f), _VE_DIR))
    end
    @test sort!(present) == sort!(listed)
end

# THE GUARD CAN FAIL: broken copies of one small manifest (pkg-paxos), each over the same tree, each
# named by the same checking function.
@testset "the checking function reports every kind of break" begin
    pin = _ve_pin("commit")
    src = joinpath(_VE_MANIFESTS, "pkg-paxos.txt")
    lines = readlines(src)
    rows = [i for (i, l) in enumerate(lines) if !startswith(l, "#")]
    @test length(rows) >= 3 && startswith(lines[rows[1]], "100644")
    first_row = split(lines[rows[1]], '\t')
    broken(edit::Function) = mktempdir() do d
        f = joinpath(d, "pkg-paxos.txt")
        write(f, join(edit(copy(lines)), "\n") * "\n")
        _ve_problems(f, _VE_DIR, pin)
    end
    wrong = "0123456789abcdef0123456789abcdef01234567"
    @test broken(identity) == String[]
    # a wrong blob id
    p = broken(ls -> (ls[rows[1]] = "100644 blob $wrong\t$(first_row[2])"; ls))
    @test length(p) == 1 && startswith(p[1], "DIFFERS: $(first_row[2]) ")
    # a file the manifest does not list: ADDED
    p = broken(ls -> (deleteat!(ls, rows[1]); ls))
    @test p == ["ADDED: $(first_row[2])"]
    # a listed file that is not in the tree: MISSING
    p = broken(ls -> (push!(ls, "100644 blob $wrong\tpackages/paxos/zz_missing.pl"); ls))
    @test p == ["MISSING: packages/paxos/zz_missing.pl"]
    # a mode that is not the file's
    p = broken(ls -> (ls[rows[1]] = "100755 blob $(split(first_row[1])[3])\t$(first_row[2])"; ls))
    @test length(p) == 1 && startswith(p[1], "MODE: $(first_row[2]) ")
    # another commit in the header
    p = broken(ls -> (ls[1] = replace(ls[1], pin => wrong); ls))
    @test any(startswith("header commit"), p)
    # a line that is no manifest row
    p = broken(ls -> (push!(ls, "not a row"); ls))
    @test p == ["unexpected manifest line: not a row"]
    # a source line that does not match the class
    p = broken(ls -> (ls[3] = replace(ls[3], "packages/paxos" => "packages/chr"); ls))
    @test any(startswith("class pkg-paxos does not match"), p)
end

# THE GITLINKS AND TREES (as test_vendored_plunit.jl): CI's jobs check out swipl-devel at the pinned
# commit with its submodules, so there (`CI=true`) this testset FAILS when the checkout, or a
# submodule at its pinned commit in it, is missing. Only a LOCAL run without a checkout skips it.
const _VE_UP = get(
    ENV,
    "LOGICKERNEL_UPSTREAM_SWIPL_DEVEL",
    joinpath(homedir(), "dev-zone", "swipl-devel")
)
const _VE_CI = get(ENV, "CI", "") == "true"

"The git command prefix of submodule `sub` of the checkout `up` holding commit `sha`, or `nothing`."
function _ve_subgit(up::String, sub::String, sha::String)::Union{Nothing, Cmd}
    for g in (`git --git-dir=$(joinpath(up, ".git", "modules", sub))`, `git -C $(joinpath(up, sub))`)
        success(pipeline(`$g cat-file -e $(sha * "^{commit}")`; stderr = devnull)) && return g
    end
    return nothing
end

if _VE_CI || isdir(joinpath(_VE_UP, ".git"))
    @testset "every manifest is upstream's own tree at the pinned swipl-devel" begin
        up = _VE_UP
        have_up = isdir(joinpath(up, ".git"))
        have_up ||
            @error "test_vendored_extra: CI must check out swipl-devel at the pinned " *
                "commit (LOGICKERNEL_UPSTREAM_SWIPL_DEVEL = $up): none there"
        @test have_up
        if have_up
            pin = _ve_pin("commit")
            for f in _ve_all_manifests()
                cls = replace(basename(f), r"\.txt$" => "")
                m = _ve_read(f)
                rows = ["$(r[1]) blob $(r[2])\t$(r[3])" for r in m.rows]
                if m.source[1] == "super"
                    listed = readlines(`git -C $up ls-tree -r $pin -- $(m.source[3:end])`)
                    @test sort!(listed) == sort!(rows)
                else
                    sub, sha = m.source[2], m.source[3]
                    link = split(readchomp(`git -C $up ls-tree $pin -- $sub`))
                    @test length(link) >= 3 && link[2] == "commit" && link[3] == sha
                    g = _ve_subgit(up, sub, sha)
                    if g !== nothing
                        listed = [
                            replace(l, '\t' => "\t$sub/"; count = 1) for
                                l in readlines(`$g ls-tree -r $sha`)
                        ]
                        @test sort!(listed) == sort!(rows)
                    elseif _VE_CI
                        @error "test_vendored_extra: CI must check out $sub at $sha in $up " *
                            "(submodules: true): it is not there"
                        @test g !== nothing
                    else
                        @info "test_vendored_extra: the local checkout $up has no $sub at " *
                            "$sha — class $cls is not checked against it (it is in CI)"
                    end
                end
            end
        end
    end
else
    @info "test_vendored_extra: no swipl-devel checkout here (a local run) — the blob ids are " *
        "checked, the gitlinks and trees are not (they are in CI)"
end
