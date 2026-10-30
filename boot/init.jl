# UPSTREAM: swipl-devel boot/init.pl @ cbf4e1896275
# CLASS: design
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE MINIMAL LOADER (R1f; user, 2026-10-07: "1a 2a 3a 4 yes" — the workspace's
# docs/research/logickernel-step-memos/R1f_plan.md). boot/init.pl's consult path, in Julia: the Prolog
# that runs it (load_files/2, `'$consult_file'`, `'$compile_term'`, `'$execute_directive_3'`,
# `'$pattr_directive'`, `'$store_clause'`) is R2's, so this renders its steps over the kernel's C
# ports — `read_clause` (src/pl-read.jl), `'$record_clause'/3` (src/pl-comp.jl), the source files
# (src/pl-srcfile.jl), `'$set_predicate_attribute'/3` (src/pl-proc.jl) — and returns the messages
# upstream would print (`print_message/2`, R2), which the differential compares with swipl's.
# A Julia API only (decision 3a): `load_file!(gd, ld, path)`. REFUSED (`NotPortedError`,
# decision 4): DCG rules (`-->`), `term_expansion/2,4` or `goal_expansion/2,4` defined, `:- module`,
# `:- use_module`, `:- include`, `:- initialization`, `:- encoding`, `:- ensure_loaded`, conditional
# compilation (`:- if/elif/else/endif`, `'$source_term'`'s); a reconsult; a directive that needs the
# meta-call (`;`, `->`, `*->`, `\+`, `call/N`, a variable goal, the inlined `true`/`fail`/`!`: V9).

# PORT: init.pl load_files as load_file!
# DIVERGES: one file, consulted into `user`, from its path (no search, no extensions, no
# `load_files/2` options, no "already loaded" check: a reconsult is refused by `startConsult`); the
# source file's name is the absolute path, as swipl's id is; the loop is `'$consult_file'`'s —
# `'$start_consult'`, read a clause (`read_clause`, with `variable_names(Bindings)` — of
# `'$term_in_file'`'s options the one the kernel's reader honours), `b_setval('$variable_names',
# Bindings)` (the local data's `variable_names`: the compiler's warnings name their variables from
# it), compile it (`'$compile_term'`), each with its bindings undone after it (the failure-driven
# loop), `'$end_consult'`, the stream closed whatever happens (`setup_call_cleanup`). An exception that is not `error(_,_)` ENDS the load, as in swipl
# (consult/1 raises it); it is returned, not raised.
"""
    load_file!(gd, ld, path) -> (status, ball, messages)

Consult the Prolog file `path` into the `user` module of the database `gd` (boot/init.pl):
`status` `:ok`, or `:exception` with the exception `ball` that ended the load; `messages` are the
`(kind, message)` pairs swipl would print — `goal_failed(directive, M:G)`, errors, singletons,
`discontiguous(…)`, syntax errors — in order.
"""
function load_file!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, path::AbstractString
)::Tuple{Symbol, Union{Nothing, T}, Vector{Tuple{Symbol, T}}} where {T}
    n0 = length(ld.messages)
    file = mk_sym(T, Symbol(abspath(path)))
    status, ball = :ok, nothing

    sf = lookupSourceFile(gd, file, true)::SourceFile{T}        # '$start_consult'(Id, Modified)
    sf.mtime = mtime(path)
    sf.isfile = true
    startConsult(sf)
    releaseSourceFile(sf)

    io = open(path, "r")
    s = Sopen_julia_io(io, "r", true)
    s === nothing && error("load_file!: Sopen_julia_io")
    setFileNameStream(gd, s, file)
    old_source = ld.modules_source
    ld.modules_source = MODULE_user(gd).index                  # '$set_source_module'(user)
    try
        while true                                              # '$load_file'/… loop
            fid = PL_open_foreign_frame(ld)
            t = PL_new_term_ref(ld)
            bindings = PL_new_term_ref(ld)
            options = PL_new_term_ref(ld)                       # [variable_names(Bindings)]
            vn = PL_new_term_ref(ld)
            PL_cons_functor(ld, vn, _err_functor(ld, :variable_names, 1), bindings)
            PL_put_nil(ld, options)
            PL_cons_list(ld, options, vn, options)
            ok = read_clause(gd, ld, s, t, options)
            ld.variable_names = bindings                        # b_setval('$variable_names', …)
            if !ok || _init_is(ld, t, :end_of_file, 0)
                ld.variable_names = 0
                PL_discard_foreign_frame(ld, fid)
                break
            end
            if !valid_term(ld, t)                               # '$valid_term'(Term): `[]`
                ld.variable_names = 0
                PL_discard_foreign_frame(ld, fid)
                continue
            end
            r, b = compile_term!(gd, ld, t, file)
            ld.variable_names = 0                               # (b_setval: undone on backtracking)
            PL_discard_foreign_frame(ld, fid)                   # the failure-driven loop
            if r === :exception
                status, ball = :exception, b
                break
            end
        end
    finally
        ld.variable_names = 0
        ld.modules_source = old_source
        sf2 = lookupSourceFile(gd, file, false)::SourceFile{T} # '$end_consult'(Id)
        endConsult(sf2)
        releaseSourceFile(sf2)
        setFileNameStream(gd, s, nothing)
        Sclose(s)
        ld.read_source = source_location{T}(nothing, IOPOS())
    end
    return (status, ball, ld.messages[(n0 + 1):end])
