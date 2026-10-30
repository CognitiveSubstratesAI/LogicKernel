# UPSTREAM: swipl-devel src/pl-global.h @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-incl.h @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-variant.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1997-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE GLOBAL AND THREAD-LOCAL DATA the clause database reads — the fields of SWI-Prolog's
# `struct PL_global_data` (GD) and `struct PL_local_data` (LD) that the ported code uses.
#
# DIVERGES (both structs): upstream has ONE GD per process and one LD per thread, reached through
# globals. The kernel allows no module-level mutable state (tools/lint_globals.jl), so a GD and an
# LD are VALUES the caller creates and passes wherever upstream reads `GD->` or `LD->` — one pair
# per database, over one term type `T`. There are no threads (upstream: one LD per thread or
# engine): one LD per GD, by convention — nothing enforces it, and clause GC marks the frames of the
# one LD it is given, where upstream marks every thread's (the divergence audit, docs/divergence_audit.md). One process-wide counter is
# allowlisted (`_KERNEL_VAR_COUNTER`, tools/lint_globals.jl).

# PORT: pl-global.h source_location
# DIVERGES: the file is the atom (`nothing` for NULL_ATOM).
"Where a term starts: its source file and position (pl-global.h)."
mutable struct source_location{T}
    file::Union{Nothing, T}     # current source file
    position::IOPOS             # Line, line pos, char and byte
end

# PORT: pl-global.h PL_global_data
"""
    PL_global_data{T}()

The database-wide state (pl-global.h `struct PL_global_data`): the generation of the database,
the predicates with erased clauses, whether clause GC is running, the control functors the clause
compiler reads (pl-funct.c `registerControlFunctors`, the `CONTROL_F` flags of upstream's functor
table), registered once, when the database is created, as upstream registers them at start-up,
and the `user` module, whose procedure table holds the database's predicates. Field names are
upstream's, nesting flattened (`procedures.dirty` is `procedures_dirty`).
"""
mutable struct PL_global_data{T}
    _generation::gen_t                                          # generation of the database
    procedures_dirty::Dict{Definition{T}, dirty_def_info{T}}    # procedures.dirty
    clauses_cgc_active::Bool                                    # clauses.cgc_active: CGC running
    const functors_control::ControlFunctors                     # functors.array's CONTROL_F
    const modules::module_table{T}                              # tables.modules: the modules (creation order, by name)
    const modules_user::module_t{T}                             # modules.user: user module
    const modules_system::module_t{T}                           # modules.system: system module
    const subclause_names::SubClauseNames                       # (the ATOM_/FUNCTOR_ tables)
    const code_data::PL_code_data                               # PL_code_data (its supervisors)
    const procedures_dc_call_prolog0::Procedure{T}              # procedures.dc_call_prolog0
    procedures_equals2::Procedure{T}                            # procedures.equals2: =/2
    procedures_dcall1::Procedure{T}                             # procedures.dcall1: '<meta-call>'/1
    procedures_catch3::Procedure{T}                             # procedures.catch3: catch/3
    procedures_dwakeup1::Procedure{T}                           # procedures.dwakeup1: '$wakeup'/1 (AV3)
    const clauses_top_clause::Clause{T}                         # clauses.top_clause
    const clauses_top_cref::ClauseRef{T}                        # clauses.top_cref
    const atom_nil::T                                           # ATOM_nil, the `[]` term
    const atom_dot::T                                           # ATOM_dot, the `'[|]'` symbol
    const no_literals::Vector{T}                                # (a supervisor's literal table)
    const files_table::Dict{UInt64, SourceFile{T}}              # files.table: name → source file
    const files_array::Vector{SourceFile{T}}                    # files.array: index → source file
    files_no_hole_before::Int                                   # files.no_hole_before
    const stream_filenames::IdDict{IOSTREAM, T}                 # (pl-file.c's stream context)
    const stream_aliases::Dict{UInt64, IOSTREAM}                # streamAliases: user alias (sym_key) → stream
    const stream_alias_names::Dict{Int, Vector{T}}              # stream_context.alias_head: a stream's aliases, by IOSTREAM.context
    const stream_table::Vector{Union{Nothing, IOSTREAM}}        # streamContext: the streams Prolog knows; IOSTREAM.context indexes it, a closed stream's entry is `nothing`
    const atoms::atoms_t                                        # atoms: the atom table (L1b A)
    const atom_symbols::atom_symbols{T}                         # (each atom's symbol, L1b C6b)
    const functors::functors_t                                  # functors: the table (L1b B)
    const atom_dexpr::UInt64                                    # (`$expr`, a reserved atom: L1c)
    const functor_dot2::UInt64                                  # FUNCTOR_dot2: '[|]'/2's word
    const atom_nil_w::UInt64                                    # ATOM_nil's WORD (L1c-6)
    const prolog_flag::prolog_flag_table{T}                     # prolog_flag: the Prolog flags (R2 F1a)
    const clause_refs::Vector{Clause{T}}                        # (pl-dbref.c: the clause a clause blob names, by its number in the payload; R2 D1)
    const clause_serials::IdDict{Clause{T}, Int}                # (a clause's number in `clause_refs`; R2 D1)
    bootsession::Bool                                           # bootsession: compiling the boot file (R2 LB2)
