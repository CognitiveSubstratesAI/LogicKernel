# UPSTREAM: swipl-devel boot/init.pl @ bae881a2
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
# `'$start_consult'`, read a clause (`read_clause`), compile it (`'$compile_term'`), each with its
# bindings undone after it (the failure-driven loop), `'$end_consult'`, the stream closed whatever
# happens (`setup_call_cleanup`). An exception that is not `error(_,_)` ENDS the load, as in swipl
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
            ok = read_clause(gd, ld, s, t, 0)
            w = deRef(ld, ld.slots[t + 1])
            if !ok || (kind(w) === SYM && sym_key(w) == sym_key(mk_sym(T, :end_of_file)))
                PL_discard_foreign_frame(ld, fid)
                break
            end
            if !valid_term(ld, w)                               # '$valid_term'(Term): `[]`
                PL_discard_foreign_frame(ld, fid)
                continue
            end
            r, b = compile_term!(gd, ld, t, file)
            PL_discard_foreign_frame(ld, fid)                   # the failure-driven loop
            if r === :exception
                status, ball = :exception, b
                break
            end
        end
    finally
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

# PORT: init.pl $valid_term as valid_term
# DIVERGES: the term itself, dereferenced; the message goes to `printMessage`.
"""
Should the term read be compiled (boot/init.pl)? Not `[]`; a variable is — after its error is
printed — and `'\$compile_term'` then raises it, ending the load.
"""
function valid_term(ld::PL_local_data{T}, w::T)::Bool where {T}
    if kind(w) === VAR
        printMessage(ld, :error, _init_error(T, mk_sym(T, :instantiation_error)))
        return true
    end
    return !is_nil(w)                                   # Term \== []
end

# Is `w` the compound `name/arity` (a symbol head) — or, for arity 0, the atom `name`?
_init_is(ld::PL_local_data{T}, w::T, name::Symbol, arity::Int) where {T} =
    if arity == 0
        (kind(w) === SYM && sym_key(w) == sym_key(mk_sym(T, name)))
    else
        _hasFunctor(w, mk_sym(T, name), arity)
    end

# PORT: init.pl $compile_term as compile_term!
# DIVERGES: `'$expanded_term'` is the identity (no `term_expansion`/`goal_expansion` defined — when
# one is, refused — and a DCG rule `-->` refused: `dcg_translate_rule` is boot/dcg.pl's, R2);
# `'$source_location'(File, Line):Term` never arises (read_clause makes no layout). Returns
# `(:ok, nothing)`, or `(:exception, Ball)` for an exception that ends the load.
"Compile the term read into `t`: a directive, or a clause stored for the file `file` (boot/init.pl)."
function compile_term!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, file::T
)::Tuple{Symbol, Union{Nothing, T}} where {T}
    w = deRef(ld, ld.slots[t + 1])
    user = MODULE_user(gd)
    for (n, a) in ((:term_expansion, 2), (:term_expansion, 4), (:goal_expansion, 2),
        (:goal_expansion, 4))
        p = isCurrentProcedure(sym_key(mk_sym(T, n)), a, user)
        p !== nothing && _impl_any_defined(p.definition) &&
            throw(
                NotPortedError{T}(w, "term_expansion/goal_expansion (expand_term/2)", "R2")
            )
    end
    _init_is(ld, w, Symbol("-->"), 2) &&
        throw(NotPortedError{T}(w, "a DCG rule (dcg_translate_rule/2)", "R2: boot/dcg.pl"))

    if kind(w) === VAR                                  # '$instantiation_error'(Var)
        return (:exception, _init_error(T, mk_sym(T, :instantiation_error)))
    elseif _init_is(ld, w, Symbol("?-"), 1) || _init_is(ld, w, Symbol(":-"), 1)
        g = PL_new_term_ref(ld)
        ld.slots[g + 1] = child(w, 2)
        return execute_directive!(gd, ld, g)
    end
    return store_clause!(gd, ld, t, file)
end

