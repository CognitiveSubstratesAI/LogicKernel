# UPSTREAM: swipl-devel src/pl-ext.c @ cbf4e1896275
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
# DIVERGES: the ported entries only, in upstream's order (upstream's table has 56, pl-ext.c:98-190);
# since R1e's write/1 family, write/1,2, writeq/1,2, writeln/1,2, print/1,2 and write_canonical/1,2;
# since V9f fail/0, true/0 and `$fail/0` (pl-prims.c; `!/0`, pl-pro.c's `pl_metacut`, is not yet); since NF4
# repeat/0 (pl-prims.c), the first NDET entry, before fail/0 as upstream's (pl-ext.c:135).
"pl-ext.c's own registration table of FRG built-ins (`foreigns[]`): the ported entries."
const foreigns = (
    PL_extension("write_canonical", 1, pl_write_canonical, PL_FA_ISO),
    PL_extension("write", 1, pl_write, PL_FA_ISO),
    PL_extension("writeq", 1, pl_writeq, PL_FA_ISO),
    PL_extension("writeln", 1, pl_writeln, 0x00),
    PL_extension("print", 1, pl_print, 0x00),
    PL_extension("repeat", 0, pl_repeat, PL_FA_NONDETERMINISTIC | PL_FA_ISO),
    PL_extension("fail", 0, pl_fail, PL_FA_ISO),
    PL_extension("true", 0, pl_true, PL_FA_ISO),
    PL_extension("\$fail", 0, pl_fail, PL_FA_NOTRACE),
    PL_extension("prolog_current_frame", 1, pl_prolog_current_frame, 0x00),
    PL_extension("write", 2, pl_write2, PL_FA_ISO),
    PL_extension("writeln", 2, pl_writeln2, 0x00),
    PL_extension("writeq", 2, pl_writeq2, PL_FA_ISO),
    PL_extension("print", 2, pl_print2, 0x00),
    PL_extension("write_canonical", 2, pl_write_canonical2, PL_FA_ISO)
)

# The PRED_DEF tables, in `initBuildIns`' order (pl-ext.c:501-574: arith, bag, comp, list, module, prims, variant,
# copyterm, prologflag, trace, pro, read, files, proc, write, system, op, attvar — AV2, Y1; rec, term, termhash and
# bisim, between op and attvar upstream, are not ported); and the two dispatch tables. A comment, not a docstring,
# as for every module-level constant the global-state lint reads.
const _PRED_TABLES = (
    PL_predicates_from_arith, PL_predicates_from_bag, PL_predicates_from_comp,
    PL_predicates_from_list, PL_predicates_from_module, PL_predicates_from_prims,
    PL_predicates_from_variant, PL_predicates_from_copyterm, PL_predicates_from_prologflag,
    PL_predicates_from_trace, PL_predicates_from_pro, PL_predicates_from_read,
    PL_predicates_from_files, PL_predicates_from_proc, PL_predicates_from_write,
    PL_predicates_from_system, PL_predicates_from_op, PL_predicates_from_attvar
)
const _FOREIGN_VA = (
    PL_predicates_from_arith..., PL_predicates_from_bag..., PL_predicates_from_comp...,
    PL_predicates_from_list..., PL_predicates_from_module..., PL_predicates_from_prims...,
    PL_predicates_from_variant..., PL_predicates_from_copyterm...,
    PL_predicates_from_prologflag..., PL_predicates_from_trace...,
    PL_predicates_from_pro...,
    PL_predicates_from_read..., PL_predicates_from_files...,
    PL_predicates_from_proc..., PL_predicates_from_write..., PL_predicates_from_system...,
    PL_predicates_from_op..., PL_predicates_from_attvar...
)
const _FOREIGN_DET = foreigns

"A registration table's entries as `(name, arity, flags)` — what `registerBuiltins!` reads of them."
# (generated, unrolled per entry: static; a `map` over a tuple of 32 or more entries — Base's `Any32`
# method — runs a loop with a dynamic call per entry, measured on pl-prims' table at 32, L1d step 7a)
@generated function _extension_sigs(table::Tuple)::Vector{Tuple{String, Int, UInt8}}
    ex = [
        :((table[$i].predicate_name, table[$i].arity, table[$i].flags))
        for i in 1:fieldcount(table)
    ]
    return :(Tuple{String, Int, UInt8}[$(ex...)])
end

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
# DIVERGES: the tables ported (see `foreigns`, `_PRED_TABLES`), in upstream's order. `initProcedures`
# creates `GD->procedures.dirty`, which the kernel creates with the global data (`procedures_dirty`,
# src/pl-global.jl). NOT PORTED: the extensions' binding loop (`bindExtensions`,
# `extensions_loaded`: no `PL_register_extensions`).
"Register the built-ins in the database whose global data is `gd` (pl-ext.c `initBuildIns`)."
function initBuildIns!(gd::PL_global_data{T})::Nothing where {T}
    registerBuiltins!(gd, _extension_sigs(foreigns), 0)
    first = 0
    for sigs in map(_extension_sigs, _PRED_TABLES)     # (a tuple map: no dynamic dispatch)
        registerBuiltins!(gd, sigs, first)      # REG_PLIST(prims), REG_PLIST(variant), …
        first += length(sigs)
    end
    @assert first == length(_FOREIGN_VA)
    setBuiltinPredicateProperties!(gd)
    _boot_catch3!(gd)
    _boot_cleanup!(gd)
    _boot_lists!(gd)
    _boot_bags!(gd)
    _boot_syspred!(gd)
    _boot_attvar!(gd)
    return nothing
end