end
# DIVERGES: `atoms` is upstream's `GD->atoms` as a struct of its own (src/pl-atom.jl), one table per
# database, built first as upstream's `initAtoms` runs first; `functors` likewise `GD->functors` with
# pl-funct.c's `functorDefTable` (src/pl-funct.jl), built after it. `atom_symbols` has no upstream
# field: each atom's interface symbol, which upstream's atom record holds as its name
# (src/pl-atom.jl `atom_symbols`, L1b C6b), shared by every engine made for the database.
# Since R2 F1a: `prolog_flag`, `GD->prolog_flag` (the table of src/pl-incl.jl, filled by `initPrologFlags!`).
# `subclause_names` has no upstream field — upstream's compiler reads its `ATOM_*` and
# `FUNCTOR_*` constants (src/pl-funct.jl); like the control functors, the kernel registers them once
# per database. The module table (`tables.modules`, since V5c a vector: src/pl-modul.jl) holds the
# `system` and `user` modules, created with the database as upstream's initModules creates them at
# start-up (pl-modul.c), `user`'s super module `system`, which the built-ins are registered in
# (`initBuildIns!`, src/pl-ext.jl): a call from `user` reaches a built-in through `autoImport`
# (src/pl-proc.jl), as decided since Q-A. The shared
# supervisors are the database's (`PL_code_data`, src/pl-incl.jl). `$c_call_prolog/0`, the top
# frame's predicate, is created as `setBuiltinPredicateProperties` creates it (no clauses, flags 0,
# `SUPERVISOR(virgin)`), in the `system` module's table. `initVM` builds the top clause, and then
# the built-ins are registered — upstream registers them first (setup:158, then 160); neither reads
# the other. `procedures_equals2`, `procedures_dcall1` (since V9e-2), `procedures_catch3` (since V9f) and `procedures_dwakeup1` (since AV3) are set where upstream sets them, by `setBuiltinPredicateProperties!`
# at the end of `initBuildIns!`, once `=/2` is registered (until then it holds `$c_call_prolog/0`,
# which nothing reads it as). `atom_nil` and
# `atom_dot` are the terms the VM writes for `[]` and a list cell's head, built once — upstream's are
# constants; `no_literals` is the literal table a supervisor's code has (none). Since R1f the source
# files (`files.table`, keyed by the name's `sym_key`; `files.array`, a vector — no hole is ever
# made, as no source file is destroyed: no unload), created with the database where upstream makes
# the table at the first lookup; and `stream_filenames`, the file name of an open stream, which
# upstream keeps in the stream's context (pl-file.c `streamContext`, the stream table) — the
# loader registers the stream it opens. Since R2's S1 the stream table has landed: `stream_table`
# (`streamContext`: the streams Prolog knows, `IOSTREAM.context` their index), `stream_aliases`
# (`streamAliases`: the user aliases) and `stream_alias_names` (each stream's `alias_head`).
# Since R2's D1: `clause_refs` and `clause_serials`, the clauses a clause blob names (pl-dbref.c: upstream's blob
# holds the `Clause` pointer, here its number in `clause_refs`, `clause_serials` its inverse); the clause blob type is
# registered where pl-setup.c:146 calls `initDBRef`. Since R2's LB2: `bootsession`, `GD->bootsession` (pl-global.h), false
# unless a boot compilation sets it (`lookupSourceFile` marks a file `system`, `from_state` and `resource` while it is on).
function PL_global_data{T}() where {T}
    cd = initSupervisors()
    modules = module_table{T}()                 # initModules: system, then user
    system = _lookupModule!(modules, cd, mk_sym(T, :system))
    user = _lookupModule!(modules, cd, mk_sym(T, :user))
    dc = mk_sym(T, Symbol("\$c_call_prolog"))
    dc_def = Definition{T}(
        sym_key(dc), 0, ClauseList{T}(), UInt64(0), dc, cd.virgin, ClauseRef{T}[], cd, 0,
        system.index
    )
    dc_proc = Procedure{T}(dc_def, UInt32(0), UInt32(0))
    top_clause, top_cref = initVM(dc_proc)
    system.procedures[(sym_key(dc), 0)] = dc_proc
    atoms = do_init_atoms!(atoms_t())          # initAtoms (setup: before everything here)
    syms = atom_symbols{T}()                   # (the atoms' symbols: filled as words are made)
    functors = initFunctors!(functors_t())     # initFunctors (after the atoms, as upstream's)
    initDBRef!(atoms)                          # initDBRef (setup:146): the clause blob type (D1)
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
        false                                   # bootsession: no boot compilation until LB3's `-b` path sets it
    )
    initPrologFlags!(gd)                        # setup:136 (src/os/pl-prologflag.jl): before the built-ins (:158), whose boot clauses read the mask
    initBuildIns!(gd)                           # setup:158 (src/pl-ext.jl)
    initOperators!(gd)                          # setup:164 (src/pl-op.jl)
    return gd
end

