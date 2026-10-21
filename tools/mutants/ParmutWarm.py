# ORIGINAL: ParmutWarm's mutant list — no swipl-devel counterpart.
# tools/mutants/ParmutWarm.py — the three guards of warm.sh's sibling-mutant opt-in (D-0077 item 6, 2026-10-21).
# Run LOCALLY, not in CI: the target is tools/test_warm.sh's guard cases, which need a user systemd (the CI
# mutation runners have none, and a skipped case would let every mutant survive).
#   tools/mutate.sh run-parallel 3 tools/mutants/ParmutWarm.py "sh:tools/test_warm.sh guard"
TARGETS = [
    "sh:tools/test_warm.sh guard",
]
WS = "tools/warm.sh"
T = ["sh:tools/test_warm.sh guard"]
MUTANTS = [
    dict(id="PW1 every mutant-worktree daemon is excused, with or without the opt-in", file=WS, targets=T,
         old='''        [ "${LOGICKERNEL_WARM_SIBLING_MUTANTS:-}" = 1 ] && [ -n "$wd" ] &&
            [ -f "$wd/.warm/MUTANT_WORKTREE" ] && continue''',
         new='''        [ -n "$wd" ] && [ -f "$wd/.warm/MUTANT_WORKTREE" ] && continue'''),
    dict(id="PW2 the opt-in excuses every other checkout's daemon", file=WS, targets=T,
         old='''        [ "${LOGICKERNEL_WARM_SIBLING_MUTANTS:-}" = 1 ] && [ -n "$wd" ] &&
            [ -f "$wd/.warm/MUTANT_WORKTREE" ] && continue''',
         new='''        [ "${LOGICKERNEL_WARM_SIBLING_MUTANTS:-}" = 1 ] && continue'''),
    dict(id="PW3 the opt-in excuses nothing", file=WS, targets=T,
         old='''        [ "${LOGICKERNEL_WARM_SIBLING_MUTANTS:-}" = 1 ] && [ -n "$wd" ] &&
            [ -f "$wd/.warm/MUTANT_WORKTREE" ] && continue''',
         new='''        [ "${LOGICKERNEL_WARM_SIBLING_MUTANTS:-}" = 99 ] && [ -n "$wd" ] &&
            [ -f "$wd/.warm/MUTANT_WORKTREE" ] && continue'''),
]