end

# ORIGINAL (f3b-3b): where a term leaves the loader — the ball `load_file!` returns, a refusal's
# culprit (`NotPortedError`, `CallableTypeError`) — it is read off the cells once (`export_cells`),
# as the messages are (`printMessage`).
"The term `t` references, exported off the cells (the loader's API ball, a refusal's culprit)."
_init_export(ld::PL_local_data{T}, t::term_t) where {T} =
    export_cells(ld, cell_export{T}(), -(t + 1))::T

# PORT: init.pl $valid_term as valid_term
# DIVERGES: the term reference read through the FLI; the message goes to `printMessage`.
"""
Should the term read into `t` be compiled (boot/init.pl)? Not `[]`; a variable is — after its error
is printed — and `'\$compile_term'` then raises it, ending the load.
"""
function valid_term(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    if PL_is_variable(ld, t)
        printMessage(ld, :error, _init_error(ld, :instantiation_error))
        return true
    end
    return !PL_get_nil(ld, t)                           # Term \== []
end

# Does term reference `t` hold the compound `name/arity` — or, for arity 0, the atom `name`?
function _init_is(ld::PL_local_data{T}, t::term_t, name::Symbol, arity::Int)::Bool where {T}
    if arity == 0
        a = PL_get_atom(ld, t)
        return a !== nothing && sym_key(a) == sym_key(mk_sym(T, name))
    end
    return PL_is_functor(ld, t, mk_sym(T, name), arity)
end

# PORT: init.pl $compile_term as compile_term!
# DIVERGES: `'$expanded_term'` is the identity (no `term_expansion`/`goal_expansion` defined — when
# one is, refused — and a DCG rule `-->` refused: `dcg_translate_rule` is boot/dcg.pl's, R2);
# `'$source_location'(File, Line):Term` never arises (read_clause makes no layout). Returns
# `(:ok, nothing)`, or `(:exception, Ball)` for an exception that ends the load (exported).
"Compile the term read into `t`: a directive, or a clause stored for the file `file` (boot/init.pl)."
function compile_term!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, file::T
)::Tuple{Symbol, Union{Nothing, T}} where {T}
    user = MODULE_user(gd)
    for (n, a) in ((:term_expansion, 2), (:term_expansion, 4), (:goal_expansion, 2),
        (:goal_expansion, 4))
        p = isCurrentProcedure(sym_key(mk_sym(T, n)), a, user)
        p !== nothing && _impl_any_defined(p.definition) &&
            throw(
                NotPortedError{T}(
                    _init_export(ld, t), "term_expansion/goal_expansion (expand_term/2)",
                    "R2"
                )
            )
    end
    _init_is(ld, t, Symbol("-->"), 2) &&
        throw(
            NotPortedError{T}(
                _init_export(ld, t), "a DCG rule (dcg_translate_rule/2)", "R2: boot/dcg.pl"
            )
        )

    if PL_is_variable(ld, t)                            # '$instantiation_error'(Var)
        return (:exception, _init_export(ld, _init_error(ld, :instantiation_error)))
    elseif _init_is(ld, t, Symbol("?-"), 1) || _init_is(ld, t, Symbol(":-"), 1)
        g = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, t, g)
        return execute_directive!(gd, ld, g)
    end
    return store_clause!(gd, ld, t, file)
