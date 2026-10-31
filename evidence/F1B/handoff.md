# F1B handoff — set_prolog_flag, create_prolog_flag/3, set_flag_value (pl-prologflag.c), the mask migration

Branch wip/f1b off main faee65f. Edit-only writer (WRITER_RULES.md). Design: evidence/r2/design/flags_rest.md (this channel)
D3 (mask), D4 (unported side effects refused by name), D5, D6 (per-module writes), H3 (bench), H4, H5, section 6 rows.
Upstream: swipl-devel cbf4e1896275 src/os/pl-prologflag.c (extract in the writer's scratchpad).

## What F1a left (read in src/os/pl-prologflag.jl, src/pl-incl.jl)
- Table, `setPrologFlag` (define side, per type), `lookupFlag`, `unify_prolog_flag_value/_access/_type`, `pl_prolog_flag5`, `initPrologFlags!`,
  `truePrologFlag(ld, PLFLAG_X)`, mask `ld.prolog_flag_mask::UInt64` (bit flag-1) copied from `gd.prolog_flag.mask`. PLFLAG_ISO and
  PLFLAG_RATIONAL are ALREADY mask reads (pl-arith.jl, pl-read.jl, pl-prims.jl, os/pl-option.jl). `deletePrologFlag!` exists for F2.
- STILL STAND-INS (F1b deletes them): local-data Bool fields `prolog_flag_last_call`, `_portable_vmi`, `_optimise`, `_optimise_unify`,
  `_character_escapes_unicode` (src/pl-global.jl:371-374, 459) read by `_prolog_flag_bit` (os/pl-prologflag.jl:129) and by pl-comp.jl
  (658, 680, 1900, 2166, 2181, 2223, 2238, 2409, 3168), pl-wam.jl (3311, 3352, 3546, 3908), pl-write.jl (2223, 2292); and
  `prolog_flag_determinism_error::Symbol` (pl-comp.jl:5361, pl-wam.jl:610; upstream reads the table with PL_current_prolog_flag);
  `print_write_options` = `_print_write_options` (pl-write.jl:2384-2404). Tests that write the fields: test/compile/test_body_code_swipl.jl
  (874, 958, 1165, 1177, 1286, 1675, 2050, 2241), test_portable_smallint_swipl.jl (11, 20, 43), test/core_lang/test_det_swipl.jl (121, 280),
  test_firstvar_swipl.jl:133, test_head_unify_swipl.jl:507, test_rules_swipl.jl (1889-1907), test/foreign/test_exceptions_swipl.jl (120-123),
  test_prolog_flag_swipl.jl:568-570 (reads), test_write_cells.jl.
- D6 / M1: `module_t` is a MUTABLE struct (MOD1) with `flags::UInt32` and `var_prefix::Int` writable in place: per-module writes work as D6 needs.
  `var_tag` has no module bits (file header of os/pl-prologflag.jl): `set_prolog_flag(var_tag, V)` is refused by name until the modules area adds them.
- `setUnknown` (pl-prologflag.c:576) is not in the kernel (only `getUnknownModule`, pl-modul.jl:342).

## Groups (upstream pl-prologflag.c line -> Julia site, all in src/os/pl-prologflag.jl unless named)
1. [x] Setters :494-960 WRITTEN (section 'setting a flag: the value setters' of os/pl-prologflag.jl, before 'the predicates'): `_flag_not_ported(key, effect)`
       (throws NotPortedError{T}(key, effect, "R2 F1b")), `_flag_atom_ref`, setRationalSyntax, var_prefix_code, get_var_prefix_ex, setVarPrefix,
       setUnknown(gd, ld, value, a, m), setUnknownOption, checkOnError, setWriteAttributes, setAccessLevelFromAtom, getOccursCheckMask, setOccursCheck,
       setStreamTypeCheck. NOT written (group 2 calls `_flag_not_ported` for them, D4): setVarTagFlag, setIncomparable (no `incomparable_error` field),
       setEncoding, setUnicodeAtoms, setAutoload, setTheme, file_name_case_handling. The header comment lists the D4 set.
2. [x] WRITTEN (coder 2; section 'changing a flag' of os/pl-prologflag.jl, before 'the predicates'): `PseudoFlag`/`PSEUDO_FLAG`, `FF_COPY_FLAGS`,
       create_oneof, set_oneof, check_oneof_flag (builds error(domain_error(oneof(L),A),_)), set_flag_type, set_flag_atom, clean_prolog_flag, keep_flag
       (answers Int 1/0/-1 as upstream), new_prolog_flag, set_flag_value(gd, ld, f, m::module_t, k, value); `setPrologFlagMask!`/`clearPrologFlagMask!` (next to
       truePrologFlag); `PL_get_int64` (pl-fli.jl, = PL_get_long) and `PL_get_int64_ex` (pl-error.jl, representation_error(int64_t), probed on swipl 10.1.19).
       D4 refusals in set_flag_value: debug, debugger_show_context, threads(true), tty_control(changed), debug_on_interrupt, var_tag, incomparable, encoding,
       unicode_atoms, file_name_case_handling, autoload, table_monotonic, theme, agc_margin, table_space, table_compile_threshold, table_drop_intermediate,
       stack_limit, string_stack_tripwire, heartbeat. on_error/on_warning are checked and STORED (no side effect upstream either). The header list of D4 flags
       was corrected. Not guarded by the refusals but NOT ported: arithmetic (`set_arith_flag`), ci_*, tabling restraint: group 3 refuses them by name.
3. [x] WRITTEN (coder 2; same section): tbl_is_restraint_flag, check_flag_write_access, check_create_flag, set_prolog_flag_unlocked, set_prolog_flag_ptr,
       set_prolog_flag(gd, ld, key, value, flags), pl_set_prolog_flag2_va, `prolog_flag_options`, pl_create_prolog_flag3_va; registered first in
       PL_predicates_from_prologflag (upstream order; create_prolog_flag with flags 0 as PRED_DEF). Pseudo flags (arith, ci_*, tabling restraints) and
       `autoload` are refused by name. FINDING (audit): at the pin, `set_prolog_flag(user_flags, error), set_prolog_flag(newkey, 1)` ends in fatal signal 11
       in swipl 10.1.19 (set_prolog_flag_unlocked :1665 continues after the if chain with f == NULL); the kernel returns at once after the existence_error.
       The source comment is neutral (private register: upstream defect to enter; the term-grep words are not used).
4. [x] DONE (coder 3, cdf1b9e, AFTER group 5 so every commit loads; src/pl-global.jl only) STRUCT COMMIT (ONE separate commit, src/pl-global.jl struct + constructor + every site that builds it): delete the 5 Bool fields and
       `prolog_flag_determinism_error` (no field is appended: F1b needs none). Stack owner hand-merges with G1/O1B at the top.
       Gate: ~30 min cold compile, alloc pins x3.
5. [x] DONE (coder 3, dcd07b0, BEFORE group 4): pl-comp.jl 9 sites, pl-wam.jl 4, pl-write.jl 2 now `truePrologFlag(ld, PLFLAG_*)`; `determinism_error_flag(ld)` (pl-prologflag.jl, returns :error/:warning/:silent, :error without ld.GD) in det_goal_error/determinism_error; print/2 reads the table's print_write_options (PL_current_prolog_flag :term) and takes `_print_write_options` where the table has none; `_prolog_flag_bit` and its manifest line deleted; 8 test files migrated (test_det_swipl sets the table entry `.a`). Migration of the ~25 sites above to `truePrologFlag(ld, PLFLAG_*)`, `_prolog_flag_bit` deleted, determinism_error and print_write_options read the
       table; tests that set the fields call `setPrologFlagMask!`/`clearPrologFlagMask!` (helpers, new).
6. [x] DONE (coder 3, a12adc9; refused list c5f0c73). Rows test/core_lang/test_set_flag_swipl.jl (`_SF`/`_sf_`), evidence/F1B/ generator + .out via swipl 10.1.19.
7. [x] DONE (coder 4: F1B.py 4a1822b, anchors 6d205c4, bench 1cb839f, docs 20b1e01, manifest = the LAST commit). tools/mutants/F1B.py (>= 14), bench rows (H3), docs/architecture.md block, static manifest entries (LAST, own commits).
F2 (pl-prologflag.c 1862-1960) afterwards as its own group: evidence/F2/.

## State at hand-back (writer 1, ran out of context after group 1)
- Committed: plan 450b654, group 1 (next commit). Upstream is extracted by `git -C ~/dev-zone/swipl-devel show cbf4e1896275:src/os/pl-prologflag.c` into your scratchpad;
  read :1126-1523 (keep_flag, new_prolog_flag, set_flag_value) next, then :1542-1810. Group 2 must ALSO port `check_oneof_flag`, `set_oneof`, `clean_prolog_flag`
  (find them with awk for the function starts: they are above :1126 and not yet read).
- APIs verified: errors `PL_error(ld, ERR_DOMAIN|ERR_TYPE|ERR_EXISTENCE, atom::T, term_t)`, `PL_error(ld, "", 0, "", ERR_PERMISSION, action::T, type::T, obj::term_t)`,
  `PL_error(ld, ERR_INSTANTIATION)`, `PL_domain_error(ld, "name", t)`, `PL_type_error`; `printMessage(ld, :warning, msg_term_ref)`; `PL_get_atom_ex(ld, t)`.
- D6 answer: `module_t` is mutable (pl-incl.jl:831), `m.flags` and `m.var_prefix` are writable in place.
- Unverified (never compiled): everything.

## State at hand-back (coder 2, forced by the 150k cap after group 3)
- Committed: group 2 = 2c3a78e. Group 3 code is in src/os/pl-prologflag.jl (section 'set_prolog_flag/2 and create_prolog_flag/3'), committed with this handoff if the
  commit hook allowed it; check `git log`. Left for the next agent: (a) the file header of src/os/pl-prologflag.jl lines 15-17 still says the write side is not ported:
  reword it positively (F1b has the write side; push/pop_prolog_flag are left to F2; the flags' threading is left out); (b) groups 4-7 as listed above.
- Decisions taken: finding 4 of coder 1 (incomparable): uniform D4 refusal by name (`setIncomparable` refused: no `incomparable_error` field). Arithmetic flags
  (set_arith_flag), ci_* and tabling restraints are refused by name as well (not in coder 1's list; the audit may ask for `set_arith_flag` as a small follow-up
  since `set_prolog_flag(float_overflow, infinity)` is common). `debugger_show_context`/`threads(true)` are refused too.
- D-0280 item 5: F1b's checklist: D1-96 (the SSU-flag argument: the term is built by _rule_term from the clause's own flags, pl-comp.jl:3506-3516) and D1-95
  (protected_predicate true only for P_FOREIGN) are RE-CHECKED when F1b turns protect_static_code/iso on. The new code makes protect_static_code settable
  (set_flag_value: true sets the mask bit PLFLAG_PROTECT_STATIC_CODE; false after true raises permission_error(set, prolog_flag, protect_static_code)) and iso
  settable (mask bit PLFLAG_ISO). The next agent: read tools/mutants/D1.py D1-95/D1-96, grep the readers of PLFLAG_PROTECT_STATIC_CODE (clause/2, listing,
  protected_predicate) and give each a kill row in group 6 (set the flag, then clause/2 on a static predicate; iso on, then a rule with an SSU head) if reachable.
- Stack owner: the mask fields are NOT appended, F1b DELETES fields (group 4): hand-merge src/pl-global.jl against G1 and O1B at the top.
- Hook notes: the commit hook that scans for absence claims fires on the words 'unported'/'NOT PORTED' in the COMMAND text and message; use 'refused by name', 'left to'.
  The cap hook (150k) blocks Edit outside evidence/: the context of this agent was ~150k at group 3, not 100k (the file reads were large).
- FINDINGS for the audit: (1) swipl 10.1.19 ends in fatal signal 11 on `set_prolog_flag(user_flags, error), set_prolog_flag(newkey, 1)`: pl-prologflag.c:1665 continues with
  f == NULL after check_create_flag fails; for the private register, a neutral marker in the source. (2) `PL_get_int64`/`PL_get_int64_ex` were added to pl-fli.jl/pl-error.jl
  (two small appends; a conflict with another writer adding them is possible). (3) create_prolog_flag is registered with flags 0 (PRED_DEF), though PRED_IMPL says PL_FA_ISO.
- UNVERIFIED: everything (nothing compiled). Specific doubts: `PL_record(ld, t)` return value for a term with attributed variables; `PL_scan_options` OPT_TERM value type
  (Int term_t, 0 for none, as pl-read.jl uses it); `ground_cells(ld, -(t+1)) != 0` as `!PL_is_ground`; `put_oneof` is used in `check_oneof_flag` with a fresh term_t.

## State at hand-back (coder 3)
- Commits: bff248a header fix, dcd07b0 group 5, cdf1b9e group 4. Left: groups 6, 7 (this file is updated after each).
- tools/mutants/MOD3a.py, SSU1.py, V9f.py have `old` anchors on the deleted field names: they need a re-fit at their next run (the audit decides; those steps are landed).
- For the audit (not decided): uniform D4 refusal of incomparable; arithmetic/ci_*/tabling flags refused by name (set_arith_flag follow-up suggested: float_overflow etc. are common); PL_get_int64/PL_get_int64_ex appended in pl-fli.jl/pl-error.jl (merge conflict risk); the swipl 10.1.19 case in the private register as Q15 (no public mention).
- UNVERIFIED (nothing compiled): `ld.GD` Union field access in the new helper (type-stable small union); PL_current_prolog_flag(gd, ld, name, opts) in pl_print2 with a fresh term_t; the test edits.

## State at hand-back (coder 3, second part: group 6 written, UNCOMMITTED until the commit below; forced by the 150k cap)
- Group 6 files: test/core_lang/test_set_flag_swipl.jl (GENERATED: rows sf01-sf89, 78 cases; pins filled), evidence/F1B/{sf_cases.json (the case table),
  sf_template.jl (the test's fixed text), build_sf_test.py (cases + template -> test file), gen_sf_rows.py (builds the program file as the test does, runs swipl 10.1.19
  twice under `timeout 20`, requires byte-identical, writes sf_rows.out and the pins into the test file)}. To change a row: edit sf_cases.json, then
  `python3 -I evidence/F1B/build_sf_test.py evidence/F1B/sf_cases.json test/core_lang/test_set_flag_swipl.jl && python3 -I evidence/F1B/gen_sf_rows.py`.
  The user_flags=error + new key case is in NO swipl row (swipl 10.1.19 does not answer it); the test pins the kernel's existence_error in its own testset.
- TO DO FIRST (found by the last probe, not yet applied): the `_SF_REFUSED` list in sf_template.jl has values that swipl may reject before the refusal is reached
  (the kernel checks oneof BEFORE refusing): `file_name_case_handling` must be `case_sensitive` (not `sensitive`), check `var_tag`, `incomparable`, `table_monotonic`,
  `encoding` values with swipl 10.1.19 (`timeout 20 swipl -q ref.pl`, ref.pl as: `t(F,V)` facts, `catch((current_prolog_flag(F,Old), set_prolog_flag(F,V)), error(E,_), ...)`);
  then rebuild with the two commands above. Also check each swipl answer in sf_rows.out that is a success with an unbound R (none left except by design).
- Rows swipl showed: `set_prolog_flag(max_integer,1)` SUCCEEDS in swipl (row sf02 now uses `pid`, read-only: permission_error(modify,flag,pid) is expected: the
  pin was regenerated); `set_prolog_flag(user_flags, foo)` succeeds (sf76 pins the read-back); `create_prolog_flag` of a term flag requires a GROUND value
  (sf78 pins instantiation_error); the per-module row (set_prolog_flag(zz_mod:double_quotes, codes)) was dropped: swipl answered string for both reads (not informative);
  a per-module row needs a consulted module file: left to the next agent or the audit.
- D1-95 kill rows: sf80 (clause/3 by reference of a static clause under iso: permission_error(access,private_procedure,sp/1)), sf81 (clause/2 head path), sf82 (dynamic
  not protected under iso), sf84 (control: iso toggled back, reference answers), sf85-sf89 (protect_static_code: sf86 permission_error, sf87 dynamic fine, sf88 set false ->
  permission_error(set,prolog_flag,protect_static_code)). D1-96: sf83 (by-reference SSU clause: ssd(1)-true) pins the unchanged answer; the equivalence argument of D1c.py
  (clause type from the clause's own flags, src/pl-comp.jl:3506-3516) does not depend on iso/protect_static_code: PLFLAG_ISO is read in pl-comp.jl only by protected_predicate
  (:3571), so D1-96 STAYS equivalent (record this in F1B.py's header).
- STILL TO DO: (a) the comment of protected_predicate (src/pl-comp.jl:3560-3563) says "nothing sets them yet (R2 F1b)": reword positively (F1b makes them settable); own commit.
  (b) group 7: tools/mutants/F1B.py (>= 14; TARGETS: test_set_flag_swipl.jl, test_prolog_flag_swipl.jl, test_det_swipl.jl, test_body_code_swipl.jl, test_portable_smallint_swipl.jl,
  test_rules_swipl.jl, test_firstvar_swipl.jl, test_head_unify_swipl.jl, test_exceptions_swipl.jl, test_write_swipl.jl; ideas: set_flag_value mask write dropped for bool; the
  protect_static_code false-after-true permission test; check_flag_write_access read-only test; keep_flag; check_create_flag's error branch; determinism_error_flag silent/warning
  branches (rows in test_det_swipl.jl); truePrologFlag reads at pl-comp.jl 658/680/1900/2166/2223/2409/3168, pl-wam.jl 3311/3352/3546/3908, pl-write.jl 2223/2292; oneof domain
  error; int64 conversion), validated by a throwaway python3 -I script; tools/mutants/MOD3a.py, SSU1.py, V9f.py anchor on the deleted field names (re-fit at their next run);
  bench rows H3; docs/architecture.md block; manifest entries for the new functions (determinism_error_flag etc.), each its own LAST commit.
- FINDINGS for the audit: (1) new engines start from the DATABASE's mask (`gd.prolog_flag.mask`), while set_flag_value writes the engine's mask only; upstream copies the creating
  thread's mask: a second engine created after `set_prolog_flag(last_call_optimisation, false)` sees the default (design H5): decide whether set_flag_value also writes gd's mask.
  (2) `print/2` reads the table's print_write_options where present, else the default. (3) the refused-by-name list (D4) now also holds float_overflow, tabling restraints, ci_*.
  (4) uniform D4 refusal of incomparable; PL_get_int64/PL_get_int64_ex appended in pl-fli.jl/pl-error.jl (merge-conflict risk); swipl crash case: private register Q15 only.
- UNVERIFIED (nothing compiled or run): the whole test file (generated Julia; `_sf_query` runs a query and lets NotPortedError propagate), the migrated tests, `ld.GD` in
  determinism_error_flag.

## State at hand-back (coder 4: groups 6 fix, 7, bench, docs, manifest; everything written, NOTHING compiled or run)
- Commits: c5f0c73 `_SF_REFUSED` (swipl 10.1.19 probed: `file_name_case_handling` is READ-ONLY, permission_error(modify,flag,...) in swipl and in the
  kernel (FF_READONLY at pl-prologflag.jl:1646) so it has no refusal row; var_tag dict, unicode_atoms error, table_monotonic lazy are values swipl accepts; the kernel
  defines no built-in oneof, so no value is rejected before the refusal; 22 flags left; sf_rows.out unchanged), 38d2a4d protected_predicate comment,
  4a1822b tools/mutants/F1B.py (23 mutants, every `old` once, validated by a throwaway runpy checker), 1290268 boot/init.jl:206 (see finding 9), 6d205c4 anchors
  of MOD3a-D2, SSU1-D2, V9f MD12/MD14, 1cb839f bench row "divide x1000, body" (tools/bench.jl, DV_PROLOG), 20b1e01 docs/architecture.md, then the manifest commit.
- Finding 9 (FIX applied, 1290268): boot/init.jl:206 still read the deleted field `ld.prolog_flag_optimise` (group 5 migrated src/ only). Now `truePrologFlag(ld, PLFLAG_OPTIMISE)`.
  A scoped grep of src/*.jl, src/*/*.jl, boot/*.jl, test/*.jl, test/*/*.jl, tools/*.jl for the six deleted field names is clean afterwards.
- Finding 10: anchors that do not occur in the current source for reasons OTHER than the deleted fields (older drift; not touched, the audit decides): MOD3a-S1, MOD3a-S2,
  SSU1-R4, SSU1-S1, V9f MK4, MK16, MK22, MD7, MD21. D1.py is not in tools/mutants at this base (only D1c.py).
- F1B.py header lists what is left out: pl-write.jl:2223/2292 (no test row clears the character_escapes_unicode bit), pl-comp.jl:2409 (compileArith refusal under optimise),
  `if f.index != 0`, setStreamTypeCheck/setWriteAttributes field writes (rows read the table, not the field). Equivalents: none; D1-96 stays equivalent (header text).
- UNVERIFIED: the Julia text of the bench row (`_nrf(:is, ...)`, `Symbol("/")`), every manifest entry's argument types (control_t{T} for the pl_*_va entries, `LK.oneof_t{T}`
  for the Union{Nothing, oneof_t{T}} arguments; `Int` for term_t), whether `PseudoFlag` and the implicit constructors need entries, every mutant's `new` compiles.
- Finding 7 (audit): D-0280 item 5 closed in writing (header of F1B.py): D1-96 equivalent, D1-95 killed by sf80-sf86. Findings 1-8 above stand for the audit.

## GATE ORDER (F1b)
1. Merge order: rebase wip/f1b onto the stack; src/pl-global.jl is a HAND MERGE (F1b DELETES six fields from `PL_local_data` and its constructor; G1, D2, O1B append
   at the end); docs/architecture.md and test/static_analysis_manifest.jl take appended blocks from each writer (manifest: F1b's block sits before "R2 S1", the others at the end).
2. fmt: `tools/warm.sh send` of the committed files (fmt only sees the HEAD diff): src/os/pl-prologflag.jl, src/pl-global.jl, src/pl-comp.jl, src/pl-wam.jl, src/pl-write.jl,
   src/pl-fli.jl, src/pl-error.jl, boot/init.jl, tools/bench.jl, the migrated tests, test/core_lang/test_set_flag_swipl.jl, test/static_analysis_manifest.jl.
   After fmt re-fit the F1B.py anchors that were re-flowed (the checker: old once, new != old).
3. inventory, then `tools/warm.sh check`.
4. Rows on all three term types: test_set_flag_swipl.jl and the 8 migrated files (test_body_code_swipl, test_portable_smallint_swipl, test_det_swipl, test_firstvar_swipl,
   test_head_unify_swipl, test_rules_swipl, test_exceptions_swipl, test_prolog_flag_swipl; test_write_cells.jl if it writes a removed field).
5. test/test_type_discipline.jl.
6. `tools/pkgtest_way.sh <file>` ONE at a time (~3 GB peak) for test_set_flag_swipl.jl and each of the 8 migrated files.
7. Alloc pins x3 (Tier 1: pl-global.jl and the run loop changed).
8. Push `mutants/F1B` at the WIP SHA once the list exists (it does); the older lists' batteries on the migrated sites: MOD3a, SSU1, V9f, D1c, D1 (the batteries run at the gate).
9. branch-gate; the term grep (D-0164, over diff and message); H3 bench with the DISPATCHER'S GO only (interleaved, allocations decide; row "divide x1000, body" plus
   nreverse/qsort/derive for the LCO/optimise reads); then `gate/<fresh name>` and `mutants/F1B` at the SAME SHA.

## Estimate: 10-13 commits. Nothing compiled, nothing run.
## Gate order (end of handoff): fmt via warm.sh send of the committed files, inventory, check, rows x3 term types, test_type_discipline.jl,
pkgtest_way per changed test file one at a time, push mutants/F1B at the WIP SHA, branch-gate, term grep, alloc pins x3 (pl-global.jl is Tier 1),
interleaved alloc bench H3 (dispatcher's go), push gate/<fresh name> and mutants/F1B at the SAME SHA.
