# EV1 gate agent 5 — state

Lane ~/code/lk-ev1. Local branch `gate/ev1d` (NEW, off origin/main 9cc76fa; upstream tracking removed so a bare push cannot reach main).
gate/ev1c (fe76984) is untouched.

## Re-stack (done)
30 commits of c4c34fd..fe76984 cherry-picked in order (non-interactive, authors kept). `git range-diff c4c34fd..fe76984 9cc76fa..gate/ev1d`:
23 commits identical (=), 7 differ (!): pl-pro.c notrace (pl-pro.jl conflict: main's abortProlog/raise_halt_exception kept, notrace code appended, table has 4 entries),
pl-event.c prolog_listen (LogicKernel.jl include line), BOOTPRED3 mutants/docs/manifest (architecture.md + manifest: both sides kept), pl-event.h/GD-LD fields
(pl-global.jl: halt_* fields then event fields, both in the struct and the constructors), pl-event.c call side (include line), 5dcc316 port markers
(architecture.md generated blocks; pl-pro.jl), 3ca2a1c (docs/port_inventory.md: main's side, regenerated at the end). Intermediate commit 7f13304-ish had a comma
slip in the pl-global.jl constructors (the resolver put the comma after the trailing comment): FIXED in the working tree (folds into the next commit), the final tree parses.
tools/mutants/EV1c.py renamed EV1d.py (git mv).

## Survivors (D-0383 item 3)
Read: pl-event.c:412-466 (call_event_list) and callEventHook's tail (pl-event.c ~700-714), restoreWakeup (src/pl-attvar.jl:103-125).
* C5: WAKEUP_KEEP_URGENT_EXCEPTION only changes restoreWakeup when the state saved an exception that was ALREADY pending at the event
  (WAKEUP_STATE_EXCEPTION): then the saved ball is put back unless the listener's new ball is MORE urgent (classify_exception). None of ev1v08-11/ev1r03 has a ball
  pending at the event, so the flag was never read. New row ev1g03 (listener ev1_ebad throws ev1_ball(g) for the first erased clause, error(type_error(integer,g),_)
  for the second, both erased in one garbage_collect_clauses pass; the loop of cleanDefinition continues after the failed first event, so the second event
  arrives with the first ball pending). swipl 10.1.19 answers error(type_error(integer,g),_) (two log entries), pinned by gen_rows.py (two byte-identical runs).
  C5's KILL name becomes ev1g03.
* C3: SURVIVED in-tree (evidence/EV1/g5/mut_c3c5.log), declared EQUIVALENT in EV1d.py with the reading: `rc = rc &&` already stops every later listener; the break only matters for upstream C-function branch (pl-event.c:420-454), which the kernel does not have before TH1. The dispatcher rules.


## STATE AT THE 150k CAP (forced hand-back; NOTHING COMMITTED OR PUSHED ON gate/ev1d YET)

Lane ~/code/lk-ev1, branch `gate/ev1d` = 30 cherry-picked commits on origin/main 9cc76fa (HEAD = last cherry-pick; upstream tracking removed).
UNCOMMITTED in the working tree / index (commit them as ONE commit after the gate below; the commit hook needs the branch-gate marker, never write one):
 * src/pl-global.jl — comma fix of the two constructors (halt_exited line, showContext line); without it the tree does not parse.
 * test/core_lang/test_event_swipl.jl — program line `ev1_ebad/2`, `ev1_ebad(_)` in ev1_unl, row `ev1g03` (ends with `ev1_unl(erase)` so swipl exits 0), pins filled (84 lines).
 * evidence/EV1/{ev1_driver.pl, ev1_rows.pl, ev1_rows.out}, gate3.md, gate4.md, gate5.md, g4/pins_done.txt, g5/mut_c3c5.log (staged or modified).
 * tools/mutants/EV1c.py -> EV1d.py (git mv, staged) with C5 KILL name = ev1g03 and C3 declared EQUIVALENT (51 mutants, anchor check 0 bad via `python3 -I .warm/ev1chk.py tools/mutants/EV1d.py`).
 * range-diff c4c34fd..fe76984 vs 9cc76fa..gate/ev1d: 23 commits "=", 7 "!" (conflict resolutions listed above in "Re-stack"), 3ca2a1c re-created (inventory differs).

## C3 / C5 in-tree results (tools/mutate.sh run-in-tree, test_event_swipl.jl, reference, baseline exit 0, final baseline exit 0)
 * C5: CAUGHT (Test Failed at test_event_swipl.jl:592 = the pin comparison) after adding row ev1g03. Cause of the survivor: KEEP_URGENT_EXCEPTION only changes
   restoreWakeup (src/pl-attvar.jl:112-118) when a ball was ALREADY pending at the event; no old row had one. ev1g03: two erased clauses in one
   garbage_collect_clauses pass (cleanDefinition! keeps looping after the first failed erase event), listener 1 throws ev1_ball(g), listener 2 throws
   error(type_error(integer,g),_) (a more urgent class); swipl 10.1.19 answers the error (two byte-identical runs), without the flag the older ball would win.
 * C3: SURVIVED (as predicted by the reading), declared EQUIVALENT with lines (text in EV1d.py): `rc = rc &&` (src/pl-event.jl:453-454, :464-465; pl-event.c:456, :462)
   already stops all later listeners, the break (:471; pl-event.c:465-466) only matters for upstream's C-function branch (pl-event.c:420-454), dead here (function_ 0, EV1-C9). The dispatcher rules.
 * ev1g03 itself passes on reference (baseline exit 0 twice). alt and alt_interned NOT yet run with the new row.

## Daemon
lk-ev1 daemon RUNNING (unit logickernel-warm-e29a7ffc, SECOND slot, started ~08:55Z, cold compile ~8 min), idle. The other slot (lk-eng3) untouched. Do not stop it.
`.warm/fmt_all2.jl` (untracked) lists the 17 changed .jl files: `tools/warm.sh send .warm/fmt_all2.jl` -> "fmt: 0 file(s) rewritten" (done after the row edits, before the EV1d.py edit).

## LEFT TO DO (in order)
1. `tools/warm.sh inventory` (commit docs/port_inventory.md and architecture.md changes; architecture.md has the merged generated mermaid blocks kept from both sides: inventory regenerates them; restore any UPSTREAM file names it drops from the pl-file/pl-event rows, GATE-PLAYBOOK pitfall), then `tools/warm.sh check`.
2. test_event_swipl.jl on alt and alt_interned (one `warm.sh file <f> <type>` call each; reference is done: 99 pass + the live-pin test now needs a re-run since the first run errored only because swipl exited 1; expect 100 per type); test_bootpred3_swipl.jl x3 (130/131/131); callers x3: test_pr1_swipl, test_update_view_gc, test_jit, test_index_swipl, test_declare_destroy_swipl, test_hash; test/test_type_discipline.jl, test/test_manifest_entries.jl, static_analysis_fast.jl, then test/test_static_analysis.jl LAST (50 min); `tools/pkgtest_way.sh` on test_event_swipl.jl then test_bootpred3_swipl.jl (one at a time); alloc pins x3: test_zero_exports 239, test_local_stack 377, test/foreign/test_query 347, test_rules_swipl 433.
3. `tools/warm.sh branch-gate` if the commit hook demands the marker; commit (subject + 5-10 lines, message mentions the pl-global.jl comma fix folded in, C5 row ev1g03, C3 declared equivalent; Co-Authored-By line); crash-term grep (done once over the diff and messages of the 30 commits: only the event name `abort`, `onabort`, `PLEV_ABORT` identifiers and evidence prose describing the grep); author check (all 30 are Shivaji Gadde).
4. `git fetch`; if origin/main moved past 9cc76fa plain rebase (no -i, no force), `warm.sh check` again. Push at the SAME SHA: `git push origin <sha>:refs/heads/mutants/EV1d` then `...:refs/heads/gate/ev1d` (redirect to a log, no git pipelines). One ci_status. Do not wait.
5. Copy gate5.md to ~/code/lk-channel/evidence/EV1/ (stage, commit in two calls, push).

## Hook/environment notes
 * Hook refusals met: none on commits (no commit was attempted); `no-uncapped-background` on a bare mutate.sh (use `systemd-run --user --scope -p MemoryMax=6G -p MemorySwapMax=0 -p TasksMax=512`); `no-sleep-loops` (waited with `tail --pid=<pid> -f /dev/null` in the background instead); the grep -rn CODEMAP hook (one command, blocked whole); the 150k cap hook ended this agent.
 * A `grep` of a test log printed a truncated `setenv(...)` process line once (a swipl process error text); no secrets seen. Do not grep the live-pin Error lines without `cut -c1-80`.