end

# `error(Formal, _)` in a new term reference, as `'$instantiation_error'` and its kin throw it:
# `Formal` the term `formal` references, or the atom `name` — with arguments, the compound
# `name(a…)`.
_init_error(ld::PL_local_data{T}, formal::term_t) where {T} =
    _message_term(ld, :error, formal, new_term_ref(ld))
function _init_error(
    ld::PL_local_data{T}, name::Symbol, a::Vararg{term_t, N}
)::term_t where {T, N}
    formal = N == 0 ? _err_atom(ld, mk_sym(T, name)) : _message_term(ld, name, a...)
    return _init_error(ld, formal)
end

# PORT: init.pl $store_clause as store_clause!
# DIVERGES: `'$compile_term'`'s `catch(…, error(_,_), print_message(error, E))` is here; the clause
# goes to `'$record_clause'/3` through the query API, its term reference shared (`PL_put_term`) —
# so an error's context is `'$record_clause'/3`'s, as swipl's — with the source location `-` (the
# term's own: `LD->read_source`); `'$valid_clause'` holds (no `sandboxed_load`); compilation mode
# `database` (no QLF). The SSU guard form (since SSU1, ssu.md D7; init.pl:4114-4121) is rewritten as
# upstream's second clause does — `(Head, Cond) => Body` becomes `?=>(Head, (Cond, !, Body))`, or
# `Head => Body` when `'$is_true'(Cond)` and the `optimise` flag is on — and stored again; the guard
# is not goal-expanded (expand.pl, R2). LB4 deletes this stand-in with the rest of the file.
"Store the clause in `t` for the file `file`; an error becomes an error message (boot/init.pl)."
function store_clause!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, file::T
)::Tuple{Symbol, Union{Nothing, T}} where {T}
    if _init_is(ld, t, Symbol(","), 2)
        printMessage(ld, :error, _err_atom(ld, mk_sym(T, :cannot_redefine_comma)))
        return (:ok, nothing)                           # fail
    end
    if _init_is(ld, t, Symbol("=>"), 2)                 # '$store_clause'((Pre => Body), …)
        pre = PL_new_term_refs(ld, 5)
        _PL_get_arg(ld, 1, t, pre)
        if _init_is(ld, pre, Symbol(","), 2)            # nonvar(Pre), Pre = (Head,Cond), !
            head, cond, body, t2 = pre + 1, pre + 2, pre + 3, pre + 4
            _PL_get_arg(ld, 1, pre, head)
            _PL_get_arg(ld, 2, pre, cond)
            _PL_get_arg(ld, 2, t, body)
            if _init_is_true(ld, cond) && ld.prolog_flag_optimise   # current_prolog_flag(optimise, true)
                PL_cons_functor(ld, t2, _err_functor(ld, Symbol("=>"), 2), head, body)
            else                                        # ?=>(Head, (Cond, !, Body))
                g = PL_new_term_refs(ld, 2)
                PL_cons_functor(
                    ld, g, _err_functor(ld, Symbol(","), 2), _err_atom(ld, mk_sym(T, :!)),
                    body
                )
                PL_cons_functor(ld, g + 1, _err_functor(ld, Symbol(","), 2), cond, g)
                PL_cons_functor(ld, t2, _err_functor(ld, Symbol("?=>"), 2), head, g + 1)
            end
            return store_clause!(gd, ld, t2, file)
        end
    end
    a = PL_new_term_refs(ld, 3)
    PL_put_term(ld, a, t)
    PL_put_atom(ld, a + 1, file)
    PL_put_atom(ld, a + 2, mk_sym(T, :-))
    proc = isCurrentProcedure(
        sym_key(mk_sym(T, Symbol("\$record_clause"))), 3, MODULE_system(gd)
    )::Procedure{T}
    ball = _init_call(gd, ld, proc, a, nothing)         # '$print_message'(error, E)
    ball === nothing || return (:exception, ball)
    return (:ok, nothing)
end

