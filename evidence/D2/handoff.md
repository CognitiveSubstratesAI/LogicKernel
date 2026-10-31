# D2 — the recorded database (handoff)

Branch `wip/d2` off origin/main bf41225, worktree ~/code/lk-d2. Edit-only: nothing below has been RUN (no
Julia, no daemon). Stack D: G1 -> D2 -> O1 -> F1b; the dispatcher rebases D2 onto G1's head. Pin: swipl-devel
cbf4e1896275 (src/pl-rec.c, src/pl-dbref.c, src/pl-incl.h, src/pl-rec.h, src/pl-builtin.h).

Scope (FLG §7 row D2, §4 D11, H12; audit D-0230 item 2, D-0252 item 2): `recorda/2,3`, `recordz/2,3`,
`recorded/2,3`, `instance/2`'s record branch, `erase/1`'s record branch, the `record` blob registered FIRST in
`initDBRef!` (rank stream < clause < record < mutex). Added by this plan (same file, same table, 50 lines
upstream): `current_key/1` (pl-rec.c:1997) — flag F1 below.

## Step list (ordered groups; each a WIP commit)

| # | group | upstream (pin cbf4e1896275) | Julia site |
|---|---|---|---|
| 1 | the types: `RL_DIRTY`, `R_ERASED`, `R_DBREF`; `RecordList{T}` (`struct recordList`), `RecordRef{T}` (`struct recordRef`), `record_az` as `RECORDA`/`RECORDZ` Int constants | pl-incl.h:1198-1206, 2068-2082; pl-rec.h:42-45 | src/pl-incl.jl (after `struct record`) |
| 2 | the record blob: `record_blob`, `acquire_record`, `release_record`, `PL_unify_recref`, `PL_is_dbref`'s and `PL_get_dbref`'s record branches, `PL_get_recref`, `initDBRef!` registering `record_blob` FIRST | pl-dbref.c:42-44, 110-148, 205-258, 285-308 | src/pl-dbref.jl |
| 3 | the record lists: `initRecords` (in the GD constructor), `lookupRecordList`, `firstRecordRecordList`, `isCurrentRecordList`, `remove_record`, `cleanRecordList`, `freeRecordRef`; `unifyKey`, `getKeyEx` | pl-rec.c:71-178, 1843-1852, 1968-1993 | src/pl-rec.jl |
| 4 | `record`, `PL_record_az`, `recorda`/`recordz` (PRED_SHARE: `pl_recordava_va`, `pl_recordzva_va`) | pl-rec.c:2054-2122 | src/pl-rec.jl |
| 5 | `recorded/2,3`: `recorded_state`, `save_state`, `free_state`, `advance_state`, `pl_recordedva_va` (NDET, a state pool) | pl-rec.c:2125-2340 | src/pl-rec.jl (+ pool in pl-global.jl, group 9) |
| 6 | `instance/2`'s and `erase/1`'s record branches (the D1 asserts/NotPortedError replaced); `current_key/1` | pl-rec.c:1997-2051, 2394-2481 | src/pl-rec.jl |
| 7 | registration: `PL_predicates_from_rec` gets upstream's order and flags (PRED_SHARE recorded/2,3 NDET, recordz/2,3, recorda/2,3; PRED_DEF erase, instance, current_key NDET) | pl-rec.c:2487-2503; pl-builtin.h:634-637 | src/pl-rec.jl |
| 8 | oracle rows: evidence/D2/gen_rows.py + driver + .out (swipl 10.1.19); test/db/test_record_swipl.jl (prefix `_rc_`), the D-0252 record-reference rows for erase/1 and instance/2 | tests/db/test_dbref.pl, test_record*.pl as row sources | test/db/, evidence/D2/ |
| 9 | mutants: tools/mutants/D2.py (>= 12); tools/mutants/D1c.py: D1-56 and D1-119 re-anchored (their `old` lines are replaced by group 6) with the equivalence dropped, test_record_swipl.jl in their targets | — | tools/mutants/ |
| 10 | SHARED FILES, separate commits, LAST: src/pl-global.jl (GD `record_lists`, `record_keys`, `record_refs`; LD `recorded_states` pool), test/static_analysis_manifest.jl (only if a new `@enum`: none planned), docs/architecture.md D2 section | — | — |

## Estimate

GATED COMMITS for the whole step: 9-10 WIP commits (groups 1-10, the handoff folded into the last), ONE gate
branch; with the usual 1-2 fix commits after CI, 10-12. Under D-0272 item 7's ~12: the step continues.

## Flags (the audit decides)

- F1. `current_key/1` is added (not in FLG's row; same table, PRED_DEF in the same `BeginPredDefs(rec)`).
  Recommendation: keep it (enumerates the same table; 50 lines). Drop = delete its function and entry.
- F2. `callEventHook(PLEV_ERASED_RECORD, r)` (erase/1's record branch): the kernel has no prolog event hooks
  (pl-event.c), so `rc` is upstream's no-hook answer, true. Representation only while no hook can be set.
- F3. Record flags `R_ERASED`/`R_DBREF` live on the `RecordRef` (the kernel's `record` struct is immutable and
  carries no flags; only recorded-database records carry these two). Representation only.
- F4. Enumeration order of keys (recorded/3 and current_key/1 with an unbound key): insertion order, upstream's
  is the hash table's (FLG H1): rows compare SORTED answer lists for an unbound key.
- F5. The blob payload is the record's number in `gd.record_refs` (as the clause blob's, D1). Written form
  `<record>(0x…)` is the term interface's.

## State

- [ ] groups 1-10 (written, UNRUN)
