# UPSTREAM: swipl-devel src/pl-setup.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's start-up (pl-setup.c): allocating and emptying the stacks
# of a thread, which leaves one foreign frame at the base of the local stack; since V5d the local
# stack's spare — room reserved above its `max` for handling a stack overflow — given back after
# an exception (`trim_stack`, `trimStacks`).

# setup:1631 the local stack's spare: `512*SIZEOF_WORD + LOCAL_MARGIN` bytes, here in positions.
"The spare of a new local stack, in positions (pl-setup.c `allocStacks`)."
const LOCAL_SPARE = 512 + LOCAL_MARGIN
# setup:1630, :1634 the global stack's spare, `512*SIZEOF_WORD`, and the trail's, `256*SIZEOF_WORD`.
"The spare of a new global stack, in positions (pl-setup.c `allocStacks`)."
const GLOBAL_SPARE = 512
"The spare of a new trail, in positions (pl-setup.c `allocStacks`)."
const TRAIL_SPARE = 256

# PORT: pl-setup.c init_stack as init_stack!
# DIVERGES: the local stack's, in positions; there is no name (the overflow's context names it,
# src/pl-alloc.jl), `min_free` (the kernel's growth doubles, src/pl-gc.jl `growStacks!`), `gced_size`
# or GC policy (no stack garbage collector until G1). The cells and the record pools are grown to
# `size` (`_resize_local!`); `stack_malloc` allocated them upstream.
"Set up the local stack: `size` positions, of which `spare` are reserved above its `max` (pl-setup.c)."
function init_stack!(ld::PL_local_data{T}, size::Int, spare::Int)::Nothing where {T}
    ld.lTop = 0                                 # s->top = s->base
    _resize_local!(ld, size)
    ld.local_spare = spare
    ld.local_def_spare = spare
    ld.lMax = size - spare                      # s->max = addPointer(s->base, size - spare)
    return nothing
end

# PORT: pl-setup.c allocStacks as allocStacks!
# DIVERGES: the local stack's cells — there is no global, trail or argument stack of fixed size (they
# grow on demand) — and in positions: `minlocal` (4 K words) is `LOCAL_INITIAL`, its spare
# `LOCAL_SPARE`; the global stack's and the trail's spares are reserves in the one limit (since L1f f1b,
# `_stacks_in_use`); nothing is allocated that can fail. `stacks.local.min_free` is not kept (see `init_stack!`).
"Allocate the local stack of a new thread (pl-setup.c)."
function allocStacks!(ld::PL_local_data{T})::Bool where {T}
    ld.global_spare = ld.global_def_spare = GLOBAL_SPARE    # init_stack(global, …, 512*SIZEOF_WORD)
    init_stack!(ld, LOCAL_INITIAL, LOCAL_SPARE)
    ld.trail_spare = ld.trail_def_spare = TRAIL_SPARE       # init_stack(trail, …, 256*SIZEOF_WORD)
    return true
end

# PORT: pl-setup.c trim_stack as trim_stack!
# DIVERGES: the local stack's, in positions.
"Reserve the local stack's spare again above its `max`, as far as its free room allows (pl-setup.c)."
function trim_stack!(ld::PL_local_data{T})::Nothing where {T}
    if ld.local_spare < ld.local_def_spare
        reduce = ld.local_def_spare - ld.local_spare
        room = ld.lMax - ld.lTop                # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end
        ld.lMax -= reduce                       # s->max = addPointer(s->max, -reduce)
        ld.local_spare += reduce
    end
    return nothing
end

# PORT: pl-setup.c trim_stack as trim_stack_global!
# DIVERGES (since L1f f1b): the global stack's spare is a reserve in the one limit (`_stacks_in_use`), so its
# free room is what the limit leaves (`stacks_limit - _stacks_in_use`). As upstream, a reserve the room
# cannot hold is kept whole (`room > 0 && room < reduce`): after an overflow trimStacks(resize) shrinks the
# local stack first (`growStacks_trim!`, GROW_TRIM), which gives the room back.
"Reserve the global stack's spare again, as far as the room under the limit allows (pl-setup.c)."
function trim_stack_global!(ld::PL_local_data)::Nothing
    if ld.global_spare < ld.global_def_spare
        reduce = ld.global_def_spare - ld.global_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end
        ld.global_spare += reduce                           # s->max -= reduce; s->spare += reduce
    end
    return nothing
