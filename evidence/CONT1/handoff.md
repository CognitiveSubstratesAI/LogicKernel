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


## C4 groups 3 and 4 (writer 3; nothing run, no Julia)
Commits on wip/cont1 after ca28f54d: 780fe16d (`put_continuation`, `shift`, `_cont_predicate_name` in src/pl-cont.jl),
3524c342 (`I_SHIFT`, `shift_common`, `I_SHIFTCP` in src/pl-wam.jl replacing the refusals; header comment of the six
instructions reworded: only `I_CALLCONT` and `I_YIELD` still refuse), a19055a2 (one comment in src/pl-gc.jl reworded). This file is its own commit.

### The lTop decision (flag for the audit, representation only; DIVERGES comment at `shift_common` in src/pl-wam.jl)
Upstream: `shift` trims `lTop`, then `shift_common` calls `PL_close_foreign_frame(fid)`, which sets `lTop = (LocalFrame) fr`, the
foreign frame opened BEFORE the trim, i.e. the `lTop` before `shift`: the trim is undone in C and the dead frames' words are left on
the stack. The kernel's frames are pool records and `dropRecords!` is what keeps dead ones out of the walks (`markPredicatesInEnvironments!`,
`_is_newest_live_frame`), so the trim must drop them: `shift` uses `setLTop!` (as pl-cont.c's trim), `shift_common` raises `ld.lTop`
to `fid` (= the foreign frame's base, `open_foreign_frame` returns `f.base`) when the trim went below it (a plain assignment, no
records dropped), then `PL_close_foreign_frame` (`lowerLTop!(f.base)`: p == lTop, nothing left to drop; `fliFrameOfFid` still finds
the dropped record through `fli_context`, records stay readable). Net `lTop` after the instruction is upstream's. The alternative
(never trim, leave the dead records) was rejected: it would leave dead frame records live in the pool. When `shift` fails before the
trim (error paths) `lTop` is above `fid` and the close lowers normally.

### Verified by reading the kernel (writer 2's guesses)
- `lookupModule(gd, name::T)` creates the module (src/pl-modul.jl:257); `lookupProcedure(name, arity, m::module_t)` ok.
- `ERR_EXISTENCE` goes through `PL_error(ld, pred, arity, msg, id, a::T, actual::term_t)` (src/pl-error.jl:365), so
  `PL_error(ld, "shift", 1, msg, ERR_EXISTENCE, mk_sym(T, :reset), ball)` gives `existence_error(reset, Ball)` with the message.
- Choice slots: C_IFTHENELSE/C_IFTHEN store `consInt(ld.choices[BFR].base)` (src/pl-wam.jl ~4292), so `ld.slots[argFrameP(base,i)+1]` copied raw is
  upstream's `consInt(argFrame(fr, i))`. C5 reads them back with that value as a choice BASE position.
- `environment_frame` is kept equal to `FR` (set at each frame entry/exit), so `shift` reads `ld.environment_frame`.
- The `shift_check` text: `$(f.predicate.name)` would interpolate a term; replaced by `_cont_predicate_name(gd, def)` (module prefix
  unless user or locked-and-visible-in-user, as pl-util.c `predicateName`); AUTOLOAD1 A3 has the same helper on its own branch
  (`_autoload_predicate_name`, wip/autoload2b src/pl-proc.jl): merge to one when both have landed. Clause number and backtrace are DBG1.
- `onStackArea`/`PL_representation_error("continuation")` left out (a clause is a Julia object), commented in `put_continuation`.
- The PC in the `'$cont$'` term is `pc - 1` (swipl's 0-based offset): the comment at the `consInt(Int64(pc - 1))` site in `put_environment`
  says C5 must add the 1 back (`codes[offset + 1]`).

### Unrun / unverified (all of it; the gate decides)
Nothing compiled. Points a first run may hit: (1) `put_continuation`'s `if ... && ... &&` layout (fmt will re-flow); (2) `rc, reset = findReset(...)`
with `rc == 1` and the `msg[-rc]` index; (3) `PL_cons_functor(ld, av, fd, contv)` Vararg with N=1; (4) `shift`'s return type
`Union{Nothing, Code{T}}` narrowing in the VMI (`sh_pc !== nothing`); (5) `sh_copy` assigned before two `@goto`s to one label;
(6) the `ld.choices[ld.BFR]` read (BFR != 0 in a running query); (7) manifest rows for `put_continuation`, `shift`, `_cont_predicate_name`,
`env_functor`, `_cont_functor`, `put_environment`, `env3_predicate`, `is_last_call`, `findReset` are C8's.

### What C5 needs
`push_continuation(gd, ld, continuation, pfr, pcret)` (pl-cont.c:456-548) and `I_CALLCONT` (pl-vmi.c:5839-5862). Julia sites and idioms:
- the term `'$cont$'(Mod, Blob, PCoffset, Slot...)` at `continuation` (deref); Mod is `[]` or a module name; `clause_clref(gd, blob)` returns the
  `Clause{T}` or `nothing` (non-blob / other blob type): `nothing` or `arity != cl.variables + 3` => `PL_type_error("continuation", continuation)`
  (`PL_error(ld, ERR_TYPE, mk_sym(T,:continuation), continuation)`).
- slots: the first `cl.prolog_vars` are `_cell_link!`'d values (inactive ones are the atom `<inactive>`); the rest are `consInt(choice base)` or 0;
  restore = walk `ld.BFR` down the `choices` chain looking for `choices[k].base == value`; found => the slot keeps `consInt(base)`
  (as C_IFTHENELSE stores it), else `consInt(choices[BFR].base)` (upstream's `consTermRef(LD->choicepoints)`).
- the frame: `pushFrame!(ld, p)` at `ld.lTop`, fields as `I_EXITCATCH`'s siblings and `normal_call` (vmi:1887-1897); `fr.clause = ClauseRef{T}(nothing,
  word(0), cl, nothing)` (src/pl-wam.jl:1986, :3726); upstream's blob-on-stack word (AGC protect) is left out (no atom GC; `gd.clause_refs` keeps every clause);
  `programPointer = pcret` (a `Code`); `fr.context` from `mname`; PC for the run = `Code(cl.codes, cl.literals, pcoffset + 1)`.
- `I_CALLCONT` (pl-vmi.c:5839): the `call(G)` shortcut at 5843-5845 and the `push_continuation_list` branch (587-627) stays refused, owner TAB1.
- R4 (read now): `clause_clref` returns the `Clause` for ANY serial in `gd.clause_refs`, erased or not (`gd.clause_refs` is append-only; docstring:
  "the clause may be erased"); upstream also does not test erasure in `push_continuation` (the blob keeps the clause alive). So an
  erased clause is restarted as upstream restarts it; no type_error for it. `lookup_clref` gives a clause its serial on first reference, so
  `'$cont$'` terms made by `put_environment` always resolve. Risk left: a frame running an erased clause must survive `I_EXIT`'s
  `ec_f.clause = nothing` / clause-GC paths (the existing erased-clause-in-frame handling), which the first C5 run will show.


## C5 and C6 (writer 4; nothing run, no Julia, no daemon)
Commits on wip/cont1 after c0412770: 740719f9 (`push_continuation`, src/pl-cont.jl), b602448c (`I_CALLCONT`, src/pl-wam.jl,
replacing the refusal), 0b732579 (`I_YIELD` non-engine branch, src/pl-wam.jl; `PL_Q_ALLOW_YIELD` declared in src/SWI-Prolog.jl,
its header comment updated; the header comment above the six instructions in pl-wam.jl brought up to date), this file.

### Written
- `push_continuation(gd, ld, continuation, pfr, pcret)` -> `Code{T}` or `nothing`: the term read DEREFERENCED word by word
  (`_deref_loc`); a non-compound, an arity < 3, a context or blob that is no atom, a PC that is no integer, a non-clause blob or
  `arity != variables + 3` gives `PL_type_error(ld, "continuation", continuation)`. Room: `ensureLocalSpace(SIZEOF_LOCALFRAME +
  variables + LOCAL_MARGIN)` (the margin is a representation addition; no `retry`, growing moves nothing). Frame = `pushFrame!(ld,
  ld.lTop)`; slots `_slot_from_cell!`; choice slots (`prolog_vars .. variables-1`): the word `consInt(base)` of the term is kept when
  a choice of the `BFR` chain has exactly that base, else `consInt(choices[BFR].base)`; `setLTop!(argFrameP(base, variables))`;
  `programPointer = pcret`, `parent = pfr`, `setNextFrameFlags`, `clause = ClauseRef{T}(nothing, word(0), cl, nothing)`, `fctx = 0`,
  predicate, context (`[]` -> the predicate's module index; else `setContextModule!(lookupModule(gd, name).index)`),
  `setGenerationFrame`, `environment_frame`. Returns `Code{T}(cl.codes, cl.literals, pcoffset + 1)`. `enterDefinition` is a no-op upstream.
- `I_CALLCONT`: location deref of the operand slot; a `call/1` compound (functor word compared with `_cont_functor(ld, :call, 1)`)
  stores `linkValI` of its argument in `argFrameP(ld.lTop, 0)` and `@goto I_CALL1`; else `pushWordAsTermRef`, `push_continuation(.., FR,
  Code{T}(PCc, PCl, PC))`, then `PCc/PCl/PC`, `FR = ld.environment_frame`, `DEF`, `ARGP`, `next_instruction`; `nothing` -> `b_throw`.
- `I_YIELD`: `ld.queries[QueryFromQid(ld, QID)].flags & PL_Q_ALLOW_YIELD == 0` -> `PL_error(ld, "", 0, "not an engine",
  ERR_PERMISSION_VMI, "I_YIELD")`, `b_throw`; the engine branch throws `NotPortedError` owner TH1. No query carries the flag
  (decision 1), so only the permission error is reachable. `push_continuation_list`: left to TAB1 (tabling only; nothing calls it).

### Unrun / unverified (the gate decides)
(1) `Code{T}(cl.codes, cl.literals, ...)` field names of `clause` (codes, literals, predicate::Definition, variables, prolog_vars)
read from pl-incl.jl; (2) `_atom_value(ld, bw)` of a clause blob word (blobs are in `atom_symbols` through `_blob_term!`; `put_environment`
makes the word with `_atom_word!(ld, cref)`); (3) `lookupModule(gd, mname).index` and `is_nil(mname)` on the `T` symbol; (4) in the tuple
ternaries of `push_continuation` the three `_deref_loc` results are `Tuple{UInt8,word,Int}`; (5) the `call/1` shortcut writes slot
`argFrameP(ld.lTop, 0) + 1` while `lTop` is the position of the callee's frame (as `I_CALL1`'s `pushFrame!(ld, ld.lTop)`); (6) `ld.choices[ld.BFR]`
read with `BFR != 0`; (7) fmt will re-flow the long `if` in `push_continuation` and `I_CALLCONT`; (8) `PL_Q_ALLOW_YIELD` is the first constant
of a left-out flag to be declared: `port_inventory` (gate-regenerated) and any "all declared flags" check may list it.

### The remaining risk: a frame running an ERASED clause (read, not run)
Sites read: `I_EXIT` `exit_continue` (src/pl-wam.jl ~4034) sets `ec_f.clause = nothing` and `lowerLTop!`: the Clause object is not touched, it
stays in `gd.clause_refs` (append-only) and in the closure of the next `ClauseRef`; `cleanDefinition!` (src/pl-proc.jl:602) only UNLINKS erased
clauses ("left to the garbage collector"), nothing frees or empties `codes`; `markPredicatesInEnvironments!` (pl-gc.jl) reads only `fr.predicate`
and the frame generation (set to now by `push_continuation`), not the clause; `walk_and_mark` reads `f.clause.clause`. So the first run must check:
(a) `c_cut`/`b_throw` assert `frame.clause !== nothing || foreign` (pl-wam.jl ~4415): holds, the pushed frame has a ClauseRef;
(b) a continuation of a clause that was RETRACTED between shift and call (`assert`/`retract` a predicate with a `shift` in its body,
resume afterwards): run once, it should run the old body to its end (upstream: the blob keeps the clause alive); (c) clause GC
(`garbage_collect_clauses/0`) while such a frame is live, then `clause_property`/backtrace of the frame (`prolog_frame_attribute(F, clause, C)`
reads `fr.clause`); (d) `ddi_is_garbage` does not know that frame's clause: only the predicate/generation protection exists, which cannot
free a Julia object, so the risk is limited to code that re-finds the clause THROUGH the predicate (decompile of an unlinked clause: a clause_ref
lookup by serial still works through `gd.clause_refs`).

### What C7 and C8 need (unchanged plan, plus)
- C7: flip b2's six `c_*` pin rows (test/core_lang/test_cont_boot_swipl.jl) from swipl 10.1.19 and remove the DIVERGES owner-CONT1 block at
  src/pl-wam.jl ~3267-3273 (the sentence on `I_YIELD` in an engine stays: owner TH1); src/pl-vmi.jl header (~34-37: "the other six are ... refused
  by name when run" is stale: only the engine branch of I_YIELD refuses). Rows to add: `call_continuation` twice resumed (shift_for_copy), a continuation
  with a live `->` choice slot, `type_error(continuation, foo)` (`call_continuation([foo])`; `'$call_continuation'` is reachable as `call_continuation/1`'s
  helper), `'$engine_yield'(a, 256)` outside an engine -> `permission_error(execute, vmi, 'I_YIELD')`.
- C8: tools/mutants/CONT1.py (TARGETS: the cont rows file, test_cont_boot_swipl.jl, every file running reset/shift or call_continuation; candidates for mutants in
  push_continuation: `pcoffset + 1` -> `pcoffset`, the `==` of the choice base, the `>` of the chain walk, `arity != variables + 3`, `is_nil(mname)` branch, `prolog_vars`
  loop bound, the `call/1` shortcut condition, I_YIELD's `== 0`), manifest rows for ALL new pl-cont.jl functions (`findReset`, `env_functor`, `_cont_functor`,
  `_cont_predicate_name`, `put_environment`, `env3_predicate`, `is_last_call`, `put_continuation`, `shift`, `push_continuation`) and pl-gc.jl's `walk_and_mark`,
  `mark_active_environment`, `mark_frame_var`, `clear_frame_var`, `clear_choice_mark`, `mark_choice_mark`; `PL_cons_functor_v`, `PL_cons_list_v`; then the architecture block.
- Gate order after the last commit: as the list above (fmt through `warm.sh send`, inventory, check, rows x3, type discipline, pkgtest_way per changed test file one at a time,
  mutants branch, branch-gate, term grep, alloc pins x3, gate push on a fresh name).


## C7 and C8 (writer 5; nothing run, no Julia, no daemon). Handed back at the 150k cap, C8 NOT STARTED

### Committed (wip/cont1, after 66eae8d6)
- 90b4a758 C7: test/core_lang/test_cont_run_swipl.jl (new; rows over the booted system's reset/3, shift/1, shift_for_copy/1,
  call_continuation/1, engine_yield/1; pins = evidence/CONT1/cr_rows.out from evidence/CONT1/gen_cr_rows.py, which runs swipl 10.1.19 twice
  and asserts byte-identical output); test_cont_boot_swipl.jl: the six c_* rows now compare with `_CB_PINNED` (the kernel refusal pins and
  `_CB_CONT1_KERNEL` are gone, `_CB_CONT1` is (id, goal)); src/pl-wam.jl: owner-CONT1 DIVERGES block replaced by a plain comment
  (the I_YIELD engine sentence, owner TH1, and the TAB1 notes stay); src/pl-vmi.jl header updated.
- a5bcdda2 C7b: eight more rows (meta-call goal under reset, \+, ;, *->, deep cut, late-written slot).
- 8a6bdf9d C7c: rows r_var_goal_ctx, r_meta_len, r_catch_shift, r_catch_len, r_nested_resume, r_ite_copy (43 rows in all, `_CR_CASES`).
- The test file is REGENERATED by a scratch assembler (not committed); to add a row: append `(id, raw"goal")` to `_CR_CASES` (and any program
  clause to `_CR_PROGRAM`), run `python3 -I evidence/CONT1/gen_cr_rows.py test/core_lang/test_cont_run_swipl.jl <scratch dir> > evidence/CONT1/cr_rows.out`,
  then replace the `_CR_PINNED` block by `raw"<line>"` per output line (one per line, first is `ok`).

### Swipl finding for the audit (private register, by SHA only)
One finding on swipl 10.1.19's `call_continuation/1` with a `$cont$` term of arity 1 ends the swipl process; it is recorded in the private
register by SHA and described nowhere in this repo. The kernel's `push_continuation` raises `type_error(continuation, _)` for arity < 3
(deliberate); NO row pins it (the oracle cannot answer).

### LEFT: C8 (own commits, in this order; nothing written yet)
1. tools/mutants/CONT1.py (format: tools/mutants/MOD3b.py: `MUTANTS = [dict(id=, file=, targets=, old=, new=[, equivalent=])]`, header says anchors
   need a re-fit at the first battery run). TARGETS: RUN = ["test/core_lang/test_cont_run_swipl.jl", "test/core_lang/test_cont_boot_swipl.jl"]; add
   test/core_lang/test_metacall_control.jl for the i_metacall_common mutant. Candidates read from the code (every `old` must be checked with
   `grep -c -F` = 1 and `new != old`; validate with a python3 -I + runpy checker in the scratchpad):
   * src/pl-wam.jl: `ld.frames[FR].flags |= FR_INRESET               # setLocal(FR, FR_INRESET)` -> `nothing` (KILL r_meta_len, r_meta_shift);
     `if _slot_is_var(ld, ir_p + 1)                   # if ( isVar(*p) )` -> `if false` (KILL r_var_goal_ctx: call/1's own error has another context);
     `bindConst(ld, ier_p, consInt(Int64(0)))` -> `consInt(Int64(1))` (KILL r_noshift, r_iter, c_reset);
     `if ier_k == DU_CELL || ier_k == DU_ATTVAR       # canBind(*p)` -> `if false` (KILL r_noshift); same with `if ier_k == DU_CELL` (the attvar arm has NO row: list NOT LISTED, reason: needs an attr hook);
     `ld.gstack[valPtr(cc_w)] == _cont_functor(ld, :call, 1)` -> `... :call, 2)` (KILL r_catch_shift, r_nested_resume: the `call(catch(..))` entry);
     `(ld.queries[QueryFromQid(ld, QID)].flags & PL_Q_ALLOW_YIELD) == 0` -> `!= 0` (KILL c_yield, r_yield_out);
     `if ld.lTop < sh_fid                             # the trim of` -> `if false` (KILL every shift row: the close asserts);
     `sh_copy = true                                  # VMH_GOTO(shift_common, true)` -> `false` (NO known row: see below).
   * src/pl-cont.jl: findReset `f.predicate === proc_fl.definition && return (FRESET_FINDALL, 0)` -> `false && ...` (KILL r_shift_findall, r_shift_findall_msg);
     `if f.predicate === reset3 || f.predicate === reset6` -> `if f.predicate === reset3` EQUIVALENT until TAB1 (no tabled frame);
     `rc = PL_unify(ld, argFrameP(f.base, 1), ball)` -> `rc = true` (KILL r_nested); final `return (FRESET_NO_FRAME, 0)` -> `(FRESET_FINDALL, 0)` (KILL r_shift_out_msg);
     put_environment `ld.gstack[p + 2] = consInt(Int64(pc - 1))` -> `pc` (KILL r_iter, r_effect, r_twice); `if (f.predicate::Definition{T}).flags & P_TRANSPARENT == 0` -> `!= 0` (KILL r_ctx);
     `        if active[i + 1]                                        # true_bit(active, i)` -> `if true` (KILL r_slots, `<inactive>`);
     `if !is_last_call(pc)` -> `if true` (KILL r_lco: length 0 expected); `arity != Int(cl.variables) + 3` -> `arity != Int(cl.variables) + 2` (KILL r_type_arity);
     `if is_nil(mname)` -> `if false` (KILL r_ctx, r_effect); `pcoffset + 1)         # cl->codes + pcoffset` -> `pcoffset)`; the choice-slot compare `ld.choices[chp].base == ichp` -> `!=`;
     the chain walk `ld.choices[chp].base > ichp` -> `>=`.
   * src/pl-gc.jl (walker, KILL r_slots / r_or / r_not / r_soft / r_cutdeep / r_late): `state.clear[i] || (state.active[i] = true)` occurs TWICE (mark_frame_var,
     mark_choice_mark): anchor with the neighbouring function line; `elseif op == C_OR` branch `walk_and_mark(state, codes, pc + 2, C_JMP)` -> `pc += 1`-style skip; the C_IFTHEN `+ 1)` skip of C_END.
   * Rows NOT able to kill (declare NOT LISTED / equivalent with reason): the for_copy choice-slot word (`sh_copy`, `ld.gstack[p] = ld.slots[...]` in put_environment): swipl
     answers `[b]` for BOTH shift and shift_for_copy of r_ite_*; the last scratch probe (cr_slot / cr_slotc: `cr_mem(Y), ( shift(k), Z = Y -> true ; Z = none ), X = Z`, then
     `findall(R, (reset(G,_,C), (call(C), R = X ; R = alt)), L)`) was about to be run to find a row where the two differ; add it (and the row) only if swipl's two answers differ.
2. Manifest (own commit): test/static_analysis_manifest.jl entries for ALL new functions of src/pl-cont.jl (`findReset`, `env_functor`, `_cont_functor`, `_cont_predicate_name`,
   `put_environment`, `env3_predicate`, `is_last_call`, `put_continuation`, `shift`, `push_continuation`), src/pl-gc.jl (`walk_and_mark`, `mark_active_environment`,
   `mark_frame_var`, `clear_frame_var`, `clear_choice_mark`, `mark_choice_mark`; `walk_state` is a struct) and src/pl-fli.jl (`PL_cons_functor_v`, `PL_cons_list_v`): copy the shape of a
   neighbour entry first. No `@enum` was added (the manifest `_enum_hash` entry is not needed).
3. docs/architecture.md block, LAST code commit (APPEND only; never regenerate docs/port_inventory.md): the DIVERGES list: lTop (shift uses setLTop!, shift_common raises lTop to
   the foreign base, representation-only), PC stored as pc-1, push_continuation_list left to TAB1, I_YIELD engine branch TH1, the ensureLocalSpace margin, DBG1 (backtrace and clause number
   in the shift_check text), tabled branches of I_RESET/I_EXITRESET TAB1, PL_Q_ALLOW_YIELD declared but no query carries it.
4. Update this file's ready-for-gate list (below) and commit it.

### Ready-for-gate list (to run after C8 is committed; nothing has run)
fmt (committed stack: the `reset --mixed` trick, then `warm.sh send` of the committed files) ; inventory (the gate regenerates docs/port_inventory.md) ; `warm.sh check` (includes the Pkg.test-way run) ;
test files x3 term types: test/core_lang/test_cont_run_swipl.jl, test/core_lang/test_cont_boot_swipl.jl ; test/test_type_discipline.jl ; alloc pins x3 (src/pl-global.jl gained five fields: Tier 1) ;
`tools/pkgtest_way.sh <file>` for each changed test file, ONE at a time ; push `mutants/CONT1` at the WIP SHA once the list exists, then branch-gate, the term grep (D-0164, over the added lines of
`git diff 4e90042a..HEAD` and the messages: writer 6 ran it, no hit; re-run before the push), then `gate/cont1` and `mutants/CONT1` at the SAME SHA on a FRESH name.
NOTE: the stack sits on wip/lb4b2c (b2, NOT landed): it must be re-stacked (cherry-pick onto main in order) after b2 lands; CONT1 cannot land before it. Dependency: the opcode declarations and the compile side live only on b2.
First-run points: the eight listed in the C4/C5/C6 sections above, plus: (a) the new rows assume the booted system defines reset/3 etc. (b2's boot) and `engine_yield/1` exported to user;
(b) `_cr_kernel` keeps all 43 rows in ONE database, a failing row after a refusal returns early: read the first mismatch only; (c) r_shift_out_msg / r_shift_findall_msg read the context message atom;
(d) r_ctx needs `context_module/1` and a module created by `cr_m:` (default import user); (e) the unrun kernel may differ on r_slots (`<inactive>` placement) = a walker finding, trace it to pl-gc.c, do not re-pin.


## C8 (writer 6; nothing run, no Julia, no daemon). C1-C8 are all COMMITTED
Commits on wip/cont1 after dfdb3b60: c19440c7 `tools/mutants/CONT1.py`, 186e6c42 manifest, 55d1ca79 architecture block, this file.

### Written
- **tools/mutants/CONT1.py**: 26 mutants (25 live, 1 equivalent), ids CONT1-R1..R6 (I_RESET / I_EXITRESET / the FR_INRESET branch), V1..V3 (I_CALLCONT shortcut, I_YIELD,
  the lTop raise), S1..S5 (findReset, shift), E1..E6 (put_environment, put_continuation), P1..P3 (push_continuation), W1..W3 (walker). Checked by a python3 -I runpy script
  (every `old` once in its file, `new != old`, ids unique, every target holds @test and @testset): 0 bad. Each KILL names a case line of test_cont_run_swipl.jl (135-177) or
  test_cont_boot_swipl.jl (140-145); they are the rows EXPECTED to kill, read in the row's goal and pin, not run. TARGETS: the two row files; R2 adds test_metacall_control.jl.
  EQUIVALENT: S4 (`reset6` in findReset) until TAB1. NOT LISTED (header, with reasons): the choice-slot restore of push_continuation, the `for_copy` word of put_environment,
  `sh_copy` of I_SHIFTCP and the choice arms of the walker (swipl answers the same for shift and shift_for_copy: t_r_ite_cut = t_r_ite_copy = [b], t_r_twice = t_r_twice_fc), the
  attvar arm of I_EXITRESET, shift's uninstantiation error, a variable written then read after the shift (r_slots writes W before the shift), the C_JMP step / control arms of
  the walker, stack-space failures. A row separating the restore from the newest choice needs a program whose cut after the resume depends on an older choice still standing:
  not found; add a row (and the mutants E7 `==` -> `!=`, E8 `>` -> `>=`) only if swipl's two answers differ.
- **Manifest** (test/static_analysis_manifest.jl): `_manifest_cont(T)` (19 entries incl. the `walk_state` constructor), spliced at the end of `_DISPATCH_MANIFEST_TUPLE` for DefaultTerm.
  The four walker leaves and `is_last_call` are marked allocation-free, the others allocating: the gate (`check`, alloc pins) decides; flip a flag if it says so.
- **docs/architecture.md**: the CONT1 block (the DIVERGES list; tests and mutants named). docs/port_inventory.md is untouched (the gate regenerates it).

### Housekeeping
- The worktree held an UNCOMMITTED, quote-stripped partial regeneration of test/core_lang/test_cont_run_swipl.jl (a scratch assembler's output: the doc comment lost its backticks,
  `_CR_PINNED` held only `ok`, the last two testsets cut); it blocked the commit hook ("unstaged changes"), so it was restored from HEAD after saving a copy
  (the dispatcher's scratchpad of writer 6, test_cont_run_swipl.jl.uncommitted-corrupt). HEAD's file (43 rows, full pins) is the committed truth.

### Ready for the gate (the list above stands), adding
alloc pins x3 (src/pl-global.jl +5 fields, Tier 1; src/pl-gc.jl and the new pl-cont.jl are on the call path); the fmt `reset --mixed` trick (committed stack: `git reset --mixed 4e90042a`, `warm.sh fmt`,
re-commit per group, or `warm.sh send` of the committed files); `mutants/CONT1` pushed at the WIP SHA once fmt is done (anchors re-fit at the first battery run: the formatter may re-flow
`if active[i + 1]   ` and `state.clear[i] || (state.active[i] = true)  # if`); the b2 dependency: the stack sits on wip/lb4b2c, re-stack (cherry-pick onto main, in order) after LB4 b2 lands.
Term grep (D-0164): writer 6 ran it over the added lines of the stack and the messages: no hit once this file is committed; re-run before the push.
