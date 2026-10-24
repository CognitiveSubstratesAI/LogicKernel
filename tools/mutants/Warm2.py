# ORIGINAL: Warm2's mutant list — no swipl-devel counterpart.
# tools/mutants/Warm2.py — the mutation battery of the second-daemon restart fix (audit D-0130 item 2, A-0079 item 5:
# tools/warm.sh `_restart` and the `.warm/second` marker; 2026-10-24), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`. The target is a shell
# command (`sh:`): tools/test_warm.sh's `guard` mode, judged by its exit code.
#
# LOCAL ONLY — do not push a `mutants/Warm2` branch: mutation.yml cannot run this list. (1) A target is ONE word to
# tools/mutate_ci.py (`sh:tools/test_warm.sh guard` holds a blank: the baseline job splits it and runs `guard` as a test
# file), and (2) `guard` needs a user systemd manager, which the mutation jobs lack (the tooling job enables lingering for
# it): with none the guard cases print "skipped" and exit 0, so every mutant would SURVIVE. Run it locally:
#   MUTATE_LIMIT_S=1200 tools/mutate.sh run tools/mutants/Warm2.py "sh:tools/test_warm.sh guard"
# 2026-10-24: 5 of 5 caught, baseline green (A-0084).
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
