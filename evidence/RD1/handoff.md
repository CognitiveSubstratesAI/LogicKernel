# RD1 handoff (pl-read.c predicates; writer, edit-only; branch wip/rd1 off main 9e0a983)

Upstream read from the pin tree ~/dev-zone/swipl-devel-cbf4e189 (cbf4e1896275; pl-read.c is 7456 lines there, not 7476).
Nothing compiled or run (edit-only): every line below is read-only until a slot runs it.

## Commits so far
- 7548ae5 ADDED: this plan.
- 9f85bb1 UPSTREAM: pl-read.c read_term pl_read2 pl_raw_read2 is_named_var (swipl-devel cbf4e1896275) — group 1, DONE (below).

## Group 1 (DONE, unrun): the registrations
Sites and upstream lines (pin tree):
| predicate | Julia (src/pl-read.jl unless noted) | upstream |
|---|---|---|
| read_term/3 | `pl_read_term3_va`, PRED_DEF, `PL_FA_ISO` | pl-read.c:7108-7124, table 7444 |
| read_term/2 | `pl_read_term2_va`, `getTextInputStream(ld, 0)` | pl-read.c:7129-7145, table 7445 |
| $is_named_var/1 | `pl_is_named_var1_va` over `atom_is_named_var` (bytes of `sym_text`) | pl-read.c:537-545, table 7451 |
| read/1 | `pl_read` (FRG, src/pl-ext.jl `foreigns` after print/1) | pl-read.c:6738-6741, pl-ext.c:116 |
| read/2 | `pl_read2` (FRG, after `$garbage_collect/1`) | pl-read.c:6713-6736, pl-ext.c:175 |
| $raw_read/1,2 | `pl_raw_read`, `pl_raw_read2` (FRG, after read/1) | pl-read.c:6652-6710, pl-ext.c:117-118 |
`PL_predicates_from_read` now holds read_term/3, read_term/2, read_clause, read_term_from_atom, atom_to_term, term_to_atom, term_string,
$is_named_var (upstream order, pl-read.c:7443-7456). The three read_term options the kernel refuses (comments, var_prefix, quasi_quotations,
blob, unicode_atoms) throw `NotPortedError` in `read_term_from_stream` (existing DIVERGES, unchanged): a row using one of them raises a Julia
exception, not a Prolog error; keep such options out of the rows or pin them as refused.
Nothing in pl-read.jl's reader internals, pl-global.jl or a Tier-1 file was touched: Tier 3.

## FLAGS / QUESTIONS for the audit (numbered, with a recommendation)
1. char_conversion/2, current_char_conversion/2 (pl-read.c:552-620, FRG pl-ext.c:120-121; NDET|ISO for the second). Upstream keeps a STATIC
   257-entry table (`char_conversion_table`) that `init_read_data` hands to the reader when the flag `char_conversion` is true
   (pl-read.c:851-854, 1430-1433). The kernel has no home for it short of a `PL_global_data` field (Tier 1 file: STOP rule) and the reader
   never converts (read_data has no table field: "no character conversion table", pl-read.jl:2282 and getchr__). Both predicates are
   library-only in the sizing (nothing on the load path). RECOMMEND: leave both to a step that owns a `PL_global_data` field
   (`char_conversion_table::Vector{Int}`, 257 entries) together with the reader's conversion in `getchr__`; do not half-port.
2. $qq_open/2 (pl-read.c:2425-2468, `#ifdef O_QUASIQUOTATIONS`): its argument is `$quasi_quotation(ReadData-pointer, Start, Len)` built by the
   parser; the kernel's reader REFUSES quasi-quotations (R1's decision), so no term of that shape can exist. RECOMMEND: deferred with the
   quasi-quotation step; only the argument checks (type_error(read_context, A1)) could be ported now, which is a partial port: not done.
3. `$code_class/2` (pl-read.c:7402): in the table at 7451 but NOT in the sizing's RD1 list; library/prolog_colour.pl calls it (library-only).
   RECOMMEND: add to RD1's list or to the library step; not done here.
4. `unify_location` (pl-read.jl:1088) throws NotPortedError for a syntax error on a stream that has no file name and is no string stream
   (`stream(S, Line, LinePos, CharNo)`, "the stream table (R2)"). The stream table exists since S1, so this branch can now be ported, but it is the
   reader's internals (STOP rule): QUESTION whether the dispatcher wants it in RD1 or in its own step. Rows over `open_string/2` streams with a syntax
   error hit it; rows over file streams (file(Path,L,LP,C)) and string/atom streams do not.
5. Stale-pin hunt (GATE-PLAYBOOK): NOT YET DONE. Before the push: grep -n "KNOWN DIFFERENCE\|interim\|until R2\|existence_error" over test/ and read
   every hit naming read/1,2, read_term/2,3, $raw_read, $is_named_var (a pin that says "unknown procedure" for them is stale now).

