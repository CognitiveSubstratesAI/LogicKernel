# ORIGINAL: FL1-FLAGS's mutant list — no swipl-devel counterpart.
# tools/mutants/FL1F.py — the mutation battery of FL1-FLAGS (R2; the 24 flag rows of NOOWNER, audit D-0501): the flag DEFINITIONS of pl-prologflag.c
# (agc_margin, stack_limit, incomparable, theme, file_name_case_handling, open_shared_object, the platform flags) and `ci_get_flag` of pl-index.c.
# UNTESTED: written without compiling or running anything. Run ONCE, in CI (.github/workflows/mutation.yml; locally tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as FL1.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# KILL: test/core_lang/test_fl1_flags_swipl.jl (rows a1-a4: the defaults, the read-only access, the absent platform flags, the kernel's pinned
# difference for open_shared_object, the float32 widening of ci_max_var_fraction). TARGETS: every test file that reads one of these flags (D-0238).
# NOT LISTED: `ci_max_var_fraction` in `initClauseIndexing!` (the setPrologFlag line): whether current_prolog_flag/2 reads the table or `ci_get_flag`
# for a ci_* flag is unverified, so a mutant there could be equivalent; the ci_get_flag mutant below is the one with a stated kill.
T = [
    "test/core_lang/test_fl1_flags_swipl.jl",
    "test/core_lang/test_flag_setters_swipl.jl",
    "test/core_lang/test_set_flag_swipl.jl",
    "test/core_lang/test_prolog_flag_swipl.jl",
    "test/core_lang/test_stack_limit.jl",
    "test/core_lang/test_lb7_swipl.jl",
    "test/core_lang/test_resource_error.jl",
    "test/core_lang/test_stack_overflow_swipl.jl",
    "test/db/test_boot_clauses_swipl.jl",
    "test/db/test_boot_image_swipl.jl",
]
TARGETS = T + ["test/test_type_discipline.jl"]       # the baseline's targets (mutate_ci.py plan reads TARGETS)
P = "src/os/pl-prologflag.jl"
ANCHOR = '    setPrologFlag(gd, "theme", FT_ATOM | FF_SHARED, "default")\n'
def add(flag, line):
    return dict(id=f"FL1F-{flag} the flag `{flag}` is defined (KILL a2: swipl's build has none)",
                file=P, targets=T, old=ANCHOR, new=ANCHOR + "    " + line + "\n")
BOOL = lambda f: f'setPrologFlag(gd, "{f}", FT_BOOL | FF_READONLY, true, 0)'
MUTANTS = [
    dict(id="FL1F-a agc_margin default 10000 -> 1 (KILL a1)", file=P, targets=T,
         old='    setPrologFlag(gd, "agc_margin", FT_INTEGER, 10000)\n',
         new='    setPrologFlag(gd, "agc_margin", FT_INTEGER, 1)\n'),
    dict(id="FL1F-b stack_limit default STACK_LIMIT_DEFAULT * 8 -> * 4 (KILL a1)", file=P, targets=T,
         old='    setPrologFlag(gd, "stack_limit", FT_INTEGER, STACK_LIMIT_DEFAULT * 8)\n',
         new='    setPrologFlag(gd, "stack_limit", FT_INTEGER, STACK_LIMIT_DEFAULT * 4)\n'),
    dict(id="FL1F-c incomparable default arbitrary -> error (KILL a1)", file=P, targets=T,
         old='    setPrologFlag(gd, "incomparable", FT_ATOM, "arbitrary")\n',
         new='    setPrologFlag(gd, "incomparable", FT_ATOM, "error")\n'),
    dict(id="FL1F-d theme default `default` -> `dark` (KILL a1)", file=P, targets=T,
         old=ANCHOR, new='    setPrologFlag(gd, "theme", FT_ATOM | FF_SHARED, "dark")\n'),
    dict(id="FL1F-e file_name_case_handling loses FF_READONLY (KILL a1: the permission_error)", file=P, targets=T,
         old='        "file_name_case_handling",\n        FT_ATOM | FF_READONLY,\n',
         new='        "file_name_case_handling",\n        FT_ATOM,\n'),
    add("apple", BOOL("apple")),
    add("apple_universal_binary", BOOL("apple_universal_binary")),
    add("bundle", BOOL("bundle")),
    add("emscripten", BOOL("emscripten")),
    add("prolog_debug", BOOL("prolog_debug")),
    add("windows", BOOL("windows")),
    add("xpce", BOOL("xpce")),
    add("shared_home", 'setPrologFlag(gd, "shared_home", FT_ATOM | FF_READONLY, "/usr/share/swipl")'),
    dict(id="FL1F-o open_shared_object is defined (KILL a3: the kernel's pinned difference, D-0151 item 6)", file=P, targets=T,
         old='    setPrologFlag(gd, "shared_object_extension", FT_ATOM | FF_READONLY, SO_EXT)\n',
         new='    setPrologFlag(gd, "shared_object_extension", FT_ATOM | FF_READONLY, SO_EXT)\n'
             '    setPrologFlag(gd, "open_shared_object", FT_BOOL | FF_READONLY, true, 0)\n'),
    dict(id="FL1F-p ci_get_flag: ci_max_var_fraction reads 0.1, not the float32 widening (KILL a4)",
         file="src/os/pl-prologflag.jl", targets=T,
         old='    name == "ci_max_var_fraction" && return PL_unify_float(ld, t, Float64(MAX_VAR_FRAC))\n',
         new='    name == "ci_max_var_fraction" && return PL_unify_float(ld, t, 0.1)\n'),
]
