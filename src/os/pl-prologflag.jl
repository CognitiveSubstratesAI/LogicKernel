# UPSTREAM: swipl-devel src/os/pl-prologflag.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/os/pl-prologflag.h @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-fli.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-incl.h @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-read.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-tabling.c @ cbf4e1896275
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
# `PL_get_prolog_flag`. Since R2 F1b: the write side — `set_prolog_flag/2`, `create_prolog_flag/3`,
# `set_flag_value` and the value setters; since R2 F2 `push_prolog_flag/2` and `pop_prolog_flag/1`. The
# flags whose side effect lives in a file of a later step are refused by name (design D4). Left out as well: the flags'
# threading (`LD->prolog_flag.table`, `FF_SHARED`'s mutex, `PL_LOCK(L_PLFLAG)`, `unify_shared_prolog_flag`:
# the kernel is upstream's single-threaded build, design D1: one table, `threads` false and read-only).
#
# WHICH FLAGS EXIST (design D4, D5). `initPrologFlags!` defines the flags of upstream's `initPrologFlags`
# for a Linux build without threads, at upstream's default; the machine-dependent ones (`pid`, `executable`,
# `arch`, `tmp_dir`, `cpu_count`, `path_max`, `address_bits`, `timezone`, `version`, `argv`, …) take the
# kernel's own values. NOT DEFINED, each a family the kernel does not have (the pinned list in
# test/core_lang/test_prolog_flag_swipl.jl names every flag swipl has and the kernel has not, with its
# family): the C toolchain and shared objects (`c_cc`, `c_cxx`, `c_libs`, `c_libplso`, `c_ldflags`,
# `c_cflags`, `open_shared_object`, `shared_object_search_path`,
# `executable_format`, `build_type`, `cmake_build_type`), pipes (`pipe`),
# threads and engines (`engines`, `system_thread_id`, `shared_table_space`), and every flag that Prolog code of
# boot/ and library/ creates (`create_prolog_flag/3`, R2 F1b).
#
# A BUILD-FEATURE FLAG answers as upstream's build WITHOUT that feature (audit D-0151 item 6), at the pin
# (pl-prologflag.c): `open_shared_object`, `shared_object_extension`, `shared_object_search_path` and the
# `c_*` flags are inside `#ifdef O_DYNAMIC_EXTENSIONS` (:2593-2606, no `#else`); `pipe` inside
# `#ifdef HAVE_POPEN` (:2608-2610, no `#else`); `shared_table_space` (:2589-2591), `system_thread_id` and
# the threaded `threads`/`gc_thread` (:2611-2619) inside `#ifdef O_PLMT`, whose `#else` (:2620-2622) defines
# `threads` and `gc_thread` read-only false; `engines` in that `#else` only `#ifdef O_ENGINES` (:2623-2625).
# All are therefore undefined, except those two. Since R2 F1c (audit D-0370 item 5) `shared_object_extension`, `libswipl` and `version_git`
# are DEFINED, as upstream sets them (the boot reads them: boot/init.pl:1406, boot/messages.pl:1275): the rest of the `O_DYNAMIC_EXTENSIONS`
# block waits for F8. Upstream's C leaves `xref` to the loader: `$set_no_xref` (boot/init.pl:3062-3067) creates it by
# `set_prolog_flag(xref, false)` (`user_flags` silent), and the kernel does the same: the flag appears when the loader first runs it. `home` is DEFINED (the kernel's own value, :2548-2549).
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
# (`setVarPrefix`, `set_prolog_flag(var_prefix, V)`) is F1b's. `var_tag` is the module's too, as upstream's: the
# VARTAG_* bits of `module_t.flags` (`setVarTagFlag`, `getVarTagFlag`; the reader's `build_dict` takes them from
# the read data's flags); its `set_prolog_flag/2` arm (:1383) is F1b's, with the rest of the write side.
# The flags whose value upstream reads from the debugger (`debug`, `debugger_show_context`), the toplevel
# (`break_level`) or the local data (`access_level`) read what the kernel has: the debugger's status fields of the local data
# (since R2 F1c; the tracer itself is DBG1's) and no toplevel,
# `access_level` the local data's (since R2 LB2: `user` unless `setAccessLevel!` set `system`).
# Since R2 F1b the compiler, the VM and write read the Boolean flags from the mask (`truePrologFlag`), as upstream:
# the five stand-in fields of the local data and `_prolog_flag_bit` are deleted; the flag `determinism_error` is read
# from the table (`determinism_error_flag`).

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

# PORT: pl-prologflag.c setVarTagFlag
# DIVERGES: as `setBackQuotes`.
"`flags` with the VARTAG_* bits the atom `a` names (`attvar`, `#`, `dict`, `error`, `warning`), or `nothing` after `domain_error(var_tag, A)` (pl-prologflag.c)."
function setVarTagFlag(
    ld::PL_local_data{T}, a::T, flags::UInt32
)::Union{Nothing, UInt32} where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :attvar))
        f = VARTAG_ATTVAR
    elseif k == sym_key(mk_sym(T, Symbol("#")))             # ATOM_dyndict
        f = VARTAG_DYNDICT
    elseif k == sym_key(mk_sym(T, :dict))                   # ATOM_dict_txt
        f = VARTAG_DICT
    elseif k == sym_key(mk_sym(T, :error))
        f = VARTAG_ERROR
    elseif k == sym_key(mk_sym(T, :warning))
        f = VARTAG_WARNING
    else
        value = PL_new_term_ref(ld)
        setSlotValue!(ld, value + 1, a)                     # PL_put_atom(value, a)
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :var_tag), value)
        return nothing
    end

    flags &= ~VARTAG_MASK
    flags |= f

    return flags
end

# PORT: pl-prologflag.c getVarTagFlag
# DIVERGES: the atom is the term type's symbol; the VARTAG_* bits are always one of the five values (the
# `assert(0)` default is a refusal here).
"The atom naming the VARTAG_* bits of `flags` (pl-prologflag.c): `dict`, `#`, `attvar`, `error` or `warning`."
function getVarTagFlag(::Type{T}, flags::UInt32)::T where {T}
    m = flags & VARTAG_MASK
    m == VARTAG_DICT && return mk_sym(T, :dict)             # ATOM_dict_txt
    m == VARTAG_DYNDICT && return mk_sym(T, Symbol("#"))    # ATOM_dyndict
    m == VARTAG_ATTVAR && return mk_sym(T, :attvar)
    m == VARTAG_ERROR && return mk_sym(T, :error)
    m == VARTAG_WARNING && return mk_sym(T, :warning)
    error("getVarTagFlag: the VARTAG bits $(m) name no mode")   # assert(0)
end

# ── the mask (pl-incl.h) ─────────────────────────────────────────────────────────────────────────
# PORT: pl-incl.h truePrologFlag
# DIVERGES: the local data is an argument (upstream's `LD`); the mask is one 64-bit word (see src/pl-incl.jl).
"Whether the bit `flag` (a `PLFLAG_*`) of the local data's mask is set (pl-incl.h)."
truePrologFlag(ld::PL_local_data, flag::Integer)::Bool =
    (ld.prolog_flag_mask & prologFlagMask(flag)) != 0

# PORT: pl-incl.h setPrologFlagMask
# DIVERGES: the local data is an argument (upstream's `LD`).
"Set the bit `flag` (a `PLFLAG_*`) of the local data's mask (pl-incl.h)."
function setPrologFlagMask!(ld::PL_local_data, flag::Integer)::Nothing
    ld.prolog_flag_mask |= prologFlagMask(flag)
    return nothing
end

# PORT: pl-incl.h clearPrologFlagMask
# DIVERGES: as `setPrologFlagMask!`.
"Clear the bit `flag` (a `PLFLAG_*`) of the local data's mask (pl-incl.h)."
function clearPrologFlagMask!(ld::PL_local_data, flag::Integer)::Nothing
    ld.prolog_flag_mask &= ~prologFlagMask(flag)
    return nothing
end

# PORT: pl-incl.h RUN_MODE_NORMAL
"The mask bits of the normal run mode: `PLFLAG_LASTCALL` and `PLFLAG_VMI_BUILTIN` (pl-incl.h); debug mode clears them."
const RUN_MODE_NORMAL = prologFlagMask(PLFLAG_LASTCALL) | prologFlagMask(PLFLAG_VMI_BUILTIN)