# (swipl-devel cbf4e189 pl-incl.h:2969-2970)
# PORT: pl-incl.h ACCESS_LEVEL_USER
"The `access_level` value of the default user view (pl-incl.h)."
const ACCESS_LEVEL_USER = 0
# PORT: pl-incl.h ACCESS_LEVEL_SYSTEM
"The `access_level` value of low-level access (pl-incl.h)."
const ACCESS_LEVEL_SYSTEM = 1

# PORT: pl-incl.h MODULE_user
"The user module of the database whose global data is `gd` (pl-incl.h `MODULE_user`)."
MODULE_user(gd::PL_global_data{T}) where {T} = gd.modules_user

# PORT: pl-incl.h MODULE_system
"The system module of the database whose global data is `gd`, where built-ins live (pl-incl.h `MODULE_system`)."
MODULE_system(gd::PL_global_data{T}) where {T} = gd.modules_system

# ── the kernel's variable keys ───────────────────────────────────────────────────────────────────
# DIVERGES: SWI's fresh variables are new cells on the global stack, unique by address. Interface
# variables are keys, so the kernel takes its own from the top half of the key space (callers own
# the bottom half — see `var_key`), from ONE PROCESS-WIDE counter: an answer retained from one
# `PL_local_data` and passed into another can carry a kernel key, which a per-instance counter
# would issue again (user, 2026-10-03). Module-level state, allowlisted in tools/lint_globals.jl:
# a monotonic source of fresh ids cannot carry behaviour from one caller to another.
# the next free kernel variable key (see `fresh_var_keys!`) — a comment, not a docstring: a docstring
# on a constant keeps a second binding to the value, which the global-state lint rightly flags
const _KERNEL_VAR_COUNTER = Threads.Atomic{UInt64}(KERNEL_VAR_BASE)

"""
    fresh_var_keys!(n) -> UInt64

Reserve `n` kernel variable keys, never issued before in this process: they are
`first, first + 1, …, first + n - 1`. Thread-safe.
"""
function fresh_var_keys!(n::Int)::UInt64
    first = Threads.atomic_add!(_KERNEL_VAR_COUNTER, UInt64(n))
    @assert first >= KERNEL_VAR_BASE && first + UInt64(n) > first "kernel variable keys exhausted"
    return first
end

# PORT: pl-variant.c node as vt_node
# (the `_cells` entries of src/pl-variant.jl use it and `vt_pairs`, as fields of the local data)
# DIVERGES: `bp` a LOCATION (src/pl-prims.jl `_deref_loc`: a global position, `-i` for slot `i`).
"A numbered variable or compound of one `=@=` walk on cells (pl-variant.c `node`)."
struct vt_node
    bp::Int                         # the location of the cell it numbers
    orig::word                      # the cell's word (upstream: saved, as the cell is overwritten)
    a::Int                          # variant at left (`node_variant`)
    b::Int                          # link to an isomorphic node (`node_isom`)
end

# PORT: pl-variant.c argPairs as vt_pairs
# DIVERGES: on LOCATIONS: `left`/`right` the next argument pair's, 0 for the sentinel `isomorphic`
# pushes (upstream's NULL); the work pushed aside on `stack` as `(left, right, arg, arity)`. Reused by
# the local data: one allocation-free walk after the first.
"The agenda of argument pairs of one `=@=` walk on cells (pl-variant.c `argPairs`)."
mutable struct vt_pairs
    left::Int                       # current work: the left argument's location
    right::Int                      # … the right one's
    arg::Int                        # the next argument (0-based)
    arity::Int                      # the number of arguments
    stack::Vector{NTuple{4, Int}}
end

# PORT: pl-global.h statistics as ld_statistics
# DIVERGES: only `PL_local_data.statistics` (the per-thread counters); `GD->statistics` has no struct here:
# its `user_cputime` (the process's CPU time statistics/2 last read) is `process_cputime`, and its counts
# of atoms, functors, predicates, clauses, modules and codes are read from the tables (src/pl-prims.jl
# `swi_statistics`). `errors` and `warnings` are not counted. The field types are upstream's, `uint64_t`
# as `Int64`. `start_time` is the creation of the local data (`WallTime()`, src/os/pl-os.jl).
"The counters of `statistics/2` that belong to one thread (pl-global.h `LD->statistics`, Y1)."
mutable struct ld_statistics
    inferences::Int64                                           # inferences in this thread
    last_cputime::Int64                                         # milliseconds last CPU time
    last_systime::Int64                                         # milliseconds last SYSTEM time
    last_real_time::Int64                                       # Last Real Time (seconds since Epoch)
    start_time::Float64                                         # When Thread was started
    last_walltime::Float64                                      # Last Wall time (m-secs since start)
    user_cputime::Float64                                       # User saved CPU time
    system_cputime::Float64                                     # Kernel saved CPU time
    process_cputime::Float64                                    # GD->statistics.user_cputime
end
ld_statistics() = ld_statistics(0, 0, 0, 0, WallTime(), 0.0, 0.0, 0.0, 0.0)

