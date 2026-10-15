# UPSTREAM: swipl-devel src/pl-global.h @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-incl.h @ 8609e216cab9
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
    const modules::Vector{module_t{T}}                          # tables.modules: the modules
    const modules_user::module_t{T}                             # modules.user: user module
    const modules_system::module_t{T}                           # modules.system: system module
    const subclause_names::SubClauseNames                       # (the ATOM_/FUNCTOR_ tables)
    const code_data::PL_code_data                               # PL_code_data (its supervisors)
    const procedures_dc_call_prolog0::Procedure{T}              # procedures.dc_call_prolog0
    procedures_equals2::Procedure{T}                            # procedures.equals2: =/2
    procedures_dcall1::Procedure{T}                             # procedures.dcall1: '<meta-call>'/1
    procedures_catch3::Procedure{T}                             # procedures.catch3: catch/3
    const clauses_top_clause::Clause{T}                         # clauses.top_clause
    const clauses_top_cref::ClauseRef{T}                        # clauses.top_cref
    const atom_nil::T                                           # ATOM_nil, the `[]` term
    const atom_dot::T                                           # ATOM_dot, the `'[|]'` symbol
    const no_literals::Vector{T}                                # (a supervisor's literal table)
    const files_table::Dict{UInt64, SourceFile{T}}              # files.table: name → source file
    const files_array::Vector{SourceFile{T}}                    # files.array: index → source file
    files_no_hole_before::Int                                   # files.no_hole_before
    const stream_filenames::IdDict{IOSTREAM, T}                 # (pl-file.c's stream context)
    const atoms::atoms_t                                        # atoms: the atom table (L1b A)
    const functors::functors_t                                  # functors: the table (L1b B)
end
# DIVERGES: `atoms` is upstream's `GD->atoms` as a struct of its own (src/pl-atom.jl), one table per
# database, built first as upstream's `initAtoms` runs first; `functors` likewise `GD->functors` with
# pl-funct.c's `functorDefTable` (src/pl-funct.jl), built after it. `subclause_names` has no upstream field — upstream's compiler reads its `ATOM_*` and
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
# the other. `procedures_equals2`, `procedures_dcall1` (since V9e-2) and `procedures_catch3` (since V9f) are set where upstream sets them, by `setBuiltinPredicateProperties!`
# at the end of `initBuildIns!`, once `=/2` is registered (until then it holds `$c_call_prolog/0`,
# which nothing reads it as). `atom_nil` and
# `atom_dot` are the terms the VM writes for `[]` and a list cell's head, built once — upstream's are
# constants; `no_literals` is the literal table a supervisor's code has (none). Since R1f the source
# files (`files.table`, keyed by the name's `sym_key`; `files.array`, a vector — no hole is ever
# made, as no source file is destroyed: no unload), created with the database where upstream makes
# the table at the first lookup; and `stream_filenames`, the file name of an open stream, which
# upstream keeps in the stream's context (pl-file.c `streamContext`, the stream table: R2) — the
# loader registers the stream it opens.
function PL_global_data{T}() where {T}
    cd = initSupervisors()
    modules = module_t{T}[]                     # initModules: system, then user
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
        top_clause,
        top_cref,
        mk_nil(T),
        mk_sym(T, Symbol("[|]")),
        T[],
        Dict{UInt64, SourceFile{T}}(),
        SourceFile{T}[],
        1,                                      # files.no_hole_before = 1
        IdDict{IOSTREAM, T}(),
        do_init_atoms!(atoms_t()),              # initAtoms (setup: before everything here)
        initFunctors!(functors_t())             # initFunctors (after the atoms, as upstream's)
    )
    initBuildIns!(gd)                           # setup:158 (src/pl-ext.jl)
    initOperators!(gd)                          # setup:164 (src/pl-op.jl)
    return gd
end

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
    @assert first >= KERNEL_VAR_BASE && first + UInt64(n) <= CELL_KEY_TAG "kernel variable keys exhausted"
    return first
end

