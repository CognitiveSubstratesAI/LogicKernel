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
# Since MOD2 the context module of an unqualified term (`stripModule_cells`; the frames' context modules are
# src/pl-wam.jl `contextModule`), `strip_module/3` and `context_module/1`.
# Since MOD5a the public table and the imports: `export/1`, `import/1`, `'$import'/2`, `'$undefined_export'/2`
# and `'$def_modules'/2`.
# Since MOD5b declaring a module (`declareModule`, `'$declare_module'/6`) and destroying a temporary one
# (`'$destroy_module'/1`, `acquireModule`/`releaseModule`).
# LATER STEPS (the module system, D-0149): the non-deterministic `import_module/2` and
# `'$current_module'/2` (MOD6, after NF1).

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
# DIVERGES: a function of the local data. LB2: the test is upstream's, `source_line_no >= 0` (pl-incl.h:2734)
# — it was `> 0`, which differs only at line 0, the line `'$set_source_location'(File, 0)` (init.pl:1933) sets
# and source_location/2 must then answer; every read sets a line of at least 1, or -1 on a stream without positions.
"Whether a file is being loaded: `LD->read_source` has a file and a line (pl-incl.h)."
ReadingSource(ld::PL_local_data{T}) where {T} =
    ld.read_source.position.lineno >= 0 && ld.read_source.file !== nothing

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
# index into `gd`'s table. A term with no qualifier gets the context module of the environment frame,
# or `user` outside one (since MOD2; pl-modul.c:834-835: `*module = (environment_frame ?
# contextModule(environment_frame) : MODULE_user);`). A qualifier names its module, which `lookupModule`
# creates (since MOD1). NOT PORTED: `SM_NOCREATE` (`flags`): its callers are not ported.
"The plain term under the qualifiers at location `l` (`(kind, word, position)`) and the module it names (pl-modul.c)."
function stripModule_cells(
    gd::PL_global_data{T}, ld::PL_local_data{T}, l::Int
)::Tuple{Bool, Tuple{UInt8, word, Int}, Int} where {T}
    ok, rc, nm = stripModuleName_cells(ld, l)
    m = MODULE_user(gd).index
    if ok
        if nm != 0                                  # if ( mname )
            m = lookupModule(gd, _atom_value(ld, nm)).index     # *module = lookupModule(mname)
        elseif ld.environment_frame != 0            # environment_frame ? contextModule(…) : MODULE_user
            m = contextModule(gd, ld, ld.environment_frame)
        end
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
# (an unqualified `set_module/1` works on `MODULE_parse`, as upstream's: pl-modul.c:739)
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

# ── export and import (pl-modul.c; MOD5a) ──────────────────────────────────────────────────────

# PORT: pl-modul.c isPublicModule
# DIVERGES: the database is not an argument (`module_t` holds its table); the key is the functor's parts.
"Whether `proc`'s predicate is in the public table of module `m` (pl-modul.c)."
isPublicModule(m::module_t, proc::Procedure)::Bool =
    haskey(m.public_, (proc.definition.functor_name, proc.definition.arity))

# PORT: pl-modul.c exportProcedure
# DIVERGES: `public_order` (no upstream field) gets the key when it is new; an existing key keeps its place, as
# `updateHTableWP` updates in place.
"Put `proc` in the public table of module `m` (pl-modul.c)."
function exportProcedure(m::module_t{T}, proc::Procedure{T})::Bool where {T}
    key = (proc.definition.functor_name, proc.definition.arity)
    haskey(m.public_, key) || push!(m.public_order, key)
    m.public_[key] = proc
    return true
end

# PORT: pl-modul.c export_pi1
# DIVERGES: the module is an index (0: the context module); the database `gd` is an argument. `ReadingSource` and
# the source file are the local data's (`ld.read_source`).
"Export the `Name/Arity` (or `M:Name/Arity`) in `pi` from module `m` (pl-modul.c)."
function export_pi1(
    gd::PL_global_data{T}, ld::PL_local_data{T}, pi::term_t, m::Int
)::Bool where {T}
    name, arity, mi = get_functor(gd, ld, pi, m, 0, GF_PROCEDURE | GF_NAMEARITY)
    arity < 0 && return false
    sp = isStaticSystemProcedure(gd, ld, sym_key(name), arity)
    if sp !== nothing && (sp.definition.flags & P_ISO) != 0     # an ISO system predicate is skipped
        return true
    end
    mod = gd.modules[mi]
    proc = lookupProcedure(name, arity, mod)
    if ReadingSource(ld)
        sf = lookupSourceFile(gd, ld.read_source.file::T, true)::SourceFile{T}
        rc = exportProcedureSource(sf, mod, proc)
        releaseSourceFile(sf)
        return rc
    else
        return exportProcedure(mod, proc)
    end