# PORT: pl-incl.h setPrologRunMode
# DIVERGES: the local data is an argument (upstream's `LD`); the mask is one word, so the run-mode bits are in it, not in the word of `PLFLAG_LASTCALL`.
"Set the run-mode bits `mask` of the local data's mask (pl-incl.h)."
function setPrologRunMode!(ld::PL_local_data, mask::UInt64)::Nothing
    ld.prolog_flag_mask |= mask
    return nothing
end

# PORT: pl-incl.h clearPrologRunMode
# DIVERGES: as `setPrologRunMode!`.
"Clear the run-mode bits `mask` of the local data's mask (pl-incl.h)."
function clearPrologRunMode!(ld::PL_local_data, mask::UInt64)::Nothing
    ld.prolog_flag_mask &= ~mask
    return nothing
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
# the local data's debugger status (`debugstatus.debugging`, `.showContext`, pl-prologflag.c:2113-2116; since R2 F1c), `break_level` fails (no toplevel: `currentBreakLevel() < 0`), `access_level` is
# the local data's (`user` by default); `stack_limit` is the local stack's limit in bytes (the kernel counts words). The shared-flag
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
    elseif name == "var_tag"
        return PL_unify_atom(ld, val, getVarTagFlag(T, mdl.flags))
    elseif name == "unknown"
        u = getUnknownModule(gd, mdl)
        u == UNKNOWN_ERROR && return PL_unify_atom(ld, val, mk_sym(T, :error))
        u == UNKNOWN_WARNING && return PL_unify_atom(ld, val, mk_sym(T, :warning))
        u == UNKNOWN_FAIL && return PL_unify_atom(ld, val, mk_sym(T, :fail))
        return false
    elseif name == "debug"
        return PL_unify_bool_ex(ld, val, ld.debugstatus_debugging)
    elseif name == "debugger_show_context"
        return PL_unify_bool_ex(ld, val, ld.debugstatus_showContext)
    elseif name == "break_level"
        return false
    elseif name == "access_level"
        # PL_unify_atom(val, accessLevel()): `system` in system mode, else `user` (pl-prologflag.c:2011; R2 LB2)
        return PL_unify_atom(ld, val, mk_sym(T, SYSTEM_MODE(ld) ? :system : :user))
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
            return PL_unify_bool_ex(ld, val, truePrologFlag(ld, f.index))
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

# ORIGINAL: `PL_current_prolog_flag(name, type)` above returns `Union{Nothing,T,Bool,Int64,Float64}` by the Symbol
# `type`; the `:atom` form the kernel's own callers use is this method, typed, so no caller dispatches at run time (D-0282).
"The atom value of the flag `name`, or `nothing` if there is no such flag or it is not an atom flag (`PL_current_prolog_flag(..., PL_ATOM, &a)`)."
function current_prolog_flag_atom(
    gd::PL_global_data{T}, name::T
)::Union{Nothing, T} where {T}
    f = lookupFlag(gd, _atom_word!(gd.atoms, gd.atom_symbols, name))
    f === nothing && return nothing
    (f.flags & FT_MASK) == FT_ATOM && return f.a
    return nothing
end

# ORIGINAL: the callers of upstream (`det_goal_error`, `determinism_error`) start from `atom_t a = ATOM_error`
# and call `PL_current_prolog_flag(ATOM_determinism_error, PL_ATOM, &a)`; the kernel's callers compare symbols.
"The flag `determinism_error` as `:error`, `:warning` or `:silent`; `:error` if the flag has no atom value (pl-comp.c, pl-wam.c)."
function determinism_error_flag(ld::PL_local_data{T})::Symbol where {T}
    gd = ld.GD
    gd === nothing && return :error                    # (no database: upstream's `a = ATOM_error`)
    a = current_prolog_flag_atom(gd, mk_sym(T, :determinism_error))
    a === nothing && return :error
    k = sym_key(a)
    k == sym_key(mk_sym(T, :silent)) && return :silent
    k == sym_key(mk_sym(T, :warning)) && return :warning
    return :error
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

# ── setting a flag: the value setters (pl-prologflag.c), R2 F1b ──────────────────────────────────
# ORIGINAL (design D4): a flag whose upstream side effect the kernel has not is DEFINED at upstream's default
# (`initPrologFlags!`) and SETTING it raises `NotPortedError` naming the side effect: loud and grep-able, and
# no answer swipl gives is changed. The flags (`debug` and `debugger_show_context` are accepted since R2 F1c): `tty_control`, `debug_on_interrupt`,
# `stack_limit` (set_stack_limit), `table_space`, `table_compile_threshold`, `table_drop_intermediate`,
# `table_monotonic`, `agc_margin`, `string_stack_tripwire`, `heartbeat`, `encoding`, `unicode_atoms`,
# `theme`, `incomparable` (`LD->prolog_flag.incomparable_error`), `var_tag`
# (the VARTAG_* bits of `m->flags`, which the kernel's `module_t` has not), the ci_* and tabling restraint flags (pseudo-flags of pl-index.c and pl-tabling.c, whose state is
# constants here), the arithmetic flags (`set_arith_flag`, pl-arith.c) and `file_name_case_handling`.
# `on_error`/`on_warning` are checked and stored (the `halt`/`status` actions belong to the toplevel).
"Refuse setting the flag `key`: its upstream side effect `effect` is not ported (design D4; R2 F1b)."
function _flag_not_ported(key::T, effect::String) where {T}
    throw(NotPortedError{T}(key, effect, "R2 F1b"))
end

# The term reference holding the atom `a` (`PL_put_atom` into a fresh reference), for an error's culprit.
function _flag_atom_ref(ld::PL_local_data{T}, a::T)::term_t where {T}
    t = PL_new_term_ref(ld)
    PL_put_atom(ld, t, a)
    return t
end

# PORT: pl-prologflag.c setRationalSyntax
# DIVERGES: as `setBackQuotes`.
"`flags` with the rational syntax the atom `a` names (`natural`, `compatibility`), or `nothing` after `domain_error(rational_syntax, A)` (pl-prologflag.c)."
function setRationalSyntax(
    ld::PL_local_data{T}, a::T, flags::UInt32
)::Union{Nothing, UInt32} where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :natural))
        f = RAT_NATURAL
    elseif k == sym_key(mk_sym(T, :compatibility))
        f = RAT_COMPAT
    else
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :rational_syntax), _flag_atom_ref(ld, a))
        return nothing
    end

    flags &= ~RAT_MASK
    flags |= f

    return flags
end

# PORT: pl-read.c var_prefix_code
# DIVERGES: the local data `ld` is an argument that binds the term type `T` (`a` may be a subtype of it).
"The code of the character `var_prefix` names — `false` 0, `true` `_`, a one-character atom that is `_` or an ASCII symbol character other than `.` and `` ` `` — or -1 (pl-read.c)."
function var_prefix_code(::PL_local_data{T}, a::T)::Int where {T}
    k = sym_key(a)
    k == sym_key(mk_sym(T, Symbol("false"))) && return 0
    k == sym_key(mk_sym(T, Symbol("true"))) && return Int('_')
    txt = sym_text(a)
    if length(txt) == 1
        c = Int(first(txt))
        if c == Int('_') || (c < 0x80 && PlSymbolW(c) && c != Int('.') && c != Int('`'))
            return c
        end
    end
    return -1
end

# PORT: pl-read.c get_var_prefix_ex
# DIVERGES: the code is returned, `nothing` after the error is raised.
"The `var_prefix` code the term `t` holds, or `nothing` after `type_error`/`domain_error(var_prefix, T)` (pl-read.c)."
function get_var_prefix_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    a = PL_get_atom_ex(ld, t)
    a === nothing && return nothing
    c = var_prefix_code(ld, a)
    if c < 0
        PL_domain_error(ld, "var_prefix", t)
        return nothing
    end
    return c
end

# PORT: pl-prologflag.c setVarPrefix
# DIVERGES: returns the normalised atom (`true` is `_`), or `nothing` after the error is raised, where upstream
# writes it through `a`.
"Set the `var_prefix` of the module `m` from the term `value` (an atom, `true` an alias for `_`); the atom the flag then holds, or `nothing` (pl-prologflag.c)."
function setVarPrefix(
    ld::PL_local_data{T}, value::term_t, m::module_t{T}
)::Union{Nothing, T} where {T}
    c = get_var_prefix_ex(ld, value)
    c === nothing && return nothing
    m.var_prefix = c
    return c != 0 ? mk_sym(T, Symbol(Char(c))) : mk_sym(T, Symbol("false"))
end

