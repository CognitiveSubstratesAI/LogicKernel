# ORIGINAL: the shared helpers of the rules differentials (a library, not run on its own: only test_*.jl run);
# Prolog has no counterpart. test/core_lang/rules_common.jl — included by test_rules_swipl.jl, test_softcut.jl,
# test_catch_swipl.jl and the other rule differentials after `term_under_test.jl` and `const LK = LogicKernel` (split 2026-10-12, user: mutants
# target the smallest test file holding the killing assertion; each test file runs in its own module).

const _R = lk_term_type(Union{Int64, Float64, String})
_rs(x) = lk_sym(_R, Symbol(x))
_rg(v) = lk_gnd(_R, v)
_rv(k::Integer) = lk_var(_R, UInt64(k))
_rf(f, xs::_R...) = mk_expr(_R, _R[_rs(f), xs...])
_rnil() = LK.mk_nil(_R)
_rcons(h::_R, t::_R) = _rf("[|]", h, t)
_rlist(xs::_R...) = foldr(_rcons, xs; init=_rnil())
_rints(r) = _rlist((_rg(i) for i in r)...)
_rconj(gs::_R...) = foldr((a, b) -> _rf(",", a, b), gs)

# ── a database, its clauses, and a caller of the query API ──────────────────────────────────────
struct _RDB
    gd::LK.PL_global_data{_R}
    ld::LK.PL_local_data{_R}
    user::LK.module_t{_R}
end
function _RDB()
    gd = LK.PL_global_data{_R}()
    return _RDB(gd, LK.PL_local_data{_R}(), LK.MODULE_user(gd))
end
_rfunctor(t::_R) = kind(t) === SYM ? (t, 0) : (child(t, 1), nchildren(t) - 1)
_rproc(db::_RDB, t::_R) = LK.lookupProcedure(_rfunctor(t)..., db.user)

"`head :- body` (`body` nothing: a fact), compiled and added at the end of its predicate."
function _radd!(db::_RDB, head::_R, body::Union{Nothing, _R}=nothing)
    pr = _rproc(db, head)
    cl = LK.compileClause(db.gd, db.ld, head, body, pr, db.user)
    LK.assertDefinition!(db.gd, pr.definition, cl, LK.CL_END)
    return cl
end

