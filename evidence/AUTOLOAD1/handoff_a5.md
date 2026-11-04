# AUTOLOAD1 A5 handoff (writer 1, Sonnet, edit-only: nothing was compiled or run)

Worktree ~/code/lk-autoload5, branch wip/autoload5, base 7d691c4a (= origin/main after A1-A4, Q3, A2, A3, static fix). Never pushed.
Sources read: audit D-0397 item 3, D-0398 item 2, D-0400 item 2; R2/autoload1_sizing.md (A5 row); gates 4, 5, 7; handoff_a23.md.
Upstream at the pin cbf4e1896275: boot/init.pl:949-969 (`$undefined_procedure/4`), boot/autoload.pl (`$autoload/1`, `set_autoload/1`
:945-946), src/pl-proc.c:2932-3063, src/pl-init.c:2347 (`vwarning`).

## What the Prolog half is (finding that shapes the plan)
The hook half is upstream's own text and is VENDORED verbatim (vendor/swipl-devel/boot/init.pl, autoload.pl; PIN file).
Nothing of it is written in this step: `system:'$undefined_procedure'/4` is defined by the loader (LB4 b2, the first boot) when
init.pl loads, and `'$autoload'/1` when autoload.pl loads. `autoLoader` (src/pl-proc.jl, A3) already reaches it as pl-proc.c does
(PL_pred system:$undefined_procedure/4, PL_Q_NODEBUG|PL_Q_PASS_EXCEPTION, four term refs). So the only unbooted piece of A5 is
the white-box side; everything that needs the real hook waits.

## Groups, in order
| # | Group | Upstream | Julia site | State |
|---|---|---|---|---|
| G1 | A1c row: the autoloader's query returns to the trapped frame (test-defined hook, VM path `call(user:foo)`; reads the hook query's record from the pool inside the `at` callback of `_rcall`) | pl-wam.c PL_open_query (`saved_environment`), pl-vmi.c:5707-5722 | test/core_lang/test_autoload_trap.jl | WRITTEN (commit 2), UNVERIFIED |
| G2 | tools/mutants/AUTOLOAD1.py: A1c `equivalent:` declaration -> KILL naming the G1 row; header lines | D-0400 item 2 | tools/mutants/AUTOLOAD1.py | WRITTEN (commit 3) |
| G3 | architecture block "AUTOLOAD1 A5 (part 1)" | - | docs/architecture.md | LAST commit |
No manifest rows: G1 adds no function.

## Waits for the first boot (b2 = LB4 b2 first boot; owner: the boot-files lane). The READY-AFTER-BOOT list, in landing order
Needs: b2 passes; LB4 b1 (INDEX.pl vendored); LB2b; EV1; DBG1 `$notrace/2`, `$restore_trace/2` (autoload.pl calls them).
1. `test/core_lang/test_autoload_swipl.jl` (new; the A5 sizing row). Swipl 10.1.19 rows, one extractor, non-vacuity block: autoload of
   a library predicate (`lists:append/3` class), error on a non-existent
   predicate, flag `autoload` false / explicit / user / user_or_explicit, module `unknown` flag fail, library(debug) from
   tabling.pl:119, the retry loop (`exception/3` answering retry twice: one "exception handler failed to define" line per trap),
   an exception inside the autoload (library with a syntax error / failing `ensure_loaded`: sizing risk 6: S_VIRGIN does not test
   `exception_term` after the call, so the final answer comes from S_UNDEF/PL_error with a ball pending; compare with swipl before
   trusting), the `user:exception/3` path (boot/init.pl:959-963). Sorted compare for unordered answers.
2. af08 flip (D-0397 item 3a). `set_prolog_flag(autoload, X)`, X unbound: swipl answers true through `$autoload:set_autoload/1`
   (autoload.pl:945-946); the kernel's rows run with `gd.bootsession` set and `propagateAutoload` returns at once
   (src/os/pl-prologflag.jl:1007-1010). Flip: run the af rows on the BOOTED template with `bootsession` off; delete
   `_AF_KERNEL_DIFFERS` and its comment (test/core_lang/test_autoload_flag_swipl.jl:243-246, :268-274), delete the DIVERGES text at
   src/os/pl-prologflag.jl:1000-1005 and the "missing seam" lines in the architecture row; the `bootsession` toggling in
   `_af_kernel` goes with it. The kernel then answers `t_af08 ... a[116,114,117,101]` (the pin, test_autoload_flag_swipl.jl:172).
