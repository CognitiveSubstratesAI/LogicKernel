# ORIGINAL: FL1's mutant list — no swipl-devel counterpart.
# tools/mutants/FL1.py — the mutation battery of FL1 (audit D-0501, D-0547): the flag setters of pl-prologflag.c (setIncomparable,
# setFileNameCaseHandling(Name), setTheme) and pl-setup.c set_stack_limit, and the agc_margin, stack_limit and string_stack_tripwire
# branches of set_flag_value (src/os/pl-prologflag.jl). UNTESTED: written without compiling or running anything. Run ONCE, in CI
# (.github/workflows/mutation.yml; locally tools/mutate.sh run). Format: tools/mutate_drive.py's (as AUTOLOAD1.py): `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. Verdicts: written by the battery, not yet run.
# KILL: test/core_lang/test_flag_setters_swipl.jl (rows fs01-fs22 against the pin's swipl, and its LK-ONLY testsets: the local-data fields
# and the file-name case mask bits); test_set_flag_swipl.jl (t_sst: the second set of string_stack_tripwire reaches the setter) and
# test_push_flag_swipl.jl (the push of a flag reaches set_flag_value).
# NOT LISTED: setTheme's `!gd.bootsession` guard and its `a == f.a` early return: the effect of `$toplevel:theme_changed/1` is not observable
# from a row (it runs the Prolog hook of the toplevel, which the rows do not define), so a mutant there would survive as equivalent by
# construction; fs16 runs the call (a theme that changes) and fs15 the early return, as smoke rows.
FS = "test/core_lang/test_flag_setters_swipl.jl"
TF = [FS, "test/core_lang/test_set_flag_swipl.jl", "test/core_lang/test_push_flag_swipl.jl"]
TARGETS = TF + ["test/test_type_discipline.jl"]       # the baseline's targets (mutate_ci.py plan reads TARGETS)
P = "src/os/pl-prologflag.jl"
MUTANTS = [
    # ── pl-prologflag.c setIncomparable ──
    dict(id="FL1-a setIncomparable stores true for `arbitrary` too (KILL the LK-ONLY testset: the field after w_arb)",
         file=P, targets=TF,
         old="        ld.prolog_flag_incomparable_error = (k == sym_key(mk_sym(T, :error)))\n",
         new="        ld.prolog_flag_incomparable_error = true\n"),
    dict(id="FL1-b setIncomparable accepts any atom: no domain_error(incomparable, A) (KILL fs02)",
         file=P, targets=TF,
         old="    return PL_error(ld, ERR_DOMAIN, mk_sym(T, :incomparable), _flag_atom_ref(ld, a))\n",
         new="    return true\n"),
    dict(id="FL1-c set_flag_value does not call setIncomparable (KILL fs02 and the LK-ONLY testset)",
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
    # ── pl-setup.c set_stack_limit ──
    dict(id="FL1-g set_stack_limit stores the byte count as words (KILL fs08, fs11 and the LK-ONLY stacks_limit row)",
         file=P, targets=TF,
         old="    ld.stacks_limit = limit ÷ 8\n",
         new="    ld.stacks_limit = limit\n"),
    dict(id="FL1-h set_stack_limit never refuses a limit below the stacks in use (KILL fs10)",
         file=P, targets=TF,
         old="    if limit < 8 * ld.stacks_limit && limit < total()\n",
         new="    if limit < 8 * ld.stacks_limit && false\n"),
    dict(id="FL1-i set_stack_limit refuses only when the limit is ABOVE the current one (KILL fs10)",
         file=P, targets=TF,
         old="    if limit < 8 * ld.stacks_limit && limit < total()\n",
         new="    if limit > 8 * ld.stacks_limit && limit < total()\n"),
    # ── set_flag_value: agc_margin, stack_limit, string_stack_tripwire ──
    dict(id="FL1-j set_flag_value: agc_margin does not reach the atom table (KILL the LK-ONLY margin row)",
         file=P, targets=TF,
         old="            gd.atoms.margin = Int(i)\n",
         new="            nothing\n"),
    dict(id="FL1-n set_flag_value: agc_margin accepts a negative value (KILL fs06)",
         file=P, targets=TF,
         old="            if i < 0                                # ",
         new="            if false                                # "),
    dict(id="FL1-k set_flag_value: stack_limit accepts a negative value (KILL fs09)",
         file=P, targets=TF,
         old="        elseif name == \"stack_limit\"\n            if i < 0\n",
         new="        elseif name == \"stack_limit\"\n            if false\n"),
    dict(id="FL1-l set_flag_value: string_stack_tripwire has no range check (KILL fs20, fs21)",
         file=P, targets=TF,
         old="            if i < 0 || i > typemax(UInt32)\n",
         new="            if false\n"),
    dict(id="FL1-m set_flag_value: string_stack_tripwire is not stored (KILL the LK-ONLY row and test_set_flag_swipl.jl t_sst)",
         file=P, targets=TF,
         old="            ld.fli_string_buffers_tripwire = Int(i)\n",
         new="            nothing\n"),
    # ── pl-prologflag.c:1344 debug_on_interrupt (R2 DBG1; the signal half of enable_debug_on_interrupt is the signal step's) ──
    dict(id="FL1-r set_flag_value: debug_on_interrupt ignores enable_debug_on_interrupt's answer (KILL the LK-ONLY signals-off testset)",
         file=P, targets=TF,
         old="            rval = enable_debug_on_interrupt(ld, val)",
         new="            rval = (enable_debug_on_interrupt(ld, val); true)"),
    dict(id="FL1-s set_flag_value: debug_on_interrupt has no branch, the value only goes to the table (KILL the LK-ONLY signals-off testset)",
         file=P, targets=TF,
         old="        elseif name == \"debug_on_interrupt\"\n",
         new="        elseif name == \"debug_on_interrupt_\"\n"),
]
