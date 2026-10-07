# ORIGINAL: helper library for the analysis gates; no swipl-devel counterpart.
# test/static_analysis_gates.jl — the PROACTIVE type-discipline gates, as plain functions.
#
# WHY THESE EXIST (user, 2026-10-02): "we don't want to keep making type-instability kinds of issues
# and fixing them — I want these tools to block and avoid proactively, ahead." Each function below
# returns the list of violations for one rule; test/test_type_discipline.jl and
# test/test_static_analysis.jl turn them into failures, and the suite gates every commit and CI.
# Each is also run on a FIXTURE that plants the defect, so none of them can pass by seeing nothing.

"Every `Any` in the parsed code of the `.jl` files under `dir` — comments and strings are not code."
function any_uses(dir::AbstractString)::Vector{String}
    out = String[]
    for (d, _, fs) in walkdir(dir), f in sort(fs)
        endswith(f, ".jl") || continue
        p = joinpath(d, f)
        _scan_any!(out, Meta.parseall(read(p, String); filename=p), relpath(p, dir), 0)
    end
    return out
end

function _scan_any!(out::Vector{String}, ex, file::String, line::Int)::Int
    if ex === :Any
        push!(out, "$file:$line")
    elseif ex isa QuoteNode
        _scan_any!(out, ex.value, file, line)
    elseif ex isa Expr
        cur = line
        for a in ex.args
            if a isa LineNumberNode
                cur = a.line
            else
                _scan_any!(out, a, file, cur)
            end
        end
    end
    return line
end

# THE UNCHECKED-ACCESS RULE (user, 2026-10-04, on Julia 1.13: `Pkg.test` no longer forces
# `--check-bounds=yes`, so an out-of-range index inside `@inbounds` corrupts memory silently instead
# of failing a test). Every construct that turns bounds checking off or reads/writes raw memory is
# listed, so each one stands on an allowlist with its reason — until a measured performance step
# justifies another.
const UNCHECKED_MACROS = (
    Symbol("@inbounds"), Symbol("@boundscheck"), Symbol("@propagate_inbounds")
)

"""
Every construct in the parsed code of the `.jl` files under `dir` that turns bounds checking off
or touches raw memory: the macros `@inbounds`, `@boundscheck`, `@propagate_inbounds` (bare or
`Base.`-qualified), every call of an `unsafe_*` function, and `ccall`/`@ccall`. As
`"file:line construct"`; comments and strings are not code.
"""
function unchecked_uses(dir::AbstractString)::Vector{String}
    out = String[]
    for (d, _, fs) in walkdir(dir), f in sort(fs)
        endswith(f, ".jl") || continue
        p = joinpath(d, f)
        _scan_unchecked!(
            out, Meta.parseall(read(p, String); filename=p), relpath(p, dir), 0
        )
    end
    return out
end

function _unchecked_name(ex)::Union{Nothing, Symbol}
    ex isa Symbol && return ex
    if ex isa Expr && ex.head === :. && length(ex.args) == 2 && ex.args[2] isa QuoteNode
        v = ex.args[2].value
        return v isa Symbol ? v : nothing
    end
    return nothing
end

function _scan_unchecked!(out::Vector{String}, ex, file::String, line::Int)::Nothing
    ex isa Expr || return nothing
    if ex.head === :macrocall
        m = _unchecked_name(ex.args[1])
        if m !== nothing && (m in UNCHECKED_MACROS || m === Symbol("@ccall"))
            push!(out, "$file:$line $m")
        end
    elseif ex.head === :call || ex.head === :foreigncall
        fn = _unchecked_name(ex.args[1])
        if fn !== nothing && (startswith(String(fn), "unsafe_") || fn === :ccall)
            push!(out, "$file:$line $fn")
        end
    end
    cur = line
    for a in ex.args
        if a isa LineNumberNode
            cur = a.line
        else
            _scan_unchecked!(out, a, file, cur)
        end
    end
    return nothing
end

"A field type the compiler can store unboxed: concrete, or a Union of at most 4 concrete types."
function field_type_ok(T)::Bool
    isconcretetype(T) && return true
    T isa Union || return false
    ts = Base.uniontypes(T)
    return length(ts) <= 4 && all(isconcretetype, ts)
end

