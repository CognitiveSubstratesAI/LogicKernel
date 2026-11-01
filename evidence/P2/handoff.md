# P2 — pl-prims.c text predicates (R2 boot C-predicates, D-0306 item 2)

Branch wip/p2 off origin/main 584476f. Edit-only writer; nothing run, nothing pushed.

## Verified predicate list (origin/main 584476f; boot calls checked at swipl-devel cbf4e1896275)

| predicate | boot caller | upstream | kernel today | in P2 |
|---|---|---|---|---|
| atomic_list_concat/3 | init.pl 1090, 1169, 1473 (also messages, packs, build_home) | pl-prims.c 4983-5070 `atomic_list_concat` + `split_atom` 4903 | NOT REGISTERED on main | yes |
| atomic_list_concat/2 | init.pl 1255, 1461 (also autoload, syspred, toplevel, tabling) | pl-prims.c 5074 | NOT REGISTERED on main | yes |
| atomics_to_string/2 | messages.pl 2679, 2713, 2721 | pl-prims.c 5088 | NOT REGISTERED on main | yes |
| atomics_to_string/3 | no boot caller (same C function as /2) | pl-prims.c 5081 | NOT REGISTERED on main | yes, one table line over the shared body |
| sub_atom/5 | init.pl 1053, 1186, 1251, 1684, 2397, 2398, 2520, 2667, 3610-3614 | pl-ext.c:107 FRG NDET\|ISO -> pl-prims.c 5487 `pl_sub_atom` -> `sub_text` | body `sub_text` is on main (pl-string.jl, T2); NOT REGISTERED as sub_atom/5 | yes: wrapper + table line |

Moved to R3 (inventory column "referencing boot files" is `-`; the boot never reaches them), not ported here:
`$filled_array/4`, `$is_char/1`, `$is_char_code/1`, `$is_char_list/2`, `$is_code_list/2`, `$seek_list/4`,
`$unbind_template/1`, `collation_key/2`, `sub_atom_icasechk/3` (pl-prims.c 2616, 4616-4671, 3005, 3532, 4729, 5098).
Already on main (VERIFIED by registration lines in src/pl-prims.jl / pl-string.jl): atom_length/2, atom_number/2,
atom_chars/2, atom_codes/2, number_codes/2, char_code/2, atom_concat/3, atom_string/2, sub_string/5, split_string/4;
term_to_atom/2 lives in pl-read.jl. string_to_atom/2: dropped per the brief.

## Groups (all written; nothing run, nothing pushed)
1. Plan (this file). 2. `atomic_list_concat`, `split_atom`, the four wrappers and `pl_sub_atom5_va` in src/pl-prims.jl.
3. The five registrations in `PL_predicates_from_strings` (src/pl-string.jl). 4. Rows test/core_lang/test_p2_swipl.jl p01-p70
(pins: swipl 10.1.19, two byte-identical runs; `python3 -I evidence/P2/gen_rows.py --fill`; output evidence/P2/p2_rows.out).
5. tools/mutants/P2.py (17 mutants, 1 declared equivalent; validated old-once/new!=old/targets with a throwaway runpy checker).
6. docs/architecture.md block. 7. Manifest entries (own commit, LAST). Commits: 10 (limit 12).

## Not run / UNVERIFIED on the kernel (the gate decides)
Every kernel answer of p01-p70 (no Julia was run): the first things to look at are p29/p30/p48/p64 (wide characters through
`PL_concat_text` and `PL_unify_text_range`), p33/p49 (the 100-element check), p69/p70 (permission_error for a clause of a
system predicate; the kernel's assertz path), p14/p18-p21/p24/p57 (instantiation_error: compared by formal only).
Mutant anchors need a re-fit if `warm.sh fmt` re-flows a line.

## Flags
- No Tier-1 file touched (no pl-wam, pl-comp, pl-supervisor, pl-fli, run loop, pl-global.jl): no alloc pins needed.
- The strings-table position (not the prims table) is the one DIVERGES comment in code; representation-only.
- Mutant P2-C2 (ISO flag) is declared equivalent with src/pl-comp.jl:1448: the gate agent may prefer a kill row.
- The rows reuse test_style_check_swipl.jl's machinery; the copied `TERM TYPES PER CHUNK` comment names the reference type, the
  rows go through `lk_term_type` so all three types run.
- test/static_analysis_manifest.jl near line 3028: the comment says `_fcall_ndet` comes back when a second non-deterministic
  entry (NF4b's sub_atom/5) keeps the dispatch tree a call. sub_atom/5 is that second entry now; the gate agent re-reads the
  `:builtin` exemption there.
- R3 (the boot reaches none of them): `$filled_array/4`, `$is_char/1`, `$is_char_code/1`, `$is_char_list/2`,
  `$is_code_list/2`, `$seek_list/4`, `$unbind_template/1`, `collation_key/2`, `sub_atom_icasechk/3`.

## Gate order for this step
fmt (format committed files through `warm.sh send`), inventory, check (with the Pkg.test-way run), test_p2_swipl.jl on all
three term types, test/test_type_discipline.jl, `tools/pkgtest_way.sh test/core_lang/test_p2_swipl.jl`, push mutants/P2 at the
WIP SHA, branch-gate, term grep, a gate push on a FRESH name (mutants/P2 at the same SHA).

## Julia sites and DIVERGES (representation only)
- upstream's `tmp_buffer` + `IOENC` promotion (`append_text_to_buffer`) -> a Vector of canonical `PL_chars_t` joined by
  `PL_concat_text` (the same text; the encoding is chosen by the same latin/wide rule).
- `PL_STRINGS_MARK/RELEASE`, `PL_free_text`: Julia's GC owns the bytes.
- texts are canonicalised after `PL_get_text` (as `concat` in pl-prims.jl does).

## Flags
None Tier 1 (no pl-wam, pl-comp, pl-fli, run loop, pl-global.jl). The strings table position is a DIVERGES comment.
