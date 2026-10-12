# ORIGINAL: rules through the VM — calls, last calls and body arguments (V4b) — against swipl 10.1.16; upstream has no such harness.
# test/core_lang/test_rules_swipl.jl — V4b's gate (port_inventory row V4b; user's decisions 2026-10-05):
#   * nreverse: the answer and its determinism identical to swipl's (`PL_S_LAST`, the next term
#     reference at +45 — libswipl's own, probed);
#   * an EXECUTION DIFFERENTIAL over random rule clauses: every answer and its determinism identical
#     to swipl's, with the body family covered — each instruction of it compiled in the corpus;
#   * a frame that fails before it is filled (`S_LIST`, vmi:3607-3608): dropped where `deep_backtrack`
#     leaves it, and swipl's answers;
#   * POSITIONS after a deterministic exit (MQ6): seven clauses as swipl's `prolog_current_frame/1`
#     and `prolog_current_choice/1` differences — the real built-ins, reached from `user` through
#     `autoImport` (since V5c), pinned and live — and libswipl's query API, pinned (the first term
#     reference after an answer); at every answer the record pools hold exactly the live records;
#   * FLATNESS: concatenate/3 on 10^3, 10^4, 10^5 elements reaches the same high-water mark, read by a
#     sentinel fill of the slots and with growth turned into an error — and with
#     `last_call_optimisation` off the mark grows, so the check can fail; the trail and the binding
#     store at the answer, reported (they grow until the store's collector exists);
#   * 10^4 open/next/close cycles of nreverse leave the stacks, the trail and the store at their
#     baseline every cycle;
#   * warm, a query of calls and exits allocates nothing (reference type).
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel

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
    for i in 1:n
        ld.slots[args + i] = child(goal, i + 1)            # term reference args + (i - 1)
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
        push!(out, (_ranswer(ld, goal), rc == LK.PL_S_LAST))
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

# ── Prolog text: the program for swipl, and answers as write_canonical/1 writes them ───────────
"An atom as `write_canonical/1` writes it: a name made only of symbol characters bare."
function _ratom_text(t::_R)::String
    n = String(lk_name(t))
    !is_nil(t) && !isempty(n) && all(in("#\$&*+-./:<=>?@^~\\"), n) && return n
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

_rclause_text(h::_R, b) =
    b === nothing ? _rsrc(h) * "." : _rsrc(h) * " :- " * _rsrc(b) * "."

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

# ── nreverse (bench/programs/nreverse.pl) ───────────────────────────────────────────────────────
function _rnreverse_clauses()
    X, L0, L, L1, L2, L3 = (_rv(k) for k in 1:6)
    return [
        (_rs("top"), _rs("nreverse")),
        (_rs("nreverse"), _rf("nreverse", _rints(1:30), _rv(7))),
        (_rf("nreverse", _rcons(X, L0), L),
            _rconj(_rf("nreverse", L0, L1), _rf("concatenate", L1, _rlist(X), L))),
        (_rf("nreverse", _rnil(), _rnil()), nothing),
        (
            _rf("concatenate", _rcons(X, L1), L2, _rcons(X, L3)),
            _rf("concatenate", L1, L2, L3)
        ),
        (_rf("concatenate", _rnil(), L, L), nothing)
    ]
end

@testset "nreverse: the answer and its determinism are swipl's" begin
    clauses = _rnreverse_clauses()
    db = _rdb(clauses)
    goals = [_rf("nreverse", _rints(1:30), _rv(100)), _rs("nreverse"), _rs("top")]
    ours = _rlines(db, goals)
    @test ours == [
        "nreverse([" * join(1:30, ",") * "],[" * join(30:-1:1, ",") * "]) det", "end",
        "nreverse det", "end", "top det", "end"
    ]
    # the next term reference after the answer at +45, as libswipl's (probed, V4b research)
    tref(qid) = (t=LK.PL_new_term_ref(db.ld); LK.PL_reset_term_refs(db.ld, t); t - qid)
    trefs = Int[]
    _rcall(db, _rs("nreverse"); at=(qid, k) -> push!(trefs, tref(qid)))
    @test trefs == [45]
    if _R_SWIPL
        @test _rswipl(clauses, goals) == ours
    end
end

# ── poly_10 (bench/programs/poly_10.pl), V8 ─────────────────────────────────────────────────────
"poly_10.pl's clauses as terms, in file order (bench/programs/poly_10.pl)."
function _rpoly_clauses()
    (Var, Terms1, Terms2, Terms, Var1, Var2, Poly, C, C1, C2, X, E, E1, E2, N, M, Part,
        Result, P,
        Q, Term, PartA, PartB, NewTerm, NewTerms) = (_rv(k) for k in 1:25)
    term(a, b) = _rf("term", a, b)
    poly(a, b) = _rf("poly", a, b)
    one = _rg(1)
    cut = _rs("!")
    return [
        (_rs("top"), _rs("poly_10")),
        (_rs("poly_10"), _rconj(_rf("test_poly", P), _rf("poly_exp", _rg(10), P, _rv(99)))),
        (
            _rf("test_poly", P),
            _rconj(
                _rf(
                    "poly_add",
                    poly(_rs(:x), _rlist(term(_rg(0), one), term(one, one))),
                    poly(_rs(:y), _rlist(term(one, one))),
                    Q
                ),
                _rf("poly_add", poly(_rs(:z), _rlist(term(one, one))), Q, P)
            )
        ),
        (_rf("less_than", _rs(:x), _rs(:y)), nothing),
        (_rf("less_than", _rs(:y), _rs(:z)), nothing),
        (_rf("less_than", _rs(:x), _rs(:z)), nothing),
        (
            _rf("poly_add", poly(Var, Terms1), poly(Var, Terms2), poly(Var, Terms)),
            _rconj(cut, _rf("term_add", Terms1, Terms2, Terms))
        ),
        (
            _rf("poly_add", poly(Var1, Terms1), poly(Var2, Terms2), poly(Var1, Terms)),
            _rconj(
                _rf("less_than", Var1, Var2),
                cut,
                _rf("add_to_order_zero_term", Terms1, poly(Var2, Terms2), Terms)
            )
        ),
        (
            _rf("poly_add", Poly, poly(Var, Terms2), poly(Var, Terms)),
            _rconj(cut, _rf("add_to_order_zero_term", Terms2, Poly, Terms))
        ),
        (
            _rf("poly_add", poly(Var, Terms1), C, poly(Var, Terms)),
            _rconj(cut, _rf("add_to_order_zero_term", Terms1, C, Terms))
        ),
        (_rf("poly_add", C1, C2, C), _rf("is", C, _rf("+", C1, C2))),
        (_rf("term_add", _rnil(), X, X), cut),
        (_rf("term_add", X, _rnil(), X), cut),
        (
            _rf(
                "term_add",
                _rcons(term(E, C1), Terms1),
                _rcons(term(E, C2), Terms2),
                _rcons(term(E, C), Terms)
            ),
            _rconj(cut, _rf("poly_add", C1, C2, C), _rf("term_add", Terms1, Terms2, Terms))
        ),
        (
            _rf(
                "term_add",
                _rcons(term(E1, C1), Terms1),
                _rcons(term(E2, C2), Terms2),
                _rcons(term(E1, C1), Terms)
            ),
            _rconj(
                _rf("<", E1, E2),
                cut,
                _rf("term_add", Terms1, _rcons(term(E2, C2), Terms2), Terms)
            )
        ),
        (
            _rf(
                "term_add",
                Terms1,
                _rcons(term(E2, C2), Terms2),
                _rcons(term(E2, C2), Terms)
            ),
            _rf("term_add", Terms1, Terms2, Terms)
        ),
        (
            _rf(
                "add_to_order_zero_term",
                _rcons(term(_rg(0), C1), Terms),
                C2,
                _rcons(term(_rg(0), C), Terms)
            ),
            _rconj(cut, _rf("poly_add", C1, C2, C))
        ),
        (_rf("add_to_order_zero_term", Terms, C, _rcons(term(_rg(0), C), Terms)), nothing),
        (_rf("poly_exp", _rg(0), _rv(98), one), cut),
        (
            _rf("poly_exp", N, Poly, Result),
            _rconj(
                _rf("is", M, _rf(">>", N, one)),
                _rf("is", N, _rf("<<", M, one)),
                cut,
                _rf("poly_exp", M, Poly, Part),
                _rf("poly_mul", Part, Part, Result)
            )
        ),
        (
            _rf("poly_exp", N, Poly, Result),
            _rconj(
                _rf("is", M, _rf("-", N, one)),
                _rf("poly_exp", M, Poly, Part),
                _rf("poly_mul", Poly, Part, Result)
            )
        ),
        (
            _rf("poly_mul", poly(Var, Terms1), poly(Var, Terms2), poly(Var, Terms)),
            _rconj(cut, _rf("term_mul", Terms1, Terms2, Terms))
        ),
        (
            _rf("poly_mul", poly(Var1, Terms1), poly(Var2, Terms2), poly(Var1, Terms)),
            _rconj(
                _rf("less_than", Var1, Var2),
                cut,
                _rf("mul_through", Terms1, poly(Var2, Terms2), Terms)
            )
        ),
        (
            _rf("poly_mul", P, poly(Var, Terms2), poly(Var, Terms)),
            _rconj(cut, _rf("mul_through", Terms2, P, Terms))
        ),
        (
            _rf("poly_mul", poly(Var, Terms1), C, poly(Var, Terms)),
            _rconj(cut, _rf("mul_through", Terms1, C, Terms))
        ),
        (_rf("poly_mul", C1, C2, C), _rf("is", C, _rf("*", C1, C2))),
        (_rf("term_mul", _rnil(), _rv(97), _rnil()), cut),
        (_rf("term_mul", _rv(96), _rnil(), _rnil()), cut),
        (
            _rf("term_mul", _rcons(Term, Terms1), Terms2, Terms),
            _rconj(
                _rf("single_term_mul", Terms2, Term, PartA),
                _rf("term_mul", Terms1, Terms2, PartB),
                _rf("term_add", PartA, PartB, Terms)
            )
        ),
        (_rf("single_term_mul", _rnil(), _rv(95), _rnil()), cut),
        (
            _rf(
                "single_term_mul",
                _rcons(term(E1, C1), Terms1),
                term(E2, C2),
                _rcons(term(E, C), Terms)
            ),
            _rconj(
                _rf("is", E, _rf("+", E1, E2)),
                _rf("poly_mul", C1, C2, C),
                _rf("single_term_mul", Terms1, term(E2, C2), Terms)
            )
        ),
        (_rf("mul_through", _rnil(), _rv(94), _rnil()), cut),
        (
            _rf(
                "mul_through",
                _rcons(term(E, Term), Terms),
                Poly,
                _rcons(term(E, NewTerm), NewTerms)
            ),
            _rconj(
                _rf("poly_mul", Term, Poly, NewTerm),
                _rf("mul_through", Terms, Poly, NewTerms)
            )
        )
    ]
end

# The milestone: poly_10 — A_ADD_FC (`M is N-1`), `>>`, `<<` with a BOUND left side, `<`, cuts —
# against swipl CONSULTING bench/programs/poly_10.pl; `pt/2` (test_poly then poly_exp) is the
# test's own, given to both sides.
@testset "poly_10: every answer and its determinism are swipl's (the V8 milestone)" begin
    N, P, R = _rv(31), _rv(32), _rv(33)
    pt = (_rf("pt", N, R), _rconj(_rf("test_poly", P), _rf("poly_exp", N, P, R)))
    db = _rdb([_rpoly_clauses(); pt])
    goals = [_rf("test_poly", _rv(100)), _rf("pt", _rg(1), _rv(100)),
        _rf("pt", _rg(2), _rv(100)),
        _rf("pt", _rg(3), _rv(100)), _rf("pt", _rg(10), _rv(100)), _rs("poly_10"),
        _rs("top")]
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    @test all(l -> l == "end" || endswith(l, " det"), ours)              # every call is deterministic
    @test occursin("term(0,1)", ours[1])
    if _R_SWIPL
        file = joinpath(@__DIR__, "..", "..", "bench", "programs", "poly_10.pl")
        prog = IOBuffer()
        println(prog, ":- style_check(-singleton).")
        println(prog, ":- consult('", file, "').")
        println(prog, "pt(N, R) :- test_poly(P), poly_exp(N, P, R).")
        println(
            prog,
            "r(G) :- ( call_cleanup(G, Det = true), ( Det == true -> D = det ; D = nondet ),"
        )
        println(
            prog,
            "     write_term(G, [quoted(true), ignore_ops(true)]), write(' '), write(D), nl,"
        )
        println(prog, "     fail ; true ), write(end), nl.")
        println(
            prog,
            ":- initialization((",
            join(("r(" * _rsrc(g) * ")" for g in goals), ", "),
            ", halt))."
        )
        theirs = mktempdir() do dir
            f = joinpath(dir, "p.pl")
            write(f, String(take!(prog)))
            split(strip(read(pipeline(`swipl -q $f`; stdin=devnull), String)), '\n')
        end
        @test ours == theirs
        ours == theirs || foreach(
            ((o, t),) ->
                o == t || println(stderr, "  ours  ", first(o, 300),
                    "\n  swipl ", first(t, 300)), zip(ours, theirs))
    end
end

# ── qsort (bench/programs/qsort.pl), V7 ─────────────────────────────────────────────────────────
const _R_QSORT_NUMS = [27, 74, 17, 33, 94, 18, 46, 83, 65, 2, 32, 53, 28, 85, 99, 47, 28,
    82, 6,
    11, 55, 29, 39, 81, 90, 37, 10, 0, 66, 51, 7, 21, 85, 27, 31, 63, 75, 4, 95, 99, 11, 28,
    61, 74,
    18, 92, 40, 53, 59, 8]
"qsort.pl's clauses as terms, in file order."
function _rqsort_clauses()
    X, L, R, R0, L1, L2, R1, Y = (_rv(k) for k in 1:8)
    return [
        (_rs("top"), _rs("qsort")),
        (
            _rs("qsort"),
            _rf("qsort", _rlist((_rg(i) for i in _R_QSORT_NUMS)...), _rv(9), _rnil())
        ),
        (_rf("qsort", _rcons(X, L), R, R0),
            _rconj(_rf("partition", L, X, L1, L2), _rf("qsort", L2, R1, R0),
                _rf("qsort", L1, R, _rcons(X, R1)))),
        (_rf("qsort", _rnil(), R, R), nothing),
        (_rf("partition", _rcons(X, L), Y, _rcons(X, L1), L2),
            _rconj(_rf("=<", X, Y), _rs("!"), _rf("partition", L, Y, L1, L2))),
        (
            _rf("partition", _rcons(X, L), Y, L1, _rcons(X, L2)),
            _rf("partition", L, Y, L1, L2)
        ),
        (_rf("partition", _rnil(), _rv(10), _rnil(), _rnil()), nothing)
    ]
end

# The milestone: qsort — `=</2` called from a body (V6c1's built-in), a cut after it (V6a) — its
# answer and determinism identical to swipl's on the same clauses.
@testset "qsort: the answer and its determinism are swipl's (the V7 milestone)" begin
    clauses = _rqsort_clauses()
    db = _rdb(clauses)
    lst = _rlist((_rg(i) for i in _R_QSORT_NUMS)...)
    goals = [_rf("qsort", lst, _rv(100), _rnil()), _rs("qsort"), _rs("top"),
        _rf("partition", lst, _rg(50), _rv(101), _rv(102))]
    ours = _rlines(db, goals)
    @test ours[1] ==
        "qsort([" * join(_R_QSORT_NUMS, ",") * "],[" *
          join(sort(_R_QSORT_NUMS), ",") * "],[]) det"
    @test ours[2:end] == ["end", "qsort det", "end", "top det", "end",
        "partition([" * join(_R_QSORT_NUMS, ",") * "],50,[" *
        join(filter(<=(50), _R_QSORT_NUMS), ",") * "],[" *
        join(filter(>(50), _R_QSORT_NUMS), ",") * "]) det", "end"]
    if _R_SWIPL
        @test _rswipl(clauses, goals) == ours
    end
end

