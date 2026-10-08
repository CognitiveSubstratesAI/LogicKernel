# UPSTREAM: swipl-devel src/pl-op.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE OPERATOR TABLES (pl-op.c; since R1b): each module's table — `module_t.operators`, the
# `system` module's holding SWI's defaults (`initOperators!`) — defining an operator
# (`defOperator!`, `op/3`) and looking one up through the module's supers (`currentOperator`,
# `priorityOperator`), as the reader (R1c, R1d) and the writer (R1e) will. An operator record is
# upstream's `operator` — `type[3]` and `priority[3]` by kind — kept as a tuple with its key atom
# (src/pl-incl.jl, `module_t`).
#
# NOT PORTED: `current_op/3` and `$local_op/3`, until V9's non-deterministic built-ins: what they
# enumerate is ported (`scanVisibleOperators!`, the buffer it fills), their FRG iteration is not;
# the thread-local table (no threads); `copyOperatorSymbol`/`freeOperatorSymbol` (atom reference
# counts: Julia's garbage collector).

# PORT: pl-op.c OP_INHERIT
"An operator record's type for a kind it does not define: look in the super modules (pl-op.c)."
const OP_INHERIT = 0x00

"An operator record: its key atom, `type[3]` and `priority[3]` (pl-op.c `struct _operator`)."
const _operator{T} = Tuple{T, NTuple{3, UInt8}, NTuple{3, Int16}}

# ── defining operators (pl-op.c) ────────────────────────────────────────────────────────────────
# PORT: pl-op.c defOperator as defOperator!
# DIVERGES: the database `gd` and the local data `ld` are arguments (the error is raised in `ld`;
# `nothing` when `force`, which raises nothing: `initOperators!` runs before any local data exists);
# no `SYSTEM_MODE` test (no system mode: it is always off) and no lock (no threads); the record is
# replaced in the table, a tuple, where upstream updates it in place.
"""
    defOperator!(gd, ld, m, name, type, priority, force) -> Bool

Define `name` as an operator of `type` and `priority` in module `m` (pl-op.c); priority 0 cancels
it, -1 inherits. Unless `force`, `,` cannot be redefined and `|` only as an infix operator of
priority 1001 or more (or 0): `permission_error(modify | create, operator, Name)`.
"""
function defOperator!(
    gd::PL_global_data{T}, ld::Union{Nothing, PL_local_data{T}}, m::module_t{T}, name::T,
    type::UInt8, priority::Int16, force::Bool
)::Bool where {T}
    t = Int(type & OP_MASK)                                 # OP_PREFIX, ...
    @assert OP_PREFIX <= t <= OP_POSTFIX
    if !force                                               # && !SYSTEM_MODE
        comma = sym_key(name) == sym_key(mk_sym(T, Symbol(",")))
        if comma || (
            sym_key(name) == sym_key(mk_sym(T, Symbol("|"))) &&
            (t != OP_INFIX || (priority < 1001 && priority != 0))
        )
            action = comma ? mk_sym(T, :modify) : mk_sym(T, :create)
            ld === nothing &&
                error("defOperator!: an unforced definition needs the local data")
            tr = new_term_ref(ld)
            ld.slots[tr + 1] = name                         # PL_put_atom(t, name)
            return PL_error(ld, "", 0, "", ERR_PERMISSION, action, mk_sym(T, :operator), tr)
        end
    end
    key = sym_key(name)
    op = get(m.operators, key, nothing)
    if op === nothing
        priority < 0 && return true                         # already inherited: do not change
        types = (OP_INHERIT, OP_INHERIT, OP_INHERIT)
        prios = (Int16(-1), Int16(-1), Int16(-1))
    else
        _, types, prios = op
    end
    prios = Base.setindex(prios, priority, t + 1)           # op->priority[t] = priority
    types = Base.setindex(types, priority >= 0 ? type : OP_INHERIT, t + 1)
    m.operators[key] = (name, types, prios)
    return true
end

# ── querying operators (pl-op.c) ────────────────────────────────────────────────────────────────
# PORT: pl-op.c visibleOperator
# DIVERGES: the name is its `sym_key`; the super modules are indices into `gd`'s module table; no
# thread-local table (no threads).
"The record of `name` (its `sym_key`) that defines `kind` in module `m` or its supers, or `nothing` (pl-op.c)."
function visibleOperator(
    gd::PL_global_data{T}, m::module_t{T}, key::UInt64, kind::Int
)::Union{Nothing, _operator{T}} where {T}
    op = get(m.operators, key, nothing)
    if op !== nothing && op[2][kind + 1] != OP_INHERIT
        return op
    end
    for s in m.supers
        op = visibleOperator(gd, gd.modules[s], key, kind)
        op === nothing || return op
    end
    return nothing
