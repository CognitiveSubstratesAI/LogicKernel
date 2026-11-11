# UPSTREAM: swipl-devel src/pl-global.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-incl.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-init.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-variant.c @ 18168e629eab
# UPSTREAM: swipl-devel src/os/pl-file.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1997-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): structure only, d755bdc4 — pl-variant.c: cell-tag access behind pl-data.h macros, no change of value, order, error or side effect. Also re-cited: pl-incl.h: access-only (d755bdc4) ported; ATOM_RESERVE_BATCH is pl-incl.jl:460 (commit 5); the PLFLAG_EPILOG comma is no value. Also re-cited: pl-global.h: the unported fields are the tabling fields (TAB1 row cfile:pl-tabling.c), LD->profile (PROF1) and LD->atoms.reserved (ATOM1), owners in docs/architecture.md (deferred owners); pl-file.c: set_eof_action, newline mode (cd67bb35, dfc1c55d, 4f259069) ported; shareStandardStream (87fc7589) is owner TH1 (docs/architecture.md, deferred owners).
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

# PORT: pl-global.h hook as event_hooks
# DIVERGES: GD's `event.hook` struct as a mutable struct of its own (a list is created at its first listener, as
# `get_event_list` does); the thread events' lists exist in every build (O_ENGINES). The LD's `onthreadexit` is a field
# of the local data (`event_hook_onthreadexit`).
"The event lists of the database (pl-global.h `GD->event.hook`): `nothing` until a first listener (NULL)."
mutable struct event_hooks{T}
    onabort::Union{Nothing, event_list{T, definition{T}}}           # the `abort` event's listeners
    onerase::Union{Nothing, event_list{T, definition{T}}}           # erased clause or dbref
    onbreak::Union{Nothing, event_list{T, definition{T}}}           # breakpoint change
    onframefinish::Union{Nothing, event_list{T, definition{T}}}     # Debugged frame finished
    onthreadstart::Union{Nothing, event_list{T, definition{T}}}     # thread start hook
    onthreadexit::Union{Nothing, event_list{T, definition{T}}}      # thread exit hook
    onuntable::Union{Nothing, event_list{T, definition{T}}}         # Untable after reload
end
event_hooks{T}() where {T} =
    event_hooks{T}(nothing, nothing, nothing, nothing, nothing, nothing, nothing)

# PORT: pl-init.h pl_options_t
# (swipl-devel cbf4e189, src/pl-init.h:61-95; `GD->options`, filled by pl-init.c `initDefaultOptions` and
# `parseCommandLineOptions`, read by `$cmd_option_val/2`, pl-prims.c:6340-6440, and by the Prolog flags)
# DIVERGES (representation only): `opt_list` (a C linked list of strings, appended at the end) is a `Vector{String}`;
# `char *` is `Union{Nothing, String}` (`nothing` = NULL); sizes are `Int` (bytes). `win_app` (Windows) is left out.
# STRUCT TYPE ONLY: the field of `PL_global_data` that holds it is LB7's struct commit (evidence/LB7/plan.md).
"""
    pl_options_t(; kw...)

The command-line options (pl-init.h `pl_options_t`): the stack and table limits in bytes, the lists `goals` (`-g`),
`scriptFiles` (`-s`, `-l`), `search_paths` (`-p`) and `defines` (`-D`), the strings `topLevel` (`-t`), `initFile`
(`-f`), `systemInitFile` (`-F`), `config`, `pldoc_server`, `bootFrom` (`-x`), `compileOut` (`-o`), `saveclass`,
`on_error` and `on_warning`, and the switches. `xpce` is `-1` until `--pce`/`--no-pce` sets it.
"""
Base.@kwdef mutable struct pl_options_t
    stackLimit::Int = 0                          # size_t stackLimit: total stack limit
    tableSpace::Int = 0                          # size_t tableSpace
    sharedTableSpace::Int = 0                    # size_t sharedTableSpace (O_PLMT)
    goals::Vector{String} = String[]             # opt_list *goals: initialization goals (-g)
    topLevel::Union{Nothing, String} = nothing   # char *topLevel: toplevel goal (-t)
    initFile::Union{Nothing, String} = nothing   # char *initFile: -f initialisation file
    systemInitFile::Union{Nothing, String} = nothing   # char *systemInitFile: -F initialisation file
    config::Union{Nothing, String} = nothing     # char *config: show config info
    scriptFiles::Vector{String} = String[]       # opt_list *scriptFiles (-s, -l)
    search_paths::Vector{String} = String[]      # opt_list *search_paths (-p path)
    defines::Vector{String} = String[]           # opt_list *defines (-Dname=value)
    pldoc_server::Union{Nothing, String} = nothing   # char *pldoc_server (--pldoc=Server)
    bootFrom::Union{Nothing, String} = nothing   # char *bootFrom (-x file)
    compileOut::Union{Nothing, String} = nothing # char *compileOut: file to store compiler output (-o)
    saveclass::Union{Nothing, String} = nothing  # char *saveclass: type of saved state
    compile::Bool = false                        # -c source ...
    silent::Bool = false                         # -q: quiet operation
    traditional::Bool = false                    # --traditional: no version 7 exts
    nothreads::Bool = false                      # --no-threads
    nosignals::Bool = false                      # --no-signals
    on_error::Union{Nothing, String} = nothing   # --on-error
    on_warning::Union{Nothing, String} = nothing # --on-warning
    xpce::Int = -1                               # int xpce: --no-pce (-1 = not given)