# `error(Formal, _)`, as `'$instantiation_error'` and its kin throw it.
_init_error(::Type{T}, formal::T) where {T} =
    mk_expr(T, T[mk_sym(T, :error), formal, mk_var(T, fresh_var_keys!(1))])

# PORT: init.pl $store_clause as store_clause!
# DIVERGES: `'$compile_term'`'s `catch(…, error(_,_), print_message(error, E))` is here; the clause
# goes to `'$record_clause'/3` through the query API — so an error's context is
# `'$record_clause'/3`'s, as swipl's — with the source location `-` (the term's own:
# `LD->read_source`); `'$valid_clause'` holds (no `sandboxed_load`); SSU clauses (`=>`) refused;
# compilation mode `database` (no QLF).
"Store the clause in `t` for the file `file`; an error becomes an error message (boot/init.pl)."
function store_clause!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, file::T
)::Tuple{Symbol, Union{Nothing, T}} where {T}
    w = deRef(ld, ld.slots[t + 1])
    if _init_is(ld, w, Symbol(","), 2)
        printMessage(ld, :error, mk_sym(T, :cannot_redefine_comma))
        return (:ok, nothing)                           # fail
    end
    _init_is(ld, w, Symbol("=>"), 2) &&
        throw(NotPortedError{T}(w, "an SSU clause (=>)", "SSU is not ported"))
    a = PL_new_term_refs(ld, 3)
    ld.slots[a + 1] = w
    ld.slots[a + 2] = file
    ld.slots[a + 3] = mk_sym(T, :-)
    proc = isCurrentProcedure(
        sym_key(mk_sym(T, Symbol("\$record_clause"))), 3, MODULE_system(gd)
    )::Procedure{T}
    rc, ball = _init_call(gd, ld, proc, a)
    if rc === :exception
        _is_error_term(ld, ball::T) || return (:exception, ball)
        printMessage(ld, :error, ball::T)                # '$print_message'(error, E)
    end
    return (:ok, nothing)
end

# Is `b` an `error(_, _)` term — what boot/init.pl's `catch(…, error(_,_), …)` catches?
_is_error_term(::PL_local_data{T}, b) where {T} =
    kind(b) === EXPR && nchildren(b) == 3 && kind(child(b, 1)) === SYM &&
    sym_key(child(b, 1)) == sym_key(mk_sym(T, :error))

# Run `proc` on the arguments at `a` through the query API, once: `(:succeeded | :failed, nothing)` or
# `(:exception, Ball)` (the ball resolved). Its bindings stay (the query is cut, not closed).
function _init_call(
    gd::PL_global_data{T}, ld::PL_local_data{T}, proc::Procedure{T}, a::term_t
)::Tuple{Symbol, Union{Nothing, T}} where {T}
    fid = PL_open_foreign_frame(ld)
    qid = PL_open_query(gd, ld, nothing, PL_Q_CATCH_EXCEPTION | PL_Q_EXT_STATUS, proc, a)
    rc = PL_next_solution(gd, ld, qid)
    out = if rc == PL_S_TRUE || rc == PL_S_LAST
        (:succeeded, nothing)
    elseif rc == PL_S_EXCEPTION
        (:exception, resolve_term(ld, ld.slots[PL_exception(ld, qid) + 1]))
    else
        (:failed, nothing)
    end
    if out[1] === :succeeded
        PL_cut_query(ld, qid)                           # keep the bindings
        PL_close_foreign_frame(ld, fid)
    else
        PL_close_query(ld, qid)
        PL_discard_foreign_frame(ld, fid)
    end
    return out
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
    w = deRef(ld, ld.slots[g + 1])
    user = MODULE_user(gd)
    if kind(w) === VAR                                  # '$execute_directive'(Var, …)
        return (:exception, _init_error(T, mk_sym(T, :instantiation_error)))
    end
    for (n, a) in ((:encoding, 1), (:module, 2), (:use_module, 1), (:use_module, 2),
        (:include, 1), (:initialization, 1), (:initialization, 2), (:ensure_loaded, 1),
        (:if, 1), (:elif, 1), (:else, 0), (:endif, 0))     # (conditional compilation: '$source_term')
        _init_is(ld, w, n, a) &&
            throw(NotPortedError{T}(w, "the directive $n/$a", "R2 (boot/init.pl)"))
    end

    handled, ball = pattr_directive!(gd, ld, w, user)
    if handled
        return ball === nothing ? (:ok, nothing) : (:exception, ball)
    end

    goals = T[]
    _init_conjuncts!(goals, ld, w)
    r = _init_solve(gd, ld, goals, 1, user)
    if r[1] === :exception
        b = r[2]::T
        _is_error_term(ld, b) || return (:exception, b)    # catch(…, error(_,_), …) only
        printMessage(ld, :error, b)                     # '$exception_in_directive'(Term): fails
    end
    if r[1] !== :succeeded
        printMessage(
            ld, :warning,
            mk_expr(
                T,
                T[mk_sym(T, :goal_failed), mk_sym(T, :directive),
                    mk_expr(T, T[mk_sym(T, :(:)), user.atom, w])]
            )
        )
    end
    return (:ok, nothing)