# DIVERGES (no upstream function; user's unattended rule: behaviour as upstream's): boot/init.pl's
# `catch(_Goal, _Catcher, _Recover) :- '\$catch'.` (init.pl:564-565), compiled when the database is
# created — `'\$catch'` compiles to `I_CATCH I_EXITCATCH` (pl-comp.c), so the clause is upstream's
# `I_ENTER I_CATCH I_EXITCATCH I_EXIT`. R2 loads boot/init.pl, which defines it the same way. `'\$iso'`
# (init.pl:388) sets `P_ISO`; boot code is system code (`P_LOCKED`). NOT PORTED: `noprofile/1`, the
# meta-predicate declaration `catch(0, ?, 0)` (no module transparency until R2).
"Define `catch/3` in the `system` module of `gd` as boot/init.pl defines it."
function _boot_catch3!(gd::PL_global_data{T})::Nothing where {T}
    proc = gd.procedures_catch3
    def = proc.definition
    ld = PL_local_data{T}(gd)
    k = fresh_var_keys!(3)
    head = mk_expr(
        T, T[mk_sym(T, :catch), mk_var(T, k), mk_var(T, k + 1), mk_var(T, k + 2)]
    )
    cl = compileClause(gd, ld, head, mk_sym(T, Symbol("\$catch")), proc, MODULE_system(gd))
    cl === nothing && error("_boot_catch3!: catch/3's boot clause does not compile")
    assertDefinition!(gd, def, cl, CL_END)
    def.flags |= P_ISO | P_LOCKED
    return nothing
end

# DIVERGES (no upstream function; as `_boot_catch3!`): boot/init.pl's cleanup family
# (init.pl:689-698) and its `call/1..8` (init.pl:501-516), compiled when the database is created:
#     setup_call_catcher_cleanup(Setup, _Goal, _Catcher, _Cleanup) :- sig_atomic(Setup), '$call_cleanup'.
#     setup_call_cleanup(Setup, _Goal, _Cleanup) :- sig_atomic(Setup), '$call_cleanup'.
#     call_cleanup(_Goal, _Cleanup) :- '$call_cleanup'.
#     call(Goal) :- Goal.
#     call(Goal, A) :- call(Goal, A).        … to call/8
# `'$call_cleanup'` compiles to `I_CALLCLEANUP I_EXITCLEANUP` (pl-comp.c), which read the frame's
# arguments by the predicate's arity; `call/1` is what the cleanup handler calls a goal through
# that is a control construct (`call1`, pl-wam.c); `call/3` is what write_term's `portray_goal` is
# called through (`callPortray`, pl-write.c; since group F, D-0123, with `call/2..8` beside it, as
# init.pl defines them — each body compiles to `I_CALLN`). R2 loads boot/init.pl, which defines
# them all the same way. boot code is system code (`P_LOCKED`); `call/1..8` are ISO (init.pl:388
# and 493-499, `'$iso'`). NOT PORTED: the meta-predicate declarations (init.pl:360-386: no module
# transparency until R2), `noprofile/1`.
"Define the cleanup family and `call/1..8` in the `system` module of `gd` as boot/init.pl defines them."
function _boot_cleanup!(gd::PL_global_data{T})::Nothing where {T}
    ld = PL_local_data{T}(gd)
    k = fresh_var_keys!(8)
    v = T[mk_var(T, k + i) for i in 0:7]
    cleanup = mk_sym(T, Symbol("\$call_cleanup"))
    setup = mk_expr(
        T, T[mk_sym(T, Symbol(",")), mk_expr(T, T[mk_sym(T, :sig_atomic), v[1]]), cleanup]
    )
    _boot_clause!(gd, ld, :setup_call_catcher_cleanup, v[1:4], setup, P_LOCKED)
    _boot_clause!(gd, ld, :setup_call_cleanup, v[1:3], setup, P_LOCKED)
    _boot_clause!(gd, ld, :call_cleanup, v[1:2], cleanup, P_LOCKED)
    _boot_clause!(gd, ld, :call, v[1:1], v[1], P_ISO | P_LOCKED)
    for n in 2:8                                    # call(Goal, A, …) :- call(Goal, A, …).
        _boot_clause!(gd, ld, :call, v[1:n], _boot_term(:call, v[1:n]), P_ISO | P_LOCKED)
    end
    return nothing
end

"Compile `name(args…) :- body` (`body` nothing: a fact) into the `system` module of `gd`, and set the predicate's `flags`."
function _boot_clause!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, name::Symbol, args::Vector{T},
    body::Union{Nothing, T}, flags::UInt64
)::Nothing where {T}
    m = MODULE_system(gd)
    proc = lookupProcedure(mk_sym(T, name), length(args), m)
    cl = compileClause(
        gd, ld, mk_expr(T, pushfirst!(copy(args), mk_sym(T, name))), body, proc, m
    )
    cl === nothing && error("_boot_clause!: the boot clause of $name does not compile")
    assertDefinition!(gd, proc.definition, cl, CL_END)
    proc.definition.flags |= flags
    return nothing
end

"The compound `name(args…)` of a boot clause."
function _boot_term(name::Symbol, args::Vector{T})::T where {T}
    return mk_expr(T, pushfirst!(copy(args), mk_sym(T, name)))
end

"The conjunction `(g1, g2, …)` of a boot clause's body."
function _boot_conj(goals::Vector{T})::T where {T}
    c = goals[end]
    for i in (length(goals) - 1):-1:1
        c = _boot_term(Symbol(","), T[goals[i], c])
    end
    return c
end

"`(c -> a ; b)` of a boot clause's body."
function _boot_ite(::Type{T}, c::T, a::T, b::T)::T where {T}
    return _boot_term(Symbol(";"), T[_boot_term(Symbol("->"), T[c, a]), b])
end

"The list cell `[h|t]` of a boot clause."
function _boot_cons(::Type{T}, h::T, t::T)::T where {T}
    return mk_expr(T, T[mk_sym(T, LIST_CONS_NAME), h, t])
end

"`n` fresh variables for the clauses of a boot stand-in."
function _boot_vars(::Type{T}, n::Int)::Vector{T} where {T}
    k = fresh_var_keys!(n)
    v = Vector{T}(undef, n)
    for i in 1:n
        v[i] = mk_var(T, k + UInt64(i - 1))
    end
    return v
end

"`throw(error(formal, context(length/2, _)))`, as boot/init.pl's length/2 raises its errors."
function _boot_length_error(::Type{T}, formal::T, anon::T)::T where {T}
    indicator = _boot_term(:/, T[mk_sym(T, :length), mk_gnd(T, 2)])
    ball = _boot_term(:error, T[formal, _boot_term(:context, T[indicator, anon])])
    return _boot_term(:throw, T[ball])
