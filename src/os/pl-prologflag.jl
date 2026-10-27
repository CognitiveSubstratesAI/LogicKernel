# UPSTREAM: swipl-devel src/os/pl-prologflag.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/os/pl-prologflag.h @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-incl.h @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# PROLOG FLAGS (pl-prologflag.c). Since R1e's write_term/2,3: `setBackQuotes` and (read_term_from_atom/3)
# `setDoubleQuotes`. Since R2 F1a (design evidence/r2/design/flags_rest.md): the flag TABLE
# (`GD->prolog_flag.table`, src/pl-incl.jl's `prolog_flag_table`), `setPrologFlag`, `initPrologFlags`
# with the flags of `initArith`, `initClauseIndexing` and `initTabling`, the mask of the fast Boolean flags
# (`truePrologFlag`), `current_prolog_flag/2` and `'$current_prolog_flag'/5` (`pl_prolog_flag5`, the
# NON-DETERMINISTIC foreign predicate over `unify_prolog_flag_value`), `PL_current_prolog_flag` and
# `PL_get_prolog_flag`. NOT PORTED: the write side — `set_prolog_flag/2`, `create_prolog_flag/3`,
# `set_flag_value` and its side effects, `push_prolog_flag/2`, `pop_prolog_flag/1` (R2 F1b, F2) — and the
# flags' threading (`LD->prolog_flag.table`, `FF_SHARED`'s mutex, `PL_LOCK(L_PLFLAG)`, `unify_shared_prolog_flag`:
# the kernel is upstream's single-threaded build, design D1: one table, `threads` false and read-only).
#
# WHICH FLAGS EXIST (design D4, D5). `initPrologFlags!` defines the flags of upstream's `initPrologFlags`
# for a Linux build without threads, at upstream's default; the machine-dependent ones (`pid`, `executable`,
# `arch`, `tmp_dir`, `cpu_count`, `path_max`, `address_bits`, `timezone`, `version`, `argv`, …) take the
# kernel's own values. NOT DEFINED, each a family the kernel does not have (the pinned list in
# test/core_lang/test_prolog_flag_swipl.jl names every flag swipl has and the kernel has not, with its
# family): the C toolchain and shared objects (`c_cc`, `c_cxx`, `c_libs`, `c_libplso`, `c_ldflags`,
# `c_cflags`, `open_shared_object`, `shared_object_extension`, `shared_object_search_path`,
# `executable_format`, `libswipl`, `build_type`, `version_git`, `cmake_build_type`), pipes (`pipe`),
# threads and engines (`engines`, `system_thread_id`, `shared_table_space`), and every flag that Prolog code of
# boot/ and library/ creates (`create_prolog_flag/3`, R2 F1b).
#
# A BUILD-FEATURE FLAG answers as upstream's build WITHOUT that feature (audit D-0151 item 6), at the pin
# (pl-prologflag.c): `open_shared_object`, `shared_object_extension`, `shared_object_search_path` and the
# `c_*` flags are inside `#ifdef O_DYNAMIC_EXTENSIONS` (:2593-2606, no `#else`); `pipe` inside
# `#ifdef HAVE_POPEN` (:2608-2610, no `#else`); `shared_table_space` (:2589-2591), `system_thread_id` and
# the threaded `threads`/`gc_thread` (:2611-2619) inside `#ifdef O_PLMT`, whose `#else` (:2620-2622) defines
# `threads` and `gc_thread` read-only false; `engines` in that `#else` only `#ifdef O_ENGINES` (:2623-2625).
# All are therefore undefined, except those two. `home` is DEFINED (the kernel's own value, :2548-2549).
# The kernel is the cmake build MULTI_THREADED=OFF, ENGINES=OFF (CMakeLists.txt:91-97, ENGINES default ON): `O_ENGINES`
# is set by the ENGINES option alone (cmake/Config.cmake:441-443; pl-incl.h:92 only adds it with O_PLMT), and a build with
# ENGINES=ON but no threads would define `engines` true (:2623-2625). The kernel has no engines, so it is the OFF build.
# `compiled_at` is DEFINED, though the C toolchain is not the kernel's: its `__DATE__`/`__TIME__` branch (:2785-2787) has
# no feature test. `abi_version` is DEFINED by every upstream build (`setABIVersionPrologFlag`, :2956-2963, called
# unconditionally from pl-setup.c:178) but its value is a dict (`abi{...}`, `PL_put_dict`), which the kernel has not:
# it stays undefined, a pending difference (not a build family) until dicts are ported. `resource_database`
# (pl-init.c:1611), `emacs_inferior_process` (pl-init.c:857) and `malloc` (pl-alloc.c:1777, :1827) are set outside this
# file, unconditionally or by the allocator found, and wait for those files.
#
# DIVERGES (file-wide): the per-module flags are read from the module record. `var_prefix` is the module's
# (`module_t.var_prefix`, MOD1: the character, 0 for none), as upstream's `m->var_prefix`; the write side
# (`setVarPrefix`, `set_prolog_flag(var_prefix, V)`) is F1b's. `module_t` has no `var_tag` (upstream keeps it in
# the VARTAG_* bits of `m->flags`, which the kernel does not have), so `var_tag` reads the table's value (its
# default, `dict`), until the modules area gives the record those bits.
# The flags whose value upstream reads from the debugger (`debug`, `debugger_show_context`), the toplevel
# (`break_level`) or the local data (`access_level`) read what the kernel has: no debugger and no toplevel,
# `access_level` `user`.
# Five Boolean flags are, until R2 F1b deletes the stand-ins, still the local data's fields
# (`prolog_flag_last_call`, `_portable_vmi`, `_optimise`, `_optimise_unify`, `_character_escapes_unicode`,
# src/pl-global.jl), which the compiler and the VM read: `_prolog_flag_bit` reads them where upstream reads
# the mask.

# PORT: pl-prologflag.c setDoubleQuotes
# DIVERGES: as `setBackQuotes`.
"`flags` with the double-quote syntax the atom `a` names (`chars`, `codes`, `atom`, `string`), or `nothing` after `domain_error(double_quotes, A)` (pl-prologflag.c)."
function setDoubleQuotes(
    ld::PL_local_data{T}, a::T, flags::UInt32
)::Union{Nothing, UInt32} where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :chars))
        f = DBLQ_CHARS
    elseif k == sym_key(mk_sym(T, :codes))
        f = UInt32(0)
    elseif k == sym_key(mk_sym(T, :atom))
        f = DBLQ_ATOM
    elseif k == sym_key(mk_sym(T, :string))
        f = DBLQ_STRING
    else
        value = PL_new_term_ref(ld)
        setSlotValue!(ld, value + 1, a)                     # PL_put_atom(value, a)
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :double_quotes), value)
        return nothing
    end

    flags &= ~DBLQ_MASK
    flags |= f

    return flags
end