end

# The conjuncts of `w`: `(A, B)` flattened, left to right.
function _init_conjuncts!(goals::Vector{T}, ld::PL_local_data{T}, w::T)::Nothing where {T}
    w = deRef(ld, w)
    if _init_is(ld, w, Symbol(","), 2)
        _init_conjuncts!(goals, ld, child(w, 2))
        _init_conjuncts!(goals, ld, child(w, 3))
    else
        push!(goals, w)
    end
    return nothing
end

# Solve `goals[i:end]` in `m`, backtracking into goal i for each later failure: `(:succeeded, nothing)`,
# `(:failed, nothing)` or `(:exception, Ball)`. A solution's bindings stay (each query is cut).
function _init_solve(
    gd::PL_global_data{T}, ld::PL_local_data{T}, goals::Vector{T}, i::Int, m::module_t{T}
)::Tuple{Symbol, Union{Nothing, T}} where {T}
    i > length(goals) && return (:succeeded, nothing)
    goal = deRef(ld, goals[i])
    if _init_is(ld, goal, :(:), 2)                      # Module:Goal
        mm = deRef(ld, child(goal, 2))
        (kind(mm) === SYM && sym_key(mm) == sym_key(m.atom)) ||
            throw(NotPortedError{T}(goal, "a goal in another module", "R2 (modules)"))
        goal = deRef(ld, child(goal, 3))
    end
    for (n, a) in
        ((Symbol(";"), 2), (Symbol("->"), 2), (Symbol("*->"), 2), (Symbol("\\+"), 1))
        _init_is(ld, goal, n, a) &&
            throw(
                NotPortedError{T}(goal, "the control construct $n/$a in a directive", "V9")
            )
    end
    if kind(goal) === VAR || !(kind(goal) === SYM || kind(goal) === EXPR) ||
        (kind(goal) === EXPR && kind(child(goal, 1)) !== SYM)
        throw(NotPortedError{T}(goal, "a goal that needs the meta-call", "V9"))
    end
    name, arity = kind(goal) === SYM ? (goal, 0) : (child(goal, 1), nchildren(goal) - 1)
    (sym_key(name) == sym_key(mk_sym(T, :call)) && arity >= 1) &&
        throw(NotPortedError{T}(goal, "call/N in a directive", "V9"))
    for c in ("true", "fail", "false", "!")             # compiled control: no procedure
        arity == 0 && sym_key(name) == sym_key(mk_sym(T, Symbol(c))) &&
            throw(NotPortedError{T}(goal, "the control construct $c in a directive", "V9"))
    end
    proc = lookupBodyProcedure(gd, goal, m)              # as the compiler resolves a call

    fid = PL_open_foreign_frame(ld)
    a = PL_new_term_refs(ld, max(arity, 1))
    for k in 1:arity
        ld.slots[a + k] = child(goal, k + 1)
    end
    qid = PL_open_query(gd, ld, nothing, PL_Q_CATCH_EXCEPTION | PL_Q_EXT_STATUS, proc, a)
    while true
        rc = PL_next_solution(gd, ld, qid)
        if rc == PL_S_EXCEPTION
            b = resolve_term(ld, ld.slots[PL_exception(ld, qid) + 1])
            PL_close_query(ld, qid)
            PL_discard_foreign_frame(ld, fid)
            return (:exception, b)
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
# clause raises it, outside the catch), else `nothing`.
"Handle `dynamic(Spec)`, `discontiguous(Spec)`, … as directives set them (boot/init.pl)."
function pattr_directive!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, w::T, m::module_t{T}
)::Tuple{Bool, Union{Nothing, T}} where {T}
    for (n, attr) in ((:dynamic, :dynamic), (:multifile, :multifile),
        (:module_transparent, :transparent), (:discontiguous, :discontiguous),
        (:volatile, :volatile), (:thread_local, :thread_local), (:noprofile, :noprofile),
        (:public, :public), (:det, :det))
        if _init_is(ld, w, n, 1)
            return (true, set_pattr!(gd, ld, child(w, 2), m, mk_sym(T, attr)))
        end
    end
    return (false, nothing)