end

# DIVERGES (no upstream function; as `_boot_catch3!`): boot/init.pl's length/2 (init.pl:4482-4519)
# and `'$append'/3` (init.pl:4426-4428), which boot/bags.pl's `alloc_bind_key_list/2` calls,
# compiled when the database is created:
#     length(List, Length) :-
#         var(Length), !,
#         '$skip_list'(Length0, List, Tail),
#         (   Tail == [] -> Length = Length0                    % +,-
#         ;   var(Tail) -> Tail \== Length,                     % avoid length(L,L)
#             '$length3'(Tail, Length, Length0)                 % -,-
#         ;   throw(error(type_error(list, List), context(length/2, _)))
#         ).
#     length(List, Length) :-
#         integer(Length), Length >= 0, !,
#         '$skip_list'(Length0, List, Tail),
#         (   Tail == [] -> Length = Length0                    % proper list
#         ;   var(Tail) -> Extra is Length-Length0, '$length'(Tail, Extra)
#         ;   throw(error(type_error(list, List), context(length/2, _)))
#         ).
#     length(_, Length) :-
#         integer(Length), !,
#         throw(error(domain_error(not_less_than_zero, Length), context(length/2, _))).
#     length(_, Length) :-
#         throw(error(type_error(integer, Length), context(length/2, _))).
#     '$length3'([], N, N).
#     '$length3'([_|List], N, N0) :- N1 is N0+1, '$length3'(List, N, N1).
#     '$append'([], L, L).
#     '$append'([H|T], L, [H|R]) :- '$append'(T, L, R).
# R2 loads boot/init.pl, which defines them the same way. boot code is system code (`P_LOCKED`);
# length/2 is ISO (init.pl:4480, `'$iso'`). DIVERGES: a database over a term type that cannot hold
# an `Int64` gets `'$append'/3` only — length/2's clauses contain integers.
"Define length/2, `'\$length3'/3` and `'\$append'/3` in the `system` module of `gd` as boot/init.pl defines them."
function _boot_lists!(gd::PL_global_data{T})::Nothing where {T}
    ld = PL_local_data{T}(gd)
    v = _boot_vars(T, 8)
    List, Length, Length0, Tail = v[1], v[2], v[3], v[4]
    Extra, Anon, N1, H = v[5], v[6], v[7], v[8]
    nil = mk_nil(T)
    append = Symbol("\$append")                         # (T: Tail, L: List, R: Extra)
    _boot_clause!(gd, ld, append, T[nil, List, List], nothing, P_LOCKED)
    _boot_clause!(
        gd, ld, append, T[_boot_cons(T, H, Tail), List, _boot_cons(T, H, Extra)],
        _boot_term(append, T[Tail, List, Extra]), P_LOCKED
    )
    # the other clauses hold the integers 0, 1 and 2: a term type that cannot hold an `Int64`
    # (the tests' `Term{BigInt}`) gets no length/2
    _holds_payload(T, Int64) || return nothing
    cut = mk_sym(T, :!)
    skip = _boot_term(Symbol("\$skip_list"), T[Length0, List, Tail])
    not_a_list = _boot_length_error(T,
        _boot_term(:type_error, T[mk_sym(T, :list), List]), Anon
    )
    proper = _boot_term(:(==), T[Tail, nil])
    same = _boot_term(:(=), T[Length, Length0])
    partial = _boot_term(:var, T[Tail])
    flags = P_ISO | P_LOCKED
    counting = _boot_conj(                              # -,-
        T[
            _boot_term(Symbol("\\=="), T[Tail, Length]),
            _boot_term(Symbol("\$length3"), T[Tail, Length, Length0])
        ]
    )
    _boot_clause!(
        gd, ld, :length, T[List, Length],
        _boot_conj(
            T[
                _boot_term(:var, T[Length]),
                cut,
                skip,
                _boot_ite(T, proper, same, _boot_ite(T, partial, counting, not_a_list))
            ]
        ),
        flags
    )
    extend = _boot_conj(
        T[
            _boot_term(:is, T[Extra, _boot_term(:-, T[Length, Length0])]),
            _boot_term(Symbol("\$length"), T[Tail, Extra])
        ]
    )
    _boot_clause!(
        gd, ld, :length, T[List, Length],
        _boot_conj(
            T[
                _boot_term(:integer, T[Length]),
                _boot_term(:>=, T[Length, mk_gnd(T, 0)]),
                cut,
                skip,
                _boot_ite(T, proper, same, _boot_ite(T, partial, extend, not_a_list))
            ]
        ),
        flags
    )
    negative = _boot_term(:domain_error, T[mk_sym(T, :not_less_than_zero), Length])
    _boot_clause!(
        gd, ld, :length, T[List, Length],
        _boot_conj(
            T[_boot_term(:integer, T[Length]), cut, _boot_length_error(T, negative, Anon)]
        ),
        flags
    )
    _boot_clause!(
        gd, ld, :length, T[List, Length],
        _boot_length_error(
            T, _boot_term(:type_error, T[mk_sym(T, :integer), Length]), Anon
        ),
        flags
    )
    length3 = Symbol("\$length3")                       # (N: Length, N0: Length0)
    _boot_clause!(gd, ld, length3, T[nil, Length, Length], nothing, P_LOCKED)
    _boot_clause!(
        gd, ld, length3, T[_boot_cons(T, Anon, List), Length, Length0],
        _boot_conj(
            T[
                _boot_term(:is, T[N1, _boot_term(:+, T[Length0, mk_gnd(T, 1)])]),
                _boot_term(length3, T[List, Length, N1])
            ]
        ),
        P_LOCKED
    )
    return nothing
end

