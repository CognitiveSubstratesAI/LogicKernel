# ORIGINAL: the TH1A mutant list (the event table of the kernel's ENGINES=OFF build, src/pl-event.jl) — no swipl-devel counterpart.
# tools/mutants/TH1A.py — the mutation battery of step TH1a (audit D-0716 item 7: the kernel is MULTI_THREADED=OFF ENGINES=OFF; the
# `PL_events` table has the nine rows of pl-event.c:81-89 and the three thread events of `#ifdef O_ENGINES` (:90-94) are not rows). Run ONCE,
# in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as EV1d.py and BOOTPREDSUB.py):
# `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_event_threads_off_swipl.jl
# (rows th01-th21 and its white-box testset "the table has nine rows"); the KILL lists are what the rows are EXPECTED to do (read, not run):
# the battery's verdict is the evidence. Verdicts: written by the battery, not yet run. Every `old` was checked to occur exactly once in
# its file with a throwaway `python3 -I` script (a text count, no Julia).
# NOT LISTED: the dead `onthreadstart`/`onthreadexit` fields (src/pl-global.jl: never set, nothing reads them) and the `PLEV_THREAD_*` enum ids
# (pl-event.h:52-54, kept): no row can observe them.
# TARGETS (audit D-0238): every test file that reaches the table: the new file, test_event_swipl.jl and test_bootpred3_swipl.jl
# (prolog_listen/2,3 rows).
TARGETS = [
    "test/core_lang/test_event_threads_off_swipl.jl",
    "test/core_lang/test_event_swipl.jl",
    "test/core_lang/test_bootpred3_swipl.jl",
]
V = "src/pl-event.jl"
MUTANTS = [
    dict(id="TH1A-M1 the event `thread_start` is a row of the table again: it is accepted (KILL th01, th04, th06, th09, th16, bp3l24, the nine-row testset)",
         file=V, targets=TARGETS,
         old="    event_type(PLEV_UNTABLE, :untable, 1, false, :onuntable)\n)",
         new="    event_type(PLEV_UNTABLE, :untable, 1, false, :onuntable),\n    event_type(PLEV_THREAD_START, :thread_start, 1, false, :onthreadstart)\n)"),
    dict(id="TH1A-M2 the second `erase` row (the record's) is dropped from the table (KILL the nine-row testset: its length, names and ids)",
         file=V, targets=TARGETS,
         old="    event_type(PLEV_ERASED_RECORD, :erase, 1, false, :onerase),\n",
         new=""),
    dict(id="TH1A-M3 the `untable` row carries the id of `frame_finished` (KILL the nine-row testset's `all(i -> id == i)`)",
         file=V, targets=TARGETS,
         old="    event_type(PLEV_UNTABLE, :untable, 1, false, :onuntable)",
         new="    event_type(PLEV_FRAMEFINISHED, :untable, 1, false, :onuntable)"),
    dict(id="TH1A-M4 a name without a row raises nothing: the listen fails silently (KILL th01-th09, th14, th15, bp3l24, bp3l25, bp3l26, bp3l13)",
         file=V, targets=TARGETS,
         old="        PL_domain_error(ld, \"event\", type)\n        return nothing\n",
         new="        return nothing\n"),
]
