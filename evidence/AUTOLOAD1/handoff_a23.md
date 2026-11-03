# AUTOLOAD1 A2/A3 handoff (writer 2, Sonnet, edit-only: nothing was compiled or run)

## State
- Worktree ~/code/lk-autoload2, branch wip/autoload2, base e95ee9fe (= origin/main 133de9c0 + the 10 AUTOLOAD1 writer commits). The commit hook ACCEPTED every commit below (no marker problem met).
- Commits (oldest first): e53cb075 A2 (struct change: cold daemon restart, D-0394); 7bafce46 A3 source (src/pl-proc.jl); 1ad0e9c1 hook-guard DIVERGES text
  (D-0398 ruling); fd6edcc7 test/core_lang/test_autoload_trap.jl; dddb8c78 manifest rows; 6f4927e6 mutants A3a-A3r + A1e and two more test rows;
  9bc0b9f5 docs/architecture.md block "AUTOLOAD1 (A2, A3)". The handoff itself is a later commit.
- Daemon: none used. lanes.conf untouched.

## What A3 contains (src/pl-proc.jl)
- `_autoload_predicate_name(gd, def)` (ORIGINAL helper for pl-util.c predicateName), `test_autoload_loop(gd, ld, def)` (vector walked from the end; sets `autoload_loop`;
  messages through `_qlf_Sdprintf!`), `autoLoader(gd, ld, def)` (guard first: hook looked up with `isCurrentProcedure`, nil answer when missing or undefined, BEFORE
  the frame/context/nesting; then frame, 4 term refs, put module/name/arity, push_input_context(:autoload), push nesting, PL_open_query(system, NODEBUG|PASS_EXCEPTION),
  answer read before close, exception cleared when the query did not open, pop, pop_input_context, discard frame), `trapUndefined` as a `while true` loop.
- Signature changes vs the earlier design: `test_autoload_loop(gd, ld, def)` takes `gd` (names in the messages); manifest rows match.
- Rulings applied: D-0398 guard (transient DIVERGES "the Prolog half is not loaded", owner b2 / A5, guard line deleted when the hook is defined, no Julia hook), reset DIVERGES owner
  "the toplevel step" (no resetProlog code), `_qlf_Sdprintf!` for messages, predicateName original helper. A5 retires the test-hook rows (refusal-flip D-0375/D-0376): said in the architecture block.
- The toplevel step had NO row in evidence/R2/status_board.md; row TOP1 was added there (channel commit, see hand-back).

## UNVERIFIED (never run) — the gate agent reads these first
1. test_autoload_trap.jl in general: expected values hand-written from pl-proc.c. Helpers rely on rules_common.jl (`_RDB`, `_radd!`, `_rcall`) and on `LK.compileClause`/`assertDefinition!` into module `system`.
2. Row "the hook makes the module link a super's definition" (`assertz(system:fi)` then `user:fi`): `assertz` into `system` may be refused; if so, rewrite or drop and move mutant A3i to NOT LISTED.
3. Row "raising hook": `PL_exception(ld, 0) != 0` after `autoLoader` (the pending ball under PL_Q_PASS_EXCEPTION; sizing risk 6) — kills A3j; if the VM does not leave it pending, A3j is unkillable here (NOT LISTED, reason).
4. A1 killer row: `t(X,Y) :- Y = 1, call(user:foo), X = Y` through `_rcall`, answer text `t(1,1)`; kills A1e only if the frame overwrite is visible. If A1e survives, record equivalent-in-practice with the code reason or strengthen the row.
5. `(sysdef.flags & P_LOCKED) != 0` for system:rational/1 in the predicate-name row; `lookupModule(gd, atom)` returns the module; `ld.fli_context` read before/after.
6. Mutant A3a's `new` line (hook created, no defined test) recurses through the loop test (hook def on the nesting) and ends in an error: any verdict (kill by failure or by S_UNDEF row) counts as killed.
7. Mutants a-m of the first design are A3a-A3r in the file: (e) is split into A3e (warn on first) and A3f (third) because "never warn" would hang; `lookupDefinition` refresh is A3i.

## Ready-for-gate list (the gate agent runs it)
A2/A3 stack on gate/autoload1b; rebase the whole (A1, A4, Q3, A2, A3) under one new name (never force): `warm.sh fmt` (re-fit AUTOLOAD1.py anchors: every `old` occurs once now, count rechecked), `check`
(includes the Pkg.test-way run, D-0222), test_autoload_trap.jl x3 term types + `tools/pkgtest_way.sh test/core_lang/test_autoload_trap.jl` once, test_module_path.jl and test_autoload_flag_swipl.jl x3 (they exercise the guard),
test/test_type_discipline.jl, push `mutants/AUTOLOAD1` at the WIP SHA once TARGETS exist, branch-gate, the D-0164 term grep over diff and messages, push `gate/<name>` and `mutants/AUTOLOAD1` at the SAME SHA.
Struct change: cold daemon start; alloc pins x3 (struct changed). Also a JET look at `trapUndefined`'s `key` / `answer` locals (`Union{Nothing,T}`).
No local mutant list, no static run (D-0220).

## Rules recap
No absence phrases in committed text; no markers in workflows/absence_verified/; no git pipelines; edit and commit in separate calls; the commit hook refuses a partial index (stage every changed file before a commit).
