# UPSTREAM: swipl-devel src/pl-modul.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-incl.h @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's modules (pl-modul.c): the module table and the modules in
# it — `system`, `user`, a `$`-module, any other a name asks for (MOD1; since V5c the table had only
# `system` and `user`) — looking a module up by name; the super modules (`add_import_module/3`,
# `delete_import_module/2`, `set_module/1`'s `base(M)`) and the module's class; the source module and the
# typein module (`'$set_source_module'/1`, …); `'$module_property'/2`; and what a call of an undefined
# predicate reads — the module's `unknown` flag, inherited from its super modules (since V5b, V5c). The
# module records are src/pl-incl.jl's `module_t`; the table is the database's (`PL_global_data.modules`).
# NOT PORTED (the module system's later steps, D-0149): the context module and `strip_module/3` (MOD2),
# `export/1`, `import/1`, `'$import'/2`, `'$undefined_export'/2`, `'$def_modules'/2` (MOD5a),
# `'$declare_module'/6`, `'$destroy_module'/1` and `acquireModule`/`releaseModule` (MOD5b), and the
# non-deterministic `import_module/2` and `'$current_module'/2` (MOD6, after NF1).

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

# PORT: pl-incl.h ReadingSource
# DIVERGES: a function of the local data. The test is the one the kernel's source-file reads have always
# made (`read_source`'s line above 0 and its file set); upstream's is `source_line_no >= 0`.
"Whether a file is being loaded: `LD->read_source` has a file and a line (pl-incl.h)."
ReadingSource(ld::PL_local_data{T}) where {T} =
    ld.read_source.position.lineno > 0 && ld.read_source.file !== nothing

# PORT: pl-incl.h MODULE_parse
# DIVERGES: the module as an INDEX into the database's table.
"The module `op/3` and `set_module/1` work in: the source module while loading, else the typein module (pl-incl.h)."
MODULE_parse(ld::PL_local_data{T}) where {T} =
    ReadingSource(ld) ? ld.modules_source : ld.modules_typein

# PORT: pl-modul.c isCurrentModule
# DIVERGES: the table is the database's `module_table`: the name's `sym_key` in its name index, where
# upstream's is a hash table by atom. NOT PORTED: the per-thread cache of the 8 most recent lookups,
# flushed by `GD->modules.generation` (new at cbf4e189): it returns what the table returns, so it is
# representation only (D-0149 MQ2); re-open if `M:G` metacalls show the lookup above a few percent.
"The module named `name` (a symbol) in `modules`, or `nothing` (pl-modul.c)."
function isCurrentModule(
    modules::module_table{T}, name::T
)::Union{Nothing, module_t{T}} where {T}
    i = get(modules.names, sym_key(name), 0)
    return i == 0 ? nothing : modules.modules[i]
end

# PORT: pl-modul.c cannotSetSuperModule
# DIVERGES: the local data is an argument; `nothing` (a module being created, with the database's global
# data under construction: no query, no error term) raises a Julia error — upstream's `PL_warning("Could
# not add super-module")` of `_lookupModule`, which cannot be reached.
"Raise `permission_error(add_import, module, M)` ('would create a cycle'); false (pl-modul.c)."
function cannotSetSuperModule(
    ld::Union{Nothing, PL_local_data{T}}, m::module_t{T}, s::module_t{T}
)::Bool where {T}
    ld === nothing && error("Could not add super-module")
    t = PL_new_term_ref(ld)
    PL_put_atom(ld, t, m.atom)
    return PL_error(
        ld, "", 0, "would create a cycle", ERR_PERMISSION, mk_sym(T, :add_import),
        mk_sym(T, :module), t
    )
end

# PORT: pl-modul.c reachableModule
# DIVERGES: the super modules are indices into `modules`.
"Whether `end_` is `here` or reachable through `here`'s super modules (pl-modul.c)."
function reachableModule(
    modules::module_table{T}, here::module_t{T}, end_::module_t{T}
)::Bool where {T}
    here === end_ && return true
    for c in here.supers
        reachableModule(modules, modules[c], end_) && return true
    end
    return false
end

