# MOD3b handoff (Opus coding agent 1, 2026-10-31 UTC): EDIT-ONLY; NO CODE WRITTEN YET (forced hand-back at the context cap)

Worktree ~/code/lk-mod3b, branch wip/mod3b off origin/main 9952080. Nothing compiled, no Julia, no daemon, no swipl run yet.
The cap hook (cap-subagent-context.sh, "~153k") blocked further work while I was still reading; this file is the whole
result: the upstream extracts and the exact edit plan, so the next agent can write the code straight away without re-reading
upstream. Upstream pin cbf4e1896275 (`git -C ~/dev-zone/swipl-devel show cbf4e1896275:src/<f>`; the checkout's HEAD is
bae881a, so ALWAYS read at the pin: line numbers below are the pin's).

## Upstream extracts (pin cbf4e189)
- pl-vmi.c:2113-2123 `VMI(I_DEPARTATM, VIF_BREAK, 3, (CA1_MODULE, CA1_MODULE, CA1_PROC))`: `PC++; /* Ignore :-qualifier */ VMI_GOTO(I_DEPARTM);`
- pl-vmi.c:5331-5341 `VMI(I_CALLATM, VIF_BREAK, 3, (CA1_MODULE, CA1_MODULE, CA1_PROC))`: `PC++; VMI_GOTO(I_CALLM);`
  ("The procedure-module is provided to support the decompiler.")
- pl-vmi.c:5343-5370 `VMI(I_DEPARTATMV, VIF_BREAK, 3, (CA1_MODULE, CA1_VAR, CA1_PROC))`:
  `if (BFR > FR || !truePrologFlag(PLFLAG_LASTCALL)) VMI_GOTO(I_CALLATMV); else { PC++; iv = (int)*PC++; ap = varFrameP(FR, iv);
  deRef(ap); if (isTextAtom(*ap)) { m = lookupModule(word2atom(*ap)); setContextModule(FR, m); VMI_GOTO(I_DEPART); } else
  { PL_error(NULL,0,NULL, ERR_TYPE, ATOM_module, pushWordAsTermRef(ap)); popTermRef(); THROW_EXCEPTION; } }`
- pl-vmi.c:5376-5400 `VMI(I_CALLATMV, VIF_BREAK, 3, (CA1_MODULE, CA1_VAR, CA1_PROC))`: `PC++; iv = (int)*PC++; proc = *PC++;
  ap = varFrameP(FR, iv); deRef(ap); if (isTextAtom(*ap)) { module = lookupModule(...); DEF = proc->definition; NFR = lTop;
  VMH_GOTO(mcall_cont, module); } else { same type_error; THROW_EXCEPTION; }`
- pl-vmi.c:5540-5542 (i_metacall_common, the CONTROL_F branch, before `lTop = NFR; setNextFrameFlags; compileClause`):
  `if ( fd->functor == FUNCTOR_at_sign2 && !checkCallAtContextInstantiation(a) ) THROW_EXCEPTION;`
- pl-wam.c:1850-1889 `checkCallAtContextInstantiation(Word p)`: deRef(p); `m = argTermP(*p,1)`, deRef, `canBind(*m)` →
  ERR_INSTANTIATION; `g = argTermP(*p,0)`, deRef, `g = stripModuleName(g, &pm)` (false → return false); if `hasFunctor(*g,
  FUNCTOR_colon2)`: its arg 0 deRef'd, canBind → ERR_INSTANTIATION; `g = argTermP(*g,1)`, deRef; `canBind(*g)` →
  ERR_INSTANTIATION; return true.
- pl-wam.c:1135-1162 put_vm_call's I_CALLATM*/I_DEPARTATM* cases: the debugger's (not ported, as MOD3a's I_CALLM case).
- pl-comp.c:412-414 `target_module at_context;` (after colon_context); :2048-2050 `ci->at_context.type = TM_NONE;`
- pl-comp.c:2434 `CB_ATSIGN /* (G@M): restore at_context */` (after CB_COLON in the enum).
- pl-comp.c:2635-2653 compileBody's `@` branch, right after the colon branch: `atsave = ci->at_context; if ((rc=getTargetModule(
  &ci->at_context, argTermP(*body, 1), ci)) != true) goto resume; frame.kind = CB_ATSIGN; frame.tmsave = atsave; push; body =
  argTermP(*body, 0); goto next_body;` then `assert(0)` (every CONTROL_F functor is handled after it).
- pl-comp.c:2668-2671 the error unwind: `else if (frame.kind == CB_ATSIGN) ci->at_context = frame.tmsave;`
- pl-comp.c:2837-2840 resume: `case CB_ATSIGN: ci->at_context = frame.tmsave; goto resume;`
- pl-comp.c:3352-3378 `callatm(call)`: I_CALL→I_CALLATM, I_DEPART→I_DEPARTATM, else assert(0); `callatmv(call)` → I_CALLATMV/I_DEPARTATMV.
- pl-comp.c:3444-3465 compileSubClause's metacall label: `if (at_context.type != TM_NONE) Output_1(ci, B_FUNCTOR, FUNCTOR_at_sign2);`
  BEFORE the colon block; AFTER it (before `I_CALL1`): `if (at_context.type != TM_NONE) { pushTargetModule(&ci->at_context, ci);
  Output_0(ci, B_POP); }`.
- pl-comp.c:3594-3598 the call/N gate: `colon_context.type == TM_NONE && at_context.type == TM_NONE`.
- pl-comp.c:3608-3628 the call selection, BEFORE the I_CALL/I_CALLM block: `tm` as now; `proc = lookupBodyProcedure(functor, tm)`;
  `if (at_context.type != TM_NONE) { ctm = (tm==ci->module) ? 0 : ptr2code(tm); if TM_MODULE: Output_3(ci, callatm(call), ctm,
  ptr2code(cm), proc) else Output_3(ci, callatmv(call), ctm, VAROFFSET(at_context.var_index), proc) } else {MOD3a's block}`
  — NO lco() on the at path. Note the `colon_context.type == TM_VAR → goto metacall` test (3574) stays colon-only.
- pl-comp.c:6801-6840 decompileBody: I_DEPARTATMV/I_CALLATMV: `pm = *PC++; cm = *PC++ (a var offset); proc = *PC++;
  BUILD_TERM(proc functor); if (pm) { swap; ARGP[-2] = pm->name; BUILD_TERM(FUNCTOR_colon2); } if (nested) unifyVar(ARGP++,
  di->variables, cm) else *ARGP++ = makeVarRef(cm); BUILD_TERM(FUNCTOR_at_sign2); pushed++;` — I_DEPARTATM/I_CALLATM the same with
  `*ARGP++ = cm->name` for the module.

## Kernel sites (main 9952080) and the edit for each
- src/pl-vmi.jl: header lines 23-34 (append "then MOD3b's `Goal@Module` calls (`I_DEPARTATM`, `I_CALLATM`, `I_DEPARTATMV`,
  `I_CALLATMV`, in pl-vmi.c's order)"; drop them from the "NOT EMITTED" list at :35); new consts after `S_LMQUAL = code(152)` (:578):
  `I_DEPARTATM = code(153)`, `I_CALLATM = 154`, `I_DEPARTATMV = 155`, `I_CALLATMV = 156` (pl-vmi.c order: DEPARTATM at 2118 comes
  before CALLATM 5337, DEPARTATMV 5343, CALLATMV 5376), each `# PORT: pl-vmi.c <NAME>` + docstring; code_info rows after :748:
  `(:I_DEPARTATM, VIF_BREAK, 3, (CA1_MODULE, CA1_MODULE, CA1_PROC, 0x00))`, `(:I_CALLATM, …same)`, `(:I_DEPARTATMV, VIF_BREAK, 3,
  (CA1_MODULE, CA1_VAR, CA1_PROC, 0x00))`, `(:I_CALLATMV, …same)`. Extend the OPERANDS paragraph: the procedure-module operand is the
  module index or 0 ("same module", as upstream's NULL); the procedure operand of the four keeps `CA1_PROC` (the clause's table).
- src/pl-comp.jl:
  * :279 drop "`at_context` (`Goal@Module`: MOD3b)" from the not-ported list; add field `at_context::target_module  # Call@Context (MOD3b)`
    after `colon_context` (:322) — a STRUCT CHANGE (daemon restarts); constructor :339 gets a second `TARGET_MODULE_NONE,  # ci->at_context.type = TM_NONE (c:2049)`.
  * getTargetModule! (:343-403): upstream writes through `tm`; give it a trailing `at::Bool=false` argument and write
    `at ? (ci.at_context = x) : (ci.colon_context = x)` at :384 and :391 (update the DIVERGES at :361-362: "into `ci.colon_context`,
    or `ci.at_context` with `at`"). MOD3a's call at :2835 stays as is.
  * compileSubClause! (:2352-2510): comment :2367 → describe the at context; :2473 `is_call && ci.colon_context.type == TM_NONE &&
    ci.at_context.type == TM_NONE`; after `proc = lookupBodyProcedure(...)` (:2487) insert the at branch (Output_3! — check it exists in
    pl-comp.jl, else `Output_2!` + `Output_0!`-style helpers; ctm = `tm === ci.module_ ? code(0) : code(tm.index)`, cm = `code(gd.modules
    index)` i.e. `code(ci.at_context.module_)`, the var operand `VAROFFSET(ci.at_context.var_index)`, proc `addProcedure!(ci, proc)`),
    wrapping MOD3a's `if tm === ci.module_ … end` in its `else`; metacall label :2499: `B_FUNCTOR` of `@/2` first (a twin of
    `_colon_functor_operand`: generalise it to `_control_functor_operand(ci, name)` or add `_at_functor_operand(ci)` with
    `mk_sym(T, Symbol("@"))`, ORIGINAL, same comment form), and `pushTargetModule!(ci, ci.at_context); Output_0!(ci, B_POP)` before `I_CALL1`.
  * new `callatm(call)`, `callatmv(call)` after `mcall` (:2512-2519), same shape (`# PORT: pl-comp.c callatm`).
  * cb_kind :2631: add `CB_ATSIGN  # (G@M): restore at_context (MOD3b)` — the `_enum_hash` manifest entry in
    test/static_analysis_manifest.jl must be updated (cb_kind's entry exists; the member count/hash changes). cb_frame.tmsave comment :2652:
    "CB_COLON/CB_ATSIGN: the saved colon/at context".
  * compileBody! :2848-2854: replace the NotPortedError ("MOD3b (Goal@Module)") by the `@` branch: `if _has_functor(body, cf.at_sign, 2)`
    (cf.at_sign exists, src/pl-funct.jl:391) — `atsave = ci.at_context; getTargetModule!(gd, ld, ci, child(body, 3), true) || (rc =
    BOOLEX_FALSE; @goto resume)` (NB `@` is Goal@Module: the MODULE is child 3, the GOAL child 2 — the reverse of `:`), push
    `cb_frame{T}(CB_ATSIGN, call, body, body, 0, 0, 0, nothing, ci.cut, true, true, atsave)`, `body = child(body, 2)`, `@goto next_body`;
    then `@assert false` for upstream's `assert(0)` (every CONTROL_F functor now handled) — or keep a throw; decide and note it.
  * the unwind :2863: `uframe.kind == CB_ATSIGN && (ci.at_context = uframe.tmsave)`; resume :2944: an `elseif frame.kind == CB_ATSIGN`
    branch (c:2837-2840).
  * decompileBodyNoShift! (:4775-4790 comment drops "and `Goal@Module` (MOD3b)"; cases after the I_CALLM one :4940-4950): pm =
    `Int(codes[di.pc])`, cm, proc = `di.clause.procedures[codes[di.pc + 2]].definition`, `di.pc += 3`; `build_term!(di, def.name,
    def.arity)`; if pm != 0 swap in the module atom and `build_term!(di, mk_sym(T, :(:)), 2)` exactly as the I_CALLM case; then for
    ATMV `_dvar!(di, nested, cm)` (pl-comp.jl:4721 is upstream's nested/makeVarRef pair already), for ATM `push!(di.argp,
    _atom_word!(ld, modules[cm].atom))`; `build_term!(di, mk_sym(T, Symbol("@")), 2)`; `pushed += 1`.
- src/pl-wam.jl:
  * label tuple :1793: add `:I_DEPARTATM, :I_CALLATM, :I_DEPARTATMV, :I_CALLATMV`.
  * after I_DEPARTM (:3326-3333): `@label I_DEPARTATM; PC += 1; @goto I_DEPARTM` (comment quotes c:2118-2121).
  * I_DEPARTATMV, I_CALLATM, I_CALLATMV before I_CALLM (:3501): I_CALLATM `PC += 1; @goto I_CALLM`. I_DEPARTATMV: the I_DEPARTM test
    (:3327-3328) → `@goto I_CALLATMV`; else `PC += 1; iv = Int(PCc[PC]); PC += 1; k, w, _ = _deref_loc(ld, -(varFrameP(ld.frames[FR].base,
    iv) + 1))`; text atom (`k == DU_WORD && isAtomW(w) && isTextAtom(_atom_value(ld, w))`) → `setContextModule!(ld.frames[FR],
    lookupModule(gd, _atom_value(ld, w)).index); @goto I_DEPART`; else the error as call_type_error does it (:3542-3552:
    SAVE_REGISTERS, PL_open_foreign_frame, `t = new_term_ref(ld)`, `_slot_copy!(ld, t + 1, varFrameP(ld.frames[FR].base, iv) + 1)`,
    `PL_error(ld, ERR_TYPE, mk_sym(T, :module), t)`, close, LOAD_REGISTERS, `@goto b_throw`) — share ONE helper label for both ATMV
    instructions (e.g. `@label callatmv_type_error`, ORIGINAL helper label, as i_metacall_clause is). I_CALLATMV: `PC += 1; iv; proc =
    _call_procedure(ld, FR, PCc[PC + 1])`, `PC += 2`; text atom → `mc_mi = module index; DEF = proc.definition; NFR = pushFrame!(ld,
    ld.lTop); @goto mcall_cont`; else the error label. An unbound M → PL_error's ERR_TYPE rule makes instantiation_error (MOD3a F4) — as swipl.
  * i_metacall_clause :3412-3442: REPLACE the NotPortedError block ("call/1 of Goal@Module", the cyclic culprit code) by
    `if mc_arity == 2 && sym_key(mc_name) == gd.functors_control.at_sign && !checkCallAtContextInstantiation(ld, mc_gloc)` →
    `@goto b_throw` (as `mc_cl === nothing` does; wrap in SAVE/LOAD_REGISTERS + a foreign frame if PL_error needs one, as
    I_CALLCLEANUP :3620-3625 does). Update the i_metacall_common comment :3363 ("NOT PORTED: `Goal@Module` (refused by name, R2)").
  * new function `checkCallAtContextInstantiation(ld, p)` near contextModule (:1816-1850), on LOCATIONS: `_deref_loc`, `canBind` =
    `k == DU_CELL || k == DU_ATTVAR`, `stripModuleName_cells(ld, valPtr(w) + 1)` (src/pl-modul.jl:275; returns (ok, (k,w,p), name)),
    the colon test as stripModuleName_cells:282 does it (`_is_gcompound(w) && ld.gstack[valPtr(w)] == colon2`), args at `valPtr(w)+1/+2`.
    `PL_error(ld, ERR_INSTANTIATION)` returns false (src/pl-error.jl:214).
  * The boot clause `@(Goal,Module) :- @(Goal,Module).` is NOT added (L6, init.pl).
- tests (all still to write):
  * test/core_lang/test_metacall_control.jl:360-385: the testset "what stays refused, by name" flips: `c(p(X)@user)` → swipl's answers
    (expected X = 1 ; 2 ; 3 — RUN swipl to confirm, pin with the swipl answer in a comment); the cyclic case `G = p(G), c(G@user)`: ask
    swipl (it should fail: p/1 has only 1,2,3) and pin; drop the NotPortedError/culprit assertions.
  * test/compile/test_body_code_swipl.jl:3019-3026: `_bf("@", _bs("g"), _bs("m"))` leaves the refusal list (it compiles to i_callatm /
    i_departatm now); add a "Goal@Module in a body compiles as swipl's (MOD3b)" testset like MOD3a's (its `_bc_op` renders CA1_MODULE as
    `M:<codes>`; the procedure-module operand 0 needs a rendering matching swipl's `vm_list` — check MOD3a's bc_op/4 on swipl's side).
  * NEW test/core_lang/test_at_body_swipl.jl in test_colon_body_swipl.jl's exact shape (prefix `_AB`, its own pins from swipl via the same
    driver; MOD3a's gen_rows.py / mod3a_driver.pl in ~/code/lk-channel/evidence/MOD3a/ are the generator pattern — put this step's into
    ~/code/lk-mod3b/evidence/MOD3b/). Rows (test_qcall.pl's at/vat/atv/atvv/atvvv — read them at the pin, tests/core_lang/test_qcall.pl):
    `qm(C)@qm2`-style I_CALLATM/I_DEPARTATM (with and without LCO: a `, true` after it), `qm:qm(C)@M` (pm != 0), `G@M` var goal (metacall
    with B_FUNCTOR @/2), `M` variable (I_CALLATMV/I_DEPARTATMV incl. a choice point before the last call), the errors (M unbound at run
    time → instantiation_error; M = 1 → type_error(module,1); `_` first-var at compile → instantiation_error), clause/2 of each (H7:
    swipl prints `qm(_)@qm2`, `qm:qm(_)@M`), and call/1 of `G@M` with M unbound / G unbound / `M2:G` with M2 unbound
    (checkCallAtContextInstantiation's three errors). Whether the kernel's loader takes `Goal@M` bodies in a FILE is unverified (MOD3a's
    first-compile risk list).
- static analysis: test/static_analysis_body.jl's call-path label list (+4 labels), test/static_analysis_manifest.jl (callatm, callatmv,
  checkCallAtContextInstantiation, any helper; cb_kind `_enum_hash`). H11: `lookupModule` in I_CALLATMV/I_DEPARTATMV can allocate (a new
  module): the AllocCheck exemption decision is the gate's.
- tools/mutants/MOD3b.py (to write, MOD3a.py's format): I_CALLATM skip (PC += 1 → 0), I_DEPARTATM skip, I_DEPARTATMV's LCO test, its
  setContextModule!, I_CALLATMV's text-atom test, checkCallAtContextInstantiation's three canBind tests, compileBody's `@` child order,
  the CB_ATSIGN restore, callatm/callatmv selection, ctm 0-vs-module, the metacall's `@` wrapper, the call/N gate's at test, decompiler
  pm/cm. TARGETS (D-0238): test_at_body_swipl, test_colon_body_swipl, test_body_code_swipl, test_metacall_control, test_context_module_swipl,
  test_clause_swipl, test_retract_swipl, test_ssu_compile_swipl, test_cleanup/catch/findall_swipl, test_query.
- docs/architecture.md: a MOD3b section beside MOD3a's.

## Not done (everything): no source edit, no test row, no swipl run, no mutant file. Flags: none raised yet (no DIVERGES added).
## Gate order for the agent after the coder: fmt, check (incl. Pkg.test-way), the new/changed test files x3 term types via the daemon,
test/test_type_discipline.jl, mutants/MOD3b early at the WIP SHA, branch-gate, JET (the static-analysis file alone), alloc pins x3
(the run loop gains 4 labels), crash-term grep over diff + messages, gate/mod3b + mutants/MOD3b at the same SHA.