"""
Struct fields of `mod`'s own types that are abstractly typed (they box, and every read of them
dispatches at runtime). A parametric type is checked with each parameter set to `placeholder`.
"""
function nonconcrete_fields(mod::Module; placeholder::Type=Int64)::Vector{String}
    out = String[]
    for n in sort!(names(mod; all=true))
        isdefined(mod, n) || continue
        T = getfield(mod, n)
        T isa Type || continue
        U = Base.unwrap_unionall(T)
        (
            U isa DataType && parentmodule(U) === mod && U.name.name === n &&
            isstructtype(U)
        ) || continue
        C = T
        try
            while C isa UnionAll
                C = C{placeholder}
            end
        catch
            push!(
                out,
                "$n: cannot instantiate its parameters with $placeholder to check its fields"
            )
            continue
        end
        for (fname, ft) in zip(fieldnames(C), fieldtypes(C))
            field_type_ok(ft) || push!(out, "$n.$fname::$ft")
        end
    end
    return out
end

"""
Every method `mod` defines — its own functions AND its methods on functions it does not own (Base
`show`, `==`, `hash`, …) — found by walking the global method table, so none can be missed by a
hand-written list. Excluded, because they are not call sites anyone writes: compiler-generated
`#…` methods (closures, keyword sorters), constructors, and type-level methods on functions `mod`
does NOT own (what `@enum` generates: `typemin(::Type{Kind})`, `instances(::Type{Kind})`, …).
⚠️ A type-level method of a function `mod` DOES own — `mk_var(::Type{Term{G}}, key)` — is a real
call site and stays in.
"""
function owned_methods(mod::Module)::Vector{Method}
    ms = Method[]
    _istype(t) = (u=Base.unwrap_unionall(t); u isa DataType && u.name === Type.body.name)
    Base.visit(Core.methodtable) do m
        m isa Method && m.module === mod || return nothing
        # only methods CURRENT in this world: since Julia 1.12 a redefined method stays in the table
        # with its world range closed (Revise redefines hundreds in a warm daemon — measured
        # 2026-10-04: 445 replaced beside 482 current, each "NOT CHECKED" by mistake)
        _current_method(m) || return nothing
        startswith(String(m.name), "#") && return nothing
        m.name === :kwcall && return nothing
        sig = Base.unwrap_unionall(m.sig)
        ft = sig.parameters[1]
        _istype(ft) && return nothing                                         # a constructor
        f_owned =
            ft isa DataType && isdefined(ft, :instance) && parentmodule(ft.instance) === mod
        !f_owned && length(sig.parameters) >= 2 && _istype(sig.parameters[2]) &&
            return nothing
        push!(ms, m)
    end
    return sort!(ms; by=m -> (String(m.name), string(m.sig)))
end

"True when `m` is the method its own signature dispatches to now — not one a redefinition replaced."
_current_method(m::Method)::Bool =
    try
        which(m.sig) === m
    catch
        true                                    # an ambiguous signature: keep it, to be checked
    end

"""
    manifest_uncovered(mod, manifest, exempt) -> (; uncovered, stale_exempt)

`manifest` holds `(f, argtypes, noalloc)` entries, `exempt` holds `(f, argtypes) => reason` pairs.
`uncovered`: methods of `mod` that no entry (or exemption) dispatches to. `stale_exempt`: exemptions
naming no method of `mod`, or with an empty reason — a stale entry would pre-approve whatever later
lands there.
"""
function manifest_uncovered(mod::Module, manifest, exempt)
    covered = Set{Method}()
    for (f, tt, _) in manifest
        push!(covered, which(f, tt))
    end
    stale = String[]
    for ((f, tt), why) in exempt
        m = try
            which(f, tt)
        catch
            nothing
        end
        if m === nothing || m.module !== mod || isempty(strip(why))
            push!(
                stale,
                "$f$(tt): $(m === nothing ? "no such method" : isempty(strip(why)) ? "no reason" : "not a method of $mod")"
            )
        else
            push!(covered, m)
        end
    end
    uncovered = [
        "$(m.name) $(m.sig)  ($(m.file):$(m.line))" for
        m in owned_methods(mod) if !(m in covered)
    ]
    return (; uncovered, stale_exempt=stale)
end