end

# PORT: pl-global.h cmdline as pl_cmdline_t
# (swipl-devel cbf4e189, src/pl-global.h, the `cmdline` member of `PL_global_data`: `os_argc`, `os_argv`, `appl_argc`,
# `appl_argv`, `packs`, `optimise`, `appl_malloc`)
# DIVERGES (representation only): the `argc`/`argv` pairs are `Vector{String}`; `appl_malloc` (a C allocation note) is left out.
"""
    pl_cmdline_t(; kw...)

`GD->cmdline`: the process's arguments (`os_argv`), the arguments left to the application after the options
(`appl_argv`, what the `argv` flag holds), and the switches `-O` (`optimise`) and `--no-packs` (`packs`).
"""
Base.@kwdef mutable struct pl_cmdline_t
    os_argv::Vector{String} = String[]           # os_argc, os_argv
    appl_argv::Vector{String} = String[]         # appl_argc, appl_argv
    packs::Bool = true                           # packs: attach packs (--no-packs)
    optimise::Bool = false                       # optimise: -O
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
    procedures_arg3::Procedure{T}                               # procedures.arg3: arg/3 (ARGINL)
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
    const record_lists::Dict{word, RecordList{T}}               # recorded_db.record_lists: the key's word -> its record list (R2 D2)
    const record_lists_order::Vector{RecordList{T}}             # (the lists in the order they were made, the enumeration of recorded/3 and current_key/1; R2 D2)
    const record_refs::Vector{RecordRef{T}}                     # (pl-dbref.c: the record a record blob names, by its number in the payload; R2 D2)
    halt_status::Int                                            # halt.status: code and flags of the halt in progress (HALT1)
    halt_thread::Int                                            # halt.thread: the initiating thread (HALT1)
    halt_cleaning::Int                                          # halt.cleaning: `CLN_*` (HALT1)
    halt_cancelled::Int                                         # halt.cancelled: times a halt was cancelled (HALT1)
    halt_exit::Bool                                             # (HALT1: the seam where upstream calls `exit(status)`: true, the real exit)
    const halt_exited::Vector{Int}                              # (HALT1: with the seam off, the statuses `exit` was called with)

    const event_hook::event_hooks{T}                            # event.hook: the event lists (R2 EV1)
    const closure_refs::Vector{closure{T}}                      # (pl-wrap.c: the closure a closure blob names, by its number in the payload; TAB1-min)
    const tries::Vector{trie{T}}                                # (pl-trie.c: the trie a trie blob names, by its number in the payload; TAB1 TR1)
    paths_CWDdir::String                                        # paths.CWDdir: the cached working directory, '/'-terminated ("" = none; paths.CWDlen is its byte length; R2 LB2b)
    procedures_print_message2::Procedure{T}                     # procedures.print_message2: print_message/2, printMessage's (R2 LB4 b2)
    procedures_reset3::Procedure{T}                             # procedures.reset3: reset/3 (R2 CONT1)
    procedures_dtbl_reset6::Procedure{T}                        # procedures.dtbl_reset6: '$tbl_reset'/6 (R2 CONT1)
    procedures_call_continuation1::Procedure{T}                 # procedures.call_continuation1: call_continuation/1 (R2 CONT1)
    procedures_dmeta_call1::Procedure{T}                        # procedures.dmeta_call1: '$meta_call'/1 (R2 CONT1)
    procedures_findall_loop4::Procedure{T}                      # procedures.findall_loop4: '$bags':findall_loop/4, looked up by findReset (R2 CONT1)
    procedures_trie_gen_compiled2::Procedure{T}                 # procedures.trie_gen_compiled2: system:trie_gen_compiled/2, set by initTries! (TR4)
    procedures_trie_gen_compiled3::Procedure{T}                 # procedures.trie_gen_compiled3: system:trie_gen_compiled/3, set by initTries! (TR4)
    reload_generation::gen_t                                    # reload.generation: GEN_INVALID (0) unless a file is being reloaded (R2 LB6a; DIVERGES, owner TH1: LD->reload.generation, kept here)
    const options::pl_options_t                                 # options: the command-line options, `$cmd_option_val/2`'s table (R2 LB7)
    const cmdline::pl_cmdline_t                                 # cmdline: the arguments and the -O/--no-packs switches (R2 LB7)
    defaults_home::Union{Nothing, String}                       # defaults.home: the home directory, `$cmd_option_val(home, _)` (R2 LB7; nothing = NULL)
    const ld_table::LDTable                                     # the local data a wrapped stream names by number (IOSTREAM.wrapped; src/os/pl-stream.jl, R2 TOP1b E; owner TH1)
    tabling_answer_delay_infos::Dict{Int, delay_info}           # (pl-tabling.c static `answer_delay_infos`: trie node id -> delay_info; TAB1 TB0)
    tabling_start_node_ids::Int                                 # (pl-tabling.c static `start_node_ids`: the last start-node id handed out, 0: none; TAB1 TB1)
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
# the other. `procedures_equals2`, `procedures_dcall1` (since V9e-2), `procedures_catch3` (since V9f), `procedures_dwakeup1` (since AV3) and `procedures_arg3` (since ARGINL) are set where upstream sets them, by `setBuiltinPredicateProperties!`
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
# Since R2's D2: `record_lists` (`GD->recorded_db.record_lists`, a hash table by the key's word, initRecords in pl-rec.c),
# `record_lists_order` (its entries in creation order: upstream enumerates the table, we cannot, see src/pl-rec.jl) and
# `record_refs` (the records a `record` blob names, as `clause_refs`). The constructor that fills them is
# src/pl-setup.jl's `setupProlog`.
# Since TAB1-min: `closure_refs` (the closures a `closure` blob names, as `clause_refs`; pl-wrap.c keeps the `struct closure`
# in the blob's payload, src/pl-wrap.jl).
# Since TAB1 TR1: `tries` (the tries a `trie` blob names, as `closure_refs`; pl-trie.c `trie_symbol` makes the blob with the
# `struct trie` as its data, here the trie's number in `tries` is the 8-byte payload, src/pl-trie.jl).
# Since R2's LB2b: `paths_CWDdir`, `GD->paths.CWDdir` (pl-global.h), the working directory `PL_cwd` caches and `ChDir` sets (src/os/pl-os.jl).
# Since R2 LB6a: `reload_generation`, DIVERGES (representation, owner TH1): upstream's `LD->reload.generation` is per thread; the kernel has one thread,
# so ONE copy lives here and nothing keeps a second in the local data (audit D-0416 item 3). `startReconsultFile` writes it and `endReconsult` (LB6b)
# clears it; every reader takes it from the database: the functions that have `gd` (`hasClausesDefinition` and what calls it, `num_visible_clauses`,
# `getClauses`, `setDefaultSupervisor`) directly, the ones that have `ld` (`visibleClause`/`visibleClauseCNT` with `ld`, `firstClause!`, `nextClause!`)
# through `ld.GD`. TH1 moves the field into the local data when a thread has a local data of its own.
# Since R2's LB7: `options` and `cmdline`, `GD->options` and `GD->cmdline` (pl-global.h, the records above), and `defaults_home`,
# `GD->defaults.home` (`systemDefaults.home`, pl-init.c); the other members of `GD->defaults` are build constants (pl-init.c `initDefaults`).