# PORT: pl-prologflag.c setBackQuotes
# DIVERGES: returns the new flags, or `nothing` with the error raised, where upstream writes them
# through `flagp` and returns a Boolean.
"`flags` with the back-quote syntax the atom `a` names (`string`, `symbol_char`, `codes`, `chars`), or `nothing` after `domain_error(back_quotes, A)` (pl-prologflag.c)."
function setBackQuotes(
    ld::PL_local_data{T}, a::T, flags::UInt32
)::Union{Nothing, UInt32} where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :string))
        f = BQ_STRING
    elseif k == sym_key(mk_sym(T, :symbol_char))
        f = UInt32(0)
    elseif k == sym_key(mk_sym(T, :codes))
        f = BQ_CODES
    elseif k == sym_key(mk_sym(T, :chars))
        f = BQ_CHARS
    else
        value = PL_new_term_ref(ld)
        setSlotValue!(ld, value + 1, a)                     # PL_put_atom(value, a)
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :back_quotes), value)
        return nothing
    end

    flags &= ~BQ_MASK
    flags |= f

    return flags
end

# ── the mask (pl-incl.h) ─────────────────────────────────────────────────────────────────────────
# PORT: pl-incl.h truePrologFlag
# DIVERGES: the local data is an argument (upstream's `LD`); the mask is one 64-bit word (see src/pl-incl.jl).
"Whether the bit `flag` (a `PLFLAG_*`) of the local data's mask is set (pl-incl.h)."
truePrologFlag(ld::PL_local_data, flag::Integer)::Bool =
    (ld.prolog_flag_mask & prologFlagMask(flag)) != 0

# ORIGINAL (until R2 F1b): a Boolean flag's bit as the compiler and the VM read it. Five bits are still
# fields of the local data (src/pl-global.jl), set by tests and read by src/pl-comp.jl and src/pl-wam.jl;
# the mask holds their defaults, never read. F1b deletes the fields, and this function with them.
"The value of the mask bit `index` of `ld` — the field that stands in for it, for the five that still have one."
function _prolog_flag_bit(ld::PL_local_data, index::Integer)::Bool
    index == PLFLAG_LASTCALL && return ld.prolog_flag_last_call
    index == PLFLAG_PORTABLE_VMI && return ld.prolog_flag_portable_vmi
    index == PLFLAG_OPTIMISE && return ld.prolog_flag_optimise
    index == PLFLAG_OPTIMISE_UNIFY && return ld.prolog_flag_optimise_unify
    index == PLFLAG_CHARESCAPE_UNICODE && return ld.prolog_flag_character_escapes_unicode
    return truePrologFlag(ld, index)
end

# ── the table (pl-prologflag.c) ──────────────────────────────────────────────────────────────────
# PORT: pl-prologflag.c accessed_prolog_flag
# DIVERGES: no local table (`FF_ISLOCAL`), so no second flag to mark.
"Mark the flag `f` accessed, if it warns when it never is (pl-prologflag.c)."
function accessed_prolog_flag(f::prolog_flag)::Nothing
    if (f.flags & FF_WARN_NOT_ACCESSED) != 0 && (f.flags & FF_ACCESSED) == 0
        f.flags |= FF_ACCESSED
    end
    return nothing
end

# PORT: pl-prologflag.c lookupFlag
# DIVERGES: the database is an argument, the key an atom WORD (the table's key); no local table
# (`FF_LOCAL`, `FF_GLOBAL`): the table is the global one.
"The flag with the key `key` (an atom word) in the table of `gd`, or `nothing` (pl-prologflag.c)."
function lookupFlag(
    gd::PL_global_data{T}, key::UInt64
)::Union{Nothing, prolog_flag{T}} where {T}
    i = get(gd.prolog_flag.slot, key, 0)
    i == 0 && return nothing
    f = gd.prolog_flag.entries[i]::prolog_flag{T}
    accessed_prolog_flag(f)
    return f
end

# PORT: pl-prologflag.c current_prolog_flag
# DIVERGES: the database is an argument.
"The flag named `name` in the table of `gd`, or `nothing` (pl-prologflag.c)."
function current_prolog_flag(
    gd::PL_global_data{T}, name::AbstractString
)::Union{Nothing, prolog_flag{T}} where {T}
    return lookupFlag(gd, _atom_word!(gd.atoms, gd.atom_symbols, mk_sym(T, Symbol(name))))
end

# ORIGINAL (design D2): upstream's `deleteHTableWP(GD->prolog_flag.table, k)` of a popped `FF_PUSH_ABSENT` frame
# (`pop_prolog_flag/1`, R2 F2): the slot is emptied and not reused (see `prolog_flag_table`).
"Delete the flag with the key `key` (an atom word) from the table of `gd`; whether there was one."
function deletePrologFlag!(gd::PL_global_data, key::UInt64)::Bool
    tab = gd.prolog_flag
    i = pop!(tab.slot, key, 0)
    i == 0 && return false
    tab.entries[i] = nothing
    return true
end

# The flag `name` of the table of `gd`, made if it is new: `(flag, true)`; if it exists, `(flag, false)`,
# or `(nothing, false)` when `flags` has `FF_KEEP` (the first lines of upstream's `setPrologFlag`).
function _prolog_flag_slot!(
    gd::PL_global_data{T}, name::AbstractString, flags::UInt32
)::Tuple{Union{Nothing, prolog_flag{T}}, Bool} where {T}
    tab = gd.prolog_flag
    an = mk_sym(T, Symbol(name))
    w = _atom_word!(gd.atoms, gd.atom_symbols, an)
    i = get(tab.slot, w, 0)
    if i != 0
        f = tab.entries[i]::prolog_flag{T}
        @assert (f.flags & FT_MASK) == (flags & FT_MASK) "setPrologFlag($name): the type differs"
        (flags & FF_KEEP) != 0 && return (nothing, false)
        return (f, false)
    end
    f = prolog_flag{T}(flags, mk_sym(T, Symbol("false")))
    push!(tab.entries, f)
    push!(tab.names, an)
    tab.slot[w] = length(tab.entries)
    return (f, true)
end

# PORT: pl-prologflag.c setPrologFlag
# DIVERGES: upstream's one variadic function is one method per value type (`FT_BOOL`: a `Bool` and the mask bit;
# `FT_INTEGER`/`FT_INT64`: an `Integer`; `FT_FLOAT`; `FT_ATOM`: a string; `FT_TERM`: a term reference, with the
# local data that holds it); the database is the first argument. The mask it writes is the database's
# (`gd.prolog_flag.mask`, the initial thread's, which every new local data copies): `setPrologFlag` runs
# where there is no local data yet, and upstream's `LD` is the initial thread's.
"Define the Boolean flag `name` with value `val`, owning the mask bit `index` (0: none) (pl-prologflag.c, `FT_BOOL`)."
function setPrologFlag(
    gd::PL_global_data{T}, name::AbstractString, flags::UInt32, val::Bool, index::Integer
)::Nothing where {T}
    (flags & FT_MASK) == FT_BOOL || error("setPrologFlag($name): not a Boolean type")
    f, first_def = _prolog_flag_slot!(gd, name, flags)
    f === nothing && return nothing
    if !first_def && index != 0 && f.index == 0         # type definition
        f.index = UInt32(index)
        val = sym_key(f.a) == sym_key(mk_sym(T, Symbol("true")))
    elseif first_def                                    # 1st definition
        f.index = UInt32(index)
    end

    f.a = mk_sym(T, val ? Symbol("true") : Symbol("false"))
    if f.index != 0
        if val
            gd.prolog_flag.mask |= prologFlagMask(f.index)      # setPrologFlagMask(f->index)
        else
            gd.prolog_flag.mask &= ~prologFlagMask(f.index)     # clearPrologFlagMask(f->index)
        end
    end
    return nothing
