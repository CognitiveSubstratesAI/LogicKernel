# ORIGINAL: FLIAPI's mutant list — no swipl-devel counterpart.
# tools/mutants/FLIAPI.py — the mutation battery of FLI-API group 1 (audit D-0777 (4)(a)): the pl-fli.c API functions
# PL_put_bool, PL_put_pointer, PL_put_functor, PL_put_list, PL_get_uintptr, PL_get_pointer, PL_get_arg
# (PL_get_arg_sz), PL_get_compound_name_arity (PL_get_compound_name_arity_sz), PL_unify_int64_ex, PL_unify_pointer
# (src/pl-fli.jl), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format:
# tools/mutate_drive.py's (as ARGINL.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# and `targets`. Each id is AIMED BY the rows its "aimed by" names, all in test/core_lang/test_fli_api1_cells.jl. Verdicts:
# written by the battery, not yet run. Every `old` was counted in src/pl-fli.jl at the commit that added this list
# (a text count, no Julia): each occurs exactly once.
# TARGETS (audit D-0238): the new functions have no caller in the kernel yet (foreign code calls them), so the step's own
# file is the only one that exercises the mutated code; PL_unify_int64_ex and PL_unify_pointer reach unify_int64_ex, whose
# other callers' file test_fli_unify_cells.jl is listed too.
# NOT LISTED: PL_put_list's and PL_put_functor's cell COUNT (the compound's arity is its functor word; a missing cell
# would be read past, a garbage read, not a verdict).
TS = ["test/core_lang/test_fli_api1_cells.jl"]
TU = TS + ["test/core_lang/test_fli_unify_cells.jl"]
F = "src/pl-fli.jl"
MUTANTS = [
    dict(id="FLIAPI-B1 PL_put_bool puts the opposite atom (aimed by PL_put_bool)", file=F, targets=TS,
         old="PL_put_atom(ld, t, mk_sym(T, val ? Symbol(\"true\") : Symbol(\"false\")))",
         new="PL_put_atom(ld, t, mk_sym(T, val ? Symbol(\"false\") : Symbol(\"true\")))"),
    dict(id="FLIAPI-P1 PL_put_pointer puts the pointer shifted right by one bit (aimed by the pointer API: PL_get_int64 == 4096)", file=F, targets=TS,
         old="return PL_put_int64(ld, t, reinterpret(Int, ptr))       # PL_put_int64(t, (int64_t)pointerToInt(ptr))",
         new="return PL_put_int64(ld, t, reinterpret(Int, ptr >> 1))       # PL_put_int64(t, (int64_t)pointerToInt(ptr))"),
    dict(id="FLIAPI-F1 PL_put_functor lays the compound out with the list functor (aimed by PL_put_functor: PL_is_functor f/3)", file=F, targets=TS,
         old="a = _alloc_compound!(ld, f, arity)                  # a = allocGlobal(1+arity); *a++ = f; setVar(*a++)…",
         new="a = _alloc_compound!(ld, ld.functor_dot2, arity)                  # a = allocGlobal(1+arity); *a++ = f; setVar(*a++)…"),
    dict(id="FLIAPI-F2 PL_put_functor of arity 0 puts [] (aimed by PL_put_functor: the atom g)", file=F, targets=TS,
         old="ld.slots[t + 1] = nameFunctor(ld.functors, f)       # setHandle(t, nameFunctor(f))",
         new="ld.slots[t + 1] = ld.atom_nil_w       # setHandle(t, nameFunctor(f))"),
    dict(id="FLIAPI-L1 PL_put_list puts [] (aimed by PL_put_functor and PL_put_list: PL_is_pair)", file=F, targets=TS,
         old="ld.slots[l + 1] = consPtr(a, TAG_COMPOUND | STG_GLOBAL) # setHandle(l, consCompound(a))",
         new="ld.slots[l + 1] = ld.atom_nil_w # setHandle(l, consCompound(a))"),
    dict(id="FLIAPI-U1 PL_get_uintptr accepts a negative integer (aimed by the pointer API: PL_get_uintptr of -1 and of -5)", file=F, targets=TS,
         old="(v === nothing || v < 0) && return nothing              # val < 0",
         new="v === nothing && return nothing              # val < 0"),
    dict(id="FLIAPI-U2 PL_get_uintptr answers one more (aimed by the pointer API, the meter: 4096, 77)", file=F, targets=TS,
         old="return UInt(v)                                          # *i = (size_t)val",
         new="return UInt(v + 1)                                          # *i = (size_t)val"),
    dict(id="FLIAPI-G1 PL_get_pointer refuses a negative integer's bits (aimed by the pointer API: typemax(UInt))", file=F, targets=TS,
         old="return reinterpret(UInt, p)                             # *ptr = intToPointer((uintptr_t)p)",
         new="return UInt(max(p, 0))                             # *ptr = intToPointer((uintptr_t)p)"),
    dict(id="FLIAPI-A1 PL_get_arg accepts the index 0 (aimed by PL_get_arg: index 0)", file=F, targets=TS,
         old="if k == DU_WORD && _is_gcompound(w) && index > 0        # isTerm(w) && index > 0",
         new="if k == DU_WORD && _is_gcompound(w) && index >= 0        # isTerm(w) && index > 0"),
    dict(id="FLIAPI-A2 PL_get_arg accepts the index one past the arity (aimed by PL_get_arg: index 4 of f/3, index 3 of $expr/2)", file=F, targets=TS,
         old="if index <= arityFunctor(ld.functors, ld.gstack[q]) # --index < arity",
         new="if index <= arityFunctor(ld.functors, ld.gstack[q]) + 1 # --index < arity"),
    dict(id="FLIAPI-A3 PL_get_arg reads the next argument (aimed by PL_get_arg: a, 2, the variable)", file=F, targets=TS,
         old="_slot_from_cell!(ld, a + 1, q + index)          # setHandle(a, linkValI(&f->arguments[index]))",
         new="_slot_from_cell!(ld, a + 1, q + index + 1)          # setHandle(a, linkValI(&f->arguments[index]))"),
    dict(id="FLIAPI-N1 PL_get_compound_name_arity answers an arity one too big (aimed by PL_get_compound_name_arity: 3, 2)", file=F, targets=TS,
         old="        return (_atom_value(ld, name), arity)\n    end\n    return nothing\nend\n\n# PORT: pl-fli.h PL_is_functor",
         new="        return (_atom_value(ld, name), arity + 1)\n    end\n    return nothing\nend\n\n# PORT: pl-fli.h PL_is_functor"),
    dict(id="FLIAPI-X1 PL_unify_int64_ex does not raise: ex false (aimed by PL_unify_int64_ex: the exception after the atom)", file=F, targets=TU,
         old="unify_int64_ex(ld, t, i, true)\n\n# PORT: pl-fli.c PL_unify_pointer",
         new="unify_int64_ex(ld, t, i, false)\n\n# PORT: pl-fli.c PL_unify_pointer"),
    dict(id="FLIAPI-Y1 PL_unify_pointer unifies the pointer shifted right by one bit (aimed by the pointer API: PL_unify_pointer on 4096)", file=F, targets=TU,
         old="unify_int64_ex(ld, t, reinterpret(Int, ptr), false)",
         new="unify_int64_ex(ld, t, reinterpret(Int, ptr >> 1), false)"),
]
