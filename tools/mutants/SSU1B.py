# ORIGINAL: SSU1B's mutant list — no swipl-devel counterpart.
# tools/mutants/SSU1B.py — the mutation battery of SSU1b (the `det/1` supervisor prefix `S_DET`: the S_DET label of src/pl-wam.jl = pl-vmi.c S_DET; `setDetDefinition!` and its
# dispatch in `setAttrDefinition` of src/pl-proc.jl = pl-proc.c setDetDefinition; the `S_DET` emission of `chainPredicateSupervisor` in src/pl-supervisor.jl = pl-supervisor.c:379-418;
# `skipWrapperPrefix` of src/pl-wrap.jl = pl-wrap.c). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as TB6.py, TB9.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# NOT RUN YET (written edit-only on wip/ssu1b, 2026-11-14, NOTHING compiled or run): every KILL below is an EXPECTATION read off the rows of
# test/core_lang/test_det_ssu_swipl.jl (DS), none observed; the first hand-run replaces this header with the true verdicts, and a mutant that survives is either killed by a new row or
# recorded equivalent with its code reason before the commit lands. A row that fails on the unmutated tree has no kill value.
# KILL ROWS (DS = test/core_lang/test_det_ssu_swipl.jl, one testset each, named by its title):
#   "supervisor codes: S_DET from P_DET, ..."      wb1 (plain), wb2 (det), wb3 (SSU + det): `det.codes[1] == S_DET`, `both.codes[1:2] == [S_SSU_DET, S_DET]`, the length row.
#   "setDetDefinition!: the flag, the reset ..."   `d.codes === installed` (already det), `d.codes === d.code_data.virgin` (after either change), and the same through `setAttrDefinition`.
#   "S_DET sets FR_DET in the frame of a det predicate"   fr1 (plain) against fr2 (det) at the first answer under `determinism_error = silent`: `n_det(fl_det) >= 1`, `n_det(fl_plain) == 0`.
#   "skipWrapperPrefix steps over S_DET ..."       the synthetic code vectors and the `tdt` predicate (`:- det(tdt/1). :- table tdt/1.`: `codes[1] == S_DET`, skip == 2).
#   the swipl differential testset (dd_*, ex_*, tt_*, sc_* rows against the pins of swipl 10.1.20): a det predicate that is not checked, or checked wrongly, changes an answer.
# TARGETS (audit D-0238): every file that reaches the mutated code: DS (the step's file); TM (test_tabling_min_swipl.jl: tabled predicates, the wrapper chain and skipWrapperPrefix);
#   TD (test_det_swipl.jl: `$`/1 and det/1 programs through the frame flags); MP (test_meta_predicate_swipl.jl: chainPredicateSupervisor's meta branch shares the emission code);
#   WR (test_wrap_swipl.jl: S_WRAP, skipWrapperPrefix on wrapped supervisors); SS (test_ssu_swipl.jl) and SC (test_ssu_compile_swipl.jl): SSU predicates take the S_SSU_DET branch of the
#   same emission; AS (test_assert_swipl.jl: the setters reached through assert and the attribute entry points). NOT listed: test_static_analysis.jl (the CI's static job).
# EQUIVALENT mutants: none claimed. Every `old` was counted EXACTLY once in its file at wip/ssu1b by python3 -I ~/code/lk-t27-scratch/oldscan.py SSU1B (no Julia ran). RE-FIT any `old`
# that `tools/warm.sh fmt` rewraps.
DS = "test/core_lang/test_det_ssu_swipl.jl"
TM = "test/core_lang/test_tabling_min_swipl.jl"
TD = "test/core_lang/test_det_swipl.jl"
MP = "test/core_lang/test_meta_predicate_swipl.jl"
WR = "test/core_lang/test_wrap_swipl.jl"
SS = "test/core_lang/test_ssu_swipl.jl"
SC = "test/compile/test_ssu_compile_swipl.jl"
AS = "test/db/test_assert_swipl.jl"
TARGETS = [DS, TM, TD, MP, WR, SS, SC, AS]
SUP = "src/pl-supervisor.jl"
WAM = "src/pl-wam.jl"
PROC = "src/pl-proc.jl"
WRAP = "src/pl-wrap.jl"
MUTANTS = [
    # ── pl-supervisor.jl chainPredicateSupervisor (pl-supervisor.c:383-392) ──
    dict(id="SSU1B-S1 chainPredicateSupervisor does not emit S_DET for a P_DET predicate (KILL DS 'supervisor codes': `det.codes[1] == S_DET`, `both.codes[1:2] == [S_SSU_DET, S_DET]`, the length row; the `tdt` row of 'skipWrapperPrefix')",
         file=SUP, targets=TARGETS,
         old="            push!(codes, S_DET)                     # addBuffer(&buf, encode(S_DET), code)\n",
         new="            nothing                                 # addBuffer(&buf, encode(S_DET), code)\n"),
    dict(id="SSU1B-S2 P_DET is dropped from the chain condition, so a det-only predicate gets no prefix (KILL DS 'supervisor codes': `det.codes[1] == S_DET` and `length(det.codes) == length(plain.codes) + 1`; wb3 keeps P_SSU_DET so only wb2 and `tdt` see it)",
         file=SUP, targets=TARGETS,
         old="    if meta || (def.flags & (P_SSU_DET | P_DET)) != 0   # ison(def, P_SSU_DET|P_DET)\n",
         new="    if meta || (def.flags & P_SSU_DET) != 0             # ison(def, P_SSU_DET|P_DET)\n"),
    dict(id="SSU1B-S3 the S_DET prefix is emitted before S_SSU_DET (KILL DS 'supervisor codes': `both.codes[1:2] == [S_SSU_DET, S_DET]`, wb3 declares both)",
         file=SUP, targets=TARGETS,
         old="        if (def.flags & P_SSU_DET) != 0\n            push!(codes, S_SSU_DET)                 # addBuffer(&buf, encode(S_SSU_DET), code)\n        end\n        if (def.flags & P_DET) != 0\n            push!(codes, S_DET)                     # addBuffer(&buf, encode(S_DET), code)\n        end\n",
         new="        if (def.flags & P_DET) != 0\n            push!(codes, S_DET)                     # addBuffer(&buf, encode(S_DET), code)\n        end\n        if (def.flags & P_SSU_DET) != 0\n            push!(codes, S_SSU_DET)                 # addBuffer(&buf, encode(S_SSU_DET), code)\n        end\n"),
    # ── pl-wam.jl: the S_DET label (pl-vmi.c S_DET) ──
    dict(id="SSU1B-S4 the S_DET label clears FR_DET instead of setting it (KILL DS 'S_DET sets FR_DET': `n_det(fl_det) >= 1`; the dd_* and tt_* rows of the differential testset: a det predicate that leaves a choice point or fails raises no determinism_error)",
         file=WAM, targets=TARGETS,
         old="    ld.frames[FR].flags |= FR_DET                   # setLocal(FR, FR_DET)\n",
         new="    ld.frames[FR].flags &= ~FR_DET                  # setLocal(FR, FR_DET)\n"),
    # ── pl-proc.jl setDetDefinition! and its dispatch (pl-proc.c setDetDefinition) ──
    dict(id="SSU1B-S5 setDetDefinition! never takes its early return (KILL DS 'setDetDefinition!': `d.codes === installed` after `setDetDefinition!(gd, d, true)` on an already det predicate, and `d.codes === after_clear` after the second clear)",
         file=PROC, targets=TARGETS,
         old="    if (isdet && (def.flags & P_DET) != 0) || (!isdet && (def.flags & P_DET) == 0)\n        return true\n    end\n",
         new="    if false\n        return true\n    end\n"),
    dict(id="SSU1B-S6 nondet --> det does not reset the supervisor (KILL DS 'setDetDefinition!': `d.codes === d.code_data.virgin` after the set, and `p.codes === p.code_data.virgin` through setAttrDefinition)",
         file=PROC, targets=TARGETS,
         old="        def.flags |= P_DET\n        freeCodesDefinition!(gd, def, true)         # reset to S_VIRGIN\n",
         new="        def.flags |= P_DET\n        nothing                                     # reset to S_VIRGIN\n"),
    dict(id="SSU1B-S7 setAttrDefinition sets P_DET by the generic flag path, no reset (KILL DS 'setDetDefinition!': `p.codes === p.code_data.virgin` after `setAttrDefinition(ld, p, P_DET, true)` and after the clear)",
         file=PROC, targets=TARGETS,
         old="    attr == P_DET && return setDetDefinition!(_query_gd(ld), def, val)\n",
         new=""),
    # ── pl-wrap.jl skipWrapperPrefix (pl-wrap.c) ──
    dict(id="SSU1B-S8 skipWrapperPrefix does not step over S_DET (KILL DS 'skipWrapperPrefix': `skipWrapperPrefix(c(S_DET, S_CALLWRAPPER, ...)) == 2`, and the `tdt` row `i == 2` with `isCallWrapper(t.codes[i])`)",
         file=WRAP, targets=TARGETS,
         old="        elseif op == S_SSU_DET || op == S_DET\n",
         new="        elseif op == S_SSU_DET\n"),
]