end

# PORT: init.pl $set_pattr as set_pattr!
# DIVERGES: the `directive` mode only, `Attr(true)`; `as(Spec, Options)` refused (its options are
# tabling's). Each predicate indicator goes to `'$set_predicate_attribute'/3` through the query API
# (`'$set_pi_attr'`), an error printed as `error(E, context(Name/1, _))`. Returns the exception
# that ends the load — a variable spec (`'$uninstantiation_error'(X)`) — or `nothing`.
"Set attribute `attr` of every predicate `spec` names (`PI`, `[PI, …]`, `(PI, PI)`, `M:PI`) (boot/init.pl)."
function set_pattr!(
    gd::PL_global_data{T}, ld::PL_local_data{T}, spec::T, m::module_t{T}, attr::T
)::Union{Nothing, T} where {T}
    spec = deRef(ld, spec)
    if kind(spec) === VAR                               # '$uninstantiation_error'(X)
        return _init_error(T, mk_expr(T, T[mk_sym(T, :uninstantiation_error), spec]))
    elseif _init_is(ld, spec, :as, 2)
        throw(
            NotPortedError{T}(spec, "a predicate declaration's options (as/2)", "tabling")
        )
    elseif is_nil(spec)
        return nothing
    elseif is_pair(spec)                                # [H|T], ISO
        b = set_pattr!(gd, ld, child(spec, 2), m, attr)
        b === nothing || return b
        return set_pattr!(gd, ld, child(spec, 3), m, attr)
    elseif _init_is(ld, spec, Symbol(","), 2)           # (A,B), ISO and traditional
        b = set_pattr!(gd, ld, child(spec, 2), m, attr)
        b === nothing || return b
        return set_pattr!(gd, ld, child(spec, 3), m, attr)
    elseif _init_is(ld, spec, :(:), 2)                  # M:T
        mm = deRef(ld, child(spec, 2))
        (kind(mm) === SYM && sym_key(mm) == sym_key(m.atom)) ||
            throw(
                NotPortedError{T}(spec, "a declaration for another module", "R2 (modules)")
            )
        return set_pattr!(gd, ld, child(spec, 3), m, attr)
    end
    # '$set_pi_attr'(M:A, Name, Val), in catch(…, error(E, _), print_message(…))
    head = _pi_head(ld, spec)
    if head isa Tuple
        _pattr_error(ld, head[2], attr)
        return nothing
    end
    a = PL_new_term_refs(ld, 3)
    ld.slots[a + 1] = mk_expr(T, T[mk_sym(T, :(:)), m.atom, head])
    ld.slots[a + 2] = attr
    ld.slots[a + 3] = mk_sym(T, Symbol("true"))
    proc = isCurrentProcedure(
        sym_key(mk_sym(T, Symbol("\$set_predicate_attribute"))), 3, MODULE_system(gd)
    )::Procedure{T}
    rc, ball = _init_call(gd, ld, proc, a)
    if rc === :exception
        _is_error_term(ld, ball::T) || return ball::T       # not error(_,_): not caught
        _pattr_error(ld, ball::T, attr)
    end
    return nothing
