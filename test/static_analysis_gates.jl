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