# PORT: init.pl $is_true as _init_is_true
# DIVERGES: a Julia function over the term reference (the SSU clauses `'$is_true'(true) => true.`,
# `'$is_true'((A,B)) => '$is_true'(A), '$is_true'(B).`, `'$is_true'(_) => fail.`, init.pl:4131-4133):
# a variable matches neither of the first two heads, so it is not true (since SSU1, for the guard rewrite).
"Whether term reference `t` holds `true`, or a conjunction of `true`s (boot/init.pl `'\$is_true'/1`)."
function _init_is_true(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    _init_is(ld, t, Symbol("true"), 0) && return true
    if _init_is(ld, t, Symbol(","), 2)
        a = PL_new_term_refs(ld, 2)
        _PL_get_arg(ld, 1, t, a)
        _PL_get_arg(ld, 2, t, a + 1)
        return _init_is_true(ld, a) && _init_is_true(ld, a + 1)
    end
    return false
end

# Does term reference `t` hold an `error(_, _)` term — what boot/init.pl's `catch(…, error(_,_), …)`
# catches?
_is_error_term(ld::PL_local_data{T}, t::term_t) where {T} =
    PL_is_functor(ld, t, mk_sym(T, :error), 2)

# boot/init.pl's `catch(…, error(_,_), Handler)` on the ball in `ex` of a query on one built-in (no
# frames of its own left to unwind): an `error(_, _)` ball handled — printed (`attr` nothing), or as
# `'$set_pattr'` prints it — and `nothing` returned; any other ball is not caught: it is returned,
# exported.
function _init_catch(
    ld::PL_local_data{T}, ex::term_t, attr::Union{Nothing, T}
)::Union{Nothing, T} where {T}
    _is_error_term(ld, ex) || return _init_export(ld, ex)
    if attr === nothing
        printMessage(ld, :error, ex)
    else
        _pattr_error(ld, ex, attr)
    end
    return nothing
end

# Run `proc` on the arguments at `a` through the query API, once: `nothing`, or the exported ball of
# an exception that is not `error(_, _)` (one that is goes to `_init_catch`'s handler, `attr`). A
# solution's bindings stay (the query is cut, not closed).
function _init_call(
    gd::PL_global_data{T}, ld::PL_local_data{T}, proc::Procedure{T}, a::term_t,
    attr::Union{Nothing, T}
)::Union{Nothing, T} where {T}
    fid = PL_open_foreign_frame(ld)
    qid = PL_open_query(gd, ld, nothing, PL_Q_CATCH_EXCEPTION | PL_Q_EXT_STATUS, proc, a)
    rc = PL_next_solution(gd, ld, qid)
    if rc == PL_S_TRUE || rc == PL_S_LAST
        PL_cut_query(ld, qid)                           # keep the bindings
        PL_close_foreign_frame(ld, fid)
        return nothing
    end
    ball = nothing
    rec = nothing
    if rc == PL_S_EXCEPTION
        ex = PL_exception(ld, qid)
        # an `error(_, _)` ball is recorded where its query raised it and handled once the query is closed (as `_init_solve`): the
        # handler's printing clears the pending exception, and `_release_frozen!` at the close then finds the slots of the failed
        # query (a warning's terms, the ball) above its reset target
        if _is_error_term(ld, ex)
            rec = compileTermToHeap(ld, ex)
        else
            ball = _init_export(ld, ex)
        end
    end
    # cut, not close: the frame's discard below undoes the bindings; `_release_frozen!` at a CLOSE of a failed query finds the
    # query's own argument slots (taken after its mark) above the reset target once the handled error has cleared the pending ball
    PL_cut_query(ld, qid)
    PL_discard_foreign_frame(ld, fid)
    if rec !== nothing
        mfid = PL_open_foreign_frame(ld)
        b = PL_new_term_ref(ld)
        copyRecordToGlobal(ld, b, rec::record{T}) && (ball = _init_catch(ld, b, attr))
        PL_discard_foreign_frame(ld, mfid)
    end
    return ball
end

# PORT: init.pl $execute_directive_3 as execute_directive!
# DIVERGES: the goal runs in `user` (the source module); `'$valid_directive'` holds (no
# `sandboxed_load`); `'$execute_directive'`'s QLF classification is moot (compilation mode
# `database`). The goal is one call or a `,`-conjunction — run through the query API, backtracking
# into an earlier conjunct as Prolog does — where upstream calls it (`catch(Module:Goal, …)`):
# the meta-call is V9, so `;`, `->`, `*->`, `\+`, `call/N`, a variable goal and the control
# constructs the compiler inlines (`true`, `fail`, `false`, `!`: they have no procedure) are
# refused. An error's context is the query's top frame, `system:'$c_call_prolog'/0`, where swipl's
# is the `catch/3` boot wraps the directive in.
"Run the directive in `g` as loading a file runs it; failure and errors become messages (boot/init.pl)."
function execute_directive!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, g::term_t
)::Tuple{Symbol, Union{Nothing, T}} where {T}
    user = MODULE_user(gd)
    if PL_is_variable(ld, g)                            # '$execute_directive'(Var, …)
        return (:exception, _init_export(ld, _init_error(ld, :instantiation_error)))
    end
    for (n, a) in ((:encoding, 1), (:module, 2), (:use_module, 1), (:use_module, 2),
        (:include, 1), (:initialization, 1), (:initialization, 2), (:ensure_loaded, 1),
        (:if, 1), (:elif, 1), (:else, 0), (:endif, 0))     # (conditional compilation: '$source_term')
        _init_is(ld, g, n, a) &&
            throw(
                NotPortedError{T}(
                    _init_export(ld, g), "the directive $n/$a", "R2 (boot/init.pl)"
                )
            )
    end

    handled, ball = pattr_directive!(gd, ld, g, user)
    if handled
        return ball === nothing ? (:ok, nothing) : (:exception, ball)
    end

    goals = term_t[]
    _init_conjuncts!(goals, ld, g)
    r = _init_solve(gd, ld, goals, 1, user)
    r[1] === :exception && return (:exception, r[2]::T)   # catch(…, error(_,_), …) only
    if r[1] === :caught                                 # '$exception_in_directive'(Term): fails
        mfid = PL_open_foreign_frame(ld)                # (the message's terms: printMessage's own)
        b = PL_new_term_ref(ld)                         # the ball, after the unwinding
        copyRecordToGlobal(ld, b, r[2]::record{T}) && printMessage(ld, :error, b)
        PL_discard_foreign_frame(ld, mfid)
    end
    if r[1] !== :succeeded
        mfid = PL_open_foreign_frame(ld)
        msg = _message_term(
            ld, :goal_failed, _err_atom(ld, mk_sym(T, :directive)),
            _message_term(ld, :(:), _err_atom(ld, user.atom), g)
        )
        printMessage(ld, :warning, msg)
        PL_discard_foreign_frame(ld, mfid)
    end
    return (:ok, nothing)
