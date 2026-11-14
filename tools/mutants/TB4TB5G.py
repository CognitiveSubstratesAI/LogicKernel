# ORIGINAL: the mutant list of the guard of the five TB4 rows that need TB5's builtin — no swipl-devel counterpart.
# tools/mutants/TB4TB5G.py — mutation-proof, at VERDICT level, of test/core_lang/test_tabling_tb4_tb5_guard_swipl.jl (audit D-0659 item 2, D-0660 item 2): a
# guard that FAILS once `'$tbl_destroy_table'/1` is defined and the five rows (TB4-S1, S3, S4, A2, A3: groups SIMP, G13A, G13B of
# test/core_lang/test_tabling_tb4_tb5_swipl.jl) are not pinned, and passes with the dependency named where the builtin is undefined. Format: tools/mutate_drive.py's
# (as TB5.py): `id`, `file`, `old` (must occur EXACTLY once in `file`), `new`, `targets`. NOT RUN: written edit-only on wip/tab-int (2026-11-14), nothing
# parsed or run; every KILL below is read off the guard's rows, not observed. Each mutant is judged by the guard file alone (GUARD): the rows file TX is
# MUTATED too (its own rows turn red then, that is not the verdict asked: the guard's rows are).
# THE ROWS (G = the guard file, its testsets in order):
#   "the guard's check sees a registered predicate and an unregistered one" (between/3 defined, no_such_predicate_tg/9 not),
#   "the guard's verdict: builtin defined and the rows pinned, the one fault at a time" (the good fixture passes; each of ten faults alone fails),
#   "the guard's verdict: builtin undefined, the dependency named, never a skip" (ok, path :dependency, the message names `$tbl_destroy_table` and TB5),
#   "the five TB4 rows are pinned wherever '$tbl_destroy_table'/1 is defined" (the REAL groups parsed out of TX; with the builtin defined `path` is :rows_checked and ok).
GUARD = "test/core_lang/test_tabling_tb4_tb5_guard_swipl.jl"
TX = "test/core_lang/test_tabling_tb4_tb5_swipl.jl"
TARGETS = [GUARD]
MUTANTS = [
    # ── the guard's own code ──
    dict(id="TBG-G1 the dependency branch is taken when the builtin IS defined, the condition inverted (KILL the good-fixture row `r.ok && r.path === :rows_checked`: the verdict is :dependency; and the real row's `path` check)",
         file=GUARD, targets=TARGETS,
         old="    builtin || return (ok=true, path=:dependency, msg=_TG_DEPENDENCY)\n",
         new="    builtin && return (ok=true, path=:dependency, msg=_TG_DEPENDENCY)\n"),
    dict(id="TBG-G2 the verdict is `ok` whatever the problems (KILL the ten fault rows: each `!_TG_judge(true, ...).ok` fails)",
         file=GUARD, targets=TARGETS,
         old="    return (ok=isempty(problems), path=:rows_checked, msg=join(problems, \"; \"))\n",
         new="    return (ok=true, path=:rows_checked, msg=join(problems, \"; \"))\n"),
    dict(id="TBG-G3 the registration check answers false for every predicate (the builtin check dropped; KILL `@test _TG_defined(gd, \"between\", 3)`)",
         file=GUARD, targets=TARGETS,
         old="    return proc !== nothing && LK.isDefinedProcedure(gd, proc)\n",
         new="    return false\n"),
    dict(id="TBG-G4 the undefined-builtin verdict FAILS instead of passing (KILL the dependency row `@test r.ok`)",
         file=GUARD, targets=TARGETS,
         old="    builtin || return (ok=true, path=:dependency, msg=_TG_DEPENDENCY)\n",
         new="    builtin || return (ok=false, path=:dependency, msg=_TG_DEPENDENCY)\n"),
    dict(id="TBG-G5 the dependency message no longer names the builtin (KILL the dependency row `occursin(\"$tbl_destroy_table\", r.msg)`)",
         file=GUARD, targets=TARGETS,
         old="    \"the five TB4 rows (TB4-S1, S3, S4, A2, A3) need the TB5 builtin '\\$tbl_destroy_table'/1, \" *\n",
         new="    \"the five TB4 rows (TB4-S1, S3, S4, A2, A3) need a builtin of TB5, \" *\n"),
    dict(id="TBG-G6 the group-key check is dropped (KILL the fault row `key=\"G13C\"`: a renamed group is reported only by this check)",
         file=GUARD, targets=TARGETS,
         old="    sort(gkeys) == sort([e[1] for e in _TG_EXPECTED]) ||\n",
         new="    true ||\n"),
    dict(id="TBG-G7 the label check is dropped (KILL the fault row `label=\"rows of S1, S3\"`: a label that stops naming S4 is reported only by this check)",
         file=GUARD, targets=TARGETS,
         old="    named == sort(reduce(vcat, [e[3] for e in _TG_EXPECTED])) ||\n",
         new="    true ||\n"),
    dict(id="TBG-G8 the case-list check is dropped (KILL the fault row `cases=g.cases[1:1]`: with the pins unchanged only this check sees the dropped case)",
         file=GUARD, targets=TARGETS,
         old="        [c[1] for c in g.cases] == e[2] ||\n",
         new="        true ||\n"),
    dict(id="TBG-G9 the first pin need not be `ok` (KILL the fault row with the pin `fail` first)",
         file=GUARD, targets=TARGETS,
         old='        isempty(g.pins) || g.pins[1] == "ok" ||\n            push!(problems, "$(e[1]): the first pin is not `ok`")\n',
         new='        isempty(g.pins) || true ||\n            push!(problems, "$(e[1]): the first pin is not `ok`")\n'),
    dict(id="TBG-G10 a pin line with an empty answer counts as pinned (KILL the fault row with the pin lines `t_r1301 ` and `t_r1302 `)",
         file=GUARD, targets=TARGETS,
         old="            (length(ls) == 1 && length(ls[1]) > length(\"t_$id \")) ||\n",
         new="            (length(ls) == 1) ||\n"),
    # ── the pins of the rows file ──
    dict(id="TBG-P1 the pins of group G13B emptied (KILL the real row `@test res.ok`: with the builtin defined the verdict lists `G13B: no pins`)",
         file=TX, targets=TARGETS,
         old="const _TR_PINS_G13B = [\n    \"ok\",\n    \"t_r1303 c[116,95,114,49,51,48,51]/1(c[45]/2(i0,a[97,49,51]))\",\n    \"t_r1304 c[116,95,114,49,51,48,52]/1(c[45]/2(i0,a[99,49,51]))\"\n]\n",
         new="const _TR_PINS_G13B = String[]\n"),
    dict(id="TBG-P2 the label of group SIMP stops naming S4, the group list names four mutants (KILL the real row `@test res.ok`: `the labels name`)",
         file=TX, targets=TARGETS,
         old="simplification to false and to true (S1, S3, S4)\"",
         new="simplification to false and to true (S1, S3)\""),
    dict(id="TBG-P3 the case r1304 of group G13B dropped from the cases (KILL the real row `@test res.ok`: `G13B: the cases are`)",
         file=TX, targets=TARGETS,
         old="    (\"r1303\", raw\"call_delays(a13, D), nb_getval(acc13, N), R = N-D\"),\n    (\"r1304\", raw\"call_delays(c13, D), nb_getval(acc13, N), R = N-D\")\n]\n",
         new="    (\"r1303\", raw\"call_delays(a13, D), nb_getval(acc13, N), R = N-D\")\n]\n"),
    dict(id="TBG-P4 group G13B renamed (KILL the real row: `the groups are`, one of the three keys missing)",
         file=TX, targets=TARGETS,
         old="        key=\"G13B\",\n",
         new="        key=\"G13C\",\n"),
    dict(id="TBG-P5 the pin line of r09b lost its answer (KILL the real row: `SIMP r09b: not exactly one pin line with an answer`)",
         file=TX, targets=TARGETS,
         old="    \"t_r09b c[116,95,114,48,57,98]/1(a[110,111])\",\n",
         new="    \"t_r09b\",\n"),
]