# PORT: pl-prologflag.c setUnknown
# DIVERGES: the database is an argument.
"Set the `unknown` flag of the module `m` from the atom `a` (`error`, `warning`, `fail`); in `user` and `system` a value other than `error` warns, and in `system` it is refused outside system mode (pl-prologflag.c)."
function setUnknown(
    gd::PL_global_data{T}, ld::PL_local_data{T}, value::term_t, a::T, m::module_t{T}
)::Bool where {T}
    flags = m.flags & ~UNKNOWN_MASK
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :error))
        flags |= UNKNOWN_ERROR
    elseif k == sym_key(mk_sym(T, :warning))
        flags |= UNKNOWN_WARNING
    elseif k == sym_key(mk_sym(T, :fail))
        flags |= UNKNOWN_FAIL
    else
        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :unknown), value)
    end

    if (flags & UNKNOWN_ERROR) == 0 &&
        (m.index == MODULE_user(gd).index || m.index == MODULE_system(gd).index)
        if m.index == MODULE_system(gd).index && !SYSTEM_MODE(ld)
            key = _flag_atom_ref(ld, mk_sym(T, :unknown))
            return PL_error(
                ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :modify), mk_sym(T, :flag), key
            )
        end

        if !SYSTEM_MODE(ld)
            msg = _flag_atom_ref(ld, mk_sym(T, :unknown_in_module_user))
            printMessage(ld, :warning, msg) || return false
        end
    end

    m.flags = flags

    return true
end

# PORT: pl-prologflag.c setUnknownOption
"Set the `unknown_option` flag from the atom `a` (`ignore`, `warning`, `error`) (pl-prologflag.c)."
function setUnknownOption(ld::PL_local_data{T}, value::term_t, a::T)::Bool where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :ignore))
        ld.prolog_flag_unknown_option = OPT_UNKNOWN_IGNORE
    elseif k == sym_key(mk_sym(T, :warning))
        ld.prolog_flag_unknown_option = OPT_UNKNOWN_WARNING
    elseif k == sym_key(mk_sym(T, :error))
        ld.prolog_flag_unknown_option = OPT_UNKNOWN_ERROR
    else
        return PL_domain_error(ld, "unknown_option", value)
    end
    return true
end

# PORT: pl-prologflag.c checkOnError
"Whether the atom `a` is a valid action of the flag `key` (`on_error`, `on_warning`): `print`, `halt` or `status`; else `domain_error(Key, Value)` (pl-prologflag.c)."
function checkOnError(ld::PL_local_data{T}, value::term_t, a::T, key::T)::Bool where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :print)) ||
        k == sym_key(mk_sym(T, :halt)) ||
        k == sym_key(mk_sym(T, :status))
        return true
    end
    return PL_error(ld, ERR_DOMAIN, key, value)
end

# PORT: pl-prologflag.c setWriteAttributes
"Set the `write_attributes` flag from the atom `a` (`ignore`, `dots`, `write`, `portray`) (pl-prologflag.c)."
function setWriteAttributes(ld::PL_local_data{T}, a::T)::Bool where {T}
    mask = writeAttributeMask(ld, a)
    if mask != 0
        ld.prolog_flag_write_attributes = mask
        return true
    end
    return PL_error(ld, ERR_DOMAIN, mk_sym(T, :write_attributes), _flag_atom_ref(ld, a))
end

# PORT: pl-prologflag.c setAccessLevelFromAtom
# DIVERGES: pl-init.c's `getAccessLevelMask` is inlined: `user` and `system`.
"Set the engine's access level from the atom `a` (`user`, `system`) (pl-prologflag.c)."
function setAccessLevelFromAtom(ld::PL_local_data{T}, a::T)::Bool where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :user))
        setAccessLevel!(ld, ACCESS_LEVEL_USER)
    elseif k == sym_key(mk_sym(T, :system))
        setAccessLevel!(ld, ACCESS_LEVEL_SYSTEM)
    else
        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :access_level), _flag_atom_ref(ld, a))
    end
    return true
end

# PORT: pl-prologflag.c getOccursCheckMask
# DIVERGES: the local data `ld` is an argument that binds the term type `T` (`a` may be a subtype of it).
"The `occurs_check_t` the atom `a` names (`false`, `true`, `error`), or `nothing` (pl-prologflag.c)."
function getOccursCheckMask(
    ::PL_local_data{T}, a::T
)::Union{Nothing, occurs_check_t} where {T}
    k = sym_key(a)
    k == sym_key(mk_sym(T, Symbol("false"))) && return OCCURS_CHECK_FALSE
    k == sym_key(mk_sym(T, Symbol("true"))) && return OCCURS_CHECK_TRUE
    k == sym_key(mk_sym(T, :error)) && return OCCURS_CHECK_ERROR
    return nothing
end

# PORT: pl-prologflag.c setOccursCheck
# DIVERGES: no `updateAlerted`: the kernel's unify reads the field directly.
"Set the `occurs_check` flag from the atom `a` (pl-prologflag.c)."
function setOccursCheck(ld::PL_local_data{T}, a::T)::Bool where {T}
    v = getOccursCheckMask(ld, a)
    if v !== nothing
        ld.prolog_flag_occurs_check = v
        return true
    end
    return PL_error(ld, ERR_DOMAIN, mk_sym(T, :occurs_check), _flag_atom_ref(ld, a))
end

# PORT: pl-prologflag.c setStreamTypeCheck
"Set the `stream_type_check` flag from the atom `a` (`false`, `loose`, `true`) (pl-prologflag.c)."
function setStreamTypeCheck(ld::PL_local_data{T}, a::T)::Bool where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, Symbol("false")))
        check = ST_FALSE
    elseif k == sym_key(mk_sym(T, :loose))
        check = ST_LOOSE
    elseif k == sym_key(mk_sym(T, Symbol("true")))
        check = ST_TRUE
    else
        return PL_error(
            ld, ERR_DOMAIN, mk_sym(T, :stream_type_check), _flag_atom_ref(ld, a)
        )
    end
    ld.IO_stream_type_check = check
    return true
end

# PORT: pl-prologflag.c setAutoload
# DIVERGES: the local data is an argument (upstream's `GET_LD`). Only `false` and not-`false` matter to the C side
# (the mask bit `PLFLAG_AUTOLOAD`); the Prolog side (`autoload_in/3`, boot/autoload.pl) tells `explicit`, `user` and
# `user_or_explicit` from `true`. Upstream's setter alone checks the domain (AUTOLOAD1 ruling Q7).
"Set the mask bit `PLFLAG_AUTOLOAD` from the atom `a` (`false` clears it; `explicit`, `true`, `user`, `user_or_explicit` set it), else `domain_error(autoload, A)` (pl-prologflag.c)."
function setAutoload(ld::PL_local_data{T}, a::T)::Bool where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, Symbol("false")))
        clearPrologFlagMask!(ld, PLFLAG_AUTOLOAD)
    elseif k == sym_key(mk_sym(T, :explicit)) ||
        k == sym_key(mk_sym(T, Symbol("true"))) ||
        k == sym_key(mk_sym(T, :user)) ||
        k == sym_key(mk_sym(T, :user_or_explicit))
        setPrologFlagMask!(ld, PLFLAG_AUTOLOAD)
    else
        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :autoload), _flag_atom_ref(ld, a))
    end
    return true
end

# PORT: pl-prologflag.c propagateAutoload
# DIVERGES: the database and the local data are arguments; `PL_predicate("set_autoload", 1, "$autoload")` is
# `lookupProcedure` in `lookupModule`'s module (both create what is not there), looked up on each call. Before
# boot/autoload.pl is loaded `$autoload:set_autoload/1` has no clauses, so a call outside the boot session raises
# the existence error upstream raises too (`PL_Q_PASS_EXCEPTION`).
# DIVERGES (a missing seam with a deferred owner; owner AUTOLOAD1 A5): upstream skips this call only while booting
# (`!GD->bootsession`, pl-prologflag.c:990 at the pin) and swipl answers the rows of a booted system, where the call
# runs `set_autoload/1` (boot/autoload.pl:945-946, first clause `current_prolog_flag(autoload, FlagValue)`, which binds
# an unbound value: `set_prolog_flag(autoload, X)` answers `true`). The kernel's rows run with `gd.bootsession` set (no
# booted autoload.pl), so the same call raises `instantiation_error` in `PL_get_atom_ex`. Removal: A5 (the hook arrives
# with boot/autoload.pl loading on the boot path); row af08 is kernel-documented until then and flips to swipl-compared at A5.
"Tell the Prolog side that `autoload` is set to the term `val`: `\$autoload:set_autoload(Val)`, not in the boot session (pl-prologflag.c)."
function propagateAutoload(
    gd::PL_global_data{T}, ld::PL_local_data{T}, val::term_t
)::Bool where {T}
    gd.bootsession && return true
    pred = lookupProcedure(
        mk_sym(T, :set_autoload), 1, lookupModule(gd, mk_sym(T, Symbol("\$autoload")))
    )
    av = PL_new_term_refs(ld, 2)
    return PL_put_term(ld, av, val) &&
           PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, pred, av)
