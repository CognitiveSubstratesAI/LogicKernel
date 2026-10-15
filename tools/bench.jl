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
# THREE DIAGNOSTIC REPORTS (user, 2026-10-13), each instead of the timing run; their full output goes
# to .warm/bench/ (ignored by git), a summary to the terminal:
#   julia --project=. tools/bench.jl --descend[=A,B]     # Cthulhu's descent into the hot functions
#                                                        # (`HOT`; default: all): its typed-source
#                                                        # view with ONLY the non-concrete types shown
#                                                        # — where a type is a Union, Any or boxed —
#                                                        # and the calls one can descend into next
#   julia --project=. tools/bench.jl --flame[=CASE]      # a flame graph of CASE (default nreverse):
#                                                        # ProfileView's window when it is installed
#                                                        # and a display exists; the profile is SAVED
#                                                        # either way, with the command that opens it
#   julia --project=. tools/bench.jl --code              # the run loop's `code_llvm` and
#                                                        # `code_native`, and what they contain: dynamic
#                                                        # calls, allocations, boxes, jump tables
# Cthulhu and ProfileView come from the global environment, as Profile does; neither is a dependency.
# In an interactive session `@descend` itself goes further: `using Cthulhu, LogicKernel` and
# `@descend LogicKernel.<function>(…)` — the report here is the same view, printed once per function.
#
# A STANDING STEP for every chunk, beside the JET/Aqua/AllocCheck gates (user, 2026-10-03) — a
# report, not a pass/fail gate: a new primitive gets a case here, with its swipl goal. THE METHOD
# (user, 2026-10-15): ≥ 30 runs per side (`--runs=N`, default 30), swipl and LogicKernel
# INTERLEAVED run by run (`interleaved_times`), the MEDIAN and IQR reported, no other heavy job; the
# raw numbers of every run in tools/bench_results/<UTC time>_<commit>.tsv (user, 2026-10-15: kernel-own
# `tools/`, since `bench/` mirrors swipl-devel), machine, commit and date in its header. Every number beside its
# upstream pair, in µs; profile before attributing a cost.
# Both sides measure ONE statistic (user, 2026-10-05): N calls per run (N doubled until a run takes
# RUN_S), a full collection before each run and every collection during it counted, WALL time per
# call, the minimum of three runs; the machine's idle CPU is recorded before and after the runs.
#
# Profile is not a dependency: it comes from the global environment (see
# tools/repl.jl). swipl comes from PATH; without it the report has no upstream column.
using LogicKernel, Profile, Printf, Serialization, InteractiveUtils, Dates
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
const LD = PL_local_data{BT}(PL_global_data{BT}())                                          # the unify cases' bindings

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
const CP_LD = PL_local_data{BT}(CP_GD)                             # the compiler reads its flags
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
const ST_LD = PL_local_data{BT}(CP_GD)
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
const Q_LD = PL_local_data{BT}(CP_GD)
const Q_ALL, Q_ONE = _v(), gnd_term(BT, 500)
function _vm_query(ld::PL_local_data{BT}, a1::BT)::Int
    fid = LogicKernel.PL_open_foreign_frame(ld)
    args = LogicKernel.PL_new_term_refs(ld, 2)
    LogicKernel.putSlotValue!(ld, args + 1, a1)                                         # term reference args + 0
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
const NR_LD = PL_local_data{BT}(NR_GD)
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
# THE BENCH SWITCH (R1f; user, 2026-10-07): each program runs from its .pl file, loaded by
# `load_file!` — after its clauses are shown to compile to EXACTLY the VM code of the hand-built
# clauses above, predicate by predicate (codes, literal tables, called procedures), so the bench
# series stays comparable across the switch and the loader is checked against something
# independent of the writer. The hand-built databases remain, as that oracle.
"Load the bench program `name`.pl into a database of its own: `(gd, ld)`."
function _load_program(name::String)
    gd = PL_global_data{BT}()
    ld = PL_local_data{BT}(gd)
    st, ball, msgs = LogicKernel.load_file!(
        gd, ld, joinpath(@__DIR__, "..", "bench", "programs", name * ".pl")
    )
    (st === :ok && isempty(msgs)) ||
        error("tools/bench.jl: loading $name.pl: $st $ball $msgs")
    return (gd, ld)
end
"The clauses of `def`, in order."
function _clauses_of(def)
    out = []
    c = def.impl_clauses.first_clause
    while c !== nothing
        push!(out, c.clause)
        c = c.next
    end
    return out
