# LB5 writer handoff (D-0386 items 1c, 2; edit-only; worktree ~/code/lk-lb5, branch wip/lb5 off 9cc76fa)

Kernel registry form: `PL_extension("name", N, fn_va, flags)` tuples; pl-file.jl's table is `PL_predicates_from_file`
(src/os/pl-file.jl ~2620). Upstream read at the pin cbf4e1896275 via `git show` (pl-file.c, pl-arith.c).

## Plan (ordered; "G" = committed group)
G1  set_stream/2 alias(Std): setStandardStream instead of the refusal (pl-file.c:2215-2227). Key fact: plunit's default
    output(on_failure) goes through library(streams) with_output_to/3 -> set_stream(S, alias(user_output)).
G2  current_input/1, current_output/1 (current_io, pl-file.c:5693-5735), line_count/2, line_position/2 (getStreamWithPosition
    pl-file.c:5524-5540, :5773-5800), tab/1,2 (pl-file.c:3809-3845; needs PL_eval_expression_to_int64_ex, pl-arith.c:5346: G2a).
G3  at_end_of_stream/0,1 (pl-file.c:5827-5860), get_code/1,2 (3626-3650), put_code/1,2 (3427-3455).
G4  write_size/4 (src/pl-write.jl; pl-write.c).
G5  rows (test/..._lb5_swipl.jl + generator), mutants tools/mutants/LB5.py, manifest, docs/architecture.md block.
Optional / may be handed on: succ/2 (pl-arith.c:274-355), peek_string/3 (needs buffer text access), seek/4 + set_stream_position/2
    (need Sseek64/Stell64: the stream layer has none), with_tty_raw/1.

## State
(see "Committed" below, updated after each commit)

## Committed
- G1 84d905d  set_stream alias(Std) -> setStandardStream (pl-file.jl). UNVERIFIED: whether closing a captured stream
  leaves the standard slot dangling (restoreStandardStream: NOT STARTED; closeStream keeps the standard streams open).
  NEED (pl-global.jl, in flight): `LD->prompt.next = true` for alias(user_input): no field in PL_local_data.
- G2+G3 (this commit): pl-file.jl current_input/1, current_output/1 (current_io, is_stream_blob), line_count/2,
  line_position/2 (getStreamWithPosition), tab/1,2, at_end_of_stream/0,1, get_code/1,2, put_code/1,2, put_char/1,2
  (the upstream table maps put_char to put_code2/1); src/pl-arith.jl PL_eval_expression_to_int64_ex (tab needs it).
  Registered in PL_predicates_from_file with the upstream flags (PL_FA_ISO for get/put_code, at_end_of_stream, current_*).
  UNVERIFIED (no Julia run): all of it; `current_io` of an alias argument (term_stream_handle SH_ALIAS), arity-0 `0`
  term_t for "current stream", PL_eval_expression_to_int64_ex's mpz branch.
  MANIFEST ENTRIES NEEDED (commit 6): LK.pl_current_input1_va pl_current_output1_va pl_line_count2_va pl_line_position2_va
  pl_tab1_va pl_tab2_va pl_at_end_of_stream0_va pl_at_end_of_stream1_va pl_get_code1_va pl_get_code2_va pl_put_code1_va
  pl_put_code2_va (Tuple{PL_local_data{T},Int,Int,foreign_context{T}}); is_stream_blob (ld,Int), current_io (ld,Int,
  Union{Nothing,IOSTREAM},Symbol), getStreamWithPosition (ld,Int), tab (ld,Int,Int), at_end_of_stream (ld,Int),
  get_code2 (ld,Int,Int), put_code (ld,Int,Int), PL_eval_expression_to_int64_ex (ld,Int).

