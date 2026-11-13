# ORIGINAL: the mutant list of R2 T25 (error/warning counting) — no swipl-devel counterpart.
# tools/mutants/T25.py — the mutation battery of `'$inc_message_count'/1`'s counting (src/pl-error.jl, pl-error.c:1457-1474) and of the
# `errors` / `warnings` keys of statistics/2 (src/pl-prims.jl, pl-prims.c:6283-6286), run ONCE, in CI (.github/workflows/mutation.yml).
# Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (EXACTLY once), `new`, optional `equivalent` and `targets`.
# Verdicts: written by the battery, not yet run. The `old` anchors are single lines in the repo's formatted style BEFORE `warm.sh fmt`
# ran (the writer had no daemon): RE-FIT any that fmt rewraps. Every `old` was checked to occur exactly once (a text count).
# TARGETS (audit D-0238): test_bootpred3_swipl.jl calls `'$inc_message_count'/1` and reads both counters (rows bp3i11-bp3i17).
TARGETS = ["test/core_lang/test_bootpred3_swipl.jl"]
E = "src/pl-error.jl"
P = "src/pl-prims.jl"
MUTANTS = [
    dict(id="T25-1 an `error` level is not counted (KILL bp3i11, bp3i14, bp3i15, bp3i17)",
         file=E, targets=TARGETS,
         old="            st.errors += Int32(1) ",
         new="            st.errors += Int32(0) "),
    dict(id="T25-2 a `warning` level is not counted (KILL bp3i12, bp3i15, bp3i17)",
         file=E, targets=TARGETS,
         old="            st.warnings += Int32(1) ",
         new="            st.warnings += Int32(0) "),
    dict(id="T25-3 a `warning` bumps the error count (KILL bp3i13, bp3i15)",
         file=E, targets=TARGETS,
         old="            st.warnings += Int32(1) ",
         new="            st.errors += Int32(1) "),
    dict(id="T25-4 statistics(errors, _) answers the warning count (KILL bp3i11, bp3i15)",
         file=P, targets=TARGETS,
         old="        v.i = st.errors\n",
         new="        v.i = st.warnings\n"),
    dict(id="T25-5 statistics(warnings, _) answers 0 again (KILL bp3i12, bp3i15)",
         file=P, targets=TARGETS,
         old="        v.i = st.warnings\n",
         new="        v.i = 0\n"),
]
