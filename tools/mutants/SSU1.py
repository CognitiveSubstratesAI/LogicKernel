# ORIGINAL: SSU1's mutant list — no swipl-devel counterpart.
# tools/mutants/SSU1.py — the mutation battery of SSU1 (single sided unification compiled, stored and decompiled: pl-comp.c
# is_neck, get_head_and_body_clause, compileClause's SSU flags, initVMIMerge's SSU entries, the head walkers, clause_functor
# and `'$rule'/2`; pl-proc.c add_ssu_clause, assertDefinition and retract's two tests; pl-supervisor.c
# chainPredicateSupervisor's S_SSU_DET; pl-error.c ERR_PERMISSION_SSU_DEF; boot/init.pl's guard rewrite in the consult
# stand-in), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as AV8.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Killed by test/compile/test_ssu_compile_swipl.jl (rows named in each id's KILL) and, for the call's
# refusal, test/db/test_assert_swipl.jl. Hand-run before the commit (D-0104, `tools/mutate.sh run-in-tree`): verdicts in
# lk-channel evidence/SSU1/mutants_verdicts.tsv.
# The `old` strings were re-fitted after `tools/warm.sh fmt` (T1, T2, D3: fmt rewrapped their lines); mutate_drive.py
# refuses a string that does not occur exactly once.
# NOT LISTED:
#   * decompile_head!'s moved-argument test without `I_SSU_*` (pl-comp.c:5991-5992): EQUIVALENT in effect — an argument the
#     body reads whose head void merged into `I_SSU_*` would take the "moved" path, which unifies the head argument with
#     its slot variable, and the terminal case then clears its bit and unifies the bvar slot with the same variable, so
#     the decompiled clause is the same. (Recorded here; not a battery entry.)
#   * `_init_is_true` (`'$is_true'/1`): with the `optimise` flag off (both systems' default; the kernel has no
#     set_prolog_flag/2 before R2) its answer never decides the rewrite.
#   * The guard rewrite's `?=>(Head, (Cond, !, Body))` shape is pinned by c02/c15/c24 and v04 (D7-1 removes it whole).
#   * The run-loop mutants (`I_CHP`'s choice point, the trail test, `S_SSU_DET`'s flag) are SSU2's: SSU1 does not run them.
TA = ["test/compile/test_ssu_compile_swipl.jl"]
TB = ["test/db/test_assert_swipl.jl"]
TARGETS = TA + TB                                    # the baseline's targets (mutate_ci.py plan reads TARGETS)
C = "src/pl-comp.jl"
P = "src/pl-proc.jl"
S = "src/pl-supervisor.jl"
E = "src/pl-error.jl"
V = "src/pl-vmi.jl"
B = "boot/init.jl"
MUTANTS = [
    # ── pl-comp.c is_neck / get_head_and_body_clause / assert_term ──
    dict(id="SSU1-N1 `=>` read as `?=>` (KILL c15, c16, c17, v01)", file=C, targets=TA,
         old="        return (true, SSU_COMMIT_CLAUSE)\n",
         new="        return (true, SSU_CHOICE_CLAUSE)\n"),
    dict(id="SSU1-N2 `?=>` read as `:-` (KILL c18, c23, v03)", file=C, targets=TA,
         old="        return (true, SSU_CHOICE_CLAUSE)\n",
         new="        return (true, UInt32(0))\n"),
    dict(id="SSU1-N3 assert_term! drops the clause flags: an SSU clause compiles as `:-` (KILL a02, a03, a13r, c15)", file=C, targets=TA + TB,
         old="    clause = compileClause(gd, ld, h, b, proc, gd.modules[module_], warnings, hflags; ex=ex)\n",
         new="    clause = compileClause(gd, ld, h, b, proc, gd.modules[module_], warnings, UInt32(0); ex=ex)\n"),
    # ── pl-comp.c compileClause ──
    dict(id="SSU1-H1 head_unify without the SSU_CHOICE term: a dynamic `?=>` does not move (KILL a13c, a13r)", file=C, targets=TA,
         old="        (flags & SSU_CHOICE_CLAUSE) != 0 || (\n",
         new="        false || (\n"),
    dict(id="SSU1-H2 head_unify without the !SSU_COMMIT term: a static `=>` moves (KILL c25, v08)", file=C, targets=TA,
         old="            (flags & SSU_COMMIT_CLAUSE) == 0 && (def.flags & P_DYNAMIC) == 0 &&\n",
         new="            (def.flags & P_DYNAMIC) == 0 &&\n"),
    dict(id="SSU1-C1 `I_CHP` not emitted (KILL v01-v10)", file=C, targets=TA,
         old="        Output_0!(ci, I_CHP)\n",
         new="        nothing\n"),
    dict(id="SSU1-C2 a `=>` rule enters with `I_ENTER` (KILL v01, v02, v07-v09)", file=C, targets=TA,
         old="            Output_0!(ci, I_SSU_COMMIT)\n",
         new="            Output_0!(ci, I_ENTER)\n"),
    dict(id="SSU1-C3 a `?=>` rule enters with `I_ENTER` (KILL v03, v04, v05, v10)", file=C, targets=TA,
         old="            Output_0!(ci, I_SSU_CHOICE)\n",
         new="            Output_0!(ci, I_ENTER)\n"),
    dict(id="SSU1-C4 an SSU clause with body `true` is a fact (`I_EXITFACT`, UNIT_CLAUSE; KILL c17, c21, v06)", file=C, targets=TA,
         old="    elseif ssu != 0                                            # an SSU clause with body `true` (c:2173-2175)\n",
         new="    elseif false\n"),
    # ── pl-comp.c initVMIMerge ──
    dict(id="SSU1-M1 a void before `I_SSU_COMMIT` stays (KILL v01, v04)", file=C, targets=TA,
         old="            vmi_merge(I_SSU_COMMIT, VMI_REPLACE, I_SSU_COMMIT, 0, code(0)),  # (SSU1, pl-comp.c:1883)\n",
         new="            vmi_merge(code(0), VMI_REPLACE, code(0), 0, code(0)),  # (SSU1, pl-comp.c:1883)\n"),
    dict(id="SSU1-M2 voids before `I_SSU_CHOICE` stay (KILL v04)", file=C, targets=TA,
         old="            vmi_merge(I_SSU_CHOICE, VMI_REPLACE, I_SSU_CHOICE, 0, code(0)),  # (SSU1, pl-comp.c:1886)\n",
         new="            vmi_merge(code(0), VMI_REPLACE, code(0), 0, code(0)),  # (SSU1, pl-comp.c:1886)\n"),
    # ── pl-vmi.c code_info ──
    dict(id="SSU1-V1 `I_SSU_COMMIT` declared with one operand (the walkers step over the next word; KILL v01)", file=V, targets=TA,
         old="    code_info(:I_SSU_COMMIT, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),\n",
         new="    code_info(:I_SSU_COMMIT, 0x00, 1, (CA1_INTEGER, 0x00, 0x00, 0x00)),\n"),
    # ── the head walkers and the decompiler ──
    dict(id="SSU1-W1 `_body_start` stops only at `I_ENTER` (KILL c01, c02)", file=C, targets=TA,
         old="    while c != I_ENTER && c != I_SSU_COMMIT && c != I_SSU_CHOICE\n",
         new="    while c != I_ENTER\n"),
    dict(id="SSU1-W3 decompile_head! has no `I_SSU_*` end case (KILL c01, c16)", file=C, targets=TA,
         old="            c == I_SSU_COMMIT || c == I_SSU_CHOICE                                   # (SSU1, pl-comp.c:6157-6158)\n",
         new="            false\n"),
    dict(id="SSU1-W4 argKey has no `I_SSU_*` case (KILL the load: zero/0's key)", file=C, targets=TA,
         old="            c == I_SSU_COMMIT || c == I_SSU_CHOICE                  # (SSU1, pl-comp.c:5526-5527)\n",
         new="            false\n"),
    dict(id="SSU1-R1 `'$rule'/2` reads `=>` as `?=>` (KILL c16, c17)", file=C, targets=TA,
         old="    ssu == SSU_COMMIT_CLAUSE && return _err_functor(ld, Symbol(\"=>\"), 2) # FUNCTOR_ssu_commit2\n",
         new="    ssu == SSU_COMMIT_CLAUSE && return _err_functor(ld, Symbol(\"?=>\"), 2) # FUNCTOR_ssu_commit2\n"),
    dict(id="SSU1-R2 `'$rule'/2` of a fact is `H :- true` (KILL c27)", file=C, targets=TA,
         old="    if (clause.flags & UNIT_CLAUSE) != 0\n        PL_put_term(ld, term, h)\n",
         new="    if false\n        PL_put_term(ld, term, h)\n"),
    dict(id="SSU1-R3 `'$rule'/2` is not registered (KILL c15)", file=C, targets=TA,
         old="        \"\\$rule\", 2, pl_ruleva_va,\n",
         new="        \"\\$rule_x\", 2, pl_ruleva_va,\n"),
    dict(id="SSU1-R4 `'$rule'/2` splits the clause as clause/2 does (KILL c15)", file=C, targets=TA,
         old="    return clause_ndet(ld, A1, A2, PL__ac, PL__ctx, IS_RULE)\n",
         new="    return clause_ndet(ld, A1, A2, PL__ac, PL__ctx, IS_CLAUSE)\n"),
    # ── pl-proc.c add_ssu_clause / retract ──
    dict(id="SSU1-A1 an SSU clause is added to a normal predicate (KILL a03, a15)", file=P, targets=TA,
         old="                def.flags |= P_SSU_DET\n            else\n                return PL_error(ld, ERR_PERMISSION_SSU_DEF, def)\n",
         new="                def.flags |= P_SSU_DET\n            else\n                return true\n"),
    dict(id="SSU1-A2 a normal clause is added to an SSU predicate (KILL a02, a14)", file=P, targets=TA,
         old="                def.flags &= ~P_SSU_DET\n            else\n                return PL_error(ld, ERR_PERMISSION_SSU_DEF, def)\n",
         new="                def.flags &= ~P_SSU_DET\n            else\n                return true\n"),
    dict(id="SSU1-A3 the first SSU clause does not set P_SSU_DET (KILL a06, the S_SSU_DET supervisor rows, the call's refusal)", file=P, targets=TA + TB,
         old="                def.flags |= P_SSU_DET\n",
         new="                nothing\n"),
    dict(id="SSU1-E1 the mixing error names `modify` (KILL a02, a03)", file=E, targets=TA,
         old="        _err_atom(ld, mk_sym(T, :assert)), _err_atom(ld, mk_sym(T, :procedure)), pi\n",
         new="        _err_atom(ld, mk_sym(T, :modify)), _err_atom(ld, mk_sym(T, :procedure)), pi\n"),
    dict(id="SSU1-T1 retract/1 without the CLAUSE_SSU_FLAGS test: `retract((F => true))` removes the fact F (KILL a22, a23, a24)", file=P, targets=TA,
         old="            (clause.flags & CLAUSE_SSU_FLAGS) == (flags & CLAUSE_SSU_FLAGS) && if cl_is_head\n",
         new="            true && if cl_is_head\n"),
    # SSU1-T2 (retract/1 without the neck test) is retired with BP2 (upstream ea1b569bd): `cl` takes the neck of the call's
    # flags, so the neck test is implied by the flags equality above it (tools/mutants/BP2r.py, BP2-Q9c/Q9d).
    # ── pl-supervisor.c chainPredicateSupervisor ──
    dict(id="SSU1-S1 `S_SSU_DET` not prepended (KILL the v-rows' supervisors, the call's refusal)", file=S, targets=TA + TB,
         old="    if (def.flags & P_SSU_DET) != 0                 # ison(def, P_SSU_DET|P_DET) (P_DET: see above)\n",
         new="    if false\n"),
    # ── boot/init.pl's guard rewrite (the consult stand-in, D7) ──
    dict(id="SSU1-D1 the guard form is not rewritten (KILL c02, c15, v04)", file=B, targets=TA,
         old="        if _init_is(ld, pre, Symbol(\",\"), 2)            # nonvar(Pre), Pre = (Head,Cond), !\n",
         new="        if false\n"),
    dict(id="SSU1-D2 a `true` guard is optimised away with the flag off (KILL c24)", file=B, targets=TA,
         old="            if _init_is_true(ld, cond) && ld.prolog_flag_optimise   # current_prolog_flag(optimise, true)\n",
         new="            if _init_is_true(ld, cond)\n"),
    dict(id="SSU1-D3 the rewrite drops the cut: `?=>(H, (G, B))` (KILL c02, c15, v04)", file=B, targets=TA,
         old="                    ld, g, _err_functor(ld, Symbol(\",\"), 2), _err_atom(ld, mk_sym(T, :!)),\n",
         new="                    ld, g, _err_functor(ld, Symbol(\",\"), 2), _err_atom(ld, mk_sym(T, Symbol(\"true\"))),\n"),
]
