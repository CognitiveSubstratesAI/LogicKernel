# ORIGINAL: R2GEN's mutant list — an LK-only list (the R2 status generator and its guards have no swipl-devel counterpart).
# tools/mutants/R2GEN.py — the mutation battery of R2GEN (tools/r2_status.jl: the scans, the owners file, the upstream snapshot guards,
# the rendering; tools/port_check.jl: r2_status_violations and _block_violations, the wiring), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as LB5B.py and AUTOLOAD1.py): `id`,
# `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Verdicts: written by the battery.
# Every `old` was counted EXACTLY once in its file at the commit that adds this list (a read-only text count, no Julia);
# RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
# TARGETS (audit D-0238): the two test files that exercise the mutated code and hold @testset and @test: test/test_r2_status.jl (the
# generator's functions called directly, on fixtures and on the real tree) and test/test_port_check.jl (the R2 testset: the guards
# through port_check on a good fixture tree, fired one mutation at a time). Both include the tools files they test.
# KILL: each id names the testset that kills it (the first failing one; the other target may fail too).
# NOT LISTED (each with its reason):
#   * the formatting of the rendered rows (column widths, the chart): rendering is checked by the rendering testset against hand-built
#     rows, a mutant of a width is a mutant of a string the testset pins whole; one rendering mutant would add no guard kind.
#   * r2_pin_checkout's search order of upstream checkouts: which checkout is found is environment, not logic.
R = "test/test_r2_status.jl"
P = "test/test_port_check.jl"
TARGETS = [R, P]
J = "tools/r2_status.jl"
C = "tools/port_check.jl"
MUTANTS = [
    dict(id="R2GEN-A1 r2_registered drops every PL_extension match (KILL r2_status: the upstream C scan, the registered scan, the predicate rows)",
         file=J, targets=TARGETS,
         old='            push!(out, _r2_unescape(m[1]) * "/" * m[2])\n',
         new='            nothing\n'),
    dict(id="R2GEN-A2 r2_owner_violations never reports STALE (KILL r2_status: owners; test_port_check: the R2 status testset, owner-stale rows)",
         file=J, targets=TARGETS,
         old='        k in live ||\n            push!(v, "R2-OWNER-STALE',
         new='        true ||\n            push!(v, "R2-OWNER-STALE'),
    dict(id="R2GEN-A3 r2_owner_violations counts a finished row as owing an owner (KILL r2_status: owners; the STALE row of the R2 status testset)",
         file=J, targets=TARGETS,
         old='        r2_owes(r) || continue\n        push!(live, r.key)',
         new='        push!(live, r.key)'),
    dict(id="R2GEN-A4 r2_status_violations has no R2-STATUS-EMPTY check (KILL test_port_check: the R2 status testset, the row with the refusal exception renamed)",
         file=C, targets=TARGETS,
         old='        any(r -> r.cat == cat, st.rows) || begin\n',
         new='        true || begin\n'),
    dict(id="R2GEN-A5 r2_upstream_violations never reports PIN (KILL r2_status: the upstream snapshot's guards, the another-pin mutation)",
         file=J, targets=TARGETS,
         old='    if pin !== nothing && have != pin\n',
         new='    if false && pin !== nothing && have != pin\n'),
    dict(id="R2GEN-A6 r2_upstream_violations never reports EMPTY (KILL r2_status: the upstream snapshot's guards, the header-only mutation)",
         file=J, targets=TARGETS,
         old='    isempty(r2_read_snapshot(text)) &&\n        push!(v, "R2-UPSTREAM-EMPTY',
         new='    false &&\n        push!(v, "R2-UPSTREAM-EMPTY'),
    dict(id="R2GEN-A7 r2_upstream_violations never compares against the pin's C (KILL r2_status: the upstream snapshot's guards, the beta/2 -> gamma/2 mutation)",
         file=J, targets=TARGETS,
         old='    if co !== nothing && r2_snapshot_text(',
         new='    if false && co !== nothing && r2_snapshot_text('),
    dict(id="R2GEN-A8 _r2_lit does not join a split literal (KILL r2_status: the refusal sites, the one-line rows)",
         file=J, targets=TARGETS,
         old='    arg = replace(arg, r"\\"\\s*\\*\\s*\\"" => "")',
         new='    arg = arg'),
    dict(id="R2GEN-A9 _block_violations accepts any block: the DRIFT comparison returns clean (KILL test_port_check `fixture: a clean mirror passes, and one mutation fails it`, first failing at :413 — the function is shared with the other generated blocks; the R2 status testset's number-in-the-block row)",
         file=C, targets=TARGETS,
         old='    have == want && return String[]\n',
         new='    return String[]\n'),
    dict(id="R2GEN-A10 _block_violations has no MISSING check (KILL test_port_check `M1: the generated code map is held to its generators`, first failing at :462; the R2 status testset's markers-deleted row)",
         file=C, targets=TARGETS,
         old='    have === nothing && return ["$code-MISSING',
         new='    have === nothing && return String[]\n    false && return ["$code-MISSING'),
]
