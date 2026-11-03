# RD1c fix agent 1 (2026-11-03) — PART 1: edits committed, runs NOT done (no daemon slot)

Commit d70183f on wip/rd1 (over 807850c; bd38a5c is the pushed gate/rd1b tip). Nothing pushed.

## Step 1: the stale-pin grep over test/ (blob read option, the refusal text, option-table users)
- The refusal text "read options the kernel cannot honour": test/core_text/test_canonical_readatom_swipl.jl:576 only.
- Rows naming the blob read option `blob(`: test_canonical_readatom_swipl.jl (the stale row, :579) and test_read_stream_swipl.jl (rt303-rt321; already
  written for the ported option, passing in gate 1). No other file names `blob(Mode)` as a read option; the other "blob" hits are blob TYPE tests
  (alt_term.jl, test_blob.jl, test_atom_table.jl, test_sort.jl, test_compare_swipl.jl, test_termhash.jl, term_interface_testlib.jl, test_s2a_swipl.jl,
  test_clause_ref/nth_clause/record/source_file, test_open_close, test_load, test_write_family, test_vendored_*, test_gate_split, test_syntax.jl,
  static_analysis_manifest.jl).
- read_term_from_atom / term_to_atom / term_string users: test_read_term_swipl.jl, test_read.jl, test_read_positions_swipl.jl, test_roundtrip_swipl.jl,
  test_syntax.jl, test_reader_cells.jl, test_op.jl, test_write_swipl.jl, test_write_family_swipl.jl, test_float_write_swipl.jl, test_load_swipl.jl,
  test_open_close_swipl.jl, test_clause_ref_swipl.jl, test_record_swipl.jl, test_set_flag_swipl.jl, test_fli_words.jl, test_read_swipl.jl (core_lang),
  test_head_code_swipl.jl, code_testlib.jl, static_analysis_manifest.jl. None lists blob as NOTPORTED (grep for NOTPORTED/refus near blob: no match).

## Step 2: the fix (test side only)
- blob(x) out of the refusal list (comments, var_prefix, quasi_quotations, unicode_atoms stay).
- swipl 10.1.19 queried (/home/shivaji1012/.local/bin/swipl; not on the agent shell's PATH, the file's `Sys.which("swipl")` finds it in the daemon's env):
  blob(x) -> error(domain_error(blob,x),context(system:read_term_from_atom/3,_)); blob(_) -> error(instantiation_error,context(system:read_term_from_atom/3,_));
  blob(1) -> type_error(atom,1); blob("dead") -> type_error(atom,"dead"); blob(error|dead|resolve) on 'f(X)' -> true;
  '<a>(f)' with blob(error) -> syntax_error(operator_expected),string("<a>(f) . ",0).
- 8 rows appended to _CR_GOALS ("the hand goals, as swipl", end of list so no index shifts) + a swipl-independent testset "blob(Mode): ported (RD1b)...".
  Left out: '<a>(f)' with blob(dead): that is RD1b's documented DIVERGES (kernel refuses, upstream builds a dead blob).
- Also updated: header comment of the file; docs/architecture.md path text (RD1b.py -> RD1c.py).

## Step 3: mutants
tools/mutants/RD1b.py git-mv'd to RD1c.py; TC = test_canonical_readatom_swipl.jl added to TB (F1-F6, F12) and as TF (TS+TC) to F7-F10. Throwaway python3 -I checker:
33 mutants, each `old` once, ids unique, old != new, every target exists.

## Step 4: fmt / check NOT run (no daemon for lk-rd1). Edits follow the file's style by hand; fmt must still run.

## READY TO RUN (needs a daemon slot for ~/code/lk-rd1). Commands, in this order:
    cd ~/code/lk-rd1
    tools/warm.sh send   (JuliaFormatter over test/core_text/test_canonical_readatom_swipl.jl; then git diff, commit if it rewrote anything)
    tools/warm.sh check
    for T in reference alt alt_interned: tools/warm.sh file test/core_text/test_canonical_readatom_swipl.jl $T
    same three types: test/core_text/test_read_stream_swipl.jl (unchanged since gate 1, 259/259; re-run as the rule says)
    same three types: test/core_text/test_read_term_swipl.jl and test/core_text/test_read.jl (mutant TARGETS in TB)
    tools/warm.sh file test/test_type_discipline.jl
    tools/pkgtest_way.sh test/core_text/test_canonical_readatom_swipl.jl
Then: author check, git fetch + plain rebase if origin/main moved, bare pushes at the SAME SHA to refs/heads/gate/rd1c and refs/heads/mutants/RD1c, one ci_status.
