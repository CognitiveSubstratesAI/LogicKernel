# ORIGINAL: EV1T's mutant list, a test tool of this repository (not the port of a swipl-devel file).
# tools/mutants/EV1T.py — the mutation battery of TAB1 EV1T (the new-answer event of a monotonic table: `atrie_answer_event` of src/pl-tabling.jl = pl-tabling.c:11443-11463
# at 18168e62, and `table_answer_event` of src/pl-event.jl = pl-event.c, the save and restore of the tabling status around the listeners). Run ONCE, in CI
# (.github/workflows/mutation.yml; locally: one mutant at a time under tools/mutate.sh).
# Format: tools/mutate_drive.py's (as TB9.py, TBW2.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# NOT RUN YET (written edit-only on wip/ev1e, 2026-11-14, nothing compiled, nothing run): every KILL below is an EXPECTATION read off the rows of the events test, none observed;
# the kernel answers of the rows are themselves unverified until the gate: a row that fails on the unmutated tree has no kill value. A mutant that survives the first
# hand-run is either killed by a new row or recorded equivalent with its code reason before the commit lands.
# KILL ROWS: EV = test/core_lang/test_tabling_events_swipl.jl: `ev02`-`ev13` = the cases of the testset "the new-answer event of a tabled predicate as swipl's (ev02-ev13)"
#   (the listener log of each case is compared with swipl 10.1.20's pin); `ev01` = "ev01: the upstream test mono_abstract/new_answer"; `wb` = the testset
#   "atrie_answer_event sends nothing and answers true when it cannot (wb)" (rows `r_novariant`, `r_nopred`, the no-listener call); `wbstatus` = the testset "the tabling status
#   is back after the hook, also after a raising listener (wb)".
# TARGETS (audit D-0238): EV (the step's own file); TM (test_tabling_monotonic_swipl.jl: every monotonic table that adds an answer runs `$tbl_monotonic_add_answer/2`, hence
# `atrie_answer_event`, with and without listeners); W2 (test_tabling_w2_swipl.jl: its `save_tabling_status` / `restore_tabling_status` rows and the monotonic units).
# Every `old` was counted EXACTLY once in its file at wip/ev1e by python3 -I ~/code/lk-t27-scratch/oldscan.py EV1T (the scan runs Python only). RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
EV = "test/core_lang/test_tabling_events_swipl.jl"
TM = "test/core_lang/test_tabling_monotonic_swipl.jl"
W2 = "test/core_lang/test_tabling_w2_swipl.jl"
TARGETS = [EV, TM, W2]
TAB = "src/pl-tabling.jl"
EVT = "src/pl-event.jl"
MUTANTS = [
    dict(id='EV1T-T1-guard (EQUIVALENT, expected: the `events !== nothing` test only spares the term references; with no listener `call_event_list(nothing)` answers true and the status is restored, so no row can read the difference; ev04, ev05, wb run the path and must stay green)',
         file=TAB, targets=TARGETS,
         equivalent='pl-event.jl:441-448 (call_event_list answers true for a list of nothing) and pl-event.jl:714-722 (save and restore of the tabling status pair): the guard of atrie_answer_event is an optimisation, as pl-tabling.c:11443-11463 where `def->events` spares the term references; UNVERIFIED until the first hand-run: if the term references outside a foreign frame (wb no-listener call) raise, wb kills it',
         old='    if def !== nothing && def.events !== nothing\n        wrapper = PL_new_term_ref(ld)\n',
         new='    if def !== nothing && true\n        wrapper = PL_new_term_ref(ld)\n'),
    dict(id='EV1T-T2-action (KILL EV ev02, ev03, ev06, ev09, ev13: the listener sees `answer` for `new_answer`, the logged event differs from the pin)',
         file=TAB, targets=TARGETS,
         old='table_answer_event(_query_gd(ld), ld, def, mk_sym(T, :new_answer), wrapper) &&\n',
         new='table_answer_event(_query_gd(ld), ld, def, mk_sym(T, :answer), wrapper) &&\n'),
    dict(id='EV1T-T3-skeleton (KILL EV ev02, ev03: the wrapper stays unbound, the listener logs `user:_` for `user:ev_b(c)`)',
         file=TAB, targets=TARGETS,
         old='           unify_skeleton(ld, atrie, wrapper, skel) &&\n',
         new='           true &&\n'),
    dict(id='EV1T-T4-answer (KILL EV ev02, ev03, ev06: the answer is not unified into the skeleton, the listener logs `user:ev_b(_)` for `user:ev_b(c)`)',
         file=TAB, targets=TARGETS,
         old='           unify_trie_term(ld, atrie, nid, skel)[1]\n',
         new='           true\n'),
    dict(id='EV1T-T5-hooktrue (KILL EV ev02: a successful hook answers false, the add of the answer answers `no` for `yes`; ev03, ev06)',
         file=TAB, targets=TARGETS,
         old='table_answer_event(_query_gd(ld), ld, def, mk_sym(T, :new_answer), wrapper) &&\n                return true\n',
         new='table_answer_event(_query_gd(ld), ld, def, mk_sym(T, :new_answer), wrapper) &&\n                return false\n'),
    dict(id='EV1T-T6-exception (KILL EV ev07: a failing listener (no exception) turns the add into `no` for `yes`; ev08: a raising listener no longer raises)',
         file=TAB, targets=TARGETS,
         old='            return PL_exception(ld, 0) == 0\n',
         new='            return PL_exception(ld, 0) != 0\n'),
    dict(id='EV1T-T7-nopred (KILL EV wb `r_nopred`: with `tr.predicate = nothing` the guard reads `nothing.events`, an error for `true`)',
         file=TAB, targets=TARGETS,
         old='    if def !== nothing && def.events !== nothing\n        wrapper = PL_new_term_ref(ld)\n',
         new='    if def.events !== nothing\n        wrapper = PL_new_term_ref(ld)\n'),
    dict(id='EV1T-T8-fallout (KILL EV wb `r_novariant` and the no-listener call, ev04: every branch that sends nothing answers false for true)',
         file=TAB, targets=TARGETS,
         old='        end\n    end\n\n    return true\nend\n\n\n# ── the predicates of the monotonic tabling',
         new='        end\n    end\n\n    return false\nend\n\n\n# ── the predicates of the monotonic tabling'),
    dict(id='EV1T-T9-save (KILL EV ev10 and wbstatus: the status is not saved, the findall of a listener that calls a tabled predicate joins the outer evaluation and `restore` sets `saved_status` from a stale value)',
         file=EVT, targets=TARGETS,
         old='        save_tabling_status(ld, tblstat)\n',
         new=''),
    dict(id='EV1T-T10-restore (KILL EV wbstatus: after the event `saved_status` stays set, `tb.saved_status === nothing` fails for ev02, ev07, ev08, ev10)',
         file=EVT, targets=TARGETS,
         old='        restore_tabling_status(ld, tblstat)\n',
         new=''),
]
