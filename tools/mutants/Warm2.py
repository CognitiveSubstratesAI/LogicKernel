# ORIGINAL: Warm2's mutant list — no swipl-devel counterpart.
# tools/mutants/Warm2.py — the mutation battery of the second-daemon restart fix (audit D-0130 item 2, A-0079 item 5:
# tools/warm.sh `_restart` and the `.warm/second` marker; 2026-10-24), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`. The target is a shell
# command (`sh:`): tools/test_warm.sh's `guard` mode, judged by its exit code.
TARGETS = ["sh:tools/test_warm.sh guard"]       # also the baseline's (tools/mutate_ci.py reads it from here)
T = TARGETS
W = "tools/warm.sh"
MUTANTS = [
    dict(id="WM1 a restart does not read the marker", file=W, targets=T,
         old='''    [ -f "$DIR/second" ] && second=1''',
         new='''    :'''),
    dict(id="WM2 a second daemon is not recorded", file=W, targets=T,
         old='''    if [ "$second" = 1 ]; then : > "$DIR/second"; else rm -f "$DIR/second"; fi''',
         new='''    :'''),
    dict(id="WM3 a deliberate stop does not forget it", file=W, targets=T,
         old='''stop) _stop; rm -f "$DIR/second" ;;''',
         new='''stop) _stop ;;'''),
    dict(id="WM4 a plain start reads the marker too", file=W, targets=T,
         old='''if [ -n "$others" ] && [ "${LOGICKERNEL_WARM_SECOND:-}" = 1 ]; then''',
         new='''if [ -n "$others" ] && { [ "${LOGICKERNEL_WARM_SECOND:-}" = 1 ] || [ -f "$DIR/second" ]; }; then'''),
    dict(id="WM5 a restart starts without the opt-in", file=W, targets=T,
         old='''    LOGICKERNEL_WARM_SECOND="$second" _start''',
         new='''    _start'''),
]
