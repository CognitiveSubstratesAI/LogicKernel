# ORIGINAL: WRAP1's mutant list - no swipl-devel counterpart.
# tools/mutants/WRAP1.py - the mutation battery of WRAP1 (pl-wrap.c: wrap_predicate/4 through '$c_wrap_predicate'/5, unwrap_predicate/2,
# '$wrapped_predicate'/2, '$wrapped_implementation'/3, '$closure_predicate'/2, write_closure; the closure branch of i_metacall_common
# (I_CALL1/I_CALLN), S_WRAP and S_CALLWRAPPER of pl-vmi.c; the kernel's own helpers supervisor_crefs and innermost_supervisor, the two retry
# sites of a wrapped foreign predicate). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's
# (as PIN1.py, D1f.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`, `targets`. Written edit-only (no Julia ran);
# the kill each id names is the assertion DESIGNED to fail: W = test/core_lang/test_wrap_swipl.jl (the differential testset, whose
# `@test (i, kl[i]) == (i, expected[i])` kills any change of a row t0..t21, and the named kill rows: row("tN") == ... , the white-box
# testsets "closures, supervisor_crefs, innermost_supervisor, unwrap" and "a query on a wrapped between/3").
# `old` was counted EXACTLY once in its file, `new` differs, by a python3 -I script at d87d1047 (src/ as at 318c7491); RE-FIT any `old`
# that `tools/warm.sh fmt` rewraps.
# VERDICTS: the CI fresh-process verdicts are authoritative. The boot makes five `$wrap$` closures (test_boot_image_swipl.jl:31), so
# `gd.closure_refs` is non-empty before any row and a mutant of closure creation is in the template (PIN1 part 2: the warm daemon cannot
# judge a boot-path mutant, `PL_global_data{T}()` copies a template built once per process, src/gd_template.jl). The closure branch of the run
# loop (src/pl-wam.jl i_metacall_common, S_WRAP, S_CALLWRAPPER) is not the boot path itself.
# LOOPS (audit D-0423 item 4, D-0440 item 2): a mutant must FAIL, not loop. A mutant that can send the run loop round forever (a wrong
# supervisor or side table: the wrapper clause runs again and again) carries its bound in its own `new` text, the idiom
#   (let t_ = task_local_storage(); n_ = get(t_, :wrap1_mut, 0) + 1; t_[:wrap1_mut] = n_; n_ > 10_000 && error("...") end)
# which counts only the DEVIATING calls (the mutant's own wrong branch: an unwrapped predicate never reaches it), so the unmutated path never
# trips it; these carry `targets=[W]`. The unwrap and closure-number mutants use a non-looping wrong value (`ClauseRef{T}[]`, an index
# past the table, ...) in place of a deleted assignment. A TIMEOUT is blocking: there is no `expect="hang"` row.
# EQUIVALENT, with the code reason:
#   * WRAP1-M8 S_CALLWRAPPER `PC += 3` -> `PC += 2`: the next instruction is `@goto TRUST_CLAUSE`, whose body sets `PC = 1` (src/pl-wam.jl:4982,
#     `@label TRUST_CLAUSE` 4974) before any operand is read.
#   * WRAP1-M16c write_closure reads `c.predicate` where it reads `c.def`: `unify_closure` copies name, arity, module and flags of the wrapped
#     predicate into the copy `c.def` (src/pl-wrap.jl:72-77), and `_autoload_predicate_name` reads only those.
# DEFERRED KILL (audit D-0374 item 2): a row declared `equivalent="DEFERRED KILL: ..."` has no killing assertion yet; it must SURVIVE the battery,
# and when the owner adds the row the declaration goes (a caught mutant declared equivalent BLOCKS):
#   * WRAP1-M7 (S_CALLWRAPPER does not set DEF to the wrapper clause's predicate): the frame's predicate is the one thing it changes. swipl 10.1.20
#     answers a wrapper body that reads its own frame (`prolog_current_frame(F), prolog_frame_attribute(F, predicate_indicator, PI)`) with
#     PI = '$wrap$p'/1, but the kernel has no prolog_frame_attribute/3 (docs/r2_owners.tsv:121, owner DBG1: missing_c_preds), so no row can
#     be run. Owner WRAP1-test (the row t22 of test_wrap_swipl.pl, written when DBG1 lands; the oracle answer is recorded in the comment of
#     test_wrap_swipl.jl's kill-row testset).
# BASELINE: test/core_lang/test_tabling_min_swipl.jl is NOT a target: its T3 rows (S_CALLWRAPPER, S_WRAP as NotPortedError) were flipped
# to the behaviour in this step (cbff7151), which nothing has run yet; it joins the baseline when the gate has read it green.
# TARGETS (audit D-0238): every test file that runs the mutated code. The wrapper-only mutants list W alone (an unwrapped predicate never
# reaches them); the common-path mutants (call/N, supervisor_crefs, the blob writer) list W plus the files that run those paths:
# test_metacall.jl (call/N), test_ssu_swipl.jl (S_LIST rows s32/s33, skipWrapperPrefix of S_SSU_DET), test_expr_functor.jl (S_LIST :301),
# test_between_swipl.jl and foreign/test_query.jl (the foreign retry sites), test_blob.jl (the blob writer).
W = "test/core_lang/test_wrap_swipl.jl"
MC = "test/core_lang/test_metacall.jl"
SSU = "test/core_lang/test_ssu_swipl.jl"
EXF = "test/core_lang/test_expr_functor.jl"
BT = "test/core_lang/test_between_swipl.jl"
FQ = "test/foreign/test_query.jl"
BL = "test/core_lang/test_blob.jl"
COMMON = [W, MC, SSU, EXF, BT, FQ, BL]
TARGETS = COMMON                              # the baseline's targets (mutate_ci.py plan reads TARGETS): every file a mutant lists
WAM = "src/pl-wam.jl"
WRP = "src/pl-wrap.jl"
WRT = "src/pl-write.jl"
BOUND = '(let t_ = task_local_storage(); n_ = get(t_, :wrap1_mut, 0) + 1; t_[:wrap1_mut] = n_; n_ > 10_000 && error("WRAP1 mutant loops: bounded (D-0423 item 4)") end)'
MUTANTS = [
    # ── the closure branch of i_metacall_common (pl-vmi.c I_CALL1/I_CALLN: `clsp`; src/pl-wam.jl) ──
    dict(id="WRAP1-M1 the closure ATOM called with call/N is a type error (KILL W: t8, named row t8)",
         file=WAM, targets=[W],
         old="            mc_clo = closure_of_word(gd, mc_w)\n            mc_clo === nothing && @goto call_type_error\n",
         new="            @goto call_type_error\n"),
    dict(id="WRAP1-M1b a non-closure blob atom as a goal is not refused (KILL W: row t21, call(Ref) = type_error(callable))",
         file=WAM, targets=[W],
         old="            mc_clo = closure_of_word(gd, mc_w)\n            mc_clo === nothing && @goto call_type_error\n",
         new="            mc_clo = closure_of_word(gd, mc_w)\n"),
    dict(id="WRAP1-M1c a compound whose name is a non-closure blob is not refused (KILL W: row t21, call(G) = type_error(callable))",
         file=WAM, targets=[W],
         old="            mc_clo = closure_of_word(gd, _atom_word!(ld, mc_name))\n            mc_clo === nothing && @goto call_type_error\n",
         new="            mc_clo = closure_of_word(gd, _atom_word!(ld, mc_name))\n"),
    dict(id="WRAP1-M2 call/N accepts a closure compound (only call/1 may; KILL W: row t13, named row t13)",
         file=WAM, targets=[W],
         old="            mc_call0 || @goto call_type_error\n            mc_clo = closure_of_word(gd, _atom_word!(ld, mc_name))\n",
         new="            mc_clo = closure_of_word(gd, _atom_word!(ld, mc_name))\n"),
    dict(id="WRAP1-M3 a closure call runs the WRAPPED predicate's definition, not the copy (the wrapper runs again: a loop, bounded; KILL W: t0, :189, or the bound's error)",
         file=WAM, targets=[W],
         old="        DEF = mc_clo.def                            # DEF = &clsp->def (the copy; S_WRAP switches to the wrapped one)\n",
         new="        DEF = (" + BOUND + "; mc_clo.predicate)                            # DEF = &clsp->def (the copy; S_WRAP switches to the wrapped one)\n"),
    dict(id="WRAP1-M3b the closure test is inverted: every call/N takes the closure branch (KILL W, test_metacall.jl: any call/N)",
         file=WAM, targets=COMMON,
         old="    if mc_clo === nothing\n        mc_proc = resolveProcedure(gd, mc_name, mc_arity + mc_callargs, gd.modules[mc_mi])\n",
         new="    if mc_clo !== nothing\n        mc_proc = resolveProcedure(gd, mc_name, mc_arity + mc_callargs, gd.modules[mc_mi])\n"),
    # ── S_WRAP (pl-vmi.c:3560-3578) ──
    dict(id="WRAP1-M4 S_WRAP never creates the wrapped supervisor (the virgin one runs: KILL W: :311, :312, t0)",
         file=WAM, targets=[W],
         old="    if sw_codes[1] == S_VIRGIN                      # codes[0] == encode(S_VIRGIN)\n",
         new="    if false                      # codes[0] == encode(S_VIRGIN)\n"),
    dict(id="WRAP1-M5 S_WRAP keeps the copy as the frame's predicate (supervisor_crefs raises: the copy's chain has no wrapper; KILL W: t0, :169)",
         file=WAM, targets=[W],
         old="    DEF = sw_c.predicate                            # DEF = DEF->impl.wrapped.predicate\n",
         new="    DEF = DEF                            # DEF = DEF->impl.wrapped.predicate\n"),
    dict(id="WRAP1-M20 S_WRAP runs the wrapped predicate's own code (the wrapper: a loop, bounded; KILL W: t0 :189 or the bound's error)",
         file=WAM, targets=[W],
         old="    PCc = sw_codes                                  # PC = codes\n",
         new="    PCc = (sw_c.predicate.codes === sw_codes ? sw_codes : (" + BOUND + "; sw_c.predicate.codes))                                  # PC = codes\n"),
    dict(id="WRAP1-M21 S_WRAP stores the supervisor but not its side table (an empty table: BoundsError; KILL W: :312, t0)",
         file=WAM, targets=[W],
         old="        sw_c.supervisor_crefs = sw_crefs\n",
         new="        sw_crefs = sw_crefs\n"),
    dict(id="WRAP1-M22 S_WRAP stores the side table but not the supervisor (the virgin stays: KILL W: :311 `c.supervisor !== virgin`)",
         file=WAM, targets=[W],
         old="        sw_c.supervisor = sw_codes                  # DEF->impl.wrapped.supervisor = codes\n",
         new="        sw_codes = sw_codes                  # DEF->impl.wrapped.supervisor = codes\n"),
    # ── the clause-reference operand of S_TRUSTME and S_LIST after S_WRAP (the running supervisor's table: supervisor_crefs) ──
    dict(id="WRAP1-M6 S_TRUSTME reads the wrapper's table, not the running supervisor's (wrong clause: a loop, bounded; KILL W: t1 :190, :313-314)",
         file=WAM, targets=[W],
         old="    tc_cref = supervisor_crefs(gd, DEF, PCc)[Int(PCc[PC])]   # code2ptr(ClauseRef, *PC++)\n",
         new="    tc_cref = (PCc === DEF.codes ? DEF.codes_crefs : (" + BOUND + "; DEF.codes_crefs))[Int(PCc[PC])]   # code2ptr(ClauseRef, *PC++)\n"),
    dict(id="WRAP1-M6b S_LIST's list clause reads the wrapper's table (bounded; KILL W: row t19 `p19([x], cons)`, named row t19)",
         file=WAM, targets=[W],
         old="                tc_cref = supervisor_crefs(gd, DEF, PCc)[Int(PCc[PC + 2])]\n",
         new="                tc_cref = (PCc === DEF.codes ? DEF.codes_crefs : (" + BOUND + "; DEF.codes_crefs))[Int(PCc[PC + 2])]\n"),
    dict(id="WRAP1-M6c S_LIST's nil clause reads the wrapper's table (bounded; KILL W: row t19 `p19([], nil)`, named row t19)",
         file=WAM, targets=[W],
         old="            tc_cref = supervisor_crefs(gd, DEF, PCc)[Int(PCc[PC + 1])]\n",
         new="            tc_cref = (PCc === DEF.codes ? DEF.codes_crefs : (" + BOUND + "; DEF.codes_crefs))[Int(PCc[PC + 1])]\n"),
    # ── S_CALLWRAPPER (pl-vmi.c:3624-3632) ──
    dict(id="WRAP1-M7 S_CALLWRAPPER leaves the frame's predicate as the wrapped one (DEFERRED KILL: the row needs prolog_frame_attribute/3, owner DBG1)",
         file=WAM, targets=[W],
         equivalent="DEFERRED KILL: owner WRAP1-test (the row t22 reads the wrapper frame's predicate_indicator with prolog_frame_attribute/3, which the kernel lacks: docs/r2_owners.tsv:121, owner DBG1; swipl 10.1.20's answer is '$wrap$p'/1); no other row reads the frame's predicate of a wrapper clause (the wrapper predicate is module_transparent in the same module as the wrapped one)",
         old="    DEF = (tc_cref.clause::Clause{T}).predicate     # FR->predicate = DEF = cref->value.clause->predicate\n",
         new="    # (WRAP1-M7: DEF stays the wrapped predicate)\n"),
    dict(id="WRAP1-M8 S_CALLWRAPPER steps over two operand words, not three (EQUIVALENT: TRUST_CLAUSE sets PC = 1, src/pl-wam.jl:4982)",
         file=WAM, targets=[W],
         equivalent="src/pl-wam.jl:4982 - `@goto TRUST_CLAUSE` runs `PC = 1` (the label is at :4974) before any operand word is read, so the value of PC after the operands is never used",
         old="    tc_cref = supervisor_crefs(gd, DEF, PCc)[Int(PCc[PC])]   # ClauseRef cref = code2ptr(ClauseRef, *PC)\n    PC += 3\n",
         new="    tc_cref = supervisor_crefs(gd, DEF, PCc)[Int(PCc[PC])]   # ClauseRef cref = code2ptr(ClauseRef, *PC)\n    PC += 2\n"),
    dict(id="WRAP1-M8b S_CALLWRAPPER reads the wrapper NAME word as its clause operand (BoundsError; KILL W: t0 :189, :169)",
         file=WAM, targets=[W],
         old="    tc_cref = supervisor_crefs(gd, DEF, PCc)[Int(PCc[PC])]   # ClauseRef cref = code2ptr(ClauseRef, *PC)\n",
         new="    tc_cref = supervisor_crefs(gd, DEF, PCc)[Int(PCc[PC + 2])]   # ClauseRef cref = code2ptr(ClauseRef, *PC)\n"),
    # ── the retry sites of a wrapped non-deterministic foreign predicate (shallow_backtrack, deep_backtrack): innermost_supervisor ──
    dict(id="WRAP1-M14a shallow_backtrack retries a wrapped foreign predicate in the wrapper's code (a loop, bounded; KILL W: the query on a wrapped between/3, `got == [1, 2, 3]`)",
         file=WAM, targets=[W],
         old="                DEF = sb_def\n                PCc = innermost_supervisor(gd, DEF)[1]  # (WRAP1) a wrapped foreign predicate retries in the foreign supervisor\n",
         new="                DEF = sb_def\n                PCc = innermost_supervisor(gd, DEF)[1] === DEF.codes ? DEF.codes : (" + BOUND + "; DEF.codes)  # (WRAP1) a wrapped foreign predicate retries in the foreign supervisor\n"),
    dict(id="WRAP1-M14b deep_backtrack retries a wrapped foreign predicate in the wrapper's code (a loop, bounded; KILL W: t18 :245, named row t18)",
         file=WAM, targets=[W],
         old="        if (DEF.flags & P_FOREIGN) != 0             # (NF1) an index into the supervisor\n            PCc = innermost_supervisor(gd, DEF)[1]  # (WRAP1) a wrapped foreign predicate retries in the foreign supervisor\n",
         new="        if (DEF.flags & P_FOREIGN) != 0             # (NF1) an index into the supervisor\n            PCc = innermost_supervisor(gd, DEF)[1] === DEF.codes ? DEF.codes : (" + BOUND + "; DEF.codes)  # (WRAP1) a wrapped foreign predicate retries in the foreign supervisor\n"),
    # ── the closure's number and payload (pl-wrap.jl unify_closure) ──
    dict(id="WRAP1-M15 the closure's number is past the table (S_WRAP: BoundsError; KILL W: :302, t0)",
         file=WRP, targets=[W],
         old="    cdef.impl_foreign_function = length(gd.closure_refs)\n",
         new="    cdef.impl_foreign_function = length(gd.closure_refs) + 1_000_000\n"),
    dict(id="WRAP1-M15b the closure's number is 0: the copy is an undefined predicate (KILL W: :303-304, t8)",
         file=WRP, targets=[W],
         old="    cdef.impl_foreign_function = length(gd.closure_refs)\n",
         new="    cdef.impl_foreign_function = 0\n"),
    dict(id="WRAP1-M15c the blob's payload is past the table (closure_of_word: BoundsError; KILL W: t1 :190, :302)",
         file=WRP, targets=[W],
         old="    bytes = _closure_bytes(length(gd.closure_refs))\n",
         new="    bytes = _closure_bytes(length(gd.closure_refs) + 1_000_000)\n"),
    # ── write_closure and its hook (pl-wrap.c write_closure; pl-write.jl writeAtom) ──
    dict(id="WRAP1-M16 write_closure prints `<closure> (` (KILL W: :254-255, row t15)",
         file=WRP, targets=[W],
         old='    "<closure>(" * _autoload_predicate_name(gd, c.def) * ")"',
         new='    "<closure> (" * _autoload_predicate_name(gd, c.def) * ")"'),
    dict(id="WRAP1-M16b writeAtom never takes the closure hook (a closure prints as an ordinary blob; KILL W: :254, :255, row t15)",
         file=WRT, targets=[W],
         old="        wc = closure_of_word(options.gd, blob_handle(a))\n        if wc !== nothing\n",
         new="        wc = closure_of_word(options.gd, blob_handle(a))\n        if false\n"),
    dict(id="WRAP1-M16d writeAtom takes the closure hook for every blob (write_closure of `nothing`: KILL test_blob.jl: a stream, clause reference or mutex written)",
         file=WRT, targets=[W, BL],
         old="        wc = closure_of_word(options.gd, blob_handle(a))\n        if wc !== nothing\n",
         new="        wc = closure_of_word(options.gd, blob_handle(a))\n        if true\n"),
    dict(id="WRAP1-M16c write_closure names the WRAPPED predicate, not the copy (EQUIVALENT: unify_closure copies name, arity, module of it)",
         file=WRP, targets=[W],
         equivalent="src/pl-wrap.jl:72-77 - `unify_closure` builds the copy `c.def` from `def.functor_name`, `def.arity`, `def.flags` and `def.module_`, which are everything `_autoload_predicate_name` reads, so `c.def` and `c.predicate` print alike",
         old='    "<closure>(" * _autoload_predicate_name(gd, c.def) * ")"',
         new='    "<closure>(" * _autoload_predicate_name(gd, c.predicate) * ")"'),
    # ── supervisor_crefs and innermost_supervisor (src/pl-wrap.jl, ORIGINAL) ──
    dict(id="WRAP1-M17 supervisor_crefs has no hot path (every unwrapped static predicate raises; KILL W :309, test_metacall.jl, test_ssu_swipl.jl, ...)",
         file=WRP, targets=COMMON,
         old="    codes === def.codes && return def.codes_crefs\n",
         new="\n"),
    dict(id="WRAP1-M17b supervisor_crefs's chain walk returns the first wrapper's table (wrong clause: a loop, bounded; KILL W :340, t2, t3)",
         file=WRP, targets=[W],
         old="        c.supervisor === codes && return c.supervisor_crefs\n",
         new="        c.supervisor === codes || " + BOUND + "\n        return c.supervisor_crefs\n"),
    dict(id="WRAP1-M17c innermost_supervisor does not follow the side table (KILL W: :319, :326-327)",
         file=WRP, targets=[W],
         old="        crefs = c.supervisor_crefs\n        i = skipWrapperPrefix(codes)\n    end\n    return codes, crefs\n",
         new="        i = skipWrapperPrefix(codes)\n    end\n    return codes, crefs\n"),
    dict(id="WRAP1-M17d innermost_supervisor goes one wrapper in, not to the innermost (KILL W: :343, :352-353)",
         file=WRP, targets=[W],
         old="    while isCallWrapper(codes[i])\n        c = closure_of_word(gd, codes[i + 2])::closure{T}\n        codes = c.supervisor\n",
         new="    if isCallWrapper(codes[i])\n        c = closure_of_word(gd, codes[i + 2])::closure{T}\n        codes = c.supervisor\n"),
    # ── find_wrapper, unify_wrapped ('$wrapped_implementation'/3) ──
    dict(id="WRAP1-M11 unify_wrapped of a nullary predicate fails (KILL W: row t6, p6z; named row t6)",
         file=WRP, targets=[W],
         old="    return PL_unify_atom(ld, wrapped, clo)\n",
         new="    return false\n"),
    dict(id="WRAP1-M11b find_wrapper finds the first wrapper whatever its name (KILL W: t6, t3 :201)",
         file=WRP, targets=[W],
         old="        codes[i + 3] == name && return (codes, crefs, i)",
         new="        true && return (codes, crefs, i)"),
    # ── unwrap_predicate/2 (pl-wrap.c uwrap_predicate) ──
    dict(id="WRAP1-M10 unwrap_predicate/2 unwraps the wrapper whose name does NOT match (KILL W: t4 :210)",
         file=WRP, targets=[W],
         old="        if !PL_unify_atom(ld, A2, wname)\n",
         new="        if PL_unify_atom(ld, A2, wname)\n"),
    dict(id="WRAP1-M9 unwrap installs an empty side table in the predicate (BoundsError; KILL W: :348, t4)",
         file=WRP, targets=[W],
         old="            def.codes_crefs = c.supervisor_crefs\n",
         new="            def.codes_crefs = ClauseRef{T}[]\n"),
    dict(id="WRAP1-M9b unwrap installs the virgin supervisor, not the inner one (the wrappers are lost: KILL W: :347 `d.codes === saved_codes`)",
         file=WRP, targets=[W],
         old="            def.codes = c.supervisor\n",
         new="            def.codes = def.code_data.virgin\n"),
    dict(id="WRAP1-M9c unwrap of an inner wrapper leaves the outer one pointing at it (KILL W: t4 :210)",
         file=WRP, targets=[W],
         old="            holder.supervisor = c.supervisor\n",
         new="\n"),
    dict(id="WRAP1-M9d unwrap of an inner wrapper gives the outer one an empty side table (BoundsError; KILL W: t4 :210)",
         file=WRP, targets=[W],
         old="            holder.supervisor_crefs = c.supervisor_crefs\n",
         new="            holder.supervisor_crefs = ClauseRef{T}[]\n"),
    dict(id="WRAP1-M9e unwrap does not retract the wrapper's clause (KILL W: row t20, the clauses of `$wrap$p20` left: 1 then 0; named row t20)",
         file=WRP, targets=[W],
         old="        retractClauseDefinition!(gd, cl.predicate, cl, false)\n",
         new="\n"),
    # ── '$wrapped_predicate'/2 (pl-wrap.c wrapped_predicate) ──
    dict(id="WRAP1-M18 '$wrapped_predicate'/2 lists only the outermost wrapper (KILL W: t5 :223, t3 :201, row t16)",
         file=WRP, targets=[W],
         old="            isCallWrapper(codes[cw]) || return PL_unify_nil(ld, tail) ? FTRUE : FFALSE\n",
         new="            return PL_unify_nil(ld, tail) ? FTRUE : FFALSE\n"),
    dict(id="WRAP1-M18b '$wrapped_predicate'/2 puts the name in argument 2 of `-` (KILL W: t3, t5)",
         file=WRP, targets=[W],
         old="            PL_unify_arg(ld, 1, head, nt) || return FFALSE",
         new="            PL_unify_arg(ld, 2, head, nt) || return FFALSE"),
    dict(id="WRAP1-M18c '$wrapped_predicate'/2 names a wrapper by the closure word, not the name word (KILL W: t5 :223)",
         file=WRP, targets=[W],
         old="            PL_put_atom(ld, nt, _atom_value(ld, codes[cw + 3]))\n",
         new="            PL_put_atom(ld, nt, _atom_value(ld, codes[cw + 2]))\n"),
    dict(id="WRAP1-M19 '$wrapped_predicate'/2 succeeds for a predicate without wrapper (KILL W: t5 :223, `plain`)",
         file=WRP, targets=[W],
         old="    return FFALSE\nend\n\n# PORT: pl-wrap.c wrapped_implementation as",
         new="    return FTRUE\nend\n\n# PORT: pl-wrap.c wrapped_implementation as"),
    # ── '$closure_predicate'/2 (pl-wrap.c closure_predicate) ──
    dict(id="WRAP1-M12 '$closure_predicate'/2 of a non-closure fails (KILL W: t7, named row t7)",
         file=WRP, targets=[W],
         old='    return PL_type_error(ld, "closure", A1) ? FTRUE : FFALSE\n',
         new="    return FFALSE\n"),
    dict(id="WRAP1-M13 '$closure_predicate'/2 gives `p/1`, not `user:p/1` (KILL W: t7, named row t7)",
         file=WRP, targets=[W],
         old="                gd, ld, MODULE_user(gd), A2, c.def, 0, GP_QUALIFY | GP_NAMEARITY\n",
         new="                gd, ld, MODULE_user(gd), A2, c.def, 0, GP_NAMEARITY\n"),
    dict(id="WRAP1-M28 '$closure_predicate'/2 reads the handle of any atom, not only a blob's (KILL W: t7, `foo`)",
         file=WRP, targets=[W],
         old="    if a !== nothing && is_blob(a)\n        c = closure_of_word(gd, blob_handle(a))\n",
         new="    if a !== nothing\n        c = closure_of_word(gd, blob_handle(a))\n"),
]