end
"""
How the defined predicates of `loaded`'s `user` module differ from `hand`'s — each must be there
with the same clauses: VM codes, literals (standard order), called procedures (name and arity) —
leaving out `except` (predicates only one side defines by design).
"""
function _vm_code_differences(
    hand::PL_global_data{BT}, loaded::PL_global_data{BT}, except::Vector{String}
)::Vector{String}
    diffs = String[]
    hu, lu = MODULE_user(hand), MODULE_user(loaded)
    pi(p) = sym_text(p.definition.name) * "/" * string(p.definition.arity)
    for (key, lp) in lu.procedures
        LogicKernel.isDefinedProcedure(loaded, lp) || continue
        pi(lp) in except && continue
        hp = get(hu.procedures, key, nothing)
        if hp === nothing || !LogicKernel.isDefinedProcedure(hand, hp)
            push!(diffs, pi(lp) * ": not hand-built")
            continue
        end
        lc, hc = _clauses_of(lp.definition), _clauses_of(hp.definition)
        if length(lc) != length(hc)
            push!(diffs, pi(lp) * ": $(length(lc)) clauses, hand-built $(length(hc))")
            continue
        end
        for (i, (a, b)) in enumerate(zip(lc, hc))
            a.codes == b.codes || push!(diffs, pi(lp) * " clause $i: VM codes differ")
            (
                length(a.literals) == length(b.literals) &&
                all(compareStandard(x, y) == 0 for (x, y) in zip(a.literals, b.literals))
            ) ||
                push!(diffs, pi(lp) * " clause $i: literals differ")
            map(pi, a.procedures) == map(pi, b.procedures) ||
                push!(diffs, pi(lp) * " clause $i: called procedures differ")
            (a.variables, a.prolog_vars, a.flags) ==
            (b.variables, b.prolog_vars, b.flags) ||
                push!(diffs, pi(lp) * " clause $i: frame size or flags differ")
        end
    end
    for (key, hp) in hu.procedures                  # nothing hand-built is missing from the file
        LogicKernel.isDefinedProcedure(hand, hp) || continue
        pi(hp) in except && continue
        lp = get(lu.procedures, key, nothing)
        (lp !== nothing && LogicKernel.isDefinedProcedure(loaded, lp)) ||
            push!(diffs, pi(hp) * ": hand-built only")
    end
    return diffs
end

const NR_LOADED = _load_program("nreverse")
# nreverse.pl's `top/0` is not hand-built (the bench calls `nreverse/0`); bw/bu are bench fixtures
let d = _vm_code_differences(
        NR_GD, NR_LOADED[1], ["top/0", "bw/1", "bwtop/0", "bu/1", "butop/0"]
    )
    isempty(d) ||
        error("tools/bench.jl: nreverse.pl loads to other VM code than hand-built: $d")