# PORT: pl-global.h PL_local_data
# DIVERGES: `index_ctx` is scratch upstream declares on the C stack in each firstClause/nextClause.
# Since L1f (f3) every variable is a cell on `gstack`, the global stack (`gTop`), bound by overwriting
# it, as upstream's; `mark_bar` is upstream's. Since L1b stage D the trail holds upstream's ENTRY WORDS
# (pl-data.h's `TAG_TRAILADDR`/`TAG_TRAILVAL` in bit 0; src/pl-inline.jl `_trail_addr`): an address
# entry names a cell by position and stack, `(pos << 3) | (stack << 1)`; a value entry
# `tagTrailPtr(gpos)` names the old value saved at global position `gpos`, above its address entry. Since L1b stage C2 the global stack holds WORDS (pl-data.h): an unbound
# cell is 0 (`setVar`), a bound one a value-table word, `consPtr(i, TAG_COMPOUND|STG_RESERVED)`,
# naming entry `i` of `vtable` — the VALUE TABLE, transitional (the workspace's L1_plan §5 L1b),
# which holds every bound value until its kind has a word form (atoms and small integers: stage C3;
# floats, big numbers, strings: C4; compounds: L1c). Each entry is pinned by a BOX, a word of its own
# on the global stack (`vbox`), so when `Undo` lowers `gTop` the table is truncated with it: an
# entry never outlives the stack it shadows. Since stage C3 an atom is its own word (`TAG_ATOM`),
# and since L1d step 4 a small integer (`consInt`, `TAG_INTEGER|STG_INLINE`; until then it stayed a
# table entry), off the table. An engine's atom words name atoms in its
# DATABASE's table (`atoms` is `GD->atoms`, the database the engine is made for: since L1b, before
# C6b, every engine has one — two engines on one database share their atom words, as clause code
# carrying words needs). An atom word's symbol is read from the DATABASE's store (`atom_symbols`,
# the same object as `GD`'s; since L1b C6b — user, 2026-10-15: no per-engine cache, as every SWI engine
# reads the one atom record); `atom_words` is the engine's cache of the other direction, a symbol's
# atom word, so a symbol's text is looked up once per engine (correct whatever it holds: one atom
# per text, so a miss finds the same word in the table). `trail` is `stacks.trail` (its
# length is `tTop`), its entries (above). A cyclic link or
# a visited mark overwrites a functor cell, as upstream's; the stacks that restore them are
# upstream's (`cycle_cells` with the saved words: `cycle.lstack`; `occurs_cells`: `var_occurs_in`'s
# `visited`). The agendas and the `visited` stacks are scratch upstream keeps on
# the C stack; kept here, and emptied entry by entry, a warm unification allocates nothing.
# `stacks.local` is the cells `slots` and the pools of frame, choice-point and foreign-frame records
# (src/pl-incl.jl § the local stack; since L1b stage C5 a cell is a WORD — src/pl-inline.jl
# `SLOT_VALUE`: a reference to a global cell, an atom, a compound, a tagged integer, a value-table
# word, or `SLOT_VALUE`, the value in the cell's own entry of `slot_values` — audit D-0024's side
# value, an indirect in a slot older than the innermost foreign frame); its
# `top` and `max` and LD's `environment`, `choicepoints` and
# `foreign_environment` are named by the macros upstream's code reads them through — `lTop`, `lMax`,
# `environment_frame`, `BFR` and `fli_context` — and the last three are pool indices (0 = NULL).
# `stacks.limit` is the local stack's alone, in positions: there is no global or trail stack to
# share it with. `query` is a query-frame index (0 = NULL). The argument stack `astack` holds
# `argstack_entry`s (upstream: `Word*`). Since L1c a compound is built IN PLACE on the global stack,
# as upstream's (the write-mode builder of decision 2 is gone); `functors` is the database's
# `GD->functors` (`$expr` and `FUNCTOR_dot2` copied from it), and `cold_imports` counts the terms
# copied onto the stack (`_compound_word!`) and the fresh cells a write gives its variables: no
# upstream field, the writers' meter. The `exception.*`
# fields are term references (`term_t`), allocated by `emptyStacks` as upstream allocates them.
# The local stack's `spare` and `def_spare` are `stacks.local`'s, in positions (since V5d); the global
# stack's and the trail's since L1f f1b (audit D-0042): reserves counted in the one limit (`_stacks_in_use`). `outofstack` is upstream's `LD->outofstack` for the one stack that can
# overflow, the local stack, so a flag. `unusable` has no upstream field: a second overflow of the
# local stack before the first is recovered from marks the engine broken, where upstream ends the
# process (`outOfStack`, src/pl-alloc.jl; user, 2026-10-07).
# `GD` is the database of the query `PL_open_query` opened last (since V9c): upstream's code reaches
# the global data as a process global (`GD`), and a built-in here receives LD alone (`t0, ac, ctx`),
# so one that changes the database (`assertz/1`) reads it through this field; `nothing` until a
# query is opened. Since R1f: `read_source` (the start of the term read last), the style checks
# (`_debugstatus.styleCheck`, pl-init.c's default), `modules.source` (a module index: `user`), and
# `messages` — no upstream field: `printMessage` appends `(kind, message)` there, as print_message/2
# (boot/messages.pl, R2) is not ported; the loader returns them. Since R1e's write/1 family:
# `variable_names` (since R1g) — upstream's GLOBAL VARIABLE `$variable_names`, which boot/init.pl
# sets to the bindings of the clause being loaded (`b_setval`) and the compiler reads for its
# warnings (`get_variable_names`); the kernel has no global variables (pl-gvar.c), so it is a term
# reference here, 0 while there is no such variable. `IO_streams` — upstream's `IO.streams`, the standard streams indexed by `SNO_*` (+1), opened over
# the process's stdin, stdout and stderr when first asked for (`initIO`, src/os/pl-file.jl), or set
# by the host (`set_standard_stream!`; decision 2a), `IO_initialised` once they are; `IO_stream_type_check` (the `stream_type_check`
# flag), `IO_portray_nesting` (since group F, D-0123: the depth of nested `callPortray` calls, src/pl-write.jl), `var_names_numbervars_frame` (the foreign frame `BEGIN_NUMBERVARS` opens, 0: none) and three
# flags as swipl 10.1.16 has them: `unknown_option` (`ignore`), `write_attributes` (`ignore`),
# `character_escapes_unicode` (`true`).
# Since V9f: `prolog_flag_determinism_error`, the `determinism_error` flag — `:error` (the default),
# `:warning` or `:silent` — which upstream reads from the flag table (`PL_current_prolog_flag`).
# Since V9g-b: `bags`, upstream's `bags` (a `findall_state`: the stack of findall/3's bags, the
# innermost last — src/pl-bag.jl).
# Since NF1: `between_states`, the pool of between/3's states (`foreign_state_pool`, pl-incl.jl):
# upstream `malloc`s them (`allocForeignState`). Since NF2: `retract_contexts` and `clause_contexts`,
# the pools of retract/1's and clause/2's states, and `retract_ctxbuf`, retract/1's first-call buffer
# (upstream's `ctxbuf`, on the C stack: no Prolog runs during the call, so one record serves).
# Since NF3: `op_enums`, the pool of current_op/3's and `$local_op/3`'s states (`op_enum`, pl-incl.jl).
# Since AV1: three of upstream's `attvar` fields — `head` and `tail`, the wakeup list's term references
# (`emptyStacks!` makes them, with PERMANENT cells as the exception's: audit D-0122 Q1 (a)), and
# `attvars`, the chain of attributed variables (`register_attvar`, `reclaim_attvars`) as a global
# position, 0 for NULL. Since AV9 `call_residue_vars_count` (call_residue_vars/2's nesting:
# `trail_new_attvar`, src/pl-attvar.jl). NOT PORTED: `gc_attvars` (the collector's, G1).
# Since R2 F1a: `prolog_flag_mask` (`LD->prolog_flag.mask`, a copy of the database's) and `prolog_flag_enums`,
# the pool of current_prolog_flag/2's states.
"""
    PL_local_data{T}(gd)

The thread-local state (pl-global.h `struct PL_local_data`): the predicates ongoing enumerations
reference, at the generation each started in — so clause GC keeps what they can still see — and
the state of unification: the bindings, the trail that undoes them back to a [`mark`](@ref), the
`occurs_check` flag, and the records the unifier keeps while it walks; and the local stack — its
cells, its frames, choice points and foreign frames, and the registers that point into it. A new
one has upstream's initial local stack, emptied as `emptyStacks` leaves it: one foreign frame at
its base. It is made for the database `gd`: its atom words name atoms in `gd.atoms` (`GD->atoms`).
"""
mutable struct PL_local_data{T}
    predicate_references::Vector{definition_ref{T}}            # Referenced predicates
    trail::Vector{UInt64}                                       # stacks.trail: its entries (L1b D)
    gstack::Vector{UInt64}                                      # stacks.global: its WORDS (L1b C2)
    gTop::Int                                                   # stacks.global.top
    vtable::Vector{T}                                           # (the value table, L1b: see above)
    vbox::Vector{Int}                                           # … each entry's box on the stack
    atoms::atoms_t                                              # GD->atoms: its database's (L1b C3)
    atom_words::Dict{UInt64, UInt64}                            # (a CACHE of GD's lookupAtom)
    atom_symbols::atom_symbols{T}                               # GD's: an atom's symbol (C6b)
    functors::functors_t                                        # GD->functors: its database's
    atom_dexpr::UInt64                                          # GD's `$expr` (L1c)
    functor_dot2::UInt64                                        # GD's FUNCTOR_dot2 (L1c)
    atom_nil_w::UInt64                                          # GD's ATOM_nil word (L1c-6)
    int_word_keys::Bool                                         # (a small integer keys by its word: L1d step 4)
    cold_imports::Int                                           # (terms copied onto the stack)
    mark_bar::Int                                               # mark_bar
    prolog_flag_occurs_check::occurs_check_t                    # prolog_flag.occurs_check
    prolog_flag_portable_vmi::Bool                              # truePrologFlag(PLFLAG_PORTABLE_VMI)
    prolog_flag_last_call::Bool                                 # truePrologFlag(PLFLAG_LASTCALL)
    prolog_flag_optimise::Bool                                  # truePrologFlag(PLFLAG_OPTIMISE)
    prolog_flag_optimise_unify::Bool                            # truePrologFlag(PLFLAG_OPTIMISE_UNIFY)
    arith_f_flags::UInt32                                       # arith.f.flags (V6c)
    arith_numbers::Vector{number}                               # (the numbers' C stack, pooled)
    arith_top::Int                                              # (how many of them are in use)
    arith_cells::Vector{Int}                                    # evalExpression_cells' term_stack (L1d)
    ucell_agenda::cell_agendaLR                                 # do_unify_cells' (L1c-4)
    ccell_agenda::cell_agendaLR                                 # compare's on cells (L1d)
    ocell_agenda::cell_agendaLR                                 # var_occurs_in_cells' (L1d)
    occurs_cells::Vector{Int}                                   # … its visited functor cells (FIRST_MASK)
    acell_agenda::cell_agendaLR                                 # ph_acyclic_unmark_cells' (L1d)
    acyclic_chains::Vector{NTuple{3, Int}}                      # ph_acyclic_mark_cells' chains (head, tail, p)
    cycle_cells::Vector{Int}                                    # … its cycle.lstack: linked functor cells
    cycle_saved::Vector{word}                                   # … their functor words (Q2: restored as saved)
    walk_agenda::cell_agenda                                    # the walks on cells' agenda (L1d step 5)
    tv_seen::Vector{Bool}                                       # … a variable cell's visited mark, by position
    cycle_vstack::Vector{Int}                                   # cycle.vstack: the cells visitedWord marked
    cp_vmarks::Vector{UInt8}                                    # copy_term's variable-cell marks, by position (L1d step 6)
    cp_lstack::Vector{Int}                                      # … the cells it forwarded (TrailCyclic)
    cp_stack::Vector{Int}                                       # … mark_for_copy's segstack
    cp_agenda::cell_agendaLR                                    # … copy_term's agenda (term_agendaLRD)
    vt_ids::Vector{Int32}                                       # =@='s node numbers, by position (L1d step 8a)
    vt_nodes::Vector{vt_node}                                   # … its node buffer (VARIANT_BUFFER)
    vt_agenda::vt_pairs                                         # … its argPairs
    random_state::UInt64                                        # LD->arith.random: the generator (0: not seeded; arith-b)
    frozen_bar::Int                                             # LD->frozen_bar: the frozen part of the global stack (0: none; e5)
    index_ctx::index_context{T}                                 # firstClause/nextClause scratch
    slots::Vector{word}                                         # stacks.local: the cells' WORDS
    slot_values::Vector{T}                                      # … a SLOT_VALUE cell's value (C5)
    lTop::Int                                                   # stacks.local.top
    lMax::Int                                                   # stacks.local.max
    stacks_limit::Int                                           # stacks.limit
    local_spare::Int                                            # stacks.local.spare
    local_def_spare::Int                                        # stacks.local.def_spare
    global_spare::Int                                           # stacks.global.spare (L1f f1b)
    global_def_spare::Int                                       # stacks.global.def_spare
    trail_spare::Int                                            # stacks.trail.spare
    trail_def_spare::Int                                        # stacks.trail.def_spare
    frames::Vector{localFrame{T}}                               # the frame records
    nframes::Int                                                # … live: frames[1:nframes]
    choices::Vector{choice{T}}                                  # the choice-point records
    nchoices::Int                                               # … choices[1:nchoices]: the live ones and those C_SOFTCUT unlinked
    fliframes::Vector{fliFrame}                                 # the foreign-frame records
    nfliframes::Int                                             # … live: fliframes[1:nfliframes]
    environment_frame::Int                                      # environment: current frame
    BFR::Int                                                    # choicepoints: choice-point chain
    fli_context::Int                                            # foreign_environment
    null_code::Code{T}                                          # a NULL `Code` (no clause)
    queries::Vector{queryFrame{T}}                              # the query-frame records
    nqueries::Int                                               # … live: queries[1:nqueries]
    query::Int                                                  # query: the innermost open one
    astack::Vector{argstack_entry{T}}                           # stacks.argument
    aTop::Int                                                   # … its top (entries in use)
    exception_term::Int                                         # exception.term (0: none)
    exception_bin::Int                                          # exception.bin
    exception_printed::Int                                      # exception.printed
    exception_tmp::Int                                          # exception.tmp
    exception_pending::Int                                      # exception.pending
    exception_cells::Int                                        # (bin's PERMANENT cell; printed's +1, pending's +3: L1c)
    attvar_head::Int                                            # attvar.head: the wakeup list (AV1; Q1, D-0122)
    attvar_tail::Int                                            # attvar.tail: its tail
    attvar_attvars::Int                                         # attvar.attvars: the newest link cell (0: NULL)
    attvar_call_residue_vars_count::Int                         # attvar.call_residue_vars_count (AV9)
    alerted::Int32                                              # alerted: ALERT_* (only ALERT_WAKEUP is ported, AV3)
    tmp_h::Int                                                  # tmp.h: the first of TMP_PTR_SIZE consecutive references
    tmp_top::Int                                                # tmp.top
    tmp_cells::Int                                              # (tmp.h[0]'s PERMANENT cell; tmp.h[i]'s +i, as exception_cells)
    exception_processing::Bool                                  # exception.processing
    outofstack::Bool                                            # outofstack (the local stack)
    unusable::Bool                                              # (after a second overflow)
    fast_condition::Int                                         # fast_condition (0: NULL; an index)
    chp_scratch::ClauseChoice{T}                                # (a C-stack clause_choice)
    placeholder::T                                              # (argp_t's unread term)
    GD::Union{Nothing, PL_global_data{T}}                       # (the database the engine is made for; L1c)
    read_source::source_location{T}                             # read_source: file, line, …
    debugstatus_styleCheck::Int                                 # _debugstatus.styleCheck
    modules_source::Int                                         # modules.source (an index)
    modules_typein::Int                                         # modules.typein (an index)
    messages::Vector{Tuple{Symbol, T}}                          # (printMessage's messages)
    IO_streams::Vector{Union{Nothing, IOSTREAM}}                # IO.streams[SNO_*]
    IO_initialised::Bool                                        # GD->io_initialised (per LD)
    IO_stream_type_check::Int                                   # IO.stream_type_check
    IO_portray_nesting::Int                                     # IO.portray_nesting
    var_names_numbervars_frame::Int                             # var_names.numbervars_frame
    prolog_flag_unknown_option::Int                             # prolog_flag.unknown_option
    prolog_flag_write_attributes::Int                           # prolog_flag.write_attributes
    prolog_flag_character_escapes_unicode::Bool                 # PLFLAG_CHARESCAPE_UNICODE
    variable_names::Int                                         # (gvar `$variable_names`: a term_t)
    prolog_flag_determinism_error::Symbol                       # the `determinism_error` flag
    bags::Vector{findall_bag{T}}                                # bags: findall/3's (pl-bag.c)
    between_states::foreign_state_pool{between_state}           # (between/3's REDO_PTR states, NF1)
    retract_contexts::foreign_state_pool{retract_context{T}}    # (retract/1's REDO_PTR states, NF2)
    retract_ctxbuf::retract_context{T}                          # (retract/1's C-stack `ctxbuf`)
    clause_contexts::foreign_state_pool{ClauseChoice{T}}        # (clause/2's REDO_PTR states, NF2)
    op_enums::foreign_state_pool{op_enum{T}}                    # (current_op/3's and $local_op/3's REDO_PTR states, NF3)
    prolog_flag_mask::UInt64                                    # prolog_flag.mask: the bits truePrologFlag reads (R2 F1a)
    prolog_flag_enums::foreign_state_pool{prolog_flag_enum}     # (current_prolog_flag/2's REDO_PTR states, R2 F1a)
    statistics::ld_statistics                                   # statistics: inferences, clocks (Y1)
    prolog_flag_access_level::Int                               # prolog_flag.access_level: ACCESS_LEVEL_USER or _SYSTEM (R2 LB2)
