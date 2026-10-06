#!/usr/bin/env julia
# tools/bench.jl — the per-chunk PERFORMANCE REPORT: each ported primitive against swipl, on the
# same terms, then a profile of the worst.
#
#   julia --project=. tools/bench.jl                     # every case
#   julia --project=. tools/bench.jl variant             # the cases whose name contains "variant"
#   julia --project=. tools/bench.jl --profile=NAME      # profile case NAME (default: worst ratio)
#   julia --project=. tools/bench.jl --no-profile
#   julia --project=. tools/bench.jl --no-compile        # without the run loop's fresh-process report
#
# A STANDING STEP for every chunk, beside the JET/Aqua/AllocCheck gates (user, 2026-10-03) — a
# report, not a pass/fail gate: a new primitive gets a case here, with its swipl goal. It follows
# the workspace's measurement rules: THREE runs from ONE process, the minimum reported and the
# spread shown; every number beside its upstream pair, in µs; profile before attributing a cost.
# Both sides measure ONE statistic (user, 2026-10-05): N calls per run (N doubled until a run takes
# RUN_S), a full collection before each run and every collection during it counted, WALL time per
# call, the minimum of three runs; the machine's idle CPU is recorded before and after the runs.
#
# Profile is not a dependency: it comes from the global environment (see
# tools/repl.jl). swipl comes from PATH; without it the report has no upstream column.
using LogicKernel, Profile, Printf
using LogicKernel:
    is_variant_ptr,
    pl_variant_sha1,
    pl_variant_hash,
    pl_term_hash,
    compareStandard,
    PL_local_data,
    pl_unify!,
    pl_unify_with_occurs_check!,
    Mark,
    Undo!,
    PL_global_data,
    lookupProcedure,
    setDynamicDefinition!,
    MODULE_user,
    compileClause,
    assertDefinition!,
    pl_clause!,
    CL_END

# ── fixtures: the same terms in Julia and in Prolog ─────────────────────────────────────────────
const BT = DefaultTerm
_a(x::Symbol) = sym_term(BT, x)
let n = UInt64(0)
    global _v() = mk_var(BT, n += 1)
end
"`f/2` tree of depth `d`, unshared, each leaf a fresh `leaf()` — Prolog `tree/3` below."
_tree(d::Int, leaf)::BT =
    d == 0 ? leaf() : mk_expr(BT, BT[_a(:f), _tree(d - 1, leaf), _tree(d - 1, leaf)])

const DEPTH = 12
const CELLS = 2^(DEPTH + 1) - 1                     # cells per tree: compounds + leaves
const G1, G2 = _tree(DEPTH, () -> _a(:a)), _tree(DEPTH, () -> _a(:a))   # ground
const V1, V2 = _tree(DEPTH, _v), _tree(DEPTH, _v)                       # 2^DEPTH variables each
const LD = PL_local_data{BT}()                                          # the unify cases' bindings

"One attempt, as a search makes it: mark, unify, undo — swipl's `forall/2` undoes the same way."
function _attempt(unify, a::BT, b::BT)::Bool
    m = Mark(LD)
    r = unify(LD, a, b)
    Undo!(LD, m)
    return r
end

"The same attempt with the undo in a `finally`, as the clause enumerations make it."
function _attempt_finally(unify, a::BT, b::BT)::Bool
    m = Mark(LD)
    try
        return unify(LD, a, b)
    finally
        Undo!(LD, m)
    end
end

const SMALL_A, SMALL_B = mk_expr(BT, BT[_a(:f), _v()]), mk_expr(BT, BT[_a(:f), _a(:a)])

# a dynamic predicate cp/2 of 1000 facts cp(I, a), for clause/2 — Prolog `cp/2` below
const CP_GD = PL_global_data{BT}()
const CP_LD = PL_local_data{BT}()                             # the compiler reads its flags
const CP_USER = MODULE_user(CP_GD)
const CP_PROC = lookupProcedure(_a(:cp), 2, CP_USER)
const CP_DEF = CP_PROC.definition
setDynamicDefinition!(CP_DEF, true)                            # :- dynamic cp/2.
_cp_compile(h::BT) = compileClause(CP_GD, CP_LD, h, nothing, CP_PROC, CP_USER)
for i in 1:1000
    assertDefinition!(
        CP_GD, CP_DEF, _cp_compile(mk_expr(BT, BT[_a(:cp), gnd_term(BT, i), _a(:a)])),
        CL_END
    )
end
const CP_GOAL = mk_expr(BT, BT[_a(:cp), _v(), _v()])

# compiling: a fact `cp(7, a)`, and the head and variable analysis of nreverse's rule clause
# `app([H|T], L, [H|R]) :- app(T, L, R)` (V1 — its body code is V2, so Julia only, no swipl goal)
const CC_FACT = mk_expr(BT, BT[_a(:cp), gnd_term(BT, 7), _a(:a)])
_cons(h::BT, t::BT)::BT = mk_expr(BT, BT[_a(Symbol("[|]")), h, t])
const APP_H, APP_T, APP_L, APP_R = _v(), _v(), _v(), _v()
const APP_HEAD = mk_expr(BT, BT[_a(:app), _cons(APP_H, APP_T), APP_L, _cons(APP_H, APP_R)])
const APP_BODY = mk_expr(BT, BT[_a(:app), APP_T, APP_L, APP_R])
const APP_PROC = lookupProcedure(_a(:app), 3, CP_USER)
# the whole rule (V2): head, I_ENTER, the body's last call with its LCO block, I_EXIT

# the local stack (V3): `n` frames, each with a choice point, pushed and then popped by one lowering
const ST_LD = PL_local_data{BT}()
LogicKernel.ensureLocalSpace(ST_LD, 1 << 16)                               # grown once, up front
function _stack_frames(ld::PL_local_data{BT}, n::Int)::Nothing
    base = ld.lTop
    for _ in 1:n
        fr = LogicKernel.pushFrame!(ld, ld.lTop)
        ld.lTop = LogicKernel.argFrameP(ld.frames[fr].base, 3)
        LogicKernel.newChoice(ld, LogicKernel.CHP_CLAUSE, fr)
    end
    ld.BFR = 0
    LogicKernel.lowerLTop!(ld, base)
    return nothing
