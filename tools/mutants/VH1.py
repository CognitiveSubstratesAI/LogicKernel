# ORIGINAL: VH-1's mutant list — no swipl-devel counterpart.
# tools/mutants/VH1.py — the mutation battery of the verdict-hardening step VH-1 (audit D-0992 item 2): tools/verdict_read.py
# `load_equivalents` refuses a row whose D-entry column is not a `D-NNNN` id. Run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`,
# `targets`. No tools/mutants file covered a python tool before; the nearest ones (ToolingE, FuzzCi) are other steps' lists, so
# this step has its own. The target is a shell command (`sh:`), judged by its exit code: tools/test_verdict_read.sh runs
# tools/test_verdict_read.py (python and git only), which reads the tool through `load_equivalents` AND through its entry point
# (an unratified row exits 2 naming the row). A guard is useless three ways (CLAUDE.md): VH1 makes the check unable to fail.
TARGETS = ["sh:tools/test_verdict_read.sh"]       # also the baseline's: tools/mutate_ci.py takes the unmutated run's targets from here
T = TARGETS
V = "tools/verdict_read.py"
MUTANTS = [
    dict(id="VH1 load_equivalents accepts a pending row (KILL: test_load_equivalents_refuses_a_row_without_a_d_entry, test_the_entry_point_refuses_an_unratified_equivalents_row)", file=V, targets=T,
         old='''        if not re.fullmatch(r"D-\\d{4,}", r["d_entry"]):''',
         new='''        if False:'''),
]