end

# ── changing a flag: oneof, keep_flag, new_prolog_flag, set_flag_value (pl-prologflag.c), R2 F1b ─────
# ORIGINAL (pl-prologflag.c `PSEUDO_FLAG`): the value `set_prolog_flag_unlocked` answers for a flag that lives
# outside the table (the arithmetic, clause-indexing and tabling-restraint flags).
"The marker `set_prolog_flag_unlocked` returns for a pseudo flag (pl-prologflag.c `PSEUDO_FLAG`)."
struct PseudoFlag end
const PSEUDO_FLAG = PseudoFlag()

# PORT: pl-prologflag.c FF_COPY_FLAGS
"The attributes a flag created from another's definition copies (pl-prologflag.c `FF_COPY_FLAGS`)."
const FF_COPY_FLAGS = FF_READONLY | FF_WARN_NOT_ACCESSED | FF_SHARED

# PORT: pl-prologflag.c create_oneof
# DIVERGES: no `PL_register_atom`; a list that is no proper list of atoms answers `nothing`, as upstream's NULL
# (the `type_error(atom, X)` of an element is raised, a tail that is no `[]` raises nothing).
"The `oneof_t` of the list of atoms `atoms` (one reference), or `nothing` (pl-prologflag.c)."
function create_oneof(
    ld::PL_local_data{T}, atoms::term_t
)::Union{Nothing, oneof_t{T}} where {T}
    tail = PL_copy_term_ref(ld, atoms)
    head = PL_new_term_ref(ld)
    values = T[]
    while PL_get_list(ld, tail, head, tail)
        a = PL_get_atom_ex(ld, head)
        a === nothing && return nothing
        push!(values, a)
    end
    PL_get_nil(ld, tail) || return nothing

    return oneof_t{T}(values, 1)
end

# PORT: pl-prologflag.c set_oneof
# DIVERGES: `free_oneof` is the garbage collector's; the local data `ld` is an argument that binds the term type `T`
# (with `f` and `of` both `nothing`, `T` is otherwise unbound: UndefVarError).
"Make `of` the `oneof` of the flag `f` on creation (`FF_ISCREATE`), dropping the reference to its old one (pl-prologflag.c)."
function set_oneof(
    ::PL_local_data{T}, f::Union{Nothing, prolog_flag{T}, PseudoFlag},
    of::Union{Nothing, oneof_t{T}}, flags::UInt32
)::Nothing where {T}
    if f isa prolog_flag{T} && of !== nothing && (flags & FF_ISCREATE) != 0 &&
        f.oneof !== of
        old = f.oneof
        if old !== nothing
            old.references -= 1
        end
        f.oneof = of
        of.references += 1
    end
    return nothing
end

# PORT: pl-prologflag.c check_oneof_flag
# DIVERGES: the exception is built on the term references (`PL_unify_term`'s `PL_FUNCTOR`, `PL_TERM`, `PL_ATOM`,
# `PL_VARIABLE` arguments); `error` is a Boolean.
"Whether the atom `a` is one of the values of `of` (always, without one); with `error`, raise `error(domain_error(oneof(List), A), _)` if not (pl-prologflag.c)."
function check_oneof_flag(
    ld::PL_local_data{T}, of::Union{Nothing, oneof_t{T}}, a::T, error::Bool
)::Bool where {T}
    if of !== nothing
        for v in of.values
            sym_key(v) == sym_key(a) && return true
        end

        if error
            dom = PL_new_term_ref(ld)
            ex = PL_new_term_ref(ld)
            put_oneof(ld, dom, of)
            formal = _message_term(ld, :domain_error, dom, _err_atom(ld, a))
            var = PL_new_term_ref(ld)
            PL_put_variable(ld, var)
            PL_cons_functor(ld, ex, _err_functor(ld, :error, 2), formal, var)
            return PL_raise_exception(ld, ex)
        else
            return false
        end
    end

    return true
end

# PORT: pl-prologflag.c set_flag_type
"Give the flag `f` the type of `flags` (pl-prologflag.c)."
function set_flag_type(f::prolog_flag, flags::UInt32)::Bool
    f.flags = (f.flags & ~FT_MASK) | (flags & FT_MASK)
    return true
end

# PORT: pl-prologflag.c set_flag_atom
# DIVERGES: no `PL_register_atom`.
"Make the atom `a` the value of the flag `f` (pl-prologflag.c)."
function set_flag_atom(f::prolog_flag{T}, a::T)::Bool where {T}
    f.a = a
    return true
end

# PORT: pl-prologflag.c clean_prolog_flag
# DIVERGES: the value is the garbage collector's (no `PL_erase`, `PL_unregister_atom`, `free_oneof`, `freeHeap`);
# `memset(&f->value, 0, …)` is the zero of each member's field. The `oneof` stays with its flag while another flag
# holds a reference, as upstream's.
"Empty the flag `f`: it becomes an integer flag without value, its pushed values dropped (pl-prologflag.c)."
function clean_prolog_flag(f::prolog_flag{T})::Nothing where {T}
    set_flag_type(f, FT_INTEGER)
    f.a = mk_sym(T, Symbol("false"))
    f.i = 0
    f.f = 0.0
    f.t = nothing

    of = f.oneof
    if of !== nothing
        of.references -= 1
        if of.references == 0
            f.oneof = nothing
        end
    end

    p = f.pushed
    while p !== nothing
        f.pushed = p.pushed
        p.pushed = nothing
        clean_prolog_flag(p)
        p = f.pushed
    end
    return nothing
end

# PORT: pl-prologflag.c keep_flag
# DIVERGES: the database and the local data are arguments; the answer is an `Int`, upstream's: 1 the flag stays
# as it is, 0 it is changed and the caller sets the value, -1 an error is raised. No `lock_shared_value`.
# `f2 = *f` is a shallow copy (`prolog_flag`'s fields).
"With `FF_KEEP`: 1 if the flag `f` keeps its definition, else (after the converted or the warning) 0; -1 after an error. Without it, 0 (pl-prologflag.c)."
function keep_flag(
    gd::PL_global_data{T}, ld::PL_local_data{T}, k::T, f::prolog_flag{T}, flags::UInt32,
    of::Union{Nothing, oneof_t{T}}, value::term_t
)::Int where {T}
    (flags & FF_KEEP) == 0 && return 0

    if of !== nothing
        check_oneof_flag(ld, of, f.a, false) && return 1
    elseif (flags & FT_MASK) == (f.flags & FT_MASK)
        return 1
    else
        ftype = f.flags & FT_MASK
        rc = -2                                         # not converted

        target = flags & FT_MASK
        if target == FT_FROM_VALUE
            rc = 1
        elseif target == FT_ATOM
            if ftype == FT_BOOL
                rc = set_flag_type(f, flags) ? 1 : 0
            end
        elseif target == FT_BOOL
            if ftype == FT_ATOM
                bv = atom_to_bool(ld, f.a)
                if bv !== nothing
                    set_flag_type(f, flags)
                    rc =
                        if set_flag_atom(
                            f, mk_sym(T, bv ? Symbol("true") : Symbol("false"))
                        )
                            1
                        else
                            0
                        end
                end
            end
        elseif target == FT_FLOAT
            if ftype == FT_INTEGER
                f.f = Float64(f.i)
                rc = set_flag_type(f, flags) ? 1 : 0
            end
        elseif target == FT_TERM
            v = PL_new_term_ref(ld)
            if unify_prolog_flag_value(gd, ld, MODULE_user(gd).index, k, f, v)
                f.t = PL_record(ld, v)
                rc = set_flag_type(f, flags) ? 1 : 0
            else
                rc = -1
            end
        end
        rc != -2 && return rc
    end

    f2 = prolog_flag{T}(flags, f.index, f.a, f.i, f.f, f.t, of, f.pushed)   # f2 = *f; f2.oneof, f2.flags
    type = PL_new_term_ref(ld)
    preset = PL_new_term_ref(ld)
    unify_prolog_flag_type(ld, f2, type) || return -1
    unify_prolog_flag_value(gd, ld, MODULE_user(gd).index, k, f, preset) || return -1
    msg = _message_term(
        ld, :prolog_flag_invalid_preset, _err_atom(ld, k), preset, type, value
    )
    printMessage(ld, :warning, msg) || return -1

    clean_prolog_flag(f)
    set_flag_type(f, flags)
    set_oneof(ld, f, of, flags)

    return 0