# ── derive (bench/programs/derive.pl), V6c2 ─────────────────────────────────────────────────────
"derive.pl's clauses as terms, in file order."
function _rderive_clauses()
    U, V, X, DU, DV, N, N1 = (_rv(k) for k in 1:7)
    x = _rs(:x)
    pw(a, b) = _rf("^", a, b)
    d(a, b, c) = _rf("d", a, b, c)
    nest(f, t, n) = n == 0 ? t : nest(f, f(t), n - 1)
    cut = _rs("!")
    return [
        (_rs("top"), _rconj(_rs("ops8"), _rs("log10"), _rs("divide10"))),
        (_rs("ops8"), d(_rderive_input(:ops8), x, _rv(20))),
        (_rs("log10"), d(_rderive_input(:log10), x, _rv(20))),
        (_rs("divide10"), d(_rderive_input(:divide10), x, _rv(20))),
        (d(_rf("+", U, V), X, _rf("+", DU, DV)), _rconj(cut, d(U, X, DU), d(V, X, DV))),
        (d(_rf("-", U, V), X, _rf("-", DU, DV)), _rconj(cut, d(U, X, DU), d(V, X, DV))),
        (d(_rf("*", U, V), X, _rf("+", _rf("*", DU, V), _rf("*", U, DV))),
            _rconj(cut, d(U, X, DU), d(V, X, DV))),
        (
            d(
                _rf("/", U, V),
                X,
                _rf("/", _rf("-", _rf("*", DU, V), _rf("*", U, DV)), pw(V, _rg(2)))
            ),
            _rconj(cut, d(U, X, DU), d(V, X, DV))),
        (d(pw(U, N), X, _rf("*", _rf("*", DU, N), pw(U, N1))),
            _rconj(cut, _rf("integer", N), _rf("is", N1, _rf("-", N, _rg(1))), d(U, X, DU))
        ),
        (d(_rf("-", U), X, _rf("-", DU)), _rconj(cut, d(U, X, DU))),
        (d(_rf("exp", U), X, _rf("*", _rf("exp", U), DU)), _rconj(cut, d(U, X, DU))),
        (d(_rf("log", U), X, _rf("/", DU, U)), _rconj(cut, d(U, X, DU))),
        (d(X, X, _rg(1)), cut),
        (d(_rv(21), _rv(22), _rg(0)), nothing)
    ]
end

"The input expression of derive's `ops8`, `log10` or `divide10`."
function _rderive_input(which::Symbol)::_R
    x = _rs(:x)
    pw(a, b) = _rf("^", a, b)
    nest(f, t, n) = n == 0 ? t : nest(f, f(t), n - 1)
    which === :ops8 && return _rf("*", _rf("+", x, _rg(1)),
        _rf("*", _rf("+", pw(x, _rg(2)), _rg(2)), _rf("+", pw(x, _rg(3)), _rg(3))))
    which === :log10 && return nest(t -> _rf("log", t), x, 10)
    return nest(t -> _rf("/", t, x), x, 9)
end

# The milestone: derive, its clauses by hand (R1 will load the file), against swipl CONSULTING
# bench/programs/derive.pl. Answers in functional notation on both sides (swipl's
# `write_term(…, [quoted(true), ignore_ops(true)])`), determinism by `call_cleanup/2`.
@testset "derive: every answer and its determinism are swipl's (the V6 milestone)" begin
    db = _rdb(_rderive_clauses())
    goals = [
        _rf("d", _rderive_input(:ops8), _rs(:x), _rv(100)),
        _rf("d", _rderive_input(:log10), _rs(:x), _rv(100)),
        _rf("d", _rderive_input(:divide10), _rs(:x), _rv(100)),
        _rf("d", _rf("^", _rs(:x), _rs(:a)), _rs(:x), _rv(100)),          # fails: the cut precedes integer/1
        _rf("d", _rs(:x), _rs(:x), _rv(100)), _rf("d", _rg(3), _rs(:x), _rv(100)),
        _rs("ops8"), _rs("log10"), _rs("divide10"), _rs("top")
    ]
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    @test all(l -> l == "end" || endswith(l, " det"), ours)              # every call is deterministic
    @test count(l -> startswith(l, "d("), ours) == 5                     # five d/3 answers, one fails
    if _R_SWIPL
        file = joinpath(@__DIR__, "..", "..", "bench", "programs", "derive.pl")
        prog = IOBuffer()
        println(prog, ":- style_check(-singleton).")
        println(prog, ":- consult('", file, "').")
        println(
            prog,
            "r(G) :- ( call_cleanup(G, Det = true), ( Det == true -> D = det ; D = nondet ),"
        )
        println(
            prog,
            "     write_term(G, [quoted(true), ignore_ops(true)]), write(' '), write(D), nl,"
        )
        println(prog, "     fail ; true ), write(end), nl.")
        println(
            prog,
            ":- initialization((",
            join(("r(" * _rsrc(g) * ")" for g in goals), ", "),
            ", halt))."
        )
        theirs = mktempdir() do dir
            f = joinpath(dir, "d.pl")
            write(f, String(take!(prog)))
            split(strip(read(pipeline(`swipl -q $f`; stdin=devnull), String)), '\n')
        end
        @test ours == theirs
        ours == theirs ||
            foreach(((o, t),) -> o == t || println(stderr, "  ours  ", o, "\n  swipl ", t),
                zip(ours, theirs))
    end
end

# ── the execution differential over random rule clauses ─────────────────────────────────────────
# The body family V4b executes; the corpus must compile each of them (static coverage — every
# predicate of every program is called).
const _R_FAMILY = (
    LK.B_ARGVAR, LK.B_VAR0, LK.B_VAR1, LK.B_VAR2, LK.B_VAR, LK.B_ARGFIRSTVAR, LK.B_FIRSTVAR,
    LK.B_VOID, LK.B_FUNCTOR, LK.B_RFUNCTOR, LK.B_LIST, LK.B_RLIST, LK.B_POP, LK.B_ATOM,
    LK.B_SMALLINT, LK.B_NIL, LK.I_ENTER, LK.I_CALL, LK.I_DEPART, LK.L_NOLCO, LK.L_VAR,
    LK.L_VOID, LK.L_ATOM, LK.L_NIL, LK.L_SMALLINT, LK.I_LCALL, LK.I_TCALL, LK.I_CUT,
    LK.I_INTEGER, LK.I_ATOM, LK.I_VAR, LK.I_NONVAR, LK.I_ATOMIC, LK.I_COMPOUND
)

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

mutable struct _RGen
    next::Int                       # the next fresh variable key
    vars::Vector{_R}                # variables seen in this clause
end

_rconst(rng) = rand(
    rng, (_rs(:a), _rs(:b), _rg(1), _rg(2), _rnil(), _rlist(_rs(:a)), _rf(:f, _rs(:a)))
)
function _rnewvar!(g::_RGen)
    g.next += 1
    return _rv(g.next)
end

"A body argument: a variable seen or new, a singleton, a constant, a compound or a list."
function _rarg(rng, g::_RGen, depth::Int)::_R
    r = rand(rng)
    if r < 0.30 && !isempty(g.vars)
        return rand(rng, g.vars)
    elseif r < 0.48
        v = _rnewvar!(g)
        push!(g.vars, v)
        return v
    elseif r < 0.56
        return _rnewvar!(g)                                 # used once: a singleton
    elseif r < 0.76 || depth >= 2
        return _rconst(rng)
    elseif r < 0.88
        return if rand(rng, Bool)
            _rf(:f, _rarg(rng, g, depth + 1))
        else
            _rf(:g, _rarg(rng, g, depth + 1), _rarg(rng, g, depth + 1))
        end
    else
        t = rand(rng, Bool) ? _rnil() : _rarg(rng, g, depth + 1)
        return _rcons(_rarg(rng, g, depth + 1), t)
    end
end

"""
A random program, layered so every query terminates, suffixed `_i`: facts, fixed rules that cover
the last-call forms and the cut's paths, and random rules over them; and a query for every
predicate. What V6 adds at random — where a body gets a `!` (V6a), a value `tsel_i` is asked about
(V6b) — is drawn from `crng`, so the rest of each program is what V4b's corpus drew.
"""
function _rprogram(rng, i::Int, crng)
    p(n) = "$(n)_$i"
    clauses = Tuple{_R, Union{Nothing, _R}}[]
    goals = _R[]
    for _ in 1:rand(rng, 2:4)
        push!(clauses, (_rf(p("e1"), _rconst(rng), _rconst(rng)), nothing))
    end
    for _ in 1:rand(rng, 1:3)
        push!(clauses, (_rf(p("e2"), _rconst(rng)), nothing))
    end
    push!(clauses, (_rf(p("e3"), _rv(1), _rv(2)), nothing))
    push!(clauses, (_rf(p("lt"), _rv(1), _rv(2), _rv(3), _rv(4), _rv(5)), nothing))
    H, T, L, R, X, Y, A, B, C, D = (_rv(k) for k in 11:20)
    fixed = [   # the last-call forms and the body family, whatever the random part draws
        (_rf(p("app"), _rnil(), L, L), nothing),                                     # I_TCALL
        (_rf(p("app"), _rcons(H, T), L, _rcons(H, R)), _rf(p("app"), T, L, R)),
        (_rf(p("walk"), _rnil(), X, X), nothing),
        (_rf(p("walk"), _rcons(_rv(21), T), A, B), _rf(p("walk"), T, A, B)),
        (_rf(p("lblk"), X, Y),                                     # L_VAR/ATOM/NIL/SMALLINT/VOID
            _rconj(_rf(p("e1"), X, Y), _rf(p("lt"), Y, _rs(:a), _rnil(), _rg(1), _rv(22)))),
        (_rf(p("bld"), X, Y),                                      # B_FUNCTOR … B_POP, B_ARG*
            _rf(p("e3"), _rf(:f, _rs(:a), _rf(:g, X, _rcons(Y, T)), _rlist(_rg(1), X)), T)),
        (_rf(p("nd"), X), _rconj(_rf(p("e2"), X), _rf(p("e2"), Y), _rf(p("e3"), X, Y))),  # L_NOLCO's jump
        (_rf(p("four"), A, B, C, D),                                                 # B_VAR0..2, B_VAR
            _rconj(_rf(p("e3"), A, B), _rf(p("e3"), C, D), _rf(p("e3"), D, A))),
        (_rs(p("top")), _rf(p("nd"), _rv(23))),                                      # I_LCALL
        # a variable FIRST seen inside a body compound (B_ARGFIRSTVAR) and read back from its slot
        # by a later call (B_VAR*), routed into the answer — invisible otherwise (MR12)
        (_rf(p("ef"), _rf(:f, _rs(:a))), nothing), (_rf(p("eq"), X, X), nothing),
        (_rf(p("afv"), Y), _rconj(_rf(p("ef"), _rf(:f, T)), _rf(p("eq"), T, Y))),
        # the cut's paths (V6a): after a non-deterministic call, mid-body, first, with nothing to
        # cut, the clause's own clause choice point, callee frames that hold choice points, and a
        # cut in a clause shallow backtracking moved to
        (_rf(p("cnd"), X, Y), _rconj(_rf(p("e1"), X, Y), _rs("!"))),
        (_rf(p("cmid"), X), _rconj(_rf(p("e1"), X, Y), _rs("!"), _rf(p("e2"), Y))),
        (_rf(p("cfirst"), X), _rconj(_rs("!"), _rf(p("e2"), X))),
        (_rf(p("cfirst"), _rs(:z)), nothing),
        (_rf(p("cdet"), X), _rconj(_rf(p("e3"), X, _rs(:a)), _rs("!"))),
        (_rf(p("cown"), X), _rconj(_rf(p("e2"), X), _rs("!"))),
        (_rf(p("cown"), _rs(:b)), nothing),
        (_rf(p("cdeep"), X), _rconj(_rf(p("nd"), X), _rs("!"))),
        (_rf(p("clast"), X), _rf(p("e2"), X)),
        (_rf(p("clast"), X), _rconj(_rs("!"), _rf(p("e1"), X, _rv(24)))),
        (_rf(p("clast"), _rs(:c)), nothing),
        # the type tests (V6b): inline on a seen variable, failing into the frame's own clause
        # choice point (FASTCOND_FAILED → shallow backtracking) or into a callee's (→ deep); and the
        # fall-back calls of the other shapes
        (_rf(p("tsel"), X, _rs(:int)), _rf("integer", X)),
        (_rf(p("tsel"), X, _rs(:atm)), _rf("atom", X)),
        (_rf(p("tsel"), X, _rs(:cmp)), _rconj(_rf("compound", X), _rs("!"))),
        (_rf(p("tsel"), _rv(25), _rs(:other)), nothing),
        (_rf(p("tnd"), X), _rconj(_rf(p("e1"), X, _rv(26)), _rf("atomic", X))),
        (_rf(p("tv"), X, Y), _rconj(_rf("var", X), _rf(p("e2"), Y))),
        (_rf(p("tnv"), X), _rconj(_rf(p("e1"), X, Y), _rf("nonvar", Y))),
        (
            _rf(p("tfb"), Y),
            _rconj(_rf(p("e2"), Y), _rf("number", _rg(3)), _rf("atom", _rv(27)))
        ),
        (_rf(p("tfb2"), Y), _rconj(_rf("callable", _rf(:f, Y)), _rf(p("e2"), Y)))
    ]
    append!(clauses, fixed)
    callable = [(p("e1"), 2), (p("e2"), 1), (p("e3"), 2)]
    for r in 1:2, _ in 1:2                                         # r1_i/3, r2_i/3: two clauses each
        g = _RGen(30, _R[])
        head = _rf(
            p("r$r"),
            (
                rand(rng) < 0.7 ? (v=_rnewvar!(g); push!(g.vars, v); v) : _rconst(rng)
                for _ in 1:3
            )...
        )
        body = _R[]
        for _ in 1:rand(rng, 1:3)
            if rand(rng) < 0.2                                     # a recursive call on a ground list
                q = rand(rng, ("app", "walk"))
                push!(
                    body,
                    _rf(
                        p(q),
                        _rlist(_rconst(rng), _rconst(rng)),
                        _rarg(rng, g, 0),
                        _rarg(rng, g, 0)
                    )
                )
            else
                (f, n) = r == 2 && rand(rng) < 0.4 ? (p("r1"), 3) : rand(rng, callable)
                push!(body, _rf(f, (_rarg(rng, g, 0) for _ in 1:n)...))
            end
        end
        if rand(crng) < 0.35                                       # a cut somewhere in the body
            insert!(body, rand(crng, 1:(length(body) + 1)), _rs("!"))
        end
        push!(clauses, (head, _rconj(body...)))
    end
    for (f, n) in
        (callable..., (p("lblk"), 2), (p("bld"), 2), (p("nd"), 1), (p("four"), 4),
        (p("afv"), 1),
        (p("r1"), 3), (p("r2"), 3), (p("cnd"), 2), (p("cmid"), 1), (p("cfirst"), 1),
        (p("cdet"), 1), (p("cown"), 1), (p("cdeep"), 1), (p("clast"), 1), (p("tsel"), 2),
        (p("tnd"), 1), (p("tv"), 2), (p("tnv"), 1), (p("tfb"), 1), (p("tfb2"), 1))
        push!(goals, _rf(f, (_rv(40 + k) for k in 1:n)...))
    end
    push!(goals, _rs(p("top")))
    push!(goals, _rf(p("app"), _rints(1:3), _rlist(_rs(:z)), _rv(50)))
    push!(goals, _rf(p("walk"), _rints(1:4), _rs(:x), _rv(51)))
    for v in (_rg(1), _rs(:a), _rf(:f, _rs(:a)), _rnil(), _rconst(crng)) # tsel_i on each kind
        push!(goals, _rf(p("tsel"), v, _rv(52)))
    end
    push!(goals, _rf(p("tv"), _rs(:a), _rv(53)))                        # var/1 failing inline
    return clauses, goals
end

@testset "rules: every answer and its determinism are swipl's (random programs)" begin
    rng = Xoshiro(20261005)
    crng = Xoshiro(20261006)                                        # where the cuts go (V6a)
    clauses = Tuple{_R, Union{Nothing, _R}}[]
    goals = _R[]
    for i in 1:12
        c, g = _rprogram(rng, i, crng)
        append!(clauses, c)
        append!(goals, g)
    end
    db = _rdb(clauses)
    ops = Set{UInt64}()
    for (h, b) in clauses
        pr = _rproc(db, h)
        cref = pr.definition.impl_clauses.first_clause
        while cref !== nothing
            union!(ops, _rops(cref.clause))
            cref = cref.next
        end
    end
    missing_ops = [LK.codeTable(o).name for o in _R_FAMILY if !(o in ops)]
    @test isempty(missing_ops)                                      # the corpus covers the family
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals) && length(ours) > 2 * length(goals)  # answers, not only ends
    ndet = count(endswith(" nondet"), ours)
    ncyc = count(startswith("cyclic"), ours)
    @info "random rule programs: $(length(goals)) queries, $(length(ours) - length(goals)) answers ($ndet non-deterministic, $ncyc cyclic)"
    @test ndet > 0 && count(endswith(" det"), ours) > 0              # both kinds of answer occur
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    end
end