end

# The conjuncts of the term in `g`: `(A, B)` flattened, left to right, each in a new term reference.
function _init_conjuncts!(
    goals::Vector{term_t}, ld::PL_local_data{T}, g::term_t
)::Nothing where {T}
    if _init_is(ld, g, Symbol(","), 2)
        a = PL_new_term_refs(ld, 2)
        _PL_get_arg(ld, 1, g, a)
        _PL_get_arg(ld, 2, g, a + 1)
        _init_conjuncts!(goals, ld, a)
        _init_conjuncts!(goals, ld, a + 1)
    else
        push!(goals, g)
    end
    return nothing
end

# Refuse the goal in `t` (its culprit exported), the foreign frame `fid` discarded first.
function _init_refuse(
    ld::PL_local_data{T}, fid::Int, t::term_t, what::String, step::String
) where {T}
    c = _init_export(ld, t)
    PL_discard_foreign_frame(ld, fid)
    throw(NotPortedError{T}(c, what, step))
end

# The goal term of functor `name/arity`, its arguments `[]` — what `lookupBodyProcedure` reads of a
# goal (its functor); the goal's own arguments stay on the cells.
_init_functor_goal(::Type{T}, name::T, arity::Int) where {T} =
    arity == 0 ? name : mk_expr(T, T[name, (mk_nil(T) for _ in 1:arity)...])

