# R2GEN handoff (writer 2, forced hand-back at the 150k cap; slices 1-3 RUN and committed, slice 4 not started)

Worktree ~/code/lk-r2gen, branch wip/r2gen (off main 012633e), not pushed. Plan: evidence/R2GEN/plan.md. Plain `julia` over text, run as
`systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 -p TasksMax=64 julia --project=. <file> > out 2>&1` (the bare form is
blocked by discourage-core-cold-start; a pipe after julia is blocked by the pipeline hook: redirect, then read).

## Commits on wip/r2gen
1. f93dcf8 plan, 2. 6c1b41b slice 1, 3. 3d3807a slice 2 WIP (writer 1)
4. f24eb11 FIXED first run (writer 2): `r2_registered` now reads through `r2_strip_jl` (a trailing comment after `PL_extension(` hid
   clause/2,3, $clause/4, nth_clause/3, meta_predicate/1, $rule/2,3); `r2_calls` sees operators (`A :< B`, `\=@=`, `is`, `=(A,B)`, prefix
   `dynamic`/`table`/...); test expectations: the r2_strip_jl assertion was WRONG (the function blanks `  # d` byte for byte = 5 blanks), the
   r2_call_args closing index 20 (the test said 21; function right); `keys` shadowed Base.keys; the test no longer imports LogicKernel.
5. ad5456f ADDED slice 3: `r2_flag_scan`, `r2_flags_defined`, `r2_flag_refusals`, `r2_flag_rows`, `r2_vmi_markers`, `r2_vmi_rows`,
   `r2_upstream(root)`, `r2_collect(root, up)` -> `(rows, files, preds)`; main prints per-category counts. Test: 6 testsets, all pass
   (`julia --project=. test/test_r2_status.jl`, exit 0). Commits 4-5 have 5-10 line bodies and the attribution line.

## REAL COUNTS (this tree, 012633e + the above; upstream snapshot read from ~/dev-zone/swipl-devel-cbf4e189 at the pin)
- Upstream C: 1787 definitions = 1554 predicates + 233 VM instructions (pl-vmi.c VMI lines). Kernel registered (PL_extension): 286.
- predicates (C-defined, reached by boot + 4 depth-1 library files): done 224 / missing 198 / platform 3 (win_folder/2,
  win_get_user_preferred_ui_languages/2, win_registry_get_value/3).
- refusal sites: 75 (61 literal throw sites + 14 QLF names). boot_features.md counted 63 + 14; the 2 fewer are pl-comp.jl struct/docstring
  mentions (grep 65 lines = 61 + 2 helpers + docstring + struct line); not a gap in the scan.
- flags: done 59 / refused 22 / missing 22 (23 setter-refusal calls = 22 rows, `autoload` twice; 3 rows keyed by effect: tabling restraint,
  arithmetic, index pseudo-flags). Missing: app_name apple apple_universal_binary argv associated_file bundle color_term emscripten
  hyperlink_term open_shared_object os_argv prolog_debug readline save_history saved_program_class shared_home shared_object_extension
  toplevel_thread version_git windows xpce xref.
- VM instructions: done 159 / missing 74 (done = a `# PORT: pl-vmi.c NAME` marker; B_THROW shows missing because no marker of that name
  exists: by the rule, not a scan bug).
- CROSS-CHECK against ~/code/lk-channel/evidence/R2/missing_c_preds.tsv (461 rows): of its 398 rows unregistered by MY registered set, the
  boot-referenced ones are 208; mine 192 + 16 explained exactly: `!/0` (compiled inline, counted done), `,/2 ;/2 ->/2 *->/2 \+/1` (no PRED
  at the pin, control constructs), `call/1,2,3,8 catch/3 not/1 once/1` (defined by boot/init.pl itself), 3 win_* (platform). Mine-minus-TSV:
  empty. The recount md (194 boot-referenced at 8ba3fae) is 2 more registered since. Library-only: mine 6 (depth-1 library files) vs the
  TSV's 190 (all of library/, LB5, deferred): by design (plan: depth 1).

## Slice 4: NOT STARTED (the next agent). Design decided while reading port_check.jl (tools/port_check.jl, 1210 lines):
- `docs/r2_upstream.tsv`: `r2_snapshot_text(rows, pin)` already exists; `write_inventory` writes it from `r2_pin_c_rows` when a pin
  checkout is found (r2_pin_checkout), else the snapshot is read. Drift check: when a checkout with the pin is found, snapshot must equal
  the scan (R2-UPSTREAM-DRIFT); the block is computed FROM the snapshot so CI checks it with no checkout.