end

# PORT: pl-op.c currentOperator
# DIVERGES: returns `(found, type, priority)`, where upstream writes them through pointers; `m`
# `nothing` is upstream's NULL (`user`).
"""
    currentOperator(gd, m, name, kind) -> (found, type, priority)

Whether `name` is an operator of `kind` (`OP_PREFIX`, `OP_INFIX`, `OP_POSTFIX`) visible from module
`m` (`user` when `nothing`), with a priority above 0, and its type and priority (pl-op.c).
"""
function currentOperator(
    gd::PL_global_data{T}, m::Union{Nothing, module_t{T}}, name::T, kind::Int
)::Tuple{Bool, UInt8, Int16} where {T}
    @assert OP_PREFIX <= kind <= OP_POSTFIX
    mm = m === nothing ? MODULE_user(gd) : m
    op = visibleOperator(gd, mm, sym_key(name), kind)
    if op !== nothing && op[3][kind + 1] > 0
        return (true, op[2][kind + 1], op[3][kind + 1])
    end
    return (false, 0x00, Int16(0))
end

# PORT: pl-op.c maxOp
# DIVERGES: returns `(sofar, done)`, where upstream updates `done` through a pointer.
"The highest priority of `op`'s kinds not yet in `done` (pl-op.c), and `done` with them added."
function maxOp(op::_operator{T}, done::Int, sofar::Int)::Tuple{Int, Int} where {T}
    for i in 0:2
        if (done & (1 << i)) == 0 && op[2][i + 1] != OP_INHERIT
            if op[3][i + 1] > sofar
                sofar = Int(op[3][i + 1])
            end
            done |= (1 << i)
        end
    end
    return (sofar, done)
end

# PORT: pl-op.c scanPriorityOperator
# DIVERGES: as `maxOp`, and the super modules are indices into `gd`'s table.
"The highest priority of `name` (its `sym_key`) in module `m` and its supers, kind by kind (pl-op.c)."
function scanPriorityOperator(
    gd::PL_global_data{T}, m::module_t{T}, key::UInt64, done::Int, sofar::Int
)::Tuple{Int, Int} where {T}
    if done != 0x7
        op = get(m.operators, key, nothing)
        if op !== nothing
            sofar, done = maxOp(op, done, sofar)
        end
        if done != 0x7
            for s in m.supers
                sofar, done = scanPriorityOperator(gd, gd.modules[s], key, done, sofar)
            end
        end
    end
    return (sofar, done)
end

# PORT: pl-op.c priorityOperator
"The highest priority `name` has as an operator of any kind, from module `m` (`user` when `nothing`), else 0 (pl-op.c)."
function priorityOperator(
    gd::PL_global_data{T}, m::Union{Nothing, module_t{T}}, name::T
)::Int where {T}
    mm = m === nothing ? MODULE_user(gd) : m
    return scanPriorityOperator(gd, mm, sym_key(name), 0, 0)[1]
end

# ── the Prolog binding (pl-op.c) ────────────────────────────────────────────────────────────────
# PORT: pl-op.c atomToOperatorType
# DIVERGES: the term type `T` is passed, as `operatorTypeToAtom`'s is: an atom's own type may be a
# subtype of it (the conformance suite's alternative term types), which cannot make the type names.
"The operator type the atom `atom` names (`fx`, …, `yfx`), else 0 (pl-op.c)."
function atomToOperatorType(::Type{T}, atom::T)::UInt8 where {T}
    kind(atom) === SYM || return 0x00
    k = sym_key(atom)
    k == sym_key(mk_sym(T, :fx)) && return OP_FX
    k == sym_key(mk_sym(T, :fy)) && return OP_FY
    k == sym_key(mk_sym(T, :xfx)) && return OP_XFX
    k == sym_key(mk_sym(T, :xfy)) && return OP_XFY
    k == sym_key(mk_sym(T, :yfx)) && return OP_YFX
    k == sym_key(mk_sym(T, :yf)) && return OP_YF
    k == sym_key(mk_sym(T, :xf)) && return OP_XF
    return 0x00
end

# PORT: pl-op.c operatorTypeToAtom
# DIVERGES: `nothing` for upstream's NULL_ATOM (type 0).
"The atom naming operator type `type` (pl-op.c)."
function operatorTypeToAtom(::Type{T}, type::UInt8)::Union{Nothing, T} where {T}
    i = Int(type >> 4)
    i == 0 && return nothing
    return mk_sym(T, (:fx, :fy, :xf, :yf, :xfx, :xfy, :yfx)[i])
end

