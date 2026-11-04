# CONT1 handoff (continuations at run time; audit D-0402 item 2d). Branch wip/cont1 off wip/lb4b2c 4e90042a.

Edit-only writer; nothing is run (no Julia). Spec: lk-channel evidence/R2/cont1_sizing.md. Upstream at the pin cbf4e1896275.

## Plan (ordered groups; upstream file:line -> Julia site; estimate)
| # | group | upstream | Julia | commits |
|---|---|---|---|---|
| C1 | five `procedures_*` fields + LOOKUPPROC; `ERR_PERMISSION_VMI` | pl-global.h:334-337,385; pl-ext.c; pl-error.c:384-391 | src/pl-global.jl, pl-setup.jl, pl-ext.jl, pl-error.jl | 1 |
| C2 | I_CALL1 `FR_INRESET` branch; I_RESET / I_EXITRESET (non-tabled) | pl-vmi.c:5529-5535, 5754-5833 | src/pl-wam.jl | 1 |
| C3 | liveness walker `mark_active_environment` / `walk_and_mark` | pl-gc.c:1709-1726, 1866-1936, 1957-2287 | src/pl-gc.jl | 2-4 |
| C4 | `findReset`, `put_environment`, `is_last_call`, `env3_predicate`, `put_continuation`, `shift`; I_SHIFT / I_SHIFTCP | pl-cont.c:74-445; pl-vmi.c:5874-5915 | new src/pl-cont.jl, pl-wam.jl, LogicKernel.jl | 2 |
| C5 | `push_continuation`; I_CALLCONT | pl-cont.c:456-548; pl-vmi.c:5839-5862 | src/pl-cont.jl, pl-wam.jl | 1 |
| C6 | I_YIELD, the non-engine branch | pl-vmi.c:2410-2418 | src/pl-wam.jl | 1 |
| C7 | flip b2's six `c_*` pin rows; remove the DIVERGES owner CONT1 block | | test files | 1 |
| C8 | mutants CONT1.py, manifest, docs (own LAST commits) | | tools/mutants, test manifest, docs/architecture.md | 2-3 |

## State (agent 1 handed back at the 150k cap; nothing run, no Julia)
Branch wip/cont1 in ~/code/lk-cont1, off wip/lb4b2c 4e90042a. Commits so far:
- 019220a5 plan; 29de9697 C1; 1d1e5e64 C2.
- C3 (src/pl-gc.jl: `walk_state`, `mark_frame_var`, `clear_frame_var`, `clear_choice_mark`, `mark_choice_mark`,
  `walk_and_mark(state, codes, pc, end_op)`, `mark_active_environment(ld, active, fr, codes, pc)`) is STAGED and
  committed together with this file (subject "ADDED: walk_and_mark and mark_active_environment ... (CONT1 C3)").

### C1 (done)
`procedures_reset3 / dtbl_reset6 / call_continuation1 / dmeta_call1 / findall_loop4` appended to `PL_global_data` (src/pl-global.jl),
constructor (src/pl-setup.jl), LOOKUPPROC of the first four in `setBuiltinPredicateProperties!` (src/pl-ext.jl); `findall_loop4` is
left at the placeholder and must be set by `findReset` (C4) with the lookup of `findall_loop/4` in module `$bags`.
`ERR_PERMISSION_VMI` appended to `PL_error_code`; it shares the `String` method of `ERR_SYNTAX` (pl-error.jl):
`PL_error(ld, "", 0, "not an engine", ERR_PERMISSION_VMI, "I_YIELD")` gives `permission_error(execute, vmi, 'I_YIELD')`.
ERR_PERMISSION_YIELD is left to the engine step (needs thread_self).

### C2 (done)
`i_metacall_common` (src/pl-wam.jl): the `FR_INRESET` branch to `mcall_cont` with `dmeta_call1`, the assert removed.
`I_RESET` and `I_EXITRESET` written (non-tabled); the `dtbl_reset6` branches throw `NotPortedError(.., "TAB1")`.
The refusal comment above `@label I_YIELD` (header of the six instructions, "refused by name until CONT1") is now stale for
I_RESET/I_EXITRESET: reword in C7.