end

# PORT: pl-modul.c export_pi
"Export the comma list of predicate indicators in `pi` from module `m` (pl-modul.c)."
function export_pi(
    gd::PL_global_data{T}, ld::PL_local_data{T}, pi::term_t, m::Int, depth::Int
)::Bool where {T}
    ok, m = PL_strip_module(gd, ld, pi, m, pi)
    ok || return false
    while PL_is_functor(ld, pi, mk_sym(T, Symbol(",")), 2)
        a1 = PL_new_term_ref(ld)
        depth += 1
        if depth == 100 && !is_acyclic_cells(ld, -(pi + 1))
            return PL_error(ld, ERR_TYPE, mk_sym(T, :acyclic_term), pi)
        end
        _PL_get_arg(ld, 1, pi, a1)
        export_pi(gd, ld, a1, m, depth) || return false
        PL_reset_term_refs(ld, a1)
        _PL_get_arg(ld, 2, pi, pi)
    end
    return export_pi1(gd, ld, pi, m)
end

# PORT: pl-modul.c export as pl_export1_va
# (PRED_IMPL("export", 1, export, PL_FA_TRANSPARENT))
"`export(+PIs)`: export the predicate indicators from the context module (pl-modul.c)."
function pl_export1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    return export_pi(gd, ld, PL__t0, 0, 0) ? FTRUE : FFALSE     # Module module = NULL
end

# PORT: pl-modul.c undefined_export as pl_undefined_export2_va
# (PRED_IMPL("$undefined_export", 2, undefined_export, 0))
# DIVERGES: the public table is walked in the order its keys were added (`public_order`), where upstream's follows
# its hash table (D-0149 item 1).
"`'\$undefined_export'(+Module, -UndefExport)`: the exported predicates of `Module` that nothing defines (pl-modul.c)."
function pl_undefined_export2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    mname = PL_get_atom_ex(ld, A1)
    mname === nothing && return FFALSE
    module_ = isCurrentModule(gd.modules, mname)
    if module_ === nothing
        return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :module), A1) ? FTRUE : FFALSE
    end
    tail = PL_copy_term_ref(ld, A2)
    head = PL_new_term_ref(ld)
    for key in module_.public_order
        proc = module_.public_[key]
        def = proc.definition
        if !isDefinedProcedure(gd, proc) &&             # not defined
            def.module_ == module_.index &&             # not imported
            autoImport(gd, def.name, def.arity, module_) === nothing
            if !(
                PL_unify_list(ld, tail, head, tail) &&
                unify_definition(
                    gd, ld, MODULE_user(gd), head, proc.definition, 0,
                    GP_QUALIFY | GP_NAMEARITY
                )
            )
                return FFALSE
            end
        end
    end
    return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
end

# PORT: pl-modul.c fixExportModule
# DIVERGES: no lock (no threads); a definition nothing shares any more is left to the garbage collector
# (`lingerDefinition`).
"Make every procedure of module `m` that has the definition `old` share `new` (pl-modul.c)."
function fixExportModule(
    m::module_t{T}, old::Definition{T}, new::Definition{T}
)::Nothing where {T}
    for proc in values(m.procedures)
        if proc.definition === old
            shareDefinition(new)
            proc.definition = new
            unshareDefinition(old)
        end
    end
    return nothing
end

# PORT: pl-modul.c fixExport
# DIVERGES: the database `gd` is an argument; a destroyed module (`M_DESTROYED`: its name left the table) is not
# in upstream's table, so it is skipped.
"Patch the definition `old` to `new` in every module (pl-modul.c)."
function fixExport(
    gd::PL_global_data{T}, old::Definition{T}, new::Definition{T}
)::Nothing where {T}
    for m in gd.modules
        (m.flags & M_DESTROYED) != 0 && continue
        fixExportModule(m, old, new)
    end
    return nothing
end