# Solve `goals[i:end]` in `m`, backtracking into goal i for each later failure:
# `(:succeeded, nothing)`, `(:failed, nothing)`, `(:caught, Record)` — an `error(_, _)` ball,
# recorded (`compileTermToHeap`) where its query raised it: the caller prints it once every query is
# closed, as catch/3 unwinds (cleanup handlers run) before its handler prints — or
# `(:exception, Ball)` (exported). A solution's bindings stay (each query is cut). The foreign frame
# is opened first: after an answer of goal i - 1, no term reference may be made outside a new one
# (fli:535-548).
function _init_solve(
    gd::PL_global_data{T}, ld::PL_local_data{T}, goals::Vector{term_t}, i::Int,
    m::module_t{T}
)::Tuple{Symbol, Union{Nothing, T, record{T}}} where {T}
    i > length(goals) && return (:succeeded, nothing)
    fid = PL_open_foreign_frame(ld)
    goal = goals[i]
    if _init_is(ld, goal, :(:), 2)                      # Module:Goal
        mm = PL_new_term_refs(ld, 2)
        _PL_get_arg(ld, 1, goal, mm)
        ma = PL_get_atom(ld, mm)
        (ma !== nothing && sym_key(ma) == sym_key(m.atom)) ||
            _init_refuse(ld, fid, goal, "a goal in another module", "R2 (modules)")
        _PL_get_arg(ld, 2, goal, mm + 1)
        goal = mm + 1
    end
    for (n, a) in
        ((Symbol(";"), 2), (Symbol("->"), 2), (Symbol("*->"), 2), (Symbol("\\+"), 1))
        _init_is(ld, goal, n, a) &&
            _init_refuse(ld, fid, goal, "the control construct $n/$a in a directive", "V9")
    end
    fa = PL_get_functor(ld, goal)                       # a variable, a number, a string, `$expr/n`
    fa === nothing && _init_refuse(ld, fid, goal, "a goal that needs the meta-call", "V9")
    name, arity = fa::Tuple{T, Int}
    (sym_key(name) == sym_key(mk_sym(T, :call)) && arity >= 1) &&
        _init_refuse(ld, fid, goal, "call/N in a directive", "V9")
    for c in ("true", "fail", "false", "!")             # compiled control: no procedure
        arity == 0 && sym_key(name) == sym_key(mk_sym(T, Symbol(c))) &&
            _init_refuse(ld, fid, goal, "the control construct $c in a directive", "V9")
    end
    fgoal = _init_functor_goal(T, name, arity)
    if _body_functor(T, fgoal)[2] < 0                   # not callable (a reserved symbol)
        c = _init_export(ld, goal)
        PL_discard_foreign_frame(ld, fid)
        throw(CallableTypeError{T}(c))
    end
    proc = lookupBodyProcedure(gd, fgoal, m)            # as the compiler resolves a call

    a = PL_new_term_refs(ld, max(arity, 1))
    for k in 1:arity
        _PL_get_arg(ld, k, goal, a + k - 1)
    end
    # the context module is the directive's `m`: a later conjunct is called inside the earlier one's query, whose frame's module
    # (`system`, for atom/1 or '$set_predicate_attribute'/3) the default `nothing` would take, so `assertz(p(1))` asserted into system
    qid = PL_open_query(gd, ld, m, PL_Q_CATCH_EXCEPTION | PL_Q_EXT_STATUS, proc, a)
    while true
        rc = PL_next_solution(gd, ld, qid)
        if rc == PL_S_EXCEPTION
            ex = PL_exception(ld, qid)
            out = if _is_error_term(ld, ex)                 # catch(…, error(_,_), …)
                (:caught, compileTermToHeap(ld, ex))
            else
                (:exception, _init_export(ld, ex))
            end
            PL_close_query(ld, qid)
            PL_discard_foreign_frame(ld, fid)
            return out
        elseif rc == PL_S_TRUE || rc == PL_S_LAST
            r = _init_solve(gd, ld, goals, i + 1, m)
            if r[1] !== :failed
                r[1] === :succeeded ? PL_cut_query(ld, qid) : PL_close_query(ld, qid)
                if r[1] === :succeeded
                    PL_close_foreign_frame(ld, fid)
                else
                    PL_discard_foreign_frame(ld, fid)
                end
                return r
            end
            rc == PL_S_LAST && break                    # no more solutions of goal i
        else
            break
        end
    end
    PL_close_query(ld, qid)
    PL_discard_foreign_frame(ld, fid)
    return (:failed, nothing)
end