end
function PL_local_data{T}(gd::PL_global_data{T}) where {T}
    e = mk_expr(T, T[])                         # any term: the idle placeholders' (index context, …)
    ld = PL_local_data{T}(
        definition_ref{T}[], UInt64[],                              # predicate_references, trail
        UInt64[], 0, T[], Int[],                                    # gstack, gTop, vtable, vbox
        gd.atoms, Dict{UInt64, UInt64}(), gd.atom_symbols,       # GD->atoms: the database's
        gd.functors, gd.atom_dexpr, gd.functor_dot2, gd.atom_nil_w,   # GD->functors (L1c); ATOM_nil (L1c-6)
        _int_word_keys(T),                      # int_word_keys (L1d step 4)
        0,                                      # cold_imports: no import yet
        0,                                      # mark_bar: gTop, set by emptyStacks!
        OCCURS_CHECK_FALSE, true,
        true,                                   # last_call_optimisation: on (pl-prologflag.c:2410)
        false,                                  # optimise: off without -O (pl-prologflag.c:2404)
        true,                                   # optimise_unify: on (pl-prologflag.c:2405)
        UInt32(0x0081),                         # FLT_ROUND_NEAREST|FLT_UNDERFLOW (initArith)
        number[], 0, Int[],
        cell_agendaLR(0, 0, 0, 0, NTuple{4, Int}[]),               # do_unify_cells (L1c-4)
        cell_agendaLR(0, 0, 0, 0, NTuple{4, Int}[]),               # compare on cells (L1d)
        cell_agendaLR(0, 0, 0, 0, NTuple{4, Int}[]), Int[],        # the occurs check on cells (L1d)
        cell_agendaLR(0, 0, 0, 0, NTuple{4, Int}[]), NTuple{3, Int}[],   # is_acyclic on cells (L1d)
        Int[], word[],                                             # (the cycle links' cells and words)
        cell_agenda(0, 0, NTuple{2, Int}[]), Bool[], Int[],      # the walks on cells (L1d step 5)
        UInt8[], Int[], Int[], cell_agendaLR(0, 0, 0, 0, NTuple{4, Int}[]),   # copy_term on cells (L1d step 6)
        Int32[], vt_node[], vt_pairs(0, 0, 0, 0, NTuple{4, Int}[]),        # =@= on cells (L1d step 8a)
        UInt64(0),                                                 # random/1's state (arith-b)
        0,                                                         # frozen_bar (e5)
        # idle until a search resets it (`_index_context!`): any predicate will do
        index_context{T}(
            gen_t(0),
            Definition{T}(
                UInt64(0), 0, ClauseList{T}(), UInt64(0), e, code[], ClauseRef{T}[],
                PL_code_data(code[], code[], code[], code[], code[], code[]), 0, 0
            ),
            nothing,
            0,
            _TOP_POSITION,
            false
        ),
        word[], T[], 0, 0, STACK_LIMIT_DEFAULT, 0, 0, 0, 0, 0, 0, localFrame{T}[], 0,
        choice{T}[], 0,
        fliFrame[],
        0,
        0, 0,
        0, Code{T}(code[], T[], 0),
        queryFrame{T}[], 0, 0,
        Vector{argstack_entry{T}}(undef, 64), 0,
        0, 0, 0, 0, 0, 0,
        0, 0, 0,                                # attvar: head, tail (set by emptyStacks!), attvars: none
        0,                                      # attvar.call_residue_vars_count (AV9)
        Int32(0),                               # alerted: nothing
        0, 0, 0,                                # tmp: set by emptyStacks!
        false, false, false, 0,
        ClauseChoice{T}(nothing, word(0)), e,
        gd,                                     # GD: the engine's database (PL_open_query sets it again)
        source_location{T}(nothing, IOPOS()),
        SINGLETON_CHECK | SEMSINGLETON_CHECK | DISCONTIGUOUS_STYLE | NOEFFECT_CHECK,  # pl-init.c:1663
        2,                                      # modules.source: user (the module table's 2nd)
        2,                                      # modules.typein: user (the module table's 2nd)
        Tuple{Symbol, T}[],
        Union{Nothing, IOSTREAM}[nothing, nothing, nothing, nothing, nothing, nothing],
        false,                                  # the standard streams: opened when first asked
        0,                                      # stream_type_check: loose (ST_LOOSE)
        0,                                      # portray_nesting: no portray call running
        0,                                      # no numbervars frame
        0x2,                                    # unknown_option: ignore (OPT_UNKNOWN_IGNORE)
        0x040,                                  # write_attributes: ignore (PL_WRT_ATTVAR_IGNORE)
        true,                                   # character_escapes_unicode: true
        0,                                      # $variable_names: no such global variable
        :error,                                 # determinism_error: error (os/pl-prologflag.c:2708)
        findall_bag{T}[],                       # bags: none (pl-bag.c: `LD->bags` is NULL)
        foreign_state_pool{between_state}(),    # between/3's states: none
        foreign_state_pool{retract_context{T}}(),   # retract/1's states: none
        retract_context{T}(),                   # retract/1's first-call buffer
        foreign_state_pool{ClauseChoice{T}}(),  # clause/2's states: none
        foreign_state_pool{op_enum{T}}(),       # current_op/3's states: none
        gd.prolog_flag.mask,                    # prolog_flag.mask: the database's (pl-thread.c copies the creating thread's)
        foreign_state_pool{prolog_flag_enum}(),  # current_prolog_flag/2's states: none
        ld_statistics(),                        # statistics: no inference yet, started now (Y1)
        ACCESS_LEVEL_USER                       # access_level: `user` (pl-init.c:1666 sets it after the boot; swipl starts `system`, LB3's path)
    )
    allocStacks!(ld)                            # the initial local stack, its spare reserved
    emptyStacks!(ld)
    return ld