# PORT: pl-incl.h cleanup_status as CLN_NORMAL
# DIVERGES: the enum's values as `Int` constants (`halt_cleaning` is an `Int`), pl-incl.h:1054-1060.
"`GD->halt.cleaning`: normal mode (pl-incl.h)."
const CLN_NORMAL = 0
"`GD->halt.cleaning`: the Prolog hooks (`at_halt/1`) run (pl-incl.h)."
const CLN_PROLOG = 1
"`GD->halt.cleaning`: the foreign hooks run (pl-incl.h)."
const CLN_FOREIGN = 2
"`GD->halt.cleaning`: cleaning the I/O (pl-incl.h)."
const CLN_IO = 3
"`GD->halt.cleaning`: unloading the shared objects (pl-incl.h)."
const CLN_SHARED = 4
"`GD->halt.cleaning`: the remaining data (pl-incl.h)."
const CLN_DATA = 5
"`GD->halt.cleaning`: the final cleanup handlers (pl-incl.h)."
const CLN_ATEXIT = 6

# ORIGINAL (HALT1): upstream calls `exit(status)` in `PL_halt` and in `PL_abort_process`; a library cannot
# end its host's process unasked, so the global data holds the call as a seam, `halt_exit`: true (the default),
# `_halt_exit!` ends the process with `status`; false, it records `status` in `halt_exited` and returns, and
# `PL_halt` then returns false where upstream never returns. A caller that embeds the kernel (a test) sets
# `gd.halt_exit = false`. (A Boolean and a vector, not a function field: no abstractly typed field.)
"The process exit `PL_halt` ends with (upstream's `exit(status)`): ends the Julia process with `status`, or records it (`gd.halt_exit` false)."
function _halt_exit!(gd::PL_global_data, status::Int)::Nothing
    if gd.halt_exit
        exit(status)
    end
    push!(gd.halt_exited, status)
    return nothing