# PORT: pl-modul.c isSuperModule
# DIVERGES: the super modules are indices into `modules`.
"Whether `s` is a super module of `m`, or `m` itself (pl-modul.c)."
function isSuperModule(
    modules::module_table{T}, s::module_t{T}, m::module_t{T}
)::Bool where {T}
    while true                                      # next:
        m === s && return true
        sup = m.supers
        isempty(sup) && return false
        for i in 1:(length(sup) - 1)                # (c->next)
            isSuperModule(modules, s, modules[sup[i]]) && return true
        end
        m = modules[sup[end]]                       # m = c->value; goto next
    end
end

# PORT: pl-modul.c updateLevelModule
# DIVERGES: the super modules are indices into `modules`.
"Set the `level` of `m`, the shortest path to the root of the module tree, from its super modules' (pl-modul.c)."
function updateLevelModule(modules::module_table{T}, m::module_t{T})::Nothing where {T}
    l = -1
    for c in m.supers
        m2 = modules[c]
        if m2.level > l
            l = m2.level
        end
    end
    m.level = l + 1
    return nothing
end

# PORT: pl-modul.c addSuperModule_no_lock
# DIVERGES: the super modules are indices into `modules`; `where_` is a `Char`, `'A'` to prepend and
# anything else to append; the local data is an argument (see `cannotSetSuperModule`).
"Make `s` a super module of `m`, first (`'A'`) or last (`'Z'`); false with the error raised if that would make a cycle (pl-modul.c)."
function addSuperModule_no_lock(
    modules::module_table{T}, ld::Union{Nothing, PL_local_data{T}}, m::module_t{T},
    s::module_t{T}, where_::Char
)::Bool where {T}
    reachableModule(modules, s, m) && return cannotSetSuperModule(ld, m, s)
    for c in m.supers
        c == s.index && return true                 # already a super-module
    end
    if where_ == 'A'
        pushfirst!(m.supers, s.index)
    else
        push!(m.supers, s.index)
    end
    updateLevelModule(modules, m)
    return true
end

# PORT: pl-modul.c addSuperModule
# DIVERGES: no lock (no threads).
"As `addSuperModule_no_lock` (pl-modul.c)."
addSuperModule(
    modules::module_table{T}, ld::Union{Nothing, PL_local_data{T}}, m::module_t{T},
    s::module_t{T}, where_::Char
) where {T} = addSuperModule_no_lock(modules, ld, m, s, where_)

# PORT: pl-modul.c delSuperModule
# DIVERGES: the super modules are indices into `modules`.
"Remove `s` from the super modules of `m`; false if it is none (pl-modul.c)."
function delSuperModule(
    modules::module_table{T}, m::module_t{T}, s::module_t{T}
)::Bool where {T}
    i = findfirst(==(s.index), m.supers)
    i === nothing && return false
    deleteat!(m.supers, i)
    updateLevelModule(modules, m)
    return true
end

# PORT: pl-modul.c clearSupersModule_no_lock
"Remove all super modules of `m` (pl-modul.c)."
function clearSupersModule_no_lock(m::module_t{T})::Nothing where {T}
    empty!(m.supers)
    m.level = 0
    return nothing
end

# PORT: pl-modul.c clearSupersModule
# DIVERGES: no lock (no threads).
"As `clearSupersModule_no_lock` (pl-modul.c)."
clearSupersModule(m::module_t{T}) where {T} = clearSupersModule_no_lock(m)

# PORT: pl-modul.c setSuperModule
# DIVERGES: the super modules are indices into `modules`. A module with ONE super gets the new one in
# its place, with no cycle check, as upstream's does.
"Make `s` the only super module of `m` (pl-modul.c)."
function setSuperModule(
    modules::module_table{T}, ld::Union{Nothing, PL_local_data{T}}, m::module_t{T},
    s::module_t{T}
)::Bool where {T}
    s === m && return cannotSetSuperModule(ld, m, s)
    if length(m.supers) == 1                        # m->supers && !m->supers->next
        if m.supers[1] != s.index
            m.supers[1] = s.index
            m.level = s.level + 1
            return true
        end
    end
    clearSupersModule_no_lock(m)
    return addSuperModule_no_lock(modules, ld, m, s, 'A')
end

