# ORIGINAL: Parmut's mutant list — no swipl-devel counterpart.
# tools/mutants/Parmut.py — the mutation battery of the parallel mutation lane (D-0077 item 6, 2026-10-21),
# run ONCE, at the batch's close, in CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's.
#
# Subject: the shard selection and the merge of tools/mutate_drive.py and the argument and memory guards of
# `tools/mutate.sh run-parallel`, all exercised by test/test_gate_split.jl without a daemon. What this list
# does NOT cover: the wiring that hands MUTATE_SHARD and the worker directories to real workers and the
# daemons' coexistence — that is the real run (evidence/A-0054/parallel_proof), and the warm.sh opt-in is
# tools/mutants/ParmutWarm.py (its target needs a user systemd, which the CI mutation runners lack).
TARGETS = [
    "test/test_gate_split.jl",
]
MD = "tools/mutate_drive.py"
MS = "tools/mutate.sh"
T = ["test/test_gate_split.jl"]
MUTANTS = [
    # ── tools/mutate_drive.py: the shard ──
    dict(id="PM1 a shard with k > n is accepted", file=MD, targets=T,
         old='''    if not m or int(m.group(1)) > int(m.group(2)):''',
         new='''    if not m:'''),
    dict(id="PM2 a shard with k = 0 is accepted", file=MD, targets=T,
         old='''    m = re.fullmatch(r"([1-9][0-9]*)/([1-9][0-9]*)", text)''',
         new='''    m = re.fullmatch(r"([0-9]*)/([1-9][0-9]*)", text)'''),
    dict(id="PM3 a malformed shard is read as the whole list", file=MD, targets=T,
         old='''        sys.exit("mutate_drive: MUTATE_SHARD=%r: expected k/n with 1 <= k <= n" % text)''',
         new='''        return (1, 1)'''),
    dict(id="PM4 the k-th shard starts one mutant late", file=MD, targets=T,
         old='''    return (i - 1) % shard[1] == shard[0] - 1''',
         new='''    return i % shard[1] == shard[0] - 1'''),
    dict(id="PM5 every shard takes every mutant", file=MD, targets=T,
         old='''    return (i - 1) % shard[1] == shard[0] - 1''',
         new='''    return True'''),
    # ── tools/mutate_drive.py: the merge ──
    dict(id="PM6 a mutant decided by two workers is accepted", file=MD, targets=T,
         old='''            if f[0] in seen:''',
         new='''            if False:'''),
    dict(id="PM7 a worker that wrote no verdicts is not noticed", file=MD, targets=T,
         old='''        if not os.path.isfile(path):
            print("merge: no verdicts.tsv in %s — that worker did not finish" % d)
            return 2''',
         new='''        if not os.path.isfile(path):
            continue'''),
    dict(id="PM8 the merged verdicts are in the workers' order, not the list's", file=MD, targets=T,
         old='''    rows = [seen[n] for n in names if n in seen]''',
         new='''    rows = list(seen.values())'''),
    dict(id="PM9 a blocking verdict does not make the merge exit 1", file=MD, targets=T,
         old='''    return 1 if any(blocks(r[1]) for r in rows) else 0''',
         new='''    return 0'''),
    dict(id="PM10 the merge counts every verdict as blocking", file=MD, targets=T,
         old='''    return 1 if any(blocks(r[1]) for r in rows) else 0''',
         new='''    return 1 if rows else 0'''),
    # ── tools/mutate.sh run-parallel: the guards ──
    dict(id="PM11 one worker is allowed", file=MS, targets=T,
         old='''    case "$n" in 2 | 3) ;; *)''',
         new='''    case "$n" in 1 | 2 | 3) ;; *)'''),
    dict(id="PM12 four workers are allowed", file=MS, targets=T,
         old='''    case "$n" in 2 | 3) ;; *)''',
         new='''    case "$n" in 2 | 3 | 4) ;; *)'''),
    dict(id="PM13 the quarter of the machine's memory is not kept free", file=MS, targets=T,
         old='''    need=$((n * per + total / 4))''',
         new='''    need=$((n * per))'''),
    dict(id="PM14 the workers' memory is not counted", file=MS, targets=T,
         old='''    need=$((n * per + total / 4))''',
         new='''    need=$((per + total / 4))'''),
    dict(id="PM15 exactly enough memory is refused", file=MS, targets=T,
         old='''    if [ "${avail:-0}" -lt "$need" ]; then''',
         new='''    if [ "${avail:-0}" -le "$need" ]; then'''),
    dict(id="PM16 a machine with too little memory goes on", file=MS, targets=T,
         old='''    if [ "${avail:-0}" -lt "$need" ]; then''',
         new='''    if [ "${avail:-0}" -gt "$need" ]; then'''),
    dict(id="PM17 the memory refusal is not exit 4", file=MS, targets=T,
         old='''        return 4
    fi
    out=''',
         new='''        return 1
    fi
    out='''),
    dict(id="PM18 a missing mutant list is not refused", file=MS, targets=T,
         old='''    [ -f "$1" ] || { echo "mutate: no such mutant list: $1" >&2; return 2; }
    mutants="$(realpath "$1")"
    shift
    if _evidence_running "$MAIN"; then
        echo "mutate: REFUSED — an evidence run holds the main lane: mutants do not share the machine with it (exit 5)" >&2
        return 5
    fi
    # THE MEMORY RULE''',
         new='''    mutants="$1"
    shift
    if _evidence_running "$MAIN"; then
        echo "mutate: REFUSED — an evidence run holds the main lane: mutants do not share the machine with it (exit 5)" >&2
        return 5
    fi
    # THE MEMORY RULE'''),
]