end

# ORIGINAL (R2 LB4 b2-1; loader_boot.md LD4, audit LQ2 (a)): a new database is a COPY of the database booted once per
# process and term type (`PL_global_data_from_template`, src/gd_template.jl; the build is `boot_global_data`), where
# upstream loads its saved state into the one `GD` of the process (pl-init.c:1648-1660, `loadWicFromStream`).
"A new database of term type `T`: the booted template's copy (boot/init.pl and the files of boot/load.pl loaded)."
PL_global_data{T}() where {T} = PL_global_data_from_template(T)

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

# PORT: pl-file.c input_context
# DIVERGES: a struct on a vector (`PL_local_data.input_context_stack`, the last pushed at the end), where
# upstream links each to its `previous`; the file is its atom, `nothing` for NULL_ATOM (R2 LB3).
"A saved input context (pl-file.c `struct input_context`): the input stream and the source location before a `see`."
struct input_context{T}
    stream::Union{Nothing, IOSTREAM}        # pushed input stream
    type::T                                 # Type of input
    term_file::Union{Nothing, T}            # old term_file
    term_line::Int                          # old term_line
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

# PORT: pl-global.h tabling as tbl_restraint
# DIVERGES: the anonymous `LD->tabling.restraint` struct is its own type; a `size_t` is an `Int` (`(size_t)-1`, no limit, is -1).
# The defaults are upstream's `initTabling` (pl-tabling.c:12696-12706): `error` for the five actions, no limit for the five
# sizes; the kernel builds the LD per database, so they are the constructor's values (src/pl-tabling.jl `initTabling!`).
"The tabling restraints of one thread (pl-global.h `LD->tabling.restraint`): the five limits and their actions."
mutable struct tbl_restraint{T}
    max_table_subgoal_size_action::T
    max_table_subgoal_size::Int
    max_table_answer_size_action::T
    max_table_answer_size::Int
    max_answers_for_subgoal_action::T
    max_answers_for_subgoal::Int
    max_incomplete_subgoals_action::T
    max_incomplete_subgoals::Int
    max_scc_subgoals_action::T
    max_scc_subgoals::Int
end
function tbl_restraint{T}() where {T}
    err = mk_sym(T, :error)
    return tbl_restraint{T}(err, -1, err, -1, err, -1, err, -1, err, -1)
end

# PORT: pl-global.h tabling as tbl_free_objects
# DIVERGES: the freed objects of each `TBL_FREE_*` kind are a typed vector (upstream links them through their first word and
# counts them in `count[]`, which is the vector's length): not observable.
"The freed tabling objects one thread keeps for reuse (pl-global.h `LD->tabling.free_objects`; pl-tabling.c `tbl_alloc`)."
mutable struct tbl_free_objects{T}
    component::Vector{tbl_component{T}}                         # list[TBL_FREE_COMPONENT]
    worklist_set::Vector{worklist_set{tbl_worklist{T}}}         # list[TBL_FREE_WORKLIST_SET]
    worklist::Vector{tbl_worklist{T}}                           # list[TBL_FREE_WORKLIST]
    cluster::Vector{cluster{T}}                                 # list[TBL_FREE_CLUSTER]
    closed::Bool                                                # Thread is terminating
end
tbl_free_objects{T}() where {T} = tbl_free_objects{T}(
    tbl_component{T}[], worklist_set{tbl_worklist{T}}[], tbl_worklist{T}[],
    cluster{T}[], false
)

# PORT: pl-global.h tabling as ld_tabling
# DIVERGES: only the private, single-thread fields; NOT PORTED, each to its owner (docs/architecture.md TB0):
# `idg_registry` (TB6); `start_nodes` (`node_array`, TB1) is a nullable `Vector{Int}` of node ids by `start_id` (no blocks: DIVERGES, no concurrent readers). `variant_table`
# is the index of the variant trie in the database's trie table (0: none). `flags` holds the `TF_*` bits,
# `delay_list` and `idg_current` are term references (0: none). `node_pool` is the pool `table_space` sets (`nothing`: NULL).
"The tabling state of one thread (pl-global.h `LD->tabling`)."
mutable struct ld_tabling{T}
    component::Union{Nothing, tbl_component{T}}                 # active component
    saved_status::Union{Nothing, tbl_status{T}}                 # Hidden components (break, ...)
    incomplete_tables::Int                                      # # tables in created_worklists
    active_components::Int                                      # # components with SCC_ACTIVE
    variant_table::Int                                          # Variant --> table (a trie index; 0: none)
    node_pool::Union{Nothing, alloc_pool}                       # Node allocation pool for tries
    start_nodes::Union{Nothing, Vector{Int}}                    # Predicate start nodes in it (a node_array: node ids by start_id, 0: none; TB1)
    dyn_orphan_events::Int                                      # Dynamic nodes that lost a dependent
    concurrent_idg_nodes::Int                                   # Private IDG nodes with shared children
    has_scheduling_component::Bool                              # A leader was created
    in_answer_completion::Bool                                  # Running answer completion
    in_assert_propagation::Bool                                 # Running propagate_assert/1
    flags::UInt32                                               # Global flags (TF_*)
    delay_list::Int                                             # Global delay list (a term_t; 0: none)
    idg_current::Int                                            # Current node in IDG (a term_t; 0: none)
    free_objects::tbl_free_objects{T}                           # Freed objects (TBL_FREE_*)
    restraint::tbl_restraint{T}                                 # the restraints
