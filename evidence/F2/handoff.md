# F2 handoff — push_prolog_flag/2, pop_prolog_flag/1 (pl-prologflag.c)

Branch wip/f2 off wip/f1b a946760 (F2 is STACKED on F1b: it uses `set_flag_value`, `new_prolog_flag`, `clean_prolog_flag`,
`check_flag_write_access`, `deletePrologFlag!`, the `pushed` field and `FF_PUSH_ABSENT`, all F1b/F1a). Edit-only writer (WRITER_RULES.md).
Upstream: swipl-devel cbf4e1896275 src/os/pl-prologflag.c, extract in the writer's scratchpad. The sprint row says 1862-1960; the
functions of the area run :1818-1991 (the helpers above the predicates, the pop function to its closing brace).

## Functions of the range (upstream line -> Julia site, all src/os/pl-prologflag.jl unless named)
1. :387 `copy_prolog_flag` (F1b did not write it; push needs it) -> new, next to `clean_prolog_flag`'s neighbours (own section 'push and pop').
2. :1822 `put_saved_flag_value` -> new. Needs `PL_put_float` (src/pl-fli.jl; the kernel has `PL_put_int64`, `PL_put_atom`, not the float put): append it to pl-fli.jl.
3. :1849 `ensure_local_flag` -> new, a DIVERGES: the build is upstream's single-threaded one (`O_PLMT` undefined, file header, design D1): the function is
   `return f` there; the `FF_SHARED` refusal of push (a thread-local rule) is ported as is.
4. :1862 `push_prolog_flag` (PRED_IMPL, flags 0) -> `push_prolog_flag(gd, ld, key, value)` + `pl_push_prolog_flag2_va`.
5. :1929 `pop_prolog_flag` (PRED_IMPL, flags 0) -> `pop_prolog_flag(gd, ld, key)` + `pl_pop_prolog_flag1_va`. Uses `deletePrologFlag!` (F1a, written for it).
6. :3044-3045 registration: two `PL_extension` entries LAST in `PL_predicates_from_prologflag` (upstream order: after `$current_prolog_flag`/5).
`PL_current_prolog_flag` (:1992) is F1a, already there.

## Plan (commits)
1. This plan. 2. `UPSTREAM: pl-prologflag.c copy_prolog_flag put_saved_flag_value ensure_local_flag push_prolog_flag pop_prolog_flag (swipl-devel cbf4e1896275)` with
   PL_put_float and the file-header reword (the header says push/pop are left to F2). 3. rows (generator + driver + .out, test/core_lang/test_push_flag_swipl.jl).
4. tools/mutants/F2.py (>= 8). 5. docs/architecture.md block (appended). 6. manifest block (appended, LAST).

## Decisions
- The refusals of F1b stay: a push/pop of a flag whose side effect is refused by name (debug, encoding, ...) reaches `set_flag_value` and ends in `NotPortedError`, as
  upstream's push reaches that function. The arithmetic/ci_*/tabling-restraint flags are NOT checked by `set_flag_value` (upstream: by `set_prolog_flag_unlocked`), so push on
  them stores the table value only, as upstream does.
- Thread-local table (`register_local_flag`, `LD->prolog_flag.table`): left out; a pushed-absent flag is added to the one table (`entries`/`names`/`slot`, as `set_prolog_flag_unlocked` does).

## State
(none yet)
