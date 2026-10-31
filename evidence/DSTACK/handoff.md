# DSTACK — the linear stack wip/dstack = G1, D2, O1, F1b (integrator, edit-only; NOTHING compiled or run)

Branch wip/dstack off main faee65f, linear (git cherry-pick, no merge commit). Source branches untouched: wip/g1 (bf41225..), wip/d2 (bf41225..),
wip/o1 (faee65f..), wip/f1b (faee65f..). Each step's own handoff stays in the tree: evidence/G1/handoff.md, evidence/D2/handoff.md,
evidence/O1/handoff.md, evidence/F1B/handoff.md (detail, UNVERIFIED lists and audit flags are THERE; none is decided here).

## STATE: COMPLETE (all four steps picked; linear; no allow-* escape, no --no-verify, no hook block met)
Order and BOUNDARY SHAs (the last commit of each step; check each out for the compile checkpoints below):
| step | picks | range picked | boundary SHA |
|---|---|---|---|
| G1 | 15 | bf41225..wip/g1 | 5aa749e846f43ed305fedf3d2fa5b3a8307fd00a |
| D2 | 13 | bf41225..wip/d2 | 0e82d755447de8eaab347319dc8a5b0458b49f9d |
| (DSTACK partial handoff, 1 evidence-only commit) | | | |
| O1 (O1-B then O1-A) | 32 | faee65f..wip/o1 | a5b381dfb53209657969c3357a238cc6006e16c0 |
| F1b | 18 | faee65f..wip/f1b | 90c479777a024b1d93a2489553356228e56ce546 |
The stack top (the gate SHA) = the F1b boundary plus this handoff's own evidence-only commit: `git rev-parse wip/dstack`.

## CONFLICTS AND HOW THEY WERE RESOLVED
- D2 687fb43 src/pl-ext.jl: the comment above `_PRED_TABLES` (G1 added "gvar — G1", D2 "D2: the recorded database"): one line with both.
- D2 6cdcd1d src/pl-global.jl (3 hunks) and src/pl-fli.jl (1 hunk): both steps appended at the end of the LD struct, the LD constructor call, the struct's doc
  comment and `live_states`. Kept both, G1 first, D2 after: LD fields `gvar_nb_vars, gvar_grefs, gvar_enums, recorded_states`; constructor args in the same order
  (G1's last arg got its trailing comma); `live_states` = `... + ld.prolog_flag_enums.live + ld.gvar_enums.live + ld.recorded_states.live`. D2's GD fields
  `record_lists, record_lists_order, record_refs` merged without conflict (G1 adds no GD field).
- D2 eb05797 docs/architecture.md: both appended before "## Still to come": `## G1` then `## D2`.
- O1 78f920a src/pl-global.jl (the same three places): kept G1, D2, then O1B's `IO_output_stack::Vector{IOSTREAM}` / `IOSTREAM[]` (D2's last arg got its comma).
  O1 6ff7796 docs/architecture.md: `## O1B` after `## D2`.
- Textually clean but READ for semantics: the O1 picks of src/pl-ext.jl (`_PRED_TABLES`/`_FOREIGN_VA`: redirect and format at O1's place, gvar at the end, in
  BOTH tables), src/LogicKernel.jl include order (pl-redirect before pl-fmt; pl-gvar after pl-bag), the manifest blocks (G1, O1B, O1A, F1b), docs `## O1A`.
