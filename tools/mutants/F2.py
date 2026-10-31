# ORIGINAL: F2's mutant list — no swipl-devel counterpart.
# tools/mutants/F2.py — the mutation battery of F2 (pl-prologflag.c push_prolog_flag, pop_prolog_flag and their helpers
# copy_prolog_flag, put_saved_flag_value, ensure_local_flag; src/pl-fli.jl PL_put_float), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as MOD3b.py and F1B.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. Killed by test/core_lang/test_push_flag_swipl.jl (rows pf01-pf44 named in each id's KILL).
# The mutated code (the push and pop paths, put_saved_flag_value, PL_put_float) is reached only through push_prolog_flag/2
# and pop_prolog_flag/1; set_flag_value is F1b's and has its own list (F1B.py), run with this one at the gate. The one
# row file of this step is therefore the whole TARGETS list; test_set_flag_swipl.jl does not call a mutated line (no
# mutant here changes set_flag_value or the validators), so it is not listed (D-0238).
# Verdicts: written by the battery, not yet run. The `old` strings are written in the repo's formatted style BEFORE
# `tools/warm.sh fmt` ran (the coding agent had no daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string
# that does not occur exactly once). Every `old` was checked to occur exactly once in its file at wip/f2 (a text count,
# no Julia).
# NOT LISTED (each with its reason):
#   * `of.references += 1` in copy_prolog_flag: the anchor occurs twice in src/os/pl-prologflag.jl (also in
#     the code of the F1b set_flag_value path), and the count is read only in clean_prolog_flag; no row copies a flag whose oneof is
#     cleaned later with a reference count that matters, so no row can judge it.
#   * `clean_prolog_flag(saved)` in push_prolog_flag's refused branch: dropping it only leaves an unreferenced copy
#     (its oneof count one too high); no row reads the count, so no verdict is claimed.
TP = ["test/core_lang/test_push_flag_swipl.jl"]
TARGETS = TP                                        # the baseline's targets (mutate_ci.py plan reads TARGETS)
P = "src/os/pl-prologflag.jl"
FLI = "src/pl-fli.jl"
MUTANTS = [
    # ── pop_prolog_flag: the frame ──
    dict(id="F2-A1 a frame saved for an absent flag is restored as a value (KILL pf13-pf17, pf20, pf22)", file=P, targets=TP,
         old="    if (prev.flags & FF_PUSH_ABSENT) != 0\n",
         new="    if false\n"),
    dict(id="F2-A2 the pop of an absent flag does not delete it from the table (KILL pf13)", file=P, targets=TP,
         old="        deletePrologFlag!(gd, w)\n",
         new="        nothing\n"),
    dict(id="F2-A3 the push of an absent flag stores no absent frame (KILL pf13)", file=P, targets=TP,
         old="    nf.pushed = absent\n",
         new="    nf.pushed = nothing\n"),
    dict(id="F2-A4 the saved copy is not linked below the flag (KILL pf01, pf04)", file=P, targets=TP,
         old="            f.pushed = saved\n",
         new="            nothing\n"),
    dict(id="F2-A5 the saved copy loses the frames below it (KILL pf18, pf23, pf38, pf44)", file=P, targets=TP,
         old="            saved.pushed = f.pushed\n",
         new="            nothing\n"),
    dict(id="F2-A6 copy_prolog_flag keeps the pushed chain: the clean of a refused push zeroes the real frame (KILL pf43)", file=P, targets=TP,
         old="f.t, f.oneof, nothing)   # *copy = *f; copy->pushed = NULL",
         new="f.t, f.oneof, f.pushed)   # *copy = *f; copy->pushed = NULL"),
    dict(id="F2-A7 copy_prolog_flag shares no record of a term flag (KILL pf30)", file=P, targets=TP,
         old="        copy.t = PL_duplicate_record(f.t::record{T})\n",
         new="        copy.t = nothing\n"),
    # ── put_saved_flag_value ──
    dict(id="F2-B1 a saved float comes back changed (KILL pf26)", file=P, targets=TP,
         old="        return PL_put_float(ld, val, saved.f)\n",
         new="        return PL_put_float(ld, val, saved.f + 1.0)\n"),
    dict(id="F2-B2 a saved term flag comes back as an atom (KILL pf30)", file=P, targets=TP,
         old="        return PL_recorded(ld, saved.t::record{T}, val)\n",
         new="        return PL_put_atom(ld, val, saved.a)\n"),
    dict(id="F2-B3 a saved integer comes back changed (KILL pf24)", file=P, targets=TP,
         old="        return PL_put_int64(ld, val, Int(saved.i))\n",
         new="        return PL_put_int64(ld, val, Int(saved.i) + 1)\n"),
    dict(id="F2-B4 a saved Boolean flag is no longer put as an atom (KILL pf04, pf28)", file=P, targets=TP,
         old="    if type == FT_BOOL || type == FT_ATOM\n",
         new="    if type == FT_ATOM\n"),
    # ── push_prolog_flag: the refusals ──
    dict(id="F2-C1 a shared flag may be pushed (KILL pf35, pf36)", file=P, targets=TP,
         old="        if (f.flags & FF_SHARED) != 0  ",
         new="        if false  "),
    dict(id="F2-C2 push does not check the write access: a read-only flag is pushed (KILL pf07, pf10, pf37)", file=P, targets=TP,
         old="        check_flag_write_access(ld, f, k, UInt32(0)) || return false\n",
         new="        nothing\n"),
    dict(id="F2-C3 the permission_error of a shared flag names the action modify, not push (KILL pf35)", file=P, targets=TP,
         old="mk_sym(T, :push)",
         new="mk_sym(T, :modify)"),
    # ── pop_prolog_flag: the refusal and the restore ──
    dict(id="F2-D1 a pop of a flag with no frame goes on: the TypeAssert of the frame, not the existence_error (KILL pf02)", file=P, targets=TP,
         old="    if f === nothing || f.pushed === nothing\n",
         new="    if f === nothing\n"),
    dict(id="F2-D2 a pop keeps the frame it restored: the flag still has a frame, the one below is lost (KILL pf18, pf38, pf44)", file=P, targets=TP,
         old="        f.pushed = prev.pushed\n",
         new="        f.pushed = nothing\n"),
    dict(id="F2-D3 push stores no new value (KILL pf01)", file=P, targets=TP,
         old="        rc = set_flag_value(gd, ld, f, m, k, value)\n",
         new="        rc = true\n"),
    dict(id="F2-D4 pop restores no saved value (KILL pf01)", file=P, targets=TP,
         old="        rc = set_flag_value(gd, ld, f, m, k, restore)\n",
         new="        rc = true\n"),
    dict(id="F2-D5 ensure_local_flag answers a copy: the write goes to a copy, not to the flag (KILL pf01)", file=P, targets=TP,
         old="ensure_local_flag(k::T, f::prolog_flag{T}) where {T} = f\n",
         new="ensure_local_flag(k::T, f::prolog_flag{T}) where {T} = copy_prolog_flag(f)\n"),
    dict(id="F2-D6 the absent frame has no FF_PUSH_ABSENT bit (KILL pf13)", file=P, targets=TP,
         old="FT_INTEGER | FF_PUSH_ABSENT",
         new="FT_INTEGER"),
    dict(id="F2-D7 the flag a push creates has the type atom, not the type of the value (KILL pf13: type_error)", file=P, targets=TP,
         old="new_prolog_flag(ld, value, FT_FROM_VALUE)",
         new="new_prolog_flag(ld, value, FT_ATOM)"),
    dict(id="F2-D8 the flag a push creates gets no slot in the table: current_prolog_flag cannot find it (KILL pf13)", file=P, targets=TP,
         old="    push!(tab.names, k)\n    tab.slot[w] = length(tab.entries)\n    return true\n",
         new="    push!(tab.names, k)\n    return true\n"),
    dict(id="F2-D9 pop_prolog_flag is registered with arity 2 (KILL pf01)", file=P, targets=TP,
         old="PL_extension(\"pop_prolog_flag\", 1,",
         new="PL_extension(\"pop_prolog_flag\", 2,"),
    dict(id="F2-D10 the existence_error of a pop names the type prolog_flag, not pushed_flag (KILL pf02, pf03, pf21)", file=P, targets=TP,
         old="mk_sym(T, :pushed_flag)",
         new="mk_sym(T, :prolog_flag)"),
    # ── src/pl-fli.jl PL_put_float ──
    dict(id="F2-E1 PL_put_float puts the float plus one (KILL pf26)", file=FLI, targets=TP,
         old="    setSlotValue!(ld, t + 1, mk_gnd(T, f))\n",
         new="    setSlotValue!(ld, t + 1, mk_gnd(T, f + 1.0))\n"),
    # ── equivalent ──
    dict(id="F2-EQ1 the pop of an absent flag does not clean the removed flag", file=P, targets=TP,
         old="        clean_prolog_flag(f)\n        return true\n",
         new="        return true\n",
         equivalent="src/os/pl-prologflag.jl:176-180: after deletePrologFlag! the table slot is emptied and not reused, so the flag `f` is unreachable; the flag was made by new_prolog_flag in push (no oneof, no record), so clean_prolog_flag(f) has nothing to release that a later row can read."),
]
