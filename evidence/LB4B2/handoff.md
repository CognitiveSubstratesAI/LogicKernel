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

## State (writer 6, 2026-11-02; in progress)
COMMITTED (edit-only; NO Julia run; swipl run as the oracle only):
- 6e1343b the T1/T3 oracle is now swipl's OWN BOOT FROM SOURCE: the driver is a second file of the boot command
  (pl-qlf.c:4784-4806 compileFileList) and prints from its last directive. Writer 5's restored-state rows had load_count 2
  and start-up dynamic counts (library_index 1247); from source: load_count 1, from_state TRUE (pl-srcfile.c:310
  GD->bootsession; writer 5's "from_state false" was wrong), T3 gets a from_state column. Static rows and flags unchanged.
- 34c4c4f test/db/test_boot_image_swipl.jl: T1 + T3 + H12, config rewrite rows (threads, open_shared_object, LD12 wrap
  closures), kernel pins `_BI_KERNEL_*` empty / -1 until G9. H12 swipl pin (3240, 192, 0, 0) = the .out's T1 sums.
FLAG F8 (audit): `open_shared_object` is undefined in the kernel (D-0151 item 6, build without O_DYNAMIC_EXTENSIONS), so
  syspred.pl:485-493 and :497-589 compile neither branch: '$syspreds' use_foreign_library/1,2, use_foreign_library_noi/1,
  ensure_shlib/0 undefined, unload_file_/1 one clause (T1/T3 pin these as DIVERGES). D-0151 ruled the flag, not this
  boot-file consequence: needs the audit's nod. Every other `:- if` of boot/*.pl reads a flag both sides agree on
  (windows/apple/emscripten/prolog_debug undefined in both; threads; open_shared_object).
- Writer 6 FORCED HAND-BACK by the 150k cap hook before T2 was committed.
T2 DESIGN (measured, not committed): evidence/LB4B2/t2_encoder_prototype.pl is the encoder prototype (run in swipl's boot
  as a 2nd file + a 1-line `:- ...` file; boot mode: autoload false, an undefined predicate is FATAL, so boot/C preds only).
  Found: a full text fixture is ~1.3 MB (3432 clauses, ~380 B/line) -> instead ONE Prolog driver for BOTH sides printing
  `t2 MODcodes NAMEcodes ARITY NCLAUSES HASH` per STATIC Prolog predicate (dynamic = boot state with this machine's paths:
  T1 covers their counts), HASH = fold H=(H*257+C) mod 2147483647 over each clause's encoding (vars numbered by first
  occurrence => equal text == =@=), 10 between clauses. The kernel loads the same driver (load_file!) and enumerates
  lb4b2c_line/1 via query_answers. FIX NEEDED in the prototype: compound_name_arity of a dict gives C'dict' (a reserved
  symbol, atom_codes raises; init.pl:4552-4554 '$option'/2 uses `:<`): encode a non-atom functor name with
  format(codes(NC), "~w", [N]) and tag `r`. Planned files: test/db/test_boot_clauses_swipl_rows.pl/.out +
  test/db/test_boot_clauses_swipl.jl; config rows pinned DIVERGES (kernel hash pinned by G9): '$error_count'/2,
  '$mt_load_file'/4, '$toplevel':main_thread_init/0 (threads), '$syspreds':unload_file_/1 (F8).
  F3 MATTERS FOR T2: expand.pl:1368-1370 simplify/4 is skipped when optimise is false, and init.pl:4118 `=>` guards; the
  boot sets -O, so a kernel boot without -O gives other bodies. Suggest: also generate the oracle WITHOUT -O and count
  the differing predicates for the audit's F3 call.
NEXT AGENT: (1) T2 as above; (2) G7 tools/mutants/LB4B2.py; (3) G8 manifest + docs block; (4) G9 needs a daemon.