# ── cell variables: the global stack's keys (L1a) ───────────────────────────────────────────────
# DIVERGES: a variable on the global stack (`allocGlobalVars!`, src/pl-inline.jl) is still an
# interface variable — a slot holds a term until L1b — so its CELL is named by a key: the cell tag
# (the top two bits), a STAMP (34 bits) and the position (28 bits). The stamp comes from ONE
# PROCESS-WIDE counter, reserved by each engine in blocks, so stamps are unique across engines and
# grow with time; the engine keeps the key of the cell living at each position (`gkey`). A key is
# this engine's live cell iff its position is at most `gTop` and `gkey` holds it: a key retained
# after its position was freed and reused, or from another engine, is not — it is a KEYED variable,
# bound in `bindings` (the workspace's L1 plan, §2). The cells of one allocation have consecutive
# keys, and keys order by stamp, then position: allocation order, as the counter's keys before L1a.
# Limits: 2^28 positions; the stamp wraps after 2^34 allocations in one process.
"The top bits of a cell variable's key (pl-global.jl, L1a): `0b11` above the kernel's keys."
const CELL_KEY_TAG = UInt64(0b11) << 62
"The bits of a cell variable's key that hold its position on the global stack."
const CELL_POS_MASK = (UInt64(1) << 28) - UInt64(1)
"The bits of a stamp, below the cell tag and above the position."
const CELL_STAMP_MASK = (UInt64(1) << 34) - UInt64(1)
"The stamps an engine reserves at a time."
const CELL_STAMP_BLOCK = UInt64(1024)
# the next free stamp (see `CELL_KEY_TAG`) — module-level, allowlisted in tools/lint_globals.jl as
# `_KERNEL_VAR_COUNTER` is: a monotonic source of fresh ids carries no behaviour between callers
const _CELL_STAMP_COUNTER = Threads.Atomic{UInt64}(1)