# DIVERGES (no upstream function; as `_boot_catch3!`): boot/syspred.pl's numbervars/3
# (syspred.pl:1502-1511; L1d step 7a, audit D-0016), compiled when the database is created:
#     :- '$iso'((numbervars/3)).
#     numbervars(Term, From, To) :-
#         numbervars(Term, From, To, []).
# R2 loads boot/syspred.pl, which defines it the same way. boot code is system code (`P_LOCKED`);
# numbervars/3 is ISO (`'$iso'`).
"Define numbervars/3 in the `system` module of `gd` as boot/syspred.pl defines it."
function _boot_syspred!(gd::PL_global_data{T})::Nothing where {T}
    ld = PL_local_data{T}(gd)
    v = _boot_vars(T, 3)
    Term, From, To = v[1], v[2], v[3]
    _boot_clause!(
        gd, ld, :numbervars, T[Term, From, To],
        _boot_term(:numbervars, T[Term, From, To, mk_nil(T)]), P_ISO | P_LOCKED
    )
    return nothing
end

# DIVERGES (no upstream function; as `_boot_catch3!`): boot/bags.pl's findall/3,4
# (bags.pl:91-112), compiled when the database is created:
#     findall(Templ, Goal, List) :- findall(Templ, Goal, List, []).
#     findall(Templ, Goal, List, Tail) :-
#         cleanup_bag(findall_loop(Templ, Goal, List, Tail), '$destroy_findall_bag').
#     cleanup_bag(_Goal, _Cleanup) :- '$new_findall_bag', '$call_cleanup'.
#     findall_loop(Templ, Goal, List, Tail) :-
#         (   Goal, '$add_findall_bag'(Templ) ; '$collect_findall_bag'(List, Tail) ).
# and its bagof/3 and setof/3 (bags.pl:189-283), with their helpers, each clause as upstream's:
#     bagof(Templ, Goal0, List) :-
#         '$free_variable_set'(Templ^Goal0, Goal, Vars),
#         (   Vars == v
#         ->  findall(Templ, Goal, List), List \== []
#         ;   alloc_bind_key_list(Vars, VDict),
#             findall(Vars-Templ, Goal, Answers),
#             bind_bagof_keys(Answers, VDict),
#             keysort(Answers, Sorted),
#             pick(Sorted, Vars, List)
#         ).
#     alloc_bind_key_list(Vars, VDict) :-
#         functor(Vars, _, Count), length(List, Count), '$append'(List, _, VDict).
#     bind_bagof_keys([], _).
#     bind_bagof_keys([W-_|WTs], Vars) :- term_variables(W, Vars, _), bind_bagof_keys(WTs, Vars).
#     pick(Bags, Vars1, Bag1) :-
#         pick_first(Bags, Vars0, Bag0, RestBags), select_bag(RestBags, Vars0, Bag0, Vars1, Bag1).
#     select_bag([], Vars0, Bag0, Vars1, Bag1) :- !, Vars0 = Vars1, Bag0 = Bag1.
#     select_bag(_, Vars, Bag, Vars, Bag).
#     select_bag(RestBags, _, _, Vars1, Bag1) :- pick(RestBags, Vars1, Bag1).
#     pick_first([Vars-Templ|T0], Vars, [Templ|T], RestBag) :- pick_same(T0, Vars, T, RestBag).
#     pick_same([V-H|T0], Vars, [H|T], Bag) :- V == Vars, !, pick_same(T0, Vars, T, Bag).
#     pick_same(Bag, _, [], Bag).
#     setof(Templ, Goal0, List) :-
#         '$free_variable_set'(Templ^Goal0, Goal, Vars),
#         (   Vars == v
#         ->  findall(Templ, Goal, Answers), Answers \== [], sort(Answers, List)
#         ;   alloc_bind_key_list(Vars, VDict),
#             findall(Vars-Templ, Goal, Answers),
#             (   ground(Answers)
#             ->  sort(Answers, Sorted), pick(Sorted, Vars, List)
#             ;   bind_bagof_keys(Answers, VDict), sort(Answers, Sorted),
#                 pick(Sorted, Vars, Listu), sort(Listu, List)
#             )
#         ).
# R2 loads boot/bags.pl, which defines them the same way — in its module `'$bags'`, which exports
# findall/3,4, bagof/3 and setof/3. Until then they are `system`'s: the exported ones locked
# (system code; findall/3, bagof/3 and setof/3 ISO, bags.pl:76 `'$iso'`), and the module's PRIVATE
# predicates (`cleanup_bag/2`, `findall_loop/4`, `alloc_bind_key_list/2`, `bind_bagof_keys/2`,
# `pick/3`, `select_bag/5`, `pick_first/4`, `pick_same/4`) NOT locked, so `user` may define
# predicates of those names as it may in swipl — but a call to one that `user` does not define
# reaches `system`'s, where swipl raises an existence error (R2 checklist). The two goals
# findall/4 hands to `cleanup_bag/2` are written `system:Goal` here: upstream's meta-predicate
# declaration `cleanup_bag(0, 0)` qualifies them with the module of the clause (`'$bags'`), and
# unqualified they would be called in `user` — a `findall_loop/4` of the user's would be run.
# NOT PORTED: the meta-predicate declarations themselves (bags.pl:57-64: the goal of findall/3,
# bagof/3 and setof/3 runs in `user`), `noprofile/1`, findnsols/4,5 (`'$suspend_findall_bag'`,
# src/pl-bag.jl).
"Define findall/3,4, bagof/3 and setof/3 in the `system` module of `gd` as boot/bags.pl defines them."
function _boot_bags!(gd::PL_global_data{T})::Nothing where {T}
    ld = PL_local_data{T}(gd)
    k = fresh_var_keys!(4)
    Templ, Goal, List, Tail = mk_var(T, k),
    mk_var(T, k + 1), mk_var(T, k + 2),
    mk_var(T, k + 3)
    sys = mk_sym(T, :system)
    _boot_clause!(
        gd, ld, :findall, T[Templ, Goal, List],
        _boot_term(:findall, T[Templ, Goal, List, mk_nil(T)]), P_ISO | P_LOCKED
    )
    _boot_clause!(
        gd, ld, :findall, T[Templ, Goal, List, Tail],
        _boot_term(
            :cleanup_bag,
            T[
                _boot_term(
                    :(:), T[sys, _boot_term(:findall_loop, T[Templ, Goal, List, Tail])]
                ),
                _boot_term(:(:), T[sys, mk_sym(T, Symbol("\$destroy_findall_bag"))])
            ]
        ),
        P_LOCKED
    )
    _boot_clause!(
        gd, ld, :cleanup_bag, T[Goal, List],
        _boot_term(
            Symbol(","),
            T[mk_sym(T, Symbol("\$new_findall_bag")), mk_sym(T, Symbol("\$call_cleanup"))]
        ),
        UInt64(0)
    )
    _boot_clause!(
        gd, ld, :findall_loop, T[Templ, Goal, List, Tail],
        _boot_term(
            Symbol(";"),
            T[
                _boot_term(
                    Symbol(","), T[Goal, _boot_term(Symbol("\$add_findall_bag"), T[Templ])]
                ),
                _boot_term(Symbol("\$collect_findall_bag"), T[List, Tail])
            ]
        ),
        UInt64(0)
    )
    _boot_bagof!(gd, ld)
    return nothing