# PORT: init.pl $pattr_directive as pattr_directive!
# DIVERGES: returns `(handled, ball)`: `handled` when the directive is one of the predicate-attribute
# declarations, after setting them (`'$set_pattr'` in its `directive` mode: each error printed, the
# rest set); `ball` an exception that ends the load (a variable spec: `'$set_pattr'`'s first
# clause raises it, outside the catch), exported, else `nothing`.
"Handle `dynamic(Spec)`, `discontiguous(Spec)`, … as directives set them (boot/init.pl)."
function pattr_directive!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, g::term_t, m::module_t{T}
)::Tuple{Bool, Union{Nothing, T}} where {T}
    for (n, attr) in ((:dynamic, :dynamic), (:multifile, :multifile),
        (:module_transparent, :transparent), (:discontiguous, :discontiguous),
        (:volatile, :volatile), (:thread_local, :thread_local), (:noprofile, :noprofile),
        (:public, :public), (:det, :det))
        if _init_is(ld, g, n, 1)
            spec = PL_new_term_ref(ld)
            _PL_get_arg(ld, 1, g, spec)
            return (true, set_pattr!(gd, ld, spec, m, mk_sym(T, attr)))
        end
    end
    return (false, nothing)
end

# PORT: init.pl $set_pattr as set_pattr!
# DIVERGES: the `directive` mode only, `Attr(true)`; `as(Spec, Options)` refused (its options are
# tabling's). Each predicate indicator goes to `'$set_predicate_attribute'/3` through the query API
# (`'$set_pi_attr'`), an error printed as `error(E, context(Name/1, _))`. Returns the exception
# that ends the load — a variable spec (`'$uninstantiation_error'(X)`), exported — or `nothing`.
"Set attribute `attr` of every predicate `spec` names (`PI`, `[PI, …]`, `(PI, PI)`, `M:PI`) (boot/init.pl)."
function set_pattr!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, spec::term_t, m::module_t{T}, attr::T
)::Union{Nothing, T} where {T}
    if PL_is_variable(ld, spec)                         # '$uninstantiation_error'(X)
        return _init_export(ld, _init_error(ld, :uninstantiation_error, spec))
    elseif _init_is(ld, spec, :as, 2)
        throw(
            NotPortedError{T}(
                _init_export(ld, spec), "a predicate declaration's options (as/2)",
                "tabling"
            )
        )
    elseif PL_get_nil(ld, spec)
        return nothing
    end
    ab = PL_new_term_refs(ld, 2)
    if PL_get_list(ld, spec, ab, ab + 1)                # [H|T], ISO
        b = set_pattr!(gd, ld, ab, m, attr)
        b === nothing || return b
        return set_pattr!(gd, ld, ab + 1, m, attr)
    elseif _init_is(ld, spec, Symbol(","), 2)           # (A,B), ISO and traditional
        _PL_get_arg(ld, 1, spec, ab)
        _PL_get_arg(ld, 2, spec, ab + 1)
        b = set_pattr!(gd, ld, ab, m, attr)
        b === nothing || return b
        return set_pattr!(gd, ld, ab + 1, m, attr)
    elseif _init_is(ld, spec, :(:), 2)                  # M:T
        _PL_get_arg(ld, 1, spec, ab)
        mm = PL_get_atom(ld, ab)
        (mm !== nothing && sym_key(mm) == sym_key(m.atom)) ||
            throw(
                NotPortedError{T}(
                    _init_export(ld, spec), "a declaration for another module",
                    "R2 (modules)"
                )
            )
        _PL_get_arg(ld, 2, spec, ab + 1)
        return set_pattr!(gd, ld, ab + 1, m, attr)
    end
    # '$set_pi_attr'(M:A, Name, Val), in catch(…, error(E, _), print_message(…))
    head = PL_new_term_ref(ld)
    err = _pi_head(ld, spec, head)
    if err !== nothing
        _pattr_error(ld, err, attr)
        return nothing
    end
    a = PL_new_term_refs(ld, 3)
    PL_cons_functor(ld, a, _err_functor(ld, :(:), 2), _err_atom(ld, m.atom), head)
    PL_put_atom(ld, a + 1, attr)
    PL_put_atom(ld, a + 2, mk_sym(T, Symbol("true")))
    proc = isCurrentProcedure(
        sym_key(mk_sym(T, Symbol("\$set_predicate_attribute"))), 3, MODULE_system(gd)
    )::Procedure{T}
    return _init_call(gd, ld, proc, a, attr)            # not error(_,_): not caught
