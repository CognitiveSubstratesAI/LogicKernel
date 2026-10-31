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

## State (2026-10-31, first agent; forced hand-back by the 150k cap hook)

- [x] handoff 5dec9fd; group 1 02e0023 (pl-incl.jl types); group 2 5988f78 (pl-dbref.jl record blob,
  initDBRef! record FIRST). Written, UNRUN.
- [~] groups 3-5 WRITTEN and STAGED, NOT COMMITTED (the cap hook blocked the commit): src/pl-rec.jl (record
  lists, keys, `current_key/1`, `record_term` = upstream `record`, `PL_record_az`, `pl_recordava_va`,
  `pl_recordzva_va`, `save_state`/`free_state`/`advance_state`, `pl_recordedva_va`) and src/pl-incl.jl
  (`recordRef{T,L}(rec)` inner constructor, `recorded_state{T}`). NEXT AGENT: `git diff --cached --stat`,
  review, then commit with subject `UPSTREAM: pl-rec.c lookupRecordList/remove_record/getKeyEx/current_key/
  record/PL_record_az/recorda/recordz/recorded (swipl-devel cbf4e1896275)`.
## State, second agent (2026-10-31; forced hand-back by the 150k cap hook)

COMMITTED (all UNRUN, nothing compiled): 0b61387 groups 3-5 (pl-rec.jl/pl-incl.jl); 687fb43 groups 6-7 (erase/instance record
branches, `PL_predicates_from_rec` in upstream's order with `PL_FA_NONDETERMINISTIC | PL_FA_VARARGS`; pl-ext.jl table comment);
6cdcd1d group 10a EARLY (pl-global.jl GD `record_lists`, `record_lists_order`, `record_refs` at the END of the struct, LD
`recorded_states` at the end of the LD struct, constructors, pl-fli.jl `live_states`) so the branch loads (a STRUCT CHANGE).
STAGED, committed with this handoff: group 8, `test/db/test_record_swipl.jl` (98 pinned rows r01-r98 + 3 white-box testsets,
prefix `_rc_`/`_RC_`) and evidence/D2/{gen_rows.py, d2_rows.pl, d2_driver.pl, d2_rows.out} (pins from two byte-identical swipl 10.1.19 runs).
Rows r65, r67 kill D1-56; r73, r75 kill D1-119 (D-0252). Rows marked UNVERIFIED on the kernel (gate decides, a mismatch is traced,
not re-pinned): r21 (string literal in the consulted program), r27/r28 (`[]` and `[a|b]` keys), r40/r41 (a blob inside a recorded
term), r16-r19 (tagged-int range), the context of r23-r26/r32-r33/r50-r51/r61/r71/r79/r85, r88 (swipl pre-fetches the NEXT record when an
answer is returned, so a record erased after that is still answered: [1,2,3]), r43/r91 (redo). The white-box testsets use
`LK.recref_record`, `LK.firstRecordRecordList`, `LK.cleanRecordList`, `LK.remove_record`, `LK.isCurrentRecordList`, `LK.record_blob`,
`LK.live_states`, `LK._blob_registration`: if one is not reachable as `LK.x` the gate says so. test_blob.jl is NOT touched (it sets
its three ranks by hand, lines 35-36; `record` is registered FIRST in `initDBRef!`, rank between clause and mutex).

REMAINING, in order:
- group 9: `tools/mutants/D2.py` (>= 12 mutants, format of tools/mutants/MOD3b.py; TARGETS = test/db/test_record_swipl.jl AND
  test/db/test_clause_ref_swipl.jl AND test/core_lang/test_blob.jl AND any file calling recorded/findall on records: grep the
  tests for `recorda\|recordz\|recorded(` first), and `tools/mutants/D1c.py`: D1-56 and D1-119 re-anchored (erase's line is now
  `if type == DB_REF_CLAUSE                                    # CLAUSE: the erase branch of a clause`; instance's is
  `if type != DB_REF_CLAUSE                                    # RECORD: the instance branch of a record`, new `if true` / `if false`),
  `equivalent=` dropped, test_record_swipl.jl in their targets, header lines 13-14 and 21-23 updated. Validate with a throwaway
  python3 -I + runpy checker (old once, new != old, ids unique, targets exist). Candidate D2 mutants: `a.flags |= R_ERASED` dropped
  in erase, `l.references != 0` -> `== 0`, recorda/recordz swapped (`az == RECORDA`), `first.prev = r` dropped, lookupRecordList
  not pushing to `record_lists_order`, `current_key` ignoring `firstRecordRecordList`, getKeyEx accepting a float, `rl.references -= 1`
  dropped in free_state, `cleanRecordList` condition, `remove_record` unlinking `next.prev`, `isCurrentRecordList(…, true)` -> false,
  `acquire_record` flag, `PL_get_recref` erased test.
- group 10b (shared, LAST, separate commits): docs/architecture.md D2 section (appended; the row-file table entry); the manifest
  block only if a new `@enum` (none: RECORDA/RECORDZ are Int constants).
- Checks never done: `test/static_analysis_manifest.jl` / port_inventory are the gate's; the register of test files (grep how
  `test_clause_ref_swipl.jl` is listed in tools/ or test/runtests*.jl: the last command run was this grep and the cap hook ended
  the turn) must list `test/db/test_record_swipl.jl` the same way.
