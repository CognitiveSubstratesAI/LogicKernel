# ORIGINAL: ToolingE's mutant list — no swipl-devel counterpart.
# tools/mutants/ToolingE.py — the mutation battery of the four mutation-driver defects (audit D-0132; A-0083 item 3,
# A-0084 item 5; 2026-10-24), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format
# is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# The cases are the testset "tools/mutate_drive.py, mutate.sh: BADMATCH, the 900 s default, ..." of test/test_gate_split.jl.
#
# NOT MUTATED: the call of _par_cleanup inside _run_parallel — it needs real worktrees and daemons, which no test of the
# file starts; the function itself is proved through `mutate.sh par-cleanup`.
TARGETS = ["test/test_gate_split.jl"]
T = TARGETS
D = "tools/mutate_drive.py"
S = "tools/mutate.sh"
MUTANTS = [
    dict(id="TE1 a BADMATCH is booked with two fields again", file=D, targets=T,
         old='''            results.append((m["id"], "BADMATCH(%d)" % n, why))''',
         new='''            results.append((m["id"], "BADMATCH(%d)" % n))'''),
    dict(id="TE2 the default limit is 240 again", file=D, targets=T,
         old='''DEFAULT_LIMIT_S = 900 ''',
         new='''DEFAULT_LIMIT_S = 240 '''),
    dict(id="TE3 the deletion hint is never given", file=D, targets=T,
         old='''    if v.startswith("NO VERDICT (does not load") and not m["new"].strip():''',
         new='''    if False:'''),
    dict(id="TE4 the hint is given to a replacement too", file=D, targets=T,
         old='''and not m["new"].strip():''',
         new='''and True:'''),
    dict(id="TE5 the worker's verdicts.tsv is left behind", file=S, targets=T,
         old='''        rm -f "$out/par$k/verdicts.tsv"
        rmdir''',
         new='''        rmdir'''),
    dict(id="TE6 a mutant's log is prefixed like the worker's own", file=S, targets=T,
         old='''                mutant_*) mv -f "$f" "$out/" ;;''',
         new='''                mutant_*) mv -f "$f" "$out/par$k-$(basename "$f")" ;;'''),
    dict(id="TE7 a non-empty worker directory is removed with its contents", file=S, targets=T,
         old='''        rmdir "$out/par$k" 2> /dev/null ||''',
         new='''        rm -rf "$out/par$k" 2> /dev/null ||'''),
    dict(id="TE8 the worker logs are deleted, not moved up", file=S, targets=T,
         old='''                *) mv -f "$f" "$out/par$k-$(basename "$f")" ;;''',
         new='''                *) rm -f "$f" ;;'''),
]
