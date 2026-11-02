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
# repeat/0 (pl-prims.c), the first NDET entry, before fail/0 as upstream's (pl-ext.c:135); since MOD2
# context_module/1 (pl-modul.c; `META` is `PL_FA_TRANSPARENT`, pl-ext.c:90), after prolog_current_frame/1; since BOOTPRED
# `$garbage_collect/1` (pl-gc.c, after context_module/1 as pl-ext.c:168), thread_self/1 (pl-thread.c) and with_mutex/2
# (pl-mutex.c), the last two at the end of the table (pl-ext.c:186-187). Since PR1 abolish/1,2 (pl-proc.c, before
# repeat/0 as pl-ext.c:125-126), `$c_current_predicate`/2 (pl-ext.c:132, after them) and garbage_collect_clauses/0 (after `$garbage_collect/1` as pl-ext.c:171).
# Since RD1 read/1 and `$raw_read/1,2` (pl-read.c) after print/1 and read/2 after `$garbage_collect/1`, at upstream's places (pl-ext.c:116-118, 175).
"pl-ext.c's own registration table of FRG built-ins (`foreigns[]`): the ported entries."
const foreigns = (
    PL_extension("write_canonical", 1, pl_write_canonical, PL_FA_ISO),
    PL_extension("write", 1, pl_write, PL_FA_ISO),
    PL_extension("writeq", 1, pl_writeq, PL_FA_ISO),
    PL_extension("writeln", 1, pl_writeln, 0x00),
    PL_extension("print", 1, pl_print, 0x00),
    PL_extension("read", 1, pl_read, PL_FA_ISO),                    # RD1 (pl-ext.c:116)
    PL_extension("\$raw_read", 1, pl_raw_read, 0x00),                # RD1 (pl-ext.c:117)
    PL_extension("\$raw_read", 2, pl_raw_read2, 0x00),               # RD1 (pl-ext.c:118)
    PL_extension("abolish", 1, pl_abolish1, PL_FA_TRANSPARENT | PL_FA_ISO),     # META|ISO (PR1, pl-ext.c:125)
    PL_extension("abolish", 2, pl_abolish, PL_FA_TRANSPARENT),                  # META (PR1, pl-ext.c:126)
    PL_extension(                                                               # NDET|META (PR1, pl-ext.c:132)
        "\$c_current_predicate", 2, pl_current_predicate,
        PL_FA_TRANSPARENT | PL_FA_NONDETERMINISTIC
    ),
    PL_extension("repeat", 0, pl_repeat, PL_FA_NONDETERMINISTIC | PL_FA_ISO),
    PL_extension("fail", 0, pl_fail, PL_FA_ISO),
    PL_extension("true", 0, pl_true, PL_FA_ISO),
    PL_extension("\$fail", 0, pl_fail, PL_FA_NOTRACE),
    PL_extension("prolog_current_frame", 1, pl_prolog_current_frame, 0x00),
    PL_extension("context_module", 1, pl_context_module, PL_FA_TRANSPARENT),   # META (MOD2)
    PL_extension("\$garbage_collect", 1, pl_garbage_collect, 0x00),            # BOOTPRED (pl-ext.c:168)
    PL_extension("garbage_collect_clauses", 0, pl_garbage_collect_clauses0, 0x00),  # PR1 (pl-ext.c:171)
    PL_extension("read", 2, pl_read2, PL_FA_ISO),                   # RD1 (pl-ext.c:175)
    PL_extension("write", 2, pl_write2, PL_FA_ISO),
    PL_extension("writeln", 2, pl_writeln2, 0x00),
    PL_extension("writeq", 2, pl_writeq2, PL_FA_ISO),
    PL_extension("print", 2, pl_print2, 0x00),
    PL_extension("write_canonical", 2, pl_write_canonical2, PL_FA_ISO),
    PL_extension("thread_self", 1, pl_thread_self, PL_FA_ISO),      # BOOTPRED (pl-ext.c:186)
    PL_extension("with_mutex", 2, pl_with_mutex, PL_FA_TRANSPARENT | PL_FA_ISO)   # META|ISO (pl-ext.c:187)
)