## FORCED HAND-BACK at the 150k cap (writer 1). Committed on wip/lb5: 84d905d (G1 + plan), 9f1e546 (G2+G3), this handoff update.
LEFT (next writer, fresh agent; read this file, then only the files it edits):
- G4 write_size/4 (src/pl-write.jl, upstream pl-write.c:3283-3380, table entry :3437 `META` = PL_FA_TRANSPARENT, no ISO).
  Findings so far: (a) the Julia stream layer has NO custom write-function set (IOFUNCTIONS = Smemfunctions, Sstringfunctions,
  Siofunctions): upstream's `limit_size_stream` with `Swrite_lss` cannot be copied 1:1. Plan: DIVERGES (representation, flag
  to audit): write into a memory stream (`Sopenmem(bufp, sizep, "w")`, as tellString, src/os/pl-file.jl ~3175), with
  clearPrologFlagMask!(ld, PLFLAG_ISO) / restore `ld.prolog_flag_mask`, `pushOutputContext(ld, s)`,
  `pl_write_term3(ld, 0, A1, A4)` (pl-write.jl:2153), `popOutputContext(ld)`, close the stream (`closeStream(ld, s)`, as
  toldString does), then measure the bytes afterwards: decode UTF-8, run `Supdatepos(IOPOS(), c)` per code point, width = max
  linepos, height = (width > 0 || lineno > 0) ? lineno + 1 : 0; fail when width > max_width or height > max_height, else
  unify A2 (width) and A3 (height). The limits are then checked after the write, not during it (differs only for output that
  would exhaust memory) and `PL_clear_exception` of the abort path is not needed.
  (b) options: `write_length_options` = (max_width, max_height) OPT_INT64; PL_scan_options (src/os/pl-option.jl) stops at
  OPT_INT64 (get_optval asserts): add `elseif type == OPT_INT64` -> `PL_get_int64_ex(ld, val)` (pl-string.jl:497; the OPT_INF
  form `PL_is_inf` is unused by write_size) and edit the file header (pl-option.jl:14). pl-option.jl is on no in-flight list.
  (c) registration: add `PL_extension("write_size", 4, pl_write_size4_va, PL_FA_TRANSPARENT | PL_FA_VARARGS)` to
  PL_predicates_from_write (pl-write.jl ~2476) and remove write_size/4 from the list in its DIVERGES line (pl-write.jl ~2474).
  Defaults max_width = max_height = typemax(Int64) (PLMAXINT; the Julia name is not in the kernel: use typemax(Int64)).
