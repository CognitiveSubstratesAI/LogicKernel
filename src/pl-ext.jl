# UPSTREAM: swipl-devel src/pl-ext.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v
#
# REGISTERING THE BUILT-INS (pl-ext.c): `initBuildIns` registers each table of built-ins in the
# `system` module — pl-ext.c's own FRG table (`foreigns`, the `a1, a2, …` convention) first, then
# each file's `PRED_DEF` table (`PL_predicates_from_<file>`, the `t0, ac, ctx` convention) — giving
# each a foreign supervisor (`createForeignSupervisor`, src/pl-supervisor.jl): `I_FCALLDETVA f`, or
# `I_FCALLDET<arity> f I_FEXITDET`.
#
# THE DISPATCH (ORIGINAL — decision 5; upstream stores a C function pointer in the operand). The
# operand `f` is the built-in's INDEX in the dispatch table of its call shape: `_FOREIGN_VA` for the
# `PRED_DEF` tables in registration order, `_FOREIGN_DET` for the FRG table; `_fcall_va` and
# `_fcall_det` are sorted branch trees whose every leaf is a STATIC call into the table.
# MEASURED 2026-10-05 against a typed function pointer — a `ccall` through a `@cfunction` made per
# term type when the database is created, FunctionWrappers.jl's mechanism written here (the memos'
# Q3: no new dependency) — as decision 5's condition 2 asks, on an idle machine (warm daemon):
#   * call overhead, `==/2` on two atoms through the table of 9: tree 99 ns, pointer 170 ns, a
#     direct call 99 ns (the harness's own closure call is ~70 ns of each); on a synthetic table of
#     785 stubs, upstream's size: tree 74/70/108 ns, pointer 83/86/84 ns at indices 1/393/785;
#   * JET: no report for either; AllocCheck: the tree is seen through to every built-in, the pointer
#     is "dynamic dispatch" — opaque — and at run time it ALLOCATES 192 bytes a call, the tree 0;
#   * compile: 785 tree leaves 10.8 s, 785 `@cfunction` pointers 19.3 s.
# The tree is as fast as a direct call at V5's size and the only one the allocation gate can judge;
# the pointer was removed. User registration (`PL_register_foreign`) will need its own design.

# PORT: pl-ext.c foreigns
# DIVERGES: the ported entry only (upstream's table has 56, pl-ext.c:98-190).
"pl-ext.c's own registration table of FRG built-ins (`foreigns[]`): the ported entry."
const foreigns = (PL_extension("prolog_current_frame", 1, pl_prolog_current_frame, 0x00),)

# The PRED_DEF tables, in `initBuildIns`' order (pl-ext.c:499-572: prims, variant, trace); and the
# two dispatch tables. A comment, not a docstring, as for every module-level constant the global-state
# lint reads.
const _PRED_TABLES = (
    PL_predicates_from_arith, PL_predicates_from_prims, PL_predicates_from_variant,
    PL_predicates_from_trace
)
const _FOREIGN_VA = (
    PL_predicates_from_arith..., PL_predicates_from_prims..., PL_predicates_from_variant...,
    PL_predicates_from_trace...
)
const _FOREIGN_DET = foreigns

"A registration table's entries as `(name, arity, flags)` — what `registerBuiltins!` reads of them."
_extension_sigs(table::Tuple)::Vector{Tuple{String, Int, UInt8}} =       # (a tuple map: static)
    collect(
        Tuple{String, Int, UInt8}, map(e -> (e.predicate_name, e.arity, e.flags), table)
    )

# PORT: pl-ext.c builtin_pred_flags
"The predicate flags of a built-in registered with `regflags` (`PL_FA_*`) (pl-ext.c)."
function builtin_pred_flags(regflags::UInt8, defflags::UInt64)::UInt64
    flags = defflags | P_FOREIGN | HIDE_CHILDS | P_LOCKED
    (regflags & PL_FA_NOTRACE) != 0 && (flags &= ~TRACE_ME)
    (regflags & PL_FA_TRANSPARENT) != 0 && (flags |= P_TRANSPARENT)
    (regflags & PL_FA_NONDETERMINISTIC) != 0 && (flags |= P_NONDET)
    (regflags & PL_FA_VARARGS) != 0 && (flags |= P_VARARG)
    (regflags & PL_FA_CREF) != 0 && (flags |= P_FOREIGN_CREF)
    (regflags & PL_FA_ISO) != 0 && (flags |= P_ISO)
    (regflags & PL_FA_SIG_ATOMIC) != 0 && (flags |= P_SIG_ATOMIC)
    return flags
