# ORIGINAL: FIRSTBOOT's mutant list — the first boot's two causes: setArgvPrologFlag's foreign frame (pl-prologflag.c:2857-2876) and
# checkPrologFlagsAccess (pl-prologflag.c:2968-3010, called by PL_cleanup, pl-init.c:1928).
# tools/mutants/FIRSTBOOT.py — the mutation battery of FIRSTBOOT. Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as TOP1.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Verdicts: written by the battery, not yet run. Every `old` was counted EXACTLY once in its file at the commit that adds this list; RE-FIT any
# `old` that `tools/warm.sh fmt` rewraps.
# KILL: test/core_lang/test_firstboot_swipl.jl — the oracle rows (swipl 10.1.19: exit status, `-g` output, the halt warning) and the white-box
# row (lTop/gTop across apply_options_to_flags!).
# TARGETS (audit D-0238): `_set_argv_prolog_flag!` is reached through apply_options_to_flags! by test_lb7_swipl.jl (the options rows) and by the
# new file; `checkPrologFlagsAccess` is reached through PL_cleanup by every halt: test_halt_swipl.jl and test_top1_pro.jl (halt through the
# `gd.halt_exit` seam) as well as the new file. The three listed older files hold @testset and @test.
FB = "test/core_lang/test_firstboot_swipl.jl"
LB7 = "test/core_lang/test_lb7_swipl.jl"
HALT = "test/core_lang/test_halt_swipl.jl"
TOP1 = "test/core_lang/test_top1_pro.jl"
TARGETS = [FB, LB7, HALT, TOP1]
PF = "src/os/pl-prologflag.jl"
PI = "src/pl-init.jl"
MUTANTS = [
    # ── setArgvPrologFlag (pl-prologflag.c:2857-2876) ──
    dict(id="FIRSTBOOT-A1 _set_argv_prolog_flag! does not discard its foreign frame (KILL test_firstboot_swipl.jl: lTop/gTop row and the -g rows)",
         file=PF, targets=[FB, LB7],
         old="setPrologFlag(gd, ld, flag, FT_TERM, t)\n    PL_discard_foreign_frame(ld, fid)",
         new="setPrologFlag(gd, ld, flag, FT_TERM, t)\n    fid"),
    dict(id="FIRSTBOOT-A2 the os_argv flag is not set (KILL test_firstboot_swipl.jl: the os_argv row)",
         file=PI, targets=[FB, LB7],
         old='_set_argv_prolog_flag!(gd, ld, "os_argv", cmd.os_argv)',
         new="nothing"),
    dict(id="FIRSTBOOT-A3 the argv flag is not set (KILL test_firstboot_swipl.jl: the argv row)",
         file=PI, targets=[FB, LB7],
         old='_set_argv_prolog_flag!(gd, ld, "argv", cmd.appl_argv)',
         new="nothing"),
    dict(id="FIRSTBOOT-A4 the argv list is built in reverse (KILL test_firstboot_swipl.jl: the argv and os_argv rows)",
         file=PF, targets=[FB, LB7],
         old="for i in length(argv):-1:1",
         new="for i in 1:length(argv)"),
    # ── checkPrologFlagsAccess (pl-prologflag.c:2968-3010) and its call in PL_cleanup (pl-init.c:1928) ──
    dict(id="FIRSTBOOT-C1 PL_cleanup does not call checkPrologFlagsAccess (KILL test_firstboot_swipl.jl: the -D row)",
         file=PI, targets=TARGETS,
         old="    checkPrologFlagsAccess(gd, ld)\n",
         new=""),
    dict(id="FIRSTBOOT-C2 a flag that was read is still reported (KILL test_firstboot_swipl.jl: the -D foo=bar -g current_prolog_flag row)",
         file=PF, targets=TARGETS,
         old="            if (f.flags & FF_WARN_NOT_ACCESSED) != 0 && (f.flags & FF_ACCESSED) == 0\n",
         new="            if (f.flags & FF_WARN_NOT_ACCESSED) != 0\n"),
    dict(id="FIRSTBOOT-C3 every unread flag is reported, not only those made with warn_not_accessed (KILL test_firstboot_swipl.jl: the plain rows)",
         file=PF, targets=TARGETS,
         old="            if (f.flags & FF_WARN_NOT_ACCESSED) != 0 && (f.flags & FF_ACCESSED) == 0\n",
         new="            if (f.flags & FF_ACCESSED) == 0\n"),
    dict(id="FIRSTBOOT-C4 the warning is printed even with no name found (KILL test_firstboot_swipl.jl: the plain rows)",
         file=PF, targets=TARGETS,
         old="if !isempty(names)",
         new="if true"),
    dict(id="FIRSTBOOT-C5 the message term is not_accessed_flag, not not_accessed_flags (KILL test_firstboot_swipl.jl: the -D row)",
         file=PF, targets=TARGETS,
         old="_message_term(ld, :not_accessed_flags, list)",
         new="_message_term(ld, :not_accessed_flag, list)"),
    dict(id="FIRSTBOOT-C6 the warning is an informational message (KILL test_firstboot_swipl.jl: the -D row)",
         file=PF, targets=TARGETS,
         old="                ld, :warning, _message_term(ld, :not_accessed_flags, list)",
         new="                ld, :informational, _message_term(ld, :not_accessed_flags, list)"),
]
