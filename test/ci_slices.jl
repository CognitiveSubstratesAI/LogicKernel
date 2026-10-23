# ORIGINAL: the CI slices (D-0059, 2026-10-20) — no swipl-devel counterpart.
# test/ci_slices.jl — the two ways CI spreads ONE run of the suite over several runners, read in one
# place (test/runtests.jl and test/static_analysis_body.jl include it):
#
#   LOGICKERNEL_FILE_GROUP=k/G   the k-th of G groups of test files (test/runtests.jl); the static
#                                analysis is in no group — it runs in jobs of its own:
#   LOGICKERNEL_SA_SHARD=k/N     the k-th of N slices of the static analysis: every N-th manifest entry
#                                and every N-th of its one-off gates (test/static_analysis_body.jl)
#
# Unset, each is `(1, 1)`: everything, as locally and in main's unsharded `analysis` job. Each job
# writes what it ran, and tools/evidence_ci.py checks that the jobs TOGETHER ran every unit exactly
# once and the shards every manifest entry — a slice that silently ran nothing must not read as green.
# THE GROUPS are balanced by test/unit_costs.tsv (seconds per file, all term types; the Verdict
# table's artifact `unit-costs` is the measured replacement): the costliest file first, each into the
# group with the least cost so far; a file with no cost counts as the median.
# CI.yml's Pkg.test jobs balance by THEIR OWN table, test/pkgtest_costs.tsv (LOGICKERNEL_COSTS_TABLE; measured under
# coverage, tools/pkgtest_costs.py turns the pkgtest gather's `unit-costs` notice into it): Evidence's costs, no
# coverage, left the `Julia 1` groups at 1004 / 483 / 559 s (A-0054). `lk_costs_path` names the table to read.

"`(k, n)` from `\"k/n\"` in `ENV[name]`, `(1, 1)` when it is unset or empty; anything else is an error."
function lk_slice(name::AbstractString)::Tuple{Int, Int}
    s = get(ENV, name, "")
    isempty(s) && return (1, 1)
    m = match(r"^([1-9][0-9]*)/([1-9][0-9]*)$", s)
    k, n = m === nothing ? (0, 0) : (parse(Int, m[1]), parse(Int, m[2]))
    1 <= k <= n || error("$name=$(repr(s)): expected k/n with 1 ≤ k ≤ n")
    return (k, n)
end

"Whether item `i` (1-based) is in slice `kn = (k, n)`: every n-th, from the k-th."
lk_in_slice(i::Integer, kn::Tuple{Int, Int})::Bool = (i - 1) % kn[2] == kn[1] - 1

"Seconds per test file (relative to `test/`) from a `file<TAB>seconds` table, `#` lines skipped."
function lk_unit_costs(path::AbstractString)::Dict{String, Float64}
    costs = Dict{String, Float64}()
    isfile(path) || return costs
    for l in eachline(path)
        (isempty(strip(l)) || startswith(l, '#')) && continue
        f, s = split(l, '\t')
        costs[f] = parse(Float64, s)
    end
    return costs
end

"""
The cost table of this run: `unit_costs.tsv` in `test_dir`, or the table `ENV["LOGICKERNEL_COSTS_TABLE"]` names
(a bare `name.tsv` file of `test_dir`). A named table that is malformed or missing is an error, never a silent
fall back to the other table: the groups of one run's jobs must all come from the same costs.
"""
function lk_costs_path(test_dir::AbstractString)::String
    name = get(ENV, "LOGICKERNEL_COSTS_TABLE", "")
    isempty(name) && return joinpath(test_dir, "unit_costs.tsv")
    occursin(r"^[A-Za-z0-9_]+\.tsv$", name) ||
        error("LOGICKERNEL_COSTS_TABLE=$(repr(name)): expected a bare file name `name.tsv`")
    path = joinpath(test_dir, name)
    isfile(path) ||
        error("LOGICKERNEL_COSTS_TABLE=$(repr(name)): no such file in $test_dir")
    return path
end

"""
The group, `1:G`, of each file in `files` (relative names): longest-processing-time first over
`costs` (a file with none counts as the median, 1.0 with no costs at all), ties to the lower group;
the order is total — cost, then name — so every job computes the same assignment.
"""
function lk_file_groups(
    files::Vector{String}, G::Int, costs::Dict{String, Float64}
)::Dict{String, Int}
    known = sort!([costs[f] for f in files if haskey(costs, f)])
    median = isempty(known) ? 1.0 : known[(length(known) + 1) ÷ 2]
    cost(f) = get(costs, f, median)
    load = zeros(G)
    group = Dict{String, Int}()
    for f in sort(files; by=f -> (-cost(f), f))
        k = argmin(load)
        group[f] = k
        load[k] += cost(f)
    end
    return group
end
