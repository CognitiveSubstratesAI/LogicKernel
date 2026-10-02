# tools/upstream_drift.jl — what changed upstream since each port, and how much of each file is ported.
#
#   julia --project=. tools/upstream_drift.jl
#
# For every `# UPSTREAM: <repo> <path> @ <commit>` header (see tools/port_check.jl for the rule):
#   * the upstream commits that touched <path> since <commit> — the incremental work list when
#     syncing with upstream;
#   * coverage: how many of the upstream file's functions/predicates carry a `# PORT:` marker here.
#
# ⚠️ The upstream function list is a HEURISTIC, by language: C — an identifier at column 0
# followed by `(` on a line not ending in `;` (SWI's style puts the return type on the line above),
# plus `PRED_IMPL("name", …)`; Prolog — clause heads at column 0; Rust — `fn name`. Good enough to
# rank what is left; never a reason to claim something "is not upstream" — port_check.jl's exact
# word search is the authority for that.

isdefined(@__MODULE__, :port_check) || include(joinpath(@__DIR__, "port_check.jl"))

struct DriftRow
    kernel_file::String
    repo::String
    path::String
    commit::String
    commits_since::Vector{String}
    upstream_names::Vector{String}
    ported::Vector{String}
end

"Function/predicate names defined in an upstream source text (heuristic, see the header)."
function upstream_names(path::AbstractString, text::AbstractString)::Vector{String}
    names = String[]
    if occursin(r"\.(c|h)$", path)
        for l in eachline(IOBuffer(text))
            m = match(r"^([A-Za-z_]\w*)\s*\(", l)
            m !== nothing && !endswith(rstrip(l), ";") && !startswith(l, "PRED_IMPL") &&
                push!(names, m[1])
            m = match(r"^PRED_IMPL\(\"([^\"]+)\"", l)
            m === nothing || push!(names, m[1])
        end
    elseif endswith(path, ".pl")
        for l in eachline(IOBuffer(text))
            m = match(r"^'?(\$?[a-z][A-Za-z0-9_]*)'?\s*(\(|:-|-->|\.)", l)
            m === nothing || push!(names, m[1])
        end
    elseif endswith(path, ".rs")
        for m in eachmatch(r"\bfn\s+([A-Za-z_]\w*)", text)
            push!(names, m[1])
        end
    end
    return sort!(unique!(names))
end

function upstream_drift(
    pkgroot::AbstractString; upstream_dirs::Dict{String, String}=default_upstream_dirs()
)
    root = abspath(pkgroot)
    rows = DriftRow[]
    for f in port_check(root; upstream_dirs=upstream_dirs).files, u in f.upstreams
        dir = get(upstream_dirs, u.repo, "")
        isdir(joinpath(dir, ".git")) || continue
        log = read(
            pipeline(
                `git -C $dir log "--format=%h %ad %s" --date=short $(u.commit)..HEAD -- $(u.path)`;
                stderr=devnull), String)
        since = filter(!isempty, split(log, '\n'))
        text = if _git_ok(dir, "cat-file", "-e", "HEAD:" * u.path)
            _git_show(dir, "HEAD:" * u.path)
        else
            ""
        end
        un = upstream_names(u.path, text)
        mine = sort!(
            unique!([m.name for m in f.markers if m.upstream_base == basename(u.path)])
        )
        push!(
            rows,
            DriftRow(
                f.rel, u.repo, u.path, u.commit, String.(since), un, filter(in(un), mine)
            )
        )
    end
    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    rows = upstream_drift(joinpath(@__DIR__, ".."))
    isempty(rows) &&
        println("upstream_drift: no ported files with an available upstream checkout")
    for r in rows
        println(r.kernel_file, "  ←  ", r.repo, " ", r.path, " @ ", r.commit)
        println("   ported ", length(r.ported), " of ", length(r.upstream_names),
            " upstream function(s)",
            isempty(r.ported) ? "" : ": " * join(r.ported, ", "))
        println(
            "   ",
            length(r.commits_since),
            " upstream commit(s) since",
            isempty(r.commits_since) ? "" : ":"
        )
        foreach(c -> println("     ", c), r.commits_since)
    end
end
