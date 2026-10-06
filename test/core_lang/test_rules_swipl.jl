# ORIGINAL: rules through the VM — calls, last calls and body arguments (V4b) — against swipl 10.1.16; upstream has no such harness.
# test/core_lang/test_rules_swipl.jl — V4b's gate (port_inventory row V4b; user's decisions 2026-10-05):
#   * nreverse: the answer and its determinism identical to swipl's (`PL_S_LAST`, the next term
#     reference at +45 — libswipl's own, probed);
#   * an EXECUTION DIFFERENTIAL over random rule clauses: every answer and its determinism identical
#     to swipl's, with the body family covered — each instruction of it compiled in the corpus;
#   * a frame that fails before it is filled (`S_LIST`, vmi:3607-3608): dropped where `deep_backtrack`
#     leaves it, and swipl's answers;
#   * POSITIONS after a deterministic exit (MQ6): seven clauses as swipl's `prolog_current_frame/1`
#     and `prolog_current_choice/1` differences — stand-in facts of those names in the kernel (V5
#     brings the real ones), pinned and live — and libswipl's query API, pinned (the first term
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
At an answer: the choice points are exactly the `BFR` chain, and the frames exactly those on the
parent chains of the current frame and of the choice points' frames — so a record a drop missed
(MQ6: an exit that does not lower `lTop`) is a record too many.
"""
function _rpools_live(ld::LK.PL_local_data{_R})::Bool
    nch = 0
    c = ld.BFR
    fr = Set{Int}()
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
# the kernel running the SAME clauses with stand-in facts of those two names (user, 2026-10-05; V5
# brings the real built-ins — port_inventory row V5). Read at the first answer from the records:
# the choice point above the clause's frame, or (`:frame`) the callee's frame left by `qn`.
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
    _radd!(db, _rf("prolog_current_frame", _rv(1)))                # the stand-ins (V5: the real ones)
    _radd!(db, _rf("prolog_current_choice", _rv(1)))
    ld = db.ld
    ours = Int[]
    live = Bool[]
    for (n, _, what) in _R_POS
        _rcall(
            db,
            _rf(n, _rv(90), _rv(91));
            at=function (qid, k)
                push!(live, _rpools_live(ld))
                k == 1 || return nothing
                q = ld.queries[LK.QueryFromQid(ld, qid)]
                f = ld.frames[q.frame].base
                push!(
                    ours,
                    if what === :choice
                        ld.choices[ld.BFR].base - f
                    else
                        ld.frames[ld.choices[ld.BFR].frame].base - f
                    end
                )
            end
        )
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
    @assert rc == LK.PL_S_LAST
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
    db.ld.prolog_flag_last_call = false
    off = [_rhighwater(db, catg(n))[1] for n in (50, 100, 200)]
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