# The PRED_DEF tables, in `initBuildIns`' order (pl-ext.c:501-574: arith, bag, comp, list, module, prims, variant,
# copyterm, prologflag, trace, pro, read, wic (LB3), file (S1), files, glob (LB2b), proc, srcfile (LB2), write, system, op, rec (D1: erase/1; D2: the recorded database), attvar — AV2, Y1; gvar — G1; dict — BOOTPRED (pl-ext.c:536-574: locale and debug, between gvar and dict, are left out); term,
# termhash and bisim, between op and attvar upstream, are not ported; strings (T2) is appended last); and the two dispatch tables. A comment, not a docstring,
# as for every module-level constant the global-state lint reads.
const _PRED_TABLES = (
    PL_predicates_from_atom, PL_predicates_from_arith, PL_predicates_from_bag,
    PL_predicates_from_comp, PL_predicates_from_list, PL_predicates_from_module,
    PL_predicates_from_prims, PL_predicates_from_variant, PL_predicates_from_copyterm,
    PL_predicates_from_prologflag,
    PL_predicates_from_trace, PL_predicates_from_pro, PL_predicates_from_read,
    PL_predicates_from_wic, PL_predicates_from_file, PL_predicates_from_files,
    PL_predicates_from_glob,
    PL_predicates_from_proc,
    PL_predicates_from_srcfile, PL_predicates_from_write,
    PL_predicates_from_redirect,
    PL_predicates_from_format,
    PL_predicates_from_system, PL_predicates_from_op, PL_predicates_from_rec,
    PL_predicates_from_attvar, PL_predicates_from_gvar, PL_predicates_from_dict,
    PL_predicates_from_strings,
    PL_predicates_from_error, PL_predicates_from_event,
    PL_predicates_from_termhash, PL_predicates_from_tabling, PL_predicates_from_wrap
)
const _FOREIGN_VA = (
    PL_predicates_from_atom..., PL_predicates_from_arith..., PL_predicates_from_bag...,
    PL_predicates_from_comp...,
    PL_predicates_from_list..., PL_predicates_from_module..., PL_predicates_from_prims...,
    PL_predicates_from_variant..., PL_predicates_from_copyterm...,
    PL_predicates_from_prologflag..., PL_predicates_from_trace...,
    PL_predicates_from_pro...,
    PL_predicates_from_read..., PL_predicates_from_wic..., PL_predicates_from_file...,
    PL_predicates_from_files..., PL_predicates_from_glob...,
    PL_predicates_from_proc..., PL_predicates_from_srcfile..., PL_predicates_from_write...,
    PL_predicates_from_redirect...,
    PL_predicates_from_format...,
    PL_predicates_from_system...,
    PL_predicates_from_op..., PL_predicates_from_rec..., PL_predicates_from_attvar...,
    PL_predicates_from_gvar..., PL_predicates_from_dict..., PL_predicates_from_strings...,
    PL_predicates_from_error..., PL_predicates_from_event...,
    PL_predicates_from_termhash..., PL_predicates_from_tabling...,
    PL_predicates_from_wrap...
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

# DIVERGES: a Julia helper for `initBuildIns!`'s REG_PLIST sequence, in upstream's order with one running
# dispatch index `first`. A recursive walk (`Base.tail`) specialises per table; a `map` over a tuple of 32
# or more entries (`_PRED_TABLES` has 34) takes Base's `Any32` method, whose result is not inferred (JET).
"Register the tables `tables` in order, the first at dispatch index `first + 1`; returns the next free index."
function _register_tables!(gd::PL_global_data{T}, first::Int, ::Tuple{})::Int where {T}
    return first
end
function _register_tables!(gd::PL_global_data{T}, first::Int, tables::Tuple)::Int where {T}
    sigs = _extension_sigs(tables[1])
    registerBuiltins!(gd, sigs, first)          # REG_PLIST(prims), REG_PLIST(variant), …
    return _register_tables!(gd, first + length(sigs), Base.tail(tables))
end

# PORT: pl-ext.c initBuildIns as initBuildIns!
# DIVERGES: the tables ported (see `foreigns`, `_PRED_TABLES`), in upstream's order. `initProcedures`
# creates `GD->procedures.dirty`, which the kernel creates with the global data (`procedures_dirty`,
# src/pl-global.jl). NOT PORTED: the extensions' binding loop (`bindExtensions`,
# `extensions_loaded`: no `PL_register_extensions`).
"Register the built-ins in the database whose global data is `gd` (pl-ext.c `initBuildIns`)."
function initBuildIns!(gd::PL_global_data{T})::Nothing where {T}
    registerBuiltins!(gd, _extension_sigs(foreigns), 0)
    # (a recursive walk over the tuple: a `map` over 32 or more entries is not inferred, see `_register_tables!`)
    first = _register_tables!(gd, 0, _PRED_TABLES)
    @assert first == length(_FOREIGN_VA)
    setBuiltinPredicateProperties!(gd)
    _boot_attvar!(gd)
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
    assertDefinition!(gd, ld, proc.definition, cl, CL_END) !== nothing ||   # no SSU clause: never refused
        error("_boot_clause!: the boot clause of $name is refused")
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
# uhook's body `Module:attr_unify_hook(AttVal, Value)` as attvar.pl writes it since MOD3a (a variable
# module: `B_FUNCTOR :/2` … `I_CALL1`, pl-comp.c:3443-3465; `call(Module:…)` before).
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
        _boot_term(:(:), T[Module, _boot_term(:attr_unify_hook, T[AttVal, Value])]),
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
# `meta_predicate call_residue_vars(0, -)` (attvar.pl:250-251) is `_boot_meta!`'s since MOD4: `S_MQUAL`
# qualifies the goal before the clause runs (run_crv/4 is not transparent).
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
# existence error of trigger/2, never a silent failure. `meta_predicate when(+, 0)` (when.pl:40-41) is
# `_boot_meta!`'s since MOD4: `S_MQUAL` qualifies the goal before the clause runs.
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
# Since MOD4 the declaration is `_boot_meta!`'s: `S_MQUAL` qualifies the goal on entry (pl-wam.c
# `m_qualify_argument`), so both clauses are upstream's (the second's body `Goal` is written
# `call(Goal)`, the same `I_USERCALL0` call).
"Define freeze/2 in the `system` module of `gd` as boot/attvar.pl defines it."
function _boot_freeze!(gd::PL_global_data{T}, ld::PL_local_data{T})::Nothing where {T}
    v = _boot_vars(T, 3)
    Var, Goal, Ignored = v[1], v[2], v[3]
    _boot_clause!(
        gd, ld, :freeze, T[Var, Goal],
        _boot_conj(T[_boot_term(Symbol("\$freeze"), T[Var, Goal]), mk_sym(T, :!)]),
        P_LOCKED
    )
    _boot_clause!(gd, ld, :freeze, T[Ignored, Goal], _boot_term(:call, T[Goal]), P_LOCKED)
    return nothing
end

# PORT: pl-ext.c setBuiltinPredicateProperties as setBuiltinPredicateProperties!
# NOT PORTED: every `LOOKUPPROC` but `equals2`, `dcall1` (the goal clauses' predicate, since
# V9e-2; `HIDE_CHILDS|TRACE_ME` cleared, `P_DYNAMIC|P_LOCKED` set), `catch3` (since V9f),
# `dwakeup1` (the VM's wakeup call, since AV3) and `arg3` (the slow route of the inline `arg/3`, since ARGINL) — the
# procedures nothing reads yet (`true/0`, `fail/0`, `is/2`, `==/2`, `\==/2`, …; since
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
    gd.procedures_arg3 = lookupProcedure(mk_sym(T, :arg), 3, m)   # LOOKUPPROC(arg3): the slow route of B_ARG_CF/B_ARG_VF
    # `:- dynamic user:exception/3` (boot/init.pl:945), here before init.pl is loaded: pl-gvar.c's
    # auto_define_gvar calls the hook through `PL_call_predicate` (G1, design D8; the repeat in init.pl is harmless)
    exception3 = lookupProcedure(mk_sym(T, :exception), 3, MODULE_user(gd))
    setDynamicDefinition!(exception3.definition, true)
    # PL_meta_predicate(PL_predicate(Name, Arity, "system"), Spec) (pl-ext.c:391-421 at the pin; the
    # `P_TRANSPARENT` half since MOD2, `P_META` and the masks since MOD4), in upstream's order. DIVERGES:
    # only the predicates the kernel defines — `PL_predicate` would create the others (an entry whose
    # predicate is not ported is skipped; it applies when that predicate is). The foreign ones get no
    # `S_MQUAL` (`createForeignSupervisor` is not chained, as upstream's): the masks are for
    # predicate_property/2, `P_TRANSPARENT` for their context module.
    for (name, arity, spec) in (
        ("assert", 1, ":"), ("asserta", 1, ":"), ("assertz", 1, ":"), ("assert", 2, ":-"),
        ("asserta", 2, ":-"), ("assertz", 2, ":-"), ("retract", 1, ":"),
        ("retractall", 1, ":"),
        ("clause", 2, ":?"), ("format", 2, "+:"), ("format", 3, "++:"),
        ("format_predicate", 2, "+0"), ("notrace", 1, "0"), ("with_mutex", 2, "+0"),
        ("with_output_to", 2, "+0"), ("thread_idle", 2, "0+"),
        ("prolog_frame_attribute", 3, "++:"), ("compile_predicates", 1, ":"),
        ("op", 3, "++:"),
        ("current_op", 3, "++:"), ("unwrap_predicate", 2, ":?"), ("prolog_listen", 2, "+:"),
        ("prolog_listen", 3, "+:+"), ("prolog_unlisten", 2, "+:"), ("with_tty_raw", 1, "0"),
        ("sig_atomic", 1, "0")
    )
        proc = isCurrentProcedure(sym_key(mk_sym(T, Symbol(name))), arity, m)
        proc === nothing || PL_meta_predicate(proc, spec)
    end
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