# ── V9d: disjunctions ───────────────────────────────────────────────────────────────────────────
# `;` through the VM (`C_OR`, `C_JMP`, `C_VAR`/`C_VAR_N`, backtracking into a `CHP_JUMP` choice point
# from the clause itself and from a frame below it): every answer and its determinism are swipl's.
_ror(a::_R, b::_R) = _rf(";", a, b)

"The pinned disjunction programs: facts `n/1`, `m/1`, `q4/4` and one clause per case."
function _ror_clauses()
    X, Y, Z, A, B, C, D, H, T = (_rv(k) for k in 1:9)
    n(x) = _rf("n", x)
    m(x) = _rf("m", x)
    eq(a, b) = _rf("=", a, b)
    cl = Tuple{_R, Union{Nothing, _R}}[
        (n(_rg(1)), nothing), (n(_rg(2)), nothing), (n(_rg(3)), nothing),
        (m(_rs("a")), nothing), (m(_rs("b")), nothing),
        (_rf("q4", _rg(1), _rg(2), _rg(3), _rg(4)), nothing),
        (_rf("o1", X), _ror(eq(X, _rs("a")), eq(X, _rs("b")))),
        (_rf("o2", X), _ror(n(X), m(X))),
        (_rf("o3", X, Y), _rconj(_ror(n(X), m(X)), _ror(eq(Y, _rs("p")), eq(Y, _rs("q"))))),
        (_rf("o4", X), _ror(_rconj(n(X), _rf(">", X, _rg(1))), m(X))),
        (_rf("o5", X), _ror(_rconj(n(X), _rs("!")), m(X))),          # a clause-level cut
        (_rf("o6", X, Y), _ror(eq(X, _rg(1)), eq(Y, _rg(2)))),       # each branch leaves one unset
        (_rf("o7", Y),
            _rconj(_ror(_rs("true"), _rs("fail")), _ror(eq(Z, _rg(1)), _rs("true")),
                eq(Y, _rf("f", Z)))),
        (_rf("o8", X), _rconj(_ror(_rs("fail"), n(X)), _rf(">=", X, _rg(2)))),
        (_rf("o9", X),
            _ror(_ror(eq(X, _rg(1)), eq(X, _rg(2))), _ror(eq(X, _rg(3)), _rs("fail")))),
        # the failure comes from a frame BELOW the clause: deep_backtrack into the CHP_JUMP
        (_rf("o10", X), _ror(_rconj(n(X), _rf(">", X, _rg(5))), eq(X, _rs("z")))),
        (_rf("o11", X), _rconj(_ror(n(X), eq(X, _rs("z"))), _rf("\\==", X, _rg(2)))),
        (_rf("o12", X), _ror(eq(X, _rg(0)), n(X))),                 # a last call in a branch
        (_rs("o13"), _ror(_rs("fail"), _rs("true"))),
        (_rf("o14", X, Y),
            _rconj(_ror(eq(X, _rg(1)), _ror(eq(X, _rg(2)), eq(X, _rg(3)))), n(Y),
                _rf(">", Y, X))),
        (_rf("o15", A, B, C, D), _ror(_rf("q4", A, B, C, D), _rs("true"))),   # nothing to balance
        (_rf("o16", X),
            _rconj(_ror(_rf("q4", A, B, C, D), _rs("true")), eq(X, _rf("r", A, B, C, D)))),
        (_rf("o17", X),                                              # C_VAR_N and a C_VAR
            _rconj(_ror(_rs("fail"), _ror(_rf("q4", A, B, C, _rg(4)), _rs("true"))),
                eq(X, _rf("r", A, B, C)))),
        (_rf("mem", X, _rcons(H, T)), _ror(eq(X, H), _rf("mem", X, T))),
        # a cut after a disjunction removes its choice point; one inside the second branch too
        (_rf("o18", X), _rconj(_ror(n(X), m(X)), _rs("!"))),
        (_rf("o19", X), _ror(_rs("fail"), _rconj(_ror(n(X), m(X)), _rs("!")))),
        (_rf("o20", X, Y), _rconj(_rf("o2", X), _ror(eq(Y, X), eq(Y, _rs("other"))))),
        # `Y is X + 1` writes Y's slot directly (A_ADD_FC: no binding to undo), so after the first
        # branch failed the slot still holds the number: C_VAR / C_VAR_N must make it fresh
        (_rf("o21", X, Y),
            _rconj(
                _ror(
                    _rconj(_rf("is", A, _rf("+", X, _rg(1))),
                        _rf("is", B, _rf("+", X, _rg(2))),
                        _rs("fail")), _rs("true")),
                eq(Y, _rf("r", A, B)))),
        (_rf("o22", X, Y),
            _rconj(
                _ror(_rconj(_rf("is", A, _rf("+", X, _rg(1))), _rs("fail")), _rs("true")),
                eq(Y, _rf("r", A))))
    ]
    return cl
end

function _ror_goals()
    X, Y, A, B, C, D = (_rv(k) for k in 101:106)
    abc = _rlist(_rs("a"), _rs("b"), _rs("c"))
    return _R[
        _rf("o1", X), _rf("o1", _rs("a")), _rf("o1", _rs("b")), _rf("o1", _rs("c")),
        _rf("o2", X), _rf("o2", _rg(2)), _rf("o2", _rs("b")), _rf("o3", X, Y),
        _rf("o4", X), _rf("o5", X), _rf("o6", X, Y), _rf("o7", X), _rf("o8", X),
        _rf("o9", X), _rf("o10", X), _rf("o11", X), _rf("o12", X), _rf("o12", _rg(3)),
        _rs("o13"), _rf("o14", X, Y), _rf("o15", A, B, C, D), _rf("o16", X), _rf("o17", X),
        _rf("mem", X, abc), _rf("mem", _rs("b"), abc), _rf("mem", _rs("c"), abc),
        _rf("mem", _rs("d"), abc), _rf("o18", X), _rf("o19", X), _rf("o20", X, Y),
        _rf("o21", _rg(1), Y), _rf("o22", _rg(1), Y)
    ]
end

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

"Random predicates `rd<i>/k` of one or two clauses, each body a disjunction, and goals on them."
function _ror_random(rng, count::Int)
    clauses = Tuple{_R, Union{Nothing, _R}}[]
    goals = _R[]
    key = 10_000
    for i in 1:count
        k = rand(rng, 1:3)
        for _ in 1:rand(rng, 1:2)
            vars = _R[_rv(key + j) for j in 1:rand(rng, k:(k + 2))]
            key += 10
            body = _ror(_rorbody(rng, vars, 1), _rorbody(rng, vars, 1))
            rand(rng) < 0.4 && (body = _rf(",", body, _rorbody(rng, vars, 2)))
            push!(clauses, (mk_expr(_R, _R[_rs("rd$i"); vars[1:k]]), body))
        end
        fresh = _R[_rv(key + j) for j in 1:k]
        key += 10
        push!(goals, mk_expr(_R, _R[_rs("rd$i"); fresh]))
        bound = copy(fresh)
        bound[1] = rand(rng, (_rg(1), _rs("a"), _rg(3)))
        push!(goals, mk_expr(_R, _R[_rs("rd$i"); bound]))
    end
    return clauses, goals
end

@testset "disjunctions: every answer and its determinism are swipl's (V9d)" begin
    clauses = _ror_clauses()
    goals = _ror_goals()
    rc, rg = _ror_random(Xoshiro(20261012), 150)
    append!(clauses, rc)
    append!(goals, rg)
    db = _rdb(clauses)
    ops = Set{UInt64}()
    for (h, _) in clauses
        cref = _rproc(db, h).definition.impl_clauses.first_clause
        while cref !== nothing
            union!(ops, _rops(cref.clause))
            cref = cref.next
        end
    end
    @test all(in(ops), (LK.C_OR, LK.C_JMP, LK.C_VAR, LK.C_VAR_N, LK.I_CUT))
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    # pinned, so the jobs without swipl check them too
    ends = findall(==("end"), ours)
    answers(i) = ours[(i == 1 ? 1 : ends[i - 1] + 1):(ends[i] - 1)]        # of the i-th goal
    @test answers(1) == ["o1(a) nondet", "o1(b) det"]                       # o1(X)
    @test answers(11) == ["o6(1,_) nondet", "o6(_,2) det"]                  # o6(X, Y)
    @test answers(15) == ["o10(z) det"]                                     # o10(X)
    @test answers(10) == ["o5(1) det"]                                      # o5(X): the cut
    @test answers(31) == ["o21(1,r(_,_)) det"]              # C_VAR_N over slots written directly
    @test answers(32) == ["o22(1,r(_)) det"]                # C_VAR
    ndet = count(endswith(" nondet"), ours)
    @info "disjunction programs: $(length(goals)) queries, $(length(ours) - length(goals)) answers ($ndet non-deterministic)"
    @test ndet > 100 && count(endswith(" det"), ours) > 100
    @test _rpools_live(db.ld)
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    end
end

# ── V9d: the conditionals ───────────────────────────────────────────────────────────────────────
# `(A -> B ; C)` and `(A -> B)` through the VM (`C_IFTHENELSE`, `C_IFTHEN`, `C_CUT` and `c_cut`,
# `C_FASTCOND`/`C_FASTCUT`, `C_END`): every answer and its determinism are swipl's. A `!` inside a
# condition compiles (`C_LCUT`) but runs with the cut's own step, so no condition here has one.
_rite(a::_R, b::_R, c::_R) = _ror(_rf("->", a, b), c)
_rit(a::_R, b::_R) = _rf("->", a, b)

"The pinned conditional programs: facts `n/1`, `m/1` and one clause per case."
function _rite_clauses()
    X, Y, Z, A, B = (_rv(k) for k in 1:5)
    n(x) = _rf("n", x)
    m(x) = _rf("m", x)
    eq(a, b) = _rf("=", a, b)
    return Tuple{_R, Union{Nothing, _R}}[
        (n(_rg(1)), nothing), (n(_rg(2)), nothing), (n(_rg(3)), nothing),
        (m(_rs("a")), nothing), (m(_rs("b")), nothing),
        # the condition commits to its FIRST answer; the then branch may still leave choices
        (_rf("c1", X), _rite(n(X), _rs("true"), eq(X, _rs("none")))),
        (_rf("c2", X, Y), _rite(n(X), m(Y), eq(Y, _rs("none")))),
        (_rf("c3", X), _rite(_rf("nope", X), eq(X, _rs("then")), eq(X, _rs("else")))),
        (_rf("nope", _rs("never")), nothing),
        (_rf("c4", X), _rite(_rs("fail"), eq(X, _rs("then")), m(X))),
        # a fast condition: tests only — taken, not taken, and with a second test
        (_rf("c5", X, Y), _rite(_rf("integer", X), eq(Y, _rs("int")), eq(Y, _rs("other")))),
        (_rf("c6", X, Y),
            _rite(_rconj(_rf("atom", X), _rf("\\==", X, _rs("a"))), eq(Y, _rs("yes")),
                eq(Y, _rs("no")))),
        (_rf("c7", X, Y), _rite(_rf("var", X), eq(Y, _rs("unbound")), eq(Y, _rs("bound")))),
        (_rf("c8", X, Y), _rite(_rf("==", X, Y), _rs("true"), _rs("fail"))),
        # the condition's bindings stay in the then branch and are undone for the else branch
        (
            _rf("c9", X, Y),
            _rite(_rconj(eq(Z, _rg(1)), n(X)), eq(Y, _rf("t", Z, X)), eq(Y, Z))
        ),
        (
            _rf("c10", Y),
            _rite(_rconj(eq(Z, _rg(1)), _rs("fail")), eq(Y, _rg(0)), eq(Y, _rf("e", Z)))
        ),
        # nested, and a chain
        (_rf("c11", X, Y),
            _rite(_rf("integer", X),
                _rite(_rf(">", X, _rg(1)), eq(Y, _rs("big")), eq(Y, _rs("small"))),
                eq(Y, _rs("nan")))),
        (_rf("c12", X, Y),
            _rite(_rf("==", X, _rs("a")), eq(Y, _rg(1)),
                _rite(_rf("==", X, _rs("b")), eq(Y, _rg(2)), eq(Y, _rg(3))))),
        # a conditional whose condition is a disjunction or a conditional
        (_rf("c13", X), _rite(_ror(_rs("fail"), n(X)), _rs("true"), eq(X, _rg(0)))),
        (_rf("c14", X, Y),
            _rite(
                _rite(n(X), _rf(">", X, _rg(5)), _rs("true")),
                eq(Y, _rs("in")),
                eq(Y, _rs("out"))
            )),
        # if-then without else: fails when the condition does
        (_rf("c15", X), _rconj(_rit(n(X), _rs("true")), m(_rs("a")))),
        (_rf("c16", X), _rit(_rf("nope", X), _rs("true"))),
        (_rf("c16", _rs("second")), nothing),
        (_rf("c17", X, Y), _rconj(_rit(n(X), m(Y)), _rf("\\==", Y, _rs("a")))),
        # a disjunction of an if-then and a goal: the if-then failing lets the second branch run
        (_rf("c18", X), _ror(_rs("fail"), _rit(n(X), _rf(">", X, _rg(1))))),
        # choice points made INSIDE the condition by deeper frames are cut; older ones are kept
        (_rf("c19", X, Y), _rconj(m(X), _rite(n(Y), _rs("true"), _rs("fail")))),
        (_rf("deep", X), _rconj(n(X), n(_rv(9)))),
        (_rf("c20", X, Y), _rite(_rf("deep", X), eq(Y, _rs("got")), eq(Y, _rs("none")))),
        # a clause-level cut in the then and in the else branch
        (_rf("c21", X), _rconj(n(X), _rite(_rf(">", X, _rg(1)), _rs("!"), _rs("fail")))),
        (_rf("c22", X), _rconj(n(X), _rite(_rf(">", X, _rg(5)), _rs("true"), _rs("!")))),
        # a variable only one branch sets, then used
        (_rf("c23", X, Y), _rconj(_rite(n(X), eq(A, X), _rs("true")), eq(Y, _rf("r", A)))),
        (_rf("c24", X, Y),
            _rconj(
                _rite(_rf("nope", X), _rf("is", A, _rf("+", _rg(1), _rg(1))), _rs("true")),
                eq(Y, _rf("r", A)))),
        # recursion through a conditional (last call in the else branch)
        (_rf("len", _rnil(), _rg(0)), nothing),
        (_rf("count", X, Y, Z),
            _rite(
                _rf(">=", X, Y),
                eq(Z, X),
                _rconj(_rf("is", A, _rf("+", X, _rg(1))), _rf("count", A, Y, Z))
            ))
    ]
end

function _rite_goals()
    X, Y = _rv(101), _rv(102)
    return _R[
        _rf("c1", X), _rf("c1", _rg(2)), _rf("c1", _rg(9)), _rf("c2", X, Y), _rf("c3", X),
        _rf("c4", X), _rf("c5", _rg(1), Y), _rf("c5", _rs("a"), Y), _rf("c5", X, Y),
        _rf("c6", _rs("b"), Y), _rf("c6", _rs("a"), Y), _rf("c6", _rg(1), Y),
        _rf("c7", X, Y), _rf("c7", _rg(1), Y), _rf("c8", X, X), _rf("c8", X, Y),
        _rf("c9", X, Y), _rf("c10", Y), _rf("c11", _rg(3), Y), _rf("c11", _rg(1), Y),
        _rf("c11", _rs("a"), Y), _rf("c12", _rs("a"), Y), _rf("c12", _rs("b"), Y),
        _rf("c12", _rs("c"), Y), _rf("c13", X), _rf("c14", X, Y), _rf("c15", X),
        _rf("c16", X), _rf("c17", X, Y), _rf("c18", X), _rf("c19", X, Y), _rf("c20", X, Y),
        _rf("c21", X), _rf("c22", X), _rf("c23", X, Y), _rf("c24", X, Y),
        _rf("count", _rg(0), _rg(2000), Y)
    ]
end