3. The hook guard (D-0398 item 2, conditions a-e): delete the two guard lines in `autoLoader` (src/pl-proc.jl, the
   `isCurrentProcedure` lookup and `(hook === nothing || !isDefinedProcedure(gd, hook)) && return answer`), replace by upstream's
   `PL_predicate` (`lookupProcedure(system, $undefined_procedure/4)`), delete the transient DIVERGES (src/pl-proc.jl:383-386 and the
   trapUndefined header), and in the SAME commit retire the test-hook rows of test_autoload_trap.jl (they define clauses in
   `system:'$undefined_procedure'/4`, which on a booted database would add clauses to the real hook): testsets "the guard",
   "a test-defined hook", loop, restore, flag/boot, autoImport, refreshed definition, A1 killer, and the G1 row; mutant A3a (hook
   created without the defined test) and the guard mutant (drop the guard) leave tools/mutants/AUTOLOAD1.py with the rows (refusal-flip
   rule D-0375/D-0376). The swipl-compared rows of item 1 replace them. LAST code commit of A5 because every unbooted database
   (test_module_path.jl:81-86 and the A1 files) relies on the guard.
4. A1c on the booted hook, swipl-compared: needs `prolog_frame_attribute/3` (DBG1, `parent`, `predicate_indicator`) inside a
   `user:exception/3` hook: parent of the query's top frame is the trapped frame, whose predicate_indicator is `foo/0`. Until then G1
   (record-pool read) is the kill. Not required for A5 to land.
5. The retry warning (pl-proc.c:3042 `warning(...)`, pl-init.c:2347 `vwarning`): upstream builds `message_lines([Strings])` and calls
   `system:print_message(error, ...)` when `!GD->bootsession && GD->initialised && !LD->outofstack && fm[0] != '$'`, else writes
   `ERROR: <text>` to `Suser_error`. The kernel has no `GD->initialised` (a struct change, so a cold restart and alloc pins) and
   `printMessage` (src/pl-error.jl:1025) is itself a stand-in until print_message/2 loads. Owner b2 (print_message/2 from
   boot/messages.pl) then one commit: `vwarning` in src/pl-init.jl, `gd.initialised` set at the end of the init sequence,
   `trapUndefined` calls it instead of `_qlf_Sdprintf!` (src/pl-proc.jl, the retry branch); `test_autoload_loop` keeps `Sdprintf`
   (upstream's too, pl-proc.c:2934-2950). The row: the swipl text "[Thread 1]: exception handler failed to define rn/0" through
   print_message (capture with `user:message_hook/3`). Not written now: it would be a second stand-in.
6. clause/2: remove the `@assert dref.generation == generationFrame(...)` (src/pl-comp.jl:3669-3675) and kill NF2-C5 (tools/mutants/NF2.py:80,
   `equivalent` -> KILL) with the row "clause/2 on an autoloadable predicate == swipl" (a `P_AUTOLOAD` predicate declared with
   `autoload/2`, `clause(append(X,Y,Z), B)` loads library(lists) inside `trapUndefined`, which bumps the global generation).
   Could be written unbooted with a test hook that `assertz`es the predicate (retry), but the assert text names the swipl-compared
   row; done with item 1.
7. Docs/ledger: sizing row A5, status board row, `docs/port_inventory.md` regenerated by the gate (never by hand).

## Notes only (no action)
- `_autoload_predicate_name` (src/pl-proc.jl:337) is the single `predicateName` text helper in this tree; the brief's
  `_cont_predicate_name` has zero matches in src/ at 7d691c4a (probably the MOD helper under another name): NOTE only, one helper once
  pl-util.c's `predicateName` is ported.
- The G1 row reads `ld.queries[ld.nqueries + 1]` and `ld.frames[E]` inside the `at` callback: dropped records stay readable until a
  push reuses them (test_local_stack.jl header). If the gate finds the pool slot recycled, move the read into the hook's own record
  (a Prolog `prolog_current_frame/1` recorded in `called/1`, then `ld.queries[i].base == F - QF_FRAME`) or restore the A1c
  declaration from the commit before G2.

## Commit estimate
Now: 4 (plan, G1, G2, G3 docs) plus this handoff update. After the boot: item 1 (1-2), 2 (1), 3 (1), 5 (1, struct change), 6 (1), 4
(DBG1, 1), docs (1): 7-9 commits, half a day of writer time once b2 passes, plus a gate with the booted template.

## Gate order for the pre-boot commits (gate agent)
fmt (committed files via `warm.sh send`), check (incl. Pkg.test-way), test_autoload_trap.jl x3 term types + `tools/pkgtest_way.sh
test/core_lang/test_autoload_trap.jl`, test_type_discipline.jl, push `mutants/AUTOLOAD1` at the WIP SHA, branch-gate, crash-term grep,
push `gate/<name>` and `mutants/AUTOLOAD1` at the same SHA. The mutants file changed: the battery re-runs (D-0374). Re-fit anchors
after fmt (every `old` once).