# PORT: pl-modul.c atomToImportStrength
"The procedure flag of the import strength `a`: `weak` is `PROC_WEAK`, `strong` 0, else -1 (pl-modul.c)."
function atomToImportStrength(::Type{T}, a)::Int where {T}
    sym_key(a) == sym_key(mk_sym(T, :weak)) && return Int(PROC_WEAK)
    sym_key(a) == sym_key(mk_sym(T, :strong)) && return 0
    return -1
end

# PORT: pl-modul.c import as import_
# DIVERGES: the database `gd` is an argument; modules are indices (`strength` 0: upstream's NULL). The definition
# nothing shares any more is left to the garbage collector (`lingerDefinition`). `sysError` ("Unknown problem
# importing") is an `error`. `retry` is a loop, as `goto retry` (a lost race for the table entry cannot happen
# without threads, so the loop runs once).
"Import the predicate `pred` names into the context module with strength `strength` (0: strong) (pl-modul.c)."
function import_(
    gd::PL_global_data{T}, ld::PL_local_data{T}, pred::term_t, strength::term_t
)::Bool where {T}
    desti = contextModule(gd, ld, ld.environment_frame)     # Module destination = contextModule(environment_frame)
    destination = gd.modules[desti]
    name, arity, srci = get_functor(gd, ld, pred, 0, 0, GF_PROCEDURE)
    arity < 0 && return false
    source = gd.modules[srci]
    pflags = UInt32(0)
    if strength != 0
        a = PL_get_atom_ex(ld, strength)
        a === nothing && return false
        pf = atomToImportStrength(T, a)
        pf < 0 && return PL_error(ld, ERR_DOMAIN, mk_sym(T, :import_type), strength)
        pflags = UInt32(pf)
    end

    proc = lookupProcedure(name, arity, source)

    if !isDefinedProcedure(gd, proc)
        autoImport(gd, name, arity, gd.modules[proc.definition.module_])
    end

    old = isCurrentProcedure(
        proc.definition.functor_name, proc.definition.arity, destination
    )
    if old !== nothing
        old.definition === proc.definition && return true       # already done this!

        if !isDefinedProcedure(gd, old)
            odef = old.definition
            fixup = false
            old.definition = proc.definition
            shareDefinition(proc.definition)
            if unshareDefinition(odef) > 0
                fixup = true                                    # delay to avoid a deadlock
            end                                                 # else lingerDefinition(odef)
            old.flags |= pflags | PROC_IMPORTED                 # set(old, pflags|PROC_IMPORTED)
            fixup && fixExport(gd, odef, proc.definition)
            return true
        end

        if old.definition.module_ == desti
            if (pflags & PROC_WEAK) != 0
                if truePrologFlag(ld, PLFLAG_WARN_OVERRIDE_IMPLICIT_IMPORT)
                    pi = PL_new_term_ref(ld)
                    unify_definition(
                        gd, ld, MODULE_user(gd), pi, proc.definition, 0, GP_NAMEARITY
                    ) || return false                           # PL_unify_predicate(pi, proc, GP_NAMEARITY)
                    printMessage(
                        ld, :warning,
                        _message_term(
                            ld, :ignored_weak_import, _err_atom(ld, destination.atom), pi
                        )
                    ) || return false
                end
                return true
            else
                return PL_error(
                    ld, "import", 1, "name clash", ERR_IMPORT_PROC, proc, destination.atom,
                    nothing
                )
            end
        end

        if old.definition.module_ != srci                       # already imported
            return PL_error(
                ld, "import", 1, "", ERR_IMPORT_PROC, proc, destination.atom,
                gd.modules[old.definition.module_].atom
            )
        end

        error("Unknown problem importing $(name)/$(arity) into module $(destination.atom)")    # sysError
    end

    if !isPublicModule(source, proc)
        pi = PL_new_term_ref(ld)
        unify_definition(
            gd, ld, MODULE_user(gd), pi, proc.definition, 0, GP_NAMEARITY
        ) || return false
        printMessage(
            ld, :warning,
            _message_term(ld, :import_private, _err_atom(ld, destination.atom), pi)
        ) || return false
    end

    nproc = Procedure{T}(proc.definition, pflags, UInt32(0))    # nproc->flags = pflags; source_no = 0
    shareDefinition(proc.definition)
    destination.procedures[(proc.definition.functor_name, proc.definition.arity)] = nproc
    return true
end

# PORT: pl-modul.c import as pl_import1_va
# (PRED_IMPL("import", 1, import, PL_FA_TRANSPARENT))
"`import(+PI)`: import the predicate into the context module (pl-modul.c)."
function pl_import1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return import_(_query_gd(ld), ld, PL__t0, 0) ? FTRUE : FFALSE
end

