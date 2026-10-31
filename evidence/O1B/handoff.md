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

## RECONCILE with O1-A (coder 2, read-only: ~/code/lk-o1a evidence/O1A/handoff.md 'INTERFACE TO B' vs src/os/pl-redirect.jl)
AGREE (name, argument order, arity, result type), each checked against the file:
- `redir_context()` zero-argument constructor (pl-redirect.jl:84), field `.stream`. Its type is `Union{Nothing, IOSTREAM}`, set before any use;
  A passes `ctx.stream` to `format_impl`: A's parameter must accept it (an `::IOSTREAM` annotation is fine at run time, the value is a stream
  once `setupOutputRedirect` returned true).
- `setupOutputRedirect(ld, to::term_t, ctx, redir::Bool)::Bool` (`to == 0`: the current output).
- `closeOutputRedirect(ld, ctx)::Bool`, `discardOutputRedirect(ld, ctx)::Nothing`.
- `tellString(ld, bufp::Base.RefValue{Union{Nothing,Vector{UInt8}}}, sizep::Base.RefValue{Int}, enc::IOENC)::Bool`, `toldString(ld)::Bool`.
- A's `Scurout(ld)` use matches pl-file.jl:125.
MISMATCH 1 (A's side, for the dispatcher): A's handoff (item 4) says `callProlog` has no `ex` out-argument and plans `PL_Q_PASS_EXCEPTION` for `~@`
  (a DIVERGES). O1-B's commit 3cb3a13 gives `callProlog(gd, ld, flags_module, goal, flags, ex::Union{Nothing, Base.RefValue{Int}})` (the 6-argument
  form, pl-pro.c:476), the 5-argument form kept as a forwarder: A can call `callProlog(_query_gd(ld), ld, 0, goal, PL_Q_CATCH_EXCEPTION, ex)` with
  `ex = Ref(0)` as pl_with_output_to2_va does and drop the DIVERGES. Nothing to change on B's side.
MISMATCH 2 (include order, for the stack owner): B includes `os/pl-redirect.jl` in src/LogicKernel.jl right after `os/pl-file.jl` (line 64, BEFORE
  pl-write.jl at line 74); A wants `pl-fmt.jl` AFTER pl-write.jl and pl-file.jl, BEFORE pl-ext.jl. Merged order on the stack:
  `os/pl-file.jl`, `os/pl-redirect.jl`, ... `pl-write.jl`, `pl-fmt.jl`, `pl-ext.jl`. pl-redirect.jl uses no pl-write.jl name at load time
  (every use is inside a function body); pl-fmt.jl needs pl-redirect.jl (earlier) and pl-write.jl (earlier): the two lines do not conflict.
  pl-ext.jl: B appends `PL_predicates_from_redirect` to `_PRED_TABLES`/`_FOREIGN_VA` after `PL_predicates_from_file`; A's table
  (`PL_predicates_from_format`) is appended by the dispatcher: both lines touch the same two tuples (hand-merge, no semantic clash).
- The test file of A is named test/core_lang/test_format_swipl.jl in A's handoff (not on disk yet); it is a TARGET of the O1B mutants.

## COMPILE RISKS (coder 2, read by hand, still NOT compiled)
- `elseif (a = PL_get_atom(...)) !== nothing` replaced: `a = to == 0 ? nothing : PL_get_atom(ld, to)` before the `if`, `elseif a !== nothing`.
- `Scurout(ld)::IOSTREAM` / `Suser_output(ld)::IOSTREAM` asserted a stream where `ld.IO_streams` holds `Union{Nothing, IOSTREAM}` (pl-file.jl:116,125):
  setupOutputRedirect (current output, `user`) and toldString now test for `nothing` before `getStream` (pushOutputContext keeps its assertion:
  the stack is a `Vector{IOSTREAM}`).
- `PL_chars_t(bytes, length(String(copy(bytes))), ENC_UTF8, false)`: fields are (text::Vector{UInt8}, length::Int, encoding::IOENC, canonical::Bool)
  (pl-text.jl:25); the call is the same shape as pl-text.jl:121 builds. OK by reading. `PL_unify_text(ld, term, tail, text, type::Int)` (pl-text.jl:549) OK.
