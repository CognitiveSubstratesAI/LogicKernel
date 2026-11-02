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
