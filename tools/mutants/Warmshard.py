# ORIGINAL: Warmshard's mutant list — no swipl-devel counterpart.
# tools/mutants/Warmshard.py — the mutation battery of the sharded tooling job (D-0059 item 3, 2026-10-21),
# run ONCE, at the batch's close, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The
# format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`.
#
# Subject: the gather's `warm` mode (tools/evidence_ci.py) and the shard dispatcher and the `main` skip of
# tools/test_warm.sh — each a guard that must be able to FAIL, and is judged by its message, not an exit code.
TARGETS = [
    "test/test_gate_split.jl",
]
EV = "tools/evidence_ci.py"
SH = "tools/test_warm.sh"
T = ["test/test_gate_split.jl"]
MUTANTS = [
    # ── tools/evidence_ci.py warm ──
    dict(id="WS1 a shard with no result is accepted", file=EV, targets=T,
         old='''            g.problems.append("shard %s: no result (the job died before writing one)" % name)''',
         new='''            pass'''),
    dict(id="WS2 a shard with failed cases is accepted", file=EV, targets=T,
         old='''        if f:
            g.problems.append("shard %s: %d case(s) failed" % (name, f))''',
         new='''        if False:
            g.problems.append("shard %s: %d case(s) failed" % (name, f))'''),
    dict(id="WS3 a shard that ran no case is accepted", file=EV, targets=T,
         old='''        if p == 0:
            g.problems.append("shard %s ran no case" % name)''',
         new='''        if False:
            g.problems.append("shard %s ran no case" % name)'''),
    dict(id="WS4 another shard's result line is accepted", file=EV, targets=T,
         old='''        if not m or m.group(1) != name:''',
         new='''        if not m:'''),
    dict(id="WS5 the passes need not sum to the whole run's", file=EV, targets=T,
         old='''        if len(got) == len(shards) and npass != total:''',
         new='''        if False:'''),
    dict(id="WS6 a surplus over the whole run's passes is accepted", file=EV, targets=T,
         old='''        if len(got) == len(shards) and npass != total:''',
         new='''        if len(got) == len(shards) and npass < total:'''),
    dict(id="WS7 some shards skipped and some run is accepted", file=EV, targets=T,
         old='''    if skipped and got:
        g.problems.append("shards %s were skipped but %s ran"''',
         new='''    if False:
        g.problems.append("shards %s were skipped but %s ran"'''),
    dict(id="WS8 an unreadable result is accepted as a pass of zero", file=EV, targets=T,
         old='''            g.problems.append("shard %s: unreadable result %r" % (name, last[:80]))''',
         new='''            pass'''),
    dict(id="WS9 a file declaring no shards passes", file=EV, targets=T,
         old='''    if not shards or total is None:
        g.problems.append("%s declares no shards or no total" % declared)''',
         new='''    if False:
        g.problems.append("%s declares no shards or no total" % declared)'''),
    # ── tools/test_warm.sh: the dispatcher ──
    dict(id="SH1 an undeclared shard exits 0", file=SH, targets=T,
         old='''in tools/test_warm_shards.tsv"; exit 2; }''',
         new='''in tools/test_warm_shards.tsv"; exit 0; }'''),
    dict(id="SH2 a mode that printed no totals is not a failure", file=SH, targets=T,
         old='''(exit $rc)"; sf=$((sf + 1)); continue''',
         new='''(exit $rc)"; continue'''),
    dict(id="SH3 a nonzero exit with no failed case is not a failure", file=SH, targets=T,
         old='''        [ "$rc" -eq 0 ] || [ "$mf" -gt 0 ] || sf=$((sf + 1))''',
         new='''        :'''),
    dict(id="SH4 the passes of a mode are not summed", file=SH, targets=T,
         old='''        sp=$((sp + $(printf '%s' "$line" | sed -E 's/.*: ([0-9]+) passed, ([0-9]+) failed/\\1/')))''',
         new='''        sp=$((sp + 0))'''),
    dict(id="SH5 the failures of a mode are not summed", file=SH, targets=T,
         old='''        sf=$((sf + mf))''',
         new='''        sf=$((sf + 0))'''),
    dict(id="SH6 the shard exits 0 whatever failed", file=SH, targets=T,
         old='''    [ "$sf" -eq 0 ]; exit $?
fi
MAIN_ONLY''',
         new='''    true; exit 0
fi
MAIN_ONLY'''),
    # ── tools/test_warm.sh: `main` skips the modes of their own ──
    dict(id="SH7 `main` is not recognised", file=SH, targets=T,
         old='''[ "${1:-}" = main ] && MAIN_ONLY=1''',
         new='''[ "${1:-}" = mainx ] && MAIN_ONLY=1'''),
    dict(id="SH8 the skip never skips", file=SH, targets=T,
         old='''_unless_main() { [ "$MAIN_ONLY" = 1 ] || "$@"; }''',
         new='''_unless_main() { "$@"; }'''),
    dict(id="SH9 the skip always skips", file=SH, targets=T,
         old='''_unless_main() { [ "$MAIN_ONLY" = 1 ] || "$@"; }''',
         new='''_unless_main() { true; }'''),
]
