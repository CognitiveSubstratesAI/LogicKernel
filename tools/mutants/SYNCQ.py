# ORIGINAL: SYNC-Q's mutant list — no swipl-devel counterpart.
# tools/mutants/SYNCQ.py — the mutation battery of SYNC-Q (the pl-setup.c slice of the sync to swipl-devel cf6960c2), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. Only the behaviour change of the slice has a mutant: `trim_stack`
# (pl-setup.c:1758-1761) gives NO spare back to a stack with no room (the pin gave the whole spare back). The mutants put the pin's
# rule back, or take the room itself (a negative reduce). Every test file that reaches `trim_stack!`, `trim_stack_global!` or
# `trim_stack_trail!` (directly, or through `growStacks!`/`growStacks_trim!`/`trimStacks!` after a stack overflow) is a target.
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does not
# occur exactly once); the python count is `src.count(old) == 1`.
TARGETS = [
    "test/core_lang/test_local_stack.jl",
    "test/core_lang/test_stack_limit.jl",
    "test/core_lang/test_resource_error.jl",
    "test/core_lang/test_stack_overflow_swipl.jl",
]
T = TARGETS
P = "src/pl-setup.jl"
MUTANTS = [
    dict(id="SQ-1 local trim_stack: no room gives the whole spare back (the pin's rule)", file=P, targets=T,
         old='''        room = ld.lMax - ld.lTop                # roomStackP(s)
        if room < reduce
            reduce = room > 0 ? room : 0
        end''',
         new='''        room = ld.lMax - ld.lTop                # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end'''),
    dict(id="SQ-2 global trim_stack: no room gives the whole spare back (the pin's rule)", file=P, targets=T,
         old='''        reduce = ld.global_def_spare - ld.global_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room < reduce
            reduce = room > 0 ? room : 0
        end''',
         new='''        reduce = ld.global_def_spare - ld.global_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end'''),
    dict(id="SQ-3 trail trim_stack: no room gives the whole spare back (the pin's rule)", file=P, targets=T,
         old='''        reduce = ld.trail_def_spare - ld.trail_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room < reduce
            reduce = room > 0 ? room : 0
        end''',
         new='''        reduce = ld.trail_def_spare - ld.trail_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room > 0 && room < reduce
            reduce = room
        end'''),
    dict(id="SQ-4 global trim_stack: past the limit the spare takes the negative room", file=P, targets=T,
         old='''        reduce = ld.global_def_spare - ld.global_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room < reduce
            reduce = room > 0 ? room : 0
        end''',
         new='''        reduce = ld.global_def_spare - ld.global_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room < reduce
            reduce = room
        end'''),
    dict(id="SQ-5 trail trim_stack: past the limit the spare takes the negative room", file=P, targets=T,
         old='''        reduce = ld.trail_def_spare - ld.trail_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room < reduce
            reduce = room > 0 ? room : 0
        end''',
         new='''        reduce = ld.trail_def_spare - ld.trail_spare
        room = ld.stacks_limit - _stacks_in_use(ld, 0)      # roomStackP(s)
        if room < reduce
            reduce = room
        end'''),
]