# PORT: pl-op.c op as pl_op3_va
# (PRED_IMPL("op", 3, op, PL_FA_TRANSPARENT|PL_FA_ISO))
# DIVERGES: the module is `MODULE_parse`, which is `user` here (since R1f the loader reads into
# `user`, its source module); modules are indices into the database's table (src/pl-modul.jl).
"`op/3` (pl-op.c): define operators in `user`, or in the module the name is qualified with."
function pl_op3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    gd = _query_gd(ld)
    m = MODULE_user(gd).index                               # MODULE_parse
    pri, type, name = A1, A2, A3
    ok, m = PL_strip_module(gd, ld, name, m, name)
    ok || return FFALSE
    if m == MODULE_system(gd).index
        t = new_term_ref(ld)
        ld.slots[t + 1] = mk_expr(
            T, T[mk_sym(T, :(:)), gd.modules[m].atom, ld.slots[name + 1]]
        )
        PL_error(
            ld, "", 0, "system operators are protected", ERR_PERMISSION,
            mk_sym(T, :redefine),
            mk_sym(T, :operator), t
        )
        return FFALSE
    end
    tp = PL_get_atom_ex(ld, type)
    tp === nothing && return FFALSE
    p = PL_get_integer_ex(ld, pri)
    p === nothing && return FFALSE
    if !((p >= 0 && p <= OP_MAXPRIORITY) || (p == -1 && m != MODULE_user(gd).index))
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :operator_priority), pri)
        return FFALSE
    end
    t = atomToOperatorType(T, tp)
    if t == 0
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :operator_specifier), type)
        return FFALSE
    end
    nm = PL_get_atom(ld, name)
    if nm !== nothing
        return defOperator!(gd, ld, gd.modules[m], nm, t, Int16(p), false) ? FTRUE : FFALSE
    else
        l = PL_copy_term_ref(ld, name)
        e = new_term_ref(ld)
        while PL_get_list_ex(ld, l, e, l)
            nm = PL_get_atom(ld, e)
            if nm === nothing
                PL_error(ld, ERR_TYPE, mk_sym(T, :atom), e)
                return FFALSE
            end
            defOperator!(gd, ld, gd.modules[m], nm, t, Int16(p), false) || return FFALSE
        end
        PL_get_nil_ex(ld, l) || return FFALSE
    end
    return FTRUE
end

# ── what current_op/3 enumerates (pl-op.c) ──────────────────────────────────────────────────────
# PORT: pl-op.c addOpToBuffer as addOpToBuffer!
# DIVERGES: the buffer is a vector of `(name, type, priority)`, upstream's `opdef`s.
"Add the operator `name`/`type`/`priority` to `b` unless one of its name and kind is there (pl-op.c)."
function addOpToBuffer!(
    b::Vector{Tuple{T, UInt8, Int16}}, name::T, type::UInt8, priority::Int16
)::Nothing where {T}
    for (n, ty, _) in b
        sym_key(n) == sym_key(name) && (ty & OP_MASK) == (type & OP_MASK) && return nothing
    end
    push!(b, (name, type, priority))
    return nothing
end

# PORT: pl-op.c addOpsFromTable as addOpsFromTable!
# DIVERGES: the name `nothing` is upstream's NULL_ATOM (any name); the table's order is the Dict's,
# not upstream's hash table's, so an enumeration's ORDER differs (compare them as sets).
"Add the operators of `table` matching `name`, `priority` (0: any) and `type` (0: any) to `b` (pl-op.c)."
function addOpsFromTable!(
    table::Dict{UInt64, _operator{T}}, name::Union{Nothing, T}, priority::Int, type::UInt8,
    b::Vector{Tuple{T, UInt8, Int16}}
)::Nothing where {T}
    for (k, op) in table
        nm = op[1]
        if name === nothing || k == sym_key(name)
            if type != 0
                kd = Int(type & OP_MASK)
                @assert OP_PREFIX <= kd <= OP_POSTFIX
                (op[3][kd + 1] < 0 || (op[2][kd + 1] & OP_MASK) != (type & OP_MASK)) &&
                    continue
                if priority == 0 || op[3][kd + 1] == priority || op[3][kd + 1] == 0
                    addOpToBuffer!(b, nm, op[2][kd + 1], op[3][kd + 1])
                end
            else
                for kd in OP_PREFIX:OP_POSTFIX
                    op[3][kd + 1] < 0 && continue
                    if priority == 0 || op[3][kd + 1] == priority || op[3][kd + 1] == 0
                        addOpToBuffer!(b, nm, op[2][kd + 1], op[3][kd + 1])
                    end
                end
            end
        end
    end
    return nothing
end

