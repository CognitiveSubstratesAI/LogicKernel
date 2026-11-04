# TOP1 handoff (writer, Sonnet, edit-only: nothing compiled or run)

Worktree ~/code/lk-top1, branch wip/top1, base 30fb3a16 (= gate/autoload2c: main 6941c5bd + the AUTOLOAD1 A2/A3 stack).
Pin cbf4e1896275. No daemon, no Julia, lanes.conf untouched.

## Sizing (read at the pin)
In this step (pl-pro.c:60-94 resetProlog, :147-218 query_loop and what they call):
- G1 src/pl-trace.jl: `resetTracer` (pl-trace.c:1882, over the fields the local data has), `enable_debug_on_interrupt` (pl-trace.c:2092, the flag-mask half).
- G2 src/os/pl-file.jl: `validUserStreams` (pl-file.c:1488), `PrologPrompt` (:3795), `PL_write_prompt` (:1868, clears `prompt.next`);
  src/pl-write.jl `writeAtomToStream` (pl-write.c:1318); src/pl-fli.jl `PL_prompt_next` (pl-fli.c:5345).
- G3 src/pl-pro.jl: `resetProlog` (clears autoload.nesting/.loop: the A2 DIVERGES), `halt_from_exception`, `restore_after_exception`, `query_loop`.
- G4 tests: test/core_lang/test_top1_*.jl (+ generator under tools/), tools/mutants/TOP1.py, manifest, architecture block, DIVERGES flips.
Readers of `prompt_next`: pl-pro.c:67 (G3), pl-fli.c:5349 (G2), PL_write_prompt clears it (G2). LEFT with an owner (TOP1b):
Sread_user + wrapIO + set_prolog_IO/3 (pl-file.c:5987, :6047, :6125), Sread_terminal (pl-os.c:2171-2224, :2462), `prologToplevel`/`pl_break`/
`currentBreakLevel`/`break_level` flag (needs a `break_level` field), PL_prompt_is_continuation, PL_prompt_string.

## Status
(updated per commit below)

## State at the context cap (writer 1; wip/top1)
Commits (oldest first): 4a32aaf4 plan; 3e5cbf9f G1 pl-trace.jl (`resetTracer`, `enable_debug_on_interrupt`); d24e8697 G2 (`validUserStreams`, `PrologPrompt`,
`PL_write_prompt` in src/os/pl-file.jl before the "input context stack" marker; `writeAtomToStream` in src/pl-write.jl after `writeAtom`; `PL_prompt_next` in src/pl-fli.jl
after `PL_halt`); 98f93af3 G3 src/pl-pro.jl (`resetProlog`, `restore_after_exception`, `halt_from_exception`, `query_loop`; header updated). Nothing compiled or run.
Prerequisites verified present by grep: `emptyStacks!`, `classify_exception`, `PL_halt`, `tracemode/debugmode`, `callEventHook`, `printMessage`, `_message_term`, `lookupProcedure`,
`PL_open_query` (the `_query_run_at_halt` idiom in src/pl-init.jl). Fields used: `autoload_nesting`, `autoload_loop`, `prompt_next`, `prompt_first(_used)`, `prompt_current`, `gvar_nb_vars`.

## LEFT for the next agent (G4, in order)
1. Tests: test/core_lang/test_top1_prompt.jl (+ generator tools/gen_top1_rows.py or evidence/TOP1/gen_top1_rows.py, template: evidence/AUTOLOAD1/gen_af_rows.py of the channel / test_autoload_flag_swipl.jl
   header, test_lb5b_prompt.jl for white-box). Oracle idea measured by reading, not run: swipl writes the prompt in `Sread_terminal` (pl-os.c:2171) also for piped stdin, once per buffer fill; a
   python driver feeding chunks with a pause between them gives `prompt1`'s atom once, `prompt/2`'s at line start (linepos 0), none mid-line. Kernel side: call `PL_write_prompt(gd, ld, true)` into a
   memory `user_output`, advance `user_input`'s position by the chunk, set `ld.prompt_next` as `Sread_user`'s three lines do (the harness says so: TOP1b ports it). White-box rows (LK-only,
   `# UNVERIFIED on the kernel: gate decides`): resetProlog clears `autoload_nesting`/`autoload_loop` (push a def, set loop, call, read both); error on user_input cleared + `prompt_next` true;
   Scurin/Scurout = user streams; query_loop on a `system:` zero-arity fact (rc 1), a failing one (0), a raising one with loop=false (-1, exception cleared by resetProlog next time),
   `unwind(abort)` loop=false (-1; the `abort` event hook fired), `unwind(halt(3))` through `gd.halt_exit` seam (status 3), `validUserStreams` false after Sseterr on user_error.
2. tools/mutants/TOP1.py (>= 6; format tools/mutants/MOD3b.py): candidates `empty!(ld.autoload_nesting)` removed, `ld.autoload_loop = nothing` removed, `Sclearerr(in)`/`ld.prompt_next = true` in resetProlog,
   `isempty(ld.gvar_nb_vars)` negated, `loop = false` in the halt branch, `rc = -1` after the exception, `ld.prompt_next = false` in PL_write_prompt, `linepos == 0` -> `!= 0`, `!ld.prompt_first_used` negated,
   `in === Suser_input(ld)` in PL_prompt_next. TARGETS = the new test + test/core_lang/test_lb5b_prompt.jl + test_autoload_trap.jl (when they exercise the code). Anchors once each (`grep -c -F`).