end

# PORT: pl-setup.c trim_stack as trim_stack_trail!
# DIVERGES (since L1f f1b): as `trim_stack_global!`, the trail's.
"Reserve the trail's spare again, as far as the room under the limit allows (pl-setup.c)."
function trim_stack_trail!(ld::PL_local_data)::Nothing
    if ld.trail_spare < ld.trail_def_spare
        reduce = ld.trail_def_spare - ld.trail_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end
        ld.trail_spare += reduce
    end
    return nothing
end

# PORT: pl-setup.c trimStacks as trimStacks!
# DIVERGES: `resize` is `growStacks_trim!` (upstream's `growStacks(GROW_TRIM, GROW_TRIM, GROW_TRIM)`, since L1f
# f1b under audit D-0049: the local stack shrunk again after an overflow, the spares re-reserved as it
# shrinks); without it the three spares are reserved again (`trim_stack!`, `_global!`, `_trail!`). `lTop` is
# raised to the query's saved argument pointer while the spares are reserved, as upstream's.
# NOT PORTED: `trim_stack_requested`: its readers are the stack garbage collector's (pl-gc.c
# `garbageCollect`), not ported until G1; SECURE_GC's clearing and the debug checks.
"Reclaim the local stack's spare after an exception (pl-setup.c)."
function trimStacks!(ld::PL_local_data{T}, resize::Bool)::Nothing where {T}
    resize && growStacks_trim!(ld)              # growStacks(GROW_TRIM, GROW_TRIM, GROW_TRIM)
    lsave = ld.lTop
    if ld.query != 0                            # saved registers above lTop
        q = ld.queries[ld.query]
        if q.registers_fr != 0 && q.registers_argp.form == ARGP_SLOT &&
            q.registers_argp.pos > ld.lTop
            ld.lTop = q.registers_argp.pos
        end
    end
    if !resize
        trim_stack!(ld)
        trim_stack_global!(ld)
        trim_stack_trail!(ld)
    end
    ld.lTop = lsave
    return nothing
end

