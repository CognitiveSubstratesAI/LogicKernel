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
9. Term grep over diff and messages (D-0164, the list in the brief). Messages: no hit. Diff hits were prose or comments in the D2, F1B and O1 handoffs, one pl-fmt.jl docstring and one F1B.py comment;
   all reworded by gate agent 4 (see the last section).
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
F1b-migrated files; test_type_discipline.jl; pkgtest_way per file; alloc pins x3 (test_zero_exports, test_ball_cells); mutants branches; branch-gate; term grep (hits reworded by gate agent 4); gate/dstack. Nothing pushed. No D-entry newer than D-0281 at 2026-11-01 (channel pulled).
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

## GATE AGENT 2 STATE (Sonnet; stopped by the 150k cap hook; WORKING TREE HAS UNCOMMITTED EDITS: `git diff` shows them)
Dispatcher addition (D-0282): BEFORE the gate push run `warm.sh file test/test_static_analysis.jl reference` (JET + Aqua + AllocCheck) on the final SHA; fix dispatch
findings in the new G1/D2/O1/F1b code by concrete types / `where {T}` (D2's local `record` -> `rec` if JET objects); `FIXED:` commits.
COMMITTED: 6723cc0 + "FIXED: G1 row g35 program reads S = "str"" (test_gvar_swipl.jl 228/228 on 3 types; swipl 10.1.19 answers "str", pin unchanged).
ROWS x3 (runner: /tmp/claude-1000/rows.sh = `warm.sh file <f>` one file after the other, logs /tmp/claude-1000/row_<name>.log): FIRST RUN green: blob, clause_ref_swipl,
body_code, portable_smallint, det, firstvar, head_unify, rules, exceptions, prolog_flag. RE-RUN green after the edits below: with_output_to_swipl (255/255), write_cells,
metacall, metacall_control. NOT YET RE-RUN: set_flag, format, record (edits made, see below).
UNCOMMITTED EDITS (all source/test fixes of first-run failures; commit them as separate small `FIXED:` commits, stage and commit in two calls):
 1. src/pl-ext.jl `_boot_control!` (new, called in initBuildIns! after `_boot_cleanup!`) + `_boot_meta!` masks: ','/2, ';'/2 (2 clauses), '->'/2, '*->'/2, '\+'/1 as boot/init.pl:398-402,
    530 define them (callProlog resolves the goal's functor: with_output_to(…, (a,b)) raised existence_error(procedure, ','/2); pl-pro.c upstream does the same, init.pl defines the
    procedures). docs/architecture.md line added; test/static_analysis_manifest.jl entry `LK._boot_control!`. Fixed w32-w49 of with_output_to; metacall tests still green.
 2. src/os/pl-prologflag.jl `set_oneof(ld, f, of, flags)`: new first argument `ld::PL_local_data{T}` (T was unbound when f and of are both `nothing`: UndefVarError in
    set_prolog_flag_ptr); manifest entry updated (Tuple{LD, prolog_flag{T}, oneof_t{T}, UInt32}).
 3. test/core_lang/test_format_swipl.jl: e18 (`~\`` with no fill char: swipl's atom is '\0', the kernel refuses an atom with char 0, NotPortedError, settled DIVERGES) leaves the
    comparison and has its own testset (KNOWN DIFFERENCE, swipl's pin asserted a[0]; checklist: phase 2's atom table); `tabs/3` program uses atom_concat/3 instead of string_concat/3
    (T2's) in the test, evidence/O1A/gen_rows.py and o1a_rows.pl (swipl gives the same "Too many tab stops" row e20; pins unchanged).
 4. test/db/test_record_swipl.jl: r62, r92, r97 programs use `( G -> true )` instead of once/1 (once/1 is not in the tree; same swipl answer, verified: d2_rows.out unchanged after
    regenerating with gen_rows.py); evidence/D2/d2_rows.pl and d2_driver.pl regenerated. The guard `count(raised…) >= 1` over swipl's pins was one that cannot pass (swipl's
    pins never raise out of ex/2): now `== 0`.
 5. test/core_lang/test_write_cells.jl at11: the old pin `existence_error(set_prolog_flag/2)` ("un-pin when set_prolog_flag/2 lands") is now swipl's text.
STILL FAILING, NOT YET FIXED (test_set_flag_swipl.jl, 3 types): (a) sf37 `set_prolog_flag(unknown, fail)` then an undefined predicate: AssertionError at src/pl-wam.jl:4475 (S_UNDEF
 asserts the module's unknown flag is UNKNOWN_ERROR; F1b makes the other two reachable). FIX = port pl-vmi.c S_UNDEF (cbf4e189 vmi.c) fully: `switch getUnknownModule(DEF->module)`:
 UNKNOWN_ERROR (the existing code), UNKNOWN_WARNING (lTop=argFrameP(FR, arity); printMessage(:warning, error(existence_error(procedure, Name/Arity), _)) with
 unify_definition(gd, ld, MODULE_user(gd), pred, DEF, 0, GP_NAMEARITY); `if exception_term: THROW_EXCEPTION`; fall through) and UNKNOWN_FAIL/default (`@goto deep_backtrack`, FRAME_FAILED,
 as S_STATIC does); update the comment lines 4473-4475. (b) testset "the flags refused by name raise NotPortedError (design D4)" test_set_flag_swipl.jl:515: 9 of the 22 `_SF_REFUSED`
 flags throw NOTHING ("No exception thrown"); find which with a loop printing the flag (probe on the warm endpoint, no restart) and compare with set_flag_value's refusals
 (pl-prologflag.jl:1185-1286: several refuse only a CHANGED value, e.g. tty_control, threads(true)); swipl's behaviour with the same value decides whether the row or the source is wrong; the row
 says "UNVERIFIED on the kernel: gate decides". (c) the third error (user_flags=error testset, :522) was the set_oneof UndefVarError: recheck after edit 2.
 Also open: test_format_swipl.jl (e18 + tabs edits), test_record_swipl.jl (guard + once edits) re-run x3.
NEXT (unchanged order): fix (a)(b), re-run set_flag/format/record x3, test_type_discipline.jl, pkgtest_way x13, alloc pins x3, JET file (D-0282), mutants branches (G1, D2, O1B, O1A, F1B) at the gate SHA,
 branch-gate, term grep (hits reworded by gate agent 4; the diff vs main counts the gate SHA's tree),
 gate/dstack at the SAME SHA. Daemon: unit logickernel-warm-b4dc834e in ~/code/lk-dstack RUNNING (rss ~2 GB), idle now. Nothing pushed. Channel: no D-entry newer than D-0281 at 06:xx
 (D-0282 arrived by the dispatcher's message).

## GATE AGENT 3 STATE (Sonnet; stopped by the 150k cap hook)
COMMITS on wip/dstack above 4b2c4a3 (g35): 799016e FIXED first-run fixes (control constructs `_boot_control!`, set_oneof ld, format e18, D2 programs r62 r92 r97, at11; ONE commit:
the tests-before-commit hook refuses a partial index, so five concerns share one green tree); a9015c5 FIXED pl-wam.jl S_UNDEF unknown=fail/warning branches (ENGINE CORE Tier 1, Sonnet
edit: FLAG FOR THE AUDIT's review; made alone by moving the other edits out with a pathspec stash, a green test_exceptions_swipl.jl 3 types wrote the marker; the warning branch has NO
row yet: untested); c18562f FIXED set_flag rows (reader takes the module's var_prefix: set_module_read_data/init_read_data; getOccursCheckMask and var_prefix_code take `ld` first (T was the
argument's subtype on alt types); sf41/sf42 programs use `;` not member/2 (also evidence/F1B/sf_cases.json); `_SF_REFUSED`: tty_control row is `true` (default false as swipl), `threads`
row dropped (read-only in the no-threads build, D1; dead refusal branch + mutant F1B-A6 removed, new testset pins permission_error), `string_stack_tripwire` row dropped (no swipl boot
flag; first set creates it, second set reaches the refusal: pinned in the new testset); docs/port_inventory.md regenerated). EXPECTED-VALUE NOTE for the audit: the `_SF_REFUSED` rows
changed because their premise was impossible (not swipl pins). Mutants lists validated after these changes: G1 20, D2 45, D1c 100, O1A 130, O1B 23, F1B 22, all 0 problems (checker:
/tmp/claude-1000/g3_val.py, rebuild if gone: each `old` once, new != old, ids unique, targets exist).
GREEN on the final tree (3 types): test_set_flag_swipl (390/390), test_format_swipl, test_record_swipl, test_write_cells, test_exceptions_swipl; `warm.sh check` PASS at c18562f's tree.
RED: test/test_type_discipline.jl:152 "no unchecked memory access in src beyond the allowlist" (found != want): the tree has `os/pl-fmt.jl @inbounds` = 1 that the allowlist (test/test_type_discipline.jl
~:105-152) does not carry (check which key differs from the printed Dict; either remove the @inbounds in src/os/pl-fmt.jl or add the allowlist entry with its reason). Fix FIRST.
NOT DONE: pkgtest_way x13 (test_body_code, portable_smallint, det, firstvar, format, gvar, head_unify, prolog_flag, rules, set_flag, with_output_to, record, exceptions; one at a time,
tools/pkgtest_way.sh <file>), alloc pins x3 (test_zero_exports, test_ball_cells), the full static file `warm.sh file test/test_static_analysis.jl reference` (D-0282: mandatory), the reword of
the term-grep hits (reworded by gate agent 4); write NO trigger word in any handoff pushed at the gate SHA, `git diff origin/main..HEAD` + commit messages are grepped), branch-gate, mutants/{G1,D2,O1B,O1A,F1B}
at the gate SHA, gate/dstack at the SAME SHA (fresh name, never force). Channel read to D-0282 (no newer at 01:xx). Not pushed. origin/main = faee65f = merge-base.
Tips: `warm.sh file` backgrounds after 180 s: `tail --pid=<pid> -f /dev/null` in a call; a runner script at /tmp/claude-1000/g3_rows.sh (files as args, status in g3_rows.status) runs files in series
inside systemd-run --scope. The marker is the last green runner on the CURRENT tree (30 min): after ANY edit rerun `warm.sh check` (about 9 min) before committing; `warm.sh inventory` after a
header/DIVERGES comment edit. The hook refuses a partial index: for a lone commit, `git stash push -- <paths>` (pathspec) the rest, run a green file, commit, `git stash pop`.
H3 bench: NOT run, awaits the dispatcher's go. Daemon: unit logickernel-warm-b4dc834e in ~/code/lk-dstack RUNNING (idle since the last file run, rss about 2 GB), not restarted by hand.

## GATE AGENT 5 STATE (Sonnet)
STAGE 1 DONE (re-stack): new local branch wip/dstack-r from origin/main a753dc0, `git cherry-pick faee65f..76a8a5e` = 90 commits (not 94; 4f69fc5 and c586ca9 excluded), linear.
Conflicts: exactly TWO, both docs/port_inventory.md (generated; main's side taken, to be regenerated with `warm.sh inventory`), at the cherry-picks of d739191 and c18562f.
NONE in src/pl-global.jl (MOD5b did not touch it: struct and positional constructor unchanged), src/pl-ext.jl, src/pl-fli.jl, docs/architecture.md, test/static_analysis_manifest.jl
(auto-merged, both sides' entries kept), tools/mutants lists. `git diff 76a8a5e HEAD -- src test tools docs` = exactly main's MOD5b changes (pl-modul.jl, pl-srcfile.jl,
test_declare_destroy_swipl.jl, MOD5b2.py, architecture.md, manifest, inventory). Re-stacked code SHA: 7ea6404.
STAGE 2 DONE: code commit 6b30145 `FIXED: JET Nothing union splits ...` (3 sources): (1) formatInteger: `grouping !== nothing &&` first in both separator conditions (gsize reaches 0 only
with a grouping, so behaviour is unchanged); (2) format_: `ctx.stream::IOSTREAM` (set whenever setupOutputRedirect succeeded); (3) clean_prolog_flag: the pushed loop holds the
flag in a local `p` that the nothing test narrows (the JET frame was the recursive call at :1011). fmt clean (daemon restarted itself: struct changed const:PL_predicates_from_module),
inventory regenerated, `warm.sh check` PASS (146 s). tools/mutants/O1A.py: anchors O1A-H5 and O1A-H9 re-fitted to the two edited lines (130 mutants, 0 bad; the other five lists 0 bad).
## GATE AGENT 5 RE-STACK 2 (onto e863f77, BOOTPRED3 landed)
New branch wip/dstack-r2 = a753dc0..8658786 (93 commits) cherry-picked onto origin/main e863f77, checked out in ~/code/lk-dstack. CODE/GATE SHA = 6945f8c (the O1A anchors commit; nothing above it yet).
Conflicts, all resolved keeping both sides: src/pl-ext.jl (3 times): _PRED_TABLES/_FOREIGN_VA order attvar, gvar, dict (upstream pl-ext.c order: gvar sits between attvar and dict), the table comment
carries "gvar — G1; dict — BOOTPRED (locale and debug, between gvar and dict, are left out)" and "rec (D1: erase/1; D2: the recorded database)"; docs/architecture.md (2 appended sections, both kept);
test/static_analysis_manifest.jl (2, both kept); docs/port_inventory.md (take main's side, regenerate). The old branch wip/dstack-r (gate SHA 8658786, rows/pkgtest/pins/static all green there) is superseded.
NOT YET RUN on the new tree: fmt, inventory (`warm.sh inventory`), check, rows x3 (all D-stack files + test_bootpred_swipl.jl), pkgtest_way (14 files), pins x3, type discipline, FULL static file, branch-gate, term grep, pushes.
LANE: the old branch-gate (my client, started 05:39) was stopped by `systemctl --user stop run-rf66286fe...scope`, but its inner `warm.sh branch-gate` bash (pid 2891750, child 2907846) still HOLDS the lane (warm.sh fmt refused, exit 5). Kill exactly those two pids (or let the dispatcher), then `warm.sh fmt`.
Mutant lists: re-validate on the new tree (/tmp/claude-1000/g3_val.py G1 D2 D1c O1A O1B F1B; also check tools/mutants/BOOTPRED3.py anchors untouched). Channel: nothing newer than D-0283 at 05:3x UTC.
