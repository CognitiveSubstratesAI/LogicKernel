# ORIGINAL: NF3's mutant list — no swipl-devel counterpart.
# tools/mutants/NF3.py — the mutation battery of NF3 (current_op/3 and '$local_op'/3 as non-deterministic foreign predicates;
# audit D-0136), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. One mutant
# per decision of current_op_ndet (src/pl-op.jl) that decides an answer: each filter of the first call and the order of its
# argument checks, the three unifications, the state's three ends (the last answer, the failure, FRG_CUTTED) and the retry, the
# two wrappers' modules and `inherit`, get_op_module's three steps, the registration flags.
# NOT equivalent (refuted by 9b187b5's battery, run 40196979036: NF3-7 was caught): the scan's name and type filters. The
#   unification filters the ANSWERS again, but not the DETERMINISM: an entry the filter would drop stays in the buffer, so the
#   answer before it is not the last (swipl: `current_op(P, fy, -)` and `current_op(P, yfx, -)` are both deterministic).
#   Killed by the testset "a name and a type leave one entry" and by '$local_op'/3's `system:mod` row. (The PRIORITY filter
#   decides answers as well: it runs before the dedup, so a `user` redefinition it drops no longer hides `system`'s — swipl's
#   quirk, case s04 — see NF3-9.)
# EQUIVALENT, with the reason:
#   NF3-E3 the buffer is emptied at the first call (`initBuffer`) AND at every end of the state (`discardBuffer`): either alone
#          leaves it empty; they are killed only together, which one substitution cannot do. NF3-E4 is the end-of-state one.
#   NF3-E5 get_op_module's shortcut `(*m)->name == mname`: when it holds, `isCurrentModule` finds the same module.
# NOT listed: the `k != 0` of FRG_CUTTED (`if ( e )`: a context is never 0 — `discardForeignFrame` decodes only a set `fctx`);
# the `empty!` of the last answer's and the failure's end (as NF3-E4); `e.index == mx` as `>=` (the index never passes `mx` in the
# loop); the foreign frame's close before a return (no observable difference found: not claimed killed).
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does
# not occur exactly once).
TARGETS = ["test/core_lang/test_current_op_swipl.jl"]
T = TARGETS
O = "src/pl-op.jl"
MUTANTS = [
    # ---- the first call (current_op_ndet)
    dict(id="NF3-1 a name given is ignored", file=O, targets=T,
         old='''        if PL_is_variable(ld, name)''',
         new='''        if true'''),
    dict(id="NF3-2 a priority given is ignored", file=O, targets=T,
         old='''        if PL_is_variable(ld, prec)''',
         new='''        if true'''),
    dict(id="NF3-3 priority 0 is a priority", file=O, targets=T,
         old='''            if !(p > 0 && p <= 1200)''',
         new='''            if !(p >= 0 && p <= 1200)'''),
    dict(id="NF3-4 priority 1201 is a priority", file=O, targets=T,
         old='''            if !(p > 0 && p <= 1200)''',
         new='''            if !(p > 0 && p <= 1201)'''),
    dict(id="NF3-5 an unknown type is no error", file=O, targets=T,
         old='''            if t == 0x00''',
         new='''            if false'''),
    dict(id="NF3-7 the scan has no name filter", file=O, targets=T,
         old='''        scanVisibleOperators!(gd, m, nm, p, t, e.buffer, inherit)''',
         new='''        scanVisibleOperators!(gd, m, nothing, p, t, e.buffer, inherit)'''),
    dict(id="NF3-8 the scan has no type filter", file=O, targets=T,
         old='''        scanVisibleOperators!(gd, m, nm, p, t, e.buffer, inherit)''',
         new='''        scanVisibleOperators!(gd, m, nm, p, 0x00, e.buffer, inherit)'''),
    dict(id="NF3-9 the scan has no priority filter", file=O, targets=T,
         old='''        scanVisibleOperators!(gd, m, nm, p, t, e.buffer, inherit)''',
         new='''        scanVisibleOperators!(gd, m, nm, 0, t, e.buffer, inherit)'''),
    dict(id="NF3-10 a reused state keeps its index", file=O, targets=T,
         old='''        e.index = 0''',
         new='''        nothing'''),
    dict(id="NF3-E3 a reused state keeps the old buffer", file=O, targets=T,
         old='''        empty!(e.buffer)                                    # initBuffer(b)''',
         new='''        nothing                                             # initBuffer(b)''',
         equivalent="NF3-E3: every end of a state empties its buffer (discardBuffer), so a state taken from the pool holds none"),
    # ---- the redo loop
    dict(id="NF3-11 the loop runs one past the buffer", file=O, targets=T,
         old='''    while e.index < mx ''',
         new='''    while e.index <= mx '''),
    dict(id="NF3-12 a cancelled operator is an answer", file=O, targets=T,
         old='''        match[3] == 0 && continue ''',
         new='''        nothing '''),
    dict(id="NF3-13 the name is not unified", file=O, targets=T,
         old='''        if PL_unify_atom(ld, name, match[1]) &&''',
         new='''        if true &&'''),
    dict(id="NF3-14 the priority is not unified", file=O, targets=T,
         old='''           PL_unify_integer(ld, prec, Int(match[3])) &&''',
         new='''           true &&'''),
    dict(id="NF3-15 the type is not unified", file=O, targets=T,
         old='''           PL_unify_atom(ld, type, operatorTypeToAtom(T, match[2])::T)''',
         new='''           true'''),
    dict(id="NF3-16 a failed attempt is not rewound", file=O, targets=T,
         old='''        PL_rewind_foreign_frame(ld, fid)''',
         new='''        nothing'''),
    dict(id="NF3-17 the answer before the last is the last", file=O, targets=T,
         old='''            if e.index == mx''',
         new='''            if e.index == mx - 1'''),
    dict(id="NF3-18 the last answer is not the last", file=O, targets=T,
         old='''            if e.index == mx''',
         new='''            if false'''),
    dict(id="NF3-19 the last answer keeps its state", file=O, targets=T,
         old='''                free_foreign_state!(pool, k)                # freeHeap(e, sizeof(*e)): the last answer''',
         new='''                nothing                                     # freeHeap(e, sizeof(*e)): the last answer'''),
    dict(id="NF3-20 a failure keeps its state", file=O, targets=T,
         old='''    free_foreign_state!(pool, k)                            # freeHeap(e, sizeof(*e)): no more answers''',
         new='''    nothing                                                 # freeHeap(e, sizeof(*e)): no more answers'''),
    dict(id="NF3-21 a retry returns true instead of its context", file=O, targets=T,
         old='''            return PL_retry_address(k)                      # ForeignRedoPtr(e)''',
         new='''            return FTRUE                                    # ForeignRedoPtr(e)'''),
    dict(id="NF3-22 FRG_CUTTED does not free the state", file=O, targets=T,
         old='''            free_foreign_state!(pool, k)                    # freeHeap(e, sizeof(*e)): FRG_CUTTED''',
         new='''            nothing                                         # freeHeap(e, sizeof(*e)): FRG_CUTTED'''),
    dict(id="NF3-E4 FRG_CUTTED leaves the buffer", file=O, targets=T,
         old='''            empty!(pool.states[k].buffer)                   # discardBuffer(&e->buffer)''',
         new='''            nothing                                         # discardBuffer(&e->buffer)''',
         equivalent="NF3-E4: the next first call empties the buffer it takes from the pool (initBuffer, src/pl-op.jl current_op_ndet)"),
    # ---- the wrappers and get_op_module
    dict(id="NF3-23 current_op/3 reads system, not user", file=O, targets=T,
         old='''    mp = MODULE_user(gd)                                    # MODULE_parse''',
         new='''    mp = MODULE_system(gd)                                  # MODULE_parse'''),
    dict(id="NF3-24 '$local_op'/3 reads system, not user", file=O, targets=T,
         old='''    m = MODULE_user(gd)                                     # Module m = MODULE_user''',
         new='''    m = MODULE_system(gd)                                   # Module m = MODULE_user'''),
    dict(id="NF3-25 current_op/3 does not inherit", file=O, targets=T,
         old='''    return current_op_ndet(ld, m, true, A1, A2, name, PL__ctx)        # inherit = true''',
         new='''    return current_op_ndet(ld, m, false, A1, A2, name, PL__ctx)       # inherit = true'''),
    dict(id="NF3-26 '$local_op'/3 inherits", file=O, targets=T,
         old='''    return current_op_ndet(ld, m, false, A1, A2, name, PL__ctx)       # inherit = false''',
         new='''    return current_op_ndet(ld, m, true, A1, A2, name, PL__ctx)        # inherit = false'''),
    dict(id="NF3-27 the qualifier is not stripped of its module", file=O, targets=T,
         old='''    if mname != 0''',
         new='''    if false'''),
    dict(id="NF3-28 a module that does not exist is system", file=O, targets=T,
         old='''        m = mm === nothing ? MODULE_user(gd) : mm           # else *m = MODULE_user''',
         new='''        m = mm === nothing ? MODULE_system(gd) : mm         # else *m = MODULE_user'''),
    dict(id="NF3-29 the name is not linked through the qualifier", file=O, targets=T,
         old='''    _slot_link_loc!(ld, name + 1, rc)                       # *valTermRef(name) = w''',
         new='''    nothing                                                 # *valTermRef(name) = w'''),
    dict(id="NF3-E5 the module of the qualifier is looked up even when it is the current one", file=O, targets=T,
         old='''        m.name == sym_key(msym) && return (true, m)         # if ( *m && (*m)->name == mname )''',
         new='''        nothing                                             # if ( *m && (*m)->name == mname )''',
         equivalent="NF3-E5: when the qualifier names m, isCurrentModule(gd.modules, msym) finds m itself (src/pl-modul.jl)"),
    # ---- the registration (the flags are read by the direct-query testsets)
    dict(id="NF3-30 current_op/3 is deterministic", file=O, targets=T,
         old='''        PL_FA_NONDETERMINISTIC | PL_FA_TRANSPARENT | PL_FA_ISO | PL_FA_VARARGS''',
         new='''        PL_FA_TRANSPARENT | PL_FA_ISO | PL_FA_VARARGS'''),
    dict(id="NF3-31 current_op/3 is not transparent", file=O, targets=T,
         old='''        PL_FA_NONDETERMINISTIC | PL_FA_TRANSPARENT | PL_FA_ISO | PL_FA_VARARGS''',
         new='''        PL_FA_NONDETERMINISTIC | PL_FA_ISO | PL_FA_VARARGS'''),
    dict(id="NF3-32 current_op/3 is not ISO", file=O, targets=T,
         old='''        PL_FA_NONDETERMINISTIC | PL_FA_TRANSPARENT | PL_FA_ISO | PL_FA_VARARGS''',
         new='''        PL_FA_NONDETERMINISTIC | PL_FA_TRANSPARENT | PL_FA_VARARGS'''),
    dict(id="NF3-33 '$local_op'/3 is ISO", file=O, targets=T,
         old='''        PL_FA_NONDETERMINISTIC | PL_FA_TRANSPARENT | PL_FA_VARARGS''',
         new='''        PL_FA_NONDETERMINISTIC | PL_FA_TRANSPARENT | PL_FA_ISO | PL_FA_VARARGS'''),
]