end

# DIVERGES (no upstream function; as `_boot_bags!`): boot/attvar.pl's wakeup clauses
# (attvar.pl:56-87), compiled when the database is created:
#     '$wakeup'([]).
#     '$wakeup'(wakeup(Attribute, Value, Rest)) :-
#         call_all_attr_uhooks(Attribute, Value), '$wakeup'(Rest).
#     call_all_attr_uhooks([], _).
#     call_all_attr_uhooks(att(Module, AttVal, Rest), Value) :-
#         uhook(Module, AttVal, Value), call_all_attr_uhooks(Rest, Value).
#     uhook(Module, AttVal, Value) :- Module:attr_unify_hook(AttVal, Value).
# The VM calls `'$wakeup'/1` (`PROCEDURE_dwakeup1`, pl-vmi.c `VMH(wakeup)`) with the wakeup list.
# R2 loads boot/attvar.pl in its module `'$attvar'`, which exports `'$wakeup'/1`; until then all
# three are `system`'s, `'$wakeup'/1` locked, the module's PRIVATE `call_all_attr_uhooks/2` and
# `uhook/3` NOT locked (as bags' helpers; main agent's decision Q2 (a), R2 checklist).
# DIVERGES: uhook's body is `call(Module:attr_unify_hook(AttVal, Value))` — the compiler has no
# colon body goal (`compileSubClause!`); call/1 reaches `stripModule_cells`, which takes `user`
# and `system` and refuses any other module (`NotPortedError`, R2): same answers for a hook in
# `user`.
# Since AV7 `uhook(freeze, Goal, Y)` (attvar.pl:76-84), unfreeze/1 and freeze/2: `_boot_freeze_uhook!`,
# `_boot_freeze!`.
"Define `'\$wakeup'/1` and its helpers in the `system` module of `gd` as boot/attvar.pl defines them."
function _boot_attvar!(gd::PL_global_data{T})::Nothing where {T}
    ld = PL_local_data{T}(gd)
    v = _boot_vars(T, 6)
    Attribute, Value, Rest, Module, AttVal, Ignored = v[1], v[2], v[3], v[4], v[5], v[6]
    nil = mk_nil(T)
    dwakeup = Symbol("\$wakeup")
    _boot_clause!(gd, ld, dwakeup, T[nil], nothing, P_LOCKED)
    _boot_clause!(
        gd, ld, dwakeup, T[_boot_term(:wakeup, T[Attribute, Value, Rest])],
        _boot_conj(
            T[
                _boot_term(:call_all_attr_uhooks, T[Attribute, Value]),
                _boot_term(dwakeup, T[Rest])
            ]
        ),
        P_LOCKED
    )
    _boot_clause!(gd, ld, :call_all_attr_uhooks, T[nil, Ignored], nothing, UInt64(0))
    _boot_clause!(
        gd, ld, :call_all_attr_uhooks, T[_boot_term(:att, T[Module, AttVal, Rest]), Value],
        _boot_conj(
            T[
                _boot_term(:uhook, T[Module, AttVal, Value]),
                _boot_term(:call_all_attr_uhooks, T[Rest, Value])
            ]
        ),
        UInt64(0)
    )
    _boot_freeze_uhook!(gd, ld)
    _boot_clause!(
        gd, ld, :uhook, T[Module, AttVal, Value],
        _boot_term(
            :call,
            T[_boot_term(:(:), T[Module, _boot_term(:attr_unify_hook, T[AttVal, Value])])]
        ),
        UInt64(0)
    )
    _boot_freeze!(gd, ld)
    _boot_when!(gd, ld)
    _boot_call_residue_vars!(gd, ld)
    return nothing
end

# DIVERGES (no upstream function; AV9, as `_boot_when!`): boot/attvar.pl's call_residue_vars/2 and
# run_crv/4 (attvar.pl:250-271), `system`'s and locked until R2 loads boot/attvar.pl in module
# `'$attvar'` (design Q2 (a)), so an error's context names `system:run_crv/4` where upstream's names
# `'$attvar':run_crv/4` (row cr11 pins both):
#     call_residue_vars(Goal, Vars) :-
#         prolog_current_choice(Chp),
#         setup_call_cleanup('$call_residue_vars_start', run_crv(Goal, Chp, Vars, Det),
#                            '$call_residue_vars_end'),
#         (   Det == true -> ! ; true ).
#     call_residue_vars(_, _) :- fail.
#     run_crv(Goal, Chp, Vars, Det) :- call(Goal), deterministic(Det),
#         '$attvars_after_choicepoint'(Chp, Vars).
# No `meta_predicate call_residue_vars(0, -)` before R2: the goal is called unqualified (call/1 takes the
# context module, `user`, design Q4 (a)).
"Define call_residue_vars/2 and run_crv/4 in the `system` module of `gd` as boot/attvar.pl defines them."
function _boot_call_residue_vars!(
    gd::PL_global_data{T}, ld::PL_local_data{T}
)::Nothing where {T}
    v = _boot_vars(T, 6)
    Goal, Vars, Chp, Det, A1, A2 = v[1], v[2], v[3], v[4], v[5], v[6]
    _boot_clause!(
        gd, ld, :call_residue_vars, T[Goal, Vars],
        _boot_conj(
            T[
                _boot_term(:prolog_current_choice, T[Chp]),
                _boot_term(
                    :setup_call_cleanup,
                    T[
                        mk_sym(T, Symbol("\$call_residue_vars_start")),
                        _boot_term(:run_crv, T[Goal, Chp, Vars, Det]),
                        mk_sym(T, Symbol("\$call_residue_vars_end"))
                    ]
                ),
                _boot_term(
                    Symbol(";"),
                    T[
                        _boot_term(
                            Symbol("->"),
                            T[
                                _boot_term(Symbol("=="), T[Det, mk_sym(T, Symbol("true"))]),
                                mk_sym(T, :!)
                            ]
                        ),
                        mk_sym(T, Symbol("true"))
                    ]
                )
            ]
        ),
        P_LOCKED
    )
    _boot_clause!(gd, ld, :call_residue_vars, T[A1, A2], mk_sym(T, :fail), P_LOCKED)
    _boot_clause!(
        gd, ld, :run_crv, T[Goal, Chp, Vars, Det],
        _boot_conj(
            T[
                _boot_term(:call, T[Goal]),
                _boot_term(:deterministic, T[Det]),
                _boot_term(Symbol("\$attvars_after_choicepoint"), T[Chp, Vars])
            ]
        ),
        P_LOCKED
    )
    return nothing