# PORT: pl-modul.c _lookupModule as _lookupModule!
# DIVERGES: the table (`modules`) and the database's supervisors (`cd`) are arguments: the database's
# global data is being built when its two modules are created. The new module goes at the end of the
# table's vector, its index its place, and into the name index. NOT PORTED: a module's mutex (no
# threads), `GD->statistics.modules`, `PL_register_atom(name)` (no atom GC). The syntax flags are
# SWI-7's (`GD->options.traditional` is false: no `--traditional`).
"""
    _lookupModule!(modules, cd, name) -> module_t

The module named `name` in `modules`, created and added if there is none (pl-modul.c): `system` is a
system module whose `unknown` flag is `error`; `user`'s super module is `system`; a name starting with
`\$` makes a system-class module under `system`; any other a user-class module under `user`.
"""
function _lookupModule!(
    modules::module_table{T}, cd::PL_code_data, name::T
)::module_t{T} where {T}
    m0 = isCurrentModule(modules, name)             # lookupHTableWP(GD->tables.modules, name)
    m0 === nothing || return m0
    flags = M_CHARESCAPE                            # set(m, M_CHARESCAPE)
    flags |= DBLQ_STRING | BQ_CODES | O_RATIONAL_SYNTAX     # !GD->options.traditional
    class = mk_sym(T, :user)                        # m->class = ATOM_user
    super = nothing
    if sym_key(name) == sym_key(mk_sym(T, :user))
        super = isCurrentModule(modules, mk_sym(T, :system))
        super === nothing && error("_lookupModule: `user` before `system`")
    elseif sym_key(name) == sym_key(mk_sym(T, :system))
        flags |= M_SYSTEM | UInt32(UNKNOWN_ERROR)   # set(m, M_SYSTEM|UNKNOWN_ERROR)
        class = mk_sym(T, :system)
    elseif sym_first_byte(name) == 0x24             # stringAtom(name)[0] == '$'
        flags |= M_SYSTEM
        class = mk_sym(T, :system)
        super = isCurrentModule(modules, mk_sym(T, :system))
        super === nothing && error("_lookupModule: `\$`-module before `system`")
    else
        super = isCurrentModule(modules, mk_sym(T, :user))
        super === nothing && error("_lookupModule: a module before `user`")
    end
    m = module_t{T}(
        sym_key(name), name, length(modules.modules) + 1, class, 0,
        Dict{Tuple{UInt64, Int}, procedure{definition{T}}}(),
        Dict{Tuple{UInt64, Int}, procedure{definition{T}}}(), Tuple{UInt64, Int}[],
        Dict{UInt64, Tuple{T, NTuple{3, UInt8}, NTuple{3, Int16}}}(), Int[],
        0, 0, 0, 0, flags, 0, 0, gen_t(0), cd
    )
    if super !== nothing                            # TBD: Better error-handling
        addSuperModule_no_lock(modules, nothing, m, super, 'A') ||
            error("Could not add super-module")
    end
    push!(modules.modules, m)                       # addNewHTableWP(GD->tables.modules, name, m)
    modules.names[m.name] = m.index
    return m
end

# PORT: pl-modul.c lookupModule
"The module named `name` of the database `gd`, created if there is none (pl-modul.c)."
lookupModule(gd::PL_global_data{T}, name::T) where {T} =
    _lookupModule!(gd.modules, gd.code_data, name)

# PORT: pl-modul.c get_module
# DIVERGES: the module, or `nothing` (with the error raised, or none by that name), where upstream
# writes it through a pointer and returns false.
"The module the atom term reference `t` names, created if `create`; `nothing` if `t` is no atom or there is none (pl-modul.c)."
function get_module(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, create::Bool
)::Union{Nothing, module_t{T}} where {T}
    name = PL_get_atom_ex(ld, t)
    name === nothing && return nothing
    create && return lookupModule(gd, name)
    return isCurrentModule(gd.modules, name)
end

