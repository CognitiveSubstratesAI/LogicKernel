# LB4 chunk (b2) — the atomic boot: handoff (writer: Opus, allow-opus D-0354; edit-only until the smoke run)

Worktree ~/code/lk-lb4b2, branch wip/lb4b2. Base: main 9e0a983 + the 12 commits of wip/lb4b1 CHERRY-PICKED (b1's
gd_template.jl / boot_image.jl are what b2 edits; one conflict in docs/architecture.md, both appended blocks kept). At the
landing those copies drop out of the rebase once b1 is on main (identical patches). Nothing pushed. Upstream = pin tree
~/dev-zone/swipl-devel-cbf4e189 (cbf4e1896275, 10.1.19), never the 10.1.16 working tree (D-0354 item 5).

## Rulings carried (D-0353, D-0354)
1. THREADS: the kernel boots with `threads` false, upstream's own single-thread build (pl-prologflag.c:2620-2622,
   CMakeLists.txt:92; read-only false at src/os/pl-prologflag.jl:1722; boot/threads.pl at the pin is an empty module). A
   RECORDED DIVERGES against the threads=true oracle: every oracle row about init.pl:2557, 2720, 2735, 2754-2785, 982 and
   toplevel.pl:560 (`$mt_load_file`, with_mutex, message queues, thread_statistics) is PINNED as DIVERGES with the upstream
   line, never skipped. TH1 (pl-thread.c/pl-mutex.c) stays after R2 and flips the flag. Shivaji may overrule D-0354 item 3.
2. `$memberchk/3`, `$inc_message_count/1`, `$notrace/2`+`$restore_trace/2`, `prolog_listen/2`, `variant_sha1/2`: written by
   the BOOTPRED writer (wip/bootpred3, ~/code/lk-dstack). NOT written here; they land via BOOTPRED.
3. Gate prerequisites ON MAIN before b2 gates: BOOTPRED `$style_check/2`, F2, PR1, LB2b, LB4 b1 (its gate adds
   `IO_output_stack` as `:streams` in GD_COPY_POLICY). The first boot run uses a LOCAL merge of the wip branches (run only);
   the fix commits sit on top of what will land.
4. D-0286: `load_file!` returns `(status, ball)`, the old shape removed at once (no shim), a release-notes entry in the SAME
   commit; messages through the message_hook path (LQ7). LQ2 (a): boot once per process and type, copy the template; no
   `bare` constructor now (D-0286 item 3), and a bare one never defines the stand-ins. LQ3/D-0286 item 5: tabling.pl's
   directives raise at boot; the EXACT pinned error list, each a KNOWN DIFFERENCE row with swipl's behaviour; only shrinks.

## Plan (ordered groups; upstream file:line -> Julia site; commit estimate 16-18 + discovery fixes)
G0 this plan (1).
G1 b2-1 the booted constructor (1-2). Upstream: pl-init.c PL_initialise boot branch (:1614-1666, LB3's `boot_from_source!`,
   src/pl-qlf.jl:323-347) over argv = [HOME/boot/init.pl] as src/CMakeLists.txt:357-361 runs it
   (`swipl --home=HOME -q -O -o boot.prc -b HOME/boot/init.pl`). Sites: src/pl-global.jl:118 the body of `PL_global_data{T}()`
   becomes `setupProlog(T)` (pl-setup.c setupProlog: the flag table :136, built-ins :158, operators :164 it already cites);
   a new `boot_global_data(T)` (pl-init.c) = setupProlog + a fresh LD + `boot_from_source!` + the H11 check (the LD's stacks
   are empty again: `emptyStacks!` state, src/pl-setup.jl:140); `PL_global_data{T}()` = `PL_global_data_from_template(T)`;
   src/gd_template.jl:107 the one-argument `gd_template(T)` builds with `boot_global_data` (was the unbooted constructor:
   would recurse). `-O`: the boot sets `optimise` true (pl-init.c `-O`); see flag F3.