end

# PORT: pl-prologflag.c new_prolog_flag
# DIVERGES: the local data is an argument; `nothing` after the error is raised (upstream's NULL); an `int64_t` is
# `PL_get_long` (LP64); no `allocHeapOrHalt`, `PL_register_atom`.
"A new flag of the type `flags` says, with the value of the term `value` (the type taken from it for `FT_FROM_VALUE`), or `nothing` (pl-prologflag.c)."
function new_prolog_flag(
    ld::PL_local_data{T}, value::term_t, flags::UInt32
)::Union{Nothing, prolog_flag{T}} where {T}
    f = prolog_flag{T}(UInt32(0), mk_sym(T, Symbol("false")))
    type = flags & FT_MASK

    if type == FT_FROM_VALUE
        a = PL_get_atom(ld, value)
        if a !== nothing
            bv = atom_to_bool(ld, a)
            if bv !== nothing
                f.a = mk_sym(T, bv ? Symbol("true") : Symbol("false"))
                f.flags = FT_BOOL
            else
                f.a = a
                f.flags = FT_ATOM
            end
        elseif (i = PL_get_int64(ld, value)) !== nothing
            f.flags = FT_INTEGER
            f.i = i
        elseif (d = PL_get_float(ld, value)) !== nothing
            f.flags = FT_FLOAT
            f.f = d
        else
            f.flags = FT_TERM
            if ground_cells(ld, -(value + 1)) != 0              # !PL_is_ground(value)
                PL_error(ld, ERR_INSTANTIATION)
                return nothing
            end
            f.t = PL_record(ld, value)
        end
    elseif type == FT_ATOM
        a = PL_get_atom_ex(ld, value)
        a === nothing && return nothing
        f.a = a
        f.flags = FT_ATOM
    elseif type == FT_BOOL
        b = PL_get_stdbool_ex(ld, value)
        b === nothing && return nothing
        f.flags = FT_BOOL
        f.a = mk_sym(T, b ? Symbol("true") : Symbol("false"))
    elseif type == FT_INTEGER
        i = PL_get_int64_ex(ld, value)
        i === nothing && return nothing
        f.i = i
        f.flags = FT_INTEGER
    elseif type == FT_FLOAT
        d = PL_get_float_ex(ld, value)
        d === nothing && return nothing
        f.f = d
        f.flags = FT_FLOAT
    elseif type == FT_TERM
        if ground_cells(ld, -(value + 1)) != 0                  # !PL_is_ground(value)
            PL_error(ld, ERR_INSTANTIATION)
            return nothing
        end
        f.t = PL_record(ld, value)
        f.flags = FT_TERM
    end
    f.flags |= (flags & FF_COPY_FLAGS)

    return f
end

# PORT: pl-prologflag.c set_flag_value
# DIVERGES: the database and the local data are arguments, the module is its record, and the key an atom. The side
# effects the kernel has none for are refused by name (design D4): `tty_control` (changed), `debug_on_interrupt`, `var_tag`, `incomparable`, `encoding`,
# `unicode_atoms`, `file_name_case_handling`, `table_monotonic`, `theme`, `agc_margin`, `table_space`,
# `table_compile_threshold`, `table_drop_intermediate`, `stack_limit`, `string_stack_tripwire` and `heartbeat`.
# Since R2 F1c `debug` and `debugger_show_context` are accepted: `debug` calls `debugmode` and `tracemode` (src/pl-trace.jl) and
# `rval` is their answer, as upstream's (pl-prologflag.c:1317-1326); the value goes to the table as upstream does, the mask bit only if `rval`.
# `threads` has no branch: it is read-only in the kernel's no-threads build (design D1; upstream's `O_PLMT` branch is not
# built), so `check_flag_write_access` answers permission_error first. `string_stack_tripwire` is no flag of swipl's
# boot (swipl 10.1.19 creates it on the first `set_prolog_flag`); its branch is reached when it is set a second time.
# `setVarPrefix` answers the atom the flag then holds (`true` is `_`) in place of writing it through `a`. The mask
# bit is the LOCAL data's (`setPrologFlagMask`). `on_error` and `on_warning` are checked and stored (their action
# belongs to the toplevel). `win_file_access_check` is `O_XOS`'s.
"Set the flag `f`, named `k`, as module `m` sees it, to the value of the term `value`, with the side effects of upstream's flags (pl-prologflag.c)."
function set_flag_value(
    gd::PL_global_data{T}, ld::PL_local_data{T}, f::prolog_flag{T}, m::module_t{T}, k::T,
    value::term_t
)::Bool where {T}
    name = sym_text(k)
    type = f.flags & FT_MASK
    rval = true

    if type == FT_BOOL
        val = PL_get_stdbool_ex(ld, value)
        val === nothing && return false

        # deal with side-effects
        if name == "character_escapes"
            if val
                m.flags |= M_CHARESCAPE
            else
                m.flags &= ~M_CHARESCAPE
            end
        elseif name == "debug"
            if val
                rval = debugmode(ld, true, nothing, DBG_ALL)
            else
                rval =
                    tracemode(ld, false, nothing) &&
                    debugmode(ld, false, nothing, UInt32(0))
            end
        elseif name == "debugger_show_context"
            ld.debugstatus_showContext = val
        elseif name == "tty_control"
            val != (sym_key(f.a) == sym_key(mk_sym(T, Symbol("true")))) &&
                _flag_not_ported(k, "PushTty and PopTty (the terminal)")
        elseif name == "debug_on_interrupt"
            _flag_not_ported(k, "enable_debug_on_interrupt (signals)")
        elseif name == "protect_static_code"
            if val != (sym_key(f.a) == sym_key(mk_sym(T, Symbol("true")))) && val == false
                ex = PL_new_term_ref(ld)
                PL_put_atom(ld, ex, mk_sym(T, :protect_static_code))
                return PL_error(
                    ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :set), mk_sym(T, :prolog_flag),
                    ex
                )
            end
        end
        # set the flag value
        if f.index != 0 && rval
            if val
                setPrologFlagMask!(ld, f.index)
            else
                clearPrologFlagMask!(ld, f.index)
            end
        end
        f.a = mk_sym(T, val ? Symbol("true") : Symbol("false"))
    elseif type == FT_ATOM
        a = PL_get_atom_ex(ld, value)
        a === nothing && return false

        check_oneof_flag(ld, f.oneof, a, true) || return false

        if name == "double_quotes"
            nf = setDoubleQuotes(ld, a, m.flags)
            nf === nothing && return false
            m.flags = nf
        elseif name == "back_quotes"
            nf = setBackQuotes(ld, a, m.flags)
            nf === nothing && return false
            m.flags = nf
        elseif name == "rational_syntax"
            nf = setRationalSyntax(ld, a, m.flags)
            nf === nothing && return false
            m.flags = nf
        elseif name == "var_tag"
            _flag_not_ported(k, "setVarTagFlag (the VARTAG_* bits of the module's flags)")
        elseif name == "var_prefix"
            na = setVarPrefix(ld, value, m)
            na === nothing && return false
            a = na
        elseif name == "unknown"
            setUnknown(gd, ld, value, a, m) || return false
        elseif name == "unknown_option"
            setUnknownOption(ld, value, a) || return false
        elseif name == "on_error" || name == "on_warning"
            checkOnError(ld, value, a, k) || return false
        elseif name == "write_attributes"
            setWriteAttributes(ld, a) || return false
        elseif name == "occurs_check"
            setOccursCheck(ld, a) || return false
        elseif name == "incomparable"
            _flag_not_ported(k, "setIncomparable (LD->prolog_flag.incomparable_error)")
        elseif name == "access_level"
            setAccessLevelFromAtom(ld, a) || return false
        elseif name == "encoding"
            _flag_not_ported(k, "setEncoding (the default encoding)")
        elseif name == "unicode_atoms"
            _flag_not_ported(k, "setUnicodeAtoms")
        elseif name == "stream_type_check"
            setStreamTypeCheck(ld, a) || return false
        elseif name == "file_name_case_handling"
            _flag_not_ported(k, "setFileNameCaseHandling")
        elseif name == "autoload"
            setAutoload(ld, a) || return false
        elseif name == "table_monotonic"
            _flag_not_ported(k, "setMonotonicMode (tabling)")
        elseif name == "theme"
            _flag_not_ported(k, "setTheme (the theme of the messages)")
        end

        f.a = a
    elseif type == FT_INTEGER
        i = PL_get_int64_ex(ld, value)
        i === nothing && return false

        if name == "agc_margin"
            _flag_not_ported(k, "GD->atoms.margin (atom garbage collection)")
        elseif name == "table_space"
            _flag_not_ported(k, "LD->tabling.node_pool (tabling)")
        elseif name == "table_compile_threshold"
            _flag_not_ported(k, "LD->table_flags.compile_threshold (tabling)")
        elseif name == "table_drop_intermediate"
            _flag_not_ported(k, "LD->table_flags.drop_intermediate (tabling)")
        elseif name == "stack_limit"
            _flag_not_ported(k, "set_stack_limit")
        elseif name == "string_stack_tripwire"
            _flag_not_ported(k, "LD->fli.string_buffers.tripwire")
        elseif name == "heartbeat"
            _flag_not_ported(k, "LD->yield.frequency")
        end

        f.i = i
    elseif type == FT_FLOAT
        d = PL_get_float_ex(ld, value)
        d === nothing && return false
        f.f = d
    elseif type == FT_TERM
        f.t = PL_record(ld, value)
    else
        error("set_flag_value: the flag $name has the type $type")
    end

    return rval