end

# DIVERGES (no upstream function; AV8, as `_boot_freeze!`): library/when.pl's when/2 and the two
# trigger_first/2 clauses that need no attribute hook (when.pl:84-86, 98-100, 104-105), `system`'s and
# locked until R2 loads library(when) (design Q2 (a)):
#     when(Condition, Goal) :- '$eval_when_condition'(Condition, Optimised), trigger_first(Optimised, Goal).
#     trigger_first(true, Goal) :- !, call(Goal).
#     trigger_first(Cond, Goal) :- trigger(Cond, Goal).
# when.pl:101-103's `trigger_first(nonvar(X), Goal)` and trigger/2 wait for R2 (their wakeup is module
# `when`'s attr_unify_hook/2): a condition still pending after `'$eval_when_condition'/2` raises the
# existence error of trigger/2, never a silent failure. No `meta_predicate when(+, 0)` before R2: the
# goal is called unqualified (call/1 takes the context module, `user`, design Q4 (a)).
"Define when/2 in the `system` module of `gd` as library/when.pl defines it, up to the conditions that are already true."
function _boot_when!(gd::PL_global_data{T}, ld::PL_local_data{T})::Nothing where {T}
    v = _boot_vars(T, 3)
    Condition, Goal, Optimised = v[1], v[2], v[3]
    _boot_clause!(
        gd, ld, :when, T[Condition, Goal],
        _boot_conj(
            T[
                _boot_term(Symbol("\$eval_when_condition"), T[Condition, Optimised]),
                _boot_term(:trigger_first, T[Optimised, Goal])
            ]
        ),
        P_LOCKED
    )
    _boot_clause!(
        gd, ld, :trigger_first, T[mk_sym(T, Symbol("true")), Goal],
        _boot_conj(T[mk_sym(T, :!), _boot_term(:call, T[Goal])]), UInt64(0)
    )
    _boot_clause!(
        gd, ld, :trigger_first, T[Condition, Goal],
        _boot_term(:trigger, T[Condition, Goal]),
        UInt64(0)
    )
    return nothing
end

# DIVERGES (no upstream function; AV7, as `_boot_attvar!`): boot/attvar.pl's freeze clauses
# (attvar.pl:76-84, 98-102), `system`'s until R2 (design Q2 (a)); `uhook(freeze, …)` is defined before
# the general `uhook/3` clause, as in the file:
#     uhook(freeze, Goal, Y) :- !,
#         ( attvar(Y) -> ( get_attr(Y, freeze, G2) -> put_attr(Y, freeze, '$and'(G2, Goal))
#                        ; put_attr(Y, freeze, Goal) )
#         ; unfreeze(Goal) ).
#     unfreeze('$and'(A,B)) :- !, unfreeze(A), unfreeze(B).
#     unfreeze(Goal) :- Goal.
"Define `uhook(freeze, …)` and unfreeze/1 in the `system` module of `gd` as boot/attvar.pl defines them."
function _boot_freeze_uhook!(gd::PL_global_data{T}, ld::PL_local_data{T})::Nothing where {T}
    v = _boot_vars(T, 5)
    Goal, Y, G2, A, B = v[1], v[2], v[3], v[4], v[5]
    fz = mk_sym(T, :freeze)
    cut = mk_sym(T, :!)
    dand = Symbol("\$and")
    append = _boot_ite(
        T, _boot_term(:get_attr, T[Y, fz, G2]),
        _boot_term(:put_attr, T[Y, fz, _boot_term(dand, T[G2, Goal])]),
        _boot_term(:put_attr, T[Y, fz, Goal])
    )
    _boot_clause!(
        gd, ld, :uhook, T[fz, Goal, Y],
        _boot_conj(
            T[
                cut,
                _boot_ite(
                    T, _boot_term(:attvar, T[Y]), append, _boot_term(:unfreeze, T[Goal])
                )
            ]
        ),
        UInt64(0)
    )
    _boot_clause!(
        gd, ld, :unfreeze, T[_boot_term(dand, T[A, B])],
        _boot_conj(T[cut, _boot_term(:unfreeze, T[A]), _boot_term(:unfreeze, T[B])]),
        UInt64(0)
    )
    _boot_clause!(gd, ld, :unfreeze, T[Goal], _boot_term(:call, T[Goal]), UInt64(0))
    return nothing
end

