# ORIGINAL: Q10's second mutant list — no swipl-devel counterpart.
# tools/mutants/Q10B.py — the mutation battery of Q10, stack 2: `$suspend_findall_bag/0` (pl-bag.c:332-361 at the pin, findnsols/4,5),
# `garbage_collect_atoms/0` (pl-atom.c pl_garbage_collect_atoms, registered in pl-ext.c:170) and `prolog_alert_signal/2` (pl-setup.c:1274-1310).
# Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. NOT RUN YET (written edit-only, 2026-11-14, UNTESTED: nothing was compiled):
# the KILL named in each id is the row that is DESIGNED to fail. TB = test/core_lang/test_q10b_swipl.jl; a row is cited by its id
# (fb = findnsols/4,5 over `$suspend_findall_bag`, ga = garbage_collect_atoms/0, pa = prolog_alert_signal/2, tq = trie_property/2 rows).
# TARGETS (audit D-0238): TB is the only test that runs these three predicates by name on the kernel; the many other test files that mention
# findnsols carry it in the SWIPL-SIDE driver text (`catch(findnsols(N, G, G, Gs), ...)`, run by swipl, never by the kernel), and
# test_q10b_swipl.jl's own rows are the kernel's. test/db/test_boot_image_swipl.jl compares the kernel's procedure table with swipl's boot
# image (name, arity, flags, foreign or not), so it is named for every registration mutant (a missing, renamed or re-flagged entry
# changes `_BI_KERNEL_MISSING_FOREIGN` = 353 or the flags column). No kernel-side test other than these two reaches `_sig_alert`,
# `prolog_alert_signal` or `garbage_collect_atoms` (grep over test/ and src/, 2026-11-14).
# tq01-tq10 (trie_property/2 through the boot's own `$trie_property`) test boot code: no kernel line of this step is mutated for them.
# EQUIVALENT, with the two-sided reason, are marked in the entries (B8, A4).
TB = ["test/core_lang/test_q10b_swipl.jl"]
TBI = TB + ["test/db/test_boot_image_swipl.jl"]
BG = "src/pl-bag.jl"
FL = "src/pl-fli.jl"
EX = "src/pl-ext.jl"
SU = "src/pl-setup.jl"
# the union of every mutant's `targets` (mutate_ci.py plan and the pre-push hook read TARGETS; audit D-0834 era, R2 gate)
TARGETS = [
    "test/core_lang/test_q10b_swipl.jl",
    "test/db/test_boot_image_swipl.jl",
]
MUTANTS = [
    # ---- pl-bag.c: $suspend_findall_bag/0
    dict(id="Q10B-B1 the suspend does not reset the chunk's solution count (KILL fb01: the next chunk is cut at the wrong place)", file=BG, targets=TB,
         old='''        bag.solutions = 0
        bag.gsize = 0
        bag.suspended = true''',
         new='''        bag.gsize = 0
        bag.suspended = true'''),
    dict(id="Q10B-B2 the chunk's count replaces the suspended count (KILL fb02: the last chunks come out as one, [5,6,7] instead of [5,6] and [7])", file=BG, targets=TB,
         old='''        bag.suspended_solutions += bag.solutions''',
         new='''        bag.suspended_solutions = bag.solutions'''),
    dict(id="Q10B-B3 the bag is not put in suspended mode (KILL fb11: the inner goal's chunk lands in the suspended bag)", file=BG, targets=TB,
         old='''        bag.gsize = 0
        bag.suspended = true''',
         new='''        bag.gsize = 0'''),
    dict(id="Q10B-B4 the foreign state is the top bag, not the current one (KILL fb08: the bag below a suspended inner one is resumed wrongly)", file=BG, targets=TB,
         old='''        while at > 0 && ld.bags[at].suspended
            at -= 1                                     # bag = bag->parent
        end
        @assert at > 0''',
         new='''        @assert at > 0'''),
    dict(id="Q10B-B5 the redo does not resume the bag (KILL fb01: the bag stays suspended, current_bag skips it and the next chunk is lost)", file=BG, targets=TB,
         old='''        bag = ld.bags[at]
        bag.suspended = false

        return FFALSE''',
         new='''        bag = ld.bags[at]

        return FFALSE'''),
    dict(id="Q10B-B6 the redo succeeds (KILL fb01: the chunk is delivered again instead of backtracking into the goal)", file=BG, targets=TB,
         old='''        bag.suspended = false

        return FFALSE''',
         new='''        bag.suspended = false

        return FTRUE'''),
    dict(id="Q10B-B7 the cut does not resume the bag (KILL fb06, fb09, fb10: `$destroy_findall_bag` asserts on a suspended bag)", file=BG, targets=TB,
         old='''        bag.suspended = false

        return FTRUE
    end

    @assert false''',
         new='''
        return FTRUE
    end

    @assert false'''),
    dict(id="Q10B-B8 the cut answers false (equivalent)", file=BG, targets=TB,
         old='''        return FTRUE
    end

    @assert false''',
         new='''        return FFALSE
    end

    @assert false''',
         equivalent="src/pl-bag.jl:204 (`return FTRUE`, the FRG_CUTTED arm) mirrors pl-bag.c:357 at the pin (`return true`), but the value is never read: "
                    "src/pl-wam.jl:1382,1384 call the foreign function in discardForeignFrame and drop its result (the function returns `Nothing`), "
                    "as pl-wam.c:666,668 at the pin do (`(*(FuncN)function)(0, argc, &context);` and `CALL_FCUTTED(argc, function, &context);`, "
                    "discardForeignFrame is `static void`)"),
    dict(id="Q10B-B9 `$suspend_findall_bag` is registered deterministic (KILL fb01: no redo, the goal is not backtracked into; boot image flags column)", file=BG, targets=TBI,
         old='''        PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    )
)''',
         new='''        PL_FA_VARARGS
    )
)'''),
    dict(id="Q10B-B10 `$suspend_findall_bag` is registered under another name (KILL fb01: findnsols/4 calls an undefined procedure; boot image)", file=BG, targets=TBI,
         old='''        "\\$suspend_findall_bag",
        0,''',
         new='''        "\\$suspend_findall_bag2",
        0,'''),
    # ---- pl-atom.c: garbage_collect_atoms/0
    dict(id="Q10B-G1 garbage_collect_atoms/0 fails (KILL ga01-ga05, ga07: the call answers false)", file=FL, targets=TB,
         old='''function pl_garbage_collect_atoms0(ld::PL_local_data{T})::foreign_t where {T}
    return FTRUE''',
         new='''function pl_garbage_collect_atoms0(ld::PL_local_data{T})::foreign_t where {T}
    return FFALSE'''),
    dict(id="Q10B-G2 garbage_collect_atoms/0 is not registered (KILL ga01: the procedure is undefined; boot image)", file=EX, targets=TBI,
         old='''    PL_extension("garbage_collect_atoms", 0, pl_garbage_collect_atoms0, 0x00),     # Q10 (pl-ext.c:170)
''',
         new=''''''),
    # ---- pl-setup.c: prolog_alert_signal/2
    dict(id="Q10B-A1 `_sig_alert` finds no alert signal (KILL pa01: the old signal reads 0, not usr2)", file=SU, targets=TB,
         old='''        if (sh.flags & PLSIG_PREPARED) != 0 && sh.handler == SIGH_ALERT
            return sig''',
         new='''        if (sh.flags & PLSIG_PREPARED) != 0 && sh.handler == SIGH_ALERT
            return 0'''),
    dict(id="Q10B-A3 an unnamed alert signal is unified as an atom (KILL pa11, pa19: the old signal is `unknown`, swipl's is the number)", file=SU, targets=TB,
         old='''        PL_unify_integer(ld, A1, sig_alert) || return FFALSE''',
         new='''        PL_unify_atom(ld, A1, mk_sym(T, :unknown)) || return FFALSE'''),
    dict(id="Q10B-A4 the equal-signal shortcut is dropped (equivalent)", file=SU, targets=TB,
         old='''    PL_compare(ld, A1, A2) == 0 && return FTRUE

''',
         new='''
''',
         equivalent="src/pl-setup.jl:905 mirrors pl-setup.c:1285-1286 at the pin (`PL_compare(A1,A2) == CMP_EQUAL` returns true). A1 now holds the old alert "
                    "signal, so an equal A2 names the signal that is installed: without the shortcut the code takes `new` = that signal (src/pl-setup.jl:907-912), "
                    "`unprepareSignal!` clears the record (src/pl-setup.jl:404-415) and `_signal_install!(handlers, new, SIGH_ALERT, PLSIG_NOFRAME)` "
                    "(src/pl-setup.jl:918, 422-431) writes back the SAME record (handler SIGH_ALERT, flags PLSIG_NOFRAME|PREPARED, predicate nothing, saved_handler "
                    "SIGH_NONE: what initSignals! installs at src/pl-setup.jl:456); for 0 (no alert signal) both unprepare and install are skipped. "
                    "C side: pl-setup.c:1291-1305 is the same sequence (unprepareSignal then PL_signal), so the only difference there is the OS handler "
                    "reinstalled, which the kernel does not have (src/pl-setup.jl:376-380)"),
    dict(id="Q10B-A4b an equal signal is not accepted at once (KILL pa02: the signal is set to a different one)", file=SU, targets=TB,
         old='''    PL_compare(ld, A1, A2) == 0 && return FTRUE''',
         new='''    PL_compare(ld, A1, A2) != 0 && return FTRUE'''),
    dict(id="Q10B-A5 the 0 test is inverted (KILL pa02, pa03: a signal number is read as a name, 0 as a signal)", file=SU, targets=TB,
         old='''    if !(new !== nothing && new == 0)                   # PL_get_integer(A2, &new) && new == 0''',
         new='''    if (new !== nothing && new == 0)                   # PL_get_integer(A2, &new) && new == 0'''),
    dict(id="Q10B-A6 a failed signal name does not fail the call (KILL pa04: the type error / failure of an unknown name is lost)", file=SU, targets=TB,
         old='''        new === nothing && return FFALSE
''',
         new=''''''),
    dict(id="Q10B-A7 the old alert signal is not unprepared (KILL pa03, pa11, pa19: the old record stays prepared, usr1 scans before usr2)", file=SU, targets=TB,
         old='''        unprepareSignal!(handlers, sig_alert)           # GD->signals.sig_alert = 0''',
         new='''        nothing                                         # GD->signals.sig_alert = 0'''),
    dict(id="Q10B-A8 a non-zero new signal is not installed, 0 is (KILL pa02: the alert signal does not move)", file=SU, targets=TB,
         old='''    if new != 0
        _signal_install!''',
         new='''    if new == 0
        _signal_install!'''),
    dict(id="Q10B-A9 the new alert signal is installed on the old one (KILL pa02: usr1 is not the alert signal afterwards)", file=SU, targets=TB,
         old='''        _signal_install!(handlers, new, SIGH_ALERT, PLSIG_NOFRAME)
    end

    return FTRUE''',
         new='''        _signal_install!(handlers, sig_alert, SIGH_ALERT, PLSIG_NOFRAME)
    end

    return FTRUE'''),
    dict(id="Q10B-A10 prolog_alert_signal/2 is registered under another name (KILL pa01: the procedure is undefined; boot image)", file=SU, targets=TBI,
         old='''    PL_extension("prolog_alert_signal", 2, pl_prolog_alert_signal2_va, PL_FA_VARARGS)''',
         new='''    PL_extension("prolog_alert_signal2", 2, pl_prolog_alert_signal2_va, PL_FA_VARARGS)'''),
    dict(id="Q10B-A11 a named alert signal is unified as its number (KILL pa01: usr2 expected, 12 found)", file=SU, targets=TB,
         old='''        PL_unify_atom(ld, A1, mk_sym(T, Symbol(sname))) || return FFALSE''',
         new='''        PL_unify_integer(ld, A1, sig_alert) || return FFALSE'''),
]