- PL_error forms used (permission: pl-file.jl:420 form; type: pl-file.jl:1010 form), `get_stream_handle(ld, a::T, flags::Int)`,
  `Sopenmem(bufp, sizep, mode)` (pl-stream.jl:1202), `callProlog` module 0 = the context module (pl-fli.jl:670) as pl-pro.jl:128: checked by reading.

## MUTANTS (tools/mutants/O1B.py, coder 2): 23 entries (21 with a kill row, 2 EQUIVALENT with file reasons Q1 Q2)
Validated with a throwaway python3 -I + runpy checker: every `old` occurs once in its file, `new != old`, ids unique; the ONLY missing target is
test/core_lang/test_format_swipl.jl (O1-A's rows, not on disk yet: its absence is expected; O1-A's handoff names it). Files: src/os/pl-redirect.jl and
src/pl-pro.jl (E1: callProlog's `ex`). TARGETS = test_with_output_to_swipl.jl + test_format_swipl.jl + the six files that call with_output_to/2 in their
Prolog text (test_write_swipl.jl:197, test_read_term_swipl.jl:392, test_builtins_swipl.jl:235/240, test_head_code_swipl.jl:144, test_blob.jl:110;
test_io.jl:17 is a comment) + the sig_atomic/callProlog users (test_cleanup_swipl.jl, test_context_module_swipl.jl, test_query_answers.jl) for E1.
At the first battery run: prune a target that fails on the unmutated tree (the driver refuses a failing baseline; the Prolog-text users may still need
format/2 or another predicate not yet landed); re-fit any `old` that `warm.sh fmt` rewraps (multi-line anchors).
D1/D2 (tellString/toldString) are killed only by O1-A's rows (column stops, ~@): if O1-A's file does not hit them the battery reports a survivor, to be
killed by a row in test_format_swipl.jl, not here. NOT COVERED by any row (header of the list): popOutputContext's closed-stream branch.

## MANIFEST (coder 2): one block after `(LK.callProlog, Tuple{GD, LD, Int, Int, UInt32}, false)` in `_manifest_index(T)` (test/static_analysis_manifest.jl):
callProlog 6-argument (`Base.RefValue{Int}`), `redir_context()` (the zero-argument outer constructor; the default 9-field constructor is not listed, as
`memfile`'s is not), setStandardStream (IOSTREAM and Nothing), pushOutputContext, popOutputContext, setupOutputRedirect, closeOutputRedirect,
discardOutputRedirect, pl_with_output_to2_va, tellString, toldString. No new `@enum`. The tellString line exceeds the formatter's width: `warm.sh send` rewraps it.

## STATE AFTER CODER 2 (all editing done; nothing compiled or run)
Commits (oldest first): c78805e plan, 8d904f9 IO_output_stack, 3cb3a13 callProlog 6-arg, 6d45cfa pl-redirect.jl + wiring + rows, f9f3b26 reconcile with O1-A,
e1c1509 compile-risk fixes, 4a2582a tools/mutants/O1B.py (23), 5c1b78f manifest block, then the architecture.md block (last).
LEFT FOR THE GATE AGENT: unformatted by the formatter (no daemon): the pl-ext.jl lines of the table wiring, all of src/os/pl-redirect.jl, the manifest tellString
line, tools/mutants/O1B.py anchors may need a re-fit. Run order: fmt through `warm.sh send`, inventory, check (includes the Pkg.test-way run), the rows on three term
types, type discipline, `tools/pkgtest_way.sh test/core_lang/test_with_output_to_swipl.jl`, push `mutants/O1B`, branch-gate, term grep, alloc pins x3
(pl-global.jl changed), gate push on a FRESH name. Merge with O1-A: src/LogicKernel.jl include lines and the pl-ext.jl tables (see RECONCILE).
FLAGS FOR THE AUDIT (not decided here): (1) the memory stream is UTF-8, upstream ENC_WCHAR (representation, R1's UTF-8 rule); (2) no Sdprintf message when the
waiting output stream was closed (popOutputContext); (3) rows w43 w44 w64 w68 w69 w70 are UNVERIFIED on the kernel (swipl's pin is truth); (4) popOutputContext's
closed-stream branch has no row; (5) O1-A's `~@` can drop its callProlog DIVERGES by using the 6-argument form.
