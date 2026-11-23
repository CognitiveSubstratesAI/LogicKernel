# ORIGINAL: STATEXT's mutant list — the refusals by name of pl-load.c `$activate_static_extension/1` and pl-apple.c
# `apple_current_locale_identifier/1`; no swipl-devel counterpart (the pin's Linux swipl answers existence_error).
# tools/mutants/STATEXT.py — run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# TARGETS (D-0238): the platform test file reaches both predicates; test/foreign/test_builtins_swipl.jl reads the registration
# tables (`_FOREIGN_VA`). UNTESTED when written: nothing compiled.
T = ["test/core_lang/test_platform_refusals_swipl.jl", "test/foreign/test_builtins_swipl.jl"]
LOAD = "src/pl-load.jl"
APPLE = "src/os/pl-apple.jl"
TARGETS = T                                                 # the baseline job's list: the union of every mutant's targets
MUTANTS = [
    # STATEXT-1 .. STATEXT-4 are RETIRED WITH THE CODE (integration merge, INT-FIX-25): they mutated the NotPortedError refusal stub of
    # src/pl-load.jl `$activate_static_extension/1` (STATEXT-1 the stub fails instead of refusing; -2 it names another predicate; -3 its
    # pin lines "(pl-load.c:450-540)" altered; -4 its owner step "LB5-LB7" altered). The stub is gone: the merged function is pl-load.c's
    # real `activate_static_extension` over the static_extensions table (json, pcre, zlib), and an unknown name raises
    # `existence_error(foreign_extension, Name)` through PL_error. Kill meaning and where it went: the refusal's behaviour (an unknown
    # name is an error, of that type, naming that extension) is pinned by test_platform_refusals_swipl.jl p01 (the existence_error row);
    # STATEXT-3 and -4 mutated message strings that no longer exist and have no successor. No new row is written here (rows only).
    dict(id="STATEXT-5 `$activate_static_extension` is registered with arity 2", file=LOAD, targets=T,
         old='''        "\\$activate_static_extension", 1, pl_activate_static_extension1_va,''',
         new='''        "\\$activate_static_extension", 2, pl_activate_static_extension1_va,'''),
    dict(id="STATEXT-6 apple_current_locale_identifier/1 fails instead of refusing", file=APPLE, targets=T,
         old='''    throw(
        NotPortedError{T}(
            mk_sym(T, :apple_current_locale_identifier),
            "apple_current_locale_identifier/1: macOS only, CoreFoundation (pl-apple.c:56-79)",
            "APPLE1"
        )
    )''',
         new='''    return FFALSE'''),
    dict(id="STATEXT-7 the refusal of apple_current_locale_identifier/1 names another predicate", file=APPLE, targets=T,
         old='''            mk_sym(T, :apple_current_locale_identifier),''',
         new='''            mk_sym(T, :apple_current_locale_identifier_),'''),
    dict(id="STATEXT-8 the apple refusal's pin lines are altered", file=APPLE, targets=T,
         old='''CoreFoundation (pl-apple.c:56-79)",''',
         new='''CoreFoundation (pl-apple.c:56-80)",'''),
    dict(id="STATEXT-9 the apple refusal's owner step is altered", file=APPLE, targets=T,
         old='''            "APPLE1"''',
         new='''            "LB5"'''),
    dict(id="STATEXT-10 apple_current_locale_identifier is registered with arity 2", file=APPLE, targets=T,
         old='''        "apple_current_locale_identifier", 1, pl_apple_current_locale_identifier1_va,''',
         new='''        "apple_current_locale_identifier", 2, pl_apple_current_locale_identifier1_va,'''),
]