end

# ── set_prolog_flag/2 and create_prolog_flag/3 (pl-prologflag.c), R2 F1b ─────────────────────────
# PORT: pl-tabling.c tbl_is_restraint_flag
# DIVERGES: the key is the atom (`sym_text`), where upstream compares atom handles.
"Whether the atom `k` names a tabling restraint flag (pl-tabling.c)."
function tbl_is_restraint_flag(k::T)::Bool where {T}
    name = sym_text(k)
    return name == "max_table_subgoal_size" ||
           name == "max_table_answer_size" ||
           name == "max_answers_for_subgoal" ||
           name == "max_table_subgoal_size_action" ||
           name == "max_table_answer_size_action" ||
           name == "max_answers_for_subgoal_action"
end

# PORT: pl-prologflag.c check_flag_write_access
"Whether the flag `f`, named `k`, may be written: not if it is read-only, unless `FF_FORCE`; else `permission_error(modify, flag, K)` (pl-prologflag.c)."
function check_flag_write_access(
    ld::PL_local_data{T}, f::prolog_flag{T}, k::T, flags::UInt32
)::Bool where {T}
    if (f.flags & FF_READONLY) != 0 && (flags & FF_FORCE) == 0
        key = PL_new_term_ref(ld)
        PL_put_atom(ld, key, k)
        return PL_error(
            ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :modify), mk_sym(T, :flag), key
        )
    end

    return true
end

# PORT: pl-prologflag.c check_create_flag
# DIVERGES: the database is an argument.
"Whether a flag `k` may be created implicitly (`FF_NOCREATE`): by the `user_flags` flag, `silent` yes, `warning` with a message, `error` with `existence_error(prolog_flag, K)` (pl-prologflag.c)."
function check_create_flag(
    gd::PL_global_data{T}, ld::PL_local_data{T}, k::T, flags::UInt32
)::Bool where {T}
    (flags & FF_NOCREATE) == 0 && return true

    how = current_prolog_flag_atom(gd, mk_sym(T, :user_flags))
    if how !== nothing
        if sym_key(how) == sym_key(mk_sym(T, :error))
            key = PL_new_term_ref(ld)
            PL_put_atom(ld, key, k)
            return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :prolog_flag), key)
        elseif sym_key(how) == sym_key(mk_sym(T, :warning))
            msg = _message_term(ld, :implicit_create_flag, _err_atom(ld, k))
            printMessage(ld, :warning, msg) || return false     # may not ignore printMessage()
        end
    end

    return true
end

# PORT: pl-prologflag.c set_prolog_flag_unlocked
# DIVERGES: no thread-local table (`FF_LOCAL`, `copy_prolog_flag`, `register_local_flag`): the table is the global
# one. The module is its record. A flag that lives outside the table is refused by name (design D4): the arithmetic
# flags (`set_arith_flag`, pl-arith.c), the clause-indexing flags (`ci_set_flag`, pl-index.c) and the tabling
# restraints (`tbl_set_restraint_flag`, pl-tabling.c). A creation that `check_create_flag` refuses returns at once
# (upstream's code continues below the `if` chain).
"Set, or with `FF_ISCREATE`/`FF_NOCREATE` create, the flag `k` to the value of the term `value`; the flag, `PSEUDO_FLAG`, or `nothing` after an error (pl-prologflag.c)."
function set_prolog_flag_unlocked(
    gd::PL_global_data{T}, ld::PL_local_data{T}, m::module_t{T}, k::T, value::term_t,
    flags::UInt32, of::Union{Nothing, oneof_t{T}}
)::Union{Nothing, prolog_flag{T}, PseudoFlag} where {T}
    f = lookupFlag(gd, _atom_word!(gd.atoms, gd.atom_symbols, k))
    if f !== nothing                                    # set existing Prolog flag
        accessed_prolog_flag(f)
        check_flag_write_access(ld, f, k, flags) || return nothing

        rc = keep_flag(gd, ld, k, f, flags, of, value)
        rc == 1 && return f
        rc == -1 && return nothing

        tbl_is_restraint_flag(k) &&
            _flag_not_ported(k, "tbl_set_restraint_flag (tabling restraints)")
        is_arith_flag(k) && _flag_not_ported(k, "set_arith_flag (pl-arith.c)")
        ci_is_flag(k) && _flag_not_ported(k, "ci_set_flag (pl-index.c)")

        if (flags & FF_ISCREATE) != 0 && (flags & FF_SHARED) != 0 && f.index == 0
            f.flags |= FF_SHARED
        end
    elseif check_create_flag(gd, ld, k, flags)          # define new Prolog flag
        f = new_prolog_flag(ld, value, flags)
        f === nothing && return nothing

        tab = gd.prolog_flag                            # addNewHTableWP(GD->prolog_flag.table, k, f)
        push!(tab.entries, f)
        push!(tab.names, k)
        tab.slot[_atom_word!(gd.atoms, gd.atom_symbols, k)] = length(tab.entries)

        return f
    else
        return nothing
    end

    return set_flag_value(gd, ld, f, m, k, value) ? f : nothing
end

# PORT: pl-prologflag.c set_prolog_flag_ptr
# DIVERGES: no `PL_LOCK(L_PLFLAG)` (one thread), so the flags `threads`, `unicode_atoms` and `theme`, which upstream
# sets unlocked, go the same way; no thread-local table, so no second `set_prolog_flag_unlocked` for `FF_GLOBAL`.
# `autoload` is propagated to `$autoload:set_autoload/1` first (`propagateAutoload`, AUTOLOAD1 A4). The module is the
# parse module unless the key is qualified.
"Set the flag the possibly module-qualified key `key` names to the value of `value`; the flag, `PSEUDO_FLAG` or `nothing` after an error (pl-prologflag.c)."
function set_prolog_flag_ptr(
    gd::PL_global_data{T}, ld::PL_local_data{T}, key::term_t, value::term_t, flags::UInt32,
    of::Union{Nothing, oneof_t{T}}
)::Union{Nothing, prolog_flag{T}, PseudoFlag} where {T}
    ok, mi = PL_strip_module(gd, ld, key, MODULE_parse(ld), key)
    ok || return nothing
    k = PL_get_atom_ex(ld, key)
    k === nothing && return nothing
    m = gd.modules[mi]

    sym_key(k) == sym_key(mk_sym(T, :autoload)) &&
        !propagateAutoload(gd, ld, value) &&
        return nothing

    f = set_prolog_flag_unlocked(gd, ld, m, k, value, flags, of)
    set_oneof(ld, f, of, flags)

    return f
end

# PORT: pl-prologflag.c set_prolog_flag
# DIVERGES: the database and the local data are arguments.
"Set the flag `key` to `value` (C-interface; pl-prologflag.c)."
function set_prolog_flag(
    gd::PL_global_data{T}, ld::PL_local_data{T}, key::term_t, value::term_t, flags::UInt32
)::Bool where {T}
    return set_prolog_flag_ptr(gd, ld, key, value, flags, nothing) !== nothing
end