# PORT: pl-op.c scanVisibleOperators as scanVisibleOperators!
# DIVERGES: the super modules are indices into `gd`'s module table.
"Add the operators visible from module `m` (with `inherit`, through its supers) matching the pattern to `b` (pl-op.c)."
function scanVisibleOperators!(
    gd::PL_global_data{T}, m::module_t{T}, name::Union{Nothing, T}, priority::Int,
    type::UInt8, b::Vector{Tuple{T, UInt8, Int16}}, inherit::Bool
)::Nothing where {T}
    addOpsFromTable!(m.operators, name, priority, type, b)
    if inherit
        for s in m.supers
            scanVisibleOperators!(gd, gd.modules[s], name, priority, type, b, inherit)
        end
    end
    return nothing
end

# ── initialising the operators (pl-op.c) ────────────────────────────────────────────────────────
# PORT: pl-op.c operators
"SWI-Prolog's default operators (pl-op.c `operators[]`): `(name, type, priority)`."
const operators = (
    ("*", OP_YFX, 400), ("+", OP_FY, 200), ("+", OP_YFX, 500), (",", OP_XFY, 1000),
    ("-", OP_FY, 200), ("-", OP_YFX, 500), ("-->", OP_XFX, 1200), ("->", OP_XFY, 1050),
    ("*->", OP_XFY, 1050), ("/", OP_YFX, 400), ("//", OP_YFX, 400), ("div", OP_YFX, 400),
    ("rdiv", OP_YFX, 400), ("/\\", OP_YFX, 500), (":", OP_XFY, 600), (":-", OP_FX, 1200),
    (":-", OP_XFX, 1200), ("=>", OP_XFX, 1200), ("==>", OP_XFX, 1200), (";", OP_XFY, 1100),
    ("|", OP_XFY, 1105), ("<", OP_XFX, 700), ("<<", OP_YFX, 400), ("=", OP_XFX, 700),
    ("=..", OP_XFX, 700), ("=:=", OP_XFX, 700), ("=<", OP_XFX, 700), (">=", OP_XFX, 700),
    ("==", OP_XFX, 700), ("=\\=", OP_XFX, 700), (">:<", OP_XFX, 700), (":<", OP_XFX, 700),
    (">", OP_XFX, 700), (">>", OP_YFX, 400), ("?-", OP_FX, 1200), ("@<", OP_XFX, 700),
    ("@=<", OP_XFX, 700), ("@>", OP_XFX, 700), ("@>=", OP_XFX, 700), ("\\", OP_FY, 200),
    ("\\+", OP_FY, 900), ("\\/", OP_YFX, 500), ("\\=", OP_XFX, 700), ("\\==", OP_XFX, 700),
    ("=@=", OP_XFX, 700), ("\\=@=", OP_XFX, 700), ("^", OP_XFY, 200), ("**", OP_XFX, 200),
    ("discontiguous", OP_FX, 1150), ("dynamic", OP_FX, 1150), ("volatile", OP_FX, 1150),
    ("thread_local", OP_FX, 1150), ("initialization", OP_FX, 1150),
    ("thread_initialization", OP_FX, 1150), ("is", OP_XFX, 700), ("as", OP_XFX, 700),
    ("mod", OP_YFX, 400), ("rem", OP_YFX, 400), ("module_transparent", OP_FX, 1150),
    ("multifile", OP_FX, 1150), ("meta_predicate", OP_FX, 1150), ("public", OP_FX, 1150),
    ("table", OP_FX, 1150), ("xor", OP_YFX, 400)
)

# PORT: pl-op.c initOperators as initOperators!
# DIVERGES: the database `gd` is an argument; the definitions are forced, so they need no local
# data. The table is the system module's, created with it (src/pl-modul.jl). `GD->options.traditional`
# is off: SWI-7 syntax.
"Define SWI-Prolog's default operators in the `system` module of the database `gd` (pl-op.c)."
function initOperators!(gd::PL_global_data{T})::Nothing where {T}
    sys = MODULE_system(gd)
    for (name, type, priority) in operators
        defOperator!(gd, nothing, sys, mk_sym(T, Symbol(name)), type, Int16(priority), true)
    end
    # !GD->options.traditional
    defOperator!(gd, nothing, sys, mk_sym(T, Symbol(".")), OP_YFX, Int16(100), true)
    defOperator!(gd, nothing, sys, mk_sym(T, Symbol(":=")), OP_XFX, Int16(800), true)
    return nothing
end

# PORT: pl-op.c BeginPredDefs as PL_predicates_from_op
# DIVERGES: the entries of the predicates the kernel has ported (`op/3`); `PRED_DEF` ors in
# `PL_FA_VARARGS`. NOT PORTED: `current_op/3` and `$local_op/3` (non-deterministic: V9).
"pl-op.c's registration table (`BeginPredDefs(op)`): the ported entries."
const PL_predicates_from_op = (
    PL_extension("op", 3, pl_op3_va, PL_FA_TRANSPARENT | PL_FA_ISO | PL_FA_VARARGS),
)