# ── the term-type rule (R1c) ─────────────────────────────────────────────────────────────────────
# A method that BUILDS terms on its type parameter `T` (`mk_sym(T, …)`, `T[…]`, …) must bind `T`
# from something that names the term type EXACTLY: `Type{T}`, or an invariant parametric type
# (`PL_local_data{T}`, `read_data{T}`, `Vector{T}`, …). A `T` bound only by a term argument
# (`x::T`), a `Union` or a covariant `Tuple` is the argument's own concrete type — under the
# alternative term types a SUBTYPE (`AltSym`), which cannot build. It broke AltTerm three times
# (the last in R1b: `atomToOperatorType(atom::T)`); a prose rule did not hold, so this is a gate.

"The calls that build a term on their first argument, the term type."
const TERM_BUILDERS = (
    :mk_sym, :mk_expr, :mk_gnd, :mk_nil, :mk_var, :mk_reserved_symbol, :put_number,
    :_atom_from_text, :_text_atom, :_text_term
)

"`file:line name` of every method in `dir` that builds terms on a `T` bound only by term arguments."
function term_type_from_term_arg_uses(dir::AbstractString)::Vector{String}
    out = String[]
    for (d, _, fs) in walkdir(dir), f in sort(fs)
        endswith(f, ".jl") || continue
        p = joinpath(d, f)
        _scan_term_type!(
            out, Meta.parseall(read(p, String); filename=p), relpath(p, dir), 0
        )
    end
    return out
end

# The where-variables and the argument types of a signature, and its name; `nothing` if not one.
function _tt_signature(sig)
    wh = Symbol[]
    while sig isa Expr && sig.head === :where
        for v in sig.args[2:end]
            v isa Symbol && push!(wh, v)
            v isa Expr && v.head === :(<:) && v.args[1] isa Symbol && push!(wh, v.args[1])
        end
        sig = sig.args[1]
    end
    if sig isa Expr && sig.head === :(::) && length(sig.args) == 2
        # the short form `f(…)::R where {T} = …` parses as `f(…)::(R where {T})`
        rt = sig.args[2]
        while rt isa Expr && rt.head === :where
            for v in rt.args[2:end]
                v isa Symbol && push!(wh, v)
                v isa Expr && v.head === :(<:) && v.args[1] isa Symbol &&
                    push!(wh, v.args[1])
            end
            rt = rt.args[1]
        end
        sig = sig.args[1]
    end
    (sig isa Expr && sig.head === :call) || return nothing
    types = Any[]
    for a in sig.args[2:end]
        a isa Expr && a.head === :parameters && continue
        a isa Expr && a.head === :kw && (a = a.args[1])
        a isa Expr && a.head === :(::) && push!(types, a.args[end])
    end
    return (wh, types, sig.args[1])
end

_tt_mentions(ex, T::Symbol)::Bool =
    ex === T || (ex isa Expr && any(a -> _tt_mentions(a, T), ex.args))

# Does the type expression `ty` bind `T` exactly: `Type{T}`, or an invariant parametric type?
function _tt_binds_exactly(ty, T::Symbol)::Bool
    (ty isa Expr && ty.head === :curly) || return false
    head = ty.args[1]
    if head === :Union || head === :Tuple || head === :NTuple || head === :Vararg
        return any(p -> _tt_binds_exactly(p, T), ty.args[2:end])
    end
    return any(p -> _tt_mentions(p, T), ty.args[2:end])
end

# Does `body` build a term on `T`?
function _tt_builds_on(ex, T::Symbol)::Bool
    ex isa Expr || return false
    if ex.head === :call && length(ex.args) >= 2 && ex.args[2] === T
        f = _unchecked_name(ex.args[1])
        f !== nothing && f in TERM_BUILDERS && return true
    end
    ex.head === :ref && !isempty(ex.args) && ex.args[1] === T && return true     # T[…]
    return any(a -> _tt_builds_on(a, T), ex.args)
end

function _scan_term_type!(out::Vector{String}, ex, file::String, line::Int)::Nothing
    ex isa Expr || return nothing
    if (ex.head === :function || ex.head === :(=)) && length(ex.args) == 2
        s = _tt_signature(ex.args[1])
        if s !== nothing
            wh, types, name = s
            for T in wh
                bytermsonly =
                    any(ty -> _tt_mentions(ty, T), types) &&
                    !any(ty -> _tt_binds_exactly(ty, T), types)
                bytermsonly && _tt_builds_on(ex.args[2], T) &&
                    push!(out, "$file:$line $name")
            end
        end
    end
    cur = line
    for a in ex.args
        if a isa LineNumberNode
            cur = a.line
        else
            _scan_term_type!(out, a, file, cur)
        end
    end
    return nothing
end