# PORT: pl-setup.c emptyStacks as emptyStacks!
# DIVERGES: the argument stack is emptied.
# `BFR` and `LD->query` are cleared with the stack they point into; there is no `mark_bar`, and no
# `lTop && gTop` guard (the stacks always exist). Of the
# engine's permanent term references upstream allocates in the base foreign frame, the exception's
# four are (`exception_bin`, `exception_printed`, `exception.tmp`, `exception.pending`, in
# upstream's order), then since AV1 `attvar.head` and `attvar.tail`, each with a PERMANENT global cell
# (audit D-0122 Q1 (a), a representation-only divergence: upstream assigns the two local-stack cells
# themselves, pl-attvar.c:127 "on local stack!", and its own TBD, pl-wam.c:1565, names the global
# stack); the others belong to subsystems not ported (`trim.dummy`, `attvar.gc_attvars` (G1), undo
# hooks, tabling; nor `destroyGlobalVars`). So later term references
# lie at other absolute positions than in
# swipl: compare DIFFERENCES between positions with swipl, never absolute ones.
"Empty the local stack and the trail, then open the base foreign frame (pl-setup.c)."
function emptyStacks!(ld::PL_local_data{T})::Nothing where {T}
    ld.environment_frame = 0                    # environment_frame = NULL;
    ld.fli_context = 0                          # fli_context = NULL;
    ld.BFR = 0

    ld.lTop = 0                                 # emptyStack((Stack)&LD->stacks.local);
    ld.nframes = 0
    ld.nchoices = 0
    ld.nfliframes = 0
    ld.nqueries = 0
    ld.query = 0                                # LD->query = NULL;
    ld.aTop = 0                                 # emptyStack((Stack)&LD->stacks.argument);
    empty!(ld.trail)                            # emptyStack((Stack)&LD->stacks.trail);
    ld.gTop = 0                                 # emptyStack((Stack)&LD->stacks.global);
    _truncate_vtable!(ld)                       # (the value table with it: L1b stage C2)
    ld.mark_bar = ld.gTop                       # LD->mark_bar = gTop;

    PL_open_foreign_frame(ld)
    ld.exception_term = 0
    ld.exception_bin = PL_new_term_ref(ld)
    ld.exception_printed = PL_new_term_ref(ld)
    ld.exception_tmp = PL_new_term_ref(ld)                     # LD->exception.tmp
    ld.exception_pending = PL_new_term_ref(ld)                 # LD->exception.pending
    # the three the kernel RESETS (`setVar(*valTermRef(…))`, pl-wam.c resumeAfterException and
    # restore_after_query): their cells, made here below every mark the engine will take, are
    # PERMANENT — a reset makes the slot reference its cell again, unbound (`_reset_exception_slot!`).
    # Until 2026-10-15 a reset allocated a FRESH cell, which the next `Undo!` freed with the slot
    # still pointing at it; the next query laid a compound over the position and
    # `classify_exception` read its functor cell as a value word (test_db.jl's BoundsError).
    ld.exception_cells = unRef(ld.slots[ld.exception_bin + 1])
    @assert unRef(ld.slots[ld.exception_printed + 1]) == ld.exception_cells + 1
    @assert unRef(ld.slots[ld.exception_pending + 1]) == ld.exception_cells + 3
    # the wakeup list's two (AV1; audit D-0122 Q1 (a)): upstream's are cells of the LOCAL stack, assigned
    # with `TrailAssignment` ("on local stack!", pl-attvar.c); here each slot references a PERMANENT global
    # cell, as the exception's three, so the list lives in the cell ("empty" = the cell unbound) and every
    # trail entry stays global — upstream's own TBD (pl-wam.c, `TrailAssignment`'s comment) names the
    # global stack.
    ld.attvar_head = PL_new_term_ref(ld)                       # LD->attvar.head
    ld.attvar_tail = PL_new_term_ref(ld)                       # LD->attvar.tail
    @assert unRef(ld.slots[ld.attvar_tail + 1]) == unRef(ld.slots[ld.attvar_head + 1]) + 1
    ld.tmp_h = PL_new_term_refs(ld, TMP_PTR_SIZE)              # for(i…) LD->tmp.h[i] = PL_new_term_ref()
    ld.tmp_top = 0                                             # LD->tmp.top = 0
    ld.tmp_cells = unRef(ld.slots[ld.tmp_h + 1])               # (PERMANENT, as the exception's: popTermRef)
    return nothing
end

# PORT: pl-setup.c signames as SIGNAMES
# DIVERGES (HALT1, for the audit): the signal numbers are Linux's (x86_64): upstream reads them from the host's
# `<signal.h>`; the kernel is Linux-only here. The `#ifdef`s of signals Linux lacks are left out (`emt`, `info`);
# the flags (`PLSIG_THROW`, `PLSIG_IGNORE`) and the Prolog interrupts from 32 up (`prolog:gc`, …) are left to the
# signal step. A comment, not a docstring, as for every module-level constant the global-state lint reads.
const SIGNAMES = (
    ("hup", 1), ("int", 2), ("quit", 3), ("ill", 4), ("abrt", 6), ("fpe", 8), ("kill", 9),
    ("segv", 11), ("pipe", 13), ("alrm", 14), ("term", 15), ("usr1", 10), ("usr2", 12),
    ("chld", 17), ("cont", 18), ("stop", 19), ("tstp", 20), ("ttin", 21), ("ttou", 22),
    ("trap", 5), ("bus", 7), ("stkflt", 16), ("urg", 23), ("io", 29), ("poll", 29),
    ("xcpu", 24), ("xfsz", 25), ("vtalrm", 26), ("prof", 27), ("pwr", 30), ("sys", 31),
    ("winch", 28)
)

# PORT: pl-setup.c signal_index
# DIVERGES: `name` is a Julia string; the bound `strlen(name) < 12` is on its UTF-8 bytes, as upstream's.
"The number of the signal `name` names — `term`, or `SIGTERM` (an uppercase `SIG` prefix, then any case) — or -1 (pl-setup.c)."
function signal_index(name::AbstractString)::Int
    if startswith(name, "SIG") && ncodeunits(name) < 12
        name = lowercase(SubString(name, 4))            # strcpy(tmp, name+3); strlwr(tmp)
    end

    for (n, sig) in SIGNAMES
        n == name && return sig
    end

    return -1
end

