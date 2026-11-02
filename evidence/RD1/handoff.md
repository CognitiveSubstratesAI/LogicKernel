# RD1 handoff (pl-read.c predicates; writer, edit-only; branch wip/rd1 off main 9e0a983)

Upstream read from the pin tree ~/dev-zone/swipl-devel-cbf4e189 (cbf4e1896275, pl-read.c is 7456 lines there).

## Plan (ordered groups)
1. src/pl-read.jl: `read_term/3`, `read_term/2` (pl-read.c:7112-7152), `$is_named_var/1` (pl-read.c:537-545) as PRED_DEF entries of
   `PL_predicates_from_read` in upstream's order (pl-read.c:7443-7456); the FRG entries `read/1`, `read/2` (pl_read2, 6714-6742),
   `$raw_read/1,2` (pl_raw_read2, 6652-6710) in src/pl-ext.jl `foreigns` at pl-ext.c:116-118 and 175.
2. Oracle rows from swipl 10.1.19 (gen_rows.py, driver, .out, test file) over option handling, end_of_file, syntax errors, stream errors.
3. tools/mutants/RD1.py. 4. manifest entries (appended). 5. docs/architecture.md block (appended).
Commit estimate: 7-8.

## Left out, flagged (see the end of this file for the final list)
- char_conversion/2, current_char_conversion/2 (pl-read.c:552-620): the static table needs state; PL_global_data field = Tier 1: QUESTION.
- $qq_open/2 (pl-read.c:2425): quasi-quotations are refused by the kernel's reader: QUESTION.
