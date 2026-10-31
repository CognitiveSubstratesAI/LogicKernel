# O1B handoff — the output redirect and with_output_to/2 (writer B of O1)

Branch wip/o1b off origin/main faee65f. Upstream pin cbf4e1896275. Edit-only: no Julia was run.

## PLAN (ordered groups)
1. pl-global.jl: ONE appended LD field `IO_output_stack::Vector{IOSTREAM}` (LD->IO.output_stack), struct end + constructor end.
   Own commit (struct change: alloc pins x3 at the gate; G1/F1b append there too, the stack owner hand-merges).
2. pl-pro.jl: `callProlog` takes upstream's `ex` out-argument (pl-pro.c:476-575), 5-arg form kept as a forwarder.
3. src/os/pl-redirect.jl (new; included right after os/pl-file.jl): pl-file.c `setStandardStream` (:331), `pushOutputContext` (:1675),
   `popOutputContext` (:1686), `redir_context` + `REDIR_MAGIC` (pl-incl.h:2714), `setupOutputRedirect` (:1708), `closeOutputRedirect` (:1774),
   `discardOutputRedirect` (:1826), `with_output_to/2` (:1848), `tellString`/`toldString` (:2629/:2642), the registration table.
   pl-ext.jl: table appended to `_PRED_TABLES` and `_FOREIGN_VA` (with_output_to/2 already has its meta-predicate entry, "+0").
4. test/core_lang/test_with_output_to_swipl.jl + generator + .out (swipl 10.1.19), prefix `_WO` / `_wo_`.
5. tools/mutants/O1B.py (>= 10).
6. architecture.md block, static_analysis_manifest block (LAST, own commits).
Commit estimate: 6-7.

## DIVERGES (representation only)
- The memory stream is UTF-8 (`ENC_UTF8`), upstream's `ENC_WCHAR` is refused by this kernel's stream layer (pl-stream.jl Scanrepresent
  / Sputcode, the UTF-8-only rule of R1). The sink is built from the bytes with `PL_unify_text` (what `PL_unify_wchars_diff` does).
- No 1024-byte `buffer` in `redir_context`: the memory file grows from empty (as atom_to_term's).
- `output_context_stack` is a Vector (a stack), upstream a linked list; no heap allocation.
