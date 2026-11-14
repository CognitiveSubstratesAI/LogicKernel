# TH1A handoff (forced at the 150k cap; NOTHING COMMITTED; worktree ~/code/lk-th1a, branch wip/th1a on origin/main b29b887d)

## Done in the worktree (uncommitted)
1. src/pl-event.jl: table cut to NINE rows (the three `#ifdef O_ENGINES` rows PLEV_THREAD_START, PLEV_THREAD_EXIT,
   PLEV_THIS_THREAD_EXIT removed; trailing comma of the UNTABLE row removed); `:onthreadstart`/`:onthreadexit` branches removed from
   event_list_at and event_list_set!; the two elseif branches (thread events, NotPortedError naming TH1) removed from PL_call_event_hook_va;
   DIVERGES comments rewritten. `et.local_` branches kept (generic upstream code, no local row left).
2. test/core_lang/test_event_threads_off_swipl.jl (NEW, 292 lines, 21 rows th01-th21): kernel pins `_TH_KERNEL` (hand-derived, UNVERIFIED) and swipl 10.1.20
   pins `_TH_SWIPL` (written by swipl, driver in the file), `_TH_DIVERGES` = th01-th09, th16, th19, th20, th21 (13); controls th10-th15, th17, th18.
   Header carries the CHECKLIST item (second oracle D-0716 Q2 b). White-box testset: 9 rows, names, ids 0:8, no local row, PLEV_* constants kept.
   NOT PARSED YET (one parse-only Julia process over all touched .jl files is still owed).
3. Scratch (outside the repo): scratchpad th/ (driver.pl, prog.pl, swipl.out, lines.json) in the session scratchpad.

## NOT done (next agent)
a. src/pl-proc.jl ~:1683 comment (`setThreadLocalDefinition!`): replace the first DIVERGES sentence by the text in the report (CONFIGURATION paragraph):
   the kernel is ENGINES=OFF whose branch is the `#else` of pl-proc.c:3829-3838 (`setDynamicDefinition(def, val)` then set/clear `P_VOLATILE|P_THREAD_LOCAL`,
   always true; the O_ENGINES branch is pl-proc.c:3799-3828). The two differ visibly: static predicate WITH clauses declared thread-local (refused here, accepted there,
   no P_TRANSACT) and thread-local -> static (refused here, accepted there). Code still takes the oracle's branch: DESIGN QUESTION 1 below.
b. src/pl-global.jl:33 comment: "the thread events' lists exist in every build (O_ENGINES)" -> pl-global.h:308-309 are not conditional.
c. src/os/pl-prologflag.jl:45-47 already says ENGINES=OFF: no edit needed beyond (optional) a pointer to pl-event.jl's table.
d. docs/r2_owners.tsv: (i) the 17 pred rows (keys: $engine_create/3 $gc_clear/1 $gc_stop/0 $gc_wait/1 $sig_unblock/0 engine_next/2 is_engine/1 message_queue_create/1
   message_queue_destroy/1 set_thread/2 thread_create/3 thread_exit/1 thread_get_message/2 thread_join/2 thread_property/2 thread_send_message/2 thread_statistics/3):
   KEEP key and owner token TH1 (the parser takes key, owner, note; only the note changes), note -> `absent as upstream non-PLMT, DIVERGES vs threads=true oracle`.
   (ii) DELETE line 157 `refusal:src/pl-event.jl::PL_call_event_hook_va::the thread events (`unify_thread_id`)` (TH1): the refusal site is gone, the line would be R2-OWNER-STALE.
   (iii) Q4: `pred:$inc_message_count/1` is DONE in the kernel (pl-error.jl:1125-1160, rows bp3i), so an owner line with that key is R2-OWNER-STALE (tools/r2_status.jl
   r2_owner_violations: a key must name a missing or refused row; keys are pred/flag/vmi/refusal exact or cfile/kfile). Recommended: a COMMENT line at the end of the file
   (parser skips `#` lines): `# COUNTING OWNER (no row key: the predicate is done): '$inc_message_count'/1 and statistics(errors|warnings) counting, owner ERR/PRIMS, swipl row when added`,
   plus the same words in the DIVERGES comment of pl-error.jl:1128. (Needs a struct field in ld_statistics: a struct change.)
e. docs/architecture.md:7063 (hand-written EV1 section): "the 12-row `PL_events` table (the O_ENGINES build;" -> "the 9-row table (ENGINES=OFF since TH1a, D-0716; EV1 first kept the 12 rows of the O_ENGINES build;".
   The generated R2 status block regenerates (refusal rows -1; the by-owner list); do not hand-edit.
f. test/core_lang/test_bootpred3_swipl.jl: ROWS bp3l24, bp3l25, bp3l26 (prolog_listen of thread_start / thread_exit / this_thread_exit, pinned `yes` from swipl) now answer
   `raised(domain_error(event, <name>))` on the kernel: add three entries to `_B3_KNOWN` (ids t_bp3l24..26, lines `t_bp3l24 c[116,95,98,112,51,108,50,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,118,101,110,116],a[...codes of the name...])))`),
   comments quoting swipl's `yes`; fix the header sentence that lists the known rows. Without this the file FAILS (pre-existing test of main).
