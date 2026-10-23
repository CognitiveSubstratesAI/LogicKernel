# ORIGINAL: PrepushUrl's mutant list — no swipl-devel counterpart.
# tools/mutants/PrepushUrl.py — the mutation battery of the pre-push hook's push-by-URL reading (audit D-0120
# item 1; gate/prepush-url f8d10a8, 2026-10-23), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY
# once), `new`, optional `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`.
#
# Subject: a $1 that names no configured remote but equals one's URL is read as that remote.
TARGETS = [
    "test/test_gate_split.jl",
]
H = "tools/githooks/pre-push"
T = ["test/test_gate_split.jl"]
MUTANTS = [
    dict(id="PU1 a URL is never mapped to its remote", file=H, targets=T,
         old='''            remote_name="$r"''',
         new='''            :'''),
    dict(id="PU2 a configured URL's credentials are compared", file=H, targets=T,
         old='''_strip_cred() { printf '%s' "$1" | sed -E 's|://[^@/]*@|://|'; }''',
         new='''_strip_cred() { printf '%s' "$1"; }'''),
]
