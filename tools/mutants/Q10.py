# ORIGINAL: Q10's mutant list — no swipl-devel counterpart.
# tools/mutants/Q10.py — the mutation battery of Q10 (`\=@=/2` pl-variant.c, `shell/2` pl-sys.c over `System` pl-os.c and the shell-signalled
# error of pl-error.c, `current_blob/2`, `$put_token/2`, `$on_signal/4`, `$set_prolog_stack/4`, `trim_heap/0`, `trim_stacks/0`, `thread_idle/2`).
# Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. NOT RUN YET (written edit-only, 2026-11-11, UNTESTED: nothing was compiled):
# the KILL named in each id is the row that is DESIGNED to fail. TQ = test/core_lang/test_q10_swipl.jl; a row is cited by its id
# (vr = `\=@=`, sh = shell/2, bl = current_blob/2, pt = `$put_token/2`, os = `$on_signal/4`, sp = `$set_prolog_stack/4`, tr = trim_heap/0 and
# trim_stacks/0, ti = thread_idle/2).
# TARGETS (audit D-0238): TQ is the only test file that runs these predicates by name; test_variant_cells.jl runs `=@=` on cells (the same
# `is_variant_ptr_cells` the `\=@=` mutants reach), so it is named for the variant mutants.
# EQUIVALENT, with the reason, are marked in the entries.
TQ = ["test/core_lang/test_q10_swipl.jl"]
TVC = TQ + ["test/core_lang/test_variant_cells.jl"]
V = "src/pl-variant.jl"
S = "src/pl-sys.jl"
O = "src/os/pl-os.jl"
E = "src/pl-error.jl"
MUTANTS = [
    # ---- pl-variant.c: \=@=
    dict(id="Q10-1 `\\=@=` succeeds for variants (KILL vr01, vr03, vr07: the answer flips)", file=V, targets=TVC,
         old='''    if is_variant_ptr_cells(ld, -(A1 + 1), -(A2 + 1))       # valTermRef (L1d 8a)
        return FFALSE
    end''',
         new='''    if is_variant_ptr_cells(ld, -(A1 + 1), -(A2 + 1))       # valTermRef (L1d 8a)
        return FTRUE
    end'''),
    dict(id="Q10-2 `\\=@=` compares the first argument with itself (KILL vr02: a \\=@= b answers no)", file=V, targets=TVC,
         old='''    if is_variant_ptr_cells(ld, -(A1 + 1), -(A2 + 1))       # valTermRef (L1d 8a)
        return FFALSE''',
         new='''    if is_variant_ptr_cells(ld, -(A1 + 1), -(A1 + 1))       # valTermRef (L1d 8a)
        return FFALSE'''),
    dict(id="Q10-3 `\\=@=` is not registered (KILL vr01-vr20: the procedure is undefined)", file=V, targets=TQ,
         old='''    PL_extension("\\\\=@=", 2, pl_not_variant2_va, PL_FA_VARARGS),''',
         new='''    '''),
    dict(id="Q10-4 `\\=@=` ignores a raised exception (equivalent)", file=V, targets=TQ,
         old='''    return PL_exception(ld, 0) == 0 ? FTRUE : FFALSE        # false: is_variant_ptr() raised''',
         new='''    return FTRUE''',
         equivalent="the kernel's is_variant_ptr_cells raises nothing (Julia arrays: no ERR_NOMEM), so no exception is pending when it answers false"),
    # ---- pl-sys.c / pl-os.c: shell/2
    dict(id="Q10-5 shell/2 is not registered (KILL sh01-sh20: the procedure is undefined)", file=S, targets=TQ,
         old='''    PL_extension("shell", 2, pl_shell2_va, PL_FA_VARARGS),''',
         new='''    '''),
    dict(id="Q10-6 the status is not unified (KILL sh01, sh02: R stays unbound)", file=S, targets=TQ,
         old='''    return PL_unify_integer(ld, A2, rval) ? FTRUE : FFALSE
end

# PORT: pl-sys.c BeginPredDefs as PL_predicates_from_system''',
         new='''    return FTRUE
end

# PORT: pl-sys.c BeginPredDefs as PL_predicates_from_system'''),
    dict(id="Q10-7 an exception pending after System is no failure (KILL sh11: the raised error is lost or the call answers)", file=S, targets=TQ,
         old='''    PL_exception(ld, 0) != 0 && return FFALSE                   # it could not run the command''',
         new='''    '''),
    dict(id="Q10-8 the child's environment has no PROLOGCHILD (KILL sh10: test exits 1)", file=O, targets=TQ,
         old='''"PROLOGCHILD" => "yes")''',
         new='''"PROLOGCHILD" => "no")'''),
    dict(id="Q10-9 the shell is run without -c (KILL sh02: `sh 'exit 3'` runs a file that is not there, status 127)", file=O, targets=TQ,
         old='''Cmd(String[shell, "-c", cmd])''',
         new='''Cmd(String[shell, "-e", cmd])'''),
    dict(id="Q10-10 a child killed by a signal answers its exit code (KILL sh11: the error is not raised)", file=O, targets=TQ,
         old='''    if p.termsignal == 0                                        # WIFEXITED(status)''',
         new='''    if true                                                     # WIFEXITED(status)'''),
    dict(id="Q10-11 the signalled error names the wrong signal (KILL sh11: signal(10) for 9)", file=O, targets=TQ,
         old='''    PL_shell_signalled_error(ld, cmd, Int(p.termsignal))        # WIFSIGNALED(status)''',
         new='''    PL_shell_signalled_error(ld, cmd, Int(p.termsignal) + 1)    # WIFSIGNALED(status)'''),
    dict(id="Q10-12 the signalled error carries no command (KILL sh11: shell(signal(9), '') )", file=E, targets=TQ,
         old='''ld, formal, _err_functor(ld, :shell, 2), s, _err_atom(ld, mk_sym(T, Symbol(cmd)))''',
         new='''ld, formal, _err_functor(ld, :shell, 2), s, _err_atom(ld, mk_sym(T, Symbol("")))'''),
    dict(id="Q10-13 the shell flag is ignored (KILL none of the rows: equivalent while the flag holds /bin/sh)", file=O, targets=TQ,
         old='''    return a === nothing ? "/bin/sh" : sym_text(a)''',
         new='''    return "/bin/sh"''',
         equivalent="`posix_shell` is /bin/sh at its default and no row sets it (setting it would run an arbitrary program for every shell/2 row)"),
    dict(id="Q10-14 the shell is not found (KILL sh01-sh20 that run: the spawn error is raised as a system_error)", file=O, targets=TQ,
         old='''    return a === nothing ? "/bin/sh" : sym_text(a)''',
         new='''    return a === nothing ? "/bin/nosuchsh" : "/bin/nosuchsh"'''),
]
