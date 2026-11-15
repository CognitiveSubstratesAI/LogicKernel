# PRIMS-C handoff (lane clone ~/code/lk-primsc, branch wip/prims-c, base c1c104f4)

Step: write the pl-prims.c predicates listed in the brief. Edit-only (no julia run). Upstream text: swipl-devel
18168e62 src/pl-prims.c (scratch copy outside the worktree: the scratchpad's pl-prims.c, re-made with
`git -C ~/dev-zone/swipl-devel show 18168e62:src/pl-prims.c`).

## Status of the predicates (src/pl-prims.jl)

Written in the working tree (committed with this handoff; read the diff):
- nonground/2            `pl_nonground2_va`   (after `pl_ground1_va`)
- functor/4              `pl_functor4_va` + `match_functor_type` (after `pl_functor3_va`)
- $filled_array/4        `pl_filled_array4_va`  (after `pl_compound_name_arguments3_va`)
- $unbind_template/1     `pl_unbind_template1_va` (same place)
- $is_char_code/1, $is_char/1, $is_code_list/2, $is_char_list/2
                         `is_code`, `is_char`, `is_text_list`, `pl_is_char_code1_va`, `pl_is_char1_va`,
                         `pl_is_code_list2_va`, `pl_is_char_list2_va` (after `pl_char_code2_va`)

STILL TO WRITE (the edit that was blocked by the context cap):
- collation_key/2 `pl_collation_key2_va`, to go right after `pl_atom_number2_va` (before the comment
  `# PORT: pl-prims.c concat`). Plan: `PL_get_text(ld, A1, CVT_ATOM|CVT_STRING|CVT_EXCEPTION)`, code points via
  `_text_code_points`, a NUL-ended `Vector{Cwchar_t}`, libc `wcsxfrm` through
  `ccall((:wcsxfrm, LIBC), Csize_t, (Ptr{Cwchar_t}, Ptr{Cwchar_t}, Csize_t), o, s, buflen)` (LIBC is in src/os/pl-os.jl),
  buffer 256, first retry buflen = n+1, later ones doubled (upstream loop, pl-prims.c ~4734-4768); result:
  `utf8_put_char(b, c)` per key char, `PL_chars_t(b, n, ENC_UTF8, false)`, `PL_unify_text(ld, A2, 0, key, PL_STRING)`.
  DIVERGES lines: `(size_t)-1` return fails; a key char that is no code point (`VALID_CODE_POINT`) is a
  `NotPortedError{Nothing}(nothing, "collation_key/2 with a key that is no code point", "owner CT1: the locale step")`.
  The "C" locale is the identity, so the pinned rows set `setlocale(collate, _, 'C')` first and restore.

## Registration (not done)
Insert into `PL_predicates_from_prims` (src/pl-prims.jl, around line 4900 now) in upstream's order, flags `PL_FA_VARARGS`
(PRED_DEF flag 0 for all nine):
- `nonground`/2 after `ground`/1 and before `$term_size`/3
- `functor`/4 (`pl_functor4_va`) after `functor`/3 and before `=..`
- `$filled_array`/4, `$unbind_template`/1 after `compound_name_arguments`/3 and before `numbervars`/4
- `$is_char_code`/1, `$is_char`/1, `$is_code_list`/2, `$is_char_list`/2 after `char_code`/2 and before `atom_number`/2
- `collation_key`/2 after `atom_number`/2 and before `statistics`/2
Update the table's DIVERGES comment only if needed. Dispatch indices are computed from the table order
(`registerBuiltins!`), no constant to edit in src; a test that pins a count of built-ins (boot image constant, the R2 status
tables docs/r2_upstream.tsv) may need the dispatcher's regeneration.

## Manifest (not done) test/static_analysis_manifest.jl
Add to the list at ~line 1722 (the `Tuple{LD, Int, Int, LK.control_t{T}}` comprehension): `LK.pl_nonground2_va`,
`LK.pl_functor4_va`, `LK.pl_filled_array4_va`, `LK.pl_unbind_template1_va`, `LK.pl_is_char_code1_va`,
`LK.pl_is_char1_va`, `LK.pl_is_code_list2_va`, `LK.pl_is_char_list2_va`, `LK.pl_collation_key2_va`.
Add helper entries (every method must be reached): `(LK.match_functor_type, Tuple{LD, Int, LK.word, T}, false)`,
`(LK.is_code, Tuple{LD, UInt8, LK.word}, false)`, `(LK.is_char, Tuple{LD, UInt8, LK.word}, false)`,
`(LK.is_text_list, Tuple{LD, Int, Int, Bool}, false)`.