"A random body of `,`, `;`, `->` (with and without else); `nocut`: inside a condition, no `!`."
function _ritebody(rng, vars::Vector{_R}, depth::Int, nocut::Bool)::_R
    r = rand(rng)
    v() = rand(rng, vars)
    tests() = _rconj(
        [
            if rand(rng, Bool)
                _rf(rand(rng, ("var", "nonvar")), v())
            else
                _rf(rand(rng, ("==", "\\==")), v(), rand(rng, Bool) ? v() : _rs("a"))
            end for
            _ in 1:rand(rng, 1:2)
        ]...
    )
    if depth < 4 && r < 0.2
        cond = rand(rng) < 0.4 ? tests() : _ritebody(rng, vars, depth + 1, true)
        return _rite(cond, _ritebody(rng, vars, depth + 1, nocut),
            _ritebody(rng, vars, depth + 1, nocut))
    elseif depth < 4 && r < 0.3
        cond = rand(rng) < 0.3 ? tests() : _ritebody(rng, vars, depth + 1, true)
        return _rit(cond, _ritebody(rng, vars, depth + 1, nocut))
    elseif depth < 4 && r < 0.42
        return _ror(
            _ritebody(rng, vars, depth + 1, nocut), _ritebody(rng, vars, depth + 1, nocut)
        )
    elseif depth < 4 && r < 0.6
        return _rf(",", _ritebody(rng, vars, depth + 1, nocut),
            _ritebody(rng, vars, depth + 1, nocut))
    end
    while true
        g = _rorbody(rng, vars, 4)                                  # a goal
        (nocut && kind(g) === SYM && lk_name(g) === Symbol("!")) || return g
    end
end

"Random predicates `rc<i>/k` of one or two clauses, each body a conditional, and goals on them."
function _rite_random(rng, count::Int)
    clauses = Tuple{_R, Union{Nothing, _R}}[]
    goals = _R[]
    key = 20_000
    for i in 1:count
        k = rand(rng, 1:3)
        for _ in 1:rand(rng, 1:2)
            vars = _R[_rv(key + j) for j in 1:rand(rng, k:(k + 2))]
            key += 10
            cond = _ritebody(rng, vars, 2, true)
            body = if rand(rng) < 0.75
                _rite(cond, _ritebody(rng, vars, 2, false), _ritebody(rng, vars, 2, false))
            else
                _rit(cond, _ritebody(rng, vars, 2, false))
            end
            rand(rng) < 0.4 && (body = _rf(",", body, _ritebody(rng, vars, 2, false)))
            push!(clauses, (mk_expr(_R, _R[_rs("rc$i"); vars[1:k]]), body))
        end
        fresh = _R[_rv(key + j) for j in 1:k]
        key += 10
        push!(goals, mk_expr(_R, _R[_rs("rc$i"); fresh]))
        bound = copy(fresh)
        bound[1] = rand(rng, (_rg(1), _rs("a"), _rg(3)))
        push!(goals, mk_expr(_R, _R[_rs("rc$i"); bound]))
    end
    return clauses, goals
end

@testset "conditionals: every answer and its determinism are swipl's (V9d)" begin
    clauses = _rite_clauses()
    goals = _rite_goals()
    rc, rg = _rite_random(Xoshiro(20261013), 200)
    append!(clauses, rc)
    append!(goals, rg)
    db = _rdb(clauses)
    ops = Set{UInt64}()
    for (h, _) in clauses
        cref = _rproc(db, h).definition.impl_clauses.first_clause
        while cref !== nothing
            union!(ops, _rops(cref.clause))
            cref = cref.next
        end
    end
    @test all(
        in(ops),
        (
            LK.C_IFTHENELSE,
            LK.C_IFTHEN,
            LK.C_CUT,
            LK.C_FASTCOND,
            LK.C_FASTCUT,
            LK.C_END,
            LK.C_OR
        )
    )
    @test !(LK.C_LCUT in ops) && !(LK.C_LCUTIFTHEN in ops)             # the cut's own step
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    ends = findall(==("end"), ours)
    answers(i) = ours[(i == 1 ? 1 : ends[i - 1] + 1):(ends[i] - 1)]        # of the i-th goal
    @test answers(1) == ["c1(1) det"]                       # the condition's first answer only
    @test isempty(answers(3))                               # c1(9): the else branch, 9 = none
    @test answers(4) == ["c2(1,a) nondet", "c2(1,b) det"]   # the then branch keeps its choices
    @test answers(7) == ["c5(1,int) det"] && answers(8) == ["c5(a,other) det"]
    @test answers(18) == ["c10(e(_)) det"]                  # the condition's binding is undone
    @test answers(28) == ["c16(never) nondet", "c16(second) det"]  # if-then, then clause 2
    # c3: the condition succeeds (X = never), the then branch fails, and the else is NOT tried
    @test isempty(answers(5)) && answers(6) == ["c4(a) nondet", "c4(b) det"]
    @test answers(37) == ["count(0,2000,2000) det"]
    @test db.ld.fast_condition == 0                         # no fast condition is left open
    ndet = count(endswith(" nondet"), ours)
    @info "conditional programs: $(length(goals)) queries, $(length(ours) - length(goals)) answers ($ndet non-deterministic)"
    @test ndet > 100 && count(endswith(" det"), ours) > 100
    @test _rpools_live(db.ld)
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    end
end

# ── V9d: negation ───────────────────────────────────────────────────────────────────────────────
# `\+ A` through the VM (`C_NOT`, `C_CUT`, `C_FAIL`): every answer and its determinism are swipl's.
# A `!` inside it compiles (`C_LCUT`) but runs with the cut's own step, so no `\+` here holds one.
_rnot(a::_R) = _rf("\\+", a)

# Left out of the random differentials; see register Q3. A random predicate is named by its
# stream's seed and its index in the stream.
const _R_Q3_SKIP = Set([(20261015, 77), (20261015, 213), (20261017, 101)])

"The stream of `seed` — its predicates named `prefix<index>` — without those `_R_Q3_SKIP` lists."
function _rq3_keep(seed::Int, prefix::String, clauses, goals)
    index(t::_R) = parse(Int, chopprefix(String(lk_name(_rfunctor(t)[1])), prefix))
    kept(t::_R) = !((seed, index(t)) in _R_Q3_SKIP)
    n = length(unique(index(g) for g in goals))
    out = count(((s, _),) -> s == seed, _R_Q3_SKIP)
    @info "random stream $seed: $out of $n predicates left out (see register Q3)"
    return [c for c in clauses if kept(c[1])], [g for g in goals if kept(g)]
end

"The pinned negation programs: facts `n/1`, `m/1` and one clause per case."
function _rnot_clauses()
    X, Y, Z, A = (_rv(k) for k in 1:4)
    n(x) = _rf("n", x)
    m(x) = _rf("m", x)
    eq(a, b) = _rf("=", a, b)
    return Tuple{_R, Union{Nothing, _R}}[
        (n(_rg(1)), nothing), (n(_rg(2)), nothing), (n(_rg(3)), nothing),
        (m(_rs("a")), nothing), (m(_rs("b")), nothing),
        (_rf("t1", X), _rnot(n(X))),
        (_rf("t2", X), _rconj(_rnot(n(X)), eq(X, _rs("free")))),
        # nothing A binds survives: X is unbound after \+ n(X) failed … and after it succeeded
        (_rf("t3", X, Y), _rconj(_rnot(_rconj(n(X), _rs("fail"))), eq(Y, _rf("r", X)))),
        (
            _rf("t4", Y),
            _rconj(_rnot(_rconj(eq(Z, _rg(1)), _rs("fail"))), eq(Y, _rf("r", Z)))
        ),
        # a slot A writes directly (A_ADD_FC) is fresh afterwards: the C_VAR behind the jump
        (_rf("t5", X, Y),
            _rconj(
                _rnot(_rconj(_rf("is", A, _rf("+", X, _rg(1))), _rs("fail"))),
                eq(Y, _rf("r", A))
            )),
        (_rf("t6", X), _rconj(m(X), _rnot(_rf("==", X, _rs("a"))))),
        (_rf("t7", X), _rconj(n(X), _rnot(_rf(">", X, _rg(1))))),
        (_rf("t8", X), _rnot(_rnot(n(X)))),                        # \+ \+: true, X unbound
        (_rf("t9", X), _rconj(n(X), _rnot(_rnot(_rf(">", X, _rg(2)))))),
        (_rf("t10", X), _rconj(m(X), _rnot(_ror(_rf("==", X, _rs("b")), _rs("fail"))))),
        (_rf("t11", X, Y), _rite(_rnot(n(X)), eq(Y, _rs("none")), eq(Y, _rs("some")))),
        (_rf("t12", X), _ror(_rnot(_rs("true")), n(X))),
        (_rf("t13", X), _rconj(n(X), _rnot(_rconj(n(Y), _rf(">", Y, X))))),       # the maximum
        (_rf("t14", X), _rconj(n(X), _rnot(_rf("nomatch", X)))),
        (_rf("nomatch", _rs("b")), nothing),
        (_rs("t15"), _rconj(_rnot(_rs("fail")), _rnot(_rs("fail")))),
        (_rs("t16"), _rnot(_rs("true")))
    ]
end

function _rnot_goals()
    X, Y = _rv(101), _rv(102)
    return _R[
        _rf("t1", X), _rf("t1", _rg(2)), _rf("t1", _rg(9)), _rf("t2", X),
        _rf("t2", _rs("free")),
        _rf("t3", X, Y), _rf("t4", Y), _rf("t5", _rg(1), Y), _rf("t6", X), _rf("t7", X),
        _rf("t8", X), _rf("t8", _rg(7)), _rf("t9", X), _rf("t10", X), _rf("t11", X, Y),
        _rf("t11", _rg(9), Y), _rf("t12", X), _rf("t13", X), _rf("t14", X), _rs("t15"),
        _rs("t16")
    ]
end

"A random body like `_ritebody`'s with `\\+`; inside a `\\+` or a condition there is no `!`."
function _rnotbody(rng, vars::Vector{_R}, depth::Int, nocut::Bool)::_R
    r = rand(rng)
    if depth < 4 && r < 0.25
        return _rnot(_rnotbody(rng, vars, depth + 1, true))
    elseif depth < 4 && r < 0.4
        return _rite(_rnotbody(rng, vars, depth + 1, true),
            _rnotbody(rng, vars, depth + 1, nocut),
            _rnotbody(rng, vars, depth + 1, nocut))
    elseif depth < 4 && r < 0.5
        return _ror(
            _rnotbody(rng, vars, depth + 1, nocut), _rnotbody(rng, vars, depth + 1, nocut)
        )
    elseif depth < 4 && r < 0.68
        return _rf(",", _rnotbody(rng, vars, depth + 1, nocut),
            _rnotbody(rng, vars, depth + 1, nocut))
    end
    while true
        g = _rorbody(rng, vars, 4)                                  # a goal
        (nocut && kind(g) === SYM && lk_name(g) === Symbol("!")) || return g
    end
end

"Random predicates `rn<i>/k` of one or two clauses, each with a `\\+`, and goals on them."
function _rnot_random(rng, count::Int)
    clauses = Tuple{_R, Union{Nothing, _R}}[]
    goals = _R[]
    key = 40_000
    for i in 1:count
        k = rand(rng, 1:3)
        for _ in 1:rand(rng, 1:2)
            vars = _R[_rv(key + j) for j in 1:rand(rng, k:(k + 2))]
            key += 10
            body = _rnot(_rnotbody(rng, vars, 2, true))
            r = rand(rng)
            if r < 0.45
                body = _rf(",", body, _rnotbody(rng, vars, 2, false))
            elseif r < 0.7
                body = _rf(",", _rnotbody(rng, vars, 2, false), body)
            end
            push!(clauses, (mk_expr(_R, _R[_rs("rn$i"); vars[1:k]]), body))
        end
        fresh = _R[_rv(key + j) for j in 1:k]
        key += 10
        push!(goals, mk_expr(_R, _R[_rs("rn$i"); fresh]))
        bound = copy(fresh)
        bound[1] = rand(rng, (_rg(1), _rs("a"), _rg(3)))
        push!(goals, mk_expr(_R, _R[_rs("rn$i"); bound]))
    end
    return clauses, goals
end

@testset "negation: every answer and its determinism are swipl's (V9d)" begin
    clauses = _rnot_clauses()
    goals = _rnot_goals()
    rc, rg = _rq3_keep(20261014, "rn", _rnot_random(Xoshiro(20261014), 200)...)
    append!(clauses, rc)
    append!(goals, rg)
    db = _rdb(clauses)
    ops = Set{UInt64}()
    for (h, _) in clauses
        cref = _rproc(db, h).definition.impl_clauses.first_clause
        while cref !== nothing
            union!(ops, _rops(cref.clause))
            cref = cref.next
        end
    end
    @test all(in(ops), (LK.C_NOT, LK.C_FAIL, LK.C_CUT, LK.C_VAR, LK.C_JMP))
    @test !(LK.C_LCUT in ops)                                          # the cut's own step
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    ends = findall(==("end"), ours)
    answers(i) = ours[(i == 1 ? 1 : ends[i - 1] + 1):(ends[i] - 1)]        # of the i-th goal
    @test isempty(answers(1)) && isempty(answers(2))        # \+ n(X), \+ n(2): n has answers
    @test answers(3) == ["t1(9) det"]
    @test isempty(answers(4)) && answers(5) == ["t2(free) det"]    # \+ n(X); \+ n(free)
    @test answers(6) == ["t3(A,r(A)) det"]                  # nothing A bound survives: X unbound
    @test answers(7) == ["t4(r(_)) det"]
    @test answers(8) == ["t5(1,r(_)) det"]                  # the slot A wrote directly is fresh
    @test answers(9) == ["t6(b) det"]
    @test answers(11) == ["t8(_) det"]                      # \+ \+ n(X): true, X unbound
    @test answers(18) == ["t13(3) det"]
    ndet = count(endswith(" nondet"), ours)
    @info "negation programs: $(length(goals)) queries, $(length(ours) - length(goals)) answers ($ndet non-deterministic)"
    @test ndet > 50 && count(endswith(" det"), ours) > 100
    @test _rpools_live(db.ld)
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    end
end

# ── V9d: the cut inside a condition and a negation ──────────────────────────────────────────────
# A `!` in the condition of `(A -> B ; C)` or in `\+ A` is `C_LCUT`: it cuts the choice points made
# since the construct started, but not the construct's own (`c_lcut_cont`, then `c_cut`); in the
# condition of `(A -> B)` it is `C_LCUTIFTHEN`, which cuts back to the mark. Every answer and its
# determinism are swipl's.
"The pinned programs: facts `n/1`, `m/1`, `deep/1` and one clause per case."
function _rlcut_clauses()
    X, Y, Z = (_rv(k) for k in 1:3)
    n(x) = _rf("n", x)
    m(x) = _rf("m", x)
    eq(a, b) = _rf("=", a, b)
    cut = _rs("!")
    return Tuple{_R, Union{Nothing, _R}}[
        (n(_rg(1)), nothing), (n(_rg(2)), nothing), (n(_rg(3)), nothing),
        (m(_rs("a")), nothing), (m(_rs("b")), nothing),
        (_rf("deep", X), _rconj(n(X), n(_rv(9)))),
        # upstream's own case (pl-vmi.c, above C_LSCUT): a :- \+ (b, !, fail) succeeds
        (_rs("u1"), _rnot(_rconj(m(_rv(8)), cut, _rs("fail")))),
        (_rf("u2", X), _rite(_rconj(n(X), cut), _rs("true"), eq(X, _rs("none")))),
        # the cut stops the condition retrying: 1 > 1 fails, so the else branch — without it, 2
        (
            _rf("u3", X),
            _rite(_rconj(n(X), cut, _rf(">", X, _rg(1))), _rs("true"), eq(X, _rs("else")))
        ),
        (
            _rf("u4", X),
            _rite(_rconj(n(X), _rf(">", X, _rg(1))), _rs("true"), eq(X, _rs("else")))
        ),
        (
            _rf("u5", X),
            _rite(_rconj(_ror(n(X), eq(X, _rs("z"))), cut), _rs("true"), _rs("fail"))
        ),
        # the local cut leaves the choice points made BEFORE the construct alone
        (_rf("u6", X, Y), _rconj(m(X), _rite(_rconj(n(Y), cut), _rs("true"), _rs("fail")))),
        (_rf("u7", X), _rconj(_rit(_rconj(n(X), cut), _rs("true")), m(_rv(8)))),      # C_LCUTIFTHEN
        (_rf("u8", X), _rconj(n(X), _rnot(_rconj(n(Y), cut, _rf("<", Y, X))))),
        (_rf("u9", X), _rconj(m(X), _rnot(_rconj(m(Y), cut, _rf("==", Y, X))))),
        (
            _rf("u10", X),
            _rite(_rconj(_rf("deep", X), cut), _rs("true"), eq(X, _rs("none")))
        ),
        (_rf("u11", X, Y), _rite(_rconj(n(X), cut, m(Y)), _rs("true"), _rs("fail"))),
        (_rf("u12", X),
            _rite(
                _rite(_rconj(n(X), cut), _rs("true"), _rs("fail")),
                _rs("true"),
                eq(X, _rs("none"))
            )),
        (_rf("u13", X), _rite(_rconj(_rs("fail"), cut), eq(X, _rs("a")), eq(X, _rs("b")))),
        (_rf("u14", X), _rite(_rconj(_rs("true"), cut), eq(X, _rs("a")), eq(X, _rs("b")))),
        (_rf("u15", X), _rite(_rconj(cut, n(X)), _rs("true"), eq(X, _rs("none")))),
        (_rf("u16", X), _rconj(_rit(_rconj(cut, n(X)), _rs("true")), _rf(">", X, _rg(1)))),
        # a cut in a condition inside a disjunction's branch: the other branch still runs
        (
            _rf("u17", X),
            _ror(
                _rite(_rconj(n(X), cut), _rf(">", X, _rg(5)), _rs("fail")),
                eq(X, _rs("other"))
            )
        ),
        (
            _rf("u18", X, Y),
            _rconj(n(X), _rit(_rconj(m(Y), cut), _rs("true")), _rf("<", X, _rg(3)))
        )
    ]
