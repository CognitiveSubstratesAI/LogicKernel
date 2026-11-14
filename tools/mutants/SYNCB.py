# ORIGINAL: SYNC-B's mutant list — no swipl-devel counterpart.
# tools/mutants/SYNCB.py — the mutation battery of SYNC-B (the pl-prims.c slice of the sync to swipl-devel cf6960c2), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. Only the behaviour change of the slice has a mutant: the key
# `minor_collections` of `swi_statistics` (the other changed functions are refactors or concern code unwritten here; see
# evidence/SYNC/sync_b_handoff.md). `swi_statistics` is exercised by the rows of test/core_lang/test_sys_swipl.jl.
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does not
# occur exactly once).
TARGETS = ["test/core_lang/test_sys_swipl.jl"]
T = TARGETS
P = "src/pl-prims.jl"
MUTANTS = [
    dict(id="SB-1 statistics(minor_collections, _) is an unknown key", file=P, targets=T,
         old='''    elseif key === :collections || key === :minor_collections || key === :collected ||''',
         new='''    elseif key === :collections || key === :collected ||'''),
    dict(id="SB-2 minor_collections answers a float", file=P, targets=T,
         old='''    elseif key === :collections || key === :minor_collections || key === :collected ||
        key === :agc ||''',
         new='''    elseif key === :minor_collections
        v.type = V_FLOAT
        v.f = 0.0
    elseif key === :collections || key === :collected ||
        key === :agc ||'''),
]