## Rows, mutants, cost lines (not done)
- test/core_lang/test_prims_c_swipl.jl + .pl + .out modelled on test/core_lang/test_dwim_swipl.jl (rows `tN(R)`, kernel
  loads the program through `load_file!`; the .out from ~/.local/bin/swipl 10.1.20 only, run twice under
  `systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=0 -p TasksMax=64`, byte-identical). Catch errors as
  `catch(G, error(F, _), R = F)` so only the formal term is compared. Rows: functor/4 (every branch: compound, atom,
  atomic, var with arity>0 / 0 and each Type value `compound`/`callable`/`atom`/`atomic`/unbound/other -> domain_error,
  type_error(atom, 1) for a bad type, atomic Name with arity 0), nonground/2 (ground, first variable, attributed
  variable if cheap), $filled_array/4 (arity 0, 1, 3, a variable Value shared, a bad Name/Arity errors),
  $unbind_template/1 (a v(...) built with term_variables + =.., a bad template -> type_error(template, _)),
  $is_code_list/$is_char_list (empty, proper, with a bad element, partial list, a 1000+ long list, a cyclic list),
  $is_char_code/$is_char (0, 0x10FFFF, 0x110000, 0xD800, a one-char atom, [] , a two-char atom, a string),
  collation_key/2 under `setlocale(collate, Old, 'C')` (atom, string, empty, a type error).
- tools/mutants/PRIMSC.py (format: tools/mutants/DICTREC.py lines 1-40): ids unique, "aimed by <rows>", never the word
  KILL, each `old` once in its file, no `equivalent=` field; TARGETS = every test file that reaches the mutated
  code (D-0238: test_prims_c_swipl.jl plus the existing functor/3 and list/text tests that call the same helpers).
- cost lines `core_lang/test_prims_c_swipl.jl<TAB>estimate` in test/pkgtest_costs.tsv and test/unit_costs.tsv (path order,
  an estimate copied from a neighbour; say so in the commit).

## Facts found (kernel helpers used)
`_deref_loc(ld, -(t+1))` -> (kind, word, pos) with DU_CELL/DU_WORD/DU_VALUE/DU_ATTVAR; `_is_list_word`,
`skip_list_cells`, `ground_cells`, `unify_ptrs_cells`, `_alloc_compound!`, `_cell_link_lower!` (bArgVar), `ensureGlobalSpace`,
`PL_get_name_arity`, `lookupFunctorDef(ld.functors, _atom_word!(ld, name), arity)`, `_untagged_int`, `charCode`.
The module lists in src/LogicKernel.jl: pl-prims.jl is included before pl-inline users' later files but function bodies
resolve at call time; `Cwchar_t` is Base's.

## Checks NOT run
test_type_discipline.jl and warm.sh check were NOT run; no julia was run in this lane (brief: edit-only). The code was
not parsed. Daemon: none started by this agent.

## STATE after PRIMS-C2 (2026-11-15, Sonnet; edit-only, no julia run)

COMMITTED on wip/prims-c (after 21529e62):
- 77b6c654 collation_key/2 `pl_collation_key2_va` (libc wcsxfrm; a key character that is no code point -> NotPortedError owner CT1).
- 2f2cc47d the nine PL_extension entries in upstream's order (flag 0 -> PL_FA_VARARGS), manifest entries (nine `_va`,
  match_functor_type, is_code, is_char, is_text_list), owner row in docs/r2_owners.tsv
  (`refusal:src/pl-prims.jl::pl_collation_key2_va::collation_key/2 with a key that is no code point	CT1`).
- dd77500f rows: test/core_lang/test_prims_c_swipl.jl/.pl/.out (18 rows t0-t17). Two swipl 10.1.20 runs under systemd-run
  were byte-identical (19 lines). The .jl was NOT run.
- 531407e5 cost lines (pkgtest_costs.tsv 5.0, unit_costs.tsv 5.1, copied from the neighbours).