# PORT: pl-modul.c import as pl_import2_va
# (PRED_IMPL("\$import", 2, import, PL_FA_TRANSPARENT))
"`'\$import'(+PI, +Strength)`: import with strength `weak` or `strong` (pl-modul.c)."
function pl_import2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return import_(_query_gd(ld), ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-modul.c MAX_TARGETS
"The most predicate indicators `'\$def_modules'/2` takes (pl-modul.c)."
const MAX_TARGETS = 10

# PORT: pl-modul.c find_modules_with_defs
# DIVERGES: the targets are `(name key, arity, PI term)` tuples (upstream's `defm_target`: `functor`, `pi`); `tmp` is the first
# of the three term references; `mhead` and `plist` hold the list cell and the fresh variable `plist`, which lives in a
# global cell here (`PL_put_variable`), so `PL_cons_functor` with it as an argument is upstream's `PL_unify_term(PL_TERM, plist)`
# (a reference to the variable's cell, linkValG). A loop of default modules is a kernel error, as `sysError`.
"Add to `mlist` the pair `Module-PIs` of each module among `m` and its default modules that defines one of `targets` (pl-modul.c)."
function find_modules_with_defs(
    gd::PL_global_data{T}, ld::PL_local_data{T}, m::module_t{T},
    targets::Vector{Tuple{UInt64, Int, term_t}}, tmp::term_t, mlist::term_t, l::Int
)::Bool where {T}
    found = false
    mhead = tmp + 0
    plist = tmp + 1
    phead = tmp + 2

    l < 0 && error("OOPS loop in default modules???")

    for (key, arity, pi) in targets
        proc = isCurrentProcedure(key, arity, m)
        if proc !== nothing && _impl_any_defined(proc.definition)
            if !found
                found = true
                PL_put_variable(ld, plist)
                PL_unify_list(ld, mlist, mhead, mlist) || return false
                pair = _message_term(ld, :-, _err_atom(ld, m.atom), plist)
                PL_unify(ld, mhead, pair) || return false   # PL_unify_term(mhead, PL_FUNCTOR, FUNCTOR_minus2, …)
            end

            PL_unify_list(ld, plist, phead, plist) || return false
            PL_unify(ld, phead, pi) || return false
        end
    end
    found && !PL_unify_nil(ld, plist) && return false

    for c in m.supers
        s = gd.modules[c]
        find_modules_with_defs(gd, ld, s, targets, tmp, mlist, l - 1) || return false
    end

    return true
end

# PORT: pl-modul.c def_modules as pl_def_modules2_va
# (PRED_IMPL("\$def_modules", 2, def_modules, PL_FA_TRANSPARENT))
# DIVERGES: the starting module is `gd.modules[ld.modules_source]` (`LD->modules.source`); the qualifier's atom is resolved with
# `isCurrentModule` (a name of no module: `system` if it starts with `$`, else `user`, as upstream); the targets are a vector of
# at most `MAX_TARGETS`, the term `pi` of each is the list element's own reference (`PL_copy_term_ref`).
"`'\$def_modules'(:List, -Pairs)`: the `Module-PIs` pairs of the modules defining some predicate of `List` (pl-modul.c)."
function pl_def_modules2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    m = gd.modules[ld.modules_source]
    targets = Tuple{UInt64, Int, term_t}[]
    ttail = PL_new_term_ref(ld)
    tmp = PL_new_term_refs(ld, 3)
    tail = PL_copy_term_ref(ld, A2)
    thead = tmp + 0

    ok, loc, mname = stripModuleName_cells(ld, -(A1 + 1))   # stripModuleName(valTermRef(A1), &mname)
    ok || return FFALSE
    _slot_link_loc!(ld, ttail + 1, loc)                     # *valTermRef(ttail) = linkValNoG(mp)

    if mname != 0
        nm = _atom_value(ld, mname)
        m2 = isCurrentModule(gd.modules, nm)
        if m2 !== nothing
            m = m2
        elseif sym_first_byte(nm) == 0x24                   # stringAtom(mname)[0] == '$'
            m = MODULE_system(gd)
        else
            m = MODULE_user(gd)
        end
    end

    while PL_get_list_ex(ld, ttail, thead, ttail)
        if length(targets) >= MAX_TARGETS
            PL_resource_error(ld, "target_predicates")
            return FFALSE
        end
        name, arity, _ = get_functor(gd, ld, thead, 0, 0, GF_PROCEDURE | GP_NOT_QUALIFIED)
        arity < 0 && return FFALSE
        push!(targets, (sym_key(name), arity, PL_copy_term_ref(ld, thead)))
    end
    PL_get_nil_ex(ld, ttail) || return FFALSE

    find_modules_with_defs(gd, ld, m, targets, tmp, tail, 100) || return FFALSE

    return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
end

# PORT: pl-modul.c acquireModule
# DIVERGES: the database `gd` is an argument; no lock (no threads).
"The module named `name`, or `nothing`; a temporary module gets a reference (pl-modul.c)."
function acquireModule(
    gd::PL_global_data{T}, name::T
)::Union{Nothing, module_t{T}} where {T}
    m = isCurrentModule(gd.modules, name)
    if m !== nothing && sym_key(m.class) == sym_key(mk_sym(T, :temporary))
        m.references += 1
    end
    return m
end

# PORT: pl-modul.c acquireModulePtr
"Count a reference to `m` when it is a temporary module (pl-modul.c)."
function acquireModulePtr(m::module_t{T})::Nothing where {T}
    if sym_key(m.class) == sym_key(mk_sym(T, :temporary))
        m.references += 1
    end
    return nothing
end

# PORT: pl-modul.c unallocModule
# DIVERGES: the memory (the tables, the super list, the lingering definitions) is Julia's garbage collector's: a destroyed module
# keeps its record, its procedures and its index, as definitions hold the index (D-0149 M2, H3); what is done is the one
# visible effect, the source and typein modules go back to `user`.
"Free a destroyed module: the source and typein modules that are `m` become `user` (pl-modul.c)."
function unallocModule(
    gd::PL_global_data{T}, ld::PL_local_data{T}, m::module_t{T}
)::Nothing where {T}
    user = MODULE_user(gd)
    ld.modules_source == m.index && (ld.modules_source = user.index)
    ld.modules_typein == m.index && (ld.modules_typein = user.index)
    return nothing
end

# PORT: pl-modul.c markSourceFilesProcedure
# DIVERGES: the bit vector is a `BitVector` indexed from 0 (element `i + 1`).
"Mark the source files `proc` was defined in: its one file, or all when it has several (pl-modul.c)."
function markSourceFilesProcedure(proc::Procedure{T}, v::BitVector)::Nothing where {T}
    if (proc.flags & PROC_MULTISOURCE) == 0
        v[Int(proc.source_no) + 1] = true
    else
        fill!(v, true)
    end
    return nothing
end

# PORT: pl-modul.c unlinkSourceFilesModule
"Remove the source-file administration's links to `m`, and release the file `m` was declared in (pl-modul.c)."
function unlinkSourceFilesModule(gd::PL_global_data{T}, m::module_t{T})::Nothing where {T}
    high = highSourceFileIndex(gd)
    vec = falses(high + 1)
    for proc in values(m.procedures)
        markSourceFilesProcedure(proc, vec)
    end
    for i in 1:high
        if vec[i + 1]
            sf = indexToSourceFile(gd, i)
            sf === nothing || unlinkSourceFileModule(sf, m)
        end
    end
    if m.file != 0
        sf = gd.files_array[m.file]
        m.file = 0
        releaseSourceFile(sf)
    end
    return nothing
end

# PORT: pl-modul.c releaseModule_unlocked
# DIVERGES: `GD->statistics.modules` and `PL_unregister_atom(name)` (no statistics, no atom GC) and the wait area (no threads) are not kept;
# the local data is an argument (`unallocModule` resets its source and typein modules).
"Drop a reference to the temporary module `m`; the last one of a destroyed module frees it (pl-modul.c)."
function releaseModule_unlocked(
    gd::PL_global_data{T}, ld::PL_local_data{T}, m::module_t{T}
)::Nothing where {T}
    m.references -= 1
    if m.references == 0 && (m.flags & M_DESTROYED) != 0
        unlinkSourceFilesModule(gd, m)
        unallocModule(gd, ld, m)
    end
    return nothing
end

# PORT: pl-modul.c releaseModule
"Drop a reference to `m` when it is a temporary module (pl-modul.c)."
function releaseModule(
    gd::PL_global_data{T}, ld::PL_local_data{T}, m::module_t{T}
)::Nothing where {T}
    if sym_key(m.class) == sym_key(mk_sym(T, :temporary))
        releaseModule_unlocked(gd, ld, m)
    end
    return nothing
end

# PORT: pl-modul.c destroyModule
# DIVERGES: the invariant check that prints "Module %s: class %s; refs %d" (a debugging line on stderr, when a temporary module is
# destroyed with no reference) and the bump of `GD->modules.generation` (the per-thread lookup cache is not ported, MOD1 Q2) are not
# kept.
"Take the name of `m` out of the module table and mark it destroyed; free it at its last reference (pl-modul.c)."
function destroyModule(
    gd::PL_global_data{T}, ld::PL_local_data{T}, m::module_t{T}
)::Bool where {T}
    if get(gd.modules.names, m.name, 0) == m.index       # deleteHTableWP(GD->tables.modules, m->name) == m
        delete!(gd.modules.names, m.name)
        m.flags |= M_DESTROYED
    end
    releaseModule(gd, ld, m)
    return true
end

# PORT: pl-modul.c destroy_module as pl_destroy_module1_va
# (PRED_IMPL("\$destroy_module", 1, destroy_module, 0))
"`'\$destroy_module'(+Module)`: destroy a temporary module; no module of that name succeeds (pl-modul.c)."
function pl_destroy_module1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    name = PL_get_atom_ex(ld, PL__t0)
    name === nothing && return FFALSE

    m = acquireModule(gd, name)
    if m !== nothing
        if sym_key(m.class) == sym_key(mk_sym(T, :temporary))
            return destroyModule(gd, ld, m) ? FTRUE : FFALSE
        else
            releaseModule(gd, ld, m)
            return if PL_error(
                ld, "", 0, "module is not temporary", ERR_PERMISSION, mk_sym(T, :destroy),
                mk_sym(T, :module), PL__t0
            )
                FTRUE
            else
                FFALSE
            end
        end
    end

    return FTRUE                                        # non-existing
end

# Ported from pl-util.c text_summary and atom_summary (a file this module does not mirror, so no PORT marker).
# Differs: a Julia string (pl-util.c returns a buffer of UTF-8); the text is `s`'s characters.
"`s` itself when it is ASCII and shorter than `maxlen`; else its first characters, `...` and its last three (pl-util.c)."
function _text_summary(s::AbstractString, maxlen::Int)::String
    chars = collect(s)
    n = length(chars)
    if n < maxlen && all(c -> UInt32(c) < 0x80, chars)
        return String(chars)
    end
    io = IOBuffer()
    i = 0
    while i < n
        print(io, chars[i + 1])
        if i == maxlen - 6
            print(io, "...")
            i = n - 4
            maxlen = typemax(Int)                       # make sure not to trap again
        end
        i += 1
    end
    return String(take!(io))
end

# Ported from pl-proc.c abolishProcedure (a file this module does not mirror, so no PORT marker).
# Differs (MOD5b; Q7, F5; audit): only the imported-link branch (pl-proc.c:1517-1530) is the kernel's; the rest (pl-proc.c:1531-1550:
# `resetProcedure`, a foreign predicate made normal, `removeClausesPredicate`, `setDynamicDefinition_unlocked`) is not in the kernel. A procedure of the module's own whose abolish would
# change nothing (no clauses, no flags) needs no work; any other own procedure is refused by name (`NotPortedError`). An IMPORTED link is
# removed as upstream does: a fresh definition for the module (upstream's `memset` leaves `shared` 0), the old one unshared; no statistics
# or code-size accounting, no `lingerDefinition` (Julia's garbage collector), and `resetProcedure` of the fresh definition only sets the
# debugger's `TRACE_ME` (not ported, as in `lookupProcedure`).
"Abolish `proc` of module `m` (pl-proc.c): an imported link is removed; an own procedure with nothing to abolish is left; else a `NotPortedError`."
function _abolishProcedure_pristine(
    gd::PL_global_data{T}, m::module_t{T}, proc::Procedure{T}
)::Bool where {T}
    def = proc.definition
    if def.module_ != m.index                           # imported predicate; remove link
        clauses = ClauseList{T}()
        if def.arity > 0
            clauses.args = [arg_info() for _ in 1:(def.arity)]
        else
            clauses.args = nothing
        end
        cd = m.code_data
        ndef = Definition{T}(
            def.functor_name, def.arity, clauses, UInt64(0), def.name, cd.virgin,
            ClauseRef{T}[], cd, 0, m.index, 0   # memset: shared 0
        )
        proc.definition = ndef
        unshareDefinition(def)
        return true
    end
    if hasClausesDefinition(gd, def) === nothing && def.flags == 0
        return true
    end
    throw(
        NotPortedError{T}(
            def.name, "redeclaring a module that has predicates (abolishProcedure)", "R2"
        )
    )
end

# PORT: pl-modul.c declareModule
# DIVERGES: `class` and `super` are atoms (the one caller, `'$declare_module'/6`, gets them with `PL_get_atom_ex`); the source file has no
# `reload` (reconsult is not ported: `registerReloadModule` is not reached); the module's file is the source file's INDEX (0: none); the
# procedures are walked in the order of the module's table (Julia's), where upstream's follows its hash table (D-0149 item 1); the
# abolish of a procedure with something to abolish is refused (Q7, `_abolishProcedure_pristine`), so the warning
# `declare_module(M, abolish(PIs))` below is written for the day `abolishProcedure` is ported.
"""
    declareModule(gd, ld, name, class, super, sf, line, allow_newfile) -> Bool

Declare `name` a module of class `class`, defined in the source file `sf` at `line` (pl-modul.c): the module becomes the source module; one
already loaded from another file is a `permission_error(redefine, module, name)` unless `allow_newfile`; the public table is cleared
and the procedures it has are abolished; `super` becomes its one super module.
"""
function declareModule(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::T, class::T, super::T,
    sf::SourceFile{T}, line::Int, allow_newfile::Bool
)::Bool where {T}
    module_ = lookupModule(gd, name)
    tmp = rdef = rtail = 0
    rc = true

    module_.class = class

    if !allow_newfile && module_.file != 0 && module_.file != sf.index
        obj = PL_new_term_ref(ld)
        PL_put_atom(ld, obj, name)
        msg =
            "Already loaded from " *
            _text_summary(sym_text(gd.files_array[module_.file].name), 100)
        return PL_error(
            ld, "module", 2, msg, ERR_PERMISSION, mk_sym(T, :redefine), mk_sym(T, :module),
            obj
        )
    end

    if module_.file != sf.index
        module_.file = sf.index
        addModuleSourceFile(sf, module_)
    end
    module_.line_no = line
    ld.modules_source = module_.index

    for proc in values(module_.procedures)
        def = proc.definition

        if (def.flags & (P_DYNAMIC | P_MULTIFILE | P_FOREIGN)) == 0
            if def.module_ == module_.index && hasClausesDefinition(gd, def) !== nothing
                if rdef == 0
                    rdef = PL_new_term_ref(ld)
                    rtail = PL_copy_term_ref(ld, rdef)
                    tmp = PL_new_term_ref(ld)
                end

                PL_unify_list(ld, rtail, tmp, rtail)
                unify_definition(gd, ld, MODULE_user(gd), tmp, def, 0, GP_NAMEARITY)
            end
            _abolishProcedure_pristine(gd, module_, proc)
        end
    end
    empty!(module_.public_)                             # clearHTableWP(module->public)
    empty!(module_.public_order)
    rc = setSuperModule(gd.modules, ld, module_, lookupModule(gd, super))

    if rdef != 0
        PL_unify_nil(ld, rtail) || return false

        if rc
            rc = printMessage(
                ld, :warning,
                _message_term(
                    ld,
                    :declare_module,
                    _err_atom(ld, name),
                    _message_term(ld, :abolish, rdef)
                )
            )
        end
    end

    return rc
end

# PORT: pl-modul.c declare_module as pl_declare_module6_va
# (PRED_IMPL("\$declare_module", 6, declare_module, 0))
"`'\$declare_module'(+Module, +Class, +Super, +File, +Line, +Redefine)`: start a new (source-)module (pl-modul.c)."
function pl_declare_module6_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3, A4, A5, A6 = PL__t0,
    PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4,
    PL__t0 + 5

    mname = PL_get_atom_ex(ld, A1)
    mname === nothing && return FFALSE
    cname = PL_get_atom_ex(ld, A2)
    cname === nothing && return FFALSE
    sname = PL_get_atom_ex(ld, A3)
    sname === nothing && return FFALSE
    fname = PL_get_atom_ex(ld, A4)
    fname === nothing && return FFALSE
    line_no = PL_get_integer_ex(ld, A5)
    line_no === nothing && return FFALSE
    rdef = PL_get_stdbool_ex(ld, A6)
    rdef === nothing && return FFALSE

    sf = lookupSourceFile(gd, fname, true)::SourceFile{T}
    return declareModule(gd, ld, mname, cname, sname, sf, line_no, rdef) ? FTRUE : FFALSE
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

# PORT: pl-modul.c strip_module as pl_strip_module3_va
# (PRED_IMPL("strip_module", 3, strip_module, PL_FA_TRANSPARENT), pl-modul.c:1077-1089 at the pin:
#     if ( (plain = PL_new_term_ref()) &&
#          PL_strip_module(A1, &m, plain) &&
#          PL_unify_atom(A2, m->name) &&
#          PL_unify(A3, plain) )
#       succeed;
#     fail;                                                                      MOD2)
# DIVERGES: the module is an index into `gd`'s table (0 for upstream's NULL `m`).
"`strip_module(+Term, -Module, -Plain)`: `Term`'s atom qualifiers off, the module they or the context name (pl-modul.c)."
function pl_strip_module3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    plain = PL_new_term_ref(ld)
    ok, m = PL_strip_module(gd, ld, A1, 0, plain)  # Module m = NULL; PL_strip_module(A1, &m, plain)
    ok || return FFALSE
    return if PL_unify_atom(ld, A2, gd.modules[m].atom) && PL_unify(ld, A3, plain)
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-modul.c pl_context_module
# (FRG("context_module", 1, pl_context_module, META), pl-ext.c:161; pl-modul.c:1613-1617 at the pin:
#     return PL_unify_atom(module, contextModule(environment_frame)->name);       MOD2)
# DIVERGES: the database is the query's (`_query_gd`); the module an index into its table.
"`context_module(-Module)`: the context module of the calling frame (pl-modul.c); `context_module/1` is transparent."
function pl_context_module(ld::PL_local_data{T}, module_::term_t)::foreign_t where {T}
    gd = _query_gd(ld)
    m = contextModule(gd, ld, ld.environment_frame)
    return PL_unify_atom(ld, module_, gd.modules[m].atom) ? FTRUE : FFALSE
end

# PORT: pl-modul.c BeginPredDefs as PL_predicates_from_module
# DIVERGES: the entries of the predicates the kernel has ported, in upstream's order (MOD1: the table, the
# supers, the source and typein modules, `'$module_property'/2`); `PRED_DEF` ors in `PL_FA_VARARGS`.
# Since MOD2 `strip_module/3`, since MOD5a `'$def_modules'/2`, `import/1`, `'$import'/2`, `export/1` and
# `'$undefined_export'/2`, since MOD5b `'$declare_module'/6` and `'$destroy_module'/1`. LATER STEPS: `import_module/2`,
# `'$current_module'/2` (non-deterministic: MOD6).
"pl-modul.c's registration table (`BeginPredDefs(module)`): the ported entries."
const PL_predicates_from_module = (
    PL_extension(
        "\$def_modules", 2, pl_def_modules2_va, PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension("\$declare_module", 6, pl_declare_module6_va, PL_FA_VARARGS),
    PL_extension("add_import_module", 3, pl_add_import_module3_va, PL_FA_VARARGS),
    PL_extension("delete_import_module", 2, pl_delete_import_module2_va, PL_FA_VARARGS),
    PL_extension("set_module", 1, pl_set_module1_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
    PL_extension("\$module_property", 2, pl_module_property2_va, PL_FA_VARARGS),
    PL_extension("strip_module", 3, pl_strip_module3_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
    PL_extension("import", 1, pl_import1_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
    PL_extension("\$import", 2, pl_import2_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
    PL_extension("export", 1, pl_export1_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
    PL_extension("\$undefined_export", 2, pl_undefined_export2_va, PL_FA_VARARGS),
    PL_extension("\$destroy_module", 1, pl_destroy_module1_va, PL_FA_VARARGS),
    PL_extension(
        "\$current_source_module", 1, pl_current_source_module1_va, PL_FA_VARARGS
    ),
    PL_extension("\$set_source_module", 1, pl_set_source_module1_va, PL_FA_VARARGS),
    PL_extension(
        "\$current_typein_module", 1, pl_current_typein_module1_va, PL_FA_VARARGS
    ),
    PL_extension("\$set_typein_module", 1, pl_set_typein_module1_va, PL_FA_VARARGS)
)