- G5 rows: test file e.g. test/core_lang/test_lb5_swipl.jl + evidence/LB5/gen_rows.py (model: evidence/MOD5b, evidence/MOD6 of the
  channel; first ~80 lines of test/core_lang/test_at_body_swipl.jl). Rows over: set_stream(S, alias(user_output)) with
  with_output_to-style capture and restore; current_output(S) round trip, current_output(user_output) domain_error;
  line_count/line_position on a string/memory stream and on a stream without position (permission_error(property,position,S));
  tab(N) expression `tab(1+2)`, tab(a) type_error(integer_expression..), tab(-1); at_end_of_stream on empty/non-empty memory
  stream; get_code at EOF (-1), get_code(S, end_of_file) (fail), put_code(0'a), put_code(-1) error; put_char; write_size.
  Pins from live swipl 10.1.19 (/home/shivaji1012/.local/bin/swipl), two byte-identical runs; LC_ALL=C.
- G6 mutants tools/mutants/LB5.py (>= 8; model tools/mutants/MOD3b.py; every `old` exactly once; TARGETS = the LB5 rows file plus
  EVERY test that registers/uses these predicates: grep -l set_stream|current_output|tab\(|put_char|get_code test/ first, e.g.
  test/core_text/test_write_family_swipl.jl, test_canonical_readatom_swipl.jl, test/core_lang/test_s2a_swipl.jl,
  test/files/test_open_close_swipl.jl); validate with a throwaway python3 -I script in a scratchpad. Candidate mutants: set_stream
  alias branch `return true` -> false / drop setStandardStream; current_io `s === cur` -> `s !== cur`; getStreamWithPosition
  drop the `position === nothing` check; line_count lineno -> linepos; tab loop `count > 0` -> `count >= 0`;
  at_end_of_stream `rval < 0` check dropped; get_code2 eof branch; put_code argument order; PL_eval_expression_to_int64_ex
  `toIntegerNumber` branch.
- G7 manifest entries (append at the END of `_manifest_index` before its closing paren, test/static_analysis_manifest.jl ~2690;
  list in the G2+G3 entry above, plus pl_write_size4_va and the write_size helper(s)) and the docs/architecture.md block at the
  END (never regenerate docs/port_inventory.md; the src/os/pl-file.jl row UPSTREAM header names must stay: pl-privitf.c,
  pl-prologflag.c, see GATE-PLAYBOOK last line).
- OPTIONAL, not started: succ/2 (pl-arith.c:274-355; quirk: the p1-integer branch sets `rc` and falls through to the p2 block),
  peek_string/3 (pl-file.c:3331-3395; needs IOSTREAM bufp/limitp text decode + `PL_get_size_ex` + string unify of a text
  range; check S__fillbuf usage), seek/4 and set_stream_position/2 (pl-file.c:5569-5650: need `Sseek64`/`Stell64`/`Sunit_size`:
  the stream layer has only `Sseek_memfile64`; a pl-stream.jl commit first), with_tty_raw/1 (pl-file.c:1959). Commit 6
  (nb_set_dict, del_dict) WAITS (pl-dict); commit 8 DEFERRED (DBG1).
FLAGS FOR THE AUDIT: (1) G1 drops `LD->prompt.next = true` for alias(user_input): needs a field in pl-global.jl (in flight).
  (2) current_input/1 was not in the sizing's list but is the twin of current_output/1 in one upstream function (current_io);
  put_char/1,2 are upstream's aliases of put_code (table lines in pl-file.c BeginPredDefs). (3) write_size DIVERGES above.
  (4) tab/1,2 needed PL_eval_expression_to_int64_ex in src/pl-arith.jl (not an in-flight file).
OVERLAP with the b2 lane (wip/lb4b2c edits src/os/pl-file.jl: get_stream_handle calls _initIO first, af6540c): my edits are in
  set_stream (alias branch), PL_predicates_from_file (table, DIVERGES comment) and two NEW sections inserted before the
  "character input" section header (current_io ... put_code); get_stream_handle is untouched. Expect a textual conflict only in
  the registration table block if b2 also adds entries there.
STALE-PIN HUNT (GATE-PLAYBOOK): test/core_lang/test_s2a_swipl.jl header (lines 4, 9) names "alias(Std) of a standard stream" as
  refused; no row pins the refusal (grep of the file for `alias(user`, `NotPorted`: no rows). test/core_text/test_write_family_swipl.jl:380-384
  and test_canonical_readatom_swipl.jl:162-165 run set_stream(S, alias(user_output)) together with set_output/1 (set_output/1 is
  registered by no table yet: read these tests before the gate; they may begin to run further than before).
No Julia or daemon run. Hook note: the absence-claim hook scans added text for absence phrases; phrase positively (NOT STARTED).

## WRITER 2 (D-0386 1c + 2; Sonnet; edit-only) — state after each commit
DISPATCHER RULINGS on writer 1's questions (provisional, pending audit):
 (1) current_input/1 stays and put_char/1,2 as upstream's aliases of put_code: accepted.
 (2) The `LD->prompt.next = true` gap for user_input needs a pl-global.jl field: a recorded NEED for after the gates land (not this step).
 (3) write_size/4: representation-only DIVERGES accepted (write into a memory stream, measure afterwards with Supdatepos; limits
     checked after the write, differing only for output that would exhaust memory). Prerequisite OPT_INT64 in src/os/pl-option.jl.
 (4) seek/4, set_stream_position/2 (Sseek64/Stell64/Sunit_size missing in the stream layer): NOT in this step; LEFT TO A STREAM-LAYER STEP.
 (5) set_output/1: DECIDED it does NOT join this step. test_write_family_swipl.jl:377-387 and test_canonical_readatom_swipl.jl:159-168 hold
     `cap/1`, which is swipl-side driver text only (the kernel side of both files runs the predicates directly: `_wf_goal_results`,
     the PL_open_query loop); the kernel never runs set_stream(S, alias(user_output)) or set_output/1 in them. No stale pin.
Committed by writer 2:
- bad6f39 G4a  OPT_INT64 branch of get_optval (src/os/pl-option.jl) + header text.
- d26bf01 G4b  write_size/4 in src/pl-write.jl (`write_length_options`, `write_size`, `pl_write_size4_va`, registered in
  PL_predicates_from_write with PL_FA_TRANSPARENT|PL_FA_VARARGS; DIVERGES comment above `write_size`). UNVERIFIED: all (no Julia).
  Uses tellString/toldString (pl-file.jl), clearPrologFlagMask!, pl_write_term3, IOPOS/Supdatepos, PL_unify_int64.
- G5 (next commit): test/core_lang/test_lb5_swipl.jl (106 rows lb001-lb106) + evidence/LB5/{gen_rows.py,lb5_rows.pl,lb5_driver.pl,lb5_rows.out}.
  Groups: lb001-011 line_position/line_count; 012-021 current_input/output; 022-035 tab; 036-043 at_end_of_stream; 044-056 get_code;
  057-073 put_code/put_char; 074-096 write_size; 097-106 set_stream alias. Pins = swipl 10.1.19, two byte-identical runs.
  Regenerate: `cd evidence/LB5; python3 -I gen_rows.py ../../test/core_lang/test_lb5_swipl.jl; swipl -q lb5_driver.pl </dev/null >lb5_rows.out` (twice, cmp), then `--fill`.
  UNVERIFIED on the kernel: every kernel answer. Likeliest to differ: kernel lacks stream_property/2 natively (boot/init.pl), the rows avoid it;
  lb010-011 (kernel open/4 record_position(false)); lb097-106 (the kernel does not restore a captured standard alias on close:
  restoreStandardStream NOT STARTED; the rows restore inside the row); at_end_of_stream/0, get_code/1, tab on user_input read process stdin: no row.
- 1fdaecd G5 committed (rows lb001-lb106 + evidence/LB5 generator/pins). Pins: two byte-identical swipl runs (done).
## WRITER 2 HAND-BACK (150k cap). LEFT, in order:
A. (optional, small) two more rows for the mutants: append at the END of CASES in the throwaway table (or add by hand to
   test/core_lang/test_lb5_swipl.jl `_LB5_CASES`, then re-run evidence/LB5/gen_rows.py + swipl x2 + --fill): lb107
   `write_size('abcd\nx', W, H, []), R = W-H` (widest line is not the last; kills a mutant `width = pos.linepos`), lb108
   `line_count(user_output, N), integer(N), R = yes` (alias argument). Then bump the header "(lb001-lb106)" and the
   `length(answered) >= 95` / noans list stay valid unless a new row has no answer.
B. G6 tools/mutants/LB5.py (model tools/mutants/MOD3b.py: header comment, TS/TARGETS lists, `MUTANTS = [dict(id=, file=, old=, new=, targets=)]`).
   TARGETS: test/core_lang/test_lb5_swipl.jl first, then per mutant (grep -l result, non-recursive globs):
   current_output/input: test_io.jl, test_write_family_swipl.jl, test_canonical_readatom_swipl.jl, files/test_open_close_swipl.jl, test_blob.jl, test_compare_swipl.jl;
   line_count/position: core_text/test_io.jl, files/test_stream_swipl.jl, core_lang/test_s2a_swipl.jl, test_pr1_swipl.jl, test_module_swipl.jl;
   set_stream alias: core_lang/test_s2a_swipl.jl, core_text/test_io.jl, test_write_family_swipl.jl, test_canonical_readatom_swipl.jl, files/test_open_close_swipl.jl;
   get_code: files/test_open_close_swipl.jl; put_code/put_char: core_text/test_read.jl. (D-0238: also the brief's four: write-family, canonical-readatom, s2a, open_close.)
   Candidate mutants (file, single-line `old` anchor to check EXACTLY once with a throwaway python3 -I script, `new`):
   1 src/os/pl-file.jl `            setStandardStream(ld, i, s)\n` (set_stream alias branch, ~2553) -> `            nothing\n` (kills al_out/al_err rows)
   2 pl-file.jl `        return s === cur\n` (current_io) -> `return s !== cur` (cur_out_inp/cur_in_outp rows)
   3 pl-file.jl `        is_stream_blob(ld, t) || return not_a_stream(ld, t, 0)\n` -> `nothing` (current_output(foo)/(1) rows)
   4 pl-file.jl `    n = (s.position::IOPOS).lineno\n` -> `.linepos` (pos rows)   5 `    n = (s.position::IOPOS).linepos\n` -> `.lineno`
   6 pl-file.jl `    while count > 0\n` (tab) -> `count >= 0` (tab0 row)   7 `    count === nothing && return false\n` (tab) -> `    nothing\n` (tab(a) row)
   8 pl-file.jl `    if rval < 0\n` (at_end_of_stream) -> `if rval > 0` (eos rows)
   9 pl-file.jl `Scurin(ld), :current_input)` -> `Scurout(ld), :current_input)` (cur_in_out row)
   10 pl-file.jl `    Sputcode(c, s)\n` (put_code; check it is unique, pl-file.jl may hold others) -> `    nothing\n` (put rows)
   11 pl-file.jl get_code2 the line `        (i == -1 || (a !== nothing && sym_key(a) == sym_key(mk_sym(T, :end_of_file)))) &&\n` -> `        false &&\n` (get_eofatom row; may survive if PL_get_char accepts end_of_file: then list as equivalent with that reason after reading PL_get_char)
   12 src/pl-arith.jl `        if toIntegerNumber(ld, n, 0)\n` -> `        if true\n` (tab(2.5) rows)   13 `                if fits\n` -> `                if true\n` (tab(1<<70) row; check uniqueness in pl-arith.jl)
   14 src/pl-write.jl `    height = (width > 0 || pos.lineno > 0) ? pos.lineno + 1 : 0\n` -> `    height = pos.lineno + 1\n` (ws_empty row)
   15 pl-write.jl `    (width > max_width || height > max_height) && return false\n` -> `width >= max_width` (ws_wok row)
   16 pl-write.jl `            pos.linepos > width && (width = pos.linepos)\n` -> `            width = pos.linepos\n` (needs lb107)
   17 pl-write.jl `        toldString(ld)\n` inside write_size (check the anchor is unique in pl-write.jl) -> `        nothing\n` (ws_ctx row)
   18 src/os/pl-option.jl `        i = PL_get_int64_ex(ld, val)\n` -> `        i = 0\n` (ws_wlimit/ws_hlimit rows; targets = LB5 rows file only)
   19 pl-file.jl getStreamWithPosition `SH_ERRORS | SH_ALIAS)` (check count in the file) -> `SH_ERRORS)` (needs lb108)
   EQUIVALENT (record with reason): `clearPrologFlagMask!(ld, PLFLAG_ISO)` and `ld.prolog_flag_mask = oldmask` in write_size (the ISO flag is
   clear by default and no row sets it). NOT LISTED: `if s.position === nothing` in getStreamWithPosition (swipl 10.1.19 gives
   ok-1/ok-0 even for open(..., [record_position(false)]) streams, lb010-011: no oracle row reaches the permission_error).
C. G7 manifest entries appended at the END of `_manifest_index` in test/static_analysis_manifest.jl (signatures: the G2+G3 list above, plus
   LK.pl_write_size4_va (Tuple{PL_local_data{T},Int,Int,control_t{T}} as the neighbours' pl_write_term3_va entry) and LK.write_size
   (ld, term_t, term_t, term_t, term_t); LK.PL_eval_expression_to_int64_ex, LK.tab etc. as listed) and a docs/architecture.md block at the END
   (never regenerate docs/port_inventory.md).
D. READY-FOR-GATE list (the playbook order): inventory (gate regenerates), `tools/warm.sh send` fmt on the changed files (src/os/pl-file.jl,
   src/os/pl-option.jl, src/pl-write.jl, src/pl-arith.jl, test/core_lang/test_lb5_swipl.jl, tools/mutants/LB5.py), `warm.sh check`, the new rows
   file on three term types (`warm.sh file test/core_lang/test_lb5_swipl.jl` x3 types), test/test_type_discipline.jl, manifest entries,
   `tools/pkgtest_way.sh test/core_lang/test_lb5_swipl.jl` (ONE at a time), alloc pins x3 [239/377/347/433] (pl-arith.jl/pl-file.jl are
   Tier-1 candidates: ask), the crash-term grep over diff + message, push `mutants/LB5` at the WIP SHA once tools/mutants/LB5.py exists, then
   branch-gate, push `gate/lb5` and `mutants/LB5` at the SAME SHA. Expect first-run kernel failures: the rows are UNVERIFIED.
E. Overlap with b2 (wip/lb4b2c, af6540c edits pl-file.jl get_stream_handle): conflict only in the PL_predicates_from_file table block.