end

# a query through the VM (V4a), as a foreign caller makes it — open, every answer, close: all of
# cp(X, Y) over the 1000 facts, and cp(500, Y), narrowed by the first-argument index
const Q_LD = PL_local_data{BT}()
const Q_ALL, Q_ONE = _v(), gnd_term(BT, 500)
function _vm_query(ld::PL_local_data{BT}, a1::BT)::Int
    fid = LogicKernel.PL_open_foreign_frame(ld)
    args = LogicKernel.PL_new_term_refs(ld, 2)
    ld.slots[args + 1] = a1                                         # term reference args + 0
    qid = LogicKernel.PL_open_query(
        CP_GD, ld, nothing, LogicKernel.PL_Q_NORMAL, CP_PROC, args
    )
    n = 0
    while LogicKernel.PL_next_solution(CP_GD, ld, qid) == LogicKernel.PL_S_TRUE
        n += 1
    end
    LogicKernel.PL_close_query(ld, qid)
    LogicKernel.PL_close_foreign_frame(ld, fid)
    return n
end

# nreverse (V4b): bench/programs/nreverse.pl's clauses in a database of their own, run through the
# query API — open, the one deterministic answer, close; swipl runs the same file's `nreverse`
const NR_GD = PL_global_data{BT}()
const NR_LD = PL_local_data{BT}()
const NR_USER = MODULE_user(NR_GD)
_nrf(f::Symbol, xs::BT...) = mk_expr(BT, BT[_a(f), xs...])
_nrcons(h::BT, t::BT) = mk_expr(BT, BT[_a(Symbol("[|]")), h, t])
_nrnil() = mk_nil(BT)
function _nr_add!(head::BT, body::Union{Nothing, BT})
    name, n = kind(head) === SYM ? (head, 0) : (child(head, 1), nchildren(head) - 1)
    pr = lookupProcedure(name, n, NR_USER)
    assertDefinition!(
        NR_GD, pr.definition, compileClause(NR_GD, NR_LD, head, body, pr, NR_USER), CL_END
    )
    return pr
end
let (X, L0, L, L1, L2, L3) = (_v() for _ in 1:6)
    _nr_add!(
        _a(:nreverse),
        _nrf(
            :nreverse, foldr(_nrcons, [gnd_term(BT, i) for i in 1:30]; init=_nrnil()), _v()
        )
    )
    _nr_add!(_nrf(:nreverse, _nrcons(X, L0), L),
        _nrf(
            Symbol(","),
            _nrf(:nreverse, L0, L1),
            _nrf(:concatenate, L1, _nrcons(X, _nrnil()), L)
        ))
    _nr_add!(_nrf(:nreverse, _nrnil(), _nrnil()), nothing)
    _nr_add!(
        _nrf(:concatenate, _nrcons(X, L1), L2, _nrcons(X, L3)),
        _nrf(:concatenate, L1, L2, L3)
    )
    _nr_add!(_nrf(:concatenate, _nrnil(), L, L), nothing)
