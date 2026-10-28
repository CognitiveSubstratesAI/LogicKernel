# ORIGINAL: Y1's mutant list — no swipl-devel counterpart.
# tools/mutants/Y1.py — the mutation battery of Y1 (getenv/2, setenv/2, unsetenv/1, get_time/1, sleep/1 of pl-sys.c;
# statistics/2 of pl-prims.c; delete_file/1 of pl-files.c; the OS layer of pl-os.c; the errno-driven codes of pl-error.c;
# design: evidence/r2/design/flags_rest.md, step Y1, audit D-0149), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `equivalent` and `targets`. One mutant per decision that decides an answer of test_sys_swipl.jl's rows.
# EQUIVALENT, with the reason: Y1-8 (`yield()` is not observable: sleep(0) is true either way) and Y1-11 (the negative guard
# of Pause is unreachable: sleep/1 answers a negative time itself).
# NOT listed here: the `ld.statistics.inferences += 1` sites of src/pl-wam.jl (depart_or_retry_continue, the CHP_JUMP
# backtrack, b_throw_unwind, b_throw_resume, call_internal_det_foreign): the run loop takes that edit separately; its
# mutants are the report's (lk-y1-report.md) and join this list when it lands.
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that
# does not occur exactly once).
TARGETS = ["test/core_lang/test_sys_swipl.jl"]
T = TARGETS
S = "src/pl-sys.jl"
O = "src/os/pl-os.jl"
F = "src/os/pl-files.jl"
P = "src/pl-prims.jl"
E = "src/pl-error.jl"
L = "src/pl-fli.jl"
H = "src/pl-thread.jl"
MUTANTS = [
    # ---- pl-sys.c (src/pl-sys.jl)
    dict(id="Y1-1 getenv/2 of an unset variable succeeds", file=S, targets=T,
         old='''    v = getenv3(n)
    v === nothing && return FFALSE''',
         new='''    v = getenv3(n)
    v === nothing && return FTRUE'''),
    dict(id="Y1-2 getenv/2 does not unify the value", file=S, targets=T,
         old='''    return PL_unify_atom(ld, A2, mk_sym(T, Symbol(v))) ? FTRUE : FFALSE''',
         new='''    return FTRUE'''),
    dict(id="Y1-3 setenv/2 sets nothing", file=S, targets=T,
         old='''    return Setenv(ld, n, v) ? FTRUE : FFALSE''',
         new='''    return FTRUE'''),
    dict(id="Y1-4 unsetenv/1 deletes nothing", file=S, targets=T,
         old='''    return Unsetenv(ld, n) ? FTRUE : FFALSE''',
         new='''    return FTRUE'''),
    dict(id="Y1-5 a C string is not cut at its NUL", file=S, targets=T,
         old='''    return i === nothing ? s : s[1:prevind(s, i)]''',
         new='''    return s'''),
    dict(id="Y1-6 get_time/1 unifies a constant", file=S, targets=T,
         old='''    return PL_unify_float(ld, A1, WallTime()) ? FTRUE : FFALSE''',
         new='''    return PL_unify_float(ld, A1, 1.0) ? FTRUE : FFALSE'''),
    dict(id="Y1-7 sleep/1 of a negative time fails", file=S, targets=T,
         old='''    t < 0.0 && return FTRUE''',
         new='''    t < 0.0 && return FFALSE'''),
    dict(id="Y1-8 sleep/1 of 0.0 does not yield", file=S, targets=T,
         old='''        yield()''',
         new='''        nothing''',
         equivalent="yield() only lets other tasks run; sleep(0) answers true with or without it, and no row observes the "
                    "scheduler (src/pl-sys.jl pl_sleep1_va)"),
    dict(id="Y1-9 getenv/2 is registered as setenv/2's function", file=S, targets=T,
         old='''    PL_extension("getenv", 2, pl_getenv2_va, PL_FA_VARARGS),''',
         new='''    PL_extension("getenv", 2, pl_setenv2_va, PL_FA_VARARGS),'''),
    # ---- pl-os.c (src/os/pl-os.jl)
    dict(id="Y1-10 Pause does not wait", file=O, targets=T,
         old='''    sleep(min(t, 1.0e15))''',
         new='''    nothing'''),
    dict(id="Y1-11 Pause of a negative time is not answered", file=O, targets=T,
         old='''    t < 0.0 && return true''',
         new='''    nothing''',
         equivalent="sleep/1 answers a negative time itself, before Pause (src/pl-sys.jl pl_sleep1_va: `t < 0.0 && return "
                    "FTRUE`), so Pause never receives one"),
    dict(id="Y1-12 Pause waits for a time nanosleep cannot represent", file=O, targets=T,
         old='''    t < 9.223372036854775807e18 || return true''',
         new='''    nothing'''),
    dict(id="Y1-13 setenv does not overwrite", file=O, targets=T,
         old='''(Cstring, Cstring, Cint), name, value, 1)''',
         new='''(Cstring, Cstring, Cint), name, value, 0)'''),
    dict(id="Y1-14 a failed setenv is not reported", file=O, targets=T,
         old='''    if rc != 0''',
         new='''    if false'''),
    dict(id="Y1-15 a failed unsetenv is not reported", file=O, targets=T,
         old='''    if rc < 0''',
         new='''    if false'''),
    dict(id="Y1-16 WallTime reads the CPU clock", file=O, targets=T,
         old='''    t = _clock_gettime(CLOCK_REALTIME)''',
         new='''    t = _clock_gettime(CLOCK_PROCESS_CPUTIME_ID)'''),
    dict(id="Y1-17 CpuTime reads the wall clock", file=O, targets=T,
         old='''_clock_gettime(CLOCK_PROCESS_CPUTIME_ID)''',
         new='''_clock_gettime(CLOCK_REALTIME)'''),
    dict(id="Y1-18 ThreadCPUTime reads the wall clock", file=H, targets=T,
         old='''_clock_gettime(CLOCK_THREAD_CPUTIME_ID)''',
         new='''_clock_gettime(CLOCK_REALTIME)'''),
    dict(id="Y1-19 the system time of a thread is its user time", file=H, targets=T,
         old='''    which == CPU_SYSTEM && return 0.0''',
         new='''    nothing'''),
    # ---- statistics/2 (src/pl-prims.jl)
    dict(id="Y1-20 statistics(cputime) is not refreshed", file=P, targets=T,
         old='''            st.user_cputime = ThreadCPUTime(CPU_USER)''',
         new='''            nothing'''),
    dict(id="Y1-21 statistics(process_cputime) is not refreshed", file=P, targets=T,
         old='''        k === :process_cputime && (st.process_cputime = CpuTime(CPU_USER))''',
         new='''        nothing'''),
    dict(id="Y1-22 statistics(system_time) is not refreshed", file=P, targets=T,
         old='''            st.system_cputime = ThreadCPUTime(CPU_SYSTEM)''',
         new='''            nothing''',
         equivalent="a thread's system time is 0.0 (ThreadCPUTime(CPU_SYSTEM), src/pl-thread.jl) and the field starts at 0.0, so "
                    "the refresh stores what is there"),
    dict(id="Y1-23 the last runtime is not remembered", file=P, targets=T,
         old='''        st.last_cputime = v[1]''',
         new='''        nothing'''),
    dict(id="Y1-24 the last real time is not remembered", file=P, targets=T,
         old='''        st.last_real_time = v[1]''',
         new='''        nothing'''),
    dict(id="Y1-25 the last wall time is not remembered", file=P, targets=T,
         old='''        st.last_walltime = wt''',
         new='''        nothing'''),
    dict(id="Y1-26 the first walltime is not counted from the start", file=P, targets=T,
         old='''        st.last_walltime == 0.0 && (st.last_walltime = st.start_time)''',
         new='''        nothing'''),
    dict(id="Y1-27 the inference count is 0", file=P, targets=T,
         old='''        v.i = st.inferences''',
         new='''        v.i = 0'''),
    dict(id="Y1-28 epoch is an integer", file=P, targets=T,
         old='''    elseif key === :epoch || key === :process_epoch
        v.type = V_FLOAT''',
         new='''    elseif key === :epoch || key === :process_epoch
        v.type = V_INTEGER'''),
    dict(id="Y1-29 stack_limit is in positions", file=P, targets=T,
         old='''        v.i = 8 * ld.stacks_limit''',
         new='''        v.i = ld.stacks_limit'''),
    dict(id="Y1-30 the statistics_key domain error names no predicate", file=P, targets=T,
         old='''PL_error(ld, "statistics", 2, "", ERR_DOMAIN''',
         new='''PL_error(ld, "", 0, "", ERR_DOMAIN'''),
    dict(id="Y1-31 a longer list than the values is accepted", file=P, targets=T,
         old='''            p += 1
        end
        return PL_unify_nil(ld, tail)''',
         new='''            p += 1
        end
        return true'''),
    # ---- delete_file/1 (src/os/pl-files.jl)
    dict(id="Y1-32 a file name with a NUL is not refused", file=F, targets=T,
         old='''    if 0x00 in codeunits(name)''',
         new='''    if false'''),
    dict(id="Y1-33 a name of PATH_MAX is not refused", file=F, targets=T,
         old='''    if ncodeunits(name) >= PATH_MAX''',
         new='''    if false'''),
    dict(id="Y1-34 RemoveFile reports permission denied", file=F, targets=T,
         old='''    return rc == 0 ? 0 : Int(Base.Libc.errno())''',
         new='''    return rc == 0 ? 0 : EACCES'''),
    dict(id="Y1-35 RemoveFile removes nothing", file=F, targets=T,
         old='''    rc = ccall((:remove, LIBC), Cint, (Cstring,), path)''',
         new='''    rc = Cint(0)'''),
    # ---- the errno-driven codes (src/pl-error.jl)
    dict(id="Y1-36 ENOTEMPTY is no permission error", file=E, targets=T,
         old='''errno == ENOTEMPTY''',
         new='''errno == -1'''),
    dict(id="Y1-37 the context holds the sentinel, not strerror(errno)", file=E, targets=T,
         old='''    msg == MSG_ERRNO ? Base.Libc.strerror(errno) : msg''',
         new='''    msg'''),
    dict(id="Y1-38 a system call error is no system_error", file=E, targets=T,
         old='''PL_put_atom(ld, formal, mk_sym(T, :system_error))''',
         new='''PL_put_atom(ld, formal, mk_sym(T, :io_error))'''),
    # ---- the FLI readers and writers (src/pl-fli.jl)
    dict(id="Y1-39 a non-number raises no type error", file=L, targets=T,
         old='''    ex && PL_type_error(ld, "float", t)''',
         new='''    nothing'''),
    dict(id="Y1-40 PL_unify_float binds 0.0", file=L, targets=T,
         old='''PL_unify_atomic(ld, t, mk_gnd(T, f))''',
         new='''PL_unify_atomic(ld, t, mk_gnd(T, 0.0))'''),
]