# DIVERGES (no upstream function; AV7): boot/attvar.pl's freeze/2 (attvar.pl:109-116), `system`'s and
# locked until R2 (design Q2 (a)):
#     :- meta_predicate freeze(?, 0).
#     freeze(Var, Goal) :- '$freeze'(Var, Goal), !.
#     freeze(_, Goal) :- Goal.
# The meta-argument qualification (no `meta_predicate` before R2, design Q4 (a)) is written into the
# first clause as `$suspend` qualifies its goal (pl-attvar.c:1133-1143): a goal that is not `_:_` gets
# the context module, which is `user` until contextModule is ported (`stripModule_cells`):
#     freeze(Var, Goal0) :- ( nonvar(Goal0), Goal0 = _:_ -> Goal = Goal0 ; Goal = user:Goal0 ),
#                           '$freeze'(Var, Goal), !.
# The second clause calls the goal unqualified (call/1 takes the same context module, `user`).
"Define freeze/2 in the `system` module of `gd` as boot/attvar.pl defines it, its goal qualified (Q4 (a))."
function _boot_freeze!(gd::PL_global_data{T}, ld::PL_local_data{T})::Nothing where {T}
    v = _boot_vars(T, 6)
    Var, Goal0, Goal, M, G, Ignored = v[1], v[2], v[3], v[4], v[5], v[6]
    qualified = _boot_conj(
        T[
            _boot_term(:nonvar, T[Goal0]),
            _boot_term(:(=), T[Goal0, _boot_term(:(:), T[M, G])])
        ]
    )
    qualify = _boot_ite(
        T, qualified, _boot_term(:(=), T[Goal, Goal0]),
        _boot_term(:(=), T[Goal, _boot_term(:(:), T[mk_sym(T, :user), Goal0])])
    )
    _boot_clause!(
        gd, ld, :freeze, T[Var, Goal0],
        _boot_conj(
            T[qualify, _boot_term(Symbol("\$freeze"), T[Var, Goal]), mk_sym(T, :!)]
        ),
        P_LOCKED
    )
    _boot_clause!(gd, ld, :freeze, T[Ignored, Goal0], _boot_term(:call, T[Goal0]), P_LOCKED)
    return nothing
end

"Define bagof/3, setof/3 and their helpers (see `_boot_bags!`)."
function _boot_bagof!(gd::PL_global_data{T}, ld::PL_local_data{T})::Nothing where {T}
    v = _boot_vars(T, 12)
    Templ, Goal0, List, Goal, Vars, VDict = v[1], v[2], v[3], v[4], v[5], v[6]
    Answers, Sorted, Listu, A1, A2, A3 = v[7], v[8], v[9], v[10], v[11], v[12]
    nil = mk_nil(T)
    cut = mk_sym(T, :!)
    none = UInt64(0)
    fvs = _boot_term(
        Symbol("\$free_variable_set"), T[_boot_term(:^, T[Templ, Goal0]), Goal, Vars]
    )
    no_free = _boot_term(:(==), T[Vars, mk_sym(T, :v)])
    alloc = _boot_term(:alloc_bind_key_list, T[Vars, VDict])
    keyed = _boot_term(:findall, T[_boot_term(:-, T[Vars, Templ]), Goal, Answers])
    bind = _boot_term(:bind_bagof_keys, T[Answers, VDict])
    plain = _boot_conj(
        T[
            _boot_term(:findall, T[Templ, Goal, List]),
            _boot_term(Symbol("\\=="), T[List, nil])
        ]
    )
    grouped = _boot_conj(
        T[
            alloc, keyed, bind, _boot_term(:keysort, T[Answers, Sorted]),
            _boot_term(:pick, T[Sorted, Vars, List])
        ]
    )
    _boot_clause!(
        gd, ld, :bagof, T[Templ, Goal0, List],
        _boot_conj(T[fvs, _boot_ite(T, no_free, plain, grouped)]), P_ISO | P_LOCKED
    )
    set = _boot_conj(
        T[
            _boot_term(:findall, T[Templ, Goal, Answers]),
            _boot_term(Symbol("\\=="), T[Answers, nil]),
            _boot_term(:sort, T[Answers, List])
        ]
    )
    ground_keys = _boot_conj(
        T[_boot_term(:sort, T[Answers, Sorted]), _boot_term(:pick, T[Sorted, Vars, List])]
    )
    bound_keys = _boot_conj(
        T[
            bind, _boot_term(:sort, T[Answers, Sorted]),
            _boot_term(:pick, T[Sorted, Vars, Listu]), _boot_term(:sort, T[Listu, List])
        ]
    )
    sets = _boot_conj(
        T[
            alloc,
            keyed,
            _boot_ite(T, _boot_term(:ground, T[Answers]), ground_keys, bound_keys)
        ]
    )
    _boot_clause!(
        gd, ld, :setof, T[Templ, Goal0, List],
        _boot_conj(T[fvs, _boot_ite(T, no_free, set, sets)]), P_ISO | P_LOCKED
    )
    # alloc_bind_key_list(Vars, VDict) (A1: _, A2: Count, A3: _)
    _boot_clause!(
        gd, ld, :alloc_bind_key_list, T[Vars, VDict],
        _boot_conj(
            T[
                _boot_term(:functor, T[Vars, A1, A2]),
                _boot_term(:length, T[List, A2]),
                _boot_term(Symbol("\$append"), T[List, A3, VDict])
            ]
        ),
        none
    )
    # bind_bagof_keys/2 (A1: W, A2: _, A3: WTs, Templ: _)
    _boot_clause!(gd, ld, :bind_bagof_keys, T[nil, A1], nothing, none)
    _boot_clause!(
        gd, ld, :bind_bagof_keys, T[_boot_cons(T, _boot_term(:-, T[A1, A2]), A3), Vars],
        _boot_conj(
            T[
                _boot_term(:term_variables, T[A1, Vars, Templ]),
                _boot_term(:bind_bagof_keys, T[A3, Vars])
            ]
        ),
        none
    )
    # pick(Bags, Vars1, Bag1) (Answers: Bags, Vars: Vars1, List: Bag1, A1: Vars0, A2: Bag0,
    # A3: RestBags)
    _boot_clause!(
        gd, ld, :pick, T[Answers, Vars, List],
        _boot_conj(
            T[
                _boot_term(:pick_first, T[Answers, A1, A2, A3]),
                _boot_term(:select_bag, T[A3, A1, A2, Vars, List])
            ]
        ),
        none
    )
    # select_bag/5 (A1: Vars0, A2: Bag0, Vars: Vars1, List: Bag1, A3: RestBags or _)
    _boot_clause!(
        gd, ld, :select_bag, T[nil, A1, A2, Vars, List],
        _boot_conj(T[cut, _boot_term(:(=), T[A1, Vars]), _boot_term(:(=), T[A2, List])]),
        none
    )
    _boot_clause!(gd, ld, :select_bag, T[A3, Vars, List, Vars, List], nothing, none)
    _boot_clause!(
        gd, ld, :select_bag, T[A3, A1, A2, Vars, List],
        _boot_term(:pick, T[A3, Vars, List]), none
    )
    # pick_first([Vars-Templ|T0], Vars, [Templ|T], RestBag) (A1: T0, A2: T, A3: RestBag)
    _boot_clause!(
        gd, ld, :pick_first,
        T[
            _boot_cons(T, _boot_term(:-, T[Vars, Templ]), A1),
            Vars,
            _boot_cons(T, Templ, A2),
            A3
        ],
        _boot_term(:pick_same, T[A1, Vars, A2, A3]), none
    )
    # pick_same([V-H|T0], Vars, [H|T], Bag) (Goal: V, Templ: H, A1: T0, A2: T, A3: Bag)
    _boot_clause!(
        gd, ld, :pick_same,
        T[
            _boot_cons(T, _boot_term(:-, T[Goal, Templ]), A1),
            Vars,
            _boot_cons(T, Templ, A2),
            A3
        ],
        _boot_conj(
            T[
                _boot_term(:(==), T[Goal, Vars]), cut,
                _boot_term(:pick_same, T[A1, Vars, A2, A3])
            ]
        ),
        none
    )
    _boot_clause!(gd, ld, :pick_same, T[A3, A1, nil, A3], nothing, none)
    return nothing
