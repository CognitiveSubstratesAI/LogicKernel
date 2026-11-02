# BOOTPRED3: five boot-load-path predicates no step owns (audit D-0354 ruling 2) -- handoff (writer 2)

Worktree ~/code/lk-dstack, branch wip/bootpred3b = wip/bootpred3 rebased onto origin/main 2416adb (`git rebase --onto origin/main 9e0a983`,
no conflicts; wip/bootpred3 e7a0dc2 untouched for the EV1 stack). Pin cbf4e1896275, oracle swipl 10.1.19. Branches deleted: none.

## Commits on wip/bootpred3b (over 2416adb)
a447a3f $memberchk, 39517f2 $inc_message_count, ae0d9ef $notrace/$restore_trace, 14ed6ae prolog_listen, 69c5dd7 variant_sha1 (writer 1, rebased),
d0f0ec2 WIP rows, 7ff833e rows pinned (98 driver lines: 'ok' + 97 cases, two byte-identical swipl runs; gen_rows.py in evidence/BOOTPRED3/).
LAST COMMIT (this handoff's) carries the still-uncommitted work listed below, all in ONE commit because the commit hook wants the whole
tree staged (the hold-aside trick for separate commits needs a second pass): test/core_lang/test_bootpred3_swipl.jl (_B3_KNOWN filled),
tools/mutants/BOOTPREDSUB.py, test/static_analysis_manifest.jl, docs/architecture.md. The fresh agent may leave it as one commit.

## Smoke run (reference term type, warm daemon logickernel-warm-b4dc834e in lk-dstack, started 17:4x UTC, LEFT RUNNING)
Before _B3_KNOWN: 111 pass, 7 fail, exactly the predicted known differences, nothing else (bp3m16, the 12000-cell list, passes):
bp3i11, bp3i12 (counters 0 vs 1), bp3n01 and bp3n18 (skip level -1 vs swipl's 0), bp3n07 (-1 vs -2), bp3l33 (listener not kept, 0 vs 1),
bp3v15 (digest value). _B3_KNOWN now pins the kernel's exact lines with swipl's answer in a comment, and a new testset checks each known
line differs from the pin. NOT RE-RUN since: a three-type run was started (`tools/warm.sh file test/core_lang/test_bootpred3_swipl.jl`,
log in the old agent's scratchpad smoke_all.log, may be lost): the gate agent re-runs the file on all three types. The test file's
TERM TYPES line says REFERENCE, so the run may cover one type only.

## Rows: 97 cases = bp3m01-18, bp3i01-12, bp3n01-19, bp3l01-33, bp3v01-15
## Mutants: tools/mutants/BOOTPREDSUB.py (33 mutants, anchors checked once each by a throwaway python3 -I checker; TARGETS = the rows file only).
NAME CLASH: tools/mutants/BOOTPRED3.py already exists on main (the landed BOOTPRED group's list, ids BOOTPRED-*): mine is BOOTPREDSUB.py,
ids BP3-*. The dispatcher's mutants/BOOTPRED3 branch must run BOOTPREDSUB.py (or rename it). Anchors need a re-fit after fmt.

## Done / left
Done: rebase, pins, known-difference mechanism, mutants, manifest (per-T list end after Q10's entry + three `_extension_sigs` table entries at the
end of _DISPATCH_MANIFEST_TUPLE), docs (a src/pl-event.jl row at the end of "What is here now", a BOOTPRED3 block at the end of the file),
stale-pin hunt (only test/core_lang/test_hash.jl:19-23 named variant_sha1/2 as no Prolog predicate: reworded; no existence_error pins found).
Left: gate order (see below); regenerate docs (code graph in docs/architecture.md, docs/port_inventory.md) at the gate.
Unverified: manifest tuple types (GD/LD/Union{Nothing,T}) are written by reading, the static check decides; mutant anchors after fmt.

## Flags for the audit
- `abort` is an event NAME (rows bp3l20, src/pl-event.jl): the term grep hits it, no crash detail anywhere.
- swipl's FIRST `'$notrace'` skip level is 0, not -1 (writer 1 assumed -1): the kernel's -1 is a recorded known difference (rows bp3n01, bp3n07, bp3n18).
- `'$inc_message_count'` counters and `prolog_listen` hooks: known differences (rows bp3i11, bp3i12, bp3l33); a prolog_listen on a predicate (`foo/1`) throws
  NotPortedError naming EV1 (swipl accepts it): NO row, a Julia throw may escape the query.
- pl-termhash.jl registers variant_sha1/2 only: variant_hash/2 and term_hash/2 on the cells stay deferred.
- Machine: the load stayed above 8 for an hour (two other daemons); the daemon was started at 7.1 and the load rose to 18 during the cold compile.

## Gate order afterwards
warm.sh fmt (committed files via warm.sh send), inventory, check, rows x3, test/test_type_discipline.jl, pkgtest_way on the rows file,
push mutants/BOOTPRED3 at the WIP SHA (running BOOTPREDSUB.py), branch-gate, term grep, gate push on a fresh name. Tier 3 (no Tier-1 file touched).
Daemon lk-dstack: free to stop (dispatcher).
