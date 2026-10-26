# ORIGINAL: F1a's mutant list — no swipl-devel counterpart.
# tools/mutants/F1a.py — the mutation battery of R2 F1a (the Prolog-flag table, `setPrologFlag`, `initPrologFlags`, the mask,
# current_prolog_flag/2 and '$current_prolog_flag'/5; audit D-0149, design evidence/r2/design/flags_rest.md §6), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. One mutant per decision of the read side (the access, the type,
# the `oneof` branch, the key check, the scope check, the module strip, the tombstone skip, the two frees of the state, the cleared
# exception, the rewind), of the table (FF_KEEP, the type definition, the mask write and clear), of the values that do not live in the
# table (`break_level`, the tabling restraints, `stack_limit`, the module's syntax, the arithmetic and clause-indexing flags), and one
# per site that moved from a constant to the mask (D3, FQ3): the arithmetic (`iso`, `prefer_rationals`), the reader (`iso` twice,
# `quasi_quotations` three times), the compiler (`protect_static_code`, `iso`, `generate_debug_info`) and the option scanner (`iso`).
# NOT listed, with the reason: the `local` scope's first phase (`e.is_local = false` for an unnamed scope: a walk of the empty local
# table and a walk of the global one answer the same — representation only, src/os/pl-prologflag.jl pl_prolog_flag5); the five
# stand-in fields in `_prolog_flag_bit` (deleted by F1b, which owns their battery); src/pl-srcfile.jl's `associateSource`, which
# still clears HIDE_CHILDS unconditionally (it has no local data to read the mask from; F1b).
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does
# not occur exactly once).
TARGETS = ["test/core_lang/test_prolog_flag_swipl.jl"]
T = TARGETS
P = "src/os/pl-prologflag.jl"
A = "src/pl-arith.jl"
C = "src/pl-comp.jl"
R = "src/pl-read.jl"
O = "src/os/pl-option.jl"
MUTANTS = [
    # ---- the read side (pl_prolog_flag5 and what it unifies)
    dict(id="F1a-1 a read-only flag reports `write`", file=P, targets=T,
         old='''        return PL_unify_atom(ld, access, mk_sym(T, :read))''',
         new='''        return PL_unify_atom(ld, access, mk_sym(T, :write))'''),
    dict(id="F1a-2 a Boolean's type is `atom`", file=P, targets=T,
         old='''        a = :boolean''',
         new='''        a = :atom'''),
    dict(id="F1a-3 a `oneof` type is reported as `atom`", file=P, targets=T,
         old='''        if of !== nothing''',
         new='''        if false'''),
    dict(id="F1a-4 a key that is no atom fails instead of raising", file=P, targets=T,
         old='''            return PL_error(ld, ERR_TYPE, mk_sym(T, :atom), key) ? FTRUE : FFALSE''',
         new='''            return FFALSE'''),
    dict(id="F1a-5 an unknown scope enumerates", file=P, targets=T,
         old='''                if !(sname == "local" || sname == "global")''',
         new='''                if false'''),
    dict(id="F1a-6 the module qualifier of the key is not stripped", file=P, targets=T,
         old='''        ok, module_ = PL_strip_module(gd, ld, key, MODULE_user(gd).index, key)''',
         new='''        ok, module_ = true, MODULE_user(gd).index'''),
    dict(id="F1a-7 a deleted flag is not skipped by the walk", file=P, targets=T,
         old='''            f === nothing && continue''',
         new='''            nothing'''),
    dict(id="F1a-8 FRG_CUTTED does not free the state", file=P, targets=T,
         old='''        idx != 0 && free_foreign_state!(pool, idx)''',
         new='''        nothing'''),
    dict(id="F1a-9 the last failed walk does not free the state", file=P, targets=T,
         old='''    PL_close_foreign_frame(ld, fid)
    free_foreign_state!(pool, idx)
    return FFALSE''',
         new='''    PL_close_foreign_frame(ld, fid)
    return FFALSE'''),
    dict(id="F1a-10 an exception of a failed unification is kept", file=P, targets=T,
         old='''            PL_exception(ld, 0) != 0 && PL_clear_exception(ld)''',
         new='''            nothing'''),
    dict(id="F1a-11 a failed attempt is not rewound", file=P, targets=T,
         old='''            PL_rewind_foreign_frame(ld, fid)''',
         new='''            nothing'''),
    dict(id="F1a-12 a bound key without a flag does not fail", file=P, targets=T,
         old='''            f === nothing && return FFALSE''',
         new='''            nothing'''),
    # ---- the table (setPrologFlag)
    dict(id="F1a-13 a Boolean flag's bit is not set", file=P, targets=T,
         old='''            gd.prolog_flag.mask |= prologFlagMask(f.index)''',
         new='''            nothing'''),
    dict(id="F1a-14 a Boolean flag's bit is not cleared", file=P, targets=T,
         old='''            gd.prolog_flag.mask &= ~prologFlagMask(f.index)''',
         new='''            nothing'''),
    dict(id="F1a-15 FF_KEEP does not keep", file=P, targets=T,
         old='''        (flags & FF_KEEP) != 0 && return (nothing, false)''',
         new='''        nothing'''),
    dict(id="F1a-16 a type definition takes the argument's value, not the flag's", file=P, targets=T,
         old='''        val = sym_key(f.a) == sym_key(mk_sym(T, Symbol("true")))''',
         new='''        val = val'''),
    dict(id="F1a-17 an indexed Boolean is read as an atom (no type error)", file=P, targets=T,
         old='''            return PL_unify_bool_ex(ld, val, _prolog_flag_bit(ld, f.index))''',
         new='''            return PL_unify_atom(ld, val, f.a)'''),
    # ---- the values that do not live in the table
    dict(id="F1a-18 character_escapes is read inverted", file=P, targets=T,
         old='''        return PL_unify_bool(ld, val, (mdl.flags & M_CHARESCAPE) != 0)''',
         new='''        return PL_unify_bool(ld, val, (mdl.flags & M_CHARESCAPE) == 0)'''),
    dict(id="F1a-19 break_level has a value", file=P, targets=T,
         old='''    elseif name == "break_level"''',
         new='''    elseif name == "break_level_"'''),
    dict(id="F1a-20 the tabling restraint sizes answer -1", file=P, targets=T,
         old='''    elseif _tbl_restraint_unlimited(key)''',
         new='''    elseif false'''),
    dict(id="F1a-21 stack_limit in words, not bytes", file=P, targets=T,
         old='''ld.stacks_limit * 8''',
         new='''ld.stacks_limit'''),
    dict(id="F1a-22 unknown reads `fail`", file=P, targets=T,
         old='''        u == UNKNOWN_ERROR && return PL_unify_atom(ld, val, mk_sym(T, :error))''',
         new='''        u == UNKNOWN_ERROR && return PL_unify_atom(ld, val, mk_sym(T, :fail))'''),
    dict(id="F1a-23 double_quotes does not see the string bit", file=P, targets=T,
         old='''        elseif (mdl.flags & DBLQ_STRING) != 0''',
         new='''        elseif (mdl.flags & DBLQ_STRING) == 0'''),
    dict(id="F1a-24 ci_max_var_fraction is the double 0.1, not the float widened", file=P, targets=T,
         old='''    name == "ci_max_var_fraction" && return PL_unify_float(ld, t, Float64(MAX_VAR_FRAC))''',
         new='''    name == "ci_max_var_fraction" && return PL_unify_float(ld, t, 0.1)'''),
    dict(id="F1a-25 float_overflow is read inverted", file=A, targets=T,
         old='''        a = (flags & FLT_OVERFLOW) != 0 ? :infinity : :error''',
         new='''        a = (flags & FLT_OVERFLOW) == 0 ? :infinity : :error'''),
    dict(id="F1a-26 a rounding mode that does not exist has a name", file=A, targets=T,
         old='''            return false                    # upstream's `default: return false`''',
         new='''            a = :to_nearest'''),
    # ---- the sites that moved from a constant to the mask (D3, FQ3)
    dict(id="F1a-27 ar_divide reads iso as the old constant", file=A, targets=T,
         old='''    if !truePrologFlag(ld, PLFLAG_ISO)''',
         new='''    if true'''),
    dict(id="F1a-28 ar_divide reads prefer_rationals as the old constant", file=A, targets=T,
         old='''            if truePrologFlag(ld, PLFLAG_RATIONAL)
                promoteToMPZNumber(n1)''',
         new='''            if false
                promoteToMPZNumber(n1)'''),
    dict(id="F1a-29 raw_read2 reads iso as the old constant", file=R, targets=T,
         old='''    rd.strictness = truePrologFlag(rd.ld, PLFLAG_ISO) ? 1 : 0''',
         new='''    rd.strictness = 0'''),
    dict(id="F1a-30 read_term reads iso as the old constant", file=R, targets=T,
         old='''    rd.strictness = truePrologFlag(ld, PLFLAG_ISO) ? 1 : 0''',
         new='''    rd.strictness = 0'''),
    dict(id="F1a-31 `||` is a quasi-quotation bar whatever quasi_quotations says (raw_read2)", file=R, targets=T,
         old='''                rd._rb.base[rd._rb.here - 1] == UInt8('|') &&''',
         new='''                rd._rb.base[rd._rb.here - 1] == UInt8('|') && true || false &&'''),
    dict(id="F1a-32 `{|` opens a quasi quotation whatever quasi_quotations says", file=R, targets=T,
         old='''        if c == Int('{') && _byte(b, rd.here) == Int('|') &&''',
         new='''        if c == Int('{') && _byte(b, rd.here) == Int('|') && true || false &&'''),
    dict(id="F1a-33 `||` is a quasi-quotation bar whatever quasi_quotations says (get_token)", file=R, targets=T,
         old='''            _byte(b, rd.here) == Int('|') && truePrologFlag(rd.ld, PLFLAG_QUASI_QUOTES)''',
         new='''            _byte(b, rd.here) == Int('|')'''),
    dict(id="F1a-34 protect_static_code is the old constant", file=C, targets=T,
         old='''    protect_static_code = truePrologFlag(ld, PLFLAG_PROTECT_STATIC_CODE)''',
         new='''    protect_static_code = false'''),
    dict(id="F1a-35 iso does not protect static code", file=C, targets=T,
         old='''        (protect_static_code || truePrologFlag(ld, PLFLAG_ISO))''',
         new='''        (protect_static_code)'''),
    dict(id="F1a-36 generate_debug_info is the old constant", file=C, targets=T,
         old='''                if truePrologFlag(ld, PLFLAG_DEBUGINFO)''',
         new='''                if true'''),
    dict(id="F1a-38 var_prefix reads the table's value, not the module's", file=P, targets=T,
         old='''        v = mdl.var_prefix != 0 ? Symbol(Char(mdl.var_prefix)) : Symbol("false")   # (`:false` is the Bool)''',
         new='''        v = Symbol("false")'''),
    dict(id="F1a-37 a bare option is `Name(true)` under iso too", file=O, targets=T,
         old='''            elseif arity == 0 && !truePrologFlag(ld, PLFLAG_ISO)''',
         new='''            elseif arity == 0'''),
]