- block in docs/architecture.md right after `<!-- END GENERATED code graph -->` (line ~1778): own heading + markers
  `<!-- BEGIN GENERATED R2 status by tools/port_check.jl --write-inventory — do not hand-edit -->` ... `<!-- END GENERATED R2 status -->`;
  port_check.jl: `include(joinpath(@__DIR__, "r2_status.jl"))` at top level, constants R2_BEGIN/R2_END, in `port_check()` after the
  GRAPH `_block_violations`: `_block_violations("R2-STATUS", architecture, text, r2_render(root), R2_BEGIN, R2_END)` ONLY when
  `isfile(src/pl-inline.jl)` (the kernel's own tree; fixtures of test_port_check have none), and then a missing docs/r2_upstream.tsv is
  R2-UPSTREAM-MISSING; `write_inventory` writes both (the architecture path and the snapshot).
- `docs/r2_owners.tsv` (`key<TAB>owner<TAB>note`, hand-edited, `#` comment lines): keys `pred:`, `flag:`, `vmi:`, `refusal:` exact,
  `cfile:<upstream C basename>` for pred/vmi rows, `kfile:<kernel file basename>` for refusal rows (new: refusal rows have a kernel file);
  exact beats the file keys. NO OWNER = a missing or refused row without owner (counted, information). Violations: R2-OWNER-STALE (key
  matches no row, or only rows that are done/platform), R2-OWNER-DUP, R2-OWNER-BAD (line with < 2 fields). SEED: pred owners from the
  channel TSV column 5 (first step token after `NEW `; the Q10-six/D3 group -> D3; `DEFER to LB5-LB7` -> LB5-LB7; NONE -> no owner),
  vmi A_* -> AR1 (ARITH1), T_*/S_TABLED/S_TRIE_GEN -> TAB1, S_WRAP/S_CALLWRAPPER -> WRAP1, I_CALLCONT/I_SHIFT*/I_RESET/I_YIELD/I_CUTCHP/
  I_EXITRESET -> CONT1, D_BREAK -> DBG1; `kfile:pl-qlf.jl` -> LB3; table_* flags -> TAB1. Everything else prints NO OWNER.
- rendering (`r2_render(root)` in r2_status.jl, uses the snapshot): counts table per category (done / refused / missing / platform /
  NO OWNER), per-boot-file table (`r2_file_table` over `res.preds`), a missing-by-owner list (owner -> count, with the keys folded to
  the first 8), a Mermaid `xychart-beta` (bar = missing per category, line = refused per category).
- Guards, each to be proved by a mutation at VERDICT level and recorded in evidence/R2GEN/guards.md: R2-STATUS-DRIFT (edit a number in the
  block), R2-STATUS-EMPTY / MISSING (generator empty on a tree with no rows; markers removed), R2-UPSTREAM-DRIFT (edit a snapshot line
  with a checkout present), R2-OWNER-STALE (an owners line for a done pred), NO OWNER count > 0 on the real tree AND the same guard
  returns 0 on a fixture where every row has an owner (both sides non-empty through one extractor). Test in test/test_r2_status.jl (or
  test_port_check.jl for the port_check wiring): mutate a copy of the tree under mktempdir.

## KNOWN UNCOMMITTED EDIT TO MAKE FIRST (found at the cap, not applied)
`r2_refusal_rows` `add!`: one refusal row's `step` literal is split over two lines (`"R2 ...; " * newline "no quasi-quotations"`, pl-read.jl:4335),
so `detail`/`label` carry a newline and break a TSV/Markdown row. Squeeze whitespace in the `R2Row("refusal", ...)` call:
`squeeze(x) = replace(x, r"\s+" => " ")` applied to `what` and `step` (the test's expected labels have single spaces, so they stay equal).

## Then (gate agent when a slot is free, after slice 4)
`julia --project=. tools/port_check.jl --write-inventory` (writes the snapshot + both blocks), `tools/warm.sh fmt`, `check`, fast static
pre-check, `tools/pkgtest_way.sh test/test_r2_status.jl` (ONE at a time), branch-gate, crash-term grep (the refusal exception name only via
`R2_REFUSAL_EXCEPTION`, never as one word in text or messages), push gate + mutants (Tier 3: ask the dispatcher). The new test file may need
registering in test/ci_slices.jl / pkgtest_costs.tsv (check what test_type_discipline.jl or runtests.jl require of a new test file).

## Hooks met (not workarounds)
discourage-core-cold-start (use the systemd-run form), no-pipeline-swallowing (redirect), require-codemap-before-capability-grep (use
`# allow-grep-search: <reason>`), no-edit-and-commit-in-one-call (edit and commit in two calls), cap-subagent-context at 150k.