end

"Define the integer flag `name` (`FT_INTEGER` or `FT_INT64`) with value `val` (pl-prologflag.c `setPrologFlag`)."
function setPrologFlag(
    gd::PL_global_data{T}, name::AbstractString, flags::UInt32, val::Integer
)::Nothing where {T}
    type = flags & FT_MASK
    (type == FT_INTEGER || type == FT_INT64) ||
        error("setPrologFlag($name): not an integer type")
    flags = (flags & ~FT_MASK) | FT_INTEGER             # FT_INT64 is stored as FT_INTEGER
    f, _ = _prolog_flag_slot!(gd, name, flags)
    f === nothing && return nothing
    f.i = Int64(val)
    return nothing
end

"Define the float flag `name` with value `val` (pl-prologflag.c `setPrologFlag`, `FT_FLOAT`)."
function setPrologFlag(
    gd::PL_global_data{T}, name::AbstractString, flags::UInt32, val::AbstractFloat
)::Nothing where {T}
    (flags & FT_MASK) == FT_FLOAT || error("setPrologFlag($name): not a float type")
    f, _ = _prolog_flag_slot!(gd, name, flags)
    f === nothing && return nothing
    f.f = Float64(val)
    return nothing
end

"Define the atom flag `name` with the atom of the text `val` (pl-prologflag.c `setPrologFlag`, `FT_ATOM`)."
function setPrologFlag(
    gd::PL_global_data{T}, name::AbstractString, flags::UInt32, val::AbstractString
)::Nothing where {T}
    (flags & FT_MASK) == FT_ATOM || error("setPrologFlag($name): not an atom type")
    f, _ = _prolog_flag_slot!(gd, name, flags)
    f === nothing && return nothing
    f.a = mk_sym(T, Symbol(val))
    return nothing
end

"Define the term flag `name` with a record of the term `t` references (pl-prologflag.c `setPrologFlag`, `FT_TERM`)."
function setPrologFlag(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::AbstractString, flags::UInt32,
    t::term_t
)::Nothing where {T}
    (flags & FT_MASK) == FT_TERM || error("setPrologFlag($name): not a term type")
    f, _ = _prolog_flag_slot!(gd, name, flags)
    f === nothing && return nothing
    f.t = PL_record(ld, t)
    return nothing
end

# ── reading a flag (pl-prologflag.c) ─────────────────────────────────────────────────────────────
# PORT: pl-prologflag.c put_oneof
# DIVERGES: the term is built whole (`oneof(List)`) and put, where upstream conses the list cell by cell.
"Put `oneof([V1, …])`, the values of the flag type `of`, into term reference `t` (pl-prologflag.c)."
function put_oneof(ld::PL_local_data{T}, t::term_t, of::oneof_t{T})::Bool where {T}
    lst = mk_nil(T)
    for i in length(of.values):-1:1
        lst = mk_expr(T, T[mk_sym(T, LIST_CONS_NAME), of.values[i], lst])
    end
    putSlotValue!(ld, t + 1, mk_expr(T, T[mk_sym(T, :oneof), lst]))
    return true
end

# ORIGINAL (pl-index.c `ci_flag`, `ci_is_flag`, `ci_get_flag`, `initClauseIndexing`'s flags): the clause-indexing
# parameters are constants here (src/pl-index.jl `MIN_SPEEDUP`, …: upstream keeps them in `GD->clause_index`,
# settable through these flags), so the flags are read-only in effect; R2 F1b refuses to set them by name. They
# are here and not in src/pl-index.jl because that file is included before the local data's type is defined.
"The names of the clause-indexing flags, in pl-index.c's `ciflags` order."
const CI_FLAG_NAMES = (
    "ci_min_speedup", "ci_max_var_fraction", "ci_min_speedup_ratio", "ci_max_lookahead",
    "ci_min_clauses"
)

"Define the Prolog flags of the clause indexing (pl-index.c `initClauseIndexing`)."
function initClauseIndexing!(gd::PL_global_data{T})::Nothing where {T}
    setPrologFlag(gd, "ci_min_speedup", FT_FLOAT, Float64(MIN_SPEEDUP))
    setPrologFlag(gd, "ci_max_var_fraction", FT_FLOAT, Float64(MAX_VAR_FRAC))
    setPrologFlag(gd, "ci_min_speedup_ratio", FT_FLOAT, Float64(MIN_SPEEDUP_RATIO))
    setPrologFlag(gd, "ci_max_lookahead", FT_INTEGER, MAX_LOOKAHEAD)
    setPrologFlag(gd, "ci_min_clauses", FT_INTEGER, MIN_CLAUSES_FOR_INDEX)
    return nothing
end

"Whether the atom `key` names a clause-indexing flag (pl-index.c `ci_is_flag`)."
ci_is_flag(key::T) where {T} = sym_text(key) in CI_FLAG_NAMES

"Unify `t` with the value of the clause-indexing flag `key` (pl-index.c `ci_get_flag`)."
function ci_get_flag(ld::PL_local_data{T}, t::term_t, key::T)::Bool where {T}
    name = sym_text(key)
    name == "ci_min_speedup" && return PL_unify_float(ld, t, Float64(MIN_SPEEDUP))
    name == "ci_max_var_fraction" && return PL_unify_float(ld, t, Float64(MAX_VAR_FRAC))
    name == "ci_min_speedup_ratio" &&
        return PL_unify_float(ld, t, Float64(MIN_SPEEDUP_RATIO))
    name == "ci_max_lookahead" && return PL_unify_integer(ld, t, MAX_LOOKAHEAD)
    name == "ci_min_clauses" && return PL_unify_integer(ld, t, MIN_CLAUSES_FOR_INDEX)
    return false
end

# ORIGINAL (pl-tabling.c `tbl_is_restraint_flag`, `tbl_get_restraint_flag`, `unify_restraint`): the tabling
# restraints live in `LD->tabling.restraint`, which the kernel does not have (tabling is not ported). Their only
# value is the default `initTabling` sets — `error` for the three `*_action` flags, `(size_t)-1`, unlimited, for
# the three sizes — which nothing can change before `set_prolog_flag/2` (R2 F1b refuses to set them by name).
# `unify_restraint` fails for `(size_t)-1`: the three sizes answer nothing, as upstream's do.
"Whether the atom `key` names a tabling restraint flag whose value is unlimited, so that reading it fails (pl-tabling.c `tbl_get_restraint_flag`)."
function _tbl_restraint_unlimited(key::T)::Bool where {T}
    name = sym_text(key)
    return name == "max_table_subgoal_size" ||
           name == "max_table_answer_size" ||
           name == "max_answers_for_subgoal"