## State (writer 7, 2026-11-02; in progress)
- 90925a4 T2: test/db/test_boot_clauses_swipl.jl + _rows.pl (driver, prototype fixed: `[]` as [0'n] since the boot's
  double_quotes made "n" fail and dropped every clause with a `[]`; a non-atom functor name or a reserved symbol
  such as C'trienode' in $tabling:'$table_mode'/3 as ~w text, tag r) + _rows.out (1389 rows, 3240 clauses = H12's sum,
  two runs byte-identical, stderr empty, NO -O: the kernel's current configuration, src/pl-qlf.jl:368). F3 measure:
  with -O 33 rows differ, all in $tabling (evidence/LB4B2/t2_optimise_diff.txt; pinned in the oracle testset). No
  machine path and no blob address in any clause (checked over a writeq dump). Kernel pins `_BC_KERNEL_DIFFER` empty,
  the 4 rewritten rows' hashes `nothing`: G9 fills them. UNVERIFIED on the kernel: gate decides.
- FORCED HAND-BACK (150k cap hook) with THREE FILES UNCOMMITTED in the worktree (written, not committed; the next
  agent checks `git status --short`, reviews, then stages and commits them as ONE commit "ADDED: tools/mutants/LB4B2.py"):
  * tools/mutants/LB4B2.py: 19 mutants (Q1 G1 G2 boot; W1 W2 _qlf_pl_write!; E1-E6 printMessage; C1 $variable_names;
    L1-L3 load_file!; B1-B4 b_throw_resume's unwind branch), every `old` counted exactly once (python3 -I runpy check),
    ids unique, TARGETS = TBOOT (146 files: every test file constructing a database directly or via rules_common.jl /
    index_testlib.jl, or booting, + test_readme_example.jl); each mutant's deciding files first (`_first`). NOT LISTED
    with reasons in its header (H11 / boot result guards, OK_RECURSIVE*3 fatal, emergency-space check). Survivor
    candidates flagged in ids: E4, E6, L2.
  * test/files/test_qlf_swipl.jl 'Failed to compile' testset: a kill row for W1/W2 (the message after the text is the
    term atom_length(a, b)).
  * test/files/test_load_swipl.jl: a new testset at the end, kill row for L3 (load_file! refuses an engine of another
    database). Both UNVERIFIED on the kernel: gate decides.
- G7 part 2, anchors of LANDED lists that no longer occur once at HEAD (DO NOT edit those lists): AV7 U1-U5, Q1
  (src/pl-ext.jl); AV8 B1, B2 (pl-ext.jl); AV9 B1-B4 (pl-ext.jl); MOD4 B1, B2 (pl-ext.jl): all in the deleted stand-ins
  (b2-2). V9g: 32 (MG7 MG20 MG23 MG24 pl-wam.jl, MG21 pl-pro.jl, MB1-MB6 pl-rec.jl, MB17-MB19 pl-list.jl, MB23 MB24
  MB26-MB28 pl-prims.jl, MB29-MB31 pl-ext.jl, CT1-CT10 pl-copyterm.jl): NOT yet split into "broken by this stack" vs
  "already broken on origin/main" (the check was cut by the cap hook; likely most V9g ones predate b2: next agent runs
  the same count against `git show origin/main:<file>`).
- G8 found (not written): manifest needs entries for `_qlf_pl_write!` (Tuple{PL_local_data{T}, Int}), and also
  `boot_global_data` (Tuple{Type{T}}) and `setupProlog` (Tuple{Type{T}}), none present; FUNCTOR_drecover_and_rethrow2
  is a const (no method, no entry; its ATOMS row 276 / F row 1168 exist). The anonymous `() -> boot_global_data(T)` of
  gd_template.jl:110 may need an entry if the coverage check counts closures (gate decides). The LB4 b1 manifest
  comment at test/static_analysis_manifest.jl:2564-2566 ("b2's caller pass it" PL_global_data{T}) is stale since
  PL_global_data{T}() is the template's copy (as a build it would recurse): reword at G8.
- GATE NOTE (D-0164 grep): src/pl-wam.jl b_throw_resume (writer 4, 86027f8) carries upstream's fatalError text
  (pl-vmi.c:5270, verbatim): the term grep over the diff hits one word of it; the audit/dispatcher decides (upstream text).

## State (writer 8, 2026-11-02; handed back at G9: no daemon slot, local merge blocked by a hook)
BRANCH NOW: wip/lb4b2c = the whole stack rebased onto origin/main 2416adb (40 commits, `git rebase --onto origin/main
eb700e8`; one conflict, docs/architecture.md LB4 b1 block vs Q10 block, both kept; identical-tree check: `git diff --stat
wip/lb4b2b wip/lb4b2c` == `git diff --stat eb700e8 origin/main`). wip/lb4b2b is left as it was (old base). Tip 1fd1afa
before this block's commit. Generated docs (docs/port_inventory.md) NOT regenerated: the gate does.
COMMITTED (SHAs on wip/lb4b2b before the rebase -> the same subjects on wip/lb4b2c):
- 3a38eb7 tools/mutants/LB4B2.py (19 mutants) + the W1/W2 and L3 kill rows + writer 7's block (re-checked: every `old`
  once, ids unique, targets exist; python3 -I). FLAG: the plan's G7 said >= 28 mutants; 19 written.
- 63f8e9b evidence/LB4B2/anchor_split.txt: 47 stale anchors of LANDED lists, counted at HEAD / origin/main / eb700e8.
  Already off on origin/main (31): V9g MG7 MG20 MG21 MG23 MG24, MB1-MB6, MB17-MB19, MB23 MB24 MB26-MB28, CT1-CT10; AV7 Q1;
  AV8 B2. Off by THIS stack (16, all src/pl-ext.jl, the b2-2 stand-in deletion): V9g MB29-MB31, AV7 U1-U5, AV8 B1,
  AV9 B1-B4, MOD4 B1 B2. Lists NOT edited (audit's).
- 8777550 manifest (G8): setupProlog, boot_global_data, _qlf_pl_write! (Int = term_t), appended to the LB4 b1 block (a
  block of this stack, so no conflict with main); the closure `() -> boot_global_data(T)` needs no entry
  (test/static_analysis_gates.jl:159 owned_methods skips `#` methods); comment at the old :2564-2566 reworded.
- 6390467 docs/architecture.md LB4 b2 block at the end (pl-setup.c, pl-qlf.c, pl-error.c, pl-vmi.c named).
G9 NOT STARTED. At the check (load 6.1, 9.8 GB free) THREE daemons ran: lk-pr1 (pid 628444), lk-dstack (711418,
3 min old), lk-f2 (609828): the D-0357 maximum, so no daemon was started.
LOCAL MERGE (prep, not committed): branch wip/lb4b2-bootmerge was made at wip/lb4b2c (no commits on it; list for the
dispatcher, not deleted). `git merge wip/lb2bw` conflicts and the resolution used (all "keep both"):
  src/LogicKernel.jl include pl-glob.jl before pl-file.jl (our pl-file comment); src/pl-ext.jl the table comment (+ "glob
  (LB2b)"), `_PRED_TABLES` wic, file, files, glob; the splice list read, wic, file, files, glob, proc, srcfile, write,
  redirect, format; src/pl-global.jl the struct: our four fields then `paths_CWDdir::String`; the comment line "Since
  R2's LB2b" before `# PORT: pl-setup.c setupProlog`; setupProlog's constructor call: `dc_proc,` then `""`; manifest and
  docs both sides. SEMANTIC CONFLICT: test/files/test_lb2b_swipl.jl (wip/lb2bw) destructures THREE values from
  load_file! (`st, ball, _ =` and `st, _, _ =`): with b2's (status, ball) it must be `st, ball =` / `st, _ =` (whichever
  lands second fixes it). The merge COMMIT was refused by require-verified-absence-before-commit.sh: the merge diff
  carries wip/lb2bw's own scope comments (the hook's absence words; lines that branch added, not new text); no allow-*
  escape was used; the merge was rolled back (tree clean). Trial merges (git merge-tree) against wip/lb4b2c: wip/bootpred3b clean;
  wip/pr1b, wip/f2t docs only; wip/dict, wip/rd1 docs + manifest.
FOR THE DISPATCHER/AUDIT: (a) how the local merge may be committed (the hook reads the whole merge diff), or run the boot
  on an uncommitted merged tree; (b) F2-F8 as before (F3: T2's oracle is without -O).
NEXT AGENT: when a daemon slot is free (load < 8, <= 3 daemons): the local merge as above (per (a)), then
  `LOGICKERNEL_WARM_THIRD=1 tools/warm.sh start` in this worktree (cold compile ~30 min: three struct changes), the
  first boot, fixes on wip/lb4b2c. Gate files to run first: test/db/test_boot_image_swipl.jl, test_boot_clauses_swipl.jl,
  test_boot_messages_swipl.jl, test/files/test_load_swipl.jl, test/files/test_qlf_swipl.jl.

## State (writer 9, G9 first boot, 2026-11-02 ~19:10Z; FORCED hand-back by the 150k cap hook)
RUN TREE ~/code/lk-lb4b2-run (branch wip/lb4b2-run at 0c85fe6, NEVER commit/push it): an UNCOMMITTED, STAGED merge of
  wip/bootpred3b, wip/lb2bw, wip/pr1c, wip/f2u, wip/rd1 (no dict), made as `git diff <merge-base> <branch> > p; git apply
  --3way p`, conflicts resolved keep-both (docs/architecture.md each time; manifest: b1 block + BOOTPRED3 block, LB3/S2a/P1
  + _manifest_lb2b, Q10/BOOTPRED3 + RD1 entries; src/LogicKernel.jl pl-glob.jl include before pl-file.jl; src/pl-ext.jl
  `_PRED_TABLES`/`_FOREIGN_VA` wic + glob, foreigns[] in upstream order pl-ext.c:116-118 read/$raw_read BEFORE 125-126
  abolish, 171 garbage_collect_clauses BEFORE 175 read/2; src/pl-global.jl our fields then `paths_CWDdir`, the LB2b
  comment line before `# PORT: pl-setup.c setupProlog`, ctor `dc_proc,` then `""`; docs/port_inventory.md ours (generated)).
  Home tree built in the run tree on the daemon (tools/build_home.jl via `warm.sh send`; gitignored; F2 stays the audit's).
  Three-value `load_file!` destructurings fixed IN THE RUN TREE ONLY for other branches' files (they fix them when they
  land second, D-0360 item 10): test/files/test_lb2b_swipl.jl:137,234 (lb2bw), test/core_text/test_read_stream_swipl.jl:533
  (rd1), test/core_lang/test_push_flag_swipl.jl:350,414 (f2u), test_bootpred3_swipl.jl:349 (bootpred3b),
  test_pr1_swipl.jl:486 (pr1c).
DAEMON: unit logickernel-warm-17790d9d (pid 95631) in lk-lb4b2-run, started LOGICKERNEL_WARM_SECOND=1 via the ABSOLUTE
  path /home/shivaji1012/code/lk-lb4b2-run/tools/warm.sh (a `cd` does NOT carry over in an agent; my first start landed in
  lk-dstack and was stopped by me within a minute). It came up in ~5 min, NOT 30: warm_session's Revise.stale_load took
  the newest cache and revised it; a probe confirmed the layout is current (PL_global_data has 42 fields incl.
  paths_CWDdir and procedures_print_message2). Dispatcher told "ready". LEFT RUNNING for the next agent.
UNCOMMITTED FIXES in ~/code/lk-lb4b2 (wip/lb4b2c; the cap hook blocked the commit; the next agent reviews, term-greps and
  commits them, then re-applies nothing: they are ALREADY in the run tree via $S/p1.patch):
  (1) test/db/test_boot_messages_swipl.jl:74-76 `:(;)`, `:(,)`, `:(:-)` are no Julia symbols (ParseError at 75:19):
      Symbol(";"), Symbol(","), Symbol(":-").
  (2) test/core_lang/test_style_check_swipl.jl:176 (Q10, on main) read three values from load_file!: b2's own breakage.
  (3) FIRST-BOOT FINDING 1, FIXED (verified: the boot passes it): pl-proc.c:2077-2081 meta_declaration's ReadingSource
      branch -> src/pl-proc.jl (the LB2 refusal replaced by upstream's branch) + NEW src/pl-srcfile.jl
      setMetapredicateSource (pl-srcfile.c:1333-1360, the non-reload branch; reload is LB6) + manifest entry appended
      to the LB4 b2 block. Hit by init.pl's first `:- meta_predicate` directive during boot_from_source!.
FIRST RUN of test/db/test_boot_messages_swipl.jl [3 types]: 21 pass, 6 fail, 6 error, ALL from finding 1 (boot raised,
  so load_files/2 and print_message/2 undefined). NOT re-run after the fix.
FIRST-BOOT FINDING 2, OPEN (traced, not fixed): a probe boot (setupProlog + boot_from_source!, NO query before it) raises
  at once "atom word 0x4c05 has no recorded symbol": src/pl-qlf.jl:47 directiveClause builds `PL_cons_functor(ld,
  directive, FUNCTOR_colon2, m, d0)` with the BUILT-IN functor; ':' (builtin atom 152, src/ATOMS `A colon`) never got
  its symbol in this database (atom_symbols is filled only by `_atom_word!`, src/pl-atom.jl:2248-2288), so the next
  PL_is_functor (src/pl-fli.jl:582 `_atom_value`) in update_conditional_compilation (src/pl-qlf.jl:94) throws. The test
  file escaped it only because its query_answers on `user:...` recorded ':' first. boot_global_data (the template boot)
  takes exactly the probe's path, so EVERY database build will hit it. Options: (a) record the symbol of every built-in
  atom at setupProlog/do_init_atoms! (mk_nil for "[]"; reserved-symbol blobs need care: read src/pl-inline.jl:218
  `_atom_word!(atoms, syms, v)` and src/pl-atom.jl:2516 registerBuiltinAtoms first) - restores the C6b invariant for all
  ATOM_/FUNCTOR_ constants; (b) PL_is_functor compare words (`n == _atom_word!(ld, name)`, upstream compares functor_t)
  - local, other readers of ':' would still miss. RECOMMEND (a), a representation-only change; it touches
  setupProlog (pl-global.jl): alloc pins x3 at the gate.
NEXT AGENT (fresh, Opus): commit (1)-(3) on wip/lb4b2c; fix finding 2 in the clean tree, `git diff > p; git apply` into the
  run tree; re-run the probe $S/boot.jl (copy in evidence: the snippet is setupProlog + boot_from_source! printing the
  exception and ld.messages) then the five files in order (boot_messages, boot_image, boot_clauses, load, qlf), each
  ALONE (a messages run took ~15 min: compile + boot, 3 types). Pins only after each difference is traced.

## State (writer 10, G9 first boot, 2026-11-02/03; handed back at a DESIGN STOP, ~85k context)
COMMITS on wip/lb4b2c (not pushed: wip/): ad7e5a1 UPSTREAM: pl-srcfile.c setMetapredicateSource (writer 9's five fixes +
  handoff 9 + g9_boot_probe.jl); 547ba6b FIXED: the built-in atoms' symbols at database setup (finding 2); this handoff.
  Both re-applied to the run tree (patch p2: src/pl-atom.jl, src/pl-global.jl, manifest; Revise took them, no restart).
FINDING 2, FIXED + VERIFIED (probe: the boot passes the first directive): new ORIGINAL `registerBuiltinAtomSymbols!`
  (src/pl-atom.jl, after setAtomSymbol!; upstream registerBuiltinAtoms pl-atom.c:1947-1993 sets `a->name`), called in
  PL_global_data's setup right after `atom_symbols{T}()` (src/pl-global.jl): every built-in atom's symbol, a retyped
  reserved symbol (`[]`, dict, ...) as `mk_reserved_symbol`. Manifest entry added. OWED AT THE GATE: alloc pins x3
  (setupProlog allocates ~1056 more symbols).
FINDING 3, OPEN (traced; DESIGN QUESTION Q1 for the audit): six boot clauses refuse to COMPILE (NotPortedError "V9",
  raised through addClauseWic, so the boot stops; upstream's addClauseWic pl-qlf.c:3222-3238 prints "Failed to compile"
  and goes on, but upstream never fails here): init.pl:572 prolog_cut_to/1 `'$cut'` (pl-comp.c:3551 -> I_CUTCHP,
  pl-vmi.c:2935; kernel refusal src/pl-comp.jl:2474), init.pl:604 reset/3 and :617 '$tbl_reset'/6 `'$reset'`
  (pl-comp.c:3543 -> I_RESET/I_EXITRESET, pl-vmi.c:5754/5801), init.pl:626 shift/1, :629 shift_for_copy/1
  (compileBodyShift, src/pl-comp.jl:2313 -> I_SHIFT/I_SHIFTCP), init.pl:645 call_continuation/1 (I_CALLCONT). Later:
  boot/engines.pl:152 `'$yield'` (I_YIELD, pl-vmi.c:2410). Enumerated with probe 2 (evidence g9_boot_probe2.jl +
  g9_probe2_out.txt: a TEMPORARY catch in the run tree's addClauseWic, REVERTED, daemon re-revised, verified).
FINDING 4, OPEN (traced; DESIGN QUESTION Q2): the reader refuses dicts (src/pl-read.jl:3654-3659, PF_DICT, "R1's
  decision"); init.pl:1297 `'$merge_options'(_{file_type:regular}, ...)` stops the boot (read_clause, compileFile);
  ~6 dict-literal lines in boot/ (autoload 1, init 1, messages 3, syspred 1). wip/dict ports pl-dict.c PREDICATES only
  (src/pl-dict.jl), not the reader's dict branch, so merging it does not clear this.
NONE of the five files was run (the boot stops at finding 3/4 first; every file needs a booted database).
NEXT AGENT: wait for the audit's answers to Q1/Q2 (handoff10.md in lk-channel), then port as ruled, re-run probe 2's
  enumeration, then the five files alone in order. Daemon 17790d9d (pid 95631) left UP and warm in the run tree.

## State (writer 11, D-0363 item 2; FORCED hand-back by the 150k cap hook, 2026-11-03)
CODE WRITTEN, UNCOMMITTED in ~/code/lk-lb4b2 (wip/lb4b2c, HEAD still fcfe9e6; the cap hook fired before the commit).
  The whole diff is saved as evidence/LB4B2/w11_p3.patch (413 lines) and is ALREADY APPLIED to the run tree
  (`git apply --3way`, clean). Contents (all cites from the pin cbf4e189):
  - src/pl-vmi.jl: seven new opcodes in pl-vmi.c order, code(159..165): I_YIELD (VIF_BREAK, 2410), I_CUTCHP (2935),
    I_RESET (5754), I_EXITRESET (5801), I_CALLCONT/I_SHIFT/I_SHIFTCP (CA1_VAR; 5839/5874/5908); `_CODE_TABLE` rows;
    header note (the "not declared" line for I_RESET/I_CUTCHP/I_YIELD removed).
  - src/pl-comp.jl: compileSubClause's atom branch emits I_RESET+I_EXITRESET / I_CUTCHP / I_YIELD (pl-comp.c:3543-3556)
    inside `sym_key(arg) in names.reserved_atoms`, keys via `_name_key(T, "$reset")` etc. (NO SubClauseNames field
    added: a struct change); the old reserved-atom NotPortedError is gone. compileBodyCallContinuation/compileBodyShift
    emit `Output_1!(ci, I_CALLCONT|I_SHIFT|I_SHIFTCP, VAROFFSET(i1))` + BOOLEX_TRUE (pl-comp.c:4703-4735). Decompiler:
    I_CUTCHP -> '$cut', I_RESET -> '$reset', I_YIELD -> '$yield' (pl-comp.c:6772-6783); I_CALLCONT/I_SHIFT/I_SHIFTCP
    via common_type_test (`_type_test_name` extended, pl-comp.c:6758-6763); I_EXITRESET beside I_EXITCATCH in
    decompile_head (6153), decompileBodyNoShift (6950, kernel's "nothing" as for I_EXITCATCH), argKey (5520), arg1Key
    (5600). src/pl-funct.jl: SubClauseNames docstring.
  - src/pl-gc.jl clearUninitialisedVarsFrame: I_EXITRESET terminates (pl-gc.c:1354). (mark_local_variables, with
    upstream's I_CUTCHP/I_CALLCONT marks pl-gc.c:2141-2193, has no kernel counterpart.)
  - src/pl-wam.jl: VMI_RUN += the seven; I_CUTCHP FULL port before C_CUT (pl-vmi.c:2930-2959: `_deref_loc` of
    argFrameP(FR,0), tagged int -> existingChoice(ld, i) -> `cc_och = base; @goto c_cut`; else ERR_EXISTENCE /
    ERR_TYPE `choice` via pushWordAsTermRef/popTermRef, `@goto b_throw`). The other six: labels that throw
    NotPortedError{T}(DEF.name, "the VM instruction I_RESET (pl-vmi.c:5754)", "CONT1") etc. — the DIVERGES block
    (owner CONT1, D-0363 item 2) sits above them. test/foreign/test_query.jl still finds I_NOP outside VMI_RUN.
  - docs/port_inventory.md VM inventory: the seven rows `declared`.
DAEMON: the probe send made the daemon RESTART ITSELF ("struct changed: const:VMI_RUN,const:_CODE_TABLE": a
  changed const also restarts it; unavoidable for new opcodes). Its output so far: evidence/LB4B2/w11_boot1.out. Unit
  logickernel-warm-17790d9d in lk-lb4b2-run; the cold compile was in progress at hand-back. NOTHING RUN on the new code.
TESTS STILL TO EDIT (next agent; read in slices):
  - test/compile/test_body_code_swipl.jl:1114-1117 `_BC_IS_REFUSED = (...)` -> `()` with a dated comment; drop the
    loop at :1140-1142 ("every emission ... names a refusal") and add "i_callcont", "i_shift(", "i_shiftcp" to the
    "every instruction of the family is emitted" list (:1144-1150; check `_bc_op`'s rendering at :67 first);
    :3026-3030 the `$reset` refusal loop -> move to the `tf` list (:3033) with pinned code
    `["i_enter","i_reset","i_exitreset","i_exit"]` (and `$cut` -> i_cutchp, `$yield` -> i_yield, `'$tbl_reset'/6`
    shape), compared live with swipl by `_bc_swipl` as pt3's.
  - NEW rows file for the six init.pl clauses (init.pl:572,604,617,626,629,645; engines.pl:152 — read them in the
    pin tree): swipl 10.1.19 LC_ALL=C, two byte-identical runs, clause/2 read-back + compiled code; plus the PIN rows of
    the named errors (reset/3, shift/1, call_continuation/1 raise NotPortedError naming the instruction; swipl's answer
    in a comment, marked "CONT1 flips"), and I_CUTCHP run rows (prolog_cut_to/1 with prolog_current_choice/1:
    a live choice, a stale one -> existence_error(choice, _), a non-integer -> type_error(choice, _), unbound ->
    instantiation_error), shaped as test/core_lang/test_arg_body_swipl.jl.
  - Then: fmt, check, the files on 3 types, commit as `UPSTREAM: pl-comp.c ... (swipl-devel cbf4e189)` with the
    DIVERGES (owner CONT1) in the message; re-run probe 2 (needs its temporary addClauseWic catch) and the five boot
    files alone in order. Mutants (TARGETS: test_body_code_swipl.jl, the new rows file, test_query.jl,
    test_boot_*): I_CUTCHP's existence test, its tagged-int test, the I_EXITRESET in clearUninitialisedVarsFrame,
    argKey/arg1Key I_EXITRESET, the decompile atoms.
OWED AT THE GATE (unchanged + this): alloc pins x3, battery on a fresh name after Evidence.