# PORT: pl-setup.c PL_get_signum_ex
# DIVERGES: returns the number, or `nothing` with the error raised (see `PL_get_integer_ex`). `PL_get_chars(sig, &s,
# CVT_ATOM)` is a text atom: not `[]` (a reserved symbol), not a blob.
"""
The signal number term reference `sig` holds — an integer, or a signal name (`term`, `SIGTERM`) — in 1..31, or `nothing`
after raising `type_error(signal, Sig)` (neither) or `domain_error(signal, Sig)` (out of range, or no such name) (pl-setup.c).
"""
function PL_get_signum_ex(ld::PL_local_data{T}, sig::term_t)::Union{Nothing, Int} where {T}
    i = PL_get_integer(ld, sig)
    if i === nothing
        a = PL_get_atom(ld, sig)
        if a !== nothing && !is_reserved_symbol(a) && !is_blob(a)
            i = signal_index(sym_text(a))
        else
            PL_error(ld, ERR_TYPE, mk_sym(T, :signal), sig)
            return nothing
        end
    end

    if i > 0 && i < 32                                  # where to get these?
        return i
    end

    PL_error(ld, ERR_DOMAIN, mk_sym(T, :signal), sig)
    return nothing
end

# PORT: pl-setup.c setupProlog
# (swipl-devel cbf4e189, src/pl-setup.c:101-186; the steps it runs are cited at each line below)
# DIVERGES: upstream fills the process's one `GD`; this makes a NEW database state and returns it (one per
# `PL_global_data{T}`). It is the unbooted half of `PL_initialise` (pl-init.c:1603): `boot_global_data` (src/pl-qlf.jl)
# runs the boot over it, and src/pl-global.jl's `PL_global_data{T}()` is a copy of that booted database (R2 LB4 b2-1).
"The database state before the boot: modules, supervisors, atoms, functors, flags, built-ins, operators (pl-setup.c)."
function setupProlog(::Type{T})::PL_global_data{T} where {T}
    cd = initSupervisors()
    modules = module_table{T}()                 # initModules: system, then user
    system = _lookupModule!(modules, cd, mk_sym(T, :system))
    user = _lookupModule!(modules, cd, mk_sym(T, :user))
    dc = mk_sym(T, Symbol("\$c_call_prolog"))
    dc_def = Definition{T}(
        sym_key(dc), 0, ClauseList{T}(), UInt64(0), dc, cd.virgin, ClauseRef{T}[], cd, 0,
        system.index, 1
    )
    dc_proc = Procedure{T}(dc_def, UInt32(0), UInt32(0))
    top_clause, top_cref = initVM(dc_proc)
    system.procedures[(sym_key(dc), 0)] = dc_proc
    atoms = do_init_atoms!(atoms_t())          # initAtoms (setup: before everything here)
    syms = atom_symbols{T}()                   # (the atoms' symbols: filled as words are made)
    registerBuiltinAtomSymbols!(atoms, syms)   # (the built-in atoms' symbols: upstream's a->name, pl-atom.c:1977)
    functors = initFunctors!(functors_t())     # initFunctors (after the atoms, as upstream's)
    initDBRef!(atoms)                          # initDBRef (setup:146): the clause blob type (D1)
    initTries!(atoms)                          # initTries (setup:149): the trie blob type (TAB1 TR1)
    initWrap!(atoms)                           # initWrap (setup:152): the closure blob type (TAB1-min)
    dexpr = first(lookupBlob(atoms, Vector{UInt8}(codeunits("\$expr")), 5, reserved_symbol))
    dot2 = lookupFunctorDef(functors, _atom_word!(atoms, syms, mk_sym(T, Symbol("[|]"))), 2)
    nilw = _atom_word!(atoms, syms, mk_nil(T))  # ATOM_nil's word, once (L1c-6)
    # (L1d step 4) the index's fixed keys ARE the database's words — built-ins registered in a fixed
    # order (`registerBuiltinAtoms`, `registerBuiltinFunctors`), as upstream's generated handles
    dot2 == FUNCTOR_dot2 || error("FUNCTOR_dot2 is not this database's '[|]'/2 word")
    nilw == ATOM_nil || error("ATOM_nil is not this database's [] word")
    gd = PL_global_data{T}(
        gen_t(0),
        Dict{Definition{T}, dirty_def_info{T}}(),
        false,
        registerControlFunctors(T),
        modules,
        user,
        system,
        _subclause_names(T),
        cd,
        dc_proc,
        dc_proc,                                # procedures_equals2: set by initBuildIns!
        dc_proc,                                # procedures_dcall1: set by initBuildIns!
        dc_proc,                                # procedures_catch3: set by initBuildIns!
        dc_proc,                                # procedures_dwakeup1: set by initBuildIns!
        dc_proc,                                # procedures_arg3: set by initBuildIns!
        top_clause,
        top_cref,
        mk_nil(T),
        mk_sym(T, Symbol("[|]")),
        T[],
        Dict{UInt64, SourceFile{T}}(),
        SourceFile{T}[],
        1,                                      # files.no_hole_before = 1
        IdDict{IOSTREAM, T}(),
        Dict{UInt64, IOSTREAM}(),
        Dict{Int, Vector{T}}(),
        Union{Nothing, IOSTREAM}[],
        atoms,
        syms,
        functors,
        dexpr,
        dot2,
        nilw,
        prolog_flag_table{T}(),                 # prolog_flag: none yet (initPrologFlags! defines them)
        Clause{T}[],                            # clause_refs: no clause has a reference yet
        IdDict{Clause{T}, Int}(),               # clause_serials
        false,                                  # bootsession: no boot compilation until LB3's `-b` path sets it
        Dict{word, RecordList{T}}(),            # record_lists: no key has a record yet
        RecordList{T}[],                        # record_lists_order
        RecordRef{T}[],                         # record_refs: no record has a reference yet
        0,                                      # halt_status: no halt in progress
        0,                                      # halt_thread
        CLN_NORMAL,                             # halt_cleaning
        0,                                      # halt_cancelled
        true,                                   # halt_exit: the process exit
        Int[],                                  # halt_exited
        event_hooks{T}(),                       # event.hook: no listener yet (R2 EV1)
        closure{T}[],                           # closure_refs: no closure has a reference yet (TAB1-min)
        trie{T}[],                              # tries: no trie has a handle yet (TAB1 TR1)
        "",                                     # paths.CWDdir: none until the first PL_cwd (R2 LB2b)
        dc_proc,                                # procedures_print_message2: set by initBuildIns!
        dc_proc,                                # procedures_reset3: set by initBuildIns!
        dc_proc,                                # procedures_dtbl_reset6: set by initBuildIns!
        dc_proc,                                # procedures_call_continuation1: set by initBuildIns!
        dc_proc,                                # procedures_dmeta_call1: set by initBuildIns!
        dc_proc,                                # procedures_findall_loop4: set by findReset
        dc_proc,                                # procedures_trie_gen_compiled2: set by initTries!(gd) (TR4)
        dc_proc,                                # procedures_trie_gen_compiled3: set by initTries!(gd) (TR4)
        GEN_INVALID,                            # reload_generation: no file is being reloaded (R2 LB6a)
        initDefaultOptions!(pl_options_t()),    # options: pl-init.c initDefaultOptions, before the command line is read (R2 LB7)
        pl_cmdline_t(),                         # cmdline: no arguments, packs on, no -O (R2 LB7)
        nothing,                                # defaults_home: set with the `home` flag by initPrologFlags!
        LDTable(),                              # ld_table: no wrapped stream yet (R2 TOP1b E)
        Dict{Int, delay_info}(),                # tabling_answer_delay_infos: initTabling's newHTablePP(64) (pl-tabling.c:12696; TAB1 TB0)
        0,                                      # tabling_start_node_ids: no start node id handed out (pl-tabling.c:12348; TAB1 TB1)
        Dict{word, Flag{T}}(),                  # flags_table: initFlags' newHTableWP(FLAGHASHSIZE) (pl-flag.c; FL1b)
        Flag{T}[]                               # flags_order
    )
    initPrologFlags!(gd)                        # setup:136 (src/os/pl-prologflag.jl): before the built-ins (:158), whose boot clauses read the mask
    initTries!(gd)                              # initTries (setup:149), its tail: trie_gen_compiled/2,3 (TR4, src/pl-trie.jl)
    initBuildIns!(gd)                           # setup:158 (src/pl-ext.jl)
    initOperators!(gd)                          # setup:164 (src/pl-op.jl)
    return gd
end
