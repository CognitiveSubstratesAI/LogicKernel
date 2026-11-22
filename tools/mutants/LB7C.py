# ORIGINAL: LB7C's mutant list — the `--dump-runtime-variables` / `-c` arms of PL_initialise_tail! (pl-init.c:1672-1680).
# tools/mutants/LB7C.py — the mutation battery of LB7C. Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as FIRSTBOOT.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Verdicts: written by the battery, not yet run (UNTESTED, nothing compiled). Every `old` was counted EXACTLY once in its file when this list was written.
# KILL: test/core_lang/test_firstboot_swipl.jl — the testset of `--dump-runtime-variables` and `-c` (swipl pin 18168e62 rows).
# TARGETS (audit D-0238): PL_initialise_tail! is reached by every `PL_initialise!` run: test_firstboot_swipl.jl and test_lb7_swipl.jl (white-box
# rows that call the options part only; listed because the tail shares the file).
FB = "test/core_lang/test_firstboot_swipl.jl"
LB7 = "test/core_lang/test_lb7_swipl.jl"
TARGETS = [FB, LB7]
PI = "src/pl-init.jl"
MUTANTS = [
    dict(id="LB7C-1 the --dump-runtime-variables arm does not run $config (KILL test_firstboot_swipl.jl: the variable names)",
         file=PI, targets=TARGETS,
         old='status = query_loop(gd, ld, mk_sym(T, Symbol("\\$config")), false) == 1 ? 0 : 1',
         new="status = 0"),
    dict(id="LB7C-2 the $config arm inverts its status (KILL test_firstboot_swipl.jl: the exit status of --dump-runtime-variables)",
         file=PI, targets=TARGETS,
         old='Symbol("\\$config")), false) == 1 ? 0 : 1',
         new='Symbol("\\$config")), false) == 1 ? 1 : 0'),
    dict(id="LB7C-3 the -c arm does not run $compile (KILL test_firstboot_swipl.jl: the nonexistent-file row)",
         file=PI, targets=TARGETS,
         old='status = query_loop(gd, ld, mk_sym(T, Symbol("\\$compile")), false) == 1 ? 0 : 1',
         new="status = 0"),
    dict(id="LB7C-4 the -c arm runs $config (KILL test_firstboot_swipl.jl: the -c rows print nothing on the pin)",
         file=PI, targets=TARGETS,
         old='Symbol("\\$compile")), false) == 1 ? 0 : 1',
         new='Symbol("\\$config")), false) == 1 ? 0 : 1'),
    dict(id="LB7C-5 the -c arm does not halt (KILL test_firstboot_swipl.jl: the exit status is read from the halt seam)",
         file=PI, targets=TARGETS,
         old='''        PL_halt(gd, ld, status)
        return false
    end
    return''',
         new='''        status
        return false
    end
    return'''),
    dict(id="LB7C-6 the $config arm answers true after its halt (equivalent: the test harness reads the status from gd.halt_exited and tests `isempty(gd.halt_exited)` before it runs anything else)",
         file=PI, targets=TARGETS,
         old='''        PL_halt(gd, ld, status)
        return false                                               # fail; (the halt seam returned)''',
         new='''        PL_halt(gd, ld, status)
        return true                                                # fail; (the halt seam returned)''',
         equivalent="PL_initialise_tail!'s caller (test_firstboot_swipl.jl `_fb_run`) takes `ok && isempty(gd.halt_exited)` and the seam recorded the halt, so an answer of true or false after a halt takes the same path (src/pl-init.jl PL_initialise_tail!)"),
]