end

function _rlcut_goals()
    X, Y = _rv(101), _rv(102)
    return _R[
        _rs("u1"), _rf("u2", X), _rf("u3", X), _rf("u4", X), _rf("u5", X), _rf("u6", X, Y),
        _rf("u7", X), _rf("u8", X), _rf("u9", X), _rf("u10", X), _rf("u11", X, Y),
        _rf("u12", X), _rf("u13", X), _rf("u14", X), _rf("u15", X), _rf("u16", X),
        _rf("u17", X), _rf("u18", X, Y)
    ]
end

"A random body of `,`, `;`, `->` and `\\+` with `!` anywhere, conditions and negations included."
function _rlcutbody(rng, vars::Vector{_R}, depth::Int)::_R
    r = rand(rng)
    if depth < 4 && r < 0.2
        return _rnot(_rlcutbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.35
        return _rite(_rlcutbody(rng, vars, depth + 1), _rlcutbody(rng, vars, depth + 1),
            _rlcutbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.42
        return _rit(_rlcutbody(rng, vars, depth + 1), _rlcutbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.5
        return _ror(_rlcutbody(rng, vars, depth + 1), _rlcutbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.72
        return _rf(",", _rlcutbody(rng, vars, depth + 1), _rlcutbody(rng, vars, depth + 1))
    end
    rand(rng) < 0.25 && return _rs("!")
    return _rorbody(rng, vars, 4)                                   # a goal
end

"Random predicates `ru<i>/k` of one or two clauses, a condition or a negation at the top, and goals."
function _rlcut_random(rng, count::Int)
    clauses = Tuple{_R, Union{Nothing, _R}}[]
    goals = _R[]
    key = 60_000
    for i in 1:count
        k = rand(rng, 1:3)
        for _ in 1:rand(rng, 1:2)
            vars = _R[_rv(key + j) for j in 1:rand(rng, k:(k + 2))]
            key += 10
            cond = _rf(",", _rlcutbody(rng, vars, 2), _rlcutbody(rng, vars, 2))
            r = rand(rng)
            body = if r < 0.4
                _rite(cond, _rlcutbody(rng, vars, 2), _rlcutbody(rng, vars, 2))
            elseif r < 0.6
                _rit(cond, _rlcutbody(rng, vars, 2))
            else
                _rnot(cond)
            end
            r = rand(rng)
            if r < 0.3
                body = _rf(",", body, _rlcutbody(rng, vars, 2))
            elseif r < 0.6
                body = _rf(",", _rf("n", vars[1]), body)        # a choice point made BEFORE
            end
            push!(clauses, (mk_expr(_R, _R[_rs("ru$i"); vars[1:k]]), body))
        end
        fresh = _R[_rv(key + j) for j in 1:k]
        key += 10
        push!(goals, mk_expr(_R, _R[_rs("ru$i"); fresh]))
        bound = copy(fresh)
        bound[1] = rand(rng, (_rg(1), _rs("a"), _rg(3)))
        push!(goals, mk_expr(_R, _R[_rs("ru$i"); bound]))
    end
    return clauses, goals
end

@testset "a cut in a condition or a negation: every answer and its determinism are swipl's (V9d)" begin
    clauses = _rlcut_clauses()
    goals = _rlcut_goals()
    rc, rg = _rq3_keep(20261015, "ru", _rlcut_random(Xoshiro(20261015), 250)...)
    append!(clauses, rc)
    append!(goals, rg)
    db = _rdb(clauses)
    ops = Set{UInt64}()
    for (h, _) in clauses
        cref = _rproc(db, h).definition.impl_clauses.first_clause
        while cref !== nothing
            union!(ops, _rops(cref.clause))
            cref = cref.next
        end
    end
    @test all(in(ops), (LK.C_LCUT, LK.C_LCUTIFTHEN, LK.C_NOT, LK.C_IFTHENELSE, LK.C_IFTHEN))
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    ends = findall(==("end"), ours)
    answers(i) = ours[(i == 1 ? 1 : ends[i - 1] + 1):(ends[i] - 1)]        # of the i-th goal
    @test answers(1) == ["u1 det"]                          # upstream's case: \+ (b, !, fail)
    @test answers(2) == ["u2(1) det"]
    @test answers(3) == ["u3(else) det"] && answers(4) == ["u4(2) det"]    # with and without
    @test answers(6) == ["u6(a,1) nondet", "u6(b,1) det"]   # the choice points before it stay
    @test answers(7) == ["u7(1) nondet", "u7(1) det"]       # C_LCUTIFTHEN
    @test answers(8) == ["u8(1) nondet"] || answers(8) == ["u8(1) det"]
    @test answers(9) == ["u9(b) det"]
    @test answers(11) == ["u11(1,a) det"]
    ndet = count(endswith(" nondet"), ours)
    @info "local-cut programs: $(length(goals)) queries, $(length(ours) - length(goals)) answers ($ndet non-deterministic)"
    @test ndet > 50 && count(endswith(" det"), ours) > 100
    @test _rpools_live(db.ld)
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    end
end

# Where a frame lands after a local cut, read with the real `prolog_current_frame/1` on both sides
# (as MQ6): `qn/1` is called INSIDE the condition, after `nd2` left a choice point — with the cut
# that choice point is gone and the frame lands right above the construct's own; without it, above
# `nd2`'s as well.
function _rlcut_pos_clauses()
    F0, F1 = _rv(1), _rv(2)
    pcf(v) = _rf("prolog_current_frame", v)
    cut = _rs("!")
    return [
        (_rs("z"), nothing), (_rs("nd2"), nothing), (_rs("nd2"), nothing),
        (_rf("qn", F1), _rconj(pcf(F1), _rs("z"))), (_rf("qn", _rv(20)), nothing),
        (_rf("lcut", F0, F1),
            _rconj(
                pcf(F0),
                _rite(_rconj(_rs("nd2"), cut, _rf("qn", F1)), _rs("z"), _rs("z")),
                _rs("z")
            )),
        (_rf("lnocut", F0, F1),
            _rconj(
                pcf(F0),
                _rite(_rconj(_rs("nd2"), _rf("qn", F1)), _rs("z"), _rs("z")),
                _rs("z")
            )),
        (_rf("lcutit", F0, F1),
            _rconj(
                pcf(F0), _rit(_rconj(_rs("nd2"), cut, _rf("qn", F1)), _rs("z")), _rs("z")
            )),
        (_rf("lnocutit", F0, F1),
            _rconj(pcf(F0), _rit(_rconj(_rs("nd2"), _rf("qn", F1)), _rs("z")), _rs("z")))
    ]
end
# swipl's distances (10.1.17, live below): 11 is the clause's frame (header 8, two variables, the
# condition's slot). `lcut` 20 = that + the construct's own choice point (9), which `C_LCUT` keeps;
# `lnocut` 37 = + `nd2`'s frame (8) and choice point (9); `lcutit` 11: an if-then has no choice
# point of its own and `C_LCUTIFTHEN` cuts back to the mark; `lnocutit` 28 = 11 + 8 + 9.
const _R_LCUTPOS = [(:lcut, 20), (:lnocut, 37), (:lcutit, 11), (:lnocutit, 28)]

@testset "after a local cut the next frame lands where swipl's does (C_LCUT, C_LCUTIFTHEN)" begin
    clauses = _rlcut_pos_clauses()
    db = _rdb(clauses)
    ours = Int[]
    for (n, _) in _R_LCUTPOS
        ans = _rcall(db, _rf(n, _rv(90), _rv(91)))
        m = match(r"^\w+\((-?\d+),(-?\d+)\)$", ans[1][1])     # the first answer: n(A,B)
        push!(ours, parse(Int, m[2]) - parse(Int, m[1]))
    end
    ours == last.(_R_LCUTPOS) || println(stderr, "  local-cut positions, kernel: ", ours)
    @test ours == last.(_R_LCUTPOS)
    @test _rpools_live(db.ld)
    if _R_SWIPL
        main =
            "main :- " *
            join(
                ("$n(A$n, B$n), D$n is B$n - A$n, writeln(D$n)" for (n, _) in _R_LCUTPOS),
                ", "
            ) * "."
        theirs = parse.(Int, _rswipl(clauses, (); main_text=main))
        theirs == last.(_R_LCUTPOS) ||
            println(stderr, "  local-cut positions, swipl: ", theirs)
        @test theirs == last.(_R_LCUTPOS)
    end
end

# ── V9d: the soft-cut ───────────────────────────────────────────────────────────────────────────
# `(A *-> B ; C)`: every answer of A, then B for each; C only when A has none. `C_SOFTCUT` takes
# the condition's own choice point out of the chain, once, and leaves A's choice points alone; its
# record stays in the pool until its stack region is popped — `_rpools_live` is asked AT EVERY
# ANSWER here, and that is the check of the restated invariant.
_rsite(a::_R, b::_R, c::_R) = _ror(_rf("*->", a, b), c)
_rsit(a::_R, b::_R) = _rf("*->", a, b)

"The pinned soft-cut programs: facts `n/1`, `m/1` and one clause per case."
function _rsoft_clauses()
    X, Y, Z, A = (_rv(k) for k in 1:4)
    n(x) = _rf("n", x)
    m(x) = _rf("m", x)
    eq(a, b) = _rf("=", a, b)
    cut = _rs("!")
    return Tuple{_R, Union{Nothing, _R}}[
        (n(_rg(1)), nothing), (n(_rg(2)), nothing), (n(_rg(3)), nothing),
        (m(_rs("a")), nothing), (m(_rs("b")), nothing),
        (_rf("nomatch", _rs("b")), nothing),
        (_rf("deep", X), _rconj(n(X), n(_rv(9)))),
        (_rf("s1", X), _rsite(n(X), _rs("true"), eq(X, _rs("none")))),           # every answer of A
        (_rf("s2", X, Y), _rsite(n(X), m(Y), eq(Y, _rs("none")))),
        (_rf("s3", X), _rsite(_rf("nomatch", X), eq(X, _rs("then")), eq(X, _rs("else")))),
        (_rf("s4", X), _rsite(_rs("fail"), eq(X, _rs("then")), m(X))),            # the else branch
        (
            _rf("s5", X, Y),
            _rsite(_rconj(n(X), _rf(">", X, _rg(1))), eq(Y, X), eq(Y, _rs("no")))
        ),
        (_rf("s6", X), _rsite(_rs("true"), n(X), _rs("fail"))),                   # A leaves no choice
        (_rf("s7", X, Y), _rconj(m(X), _rsite(n(Y), _rs("true"), _rs("fail")))),
        (_rf("s8", X), _rconj(_rsit(n(X), _rs("true")), _rf(">", X, _rg(1)))),    # *-> without else
        (_rf("s9", X), _rsit(_rf("nomatch", X), _rs("true"))),
        (_rf("s9", _rs("second")), nothing),
        (_rf("s10", X, Y), _rsite(_rf("deep", X), eq(Y, _rs("got")), eq(Y, _rs("none")))),
        (
            _rf("s11", X, Y),
            _rsite(
                _rsite(n(X), _rf(">", X, _rg(1)), _rs("fail")),
                eq(Y, _rs("in")),
                eq(Y, _rs("out"))
            )
        ),
        (_rf("s12", X), _rsite(_rconj(n(X), cut), _rs("true"), eq(X, _rs("none")))),      # C_LSCUT
        (
            _rf("s13", X),
            _rsite(_rconj(n(X), cut, _rf(">", X, _rg(1))), _rs("true"), eq(X, _rs("else")))
        ),
        (
            _rf("s14", X, Y),
            _rconj(m(X), _rsite(_rconj(n(Y), cut), _rs("true"), _rs("fail")))
        ),
        (_rf("s15", X), _rconj(_rsit(_rconj(n(X), cut), _rs("true")), m(_rv(8)))),        # C_LCUTIFTHEN
        (_rf("s16", X, Y), _rconj(_rsite(n(X), eq(A, X), _rs("true")), eq(Y, _rf("r", A)))),
        (
            _rf("s17", X, Y),
            _rconj(
                _rsite(_rf("nomatch", X), eq(A, _rg(1)), _rs("true")), eq(Y, _rf("r", A))
            )
        ),
        (_rf("s18", X), _rconj(_rsite(n(X), _rs("true"), _rs("fail")), cut)),             # a cut after it
        (_rf("s19", X), _rnot(_rsite(n(X), _rf(">", X, _rg(5)), _rs("fail")))),
        (
            _rf("s20", X, Y),
            _rsite(n(X), _rsite(m(Y), _rs("true"), _rs("fail")), _rs("fail"))
        ),
        # a last call after a soft-cut that left its record behind: the frame is reused 2,000 times
        (_rf("sloop", X, Y),
            _rsite(_rf(">", X, _rg(0)),
                _rconj(_rf("is", A, _rf("+", X, _rg(-1))), _rf("sloop", A, Y)),
                eq(Y, _rs("done")))),
        # … and a clause choice point resumed in place after one
        (_rf("s21", X), _rconj(_rsite(_rs("true"), _rs("true"), _rs("fail")), _rs("fail"))),
        (_rf("s21", _rs("second")), nothing)
    ]
end

function _rsoft_goals()
    X, Y = _rv(101), _rv(102)
    return _R[
        _rf("s1", X), _rf("s1", _rg(2)), _rf("s1", _rg(9)), _rf("s2", X, Y), _rf("s3", X),
        _rf("s4", X), _rf("s5", X, Y), _rf("s6", X), _rf("s7", X, Y), _rf("s8", X),
        _rf("s9", X),
        _rf("s10", X, Y), _rf("s11", X, Y), _rf("s12", X), _rf("s13", X), _rf("s14", X, Y),
        _rf("s15", X), _rf("s16", X, Y), _rf("s17", X, Y), _rf("s18", X), _rf("s19", X),
        _rf("s20", X, Y), _rf("sloop", _rg(2000), Y), _rf("s21", X)
    ]
end

"A random body of `,`, `;`, `->`, `*->` and `\\+` with `!` anywhere."
function _rsoftbody(rng, vars::Vector{_R}, depth::Int)::_R
    r = rand(rng)
    if depth < 4 && r < 0.22
        return _rsite(_rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1),
            _rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.3
        return _rsit(_rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.38
        return _rite(_rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1),
            _rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.45
        return _rnot(_rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.53
        return _ror(_rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.75
        return _rf(",", _rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1))
    end
    rand(rng) < 0.15 && return _rs("!")
    return _rorbody(rng, vars, 4)                                   # a goal
end

"Random predicates `rs<i>/k` of one or two clauses, a soft-cut at the top, and goals on them."
function _rsoft_random(rng, count::Int)
    clauses = Tuple{_R, Union{Nothing, _R}}[]
    goals = _R[]
    key = 80_000
    for i in 1:count
        k = rand(rng, 1:3)
        for _ in 1:rand(rng, 1:2)
            vars = _R[_rv(key + j) for j in 1:rand(rng, k:(k + 2))]
            key += 10
            cond = _rf(
                ",", _rf(rand(rng, ("n", "m")), rand(rng, vars)),
                _rsoftbody(rng, vars, 2)
            )
            body = if rand(rng) < 0.7
                _rsite(cond, _rsoftbody(rng, vars, 2), _rsoftbody(rng, vars, 2))
            else
                _rsit(cond, _rsoftbody(rng, vars, 2))
            end
            r = rand(rng)
            if r < 0.3
                body = _rf(",", body, _rsoftbody(rng, vars, 2))
            elseif r < 0.6
                body = _rf(",", _rf("n", vars[1]), body)        # a choice point made BEFORE
            end
            push!(clauses, (mk_expr(_R, _R[_rs("rs$i"); vars[1:k]]), body))
        end
        fresh = _R[_rv(key + j) for j in 1:k]
        key += 10
        push!(goals, mk_expr(_R, _R[_rs("rs$i"); fresh]))
        bound = copy(fresh)
        bound[1] = rand(rng, (_rg(1), _rs("a"), _rg(3)))
        push!(goals, mk_expr(_R, _R[_rs("rs$i"); bound]))
    end
    return clauses, goals
end

# The pinned programs' answers, from the run in which the whole list was identical to swipl's.
const _R_SOFT_PINNED = Dict{Int, Vector{String}}(
    1 => ["s1(1) nondet", "s1(2) nondet", "s1(3) det"],
    2 => ["s1(2) det"],
    3 => String[],
    4 => [
        "s2(1,a) nondet",
        "s2(1,b) nondet",
        "s2(2,a) nondet",
        "s2(2,b) nondet",
        "s2(3,a) nondet",
        "s2(3,b) det"
    ],
    5 => String[],
    6 => ["s4(a) nondet", "s4(b) det"],
    7 => ["s5(2,2) nondet", "s5(3,3) det"],
    8 => ["s6(1) nondet", "s6(2) nondet", "s6(3) det"],
    9 => [
        "s7(a,1) nondet",
        "s7(a,2) nondet",
        "s7(a,3) nondet",
        "s7(b,1) nondet",
        "s7(b,2) nondet",
        "s7(b,3) det"
    ],
    10 => ["s8(2) nondet", "s8(3) det"],
    11 => ["s9(b) nondet", "s9(second) det"],
    12 => [
        "s10(1,got) nondet",
        "s10(1,got) nondet",
        "s10(1,got) nondet",
        "s10(2,got) nondet",
        "s10(2,got) nondet",
        "s10(2,got) nondet",
        "s10(3,got) nondet",
        "s10(3,got) nondet",
        "s10(3,got) det"
    ],
    13 => ["s11(2,in) nondet", "s11(3,in) det"],
    14 => ["s12(1) det"],
    15 => ["s13(else) det"],
    16 => ["s14(a,1) nondet", "s14(b,1) det"],
    17 => ["s15(1) nondet", "s15(1) det"],
    18 => ["s16(1,r(1)) nondet", "s16(2,r(2)) nondet", "s16(3,r(3)) det"],
    19 => ["s17(b,r(1)) det"],
    20 => ["s18(1) det"],
    21 => ["s19(_) det"],
    22 => [
        "s20(1,a) nondet",
        "s20(1,b) nondet",
        "s20(2,a) nondet",
        "s20(2,b) nondet",
        "s20(3,a) nondet",
        "s20(3,b) det"
    ],
    23 => ["sloop(2000,done) det"],
    24 => ["s21(second) det"]
)

@testset "the soft-cut: every answer and its determinism are swipl's (V9d)" begin
    clauses = _rsoft_clauses()
    goals = _rsoft_goals()
    npinned = length(goals)
    rc, rg = _rq3_keep(20261017, "rs", _rsoft_random(Xoshiro(20261017), 250)...)
    append!(clauses, rc)
    append!(goals, rg)
    db = _rdb(clauses)
    ops = Set{UInt64}()
    for (h, _) in clauses
        cref = _rproc(db, h).definition.impl_clauses.first_clause
        while cref !== nothing
            union!(ops, _rops(cref.clause))
            cref = cref.next
        end
    end
    @test all(in(ops), (LK.C_SOFTIF, LK.C_SOFTCUT, LK.C_SOFTIFTHEN, LK.C_SCUT, LK.C_LSCUT))
    # the kernel's lines, with the pools checked AT EVERY ANSWER (the restated invariant), and how
    # many answers were given while a record C_SOFTCUT unlinked was still in the pool
    ours = String[]
    live = Bool[]
    held = 0
    for g in goals
        for (a, det) in _rcall(
            db, g;
            at=(qid, k) -> begin
                push!(live, _rpools_live(db.ld))
                held += any(i -> db.ld.choices[i].unlinked, 1:(db.ld.nchoices))
            end
        )
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
    end
    @test !isempty(live) && all(live)
    @test held > 50                                     # the check met such records, often
    @test db.ld.nchoices == 0 && db.ld.nframes == 0     # and every one was reclaimed in the end
    ends = findall(==("end"), ours)
    answers(i) = ours[(i == 1 ? 1 : ends[i - 1] + 1):(ends[i] - 1)]        # of the i-th goal
    # pinned from the run in which the whole list was identical to swipl's
    for i in 1:npinned
        want = get(_R_SOFT_PINNED, i, ["?"])
        answers(i) == want || println(stderr, "  PIN ", i, " => ", repr(answers(i)), ",")
        @test answers(i) == want
    end
    ndet = count(endswith(" nondet"), ours)
    @info "soft-cut programs: $(length(goals)) queries, $(length(ours) - length(goals)) answers ($ndet non-deterministic); $held answers with an unlinked record in the pool"
    @test ndet > 100 && count(endswith(" det"), ours) > 100
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    end
end

# Where a frame lands around a soft-cut, read with the real `prolog_current_frame/1` on both
# sides: `C_SOFTCUT` does not lower `lTop`, so after it the next frame lands ABOVE the condition's
# choice point, dead or not — the hard `->` beside each case lands below.
function _rsoft_pos_clauses()
    F0, F1 = _rv(1), _rv(2)
    pcf(v) = _rf("prolog_current_frame", v)
    return [
        (_rs("z"), nothing), (_rs("nd2"), nothing), (_rs("nd2"), nothing),
        (_rf("nomatch", _rs("b")), nothing),
        (_rf("qn", F1), _rconj(pcf(F1), _rs("z"))), (_rf("qn", _rv(20)), nothing),
        (
            _rf("sthen0", F0, F1),
            _rconj(pcf(F0), _rsite(_rs("z"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (
            _rf("hthen0", F0, F1),
            _rconj(pcf(F0), _rite(_rs("z"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (
            _rf("sthen", F0, F1),
            _rconj(pcf(F0), _rsite(_rs("nd2"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (
            _rf("hthen", F0, F1),
            _rconj(pcf(F0), _rite(_rs("nd2"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (_rf("selse", F0, F1),
            _rconj(
                pcf(F0), _rsite(_rf("nomatch", _rs("a")), _rs("z"), _rf("qn", F1)), _rs("z")
            )),
        (_rf("safter", F0, F1),
            _rconj(pcf(F0), _rsite(_rs("z"), _rs("z"), _rs("z")), _rf("qn", F1), _rs("z"))),
        (_rf("sit", F0, F1), _rconj(pcf(F0), _rsit(_rs("nd2"), _rf("qn", F1)), _rs("z")))
    ]
end
const _R_SOFTPOS = [
    (:sthen0, 20), (:hthen0, 11), (:sthen, 37), (:hthen, 11), (:selse, 11), (:safter, 20),
    (:sit, 28)
]

@testset "around a soft-cut the next frame lands where swipl's does (C_SOFTIF, C_SOFTCUT)" begin
    clauses = _rsoft_pos_clauses()
    db = _rdb(clauses)
    ours = Int[]
    for (n, _) in _R_SOFTPOS
        ans = _rcall(db, _rf(n, _rv(90), _rv(91)))
        m = match(r"^\w+\((-?\d+),(-?\d+)\)$", ans[1][1])     # the first answer: n(A,B)
        push!(ours, parse(Int, m[2]) - parse(Int, m[1]))
    end
    ours == last.(_R_SOFTPOS) || println(stderr, "  soft-cut positions, kernel: ", ours)
    @test ours == last.(_R_SOFTPOS)
    if _R_SWIPL
        main =
            "main :- " *
            join(
                ("$n(A$n, B$n), D$n is B$n - A$n, writeln(D$n)" for (n, _) in _R_SOFTPOS),
                ", "
            ) * "."
        theirs = parse.(Int, _rswipl(clauses, (); main_text=main))
        theirs == last.(_R_SOFTPOS) ||
            println(stderr, "  soft-cut positions, swipl: ", theirs)
        @test theirs == last.(_R_SOFTPOS)
    end
end

# ── soft-cut mutation regression: a cut inside a `*->` condition, AFTER the soft-cut (SC4) ───────
# The slot `C_SOFTCUT` negates (to −ref(P), P = the else-choice's parent) is read by `C_LSCUT` to
# know how far a `!` in the condition cuts: baseline cuts to P's parent, removing the condition's
# first choice; without the negation (SC4) the cut reaches the wrong record and the condition's
# first choice survives, so backtracking yields extra solutions. The shape: a condition that
# succeeds more than once with a cut that runs on a later success, binding the head var to the
# condition var so an extra solution shows by value (mutation 2026-10-12, V9d_softcut_mutation).
# (`sc9`'s tail call after the soft-cut compiles to I_DEPART — the LCO path whose reclaim SC9
# removes — checked structurally here; the growth itself is the "soft-cut loop … stays flat" test.)
function _rscreg_clauses()
    X, R, Y = _rv(1), _rv(3), _rv(2)
    n(x) = _rf("n", x)
    eq(a, b) = _rf("=", a, b)
    return Tuple{_R, Union{Nothing, _R}}[
        (n(_rg(1)), nothing), (n(_rg(2)), nothing), (n(_rg(3)), nothing),
        (_rf("deep2", X), n(X)),
        # sc4: ( ( n(X), ( X > 1, ! ; true ) ) *-> R = X ; R = no ) — swipl: R in {1, 2}
        (
            _rf("sc4", R),
            _rsite(
                _rconj(n(X), _ror(_rconj(_rf(">", X, _rg(1)), _rs("!")), _rs("true"))),
                eq(R, X), eq(R, _rs("no"))
            )
        ),
        (_rf("sc9", X, R),
            _rconj(_rsite(_rs("true"), eq(R, _rs("a")), eq(R, _rs("b"))), _rf("deep2", X)))
    ]
end

@testset "soft-cut regression: a cut in a *-> condition after the soft-cut (SC4)" begin
    db = _rdb(_rscreg_clauses())
    sc9ops = Set{UInt64}()
    cref = _rproc(db, _rf("sc9", _rv(80), _rv(81))).definition.impl_clauses.first_clause
    while cref !== nothing
        union!(sc9ops, _rops(cref.clause))
        cref = cref.next
    end
    @test LK.I_DEPART in sc9ops && LK.C_SOFTCUT in sc9ops
    # SC4: the cut keeps the condition's first choice, so an extra R appears (or C_LSCUT throws)
    sc4 = [a for (a, _) in _rcall(db, _rf("sc4", _rv(90)))]
    @test sc4 == ["sc4(1)", "sc4(2)"]              # not sc4(3): the ! removed X=3
    if _R_SWIPL
        ours4 = [a * (d ? " det" : " nondet") for (a, d) in _rcall(db, _rf("sc4", _rv(90)))]
        push!(ours4, "end")
        @test ours4 == _rswipl(_rscreg_clauses(), [_rf("sc4", _rv(90))])
    end
    # sc9 answers + pools (the flatness test is the growth kill; this pins the answers)
    live = Bool[]
    sc9 = String[]
    for (a, det) in _rcall(
        db, _rf("sc9", _rv(90), _rv(91)); at=(qid, k) -> push!(live, _rpools_live(db.ld))
    )
        push!(sc9, a * (det ? " det" : " nondet"))
    end
    @test all(live) && sc9 == ["sc9(1,a) nondet", "sc9(2,a) nondet", "sc9(3,a) det"]
end

# SC11': dropUnlinkedChoices! asserts no LIVE record above p. Build a choice record above p that is
# NOT unlinked and require the AssertionError — the guard-turned-assert that obsoletes mutant SC11
# (a future call site that broke "no live record above p" would be caught here, not silent).
@testset "dropUnlinkedChoices! asserts no live record above p (SC11')" begin
    ld = _RDB().ld
    ch = LK.newChoice(ld, LK.CHP_JUMP, 0)              # a fresh choice record on the pool
    ld.choices[ch].base = ld.lTop + 100               # above any p we pass
    ld.choices[ch].unlinked = false                   # LIVE — must not be reclaimed
    @test_throws AssertionError LK.dropUnlinkedChoices!(ld, ld.lTop)
    ld.choices[ch].unlinked = true                    # unlinked: now it reclaims, no throw
    LK.dropUnlinkedChoices!(ld, ld.lTop)
    @test ld.nchoices == ch - 1
end

# ── where the next frame lands around a disjunction (V9d) ───────────────────────────────────────
# Backtracking into a `CHP_JUMP` choice point lowers `lTop` to it (vmi: `lTop = (LocalFrame)ch`), so
# the next frame lands where the choice point was — from the clause itself (`oshallow`; `odeep`
# after a callee's own choice point is used up) and from a callee's frame that fails (`ofail`:
# `deep_backtrack`); a frame pushed while the choice point is alive lands above it, inside
# the first branch (`oleft`) and after the disjunction (`oafter`). Read as the cut's positions are
# (below): `qn/1` keeps its frame, and the distance is its frame from the clause's.
function _ror_pos_clauses()
    F0, F1 = _rv(1), _rv(2)
    pcf(v) = _rf("prolog_current_frame", v)
    return [
        (_rs("z"), nothing), (_rs("nd2"), nothing), (_rs("nd2"), nothing),
        (_rf("qn", F1), _rconj(pcf(F1), _rs("z"))), (_rf("qn", _rv(20)), nothing),
        (
            _rf("oshallow", F0, F1),
            _rconj(pcf(F0), _ror(_rs("fail"), _rf("qn", F1)), _rs("z"))
        ),
        (
            _rf("odeep", F0, F1),
            _rconj(pcf(F0), _ror(_rconj(_rs("nd2"), _rs("fail")), _rf("qn", F1)), _rs("z"))
        ),
        (_rf("nomatch", _rs("b")), nothing),
        (
            _rf("ofail", F0, F1),                   # the callee has no matching clause: FRAME_FAILED
            _rconj(pcf(F0), _ror(_rf("nomatch", _rs("a")), _rf("qn", F1)), _rs("z"))
        ),
        (_rf("oleft", F0, F1), _rconj(pcf(F0), _ror(_rf("qn", F1), _rs("z")), _rs("z"))),
        (
            _rf("oafter", F0, F1),
            _rconj(pcf(F0), _ror(_rs("z"), _rs("z")), _rf("qn", F1), _rs("z"))
        ),
        (
            _rf("pthen", F0, F1),
            _rconj(pcf(F0), _rite(_rs("nd2"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (
            _rf("pthen0", F0, F1),
            _rconj(pcf(F0), _rite(_rs("z"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (
            _rf("pfast", F0, F1),
            _rconj(pcf(F0), _rite(_rf("var", F1), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (
            _rf("pelse", F0, F1),
            _rconj(
                pcf(F0), _rite(_rf("nomatch", _rs("a")), _rs("z"), _rf("qn", F1)), _rs("z")
            )
        ),
        (
            _rf("pelsef", F0, F1),
            _rconj(pcf(F0), _rite(_rf("nonvar", F1), _rs("z"), _rf("qn", F1)), _rs("z"))
        ),
        (_rf("pit", F0, F1), _rconj(pcf(F0), _rit(_rs("nd2"), _rf("qn", F1)), _rs("z"))),
        (
            _rf("pnot", F0, F1),
            _rconj(pcf(F0), _rnot(_rf("nomatch", _rs("a"))), _rf("qn", F1), _rs("z"))
        ),
        (
            _rf("pnotd", F0, F1),
            _rconj(
                pcf(F0), _rnot(_rconj(_rs("nd2"), _rs("fail"))), _rf("qn", F1), _rs("z")
            )
        )
    ]
end
# swipl's distances (10.1.17, live below): 10 = the frame header (8) + the two variables — the
# choice point is gone; 19 = that + a choice point (9).
const _R_ORPOS = [
    (:oshallow, 10), (:odeep, 10), (:ofail, 10), (:oleft, 19), (:oafter, 19),
    # the conditionals (their clauses have a third slot, the condition's): after the commit of a
    # condition that left choice points (`pthen`), of one that left none (`pthen0`), of a fast one
    # (`pfast`); in the else branch (`pelse`: a callee failed; `pelsef`: a fast test failed); after
    # an if-then (`pit`)
    # — 11 everywhere: the frame header (8) + its three slots; nothing of the condition is left
    (:pthen, 11), (:pthen0, 11), (:pfast, 11), (:pelse, 11), (:pelsef, 11), (:pit, 11),
    # after a negation succeeded: its goal failed in a callee (`pnot`), or after leaving and
    # using up a callee's choice points (`pnotd`)
    (:pnot, 11), (:pnotd, 11)
]

@testset "around a disjunction the next frame lands where swipl's does (C_OR, CHP_JUMP)" begin
    clauses = _ror_pos_clauses()
    db = _rdb(clauses)
    _radd!(db, _rf("prolog_current_frame", _rv(1)))                # the stand-in, as for the cut
    ld = db.ld
    ours = Int[]
    live = Bool[]
    for (n, _) in _R_ORPOS
        answers = _rcall(
            db,
            _rf(n, _rv(90), _rv(91));
            at=function (qid, k)
                push!(live, _rpools_live(ld))
                k == 1 || return nothing
                q = ld.queries[LK.QueryFromQid(ld, qid)]
                push!(
                    ours, ld.frames[ld.choices[ld.BFR].frame].base - ld.frames[q.frame].base
                )
            end
        )
        @test !isempty(answers)
    end
    ours == last.(_R_ORPOS) || println(stderr, "  disjunction positions, kernel: ", ours)
    @test ours == last.(_R_ORPOS)
    @test !isempty(live) && all(live)
    if _R_SWIPL
        main =
            "main :- " *
            join(
                ("$n(A$n, B$n), D$n is B$n - A$n, writeln(D$n)" for (n, _) in _R_ORPOS),
                ", "
            ) *
            "."
        theirs = parse.(Int, _rswipl(clauses, (); main_text=main))
        theirs == last.(_R_ORPOS) ||
            println(stderr, "  disjunction positions, swipl: ", theirs)
        @test theirs == last.(_R_ORPOS)
    end
end

# ── a frame whose call fails before it is filled ────────────────────────────────────────────────
# ── the inline compilers' fall-back calls (V6b2) ────────────────────────────────────────────────
# Where upstream's compiler falls back to a call (pl-comp.c c:3488-3517), the kernel calls the
# built-in: `Term = Term`, and `==`/`\\==` on a void, a non-portable constant or two non-variables.
# Every answer and its determinism are swipl's.
@testset "the inline compilers' fall-back calls answer as swipl does (V6b2)" begin
    X, Y = _rv(1), _rv(2)
    fa = _rf("f", _rs("a"))
    clauses = [
        (_rf("u1", X, Y), _rf("=", _rf("f", X, _rs("b")), _rf("f", _rs("a"), Y))),  # Term = Term
        (_rs("u2"), _rf("=", _rs("a"), _rs("b"))),
        (_rf("e1", X), _rf("==", X, fa)),                                          # a compound
        (_rf("e2", X), _rf("==", X, _rg(16777216))),                               # not portable
        (_rf("e3", X), _rf("==", X, _rg(1.5))),
        (_rs("e4"), _rf("==", _rs("a"), _rs("a"))),                                # two atoms
        (_rf("e5", X), _rf("==", _rv(9), X)),                                      # a void side
        (_rf("n1", X), _rf("\\==", X, fa)),
        (_rf("n2", X), _rf("\\==", _rv(9), X)),
        (_rf("n3", X), _rf("\\==", X, _rg(-16777217)))
    ]
    db = _rdb(clauses)
    goals = [
        _rf("u1", _rv(100), _rv(101)), _rs("u2"),
        _rf("e1", fa), _rf("e1", _rf("f", _rs("b"))), _rf("e1", _rv(100)),
        _rf("e2", _rg(16777216)), _rf("e2", _rg(16777215)), _rf("e3", _rg(1.5)), _rs("e4"),
        _rf("e5", _rs("a")), _rf("n1", fa), _rf("n1", _rs("g")), _rf("n2", _rs("a")),
        _rf("n3", _rg(-16777217)), _rf("n3", _rg(3))
    ]
    ours = _rlines(db, goals)
    @test ours[1:2] == ["u1(a,b) det", "end"]
    @test count(==("end"), ours) == length(goals)
    @test all(l -> l == "end" || endswith(l, " det"), ours)
    if _R_SWIPL
        @test _rswipl(clauses, goals) == ours
    end
    # arg/3's fall-back is a call, as upstream's; arg/3 itself is nondeterministic
    # (PL_FA_NONDETERMINISTIC), a foreign predicate V9 brings: until then the call raises
    # existence_error(procedure, arg/3), where swipl answers `Y = a` (the interim, pinned)
    db2 = _rdb([(_rf("ag", Y), _rf("arg", _rg(1), fa, Y))])
    gd, ld = db2.gd, db2.ld
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    ld.slots[a + 1] = _rv(100)
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS,
        _rproc(db2, _rf("ag", _rv(100))), a)
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_EXCEPTION
    ball = LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1])
    formal = child(ball, 2)
    @test lk_name(child(formal, 1)) === :existence_error
    @test lk_name(child(formal, 2)) === :procedure
    @test lk_name(child(child(formal, 3), 2)) === :arg &&
        lk_value(child(child(formal, 3), 3)) == 3
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end

@testset "a call failing before its frame is filled: dropped where it is left (S_LIST)" begin
    Z = _rv(1)
    clauses = [
        (_rf("q42", _rnil()), nothing),
        (_rf("q42", _rcons(_rv(2), _rv(3))), nothing),
        (_rs("p42"), _rf("q42", _rs(:foo))),                       # fails: no list
        (_rs("p42"), nothing),
        (_rs("p42b"), _rf("q42", _rs(:foo))),
        (_rf("p42c", Z), _rconj(_rf("q42", _rs(:foo)), _rf("q42", Z)))
    ]
    db = _rdb(clauses)
    # q42's first call goes through S_VIRGIN, which raises lTop over the frame before it installs
    # S_LIST; only LATER calls fail with the frame still unfilled — p42's then backtracks to its own
    # clause choice point (deep_backtrack's CHP_CLAUSE arm), p42b's and p42c's to the query's CHP_TOP
    goals = [_rf("q42", _rs(:foo)), _rs("p42"), _rs("p42b"), _rf("p42c", _rv(9))]
    ours = _rlines(db, goals)
    @test ours == ["end", "p42 det", "end", "end", "end"]
    @test _rproc(db, _rf("q42", _rnil())).definition.codes[1] == LK.S_LIST   # the path taken
    @test db.ld.nframes == 0 && db.ld.nchoices == 0                 # every record dropped
    if _R_SWIPL
        @test _rswipl(clauses, goals) == ours
    end
end

# ── MQ6: positions after a deterministic exit ───────────────────────────────────────────────────
# A: swipl's `prolog_current_frame/1` / `prolog_current_choice/1` differences (V4b research, probed),
# the kernel running the SAME clauses with the real built-ins: not ISO, so a clause of `user` reaches
# them through `autoImport` (since V5c; the stand-in facts of V4b are gone, user, 2026-10-07). The
# distance is the answer's `B - A`, as swipl's: the choice point above the clause's frame, or
# (`:frame`) the callee's frame left by `qn`.
function _rpos_clauses()
    F, Ch, X, A, B, C, F0, F1, Y, P, Q, R = (_rv(k) for k in 1:12)
    pcf(v) = _rf("prolog_current_frame", v)
    pcc(v) = _rf("prolog_current_choice", v)
    return [
        (_rf("g", _rv(20), _rv(21), _rv(22)), nothing),
        (_rs("z"), nothing), (_rf("z", _rv(20)), nothing),
        (_rf("z", _rv(20), _rv(21)), nothing),
        (_rf("m1", _rg(1)), nothing), (_rf("m1", _rg(2)), nothing),
        (_rs("d"), nothing),
        (_rs("dr"), _rconj(_rs("d"), _rs("d"))),
        (_rf("d3", _rv(20), _rv(21), _rv(22)), nothing),
        (_rf("c1", F, Ch), _rconj(pcf(F), _rf("m1", X), pcc(Ch), _rf("z", X))),
        (_rf("mq6a", F, Ch), _rconj(pcf(F), _rs("d"), _rf("m1", X), pcc(Ch), _rf("z", X))),
        (_rf("mq6b", F, Ch), _rconj(pcf(F), _rs("dr"), _rf("m1", X), pcc(Ch), _rf("z", X))),
        (
            _rf("mq6c", F, Ch),
            _rconj(pcf(F), _rf("d3", A, B, C), _rf("m1", X), pcc(Ch), _rf("z", X),
                _rf("z", A, B), _rf("z", C))
        ),
        (_rf("qn", F1), _rconj(pcf(F1), _rs("z"))), (_rf("qn", _rv(20)), nothing),
        (_rf("mq6g", F0, F1), _rconj(pcf(F0), _rs("d"), _rf("qn", F1), _rs("z"))),
        (_rf("k", X, X, _rg(1)), nothing),
        (_rf("k", _rv(20), _rv(21), Y), _rconj(_rf("g", Y, P, Q), _rf("g", P, Q, _rv(22)))),
        (_rf("k", _rv(20), _rv(21), _rg(3)), nothing),
        (
            _rf("sh", F, Ch),
            _rconj(pcf(F), _rf("k", _rs(:a), _rs(:b), Y), pcc(Ch), _rf("z", Y))
        ),
        (_rf("t", _rg(3)), nothing),
        (_rf("s", X), _rconj(_rs("d"), _rf("m1", X), _rf("t", X))),
        (_rf("s", X), _rconj(_rf("g", X, P, Q), _rf("g", P, Q, R), _rf("z", R))),
        (_rf("s", _rv(20)), nothing),
        (_rf("dp", F, Ch), _rconj(pcf(F), _rf("s", X), pcc(Ch), _rf("z", X)))
    ]
end
const _R_POS = [(:c1, 20, :choice), (:mq6a, 20, :choice), (:mq6b, 20, :choice),
    (:mq6c, 23, :choice),
    (:mq6g, 10, :frame), (:sh, 24, :choice), (:dp, 23, :choice)]

@testset "positions after deterministic exits are swipl's (MQ6), and the pools hold only live records" begin
    clauses = _rpos_clauses()
    db = _rdb(clauses)
    ld = db.ld
    ours = Int[]
    live = Bool[]
    for (n, _, _) in _R_POS
        ans = _rcall(
            db, _rf(n, _rv(90), _rv(91)); at=(qid, k) -> push!(live, _rpools_live(ld))
        )
        m = match(r"^\w+\((-?\d+),(-?\d+)\)$", ans[1][1])     # the first answer: n(A,B)
        a, b = parse(Int, m[1]), parse(Int, m[2])
        push!(ours, b - a)
    end
    # the built-ins were reached through autoImport: `user`'s procedures hold `system`'s definitions
    for name in ("prolog_current_frame", "prolog_current_choice")
        up = LK.isCurrentProcedure(sym_key(_rs(name)), 1, db.user)
        @test up !== nothing && up.definition.module_ == LK.MODULE_system(db.gd).index
    end
    @test ours == [d for (_, d, _) in _R_POS]
    @test !isempty(live) && all(live)
    if _R_SWIPL
        main =
            "main :- " *
            join(
                ("$n(A$n, B$n), D$n is B$n - A$n, writeln(D$n)" for (n, _, _) in _R_POS),
                ", "
            ) * "."
        @test parse.(Int, _rswipl(clauses, (); main_text=main)) ==
            [d for (_, d, _) in _R_POS]
    end

    # B: libswipl's query API (V4b research: a C program over these clauses), PINNED — the first term
    # reference after each answer, relative to the query; the same clauses, no stand-ins needed.
    db2 = _rdb([
        (_rs("d"), nothing), (_rs("m0"), nothing), (_rs("m0"), nothing),
        (_rf("g", _rv(1), _rv(2), _rv(3)), nothing), (_rf("z", _rv(1)), nothing),
        (_rs("p6"), _rconj(_rs("d"), _rs("m0"), _rs("d"))),
        (_rs("p6det"), _rconj(_rs("d"), _rs("d"))),
        clauses[17:19]..., (_rf("m1", _rg(1)), nothing), (_rf("m1", _rg(2)), nothing),
        clauses[21:24]...
    ])
    tref(ld, qid) = (t=LK.PL_new_term_ref(ld); LK.PL_reset_term_refs(ld, t); t - qid)
    for (goal, want) in
        ((_rs("p6"), [(70, false), (45, true)]), (_rs("p6det"), [(45, true)]),
        (_rf("k", _rs(:a), _rs(:b), _rv(5)), [(67, false), (45, true)]),
        (_rf("s", _rv(5)), [(66, false), (45, true)]))
        got = Int[]
        answers = _rcall(db2, goal; at=(qid, k) -> push!(got, tref(db2.ld, qid)))
        @test got == first.(want)
        @test last.(answers) == last.(want)
    end
end

# ── defensive initialisation ────────────────────────────────────────────────────────────────────
# Defensive initialisation; see register Q3 (user, 2026-10-12). The cells a clause's `init_vars`
# lists hold fresh variables from the moment the clause gets its frame (`_init_clause_vars!`); its
# other cells are left as they were. Each `fv…` predicate below is called with equal arguments —
# it answers, and `prolog_current_frame/1` gives the frame's position — and then with different
# ones, a value planted over the stack above `lTop` first: it fails at `A == B`, before any goal
# on its other variables, and their cells are read from the stack. One predicate per point that
# hands a frame to a clause.
"The clauses: `D` and `E` are listed in `init_vars`, `G` is not."
function _rinit_clauses()
    F, A, B, D, E, G = (_rv(k) for k in 1:6)
    eq(v, i) = _rf("==", v, _rg(i))
    body = _rconj(
        _rf("prolog_current_frame", F), _rf("==", A, B),
        _rnot(_rconj(eq(D, 1), eq(D, 2), eq(E, 1), eq(E, 2), _rf("==", A, _rs("zz")))),
        _rf("=", G, _rg(1)), _rf("\\==", G, _rg(2))
    )
    h(name) = _rf(name, F, A, B)
    other(name) = _rf(name, _rv(7), _rv(8), _rv(9))
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("one", _rg(2)), nothing),
        (h("fvtrust"), body),                                       # its only clause
        (h("fvfirst"), body),                                       # the first of two
        (_rf("fvfirst", _rs("zz"), _rs("zz"), _rs("zz")), nothing),
        (other("fvshallow"), _rs("fail")),                          # fails in its own frame
        (h("fvshallow"), body),
        (other("fvdeep"), _rf("one", _rg(1))),                      # fails in a frame below
        (h("fvdeep"), body)
    ]
end

@testset "defensive initialisation: the cells a clause lists start as fresh variables" begin
    db = _rdb(_rinit_clauses())
    ld = db.ld
    planted = _rs("planted")
    arity = 3
    for name in ("fvtrust", "fvfirst", "fvshallow", "fvdeep")
        pr = _rproc(db, _rf(name, _rv(81), _rv(82), _rv(83)))
        cref = pr.definition.impl_clauses.first_clause
        lists = Vector{Int32}[]
        nvars = 0
        while cref !== nothing
            isempty(cref.clause.init_vars) || push!(lists, cref.clause.init_vars)
            isempty(cref.clause.init_vars) || (nvars = Int(cref.clause.prolog_vars))
            cref = cref.next
        end
        @test length(lists) == 1 && length(lists[1]) == 2          # one clause lists D and E
        @test nvars == arity + 3                                    # the arguments, D, E and G
        listed = Int.(lists[1])
        @test listed == [arity, arity + 1]          # D and E, the first two after the arguments; not A
        rest = setdiff(arity:(nvars - 1), listed)                   # G
        @test length(rest) == 1
        ans = _rcall(db, _rf(name, _rv(90), _rs("x"), _rs("x")))
        m = match(r"^\w+\((\d+),x,x\)$", ans[1][1])                 # the first answer: name(F,x,x)
        @test m !== nothing
        base = parse(Int, m[1])
        top = ld.lTop + 400
        length(ld.slots) < top && resize!(ld.slots, top)
        fill!(view(ld.slots, (ld.lTop + 1):top), planted)
        @test isempty(_rcall(db, _rf(name, _rv(90), _rs("x"), _rs("y"))))
        cells = [LK.argFrameP(base, v) + 1 for v in listed]
        @test all(c -> isassigned(ld.slots, c), cells)
        d = LK.resolve_term(ld, ld.slots[cells[1]])
        e = LK.resolve_term(ld, ld.slots[cells[2]])
        @test kind(d) === VAR && kind(e) === VAR                    # fresh, and unbound (resolve is the var)
        @test var_key(d) != var_key(e)                              # two variables, not one
        rest_cell = ld.slots[LK.argFrameP(base, rest[1]) + 1]       # the cell not listed: untouched
        @test LK.compareStandard(rest_cell, planted, true) == 0
    end
end

# Coverage (user, 2026-10-12): one place hands a frame to a clause and must initialise its listed
# cells. The check ties the two together in src/pl-wam.jl — every assignment of a clause to the
# running frame (`ld.frames[FR].clause = <cl>`, other than the `nothing` of frame teardown) is a
# clause entry, and each must be matched by a `_init_clause_vars!` call. A new entry point that
# sets the frame's clause without the call makes the counts diverge, and this fails. Goes with the
# initialisation when upstream fixes Q3.
@testset "every clause-entry point initialises the clause's cells (Q3 coverage)" begin
    src = read(joinpath(@__DIR__, "..", "..", "src", "pl-wam.jl"), String)
    lines = split(src, '\n')
    code(l) = strip(first(split(l, '#')))                       # the line without its comment
    entries = [
        l for l in lines if occursin(r"\bframes\[FR\]\.clause\s*=", code(l)) &&
            !occursin(r"=\s*nothing\b", code(l))
    ]
    inits = [l for l in lines if occursin(r"_init_clause_vars!\(ld,", code(l))]
    @test !isempty(entries) && !isempty(inits)                  # both sides non-empty
    @test length(entries) == length(inits)                      # no entry bypasses the call
    # and the known four are present by name, so a rename cannot hollow the check out
    for cl in ("ss_cl", "tc_cref", "sb_cl", "db_cl")
        @test any(l -> occursin("frames[FR].clause = $cl", code(l)), entries)
    end
    for v in ("ss_clause", "tc_clause", "sb_clause", "db_clause")
        @test any(
            l -> occursin("_init_clause_vars!(ld, ld.frames[FR].base, $v)", code(l)), inits
        )
    end
end

# ── where the next frame lands after a cut (V6a) ────────────────────────────────────────────────
# `I_CUT` lowers `lTop` to the clause's variables (vmi:2591), so a frame pushed after the cut lands
# there, whatever the cut discarded: a callee's choice point (`ccut`), the clause's own clause choice
# point (`kcut`), a callee frame holding choice points (`cdeep`). `qn/1` keeps its frame (its second
# clause is a choice point); the distance is its frame from the clause's, read as MQ6 reads it.
# swipl's distances, probed (scratchpad v6a_cut/cutpos.pl, stable over runs): with the cut 10 = the
# frame header (8) + the two variables; without it 27 and 19.
function _rcut_pos_clauses()
    F0, F1 = _rv(1), _rv(2)
    pcf(v) = _rf("prolog_current_frame", v)
    return [
        (_rs("z"), nothing), (_rs("nd2"), nothing), (_rs("nd2"), nothing),
        (_rs("ndf"), _rconj(_rs("nd2"), _rs("nd2"))),
        (_rf("qn", F1), _rconj(pcf(F1), _rs("z"))), (_rf("qn", _rv(20)), nothing),
        (
            _rf("ccut", F0, F1),
            _rconj(pcf(F0), _rs("nd2"), _rs("!"), _rf("qn", F1), _rs("z"))
        ),
        (_rf("cnocut", F0, F1), _rconj(pcf(F0), _rs("nd2"), _rf("qn", F1), _rs("z"))),
        (_rf("kcut", F0, F1), _rconj(pcf(F0), _rs("!"), _rf("qn", F1), _rs("z"))),
        (_rf("kcut", _rv(20), _rv(21)), nothing),
        (_rf("knocut", F0, F1), _rconj(pcf(F0), _rf("qn", F1), _rs("z"))),
        (_rf("knocut", _rv(20), _rv(21)), nothing),
        (
            _rf("cdeep", F0, F1),
            _rconj(pcf(F0), _rs("ndf"), _rs("!"), _rf("qn", F1), _rs("z"))
        )
    ]
end
const _R_CUTPOS = [(:ccut, 10), (:cnocut, 27), (:kcut, 10), (:knocut, 19), (:cdeep, 10)]

@testset "after a cut the next frame lands at the clause's variables (I_CUT), as in swipl" begin
    clauses = _rcut_pos_clauses()
    db = _rdb(clauses)
    _radd!(db, _rf("prolog_current_frame", _rv(1)))                # the stand-in (V5c: the real one)
    ld = db.ld
    ours = Int[]
    live = Bool[]
    for (n, _) in _R_CUTPOS
        answers = _rcall(
            db,
            _rf(n, _rv(90), _rv(91));
            at=function (qid, k)
                push!(live, _rpools_live(ld))
                k == 1 || return nothing
                q = ld.queries[LK.QueryFromQid(ld, qid)]
                push!(
                    ours, ld.frames[ld.choices[ld.BFR].frame].base - ld.frames[q.frame].base
                )
            end
        )
        @test !isempty(answers)
    end
    @test ours == last.(_R_CUTPOS)
    @test !isempty(live) && all(live)
    if _R_SWIPL
        main =
            "main :- " *
            join(
                ("$n(A$n, B$n), D$n is B$n - A$n, writeln(D$n)" for (n, _) in _R_CUTPOS),
                ", "
            ) *
            "."
        @test parse.(Int, _rswipl(clauses, (); main_text=main)) == last.(_R_CUTPOS)
    end
end

# ── a tail call's lTop, and the logical update view per call ────────────────────────────────────
"Open `goal`, ask for its first answer, read the next term reference after it (relative to the query)."
function _rfirst_tref(db::_RDB, goal::_R)::Tuple{Int, Int}
    ld = db.ld
    fid = LK.PL_open_foreign_frame(ld)
    qid = LK.PL_open_query(
        db.gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, goal), 0
    )
    rc = LK.PL_next_solution(db.gd, ld, qid)
    t = LK.PL_new_term_ref(ld)
    LK.PL_reset_term_refs(ld, t)
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return (rc, t - qid)
end

@testset "a tail call sets lTop (I_LCALL), and every call sees the current generation" begin
    # `w15 :- l15(foo).` departs by `I_LCALL` (its frame reused, lTop set to the callee's arguments)
    # into `S_LIST`, which fails before any supervisor raises lTop — so CHP_TOP's foreign frame opens
    # at the lTop `I_LCALL` left. libswipl's query API, probed (V4b): 54 after the failure, both on
    # l15's first call (through S_VIRGIN) and once S_LIST is installed.
    db = _rdb([(_rf("l15", _rnil()), nothing),
        (_rf("l15", _rcons(_rv(1), _rv(2))), nothing),
        (_rs("warm15"), _rf("l15", _rnil())),
        (_rs("w15b"), _rf("l15", _rs(:foo))), (_rs("w15"), _rf("l15", _rs(:foo)))])
    @test LK.I_LCALL in
        _rops(_rproc(db, _rs("w15")).definition.impl_clauses.first_clause.clause)
    @test _rfirst_tref(db, _rs("w15b")) == (0, 54)
    @test _rlines(db, [_rs("warm15")]) == ["warm15 det", "end"]
    @test _rproc(db, _rf("l15", _rnil())).definition.codes[1] == LK.S_LIST
    @test _rfirst_tref(db, _rs("w15")) == (0, 54)

    # The logical update view, per CALL (vmi:1900: every call re-stamps its frame's generation):
    # d16(2) retracted between the two answers, so the second call of d16 does not see it.
    X = _rv(1)
    clauses = [(_rf("m16", _rg(1)), nothing), (_rf("m16", _rg(2)), nothing),
        (_rf("d16", _rg(1)), nothing), (_rf("d16", _rg(2)), nothing),
        (_rf("c16", X), _rconj(_rf("m16", X), _rf("d16", X)))]
    db = _RDB()
    LK.setDynamicDefinition!(_rproc(db, _rf("d16", X)).definition, true)
    for (h, b) in clauses
        _radd!(db, h, b)
    end
    d16 = _rproc(db, _rf("d16", X)).definition
    retracted = Ref(false)
    ours = _rcall(
        db,
        _rf("c16", _rv(9));
        at=function (qid, k)
            k == 1 || return nothing
            LK.pl_retract!(db.gd, db.ld, d16, _rf("d16", _rg(2)), _ -> false)    # retract(d16(2))
            retracted[] = true
        end
    )
    @test retracted[] && ours == [("c16(1)", false)]
    if _R_SWIPL                              # the same semantics in swipl: retract inside the query
        @test _rswipl(
            [(_rf("m16", _rg(1)), nothing), (_rf("m16", _rg(2)), nothing),
                (_rf("d16", _rg(1)), nothing), (_rf("d16", _rg(2)), nothing),
                (
                    _rf("c16", X),
                    _rconj(_rf("m16", X), _rf("d16", X),
                        _rf(
                            "->", _rf("==", X, _rg(1)), _rf("retract", _rf("d16", _rg(2)))
                        ) |>
                        t -> _rf(";", t, _rs("true")))
                )],
            [_rf("c16", _rv(9))]; extra=":- dynamic d16/1.\n") == ["c16(1) nondet", "end"]
    end
end

# ── flatness: the last-call optimisation keeps the stack flat ───────────────────────────────────
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
    for i in 1:n
        ld.slots[args + i] = child(goal, i + 1)
    end
    fill!(view(ld.slots, (ld.lTop + 1):length(ld.slots)), _R_SENTINEL)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, goal), args
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    if rc != LK.PL_S_LAST                                           # the tripwire: say what tripped
        ex = rc == LK.PL_S_EXCEPTION ? LK.PL_exception(ld, qid) : 0
        ball = ex == 0 ? "none" : string(ld.slots[ex + 1])
        error("_rhighwater: $(_rsrc(goal)) returned $rc, ball $ball (growth past lMax?)")
    end
    high = findlast(t -> t !== _R_SENTINEL, ld.slots) - 1           # a position: slots[p + 1]
    tr, st = length(ld.trail), length(ld.bindings)
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    ld.stacks_limit = saved_limit
    return (high - qid, tr, st)
end

@testset "flatness: concatenate on 10^3..10^5 elements reaches one high-water mark" begin
    db = _rdb(_rnreverse_clauses())
    catg(n) = _rf("concatenate", _rints(1:n), _rlist(_rs(:x)), _rv(1))
    marks = Dict(n => _rhighwater(db, catg(n)) for n in (10^3, 10^4, 10^5))
    @test marks[10 ^ 3][1] == marks[10 ^ 4][1] == marks[10 ^ 5][1]
    for n in (10^3, 10^4, 10^5)                                     # reported: no collector yet (G1)
        @info "concatenate/3, $n elements: local high-water qid+$(marks[n][1]), trail $(marks[n][2]), binding store $(marks[n][3])"
        @test marks[n][2] == n + 1 && marks[n][3] == n + 1
    end
    # …and the check can fail: without the last-call optimisation the mark grows with the list
    # (lists short enough for the region below the spare, which the tripwire keeps fixed: V5d)
    db.ld.prolog_flag_last_call = false
    off = [_rhighwater(db, catg(n))[1] for n in (25, 50, 100)]
    db.ld.prolog_flag_last_call = true
    @test off[1] < off[2] < off[3] && off[1] > marks[10 ^ 3][1]
    # and the same answer either way
    @test _rlines(db, [catg(3)]) == ["concatenate([1,2,3],[x],[1,2,3,x]) det", "end"]
end

# V7: qsort's partition/4 — a clause choice point, `=</2`, a cut, then the last call — stays flat
# too, through both its clauses (the elements below the pivot take the cut, the others the second
# clause); without the last-call optimisation the mark grows.
@testset "flatness: qsort's partition on 10^3..10^5 elements reaches one high-water mark (V7)" begin
    db = _rdb(_rqsort_clauses())
    part(n) = _rf("partition", _rints(1:n), _rg(n ÷ 2), _rv(1), _rv(2))
    marks = Dict(n => _rhighwater(db, part(n))[1] for n in (10^3, 10^4, 10^5))
    @test marks[10 ^ 3] == marks[10 ^ 4] == marks[10 ^ 5]
    db.ld.prolog_flag_last_call = false
    off = [_rhighwater(db, part(n))[1] for n in (20, 40, 80)]      # larger frames: fewer elements
    db.ld.prolog_flag_last_call = true
    @test off[1] < off[2] < off[3] && off[1] > marks[10 ^ 3]
end

# V9d soft-cut, SC9: the I_DEPART reclaim. `lco()` emits the L_NOLCO block only when every
# argument is simple and none overwrites another; a COMPOUND arg (`sl`, `f(K)`) or a SWAP (`sw`,
# `B, A`) makes it bail, so the clause ends in a plain `I_DEPART` that runs its own LCO check. The
# soft-cut `( p2(X) *-> X == 2 ; true )` unlinks its else-choice in the MIDDLE branch (p2's choice
# is above it); `X == 2` fails for X=1, backtracks into p2, whose last clause pops p2's choice, and
# X=2 succeeds — so at the tail call `BFR <= FR` while the unlinked record is still above the frame.
# That is exactly where I_DEPART's `dropUnlinkedChoices!` is needed (SC9). Flat baseline; SC9 grows.
function _ri_depart_clauses()
    N, N1, A, B, K, X = (_rv(k) for k in 1:6)
    sc(c, t, e) = _ror(_rf("*->", c, t), e)
    cond = sc(_rf("p2", X), _rf("==", X, _rg(2)), _rs("true"))
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("p2", _rg(1)), nothing), (_rf("p2", _rg(2)), nothing),
        (_rf("sl", _rg(0), _rv(9)), _rs("!")),
        (
            _rf("sl", N, _rf("f", K)),
            _rconj(
                cond, _rf("is", N1, _rf("-", N, _rg(1))), _rf("sl", N1, _rf("f", K))
            )
        ),
        (_rf("sw", _rg(0), _rv(9), _rv(8)), _rs("!")),
        (
            _rf("sw", N, A, B),
            _rconj(
                cond, _rf("is", N1, _rf("-", N, _rg(1))), _rf("sw", N1, B, A)
            )
        )
    ]
end

@testset "flatness: a soft-cut whose plain-I_DEPART tail call reuses its frame stays flat (V9d, SC9)" begin
    db = _rdb(_ri_depart_clauses())
    # both recursive clauses end in a PLAIN I_DEPART (the LCO path SC9 removes the reclaim from),
    # not the L_NOLCO block — assert it, else `lco()` accepts shapes upstream rejects
    for (name, args) in (("sl", 2), ("sw", 3))
        ops = Set{UInt64}()
        cref =
            _rproc(db, mk_expr(_R, _R[_rs(name); [_rv(80 + i) for i in 1:args]])).definition.impl_clauses.first_clause
        while cref !== nothing
            union!(ops, _rops(cref.clause))
            cref = cref.next
        end
        @test LK.I_DEPART in ops && LK.C_SOFTCUT in ops
        @test !(LK.L_NOLCO in ops)
    end
    for (name, g) in (("sl", n -> _rf("sl", _rg(n), _rf("f", _rv(1)))),
        ("sw", n -> _rf("sw", _rg(n), _rg(7), _rg(8))))
        marks = Dict(k => _rhighwater(db, g(k)) for k in (10^3, 10^4, 10^5))
        @test marks[10 ^ 3][1] == marks[10 ^ 4][1] == marks[10 ^ 5][1]   # SC9: grows with N
        @info "$name (plain I_DEPART through *->), high-water qid+$(marks[10 ^ 3][1])"
    end
    @test db.ld.nchoices == 0 && db.ld.nframes == 0
end

@testset "10^4 open/next/close cycles of nreverse leave everything at its baseline" begin
    db = _rdb(_rnreverse_clauses())
    ld = db.ld
    snap() = (ld.lTop, ld.nframes, ld.nchoices, ld.nfliframes, ld.nqueries, ld.BFR,
        ld.fli_context,
        ld.environment_frame, ld.aTop, ld.nbframes, ld.bTop, length(ld.trail),
        length(ld.bindings))
    goal = _rs("nreverse")
    base = snap()
    ok = 0
    for _ in 1:(10 ^ 4)
        _rcall(db, goal)
        snap() == base && (ok += 1)
    end
    @test ok == 10^4
end

LK_TERM_IMPL == "reference" &&
    @testset "warm, a query of calls and exits allocates nothing (reference type)" begin
        db = _rdb([(_rs("d"), nothing), (_rs("m0"), nothing), (_rs("m0"), nothing),
            (_rs("p6"), _rconj(_rs("d"), _rs("m0"), _rs("d"))),
            (_rs("p6det"), _rconj(_rs("d"), _rs("d")))])
        ld = db.ld
        function onlynext(goal)
            fid = LK.PL_open_foreign_frame(ld)
            qid = LK.PL_open_query(
                db.gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, goal), 0
            )
            a = @allocated while true
                rc = LK.PL_next_solution(db.gd, ld, qid)
                (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
            end
            LK.PL_close_query(ld, qid)
            LK.PL_close_foreign_frame(ld, fid)
            return a
        end
        for _ in 1:3
            onlynext(_rs("p6"))
            onlynext(_rs("p6det"))
        end
        @test onlynext(_rs("p6")) == 0 && onlynext(_rs("p6det")) == 0
    end