### C3 (written, unrun)
Flags: (a) `I_RATIONAL` is not in upstream's list of type tests in `walk_and_mark` (pl-gc.c ~2131-2141); ported as is, check against swipl
with a clause using `rational/1` on a late-read variable. (b) The indirect literals (B_STRING, B_MPZ ...) are ONE operand word here,
so `code_get_indirect` is not needed. (c) `pc` is the OPCODE INDEX (like `clearUninitialisedVarsFrame`); the caller of
`mark_active_environment` (C4 `put_environment`) must pass the index of the instruction the frame resumes at: for a frame
that called a child, the saved `programPointer` of the child (`Code{T}(PCc, PCl, PC)`: its `PC` is already the index past the call's operands).
(d) The walker needs `fr`'s predicate arity only for I_CALLCLEANUP / I_EXITCLEANUP / I_EXITRESET.

## LEFT (new agent starts here; each is one WIP commit, in this order)
- C4: new `src/pl-cont.jl` (read the reference corpora first: new-file rule; include it in src/LogicKernel.jl after pl-gc.jl).
  `findReset` (pl-cont.c:74-100), `put_environment` (110-241), `env3_predicate` (244-253), `is_last_call` (265-283), `put_continuation`
  (286-366), `shift` (372-445); `I_SHIFT` / `I_SHIFTCP` / `shift_common` (pl-vmi.c:5874-5915) replacing the refusals in src/pl-wam.jl
  (~line 3340). Julia needs: the term construction of `'$cont$'(Module, ClauseRef, PCoffset, Slot...)` (PL_cons_functor_v / list
  builders are NOT verified in the kernel: check src/pl-fli.jl), the clause blob of a frame's clause (`clause_clref`, src/pl-dbref.jl),
  `setLTop!` / pool drop for the `lTop` trim (pl-cont.c:411-445), `environment_frame` update, `shift_check` flag (os/pl-prologflag.jl:1976),
  error `existence_error(reset, Ball)` (pl-cont.c:436-443) and the findall message (pl-cont.c ~85-95).
- C5: `push_continuation` (pl-cont.c:456-548) + `I_CALLCONT` (pl-vmi.c:5839-5862; the `call(G)` shortcut at 5843-5845).
  `push_continuation_list` (587-627) stays refused, owner TAB1.
- C6: `I_YIELD` non-engine branch (pl-vmi.c:2410-2418) using `ERR_PERMISSION_VMI`.
- C7: flip b2's six `c_*` pin rows in `test/core_lang/test_cont_boot_swipl.jl` to swipl's answer (query swipl 10.1.19), remove the
  `DIVERGES owner CONT1` block (src/pl-wam.jl ~3268-3272 and the NotPortedError arms), update the src/pl-vmi.jl header ("run: CONT1" docstrings).
- C8: `tools/mutants/CONT1.py` (TARGETS: the cont rows file, test_cont_boot_swipl.jl, any file running reset/shift; anchors once each),
  manifest entries (test/static_analysis_manifest.jl: the new `PL_error` method set is unchanged except the enum value; new functions
  `walk_and_mark`, `mark_active_environment`, `mark_frame_var`, `clear_frame_var`, `clear_choice_mark`, `mark_choice_mark`, and C4/C5's),
  docs/architecture.md block; each in its own LAST commit. Oracle rows via swipl 10.1.19 (reset/3 with no shift => Cont == 0; control construct
  inside reset; Cont bound => uninstantiation_error; var goal => instantiation_error; shift outside reset => existence_error(reset, a);
  shift under findall; the standard iterator and effect-handler programs).
- Gate order after the last commit: fmt (through warm.sh send of the committed files), inventory, check, rows x3, type discipline,
  pkgtest_way, mutants branch, branch-gate, term grep, alloc pins x3 (pl-global.jl and Tier-1 files changed), gate push on a FRESH name.

## Flags for the audit
1. pl-global.jl struct grows by five fields (append-only; Tier 1 alloc pins x3).
2. `I_RESET`/`I_EXITRESET` tabled branches refused by name with owner TAB1 (representation of a recorded deferral, not a behaviour change for non-tabled code).
3. `ERR_PERMISSION_VMI` is dispatched inside the `ERR_SYNTAX` String method (same argument types); manifest has no new `PL_error` signature.


## C4 state (writer 2, handed back at the cap; nothing run, no Julia)
Commits on wip/cont1 after aa3197d0: be62dfc8 (PL_cons_functor_v, PL_cons_list_v in src/pl-fli.jl: the builders existed only as the
Vararg PL_cons_functor / PL_cons_list); 0170e319 (new src/pl-cont.jl + include after pl-gc.jl: `findReset`, sets
`procedures_findall_loop4` when its definition arity is not 4); group 2 (`env_functor`, `_cont_functor`, `put_environment`,
`env3_predicate`, `is_last_call`) is in src/pl-cont.jl, committed together with this file.
LEFT for the next agent (C4 groups 3-4, then C5): 
- group 3 `put_continuation(gd, ld, cont, resetfr, fr, pc::Code{T}, for_copy)` (pl-cont.c:286-366) and `shift(gd, ld, ball, for_copy)` (372-445).
  Notes from reading: frames are pool indices (stable: no reload of valTermRef); a frame argument is the term_t `argFrameP(f.base, i)`;
  `contv = PL_new_term_refs(ld, depth)` (0 = failure); the `env3_predicate` branch uses `PL_put_term(ld, av+i, argFrameP(base,i))`,
  `PL_cons_list_v`, `PL_cons_functor(ld, av+0, _cont_functor(ld,:call_continuation,1), contv)`, `PL_cons_functor_v`, `PL_cons_functor(.., :call, 1, ..)`;
  `onStackArea(local, cl)` has no counterpart (a Clause is a Julia object): omit with a comment; the loop's `pc = fr->programPointer` is a `Code{T}`;
  put_environment takes `pc.pc` (index). Errors: `PL_error(ld, "shift", 1, msg, ERR_EXISTENCE, mk_sym(T,:reset), ball)` with msg
  "No matching reset/3 call" / "Cannot catch continuation through findall/3" (FRESET_FINDALL -> second); ERR_UNINSTANTIATION via
  `PL_error(ld, "", 0, "", ERR_UNINSTANTIATION, 0, argFrameP(resetbase,1))` when `PL_exception(ld,0) == 0`; `PL_new_term_ref(ld)` + `PL_put_nil(ld, cont)`.
  lTop trim: use `lowerLTop!(ld, X)` (X = `ld.choices[ld.BFR].base + SIZEOF_CHOICE` when `frame.base <= choices[BFR].base`, else
  `argFrameP(parent.base, Int(parent.clause.clause.variables))` after `fr == resetfr`); then `ld.environment_frame = resetfr.parent`, return
  `resetfr.programPointer` (a dropped record stays readable).
  FLAG (for the audit): upstream's shift_common closes its foreign frame AFTER shift: `PL_close_foreign_frame` does `lTop = fr` (the foreign
  frame's base, above the trimmed value), which undoes the trim in C. In Julia `PL_close_foreign_frame` -> `lowerLTop!(ld, f.base)` asserts
  `p <= ld.lTop`, so the VMI must raise `ld.lTop = ld.fliframes[fliFrameOfFid(ld, fid)].base` (a raise, no drop) before closing; the trimmed-away
  frame records stay dead. Document as DIVERGES.
- group 4 the VMIs in src/pl-wam.jl, replacing the refusals at ~3340-3352: I_SHIFT / I_SHIFTCP set `sh_copy` and `@goto shift_common`; the label:
  `sh_k, sh_w, sh_p = _deref_loc(ld, -(varFrameP(ld.frames[FR].base, Int(PCc[PC])) + 1)); PC += 1; ball = pushWordAsTermRef(ld, (sh_k, sh_w, sh_p))`;
  `@SAVE_REGISTERS(QID)`; `fid = PL_open_foreign_frame(ld)`; `pc = shift(gd, ld, ball, sh_copy)`; raise lTop (flag above); `PL_close_foreign_frame(ld, fid)`;
  `@LOAD_REGISTERS(QID)`; `popTermRef(ld)`; on a `Code`: `PCc=pc.codes; PCl=pc.literals; PC=pc.pc; FR=ld.environment_frame;
  DEF=ld.frames[FR].predicate::Definition{T}; ARGP=argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph); @goto next_instruction`, else `@goto b_throw`.
  Also reword the stale "refused by name until CONT1" lines for I_SHIFT/I_SHIFTCP at the pl-wam.jl header (~3263-3272, C7 finishes).
- Not verified (nothing run): `lookupModule(gd, mk_sym(T, Symbol("$bags")))`, `_qlf_Sdprintf!` text (`$(f.predicate.name)` interpolates a term), the
  `consInt(Int64(pc - 1))` base (the 0-based offset as swipl), `f.clause.clause::Clause{T}`.
- Hook note: creating src/pl-cont.jl needed a Read of the upstream file under ~/dev-zone (new-artifact hook); a docstring `$` must be `\$`.
