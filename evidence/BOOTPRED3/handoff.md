# BOOTPRED3: five boot-load-path predicates no step owns (audit D-0354 ruling 2) -- handoff

Worktree ~/code/lk-dstack, branch wip/bootpred3 (off main 9e0a983). Writer: Sonnet, paused at D-0355. Pin: swipl-devel cbf4e1896275
(pin tree ~/dev-zone/swipl-devel-cbf4e189). Oracle: swipl 10.1.19. NOTHING was compiled or run (no smoke run yet).

## Source groups (all committed)
| # | predicate | upstream (pin) | Julia | commit |
|---|---|---|---|---|
| 1 | `$memberchk`/3 | pl-list.c:109-152 | src/pl-list.jl `pl_memberchk3_va`, in PL_predicates_from_list | 072e40a |
| 2 | `$inc_message_count`/1 | pl-error.c:1457-1474 | src/pl-error.jl `pl_inc_message_count1_va`, new PL_predicates_from_error | c55811c |
| 3 | `$notrace`/2, `$restore_trace`/2 | pl-pro.c:317-390 (NOT pl-trace.c) | src/pl-pro.jl | ebb7498 |
| 4 | prolog_listen/2,3 | pl-event.c:241-290 + add_event_hook, get_event_listp, get_callback | new src/pl-event.jl (+ include in LogicKernel.jl) | 33c6bcf |
| 5 | variant_sha1/2 registration | pl-termhash.c:659-681 | src/pl-termhash.jl `pl_variant_sha1_2_va`, PL_predicates_from_termhash | b8a4075 |
Tables PL_predicates_from_error/event/termhash are appended to `_PRED_TABLES` and `_FOREIGN_VA` in src/pl-ext.jl (after strings).

## Rows (WIP commit): test/core_lang/test_bootpred3_swipl.jl
Cases bp3m01-18 ($memberchk), bp3i01-10, bp3n01-19, bp3l01-32, bp3v01-14 are written. `_B3_PINNED` is EMPTY: still to do,
copy evidence/Q10/gen_rows.py (in ~/code/lk-q10) to evidence/BOOTPRED3/ with regex ids `bp3[a-z]\d{2}`, `_SC`->`_B3`, files
bp3_rows.pl / bp3_driver.pl / bp3_rows.out; run swipl twice (byte-identical), then `--fill`. Check the case list for rows swipl
refuses to parse. The test file will fail until filled.

## Left
1. rows pins (above); 2. tools/mutants/BOOTPRED3.py (anchors once; TARGETS = test/core_lang/test_bootpred3_swipl.jl plus any
test exercising list/pro/termhash/error code, D-0238); 3. test/static_analysis_manifest.jl entries (append at the end);
4. docs/architecture.md block (append at the end; src/pl-event.jl row with UPSTREAM header pl-event.c for the inventory);
5. the smoke run `tools/warm.sh file test/core_lang/test_bootpred3_swipl.jl` on the three term types (daemon logickernel-warm-b4dc834e);
6. stale-pin hunt over test/ for prolog_listen / variant_sha1 / memberchk existence_error pins; hook-wording check (no absence claims).

## Flags for the audit
- Crash-term grep hit (false positive): `abort` is the event name in src/pl-event.jl and the table comment; no crash detail.
- `$notrace/2`, `$restore_trace/2`: the kernel has no debugstatus tracing/debugging/skiplevel in LD (a new field = struct change, Tier-1 alarm).
  Implemented without state: bits 1,2 read 0, skip level -1, restore keeps only the LASTCALL and VMI_BUILTIN flag bits, depth checked and dropped.
  Recommendation: leave until DBG1 adds the fields.
- `$inc_message_count/1`: errors/warnings counters not kept (ld_statistics has no field; statistics(errors,_) is 0 already). Argument check as upstream.
- prolog_listen: no event lists exist (GD/LD fields = struct change; a module-level registry would trip the global-state lint). The registration is
  checked (options, event name, closure) and accepted, the hook is NOT kept; a listener on a predicate throws NotPortedError naming EV1. Event table is the
  O_ENGINES build's (thread events included, as the threads=true oracle). Recommendation: EV1 adds the lists with the calling side.
- variant_sha1/2: unifies an ATOM (upstream PL_ATOM, not a string); the digest VALUES differ from swipl's (pl-termhash.jl DIVERGES 1-2), so rows compare properties only.
- The recount names pl-trace.c for `$notrace`/`$restore_trace`; they are in pl-pro.c.
- `$memberchk`: upstream's PL_handle_signals at every 10000th cell is left out (no signal queue); a long-list row (bp3m16, 12000 cells) exercises the
  usedStack check: if the kernel's gTop accounting differs it shows as a false type_error at the gate.
- The commit hook wants the whole tree staged: the plan file rode in the first commit.
- Shared files touched: src/pl-ext.jl (table tuples, appended last), src/LogicKernel.jl (one include).

## Gate order afterwards
warm.sh fmt (committed files via warm.sh send), inventory, check, rows x3, test/test_type_discipline.jl, pkgtest_way on the rows file, mutants/BOOTPRED3 push,
branch-gate, term grep, gate push on a fresh name. Tier 3 if no Tier-1 file changes (none touched). Branches deleted: none.