end
const NR_PROC = lookupProcedure(_a(:nreverse), 0, NR_USER)
function _vm_nreverse()::Int
    fid = LogicKernel.PL_open_foreign_frame(NR_LD)
    qid = LogicKernel.PL_open_query(
        NR_GD, NR_LD, nothing, LogicKernel.PL_Q_NORMAL, NR_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(NR_GD, NR_LD, qid)
    LogicKernel.PL_close_query(NR_LD, qid)
    LogicKernel.PL_close_foreign_frame(NR_LD, fid)
    return rc
end
@assert _vm_nreverse() == LogicKernel.PL_S_TRUE

# derive (V6c2): bench/programs/derive.pl's clauses in a database of their own (derive.pl and
# nreverse.pl both define `top/0`), run through the query API as `top` — ops8, log10, divide10;
# swipl runs the same file's three goals (its `top` line left out of the shared program text)
const DR_GD = PL_global_data{BT}()
const DR_LD = PL_local_data{BT}()
const DR_USER = MODULE_user(DR_GD)
function _dr_add!(head::BT, body::Union{Nothing, BT})
    name, n = kind(head) === SYM ? (head, 0) : (child(head, 1), nchildren(head) - 1)
    pr = lookupProcedure(name, n, DR_USER)
    assertDefinition!(
        DR_GD, pr.definition, compileClause(DR_GD, DR_LD, head, body, pr, DR_USER), CL_END
    )
    return pr
end
let (U, V, X, DU, DV, N, N1) = (_v() for _ in 1:7)
    x = _a(:x)
    pw(a, b) = _nrf(:^, a, b)
    d(a, b, c) = _nrf(:d, a, b, c)
    conj(gs...) = foldr((g, r) -> _nrf(Symbol(","), g, r), gs)
    nest(f, t, n) = n == 0 ? t : nest(f, f(t), n - 1)
    cut = _a(Symbol("!"))
    _dr_add!(_a(:top), conj(_a(:ops8), _a(:log10), _a(:divide10)))
    _dr_add!(
        _a(:ops8),
        d(
            _nrf(:*, _nrf(:+, x, gnd_term(BT, 1)),
                _nrf(:*, _nrf(:+, pw(x, gnd_term(BT, 2)), gnd_term(BT, 2)),
                    _nrf(:+, pw(x, gnd_term(BT, 3)), gnd_term(BT, 3)))), x, _v())
    )
    _dr_add!(_a(:log10), d(nest(t -> _nrf(:log, t), x, 10), x, _v()))
    _dr_add!(_a(:divide10), d(nest(t -> _nrf(:/, t, x), x, 9), x, _v()))
    _dr_add!(d(_nrf(:+, U, V), X, _nrf(:+, DU, DV)), conj(cut, d(U, X, DU), d(V, X, DV)))
    _dr_add!(d(_nrf(:-, U, V), X, _nrf(:-, DU, DV)), conj(cut, d(U, X, DU), d(V, X, DV)))
    _dr_add!(d(_nrf(:*, U, V), X, _nrf(:+, _nrf(:*, DU, V), _nrf(:*, U, DV))),
        conj(cut, d(U, X, DU), d(V, X, DV)))
    _dr_add!(
        d(_nrf(:/, U, V), X,
            _nrf(:/, _nrf(:-, _nrf(:*, DU, V), _nrf(:*, U, DV)), pw(V, gnd_term(BT, 2)))),
        conj(cut, d(U, X, DU), d(V, X, DV)))
    _dr_add!(d(pw(U, N), X, _nrf(:*, _nrf(:*, DU, N), pw(U, N1))),
        conj(
            cut, _nrf(:integer, N), _nrf(:is, N1, _nrf(:-, N, gnd_term(BT, 1))), d(U, X, DU)
        ))
    _dr_add!(d(_nrf(:-, U), X, _nrf(:-, DU)), conj(cut, d(U, X, DU)))
    _dr_add!(d(_nrf(:exp, U), X, _nrf(:*, _nrf(:exp, U), DU)), conj(cut, d(U, X, DU)))
    _dr_add!(d(_nrf(:log, U), X, _nrf(:/, DU, U)), conj(cut, d(U, X, DU)))
    _dr_add!(d(X, X, gnd_term(BT, 1)), cut)
    _dr_add!(d(_v(), _v(), gnd_term(BT, 0)), nothing)
end
const DR_PROC = lookupProcedure(_a(:top), 0, DR_USER)
function _vm_derive()::Int
    fid = LogicKernel.PL_open_foreign_frame(DR_LD)
    qid = LogicKernel.PL_open_query(
        DR_GD, DR_LD, nothing, LogicKernel.PL_Q_NORMAL, DR_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(DR_GD, DR_LD, qid)
    LogicKernel.PL_close_query(DR_LD, qid)
    LogicKernel.PL_close_foreign_frame(DR_LD, fid)
    return rc
end
@assert _vm_derive() == LogicKernel.PL_S_TRUE
const DERIVE_PL = read(joinpath(@__DIR__, "..", "bench", "programs", "derive.pl"), String)
@assert count("top:-ops8,log10,divide10.", DERIVE_PL) == 1      # the line left out, exactly once
const DERIVE_PROLOG = replace(DERIVE_PL, "top:-ops8,log10,divide10." => "")

# qsort (V7): bench/programs/qsort.pl's clauses in a database of their own (its `top/0` too), run
# as `qsort`; swipl runs the same file's `qsort`
const QS_GD = PL_global_data{BT}()
const QS_LD = PL_local_data{BT}()
const QS_USER = MODULE_user(QS_GD)
function _qs_add!(head::BT, body::Union{Nothing, BT})
    name, n = kind(head) === SYM ? (head, 0) : (child(head, 1), nchildren(head) - 1)
    pr = lookupProcedure(name, n, QS_USER)
    assertDefinition!(
        QS_GD, pr.definition, compileClause(QS_GD, QS_LD, head, body, pr, QS_USER), CL_END
    )
    return pr
end
let (X, L, R, R0, L1, L2, R1, Y) = (_v() for _ in 1:8)
    conj(gs...) = foldr((g, r) -> _nrf(Symbol(","), g, r), gs)
    nums = [27, 74, 17, 33, 94, 18, 46, 83, 65, 2, 32, 53, 28, 85, 99, 47, 28, 82, 6, 11,
        55, 29,
        39, 81, 90, 37, 10, 0, 66, 51, 7, 21, 85, 27, 31, 63, 75, 4, 95, 99, 11, 28, 61, 74,
        18, 92,
        40, 53, 59, 8]
    _qs_add!(_a(:qsort),
        _nrf(
            :qsort,
            foldr(_nrcons, [gnd_term(BT, i) for i in nums]; init=_nrnil()),
            _v(),
            _nrnil()
        ))
    _qs_add!(_nrf(:qsort, _nrcons(X, L), R, R0),
        conj(_nrf(:partition, L, X, L1, L2), _nrf(:qsort, L2, R1, R0),
            _nrf(:qsort, L1, R, _nrcons(X, R1))))
    _qs_add!(_nrf(:qsort, _nrnil(), R, R), nothing)
    _qs_add!(_nrf(:partition, _nrcons(X, L), Y, _nrcons(X, L1), L2),
        conj(_nrf(Symbol("=<"), X, Y), _a(Symbol("!")), _nrf(:partition, L, Y, L1, L2)))
    _qs_add!(_nrf(:partition, _nrcons(X, L), Y, L1, _nrcons(X, L2)),
        _nrf(:partition, L, Y, L1, L2))
    _qs_add!(_nrf(:partition, _nrnil(), _v(), _nrnil(), _nrnil()), nothing)
end
const QS_PROC = lookupProcedure(_a(:qsort), 0, QS_USER)
function _vm_qsort()::Int
    fid = LogicKernel.PL_open_foreign_frame(QS_LD)
    qid = LogicKernel.PL_open_query(
        QS_GD, QS_LD, nothing, LogicKernel.PL_Q_NORMAL, QS_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(QS_GD, QS_LD, qid)
    LogicKernel.PL_close_query(QS_LD, qid)
    LogicKernel.PL_close_foreign_frame(QS_LD, fid)
    return rc
end
@assert _vm_qsort() == LogicKernel.PL_S_TRUE
const QSORT_PL = read(joinpath(@__DIR__, "..", "bench", "programs", "qsort.pl"), String)
@assert count("top:-qsort.", QSORT_PL) == 1                 # the line left out, exactly once
const QSORT_PROLOG = replace(QSORT_PL, "top:-qsort." => "")

# poly_10 (V8): bench/programs/poly_10.pl's clauses in a database of their own (its `top/0` too),
# run as `poly_10`; swipl runs the same file's `poly_10` — A_ADD_FC (`M is N-1`), `>>`, `<<`
const PY_GD = PL_global_data{BT}()
const PY_LD = PL_local_data{BT}()
const PY_USER = MODULE_user(PY_GD)
function _py_add!(head::BT, body::Union{Nothing, BT})
    name, n = kind(head) === SYM ? (head, 0) : (child(head, 1), nchildren(head) - 1)
    pr = lookupProcedure(name, n, PY_USER)
    assertDefinition!(
        PY_GD, pr.definition, compileClause(PY_GD, PY_LD, head, body, pr, PY_USER), CL_END
    )
    return pr
end
let (Var, Terms1, Terms2, Terms, Var1, Var2, Poly, C, C1, C2, X, E, E1, E2, N, M, Part,
        Result,
        P, Q, Term, PartA, PartB, NewTerm, NewTerms) = (_v() for _ in 1:25)
    conj(gs...) = foldr((g, r) -> _nrf(Symbol(","), g, r), gs)
    list(xs...) = foldr(_nrcons, collect(BT, xs); init=_nrnil())
    term(a, b) = _nrf(:term, a, b)
    poly(a, b) = _nrf(:poly, a, b)
    g(i) = gnd_term(BT, i)
    cut = _a(Symbol("!"))
    _py_add!(_a(:top), _a(:poly_10))
    _py_add!(_a(:poly_10), conj(_nrf(:test_poly, P), _nrf(:poly_exp, g(10), P, _v())))
    _py_add!(_nrf(:test_poly, P),
        conj(
            _nrf(:poly_add, poly(_a(:x), list(term(g(0), g(1)), term(g(1), g(1)))),
                poly(_a(:y), list(term(g(1), g(1)))), Q),
            _nrf(:poly_add, poly(_a(:z), list(term(g(1), g(1)))), Q, P)))
    _py_add!(_nrf(:less_than, _a(:x), _a(:y)), nothing)
    _py_add!(_nrf(:less_than, _a(:y), _a(:z)), nothing)
    _py_add!(_nrf(:less_than, _a(:x), _a(:z)), nothing)
    _py_add!(_nrf(:poly_add, poly(Var, Terms1), poly(Var, Terms2), poly(Var, Terms)),
        conj(cut, _nrf(:term_add, Terms1, Terms2, Terms)))
    _py_add!(_nrf(:poly_add, poly(Var1, Terms1), poly(Var2, Terms2), poly(Var1, Terms)),
        conj(_nrf(:less_than, Var1, Var2), cut,
            _nrf(:add_to_order_zero_term, Terms1, poly(Var2, Terms2), Terms)))
    _py_add!(_nrf(:poly_add, Poly, poly(Var, Terms2), poly(Var, Terms)),
        conj(cut, _nrf(:add_to_order_zero_term, Terms2, Poly, Terms)))
    _py_add!(_nrf(:poly_add, poly(Var, Terms1), C, poly(Var, Terms)),
        conj(cut, _nrf(:add_to_order_zero_term, Terms1, C, Terms)))
    _py_add!(_nrf(:poly_add, C1, C2, C), _nrf(:is, C, _nrf(:+, C1, C2)))
    _py_add!(_nrf(:term_add, _nrnil(), X, X), cut)
    _py_add!(_nrf(:term_add, X, _nrnil(), X), cut)
    _py_add!(
        _nrf(:term_add, _nrcons(term(E, C1), Terms1), _nrcons(term(E, C2), Terms2),
            _nrcons(term(E, C), Terms)),
        conj(cut, _nrf(:poly_add, C1, C2, C), _nrf(:term_add, Terms1, Terms2, Terms)))
    _py_add!(
        _nrf(:term_add, _nrcons(term(E1, C1), Terms1), _nrcons(term(E2, C2), Terms2),
            _nrcons(term(E1, C1), Terms)),
        conj(_nrf(:<, E1, E2), cut,
            _nrf(:term_add, Terms1, _nrcons(term(E2, C2), Terms2), Terms)))
    _py_add!(
        _nrf(
            :term_add, Terms1, _nrcons(term(E2, C2), Terms2), _nrcons(term(E2, C2), Terms)
        ),
        _nrf(:term_add, Terms1, Terms2, Terms))
    _py_add!(
        _nrf(:add_to_order_zero_term, _nrcons(term(g(0), C1), Terms), C2,
            _nrcons(term(g(0), C), Terms)),
        conj(cut, _nrf(:poly_add, C1, C2, C)))
    _py_add!(
        _nrf(:add_to_order_zero_term, Terms, C, _nrcons(term(g(0), C), Terms)), nothing
    )
    _py_add!(_nrf(:poly_exp, g(0), _v(), g(1)), cut)
    _py_add!(_nrf(:poly_exp, N, Poly, Result),
        conj(_nrf(:is, M, _nrf(:>>, N, g(1))), _nrf(:is, N, _nrf(:<<, M, g(1))), cut,
            _nrf(:poly_exp, M, Poly, Part), _nrf(:poly_mul, Part, Part, Result)))
    _py_add!(_nrf(:poly_exp, N, Poly, Result),
        conj(_nrf(:is, M, _nrf(:-, N, g(1))), _nrf(:poly_exp, M, Poly, Part),
            _nrf(:poly_mul, Poly, Part, Result)))
    _py_add!(_nrf(:poly_mul, poly(Var, Terms1), poly(Var, Terms2), poly(Var, Terms)),
        conj(cut, _nrf(:term_mul, Terms1, Terms2, Terms)))
    _py_add!(_nrf(:poly_mul, poly(Var1, Terms1), poly(Var2, Terms2), poly(Var1, Terms)),
        conj(_nrf(:less_than, Var1, Var2), cut,
            _nrf(:mul_through, Terms1, poly(Var2, Terms2), Terms)))
    _py_add!(_nrf(:poly_mul, P, poly(Var, Terms2), poly(Var, Terms)),
        conj(cut, _nrf(:mul_through, Terms2, P, Terms)))
    _py_add!(_nrf(:poly_mul, poly(Var, Terms1), C, poly(Var, Terms)),
        conj(cut, _nrf(:mul_through, Terms1, C, Terms)))
    _py_add!(_nrf(:poly_mul, C1, C2, C), _nrf(:is, C, _nrf(:*, C1, C2)))
    _py_add!(_nrf(:term_mul, _nrnil(), _v(), _nrnil()), cut)
    _py_add!(_nrf(:term_mul, _v(), _nrnil(), _nrnil()), cut)
    _py_add!(_nrf(:term_mul, _nrcons(Term, Terms1), Terms2, Terms),
        conj(_nrf(:single_term_mul, Terms2, Term, PartA),
            _nrf(:term_mul, Terms1, Terms2, PartB),
            _nrf(:term_add, PartA, PartB, Terms)))
    _py_add!(_nrf(:single_term_mul, _nrnil(), _v(), _nrnil()), cut)
    _py_add!(
        _nrf(:single_term_mul, _nrcons(term(E1, C1), Terms1), term(E2, C2),
            _nrcons(term(E, C), Terms)),
        conj(_nrf(:is, E, _nrf(:+, E1, E2)), _nrf(:poly_mul, C1, C2, C),
            _nrf(:single_term_mul, Terms1, term(E2, C2), Terms)))
    _py_add!(_nrf(:mul_through, _nrnil(), _v(), _nrnil()), cut)
    _py_add!(
        _nrf(:mul_through, _nrcons(term(E, Term), Terms), Poly,
            _nrcons(term(E, NewTerm), NewTerms)),
        conj(
            _nrf(:poly_mul, Term, Poly, NewTerm), _nrf(:mul_through, Terms, Poly, NewTerms)
        ))
end
const PY_PROC = lookupProcedure(_a(:poly_10), 0, PY_USER)
function _vm_poly()::Int
    fid = LogicKernel.PL_open_foreign_frame(PY_LD)
    qid = LogicKernel.PL_open_query(
        PY_GD, PY_LD, nothing, LogicKernel.PL_Q_NORMAL, PY_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(PY_GD, PY_LD, qid)
    LogicKernel.PL_close_query(PY_LD, qid)
    LogicKernel.PL_close_foreign_frame(PY_LD, fid)
    return rc
end
@assert _vm_poly() == LogicKernel.PL_S_TRUE
let c = lookupProcedure(_a(:poly_exp), 3, PY_USER).definition.impl_clauses.first_clause
    @assert LogicKernel.A_ADD_FC in c.next.next.clause.codes     # `M is N-1`, inline (V8)
end
const POLY_PL = read(joinpath(@__DIR__, "..", "bench", "programs", "poly_10.pl"), String)
@assert count("top:-poly_10.", POLY_PL) == 1                # the line left out, exactly once
const POLY_PROLOG = replace(POLY_PL, "top:-poly_10." => "")

# built-in calls (V5a2): a 1000-element list walk calling `compare/3` from a clause body — `I_CALL`
# into a foreign predicate and back, per element; swipl runs the same clauses (`BW_PROLOG`), the list
# a literal on both sides
let (X, T) = (_v(), _v())
    _nr_add!(_nrf(:bw, _nrnil()), nothing)
    _nr_add!(
        _nrf(:bw, _nrcons(X, T)),
        _nrf(Symbol(","), _nrf(:compare, _v(), X, X), _nrf(:bw, T))
    )
    _nr_add!(
        _a(:bwtop),
        _nrf(:bw, foldr(_nrcons, [gnd_term(BT, i) for i in 1:1000]; init=_nrnil()))
    )
end
const BW_PROC = lookupProcedure(_a(:bwtop), 0, NR_USER)
function _vm_bw()::Int
    fid = LogicKernel.PL_open_foreign_frame(NR_LD)
    qid = LogicKernel.PL_open_query(
        NR_GD, NR_LD, nothing, LogicKernel.PL_Q_NORMAL, BW_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(NR_GD, NR_LD, qid)
    LogicKernel.PL_close_query(NR_LD, qid)
    LogicKernel.PL_close_foreign_frame(NR_LD, fid)
    return rc
end
@assert _vm_bw() == LogicKernel.PL_S_TRUE
const BW_PROLOG =
    "bw([]).\nbw([X|T]) :- compare(_, X, X), bw(T).\nbwtop :- bw([" * join(1:1000, ",") *
    "]).\n"

# unification in a body (V9a): a 1000-element list walk whose clause unifies and compares inline per
# element — B_UNIFY_FIRSTVAR, B_UNIFY_VAR … B_UNIFY_EXIT, B_EQ_VV, B_UNIFY_FV, B_NEQ_VC; none is
# against a head argument, so swipl moves none into the head and runs the same code (`BU_PROLOG`)
let (X, T, Y, Z, W) = (_v(), _v(), _v(), _v(), _v())
    _nr_add!(_nrf(:bu, _nrnil()), nothing)
    _nr_add!(
        _nrf(:bu, _nrcons(X, T)),
        foldr(
            (g, r) -> _nrf(Symbol(","), g, r),
            [
                _nrf(:(=), Y, _nrf(:f, X)), _nrf(:(=), Y, _nrf(:f, Z)), _nrf(:(==), Z, X),
                _nrf(:(=), W, Z), _nrf(Symbol("\\=="), W, _a(:a)), _nrf(:bu, T)
            ]
        )
    )
    _nr_add!(
        _a(:butop),
        _nrf(:bu, foldr(_nrcons, [gnd_term(BT, i) for i in 1:1000]; init=_nrnil()))
    )
end
const BU_PROC = lookupProcedure(_a(:butop), 0, NR_USER)
function _vm_bu()::Int
    fid = LogicKernel.PL_open_foreign_frame(NR_LD)
    qid = LogicKernel.PL_open_query(
        NR_GD, NR_LD, nothing, LogicKernel.PL_Q_NORMAL, BU_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(NR_GD, NR_LD, qid)
    LogicKernel.PL_close_query(NR_LD, qid)
    LogicKernel.PL_close_foreign_frame(NR_LD, fid)
    return rc
end
@assert _vm_bu() == LogicKernel.PL_S_TRUE
let c =
        lookupProcedure(_a(:bu), 1, NR_USER).definition.impl_clauses.first_clause.next.clause
    @assert LogicKernel.B_UNIFY_FIRSTVAR in c.codes && LogicKernel.B_NEQ_VC in c.codes
end
const BU_PROLOG =
    "bu([]).\nbu([X|T]) :- Y = f(X), Y = f(Z), Z == X, W = Z, W \\== a, bu(T).\n" *
    "butop :- bu([" * join(1:1000, ",") * "]).\n"

# allow-docstring-interp: not a docstring — this Prolog source interpolates DEPTH on purpose
const PROLOG_FIXTURES =
    """
tree(0, Leaf, L) :- !, copy_term(Leaf, L).
tree(N, Leaf, f(A, B)) :- N1 is N-1, tree(N1, Leaf, A), tree(N1, Leaf, B).
fixtures(G1, G2, V1, V2) :-
    tree($DEPTH, a, G1), tree($DEPTH, a, G2), tree($DEPTH, _, V1), tree($DEPTH, _, V2),
    forall(between(1, 1000, I), assertz(cp(I, a))).
:- dynamic cp/2.
""" * read(joinpath(@__DIR__, "..", "bench", "programs", "nreverse.pl"), String) *
    BW_PROLOG * BU_PROLOG *
    DERIVE_PROLOG * QSORT_PROLOG * POLY_PROLOG

# ── cases: (name, Julia thunk, the swipl goal over G1 G2 V1 V2) ─────────────────────────────────
const CASES = [
    ("compare ground", () -> compareStandard(G1, G2), "compare(_, G1, G2)"),
    ("=@= ground", () -> is_variant_ptr(G1, G2), "G1 =@= G2"),
    ("=@= vars", () -> is_variant_ptr(V1, V2), "V1 =@= V2"),
    ("term_hash ground", () -> pl_term_hash(G1), "term_hash(G1, _)"),
    ("variant_sha1 ground", () -> pl_variant_sha1(G1), "variant_sha1(G1, _)"),
    ("variant_sha1 vars", () -> pl_variant_sha1(V1), "variant_sha1(V1, _)"),
    ("variant_hash ground", () -> pl_variant_hash(G1), "variant_hash(G1, _)"),
    ("variant_hash vars", () -> pl_variant_hash(V1), "variant_hash(V1, _)"),
    ("= ground", () -> _attempt(pl_unify!, G1, G2), "G1 = G2"),
    ("= bind vars", () -> _attempt(pl_unify!, V1, G1), "V1 = G1"),
    ("= var-var", () -> _attempt(pl_unify!, V1, V2), "V1 = V2"),
    (
        "occurs-check bind vars",
        () -> _attempt(pl_unify_with_occurs_check!, V1, G1),
        "unify_with_occurs_check(V1, G1)"
    ),
    (
        "clause/2 1000 facts",
        () -> pl_clause!(CP_GD, LD, CP_DEF, CP_GOAL, _ -> true),
        "forall(clause(cp(_, _), true), true)"
    ),
    # Julia only (no swipl goal): compiling a fact, and a rule clause's head with its analysis
    ("compileClause fact", () -> _cp_compile(CC_FACT), ""),
    (
        "rule head + analysis",
        () -> LogicKernel._compile_clause_head!(
            CP_GD, LogicKernel.compileInfo{BT}(3, CP_USER, APP_PROC), APP_HEAD, APP_BODY
        ),
        ""
    ),
    (
        "compileClause rule",
        () -> compileClause(CP_GD, CP_LD, APP_HEAD, APP_BODY, APP_PROC, CP_USER),
        ""
    ),
    # the VM's run loop (V4a): every answer, and one answer through the index
    ("query cp(X,Y) 1000", () -> _vm_query(Q_LD, Q_ALL), "forall(cp(_, _), true)"),
    ("query cp(500,Y)", () -> _vm_query(Q_LD, Q_ONE), "forall(cp(500, _), true)"),
    # rules (V4b): nreverse of 30, 496 calls with last-call reuse, open to close
    ("nreverse", _vm_nreverse, "nreverse"),
    ("compare/3 ×1000, body", _vm_bw, "bwtop"),
    # unification and comparison inline in a body (V9a), per element of a 1000-element list
    ("unify inline ×1000, body", _vm_bu, "butop"),
    # derive (V6c2): the first program with cuts, type tests and is/2 from a body
    ("derive", _vm_derive, "ops8, log10, divide10"),
    # qsort (V7): 50 numbers, `=</2` and a cut per partition step
    ("qsort", _vm_qsort, "qsort"),
    # poly_10 (V8): (1+x+y+z)^10, A_ADD_FC and the shifts in poly_exp
    ("poly_10", _vm_poly, "poly_10"),
    # Julia only (no swipl goal): the local stack's primitives
    ("1000 frames + choice points", () -> _stack_frames(ST_LD, 1000), ""),
    # Julia only (no swipl goal): what the `finally` around each enumeration step costs
    ("attempt f(X)=f(a)", () -> _attempt(pl_unify!, SMALL_A, SMALL_B), ""),
    ("attempt + finally", () -> _attempt_finally(pl_unify!, SMALL_A, SMALL_B), "")
]

# A run's length: long enough that one collection inside it is a small share of it (0.1 s was too
# short — measured 2026-10-05, a single collection doubled a run).
const RUN_S = 0.5

# ── swipl: three timed runs of each goal, after calibrating the loop to ≥ RUN_S ─────────────────
function swipl_times(cases)::Dict{String, Tuple{NTuple{3, Float64}, Int}}
    out = Dict{String, Tuple{NTuple{3, Float64}, Int}}()
    Sys.which("swipl") === nothing && return out
    prog = IOBuffer()
    print(prog, PROLOG_FIXTURES)
    print(
        prog,
        """
        run_s(Goal, N, T) :-
            get_time(T0), forall(between(1, N, _), Goal), get_time(T1), T is T1 - T0.
        time_s(Goal, N, T) :-
            garbage_collect, run_s(Goal, N, T).
        calib(Goal, N0, N) :-
            run_s(Goal, N0, T), ( T >= $RUN_S -> N = N0 ; N1 is N0 * 2, calib(Goal, N1, N) ).
        bench(Name, Goal) :-
            calib(Goal, 1, N),
            time_s(Goal, N, T1), time_s(Goal, N, T2), time_s(Goal, N, T3),
            U1 is T1 / N * 1.0e6, U2 is T2 / N * 1.0e6, U3 is T3 / N * 1.0e6,
            format("~w\\t~6f\\t~6f\\t~6f\\t~d~n", [Name, U1, U2, U3, N]).
        main :-
            fixtures(G1, G2, V1, V2),
        """
    )
    timed = [(name, goal) for (name, _, goal) in cases if !isempty(goal)]
    isempty(timed) && return out
    for (i, (name, goal)) in enumerate(timed)
        sep = i == length(timed) ? ".\n" : ",\n"
        print(prog, "    bench('", name, "', (", goal, "))", sep)
    end
    print(prog, ":- initialization((main, halt)).\n")
    text = mktempdir() do d
        f = joinpath(d, "bench.pl")
        write(f, String(take!(prog)))
        read(`swipl -q $f`, String)
    end
    for l in eachline(IOBuffer(text))
        p = split(l, '\t')
        length(p) == 5 || error("tools/bench.jl: unexpected swipl output: $l")
        out[p[1]] = (
            (parse(Float64, p[2]), parse(Float64, p[3]), parse(Float64, p[4])),
            parse(Int, p[5])
        )
    end
    return out
end

# ── the run loop in a FRESH process: first-call latency, compile time, dispatch (V4a) ───────────
# One very large function (decision 1): what a fresh process pays at its first query — after the
# precompile workload compiled it for DefaultTerm — and what compiling it costs for a term type the
# workload did not cover. Its dispatch is reported as the native code's jump tables.
const RUN_LOOP_PROBE = raw"""
using LogicKernel, InteractiveUtils
const LK = LogicKernel
const T = DefaultTerm
t_load = @elapsed begin
    gd = LK.PL_global_data{T}(); ld = LK.PL_local_data{T}()
    user = LK.MODULE_user(gd)
    proc = LK.lookupProcedure(sym_term(T, :p), 1, user)
    LK.setDynamicDefinition!(proc.definition, true)
    LK.assertDefinition!(gd, proc.definition,
        LK.compileClause(gd, ld, mk_expr(T, T[sym_term(T, :p), sym_term(T, :a)]), nothing, proc, user), LK.CL_END)
end
t_first = @elapsed begin
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, 1)
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, proc, args)
    LK.PL_next_solution(gd, ld, qid)
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end
const U = Term{Vector{Float64}}                 # a term type the workload did not compile
t_compile = @elapsed precompile(
    LK.PL_next_solution_guarded, (LK.PL_global_data{U}, LK.PL_local_data{U}, Int, Bool)
)
io = IOBuffer()
code_native(io, LK.PL_next_solution_guarded, (LK.PL_global_data{T}, LK.PL_local_data{T}, Int, Bool);
    debuginfo=:none, syntax=:intel)
jt = length(collect(eachmatch(r"^\s*jmp\s+qword ptr \[[^\]]+\]\s*$"m, String(take!(io)))))
println(t_load, " ", t_first, " ", t_compile, " ", jt)
"""

function run_loop_report()::Nothing
    root = dirname(@__DIR__)
    out = try
        read(`$(Base.julia_cmd()) --project=$root --startup-file=no -e $RUN_LOOP_PROBE`, String)
    catch e
        println("\nrun loop (fresh process): probe failed — ", sprint(showerror, e))
        return nothing
    end
    t_load, t_first, t_compile, jt = split(strip(out))
    @printf(
        "\nrun loop (fresh process): first query %.1f ms (after a first assert %.1f ms); compiling it for a new term type %.1f s; dispatch: %s jump tables in its native code\n",
        1e3 * parse(Float64, t_first), 1e3 * parse(Float64, t_load),
        parse(Float64, t_compile), jt
    )
    return nothing
end

# ── the quiet rule (user, 2026-10-05): ratios only on a machine MEASURED quiet ─────────────────────
# The load average misleads on this machine — it counts short-lived processes (`top` showed 97% idle
# at a load of 3) — so it is printed as context only. Quiet is measured: the CPUs' idle share over a
# few seconds (/proc/stat) and no other julia or swipl process using CPU in that window
# (/proc/<pid>/stat), the bench's own process excepted.
"All CPUs' total and idle jiffies (/proc/stat)."
function _cpu_jiffies()::Tuple{Int, Int}
    f = split(readline("/proc/stat"))                   # cpu user nice system idle iowait …
    v = parse.(Int, f[2:end])
    return (sum(v), v[4] + v[5])
end
"A process's CPU ticks (user + system) from its /proc/<pid>/stat text."
function _stat_ticks(st::String)::Int
    f = split(st[(findlast(')', st) + 2):end])          # the fields after "(comm)": state is 1
    return parse(Int, f[12]) + parse(Int, f[13])        # utime, stime (fields 14, 15)
end
"The CPU ticks of every OTHER process, with its command name."
function _other_ticks()::Dict{Int, Tuple{String, Int}}
    out = Dict{Int, Tuple{String, Int}}()
    for d in readdir("/proc")
        pid = tryparse(Int, d)
        (pid === nothing || pid == getpid()) && continue
        comm, st = try
            (String(strip(read("/proc/$d/comm", String))), read("/proc/$d/stat", String))
        catch
            continue                                    # it exited meanwhile
        end
        out[pid] = (comm, _stat_ticks(st))
    end
    return out
end
"""
    quiet_check(seconds) -> (; quiet, idle, self, busy, top, load)

Quiet: at least 90% of the CPUs idle over `seconds` — the bench's OWN process not counted as load
(`self`, its share, printed apart: its GC or compiler threads are not the machine's other load) —
and no other julia or swipl process used more than 5% of a CPU in that window (`busy`). `top` names
the busiest other process of any kind, for the record (2026-10-05: a run measured 73% idle with no
busy julia or swipl, and nothing said what the load was).
"""
function quiet_check(seconds::Float64=3.0)
    t0, i0 = _cpu_jiffies()
    s0 = _stat_ticks(read("/proc/self/stat", String))
    b0 = _other_ticks()
    sleep(seconds)
    t1, i1 = _cpu_jiffies()
    s1 = _stat_ticks(read("/proc/self/stat", String))
    b1 = _other_ticks()
    tot = max(1, t1 - t0)
    idle = (i1 - i0 + (s1 - s0)) / tot
    d = Dict(pid => (c, t - (haskey(b0, pid) ? b0[pid][2] : t)) for (pid, (c, t)) in b1)
    lim = 0.05 * seconds * 100                          # 5% of one CPU, in USER_HZ ticks
    busy = sort!([
        pid for (pid, (c, dt)) in d if
        dt > lim && (startswith(c, "julia") || startswith(c, "swipl"))
    ])
    k = isempty(d) ? 0 : argmax(p -> d[p][2], collect(keys(d)))
    top = if k == 0
        "none"
    else
        string(
            d[k][1],
            " (pid ",
            k,
            ", ",
            round(Int, 100 * d[k][2] / (seconds * 100)),
            "% of a CPU)"
        )
    end
    return (; quiet=idle >= 0.90 && isempty(busy), idle, self=(s1 - s0) / tot, busy, top,
        load=Sys.loadavg()[1])
end

# ── Julia: THE SAME STATISTIC AS swipl_times (user, 2026-10-05) ──────────────────────────────────
# N calls per run, N doubled from 1 until a run takes at least RUN_S of wall time (calibration runs
# collect nothing first); then three runs, each after a full collection, every collection DURING a
# run counted; wall time per call; the minimum of the three is the number.
function _wall_per_call(f, n::Int, collect::Bool)::Float64
    collect && GC.gc()
    t0 = time_ns()
    for _ in 1:n
        f()
    end
    return (time_ns() - t0) / n / 1e3                   # µs per call
end
function julia_times(f)
    f()
    n = 1
    while _wall_per_call(f, n, false) * n < RUN_S * 1e6   # µs
        n *= 2
    end
    ts = ntuple(_ -> _wall_per_call(f, n, true), 3)
    return ts, n, (@allocations f()), (@allocated f())
end

function main(args)
    filt = filter(a -> !startswith(a, "--"), args)
    cases = [c for c in CASES if isempty(filt) || any(f -> occursin(f, c[1]), filt)]
    isempty(cases) && error("tools/bench.jl: no case matches $(filt)")
    k = findfirst(a -> startswith(a, "--profile="), args)
    prof = k === nothing ? "" : String(split(args[k], '='; limit=2)[2])
    sw = swipl_times(cases)
    swv = isempty(sw) ? "no swipl on PATH" : strip(read(`swipl --version`, String))
    println("LogicKernel bench — julia $(VERSION), pid $(getpid()), $swv")
    # the machine's idle CPU BEFORE and AFTER the Julia runs; a ratio is quoted only if both are quiet
    qc = quiet_check()
    rows = Tuple{String, NTuple{3, Float64}, Int, Int, Int}[]
    for (name, f, _) in cases
        jt, n, allocs, bytes = julia_times(f)
        push!(rows, (name, jt, n, allocs, bytes))
    end
    qa = quiet_check()
    quiet = qc.quiet && qa.quiet
    for (when, q) in (("before", qc), ("after", qa))
        @printf(
            "machine %s the runs: %.0f%% idle over 3 s (this process %.0f%%), busy julia/swipl: %s, busiest other: %s, load average %.2f (context only)\n",
            when, 100 * q.idle, 100 * q.self, isempty(q.busy) ? "none" : join(q.busy, ","),
            q.top,
            q.load
        )
    end
    println(
        quiet ? "QUIET before and after: ratios quoted" : "NOT QUIET: no ratio is quoted"
    )
    @printf("fixtures: f/2 trees of %d cells\n", CELLS)
    @printf(
        "%-22s %-26s %-26s %8s %16s %8s %9s\n", "case", "LogicKernel µs (3 runs)",
        "swipl µs (3 runs)", "LK/swipl", "calls/run LK sw", "allocs", "bytes"
    )
    ratios = Dict{String, Float64}()
    for (name, jt, n, allocs, bytes) in rows
        sn = get(sw, name, nothing)
        js = join((@sprintf("%.2f", t) for t in jt), " ")
        ss = sn === nothing ? "—" : join((@sprintf("%.2f", t) for t in sn[1]), " ")
        r = sn === nothing || !quiet ? NaN : minimum(jt) / minimum(sn[1])
        ratios[name] = r
        ns = sn === nothing ? "$n —" : "$n $(sn[2])"
        @printf("%-22s %-26s %-26s %8.2f %16s %8d %9d", name, js, ss, r, ns, allocs, bytes)
        spread = maximum(jt) / minimum(jt)
        spread > 1.15 && @printf("   ⚠ LK runs spread %.0f%%", (spread - 1) * 100)
        if sn !== nothing
            sspread = maximum(sn[1]) / minimum(sn[1])
            sspread > 1.15 && @printf("   ⚠ swipl runs spread %.0f%%", (sspread - 1) * 100)
        end
        println()
    end
    "--no-compile" in args || run_loop_report()
    "--no-profile" in args && return nothing
    target = prof
    if isempty(target)
        known = filter(p -> !isnan(p[2]), collect(ratios))
        isempty(known) && return nothing
        target = first(sort(known; by=p -> -p[2]))[1]
    end
    i = findfirst(c -> c[1] == target, cases)
    i === nothing && error("tools/bench.jl: --profile=$target names no case run")
    f = cases[i][2]
    Profile.clear()
    t0 = time()
    Profile.@profile while time() - t0 < 2.0
        f()
    end
    buf = IOBuffer()
    Profile.print(
        IOContext(buf, :displaysize => (1000, 200)); format=:flat, sortedby=:count, C=false
    )
    rows = Tuple{Int, Int, String}[]                # (count, self, line)
    for l in eachline(IOBuffer(take!(buf)))
        p = split(l)
        length(p) >= 4 || continue
        c, o = tryparse(Int, p[1]), tryparse(Int, p[2])
        (c === nothing || o === nothing) && continue
        # LogicKernel's frames, and any frame with SELF time except the idle profiler task's
        (occursin("@LogicKernel", l) || (o > 0 && !occursin("task.jl", l))) || continue
        push!(rows, (c, o, l))
    end
    sort!(rows; by=r -> -r[1])
    println(
        "\n── profile: $target (flat; LogicKernel frames + frames with self time, top 25) ──"
    )
    println(" Count  Self  File:Line Function")
    for (_, _, l) in first(rows, 25)
        println(l)
    end
    return nothing
end

main(ARGS)
