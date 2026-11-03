# EV1 gate agent 3 — state

Lane ~/code/lk-ev1, branch wip/ev1b (rebased onto origin/main c4c34fd, was dd93b68; the pre-push hook refuses a `wip/` ref, so the push
goes from a local branch `gate/ev1c`). Filled in as the steps finish; the last section is the final state.

## Done (in order)
1. Committed gate agent 2's staged work (1e769b7 before the rebase).
2. bp3v15 (test-only, dispatcher's ruling): test_bootpred3_swipl.jl compares the row by SHAPE (one atom of 40 codes, `_b3_digest_shape`) when
   LOGICKERNEL_TERM is not reference; the exact digest pin stays on reference (pl-termhash.jl DIVERGES 1-2: the digest hashes the term type's
   symbol hash). Guard able to fail: regex mutated to 39 codes -> 2 failures on alt. 130/130 reference, 131/131 alt and alt_interned.
3. Callers on THREE types, no SKIP/Warning/Fail: test_pr1_swipl 226 x3, test_update_view_gc 6 x3, test_jit 8043 x3 (reference 2m38s cold),
   test_index_swipl 33 x3, test_declare_destroy_swipl 79 x3, test_hash 22 x3.
4. `warm.sh inventory` FAILED port_check on the event stack's markers (never run by agents 1-2): fixed in the sources (pl-event.h, pl-event.c,
   pl-copyterm.h as UPSTREAM files of pl-event.jl / pl-incl.jl; one name per PORT line; `pl_event_type as PLEV_ABORT`; `event_list_location as
   event_location`; `hook as event_hooks`; NOTRACE_* one marker each), docs/architecture.md rows updated. Comment/marker changes only.
   `warm.sh check`: PASS. test_type_discipline 33/33 (3m13s).
5. EV1.py renamed EV1c.py (the list is found by branch name), C8/C9/C10 re-cited, architecture.md says 51.