# PORT: pl-global.h PL_local_data
# DIVERGES: `index_ctx` is scratch upstream declares on the C stack in each firstClause/nextClause.
# `bindings` has no field upstream — SWI binds a variable by overwriting its cell on the
# global stack; interface variables are immutable values, so a binding is an entry keyed by
# `var_key`. Since L1a it holds only KEYED variables' bindings: a CELL variable's binding is in its
# cell on `gstack`, the global stack of variables (`gkey`, `gTop`; see `CELL_KEY_TAG`), and
# `mark_bar` is upstream's. Since L1b stage D the trail holds upstream's ENTRY WORDS (pl-data.h's
# `TAG_TRAILADDR`/`TAG_TRAILVAL` in bit 0; src/pl-inline.jl `_trail_addr`): an address entry names a
# cell by position and stack, `(pos << 3) | (stack << 1)`, and while keyed variables live (until
# the stamp falls) a third stack code names entry `pos` of `trail_keys`, the keyed variable's key (a
# key is too wide to shift); a value entry `tagTrailPtr(gpos)` names the old value saved at global
# position `gpos`, above its address entry. Since L1b stage C2 the global stack holds WORDS (pl-data.h): an unbound
# cell is 0 (`setVar`), a bound one a value-table word, `consPtr(i, TAG_COMPOUND|STG_RESERVED)`,
# naming entry `i` of `vtable` — the VALUE TABLE, transitional (the workspace's L1 plan §5 L1b),
# which holds every bound value until its kind has a word form (atoms and small integers: stage C3;
# floats, big numbers, strings: C4; compounds: L1c). Each entry is pinned by a BOX, a word of its own
# on the global stack (`vbox`), so when `Undo` lowers `gTop` the table is truncated with it: an
# entry never outlives the stack it shadows. Since stage C3 an atom and a small integer are their
# own words (`TAG_ATOM`, `consInt`), off the table. An engine's atom words name atoms in its OWN
# atom table (`atoms`), DIVERGES from upstream's one `GD->atoms` while nothing outside the engine
# holds a word (clauses and records are values) — 255 test lines make an engine with no database —
# until clause code carries words; `atom_words` and `atom_values` cache the symbol ↔ atom
# conversion both ways, so neither direction looks text up twice. `trail` is `stacks.trail` (its
# length is `tTop`), entries of both kinds of variable (above). A cyclic link or
# a visited mark is an entry in an identity map (`cycle_links`, `occurs_marked`) where upstream
# overwrites a functor cell; the stacks that restore them are upstream's (`cycle.lstack`,
# `var_occurs_in`'s `visited`). The agendas and the `visited` stack are scratch upstream keeps on
# the C stack; kept here, and emptied entry by entry, a warm unification allocates nothing.
# `stacks.local` is the cells `slots` and the pools of frame, choice-point and foreign-frame records
# (src/pl-incl.jl § the local stack; since L1b stage C5 a cell is a WORD — src/pl-inline.jl
# `slotValue`: a reference to a global cell, an atom, or `SLOT_VALUE`, the value in the cell's own
# entry of `slot_values`, transitional — a reference reads back as the cell's variable term, made
# ONCE when the cell is allocated and kept in `gvars` beside its key, as building one allocates;
# transitional with `gkey`, gone when the stamp falls); its `top` and `max` and LD's `environment`, `choicepoints` and
# `foreign_environment` are named by the macros upstream's code reads them through — `lTop`, `lMax`,
# `environment_frame`, `BFR` and `fli_context` — and the last three are pool indices (0 = NULL).
# `stacks.limit` is the local stack's alone, in positions: there is no global or trail stack to
# share it with. `query` is a query-frame index (0 = NULL). The argument stack `astack` holds
# `argstack_entry`s (upstream: `Word*`); the write-mode builder (`bcells`, `bframes`; decision 2, Q3)
# has no upstream field — it builds where upstream fills cells on the global stack. The `exception.*`
# fields are term references (`term_t`), allocated by `emptyStacks` as upstream allocates them.
# The local stack's `spare` and `def_spare` are `stacks.local`'s, in positions (since V5d); the
# other stacks have none. `outofstack` is upstream's `LD->outofstack` for the one stack that can
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
# flag), `var_names_numbervars_frame` (the foreign frame `BEGIN_NUMBERVARS` opens, 0: none) and three
# flags as swipl 10.1.16 has them: `unknown_option` (`ignore`), `write_attributes` (`ignore`),
# `character_escapes_unicode` (`true`). Since write_canonical: `numbervars_visited` and
# `numbervars_made`, `numberVars`' scratch (upstream's visited marks and global-stack mark).
# Since V9f: `prolog_flag_determinism_error`, the `determinism_error` flag — `:error` (the default),
# `:warning` or `:silent` — which upstream reads from the flag table (`PL_current_prolog_flag`).
# Since V9g-b: `bags`, upstream's `bags` (a `findall_state`: the stack of findall/3's bags, the
# innermost last — src/pl-bag.jl).
"""
    PL_local_data{T}()

The thread-local state (pl-global.h `struct PL_local_data`): the predicates ongoing enumerations
reference, at the generation each started in — so clause GC keeps what they can still see — and
the state of unification: the bindings, the trail that undoes them back to a [`mark`](@ref), the
`occurs_check` flag, and the records the unifier keeps while it walks; and the local stack — its
cells, its frames, choice points and foreign frames, and the registers that point into it. A new
one has upstream's initial local stack, emptied as `emptyStacks` leaves it: one foreign frame at
its base.
"""
mutable struct PL_local_data{T}
    predicate_references::Vector{definition_ref{T}}            # Referenced predicates
    bindings::Dict{UInt64, T}                                   # var_key → value (see above)
    trail::Vector{UInt64}                                       # stacks.trail: its entries (L1b D)
    trail_keys::Vector{UInt64}                                  # … the keyed variables' keys
    gstack::Vector{UInt64}                                      # stacks.global: its WORDS (L1b C2)
    gkey::Vector{UInt64}                                        # … the key of each cell's variable
    gvars::Vector{T}                                            # … and its variable term (L1b C5)
    gTop::Int                                                   # stacks.global.top
    vtable::Vector{T}                                           # (the value table, L1b: see above)
    vbox::Vector{Int}                                           # … each entry's box on the stack
    atoms::atoms_t                                              # (the engine's atom table, L1b C3)
    atom_words::Dict{UInt64, UInt64}                            # … a symbol's sym_key → its atom
    atom_values::Vector{Union{Nothing, T}}                      # … an atom's index → its symbol
    mark_bar::Int                                               # mark_bar
    stamp_next::UInt64                                          # (the engine's reserved stamps:
    stamp_end::UInt64                                           #  stamp_next until stamp_end)
    prolog_flag_occurs_check::occurs_check_t                    # prolog_flag.occurs_check
    prolog_flag_portable_vmi::Bool                              # truePrologFlag(PLFLAG_PORTABLE_VMI)
    prolog_flag_last_call::Bool                                 # truePrologFlag(PLFLAG_LASTCALL)
    prolog_flag_optimise::Bool                                  # truePrologFlag(PLFLAG_OPTIMISE)
    prolog_flag_optimise_unify::Bool                            # truePrologFlag(PLFLAG_OPTIMISE_UNIFY)
    arith_f_flags::UInt32                                       # arith.f.flags (V6c)
    arith_numbers::Vector{number}                               # (the numbers' C stack, pooled)
    arith_top::Int                                              # (how many of them are in use)
    arith_frames::Vector{Tuple{T, Int}}                         # evalExpression's term_stack
    cycle_lstack::Vector{T}                                     # cycle.lstack: linked compounds
    cycle_links::IdDict{T, T}                                   # the links themselves
    occurs_visited::Vector{T}                                   # var_occurs_in's `visited`
    occurs_marked::IdDict{T, Nothing}                           # its FIRST_MASK marks
    unify_agenda::term_agendaLR{T}                              # do_unify's `agenda`
    compare_agenda::term_agendaLR{T}                            # compare_fast's `agenda`
    occurs_agenda::term_agenda{T}                               # var_occurs_in's `agenda`
    index_ctx::index_context{T}                                 # firstClause/nextClause scratch
    slots::Vector{word}                                         # stacks.local: the cells' WORDS
    slot_values::Vector{T}                                      # … a SLOT_VALUE cell's value (C5)
    lTop::Int                                                   # stacks.local.top
    lMax::Int                                                   # stacks.local.max
    stacks_limit::Int                                           # stacks.limit
    local_spare::Int                                            # stacks.local.spare
    local_def_spare::Int                                        # stacks.local.def_spare
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
    bcells::Vector{T}                                           # the write-mode builder's cells
    bTop::Int                                                   # … in use: bcells[1:bTop]
    bframes::Vector{bframe{T}}                                  # … the compounds it is building
    nbframes::Int                                               # … open: bframes[1:nbframes]
    exception_term::Int                                         # exception.term (0: none)
    exception_bin::Int                                          # exception.bin
    exception_printed::Int                                      # exception.printed
    exception_tmp::Int                                          # exception.tmp
    exception_pending::Int                                      # exception.pending
    exception_processing::Bool                                  # exception.processing
    outofstack::Bool                                            # outofstack (the local stack)
    unusable::Bool                                              # (after a second overflow)
    fast_condition::Int                                         # fast_condition (0: NULL; an index)
    chp_scratch::ClauseChoice{T}                                # (a C-stack clause_choice)
    placeholder::T                                              # (argp_t's term but in a cursor)
    GD::Union{Nothing, PL_global_data{T}}                       # (the running query's database)
    read_source::source_location{T}                             # read_source: file, line, …
    debugstatus_styleCheck::Int                                 # _debugstatus.styleCheck
    modules_source::Int                                         # modules.source (an index)
    messages::Vector{Tuple{Symbol, T}}                          # (printMessage's messages)
    IO_streams::Vector{Union{Nothing, IOSTREAM}}                # IO.streams[SNO_*]
    IO_initialised::Bool                                        # GD->io_initialised (per LD)
    IO_stream_type_check::Int                                   # IO.stream_type_check
    var_names_numbervars_frame::Int                             # var_names.numbervars_frame
    prolog_flag_unknown_option::Int                             # prolog_flag.unknown_option
    prolog_flag_write_attributes::Int                           # prolog_flag.write_attributes
    prolog_flag_character_escapes_unicode::Bool                 # PLFLAG_CHARESCAPE_UNICODE
    numbervars_visited::IdDict{T, Nothing}                      # (numberVars' visited marks)
    numbervars_made::IdDict{T, Nothing}                         # (the '$VAR's a numberVars made)
    variable_names::Int                                         # (gvar `$variable_names`: a term_t)
    prolog_flag_determinism_error::Symbol                       # the `determinism_error` flag
    bags::Vector{findall_bag{T}}                                # bags: findall/3's (pl-bag.c)