## Groups left (a fresh agent; ~4 commits)
2. ORACLE ROWS: test/core_text/test_read_term_swipl.jl in the form of test/core_lang/test_at_body_swipl.jl (program + `_RT_CASES` + `_RT_PINNED`,
   driver `fz_run`, `swipl -q` live compare with LC_ALL=C), generator evidence/RD1/gen_rows.py in the form of ~/code/lk-q10/evidence/Q10/gen_rows.py
   (a unique name prefix `rt`, ONE extractor, non-vacuity block, pins from TWO byte-identical swipl runs). The input comes from a stream: the cases
   open `open_string/2` or a file the program writes (`tmp_file`-free: write the file with the kernel's own open/write if it exists, else cases use
   `read_term_from_atom`-free `open_string`; CHECK which of open_string/2, open/3, see/1, set_input/1, current_input/1 the kernel registers on main
   before writing a row that needs it: a row whose setup predicate is missing is UNVERIFIED on the kernel). Case families (swipl is the oracle for each):
   read/1,2 and read_term/2,3 over: a term; two terms in a row; `end_of_file` at EOF (twice); variable_names, variables, singletons (list and
   `warning`), term_position, subterm_positions, syntax_errors(fail|quiet|error|dec10), module(M), double_quotes(codes|atom|string), back_quotes,
   character_escapes(false), cycles(true) `@`-template, dotlists; options errors (non-list, partial list, unknown option `foo` = ignored, wrong type
   `variable_names(foo)`, `syntax_errors(bar)` = domain_error(syntax_errors,bar)); stream errors: unbound stream (instantiation_error), `foo`
   (existence_error(stream,foo)), an output stream (permission_error(input,stream,S)), a binary stream (permission_error(input,binary_stream,S));
   syntax errors: `a b.` (operator expected), `foo(.` , unterminated quoted, a missing full stop at EOF; `$raw_read/1,2`: text of the next term without
   the full stop and layout (`foo( X ,b ) .` -> `foo( X ,b )`), `0' .` (the `0'<space>` guard), end_of_file text `end_of_file`, comments dropped;
   `$is_named_var/1`: X, _X, _1, __a, _, _a, 'Foo', [] , 1, f(x), unbound (instantiation_error).
   Avoid the refused options (comments, var_prefix, quasi_quotations, blob, unicode_atoms); pin their refusal separately if wanted.
3. tools/mutants/RD1.py in the format of tools/mutants/MOD3b.py (>= 10 mutants; anchors `old` ONCE: the `pl_raw_read2` `chr == Int('.')` test, the
   `0'` guard `top += 1`, `top - 2 >= s`, `read_term(term, rd)` -> failing, `rd.has_exception` test in pl_read2, `Sferror(s) != 0` in the three
   wrappers, `getTextInputStream(ld, 0)` -> 1-arg stream, `== 1` in `$is_named_var`, `PL_FA_ISO` flags, `read_term_from_stream(gd, ld, s, A1, A2)` ->
   A2, A3 swap; TARGETS = the new test file + test/core_text/test_read_positions_swipl.jl + every file calling read_term_from_atom/atom_to_term
   that shares `read_term_from_stream`: grep -l before writing). Validate with a throwaway python3 -I + runpy checker (old once, new != old, ids unique,
   targets exist).
4. test/static_analysis_manifest.jl: APPEND entries for pl_read_term3_va, pl_read_term2_va, pl_is_named_var1_va, pl_raw_read2, pl_raw_read, pl_read2,
   pl_read (copy the entry shape of `pl_read_clause3_va`: grep it) — a changed struct is none, so no `_enum_hash` entry.
5. docs/architecture.md: APPEND at the END a RD1 block (UPSTREAM / DIVERGES / ORIGINAL bullets, the src/pl-read.jl and src/pl-ext.jl rows are generated
   by the inventory: restore the pl-file.jl header names after a rebase, GATE-PLAYBOOK). Never regenerate docs/port_inventory.md.
6. Final handoff copy to ~/code/lk-channel/evidence/RD1/handoff.md (stage ONLY it, commit in a second call).

## Gate (for the gate agent, after the groups above)
fmt (format committed files through `warm.sh send`), inventory, `warm.sh check` (includes the Pkg.test-way run: pkgtest_way.sh on the new test file),
the new test file on all three term types, test/test_type_discipline.jl, push `mutants/RD1` at the WIP SHA once the list exists, branch-gate, term grep,
push `gate/rd1` and `mutants/RD1` at the SAME SHA; Tier 3: no battery, but the ROOT SUITE runs; alloc pins x3 are NOT needed (no pl-global/Tier-1 file).
A daemon slot is needed for the first smoke run (read/1 through the `foreigns` dispatch is the one thing unrun: `_fcall_det` tree grew by 4 entries,
and one FRG entry per arity of `read`/`$raw_read` with the same name: registerBuiltins! must accept two arities of one name, as write/1 and write/2).
