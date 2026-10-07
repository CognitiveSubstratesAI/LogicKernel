# UPSTREAM: swipl-devel src/pl-modul.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's modules (pl-modul.c): the module table and its two modules,
# `system` and `user`, `user`'s super module being `system` (since V5c, as decided since Q-A); looking
# a module up by name; and what a call of an undefined predicate reads — the module's `unknown` flag,
# inherited from its super modules (since V5b, V5c). The module records are src/pl-incl.jl's `module_t`;
# the table is the database's (`PL_global_data.modules`).

# PORT: pl-incl.h UNKNOWN_FAIL
"The `unknown` flag's `fail`: an undefined predicate fails silently (pl-incl.h)."
const UNKNOWN_FAIL = 0x00001000
# PORT: pl-incl.h UNKNOWN_WARNING
"The `unknown` flag's `warning`: print a warning, then fail (pl-incl.h)."
const UNKNOWN_WARNING = 0x00002000
# PORT: pl-incl.h UNKNOWN_ERROR
"The `unknown` flag's `error`, the default: raise `existence_error(procedure, PI)` (pl-incl.h)."
const UNKNOWN_ERROR = 0x00004000
# PORT: pl-incl.h UNKNOWN_MASK
"The `unknown` flag's bits in a module's flags (pl-incl.h)."
const UNKNOWN_MASK = UNKNOWN_ERROR | UNKNOWN_WARNING | UNKNOWN_FAIL

# PORT: pl-modul.c isCurrentModule
# DIVERGES: the table is a vector, searched by name (two entries), where upstream's is a hash table.
"The module named `name` (a symbol) in `modules`, or `nothing` (pl-modul.c)."
function isCurrentModule(
    modules::Vector{module_t{T}}, name::T
)::Union{Nothing, module_t{T}} where {T}
    key = sym_key(name)
    for m in modules
        m.name == key && return m
    end
    return nothing
end

# PORT: pl-modul.c _lookupModule as _lookupModule!
# DIVERGES: the table (`modules`, a vector the module's `index` points into) and the database's
# supervisors (`cd`) are arguments: the database's global data is being built when its two modules
# are created. `addSuperModule_no_lock` is the push of the super's index.
# NOT PORTED: modules other than `system` and `user` — a `$`-module or one `module/2` would create —
# are refused (`NotPortedError`) until R2's loader needs them (user, 2026-10-07); a module's mutex
# (no threads), its syntax flags (`M_CHARESCAPE`, `DBLQ_STRING`, …: no reader until R1), its public
# table and its class.
"""
    _lookupModule!(modules, cd, name) -> module_t

The module named `name` in `modules`, created and added when it is `system` or `user` (pl-modul.c):
`system` is a system module whose `unknown` flag is `error`; `user`'s super module is `system`.
"""
function _lookupModule!(
    modules::Vector{module_t{T}}, cd::PL_code_data, name::T
)::module_t{T} where {T}
    m = isCurrentModule(modules, name)
    m === nothing || return m
    supers = Int[]
    if sym_key(name) == sym_key(mk_sym(T, :user))
        sys = isCurrentModule(modules, mk_sym(T, :system))
        sys === nothing && error("_lookupModule: `user` before `system`")
        push!(supers, sys.index)                    # super = MODULE_system
        flags = UInt32(0)
    elseif sym_key(name) == sym_key(mk_sym(T, :system))
        flags = M_SYSTEM | UInt32(UNKNOWN_ERROR)    # set(m, M_SYSTEM|UNKNOWN_ERROR)
    else
        throw(
            NotPortedError{T}(name, "a module other than system and user (module/2)", "R2")
        )
    end
    m = module_t{T}(
        sym_key(name), name, length(modules) + 1,
        Dict{Tuple{UInt64, Int}, procedure{definition{T}}}(), cd, flags, supers
    )
    push!(modules, m)                               # addNewHTableWP(GD->tables.modules, name, m)
    return m
end