"""
Every answer of `goal` through the query API, as `(write_canonical text, deterministic)`;
`at(qid, k)` runs at answer `k` while it is current.
"""
function _rcall(db::_RDB, goal::_R; at=(qid, k) -> nothing)::Vector{Tuple{String, Bool}}
    gd, ld = db.gd, db.ld
    _, n = _rfunctor(goal)
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, n)
    pvm = LK.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    for i in 1:n
        LK.putSlotValue!(ld, args + i, child(goal, i + 1), pvm)            # term reference args + (i - 1)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, goal), args
    )
    out = Tuple{String, Bool}[]
    while true
        rc = LK.PL_next_solution(gd, ld, qid)
        (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
        # bounded (V4b): a regression that answers without end fails here instead of hanging the
        # suite — the corpus's queries answer at most a few dozen times (MR8 answered on and on)
        length(out) < 10_000 ||
            error("_rcall: over 10000 answers to $(_rsrc(goal)) — answering without end?")
        at(qid, length(out) + 1)
        # the answer through the argument handles, never the caller's variables (L1b boundary,
        # user 2026-10-14: a put copies, variable identity is the handle)
        push!(out, (_ranswer(ld, _rhandles_goal(ld, goal, args, n)), rc == LK.PL_S_LAST))
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

# ── Prolog text: the program for swipl, and answers as write_canonical/1 writes them ───────────
"An atom as `write_canonical/1` writes it: a name made only of symbol characters, and the solo atoms `;` and `!`, bare."
function _ratom_text(t::_R)::String
    n = String(lk_name(t))
    !is_nil(t) && !isempty(n) && all(in("#\$&*+-./:<=>?@^~\\"), n) && return n
    !is_nil(t) && (n == ";" || n == "!") && return n             # solo characters (swipl 10.1.17)
    return lk_atom_text(t)
end

"`t` as `write_canonical/1` writes it, each variable by `var(t)`."
function _rwrite(t::_R, var)::String
    k = kind(t)
    k === VAR && return var(t)
    k === SYM && return _ratom_text(t)
    k === GND && return string(lk_value(t))
    if is_pair(t)
        elems = String[]
        while is_pair(t)
            push!(elems, _rwrite(child(t, 2), var))
            t = child(t, 3)
        end
        return "[" * join(elems, ",") * (is_nil(t) ? "" : "|" * _rwrite(t, var)) * "]"
    end
    return _rwrite(child(t, 1), var) * "(" *
           join((_rwrite(child(t, i), var) for i in 2:nchildren(t)), ",") * ")"
end

_rsrc(t::_R)::String = _rwrite(t, v -> "V$(var_key(v))")

"`write_canonical/1` of `t`: repeated variables `A, B, …` by first occurrence, singletons `_`."
function _rcanonical(t::_R)::String
    counts = Dict{UInt64, Int}()
    order = UInt64[]
    function count!(u)
        if kind(u) === VAR
            c = get(counts, var_key(u), 0)
            c == 0 && push!(order, var_key(u))
            counts[var_key(u)] = c + 1
        elseif kind(u) === EXPR
            foreach(i -> count!(child(u, i)), 1:nchildren(u))
        end
    end
    count!(t)
    names = Dict{UInt64, String}()
    for k in order
        counts[k] > 1 && (names[k] = string('A' + length(names)))
    end
    return _rwrite(t, u -> get(names, var_key(u), "_"))
end

"`goal` rebuilt from its `n` argument handles at `args` (the answer is read through them)."
function _rhandles_goal(ld::LK.PL_local_data{_R}, goal::_R, args::Int, n::Int)::_R
    n == 0 && return goal
    return mk_expr(_R, _R[child(goal, 1); [LK.slotValue(ld, args + i) for i in 1:n]])
end

"""
The goal's answer as written: `cyclic` for a rational tree — without the occurs check a body can bind
`X = f(X)`; swipl's `cyclic_term/1` and the kernel's `resolve_term` refusal must then agree.
"""
function _ranswer(ld::LK.PL_local_data{_R}, goal::_R)::String
    t = try
        LK.resolve_term(ld, goal)
    catch e
        e isa ArgumentError && occursin("cyclic", e.msg) && return "cyclic"
        rethrow()
    end
    return _rcanonical(t)
end

# A clause that ends in a symbol-character atom (`p :- $`) gets a space before its end: `$.` is
# one atom to the reader.
function _rclause_text(h::_R, b)::String
    t = b === nothing ? _rsrc(h) : _rsrc(h) * " :- " * _rsrc(b)
    return t * (last(t) in "#\$&*+-./:<=>?@^~\\" ? " ." : ".")
end

# Each query's answers, then `end`: `G det|nondet` per answer — deterministic when the goal left no
# choice point (`call_cleanup/2` ran its cleanup), as `PL_S_LAST` reports it.
const _R_DRIVER = raw"""
:- style_check(-singleton).
:- style_check(-no_effect).
r(G) :- ( call_cleanup(G, Det = true), ( Det == true -> D = det ; D = nondet ),
          ( cyclic_term(G) -> write(cyclic) ; write_canonical(G) ), write(' '), write(D), nl,
          fail ; true ), write(end), nl.
"""

const _R_SWIPL = Sys.which("swipl") !== nothing
const _R_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"
_R_SWIPL || !_R_SWIPL_REQUIRED ||
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the rules differential would be skipped"
    )

"swipl's output for `clauses` and `goal(s)` (`r/1` each), as lines; or `main_text` run as is."
function _rswipl(clauses, goals; extra::String="", main_text::String="")::Vector{String}
    mktempdir() do d
        f = joinpath(d, "r.pl")
        io = IOBuffer()
        print(io, _R_DRIVER)
        print(io, extra)
        for (h, b) in clauses
            println(io, _rclause_text(h, b))
        end
        if isempty(main_text)
            println(io, "main :- ", join(("r($(_rsrc(g)))" for g in goals), ", "), ".")
        else
            println(io, main_text)
        end
        write(f, String(take!(io)))
        out = read(
            pipeline(ignorestatus(`swipl -q -g main -t halt $f`); stdin=devnull), String
        )
        return [String(l) for l in split(strip(out), '\n') if !isempty(l)]
    end
end

"The kernel's lines for `goals`, in `_R_DRIVER`'s format."
function _rlines(db::_RDB, goals)::Vector{String}
    out = String[]
    for g in goals
        for (a, det) in _rcall(db, g)
            push!(out, a * (det ? " det" : " nondet"))
        end
        push!(out, "end")
    end
    return out
end

"A database holding `clauses`."
function _rdb(clauses)::_RDB
    db = _RDB()
    for (h, b) in clauses
        _radd!(db, h, b)
    end
    return db
end