G2 b2-2 delete the stand-ins, 3 commits (LD8, H2): src/pl-ext.jl `_boot_catch3!`, `_boot_cleanup!`, `_boot_meta!`,
   `_boot_lists!` (init.pl set) | `_boot_syspred!`, `_boot_bags!`, `_boot_bagof!` | `_boot_attvar!`, `_boot_call_residue_vars!`,
   `_boot_when!`, `_boot_freeze_uhook!`, `_boot_freeze!` + helpers (`_boot_clause!`, `_boot_term`, `_boot_conj`, `_boot_ite`,
   `_boot_cons`, `_boot_vars`, `_boot_length_error`); their static_analysis_manifest entries; the test files naming them.
G3 b2-3 delete boot/init.jl (src/LogicKernel.jl:85 include); `load_file!(gd, ld, path)` = `load_files(Path, [])` in `user`
   through the query API (LD7), returns `(status, ball)`; messages via a `message_hook/3` collector (LQ7); README + the
   release-notes entry in the same commit (2-3).
G4 b2-4 `ld.variable_names` removed (Q5; init.pl:1948-1949 `b_setval('$variable_names', ...)` via G1's pl-gvar.jl): pl-comp.jl,
   pl-read.jl, pl-atom.jl, pl-write.jl, pl-global.jl, SWI-Prolog.jl (28 sites at 8ba3fae; recount at the edit) (1-2).
   STRUCT CHANGE in PL_local_data: alloc pins x3.
G5 b2-5 re-point the test files calling `load_file!` (about 40 call sites in ~16 files; each former refusal row now loads,
   against swipl) (2).
G6 b2-6 new gate files (4): T1 boot image (boot_image_predicates vs the oracle), T2 clauses `=@=`, T3 source files, T4 the
   EXACT boot-message list (H1, LD12 pinned), H12 no attvar left in booted clauses. Threads rows pinned DIVERGES (ruling 1).
G7 tools/mutants/LB4B2.py (>= 28; TARGETS = every test file that boots: all that construct a database, D-0238) (1).
G8 docs/architecture.md block, manifest entries (LAST, own commits) (2).
G9 b2-7 boot-discovery fixes from the smoke run on the local merge (3-4, unknown).

## State (writer 2, 2026-11-02 15:50Z; handed back at ~90k context at a clean commit boundary)
COMMITTED on wip/lb4b2 (writer 1): 12 cherry-picked b1 commits (..87d0db0); 612914e G0 plan; 18eb1c3 G1 (b2-1: setupProlog,
boot_global_data, gd_template's default build); 62133f4 handoff.
COMMITTED (writer 2), all EDIT-ONLY, NOTHING RUN (no daemon slot: three warm daemons up, 13.5 GB available at 15:48Z):
- b43f705 G2 family 1: `_boot_catch3!` `_boot_cleanup!` `_boot_control!` `_boot_lists!` `_boot_meta!` `_boot_length_error`
  deleted with their initBuildIns! calls; 6 manifest entries; comments naming them in 7 test files + pl-wam.jl/pl-attvar.jl reworded.
- b852d54 G2 family 2: `_boot_syspred!` `_boot_bags!` `_boot_bagof!`; 3 manifest entries.
- 061b906 G2 family 3: `_boot_attvar!` `_boot_freeze_uhook!` `_boot_freeze!` `_boot_when!` `_boot_call_residue_vars!` and the
  helpers (`_boot_clause!` `_boot_term` `_boot_conj` `_boot_ite` `_boot_cons` `_boot_vars`); 12 manifest entries. initBuildIns!
  is pl-ext.c's again. Two pinned KNOWN DIFFERENCES flipped to swipl's answer, marked `UNVERIFIED on the kernel: gate decides`:
  cr11 in test/core_lang/test_attvar_wakeup.jl ('$attvar':run_crv/4) and the uhook/3 context in test_attvar_store.jl.
- ab7e998 G3: boot/init.jl and its include deleted; `load_file!(gd, ld, path)::Tuple{Symbol, Union{Nothing,T}}` in src/pl-wam.jl
  after query_answers = `user:load_files(AbsPath, [])` via query_answers: `:ok` / `:failed` / `(:exception, ball)`. README block +
  test/foreign/test_readme_example.jl, docs/release-notes/unreleased.md (NEW file: the D-0286 item 4 entry), tools/bench.jl,
  tools/fuzz.jl re-pointed; manifest drops init.jl's 24 entries (load_file! entry kept, same signature).
The tree does not pass its tests at this SHA: about 50 test files still destructure `load_file!`'s old three values (G5).

FINDINGS for the next agent (read-only, from the edits):
- G3b (NEW, before G5): src/pl-error.jl:1021 `printMessage` still appends to `ld.messages` (an R1f DIVERGES) instead of calling
  print_message/2, so C-side messages (singleton warnings, pl-read.c; the flag warnings, os/pl-prologflag.jl:769) never reach a
  `user:message_hook/3` collector (LQ7). Port pl-error.c printMessagev AS IS (pin src/pl-error.c:990-1063): `LD->in_print_message`
  (OK_RECURSIVE 10; new PL_local_data field, pl-global.h:525), saveWakeup/restoreWakeup (src/pl-attvar.jl:44/103, the
  WAKEUP_KEEP_URGENT_EXCEPTION pattern at src/pl-wam.jl:1050), `PROCEDURE_print_message2` (LOOKUPPROC, pl-ext.c:372 ->
  `gd.procedures_print_message2` in setBuiltinPredicateProperties!, src/pl-ext.jl:182 style; new PL_global_data field),
  PL_call_predicate(NULL, PL_Q_NODEBUG|PL_Q_PASS_EXCEPTION), `Sferror(Suser_error(ld))` (src/os/pl-file.jl:122). The Sdprintf
  fallback branches: Sdprintf is left to port (src/pl-qlf.jl:152 `_qlf_Sdprintf!` collects into ld.messages: reuse or port Sdprintf). 20
  callers of printMessage: check each against its upstream caller's rc handling. Struct change in BOTH structs: combine with G4's
  alloc pins. Then `ld.messages` has only `_qlf_Sdprintf!` left (decide with G9).
- when/2 now comes from library/when.pl by autoload (as upstream); `'$wakeup'/1`, freeze/2 from boot/attvar.pl in '$attvar':
  `gd.procedures_dwakeup1` is LOOKUPPROC(system:'$wakeup'/1) (src/pl-ext.jl:183): whether system sees '$attvar's export at
  wakeup is a first-boot item (G9).
- The removed `_boot_lists!` carried a DIVERGES: a term type that cannot hold an Int64 got `'$append'/3` only. init.pl's
  length/2 has integers: booting init.pl on such a term type is a first-boot item (G9); check which of the three term types.
- Mutant lists of LANDED steps whose anchors sat in the deleted code (tools/mutants/AV7.py, AV8.py, AV9.py, V9g.py, MOD4.py):
  left unchanged (historical); a re-run of those batteries would report missing anchors. LB4B2.py (G7) carries one mutant per
  stand-in KEPT (sizing: T1 must fail), not these.
- docs/architecture.md still describes the stand-ins (lines ~2656, 3390-3446, 3528, 5215-5269, 5331, 5446, 5752): G8 appends a
  block saying they are deleted; old blocks stay (append-only rule).

NEXT AGENT, in order:
1. G3b printMessagev (above), one commit (UPSTREAM: subject form, pin cite).
2. G4 `ld.variable_names` (plan G4; the old init.jl set it at :69, now init.pl:1948-1949's b_setval does): recount sites.
3. G5 the ~50 test files with `load_file!` (`grep -l 'load_file!' test/*.jl test/*/*.jl`): two values; message rows through a
   `user:message_hook/3` collector (needs G3b); test_load_swipl.jl's refusal rows now load (against swipl); stale-pin hunt
   (GATE-PLAYBOOK: KNOWN DIFFERENCE|interim|until R2 over test/) for everything the boot now defines in its own module.
4. G6-G8 as planned; then G9 on the local merge (wip/lb2bw, wip/pr1, wip/q10b, wip/bootpred3, wip/dict) when a daemon slot is
   free (ps/free -m first: at most three daemons, MemAvailable >= 12 GB), home tree built first (F2).
5. test/db/test_gd_template.jl: rows meant to be cheap pass `() -> setupProlog(T)` (writer 1's item 3, still open).

## State (writer 3, 2026-11-02; forced hand-back by the 150k cap hook)
COMMITTED (edit-only, NOTHING RUN, no daemon slot taken):
- 36b3d7f G3b `UPSTREAM: pl-error.c printMessage printMessagev`: printMessage calls print_message/2 (pin pl-error.c:990-1063),
  OK_RECURSIVE, saveWakeup(true)/restoreWakeup + KEEP_URGENT, PL_Q_NODEBUG|PL_Q_PASS_EXCEPTION. NEW FIELDS at the END of each
  struct: `PL_global_data.procedures_print_message2` (LOOKUPPROC in setBuiltinPredicateProperties!, src/pl-ext.jl:184),
  `PL_local_data.in_print_message::Int`. Fallback Sdprintf branches + addClauseWic's pl_write collected on ld.messages
  (`_qlf_Sdprintf!`, NEW `_qlf_pl_write!` in src/pl-qlf.jl). The 20 callers checked: their rc handling already mirrors upstream.
- 2a23a11 G4: compileClause reads `$variable_names` with gvar_value (src/pl-comp.jl ~3157); field `variable_names` removed from
  PL_local_data (struct change); test_compiler_warnings_swipl.jl sets it with gvar_setval(SETVAL_BACKTRACKABLE).
UNCOMMITTED in the worktree (G5, written, NOT staged; the next agent reviews `git diff`, then stages + commits as G5):
- 55 destructurings `st, ball, _ =` / `st, _, _ =` -> two values, over the test files (mechanical regex).
- NEW helper `lk_load_file_messages!(gd, ld, path)` appended to test/term_under_test.jl: loads a `user:message_hook/3` collector
  file once per database (error/warning kinds -> `user:'$lk_message'/2`), loads `path`, returns `(st, ball, msgs)`. The 18 msgs
  sites (test_zero_exports x9, test_numbervars_cells, test_slot_indirects, test_write_cells, test_clause_ref_swipl,
  test_nth_clause_swipl, test_load_swipl x4) call it.
- test/files/test_load_swipl.jl: the "refusals" testset replaced by `_TL_FORMER_REFUSALS` (18 texts compared with the swipl
  driver, `_tl_kernel` vs `_tl_swipl`, non-vacuity) + a reconsult/second-file testset (UNVERIFIED on the kernel: gate decides).
  NOT YET DONE there: the header comment lines 13-15 still say "THE REFUSALS ... NotPortedError" (reword to "THE FORMER
  REFUSALS ... since LB4 b2 each loads through boot/init.pl, compared with swipl"); the header's `boot/init.jl execute_directive!`
  normalisation note and `1 <= _TL_NORMALISED[] <= 4` are stale-pin candidates (G9 decides).
LEFT for G5: `grep -n 'ld\.messages' test/*/*.jl` (6 files read ld.messages after a load: test_set_flag_swipl, test_det_swipl,
  test_canonical_readatom_swipl, test_qlf_swipl, test_exceptions_swipl, test_load_swipl): re-point to the collector where the
  message is now print_message/2's; test_stack_limit.jl:150 and test_set_flag_swipl.jl:558/578 already fit the two-value shape.
  Then the stale-pin hunt (GATE-PLAYBOOK: KNOWN DIFFERENCE|interim|until R2 over test/).
G8 items found: manifest entry `(LK._qlf_pl_write!, Tuple{LK.PL_local_data{T}, Int}, false)` after `_qlf_Sdprintf!`
  (test/static_analysis_manifest.jl ~2426); OK_RECURSIVE is a plain const (no enum).
G9 items found: gd.procedures_print_message2 is system:print_message/2 created undefined at setup; boot/messages.pl's export must
  reach it (upstream import fills an undefined procedure's definition) — same question as dwakeup1. Before messages.pl is
  loaded every printMessage goes to the collected fallback ("print_message/2: recursive call: " + term), as upstream prints it.
Alloc pins x3 at the gate cover THREE struct changes (G3b two fields, G4 one removal).
NEXT AGENT: finish G5 (above), commit; then G6-G8, G9 as in writer 2's list.

## Answers for D-0354 item 7 (read-only)
- UPSTREAM markers: not settled per row. Commit subjects `^UPSTREAM:` on origin/main: 95 (`git log --grep`); a per-predicate
  check against the recount's 60 rows was not done (it needs the 60 names mapped to commits). Source files carry `# PORT:` lines.
- init.pl:4554 `[Opt] :< Options` sits in `'$option'/2`'s first clause behind `is_dict(Options), !` (:4552-4553): at first
  boot every caller passes a list, so the second clause (`memberchk`) runs and `:<` is only compiled as a call.
  expand.pl:486 (`Left >:< Right`, `put_dict/3`, `get_dict/3` at :480-487) is in `merge_states/3` of the `'$var_info'`
  variable-state merge of goal expansion (:474-490): reached when a clause body's branches give a variable different
  states, plausibly during the boot once load.pl has swapped expand.pl in. The first boot run decides; include wip/dict.
- halt/1: defined at init.pl:4655-4661; no boot directive calls it. Upstream's boot ends in `PL_halt` from C
  (pl-init.c:1625, :1643), which LB3's `boot_from_source!` leaves out (no state file). Prolog `halt/1` is first reached at
  run time from toplevel.pl (:403, :417, :491 initialisation errors; :1140-1168 `-c` compile), never on the boot load path.

## Flags for the audit
F1 Base of wip/lb4b2 = main + cherry-picked wip/lb4b1 (b2-1 edits b1's file). The gate rebase drops the copies.
F2 HOME TREE at boot: the home flag names `<pkg>/home` (src/os/pl-prologflag.jl:1692), built by tools/build_home.jl, which only
   test/test_home_tree.jl calls (in a temp dir). A boot needs HOME/boot/init.pl. Options: (a) the booted constructor builds the
   tree on first use (needs build_home in the package: move or include it); (b) the runners build it (runtests, warm, CI), the
   constructor raises naming tools/build_home.jl; (c) a writable scratch home for a Pkg-installed (read-only) package.
   Recommendation: (a) for the repo + (c) later for installs. This writer does (b)-style raise now; decision needed before gating.
F3 `-O` in upstream's boot command (src/CMakeLists.txt:360) sets `optimise` true for the boot compilation; the kernel's flag is
   false (src/os/pl-prologflag.jl:1698). Whether the kernel boots with -O is a flag value that differs: the audit's call.
F5 docs/release-notes/unreleased.md is a NEW file (the release-notes entry D-0286 item 4 asks for; only v0.1.0-pre.1.md
   existed). The audit may prefer another name.
F4 precompile_workload.jl constructs databases: with the boot on, precompilation would boot (minutes). Needs a decision
   (skip the boot in the workload, or accept the cost).

## State (writer 4, 2026-11-02; handed back at ~95k context at a clean commit boundary)
COMMITTED (edit-only, NOTHING RUN, no daemon slot taken):
- 43e60be G5 part 1 = writer 3's uncommitted edits, reviewed (diff stat = 48 test files + this file, as described).
- da14a14 `UPSTREAM: pl-vmi.c b_throw_resume`: the unwind(_) ball's recover goal is wrapped as
  `'$recover_and_rethrow'(Goal, Ball)` (pin pl-vmi.c:5266-5278; `uncachableException` pl-wam.c:2253-2263), the old
  refusal by name removed; `FUNCTOR_drecover_and_rethrow2` in src/pl-prims.jl beside FUNCTOR_colon2. Folded into it, G5's rest:
  term_under_test.jl now has `lk_install_message_collector!(gd, ld; printing=false)`, `lk_take_messages!(ld)` and
  `lk_load_file_messages!` on top of them (`printing=true`: the hook records then fails, so print_message/2 still prints,
  as the swipl drivers' hooks ending in `fail`). Re-pointed from ld.messages: test_det_swipl (`_rdt_ours` returns msgs),
  test_canonical_readatom_swipl (printing collector; `_cr_strip_printed` dropped: both sides' user_error compared),
  test_set_flag_swipl (`_sf_kernel` returns msgs 4th), test_exceptions_swipl (reportStreamError row), test_qlf_swipl
  (the syntax-error report row; `_ql_messages` stays on ld.messages = the boot loop's `_qlf_Sdprintf!` texts).
  Pins flipped to swipl 10.1.19, each `UNVERIFIED on the kernel: gate decides`: test_findall_swipl (context
  `'$bags':findall_loop/4`, probed twice), test_catch_swipl (unwind row: recover goal runs, ball goes on; probed incl.
  side effects via threads), test_load_swipl (`_TL_NORMALISED[] == 0`; header lines 9-15 reworded). test_module_swipl
  "the table" testset and test_module_path.jl use `LK.setupProlog(T)` (the unbooted table: 2 modules, no clause).
TERM GREP: one expected hit in da14a14's diff: upstream's own fatalError text "Cannot wrap abort exception" (pl-vmi.c:5270),
  copied as is into a Julia `error`; not a crash description. The audit may ask for a reword.
LEFT for G5 (stale-pin hunt, 166 hits of KNOWN DIFFERENCE|interim|until R2|stand-in|NotPortedError|printMessage over test/,
  scratch list rebuilt by that grep): checked and left (expectation already swipl's or a refusal still in src):
  test_ssu_compile_swipl:561 (','/2 stand-in comment), test_metacall:243, test_attvar_wakeup header, test_declare_destroy /
  test_export_import (abolishProcedure: PR1's), test_format, test_module_swipl:589 (program_space). NOT yet read:
  test_meta_predicate_swipl:182 (the stand-in's S_LMQUAL), test_ssu_swipl:5/174 (consult stand-in rewrite), test_body_code,
  test_read_term/write/positions, test_prolog_flag, test_source_file, test_open_close, test_arith, test_rules hits.
NEXT AGENT: (1) finish the hunt above (one commit); (2) G6 gate files, G7 tools/mutants/LB4B2.py (add a mutant on the new
  b_throw_resume branch: TARGETS test_catch_swipl.jl + every booting file), G8 manifest (`_qlf_pl_write!` entry; check
  whether FUNCTOR_drecover_and_rethrow2 needs one: FUNCTOR_colon2's treatment decides) + docs block; (3) G9 on the local merge.
Daemons at 2026-11-02 hand-back: one warm daemon (pid 84292, up ~1 h) plus a cold compile started ~90 s before by
  another lane; MemAvailable 18.4 GB. No slot taken by this writer (a second cold compile is refused).

## State (writer 5, 2026-11-02 17:00Z; handed back at ~100k context at a clean commit boundary)
BRANCH NOW wip/lb4b2b (wip/lb4b2 left as it was, 81bcfe0; not deleted). wip/lb4b2b = wip/lb4b2's 25 commits rebased onto
origin/main eb700e8 (ARGINL; `git rebase --onto origin/main 9e0a983`, non-interactive). One conflict, src/pl-ext.jl
setBuiltinPredicateProperties!: LOOKUPPROC(arg3) and LOOKUPPROC(print_message2) both kept, upstream order (pin
pl-ext.c:371-372). pl-global.jl auto-merged: procedures_arg3 (main) in upstream place, our fields at the end; the
constructor's positional args line up (fields :56/:82 vs args :165/:191). File list vs base identical to the old range
(89 files; +1 comment line in pl-ext.jl). The 12 wip/lb4b1 commits are still in the stack (b1 not on main).
COMMITTED (edit-only; NO Julia run; swipl run as the oracle only):
- 4e94b3d test_arg_body_swipl.jl (ARGINL's new file) takes load_file!'s two values.
- a1df75a stale-pin hunt DONE: test_meta_predicate_swipl b01/b02 and test_ssu_swipl header/s16 re-cite boot/init.pl
  (:501-504, :364-365) and boot/expand.pl head_guard/4 (:248-269). The rest of the hits are refusals still in src or other
  owners' (body_code V2 refusals, arith interim, prolog_flag pipe, rules' local stand-in facts, write*/read_term dict and
  qq refusals, source_file LB6, open_close set_output/stream_property: unregistered in src).
- c3cc2a3 G6 T4 test/db/test_boot_messages_swipl.jl: boot as boot_global_data does (setupProlog, own ld, collector
  asserted BEFORE boot_from_source!), lines = ld.messages (Sdprintf) + hook-recorded error/warning; must == `_BM_KNOWN`
  (EMPTY; G9 fills it with the LD12 rows, each with its cause). Oracle: swipl's own boot command (src/CMakeLists.txt:357-361)
  over its home prints NOTHING, exit 0, two runs identical; re-run live when swipl on PATH. PLBASE boot/*.pl ==
  vendor/swipl-devel/boot/ (diff -rq; only build_home.pl extra in vendor).
- 6502080 T1/T3 oracle fixtures test/db/test_boot_image_swipl_rows.pl/.out (precedent test/core_lang/test_module_swipl_rows.*):
  `t1 <module codes> <name codes> <arity> <dynamic foreign system iso transparent meta public exported> <nclauses|none>`,
  2187 rows over 23 modules (753 foreign, all in system); `t3 <file rel. to boot/> <type> <load_count> <nclauses> <reloading>
  <modules>`, 25 files. Modules found via module_property(M, file(F)) over the boot files (current_module/1 skips
  system-class modules). Oracle facts seen: `system` (P_LOCKED) property is 0 on the boot's Prolog predicates;
  load_count 2 and from_state are the restored state's (not comparable to a from-source boot: expected kernel load_count 1,
  from_state false by upstream's from-source path, read not run).
NEXT AGENT (in order):
1. G6 T1+T3 test/db/test_boot_image_swipl.jl reading the .out (ONE parser for both sides; kernel rows from
   LK.boot_image_predicates / boot_image_source_files on `PL_global_data{T}()`): (a) foreign=0 rows: EXACT set and columns
   vs the oracle, minus the DIVERGES rows below; (b) foreign=1 rows: only those the kernel defines, columns equal; kernel
   foreign rows swipl lacks = pinned list; (c) T3 order + type + nclauses + reloading + modules, minus threads.pl;
   load_count == 1 and from_state == false by reasoning (comment). Non-vacuity: both sides > 1000 rows. Live re-run of
   the driver when swipl on PATH (cmp with the .out). THREADS DIVERGES rows (verified in the .out): system '$error_count'/2
   swipl 2 clauses -> kernel 1 (init.pl:2557-2564); system '$mt_load_file'/4 3 -> 2 (init.pl:2720-2741);
   system '$mt_start_load'/3, '$mt_do_load'/5, '$mt_end_load'/1 (3 clauses each) -> undefined (init.pl:2754-2785);
   '$toplevel':main_thread_init/0 2 -> 1 (toplevel.pl:560-582); T3: boot/threads.pl (module '$threads', 0 clauses) not
   loaded: load.pl:78-80 `:- if(current_prolog_flag(threads, true)). :- consult(threads).` (FLAG F6 below).
   Then H12 (no attvar in any booted clause) in the same file or T2's.
2. G6 T2 test/db/test_boot_clauses_swipl.jl: clause/2 bodies =@= swipl's (oracle needs access_level system); suggestion:
   per-predicate text of the numbervar'd clause list as a fixture .out like T1's.
3. G7, G8 as in writer 4's list; G9 on the local merge (needs a daemon; at 17:00Z two warm daemons up, pids 84292 and 486658,
   load 6.6, 16.4 GB available: a THIRD slot is free by the rule, no cold compile seen).
FLAG F6 (audit): ruling 1 (D-0354 item 3) lists init.pl and toplevel.pl lines; load.pl:78-80 (threads.pl consulted only
   when threads is true) is the same DIVERGES; T3's 24-vs-25 file row cites it. Needs the audit's nod.
FLAG F7 (audit): T1/T3 pins live in a .out fixture beside the test (2187 rows, 214 KB), not inline.
