# BOOTPRED3: five boot-load-path predicates no step owns (audit D-0354 ruling 2) -- handoff

Worktree ~/code/lk-dstack, branch wip/bootpred3 (off main 9e0a983). Writer: Sonnet. Pin: swipl-devel cbf4e1896275 (pin tree ~/dev-zone/swipl-devel-cbf4e189). Oracle: swipl 10.1.19.
One smoke run (warm.sh file, three term types) is the only Julia run; no gate.

## Groups (commit order); upstream sites read from the pin tree
1. [ ] plan (this file)
2. [ ] `$memberchk`/3: pl-list.c:109-152 -> src/pl-list.jl `pl_memberchk3_va`, table `PL_predicates_from_list`
3. [ ] `$inc_message_count`/1: pl-error.c:1457-1474 -> src/pl-error.jl, table entry in PL_predicates_from_error (new)
4. [ ] `$notrace`/2 + `$restore_trace`/2: pl-pro.c:317-390 (they live in pl-pro.c, not pl-trace.c) -> src/pl-pro.jl
5. [ ] `prolog_listen`/2 (and /3 by the same function): pl-event.c:241-290 + add_event_hook/get_event_listp/get_callback -> new src/pl-event.jl
6. [ ] `variant_sha1`/2 registration: pl-termhash.c:651-700 -> src/pl-termhash.jl (body `pl_variant_sha1` exists)
7. [ ] rows (one test file per sub-part, swipl oracle), tools/mutants/BOOTPRED3.py, manifest, docs block, handoff update

## Flags for the audit (filled as found)
