# Q10C2: a COPY of Q10C.py at 5324ea76aff5ff3abbdc2bd8548286da78036142 under a new ref name (audit D-0929 (5)); nothing else changed.
# ORIGINAL: Q10's mutant list — no swipl-devel counterpart.
# tools/mutants/Q10C.py — the mutation battery of Q10 (`\=@=/2` pl-variant.c, `shell/2` pl-sys.c over `System` pl-os.c and the shell-signalled
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
SU = "src/pl-setup.jl"
AL = "src/pl-alloc.jl"
W = "src/pl-write.jl"
F = "src/pl-fli.jl"
# the union of every mutant's `targets` (mutate_ci.py plan and the pre-push hook read TARGETS; audit D-0834 era, R2 gate)
TARGETS = [
    "test/core_lang/test_q10_swipl.jl",
    "test/core_lang/test_variant_cells.jl",
    "test/core_lang/test_halt_swipl.jl",
]
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
         old='    PL_extension("\\\\=@=", 2, pl_not_variant2_va, PL_FA_VARARGS)',
         new='    '),
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
    dict(id="Q10-13 the shell flag is ignored (KILL sh21; the flag is set to /bin/true, whose answer 0 differs from /bin/sh's 3)", file=O, targets=TQ,
         old='''    return a === nothing ? "/bin/sh" : sym_text(a)''',
         new='''    return "/bin/sh"'''),
    dict(id="Q10-14 the shell is not found (KILL sh01-sh20 that run: the spawn error is raised as a system_error)", file=O, targets=TQ,
         old='''    return a === nothing ? "/bin/sh" : sym_text(a)''',
         new='''    return a === nothing ? "/bin/nosuchsh" : "/bin/nosuchsh"'''),
    dict(id="Q10-15 thread_idle ignores a failed How (KILL ti04, ti05: no type_error)", file=AL, targets=TQ,
         old='''    how === nothing && return FFALSE
''',
         new='''    how === nothing && return FTRUE
'''),
    dict(id="Q10-16 thread_idle always succeeds (KILL ti06, ti13: a failing goal)", file=AL, targets=TQ,
         old='''    return rc ? FTRUE : FFALSE
end

# PORT: pl-alloc.c BeginPredDefs''',
         new='''    return FTRUE
end

# PORT: pl-alloc.c BeginPredDefs'''),
    dict(id="Q10-17 the ignored state is reported as throw (KILL os15, os28)", file=SU, targets=TQ,
         old='''PL_unify_atom(ld, old, mk_sym(T, :ignore)) || return FFALSE''',
         new='''PL_unify_atom(ld, old, mk_sym(T, :throw)) || return FFALSE'''),
    dict(id="Q10-18 an unchanged state fails (KILL os22, os23, os27)", file=SU, targets=TQ,
         old='''    rc == 0 && return FTRUE                             # no change''',
         new='''    rc == 0 && return FFALSE                            # no change'''),
    dict(id="Q10-19 debug records no handler token (KILL os16, os17)", file=SU, targets=TQ,
         old='''            sh.handler = SIGH_INTERRUPT
''',
         new='''            sh.handler = SIGH_NONE
'''),
    dict(id="Q10-20 throw is prepared without the throw flag (KILL os15, os16)", file=SU, targets=TQ,
         old='''sh = prepareSignal!(handlers, sign, PLSIG_THROW | PLSIG_SYNC)''',
         new='''sh = prepareSignal!(handlers, sign, PLSIG_SYNC)'''),
    dict(id="Q10-21 default keeps the state (KILL os18, os21, os27)", file=SU, targets=TQ,
         old='''        sh.flags = 0
        sh.handler = SIGH_NONE
''',
         new='''        sh.flags = sh.flags
        sh.handler = SIGH_NONE
'''),
    dict(id="Q10-22 the trail spare is set one too high (KILL ss27, ss28)", file=SU, targets=TQ,
         old='''            ld.trail_def_spare = v
''',
         new='''            ld.trail_def_spare = v + 1
'''),
    dict(id="Q10-23 low is not stored (KILL ss23, ss24)", file=SU, targets=TQ,
         old='''        stack.small = v
''',
         new='''        stack.small = stack.small
'''),
    dict(id="Q10-24 factor is not stored (KILL ss25, ss26)", file=SU, targets=TQ,
         old='''        stack.factor = v
''',
         new='''        stack.factor = stack.factor
'''),
    dict(id="Q10-25 the limit is reported in words (KILL ss17, ss18)", file=SU, targets=TQ,
         old='''limit = ld.stacks_limit * 8 ''',
         new='''limit = ld.stacks_limit * 1 '''),
    dict(id="Q10-26 the bad-property domain names another type (KILL ss21)", file=SU, targets=TQ,
         old='''mk_sym(T, :stack_parameter), prop)''',
         new='''mk_sym(T, :stack_parameters), prop)'''),
    dict(id="Q10-27 the unknown-stack error names another type (KILL ss19, ss20)", file=SU, targets=TQ,
         old='''PL_error(ld, ERR_EXISTENCE, mk_sym(T, :stack), name)''',
         new='''PL_error(ld, ERR_EXISTENCE, mk_sym(T, :stacks), name)'''),
    dict(id="Q10-28 the local stack's min_free is 256 (KILL ss04)", file=SU, targets=TQ,
         old='''        stack_params_t(0, 0, LOCAL_MARGIN, 0),''',
         new='''        stack_params_t(0, 0, 256, 0),'''),
    dict(id="Q10-29 SIGHUP has no handler record (KILL os01)", file=SU, targets=TQ,
         old='''    _signal_install!(handlers, 1, SIGH_HUP, PLSIG_SYNC)     # PL_signal(SIGHUP|PL_SIGSYNC, hupHandler)''',
         new='''    nothing'''),
    dict(id="Q10-30 pipe is thrown, not ignored (KILL os01)", file=SU, targets=TQ,
         old='''(13, PLSIG_IGNORE)''',
         new='''(13, PLSIG_THROW)'''),
    dict(id="Q10-31 the meta-argument error names another type (KILL os13)", file=SU, targets=TQ,
         old='''PL_error(ld, ERR_TYPE, mk_sym(T, :meta_argument), arg)''',
         new='''PL_error(ld, ERR_TYPE, mk_sym(T, :meta_arguments), arg)'''),
    dict(id="Q10-32 a signal name is not looked up (KILL os05, os06, os29)", file=SU, targets=TQ + ["test/core_lang/test_halt_swipl.jl"],
         old='''            sign = signal_index(sym_text(na))
''',
         new='''            sign = -1
'''),
    dict(id="Q10-33 trim_stacks does not trim (KILL th04: statistics(local) before and after trim_stacks after a deep recursion; D-0895 (2))", file=SU, targets=TQ,
         old='''    trimStacks!(ld, true)                               # trimStacks(true)
''',
         new='''    nothing
'''),
    dict(id="Q10-34 thread_idle is not transparent (KILL ti14; the goal is defined only in the context module q10_m)", file=AL, targets=TQ,
         old='''PL_extension("thread_idle", 2, pl_thread_idle2_va, PL_FA_TRANSPARENT | PL_FA_VARARGS)''',
         new='''PL_extension("thread_idle", 2, pl_thread_idle2_va, PL_FA_VARARGS)'''),
    dict(id="Q10-35 PutStringN writes the first byte only (KILL pt01)", file=W, targets=TQ,
         old='''function PutStringN(bytes::Vector{UInt8}, s::IOSTREAM)::Bool
    for b in bytes''',
         new='''function PutStringN(bytes::Vector{UInt8}, s::IOSTREAM)::Bool
    for b in bytes[1:min(end, 1)]'''),
    dict(id="Q10-36 PutTokenN never asks for a space (KILL pt02, pt03, pt15)", file=W, targets=TQ,
         old='''        rc = PutOpenToken(Int(bytes[1]), s, flags)
        rc == 0 && return 0
        PutStringN(bytes, s) || return 0''',
         new='''        rc = 1
        rc == 0 && return 0
        PutStringN(bytes, s) || return 0'''),
    dict(id="Q10-37 a wide text is not refused (KILL pt09)", file=W, targets=TQ,
         old='''    txt.encoding === ENC_WCHAR && return text_representation_error(ld, ENC_ISO_LATIN_1)''',
         new='''    nothing'''),
    dict(id="Q10-38 a string is no token text (KILL pt06)", file=W, targets=TQ,
         old='''    txt = PL_get_text(ld, A2, CVT_ATOM | CVT_STRING | CVT_EXCEPTION)
    txt === nothing && return false
    PL_canonicalise_text_ex(ld, txt) || return false''',
         new='''    txt = PL_get_text(ld, A2, CVT_ATOM | CVT_EXCEPTION)
    txt === nothing && return false
    PL_canonicalise_text_ex(ld, txt) || return false'''),
    dict(id="Q10-39 the stream is not looked up by alias (KILL pt24, pt25; a non-atom, non-stream gives stream_or_alias, pt13 and pt23 give an atom and never reach `not_a_stream`)", file=W, targets=TQ,
         old='''term_stream_handle(ld, A1, SH_ERRORS | SH_ALIAS)          # PL_get_stream_handle(A1, &out)''',
         new='''term_stream_handle(ld, A1, SH_ERRORS)                     # PL_get_stream_handle(A1, &out)'''),
    dict(id="Q10-40 the predicate is registered under another name (KILL pt01 and every pt row)", file=W, targets=TQ,
         old='''PL_extension("\\$put_token", 2, pl_put_token2_va, PL_FA_VARARGS)''',
         new='''PL_extension("\\$put_tokens", 2, pl_put_token2_va, PL_FA_VARARGS)'''),
    dict(id="Q10-41 the text is not canonicalised (KILL pt10, pt11)", file=W, targets=TQ,
         old='''    PL_canonicalise_text_ex(ld, txt) || return false
    txt.encoding === ENC_WCHAR''',
         new='''    txt.encoding === ENC_WCHAR'''),
    dict(id="Q10-42 the stream status of a written token is not read where the write itself succeeded (KILL pt27, pt28: an unbuffered stream on a full device, whose release flush fails)", file=W, targets=TQ,
         old='''        return streamStatus(ld, out)                                # PL_release_stream(out)
    end''',
         new='''        return true
    end'''),
    dict(id="Q10-43 the type of an atom is not unified (KILL cb07, cb08)", file=F, targets=TQ,
         old='''            return PL_unify_atom(ld, type, mk_sym(T, Symbol(name))) ? FTRUE : FFALSE
        end
        PL_is_variable(ld, a) || return FFALSE''',
         new='''            return FTRUE
        end
        PL_is_variable(ld, a) || return FFALSE'''),
    dict(id="Q10-44 a bound non-atom is enumerated over (KILL cb21, cb22; a bound non-blob with a type that is no atom fails, the mutant raises type_error(atom, 1), cb03-cb05 have an unbound type and give false either way)", file=F, targets=TQ,
         old='''        PL_is_variable(ld, a) || return FFALSE
        index = 1''',
         new='''        index = 1'''),
    dict(id="Q10-45 the given type does not filter (KILL cb15, cb11)", file=F, targets=TQ,
         old='''(!have_type || tname == btype.name)''',
         new='''true'''),
    dict(id="Q10-46 the enumeration is deterministic after its first answer (KILL cb13, cb14)", file=F, targets=TQ,
         old='''                        return PL_retry(index + 1)          # ForeignRedoInt(index+1)''',
         new='''                        return FTRUE'''),
    dict(id="Q10-47 current_blob/2 is registered deterministic (KILL cb13, cb14)", file=F, targets=TQ,
         old='''"current_blob", 2, pl_current_blob2_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS''',
         new='''"current_blob", 2, pl_current_blob2_va, PL_FA_VARARGS'''),
    dict(id="Q10-48 an unbound type is not unified with the type found (KILL cb17)", file=F, targets=TQ,
         old='''                            PL_unify_atom(ld, type, mk_sym(T, Symbol(btype.name))) ||
                                return FFALSE''',
         new='''                            nothing'''),
]
