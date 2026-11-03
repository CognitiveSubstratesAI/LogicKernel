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