# PORT: pl-modul.c stripModuleName as stripModuleName_cells
# DIVERGES: on a LOCATION (L1e e2; src/pl-prims.jl `_deref_loc`): returns `(ok, (kind, word, position), name)`
# — the plain term dereferenced, as `_deref_loc` gives it, and the innermost module's atom WORD (0: none);
# the 100-step cyclic check is `is_acyclic_cells`.
"Strip `Module:` qualifiers off the term at location `l` while each `Module` is a text atom (pl-modul.c)."
function stripModuleName_cells(
    ld::PL_local_data{T}, l::Int
)::Tuple{Bool, Tuple{UInt8, word, Int}, word} where {T}
    depth = 100
    colon2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(:))), 2)
    k, w, p = _deref_loc(ld, l)                             # deRef(term)
    nm = word(0)
    while k == DU_WORD && _is_gcompound(w) && ld.gstack[valPtr(w)] == colon2   # hasFunctor(*term, FUNCTOR_colon2)
        mk, mw, _ = _deref_loc(ld, valPtr(w) + 1)           # mp = argTermP(*term, 0); deRef(mp)
        (mk == DU_WORD && isAtomW(mw) && isTextAtom(_atom_value(ld, mw))) || break   # isTextAtom(*mp)
        nm = mw
        q = valPtr(w) + 2                                   # term = argTermP(*term, 1); deRef(term)
        k, w, p = _deref_loc(ld, q)
        p = p > 0 ? p : q
        depth -= 1
        if depth == 0 && !is_acyclic_cells(ld, p)
            t = new_term_ref(ld)                            # pushWordAsTermRef(term)
            ld.slots[t + 1] = makeRefG(p)
            PL_error(ld, ERR_TYPE, mk_sym(T, :acyclic_term), t)
            return (false, (k, w, p), nm)
        end
    end
    return (true, (k, w, p), nm)
end

# PORT: pl-modul.c stripModule as stripModule_cells
# DIVERGES: on a location, as `stripModuleName_cells`; returns `(ok, plain, module)`, the module as its
# index into `gd`'s table. A term with no qualifier gets the context module, which is `user`: every
# clause is `user`'s until MOD2 (`contextModule` reads frames' context modules, not ported). A
# qualifier names its module, which `lookupModule` creates (since MOD1). NOT PORTED: `SM_NOCREATE`
# (`flags`): its callers are not ported.
"The plain term under the qualifiers at location `l` (`(kind, word, position)`) and the module it names (pl-modul.c)."
function stripModule_cells(
    gd::PL_global_data{T}, ld::PL_local_data{T}, l::Int
)::Tuple{Bool, Tuple{UInt8, word, Int}, Int} where {T}
    ok, rc, nm = stripModuleName_cells(ld, l)
    m = MODULE_user(gd).index                       # (environment_frame ? contextModule(…) : user)
    if ok && nm != 0
        m = lookupModule(gd, _atom_value(ld, nm)).index
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
# flag here (no `set_prolog_flag(unknown, …)` on a module: F1), so it is `system`'s, `error`, and
# `S_UNDEF`'s warning and fail branches are not reachable, and not ported (src/pl-wam.jl).
"The `unknown` flag in force for module `m` (pl-modul.c): its own or inherited, else `UNKNOWN_ERROR`."
function getUnknownModule(gd::PL_global_data{T}, m::module_t{T})::UInt32 where {T}
    u = inheritUnknown(gd, m)
    if u == 0
        u = UInt32(UNKNOWN_ERROR)
    end
    return u
end

# ── the Prolog connection (pl-modul.c) ──────────────────────────────────────────────────────────