end

# PORT: pl-prologflag.c unify_prolog_flag_value
# DIVERGES: the database and the module (an index into its table) are arguments; the key is compared by its
# text, where upstream compares atom handles. The per-module flags are the module record's (see the file
# header for `var_tag`, which reads the table); `debug` and `debugger_show_context` answer
# `false` (no debugger), `break_level` fails (no toplevel: `currentBreakLevel() < 0`), `access_level` is
# `user`; `stack_limit` is the local stack's limit in bytes (the kernel counts words). The shared-flag
# copy (`unify_shared_prolog_flag`) is not needed without threads.
"Unify `val` with the value of the flag `f`, named `key`, as module `m` sees it (pl-prologflag.c)."
function unify_prolog_flag_value(
    gd::PL_global_data{T}, ld::PL_local_data{T}, m::Int, key::T, f::prolog_flag{T},
    val::term_t
)::Bool where {T}
    name = sym_text(key)
    mdl = gd.modules[m]
    if name == "character_escapes"
        return PL_unify_bool(ld, val, (mdl.flags & M_CHARESCAPE) != 0)
    elseif name == "var_prefix"
        # m->var_prefix ? codeToAtom(m->var_prefix) : ATOM_false
        v = mdl.var_prefix != 0 ? Symbol(Char(mdl.var_prefix)) : Symbol("false")   # (`:false` is the Bool)
        return PL_unify_atom(ld, val, mk_sym(T, v))
    elseif name == "double_quotes"
        if (mdl.flags & DBLQ_CHARS) != 0
            v = :chars
        elseif (mdl.flags & DBLQ_ATOM) != 0
            v = :atom
        elseif (mdl.flags & DBLQ_STRING) != 0
            v = :string
        else
            v = :codes
        end
        return PL_unify_atom(ld, val, mk_sym(T, v))
    elseif name == "back_quotes"
        if (mdl.flags & BQ_STRING) != 0
            v = :string
        elseif (mdl.flags & BQ_CODES) != 0
            v = :codes
        elseif (mdl.flags & BQ_CHARS) != 0
            v = :chars
        else
            v = :symbol_char
        end
        return PL_unify_atom(ld, val, mk_sym(T, v))
    elseif name == "rational_syntax"
        v = (mdl.flags & RAT_MASK) == RAT_NATURAL ? :natural : :compatibility
        return PL_unify_atom(ld, val, mk_sym(T, v))
    elseif name == "unknown"
        u = getUnknownModule(gd, mdl)
        u == UNKNOWN_ERROR && return PL_unify_atom(ld, val, mk_sym(T, :error))
        u == UNKNOWN_WARNING && return PL_unify_atom(ld, val, mk_sym(T, :warning))
        u == UNKNOWN_FAIL && return PL_unify_atom(ld, val, mk_sym(T, :fail))
        return false
    elseif name == "debug"
        return PL_unify_bool_ex(ld, val, false)
    elseif name == "debugger_show_context"
        return PL_unify_bool_ex(ld, val, false)
    elseif name == "break_level"
        return false
    elseif name == "access_level"
        return PL_unify_atom(ld, val, mk_sym(T, :user))
    elseif name == "stack_limit"
        return PL_unify_int64(ld, val, ld.stacks_limit * 8)
    elseif _tbl_restraint_unlimited(key)
        return false
    elseif is_arith_flag(key)
        return get_arith_flag(ld, val, key)
    elseif ci_is_flag(key)
        return ci_get_flag(ld, val, key)
    end

    type = f.flags & FT_MASK
    if type == FT_BOOL
        if f.index != 0
            return PL_unify_bool_ex(ld, val, _prolog_flag_bit(ld, f.index))
        end
        return PL_unify_atom(ld, val, f.a)
    elseif type == FT_ATOM
        return PL_unify_atom(ld, val, f.a)
    elseif type == FT_INTEGER
        return PL_unify_int64(ld, val, Int(f.i))
    elseif type == FT_FLOAT
        return PL_unify_float(ld, val, f.f)
    elseif type == FT_TERM
        tmp = PL_new_term_ref(ld)
        if PL_recorded(ld, f.t::record{T}, tmp)
            return PL_unify(ld, val, tmp)
        end
        return false                                    # the overflow is raised (raiseStackOverflow)
    end
    error("unify_prolog_flag_value: the flag $name has the type $type")
end

# PORT: pl-prologflag.c unify_prolog_flag_access
"Unify `access` with `read` for a read-only flag, `write` for another (pl-prologflag.c)."
function unify_prolog_flag_access(
    ld::PL_local_data{T}, f::prolog_flag{T}, access::term_t
)::Bool where {T}
    if (f.flags & FF_READONLY) != 0
        return PL_unify_atom(ld, access, mk_sym(T, :read))
    end
    return PL_unify_atom(ld, access, mk_sym(T, :write))
end

# PORT: pl-prologflag.c unify_prolog_flag_type
"Unify `type` with the type of the flag `f`: `boolean`, `atom`, `oneof(List)`, `integer`, `float` or `term` (pl-prologflag.c)."
function unify_prolog_flag_type(
    ld::PL_local_data{T}, f::prolog_flag{T}, type::term_t
)::Bool where {T}
    t = f.flags & FT_MASK
    if t == FT_BOOL
        a = :boolean
    elseif t == FT_ATOM
        of = f.oneof
        if of !== nothing
            tt = PL_new_term_ref(ld)
            return put_oneof(ld, tt, of) && PL_unify(ld, tt, type)
        end
        a = :atom
    elseif t == FT_INTEGER
        a = :integer
    elseif t == FT_FLOAT
        a = :float
    elseif t == FT_TERM
        a = :term
    else
        error("unify_prolog_flag_type: type $t")
    end
    return PL_unify_atom(ld, type, mk_sym(T, a))
end

