# ORIGINAL: stream D's mutant list — no swipl-devel counterpart.
# tools/mutants/ToolingD.py — the mutation battery of stream D (the Pkg.test cost table, D-0091 item 3; D-0107 item 3:
# its NEW invariants only): the Pkg.test jobs read the table LOGICKERNEL_COSTS_TABLE names, and the table is
# validated before it is written. Run once, in CI, alongside the gate's CI + Evidence (D-0105 item 2).
# Format: tools/mutate_drive.py's.
TARGETS = [                      # the union of the mutants' targets: the baseline must be green on every one
    "test/test_gate_split.jl",
]
MUTANTS = [
    # lk_costs_path: a named table is the one read, never a silent fall back to unit_costs.tsv
    dict(id="TD1 the named cost table is ignored", file="test/ci_slices.jl",
         targets=["test/test_gate_split.jl"],
         old='    isempty(name) && return joinpath(test_dir, "unit_costs.tsv")\n',
         new='    return joinpath(test_dir, "unit_costs.tsv")\n'),
    # pkgtest_costs.py: a negative or non-finite cost is refused before the table is written
    dict(id="TD2 a negative or infinite cost is accepted", file="tools/pkgtest_costs.py",
         targets=["test/test_gate_split.jl"],
         old="        if not math.isfinite(v) or v < 0:\n",
         new="        if False:\n"),
]
