# ORIGINAL: SetupMachine's mutant list — no swipl-devel counterpart.
# tools/mutants/SetupMachine.py — the mutation battery of the setup script's guards (audit D-0130 item 2:
# tools/setup_machine.sh `--check`'s verdict and its argument parsing; 2026-10-24), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. The target is a shell command (`sh:`):
# tools/test_setup_machine.sh, judged by its exit code. NO mutant makes an unknown argument fall through to the install:
# the real steps would run on this machine.
TARGETS = ["sh:tools/test_setup_machine.sh"]       # also the baseline's (tools/mutate_ci.py reads it from here)
T = TARGETS
S = "tools/setup_machine.sh"
MUTANTS = [
    dict(id="SM1 --check always exits 0", file=S, targets=T,
         old='''        exit "$fail" ;;''',
         new='''        exit 0 ;;'''),
    dict(id="SM2 a missing component is not recorded", file=S, targets=T,
         old='''            [ "$state" = missing ] && fail=1 ;;''',
         new='''            : ;;'''),
    dict(id="SM3 an unknown argument has the wrong exit code", file=S, targets=T,
         old='''(see --help)" >&2; exit 2 ;;''',
         new='''(see --help)" >&2; exit 3 ;;'''),
    dict(id="SM4 a missing Julia is reported as present", file=S, targets=T,
         old='''have_julia() { command -v julia > /dev/null 2>&1 &&''',
         new='''have_julia() { true ||'''),
]