end

# '$set_pattr''s catch: `error(E, _)` in `ex` printed as `error(E, context(Name/1, _))`.
function _pattr_error(ld::PL_local_data{T}, ex::term_t, attr::T)::Nothing where {T}
    fid = PL_open_foreign_frame(ld)     # (its terms are printMessage's own: none may outlive the
    e = new_term_ref(ld)                #  open query whose ball they read — `_release_frozen!`)
    _PL_get_arg(ld, 1, ex, e)
    ctx = _message_term(
        ld, :context, _message_term(ld, :/, _err_atom(ld, attr), _err_int(ld, 1)),
        new_term_ref(ld)
    )
    printMessage(ld, :error, _message_term(ld, :error, e, ctx))
    PL_discard_foreign_frame(ld, fid)
    return nothing
end

# PORT: init.pl $pi_head as _pi_head
# DIVERGES: the head of `Name/Arity` or `Name//DCGArity` (two more arguments) put into `head`, built
# with fresh variables (`'$head_name_arity'`, then `compound_name_arity/3`: `PL_unify_functor` on
# `head`'s fresh variable), and `nothing` returned; an error is returned as a term reference holding
# `error(Formal, _)`, its formal what swipl raises (its context is replaced by the caller):
# `instantiation_error` (a variable PI, name or arity), `type_error(atom, Name)` (`Name/0` with a
# name that is no atom, or a compound's name that is no atom), `type_error(integer, A)`,
# `domain_error(not_less_than_zero, A)`, `type_error(evaluable, …)` (a `//` arity),
# `type_error(predicate_indicator, PI)`.
function _pi_head(
    ld::PL_local_data{T}, pi::term_t, head::term_t
)::Union{Nothing, term_t} where {T}
    PL_is_variable(ld, pi) && return _init_error(ld, :instantiation_error)
    if _init_is(ld, pi, :/, 2) || _init_is(ld, pi, Symbol("//"), 2)
        dcg = _init_is(ld, pi, Symbol("//"), 2)
        n = PL_new_term_refs(ld, 2)
        a = n + 1
        _PL_get_arg(ld, 1, pi, n)
        _PL_get_arg(ld, 2, pi, a)
        PL_is_variable(ld, a) && return _init_error(ld, :instantiation_error)
        ai = PL_get_long(ld, a)                         # an integer in Int64's range
        if ai === nothing
            dcg && PL_is_number(ld, a) && return _init_error(ld, :instantiation_error)   # (not reached)
            if dcg
                culprit = if PL_get_atom(ld, a) !== nothing
                    _message_term(ld, :/, a, _err_int(ld, 0))
                else
                    a
                end
                return _init_error(
                    ld, :type_error, _err_atom(ld, mk_sym(T, :evaluable)), culprit
                )
            end
            return _init_error(ld, :type_error, _err_atom(ld, mk_sym(T, :integer)), a)
        end
        arity = ai + (dcg ? 2 : 0)
        name = PL_get_atom(ld, n)
        if arity == 0                                   # '$head_name_arity'(-Goal, +Name, 0)
            if name !== nothing                         # atom(Name) ; Name == []
                PL_put_term(ld, head, n)
                return nothing
            end
            # '$type_error'(atom, Name): `var(Value) -> throw(error(instantiation_error, _))`
            PL_is_variable(ld, n) && return _init_error(ld, :instantiation_error)
            return _init_error(ld, :type_error, _err_atom(ld, mk_sym(T, :atom)), n)
        end
        PL_is_variable(ld, n) && return _init_error(ld, :instantiation_error)   # compound_name_arity
        name === nothing &&
            return _init_error(ld, :type_error, _err_atom(ld, mk_sym(T, :atom)), n)
        arity < 0 && return _init_error(
            ld, :domain_error, _err_atom(ld, mk_sym(T, :not_less_than_zero)),
            _err_int(ld, arity)
        )
        PL_unify_functor(ld, head, name, arity)         # head: a fresh variable
        return nothing
    end
    return _init_error(ld, :type_error, _err_atom(ld, mk_sym(T, :predicate_indicator)), pi)
end