NOT DONE: tools/mutants/PRIMSC.py (the next piece). The brief's step 4 stopped at a hook block: the command
`grep -n "pl-prims" workflows/CODEMAP.md | cut -c1-300` was refused ("reading a curated INDEX row through a truncating filter";
CODEMAP rows are read whole with `sed -n '<N>p' workflows/CODEMAP.md | fold -w 120 -s`). It was meant to find the existing
test files that exercise functor/3 and the list/text helpers for TARGETS (audit D-0238). Then D-0794 stopped new code.

Facts the next agent needs:
- The rows' answers worth knowing (swipl 10.1.20): functor(T,foo,0,Var) -> instantiation_error (not domain_error: a variable
  culprit), `functor(T,foo,0,bar)` -> domain_error(functor_type,bar); bignum arity -> representation_error(size_t); negative arity
  -> domain_error(not_less_than_zero,-1); collation_key([a,b],K) -> type_error(string,[a,b]). The kernel's PL_domain_error on a
  variable culprit must give instantiation_error: the first run of the rows will show it.
- The rows use `f()`-free text, no NUL atom (the kernel refuses an atom holding character 0 at read), no non-C locale.

MUTANT PLAN (all in my head, not written; each `old` must be checked to occur exactly once in src/pl-prims.jl; ids "aimed by <rows>",
no word KILL, no `equivalent=`; TARGETS = test_prims_c_swipl.jl + the existing tests that reach functor/3, atom/text helpers
+ test/test_type_discipline.jl):
- nonground: `p != 0 && return unify_ptrs_cells(...)` -> `return FTRUE` (t5); unify against A1 instead of A2 (t5).
- functor/4: type error "atom" -> "atomic" (t1); drop match_functor_type in the compound branch (t0), in the atom branch
  `:atom`->`:atomic` (t0), atomic branch `:atomic`->`:atom` (t0); `if arity > 0` -> `>= 0` (t3); drop the type check before
  ensureGlobalSpace (t2); arity-0 `:compound` test -> `:atom` (t3); `:atomic` arm `return FFALSE` -> FTRUE (t3);
  "functor_type" -> "functor_typ" (t3); drop the match in `PL_unify(ld, A2, A1) && match_functor_type(...)` (t3);
  "atomic" error at the end -> "atom" (t3); match_functor_type: `if atype == ... :callable) &&` -> `if false &&` (t0), the unify of an
  unbound type -> `return true` (t0).
- $filled_array: `ld.gstack[p + i] = wv` -> `= ld.gstack[p + 1]` (t7); `if arity > 0` -> `> 1` (t7); PL_get_atom_ex -> PL_get_atom (t7);
  final unify -> FTRUE (t7).
- $unbind_template: `ld.gstack[unRef(c)] = word(0)` -> nothing (t9); the loop's else-branch type error -> `continue` (t9);
  `elseif !(k == DU_WORD && isAtomW(w))` -> `elseif false` (t9); `for i in 1:arity` -> `1:min(arity, 1)` (t9).
- is_text_list: cycle-check `return false` -> `return true` (t12, t13; no hang); is_code/is_char swapped (t10, t11, t13);
  `PL_unify_integer(ld, lent, len)` -> `len + 1` (t10); head read `valPtr(w) + 1` -> `+ 2` (t10).
  pl_is_code_list2_va passes `true`, pl_is_char_list2_va passes `false` (t10-t13).
- is_code: `VALID_CODE_POINT(Int(v))` -> `Int(v) >= 0` (t10, t14); `k == DU_VALUE || return false` -> `return true` (t14).
  is_char: `|| return false` on the atom test -> `return true` (t15). pl_is_char_code1_va / pl_is_char1_va call each other's test.
- collation_key: flags add CVT_LIST (t16); PL_STRING -> PL_ATOM (t16); `utf8_put_char(b, c)` -> `c & 0x7f` (t16);
  `n < buflen` -> `n <= buflen` (t17).
  Candidate equivalents (comments only): `buflen = n + 1` -> `n` (the doubling reaches the same key; needs the widened run and the
  audit's ruling); `charCode(...) != -1` -> `> 0` (a NUL atom cannot exist in the kernel); the `(size_t)-1` fail (no row can trigger it).

The test_type_discipline.jl and warm.sh check were NOT run; nothing in this lane was parsed or executed by julia.
No daemon was started or touched by this agent.
