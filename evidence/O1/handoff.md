# O1 — the stack (wip/o1 = O1-B's commits, then O1-A's; integrator, edit-only, NOTHING compiled or run)

Branch wip/o1, linear, off main faee65f. Source handoffs: evidence/O1B/handoff.md (output redirect and with_output_to/2,
src/os/pl-redirect.jl, callProlog's `ex`), evidence/O1A/handoff.md (format/2,3, src/pl-fmt.jl). Both are in the tree unchanged.

## STACK ORDER (git cherry-pick, no merge commit; all other commits kept their messages)
1. O1-B: c78805e plan, 8d904f9 pl-global.jl IO_output_stack, 3cb3a13 callProlog `ex` (pl-pro.jl), 6d45cfa pl-redirect.jl + wiring + rows w01-w72,
   f9f3b26 handoff reconcile, e1c1509 FIXED pl-redirect.jl, 4a2582a tools/mutants/O1B.py (23), 5c1b78f manifest block, d99b4b4 docs block.
2. O1-A: f588119 plan, 7f05923..3c15680 pl-fmt.jl groups 1-7c, 5611e88 group 8 + include, 36ffdb6 `~@` with `ex`, 6124441 rows + generator,
   b3171b3 pl-ext.jl registration, 07d58ab / f19bfb3 / 54ae833 more rows (123 in all), 218a83e tools/mutants/O1A.py (130), c527abf handoff,
   b034159 docs block, b5fb111 manifest block, 8a5fc60 handoff.
3. Integrator: one commit, tools/mutants/O1A.py (test_with_output_to_swipl.jl joins `TO`), then this file.
`git log --oneline faee65f..wip/o1` lists them (O1-A's hashes changed by the pick; the subjects did not).

## CONFLICTS (3 in 30 picks) AND HOW THEY WERE RESOLVED
- src/pl-ext.jl (b3171b3): both steps edited `_PRED_TABLES` and `_FOREIGN_VA`. Kept both: `... PL_predicates_from_file, PL_predicates_from_redirect,
  PL_predicates_from_files, PL_predicates_from_format, PL_predicates_from_proc, ...` in the table tuple, and the same order (with the `...` splat)
  in `_FOREIGN_VA`. No duplicate, no entry lost (checked by reading the two tuples after the resolution).
- docs/architecture.md (b034159): both appended a block before `## Still to come`. Kept both: `## O1B` (HEAD), a blank line, `## O1A`.
- test/static_analysis_manifest.jl (b5fb111) and src/LogicKernel.jl (5611e88): auto-merged without a conflict. Manifest: O1B's block follows the
  callProlog line (~l.1460), O1A's block is appended at the end of `_manifest_index`, `FST = LK.format_state` added to the alias lines. LogicKernel.jl include
  order checked: `os/pl-files.jl`, `os/pl-file.jl`, `os/pl-redirect.jl`, `pl-write.jl`, `pl-fmt.jl`, `pl-ext.jl` (lines 62-78): exactly the order wanted, no
  commit was needed for it.
- tools/mutants/O1A.py: `test/core_lang/test_with_output_to_swipl.jl` added to `TO`, comment updated. A throwaway `python3 -I` + runpy checker (scratchpad, not
  committed) was run over BOTH lists on the merged tree: O1A 130 mutants, O1B 23, every `old` occurs exactly once in its file, `new != old`, ids unique, every
  target on disk (TARGETS: O1A 56, O1B 10), equivalents 1 and 2. The comment in O1B.py line 23 still says O1-A's file is not on disk: comment only, stale.

## GATE ORDER (combined; the gate agent runs it; all steps are the dispatcher's to order, nothing here was run)
1. `warm.sh send` fmt of the COMMITTED files (`warm.sh fmt` sees only the HEAD diff): src/os/pl-redirect.jl, src/pl-fmt.jl, src/pl-pro.jl, src/pl-global.jl,
   src/pl-ext.jl, src/LogicKernel.jl, test/core_lang/test_with_output_to_swipl.jl, test/core_lang/test_format_swipl.jl, test/static_analysis_manifest.jl
   (the manifest `tellString` line is over width; pl-redirect.jl and the pl-ext.jl wiring were never formatted). Expect fmt to rewrap `old` anchors of the
   mutant lists: re-fit them (O1B's multi-line anchors CLOSE_POP / DISCARD_POP, O1A's multi-line ones) with the checker, which the driver also enforces.
2. inventory.  3. `warm.sh check` (includes the Pkg.test-way run, D-0222).
4. Rows on all three term types: test/core_lang/test_with_output_to_swipl.jl (w01-w72) and test/core_lang/test_format_swipl.jl (123 rows).
5. test/test_type_discipline.jl.  6. `tools/pkgtest_way.sh <file>` for each of the two row files, ONE at a time.
7. Alloc pins on all three term types (src/pl-global.jl changed: IO_output_stack appended to the global; alloc bench only with the dispatcher's go).
8. Push `mutants/O1B` (23 mutants) at the WIP SHA, then `mutants/O1A` (130 mutants; large, may be split into two branches, e.g. K1-K65 / K66-end, if CI
   time asks; the list is TARGETS-complete only if every part keeps `TO`). If one branch name is used the plan reads the single MUTANTS file named by the
   branch: the two lists need two branch names or a combined file; the integrator did NOT combine them.
9. branch-gate.  10. crash-term grep over diff and message (D-0164).  11. gate push on a FRESH name, `mutants/*` at the SAME SHA.
FIRST-RUN EXPECTATIONS: nothing in src/os/pl-redirect.jl, src/pl-fmt.jl or the two row files was ever parsed by Julia. A FIX COMMIT is expected (syntax, names:
`redir_context`, `setupOutputRedirect`, `tellString`, `toldString`, `PL_is_pair`, `PL_put_integer`, `pl_write_term3`; O1-A's `_FM` harness renamed from
test_at_body_swipl.jl's `_AB`; both pl-redirect.jl and pl-fmt.jl use each other: `~@` and the column code call tellString/toldString/callProlog(6-arg)).
Static analysis (JET/Aqua) reads the manifest: expect a fix for any signature the compiler refuses. Watch items for the first run (read, not run): src/pl-ext.jl ~l.942 holds the meta-predicate loop that applies P_TRANSPARENT and the mask only to predicates the kernel
defines, and it already lists ("format",2,"+:"), ("format",3,"++:"), ("format_predicate",2,"+0"), ("with_output_to",2,"+0"). Until this stack those entries were skipped; now
they apply, so predicate_property/2 answers for format/2,3 and with_output_to/2 change, and a test that pinned the old answer would show it. Grep a green run for SKIP/Warning,
and check that this loop (`_boot_meta!`, src/pl-ext.jl:267) runs after `initBuildIns!` registers the new tables: the call order was NOT checked.

## UNVERIFIED (nothing compiled; all of it)
O1-B: rows w43 w44 w64 w68 w69 w70 (a kernel error term may differ; trace, do not re-pin); the compile risks in evidence/O1B/handoff.md (Scurout/Suser_output
`Union{Nothing,IOSTREAM}`, PL_chars_t field order, `get_stream_handle`, `Sopenmem`, `callProlog` module 0); popOutputContext's closed-stream branch has no row;
the mutant `old` anchors before fmt.
O1-A: nothing in pl-fmt.jl or test_format_swipl.jl was ever parsed by Julia; `mpz_sizeinbase10` (floor(bits*log10 2)+1) and the mpf precision
(`keep = (max(53,bits)+127)/64+1`) were written FROM MEMORY (verify against the GMP source or the oracle); `Base.Ryu.writefixed(f, digits)` /
`writeexp(f, digits, plus, space, hash, expchar)` argument positions; the mutant KILL ids in O1A.py are hypotheses; all `must_not_allocate` in the manifest are `false`
(unmeasured). Integrator: the merge itself (pl-ext.jl tuples, docs order) was resolved by reading; the include order was read from src/LogicKernel.jl.

## FLAGS, ALL UNDECIDED (for the audit; none was settled by the integrator)
O1-A a-k (evidence/O1A/handoff.md, "State after agent 2"/"coder 3"): (a) `~@` uses callProlog with PL_Q_CATCH_EXCEPTION and `ex` as upstream (36ffdb6): RESOLVED by
the dispatcher's note, now consistent in the stack (O1-B's 6-argument callProlog is in the stack before it); (b) `format("a~")` existence_error(format_character,'\0')
is blocked by codeToAtom(T,0); (c) no stream locale (D9): `~:d` / `~:f` print the C locale; (d) formatInteger of a bignum with more fraction digits than digits
pads '0' (upstream reads before the buffer); (e) a raw Latin-1 byte in pending rubber is decoded as UTF-8 as upstream does; (f) the 'g' of a bignum or rational
emulates GMP's mpf with exact rationals (cut by bit length, differs from GMP only within 2^-(64*prec) of a rounding boundary); (g) float `~e ~f ~g` use Base.Ryu
(exact, ties to even) in place of libc snprintf; (h) the LibBF branch of formatFloat and the `__WINDOWS__` exponent fix-up are left out; (i) `mpz_sizeinbase(z,10)`
emulated as floor(bits*log10 2)+1; (j) `format_predicate/2` is refused by name, the `format_predicates` table is empty; (k) numeric-argument overflow: upstream's
`int arg2 = arg*10+dw` wraps in C and swipl 10.1.19 prints `1` for `format("~3000000000d", [1])`, the Julia source raises `argument overflow`; no row and no
mutant for it (NOT STARTED).
O1-B five: (1) the memory stream is UTF-8, upstream ENC_WCHAR (representation, R1's UTF-8 rule); (2) no Sdprintf message when the waiting output stream was closed
(popOutputContext); (3) rows w43 w44 w64 w68 w69 w70 UNVERIFIED on the kernel (swipl's pin is truth); (4) popOutputContext's closed-stream branch has no row;
(5) O1-A's `~@` could drop its callProlog DIVERGES by using the 6-argument form: DONE in the stack by 36ffdb6 (flag closed in substance, still for the audit to confirm).

## OPEN ITEMS FOR THE STACK OWNER / AUDIT
- (k) the numeric-argument overflow behaviour difference (behaviour-changing against compiled swipl): decide DIVERGES (keep the error) or mimic the wrap (a C `int`
  wrap in the number parse), then a row and a mutant.
- Two mutant lists, two branch names (`mutants/O1B`, `mutants/O1A`): nothing in tools/ was changed to combine them.
- The docs blocks and the manifest blocks stay in the stack order O1B then O1A; the block "Still to come in ..." text of neither was touched.
- O1B.py's header comment (line 23) is stale ("NOT on disk when this list was written"); harmless.
