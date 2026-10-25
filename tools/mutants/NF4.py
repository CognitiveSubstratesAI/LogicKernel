# ORIGINAL: NF4's mutant list — no swipl-devel counterpart.
# tools/mutants/NF4.py — the mutation battery of NF4 (the non-deterministic `a1, a2, …` convention: I_FCALLNDET0..10,
# `_fcall_ndet`, discardForeignFrame's CALL_FCUTTED; repeat/0 its first user, audit D-0149 item 3), run ONCE, in CI. The
# format is tools/mutate_drive.py's. NOT LISTED, carried by name into NF4b's list (D-0141's pattern): "the a1 FRG_CUTTED call
# is skipped" — repeat/0 does nothing at FRG_CUTTED, so only a built-in that frees state there (sub_atom/5, NF4b) can tell.
TARGETS = ["test/core_lang/test_repeat_swipl.jl"]
T = TARGETS
W = "src/pl-wam.jl"
P = "src/pl-prims.jl"
E = "src/pl-ext.jl"
S = "src/pl-supervisor.jl"
MUTANTS = [
    dict(id="NF4-1 repeat/0 retries with another integer", file=P, targets=T,
         old='''        return PL_retry(2)                          # ForeignRedoInt(2L)''',
         new='''        return PL_retry(3)                          # ForeignRedoInt(2L)'''),
    dict(id="NF4-2 repeat/0 succeeds once, deterministically", file=P, targets=T,
         old='''    if c == FRG_FIRST_CALL || c == FRG_REDO''',
         new='''    if c == FRG_REDO'''),
    dict(id="NF4-3 repeat/0 stops at its first redo", file=P, targets=T,
         old='''    if c == FRG_FIRST_CALL || c == FRG_REDO''',
         new='''    if c == FRG_FIRST_CALL'''),
    dict(id="NF4-4 the a1 call does not step past its operand", file=W, targets=T,
         old='''    @label fcall_ndetn
    fn_i = Int(PCc[PC])
    PC += 1''',
         new='''    @label fcall_ndetn
    fn_i = Int(PCc[PC])''',
         equivalent="NF4-E1: the step is dead, as upstream's `*PC++` (pl-vmi.c FCALL_NDETN): the one path on is "
                    "helper_I_FEXITNDET, whose @LOAD_REGISTERS(QID) (src/pl-wam.jl:4215) reloads the PC foreign_redo's "
                    "@SAVE_REGISTERS(QID) saved (src/pl-wam.jl:4153) before PC is read (PC += 3; pl-vmi.c:4609-4610)"),
    dict(id="NF4-5 I_FREDO decodes REDO_INT without the shift", file=W, targets=T,
         old='''        fd_ctx.context = reinterpret(UInt, reinterpret(Int, fd_wcl) >> FRG_REDO_BITS)''',
         new='''        fd_ctx.context = fd_wcl'''),
    dict(id="NF4-6 discardForeignFrame decodes REDO_INT without the shift", file=W, targets=T,
         old='''        context.context = wcl >> FRG_REDO_BITS      # (uintptr_t)(wcl >> FRG_REDO_BITS): `word`, unsigned''',
         new='''        context.context = wcl                       # (uintptr_t)(wcl >> FRG_REDO_BITS): `word`, unsigned'''),
    dict(id="NF4-7 discardForeignFrame calls an a1 built-in through the VA tree", file=W, targets=T,
         old='''        _fcall_ndet(func, ld, 0, context)           # CALL_FCUTTED(argc, function, &context)''',
         new='''        _fcall_va(func, ld, 0, argc, context)       # CALL_FCUTTED(argc, function, &context)'''),
    dict(id="NF4-8 the supervisor of an a1 NDET built-in calls the VA instruction", file=S, targets=T,
         old='''                I_FOPENNDET, I_FCALLNDET0 + code(def.arity), code(f), I_FEXITNDET, I_FREDO''',
         new='''                I_FOPENNDET, I_FCALLNDETVA, code(f), I_FEXITNDET, I_FREDO'''),
    dict(id="NF4-9 no FRG entry is non-deterministic to the trees", file=E, targets=T,
         old='''_frg_ndet(k::Int)::Bool = (_FOREIGN_DET[k].flags & PL_FA_NONDETERMINISTIC) != 0''',
         new='''_frg_ndet(k::Int)::Bool = false'''),
    dict(id="NF4-10 repeat/0 is registered deterministic", file=E, targets=T,
         old='''    PL_extension("repeat", 0, pl_repeat, PL_FA_NONDETERMINISTIC | PL_FA_ISO),''',
         new='''    PL_extension("repeat", 0, pl_repeat, PL_FA_ISO),'''),
]