# PORT: pl-prologflag.c pl_prolog_flag5
# DIVERGES: the database is an argument; the state of an enumeration is a record of the local data's pool
# (`ld.prolog_flag_enums`), its index the `REDO_PTR` context, and the walk is over the table's slots in
# creation order (upstream's `TableEnum`, hash-table order: audit D-0149 item 1); there is no local table
# (no threads), so `scope` is `global` unless the caller names one. At the pin cbf4e189 plus upstream's fix 1412ce49
# (the marker line is port_check's strict form; D-0175): an explicit `local` scope without a thread-local table fails
# (`if ( !LD->prolog_flag.table ) { freeHeap(e, sizeof(*e)); fail; }`), here always, since the kernel has no such table.
# The foreign frame is closed before a retry (the kernel's non-deterministic built-ins do: upstream leaves it to the exit
# of the predicate). No locking (`PL_LOCK(L_PLFLAG)`).
"""
    pl_prolog_flag5(gd, ld, key, value, scope, access, type, h)

`current_prolog_flag/2` and `'\$current_prolog_flag'/5` (pl-prologflag.c): `scope`, `access` and `type` are
term references, 0 when the predicate has no such argument. With the key bound it is deterministic; with
it unbound it enumerates the flags whose value, scope, access and type unify, one per answer.
"""
function pl_prolog_flag5(
    gd::PL_global_data{T}, ld::PL_local_data{T}, key::term_t, value::term_t, scope::term_t,
    access::term_t, type::term_t, h::control_t{T}
)::foreign_t where {T}
    pool = ld.prolog_flag_enums
    ctl = PL_foreign_control(h)
    if ctl == FRG_FIRST_CALL
        ok, module_ = PL_strip_module(gd, ld, key, MODULE_user(gd).index, key)  # MODULE_parse
        ok || return FFALSE

        k = PL_get_atom(ld, key)
        if k !== nothing
            f = lookupFlag(gd, _atom_word!(ld, k))
            f === nothing && return FFALSE
            return if (
                unify_prolog_flag_value(gd, ld, module_, k, f, value) &&
                (access == 0 || unify_prolog_flag_access(ld, f, access)) &&
                (type == 0 || unify_prolog_flag_type(ld, f, type))
            )
                FTRUE
            else
                FFALSE
            end
        elseif PL_is_variable(ld, key)
            idx = alloc_foreign_state!(pool)
            e = pool.states[idx]
            e.module_ = module_
            e.next = 1
            sa = scope != 0 ? PL_get_atom(ld, scope) : nothing
            if sa !== nothing
                e.explicit_scope = true
                sname = sym_text(sa)
                if !(sname == "local" || sname == "global")
                    free_foreign_state!(pool, idx)
                    return if PL_error(ld, ERR_DOMAIN, mk_sym(T, :scope), scope)
                        FTRUE
                    else
                        FFALSE
                    end
                end
                e.is_local = sname == "local"
            else
                e.explicit_scope = false
                e.is_local = false                      # no thread-local table: the global one
            end
            if e.is_local                               # if ( e->scope == ATOM_local )
                # upstream 1412ce49: if ( !LD->prolog_flag.table ) { freeHeap(e, sizeof(*e)); fail; } — the kernel has none
                free_foreign_state!(pool, idx)
                return FFALSE
            end
        else
            return PL_error(ld, ERR_TYPE, mk_sym(T, :atom), key) ? FTRUE : FFALSE
        end
    elseif ctl == FRG_REDO
        idx = PL_foreign_context_address(h)             # e = ForeignContextPtr(h)
    else                                                # FRG_CUTTED
        idx = PL_foreign_context_address(h)
        idx != 0 && free_foreign_state!(pool, idx)
        return FTRUE
    end
    e = pool.states[idx]

    fid = PL_open_foreign_frame(ld)
    if fid == 0
        free_foreign_state!(pool, idx)
        return FFALSE
    end
    tab = gd.prolog_flag
    while true
        # (`e.is_local` is never set here: an explicit `local` scope has failed above; the switch below is upstream's, kept for a local table)
        while !e.is_local && e.next <= length(tab.entries)
            i = e.next
            e.next += 1
            f = tab.entries[i]
            f === nothing && continue                   # a deleted flag
            fn = tab.names[i]

            if PL_unify_atom(ld, key, fn) &&
                unify_prolog_flag_value(gd, ld, e.module_, fn, f, value) &&
                (
                    scope == 0 ||
                    PL_unify_atom(
                        ld,
                        scope,
                        mk_sym(T, e.is_local ? Symbol("local") : Symbol("global"))
                    )
                ) &&
                (access == 0 || unify_prolog_flag_access(ld, f, access)) &&
                (type == 0 || unify_prolog_flag_type(ld, f, type))
                PL_close_foreign_frame(ld, fid)
                return PL_retry_address(idx)            # ForeignRedoPtr(e)
            end
            PL_exception(ld, 0) != 0 && PL_clear_exception(ld)
            PL_rewind_foreign_frame(ld, fid)
        end

        if e.is_local
            e.is_local = false                          # on to the global table
            e.next = 1
        else
            break
        end
    end

    PL_close_foreign_frame(ld, fid)
    free_foreign_state!(pool, idx)
    return FFALSE
end

# PORT: pl-prologflag.c PL_get_prolog_flag
# DIVERGES: the database is an argument; the name is an atom (`T`).
"Unify `value` with the value of the flag `name` (pl-prologflag.c); false if there is no such flag."
function PL_get_prolog_flag(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::T, value::term_t
)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    fid == 0 && return false
    key = PL_new_term_ref(ld)
    PL_put_atom(ld, key, name)
    h = foreign_context{T}(FRG_FIRST_CALL, UInt(0), nothing)
    rc = pl_prolog_flag5(gd, ld, key, value, 0, 0, 0, h) != FFALSE
    PL_close_foreign_frame(ld, fid)
    return rc
end

# PORT: pl-prologflag.c PL_current_prolog_flag
# DIVERGES: `type` is one of `:atom`, `:bool`, `:integer` and `:float`, and the value is returned (upstream
# writes it through a pointer); `nothing` when there is no such flag or it has another type. The `:term`
# form is the method with a term reference, which it makes hold the term and returns whether it did.
"The value of the flag `name` if it has the type `type`, else `nothing` (pl-prologflag.c)."
function PL_current_prolog_flag(
    gd::PL_global_data{T}, name::T, type::Symbol
) where {T}
    f = lookupFlag(gd, _atom_word!(gd.atoms, gd.atom_symbols, name))
    f === nothing && return nothing
    t = f.flags & FT_MASK
    if type === :atom
        t == FT_ATOM && return f.a
    elseif type === :bool
        t == FT_BOOL && return sym_key(f.a) == sym_key(mk_sym(T, Symbol("true")))
    elseif type === :integer
        t == FT_INTEGER && return f.i
    elseif type === :float
        t == FT_FLOAT && return f.f
    end
    return nothing
end

"Make the term reference `t` hold the term of the term flag `name`; false if there is no such flag, or another type (pl-prologflag.c `PL_current_prolog_flag`, `PL_TERM`)."
function PL_current_prolog_flag(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::T, t::term_t
)::Bool where {T}
    f = lookupFlag(gd, _atom_word!(gd.atoms, gd.atom_symbols, name))
    f === nothing && return false
    (f.flags & FT_MASK) == FT_TERM || return false
    return PL_recorded(ld, f.t::record{T}, t)
end

# ── the predicates (pl-prologflag.c) ─────────────────────────────────────────────────────────────
# PORT: pl-prologflag.c dcurrent_prolog_flag as pl_dcurrent_prolog_flag5_va
# (PRED_IMPL("$current_prolog_flag", 5, dcurrent_prolog_flag, PL_FA_NONDETERMINISTIC))
"`'\$current_prolog_flag'(?Key, ?Value, ?Scope, ?Access, ?Type)` (pl-prologflag.c)."
function pl_dcurrent_prolog_flag5_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4, A5 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4
    return pl_prolog_flag5(_query_gd(ld), ld, A1, A2, A3, A4, A5, PL__ctx)