# ── the record pools hold exactly the live records ──────────────────────────────────────────────
"""
At an answer: the pools hold the LIVE records — the choice points on the `BFR` chain, and the
frames on the parent chains of the current frame and of the choice points' frames — plus the
choice-point records `C_SOFTCUT` unlinked (`unlinked`) whose stack region is still in use, i.e.
that lie below `lTop`; nothing else. So a record a drop missed (MQ6: an exit that does not lower
`lTop`) is a record too many, a record on the chain is never marked unlinked, and one off the
chain always is (user, 2026-10-05; restated 2026-10-12 for `*->`).
"""
function _rpools_live(ld::LK.PL_local_data{_R})::Bool
    nch = 0
    c = ld.BFR
    fr = Set{Int}()
    chain = Set{Int}()
    while c != 0
        push!(chain, c)
        ld.choices[c].unlinked && return false              # on the chain: not unlinked
        c = ld.choices[c].parent
    end
    for i in 1:(ld.nchoices)                                # off the chain: unlinked, region in use
        i in chain && continue
        (ld.choices[i].unlinked && ld.choices[i].base < ld.lTop) || return false
        nch += 1
    end
    all(i -> i <= ld.nchoices, chain) || return false
    c = ld.BFR
    while c != 0
        nch += 1
        f = ld.choices[c].frame
        while f != 0 && !(f in fr)
            push!(fr, f)
            f = ld.frames[f].parent
        end
        c = ld.choices[c].parent
    end
    f = ld.environment_frame
    while f != 0 && !(f in fr)
        push!(fr, f)
        f = ld.frames[f].parent
    end
    return nch == ld.nchoices && length(fr) == ld.nframes &&
           (isempty(fr) || maximum(fr) == ld.nframes)
end

"Every instruction in clause `cl`'s code."
function _rops(cl)::Vector{UInt64}
    ops = UInt64[]
    pc = LK.Code(cl, 1)
    while pc.pc <= length(cl.codes)
        push!(ops, LK.decode(pc))
        pc = LK.stepPC(pc)
    end
    return ops
end

_ror(a::_R, b::_R) = _rf(";", a, b)

"A random body of `,` and `;` over `n/1`, `m/1`, the inline goals and `!` on `vars`."
function _rorbody(rng, vars::Vector{_R}, depth::Int)::_R
    r = rand(rng)
    if depth < 4 && r < 0.3
        return _ror(_rorbody(rng, vars, depth + 1), _rorbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.55
        return _rf(",", _rorbody(rng, vars, depth + 1), _rorbody(rng, vars, depth + 1))
    end
    v() = rand(rng, vars)
    c() = rand(rng, (_rg(1), _rg(2), _rs("a"), _rs("z")))
    r = rand(rng, 1:14)
    r <= 3 && return _rf("n", v())
    r <= 5 && return _rf("m", v())
    r <= 7 && return _rf("=", v(), rand(rng, Bool) ? c() : v())
    r == 8 && return _rf("==", v(), c())
    r == 9 && return _rf("\\==", v(), rand(rng, Bool) ? c() : v())
    r == 10 && return _rf(rand(rng, ("var", "nonvar")), v())
    r == 11 && return _rs("!")
    r == 12 && return _rs("fail")
    r == 13 && return _rf("=", v(), _rf("f", v()))
    return _rs("true")
end

_rite(a::_R, b::_R, c::_R) = _ror(_rf("->", a, b), c)
_rit(a::_R, b::_R) = _rf("->", a, b)

_rnot(a::_R) = _rf("\\+", a)

const _R_SENTINEL = _rs(Symbol("\$lk_sentinel"))

"""
The highest local-stack position written while `goal` finds its first answer, relative to the query
(a sentinel fill: TEST instrumentation, user 2026-10-05), with growth turned into an error (the
`lMax` tripwire); and the trail and binding store at the answer.
"""
function _rhighwater(db::_RDB, goal::_R)::Tuple{Int, Int, Int}
    gd, ld = db.gd, db.ld
    saved_limit = ld.stacks_limit
    ld.stacks_limit = ld.lMax                                       # growth would raise
    _, n = _rfunctor(goal)
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, n)
    pvm = LK.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    for i in 1:n
        LK.putSlotValue!(ld, args + i, child(goal, i + 1), pvm)
    end
    fill!(view(ld.slots, (ld.lTop + 1):length(ld.slots)), _R_SENTINEL)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, goal), args
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    if rc != LK.PL_S_LAST                                           # the tripwire: say what tripped
        ex = rc == LK.PL_S_EXCEPTION ? LK.PL_exception(ld, qid) : 0
        ball = ex == 0 ? "none" : string(LK.slotValue(ld, ex + 1))
        error("_rhighwater: $(_rsrc(goal)) returned $rc, ball $ball (growth past lMax?)")
    end
    high = findlast(t -> t !== _R_SENTINEL, ld.slots) - 1           # a position: slots[p + 1]
    tr, st = length(ld.trail), lk_bound_count(ld)
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    ld.stacks_limit = saved_limit
    return (high - qid, tr, st)
end
