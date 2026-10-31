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

## STATE (agent 1 handed back at the context cap)
COMMITTED: c78805e plan; 8d904f9 pl-global.jl IO_output_stack (own commit, struct change); callProlog `ex` (pl-pro.jl); then the commit
holding src/os/pl-redirect.jl (setStandardStream, pushOutputContext, popOutputContext, REDIR_MAGIC, redir_context, setupOutputRedirect,
closeOutputRedirect, discardOutputRedirect, pl_with_output_to2_va, tellString, toldString, PL_predicates_from_redirect), the include in
LogicKernel.jl (after os/pl-file.jl), the table in pl-ext.jl `_PRED_TABLES`/`_FOREIGN_VA` (after PL_predicates_from_file), the rows
(evidence/O1B/gen_rows.py renders test/core_lang/test_with_output_to_swipl.jl; wo_rows.out = swipl 10.1.19, two identical runs; w01-w72).
NOT RUN anywhere (writer rule): no Julia. The first compile is the gate's. Points to check at the first compile:
- `elseif (a = PL_get_atom(ld, to)) !== nothing` in setupOutputRedirect (an assignment inside the condition).
- `PL_chars_t(bytes, length(String(copy(bytes))), ENC_UTF8, false)` then `PL_unify_text` (as pl-text.jl:121 builds one).
- the 6-argument `callProlog(..., ex::Union{Nothing, Base.RefValue{Int}})` and its 5-argument forwarder (the manifest line for the 5-arg form
  stays valid; ADD in the manifest commit: `(LK.callProlog, Tuple{GD, LD, Int, Int, UInt32, Base.RefValue{Int}}, false)`).
- rows marked UNVERIFIED on the kernel: w43 w44 w64 w68 w69 w70 (a kernel error term may differ; trace, do not re-pin).
LEFT: (1) tools/mutants/O1B.py (>= 10; TARGETS = test_with_output_to_swipl.jl + every test file that exercises the redirect, O1A's format rows
file when it lands); (2) manifest block (callProlog 6-arg, pl_with_output_to2_va, setupOutputRedirect, closeOutputRedirect, discardOutputRedirect,
pushOutputContext, popOutputContext, tellString, toldString, setStandardStream) and an architecture.md row for os/pl-redirect.jl as the LAST commits;
(3) `warm.sh fmt` through `send` (pl-ext.jl line lengths), then the gates.
Mutant ideas (anchors in src/os/pl-redirect.jl): drop the `popOutputContext` in closeOutputRedirect / discardOutputRedirect (`ctx.redirected && popOutputContext(ld)`);
drop `redir && pushOutputContext`; swap `PL_CODE_LIST`/`PL_CHAR_LIST` for codes/1; `out_arity = 2` -> 1; drop `PL_unify(ld, tail, diff)`; drop the
`discardOutputRedirect` call in with_output_to; return TRUE on a failed goal; drop `PL_raise_exception`; `ctx.magic != REDIR_MAGIC` guard removed;
`Sclose(s) == 0` -> `!= 0`; user alias branch `:user` -> other; `(s.flags & SIO_OUTPUT) == 0` check inverted; ENC_UTF8 -> ENC_ISO_LATIN_1 on the memory stream
(w19-w21 wide characters); bytes slice `b[1:ctx.size[]]` -> whole buffer (w13 and w22); popOutputContext's `s.magic != SIO_MAGIC` branch; setStandardStream's `old !== s` guard.

## INTERFACE FOR A (exact names; ld first, as the rest of the kernel; all in src/os/pl-redirect.jl)
- `redir_context()` -> a fresh `redir_context` (mutable struct, pl-incl.h `redir_context`), fields stream/is_stream/redirected/term/out_format/out_arity/size/data.
- `setupOutputRedirect(ld, to::term_t, ctx::redir_context, redir::Bool)::Bool` (format/3: `redir = false`; `to` is 0 for the current output).
- `closeOutputRedirect(ld, ctx)::Bool`, `discardOutputRedirect(ld, ctx)::Nothing`.
  format/3 shape: `setupOutputRedirect(ld, out, ctx, false) && (format_impl(ld, ctx.stream, ...) ? closeOutputRedirect(ld, ctx) : (discardOutputRedirect(ld, ctx); false))`.
- `tellString(ld, bufp::Base.RefValue{Union{Nothing, Vector{UInt8}}}, sizep::Base.RefValue{Int}, enc::IOENC)::Bool` and `toldString(ld)::Bool`
  (pl-fmt.c:450/468: `tellString(&state->str, &state->bufsize, ENC_UTF8)`; the bytes written are `bufp[][1:sizep[]]`, size in BYTES).
- `pushOutputContext(ld, s)`, `popOutputContext(ld)`, `setStandardStream(ld, i, s)`.
- A's expectations (INTERFACE TO B in evidence/O1A/handoff.md) were not readable (the file did not exist yet): the dispatcher reconciles.
Gate order: fmt (via send), inventory, check, rows on three term types, type discipline, pkgtest_way, mutants branch, branch-gate, term grep,
alloc pins x3 (pl-global.jl changed), gate push on a FRESH name.
