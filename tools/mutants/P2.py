# ORIGINAL: P2's mutant list — no swipl-devel counterpart.
# tools/mutants/P2.py — the mutation battery of P2 (pl-prims.c atomic_list_concat/2,3, atomics_to_string/2,3, split_atom,
# pl_sub_atom/sub_atom/5 over T2's sub_text), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh
# run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. Killed by test/core_lang/test_p2_swipl.jl (rows p01-p70 named in each id's KILL).
# Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in its file at the P2 branch head (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * the separator-empty test of the split label (`sep == 0 || st.length == 0`): with the test gone `split_atom` runs
#     with a zero-length separator and never advances (`i += sep_len`), a HANG, not a verdict; the `domain_error` below
#     it is mutated instead (P2-A8).
#   * `split_atom`'s `at === nothing && return false` and the canonicalise guard: a text the term interface cannot
#     read raises through CVT_EXCEPTION before the guard is reached (the same error as swipl's p39 pin).
# TARGETS (audit D-0238): the only test file that runs atomic_list_concat/2,3, atomics_to_string/2,3 or sub_atom/5 on
# the kernel is test_p2_swipl.jl; the other files that name them (test_read_swipl.jl, test_arith_swipl.jl,
# test_unify_swipl.jl, test_string_swipl.jl, test_body_code_swipl.jl, test_analyse_variables_swipl.jl,
# test_canonical_readatom_swipl.jl, test_read_term_swipl.jl, test_open_close_swipl.jl, code_testlib.jl) call them only
# in the swipl-side driver text, which the kernel does not run.
T = ["test/core_lang/test_p2_swipl.jl"]
TARGETS = T                                    # the baseline's (mutate_ci.py plan reads TARGETS)
P = "src/pl-prims.jl"
S = "src/pl-string.jl"
MUTANTS = [
    # ── pl-prims.c split_atom, atomic_list_concat ──
    dict(id="P2-A1 split_atom steps one character after a separator, not the separator's length (KILL p08, p31, p32)",
         file=P, targets=T,
         old="            i += sep_len\n",
         new="            i += 1\n"),
    dict(id="P2-A2 split_atom's loop stops one position early: a separator at the very end is not seen (KILL p08)",
         file=P, targets=T,
         old="while i <= at.length - sep_len",
         new="while i < at.length - sep_len"),
    dict(id="P2-A3 split_atom's last piece is one character, not the rest (KILL p06, p09)",
         file=P, targets=T,
         old="PL_unify_text_range(ld, head, at, last, at.length - last, PL_ATOM)",
         new="PL_unify_text_range(ld, head, at, last, 1, PL_ATOM)"),
    dict(id="P2-A4 split_atom takes a match where the text differs (KILL p06, p07)", file=P, targets=T,
         old="PL_cmp_text(st, 0, at, i, sep_len) == 0",
         new="PL_cmp_text(st, 0, at, i, sep_len) != 0"),
    dict(id="P2-A5 the join puts the separator before the first element too (KILL p01, p02)", file=P, targets=T,
         old="if ntxt > 0 && sep != 0",
         new="if sep != 0"),
    dict(id="P2-A6 the 100-element list check never fires: a long partial list is split (KILL p33)", file=P, targets=T,
         old="if ntxt == 100 && lengthList(ld, l, true) < 0",
         new="if ntxt == 101 && lengthList(ld, l, true) < 0"),
    dict(id="P2-A7 the 100-element list check fires at 99: a shorter partial list is refused (KILL p49)", file=P, targets=T,
         old="if ntxt == 100 && lengthList(ld, l, true) < 0",
         new="if ntxt == 99 && lengthList(ld, l, true) < 0"),
    dict(id="P2-A8 the empty separator's domain error names another domain (KILL p13)", file=P, targets=T,
         old="\"non_empty_atom\", sep",
         new="\"nonempty_atom\", sep"),
    dict(id="P2-A9 a unbound element splits for a string result as well (KILL p43)", file=P, targets=T,
         old="PL_is_variable(ld, head) && sep != 0 && ret_type == PL_ATOM",
         new="PL_is_variable(ld, head) && sep != 0"),
    dict(id="P2-A10 a list with a non-list tail is split, not refused with type_error(list, _) (KILL p35, p47)", file=P, targets=T,
         old="elseif !PL_is_variable(ld, l)",
         new="elseif false"),
    dict(id="P2-A11 a separator that is no text raises type_error(atom, _), not text (KILL p16)", file=P, targets=T,
         old="PL_error(ld, ERR_TYPE, mk_sym(T, :text), sep)",
         new="PL_error(ld, ERR_TYPE, mk_sym(T, :atom), sep)"),
    # ── the wrappers ──
    dict(id="P2-B1 atomics_to_string/2 makes an atom (KILL p40, p44)", file=P, targets=T,
         old="return atomic_list_concat(ld, PL__t0, 0, PL__t0 + 1, PL_STRING)",
         new="return atomic_list_concat(ld, PL__t0, 0, PL__t0 + 1, PL_ATOM)"),
    dict(id="P2-B2 atomics_to_string/3 makes an atom (KILL p41, p46)", file=P, targets=T,
         old="return atomic_list_concat(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, PL_STRING)",
         new="return atomic_list_concat(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, PL_ATOM)"),
    dict(id="P2-B3 atomic_list_concat/2 makes a string (KILL p22, p23)", file=P, targets=T,
         old="return atomic_list_concat(ld, PL__t0, 0, PL__t0 + 1, PL_ATOM)",
         new="return atomic_list_concat(ld, PL__t0, 0, PL__t0 + 1, PL_STRING)"),
    dict(id="P2-B4 sub_atom/5 makes strings (KILL p51, p63)", file=P, targets=T,
         old="PL__t0 + 3, PL__t0 + 4, PL__ctx, PL_ATOM",
         new="PL__t0 + 3, PL__t0 + 4, PL__ctx, PL_STRING"),
    # ── the registration table ──
    dict(id="P2-C1 sub_atom/5 is registered deterministic (KILL p50, p53, p65)", file=S, targets=T,
         old="PL_FA_NONDETERMINISTIC | PL_FA_ISO | PL_FA_VARARGS",
         new="PL_FA_ISO | PL_FA_VARARGS"),
    dict(id="P2-C2 sub_atom/5 loses its ISO flag",
         file=S, targets=T,
         old="PL_FA_NONDETERMINISTIC | PL_FA_ISO | PL_FA_VARARGS",
         new="PL_FA_NONDETERMINISTIC | PL_FA_VARARGS",
         equivalent="src/pl-comp.jl:1448 — read, not run: P_ISO is read only to pick the system procedure for a body goal "
                    "in a module other than system, which the user module's own lookup reaches by inheritance from system "
                    "as well; no user definition of sub_atom/5 can shadow it (row p69: permission_error), so the answers are the same"),
]
