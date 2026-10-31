# LB3 handoff — src/pl-qlf.jl, the C boot loop (edit-only, coder 1, R2 sprint; D-0272/D-0273)

Worktree ~/code/lk-lb3, branch `wip/lb3` off origin/main bf41225 (NEVER pushed by the coder). Reference: swipl-devel
cbf4e1896275 (src/pl-qlf.c, src/os/pl-file.c, src/pl-init.c, boot/init.pl). Design: evidence/r2/design/loader_boot.md
§2.2-2.3, §2.7, LD2, LD3, §6 (LB3 mutants), §7 row LB3. NOTHING IS COMPILED OR RUN (no Julia in this step).

## Plan (written first)

| group | what (upstream file:line @ cbf4e189) | Julia site |
|---|---|---|
| G1 | `push_input_context` / `pop_input_context` (os/pl-file.c:1584-1619), `pl_see` / `pl_seen` (os/pl-file.c:4447-4501); LD fields `input_context_stack` (pl-global.h `input_context_stack`) and `qlf_write_state` (`LD->qlf.write_state`) | src/os/pl-file.jl, src/pl-global.jl |
| G2 | `directiveClause` (pl-qlf.c:4583-4608), `iftrue`, `MAX_IFDEF_NEST`, `condc`, `cond_true`, `update_conditional_compilation` (:4611-4689) | src/pl-qlf.jl (new) |
| G3 | `compileFile` (:4696-4780), `addClauseWic` (:3222-3238), `addDirectiveWic` (:3242-3250), `qlfStartFile` (:4070), `qlfEndPart` (:4082) | src/pl-qlf.jl |
| G4 | `compileFileList` (:4784-4820) minus `writeWicHeader`/`writeWicTrailer`; the boot entry (pl-init.c:1614-1647, the `bootsession` branch) | src/pl-qlf.jl |
| G5 | the 7 write-side shells (:4098, 4116, 4134, 4167, 4222, 4481, 4537), the 15 others refused by name, `BeginPredDefs(wic)` (:4953-4976); registered after `read`, before `file` (pl-ext.c:518-522); include after pl-read.jl | src/pl-qlf.jl, src/pl-ext.jl, src/LogicKernel.jl |
| G6 | fixture files + white-box rows (`_ql_` prefix) | test/fixtures/qlf/*.pl, test/test_qlf_rows.jl |
| G7 | tools/mutants/LB3.py (>= 20, TARGETS per D-0238) | tools/mutants/LB3.py |
| G8 | docs/architecture.md LB3 section (LAST but one) | docs/architecture.md |
| G9 | static_analysis_manifest `_enum_hash` entry for `iftrue` (LAST) | test/static_analysis_manifest.jl |

Commit estimate for the gated stack: 15-20 (9 WIP commits from the coder; the gate adds fmt/fix commits).

## UPDATE 1 (coder 1, cap-stopped at 150k by the hook; nothing compiled)

- COMMITTED on wip/lb3 (~/code/lk-lb3, NOT pushed): G1 `502ffff` (pl-file.jl push/pop_input_context, pl_see,
  pl_seen; pl-global.jl `input_context` struct + LD fields `input_context_stack`, `qlf_write_state::Nothing`),
  G2 `8a1079b` (new src/pl-qlf.jl: directiveClause, iftrue, MAX_IFDEF_NEST, condc, cond_true,
  update_conditional_compilation).
- G3 WRITTEN AND STAGED, NOT COMMITTED (the cap hook blocked the commit): src/pl-qlf.jl gained `_qlf_Sdprintf!`,
  qlfStartFile, qlfEndPart, addDirectiveWic, addClauseWic, `_qlf_source_file_text`, compileFile. NEXT AGENT: first
  `git -C ~/code/lk-lb3 diff --cached --stat`, then commit it with subject
  `UPSTREAM: pl-qlf.c compileFile/addClauseWic/addDirectiveWic/qlfStartFile/qlfEndPart (swipl-devel cbf4e189)`
  (the commit hook requires `UPSTREAM: <file> <functions> (swipl-devel <sha>)`).
- LEFT: G4 compileFileList + boot entry; G5 the 7 shells, the 15 refusals, `PL_predicates_from_wic` (registered
  between `read` and `file` in BOTH `_PRED_TABLES` and `_FOREIGN_VA`, pl-ext.c:518-522), `include("pl-qlf.jl")`
  after pl-read.jl in src/LogicKernel.jl; G6-G9 as planned.

### Findings the next agent need not re-read (all cbf4e189)
- compileFileList (pl-qlf.c:4784-4820): `alevel = setAccessLevel(SYSTEM)`; `PL_set_prolog_flag("autoload", PL_BOOL,
  false)`; write_state = state; compileFile per argv until `"-c"` (false → return false); autoload true;
  `setAccessLevel(alevel)`; `PL_call_predicate(MODULE_user, true /*=PL_Q_DEBUG*/, user:'$load_additional_boot_files'/0, 0)`.
  The kernel has no `set_prolog_flag` (F1b): use `setPrologFlag(gd, "autoload", FT_ATOM, "false")` (flag is FT_ATOM,
  pl-prologflag.jl:821) with a DIVERGES. `setAccessLevel!(ld, level)` returns nothing: read
  `ld.prolog_flag_access_level` first. Procedure: `lookupProcedure(mk_sym(T, Symbol("\$load_additional_boot_files")), 0,
  MODULE_user(gd))`; `PL_call_predicate(gd, ld, ctx::module_t, flags, pred, h0)` (pl-fli.jl:1294).
- Boot entry (pl-init.c:1614-1666, LD3): setAccessLevel(SYSTEM); `gd.bootsession = true`; compileFileList; bootsession
  false; `ld.debugstatus_styleCheck = SINGLETON_CHECK|SEMSINGLETON_CHECK|DISCONTIGUOUS_STYLE|NOEFFECT_CHECK`;
  setAccessLevel(USER). ORIGINAL name (e.g. `boot_from_source!`): pl-init.c has no function of its own for it.
  A FIXTURE must define `'$load_additional_boot_files'/0` (init.pl:4782 does), or the call raises existence_error.
- The 7 shells (PRED_DEF flags 0 → `PL_FA_VARARGS`; `$add_directive_wic` `PL_FA_TRANSPARENT|PL_FA_VARARGS`):
  `$qlf_start_module`/1, `$qlf_start_sub_module`/1, `$qlf_start_file`/1, `$qlf_end_part`/0, `$add_directive_wic`/1:
  NULL state → succeed, no argument check. `$qlf_assert_clause`/2 → true. **`$qlf_include`/5 FAILS with NULL state**
  after `PL_get_atom_ex` A1, A2, `PL_get_integer_ex` A3, `PL_get_atom_ex` A4, `PL_get_float` A5 (non-ex) (:4174-4197).
- The 15 refused: `$qlf_versions`/6, `$qlf_is_compatible`/1, `$qlf_sources`/2, `$file_hash`/2, `$qlf_module`/2,
  `$qlf_load`/2 (TRANSPARENT), `$qlf_current_source`/1, `$qlf_dependency`/1, `$qlf_open`/1, `$qlf_close`/0,
  `$open_wic`/2, `$close_wic`/0, `$map_id`/2, `$unmap_id`/1, `$import_wic`/3; table order :4953-4976.
  `NotPortedError{T}(culprit, what, step)` (pl-comp.jl:796).

### FLAGS for the audit
- **Q1 (behaviour, LB4):** `'$import_wic'/3` has a NULL branch that SUCCEEDS (:4512-4530) and init.pl calls it in wic
  mode through `'$ifcompiling'` (init.pl:3794, `'$import_all2'`). Refusing it (the brief's 15) raises in LB4's boot on the
  first import. Options: (a) refuse now, promote to an 8th shell in LB4; (b) make it a shell in LB3 now (upstream as is).
  Rec. (b).
- **Q2 (behaviour, LB4):** `'$qlf_include'/5` fails with NULL state; upstream's boot has a state open, so init.pl's
  `'$record_included'` (init.pl:2090) succeeds there and would FAIL in the kernel's boot on an `include/1` in wic
  mode. Ported as is; LB4 checks whether a boot file includes.
- **Q3:** `fatalError` in update_conditional_compilation is a Julia `error` (ends the boot by an exception).
- **Q4:** compileFile's syntax-error `continue` / eof `break` leave a foreign frame open, as upstream; an
  `addClauseWic` failure leaves assert_term's exception pending, as upstream. H11 (LB4) checks the stacks after boot.
- **Q5:** AbsoluteFile/LastModifiedFile are Julia's abspath/stat (re-point when LB2b ports pl-os.c);
  `findStreamFromFile` and the `IO_SEE` context flag are not kept (see/1 unregistered: no stream can carry it).
- **Q6:** the LD struct changed (pl-global.jl): alloc pins x3 at the gate.