- F1b (18 picks): NO conflict. Its six deleted LD fields and constructor args sit before the appended ones; PL_get_int64 (pl-fli.jl) and PL_get_int64_ex
  (pl-error.jl) clash with nothing earlier in the stack. A scoped grep of src/*.jl, src/*/*.jl, boot/*.jl, test/*.jl, test/*/*.jl, tools/*.jl and the G1/D2/O1A/O1B lists
  for the six deleted field names is clean.

## pl-global.jl FIELD COUNT (struct fields / constructor arguments, a throwaway script, both counted after each step)
| point | GD struct/ctor | LD struct/ctor |
|---|---|---|
| main faee65f | 36/36 | 118/118 |
| after G1 | 36/36 | 121/121 |
| after D2 | 39/39 | 122/122 |
| after O1 (IO_output_stack) | 39/39 | 123/123 |
| after F1b (six deletions) | 39/39 | 117/117 |
LD appended at the end, in order: gvar_nb_vars, gvar_grefs, gvar_enums, recorded_states, IO_output_stack. GD appended: record_lists, record_lists_order, record_refs.
The count shows the numbers agree, not that each constructor argument sits at its field's position: the gate's first compile decides (a type error names the position).

## MUTANT LISTS (throwaway python3 -I + runpy checker: every `old` once, new != old, ids unique, targets on disk)
Final tree: G1 20, D2 45, D1c 100, O1A 130, O1B 23, F1B 23: 0 problems each. MOD3a 18 / SSU1 28 / V9f 44: exactly the nine anchors F1b's finding 10 lists as
stale before the merge (MOD3a-S1, MOD3a-S2, SSU1-R4, SSU1-S1, V9f MK4, MK16, MK22, MD7, MD21), nothing new; not touched.
`mutants/<STEP>` selects tools/mutants/<STEP>.py, one list per branch: G1, D2 (+ D1c, whose D1-56/D1-119 are meant to be KILLED now), O1B, O1A (130; may be
split), F1B; plus MOD3a, SSU1, V9f, D1c on F1b's migrated sites (F1b handoff item 8). Anchors were checked at the stack top: push every `mutants/*` at the
top SHA, not at a boundary. fmt will re-flow some anchors: re-fit with the same kind of checker.

## COMBINED GATE ORDER (the gate agent; nothing below was run)
0. COMPILE CHECKPOINTS first: `warm.sh check` with EACH boundary SHA checked out in turn (5aa749e G1, 0e82d75 D2, a5b381d O1, 90c4797 F1b), so a first-compile
   error is attributed to one step (all four were written without Julia). A fix belongs to the step that owns the error; fix forward at the top unless the
   dispatcher wants a bisect point, and name the step in the fix commit.
1. fmt: `warm.sh send` of the committed files of all four steps (fmt sees only the HEAD diff): G1 src/pl-gvar.jl, pl-copyterm.jl, pl-inline.jl; D2 src/pl-rec.jl,
   pl-dbref.jl, pl-incl.jl, pl-fli.jl; O1 src/os/pl-redirect.jl, src/pl-fmt.jl, src/pl-pro.jl; F1b src/os/pl-prologflag.jl, pl-comp.jl, pl-wam.jl, pl-write.jl,
   pl-error.jl, boot/init.jl, tools/bench.jl; shared src/pl-global.jl, src/pl-ext.jl, src/LogicKernel.jl, test/static_analysis_manifest.jl; the test files (G1
   test_gvar_swipl.jl, D2 test_record_swipl.jl, O1 test_with_output_to_swipl.jl + test_format_swipl.jl, F1b test_set_flag_swipl.jl and its eight migrated
   files). Commit the result; re-fit the mutant anchors.
2. inventory (docs/port_inventory.md is the gate's, never by hand), then `warm.sh check` (includes the Pkg.test-way run).
3. Rows x3 term types, in STACK ORDER: G1 test/core_lang/test_gvar_swipl.jl; D2 test/db/test_record_swipl.jl (+ test/core_lang/test_blob.jl,
   test/db/test_clause_ref_swipl.jl); O1 test/core_lang/test_with_output_to_swipl.jl, test/core_lang/test_format_swipl.jl; F1b test_set_flag_swipl.jl and the 8
   migrated files (test_body_code_swipl, test_portable_smallint_swipl, test_det_swipl, test_firstvar_swipl, test_head_unify_swipl, test_rules_swipl,
   test_exceptions_swipl, test_prolog_flag_swipl). A mismatch on an UNVERIFIED row is traced to its upstream cause, not re-pinned.
4. test/test_type_discipline.jl.
5. `tools/pkgtest_way.sh <file>` for every changed or new test file above, ONE at a time (~3 GB peak).
6. Alloc pins x3 term types (test_zero_exports and test_ball_cells; struct changes in all four steps; Tier 1: pl-global.jl and the run loop). The alloc BENCH
   (H3) only with the dispatcher's go.
7. Push `mutants/G1`, `mutants/D2` (and D1c), `mutants/O1B`, `mutants/O1A`, `mutants/F1B` as separate branches at the WIP SHA once the top is formatted and committed.
8. `warm.sh branch-gate`.
9. Term grep over diff and messages (D-0164: `segment|SIGSEGV|crash|abort|invalid term_t|dies of`). Messages: no hit. DIFF hits already present, all prose or comments:
   evidence/D2/handoff.md, evidence/F1B/handoff.md ("swipl crash case"), evidence/O1/handoff.md (the gate-order wording itself), src/pl-fmt.jl (a docstring about a
   column "segment"), tools/mutants/F1B.py (a comment "a crash, not a verdict"). Re-word these before the push if the term grep is applied to the diff.
10. Gate push `gate/dstack<fresh suffix>` and every `mutants/*` at the SAME SHA, bare `git push`, never force.

## GATE AGENT 1 STATE (Sonnet, 2026-10-31/11-01; stopped by the 150k cap hook)
Daemon: SECOND daemon started in ~/code/lk-dstack (unit logickernel-warm-b4dc834e) and RUNNING; lk-mod5a daemon is the other. NOTE the worktree had NO
Manifest.toml (gitignored): copied from ~/code/lk-t2/Manifest.toml (same Project.toml) before the first start. The whole stack LOADED at the first start
(top-level code compiled: no checkpoint-by-checkpoint compile was needed; only `warm.sh check` errors were attributed by file). The daemon revises
in place (no restart) for source edits; it restarted once by itself after formatting changed a `const`.
Commits on top of b76f1be: 2f498cd CLEANUP (JuliaFormatter over 16 files; fmt of committed files done by hand via warm.sh send) and d739191 FIXED
(first port_check + manifest pass): src/pl-fmt.jl -> src/os/pl-fmt.jl (upstream path rule), copyright lines = pl-fmt.c's, PORT markers one name each
(`as <julia-name>`), src/os/pl-redirect.jl APPENDED to src/os/pl-file.jl (port_check PATH-MISMATCH: pl-file.c code must live in pl-file.jl; include line removed,
refs in docs/tests/mutants/manifest renamed), UPSTREAM headers added (pl-incl.jl: pl-rec.h, pl-rec.c, pl-gvar.c; pl-prologflag.jl: pl-read.c, pl-tabling.c;
pl-file.jl: pl-incl.h), docs/architecture.md rows for pl-gvar.jl and os/pl-fmt.jl, inventory regenerated, D2's 23 manifest entries (test/static_analysis_manifest.jl,
"D2" block before "AV9") which D2 had never written, mutant anchors re-fitted (G1-T2, D1-52, O1A-D20, O1A-F8, O1B-B5; checker at the scratchpad: every
`old` once in its file; G1 20, D2 45, D1c 100, O1A 130, O1B 23, F1B 23 all 0 problems).
`warm.sh check` = PASS at d739191 (format, port_check clean 233 files, manifest 2960 entries, term scopes, meta files); its Pkg.test-way run was over budget
(780 s estimate) and is LEFT to me: run `tools/pkgtest_way.sh <file>` one at a time for the 13 files check listed (test_body_code, test_portable_smallint,
test_det, test_firstvar, test_format, test_gvar, test_head_unify, test_prolog_flag, test_rules, test_set_flag, test_with_output_to, test_record,
test_exceptions).
ROWS x3 (`warm.sh file <path>` = all three types, ~10 min for gvar): test_gvar_swipl.jl 225 pass / 3 fail (ONE row, g35, on each type; the 3 + 3 "pins are
swipl's" and hook testsets pass). g35 = `string_codes(S, [115,116,114]), nb_setval(gv_s,S), nb_getval(gv_s,R)`: ours raises existence_error(procedure,
string_codes/2) (string_codes/2 is T2's, not in this tree; swipl's answer s"str"). PLANNED FIX (NOT yet applied: the cap hook blocked the edit): change only the
PROGRAM of g35 in test/core_lang/test_gvar_swipl.jl line ~188 (and evidence/G1/gvar_rows.pl line 47) to `S = "str", nb_setval(gv_s, S), nb_getval(gv_s, R)`; the pin
t_g35 c[...]/1(s[115,116,114]) stays (swipl's answer is the same; confirm with gen_rows.py + `swipl -q gvar_driver.pl` per evidence/G1/gen_rows.py); if the
kernel's reader gives codes for "str" in that file's mode, keep the row and record it as a known difference with a comment naming swipl's answer + a checklist item
(gate/dstack must pass CI without T2). This is a stale program, not an expected-value change.
NOT RUN YET: rows for test_record_swipl.jl (+ test_blob.jl, test_clause_ref_swipl.jl), test_with_output_to_swipl.jl, test_format_swipl.jl, test_set_flag_swipl.jl and the 8
F1b-migrated files; test_type_discipline.jl; pkgtest_way per file; alloc pins x3 (test_zero_exports, test_ball_cells); mutants branches; branch-gate; term grep (reword
the hits listed in step 9 above, plus check src/os/pl-fmt.jl docstring "segment"); gate/dstack. Nothing pushed. No D-entry newer than D-0281 at 2026-11-01 (channel pulled).
Tips: `tools/warm.sh file` and `check` are backgrounded by the tool after 180 s: block on the pid with `tail --pid=<pid> -f /dev/null` (no sleep loop) and read the log
afterwards; a grep for a name over the tree can trip the CODEMAP hook (use `git grep`). evidence/F1B/sf_template.jl is a template (not parseable Julia): check prints a
JuliaFormatter warning for it each time, harmless; rename it to .tmpl if the warning should go.

## OPEN ITEMS carried (each step's own handoff has the detail; none is decided here)
- UNVERIFIED and audit flags: G1 flags a-f and rows g15 g25 g35 g42 g52; D2 flags F1-F10 and rows r16-r19 r21 r27 r28 r40 r41 r43 r88 r91 plus the white-box
  testsets; O1 flags a-k, O1-B five, rows w43 w44 w64 w68 w69 w70, the `_boot_meta!` order; F1b findings 1-10, the swipl signal case (private register Q15).
- G1 item 6 (`'$variable_names'` read as a global variable in pl-comp.jl) is NOT DONE (G1 handoff); the comments in pl-comp.jl and pl-global.jl still say so.
- O1 watch item: `_boot_meta!` (src/pl-ext.jl) now applies P_TRANSPARENT and the mask to format/2,3 and with_output_to/2, so predicate_property answers change.
- Interactions only read, not run: G1's `_release_frozen!` early return and D2's recorded states (no shared state); O1A's `~@` through callProlog and G1's D8 hook
  (user:exception/3 dynamic from the start; no shared code); F1b's mask readers in pl-comp/pl-wam/pl-write against the new files (grep clean).