end
const NR_PROC = lookupProcedure(_a(:nreverse), 0, MODULE_user(NR_LOADED[1]))
function _vm_nreverse()::Int
    fid = LogicKernel.PL_open_foreign_frame(NR_LOADED[2])
    qid = LogicKernel.PL_open_query(
        NR_LOADED[1], NR_LOADED[2], nothing, LogicKernel.PL_Q_NORMAL, NR_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(NR_LOADED[1], NR_LOADED[2], qid)
    LogicKernel.PL_close_query(NR_LOADED[2], qid)
    LogicKernel.PL_close_foreign_frame(NR_LOADED[2], fid)
    return rc
end
@assert _vm_nreverse() == LogicKernel.PL_S_TRUE

# derive (V6c2): bench/programs/derive.pl's clauses in a database of their own (derive.pl and
# nreverse.pl both define `top/0`), run through the query API as `top` — ops8, log10, divide10;
# swipl runs the same file's three goals (its `top` line left out of the shared program text)
const DR_GD = PL_global_data{BT}()
const DR_LD = PL_local_data{BT}(DR_GD)
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
const DR_LOADED = _load_program("derive")
let d = _vm_code_differences(DR_GD, DR_LOADED[1], String[])
    isempty(d) ||
        error("tools/bench.jl: derive.pl loads to other VM code than hand-built: $d")
end
const DR_PROC = lookupProcedure(_a(:top), 0, MODULE_user(DR_LOADED[1]))
function _vm_derive()::Int
    fid = LogicKernel.PL_open_foreign_frame(DR_LOADED[2])
    qid = LogicKernel.PL_open_query(
        DR_LOADED[1], DR_LOADED[2], nothing, LogicKernel.PL_Q_NORMAL, DR_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(DR_LOADED[1], DR_LOADED[2], qid)
    LogicKernel.PL_close_query(DR_LOADED[2], qid)
    LogicKernel.PL_close_foreign_frame(DR_LOADED[2], fid)
    return rc
end
@assert _vm_derive() == LogicKernel.PL_S_TRUE
const DERIVE_PL = read(joinpath(@__DIR__, "..", "bench", "programs", "derive.pl"), String)
@assert count("top:-ops8,log10,divide10.", DERIVE_PL) == 1      # the line left out, exactly once
const DERIVE_PROLOG = replace(DERIVE_PL, "top:-ops8,log10,divide10." => "")

# qsort (V7): bench/programs/qsort.pl's clauses in a database of their own (its `top/0` too), run
# as `qsort`; swipl runs the same file's `qsort`
const QS_GD = PL_global_data{BT}()
const QS_LD = PL_local_data{BT}(QS_GD)
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
const QS_LOADED = _load_program("qsort")
let d = _vm_code_differences(QS_GD, QS_LOADED[1], String["top/0"])
    isempty(d) ||
        error("tools/bench.jl: qsort.pl loads to other VM code than hand-built: $d")
end
const QS_PROC = lookupProcedure(_a(:qsort), 0, MODULE_user(QS_LOADED[1]))
function _vm_qsort()::Int
    fid = LogicKernel.PL_open_foreign_frame(QS_LOADED[2])
    qid = LogicKernel.PL_open_query(
        QS_LOADED[1], QS_LOADED[2], nothing, LogicKernel.PL_Q_NORMAL, QS_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(QS_LOADED[1], QS_LOADED[2], qid)
    LogicKernel.PL_close_query(QS_LOADED[2], qid)
    LogicKernel.PL_close_foreign_frame(QS_LOADED[2], fid)
    return rc
end
@assert _vm_qsort() == LogicKernel.PL_S_TRUE
const QSORT_PL = read(joinpath(@__DIR__, "..", "bench", "programs", "qsort.pl"), String)
@assert count("top:-qsort.", QSORT_PL) == 1                 # the line left out, exactly once
const QSORT_PROLOG = replace(QSORT_PL, "top:-qsort." => "")

# poly_10 (V8): bench/programs/poly_10.pl's clauses in a database of their own (its `top/0` too),
# run as `poly_10`; swipl runs the same file's `poly_10` — A_ADD_FC (`M is N-1`), `>>`, `<<`
const PY_GD = PL_global_data{BT}()
const PY_LD = PL_local_data{BT}(PY_GD)
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
const PY_LOADED = _load_program("poly_10")
let d = _vm_code_differences(PY_GD, PY_LOADED[1], String["top/0"])
    isempty(d) ||
        error("tools/bench.jl: poly_10.pl loads to other VM code than hand-built: $d")
end
const PY_PROC = lookupProcedure(_a(:poly_10), 0, MODULE_user(PY_LOADED[1]))
function _vm_poly()::Int
    fid = LogicKernel.PL_open_foreign_frame(PY_LOADED[2])
    qid = LogicKernel.PL_open_query(
        PY_LOADED[1], PY_LOADED[2], nothing, LogicKernel.PL_Q_NORMAL, PY_PROC, 0
    )
    rc = LogicKernel.PL_next_solution(PY_LOADED[1], PY_LOADED[2], qid)
    LogicKernel.PL_close_query(PY_LOADED[2], qid)
    LogicKernel.PL_close_foreign_frame(PY_LOADED[2], fid)
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

# the bags (V9g-b): findall/3 over 1000 facts; the same list then sorted (the facts are in
# descending order, so the merge sort's every run is a swapped pair); bagof/3 over 1000 facts with
# one free variable of three values — the keyed findall/3, keysort/2 and the bags, taken to the
# third; swipl runs the same clauses (`BAG_PROLOG`)
let (X, K, L) = (_v(), _v(), _v())
    for i in 1000:-1:1
        _nr_add!(_nrf(:bn, gnd_term(BT, i)), nothing)
        _nr_add!(_nrf(:bk, gnd_term(BT, i), _a((:a, :b, :c)[i % 3 + 1])), nothing)
    end
    _nr_add!(_a(:fatop), _nrf(:findall, X, _nrf(:bn, X), _v()))
    _nr_add!(
        _a(:fstop),
        _nrf(Symbol(","), _nrf(:findall, X, _nrf(:bn, X), L), _nrf(:sort, L, _v()))
    )
    _nr_add!(
        _a(:botop),
        _nrf(
            Symbol(","), _nrf(:bagof, X, _nrf(:bk, X, K), _v()), _nrf(:(==), K, _a(:c))
        )
    )
end
const FA_PROC = lookupProcedure(_a(:fatop), 0, NR_USER)
const FS_PROC = lookupProcedure(_a(:fstop), 0, NR_USER)
const BO_PROC = lookupProcedure(_a(:botop), 0, NR_USER)
function _vm_bag(proc)::Int
    fid = LogicKernel.PL_open_foreign_frame(NR_LD)
    qid = LogicKernel.PL_open_query(NR_GD, NR_LD, nothing, LogicKernel.PL_Q_NORMAL, proc, 0)
    rc = LogicKernel.PL_next_solution(NR_GD, NR_LD, qid)
    LogicKernel.PL_close_query(NR_LD, qid)
    LogicKernel.PL_close_foreign_frame(NR_LD, fid)
    return rc
end
_vm_findall()::Int = _vm_bag(FA_PROC)
_vm_fsort()::Int = _vm_bag(FS_PROC)
_vm_bagof()::Int = _vm_bag(BO_PROC)
@assert _vm_findall() == LogicKernel.PL_S_TRUE
@assert _vm_fsort() == LogicKernel.PL_S_TRUE
@assert _vm_bagof() == LogicKernel.PL_S_TRUE
const BAG_PROLOG =
    join("bn($i).\n" for i in 1000:-1:1) *
    join("bk($i, $(("a", "b", "c")[i % 3 + 1])).\n" for i in 1000:-1:1) *
    "fatop :- findall(X, bn(X), _).\nfstop :- findall(X, bn(X), L), sort(L, _).\n" *
    "botop :- bagof(X, bk(X, K), _), K == c.\n"

# the reader (R1d): term_to_atom/2 reads one clause's text — raw_read, the tokens, operators of
# several priorities and kinds, a list with a tail, a string, brackets; swipl runs the same goal on
# the same text (no `'` or `\` in it: it is quoted as an atom in the swipl goal)
const RD_TEXT =
    "nrev([H|T], R) :- nrev(T, RT), app(RT, [H], R), X is 1 + 2 * 3 - f(a, \"s\", " *
    "[1, 2, 3 | Y]), Z = W, (A -> B ; C), - - 1 =< 2, {p, q}."
const RD_PROC = LogicKernel.isCurrentProcedure(
    sym_key(_a(:term_to_atom)), 2, LogicKernel.MODULE_system(NR_GD)
)
function _vm_read()::Int
    fid = LogicKernel.PL_open_foreign_frame(NR_LD)
    a = LogicKernel.PL_new_term_refs(NR_LD, 2)
    LogicKernel.putSlotValue!(NR_LD, a + 2, _a(Symbol(RD_TEXT)))
    qid = LogicKernel.PL_open_query(
        NR_GD, NR_LD, nothing, LogicKernel.PL_Q_NORMAL, RD_PROC, a
    )
    rc = LogicKernel.PL_next_solution(NR_GD, NR_LD, qid)
    LogicKernel.PL_close_query(NR_LD, qid)
    LogicKernel.PL_close_foreign_frame(NR_LD, fid)
    return rc
end
@assert _vm_read() == LogicKernel.PL_S_TRUE

# the writer (R1e): term_to_atom/2 writes that clause back as text — writeTerm2's state machine,
# operators, the token layer, quoting. The term is read once; swipl's goal takes it from a fact
# (`wr_term/1`), whose copy is in its timing (a few dozen cells)
const WR_TERM = let
    fid = LogicKernel.PL_open_foreign_frame(NR_LD)
    a = LogicKernel.PL_new_term_refs(NR_LD, 2)
    LogicKernel.putSlotValue!(NR_LD, a + 2, _a(Symbol(RD_TEXT)))
    qid = LogicKernel.PL_open_query(
        NR_GD, NR_LD, nothing, LogicKernel.PL_Q_NORMAL, RD_PROC, a
    )
    @assert LogicKernel.PL_next_solution(NR_GD, NR_LD, qid) == LogicKernel.PL_S_TRUE
    t = LogicKernel.resolve_term(NR_LD, LogicKernel.slotValue(NR_LD, a + 1))
    LogicKernel.PL_close_query(NR_LD, qid)
    LogicKernel.PL_close_foreign_frame(NR_LD, fid)
    t
end
const WR_PROLOG = "wr_term((" * chop(RD_TEXT) * ")).\n"
function _vm_write()::Int
    fid = LogicKernel.PL_open_foreign_frame(NR_LD)
    a = LogicKernel.PL_new_term_refs(NR_LD, 2)
    LogicKernel.putSlotValue!(NR_LD, a + 1, WR_TERM)
    qid = LogicKernel.PL_open_query(
        NR_GD, NR_LD, nothing, LogicKernel.PL_Q_NORMAL, RD_PROC, a
    )
    rc = LogicKernel.PL_next_solution(NR_GD, NR_LD, qid)
    LogicKernel.PL_close_query(NR_LD, qid)
    LogicKernel.PL_close_foreign_frame(NR_LD, fid)
    return rc
end
@assert _vm_write() == LogicKernel.PL_S_TRUE

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
    BW_PROLOG * BU_PROLOG * BAG_PROLOG *
    DERIVE_PROLOG * QSORT_PROLOG * POLY_PROLOG * WR_PROLOG

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
    # the bags (V9g-b): 1000 answers recorded and put back; the list sorted; three bags of bagof/3
    ("findall/3 ×1000", _vm_findall, "fatop"),
    ("findall/3 + sort/2 ×1000", _vm_fsort, "fstop"),
    ("bagof/3 ×1000, 3 bags", _vm_bagof, "botop"),
    # derive (V6c2): the first program with cuts, type tests and is/2 from a body
    ("derive", _vm_derive, "ops8, log10, divide10"),
    # qsort (V7): 50 numbers, `=</2` and a cut per partition step
    ("qsort", _vm_qsort, "qsort"),
    # poly_10 (V8): (1+x+y+z)^10, A_ADD_FC and the shifts in poly_exp
    ("poly_10", _vm_poly, "poly_10"),
    # the reader (R1d): one clause's text through term_to_atom/2
    ("term_to_atom clause", _vm_read, "term_to_atom(_, '" * RD_TEXT * "')"),
    # the writer (R1e): the same clause's term written back by term_to_atom/2
    ("term_to_atom write clause", _vm_write, "wr_term(T), term_to_atom(T, _)"),
    # Julia only (no swipl goal): the local stack's primitives
    ("1000 frames + choice points", () -> _stack_frames(ST_LD, 1000), ""),
    # Julia only (no swipl goal): what the `finally` around each enumeration step costs
    ("attempt f(X)=f(a)", () -> _attempt(pl_unify!, SMALL_A, SMALL_B), ""),
    ("attempt + finally", () -> _attempt_finally(pl_unify!, SMALL_A, SMALL_B), "")
]

# A run's length: long enough that one collection inside it is a small share of it (0.1 s was too
# short — measured 2026-10-05, a single collection doubled a run).
const RUN_S = 0.5

# ── the run loop in a FRESH process: first-call latency, compile time, dispatch (V4a) ───────────
# One very large function (decision 1): what a fresh process pays at its first query — after the
# precompile workload compiled it for DefaultTerm — and what compiling it costs for a term type the
# workload did not cover. Its dispatch is reported as the native code's jump tables.
const RUN_LOOP_PROBE = raw"""
using LogicKernel, InteractiveUtils
const LK = LogicKernel
const T = DefaultTerm
t_load = @elapsed begin
    gd = LK.PL_global_data{T}(); ld = LK.PL_local_data{T}(gd)
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

# ── one timed run: THE SAME STATISTIC AS swipl's `time_s` (user, 2026-10-05) ──────────────────────
# N calls per run, N doubled from 1 until a run takes at least RUN_S of wall time (calibration runs
# collect nothing first); each timed run after a full collection, every collection DURING it
# counted; wall time per call.
function _wall_per_call(f, n::Int, collect::Bool)::Float64
    collect && GC.gc()
    t0 = time_ns()
    for _ in 1:n
        f()
    end
    return (time_ns() - t0) / n / 1e3                   # µs per call
end
# ── THE METHOD SINCE 2026-10-15 (user): ≥ 30 runs per benchmark, swipl and LogicKernel INTERLEAVED
# run by run, median and IQR, no other heavy job; the raw numbers in tools/bench_results/. MEASURED the
# night before: swipl's own nreverse moved 19.7 ↔ 30.9 µs between two sessions, because the old
# method ran all of one side, then all of the other, three runs each — a ratio of two moments.
# Here swipl is a SERVER read over a pipe: each LogicKernel run is followed at once by one swipl run
# of the same case, both after a full collection, both counting the collections during the run.
"Runs per benchmark (each side), unless `--runs=N` says otherwise."
const RUNS_DEFAULT = 30

"swipl as a server for `cases` (numbered by position): `calib(I)` → calls per run, `run(I, N)` → µs per call."
function swipl_server(cases)::Union{Nothing, Base.Process}
    Sys.which("swipl") === nothing && return nothing
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
        serve :-
            read_term(user_input, T, []),
            (   T == end_of_file -> true
            ;   T = calib(I) -> case(I, G), calib(G, 1, N), format("~d~n", [N]), flush_output, serve
            ;   T = run(I, N) -> case(I, G), time_s(G, N, S), U is S / N * 1.0e6,
                format("~6f~n", [U]), flush_output, serve
            ).
        """
    )
    for (i, (_, _, goal)) in enumerate(cases)
        isempty(goal) && continue
        print(prog, "case($i, Goal) :- fixtures(G1, G2, V1, V2), Goal = (", goal, ").\n")
    end
    print(prog, ":- initialization((serve, halt)).\n")
    d = mktempdir()
    f = joinpath(d, "bench_server.pl")
    write(f, String(take!(prog)))
    return open(pipeline(`swipl -q $f`; stderr=devnull), "r+")
end

"Ask the swipl server `q` and read its one-line answer."
function _ask(p::Base.Process, q::AbstractString)::String
    println(p, q)
    flush(p)
    return readline(p)
end

"Median and interquartile range of `xs` (linear interpolation, as `Statistics.quantile`)."
function _median_iqr(xs::Vector{Float64})::Tuple{Float64, Float64}
    v = sort(xs)
    q(t) = (h=(length(v) - 1) * t + 1; lo=floor(Int, h); hi=min(lo + 1, length(v));
        v[lo] + (h - lo) * (v[hi] - v[lo]))
    return q(0.5), q(0.75) - q(0.25)
end

"""
Interleaved timings: per case, both sides calibrated, then `runs` pairs — one LogicKernel run, one
swipl run — each a full collection then N calls. Returns per case (lk runs, swipl runs, N lk, N sw).
"""
function interleaved_times(cases, runs::Int, p::Union{Nothing, Base.Process})
    out = Dict{String, Tuple{Vector{Float64}, Vector{Float64}, Int, Int}}()
    for (i, (name, f, goal)) in enumerate(cases)
        f()
        n = 1
        while _wall_per_call(f, n, false) * n < RUN_S * 1e6
            n *= 2
        end
        nsw = (p === nothing || isempty(goal)) ? 0 : parse(Int, _ask(p, "calib($i)."))
        lk, sw = Float64[], Float64[]
        for _ in 1:runs
            push!(lk, _wall_per_call(f, n, true))
            nsw > 0 && push!(sw, parse(Float64, _ask(p, "run($i, $nsw).")))
        end
        out[name] = (lk, sw, n, nsw)
    end
    return out
end

# ── the diagnostic reports: Cthulhu's descent, a flame graph, the run loop's code ────────────────
"Where the diagnostic reports write their full output."
const BENCH_OUT = joinpath(dirname(@__DIR__), ".warm", "bench")

"The hot functions `--descend` looks into, on the bench's term type: name => (function, argument types)."
const HOT = [
    "run_loop" => (
        LogicKernel.PL_next_solution_guarded,
        Tuple{PL_global_data{BT}, PL_local_data{BT}, Int, Bool}
    ),
    "deRef" => (LogicKernel.deRef, Tuple{PL_local_data{BT}, BT}),
    "do_unify" => (LogicKernel.do_unify, Tuple{PL_local_data{BT}, BT, BT}),
    "compare" => (compareStandard, Tuple{PL_local_data{BT}, BT, BT, Bool}),
    "newChoice" =>
        (LogicKernel.newChoice, Tuple{PL_local_data{BT}, LogicKernel.choice_type, Int}),
    "discardFrame" => (LogicKernel.discardFrame, Tuple{PL_local_data{BT}, Int})
]

_plain(s::AbstractString)::String = replace(s, r"\e\[[0-9;?]*[A-Za-z]" => "")

"`text` before and after the first `sep` (the whole text and \"\" when it does not occur)."
function _split2(text::AbstractString, sep::AbstractString)::Tuple{String, String}
    r = findfirst(sep, text)
    r === nothing && return (String(text), "")
    return (
        String(text[1:prevind(text, first(r))]), String(text[nextind(text, last(r)):end])
    )
end

"""
Cthulhu's view of `f(tt)`, as text: `Cthulhu.descend` on a terminal whose only key press is `q` — the
first screen (the typed source, warnings on, type-stable statements hidden, and the list of calls),
printed once.
"""
function _descend_text(cth::Module, f, tt; optimize::Bool=false)::String
    repl = Base.require(
        Base.PkgId(Base.UUID("3fa0cd96-eef1-5676-8a61-b3b8758bbffb"), "REPL")
    )
    inp = Pipe()
    Base.link_pipe!(inp; reader_supports_async=true, writer_supports_async=true)
    out = IOBuffer()
    term = Base.invokelatest(
        repl.Terminals.TTYTerminal, "dumb", inp.out,
        IOContext(out, :color => true, :displaysize => (1_000_000, 200)), devnull
    )
    write(inp.in, "q")
    try
        Base.invokelatest(
            cth.descend, f, tt; terminal=term, iswarn=true, hide_type_stable=true,
            optimize=optimize
        )
    catch e
        return "ERROR: " * sprint(showerror, e) * "\n" * _plain(String(take!(out)))
    finally
        close(inp.in)
    end
    return _plain(String(take!(out)))
end

"""
What Julia's own inference says of `f(tt)`, for a function Cthulhu cannot show (the run loop): the
VARIABLES and the intermediate values whose inferred type is not concrete — a Union, `Any`, an
abstract type, a `Core.Box` — from `code_typed(…; optimize=false)`.
"""
function _typed_fallback(name::String, f, tt)::Nothing
    ci, rt = only(code_typed(f, tt; optimize=false))
    wc(t) = t isa Type ? t : (isdefined(t, :typ) ? wc(t.typ) : typeof(t))    # a lattice element's type
    loose(t) = t === Core.Box || !(isconcretetype(t) || t === Union{})
    slots = [
        (string(ci.slotnames[i]), wc(ci.slottypes[i])) for i in eachindex(ci.slotnames)
    ]
    bad = unique!([(n, t) for (n, t) in slots if loose(t) && !startswith(n, "#")])
    sort!(bad; by=x -> (x[1], string(x[2])))
    # the values of CALLS whose result is USED: a control-flow statement has no value, and inference
    # records no type (`Any`) for a result nothing reads — `x.f = v`, `a[i] = v`
    used = Set{Int}()
    uses!(x) =
        if x isa Core.SSAValue
            push!(used, x.id)
        elseif x isa Expr
            foreach(uses!, x.args)
        elseif x isa Core.GotoIfNot
            uses!(x.cond)
        elseif x isa Core.ReturnNode
            isdefined(x, :val) && uses!(x.val)
        elseif x isa Core.PiNode
            uses!(x.val)
        end
    foreach(uses!, ci.code)
    iscall(i) =
        i in used && ci.code[i] isa Expr &&
        ci.code[i].head in (:call, :invoke, :new, :foreigncall)
    ssa = [wc(ci.ssavaluetypes[i]) for i in eachindex(ci.code) if iscall(i)]
    @printf(
        "%-14s inference: %d of %d variables and %d of %d used call results are not concrete (Any: %d, Core.Box: %d); returns %s\n",
        name, length(bad), length(slots), count(loose, ssa), length(ssa),
        count(==(Any), ssa),
        count(==(Core.Box), ssa), rt
    )
    # which calls give the non-concrete results: by callee, most frequent first
    callees = Dict{String, Int}()
    for i in eachindex(ci.code)
        ex = ci.code[i]
        (iscall(i) && loose(wc(ci.ssavaluetypes[i]))) || continue
        k =
            first(string(ex.args[ex.head === :invoke ? 2 : 1]), 60) * " → " *
            first(string(wc(ci.ssavaluetypes[i])), 50)
        callees[k] = get(callees, k, 0) + 1
    end
    for (k, c) in first(sort!(collect(callees); by=x -> -x[2]), 8)
        @printf("      %5d × %s\n", c, k)
    end
    path = joinpath(BENCH_OUT, "descend_$(name)_inference.txt")
    open(path, "w") do io
        foreach(((n, t),) -> println(io, n, " :: ", t), bad)
    end
    for (n, t) in first(bad, 12)
        println("      ", n, " :: ", first(string(t), 130))
    end
    length(bad) > 12 && println("      … ", length(bad) - 12, " more in ", path)
    return nothing
end

"`--descend`: each hot function's view to a file, and how many of its types are not concrete."
function descend_report(names::Vector{String})::Nothing
    Base.find_package("Cthulhu") === nothing &&
        error(
            "tools/bench.jl --descend: Cthulhu is not installed in the global environment"
        )
    cth = Base.require(Main, :Cthulhu)
    mkpath(BENCH_OUT)
    picked = isempty(names) ? HOT : [h for h in HOT if h.first in names]
    isempty(picked) &&
        error("tools/bench.jl --descend: none of $(names) is in HOT ($(first.(HOT)))")
    println(
        "Cthulhu ",
        pkgversion(cth),
        " — non-concrete types in the hot functions (full views: ",
        BENCH_OUT,
        ")"
    )
    @printf("%-14s %8s %8s %8s %10s\n", "function", "Union", "Any", "Box", "calls")
    for (name, (f, tt)) in picked
        t = @elapsed text = _descend_text(cth, f, tt)
        note = ""
        if startswith(text, "ERROR")
            # Cthulhu's view of the code BEFORE optimisation can fail on a very large function (the
            # run loop: an assertion of the compiler's own); its view of the OPTIMISED code is next
            println(
                name,
                ": the unoptimised view failed — ",
                first(split(text, '\n')),
                "; trying the optimised one"
            )
            t += @elapsed text = _descend_text(cth, f, tt; optimize=true)
            note = " (optimised view)"
        end
        path = joinpath(BENCH_OUT, "descend_$name.txt")
        write(path, text)
        if startswith(text, "ERROR")
            println(
                name, ": ", first(split(text, '\n')), " — Cthulhu cannot show this function"
            )
            _typed_fallback(name, f, tt)
            continue
        end
        name *= note
        body, menu = _split2(text, "Select a call to descend into")
        calls = count(
            l -> startswith(lstrip(l), "•") || startswith(l, "   "), split(menu, '\n')
        )
        @printf(
            "%-14s %8d %8d %8d %10d   (%.1f s)\n", name,
            length(collect(eachmatch(r"::Union\{", body))),
            length(collect(eachmatch(r"::Any\b", body))),
            length(collect(eachmatch(r"Core\.Box", body))), calls, t
        )
        marked = unique!([strip(l) for l in split(body, '\n') if occursin("::", l)][2:end])
        for l in first(marked, 8)
            println("      ", first(l, 150))
        end
        length(marked) > 8 &&
            println("      … ", length(marked) - 8, " more lines in ", path)
    end
    return nothing
end

"`--code`: the run loop's LLVM IR and native code, to files, and what they contain."
function code_report()::Nothing
    f, tt = HOT[1].second
    mkpath(BENCH_OUT)
    llvm = sprint(io -> code_llvm(io, f, tt; debuginfo=:none))
    native = sprint(io -> code_native(io, f, tt; debuginfo=:none, syntax=:intel))
    write(joinpath(BENCH_OUT, "run_loop.ll"), llvm)
    write(joinpath(BENCH_OUT, "run_loop.s"), native)
    n(text, rx) = length(collect(eachmatch(rx, text)))
    println(
        "the run loop, PL_next_solution_guarded on ",
        BT,
        " (files: ",
        BENCH_OUT,
        "/run_loop.ll, run_loop.s)"
    )
    for (what, v) in (
        ("LLVM IR lines", count(==('\n'), llvm)),
        ("  basic blocks", n(llvm, r"(?m)^[A-Za-z0-9_.]+:")),
        ("  calls", n(llvm, r"\bcall\b")),
        (
            "  DYNAMIC calls (jl_apply_generic, jl_invoke)",
            n(llvm, r"@i?jl_(apply_generic|invoke)\b")
        ),
        (
            "  allocations (gc_alloc, gc_small_alloc, gc_big_alloc)",
            n(llvm, r"@(julia\.gc_alloc_obj|i?jl_gc_(small|big|pool)_alloc\w*)")
        ),
        ("  boxes (jl_box_*)", n(llvm, r"@i?jl_box_\w+")),
        ("  switch instructions", n(llvm, r"\bswitch\b")),
        (
            "  bounds-check failure sites (throw_boundserror)",
            n(llvm, r"@(j_throw_boundserror_\w+|i?jl_bounds_error\w*)")
        ),
        (
            "  method-error fallbacks (a union the compiler did not close)",
            n(llvm, r"@jl_f_throw_methoderror\b")
        ),
        ("  other throw sites (ijl_throw)", n(llvm, r"@ijl_throw\b")),
        ("native code lines", count(==('\n'), native)),
        (
            "  indirect jumps through a table (jmp qword ptr [...])",
            n(native, r"(?m)^\s*jmp\s+qword ptr \[[^\]]+\]\s*$")
        ),
        ("  calls", n(native, r"(?m)^\s*call\b")),
        ("  conditional jumps", n(native, r"(?m)^\s*j(?!mp)[a-z]+\b"))
    )
        @printf("%-58s %8d\n", what, v)
    end
    return nothing
end

"`--flame`: a profile of case `name`, saved; ProfileView's flame graph when it can be shown."
function flame_report(name::String)::Nothing
    i = findfirst(c -> c[1] == name, CASES)
    i === nothing &&
        error("tools/bench.jl --flame=$name names no case ($(join(first.(CASES), ", ")))")
    f = CASES[i][2]
    f()                                                         # compiled before the profile
    Profile.clear()
    t0 = time()
    Profile.@profile while time() - t0 < 3.0
        f()
    end
    data, lidict = Profile.retrieve()
    mkpath(BENCH_OUT)
    path = joinpath(BENCH_OUT, "flame_$name.jlprof")
    serialize(path, (data, lidict))
    tree = joinpath(BENCH_OUT, "flame_$name.txt")
    open(tree, "w") do io
        Profile.print(
            IOContext(io, :displaysize => (100_000, 250));
            format=:tree,
            C=false,
            mincount=10
        )
    end
    println(
        "profile of ",
        name,
        ": ",
        length(data),
        " samples words; saved to ",
        path,
        " (and as a call tree: ",
        tree,
        ")"
    )
    display_ = haskey(ENV, "DISPLAY") || haskey(ENV, "WAYLAND_DISPLAY")
    if display_ && Base.find_package("ProfileView") !== nothing
        pv = Base.require(Main, :ProfileView)
        Base.invokelatest(pv.view, data; lidict=lidict)
        println(
            "ProfileView: the flame graph of ",
            name,
            " is open — press Enter here to close it"
        )
        readline()
    else
        println(
            if display_
                "ProfileView is not installed (julia -e 'using Pkg; Pkg.add(\"ProfileView\")')"
            else
                "no display in this session (DISPLAY/WAYLAND_DISPLAY unset): the flame graph cannot be shown here"
            end
        )
        println("open it where there is one:")
        println(
            "  julia -e 'using Serialization, ProfileView; d, l = deserialize(\"",
            path,
            "\"); ProfileView.view(d; lidict=l); readline()'"
        )
    end
    return nothing
end

function main(args)
    diag = filter(a -> occursin(r"^--(descend|code|flame)(=|$)", a), args)
    if !isempty(diag)
        for a in diag
            key, val = _split2(a, "=")
            if key == "--descend"
                descend_report(String.(filter(!isempty, split(val, ','))))
            elseif key == "--code"
                code_report()
            else
                flame_report(isempty(val) ? "nreverse" : String(val))
            end
        end
        return nothing
    end
    filt = filter(a -> !startswith(a, "--"), args)
    cases = [c for c in CASES if isempty(filt) || any(f -> occursin(f, c[1]), filt)]
    isempty(cases) && error("tools/bench.jl: no case matches $(filt)")
    k = findfirst(a -> startswith(a, "--profile="), args)
    prof = k === nothing ? "" : String(split(args[k], '='; limit=2)[2])
    kr = findfirst(a -> startswith(a, "--runs="), args)
    runs = kr === nothing ? RUNS_DEFAULT : parse(Int, split(args[kr], '='; limit=2)[2])
    sp = swipl_server(cases)
    swv = sp === nothing ? "no swipl on PATH" : strip(read(`swipl --version`, String))
    println(
        "LogicKernel bench — julia $(VERSION), pid $(getpid()), $swv; $runs runs per side, interleaved"
    )
    # the machine's idle CPU BEFORE and AFTER the runs; a ratio is quoted only if both are quiet
    qc = quiet_check()
    tm = interleaved_times(cases, runs, sp)
    sp === nothing || close(sp)
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
    # the raw numbers: one row per run, both sides (tools/bench_results/, the user's rule, 2026-10-15)
    sha = try
        strip(read(`git -C $(dirname(@__DIR__)) rev-parse --short HEAD`, String))
    catch
        "nogit"
    end
    dirty = try
        !isempty(
            read(
                `git -C $(dirname(@__DIR__)) status --porcelain --untracked-files=no`,
                String
            )
        )
    catch
        false
    end
    now_utc = Dates.now(Dates.UTC)
    resdir = joinpath(@__DIR__, "bench_results")
    mkpath(resdir)
    stamp = Dates.format(now_utc, "yyyy-mm-ddTHHMMSS") * "Z"
    raw = joinpath(resdir, "$(stamp)_$(sha).tsv")
    open(raw, "w") do io
        println(io,
            "# machine: $(gethostname()); $(Sys.CPU_NAME), $(Sys.CPU_THREADS) threads, ",
            "$(round(Sys.total_physical_memory() / 2^30; digits=1)) GiB")
        println(io, "# commit: $sha$(dirty ? " (+ uncommitted changes)" : "")")
        println(io, "# date: $(Dates.format(now_utc, "yyyy-mm-dd HH:MM:SS")) UTC")
        println(
            io, "# $(swv); julia $(VERSION); $runs runs per side, interleaved; quiet=$quiet"
        )
        println(io, "case\tside\trun\tus_per_call\tcalls_per_run")
        for (name, _, _) in cases
            lk, sw, n, nsw = tm[name]
            for (r, t) in enumerate(lk)
                @printf(io, "%s\tLogicKernel\t%d\t%.6f\t%d\n", name, r, t, n)
            end
            for (r, t) in enumerate(sw)
                @printf(io, "%s\tswipl\t%d\t%.6f\t%d\n", name, r, t, nsw)
            end
        end
    end
    println("raw numbers: ", raw)
    @printf(
        "%-26s %22s %22s %9s %16s %8s %9s\n", "case", "LogicKernel µs med (IQR)",
        "swipl µs med (IQR)", "LK/swipl", "calls/run LK sw", "allocs", "bytes"
    )
    ratios = Dict{String, Float64}()
    for (name, f, _) in cases
        lk, sw, n, nsw = tm[name]
        lm, li = _median_iqr(lk)
        allocs, bytes = (@allocations f()), (@allocated f())
        if isempty(sw)
            ratios[name] = NaN
            @printf("%-26s %12.2f (%7.2f) %22s %9s %16s %8d %9d\n", name, lm, li, "—", "—",
                "$n —", allocs, bytes)
        else
            sm, si = _median_iqr(sw)
            r = quiet ? lm / sm : NaN
            ratios[name] = r
            @printf("%-26s %12.2f (%7.2f) %12.2f (%7.2f) %9.2f %16s %8d %9d\n", name, lm,
                li,
                sm, si, r, "$n $nsw", allocs, bytes)
        end
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
