# ENG3 — the foreign-environment check split out of PL_new_term_ref(s), as upstream (audit D-0379, option 1)

Writer: Opus (allow-opus D-0379), worktree ~/code/lk-eng3, branch wip/eng3 off origin/main c4c34fd. EDIT-ONLY (no Julia run).
The writer hit the 150k context cap after group 3 was written; state below.

## Upstream, read at the pin cbf4e1896275 (~/dev-zone/swipl-devel-cbf4e189)
- pl-fli.c:450-476 `PL_new_term_refs(DECL_LD size_t n)`, :479-500 `new_term_ref`, :503-508 `PL_new_term_ref(DECL_LD)`: no check.
- pl-fli.c:535-541 / :544-550 the API stubs: `if ((void*)fli_context <= (void*)environment_frame) fatalError("PL_new_term_refs(): No foreign environment")` / `"PL_new_term_ref(): …"`, then the LD form.
- pl-fli.c:563-574 `PL_new_nil_ref(void)` makes the same check; the kernel has no port of it (not in scope).
- pl-fli.h:72-74 maps `PL_new_term_ref(_)`/`PL_new_term_refs(n)` to the LDFUNC forms inside the kernel: every upstream src
  file calling them includes pl-incl.h (checked file by file, incl. pl-gvar.c/pl-coverage.c/pl-vmi.c via headers), so all
  internal C callers use the unchecked form; only code linked against SWI-Prolog.h reaches the stubs.

## Commits on wip/eng3 (not pushed)
- 2358638 DOC: this handoff's plan.
- eb1dc87 FIXED: src/pl-fli.jl — `PL_new_term_refs`/`PL_new_term_ref` are the LD forms (check removed; the V4a DIVERGES
  sentences removed; PORT comments cite pl-fli.c:450-476 / :503-508); new `PL_new_term_refs_api`, `PL_new_term_ref_api`
  (`# PORT: pl-fli.c PL_new_term_ref(s) as PL_new_term_ref(s)_api`, DIVERGES: a name of its own + `GET_LD` as an
  argument) = `_check_foreign_environment` + the LD form; `_check_foreign_environment`'s comment rewritten.
  src/pl-wam.jl `query_answers` (the host entry) calls the `_api` forms (3 sites).