# PORT: pl-fli.c PL_set_prolog_flag
# DIVERGES: the `PL_BOOL` case only (a Julia `Bool` value), and the first branch only (`HAS_LD && GD->io_initialised`:
# the kernel's flag table exists from the database's construction, so there is no initialisation order to serve);
# the database and the local data are arguments, and it lives with `set_prolog_flag`, not in src/pl-fli.jl. A failed
# foreign frame or term reference is false (upstream falls to the branch that defines the flag outright).
"Set the flag `name` to the Boolean `val` through `set_prolog_flag` (pl-fli.c)."
function PL_set_prolog_flag(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::AbstractString, val::Bool
)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    fid == 0 && return false
    av = PL_new_term_refs(ld, 2)
    PL_put_atom(ld, av, mk_sym(T, Symbol(name)))
    PL_put_atom(ld, av + 1, mk_sym(T, Symbol(val ? "true" : "false")))     # PL_put_bool
    rval = set_prolog_flag(gd, ld, av, av + 1, FT_BOOL)
    PL_close_foreign_frame(ld, fid)
    return rval
end

# PORT: pl-prologflag.c set_prolog_flag as pl_set_prolog_flag2_va
# (PRED_IMPL("set_prolog_flag", 2, set_prolog_flag, PL_FA_ISO))
"`set_prolog_flag(+Key, +Value)` (pl-prologflag.c)."
function pl_set_prolog_flag2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return if set_prolog_flag(_query_gd(ld), ld, A1, A2, FF_NOCREATE | FT_FROM_VALUE)
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-prologflag.c prolog_flag_options
const prolog_flag_options = (
    PL_option_t(:type, OPT_TERM),
    PL_option_t(:access, OPT_ATOM),
    PL_option_t(:keep, OPT_BOOL),
    PL_option_t(:warn_not_accessed, OPT_BOOL),
    PL_option_t(:local, OPT_BOOL),
    PL_option_t(:shared, OPT_BOOL)
)

# PORT: pl-prologflag.c create_prolog_flag as pl_create_prolog_flag3_va
# (PRED_IMPL("create_prolog_flag", 3, create_prolog_flag, PL_FA_ISO); registered with 0)
# DIVERGES: `PL_scan_options` answers the option values (`nothing` for one not given, where upstream keeps its
# defaults); the `oneof`'s reference is dropped by the garbage collector (`free_oneof`).
"`create_prolog_flag(+Key, +Value, +Options)`: options `type(T)`, `access(A)`, `keep(B)`, `warn_not_accessed(B)`, `local(B)`, `shared(B)` (pl-prologflag.c)."
function pl_create_prolog_flag3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    flags = FF_ISCREATE | FF_GLOBAL
    of = nothing

    vals = PL_scan_options(ld, A3, 0, "prolog_flag_option", prolog_flag_options)
    vals === nothing && return FFALSE
    type = something(vals[1], 0)::Int
    access = vals[2] === nothing ? mk_sym(T, :read_write) : vals[2]::T
    keep = vals[3] === nothing ? false : vals[3]::Bool
    warn_not_accessed = vals[4] === nothing ? false : vals[4]::Bool
    local_ = vals[5] === nothing ? false : vals[5]::Bool
    shared = vals[6] === nothing ? false : vals[6]::Bool

    if type == 0
        flags |= FT_FROM_VALUE
    elseif (a = PL_get_atom(ld, type)) !== nothing
        k = sym_key(a)
        if k == sym_key(mk_sym(T, :boolean))
            flags |= FT_BOOL
        elseif k == sym_key(mk_sym(T, :integer))
            flags |= FT_INTEGER
        elseif k == sym_key(mk_sym(T, :float))
            flags |= FT_FLOAT
        elseif k == sym_key(mk_sym(T, :atom))
            flags |= FT_ATOM
        elseif k == sym_key(mk_sym(T, :term))
            flags |= FT_TERM
        else
            PL_error(ld, ERR_DOMAIN, mk_sym(T, :prolog_flag_type), type)
            return FFALSE
        end
    elseif PL_is_functor(ld, type, mk_sym(T, :oneof), 1)
        _PL_get_arg(ld, 1, type, type)
        of = create_oneof(ld, type)
        of === nothing && return FFALSE
        flags |= FT_ATOM
    else
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :prolog_flag_type), type)
        return FFALSE
    end

    if sym_key(access) == sym_key(mk_sym(T, :read_only))
        flags |= FF_READONLY
    elseif sym_key(access) != sym_key(mk_sym(T, :read_write))
        at = PL_new_term_ref(ld)
        PL_put_atom(ld, at, access)
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :prolog_flag_access), at)
        return FFALSE
    end

    keep && (flags |= FF_KEEP)
    warn_not_accessed && (flags |= FF_WARN_NOT_ACCESSED)
    if local_ && shared
        PL_error(
            ld, "", 0, "local(true) conflicts with shared(true)", ERR_DOMAIN,
            mk_sym(T, :prolog_flag_option), A3
        )
        return FFALSE
    end
    if local_
        flags &= ~FF_GLOBAL
        flags |= FF_LOCAL
    end
    shared && (flags |= FF_SHARED)

    f = set_prolog_flag_ptr(_query_gd(ld), ld, A1, A2, flags, of)
    if of !== nothing
        of.references -= 1                              # free_oneof() at zero: the garbage collector's
    end

    return f !== nothing ? FTRUE : FFALSE
end

# ── push_prolog_flag/2 and pop_prolog_flag/1 (pl-prologflag.c), R2 F2 ───────────────────────────
# PORT: pl-prologflag.c copy_prolog_flag
# DIVERGES: the copy's record is `PL_duplicate_record`'s (the record itself, see src/pl-fli.jl); no `allocHeapOrHalt`,
# `PL_register_atom`.
"A copy of the flag `f` with no pushed values; it shares the `oneof`, whose count it raises (pl-prologflag.c)."
function copy_prolog_flag(f::prolog_flag{T})::prolog_flag{T} where {T}
    copy = prolog_flag{T}(f.flags, f.index, f.a, f.i, f.f, f.t, f.oneof, nothing)   # *copy = *f; copy->pushed = NULL
    of = f.oneof
    if of !== nothing
        of.references += 1
    end
    if (f.flags & FT_MASK) == FT_TERM
        copy.t = PL_duplicate_record(f.t::record{T})
    end
    return copy
end

# PORT: pl-prologflag.c put_saved_flag_value
# DIVERGES: the local data is an argument; a type upstream's `switch` does not hold (`assert(0)`) raises an error.
"Put the value of the saved flag `saved` into the term reference `val` (pl-prologflag.c)."
function put_saved_flag_value(
    ld::PL_local_data{T}, val::term_t, saved::prolog_flag{T}
)::Bool where {T}
    type = saved.flags & FT_MASK
    if type == FT_BOOL || type == FT_ATOM
        return PL_put_atom(ld, val, saved.a)
    elseif type == FT_INTEGER
        return PL_put_int64(ld, val, Int(saved.i))
    elseif type == FT_FLOAT
        return PL_put_float(ld, val, saved.f)
    elseif type == FT_TERM
        return PL_recorded(ld, saved.t::record{T}, val)
    end
    error("put_saved_flag_value: the saved flag has the type $type")
end

# PORT: pl-prologflag.c ensure_local_flag
# DIVERGES: the kernel has one table (design D1: upstream's build without `O_PLMT`, where the body is `return f`): there is
# no thread-local copy to make.
"The flag `f`, named `k`, as the table of this thread holds it (pl-prologflag.c)."
ensure_local_flag(k::T, f::prolog_flag{T}) where {T} = f

# The flag with the key `w` (an atom word) in the table of `gd`, or `nothing`: upstream's `lookupHTableWP` of the
# table, which marks no flag accessed (`lookupFlag` does).
function _prolog_flag_table_get(
    gd::PL_global_data{T}, w::UInt64
)::Union{Nothing, prolog_flag{T}} where {T}
    i = get(gd.prolog_flag.slot, w, 0)
    i == 0 && return nothing
    return gd.prolog_flag.entries[i]::prolog_flag{T}
end