# PORT: pl-modul.c set_module
# DIVERGES: the database and the local data are arguments. `program_space(N)` with N > 0 raises
# `NotPortedError`: the kernel does not keep `m->code_size` up to date (bench H1; D-0149 MQ3), so the
# limit could be neither checked nor enforced — it is never stored silently. `program_space(0)` (no
# limit) is stored, as upstream (`code_limit` 0).
"""
    set_module(gd, ld, m, prop) -> Bool

Set the property `prop` (`base(M)`, `class(C)`, `program_space(N)`) of module `m` (pl-modul.c); false
with the error raised.
"""
function set_module(
    gd::PL_global_data{T}, ld::PL_local_data{T}, m::module_t{T}, prop::term_t
)::Bool where {T}
    na = PL_get_name_arity(ld, prop)
    if na !== nothing && na[2] == 1
        pname = na[1]
        arg = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, prop, arg)

        if sym_key(pname) == sym_key(mk_sym(T, :base))
            mname = PL_get_atom_ex(ld, arg)
            mname === nothing && return false
            return setSuperModule(gd.modules, ld, m, lookupModule(gd, mname))
        elseif sym_key(pname) == sym_key(mk_sym(T, :class))
            class = PL_get_atom_ex(ld, arg)
            class === nothing && return false
            if sym_key(class) == sym_key(mk_sym(T, :user)) ||
                sym_key(class) == sym_key(mk_sym(T, :system)) ||
                sym_key(class) == sym_key(mk_sym(T, :library)) ||
                sym_key(class) == sym_key(mk_sym(T, :test)) ||
                sym_key(class) == sym_key(mk_sym(T, :development))
                m.class = class
                return true
            elseif sym_key(class) == sym_key(mk_sym(T, :temporary))
                if sym_key(m.class) == sym_key(mk_sym(T, :user)) && isempty(m.procedures)
                    m.class = class
                else
                    return PL_error(
                        ld, "", 0,
                        if sym_key(m.class) != sym_key(mk_sym(T, :user))
                            "Not a user module"
                        else
                            "module is not empty"
                        end,
                        ERR_PERMISSION, mk_sym(T, :module_property), mk_sym(T, :class), arg
                    )
                end
                return true
            else
                return PL_error(ld, ERR_DOMAIN, mk_sym(T, :module_class), arg)
            end
        elseif sym_key(pname) == sym_key(mk_sym(T, :program_space))
            limit = PL_get_size_ex(ld, arg)
            limit === nothing && return false
            limit != 0 && throw(
                NotPortedError{T}(
                    m.atom,
                    "set_module(program_space(N)): the module's code accounting", "R2"
                )
            )
            m.code_limit = limit
            return true
        else
            return PL_error(ld, ERR_DOMAIN, mk_sym(T, :module_property), prop)
        end
    else
        return PL_error(ld, ERR_TYPE, mk_sym(T, :module_property), prop)
    end
end

# PORT: pl-modul.c set_module as pl_set_module1_va
# (PRED_IMPL("set_module", 1, set_module, PL_FA_TRANSPARENT))
# DIVERGES: an unqualified `set_module/1` works on `MODULE_parse`, the typein module outside a load: the
# context module (MOD2) is not ported.
"`set_module(:Property)`: set a property of a module (pl-modul.c)."
function pl_set_module1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1 = PL__t0
    prop = PL_new_term_ref(ld)

    ok, loc, mname = stripModuleName_cells(ld, -(A1 + 1))   # stripModuleName(valTermRef(A1), &mname)
    ok || return FFALSE
    _slot_link_loc!(ld, prop + 1, loc)                      # *valTermRef(prop) = linkValNoG(p)

    m = mname != 0 ? lookupModule(gd, _atom_value(ld, mname)) : gd.modules[MODULE_parse(ld)]
    return set_module(gd, ld, m, prop) ? FTRUE : FFALSE
end

# PORT: pl-modul.c add_import_module as pl_add_import_module3_va
# (PRED_IMPL("add_import_module", 3, add_import_module, 0))
"`add_import_module(+Module, +Import, +StartOrEnd)`: add `Import` as a super module of `Module` (pl-modul.c)."
function pl_add_import_module3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    me = get_module(gd, ld, A1, true)
    me === nothing && return FFALSE
    super = get_module(gd, ld, A2, true)
    super === nothing && return FFALSE
    at = PL_get_atom_ex(ld, A3)
    at === nothing && return FFALSE

    start = sym_key(at) == sym_key(mk_sym(T, :start))
    return addSuperModule(gd.modules, ld, me, super, start ? 'A' : 'Z') ? FTRUE : FFALSE
end

# PORT: pl-modul.c delete_import_module as pl_delete_import_module2_va
# (PRED_IMPL("delete_import_module", 2, delete_import_module, 0))
"`delete_import_module(+Module, +Import)`: remove `Import` from the super modules of `Module` (pl-modul.c)."
function pl_delete_import_module2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1

    me = get_module(gd, ld, A1, true)
    me === nothing && return FFALSE
    super = get_module(gd, ld, A2, true)
    super === nothing && return FFALSE

    return delSuperModule(gd.modules, me, super) ? FTRUE : FFALSE
end

# PORT: pl-modul.c current_typein_module as pl_current_typein_module1_va
# (PRED_IMPL("$current_typein_module", 1, current_typein_module, 0))
"`'\$current_typein_module'(-Module)` (pl-modul.c)."
function pl_current_typein_module1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    return PL_unify_atom(ld, PL__t0, gd.modules[ld.modules_typein].atom) ? FTRUE : FFALSE
end