end

# PORT: pl-ext.c setBuiltinPredicateProperties as setBuiltinPredicateProperties!
# NOT PORTED: every `LOOKUPPROC` but `equals2`, `dcall1` (the goal clauses' predicate, since
# V9e-2; `HIDE_CHILDS|TRACE_ME` cleared, `P_DYNAMIC|P_LOCKED` set), `catch3` (since V9f) and
# `dwakeup1` (the VM's wakeup call, since AV3) — the
# procedures nothing reads yet (`true/0`, `fail/0`, `is/2`, `==/2`, `\==/2`, `arg/3`, …; since
# 10.1.19 `'$tbl_reset'/6` and `call_continuation/1`: tabling and continuations), each when
# its first reader is ported;
# `$c_call_prolog/0` is created with the global data (src/pl-global.jl); `heartbeat/0`; `call/1`'s
# flags and the meta-predicate declarations (no meta-call, V9).
"Cache the system procedures the VM calls directly in the global data (pl-ext.c)."
function setBuiltinPredicateProperties!(gd::PL_global_data{T})::Nothing where {T}
    m = MODULE_system(gd)
    gd.procedures_equals2 = lookupProcedure(mk_sym(T, :(=)), 2, m)   # LOOKUPPROC(equals2)
    # ATOM_dcall's text is `<meta-call>` (src/ATOMS: `A dcall "<meta-call>"`), not `$call`
    gd.procedures_dcall1 = lookupProcedure(mk_sym(T, Symbol("<meta-call>")), 1, m)  # LOOKUPPROC(dcall1)
    d = gd.procedures_dcall1.definition                 # allow debugging in call/1
    d.flags &= ~(HIDE_CHILDS | TRACE_ME)
    d.flags |= P_DYNAMIC | P_LOCKED
    gd.procedures_catch3 = lookupProcedure(mk_sym(T, :catch), 3, m)   # LOOKUPPROC(catch3)
    gd.procedures_dwakeup1 = lookupProcedure(mk_sym(T, Symbol("\$wakeup")), 1, m)  # LOOKUPPROC(dwakeup1)
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

"Whether FRG entry `k` is non-deterministic (`PL_FA_NONDETERMINISTIC`): its function takes the context last."
_frg_ndet(k::Int)::Bool = (_FOREIGN_DET[k].flags & PL_FA_NONDETERMINISTIC) != 0

"The leaf of `_fcall_det`'s tree for entry `k`: its function, on its arity's term references."
_det_leaf(k::Int)::Expr =
    if _frg_ndet(k)
        :(error($("_fcall_det: FRG entry $k is non-deterministic (_fcall_ndet)")))
    else
        :(
            return @noinline _FOREIGN_DET[$k].function_(
                ld, $((:(h0 + $j) for j in 0:(_FOREIGN_DET[k].arity - 1))...)
            )
        )
    end

# ORIGINAL (NF4): the non-deterministic `a1, a2, …` call, `(*f)(h0, h0+1, …, &FNDET_CONTEXT)` (pl-vmi.c FCALL_NDETN).
# `h0 == 0` is discardForeignFrame's FRG_CUTTED call, whose arguments are all 0 (pl-wam.c CALL_FCUTTED).
"The leaf of `_fcall_ndet`'s tree for entry `k`: its function, on its arity's term references and the context."
_ndet_leaf(k::Int)::Expr =
    if !_frg_ndet(k)
        :(error($("_fcall_ndet: FRG entry $k is deterministic (_fcall_det)")))
    else
        :(
            return @noinline _FOREIGN_DET[$k].function_(
                ld, $((:(h0 == 0 ? 0 : h0 + $j) for j in 0:(_FOREIGN_DET[k].arity - 1))...),
                ctx
            )
        )
    end

"The tree over `_FOREIGN_VA`."
macro _fcall_va_body()
    return esc(_foreign_tree(:i, 1, length(_FOREIGN_VA), _va_leaf))
end

"The tree over `_FOREIGN_DET`."
macro _fcall_det_body()
    return esc(_foreign_tree(:i, 1, length(_FOREIGN_DET), _det_leaf))
end

"The tree over `_FOREIGN_DET`'s non-deterministic entries (NF4)."
macro _fcall_ndet_body()
    return esc(_foreign_tree(:i, 1, length(_FOREIGN_DET), _ndet_leaf))
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

"Call non-deterministic FRG built-in `i` on the term references from `h0` (0: all 0) and `ctx` — the generated tree."
function _fcall_ndet(
    i::Int, ld::PL_local_data{T}, h0::term_t, ctx::control_t{T}
)::foreign_t where {T}
    @assert 1 <= i <= length(_FOREIGN_DET)
    @_fcall_ndet_body
end