# PORT: pl-prologflag.c push_prolog_flag
# DIVERGES: the database and the local data are arguments; no thread-local table (`LD->prolog_flag.table`,
# `register_local_flag`) and no `PL_LOCK(L_PLFLAG)`: a flag that is absent is added to the one table, as
# `set_prolog_flag_unlocked` adds one; the module is its record.
"`push_prolog_flag(+Flag, +Value)`: save the value of `Flag`, or that it is absent, and set it to `Value` (pl-prologflag.c)."
function push_prolog_flag(
    gd::PL_global_data{T}, ld::PL_local_data{T}, A1::term_t, value::term_t
)::Bool where {T}
    key = PL_new_term_ref(ld)
    ok, mi = PL_strip_module(gd, ld, A1, MODULE_parse(ld), key)
    ok || return false
    k = PL_get_atom_ex(ld, key)
    k === nothing && return false
    m = gd.modules[mi]
    w = _atom_word!(gd.atoms, gd.atom_symbols, k)

    f = _prolog_flag_table_get(gd, w)
    if f !== nothing
        check_flag_write_access(ld, f, k, UInt32(0)) || return false
        if (f.flags & FF_SHARED) != 0                   # pushing is per thread
            key2 = PL_new_term_ref(ld)
            return PL_put_atom(ld, key2, k) &&
                   PL_error(
                ld, "", 0, "the flag is shared", ERR_PERMISSION, mk_sym(T, :push),
                mk_sym(T, :prolog_flag), key2
            )
        end
        f = ensure_local_flag(k, f)
        saved = copy_prolog_flag(f)
        rc = set_flag_value(gd, ld, f, m, k, value)
        if rc
            saved.pushed = f.pushed
            f.pushed = saved
        else
            clean_prolog_flag(saved)
        end
        return rc
    end

    nf = new_prolog_flag(ld, value, FT_FROM_VALUE)
    nf === nothing && return false
    absent = prolog_flag{T}(FT_INTEGER | FF_PUSH_ABSENT, mk_sym(T, Symbol("false")))
    nf.pushed = absent
    tab = gd.prolog_flag                                # addNewHTableWP(GD->prolog_flag.table, k, nf)
    push!(tab.entries, nf)
    push!(tab.names, k)
    tab.slot[w] = length(tab.entries)
    return true
end

# PORT: pl-prologflag.c push_prolog_flag as pl_push_prolog_flag2_va
# (PRED_IMPL("push_prolog_flag", 2, push_prolog_flag, 0))
"`push_prolog_flag(+Flag, +Value)` (pl-prologflag.c)."
function pl_push_prolog_flag2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return push_prolog_flag(_query_gd(ld), ld, A1, A2) ? FTRUE : FFALSE
end

# PORT: pl-prologflag.c pop_prolog_flag
# DIVERGES: as `push_prolog_flag`; the table's slot of a flag that was absent at its push is emptied (`deletePrologFlag!`).
"`pop_prolog_flag(+Flag)`: restore the state `push_prolog_flag/2` saved; `existence_error(pushed_flag, Flag)` without a push (pl-prologflag.c)."
function pop_prolog_flag(
    gd::PL_global_data{T}, ld::PL_local_data{T}, A1::term_t
)::Bool where {T}
    key = PL_new_term_ref(ld)
    ok, mi = PL_strip_module(gd, ld, A1, MODULE_parse(ld), key)
    ok || return false
    k = PL_get_atom_ex(ld, key)
    k === nothing && return false
    m = gd.modules[mi]
    w = _atom_word!(gd.atoms, gd.atom_symbols, k)

    f = _prolog_flag_table_get(gd, w)
    if f === nothing || f.pushed === nothing
        ex = PL_new_term_ref(ld)
        return PL_put_atom(ld, ex, k) &&
               PL_error(ld, ERR_EXISTENCE, mk_sym(T, :pushed_flag), ex)
    end

    prev = f.pushed::prolog_flag{T}
    if (prev.flags & FF_PUSH_ABSENT) != 0
        f.pushed = nothing
        deletePrologFlag!(gd, w)
        clean_prolog_flag(f)
        return true
    end

    restore = PL_new_term_ref(ld)
    rc = put_saved_flag_value(ld, restore, prev)
    if rc
        f.pushed = prev.pushed
        prev.pushed = nothing
        rc = set_flag_value(gd, ld, f, m, k, restore)
        clean_prolog_flag(prev)
    end
    return rc
end

# PORT: pl-prologflag.c pop_prolog_flag as pl_pop_prolog_flag1_va
# (PRED_IMPL("pop_prolog_flag", 1, pop_prolog_flag, 0))
"`pop_prolog_flag(+Flag)` (pl-prologflag.c)."
function pl_pop_prolog_flag1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return pop_prolog_flag(_query_gd(ld), ld, PL__t0) ? FTRUE : FFALSE
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

# Not a port of C code: the cmake variable SO_EXT (src/CMakeLists.txt:40).
"The shared-object extension, `SO_EXT` (src/CMakeLists.txt:40: `CMAKE_SHARED_MODULE_SUFFIX` without its dot)."
const SO_EXT = Sys.iswindows() ? "dll" : "so"

# Not a port of C code: the value of cmake/GitVersion.cmake's GIT_VERSION, which pl-version.c setGITVersion reads.
"The `version_git` flag: `git describe --match \"V*\"` of the pin cbf4e1896275 with the `V` cut (cmake/GitVersion.cmake)."
const GIT_VERSION = "10.1.19-1-gcbf4e189"

# PORT: pl-prologflag.c initPrologFlags as initPrologFlags!
# DIVERGES: the database is the argument and the flags go to its table, in upstream's order. The order of the
# calls of pl-setup.c (`initClauseIndexing`, `initPrologFlags`, `initTabling`, `initArith`) is kept inside
# this function, so the constructor of the database makes one call, before `initBuildIns!` (pl-setup.c:136
# comes before :158). The command-line options are their defaults, with `-q` absent (`verbose` is `normal`),
# and `GD->options.traditional` false. NOT DEFINED, as the file header says: the build's configuration flags,
# `pipe`, `engines`, `system_thread_id`, `shared_table_space`; the Windows, macOS, Android, conda, WASM
# and runtime-only flags; `xpce` (no `--xpce`); `asan`; `abi_version`; `cmake_build_type`. `PL_set_prolog_flag`'s
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
    # pl-prologflag.c:2548-2549 defines `home` where `systemDefaults.home` is known; the kernel's own is the HOME TREE of R2 LB4
    # (design D5, audit D-0151 item 6; loader_boot.md LD6): `home` in the package directory, a tree of links over vendor/swipl-devel
    # and packages/plunit that tools/build_home.jl builds (swipl's build home, cmake/InstallSource.cmake:8-25)
    home = joinpath(dirname(dirname(@__DIR__)), "home")
    gd.defaults_home = home                             # systemDefaults.home (pl-init.c initPaths): `$cmd_option_val(home, _)` reads it
    setPrologFlag(gd, "home", FT_ATOM | FF_READONLY, home)
    # Port of pl-prologflag.c set_libswipl (:2470-2493). DIVERGES: no libswipl is loaded, so `dladdr` (:2483-2488) has no object to find and
    # the `#ifdef LIBPL_PATH` fallback (:2491-2493, `FT_ATOM`, writable) answers: `<prefix>/lib/libswipl.so` as cmake/Params.cmake:60-63 builds
    # it (`LIBSWIPL_DIR` = `lib`, src/CMakeLists.txt:421-422; `SO_EXT`, :40), the prefix being the package directory `home` lies in. The file is none.
    setPrologFlag(
        gd,
        "libswipl",
        FT_ATOM,
        joinpath(dirname(dirname(@__DIR__)), "lib", "libswipl." * SO_EXT)
    )
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
    # Port of pl-prologflag.c initPrologFlags :2595. DIVERGES: the first flag of the `O_DYNAMIC_EXTENSIONS` block only (:2593-2606; `open_shared_object`,
    # `shared_object_search_path` and the `c_*` flags wait for F8): boot/init.pl:1406 reads this one for `prolog_file_type(Ext, executable)`.
    setPrologFlag(gd, "shared_object_extension", FT_ATOM | FF_READONLY, SO_EXT)
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
    # Port of pl-version.c setGITVersion (:41-48), called at the end of the version flags (pl-prologflag.c:2930). DIVERGES: `GIT_VERSION` is
    # cmake/GitVersion.cmake's `git describe --match "V*"` of the pin with the `V` cut, as a build of the pin gets it: `V10.1.19-1-gcbf4e189`.
    # `cmake_build_type` (:46) is the build's own and stays deferred.
    setPrologFlag(gd, "version_git", FT_ATOM | FF_READONLY, GIT_VERSION)
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
    PL_extension("set_prolog_flag", 2, pl_set_prolog_flag2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("create_prolog_flag", 3, pl_create_prolog_flag3_va, PL_FA_VARARGS),
    PL_extension(
        "current_prolog_flag", 2, pl_current_prolog_flag2_va,
        PL_FA_ISO | PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "\$current_prolog_flag", 5, pl_dcurrent_prolog_flag5_va,
        PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("push_prolog_flag", 2, pl_push_prolog_flag2_va, PL_FA_VARARGS),
    PL_extension("pop_prolog_flag", 1, pl_pop_prolog_flag1_va, PL_FA_VARARGS)
)