- Gate order (WRITER_RULES): fmt (`warm.sh send` for committed files), inventory, check, rows on all three term types
  (`warm.sh file test/db/test_record_swipl.jl`), type discipline, `tools/pkgtest_way.sh test/db/test_record_swipl.jl`, the
  mutants branch (`mutants/D2` at the WIP SHA once D2.py exists), branch-gate, term grep, alloc pins x3 (pl-global.jl changed),
  gate push on a FRESH name.
- Flags for the audit: F1-F5 above; plus F6: the record branch's `callEventHook` is the no-hook answer (F2); F7: `recorded/3`
  pre-fetches the next record (upstream's behaviour, row r88); F8: the local name `record` in `firstRecordRecordList`,
  `isCurrentRecordList`, `pl_current_key1_va` hides the type `record` inside those functions (no type use there; rename to `rec` if JET objects).

- [x] (done by 687fb43) group 6: in src/pl-rec.jl `pl_erase1_va` replace `@assert type == DB_REF_CLAUSE` by `if type ==
  DB_REF_CLAUSE … else` the record branch (pl-rec.c:2464-2480: rc = true (F2); `l.references != 0` → set
  `R_ERASED` on the ref's `flags` and `RL_DIRTY` on the list, else `remove_record`); `clause = ptr::Clause{T}`
  in the clause branch. `pl_instance2_va`: replace the NotPortedError by the record branch (pl-rec.c:2431-2436:
  `t = PL_new_term_ref`, `copyRecordToGlobal(ld, t, rref.record::record{T})`, `PL_unify(term, t)`, else false).
  Give the two `if type == DB_REF_CLAUSE` lines DIFFERENT trailing comments (mutant anchors). Update the file
  header (lines 35-41: the recorded database is ported now) and the erase/instance DIVERGES comments.
- [ ] group 7: `PL_predicates_from_rec` in upstream's order (pl-rec.c:2489-2498): recorded/2,3
  `pl_recordedva_va` NDET, recordz/2,3, recorda/2,3, erase/1, instance/2, current_key/1 NDET; all
  `| PL_FA_VARARGS` (PRED_DEF/PRED_SHARE, pl-builtin.h:634-637). Check how pl-ext.jl wires NDET (pl-op.jl:541).
- [ ] group 10 (shared, LAST, separate commits): src/pl-global.jl GD fields `record_lists::Dict{word,
  RecordList{T}}`, `record_lists_order::Vector{RecordList{T}}`, `record_refs::Vector{RecordRef{T}}` (the
  constructor near line 169, comments as `clause_refs`); LD `recorded_states::foreign_state_pool{recorded_state{T}}`
  (near line 469/549) and the live count in src/pl-fli.jl:1242 (`+ ld.recorded_states.live`).
- [ ] groups 8-9 rows and mutants as in the table; D1c.py D1-56 (old line now `if type == DB_REF_CLAUSE` in
  erase, new `if true`) and D1-119 (instance's line, new `if true`): drop `equivalent=`, add
  test/db/test_record_swipl.jl to their targets; update D1c.py's header lines 13-14 and 21-23.
- Check for the gate: test/core_lang/test_blob.jl pins blob ranks (a new type registered: `record` between
  clause and mutex, as swipl); the local name `record` in firstRecordRecordList/isCurrentRecordList/current_key
  hides the type there (no type use inside; rename to `rec` if JET or a reader objects).

## State, third agent (2026-10-31): groups 9a, 9b, 10b WRITTEN and COMMITTED (all UNRUN, nothing compiled)

- df91fa7 rows r99-r101 (swipl: r99 [3], r100 [kb], r101 [kb-2], two byte-identical runs; gen_rows.py reads 2-3 digit ids) + a white-box
  testset "the references of a list" (recorded cut/finished/enumerating leaves `references == 0` and `ld.recorded_states.live == 0`;
  PL_get_recref of a marked record). It is UNVERIFIED on the kernel (a query closed after its first answer is FRG_CUTTED: gate decides).
- a27dbdc tools/mutants/D2.py: 45 mutants (D2-45 EQUIVALENT: `release_record` has no caller), TARGETS = test_record_swipl.jl (+ test_clause_ref_swipl.jl,
  test_blob.jl, test_assert_swipl.jl for the shared pl-dbref/erase/instance code); every `old` once (throwaway checker). KILL rows are
  named in each id; "wb" = a white-box testset. The mutants on the references (D2-18..20, 26, 27) are killed ONLY by the new white-box testset.
- e254ed8 tools/mutants/D1c.py: D1-56 and D1-119 re-anchored, `equivalent=` dropped, `TREC` added to their targets, header updated. The
  checker found 10 more stale `old` strings (D1-10, 14, 16, 18, 20, 50, 57, 94, 100, 101: pl-dbref/pl-rec gained record counterparts, the
  registration table grew); D1-94 was stale ALREADY on main bf41225 (`$rule/3` is no longer the last table entry). All re-fitted; 100/100 once.
- eb05797 docs/architecture.md: D2 section before "Still to come", the pl-rec.jl / pl-dbref.jl rows amended, a row for test_record_swipl.jl.
  The D1 section's sentences "the record branch is D2's" / the NotPortedError stay (superseded; the D2 section says so): APPENDED-only rule.
- Registration of the test file: test/runtests.jl:180 discovers test directories with `readdir`, tools/pkgtest_costs.py, coverage_zero_known.txt,
  mutate_ci.py and pkgtest_way.jl name no test file individually (named-file counts of `test_clause_ref`: 0). Nothing to register.
- No manifest block (no new `@enum`; RECORDA/RECORDZ are Int constants).

## GATE ORDER (the dispatcher / stack owner; D2 sits in stack D: G1 -> D2 -> O1 -> F1b)

1. Rebase/merge: pl-global.jl changed (GD `record_lists`, `record_lists_order`, `record_refs` at the END of the struct; LD `recorded_states` at the END of
   the LD struct; constructors; pl-fli.jl `live_states`). The stack owner HAND-MERGES against G1, F1b, O1B (fields appended, ordering of constructor args).
2. `warm.sh fmt`, then `warm.sh send` for the committed files (fmt sees only the HEAD diff); re-fit any `old` of D2.py / D1c.py the formatter re-flows.
3. inventory (docs/port_inventory.md is regenerated by the gate, never by hand), `warm.sh check` (includes the Pkg.test-way run).
4. rows on all three term types: `warm.sh file test/db/test_record_swipl.jl` (+ test/core_lang/test_blob.jl, test/db/test_clause_ref_swipl.jl: the blob ranks and
   the erase/instance branch tests changed). A mismatch on an UNVERIFIED row is TRACED to the upstream cause, not re-pinned.
5. `warm.sh file test/test_type_discipline.jl`.
6. `tools/pkgtest_way.sh test/db/test_record_swipl.jl`, ONE at a time (~3 GB peak).
7. alloc pins x3 (pl-global.jl changed: the dispatcher's go for the alloc bench).
8. push `mutants/D2` at the WIP SHA (D2.py exists) and run D2 + D1c (45 + 100; D1-56, D1-119 must now be KILLED, not equivalent);
   the battery covers the white-box survivors; a survivor is killed by a test or proved equivalent with file:line (D-0100, D-0238).
9. `warm.sh branch-gate`.
10. the term grep over diff and message: `segment|SIGSEGV|crash|abort|invalid term_t|dies of`.
11. gate push `gate/d2<fresh suffix>` and `mutants/D2` at the SAME SHA, bare `git push`, never force.

## Flags for the audit (F1-F5 above, plus)

F6 the record branch's `callEventHook` is the no-hook answer (F2); F7 `recorded/3` takes the next record when an answer is returned (row r88; r99's
design relies on it: only the failed-unify path reaches `advance_state`'s skip); F8 the local name `record` in `firstRecordRecordList`,
`isCurrentRecordList`, `pl_current_key1_va` hides the type `record` there (rename to `rec` if JET objects; NOT done). F9: D1-94 was stale on main
(re-fitted here, needs a re-fit again only if the table moves). F10: a Julia exception (not a Prolog error) from `recref_record` for a clause blob is
what D2-41 expects to expose; the real code returns `nothing` after the type test.
