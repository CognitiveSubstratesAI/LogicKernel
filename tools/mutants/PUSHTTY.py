# ORIGINAL: PUSHTTY's mutant list — PushTty/PopTty (pl-os.c:2294-2346, :2354-2379 at the pin); no swipl-devel counterpart for a Julia-IO stream.
# tools/mutants/PUSHTTY.py — run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# C29 (reconcile of the old COMB1 line and wip/rec-flags): the 8 mutants of the old line, every `old` counted once against wip/rec-flags 0c7326e2 (python3 -I),
# plus PUSHTTY-9 and PUSHTTY-10 for the tty_control arm of set_flag_value, killed by the new testset `tty_control true sets the mask bit` in
# test/core_lang/test_set_flag_swipl.jl. NOT RUN: the kills are read off the rows.
# TARGETS (D-0238): PushTty/PopTty are called by set_flag_value's tty_control arm and by the testsets of test_set_flag_swipl.jl; test_top1b_swipl.jl reads
# Sttymode/Sset_ttymode, which these call, and is listed for the mode bit; test_r2_status.jl reads the flag refusal table (tty_control is off it since REC-FLAGS).
T = ["test/core_lang/test_set_flag_swipl.jl", "test/core_lang/test_top1b_swipl.jl", "test/test_r2_status.jl"]
PF = "src/os/pl-prologflag.jl"
OS = "src/os/pl-os.jl"
TARGETS = T                                                 # the baseline job's list: the union of every mutant's targets
MUTANTS = [
    dict(id="PUSHTTY-1 a stream that is no terminal is treated as one", file=OS, targets=T,
         old='''    (s.flags & SIO_ISATTY) == 0 && return true                  # not a terminal''',
         new='''    (s.flags & SIO_ISATTY) != 0 && return true                  # not a terminal'''),
    dict(id="PUSHTTY-2 tty_control false does not leave PushTty", file=OS, targets=T,
         old='''    truePrologFlag(ld, PLFLAG_TTY_CONTROL) || return true       # tty_control is false''',
         new='''    truePrologFlag(ld, PLFLAG_TTY_CONTROL) && return true       # tty_control is false'''),
    dict(id="PUSHTTY-3 the mode is not recorded before the terminal is refused", file=OS, targets=T,
         old='''    Sset_ttymode(s, mode)

    throw(
        NotPortedError{T}(
            mk_sym(T, :PushTty),''',
         new='''    throw(
        NotPortedError{T}(
            mk_sym(T, :PushTty),'''),
    dict(id="PUSHTTY-4 the stream's mode is not saved in the buffer", file=OS, targets=T,
         old='''    buf.mode = Sttymode(s)
    buf.state = nothing''',
         new='''    buf.mode = TTY_COOKED
    buf.state = nothing'''),
    dict(id="PUSHTTY-5 PushTty's refusal names the wrong owner step", file=OS, targets=T,
         old='''            "PushTty of a terminal: tcgetattr, cfmakeraw, tcsetattr (pl-os.c:2294-2346)",
            "TOP1b"''',
         new='''            "PushTty of a terminal: tcgetattr, cfmakeraw, tcsetattr (pl-os.c:2294-2346)",
            "LB7"'''),
    dict(id="PUSHTTY-6 PopTty does not restore the stream's mode", file=OS, targets=T,
         old='''    Sset_ttymode(s, buf.mode)

    buf.state === nothing && return true''',
         new='''    buf.state === nothing && return true'''),
    dict(id="PUSHTTY-7 PopTty ignores a saved state", file=OS, targets=T,
         old='''    buf.state === nothing && return true''',
         new='''    buf.state !== nothing && return true'''),
    dict(id="PUSHTTY-8 PopTty's refusal names the wrong pin lines", file=OS, targets=T,
         old='''"PopTty of a saved terminal state: tcsetattr (pl-os.c:2354-2379)",''',
         new='''"PopTty of a saved terminal state: tcsetattr (pl-os.c:2354-2380)",'''),
    dict(id="PUSHTTY-9 tty_control true does not set the mask bit before PushTty", file=PF, targets=T,
         old='''                        setPrologFlagMask!(ld, PLFLAG_TTY_CONTROL)
                        PushTty(ld, sin, ttytab, TTY_SAVE)''',
         new='''                        PushTty(ld, sin, ttytab, TTY_SAVE)'''),
    dict(id="PUSHTTY-10 the arm sets the mask for the false value and leaves it off for true", file=PF, targets=T,
         old='''                    elseif val
                        setPrologFlagMask!(ld, PLFLAG_TTY_CONTROL)''',
         new='''                    elseif !val
                        setPrologFlagMask!(ld, PLFLAG_TTY_CONTROL)'''),
]
