# ORIGINAL: CSTACK's mutant list (lane F, os/pl-cstack.c) — no swipl-devel counterpart.
# tools/mutants/CSTACK.py — the mutation battery of src/os/pl-cstack.jl (the fallback block) and of the call the table's duplicate-add
# warning makes into it. Format: tools/mutate_drive.py's (as COVERAGE.py): `id`, `file`, `old` (EXACTLY once in its file), `new`, `targets`,
# optional `equivalent`. NOT RUN YET: written edit-only on wip/lane-f, nothing compiled; every `old` was counted exactly once with python3 -I.
# TARGETS (audit D-0238): the fallbacks are reached by test_cstack.jl and, through addNewHTable, by test_htable.jl (its message count).
TC = "test/core_lang/test_cstack.jl"
TH = "test/core_lang/test_htable.jl"
TARGETS = [TC, TH]
C = "src/os/pl-cstack.jl"
MUTANTS = [
    dict(id="CSTACK-1 print_backtrace_named prints nothing (KILL TC 'print_backtrace_named', TH 'addNewHTable warns')",
         file=C, targets=TARGETS,
         old='    _qlf_Sdprintf!(ld, _CSTACK_UNSUPPORTED_BACKTRACE_NAMED)\n',
         new='    nothing\n'),
    dict(id="CSTACK-2 print_backtrace prints nothing (KILL TC 'print_backtrace')",
         file=C, targets=TARGETS,
         old='    _qlf_Sdprintf!(ld, _CSTACK_UNSUPPORTED_BACKTRACE)\n',
         new='    nothing\n'),
    dict(id="CSTACK-3 print_backtrace prints the named variant's text (KILL TC 'pl-cstack.c:943')",
         file=C, targets=TARGETS,
         old='    _qlf_Sdprintf!(ld, _CSTACK_UNSUPPORTED_BACKTRACE)\n',
         new='    _qlf_Sdprintf!(ld, _CSTACK_UNSUPPORTED_BACKTRACE_NAMED)\n'),
    dict(id="CSTACK-4 the message names another reason (KILL TC, TH 'C-stack dumps are not supported')",
         file=C, targets=TARGETS,
         old='const _CSTACK_UNSUPPORTED_BACKTRACE_NAMED = "os/pl-cstack.c:949 C-stack dumps are not supported on this platform\\n"',
         new='const _CSTACK_UNSUPPORTED_BACKTRACE_NAMED = "os/pl-cstack.c:949 C-stack dumps are available\\n"'),
    dict(id="CSTACK-5 sigCrashHandler returns instead of refusing (KILL TC 'sigCrashHandler')",
         file=C, targets=TARGETS,
         old='function sigCrashHandler(::Type{T}, sig::Int)::Nothing where {T}\n    throw(\n',
         new='function sigCrashHandler(::Type{T}, sig::Int)::Nothing where {T}\n    sig > 0 && return nothing\n    throw(\n'),
    dict(id="CSTACK-6 CStackSize returns instead of refusing (KILL TC 'CStackSize')",
         file=C, targets=TARGETS,
         old='function CStackSize(ld::PL_local_data{T})::Nothing where {T}\n    throw(\n',
         new='function CStackSize(ld::PL_local_data{T})::Nothing where {T}\n    return nothing\n    throw(\n'),
    dict(id="CSTACK-7 the refusal's step is another (KILL TC 'e2.step')",
         file=C, targets=TARGETS,
         old='            mk_sym(T, :CStackSize),\n            "the size and base of the C stack (`getrlimit(RLIMIT_STACK)`, `pthread_getattr_np`): no Julia equivalent",\n            "CSTACK1"\n',
         new='            mk_sym(T, :CStackSize),\n            "the size and base of the C stack (`getrlimit(RLIMIT_STACK)`, `pthread_getattr_np`): no Julia equivalent",\n            "CSTACK2"\n'),
    dict(id="CSTACK-8 addNewHTable skips print_backtrace_named (KILL TH 'addNewHTable warns': the second message)",
         file="src/os/pl-table.jl", targets=TARGETS,
         old='        print_backtrace_named(ld, "addNewHTable")\n',
         new='        nothing\n'),
    dict(id="CSTACK-9 addNewHTable does not call save_backtrace (equivalent: the fallback has no effect)",
         file="src/os/pl-table.jl", targets=TARGETS,
         old='        save_backtrace("addNewHTable")\n',
         new='        nothing\n',
         equivalent="src/os/pl-cstack.jl save_backtrace: the fallback returns nothing and addNewHTable ignores the result (upstream does too), so dropping the call changes no state"),
]
