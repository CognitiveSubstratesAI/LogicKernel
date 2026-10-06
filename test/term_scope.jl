# ORIGINAL: the gate split (user, 2026-10-06) — which term-generic test files the LOCAL commit gate
# runs on every term implementation between milestones, and which changes make it run them all.
#
# A term-generic test file (one that includes test/term_under_test.jl) runs on every implementation
# of the term interface (`LK_TERM_IMPLS`). CI (`Pkg.test`, no environment) always runs every unit,
# and so does a milestone. Between milestones the local gate runs a declared subset on the
# alternative implementations. Each term-generic file declares its term types per chunk in ONE line:
#
#   # TERM TYPES PER CHUNK: ALL — src/…jl, src/…jl         every implementation, every chunk; the
#                                                          source files behind the file follow
#   # TERM TYPES PER CHUNK: REFERENCE — <why>              the reference implementation only
#
# The ALL files test the term layer and the primitives that walk terms (unification, comparison,
# hashing, variants, the binding store). A chunk that changes a TRIGGER — the term layer itself, a
# source file an ALL declaration names, or this gate's own logic — runs every file on every
# implementation. Both the runner (test/runtests.jl) and the coordinator's decision
# (tools/term_scope.jl) use this file: ONE extractor, so they cannot disagree.

const LK_TERM_GENERIC_RX = r"^include\(joinpath\(@__DIR__, \"\.\.\", \"term_under_test\.jl\"\)\)"m
const LK_TERM_SCOPE_RX = r"^# TERM TYPES PER CHUNK: ([A-Z]+)\b(.*)$"m

"The term layer: the interface, the reference type, the alternative type and its test library."
const LK_TERM_LAYER = [
    "src/term_interface.jl", "src/default_term.jl", "test/term_under_test.jl",
    "test/core_lang/alt_term.jl", "test/core_lang/term_interface_testlib.jl"
]

"The gate's own logic: a change to how the scope is decided runs every file on every type."
const LK_TERM_GATE_LOGIC = [
    "test/term_scope.jl", "test/runtests.jl", "tools/term_scope.jl", "tools/worker.jl",
    "tools/run_tests.sh"
]

"Whether a test file's `text` is term-generic: it includes test/term_under_test.jl."
lk_term_generic(text::AbstractString)::Bool = occursin(LK_TERM_GENERIC_RX, text)

"""
    lk_term_scope(path, text) -> (scope, sources)

A term-generic file's declaration: `(:all, the source files it names)` or `(:reference, [])`.
Throws unless the file declares exactly one known scope, and an ALL one names its sources.
"""
function lk_term_scope(path::AbstractString, text::AbstractString)
    ms = collect(eachmatch(LK_TERM_SCOPE_RX, text))
    length(ms) == 1 || error(
        "$path: a term-generic test file declares its term types per chunk in exactly ONE " *
        "line, `# TERM TYPES PER CHUNK: ALL — src/…` or `# TERM TYPES PER CHUNK: REFERENCE — " *
        "why` (test/term_scope.jl); found $(length(ms))"
    )
    kind, rest = ms[1][1], ms[1][2]
    if kind == "ALL"
        srcs = String[m.match for m in eachmatch(r"\bsrc/[A-Za-z0-9_.-]+\.jl\b", rest)]
        isempty(srcs) && error("$path: an ALL declaration names the source files behind it")
        return (:all, srcs)
    elseif kind == "REFERENCE"
        return (:reference, String[])
    end
    error("$path: unknown term types per chunk `$kind` (ALL or REFERENCE)")
end

"Every test file under `testdir` (`test_*.jl`), sorted."
lk_test_files(testdir::AbstractString)::Vector{String} = sort!([
    joinpath(dir, f) for (dir, _, files) in walkdir(testdir) for
    f in files if startswith(f, "test_") && endswith(f, ".jl")
])

"""
    lk_term_scopes(testdir) -> Dict(file => (scope, sources))

The declaration of every term-generic test file under `testdir`; throws on a missing or bad one.
"""
function lk_term_scopes(testdir::AbstractString)
    out = Dict{String, Tuple{Symbol, Vector{String}}}()
    for f in lk_test_files(testdir)
        text = read(f, String)
        lk_term_generic(text) && (out[f] = lk_term_scope(f, text))
    end
    return out
end

"""
    lk_term_triggers(root) -> Vector{String}

The paths (relative to the package `root`) whose change runs every file on every implementation:
the term layer, every source file an ALL declaration names, and the gate's own logic. Throws if a
named source file does not exist: a trigger that cannot match would never fire.
"""
function lk_term_triggers(root::AbstractString)::Vector{String}
    named = String[]
    for (f, (scope, srcs)) in lk_term_scopes(joinpath(root, "test"))
        scope === :all || continue
        for s in srcs
            isfile(joinpath(root, s)) ||
                error("$f: its ALL declaration names $s, which does not exist")
            push!(named, s)
        end
    end
    return sort!(unique!([LK_TERM_LAYER; LK_TERM_GATE_LOGIC; named]))
end

"""
    lk_term_types(triggers, changed; full=false) -> (types, why)

The term types of a chunk's local gate: `"all"` when `full` (a milestone) or when a `changed` path
is a trigger, else `"chunk"`; and why, for the run's header.
"""
function lk_term_types(triggers::Vector{String}, changed::Vector{String}; full::Bool=false)
    full && return ("all", "a milestone (LOGICKERNEL_FULL=1)")
    hit = sort!(intersect(changed, triggers))
    isempty(hit) || return ("all", "a trigger changed: " * join(hit, ", "))
    return ("chunk", "no trigger changed ($(length(changed)) files changed)")
end

"""
    lk_units_impls(scope, types, impls) -> the implementations a term-generic file runs on

Every implementation under `"all"` or for an ALL file; the reference one alone (`first(impls)`)
for a REFERENCE file in a `"chunk"` run.
"""
function lk_units_impls(scope::Symbol, types::AbstractString, impls)
    types in ("all", "chunk") ||
        error("LOGICKERNEL_TERM_TYPES is `$types`: it is `all` or `chunk`")
    return types == "all" || scope === :all ? impls : (first(impls),)
end
