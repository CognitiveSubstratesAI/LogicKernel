# ORIGINAL: MutGuard's mutant list — no swipl-devel counterpart.
# tools/mutants/MutGuard.py — the mutation battery of pre-push's refusal 5 (a push to mutants/<name> needs
# tools/mutants/<name>.py in the pushed commit; user 2026-10-24), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. The rows are the "a mutants/ branch needs its list file" testset of
# test/test_gate_split.jl.
TARGETS = ["test/test_gate_split.jl"]
T = TARGETS
H = "tools/githooks/pre-push"
MUTANTS = [
    dict(id="MG1 the list file is not checked", file=H, targets=T,
         old='''                    git -C "$top" cat-file -e "$local_sha:tools/mutants/$_mname.py" 2>/dev/null || {''',
         new='''                    true || {'''),
    dict(id="MG2 a delete of a mutants/ branch is refused", file=H, targets=T,
         old='''            case "$local_sha" in
                *[!0]*)
                    _mname=''',
         new='''            case "$local_sha" in
                *)
                    _mname='''),
    dict(id="MG3 the list file is looked up in the wrong directory", file=H, targets=T,
         old='''cat-file -e "$local_sha:tools/mutants/$_mname.py"''',
         new='''cat-file -e "$local_sha:tools/$_mname.py"'''),
    dict(id="MG4 the refusal does not fail the push", file=H, targets=T,
         old='''Name the branch after the list file, or add the file." >&2
                        rc=1
                        continue''',
         new='''Name the branch after the list file, or add the file." >&2
                        continue'''),
]
