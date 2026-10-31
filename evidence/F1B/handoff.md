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
2. [ ] keep_flag, check_oneof_flag, new_prolog_flag, set_flag_value :1126-1523 (D4 refusals: NotPortedError naming the side effect).
3. [ ] check_flag_write_access, check_create_flag, set_prolog_flag_unlocked, set_prolog_flag_ptr, set_prolog_flag/2, create_prolog_flag/3 :1542-1810; registration.
4. [ ] STRUCT COMMIT (ONE separate commit, src/pl-global.jl struct + constructor + every site that builds it): delete the 5 Bool fields and
       `prolog_flag_determinism_error` (no field is appended: F1b needs none). Stack owner hand-merges with G1/O1B at the top.
       Gate: ~30 min cold compile, alloc pins x3.
5. [ ] Migration of the ~25 sites above to `truePrologFlag(ld, PLFLAG_*)`, `_prolog_flag_bit` deleted, determinism_error and print_write_options read the
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

## Estimate: 10-13 commits. Nothing compiled, nothing run.
## Gate order (end of handoff): fmt via warm.sh send of the committed files, inventory, check, rows x3 term types, test_type_discipline.jl,
pkgtest_way per changed test file one at a time, push mutants/F1B at the WIP SHA, branch-gate, term grep, alloc pins x3 (pl-global.jl is Tier 1),
interleaved alloc bench H3 (dispatcher's go), push gate/<fresh name> and mutants/F1B at the SAME SHA.