end

# PORT: pl-incl.h SYSTEM_MODE
# (pl-incl.h:2973)
# DIVERGES: a function of the local data.
"Whether the engine is in system mode: `LD->prolog_flag.access_level == ACCESS_LEVEL_SYSTEM` (pl-incl.h)."
SYSTEM_MODE(ld::PL_local_data{T}) where {T} =
    ld.prolog_flag_access_level == ACCESS_LEVEL_SYSTEM

# setAccessLevel (swipl-devel pl-init.c; called at pl-init.c:1614, :1666 and by pl-prologflag.c setAccessLevelFromAtom :707) is
# not a marked port: pl-init.c is not one of this file's UPSTREAM files. The kernel has no `set_prolog_flag(access_level, _)`
# yet (R2 F1b), so this is the only way to set the level.
"Set the engine's access level (`setAccessLevel(level)`)."
function setAccessLevel!(ld::PL_local_data{T}, level::Int) where {T}
    ld.prolog_flag_access_level = level
    return nothing
end

# setup:1600 `minlocal = 4*SIZEOF_WORD K`: the local stack a thread starts with, here in positions.
"The positions of a new local stack (pl-setup.c `allocStacks`'s `minlocal`, in words)."
const LOCAL_INITIAL = 4096

# The `stack_limit` flag's default, 1 GiB (swipl 10.1.16: `1073741824`), here in positions.
"The default `stacks_limit`, in positions: `stack_limit`'s default of 1 GiB, in words."
const STACK_LIMIT_DEFAULT = (1 << 30) ÷ 8
