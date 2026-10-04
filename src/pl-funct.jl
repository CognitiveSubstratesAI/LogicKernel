# UPSTREAM: swipl-devel src/pl-funct.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2020, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
#
# THE FUNCTOR TABLE'S FLAGS, as far as the clause compiler reads them — SWI-Prolog's pl-funct.c as
# far as the control functors. `initFunctors` creates the functor table at start-up, and
# `registerControlFunctors` flags `CONTROL_F` on the definitions of the functors `compileBody`
# compiles; the compiler reads the flag through `valueFunctor`, that is, through GD's functor table
# (`GD->functors.array`).
#
# In the kernel the flagged set is a field of the database's global data (`functors_control`,
# src/pl-global.jl), registered when a `PL_global_data` is created — once per database, as upstream
# registers it once per process — and the compiler reaches it through the global data passed in.
#
# NOT PORTED: the functor table itself (`lookupFunctorDef`, `allocFunctorTable`, its rehashing; the
# kernel has none, see `registerControlFunctors`), `registerBuiltinFunctors`, and
# `registerArithFunctors` (`ARITH_F`, which comes with compiled arithmetic).

# ── the control functors (pl-funct.c) ──────────────────────────────────────────────────────────
# From pl-funct.c registerControlFunctors: the set it flags `CONTROL_F`, as the kernel holds it.
"""
The functors `compileBody` compiles (pl-funct.c `registerControlFunctors`, the `CONTROL_F` flag):
`,/2`, `;/2`, `|/2`, `->/2`, `*->/2`, `\\+/1`, `:/2` (Module:Goal), `\$/1` and `@/2` (Goal@Module,
O_CALL_AT_MODULE) — each the `sym_key` of its name.
"""
struct ControlFunctors
    comma::UInt64           # FUNCTOR_comma2
    semicolon::UInt64       # FUNCTOR_semicolon2
    bar::UInt64             # FUNCTOR_bar2
    ifthen::UInt64          # FUNCTOR_ifthen2
    softcut::UInt64         # FUNCTOR_softcut2
    not_provable::UInt64    # FUNCTOR_not_provable1
    colon::UInt64           # FUNCTOR_colon2: Module:Goal
    dollar::UInt64          # FUNCTOR_dollar1: $(Goal)
    at_sign::UInt64         # FUNCTOR_at_sign2: Goal@Module
end

# PORT: pl-funct.c registerControlFunctors
# DIVERGES: upstream sets `CONTROL_F` on the functor definitions of its functor table at start-up;
# the kernel has no functor table, so the set is the `sym_key`s of the names' TEXT atoms, resolved
# for the term type once per database, when its `PL_global_data` is created (the field
# `functors_control`). `name/arity` is matched by `_has_functor`.
"The control functors of term type `T` (pl-funct.c `registerControlFunctors`)."
function registerControlFunctors(::Type{T})::ControlFunctors where {T}
    return ControlFunctors(
        sym_key(mk_sym(T, Symbol(","))), sym_key(mk_sym(T, Symbol(";"))),
        sym_key(mk_sym(T, Symbol("|"))), sym_key(mk_sym(T, Symbol("->"))),
        sym_key(mk_sym(T, Symbol("*->"))), sym_key(mk_sym(T, Symbol("\\+"))),
        sym_key(mk_sym(T, Symbol(":"))), sym_key(mk_sym(T, Symbol("\$"))),
        sym_key(mk_sym(T, Symbol("@")))
    )
end

"""
Whether compound `t` has the functor `name/arity` of the symbol whose `sym_key` is `key` — upstream's
`f->definition == FUNCTOR_…`. A compound whose head is not a symbol (`\$expr/n`) has none.
"""
_has_functor(t, key::UInt64, arity::Int)::Bool =
    nchildren(t) == arity + 1 && kind(child(t, 1)) === SYM && sym_key(child(t, 1)) == key

"Whether compound `t`'s functor is a control functor (`ison(fd, CONTROL_F)`, pl-funct.c)."
function _is_control(t, cf::ControlFunctors)::Bool
    return _has_functor(t, cf.comma, 2) || _has_functor(t, cf.semicolon, 2) ||
           _has_functor(t, cf.bar, 2) || _has_functor(t, cf.ifthen, 2) ||
           _has_functor(t, cf.softcut, 2) || _has_functor(t, cf.not_provable, 1) ||
           _has_functor(t, cf.colon, 2) || _has_functor(t, cf.dollar, 1) ||
           _has_functor(t, cf.at_sign, 2)
end
