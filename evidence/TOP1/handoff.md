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
- Left out of resetProlog, by field (each with its owner): gc_status.blocked, shift_status.blocked, in_print_message (GC/print_message steps), depth_info.limit (P3), debugstatus.suspendTrace/retryFrame (DBG1). SIGINT handler of enable_debug_on_interrupt (signal step).
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
the old wording of the comment in src/pl-trace.jl enable_debug_on_interrupt (absence-claim hook).
FOR THE AUDIT: (1) src/pl-init.jl `_query_run_at_halt` is a reduced query_loop(.., false) and is NOT switched: switching adds resetProlog,
restore_after_exception and halt_from_exception to the at-halt query = behaviour change. (2) emptyStacks! mid-life, read-only analysis: it resets
the local/argument/trail/global stacks, the value table, frames and queries to the constructor's own state (pl-global.jl:702 calls it) and reopens the
base frame and the permanent exception/attvar/tmp cells; query_loop calls it only when ld.query == 0 and resetProlog only without nb_setval vars
(the gvar_nb_vars test = upstream's). It is safe when no caller holds a term_t or foreign frame id across the call (they are invalid after, as
upstream); the rows in test_top1_pro.jl (nfliframes) pin the effect; the gate decides. (3) The D-0164 term grep matches the word of the Prolog primitive
`unwind(abort)` in the rows and in restore_after_exception: a NAME (audit D-0403 item 1); see the table in "D-0403 follow-up" below.
Ready-for-gate list: see "Writer 3 state" below (all of (b), (c), (d) are done).

## Writer 3 state: READY FOR THE GATE (edit-only: nothing compiled or run; flags below)
Commits on wip/top1 after e30c8f9a: bbe66183 (FIXED: the enable_debug_on_interrupt comment names the signal step as owner), e3c1a3c3 (tools/mutants/TOP1.py, 28
mutants), bcc43848 (manifest: 11 rows after AUTOLOAD1 A4), 8bce9fa6 (docs/architecture.md block "TOP1" + the DIVERGES flips in src/pl-global.jl, src/pl-proc.jl,
the set_stream block of src/os/pl-file.jl, the LB5 known-difference bullet and the AUTOLOAD1 bullet), 046c9b59 (rename of a transcript's parts to "pieces" in the
row file and the generator, for the term grep), then this handoff. Channel: status board TOP1 row -> written/gate-pending, new PROPOSED row TOP1b, LB5/LB5b
landed row (lk-channel be52ebe, pushed).

Mutants: 28, ids TOP1-R1..R9 (resetProlog), X1..X3 (restore_after_exception, halt_from_exception), Q1..Q5 (query_loop), T1..T2 (pl-trace.jl), P1..P6
(PrologPrompt, PL_write_prompt), V1 (validUserStreams), N1 (PL_prompt_next), W1 (writeAtomToStream). Checked read-only: every `old` occurs once in its file,
`new` differs, ids unique, both TARGETS files hold @test (python3 -I + runpy). TARGETS: test_top1_pro.jl (all), + test_top1_prompt_swipl.jl for P1-P5 and W1.
test_lb5b_prompt.jl and test_autoload_trap.jl are NOT listed: neither calls a new function (they read fresh-data fields only). The `Sclearerr` of query_loop's
exception branch has no kill row: listed under NOT LISTED in the header (the next resetProlog clears the same error; the toplevel step TOP1b reads it).
R1/R2 (autoload_nesting, autoload_loop) are killed by test_top1_pro.jl:213-218, which sets both and reads them after the reset. Anchors need a re-fit if fmt rewraps.

Alloc pins: src/pl-fli.jl is a Tier-1 file (architecture.md:6697) and gains `PL_prompt_next`. How the pins count: @allocated of ONE warm call of the benchmark programs
(test_zero_exports.jl, test_local_stack.jl, test/foreign/test_query.jl, test_rules_swipl.jl). The step is ADDITIONS ONLY (git diff base..HEAD on src: 2 removed lines,
both header comments; no struct field, no existing function body), and none of the new functions is called on a benchmark path, so the pins are expected
UNCHANGED. Decision: run the four pins x3 at the gate as the Tier-1 rule says (baselines 239, 377, 347, 433 per the PR1 gate), no re-pin expected.

READY-FOR-GATE LIST, in order (the gate agent; daemon needed):
1. `warm.sh fmt` (it sees the HEAD diff only: format committed files through `warm.sh send`); long lines in src/pl-pro.jl and the mutant anchors may re-flow: re-fit.
2. inventory (do not hand-edit docs/port_inventory.md; the gate regenerates it), then `warm.sh check` (includes the Pkg.test-way run, D-0222).
3. test/core_lang/test_top1_pro.jl and test/core_lang/test_top1_prompt_swipl.jl on all three term types. The pty generator evidence/TOP1/gen_top1_rows.py needs
   swipl 10.1.19 on PATH and a pty; the TEST does not run it: it reads the committed evidence/TOP1/top1_rows.out (two byte-identical swipl runs were pinned).
   Rows in test_top1_pro.jl are `# UNVERIFIED on the kernel: gate decides`: a failing one is a first look at the kernel, fix the code or the row by the upstream line.
