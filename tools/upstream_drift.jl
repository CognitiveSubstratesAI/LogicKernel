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

# `upstream_names` (the heuristic above) lives in tools/port_check.jl, whose code map counts with it.

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

# ── not ported: unreachable upstream (user, 2026-10-05) ─────────────────────────────────────────
# A function or macro that NOTHING reaches at the recorded commit is not ported: unreachable code
# cannot be tested, so it would sit in the kernel unverified. docs/port_inventory.md lists each one
# in a table between the two markers below, and this report re-checks it against upstream HEAD — the
# moment upstream USES it, it is reported, and porting it becomes work. A use is an occurrence of
# the name as a word on a line that is not its definition (`#define NAME`, or `NAME(` at column 0),
# searched in the upstream file the row names: the list holds file-local macros and static functions.
const UNREACHABLE_BEGIN = "<!-- BEGIN not ported: unreachable upstream"
const UNREACHABLE_END = "<!-- END not ported: unreachable upstream -->"

struct UnreachableRow
    repo::String
    path::String
    name::String
    commit::String
end

"The rows of the not-ported-because-unreachable table in the inventory text `inventory`."
function unreachable_rows(inventory::AbstractString)::Vector{UnreachableRow}
    i = findfirst(UNREACHABLE_BEGIN, inventory)
    j = findfirst(UNREACHABLE_END, inventory)
    (i === nothing || j === nothing) && return UnreachableRow[]
    rows = UnreachableRow[]
    for l in split(inventory[last(i):first(j)], '\n')
        m = match(r"^\|\s*(\S+)\s+`([^`]+)`\s*\|\s*`([^`]+)`\s*\|\s*`([0-9a-f]+)`\s*\|", l)
        m === nothing || push!(rows, UnreachableRow(m[1], m[2], m[3], m[4]))
    end
    return rows
end

"""
The line numbers of `text` that use `name`: a word occurrence on a line that is not its definition —
`#define name` when `text` defines it as a macro (so a macro used at column 0, `VMI(…)`, is a use),
else `name(` at column 0, SWI's style for a function definition.
"""
function unreachable_uses(text::AbstractString, name::AbstractString)::Vector{Int}
    word = Regex("\\b" * name * "\\b")
    macro_def = Regex("^#\\s*define\\s+" * name * "\\b")
    def = if occursin(Regex(macro_def.pattern, "m"), text)
        macro_def
    else
        Regex("^" * name * "\\s*\\(")
    end
    return [
        k for
        (k, l) in enumerate(split(text, '\n')) if occursin(word, l) && !occursin(def, l)
    ]
end

"""
    unreachable_drift(pkgroot; upstream_dirs, at_head=true)

For each row of the unreachable list whose upstream checkout is here: the row and the lines of its
upstream file that use its name — at upstream HEAD, or (`at_head=false`) at the commit it records.
"""
function unreachable_drift(
    pkgroot::AbstractString;
    upstream_dirs::Dict{String, String}=default_upstream_dirs(),
    at_head::Bool=true
)::Vector{Tuple{UnreachableRow, Vector{Int}}}
    inventory = read(joinpath(pkgroot, "docs", "port_inventory.md"), String)
    out = Tuple{UnreachableRow, Vector{Int}}[]
    for r in unreachable_rows(inventory)
        dir = get(upstream_dirs, r.repo, "")
        isdir(joinpath(dir, ".git")) || continue
        spec = (at_head ? "HEAD" : r.commit) * ":" * r.path
        text = _git_ok(dir, "cat-file", "-e", spec) ? _git_show(dir, spec) : ""
        push!(out, (r, unreachable_uses(text, r.name)))
    end
    return out
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
    for (r, uses) in unreachable_drift(joinpath(@__DIR__, ".."))
        println(r.name, "  (", r.repo, " ", r.path, ", not ported: unreachable @ ",
            r.commit, ")  ",
            if isempty(uses)
                "still unreachable at HEAD"
            else
                "NOW USED at HEAD, line(s) " * join(uses, ", ") * " — port it"
            end)
    end
end