end
ld_tabling{T}() where {T} = ld_tabling{T}(
    nothing, nothing, 0, 0, 0, nothing, nothing, 0, 0, false, false, false, UInt32(0),
    0, 0,
    tbl_free_objects{T}(), tbl_restraint{T}()
)

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
# `messages` — no upstream field: what upstream's `Sdprintf` writes to `Serror` is collected there as
# `(kind, message)` (src/pl-qlf.jl; printMessage calls print_message/2 since LB4 b2). Since R1e's write/1 family:
# (The `variable_names` term reference, there since R1g, went in LB4 b2: `$variable_names` is the global variable
# boot/init.pl:1949 sets, src/pl-gvar.jl, which the compiler reads, `get_variable_names`.) `IO_streams` — upstream's `IO.streams`, the standard streams indexed by `SNO_*` (+1), opened over
# the process's stdin, stdout and stderr when the engine is made (`initIO`, src/os/pl-file.jl), or set
# by the host (`set_standard_stream!`; decision 2a), `IO_initialised` from then on; `IO_stream_type_check` (the `stream_type_check`
# flag), `IO_portray_nesting` (since group F, D-0123: the depth of nested `callPortray` calls, src/pl-write.jl), `var_names_numbervars_frame` (the foreign frame `BEGIN_NUMBERVARS` opens, 0: none) and two
# flags as swipl 10.1.16 has them: `unknown_option` (`ignore`), `write_attributes` (`ignore`).
# Since R2 F1b the Boolean flags the compiler, the VM and write read are bits of `prolog_flag_mask` (`truePrologFlag`),
# and the `determinism_error` flag is read from the flag table (`determinism_error_flag`), as upstream.
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
# Since R2 CONT1: the five `procedures_*` fields `reset3`, `dtbl_reset6`, `call_continuation1`, `dmeta_call1` (set by
# `setBuiltinPredicateProperties!`, pl-ext.c) and `findall_loop4` (set by pl-cont.c `findReset`'s `_PL_predicate`).
# Since MOD6: `module_enums`, the pool of `'$current_module'/2`'s states.
# Since R2 G1: `gvar_nb_vars` and `gvar_grefs`, upstream's `LD->gvar.nb_vars` (the
# global variables: atom word -> value word) and `.grefs` (how many hold a value on the global stack, which
# `_release_frozen!` then keeps), and `gvar_enums`, the pool of nb_current/2's states (src/pl-gvar.jl). Since R2 D2: `recorded_states`, the pool of recorded/2,3's states
# (`recorded_state`, pl-incl.jl).
# Since R2 PR1: `cur_pred_enums` and `cur_enums`, the pools of `'$c_current_predicate'/2`'s and `current_predicate/1`'s states
# (`cur_pred_enum`, `cur_enum`, pl-incl.jl). Since R2 O1B: `IO_output_stack` (`LD->IO.output_stack`: the output context stack
# of `with_output_to/2` and `format/3`'s redirect, src/os/pl-file.jl).
# Since R2 S2a: `prompt_current`, `prompt_first`, `prompt_first_used` (`LD->prompt`: prompt/2, prompt1/1; src/os/pl-file.jl).
# Since R2 LB5b: `prompt_next` (`LD->prompt.next`). DIVERGES: only `set_stream/2`'s alias(user_input) sets it
# (src/os/pl-file.jl); of upstream's readers `PL_write_prompt` (clears it once a prompt is written), `PL_prompt_next` and `resetProlog`
# are ported since R2 TOP1, but `Sread_user`, `wrapIO` and `Sread_terminal` (pl-file.c, pl-os.c) are TOP1b's pieces E-G, which wait for the
# audit's ruling on where the stream handle's local data lives. Removal condition: those pieces port the readers.
# Since TAB1 TB0: `tabling` (`LD->tabling`, `ld_tabling` above: the private tabling state, the restraints, the freed objects), and
# `table_flags_compile_threshold`, `table_flags_drop_intermediate` (`LD->table_flags`, nesting flattened), appended last.
# Since R2 TOP1b A: `break_level` (`LD->break_level`, pl-setup.c:199: -1 outside a toplevel; `currentBreakLevel`, src/pl-pro.jl), appended last.
# Since TR2: `trie_gens`, the pool of trie_gen/2,3's states (`trie_gen_state`, pl-incl.jl; upstream keeps them on the C stack, then `allocForeignState`), appended last;
# `trie_gen_force_epoch` (ORIGINAL, a test switch; a module-level `Ref` would be shared state, which the lint refuses), appended after it.
# Since R2 F1c: `debugstatus_skiplevel`, `debugstatus_tracing`, `debugstatus_debugging`, `debugstatus_showContext` (`LD->_debugstatus`, pl-incl.h
# `pl_debugstatus_t`; the flags `debug`, `debugger_show_context`: src/os/pl-prologflag.jl, `debugmode`, `tracemode`: src/pl-trace.jl).
# (the input context stack is LB3's `input_context_stack`, which `'\$push_input_context'/1` shares; src/os/pl-file.jl).
# Since R2 AUTOLOAD1 A2: `autoload_nesting` and `autoload_loop`, upstream's `LD->autoload.nesting` (a chain of `struct
# definition_chain`, pl-incl.h:1780, the innermost first; here a vector, the innermost LAST, as `input_context_stack`) and
# `LD->autoload.loop` (pl-global.h:897-899): the predicates the autoloader is loading, and the one it found itself looping on
# (src/pl-proc.jl `autoLoader`, `test_autoload_loop`). Upstream sets both to NULL in `resetProlog` (pl-pro.c:89-90); since R2 TOP1
# `resetProlog` (src/pl-pro.jl) empties the vector and sets the loop mark to `nothing`, and `query_loop` calls it before every run
# (this A2 DIVERGES is resolved); a new local data starts empty.
# Since R2 LB6a: `reload_nesting`, upstream's `LD->reload.nesting` (pl-global.h:892-894), appended last: how deeply reconsult is nested, written by
# `startReconsultFile` (src/pl-srcfile.jl). Upstream's `.generation` is NOT a field of this struct: `gd.reload_generation` is its single copy (see
# `PL_global_data`; audit D-0416 item 3).
"""
    PL_local_data{T}(gd)

The thread-local state (pl-global.h `struct PL_local_data`): the predicates ongoing enumerations
reference, at the generation each started in — so clause GC keeps what they can still see — and
the state of unification: the bindings, the trail that undoes them back to a [`mark`](@ref), the
`occurs_check` flag, and the records the unifier keeps while it walks; and the local stack — its
cells, its frames, choice points and foreign frames, and the registers that point into it. A new
one has upstream's initial local stack, emptied as `emptyStacks` leaves it: one foreign frame at
its base, and the three standard streams open (`initIO`, as upstream's start-up leaves them). It is made for the database `gd`: its atom words name atoms in `gd.atoms` (`GD->atoms`).
"""
mutable struct PL_local_data{T} <: AbstractLocalData
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
    random_state::Vector{UInt32}                                # LD->arith.random: GMP's Mersenne twister, mt[624] then mti (empty: not initialised; arith-c)
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
    messages::Vector{Tuple{Symbol, T}}                          # (the collected Sdprintf text and terms, src/pl-qlf.jl)
    IO_streams::Vector{Union{Nothing, IOSTREAM}}                # IO.streams[SNO_*]
    IO_initialised::Bool                                        # GD->io_initialised (per LD)
    IO_stream_type_check::Int                                   # IO.stream_type_check
    IO_portray_nesting::Int                                     # IO.portray_nesting
    var_names_numbervars_frame::Int                             # var_names.numbervars_frame
    prolog_flag_unknown_option::Int                             # prolog_flag.unknown_option
    prolog_flag_write_attributes::Int                           # prolog_flag.write_attributes
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
    module_enums::foreign_state_pool{module_enum}               # ('\$current_module'/2's REDO_PTR states, MOD6)
    gvar_nb_vars::Dict{UInt64, UInt64}                          # gvar.nb_vars: atom word -> value word (R2 G1)
    gvar_grefs::Int                                             # gvar.grefs: the values on the global stack
    gvar_enums::foreign_state_pool{gvar_enum}                   # (nb_current/2's REDO_PTR states, R2 G1)
    recorded_states::foreign_state_pool{recorded_state{T}}      # (recorded/2,3's REDO_PTR states, R2 D2)
    cur_pred_enums::foreign_state_pool{cur_pred_enum}           # ('$c_current_predicate'/2's REDO_PTR states, R2 PR1)
    cur_enums::foreign_state_pool{cur_enum{T}}                  # (current_predicate/1's REDO_PTR states, R2 PR1)
    input_context_stack::Vector{input_context{T}}               # input_context_stack: see/seen's (R2 LB3)
    qlf_write_state::Nothing                                    # qlf.write_state: always NULL, no state file (R2 LB3, LD2)
    IO_output_stack::Vector{IOSTREAM}                           # IO.output_stack: the streams current_output was before each redirect (R2 O1B)
    prompt_current::T                                           # prompt.current: prompt/2's atom (R2 S2a)
    prompt_first::Union{Nothing, T}                             # prompt.first: prompt1/1's atom (R2 S2a)
    prompt_first_used::Bool                                     # prompt.first_used
    debugstatus_skiplevel::UInt                                 # _debugstatus.skiplevel (SKIP_VERY_DEEP: typemax(UInt); R2 F1c)
    debugstatus_tracing::Bool                                   # _debugstatus.tracing
    debugstatus_debugging::Bool                                 # _debugstatus.debugging
    debugstatus_showContext::Bool                               # _debugstatus.showContext

    event_buffered::Union{Nothing, Vector{delayed_event{T}}}    # event.buffered: the delayed events (R2 EV1; nothing: NULL)
    event_delay_nesting::Int                                    # event.delay_nesting: how deeply is delay nested?
    event_hook_onthreadexit::Union{Nothing, event_list{T, definition{T}}}  # event.hook.onthreadexit: this thread's exit hook
    prompt_next::Bool                                           # prompt.next: the next read from user_input prompts (R2 LB5b)
    autoload_nesting::Vector{definition{T}}                     # autoload.nesting: the autoloader's chain, the innermost last (R2 AUTOLOAD1 A2)
    autoload_loop::Union{Nothing, definition{T}}                # autoload.loop: we are looping on this def (nothing: NULL)
    in_print_message::Int                                       # in_print_message: inside printMessage() (R2 LB4 b2)
    reload_nesting::Int                                         # reload.nesting: how deeply is reconsult nested
    break_level::Int                                            # break_level: the toplevel's nesting, -1 outside one (R2 TOP1b)
    tabling::ld_tabling{T}                                      # tabling: the tabling state of this thread (TAB1 TB0)
    table_flags_compile_threshold::Int                          # table_flags.compile_threshold: flag table_compile_threshold
    table_flags_drop_intermediate::Int                          # table_flags.drop_intermediate: flag table_drop_intermediate
    trie_gens::foreign_state_pool{trie_gen_state{T}}            # (trie_gen/2,3's REDO_PTR states, TR2)
    trie_gen_force_epoch::Bool                                  # ORIGINAL test switch: check_epoch! starts a new epoch at every call (TR2)
