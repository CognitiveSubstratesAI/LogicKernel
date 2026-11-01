# ORIGINAL: the template database (R2 LB4 b1, loader_boot design LD4 / H3) — upstream loads a saved state once per process; the kernel copies a booted `PL_global_data{T}` per new database.
#
# THE TEMPLATE DATABASE. Upstream boots once per process (the boot file compiled by `pl-init.c`, or the saved state
# loaded) and every thread then shares the one `GD`. The kernel's `GD` is a value, one per database, so a database made
# after the boot gets a COPY of a booted one: the boot (the 21.6k lines of boot/*.pl, LB4 b2) is paid once per process
# and term type, not once per `PL_global_data{T}()` (139 call sites in test/, three term types: H3).
#
# THIS FILE IS DORMANT. b1 builds the copy and the registry; b2 turns them on (the booted constructor becomes the
# registry's `build`, and `PL_global_data{T}()` the copy). Until then no constructor calls any of it, and the template
# the registry builds by default is the UNBOOTED database `PL_global_data{T}()` makes.
#
# THE COPY IS GENERIC. `copy_global_data` is generated from the fields of `PL_global_data`: a field a later step appends
# (G1, D2, F1b, O1B) is copied with no edit here. `GD_COPY_POLICY` lists the exceptions; every other field is DEEP-copied,
# all of them through ONE `IdDict`, so the identities that hold inside a database hold in its copy (`modules_user` is an
# entry of `modules`, the `procedures_*` are entries of the system module's table, every definition holds the one
# `code_data`, a clause its definition and the definition its clause list) and nothing the copy reaches is shared with the
# template. `gd_aliased_objects` is the check of that claim; the H3 rows in test/db/test_gd_template.jl run it.

# The fields of `PL_global_data` the copy does not deep-copy, and what it does instead:
#   :streams — the stream tables (`stream_filenames`, `stream_aliases`, `stream_table`). A booted template holds no open
#              stream (the boot closes every file it opens); the copy gets EMPTY tables of the same shape (a closed
#              stream's slot in `stream_table` stays `nothing`, so a stream context keeps its index) and REFUSES a template
#              that holds a live IOSTREAM: an open file must not be shared by two databases, and an IOSTREAM wraps a Julia IO.
# Any field not named here is :deep.
"How `copy_global_data` copies a `PL_global_data` field, when it is not a deep copy (`:streams`: see the comment above)."
const GD_COPY_POLICY = (
    stream_filenames = :streams,
    stream_aliases = :streams,
    stream_table = :streams,
)

# The copy of one stream table: empty, and the same shape. `x` is the template's field.
function _copy_stream_free(x::AbstractVector)
    for s in x
        s === nothing || error("copy_global_data: the template holds an open stream")
    end
    return copy(x)
end

function _copy_stream_free(x::AbstractDict)
    isempty(x) || error("copy_global_data: the template holds an open stream")
    return typeof(x)()
end

"""
    copy_global_data(gd) -> PL_global_data

A copy of the database state `gd`, sharing no mutable object with it (see the comment at the top of
src/gd_template.jl and `GD_COPY_POLICY`). Generated from the fields of `PL_global_data`: the call lists every
field in the struct's order, each by its policy, so the copy follows the struct.
"""
@generated function copy_global_data(gd::PL_global_data{T}) where {T}
    names = fieldnames(gd)
    types = fieldtypes(gd)
    args = Expr[]
    for (f, ft) in zip(names, types)
        policy = get(GD_COPY_POLICY, f, :deep)
        if policy === :streams
            push!(args, :(_copy_stream_free(getfield(gd, $(QuoteNode(f))))::$ft))
        elseif policy === :deep
            push!(args, :(Base.deepcopy_internal(getfield(gd, $(QuoteNode(f))), stay)::$ft))
        else
            error("copy_global_data: field $f has the unknown policy $policy")
        end
    end
    return quote
        stay = IdDict{Any, Any}()   # allow-any: deepcopy_internal's own stack-dict type
        PL_global_data{T}($(args...))
    end
end

# ── the registry: one template per process and term type ─────────────────────────────────────────
# DIVERGES: upstream has one process-wide GD; the kernel allows no module-level mutable state
# (tools/lint_globals.jl), and this registry is the one place a database outlives its caller: it is
# allowlisted there. It holds BOOTED TEMPLATES only; a database made from one is a copy the caller owns.
"The templates of a process: a booted `PL_global_data{T}` per term type `T`, built at the first request (src/gd_template.jl)."
mutable struct gd_template_registry
    const lock::ReentrantLock
    const templates::Dict{DataType, PL_global_data}
