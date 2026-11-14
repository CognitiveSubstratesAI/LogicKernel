# UPSTREAM: swipl-devel src/os/pl-cstack.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of the pin's src/os/pl-cstack.c, the fallback block, read from the pin (git show 18168e62) for this file
#
# CSTACK (pl-cstack.c), lane F: C-stack backtraces (libbacktrace, libunwind, execinfo, dbghelp), the fatal-signal handler and the
# C-stack size of a thread. The kernel runs on no C stack it could unwind or measure, so what is ported is the pin's FALLBACK block
# (`#ifndef BTRACE_DONE`, pl-cstack.c lines 925-1001), the code an upstream build without a backtrace library runs:
#   - save_backtrace / btrace_destroy / print_c_backtrace / initBackTrace do nothing, as upstream's fallbacks do;
#   - print_backtrace / print_backtrace_named print "C-stack dumps are not supported on this platform" (upstream's own text), collected
#     on the local data's messages (`_qlf_Sdprintf!`) as the kernel's other `Sdprintf`s are, so the refusal is visible, never silent;
#   - sigCrashHandler (fatal-signal handler: `signal(sig, SIG_DFL)`, `kill(getpid(), sig)`) and CStackSize (`getrlimit(RLIMIT_STACK)`,
#     `pthread_getattr_np`) have no Julia equivalent: they raise a NotPortedError naming the reason (named refusal, step CSTACK1).
# c_backtrace_clear/0 and c_backtrace_print/1 are registered only under `O_DEBUG && BTRACE_DONE` (BTRACE_PREDS) and
# `BeginPredDefs(cbtrace)` is empty at the pin otherwise: a release build, which is what the oracle is, has neither predicate, so none
# is registered here and no `PL_predicates_from_cbtrace` exists.
# DIVERGES (file-wide): the message's `__FILE__:__LINE__` prefix is the pin's file and the line of the `Sdprintf` (os/pl-cstack.c:943 and :949);
# a C build prints its build-time path of the file, which the kernel has not.

"The fallback's message for `print_backtrace` (pl-cstack.c:943)."
# No upstream twin (a comment, not a header line): the text the fallback's `Sdprintf` formats (`"%s:%d C-stack dumps are not supported on this platform\n"`), the file and line
# being the pin's.
const _CSTACK_UNSUPPORTED_BACKTRACE = "os/pl-cstack.c:943 C-stack dumps are not supported on this platform\n"
"The fallback's message for `print_backtrace_named` (pl-cstack.c:949)."
const _CSTACK_UNSUPPORTED_BACKTRACE_NAMED = "os/pl-cstack.c:949 C-stack dumps are not supported on this platform\n"

# PORT: pl-cstack.c save_backtrace
# (the fallback: `return NULL`; a `btrace *` is `nothing`)
"A saved C backtrace of `why`: none, there is no C stack to unwind (the fallback returns NULL)."
function save_backtrace(why::String)::Nothing
    return nothing
end

# PORT: pl-cstack.c btrace_destroy
"Free a saved backtrace: the fallback's body is empty."
function btrace_destroy(bt::Nothing)::Nothing
    return nothing
end

# PORT: pl-cstack.c print_backtrace
"Print the last `last` saved backtraces: the fallback's message, collected on the local data."
function print_backtrace(ld::PL_local_data{T}, last::Int)::Nothing where {T}
    _qlf_Sdprintf!(ld, _CSTACK_UNSUPPORTED_BACKTRACE)
    return nothing
end

# PORT: pl-cstack.c print_backtrace_named
"Print the backtrace saved under `why`: the fallback's message, collected on the local data."
function print_backtrace_named(ld::PL_local_data{T}, why::String)::Nothing where {T}
    _qlf_Sdprintf!(ld, _CSTACK_UNSUPPORTED_BACKTRACE_NAMED)
    return nothing
end

# PORT: pl-cstack.c print_c_backtrace
"Save and print a C backtrace of `why`: the fallback's body is empty."
function print_c_backtrace(why::String)::Nothing
    return nothing
end

# PORT: pl-cstack.c initBackTrace
"Install the fatal-signal handlers: the fallback's body is empty."
function initBackTrace()::Nothing
    return nothing
end

# PORT: pl-cstack.c sigCrashHandler
# DIVERGES: the handler resets the signal, prints "received fatal signal", runs the exit hooks and re-raises with `kill(getpid(), sig)`;
# a Julia process has no such signal to deliver, so the call is a named refusal.
"The fatal-signal handler: refused by name, the kernel installs no signal handlers (pl-cstack.c)."
function sigCrashHandler(::Type{T}, sig::Int)::Nothing where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :sigCrashHandler),
            "the fatal-signal handler of os/pl-cstack.c (C signals, `kill(getpid(), sig)`, the C stack): no Julia equivalent",
            "CSTACK1"
        )
    )
end

# PORT: pl-cstack.c CStackSize
# DIVERGES: upstream reads the C stack's base and size (`getrlimit(RLIMIT_STACK)`, `pthread_getattr_np`) into a per-thread
# `c_stack_info`; the kernel has no C stack to measure, so the call is a named refusal.
"The C stack of this thread: refused by name, the kernel runs on no C stack it can measure (pl-cstack.c)."
function CStackSize(ld::PL_local_data{T})::Nothing where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :CStackSize),
            "the size and base of the C stack (`getrlimit(RLIMIT_STACK)`, `pthread_getattr_np`): no Julia equivalent",
            "CSTACK1"
        )
    )
end