end

# '$set_pattr''s catch: `error(E, _)` printed as `error(E, context(Name/1, _))`.
function _pattr_error(ld::PL_local_data{T}, ball::T, attr::T)::Nothing where {T}
    e = child(ball, 2)
    ctx = mk_expr(
        T,
        T[mk_sym(T, :context), mk_expr(T, T[mk_sym(T, :/), attr, mk_gnd(T, 1)]),
            mk_var(T, fresh_var_keys!(1))]
    )
    printMessage(ld, :error, mk_expr(T, T[mk_sym(T, :error), e, ctx]))
    return nothing
end

# `(:error, error(Formal, _))`, as `_pi_head` returns an error.
_pi_error(::Type{T}, formal::T) where {T} = (:error, _init_error(T, formal))

# PORT: init.pl $pi_head as _pi_head
# DIVERGES: the head of `Name/Arity` or `Name//DCGArity` (two more arguments), built with fresh
# variables (`'$head_name_arity'`, then `compound_name_arity/3`); an error is returned as
# `(:error, Ball)`, its formal what swipl raises (its context is replaced by the caller):
# `instantiation_error` (a variable PI, name or arity), `type_error(atom, Name)` (`Name/0` with a
# name that is no atom, or a compound's name that is no atom), `type_error(integer, A)`,
# `domain_error(not_less_than_zero, A)`, `type_error(evaluable, …)` (a `//` arity),
# `type_error(predicate_indicator, PI)`.
function _pi_head(ld::PL_local_data{T}, pi::T)::Union{T, Tuple{Symbol, T}} where {T}
    pi = deRef(ld, pi)
    kind(pi) === VAR && return _pi_error(T, mk_sym(T, :instantiation_error))
    if _init_is(ld, pi, :/, 2) || _init_is(ld, pi, Symbol("//"), 2)
        dcg = _init_is(ld, pi, Symbol("//"), 2)
        n = deRef(ld, child(pi, 2))
        a = deRef(ld, child(pi, 3))
        kind(a) === VAR && return _pi_error(T, mk_sym(T, :instantiation_error))
        if !(isInteger(a) && integer_is_int64(a))
            dcg && isNumber(a) && return _pi_error(T, mk_sym(T, :instantiation_error))   # (not reached)
            dcg && return _pi_error(T,
                mk_expr(
                    T,
                    T[mk_sym(T, :type_error), mk_sym(T, :evaluable),
                        if kind(a) === SYM
                            mk_expr(T, T[mk_sym(T, :/), a, mk_gnd(T, 0)])
                        else
                            a
                        end]
                )
            )
            return _pi_error(
                T, mk_expr(T, T[mk_sym(T, :type_error), mk_sym(T, :integer), a])
            )
        end
        arity = Int(int64_value(a)) + (dcg ? 2 : 0)
        if arity == 0                                   # '$head_name_arity'(-Goal, +Name, 0)
            kind(n) === SYM && return n                 # atom(Name) ; Name == []
            return _pi_error(T, mk_expr(T, T[mk_sym(T, :type_error), mk_sym(T, :atom), n]))
        end
        kind(n) === VAR && return _pi_error(T, mk_sym(T, :instantiation_error))   # compound_name_arity
        kind(n) === SYM ||
            return _pi_error(T, mk_expr(T, T[mk_sym(T, :type_error), mk_sym(T, :atom), n]))
        arity < 0 && return _pi_error(T,
            mk_expr(
                T,
                T[
                    mk_sym(T, :domain_error),
                    mk_sym(T, :not_less_than_zero),
                    mk_gnd(T, arity)
                ]
            )
        )
        return mk_expr(T, T[n, (mk_var(T, fresh_var_keys!(1)) for _ in 1:arity)...])
    end
    return _pi_error(
        T, mk_expr(T, T[mk_sym(T, :type_error), mk_sym(T, :predicate_indicator), pi])
    )
end