end
function PL_local_data{T}() where {T}
    e = mk_expr(T, T[])                         # any term: the agendas' idle work nodes
    ld = PL_local_data{T}(
        definition_ref{T}[], Dict{UInt64, T}(), UInt64[], UInt64[],
        UInt64[], UInt64[], T[], 0, T[], Int[],
        do_init_atoms!(atoms_t()), Dict{UInt64, UInt64}(), Union{Nothing, T}[],
        0,                                      # mark_bar: gTop, set by emptyStacks!
        UInt64(0), UInt64(0),                   # no stamps reserved yet
        OCCURS_CHECK_FALSE, true,
        true,                                   # last_call_optimisation: on (pl-prologflag.c:2400)
        false,                                  # optimise: off without -O (pl-prologflag.c:2394)
        true,                                   # optimise_unify: on (pl-prologflag.c:2395)
        UInt32(0x0081),                         # FLT_ROUND_NEAREST|FLT_UNDERFLOW (initArith)
        number[], 0, Tuple{T, Int}[],
        T[],
        IdDict{T, T}(), T[], IdDict{T, Nothing}(),
        term_agendaLR{T}(aNodeLR{T}(e, e, 0, 0), aNodeLR{T}[]),
        term_agendaLR{T}(aNodeLR{T}(e, e, 0, 0), aNodeLR{T}[]),
        term_agenda{T}(aNode{T}(e, 0, 0), aNode{T}[]),
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
        word[], T[], 0, 0, STACK_LIMIT_DEFAULT, 0, 0, localFrame{T}[], 0, choice{T}[], 0,
        fliFrame[],
        0,
        0, 0,
        0, Code{T}(code[], T[], 0),
        queryFrame{T}[], 0, 0,
        Vector{argstack_entry{T}}(undef, 64), 0,
        Vector{T}(undef, 256), 0, Vector{bframe{T}}(undef, 64), 0,
        0, 0, 0, 0, 0,
        false, false, false, 0,
        ClauseChoice{T}(nothing, word(0)), e,
        nothing,                                # GD: set by PL_open_query
        source_location{T}(nothing, IOPOS()),
        SINGLETON_CHECK | SEMSINGLETON_CHECK | DISCONTIGUOUS_STYLE | NOEFFECT_CHECK,  # pl-init.c:1663
        2,                                      # modules.source: user (the module table's 2nd)
        Tuple{Symbol, T}[],
        Union{Nothing, IOSTREAM}[nothing, nothing, nothing, nothing, nothing, nothing],
        false,                                  # the standard streams: opened when first asked
        0,                                      # stream_type_check: loose (ST_LOOSE)
        0,                                      # no numbervars frame
        0x2,                                    # unknown_option: ignore (OPT_UNKNOWN_IGNORE)
        0x040,                                  # write_attributes: ignore (PL_WRT_ATTVAR_IGNORE)
        true,                                   # character_escapes_unicode: true
        IdDict{T, Nothing}(), IdDict{T, Nothing}(),
        0,                                      # $variable_names: no such global variable
        :error,                                 # determinism_error: error (os/pl-prologflag.c:2708)
        findall_bag{T}[]                        # bags: none (pl-bag.c: `LD->bags` is NULL)
    )
    allocStacks!(ld)                            # the initial local stack, its spare reserved
    emptyStacks!(ld)
    return ld
end

# setup:1600 `minlocal = 4*SIZEOF_WORD K`: the local stack a thread starts with, here in positions.
"The positions of a new local stack (pl-setup.c `allocStacks`'s `minlocal`, in words)."
const LOCAL_INITIAL = 4096

# The `stack_limit` flag's default, 1 GiB (swipl 10.1.16: `1073741824`), here in positions.
"The default `stacks_limit`, in positions: `stack_limit`'s default of 1 GiB, in words."
const STACK_LIMIT_DEFAULT = (1 << 30) ÷ 8