# PORT: pl-modul.c set_typein_module as pl_set_typein_module1_va
# (PRED_IMPL("$set_typein_module", 1, set_typein_module, 0))
"`'\$set_typein_module'(+Module)`: make `Module` the typein module, creating it (pl-modul.c)."
function pl_set_typein_module1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    name = PL_get_atom_ex(ld, PL__t0)
    name === nothing && return FFALSE

    ld.modules_typein = lookupModule(gd, name).index
    return FTRUE
end

# PORT: pl-modul.c current_source_module as pl_current_source_module1_va
# (PRED_IMPL("$current_source_module", 1, current_source_module, 0))
"`'\$current_source_module'(-Module)` (pl-modul.c)."
function pl_current_source_module1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    return PL_unify_atom(ld, PL__t0, gd.modules[ld.modules_source].atom) ? FTRUE : FFALSE
end

# PORT: pl-modul.c set_source_module as pl_set_source_module1_va
# (PRED_IMPL("$set_source_module", 1, set_source_module, 0))
"`'\$set_source_module'(+Module)`: make `Module` the source module, creating it (pl-modul.c)."
function pl_set_source_module1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    name = PL_get_atom_ex(ld, PL__t0)
    name === nothing && return FFALSE

    ld.modules_source = lookupModule(gd, name).index
    return FTRUE
end

# PORT: pl-modul.c unify_export_list
# DIVERGES: `public` (a Julia keyword since 1.11) is `pub`; the public table is walked in the order its procedures were added (`public_order`), where
# upstream walks its hash table (D-0149 item 1).
"Unify the term reference `pub` with the list of `Name/Arity` of module `m`'s public predicates (pl-modul.c)."
function unify_export_list(
    ld::PL_local_data{T}, pub::term_t, m::module_t{T}
)::Bool where {T}
    head = PL_new_term_ref(ld)
    list = PL_copy_term_ref(ld, pub)
    for key in m.public_order
        if !(
            PL_unify_list(ld, list, head, list) &&
            unify_functor(ld, head, m.public_[key].definition, GP_NAMEARITY)
        )
            return false
        end
    end
    return PL_unify_nil(ld, list)
end

# ORIGINAL (MOD1; D-0149 MQ3): the kernel's own count of the bytes a module's clauses take, for
# `'$module_property'(M, program_size(S))` — upstream's `m->code_size`, which the kernel does not keep
# (assert and retract are the hot path, bench H1). A clause is its code words and its header (`sizeofClause`)
# and its clause reference (`SIZEOF_CREF_CLAUSE`), 8 bytes a word, as `compileClause` counts a clause
# (pl-comp.c:2192-2202); the predicates are the module's own and not foreign; a clause that is erased no longer
# counts, as upstream subtracts its size when it is retracted (pl-proc.c:1691), not when it is collected.
"The bytes the clauses of the predicates module `m` defines take (kernel; see above)."
function module_code_size(m::module_t{T})::Int where {T}
    bytes = 0
    for proc in values(m.procedures)
        def = proc.definition
        def.module_ == m.index || continue          # def->module == m
        (def.flags & P_FOREIGN) == 0 || continue
        c = def.impl_clauses.first_clause
        while c !== nothing
            cl = c.clause::Clause{T}
            if (cl.flags & CL_ERASED) == 0          # retract subtracts the clause's size at once
                bytes += 8 * (sizeofClause(length(cl.codes)) + SIZEOF_CREF_CLAUSE)
            end
            c = c.next
        end
    end
    return bytes
end

# PORT: pl-modul.c sizeof_module
# DIVERGES: the kernel's own count, not upstream's byte count (`sizeof` of C structs and hash tables, which
# no Julia value has; machine-dependent in upstream too): the module's clauses (`module_code_size`) and a
# procedure record of 16 bytes (upstream's `sizeof(struct procedure)`) for each of its procedures (D-0149 MQ3).
"The size in bytes of module `m` and what it defines, as the kernel counts it (pl-modul.c)."
function sizeof_module(m::module_t{T})::Int where {T}
    return module_code_size(m) + 16 * length(m.procedures)
end