end

# PORT: pl-prologflag.c current_prolog_flag as pl_current_prolog_flag2_va
# (PRED_IMPL("current_prolog_flag", 2, current_prolog_flag, PL_FA_ISO|PL_FA_NONDETERMINISTIC))
"`current_prolog_flag(?Key, ?Value)` (pl-prologflag.c)."
function pl_current_prolog_flag2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return pl_prolog_flag5(_query_gd(ld), ld, A1, A2, 0, 0, 0, PL__ctx)
end

# ── defining the flags (pl-prologflag.c) ─────────────────────────────────────────────────────────
# pl-prologflag.c `currentFileNameCaseHandling`, on the database's mask.
"The value of the flag `file_name_case_handling` from the mask bits of `gd` (pl-prologflag.c)."
function _current_file_name_case_handling(gd::PL_global_data)::String
    mask = gd.prolog_flag.mask
    (mask & prologFlagMask(PLFLAG_FILE_CASE)) != 0 && return "case_sensitive"
    (mask & prologFlagMask(PLFLAG_FILE_CASE_PRESERVING)) != 0 && return "case_preserving"
    return "case_insensitive"
end

# ORIGINAL: the machine-dependent values of design D5, read from Julia and the OS.
"The seconds west of Greenwich of the standard time (`timezone`, set by `tzset()`): the UTC offset of local time, the smaller of now's and six months on (a daylight saving time only adds), negated; 0 where libc has none."
function _timezone_seconds()::Int
    try
        now = time()
        east = min(_utc_offset(now), _utc_offset(now + 182 * 86400.0))
        return -east
    catch
        return 0
    end
end

# The offset of local time from UTC at the Unix time `t`, in seconds east: libc's `%z` (`+hhmm`).
function _utc_offset(t::Float64)::Int
    z = Libc.strftime("%z", t)
    sgn = z[1] == '-' ? -1 : 1
    return sgn * (parse(Int, z[2:3]) * 3600 + parse(Int, z[4:5]) * 60)
end

# ORIGINAL: `unicode_syntax_version` is a build-time constant of upstream (src/pl-umap-version.h, generated
# with src/pl-umap.c by Unicode/prolog_syntax_map.pl); the kernel's table (src/pl-umap.jl) is carried from the
# same generated file, so the version is the oracle's at the pin.
"The Unicode version of the syntax map (pl-umap-version.h `UNICODE_SYNTAX_VERSION`)."
const UNICODE_SYNTAX_VERSION = "17.0.0"

# ORIGINAL: the version of the system the pin names (src/pl-version.h `PLVERSION`: major*10000+minor*100+patch).
"The SWI-Prolog version the port follows, as the flag `version` has it: 10.1.19 is 100119 (pl-version.h `PLVERSION`)."
const PLVERSION = 100119

# ORIGINAL: upstream's `compiled_at` is the C compiler's `__DATE__ ", " __TIME__` (the `#elif defined(__DATE__) &&
# defined(__TIME__)` branch, pl-prologflag.c:2785-2787, which every C compiler satisfies, so a build without cmake's
# BUILD_DATE still defines it): `Mmm dd yyyy, hh:mm:ss`. The kernel has no C compilation: the value is the time Julia
# compiled this file (the package's precompilation), in the same layout.
"The time the kernel was compiled, laid out as the C compiler's `__DATE__`, `__TIME__` (the flag `compiled_at`)."
const COMPILED_AT = Libc.strftime("%b %e %Y, %T", time())

# ORIGINAL (design D3, D4): initTabling's flags (src/pl-tabling.c:11346-11352 at the pin, with the two of
# `initPrologFlags` for the tabling thresholds); pl-tabling.c is not ported, so they are defined here, at
# their defaults, in upstream's order.
"Define the Prolog flags of the tabling restraints (pl-tabling.c `initTabling`)."
function _init_tabling_flags!(gd::PL_global_data{T})::Nothing where {T}
    setPrologFlag(gd, "max_table_subgoal_size_action", FT_ATOM, "error")
    setPrologFlag(gd, "max_table_answer_size_action", FT_ATOM, "error")
    setPrologFlag(gd, "max_answers_for_subgoal_action", FT_ATOM, "error")
    setPrologFlag(gd, "max_table_subgoal_size", FT_INTEGER, -1)
    setPrologFlag(gd, "max_table_answer_size", FT_INTEGER, -1)
    setPrologFlag(gd, "max_answers_for_subgoal", FT_INTEGER, -1)
    setPrologFlag(gd, "table_monotonic", FT_ATOM, "eager")
    return nothing
end

# The flags that hold a list of atoms: `os_argv` and `argv` (pl-prologflag.c `setArgvPrologFlag`).
function _set_argv_prolog_flag!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, flag::String, argv::Vector{String}
)::Nothing where {T}
    t = PL_new_term_ref(ld)
    lst = mk_nil(T)
    for i in length(argv):-1:1
        lst = mk_expr(T, T[mk_sym(T, LIST_CONS_NAME), mk_sym(T, Symbol(argv[i])), lst])
    end
    putSlotValue!(ld, t + 1, lst)
    setPrologFlag(gd, ld, flag, FT_TERM, t)
    return nothing
end