# PORT: pl-modul.c lookupModule
"The module named `name` of the database `gd`, created if it is `system` or `user` (pl-modul.c)."
lookupModule(gd::PL_global_data{T}, name::T) where {T} =
    _lookupModule!(gd.modules, gd.code_data, name)

# PORT: pl-modul.c stripModuleName
# DIVERGES: returns `(ok, plain, name)` — `name` the last module's name, `nothing` when none — where
# upstream returns the plain term (NULL on a cyclic term) and writes the name through `name`.
"""
    stripModuleName(ld, term) -> (ok, plain, name)

Strip the `Module:` qualifiers off `term` while each `Module` is a text atom: the term left and the
innermost module name (pl-modul.c). On a cyclic chain, `type_error(acyclic_term, …)` and `ok` false.
"""
function stripModuleName(
    ld::PL_local_data{T}, term::T
)::Tuple{Bool, T, Union{Nothing, T}} where {T}
    depth = 100
    term = deRef(ld, term)
    nm::Union{Nothing, T} = nothing
    while _hasFunctor(term, mk_sym(T, :(:)), 2)
        mp = deRef(ld, child(term, 2))
        isTextAtom(mp) || break
        nm = mp
        term = deRef(ld, child(term, 3))
        depth -= 1
        if depth == 0 && !is_acyclic(ld, term)
            t = new_term_ref(ld)                    # pushWordAsTermRef(term)
            ld.slots[t + 1] = term
            PL_error(ld, ERR_TYPE, mk_sym(T, :acyclic_term), t)
            return (false, term, nm)
        end
    end
    return (true, term, nm)
end

# PORT: pl-modul.c stripModule
# DIVERGES: returns `(ok, plain, module)`, the module as its index into `gd`'s table. A term with no
# qualifier gets the context module, which is `user`: every clause is `user`'s until R2's `module/2`
# (`contextModule` reads frames' context modules, not ported). `lookupModule` refuses a module other
# than `system` and `user` (`NotPortedError`, until R2).
# NOT PORTED: `SM_NOCREATE` (`flags`): its callers are not ported.
"""
    stripModule(gd, ld, term) -> (ok, plain, module)

The plain term under `term`'s module qualifiers, and the module it names — the context module,
`user`, when none (pl-modul.c).
"""
function stripModule(
    gd::PL_global_data{T}, ld::PL_local_data{T}, term::T
)::Tuple{Bool, T, Int} where {T}
    ok, rc, mname = stripModuleName(ld, term)
    m = MODULE_user(gd).index                       # (environment_frame ? contextModule(…) : user)
    if ok && mname !== nothing
        m = lookupModule(gd, mname).index
    end
    return (ok, rc, m)
end

# PORT: pl-modul.c inheritUnknown
# DIVERGES: the super modules are indices into the database's module table.
"The `unknown` bits of module `m` or, if it sets none, of its first super module that does (pl-modul.c)."
function inheritUnknown(gd::PL_global_data{T}, m::module_t{T})::UInt32 where {T}
    u = m.flags & UInt32(UNKNOWN_MASK)
    u != 0 && return u
    for s in m.supers
        u = getUnknownModule(gd, gd.modules[s])
        u != 0 && return u
    end
    return UInt32(0)
end

# PORT: pl-modul.c getUnknownModule
# DIVERGES: the super modules are found in the database `gd`. Nothing sets a module's `unknown`
# flag here (no `set_prolog_flag(unknown, …)` on a module), so it is `system`'s, `error`, and
# `S_UNDEF`'s warning and fail branches are not reachable, and not ported (src/pl-wam.jl).
"The `unknown` flag in force for module `m` (pl-modul.c): its own or inherited, else `UNKNOWN_ERROR`."
function getUnknownModule(gd::PL_global_data{T}, m::module_t{T})::UInt32 where {T}
    u = inheritUnknown(gd, m)
    if u == 0
        u = UInt32(UNKNOWN_ERROR)
    end
    return u
end