# PORT: pl-modul.c module_property as pl_module_property2_va
# (PRED_IMPL("$module_property", 2, module_property, 0))
# DIVERGES: `size(_)` and `program_size(_)` answer the kernel's own count (`sizeof_module`,
# `module_code_size`), not upstream's, which depends on the machine (D-0149 MQ3); `exports(L)` lists the
# public table in the order added. `program_space(_)` fails without a limit, as upstream, and the kernel
# stores none (`set_module/1`). `file(_)` is the module's source file's name.
"`'\$module_property'(+Module, ?Property)`: a property of an existing module, deterministically (pl-modul.c)."
function pl_module_property2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    a = PL_new_term_ref(ld)

    m = get_module(gd, ld, A1, false)
    m === nothing && return FFALSE

    na = PL_get_name_arity(ld, A2)
    if na === nothing || na[2] != 1
        return PL_error(ld, ERR_TYPE, mk_sym(T, :module_property), A2) ? FTRUE : FFALSE
    end
    pname = na[1]

    _PL_get_arg(ld, 1, A2, a)

    if sym_key(pname) == sym_key(mk_sym(T, :line_count))
        m.line_no > 0 || return FFALSE
        return PL_unify_integer(ld, a, m.line_no) ? FTRUE : FFALSE
    elseif sym_key(pname) == sym_key(mk_sym(T, :file))
        m.file != 0 || return FFALSE
        return PL_unify_atom(ld, a, gd.files_array[m.file].name) ? FTRUE : FFALSE
    elseif sym_key(pname) == sym_key(mk_sym(T, :exports))
        return unify_export_list(ld, a, m) ? FTRUE : FFALSE
    elseif sym_key(pname) == sym_key(mk_sym(T, :class))
        return PL_unify_atom(ld, a, m.class) ? FTRUE : FFALSE
    elseif sym_key(pname) == sym_key(mk_sym(T, :size))
        return PL_unify_int64(ld, a, sizeof_module(m)) ? FTRUE : FFALSE
    elseif sym_key(pname) == sym_key(mk_sym(T, :program_size))
        return PL_unify_int64(ld, a, module_code_size(m)) ? FTRUE : FFALSE
    elseif sym_key(pname) == sym_key(mk_sym(T, :last_modified_generation))
        return PL_unify_int64(ld, a, Int(m.last_modified)) ? FTRUE : FFALSE
    elseif sym_key(pname) == sym_key(mk_sym(T, :program_space))
        m.code_limit != 0 || return FFALSE
        return PL_unify_int64(ld, a, m.code_limit) ? FTRUE : FFALSE
    else
        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :module_property), A2) ? FTRUE : FFALSE
    end
end

# PORT: pl-modul.c BeginPredDefs as PL_predicates_from_module
# DIVERGES: the entries of the predicates the kernel has ported, in upstream's order (MOD1: the table, the
# supers, the source and typein modules, `'$module_property'/2`); `PRED_DEF` ors in `PL_FA_VARARGS`.
# NOT PORTED: `import_module/2`, `'$current_module'/2` (non-deterministic: MOD6), `strip_module/3` (MOD2),
# `'$def_modules'/2`, `import/1`, `'$import'/2`, `export/1`, `'$undefined_export'/2` (MOD5a),
# `'$declare_module'/6`, `'$destroy_module'/1` (MOD5b).
"pl-modul.c's registration table (`BeginPredDefs(module)`): the ported entries."
const PL_predicates_from_module = (
    PL_extension("add_import_module", 3, pl_add_import_module3_va, PL_FA_VARARGS),
    PL_extension("delete_import_module", 2, pl_delete_import_module2_va, PL_FA_VARARGS),
    PL_extension("set_module", 1, pl_set_module1_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
    PL_extension("\$module_property", 2, pl_module_property2_va, PL_FA_VARARGS),
    PL_extension(
        "\$current_source_module", 1, pl_current_source_module1_va, PL_FA_VARARGS
    ),
    PL_extension("\$set_source_module", 1, pl_set_source_module1_va, PL_FA_VARARGS),
    PL_extension(
        "\$current_typein_module", 1, pl_current_typein_module1_va, PL_FA_VARARGS
    ),
    PL_extension("\$set_typein_module", 1, pl_set_typein_module1_va, PL_FA_VARARGS)
)
