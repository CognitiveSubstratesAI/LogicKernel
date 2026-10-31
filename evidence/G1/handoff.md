# G1 — global variables (pl-gvar.c whole), coder 1. Branch wip/g1 off origin/main bf41225.

State: CODED (coder 2 done, 2026-10-31): every file written, NOTHING COMPILED OR RUN (no Julia in this lane). The gates are next; see the last section.
Design: lk-channel evidence/r2/design/flags_rest.md §4 D7/D8, H6-H9, §6 G1 row. Upstream: pl-gvar.c @ cbf4e1896275.

## Plan: function -> upstream -> Julia site
New file src/pl-gvar.jl (included after pl-bag.jl in src/LogicKernel.jl; table `PL_predicates_from_gvar` appended
to `_PRED_TABLES`/`_FOREIGN_VA` in src/pl-ext.jl, upstream's order: after attvar).

| function | upstream | Julia |
|---|---|---|
| table + `grefs` | LD->gvar.nb_vars / .grefs | `ld.gvar_nb_vars::Dict{UInt64,UInt64}`, `ld.gvar_grefs::Int` (pl-global.jl, D7); `ld.gvar_enums` pool for nb_current |
| new_gvar, lookup_gvar | pl-gvar.c:98-125 | `new_gvar!`, `lookup_gvar` |
| PL_getval | :133-141 | `PL_getval` (a term_t) |
| word_is_attvar, setval_duplicate | :153-189 | same names; `duplicate_term` (pl-copyterm.jl, nshare/share NOT PORTED) |
| setval (SETVAL_BACKTRACKABLE/LINK) | :194-262 | `gvar_setval` ; H7: b_setval moves the value into a fresh global cell, freezeGlobal!, TrailAssignment! |
| auto_define_gvar, gvar_value | :272-343 | `auto_define_gvar` (user:exception/3 via PL_call_predicate, D8), `gvar_value` |
| is_gval, getval | :346-395 | `is_gval`, `gvar_getval` |
| nb_setval/nb_linkval/nb_getval/b_setval/b_getval | :398-430 | `pl_nb_setval2_va` ... |
| nb_delete | :436-460 | `pl_nb_delete1_va` |
| nb_current | :464-520 | `pl_nb_current2_va` (REDO_PTR pool `ld.gvar_enums`, keys snapshotted) |
| destroyGlobalVars | :56-63 | NOT PORTED (no thread end); `freeze` already in pl-inline.jl |
| `user:exception/3` dynamic (D8) | boot/init.pl:945 | `setBuiltinPredicateProperties!` (src/pl-ext.jl) |
| query-end release (D7) | — | `_release_frozen!` returns while `gvar_grefs > 0` (src/pl-inline.jl) |
| get_variable_names | pl-comp.c | reads `gvar_value('$variable_names')` when `ld.variable_names == 0` (field stays until LB4) |

## STATE after coder 1 (context cap hit at ~158k while READING; the cap hook then allowed only evidence/ writes)
Committed on wip/g1: b4dafc8 plan; e94e2c5 struct fields (pl-global.jl: gvar_nb_vars, gvar_grefs, gvar_enums; pl-incl.jl: `gvar_enum`;
pl-fli.jl: live_states counts gvar_enums). NOT committed anywhere else: everything below. Nothing run (no Julia).

### Group 2b — WRITTEN BUT NOT IN src/: evidence/G1/pl-gvar.jl.draft
The whole of pl-gvar.c as Julia (all 7 predicates, setval/getval/auto_define_gvar/gvar_value/PL_getval, table PL_predicates_from_gvar).
`git mv evidence/G1/pl-gvar.jl.draft src/pl-gvar.jl` (hook for a new src file wants a reference read first: read
workflows/DEVZONE_INDEX.md head, clears it for 2h), then the edits below. Still to do for the source:
1. src/LogicKernel.jl: `include("pl-gvar.jl")   # swipl-devel src/pl-gvar.c — global variables: b_setval, nb_setval, nb_current …` after the pl-bag.jl line.
2. src/pl-ext.jl: add `PL_predicates_from_gvar` at the END of `_PRED_TABLES` and `_FOREIGN_VA` (upstream: after attvar; also the
   comment above `_PRED_TABLES`). Check how `_FOREIGN_DET`/dispatch trees count entries (generated; should follow the tuples).
3. src/pl-copyterm.jl: add `duplicate_term(ld, in::term_t, copy::term_t)::Bool = copy_term_refs(ld, in, copy, cp_options(COPY_ATTRS))`
   (# PORT: pl-copyterm.c duplicate_term; DIVERGES: no nshare/share) and call it from `pl_duplicate_term2_va` (upstream does).
4. src/pl-ext.jl `setBuiltinPredicateProperties!`: D8 — `setDynamicDefinition!(lookupProcedure(mk_sym(T, :exception), 3,
   MODULE_user(gd)).definition, true)` (boot/init.pl:945 `:- dynamic user:exception/3`, before init.pl is loaded).
5. src/pl-inline.jl `_release_frozen!`: D7 — return early while `ld.gvar_grefs > 0` (add to the first `&& return nothing` test), and
   rewrite the comment above it (the "REVISIT when nb_setval/b_setval are ported" sentence is now done: GOES with the collector).
6. src/pl-comp.jl:3157 (`ld.variable_names != 0`): ALSO read `gvar_value(ld, atom word of '$variable_names')` when the field is 0
   (field stays until LB4, sprint Q5). The word is a ref (b_setval: location unRef(w)) or a compound word (nb_setval: put it in a
   fresh global cell with allocGlobalCells!, `ld.gstack[p] = w`, then `export_cells(ld, ex, p)` — a positive location is a cell).
   Update pl-comp.jl's "DIVERGES: `$variable_names` is not a global variable here" comment (~line 3150-3156) and the PL_local_data
   comment lines ~316-320 in pl-global.jl ("the kernel has no global variables"). KEEP IT SMALL; if unsure, skip item 6 and FLAG it.
7. FLAGS to carry in the report: (a) duplicate_term shares nothing with the old value (nshare/share NOT PORTED; identity-only);
   (b) vword (float/string/bigint) counts as "on the global stack" for freeze/grefs (`_gvar_on_global`); (c) `nb_current` order is
   insertion order of the table, upstream's is hash order (rows sort); (d) auto_define_gvar keeps upstream's `rc = PL_get_atom_ex()`
   quirk (an answer other than retry/fail = retry, so the hook runs twice, then existence_error); (e) nb_delete on an EMPTY table
   does nothing (upstream: NULL table) — an empty `ld.gvar_nb_vars` stands for NULL; (f) b_setval over a nb_setval'ed unbound
   variable binds that variable (upstream quirk, `swipl: nb_setval(k,X), b_setval(k,1)` gives X = 1) — kept; add a row.

### Sizing (D-0272 item 7): expected gated commits for the whole step ~ 9-10:
 struct fields (done), pl-gvar.jl + ext/include/copyterm/pl-inline/pl-comp edits (2: source, hook+release), rows generator+driver+.out+test (2),
 mutants/G1.py (1), architecture.md + manifest (2, LAST), handoff (1) => about 10. Under the ~12 limit; no re-plan needed.

### Oracle facts measured with swipl 10.1.19 (for the rows)
- `nb_setval(k,X), X=1, nb_getval(k,V)` -> V = 1 (an unbound variable is SHARED by nb_setval); `(nb_setval(k,X), X=1, fail ; nb_getval(k,V))` -> V unbound.
- `nb_setval(k,X), b_setval(k,1)` -> X = 1.   `b_setval(k,1), b_setval(k,f(Y)), b_getval(k,Z)` -> Z = f(_).
- (rows to write: design FLG §6 G1 + H6-H9; the C source is /tmp-free: `git -C ~/dev-zone/swipl-devel show cbf4e1896275:src/pl-gvar.c`.)

### Still to do after the source (steps 4-7 of the brief)
rows (test/core_lang/test_gvar_swipl.jl, gen_rows.py, driver, .out; see test_at_body_swipl.jl's first 80 lines), tools/mutants/G1.py (>= 8, aim 15-25,
TARGETS includes test_gvar_swipl.jl and every file exercising nb_/b_ gvars, `_release_frozen!`, duplicate_term: test_copy_term*, test_unify*, the toplevel/exception tests that
hit `_release_frozen!`), docs/architecture.md G1 section + test/static_analysis_manifest.jl LAST, gate order as in the brief.

## STATE after coder 2 (all committed on wip/g1; nothing pushed; nothing run)
Commits, oldest first: 3bdb02a pl-gvar.jl moved into src/ and included; 53362fe `PL_predicates_from_gvar` in `_PRED_TABLES`/`_FOREIGN_VA`;
168119c `duplicate_term` in pl-copyterm.jl; 8c0e656 D8 (`user:exception/3` dynamic in `setBuiltinPredicateProperties!`);
109b78d D7 (`_release_frozen!` returns while `gvar_grefs > 0`); 83c27dc test_gvar_swipl.jl (56 rows) + evidence/G1/gen_rows.py,
gvar_driver.pl, gvar_rows.pl, gvar_rows.out; 9d85b81 the h9 database row (evidence/G1/h9_*); 0dc6a93 row g57; a637ae1
tools/mutants/G1.py (20 mutants, anchors counted once by a python checker); 3e9edf4 docs/architecture.md G1 section; 22a200f the
static-analysis manifest block.
- Rows: g01-g57 + h9, ALL pinned from swipl 10.1.19; the kernel's answers are UNRUN. UNVERIFIED on the kernel (gate decides):
  g15 (cyclic value), g25 (the full ball, context term), g35 (`string_codes/2` is T1's), g42 (an attributed variable value, needs
  `put_attr`/`get_attr` as the file's helper `gv_dom:attr_unify_hook/2` clause), g52 (`atom_concat/3` mode (+,+,-)); the hook
  clauses are `user:exception(...)` clauses in the consulted program (needs the loader to accept `M:Head :- Body`).
- Item 6 (pl-comp.jl:3157 reading `'$variable_names'` as a global variable) is NOT DONE: not a 3-line edit (the word is a ref or a
  compound word that must be exported into a cell_export); `ld.variable_names` stays until LB4; comment lines in pl-comp.jl
  (~3150) and pl-global.jl (~316-320) still say the kernel has no global variables: refresh them with that edit.
- Flags a-f are in the architecture section. Mutant gaps recorded in tools/mutants/G1.py: `_gvar_on_global`'s `_is_vword` half and
  nb_delete's `gvar_grefs -= 1` have no row (a white-box `gvar_grefs` check after `nb_setval(k, 1.5), nb_delete(k)` would kill them).
- docs/port_inventory.md is generated (pl-gvar.c currently lists pl-inline.jl only): regenerate it in the inventory step.
- The mutant ids' KILL lists are best guesses by row, not run.

## GATE ORDER (next agent, a Julia lane)
fmt (format the committed files through `warm.sh send`; fmt sees only the HEAD diff, so run it after the last commit and commit the
result), inventory (port_inventory.md), check (incl. the Pkg.test-way run: `tools/pkgtest_way.sh test/core_lang/test_gvar_swipl.jl`),
rows x3 term types (`warm.sh file test/core_lang/test_gvar_swipl.jl`, then the two others), `test/test_type_discipline.jl`,
push `mutants/G1` at the WIP SHA, branch-gate, term grep over diff and messages, alloc pins x3 (STRUCT CHANGE: a ~30 min cold
compile), then the gate push on a fresh name (`gate/g1` + `mutants/G1` at the SAME SHA). Main takes NO merge commits.
Likely first-run fixes: the draft was never compiled (type names, `_slot_new_var!`-style helpers, `PL_retry_address`,
`alloc_foreign_state!`/`free_foreign_state!` signatures, `_deref_loc`, `_value_word!`, `_is_side_word`).