end
function PL_local_data{T}(gd::PL_global_data{T}) where {T}
    ld = _bare_local_data(gd)
    initIO(ld)              # Suser_input, Suser_output, Suser_error, Scurin, Scurout: open when the engine exists (pl-file.c initIO)
    return ld
end

# ORIGINAL: `PL_local_data{T}(gd)` without `initIO`: the engine `setupProlog` makes for its own use (a record for a flag)
# while the database is not yet a template; they open no stream, so the template's stream table stays
# empty (src/gd_template.jl `_copy_stream_free`). Every other engine is made by `PL_local_data{T}(gd)`.
function _bare_local_data(gd::PL_global_data{T}) where {T}
    e = mk_expr(T, T[])                         # any term: the idle placeholders' (index context, …)
    ld = PL_local_data{T}(
        definition_ref{T}[], UInt64[],                              # predicate_references, trail
        UInt64[], 0, T[], Int[],                                    # gstack, gTop, vtable, vbox
        gd.atoms, Dict{UInt64, UInt64}(), gd.atom_symbols,       # GD->atoms: the database's
        gd.functors, gd.atom_dexpr, gd.functor_dot2, gd.atom_nil_w,   # GD->functors (L1c); ATOM_nil (L1c-6)
        _int_word_keys(T),                      # int_word_keys (L1d step 4)
        0,                                      # cold_imports: no import yet
        0,                                      # mark_bar: gTop, set by emptyStacks!
        OCCURS_CHECK_FALSE,
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
        UInt32[],                                                  # random/1's state: gmp_randstate_t (arith-c)
        0,                                                         # frozen_bar (e5)
        # idle until a search resets it (`_index_context!`): any predicate will do
        index_context{T}(
            gen_t(0),
            Definition{T}(
                UInt64(0), 0, ClauseList{T}(), UInt64(0), e, code[], ClauseRef{T}[],
                PL_code_data(
                    code[], code[], code[], code[], code[], code[], code[], code[]
                ), 0, 0,
                0
            ),
            nothing,
            0,
            _TOP_POSITION,
            false,
            GEN_INVALID
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
        false,                                  # IO_initialised: `initIO` sets it (`PL_local_data{T}(gd)`)
        0,                                      # stream_type_check: loose (ST_LOOSE)
        0,                                      # portray_nesting: no portray call running
        0,                                      # no numbervars frame
        0x2,                                    # unknown_option: ignore (OPT_UNKNOWN_IGNORE)
        0x040,                                  # write_attributes: ignore (PL_WRT_ATTVAR_IGNORE)
        findall_bag{T}[],                       # bags: none (pl-bag.c: `LD->bags` is NULL)
        foreign_state_pool{between_state}(),    # between/3's states: none
        foreign_state_pool{retract_context{T}}(),   # retract/1's states: none
        retract_context{T}(),                   # retract/1's first-call buffer
        foreign_state_pool{ClauseChoice{T}}(),  # clause/2's states: none
        foreign_state_pool{op_enum{T}}(),       # current_op/3's states: none
        gd.prolog_flag.mask,                    # prolog_flag.mask: the database's (pl-thread.c copies the creating thread's)
        foreign_state_pool{prolog_flag_enum}(),  # current_prolog_flag/2's states: none
        ld_statistics(),                        # statistics: no inference yet, started now (Y1)
        ACCESS_LEVEL_USER,                      # access_level: `user` (pl-init.c:1666 sets it after the boot; swipl starts `system`, LB3's path)
        foreign_state_pool{module_enum}(),      # '$current_module'/2's states: none
        Dict{UInt64, UInt64}(),                 # gvar.nb_vars: no global variable (pl-gvar.c: NULL)
        0,                                      # gvar.grefs: none
        foreign_state_pool{gvar_enum}(),        # nb_current/2's states: none
        foreign_state_pool{recorded_state{T}}(), # recorded/2,3's states: none
        foreign_state_pool{cur_pred_enum}(),    # '$c_current_predicate'/2's states: none
        foreign_state_pool{cur_enum{T}}(),      # current_predicate/1's states: none
        input_context{T}[],                     # input_context_stack: empty (NULL)
        nothing,                                # qlf.write_state: NULL (LD2: the state is never written)
        IOSTREAM[],                             # output_stack: no redirect (R2 O1B)
        mk_sym(T, Symbol("|: ")),               # prompt.current: ATOM_prompt (pl-file.c:536, initIO)
        nothing,                                # prompt.first: NULL_ATOM
        false,                                  # prompt.first_used
        UInt(0),                                # debugstatus.skiplevel: resetTracer (pl-trace.c:1888)
        false,                                  # debugstatus.tracing
        false,                                  # debugstatus.debugging
        false,                                  # debugstatus.showContext: zero (static LD)
        nothing,                                # event.buffered: NULL
        0,                                      # event.delay_nesting
        nothing,                                # event.hook.onthreadexit: no listener yet (R2 EV1)
        false,                                  # prompt.next: false (pl-global.c: zero; set by set_stream's alias(user_input), R2 LB5b)
        definition{T}[],                        # autoload.nesting: NULL (R2 AUTOLOAD1 A2)
        nothing,                                # autoload.loop: NULL
        0,                                      # in_print_message: not inside printMessage() (pl-pro.c:82)
        0,                                      # reload.nesting (the generation is gd.reload_generation)
        -1,                                     # break_level: no toplevel runs (pl-setup.c:199)
        ld_tabling{T}(),                        # tabling: no component, no pool; the restraints at initTabling's defaults (TAB1 TB0)
        TABLE_COMPILE_THRESHOLD,                # table_flags.compile_threshold (pl-prologflag.c:2587)
        0,                                      # table_flags.drop_intermediate (pl-prologflag.c:2589)
        foreign_state_pool{trie_gen_state{T}}(), # trie_gen/2,3's states: none (TR2)
        false                                   # trie_gen_force_epoch: off (TR2)
    )
    allocStacks!(ld)                            # the initial local stack, its spare reserved
    emptyStacks!(ld)
    initTabling!(ld)                            # the restraints at their defaults (pl-tabling.c initTabling; TAB1 TB0)
    return ld
end

# ORIGINAL (R2 LB4 b2, the printing trap): a compact `show` for the database and the engine, NOT a port
# (upstream's structs have no printer). Julia's default `show` walks every reachable field, and a booted
# database reaches the boot files' whole graph: a failing `@test` whose value reached one printed it for
# over an hour (test_load and test_qlf, 2026-11-02). These print a few scalar fields and follow no
# reference; nothing reads their text, so no behaviour changes. The same for `procedure`, `definition`
# and `sourceFile` (src/pl-incl.jl).
function Base.show(io::IO, gd::PL_global_data{T}) where {T}
    print(io, "PL_global_data{", T, "}(modules=", length(gd.modules.modules))
    print(io, ", files=", length(gd.files_array), ", generation=", gd._generation)
    print(io, ", bootsession=", gd.bootsession, ")")
    return nothing
end

# ORIGINAL (R2 LB4 b2): see `show(::IO, ::PL_global_data)` above.
function Base.show(io::IO, ld::PL_local_data{T}) where {T}
    print(io, "PL_local_data{", T, "}(gTop=", ld.gTop, ", lTop=", ld.lTop)
    print(io, ", trail=", length(ld.trail), ")")
    return nothing
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