- 52184dd TEST: test/foreign/test_query.jl — consts `_Q_NO_ENV_REF`/`_Q_NO_ENV_REFS` (exact fatalError text, read from
  pl-fli.c:538/547: a stub is reachable only from C, swipl's Prolog side cannot be queried); the two old
  `@test_throws ErrorException LK.PL_new_term_ref(ld)` rows now call `PL_new_term_ref_api` with the exact text, plus
  `PL_new_term_refs_api(ld, 2)`; new row (b): in the same no-environment state the LD forms return lTop (t0, t0+1).
- 5f56012 TEST: test_query.jl — the stub passes with a foreign frame opened above a running query's frame (kills ENG3-7);
  `PL_new_term_refs_api(ld, 2)` moves lTop by 2 (kills ENG3-10).

## UNCOMMITTED in the worktree (written, validated, commit it first): tools/mutants/ENG3.py
11 mutants (1 equivalent: ENG3-11 query_answers via the LD form — a foreign frame is opened on the line before). Validated
with a python3 -I runpy checker at 5f56012: every `old` once, new != old, ids unique, all targets exist. TARGETS: TLD =
test_query.jl + the 127 test files that call PL_new_term_ref(/PL_new_term_refs( directly (grep -rlE at 5f56012); TAPI =
test_query.jl + the 5 query_answers callers (test_context_module_swipl, test_prolog_flag_swipl, test_same_term_swipl,
test_query_answers, test_readme_example). Not yet checked: that tools/mutate_drive.py reads per-mutant `targets` with
these global names (TLD/TAPI; MOD3b.py uses TS/TB the same way).

## Caller classification (src/, at eb1dc87): 315 code call sites
- API surface (calls the stub): src/pl-wam.jl query_answers, 3 sites (`t`, `g`, `a` at ~927/930/942).
- Internal (LD form, unchanged): every other site, all inside ports of upstream C files (each file's header is
  `# UPSTREAM: swipl-devel src/<file>.c`): os/pl-file 35, os/pl-fmt 7, os/pl-option 1, os/pl-prologflag 24, os/pl-text 2,
  pl-arith 1, pl-attvar 5, pl-bag 1, pl-comp 37 (incl. unify_definition ~3524), pl-copyterm 3, pl-dict 9, pl-error 1,
  pl-fli 3 (814, 815, 1291), pl-gvar 5, pl-list 6, pl-modul 17, pl-op 2, pl-pro 3, pl-proc 27, pl-prims 25, pl-qlf 7,
  pl-read 23, pl-rec 12, pl-setup 7, pl-srcfile 1, pl-string 5, pl-trace 1, pl-wam 8 (362, 436, 510, 648, 692, 847, 2181,
  4568), pl-write 34 (counts are grep lines, comments included). The ORIGINAL helpers among them (`_unifiable_single!`,
  `writing_attvar`, `newline_domain_error`, `_atom_to_unicode_atoms`, `_rule_term`, `_head_compound!`,
  `_decompile_context!`, `_flag_atom_ref`, `_set_argv_prolog_flag!`) are pieces of upstream functions: internal.
- src/precompile_workload.jl (4 sites: 35, 74, 85, 92): ORIGINAL warm-up of the hot path; kept on the LD form (it warms
  what the engine calls; a foreign frame or env 0 there).
- test/: 127 files call the LD forms directly (they run inside open foreign frames or with env 0: no behaviour change);
  only test_query.jl's rows meant the foreign caller and now call the stubs. Per-line list: regenerate with
  `grep -rnE "PL_new_term_refs?\(" src/` (the classing script was a throwaway).

## Row (b) without b2: NONE reproduces cp5 on main
test_meta_predicate_swipl.jl a24 (`T = a:T, catch(kt(T, true), …)`) already runs catch → I_USERCALL0 → S_MQUAL →
m_qualify_argument → PL_error → unify_definition on main and passes, so main never fills a frame above lTop on that
chain; the state arises only with b2's booted catch/3. cp5 stays in test_catch_swipl.jl for the b2 gate; the white-box
row (52184dd) covers the LD form in a no-environment state. (A candidate `catch(call(G), …)` with `G = call(X)`,
`X = user:X` was probed on swipl 10.1.19 and is unusable as a pin: details in the hand-back report, private.)

## LEFT (next agent, edit-only unless a daemon is given)
1. Commit tools/mutants/ENG3.py (MODIFIED/ADDED: subject + lines; check mutate_drive.py's reading first).
2. test/static_analysis_manifest.jl: append after the RD1b block (~line 2450, the list using `LD`):
   `# ENG3 — pl-fli.c's API stubs` + `(LK.PL_new_term_ref_api, Tuple{LD}, false)`,
   `(LK.PL_new_term_refs_api, Tuple{LD, Int}, false)` (false: the LD form can grow the stack, as lines 333/335).
3. docs/architecture.md: the pl-fli.jl row (line ~775) says "with the foreign-environment check" → "the API stubs with
   the foreign-environment check (`PL_new_term_ref_api`, `PL_new_term_refs_api`, since ENG3)"; the V4a block mentions
   (~4731 "`PL_new_term_ref`'s foreign-environment check", ~4789 the V4a mutant "`PL_new_term_ref`'s check removed") stay
   history; append an ENG3 block at the END (what moved, why, D-0379, the classification summary, row (b) above).
4. Unverified (no Julia run): fmt reflow of the new lines; JET on the `_api` forms; `@test_throws <instance>` comparing
   the message (Julia Test compares fields); the det-last-answer row's lTop arithmetic (t0, t0+1, t0+3) and that writing
   slots at lTop there is harmless before PL_close_query; that the PL_open_foreign_frame-above-a-query row passes
   (upstream PL_open_query leaves lTop above the frame's arguments, pl-wam.c, assumed mirrored); a test elsewhere that
   expected an ErrorException which in fact came from the old check (CI tells). Identical on all three term types by
   construction (no term-type-dependent code).

## Gate command list (gate agent)
fmt via `tools/warm.sh send` (format the committed files) · `tools/warm.sh inventory` (commit docs/port_inventory.md) ·
`tools/warm.sh check` · test/foreign/test_query.jl on all three types · test/core_lang/test_meta_predicate_swipl.jl and
test/core_lang/test_catch_swipl.jl x3 (MC19 cp5 reproduces only on b2) · test/foreign/test_query_answers.jl,
test_readme_example.jl, test_context_module_swipl.jl, test_prolog_flag_swipl.jl, test_same_term_swipl.jl x3 (the stub
callers) · test/core_lang/test_local_stack.jl x3 · test/test_type_discipline.jl · test/test_manifest_entries.jl ·
`tools/pkgtest_way.sh test/foreign/test_query.jl` · alloc pins x3 (239/377/347/433: expect UNCHANGED, the check is a
branch) · static analysis (JET + AllocCheck on the new-term-ref path: an engine hot path, bench risk) · push
`mutants/ENG3` at the WIP SHA · branch-gate · term grep over diff + messages · push gate/eng3 + mutants/ENG3 at one SHA ·
battery after Evidence.

## FINISHER (Sonnet, edit-only, no Julia) — LEFT items 1-3 done, item 4 still the gate's
- ee22ed5 ADDED tools/mutants/ENG3.py (+ this handoff as it stood). The list needed ONE fix: mutate_ci.py `plan` reads a
  module-level `TARGETS` (the baseline, and a push-triggered run's targets), which the file lacked; added
  `TARGETS = TLD + [t for t in TAPI if t not in TLD]` (128 files, as MOD3b.py builds a union). The per-mutant
  `targets=TLD` / `targets=TAPI` are accepted as they are: mutate_ci.py:130 and mutate_drive.py:194 read `m.get("targets")`
  from the dict (the list names are only Python variables). Re-checked with a python3 -I runpy script: 11 mutants, every
  `old` once, ids unique, old != new, all targets exist, `mutate_ci.py plan` prints matrix/count/targets (read, no Julia).
- 97cddc1 MODIFIED test/static_analysis_manifest.jl: `(LK.PL_new_term_ref_api, Tuple{LD}, false)` and
  `(LK.PL_new_term_refs_api, Tuple{LD, Int}, false)` after the RD1b block, inside `_manifest_index` where `LD` is spelled.
- b2e06b5 DOC docs/architecture.md: the pl-fli.jl row reworded; ENG3 block appended at the end. docs/port_inventory.md not
  touched (the gate runs `tools/warm.sh inventory`).
- Commit hook: accepted all three commits (no marker was needed/created by me).
- Gate agent: the new ENG3.py `old` strings were written before fmt (RE-FIT any that fmt rewraps); the baseline of the
  mutation run is 128 files (long: if the budget is tight, give `targets` as the workflow input).