# PORT: pl-prologflag.c initPrologFlags as initPrologFlags!
# DIVERGES: the database is the argument and the flags go to its table, in upstream's order. The order of the
# calls of pl-setup.c (`initClauseIndexing`, `initPrologFlags`, `initTabling`, `initArith`) is kept inside
# this function, so the constructor of the database makes one call, before `initBuildIns!` (pl-setup.c:136
# comes before :158). The command-line options are their defaults, with `-q` absent (`verbose` is `normal`),
# and `GD->options.traditional` false. NOT DEFINED, as the file header says: the build's configuration flags,
# `pipe`, `engines`, `system_thread_id`, `shared_table_space`; the Windows, macOS, Android, conda, WASM
# and runtime-only flags; `xpce` (no `--xpce`); `asan`; `version_git`; `abi_version`. `PL_set_prolog_flag`'s
# `cpu_count` (setOSPrologFlags, pl-os.c) is a plain definition here. Records are made in a local data of its
# own, which this function drops.
"Define the Prolog flags of the database `gd` at their defaults (pl-prologflag.c `initPrologFlags`, and the flags of the files it calls)."
function initPrologFlags!(gd::PL_global_data{T})::Nothing where {T}
    # the bits pl-os.c (:164-167) and pl-init.c (:1001, :1512) set before initPrologFlags
    gd.prolog_flag.mask |=
        prologFlagMask(PLFLAG_FILE_CASE) | prologFlagMask(PLFLAG_FILE_CASE_PRESERVING) |
        prologFlagMask(PLFLAG_DEBUGINFO) | prologFlagMask(PLFLAG_SIGNALS)

    initClauseIndexing!(gd)                             # pl-setup.c:123

    setPrologFlag(gd, "iso", FT_BOOL, false, PLFLAG_ISO)
    setPrologFlag(
        gd,
        "arch",
        FT_ATOM | FF_READONLY,
        string(Sys.ARCH, "-", lowercase(string(Sys.KERNEL)))
    )
    setPrologFlag(
        gd,
        "file_name_case_handling",
        FT_ATOM | FF_READONLY,
        _current_file_name_case_handling(gd)
    )
    setPrologFlag(gd, "path_max", FT_INTEGER | FF_READONLY, 4096)
    setPrologFlag(gd, "version", FT_INTEGER | FF_READONLY, PLVERSION)
    setPrologFlag(gd, "dialect", FT_ATOM | FF_READONLY, "swi")
    # pl-prologflag.c:2548-2549 defines `home` where `systemDefaults.home` is known; the kernel's own is its
    # package directory (design D5, audit D-0151 item 6), pointed at the home tree of R2 LB4 when that lands
    setPrologFlag(gd, "home", FT_ATOM | FF_READONLY, dirname(dirname(@__DIR__)))
    setPrologFlag(
        gd, "executable", FT_ATOM | FF_READONLY, joinpath(Sys.BINDIR, Base.julia_exename())
    )
    setPrologFlag(gd, "pid", FT_INTEGER | FF_READONLY, Int(Libc.getpid()))
    setPrologFlag(gd, "optimise", FT_BOOL, false, PLFLAG_OPTIMISE)
    setPrologFlag(gd, "optimise_unify", FT_BOOL, true, PLFLAG_OPTIMISE_UNIFY)
    setPrologFlag(
        gd, "generate_debug_info", FT_BOOL,
        (gd.prolog_flag.mask & prologFlagMask(PLFLAG_DEBUGINFO)) != 0, PLFLAG_DEBUGINFO
    )
    setPrologFlag(gd, "protect_static_code", FT_BOOL, false, PLFLAG_PROTECT_STATIC_CODE)
    setPrologFlag(gd, "last_call_optimisation", FT_BOOL, true, PLFLAG_LASTCALL)
    setPrologFlag(gd, "vmi_builtin", FT_BOOL, true, PLFLAG_VMI_BUILTIN)
    setPrologFlag(
        gd, "warn_override_implicit_import", FT_BOOL, true,
        PLFLAG_WARN_OVERRIDE_IMPLICIT_IMPORT
    )
    setPrologFlag(gd, "large_files", FT_BOOL | FF_READONLY, true, 0)
    setPrologFlag(gd, "unload_foreign_libraries", FT_BOOL, false, 0)
    setPrologFlag(gd, "gc", FT_BOOL, true, PLFLAG_GC)
    setPrologFlag(gd, "trace_gc", FT_BOOL, false, PLFLAG_TRACE_GC)
    setPrologFlag(gd, "agc_margin", FT_INTEGER, 10000)
    setPrologFlag(gd, "agc_close_streams", FT_BOOL, false, PLFLAG_AGC_CLOSE_STREAMS)
    setPrologFlag(gd, "table_space", FT_INTEGER, 1 << 30)
    setPrologFlag(gd, "table_compile_threshold", FT_INTEGER, 32)
    setPrologFlag(gd, "table_drop_intermediate", FT_INTEGER, 0)
    setPrologFlag(gd, "stack_limit", FT_INTEGER, STACK_LIMIT_DEFAULT * 8)
    setPrologFlag(gd, "address_bits", FT_INTEGER | FF_READONLY, 64)
    setPrologFlag(gd, "threads", FT_BOOL | FF_READONLY, false, 0)
    setPrologFlag(gd, "gc_thread", FT_BOOL | FF_READONLY, false, PLFLAG_GCTHREAD)
    setPrologFlag(gd, "debug_on_error", FT_BOOL, true, PLFLAG_DEBUG_ON_ERROR)
    setPrologFlag(gd, "report_error", FT_BOOL, true, PLFLAG_REPORT_ERROR)
    setPrologFlag(gd, "on_error", FT_ATOM, "print")
    setPrologFlag(gd, "on_warning", FT_ATOM, "print")
    setPrologFlag(gd, "break_level", FT_INTEGER | FF_READONLY, 0)
    setPrologFlag(gd, "user_flags", FT_ATOM, "silent")
    setPrologFlag(gd, "editor", FT_ATOM, "default")
    setPrologFlag(gd, "debugger_show_context", FT_BOOL, false, 0)
    setPrologFlag(gd, "autoload", FT_ATOM, "true")
    gd.prolog_flag.mask |= prologFlagMask(PLFLAG_AUTOLOAD)  # setPrologFlagMask(PLFLAG_AUTOLOAD)
    setPrologFlag(gd, "max_tagged_integer", FT_INT64 | FF_READONLY, PLMAXTAGGEDINT)
    setPrologFlag(gd, "min_tagged_integer", FT_INT64 | FF_READONLY, PLMINTAGGEDINT)
    setPrologFlag(gd, "bounded", FT_BOOL | FF_READONLY, false, 0)
    setPrologFlag(gd, "rationals", FT_BOOL | FF_READONLY, true, 0)
    setPrologFlag(gd, "prefer_rationals", FT_BOOL, false, PLFLAG_RATIONAL)
    setPrologFlag(
        gd, "rational_syntax", FT_ATOM,
        O_RATIONAL_SYNTAX == RAT_NATURAL ? "natural" : "compatibility"
    )
    setPrologFlag(gd, "gmp_version", FT_INTEGER | FF_READONLY, Base.GMP.version().major)
    setPrologFlag(gd, "integer_rounding_function", FT_ATOM | FF_READONLY, "toward_zero")
    setPrologFlag(gd, "max_char_code", FT_INTEGER | FF_READONLY, 0x10ffff)
    setPrologFlag(
        gd, "unicode_syntax_version", FT_ATOM | FF_READONLY, UNICODE_SYNTAX_VERSION
    )
    setPrologFlag(gd, "max_arity", FT_ATOM | FF_READONLY, "unbounded")
    setPrologFlag(gd, "max_procedure_arity", FT_INTEGER | FF_READONLY, MAXARITY)
    setPrologFlag(gd, "colon_sets_calling_context", FT_BOOL | FF_READONLY, true, 0)
    setPrologFlag(gd, "character_escapes", FT_BOOL, true, PLFLAG_CHARESCAPE)
    setPrologFlag(gd, "character_escapes_unicode", FT_BOOL, true, PLFLAG_CHARESCAPE_UNICODE)
    setPrologFlag(gd, "var_prefix", FT_ATOM, "false")
    setPrologFlag(gd, "unicode_atoms", FT_ATOM, "accept")
    setPrologFlag(gd, "atom_normalize_hook", FT_BOOL, false, 0)
    setPrologFlag(gd, "char_conversion", FT_BOOL, false, PLFLAG_CHARCONVERSION)
    setPrologFlag(gd, "quasi_quotations", FT_BOOL, true, PLFLAG_QUASI_QUOTES)
    setPrologFlag(gd, "write_attributes", FT_ATOM, "ignore")
    setPrologFlag(gd, "stream_type_check", FT_ATOM, "loose")
    setPrologFlag(gd, "occurs_check", FT_ATOM, "false")
    setPrologFlag(gd, "incomparable", FT_ATOM, "arbitrary")
    setPrologFlag(gd, "shift_check", FT_BOOL, false, PLFLAG_SHIFT_CHECK)
    setPrologFlag(gd, "access_level", FT_ATOM, "user")
    setPrologFlag(gd, "double_quotes", FT_ATOM, "string")
    setPrologFlag(gd, "back_quotes", FT_ATOM, "codes")
    setPrologFlag(gd, "var_tag", FT_ATOM, "dict")
    setPrologFlag(gd, "portable_vmi", FT_BOOL, true, PLFLAG_PORTABLE_VMI)
    setPrologFlag(gd, "traditional", FT_BOOL | FF_READONLY, false, 0)
    setPrologFlag(gd, "unknown", FT_ATOM, "error")
    setPrologFlag(gd, "unknown_option", FT_ATOM, "ignore")
    setPrologFlag(gd, "debug", FT_BOOL, false, 0)
    setPrologFlag(gd, "debug_on_interrupt", FT_BOOL, false, PLFLAG_DEBUG_ON_INTERRUPT)
    setPrologFlag(gd, "verbose", FT_ATOM | FF_KEEP, "normal")
    setPrologFlag(gd, "verbose_load", FT_ATOM, "silent")
    setPrologFlag(gd, "verbose_autoload", FT_BOOL, false, 0)
    setPrologFlag(gd, "verbose_file_search", FT_BOOL, false, 0)
    setPrologFlag(gd, "source", FT_BOOL, false, 0)
    setPrologFlag(gd, "source_search_working_directory", FT_BOOL, true, 0)
    setPrologFlag(gd, "sandboxed_load", FT_BOOL, false, 0)
    setPrologFlag(
        gd, "allow_variable_name_as_functor", FT_BOOL, false, ALLOW_VARNAME_FUNCTOR
    )
    setPrologFlag(gd, "allow_dot_in_atom", FT_BOOL, false, PLFLAG_DOT_IN_ATOM)
    setPrologFlag(gd, "toplevel_var_size", FT_INTEGER, 1000)
    setPrologFlag(gd, "toplevel_print_anon", FT_BOOL, false, 0)
    setPrologFlag(gd, "toplevel_name_variables", FT_BOOL, true, 0)
    setPrologFlag(gd, "toplevel_prompt", FT_ATOM, "~m~d~l~! ?- ")
    setPrologFlag(gd, "theme", FT_ATOM | FF_SHARED, "default")
    setPrologFlag(gd, "file_name_variables", FT_BOOL, false, PLFLAG_FILEVARS)
    setPrologFlag(gd, "fileerrors", FT_BOOL, true, PLFLAG_FILEERRORS)
    setPrologFlag(gd, "determinism_error", FT_ATOM, "error")
    setPrologFlag(gd, "unix", FT_BOOL | FF_READONLY, true, 0)
    setPrologFlag(gd, "linux", FT_BOOL | FF_READONLY, true, 0)
    setPrologFlag(gd, "xdg", FT_BOOL | FF_READONLY, true, 0)
    setPrologFlag(gd, "encoding", FT_ATOM, "utf8")
    setPrologFlag(gd, "epilog", FT_BOOL, false, PLFLAG_EPILOG)
    setPrologFlag(gd, "tty_control", FT_BOOL, false, PLFLAG_TTY_CONTROL)
    setPrologFlag(
        gd, "signals", FT_BOOL | FF_READONLY,
        (gd.prolog_flag.mask & prologFlagMask(PLFLAG_SIGNALS)) != 0, PLFLAG_SIGNALS
    )
    setPrologFlag(gd, "packs", FT_BOOL, true, 0)
    setPrologFlag(gd, "heartbeat", FT_INTEGER, 0)
    setPrologFlag(gd, "halt_grace_time", FT_FLOAT, 1.0)
    setPrologFlag(gd, "compiled_at", FT_ATOM | FF_READONLY, COMPILED_AT)
    setPrologFlag(
        gd, "error_ambiguous_stream_pair", FT_BOOL, false,
        PLFLAG_ERROR_AMBIGUOUS_STREAM_PAIR
    )
    setPrologFlag(gd, "mitigate_spectre", FT_BOOL, false, PLFLAG_MITIGATE_SPECTRE)
    setPrologFlag(gd, "posix_shell", FT_ATOM, "/bin/sh")
    setPrologFlag(gd, "path_sep", FT_ATOM | FF_READONLY, ":")
    setPrologFlag(gd, "dir_sep", FT_ATOM | FF_READONLY, "/")
    setPrologFlag(gd, "table_incremental", FT_BOOL, false, PLFLAG_TABLE_INCREMENTAL)
    setPrologFlag(gd, "table_subsumptive", FT_BOOL, false, 0)
    setPrologFlag(gd, "table_shared", FT_BOOL, false, PLFLAG_TABLE_SHARED)

    setPrologFlag(gd, "tmp_dir", FT_ATOM, get(ENV, "TMP", "/tmp"))      # setTmpDirPrologFlag
    setPrologFlag(gd, "timezone", FT_INTEGER | FF_READONLY, _timezone_seconds())
    setPrologFlag(gd, "cpu_count", FT_INTEGER, Sys.CPU_THREADS)         # setOSPrologFlags

    # the flags that hold a term: records, made in a local data of their own
    ld = PL_local_data{T}(gd)
    if _holds_payload(T, Int64)                         # version_data holds integers
        t = PL_new_term_ref(ld)
        putSlotValue!(
            ld, t + 1,
            mk_expr(
                T,
                T[
                    mk_sym(T, :swi), mk_gnd(T, 10), mk_gnd(T, 1), mk_gnd(T, 19), mk_nil(T)
                ]
            )
        )
        setPrologFlag(gd, ld, "version_data", FT_TERM | FF_READONLY, t)
    end
    _set_argv_prolog_flag!(gd, ld, "os_argv", ["swipl"])
    _set_argv_prolog_flag!(gd, ld, "argv", ["swipl"])

    _init_tabling_flags!(gd)                            # pl-setup.c:154
    initArith!(gd)                                      # pl-setup.c:168
    return nothing
end

# PORT: pl-prologflag.c BeginPredDefs as PL_predicates_from_prologflag
# DIVERGES: the entries of the predicates the kernel has ported, in upstream's order; `PRED_DEF` ors in
# `PL_FA_VARARGS`.
"pl-prologflag.c's registration table (`BeginPredDefs(prologflag)`): the ported entries."
const PL_predicates_from_prologflag = (
    PL_extension(
        "current_prolog_flag", 2, pl_current_prolog_flag2_va,
        PL_FA_ISO | PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "\$current_prolog_flag", 5, pl_dcurrent_prolog_flag5_va,
        PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    )
)
