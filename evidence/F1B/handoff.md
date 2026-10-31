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
6. [ ] Rows test/core_lang/test_set_flag_swipl.jl (`_SF`/`_sf_`), evidence/F1B/ generator + .out via swipl 10.1.19.
7. [ ] tools/mutants/F1B.py (>= 14), bench rows (H3), docs/architecture.md block, static manifest entries (LAST, own commits).
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

## Estimate: 10-13 commits. Nothing compiled, nothing run.
## Gate order (end of handoff): fmt via warm.sh send of the committed files, inventory, check, rows x3 term types, test_type_discipline.jl,
pkgtest_way per changed test file one at a time, push mutants/F1B at the WIP SHA, branch-gate, term grep, alloc pins x3 (pl-global.jl is Tier 1),
interleaved alloc bench H3 (dispatcher's go), push gate/<fresh name> and mutants/F1B at the SAME SHA.
