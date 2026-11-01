# S2a handoff — os/pl-file.c boot-referenced stream predicates (D-0306 item 2)

Branch wip/s2a (off origin/main 584476f), worktree ~/code/lk-s2a. Writer: edit-only, nothing run, nothing pushed.
Upstream: swipl-devel cbf4e189, src/os/pl-file.c (line numbers below are that file's).

## Verified list (17 predicates; boot call confirmed in boot/*.pl at the pin; NOT REGISTERED on origin/main)
| predicate | upstream | boot caller (file:line) | Julia site |
|---|---|---|---|
| prompt/2 | 3735 | init.pl:1701 (directive) | src/os/pl-file.jl, LD fields `prompt_*` |
| prompt1/1 | 3778 | toplevel.pl:1324, history.pl:140 | same |
| $push_input_context/1, $pop_input_context/0, $input_context/1 | 1623, 1635, 1647 | init.pl:813,817,847,1879 | LD `IO_input_stack` |
| flush_output/1 | 5516 (helper 5497) | messages.pl:2614 | pl-file.jl |
| ttyflush/0 | 3690 | history.pl:130 | pl-file.jl |
| is_stream/1 | 5476 | messages.pl:375 | pl-file.jl |
| $alias_stream/2 | 5457 | init.pl:902 | pl-file.jl |
| get_char/2 | 3676 | toplevel.pl:1390 | pl-file.jl |
| peek_char/2 | 5954 | init.pl:2108 | pl-file.jl |
| skip/2 | 3549 | init.pl:2109 | pl-file.jl |
| get_single_char/1 | 3557 | init.pl:1039,3581 | pl-file.jl |
| $stream_property/2, $stream_properties/2, $streams_properties/2 | 5265, 5344, 5387 (sprop_list 5208) | init.pl:891-907 | pl-file.jl |
| set_stream/2 | 2520 (set_stream_info 2437) | init.pl:2011,2117,2127,2130; syspred.pl | pl-file.jl |

## Moved to R3 on evidence (4 predicates, not ported)
get/1, get/2, put/1, put/2: in boot/dicts.pl:62-65 they are `is_dict_func(get(_))` facts and
`eval_dict_function(get(Key), ...)` heads, and `Context.get(stack)` / `Dict.put(Opt,V)` in messages.pl:1048,
tabling.pl:1373, toplevel.pl:1030: dict-function names, never a call of the Edinburgh get/put predicates.

## Collision check with landing B (wip/dstack-b4, read only)
B adds to src/os/pl-file.jl: setStandardStream, pushOutputContext/popOutputContext, redirect (setupOutputRedirect...),
tellString/toldString, PL_predicates_from_redirect, and the `IO_output_stack` field at the END of PL_local_data
(pl-global.jl). None of the 17 predicates is in B. Expected rebase conflicts, all append-vs-append: the end of the
PL_local_data field list, the end of its positional constructor, and the pl-global.jl header comment.
S2a adds `prompt_*` and `IO_input_stack` fields after `recorded_states`; resolve by keeping both blocks.
flush_output/0 is S2b's (inventory); flush_output/1 here shares upstream's `flush_output(out)` helper.

## Plan (commit estimate 11)
1. plan (this file)
2. prompt/2, prompt1/1 (+ LD fields; pl-global.jl struct = Tier-1 contact, FLAG)
3. $push_input_context/1, $pop_input_context/0, $input_context/1
4. flush_output/1, ttyflush/0, is_stream/1, $alias_stream/2
5. get_char/2, peek_char/2, skip/2, get_single_char/1
6. $stream_property/2, $stream_properties/2, $streams_properties/2
7. set_stream/2
8. oracle rows test/core_lang/test_s2a_swipl.jl (+ generator, .out) and 9. tools/mutants/S2A.py (may merge 8+9)
10. docs/architecture.md block   11. manifest entries (own commit, LAST)

## State
Written and committed (src/os/pl-file.jl, src/pl-global.jl; nothing run, nothing pushed):
- 4223452 prompt/2, prompt1/1 + LD fields `prompt_current/prompt_first/prompt_first_used`, `IO_input_stack`, struct `input_context{T}` (pl-global.jl)
- 28b2925 $push_input_context/1, $pop_input_context/0, $input_context/1
- c78eec4 flush_output/1 (+ helper flush_output), ttyflush/0, is_stream/1, $alias_stream/2
- 10f69ce get_char/2, peek_char/2, skip/2, get_single_char/1 (+ PL_unify_char, Sgetcode_intr, getSingleChar)
All entries are in `PL_predicates_from_file` in upstream's order; its DIVERGES header comment lists them.

LEFT (next agent; 5 of the 12 commits used incl. the plan and this handoff):
6. `$stream_property/2`, `$stream_properties/2`, `$streams_properties/2` (pl-file.c:4784-5440, sprop_list 5208): one commit.
   Idiom: a table of (functor name, arity, function) tuples; properties as `stream_*_prop(ld, s, prop::term_t)` functions
   returning Bool. Julia sites: `getStreamContext(gd, s)` / `gd.stream_alias_names[s.context]` (alias list, as
   PL_unify_stream_or_alias at pl-file.jl:~492), `standardStreamIndexFromName/FromStream`, `unify_stream_ref`, `_stream_of(gd, serial)`
   and `gd.stream_table` (what the C `streamContext` table enumerates; skip nothing/erased entries), `encoding_names` (reverse
   lookup for encoding/1; `PL_encoding_to_atom` has no Julia port yet: write it from `encoding_names`), the unicode_atoms
   table (look for `atom_to_unicode_atoms_ex` in pl-file.jl/pl-stream.jl), `s.posbuf`/`s.position` (position/1 is
   '$stream_position'(Char,Line,LinePos,Byte): PL_unify_functor + PL_unify_arg), file_name/1 reads the context's filename
   (`setFileNameStream` at pl-file.jl:43 shows where it is kept). Properties the stream layer cannot answer: file_no (no fd:
   answer false), nlink, close_on_exec, reposition via fstat, timeout (IOSTREAM has no timeout field), locale: each a DIVERGES
   comment citing the upstream line, result `false`; flag them as representation-only.
   There is NO PL_unify_term, PL_put_functor or PL_get_arg in the Julia FLI: build a property with
   `PL_unify_functor(ld, t, name, arity)` on a fresh term ref, then `_PL_get_arg(ld, i, t, a)` (pl-fli.jl:544) and
   `PL_unify_*` (see pl_input_context1_va for the idiom). `$streams_properties/2` needs `can_unify` (not in Julia: find how
   neighbours test "unifiable", e.g. unifiable/3 in pl-prims.jl, or use a mark, PL_unify and undo) and an enumeration of `gd.stream_table`.
7. `set_stream/2` (pl-file.c:2250-2420 the property setter, ss_info table 2437, entry 2520): one commit. Already in Julia:
   `set_eof_action`, `set_buffering`, `stream_encoding_options`, `PL_atom_to_encoding`, `bad_encoding`,
   `atom_to_newline_mode`, `aliasStream`/`unaliasStream`, `setFileNameStream`, `ScheckBOM` (pl-stream.jl:1079). Missing in the
   stream layer (refuse with a DIVERGES comment citing the upstream line; flag for the audit): `Sset_timeout`, `Ssetlocale`,
   `setCloseOnExec`; check `Ssetenc` in pl-stream.jl first.
8. test/core_lang/test_s2a_swipl.jl (ids s01..) + generator/driver/.out from swipl 10.1.19 (style: test_style_check_swipl.jl
   on wip/q10); rows: prompt/2 (old/new, same atom, type_error), prompt1/1 (var, atom, string, number), input context push/pop
   round trip with $input_context, flush_output/1 on user_output and a bad alias, is_stream/1, $alias_stream/2, get_char/2 and
   peek_char/2 and skip/2 over open/3 of a temp file (open via a helper clause), $stream_property/2 over properties, a few
   set_stream/2 (encoding, alias, file_name, eof_action, buffer). Zero-argument compounds only through a helper clause.
9. tools/mutants/S2A.py (>= 2.5 per commit; TARGETS test_s2a_swipl.jl plus every file exercising pl-file.jl streams: find
   them with `git grep -l 'open(' -- test/core_lang`), validated by a scratchpad checker.
10. docs/architecture.md block (appended)   11. test/static_analysis_manifest.jl entries (own commit, LAST).

## STATE after coder 2 (read this first; supersedes the LEFT list above)
Committed: 97a3dc2 = group 6 (`$stream_property/2`, `$stream_properties/2`, `$streams_properties/2`, sprop_list of 26,
term_stream_handle, PL_encoding_to_atom, unicode_atoms_to_atom, `_put_functor`, `_unify_sym`, SIO_NOERROR in pl-stream.jl,
3 registrations before `$alias_stream`). Nothing compiled or run. 6 commits over origin/main + this handoff commit.
Property choices (flag): file_no, nlink, close_on_exec, locale answer `false` (DIVERGES cites the upstream line);
timeout answers `infinite` (no stream here times out; the brief said false, infinite is swipl's default answer);
reposition = a Julia `IOStream` file handle (stands in for the fstat S_ISREG test), others false.

GROUP 7 (set_stream/2) is WRITTEN BUT NOT APPLIED: the cap hook stopped coder 2 before the edit. The complete code is in
`evidence/S2A/setstream_draft.jl` (set_stream, ss_info, SS_* consts, prop_get_stream, pl_set_stream2_va). To apply, in this order:
 1. src/os/pl-stream.jl, before `# PORT: pl-stream.c S__removebuf`, add `Ssetbuffer(s, buffer, size)::Nothing`
    (`S__setbuf(s, buffer, size) != -1 && (s.flags &= ~SIO_USERBUF)`), and `Ssetenc(s, enc)::Int` (pl-stream.c:1902; DIVERGES: no
    `control` function and no `old`; `s.encoding == enc` -> 0; else `s.encoding = enc`; `enc == ENC_OCTET` clears SIO_TEXT, else sets it; 0)
    and `Sresetesc(p::IOPOS)` (`p.esc_state = 0`, pl-stream.c:869).
 2. src/os/pl-file.jl, before `# PORT: pl-file.c BeginPredDefs as PL_predicates_from_file`, paste the draft, then add
    `symbol_stream_pair_not_allowed(ld, symbol::T)` (pl-file.c:659: `type_error(stream, Blob)` with message
    "operation is ambiguous on a stream pair"; the draft's pair branch currently builds a permission_error: replace the branch
    by `return symbol_stream_pair_not_allowed(ld, sblob) ? FTRUE : FFALSE`).
 3. Register `PL_extension("set_stream", 2, pl_set_stream2_va, PL_FA_VARARGS)` after the `$alias_stream` entry, extend the DIVERGES
    header comment of PL_predicates_from_file (add "and set_stream/2"), and in the file header (line ~27) drop `set_stream/2` from the NOT PORTED list.
 4. set_stream's refusals (flag to the audit): `alias(Std)` of a standard stream name -> NotPortedError ("setStandardStream, landing B": after the
    rebase onto B call B's `setStandardStream(ld, i, s)` and set the prompt.next equivalent; the kernel has no `prompt.next` field);
    `locale(L)` -> NotPortedError; `timeout(infinite)` -> true, other times -> upstream's `permission_error(timeout, stream, S)`;
    `close_on_exec(B)` -> upstream's no-descriptor `permission_error(close_on_exec, stream, S)`; `unicode_atoms(nfc)` -> NotPortedError;
    `buffer_size(N)` on an input stream holding more than N buffered bytes stops in S__setbuf's `@assert`. `LD->encoding` = ENC_UTF8.
    Commit subject: `UPSTREAM: os/pl-file.c set_stream prop_get_stream ss_info (swipl-devel cbf4e189)` (blank line after the subject!).
 The draft file is deleted from evidence/S2A in the commit that applies it (or kept as evidence; it is not code).

REMAINING after group 7 (5 commits of the 12 cap used incl. 97a3dc2 and the group-7 commit: total 8 + docs/rows/mutants/manifest = fold if the cap binds):
 8. oracle rows test/core_lang/test_s2a_swipl.jl (+ generator, driver, .out in evidence/S2A/): see the Plan above; add rows for
    `$stream_property` (mode, input, output, eof_action, type, buffer, encoding on an open/3 temp file; `alias` after set_stream alias; `file_name`
    after set_stream file_name), `$stream_properties` (sorted, compare only the properties the kernel answers the same: leave out file_no, nlink,
    close_on_exec, locale, timeout, reposition, position values that differ), `$streams_properties(mode(M), L)` sorted, set_stream encoding/eof_action/buffer/type/
    newline/representation_errors/write_errors/line_position errors. No tty. Mark kernel-only rows `# UNVERIFIED on the kernel: gate decides`.
 9. tools/mutants/S2A.py (about 2.5 per source commit; anchors `grep -c -F` once in this worktree; TARGETS = test_s2a_swipl.jl plus the S1 stream test files;
    validate with a scratchpad python3 -I + runpy checker).
10. docs/architecture.md appended block.   11. test/static_analysis_manifest.jl: new struct `input_context{T}`, new struct `sprop`, the 4 new PL_local_data fields'
    constructors (prompt_current, prompt_first, prompt_first_used, IO_input_stack), new consts SS_* / SIO_NOERROR if the manifest lists consts.
Flags added by coder 2: reposition/timeout/file_no/nlink/close_on_exec/locale choices above (representation-only); SIO_NOERROR (bit 13) added to pl-stream.jl;
landing B rebase: `IO_output_stack` appended at the end of PL_local_data and its constructor against our `IO_input_stack` block: append against append, keep both.
Daemon status: none used (edit-only).

## Flags for the audit
- Tier 1: src/pl-global.jl struct PL_local_data (4 fields appended after `recorded_states`; B appends `IO_output_stack` at the
  same place: rebase conflict, keep both) -> alloc pins x3 at the gate.
- DIVERGES (representation): atoms in prompt_* are not registered (no atom GC); getSingleChar has no tty raw mode (PushTty
  left out), so on a terminal get_single_char/1 is line-buffered, which differs from swipl: the audit may want a PushTty step
  before the toplevel runs interactively; `_initIO(ld)` at the head of the context functions.
- PL_unify_char lives in os/pl-file.jl (upstream: pl-privitf.c) taking a Symbol `how`.
- get/1, get/2, put/1, put/2 -> R3 (evidence above).
- Hook note: the absence-claim hook fires on 'NOT PORTED' in a COMMIT MESSAGE (code comments are not scanned); a heredoc or
  python edit and `git commit` in one Bash call are blocked (use the Edit/Write tools, then commit).

## Gate order (end of this step)
fmt (format committed files via `warm.sh send`), inventory, check, rows on all three term types, type discipline,
pkgtest_way on test_s2a_swipl.jl, the mutants branch, branch-gate, term grep, alloc pins x3 (pl-global.jl changed),
a gate push on a FRESH name.

## STATE after coder 3 (supersedes the LEFT lists above)
Committed (nothing compiled or run, nothing pushed), on wip/s2a over origin/main 584476f:
- 5a52eaf group 7 = set_stream/2 applied (draft deleted; Ssetbuffer, Ssetenc added to pl-stream.jl; Sresetesc already existed there;
  symbol_stream_pair_not_allowed added; registered after `$alias_stream`; file header and DIVERGES header updated).
- 44a1eb7 rows test/core_lang/test_s2a_swipl.jl (s001-s137), evidence/S2A/gen_rows.py (one extractor: reads program/cases/driver/data from the
  test file, runs swipl twice), s2a_rows.pl, s2a_driver.pl, s2a_rows.out (= .out2, byte-identical), s2a_rows.err (singleton warning only).
  Pins are filled (`--fill`). Kernel-judged rows are marked `# UNVERIFIED on the kernel: gate decides` (s056-57 binary get_char, s076-s079
  encoding/buffer_size/reposition/timeout, s119 encoding(bom)). Rows left out on purpose: timeout(Seconds), close_on_exec, alias(Std),
  locale, unicode_atoms(nfc), get_single_char/1 (stdin).
- f345530 tools/mutants/S2A.py (37 mutants, validated by a runpy checker: every old once, new != old, targets exist; S2A-T14 equivalent).
Commits used: 11 of 12 incl. the plan and handoffs (plan, 4 code, trio, set_stream, rows, mutants, 2 handoffs).

LEFT: (10) docs/architecture.md block, inserted before the line `## Still to come` (line ~5890; style: see the T2 block at ~5791: heading
`## S2a — ...`, bullets of what is done, DIVERGES, refusals); (11) test/static_analysis_manifest.jl entries (own LAST commit): struct
`input_context{T}`, struct `sprop`, the 4 new PL_local_data fields' constructors (prompt_current, prompt_first, prompt_first_used,
IO_input_stack), consts SS_* and SIO_NOERROR if the manifest lists consts, the new functions (look at how S1/LB2 entries read:
`grep -n 'pl_open4_va' test/static_analysis_manifest.jl`). Both fit in the 12th commit (fold docs + manifest into ONE commit if the cap binds;
manifest in the last commit).

FLAGS for the audit: Tier 1: src/pl-global.jl PL_local_data +4 fields (alloc pins x3); landing B (wip/dstack-b4) appends IO_output_stack at the
same end of the struct and its constructor: append against append, keep both. Representation-only: prompt atoms not registered; getSingleChar has
no tty raw mode; PL_unify_char lives in os/pl-file.jl. AUDIT-DECISIONS (behaviour): property answers false for file_no/nlink/close_on_exec/locale,
`infinite` for timeout (swipl's default), `reposition` true only for a Julia IOStream file handle. set_stream REFUSALS: alias(Std) of a standard
stream name raises NotPortedError pending B's setStandardStream; locale and unicode_atoms(nfc) raise NotPortedError; timeout(T) other than infinite
and close_on_exec(B) raise permission_error (swipl 10.1.19 accepts both on a file: known difference, rows leave them out); buffer_size(N) on an
input stream holding more than N buffered bytes stops in S__setbuf's @assert. Rows s010/s011: prompt1(_) answers ok in swipl after an earlier
prompt1 (the kernel unifies with prompt_first only when set).
Daemon status: none used (edit-only).