3. test/static_analysis_manifest.jl rows for the new functions (appended block, own commit); docs/architecture.md block "TOP1" (own commit, last).
4. Flip the DIVERGES texts (comments, own commit with the docs): src/pl-global.jl:447-452 (A2 reset: now `resetProlog`), src/pl-proc.jl:355, src/os/pl-file.jl "set_stream ... DIVERGES" block (readers in resetProlog/PL_write_prompt/PL_prompt_next now ported;
   Sread_user/wrapIO/set_prolog_IO/Sread_terminal stay TOP1b), docs/architecture.md:6726 (LB5b known difference 1) and :6873 (the "No resetProlog" bullet), status board TOP1 row.

## Flags for the audit
- TOP1b (owner needed): `Sread_user` + `wrapIO` + `set_prolog_IO/3` (pl-file.c:5987, :6047, :6125) and `Sread_terminal` (pl-os.c:2171-2224, :2462): the stream layer dispatches on the closed enum `IOFUNCTIONS` and `S_read`
  has no `ld`, so a read hook needs a design (recommendation: a new function-set member plus an `ld` reference in the handle); `prologToplevel`/`pl_break`/`currentBreakLevel` need a `break_level` field (struct change) and
  the flag `break_level`; `PL_prompt_is_continuation`, `PL_prompt_string` (editline consumers).
- `resetProlog` calls `emptyStacks!` mid-life (written for init): UNVERIFIED on the kernel, gate decides. `src/pl-init.jl` `_query_run_at_halt` is a reduced `query_loop(.., false)`; switching it to `query_loop` is a behaviour change left to the gate/audit.
- Not ported in resetProlog, by field: gc_status.blocked, shift_status.blocked, in_print_message (GC/print_message steps), depth_info.limit (P3), debugstatus.suspendTrace/retryFrame (DBG1). SIGINT handler of enable_debug_on_interrupt (signal step).
- Long code lines in pl-pro.jl may be re-wrapped by `warm.sh fmt`.
- Gate order after G4: fmt (committed files via `warm.sh send`), inventory, check, new test x3 term types, test_type_discipline, pkgtest_way once, mutants/TOP1 push, branch-gate, term grep, gate push. Struct unchanged by this step (no new field), so no alloc pins unless pl-fli.jl counts as Tier 1 (PL_prompt_next is added there).

## Writer 2 state (context cap reached after group 4a)
Committed on wip/top1: dff67ba8 = G4(a): test/core_lang/test_top1_prompt_swipl.jl (12 swipl-pinned prompt transcripts, pty-driven by
evidence/TOP1/gen_top1_rows.py, two byte-identical runs, evidence/TOP1/top1_rows.out; kernel side = Sread_user's three lines by hand over buffers
sharing one position record) and test/core_lang/test_top1_pro.jl (LK-only: PL_prompt_next, PrologPrompt/PL_write_prompt, writeAtomToStream,
validUserStreams, resetTracer/enable_debug_on_interrupt, resetProlog, halt_from_exception/restore_after_exception, query_loop x8 testsets).
Nothing compiled or run. Found: swipl prints the prompt only for a TTY stdin (pl-os.c:2171-2185), so the oracle needs a pty (python pty, echo off),
NOT a pipe. halt_from_exception returns false with the seam off (PL_halt), so the rows read gd.halt_exited.
LEFT (next agent, in order): (b) tools/mutants/TOP1.py (>=6; MOD3b.py format; candidates in "LEFT 2" above; TARGETS: test_top1_pro.jl,
test_top1_prompt_swipl.jl, test_lb5b_prompt.jl, test_autoload_trap.jl; anchors once via grep -c -F; throwaway runpy checker); (c) manifest rows
(pl-trace.jl/pl-pro.jl neighbours; PL_prompt_next is in src/pl-fli.jl: say whether the alloc pins x3 apply); (d) architecture block + DIVERGES flips
(src/pl-global.jl:447-452, src/pl-proc.jl:355, set_stream block in src/os/pl-file.jl, architecture ~6726 and ~6873), status board TOP1 row and a NEW
row TOP1b (PROPOSED: Sread_user, wrapIO, set_prolog_IO/3, Sread_terminal pl-os.c:2171-2224/:2462, prologToplevel, pl_break, currentBreakLevel +
break_level flag, PL_prompt_is_continuation, PL_prompt_string; why: stream layer dispatches on closed enum IOFUNCTIONS, S_read has no ld; recommend a
new function-set member plus an ld reference in the handle) in ~/code/lk-channel/evidence/R2/status_board.md (commit + push there). Also reword
the comment "have no counterpart yet" in src/pl-trace.jl enable_debug_on_interrupt (absence-claim hook).
FOR THE AUDIT: (1) src/pl-init.jl `_query_run_at_halt` is a reduced query_loop(.., false) and is NOT switched: switching adds resetProlog,
restore_after_exception and halt_from_exception to the at-halt query = behaviour change. (2) emptyStacks! mid-life, read-only analysis: it resets
the local/argument/trail/global stacks, the value table, frames and queries to the constructor's own state (pl-global.jl:702 calls it) and reopens the
base frame and the permanent exception/attvar/tmp cells; query_loop calls it only when ld.query == 0 and resetProlog only without nb_setval vars
(the gvar_nb_vars test = upstream's). It is safe when no caller holds a term_t or foreign frame id across the call (they are invalid after, as
upstream); the rows in test_top1_pro.jl (nfliframes) pin the effect; the gate decides. (3) The D-0164 term grep matches "abort" in the rows and in
restore_after_exception: it is the Prolog primitive unwind(abort), not the crash term.
Ready-for-gate list: NOT ready (b), (c), (d) missing.
