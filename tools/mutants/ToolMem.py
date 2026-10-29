# ORIGINAL: ToolMem's mutant list — no swipl-devel counterpart.
# tools/mutants/ToolMem.py — the mutation battery of the TOOL-MEM step (audit D-0242 item 2, 2026-10-29): the
# Pkg.test-way runs go one at a time (a lock), each in its own scope with a memory ceiling nested in the lane's slice
# (tools/pkgtest_way.sh), the peak is printed and kept in peaks.tsv, a killed run is named (KILLED) and fails, and
# `tools/warm.sh` names the lane's slice (`_lane_slice`) and hands it on in `_inert_check`. Run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` (a mutant that must SURVIVE, with the code reason)
# and `targets`.
#
# TARGETS (D-0238): every test file that exercises the mutated code. Both shell files are exercised by
# test/test_gate_split.jl alone among the mutate.sh targets (tools/test_warm.sh is a shell suite, run by CI's
# tooling job, not a mutate.sh target; no case of it was added by this step).
#
# Subject: a guard must be able to FAIL, so each mutant is one of the three ways a guard is useless — the limit never
# applies (cap flag, swap cap, OOMPolicy, slice, the scope itself), it cannot fail (the lock does not wait, a killed
# run reported as a pass), or it compares/records the wrong thing (the wrong cgroup file, the wrong unit, the wrong
# column of peaks.tsv).
TARGETS = [
    "test/test_gate_split.jl",
]
W = "tools/warm.sh"
P = "tools/pkgtest_way.sh"
T = ["test/test_gate_split.jl"]
MUTANTS = [
    # ── tools/pkgtest_way.sh: the scope and its limits ──
    dict(id="TM1 the memory ceiling flag is dropped", file=P, targets=T,
         old=r'''"${slice[@]}" -p MemoryMax="$mem" -p MemorySwapMax=0''',
         new=r'''"${slice[@]}" -p MemorySwapMax=0'''),
    dict(id="TM2 the default ceiling is 6G", file=P, targets=T,
         old=r'''mem="${LOGICKERNEL_INERT_MEM_MAX:-3G}"''',
         new=r'''mem="${LOGICKERNEL_INERT_MEM_MAX:-6G}"'''),
    dict(id="TM3 the ceiling ignores LOGICKERNEL_INERT_MEM_MAX", file=P, targets=T,
         old=r'''mem="${LOGICKERNEL_INERT_MEM_MAX:-3G}"''',
         new=r'''mem="3G"'''),
    dict(id="TM4 the swap cap is dropped", file=P, targets=T,
         old=r'''-p MemoryMax="$mem" -p MemorySwapMax=0 -p TasksMax=512''',
         new=r'''-p MemoryMax="$mem" -p TasksMax=512'''),
    dict(id="TM5 OOMPolicy=continue is dropped (the wrapper dies with the kill)", file=P, targets=T,
         old=r'''-p TasksMax=512
        -p OOMPolicy=continue)''',
         new=r'''-p TasksMax=512)'''),
    dict(id="TM6 the scope is not nested in the lane's slice", file=P, targets=T,
         old=r'''    [ -n "${LOGICKERNEL_INERT_SLICE:-}" ] && slice=(--slice="$LOGICKERNEL_INERT_SLICE")''',
         new=r'''    :'''),
    dict(id="TM7 the run is not in a scope at all", file=P, targets=T,
         old=r'''if command -v systemd-run > /dev/null 2>&1 && systemd-run --user --scope true > /dev/null 2>&1; then''',
         new=r'''if false; then'''),
    # ── tools/pkgtest_way.sh: one at a time ──
    dict(id="TM8 every run takes a lock of its own (no mutual exclusion)", file=P, targets=T,
         old=r'''exec 9> "$lock"''',
         new=r'''exec 9> "$lock.$$"'''),
    dict(id="TM9 a second run does not wait for the first", file=P, targets=T,
         old=r'''    flock 9
fi''',
         new=r'''    :
fi'''),
    dict(id="TM10 the lock is never taken", file=P, targets=T,
         old=r'''if ! flock -n 9; then''',
         new=r'''if true; then'''),
    dict(id="TM11 the lock is taken blocking (a waiting run says nothing)", file=P, targets=T,
         old=r'''if ! flock -n 9; then''',
         new=r'''if ! flock 9; then'''),
    dict(id="TM12 a waiting run does not say it waits", file=P, targets=T,
         old=r'''    echo "pkgtest_way: another Pkg.test-way run holds $lock — waiting (they run one at a time, D-0242)" >&2''',
         new=r'''    :'''),
    # ── tools/pkgtest_way.sh: the peak ──
    dict(id="TM13 the peak is read from memory.current", file=P, targets=T,
         old=r'''"/sys/fs/cgroup$cg/memory.peak"''',
         new=r'''"/sys/fs/cgroup$cg/memory.current"'''),
    dict(id="TM14 the peak is not converted to MiB", file=P, targets=T,
         old=r'''peak_mib=$((pb / 1048576))''',
         new=r'''peak_mib=$((pb / 1024))'''),
    dict(id="TM15 the oom_kill count is never read", file=P, targets=T,
         old=r'''"s/^oom_kill //p" "/sys/fs/cgroup$cg/memory.events"''',
         new=r'''"s/^oom_kill //p" /dev/null'''),
    dict(id="TM16 the peak line is not printed", file=P, targets=T,
         old=r'''echo "pkgtest_way: $(basename "$f") peak ${peak_txt} (cap $mem, oom_kill $oom)"''',
         new=r''':'''),
    dict(id="TM17 peaks.tsv is not written", file=P, targets=T,
         old=r'''>> "$out/peaks.tsv"''',
         new=r'''> /dev/null'''),
    dict(id="TM18 peaks.tsv swaps the cap and the oom_kill columns", file=P, targets=T,
         old=r'''"${peak_mib:--}" "$mem" "$oom" "$rc"''',
         new=r'''"${peak_mib:--}" "$oom" "$mem" "$rc"'''),
    dict(id="TM19 the inner shell loses the test process's exit code", file=P, targets=T,
         old=r'''exit $rc'
runner=()''',
         new=r'''exit 0'
runner=()'''),
    dict(id="TM20 the exit code is overwritten after the run", file=P, targets=T,
         old=r'''rc=$?
peak_mib="" oom=0''',
         new=r'''rc=0
peak_mib="" oom=0'''),
    # ── tools/pkgtest_way.sh: the verdict ──
    dict(id="TM21 a killed run is not named", file=P, targets=T,
         old=r'''if [ "$rc" -ne 0 ] && { [ "$rc" -eq 137 ] || [ "$oom" != 0 ]; }; then''',
         new=r'''if false; then'''),
    dict(id="TM22 a run that exits non-zero is named only when it exits zero", file=P, targets=T,
         old=r'''if [ "$rc" -ne 0 ] && { [ "$rc" -eq 137 ] || [ "$oom" != 0 ]; }; then''',
         new=r'''if [ "$rc" -eq 0 ] && { [ "$rc" -eq 137 ] || [ "$oom" != 0 ]; }; then'''),
    dict(id="TM23 a killed run is reported as a pass", file=P, targets=T,
         old=r'''    tail -n 25 "$base.err" >&2
    exit "$rc"''',
         new=r'''    tail -n 25 "$base.err" >&2
    exit 0'''),
    dict(id="TM24 the failure branch is never taken", file=P, targets=T,
         old=r'''if [ "$rc" -ne 0 ]; then
    echo "pkgtest_way: FAILED''',
         new=r'''if false; then
    echo "pkgtest_way: FAILED'''),
    dict(id="TM25 the lock file descriptor reaches the test process", file=P, targets=T,
         old=r'''2> "$base.err" 9>&-''',
         new=r'''2> "$base.err"''',
         equivalent="tools/pkgtest_way.sh (the run line): the flock is on fd 9's open file description, released when every holder has closed it. The test process is the scope's only child and ends before the script's own exit; the descriptor outlives the run only in a grandchild the test process leaks, which neither the stub nor Julia does."),
    # ── tools/warm.sh: the lane's slice, and the step ──
    dict(id="TM26 the second daemon's lane names the first one's slice", file=W, targets=T,
         old=r'''elif [ -f "$DIR/second" ]; then echo lk-warm2.slice''',
         new=r'''elif [ -f "$DIR/second" ]; then echo lk-warm.slice'''),
    dict(id="TM27 the first daemon's lane names the second one's slice", file=W, targets=T,
         old=r'''else echo lk-warm.slice; fi''',
         new=r'''else echo lk-warm2.slice; fi'''),
    dict(id="TM28 an explicit LOGICKERNEL_SLICE is ignored", file=W, targets=T,
         old=r'''    if [ -n "${LOGICKERNEL_SLICE:-}" ]; then echo "$LOGICKERNEL_SLICE"''',
         new=r'''    if false; then echo "$LOGICKERNEL_SLICE"'''),
    dict(id="TM29 a slice is named where the shared budget is off", file=W, targets=T,
         old=r'''    _lk_budget_on || return 0
    systemctl --user show-environment > /dev/null 2>&1 || return 0
    if [ -n "${LOGICKERNEL_SLICE:-}" ]''',
         new=r'''    systemctl --user show-environment > /dev/null 2>&1 || return 0
    if [ -n "${LOGICKERNEL_SLICE:-}" ]'''),
    dict(id="TM30 the step does not hand the slice on", file=W, targets=T,
         old=r'''        LOGICKERNEL_INERT_SLICE="$(_lane_slice)" "$ROOT/tools/pkgtest_way.sh" "$f" > "$log" 2>&1''',
         new=r'''        "$ROOT/tools/pkgtest_way.sh" "$f" > "$log" 2>&1'''),
    dict(id="TM31 the step does not print the peak", file=W, targets=T,
         old=r'''        grep -h '^pkgtest_way: .* peak ' "$log"''',
         new=r'''        :'''),
    dict(id="TM32 the step ignores the run's exit code", file=W, targets=T,
         old=r'''        if [ "$prc" -ne 0 ]; then''',
         new=r'''        if false; then'''),
    dict(id="TM33 the step takes the wrong exit code", file=W, targets=T,
         old=r'''        prc=$?  ''',
         new=r'''        prc=0   '''),
    dict(id="TM34 the step runs the files in the background (they overlap the next)", file=W, targets=T,
         old=r'''"$ROOT/tools/pkgtest_way.sh" "$f" > "$log" 2>&1
        prc=$?''',
         new=r'''"$ROOT/tools/pkgtest_way.sh" "$f" > "$log" 2>&1 &
        prc=$?'''),
]