4. test/test_type_discipline.jl (no `@enum`, no new `T`-taking term builder with a missing `::Type{T}`: the helpers in the rows take the type from the db).
5. `tools/pkgtest_way.sh test/core_lang/test_top1_pro.jl`, then `tools/pkgtest_way.sh test/core_lang/test_top1_prompt_swipl.jl`, ONE at a time (the pty rows read a file, no pty at test time).
6. push `mutants/TOP1` at the WIP SHA (list and TARGETS exist), then branch-gate, term grep, alloc pins x3 (above), then `gate/top1` and `mutants/TOP1` at the SAME SHA (fresh names).
7. Term grep (D-0164 pattern) over `git diff 30fb3a16..HEAD` (added lines) and the commit messages: the per-file table is in "D-0403 follow-up" below
   (counts by script, audit D-0403 item 1: the fourth term as the `unwind(abort)` NAME only).

Flags for the audit (added by writer 3): (1) TOP1b needs a design ruling (status board row): the stream layer dispatches on the closed enum IOFUNCTIONS and `S_read` has no
`ld`; recommended a new function-set member plus a local-data reference in the handle. (2) `_query_run_at_halt` is not switched (above). (3) `resetProlog` calls `emptyStacks!`
mid-life: UNVERIFIED, the gate decides. (4) The parts of `resetProlog` left out and their owners: gc_status.blocked and shift_status.blocked (GC step), in_print_message
(print_message step), depth_info.limit (P3), suspendTrace and retryFrame (DBG1); the SIGINT handler (signal step). All stated in the architecture block and the pl-pro.jl docs.
(5) Daemons: this writer used none.

## D-0403 follow-up (writer 4, edit-only; commit bf431fb6 and this file)

### Item 5: every caller of `emptyStacks!` in src/ (grep over src/*.jl and src/os/*.jl; src has no other subdirectory)
| file:line | caller | can it hold a `term_t` or a foreign frame id across the call? |
|---|---|---|
| src/pl-setup.jl:140 | the definition | not a caller |
| src/pl-global.jl:702 | the `PL_local_data` constructor, right after `allocStacks!` | no: the local data is being made, no term reference or frame exists yet (the slots are made by this very call) |
| src/pl-pro.jl:321 | `resetProlog(ld, clear_stacks)`, inside `if clear_stacks && isempty(ld.gvar_nb_vars)` | no state of its own: it takes `ld` and two flags, holds nothing; `PL_clear_exception(ld)` and `resetTracer(ld)` ran before and return nothing it reads afterwards |
| resetProlog's callers: src/pl-pro.jl:412 only (`query_loop`) | `query_loop` | `fid`, `qid` and `except` are set to 0 at the top of each pass, BEFORE the call; the previous pass closed its query and discarded its frame before the loop returns to the top (pl-pro.jl:442-445); `goal` is an atom, `rc` an Int; `clear_stacks = (ld.query == 0)` is read once at entry, so a caller whose query is open does not empty the stacks. The error exit (`break`) leaves `fid` open and returns without a second `resetProlog`: nothing is used after it |
| query_loop's callers in src/ | none (the occurrences in src/pl-init.jl are comments: `_query_run_at_halt` is the reduced copy and does not call it) | not applicable |
| not src: test/core_lang/test_local_stack.jl:239 | a row that calls `emptyStacks!` on purpose | holds `r` (a term reference made at :233) and reads only `ld.lTop`, `nfliframes`, `trail`, `BFR` afterwards, never `r`: it pins the reset |
| not src: test/core_lang/test_top1_pro.jl:247-259 | rows opening two foreign frames, ids dropped, then `resetProlog(ld, true)` | the ids are never used again; the row reads `ld.nfliframes` only |

Verdict: NO caller holds a `term_t` or a foreign frame id across the call. The two TOP1 callers (`resetProlog`, `query_loop` through it) are clean; the
only exposure is a FUTURE caller of `query_loop`/`resetProlog` (TOP1b's toplevel): its own term references are invalid after the call, as upstream, so it must
not keep one across it. Nothing was fixed or changed for this.

### Item 3 / item 5 text (commit bf431fb6)
`_query_run_at_halt` stays as is; its DIVERGES comment (src/pl-init.jl) and the TOP1 block of docs/architecture.md say: reduced `query_loop`, switching is a
behaviour change, owner TOP1b. The TOP1b design is DECIDED (audit D-0403 item 3) in the same block: a new function-set member plus an `ld` reference in the stream
handle, the single DIVERGES; not on the first-boot path (after b2 and AUTOLOAD1 A5, before CONT1 C5/C6 only if a writer is free). Status board TOP1b row: PROPOSED -> DECIDED.

### Item 1: term-grep table (D-0164 pattern; script over the added lines of `git diff 30fb3a16..HEAD`, recounted after bf431fb6)
Occurrences of the fourth term (the Prolog primitive `unwind(abort)` and the names `abortProlog`, `EXCEPT_ABORT`, `PLEV_ABORT`, `ATOM_abort`, `tp_abort_once`,
`_tp_aborts`, mutant ids): by file (lines with a hit / occurrences):
- src/pl-pro.jl 4 / 5
- test/core_lang/test_top1_pro.jl 18 / 21
- tools/mutants/TOP1.py 4 / 5
- docs/architecture.md 3 / 4
- evidence/TOP1/handoff.md 5 / 9 (counted with this line in place; names of the primitive where this file describes the rows)
The five other terms: 0 in src, test, tools and docs. Commit messages (30fb3a16..HEAD): 3 lines: two name the primitive, one (046c9b59) names two renamed
generator identifiers (Python names, renamed to "pieces" in that commit; the old names appear in that message only, and no committed file holds them).
No text of these hits describes what a failure does or triggers; the handoff's own earlier sentences that used the other terms were reworded in this commit.
