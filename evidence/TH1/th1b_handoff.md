# TH1-B handoff: the L_* lock table, no threads (edit-only)

Branch wip/th1-b, off wip/th1-a 3825b651. Design: ~/code/lk-channel/evidence/TH1/design.md sections 1b, 3, 6.B (ruled D-0789); probes: evidence/TH1/probes.md in the same channel.
PHASE 1: faithful port of swipl-devel as-is, no Julia redesign; a divergence only where forced, named with its reason.
Written by the TH1-B reader (first attempt stopped at a recursive-search hook before any edit); the plan below is its, taken by the dispatcher on 2026-11-15 with the two design points ruled by the dispatcher as representation-only (logged for the audit).

## What upstream says (scratch copies of the files may be gone: `git -C ~/dev-zone/swipl-devel show 18168e62:src/pl-thread.c`, same for pl-thread.h, pl-mutex.h)
- pl-thread.c:302-337 `_PL_mutexes[]`: 30 `COUNT_MUTEX_INITIALIZER` names in this order (ids 0-29, pl-thread.h:242-271): L_MISC, L_ALLOC, L_REHASH_ATOMS, L_FLAG, L_FUNCTOR, L_RECORD, L_THREAD, L_MUTEX, L_PREDICATE, L_MODULE, L_SRCFILE, L_TABLE, L_BREAK, L_FILE, L_SEETELL, L_PLFLAG, L_OP, L_INIT, L_TERM, L_FOREIGN, L_OS, L_LOCALE, L_SORTR, L_UMUTEX, L_INIT_ATOMS, L_CGCGEN, L_EVHOOK, L_OSDIR, L_ALERT, L_GENERATION. Index 7 is L_MUTEX, not L_UMUTEX. L_DDE=30 and L_CSTACK=31 are Windows-only (left out).
- pl-thread.c:607-634 `enableThreads`; pl-thread.h:286-340 `IF_MT`, `countingMutexLock/Unlock`, `PL_LOCK/PL_UNLOCK`, `holdsLock` (true when `lock_count > 0`, by any owner).
- `counting_mutex` is at pl-mutex.h:151-159: mutex, name, count (u64), lock_count, collisions, next, prev.
- Initial values: `GD->statistics.threads_created = 1`, `threads_finished = 0` (pl-thread.c:952-953); `GD->thread.enabled` is set true at init by `enableThreads(!GD->options.nothreads)` (pl-init.c:1609).

## Kernel facts
- src/pl-thread.jl is 123 lines and is included AFTER pl-global.jl (include order: pl-incl, pl-global, ..., pl-thread, ..., pl-setup, ..., gd_template).
- `PL_global_data{T}` has one real positional constructor, src/pl-setup.jl:277, whose last two arguments are at pl-setup.jl:341-342 (`tabling_answer_delay_infos`, `tabling_start_node_ids`). The other source of instances is the @generated `copy_global_data` in src/gd_template.jl. Confirm there is no other positional call with `grep -n 'PL_global_data{' <file>` on pl-setup.jl, gd_template.jl and test/db/test_gd_template.jl (NO recursive search: the pre-bash hook refuses it and you must not use its escape); the first compile will show any other call site, so name that risk in the state section.
- A `:reset` entry in `GD_COPY_POLICY` interpolates a literal, so it cannot give each copy a fresh lock object.
- `_query_gd(ld)` returns the database from `ld.GD`. `PL_error(ld, "", 0, "", ERR_PERMISSION, mk_sym(T,:modify), mk_sym(T,:flag), key)` is used at src/os/pl-prologflag.jl:865, with `_flag_atom_ref` building the key term.
- Manifest entries in test/static_analysis_manifest.jl: per-type entries next to the line with `(LK.cgcActivatePredicate!, Tuple{GD, D, UInt64}, false)` (about line 680), non-per-type entries near `LK.ThreadCPUTime` (about line 4122).
- Mutant format: tools/mutants/TH1AA.py (dict id/file/old/new/targets, TARGETS list).
- Cost files: test/pkgtest_costs.tsv and test/unit_costs.tsv use `dir/file.jl<TAB>seconds`.
- test/threads/ does not exist; runtests.jl finds directories with `readdir`, so a new directory is picked up.

## The plan (decisions taken)
1. src/pl-incl.jl: `# PORT: pl-thread.h L_*` constants (Int, ids 0-29) and `mutable struct counting_mutex` (const mutex::ReentrantLock, const name::String, count::UInt64, lock_count::UInt32, collisions::UInt32, `@atomic owner::Union{Nothing,Task}`), plus `Base.deepcopy_internal(::counting_mutex, ::IdDict)` returning a fresh unlocked mutex of the same name.
   DIVERGES (named, representation only): the struct is in pl-incl.jl rather than pl-thread.jl because the GD field type must exist before pl-global.jl. Upstream's process-wide `_PL_mutexes[]` becomes a per-database vector in GD (a GD is a value, one per database; module-level mutable state is refused by tools/lint_globals.jl). The deepcopy method gives each copied database its own unlocked table: the design said `:reset`, which cannot make a fresh object.
2. src/pl-global.jl: four new GD fields appended after `tabling_start_node_ids`: `thread_enabled::Bool` (initial true), `statistics_threads_created::Int` (1), `statistics_threads_finished::Int` (0), `const mutexes::Vector{counting_mutex}`. pl-setup.jl gets the four constructor arguments, the vector from `new_PL_mutexes()`.
3. src/pl-thread.jl, new code (each with `# PORT: pl-thread.c <name>`):
   - `new_PL_mutexes()`: the 30-name table in upstream order.
   - `PL_LOCK(gd, id)`: skips when `id != L_THREAD && !gd.thread_enabled` (IF_MT); a relock by the owning task raises an error; trylock counts a collision, then lock, then `count += 1`, `lock_count += 1`, set owner.
   - `PL_UNLOCK(gd, id)`: same IF_MT skip, asserts `lock_count > 0`, decrements, clears owner, unlocks.
   - `holdsLock(gd, id)`: `lock_count > 0`.
   - `enableThreads(ld, enable)`: copy of pl-thread.c:608-631, with the `ERR_PERMISSION modify flag threads` error when created-finished != 1. It takes `ld` because `PL_error` needs it.
   DIVERGES (named): a ReentrantLock where upstream uses a non-recursive pthread mutex; the relock check turns upstream's self-deadlock into an error; `holdsLock` keeps upstream's meaning (held by anyone); the Windows-only L_DDE and L_CSTACK are left out of the table.
   Open question for the audit: `thread_enabled` starts true as upstream's pl-init.c:1609 does, while the kernel's `threads` flag is false until TH1-C. Nothing reads it yet (no PL_LOCK site is placed in this step).
4. test/threads/test_th1b_locks.jl (LK-ONLY): lock/unlock pairing and counts, holdsLock, the relock error, `enableThreads` answers (created-finished == 1 gives true and enabled=false; set the counters to 2 to get the permission error and see the lock released), the table's 30 names in order, and the copied GD's fresh table. One row per upstream line cited. Manifest entries (per-type `Tuple{GD, Int}` for PL_LOCK/PL_UNLOCK/holdsLock, `Tuple{LD, Bool}` for enableThreads, non-per-type for `new_PL_mutexes` and the `deepcopy_internal` method) and both cost lines (estimate copied from a neighbour such as `db/test_retract_swipl.jl 1.6`).
5. tools/mutants/TH1B.py with TARGETS = the new file plus test/db/test_gd_template.jl (it exercises the copy). Ids say "aimed by <rows>", unique, no KILL, no `equivalent=`.
6. Commits: src first, then tests and mutants.