end

# PORT: pl-ext.c registerBuiltins as registerBuiltins!
# DIVERGES: no `signonly` (no saved-state signatures). `defflags` is 0 for every predicate:
# `TRACE_ME` is the debugger's, and `lookupProcedure` does not set it (src/pl-proc.jl), so a new
# procedure's flags are 0 — upstream asserts they equal `defflags`. `impl.foreign.function` and the
# supervisor's operand are the entry's index in its dispatch table, `first + k` for entry `k`.
"Register the entries `sigs` of a table, the first at dispatch index `first + 1`, in the `system` module (pl-ext.c)."
function registerBuiltins!(
    gd::PL_global_data{T}, sigs::Vector{Tuple{String, Int, UInt8}}, first::Int
)::Nothing where {T}
    m = MODULE_system(gd)
    for (k, (name, arity, regflags)) in enumerate(sigs)
        defflags = UInt64(0)                    # userpred ? TRACE_ME : 0 (see above)
        flags = builtin_pred_flags(regflags, defflags)
        proc = lookupProcedure(mk_sym(T, Symbol(name)), arity, m)
        def = proc.definition
        @assert def.flags == defflags "registerBuiltins!: $name/$arity is not a new procedure"
        def.flags = flags
        def.impl_foreign_function = first + k
        createForeignSupervisor!(def, first + k)
    end
    return nothing
end

# PORT: pl-ext.c initBuildIns as initBuildIns!
# DIVERGES: the tables ported (see `foreigns`, `_PRED_TABLES`); no `initProcedures` (nothing to
# reset in a new database) and no `setBuiltinPredicateProperties` (its procedures are created with
# the global data, src/pl-global.jl).
"Register the built-ins in the database whose global data is `gd` (pl-ext.c `initBuildIns`)."
function initBuildIns!(gd::PL_global_data{T})::Nothing where {T}
    registerBuiltins!(gd, _extension_sigs(foreigns), 0)
    first = 0
    for sigs in map(_extension_sigs, _PRED_TABLES)     # (a tuple map: no dynamic dispatch)
        registerBuiltins!(gd, sigs, first)      # REG_PLIST(prims), REG_PLIST(variant), …
        first += length(sigs)
    end
    @assert first == length(_FOREIGN_VA)
    return nothing
end

# ── the dispatch: generated trees ────────────────────────────────────────────────────────────────
# A sorted branch tree over the indices `lo:hi`, each leaf `leaf(k)` (built when the macro expands).
function _foreign_tree(i::Symbol, lo::Int, hi::Int, leaf)::Expr
    lo == hi && return leaf(lo)
    mid = (lo + hi) ÷ 2
    return :(
        if $i <= $mid
            $(_foreign_tree(i, lo, mid, leaf))
        else
            $(_foreign_tree(i, mid + 1, hi, leaf))
        end
    )
end

"The leaf of `_fcall_va`'s tree for entry `k`: its function, called statically, never inlined."
_va_leaf(k::Int)::Expr = :(return @noinline _FOREIGN_VA[$k].function_(ld, h0, ac, ctx))

"The leaf of `_fcall_det`'s tree for entry `k`: its function, on its arity's term references."
_det_leaf(k::Int)::Expr = :(
    return @noinline _FOREIGN_DET[$k].function_(
        ld, $((:(h0 + $j) for j in 0:(_FOREIGN_DET[k].arity - 1))...)
    )
)

"The tree over `_FOREIGN_VA`."
macro _fcall_va_body()
    return esc(_foreign_tree(:i, 1, length(_FOREIGN_VA), _va_leaf))
end

"The tree over `_FOREIGN_DET`."
macro _fcall_det_body()
    return esc(_foreign_tree(:i, 1, length(_FOREIGN_DET), _det_leaf))
end

"Call `PRED_DEF` built-in `i` with the `t0, ac, ctx` convention — the generated tree."
function _fcall_va(
    i::Int, ld::PL_local_data{T}, h0::term_t, ac::Int, ctx::control_t{T}
)::foreign_t where {T}
    @assert 1 <= i <= length(_FOREIGN_VA)
    @_fcall_va_body
end

"Call FRG built-in `i` on the term references from `h0` — the generated tree."
function _fcall_det(i::Int, ld::PL_local_data{T}, h0::term_t)::foreign_t where {T}
    @assert 1 <= i <= length(_FOREIGN_DET)
    @_fcall_det_body
end