end

# a registry per process, allowlisted in tools/lint_globals.jl (a comment: a docstring would keep a second binding to the value)
const _GD_TEMPLATES = gd_template_registry(ReentrantLock(), Dict{DataType, PL_global_data}())

"""
    gd_template(T, build) -> PL_global_data{T}
    gd_template(T)

The template database of term type `T`: `build()` is called ONCE per process and type, under a lock, and the result is
kept. `build` makes a booted `PL_global_data{T}`; the one-argument form builds with the constructor
`PL_global_data{T}` (UNBOOTED until b2 enables the boot). The caller must not change the template: databases are
made by `PL_global_data_from_template`.
"""
function gd_template(::Type{T}, build::F)::PL_global_data{T} where {T, F}
    reg = _GD_TEMPLATES
    lock(reg.lock)
    try
        t = get(reg.templates, T, nothing)
        if t === nothing
            t = build()::PL_global_data{T}
            reg.templates[T] = t
        end
        return t::PL_global_data{T}
    finally
        unlock(reg.lock)
    end
end

gd_template(::Type{T}) where {T} = gd_template(T, PL_global_data{T})

"""
    PL_global_data_from_template(T, build) -> PL_global_data{T}
    PL_global_data_from_template(T)

A new database state: a copy of the template of `T` (`gd_template`), which this builds if it is the first request.
"""
PL_global_data_from_template(::Type{T}, build::F) where {T, F} = copy_global_data(gd_template(T, build))

PL_global_data_from_template(::Type{T}) where {T} = copy_global_data(gd_template(T))

"Whether the template of term type `T` has been built in this process (`gd_template`)."
function gd_template_built(::Type{T})::Bool where {T}
    reg = _GD_TEMPLATES
    lock(reg.lock)
    try
        return haskey(reg.templates, T)
    finally
        unlock(reg.lock)
    end
end

"Forget every template of this process, so the next request builds again (for tests; a copy already made is unaffected)."
function reset_gd_templates!()::Nothing
    reg = _GD_TEMPLATES
    lock(reg.lock)
    try
        empty!(reg.templates)
    finally
        unlock(reg.lock)
    end
    return nothing
end

# ── the alias check ──────────────────────────────────────────────────────────────────────────────
# Skipped by the walk: values with no identity worth tracking (bits, symbols, strings, types, modules).
_alias_skip(x) = isbits(x) || x isa Union{Symbol, String, Module, DataType, Union, UnionAll, Core.SimpleVector}

"""
    _reachable_mutables(root) -> IdSet

Every mutable object reachable from `root` through fields and array elements (strings, symbols and types left out).
Explicit stack: a clause list is a linked list as long as the predicate.
"""
function _reachable_mutables(root)::IdSet{Any}   # allow-any: the objects of a database graph have every type
    seen = IdSet{Any}()   # allow-any: as above
    stack = Any[root]   # allow-any: as above; a test-time walk, not a hot path
    while !isempty(stack)
        x = pop!(stack)
        _alias_skip(x) && continue
        x isa Memory && isempty(x) && continue   # the empty Memory of a type is one shared instance: no database owns it
        if ismutable(x)
            x in seen && continue
            push!(seen, x)
        end
        if x isa Memory
            isbitstype(eltype(x)) && continue
            for i in eachindex(x)
                isassigned(x, i) && push!(stack, x[i])
            end
        else
            for i in 1:nfields(x)
                isdefined(x, i) && push!(stack, getfield(x, i))
            end
        end
    end
    return seen
end

"""
    gd_aliased_objects(a, b) -> Vector

The mutable objects reachable from both `a` and `b` (two database states): empty for a template and its copy, and
for two copies. The H3 rows' guard that the copy shares no clause table, flag table, atom table or module.
"""
function gd_aliased_objects(a, b)::Vector{Any}   # allow-any: the objects of a database graph have every type
    ra = _reachable_mutables(a)
    rb = _reachable_mutables(b)
    shared = Any[]   # allow-any: as above
    for x in ra
        x in rb && push!(shared, x)
    end
    return shared
end