g. tools/mutants/BOOTPREDSUB.py: mutant BP3-L8 (`this_thread_exit` not accepted, KILL bp3l26) has no `old` any more (row removed): retire it with its reason in the header; renumber nothing.
h. tools/mutants/TH1A.py (format as EV1d.py / BOOTPREDSUB.py: TARGETS = test_event_threads_off_swipl.jl + test_event_swipl.jl + test_bootpred3_swipl.jl; V = "src/pl-event.jl"; `old` once each, count with python3 -I):
   M1 a thread event name is accepted: add back a row (old `event_type(PLEV_UNTABLE, :untable, 1, false, :onuntable)\n)` -> `...),\n    event_type(PLEV_THREAD_START, :thread_start, 1, false, :onthreadstart)\n)`) KILL th01, th04, th06, th09, th16 + the nine-row testset;
   M2 the `erase` row dropped (old: the PLEV_ERASED_RECORD row text) KILL the nine-row testset, ev1r*; M3 the id check: change the UNTABLE id to PLEV_FRAMEFINISHED KILL `all(i -> id == i)`;
   M4 unlisten of an unknown name answers true (old `PL_domain_error(ld, "event", type)` is shared with EV1d/BP3-L4: use a separate mutant on prolog_unlisten only if its text is unique) ; list `old` counts in the report.
i. Gates owed: one parse-only Julia process over src/pl-event.jl, test/core_lang/test_event_threads_off_swipl.jl, test_bootpred3_swipl.jl (and any other touched .jl); commit on wip/th1a
   (separate `git add` and `git commit`; category MODIFIED: or UPSTREAM: pl-event.c ... (swipl-devel 18168e62); body 5-10 lines; Co-Authored-By line of the brief); DO NOT push.

## The C quotes for the report (pin 18168e62, src/pl-event.c)
- :81-89 nine rows `GEVENT(PLEV_ABORT ...)` ... `GEVENT(PLEV_UNTABLE, ATOM_untable, 1, onuntable),`; :90 `#ifdef O_ENGINES`; :91 `GEVENT(PLEV_THREAD_START, ATOM_thread_start, 1, onthreadstart),`
  :92 `GEVENT(PLEV_THREAD_EXIT, ATOM_thread_exit, 1, onthreadexit),` :93 `LEVENT(PLEV_THIS_THREAD_EXIT, ATOM_this_thread_exit, 0, onthreadexit),` :94 `#endif`.
- :682-691 `#ifdef O_ENGINES case PLEV_THREAD_START: case PLEV_THREAD_EXIT: { ... unify_thread_id(av+1, info) } case PLEV_THIS_THREAD_EXIT: break; #endif` (callEventHook).
- get_event_listp :208-238: `if ( arity == 0 ) { for(et=PL_events; et->name; et++) { if ( et->name == name ) {... return true;} } } else if ( get_procedure(type, &proc, 0, GP_RESOLVE|GP_NAMEARITY) ) {...}` then :235 `return PL_domain_error("event", type);`
  So with no row, `prolog_listen(thread_start, G)` (arity 0, no match) answers domain_error(event, thread_start); prolog_listen/3 order: options, `as` check (domain_error(as, ...)) BEFORE the event lookup, the closure's callable check AFTER it.
- pl-event.h:52-54 the three enum ids and pl-global.h:308-309 / :707 the list fields are NOT conditional; extern table `PL_events[PLEV_THIS_THREAD_EXIT+2]` (:120).
- pl-event.jl before the edit kept 12 rows; the 3 removed: thread_start, thread_exit, this_thread_exit (the rows between `#ifdef O_ENGINES` and `#endif`).

## Design questions for the dispatcher
1. ENGINES=OFF branch of setThreadLocalDefinition (pl-proc.c:3829-3838): the kernel keeps the O_ENGINES branch's behaviour. Declaring ENGINES=OFF makes that a known divergence
   (two visible cases above). Options: (a) port the `#else` branch now (small: a 6-line function, but the thread_local rows pinned against the threaded oracle change and `$local_definitions/2`
   (pl-proc.c:4426-4428, O_ENGINES only) must stay absent); (b) keep and record it (recommended for this step: its own small step with rows, swipl cannot answer it: needs the Q2(b) second oracle).
2. $inc_message_count owner line cannot be a row key (it is a done predicate): comment-line owner (recommended) or a refusal site in statistics errors/warnings.

## TH1A2 (second agent): the remaining list a-g is DONE and committed on wip/th1a (not pushed)
- Corrected a claim above: pl-global.h:307-310 (the `onthreadstart`/`onthreadexit` list fields) and :705-707 (the LD's `onthreadexit`) ARE inside `#ifdef O_ENGINES`; only the
  pl-event.h enum ids are unconditional. The fields stay in the kernel structs as never-set fields (comments in pl-event.jl, pl-global.jl say so).
- Comments: pl-proc.jl setThreadLocalDefinition! (`#else` branch pl-proc.c:3829-3838 recorded as DIVERGES, dispatcher ruling (b)), pl-global.jl, pl-error.jl (counting owner ERR/PRIMS).
- docs/r2_owners.tsv: 17 TH1 pred notes retagged, the pl-event refusal line deleted, two `#` owner lines at the end (thread-local branch; message counting).
- docs/architecture.md: both "12-row" mentions (:934 file table, :7063 EV1 section) now say 9-row.
- test_bootpred3_swipl.jl: `_B3_KNOWN` entries t_bp3l24..26 (exact kernel answer domain_error(event, <name>)), header sentence updated.
- tools/mutants/BOOTPREDSUB.py: BP3-L8 retired (reason in the header); tools/mutants/TH1A.py: M1-M4, `old` count 1 each.
- NOT RUN (edit-only step): the parse of the touched .jl files (the cold-start hook refused the one parse-only process; not retried), every test, fmt, check.
