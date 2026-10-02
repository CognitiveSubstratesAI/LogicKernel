# tools/lint_globals.jl — FAIL ON MODULE-LEVEL MUTABLE STATE.
#
# WHY. A kernel meant to serve more than one client cannot keep state at module scope: it is shared
# by every caller in the process, and it outlives each of them. The failure it prevents is concrete:
# a tabling registry kept as a bare `Set` at module scope means that once anything tables a
# predicate, EVERY later database in the process inherits it — a benchmark's "untabled" rows are
# silently tabled, and the only tell is suspiciously flat timings. State that belongs to one evaluation lives in a
# value the caller owns and passes in.
#
# HOW. It enumerates the module's BINDINGS at runtime (`names(m; all = true)`), recursing into
# submodules, instead of grepping the source — so a global made by a macro, or a closure that
# captured a `Ref`, cannot hide from it. A binding passes only if it is `const` AND its value is
# FROZEN: isbits; a `Symbol`, `String`, `Module` or `Type`; or an immutable struct / tuple /
# closure whose every field is frozen. So `Dict`, `Set` (a struct around a `Dict`), `Vector`, `Ref`,
# `IdDict` and every mutable struct fail, at any depth: `const T = (1, Int[])` fails too.
#
# TWO EXEMPTIONS, BOTH JULIA'S OWN, BOTH MATCHED EXACTLY — never by a blanket `#` prefix:
#   * the docstring table, bound under the name `Base.Docs.META`;
#   * compiler-generated `#…` bindings whose value is a Function or a Type (closures, and the
#     temporaries a docstring macro leaves behind). A `#…` binding holding anything else is flagged.
#
# THE ALLOWLIST is `LINT_ALLOWLIST` below: `"Module.name" => "reason"` pairs. An empty reason is an
# error, and an entry that matches no binding is a violation — a stale entry would otherwise
# pre-approve whatever later takes that name.
#
# Usage:
#   from the suite — `test/test_lint_globals.jl` includes this file and runs it;
#   standalone     — `julia --project=. tools/lint_globals.jl`  (exit 0 clean, 1 violations)

"""Qualified binding name => why it is allowed to be module-level state. Empty: nothing is."""
const LINT_ALLOWLIST = ()   # e.g. ("LogicKernel.SOME_CACHE" => "why this cannot be per-caller",)

"""
    _lint_frozen(v, depth = 0) -> Bool

True when `v` cannot change after construction: isbits, a `Symbol`/`String`/`Module`/`Type`, or an
immutable object all of whose defined fields are frozen. Depth-capped and conservative: an object
nested deeper than 64 levels is reported, not assumed safe.
"""
function _lint_frozen(v, depth::Int=0)::Bool
    depth > 64 && return false
    v isa Union{Module, Type, Symbol, String} && return true   # `ismutable` says true; they are not
    isbits(v) && return true
    ismutable(v) && return false
    for i in 1:nfields(v)
        isdefined(v, i) || continue        # an undefined field of an immutable stays undefined
        _lint_frozen(getfield(v, i), depth + 1) || return false
    end
    return true
end

_lint_generated(n::Symbol, v)::Bool =
    startswith(String(n), "#") && (v isa Function || v isa Type)

"""
    lint_globals(m::Module; allow = LINT_ALLOWLIST) -> (; violations::Vector{String}, inspected::Int)

Every module-level binding of `m` and its submodules that is not `const` or whose value is not
frozen, minus the allowlist. `inspected` counts the bindings examined, so a caller can assert the
scan saw something — an empty violation list from a scan of nothing proves nothing.
"""
function lint_globals(m::Module; allow=LINT_ALLOWLIST)
    allowed = Dict{String, String}()
    for (k, why) in allow
        isempty(strip(why)) && error("lint_globals: allowlist entry `$k` has no reason")
        allowed[k] = why
    end
    used = Set{String}()
    violations = String[]
    inspected = _lint_scan!(violations, used, m, allowed, Set{Module}())
    for k in sort!(collect(keys(allowed)))
        k in used || push!(violations, "$k: STALE allowlist entry — no such binding")
    end
    return (; violations, inspected)
end

function _lint_scan!(out::Vector{String}, used::Set{String}, m::Module,
    allowed::Dict{String, String}, seen::Set{Module})::Int
    m in seen && return 0
    push!(seen, m)
    inspected = 0
    for n in names(m; all=true, imported=false)
        n === Base.Docs.META && continue
        qn = string(nameof(m), ".", n)
        inspected += 1
        if !isdefined(m, n)
            if haskey(allowed, qn)
                push!(used, qn)
            else
                push!(out, "$qn: declared but never assigned — a mutable global slot")
            end
            continue
        end
        v = getfield(m, n)
        if v isa Module
            v !== m && parentmodule(v) === m &&
                (inspected += _lint_scan!(out, used, v, allowed, seen))
            continue
        end
        _lint_generated(n, v) && continue
        bad = if !isconst(m, n)
            "non-const global (a $(typeof(v)))"
        elseif !_lint_frozen(v)
            "mutable state at module level (a $(typeof(v)))"
        else
            nothing
        end
        bad === nothing && continue
        haskey(allowed, qn) ? push!(used, qn) : push!(out, "$qn: $bad")
    end
    return inspected
end

if abspath(PROGRAM_FILE) == @__FILE__
    using LogicKernel
    r = lint_globals(LogicKernel)
    println(
        "lint_globals: $(r.inspected) binding(s) inspected, $(length(r.violations)) violation(s)"
    )
    foreach(v -> println("  ", v), r.violations)
    exit(isempty(r.violations) && r.inspected > 0 ? 0 : 1)
end
