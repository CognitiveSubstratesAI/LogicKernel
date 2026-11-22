# ORIGINAL: FL1's mutant list — no swipl-devel counterpart.
# tools/mutants/FL1.py — the mutation battery of FL1 (audit D-0501, D-0547), refit onto the Nov-22 source (wip/late-flag-2): the flag setters
# of pl-prologflag.c (setIncomparable, setFileNameCaseHandling(Name), setTheme) and their branches of set_flag_value
# (src/os/pl-prologflag.jl). The old list's agc_margin, stack_limit, string_stack_tripwire and debug_on_interrupt mutants (FL1-g .. FL1-s) are
# not here: those setters are not on this line. Run ONCE, in CI (.github/workflows/mutation.yml; locally tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as AUTOLOAD1.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Not run (edit-only step): re-check every `old` after `warm.sh fmt`. Verdicts: written by the battery.
# KILL: test/core_lang/test_flag_setters_swipl.jl (rows fs01-fs04, fs12-fs17 against the pin's swipl, the fs16 KNOWN DIFFERENCE testset, and its
# LK-ONLY testsets: the incomparable field, the boot-session theme, the file-name case mask bits).
# TARGETS (D-0238): every test file that reaches these branches: test_set_flag_swipl.jl and test_push_flag_swipl.jl (set_prolog_flag,
# push_prolog_flag reach set_flag_value), test_prolog_flag_swipl.jl (the flag table, the mask bits), test_lb7_swipl.jl (the early define
# `-Dfile_name_case_handling`), and the type-discipline test (the baseline's).
FS = "test/core_lang/test_flag_setters_swipl.jl"
TF = [
    FS, "test/core_lang/test_set_flag_swipl.jl", "test/core_lang/test_push_flag_swipl.jl",
    "test/core_lang/test_prolog_flag_swipl.jl", "test/core_lang/test_lb7_swipl.jl",
]
TARGETS = TF + ["test/test_type_discipline.jl"]       # the baseline's targets (mutate_ci.py plan reads TARGETS)
P = "src/os/pl-prologflag.jl"
MUTANTS = [
    # ── pl-prologflag.c setIncomparable ──
    dict(id="FL1-a setIncomparable stores true for `arbitrary` too (KILL the LK-ONLY incomparable testset: the field after w_arb)",
         file=P, targets=TF,
         old="        ld.prolog_flag_incomparable_error = (k == sym_key(mk_sym(T, :error)))\n",
         new="        ld.prolog_flag_incomparable_error = true\n"),
    dict(id="FL1-b setIncomparable accepts any atom: no domain_error(incomparable, A) (KILL fs02 and the direct call in the LK-ONLY testset)",
         file=P, targets=TF,
         old="    return PL_error(ld, ERR_DOMAIN, mk_sym(T, :incomparable), _flag_atom_ref(ld, a))\n",
         new="    return true\n"),
    dict(id="FL1-c set_flag_value does not call setIncomparable (KILL fs02 and the LK-ONLY incomparable testset)",
         file=P, targets=TF,
         old="            setIncomparable(ld, a) || return false\n",
         new="            nothing\n"),
    # ── pl-prologflag.c setFileNameCaseHandlingName / setFileNameCaseHandling ──
    dict(id="FL1-d setFileNameCaseHandlingName: case_preserving keeps the case bit (KILL the LK-ONLY mask testset)",
         file=P, targets=TF,
         old="        setPrologFlagMask!(ld, PLFLAG_FILE_CASE_PRESERVING)\n        clearPrologFlagMask!(ld, PLFLAG_FILE_CASE)\n    elseif",
         new="        setPrologFlagMask!(ld, PLFLAG_FILE_CASE_PRESERVING)\n    elseif"),
    dict(id="FL1-e setFileNameCaseHandlingName: an unknown name answers true (KILL the LK-ONLY mask testset)",
         file=P, targets=TF,
         old="    else\n        return false\n    end\n    return true\nend\n\n# PORT: pl-prologflag.c setFileNameCaseHandling\n",
         new="    else\n        return true\n    end\n    return true\nend\n\n# PORT: pl-prologflag.c setFileNameCaseHandling\n"),
    dict(id="FL1-f setFileNameCaseHandling answers true for an unknown name (KILL the LK-ONLY mask testset: the pending domain_error)",
         file=P, targets=TF,
         old="    if !setFileNameCaseHandlingName(ld, sym_text(a))\n",
         new="    if false\n"),
    dict(id="FL1-g setFileNameCaseHandlingName: case_insensitive leaves the preserving bit (KILL the LK-ONLY mask testset)",
         file=P, targets=TF,
         old="        clearPrologFlagMask!(ld, PLFLAG_FILE_CASE)\n        clearPrologFlagMask!(ld, PLFLAG_FILE_CASE_PRESERVING)\n    else",
         new="        clearPrologFlagMask!(ld, PLFLAG_FILE_CASE)\n    else"),
    dict(id="FL1-h set_flag_value does not call setFileNameCaseHandling",
         file=P, targets=TF,
         old="            setFileNameCaseHandling(ld, a) || return false\n",
         new="            nothing\n",
         equivalent="src/os/pl-prologflag.jl:1543 check_flag_write_access refuses every write to the read-only flag `file_name_case_handling` "
                    "(FT_ATOM | FF_READONLY, :2124) before set_flag_value runs, unless the caller passes FF_FORCE; no source file passes "
                    "FF_FORCE (grep over src/), and `-Dfile_name_case_handling` is dropped by the early-define path (src/pl-init.jl:188), so the "
                    "dispatch line is unreachable in the kernel; fs13 pins the permission_error that stands in its place."),
    # ── pl-prologflag.c setTheme ──
    dict(id="FL1-i setTheme: no early return for an unchanged value, the hook is called (KILL fs15: the existence error of $toplevel:theme_changed/1)",
         file=P, targets=TF,
         old="    sym_key(a) == sym_key(f.a) && return true\n",
         new="    false && return true\n"),
    dict(id="FL1-j setTheme: the hook is called inside the boot session too (KILL the LK-ONLY boot-session testset)",
         file=P, targets=TF,
         old="    if !gd.bootsession\n        pred = lookupProcedure(\n",
         new="    if true\n        pred = lookupProcedure(\n"),
    dict(id="FL1-k setTheme: a raising hook does not stop the store (KILL the fs16 KNOWN DIFFERENCE testset: `dark` stored after the failed set)",
         file=P, targets=TF,
         old="        rc || return false\n    end\n\n    return set_flag_atom(f, a)\n",
         new="        rc || nothing\n    end\n\n    return set_flag_atom(f, a)\n"),
    dict(id="FL1-l setTheme: the value is not stored (KILL the LK-ONLY boot-session testset: the flag after `dark`)",
         file=P, targets=TF,
         old="    return set_flag_atom(f, a)\n",
         new="    return true\n"),
    dict(id="FL1-m setTheme: the hook argument atom is not put (EQUIVALENT: the call raises either way)",
         file=P, targets=TF,
         old="            PL_put_atom(ld, av, a) &&\n",
         new="            true &&\n",
         equivalent="src/os/pl-prologflag.jl setTheme: `$toplevel:theme_changed/1` has no clauses in the kernel's database (boot/toplevel.pl is not "
                    "loaded), so the call raises the existence error whatever argument is put; the argument is observable only by the Prolog "
                    "hook, which no row defines (the old list's NOT LISTED note)."),
    dict(id="FL1-n set_flag_value: the theme branch does not reach setTheme (KILL fs16: the flag is stored without the hook call, so the kernel answers dark and not the existence error)",
         file=P, targets=TF,
         old="            return setTheme(gd, ld, f, a)",
         new="            nothing"),
]
