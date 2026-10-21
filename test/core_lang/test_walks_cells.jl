# ORIGINAL: L1d step 5 — the walks on CELLS (pl-prims.c `ground`/`ph_ground`, `term_variables_loop`,
# `term_variables_to_termv`, `free_variables_loop` as `ground_cells`, `term_variables_loop_cells`,
# `term_variables_to_termv_cells`, `free_variables_loop_cells`, src/pl-prims.jl; the workspace's
# L1_plan/stageL1d_design.md §3d). Upstream marks a compound's FUNCTOR cell (MARK_MASK, as here) and a
# VARIABLE cell itself; ours keeps a variable cell 0 and marks it in a side vector (`ld.tv_seen`) — a
# representation-only DIVERGES. test/core_lang/test_walks_cells.jl — on every term type:
#   * a differential against swipl through clause bodies (the rules harness): ground/1,
#     term_variables/2,3 and bagof/setof's free variables (`^`, a `Module:` goal) over atoms, flat
#     and nested compounds, SHARED sub-terms reached through a binding (a DAG), cyclic terms, a long
#     list, a proper-list second argument too short; the variables' ORDER (depth-first, left to right);
#   * white-box: after every call no functor cell carries MARK_MASK, the side vector is all false and
#     the visited stack is empty — a second call on the same term answers the same;
#   * the boundary: a keyed variable bound to a term is decided on terms, COUNTED;
#   * the meter: the walk over a term on the stack makes no cold export, import or variable read.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_wi(i) = _rg(Int64(i))

_wc_clauses() = Tuple{_R, Union{Nothing, _R}}[
    # gr(T) :- ground(T).   tv(T, Vs) :- term_variables(T, Vs).   tv3(T, Vs, Tl) :- term_variables(T, Vs, Tl).
    (_rf("gr", _rv(1)), _rf("ground", _rv(1))),
    (_rf("tv", _rv(1), _rv(2)), _rf("term_variables", _rv(1), _rv(2))),
    (_rf("tv3", _rv(1), _rv(2), _rv(3)), _rf("term_variables", _rv(1), _rv(2), _rv(3))),
    # a DAG built by the program: S = s(X, 1) shared three times; ground after X = a
    (
        _rf("dag_gr", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("s", _rv(2), _wi(1))),
            _rf("=", _rv(9), _rf("d", _rv(1), _rv(1), _rf("e", _rv(1), _rv(1)))),
            _rf("\\+", _rf("ground", _rv(9))), _rf("=", _rv(2), _rs("a")),
            _rf("ground", _rv(9)))
    ),
    (
        _rf("dag_tv", _rv(8), _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("s", _rv(2), _rv(3))),
            _rf(
                "=",
                _rv(8),
                _rf("d", _rv(4), _rv(1), _rv(1), _rf("e", _rv(3), _rv(1), _rv(4)))
            ),
            _rf("term_variables", _rv(8), _rv(9)))
    ),
    # cyclic: X = f(X) is ground; X = f(X, Y) is not, and has one variable
    (
        _rf("cyc_gr", _rv(9)),
        _rconj(_rf("=", _rv(9), _rf("f", _rv(9))), _rf("ground", _rv(9)))
    ),
    (
        _rf("cyc_ng", _rv(8)),
        _rconj(
            _rf("=", _rv(9), _rf("f", _rv(9), _rv(8))),
            _rf("\\+", _rf("ground", _rv(9)))
        )
    ),
    (
        _rf("cyc_tv", _rv(8)),
        _rconj(
            _rf("=", _rv(9), _rf("f", _rv(9), _rv(1), _rf("g", _rv(9), _rv(2), _rv(1)))),
            _rf("term_variables", _rv(9), _rv(8)))
    ),
    # long(N, Vs): a list of N fresh variables (length/2), then its variables
    (
        _rf("long", _rv(1), _rv(2)),
        _rconj(_rf("length", _rv(3), _rv(1)), _rf("term_variables", _rv(3), _rv(2)))
    ),
    (
        _rf("longg", _rv(1)),
        _rconj(_rf("length", _rv(3), _rv(1)), _rf("\\+", _rf("ground", _rv(3))))
    ),
    # the free variables of bagof/setof: p/2 facts
    (_rf("p", _wi(1), _rs("a")), nothing), (_rf("p", _wi(2), _rs("b")), nothing),
    (_rf("p", _wi(3), _rs("a")), nothing),
    (
        _rf("bag_free", _rv(1), _rv(2)),
        _rf("bagof", _rv(1), _rf("p", _rv(1), _rv(2)), _rv(3))
    ),
    (
        _rf("bag_hat", _rv(9)),
        _rf("bagof", _rv(1), _rf("^", _rv(2), _rf("p", _rv(1), _rv(2))), _rv(9))
    ),
    (
        _rf("bag_mod", _rv(2), _rv(9)),
        _rf("bagof", _rv(1), _rf(":", _rs("user"), _rf("p", _rv(1), _rv(2))), _rv(9))
    ),
    (
        _rf("set_free", _rv(2), _rv(9)),
        _rf("setof", _rv(1), _rf("p", _rv(1), _rv(2)), _rv(9))
    ),
    (
        _rf("bag_two", _rv(2), _rv(3), _rv(9)),
        _rf(
            "bagof",
            _rv(1),
            _rf(",", _rf("p", _rv(1), _rv(2)), _rf("p", _rv(3), _rv(2))),
            _rv(9)
        )
    )
]

@testset "the walks on cells, as swipl: ground/1, term_variables/2,3, bagof/setof's free variables" begin
    db = _rdb(_wc_clauses())
    A, B, C, Vs = _rv(50), _rv(51), _rv(52), _rv(53)
    goals = _R[
        _rf("gr", _rs("a")), _rf("gr", _rf("f", _rs("a"), _rf("g", _wi(1)))), _rf("gr", A),
        _rf("gr", _rf("f", _rs("a"), _rf("g", A))), _rf("gr", _rints(1:2000)),
        _rf("tv", _rs("a"), Vs), _rf("tv", A, Vs),
        _rf("tv", _rf("f", A, _rf("g", B, A), C, B), Vs),
        _rf("tv", _rcons(B, _rcons(A, _rcons(B, C))), Vs),
        _rf("tv3", _rf("f", A, B), Vs, _rlist(C)),
        _rf("tv", _rf("f", A, B, C), _rlist(_rv(54))),           # a proper list too short: fails
        _rf("tv", _rf("f", A, B), _rlist(_rv(54), _rv(55))),
        _rf("dag_gr", A), _rf("dag_tv", A, Vs), _rf("cyc_gr", A), _rf("cyc_ng", A),
        _rf("cyc_tv", Vs), _rf("long", _wi(3000), _rv(56)), _rf("longg", _wi(3000)),
        _rf("bag_free", A, B), _rf("bag_hat", Vs), _rf("bag_mod", B, Vs),
        _rf("set_free", B, Vs),
        _rf("bag_two", B, C, Vs)
    ]
    ours = _rlines(db, goals)
    # the kernel's side alone (also where swipl is absent: Pkg.test)
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> startswith(l, "exception("), ours)
    @test "gr(a) det" in ours && !any(l -> startswith(l, "gr(_)"), ours)
    @test "tv(f(A,g(B,A),C,B),[A,B,C]) det" in ours
    @test "tv([A,B,A|C],[A,B,C]) det" in ours
    @test "cyclic det" in ours && "cyc_ng(_) det" in ours       # cyc_gr's answer is a rational tree
    if _R_SWIPL
        theirs = _rswipl(_wc_clauses(), goals)
        @test ours == theirs
        if ours != theirs
            for i in eachindex(ours)
                if i > length(theirs) || ours[i] != theirs[i]
                    @info "first difference" i ours[i] get(theirs, i, "—")
                    break
                end
            end
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

"An engine with the values of `vs` put into term references; `(ld, t)` (reference `t + i - 1` is slot `t + i`)."
function _wc_engine(vs::Vector{_R}; pvm=LK.PutVarMap())
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
_wc_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)
"No functor cell marked, the side vector all false, the visited stack empty."
_wc_clean(ld) =
    !any(
        p -> LK.isFunctor(ld.gstack[p]) && (ld.gstack[p] & LK.MARK_MASK) != 0, 1:(ld.gTop)
    ) &&
    !any(ld.tv_seen) && isempty(ld.cycle_vstack)

@testset "white-box: the marks and the side vector cleared, a second call the same" begin
    X, Y, Z = _rv(1), _rv(2), _rv(3)
    s = _rf("s", X, _wi(1))
    ld, t = _wc_engine(
        _R[_rf("d", s, s, _rf("e", Y, s, X), Z), _rf("f", _rs("a"), _rf("g", _wi(1)))]
    )
    for _ in 1:2
        @test LK.ground_cells(ld, -(t + 1)) > 0
        @test _wc_clean(ld)
        @test LK.ground_cells(ld, -(t + 2)) == 0
        @test _wc_clean(ld)
        v0 = LK.PL_new_term_refs(ld, 0)
        n, r = LK.term_variables_to_termv_cells(ld, t, typemax(Int))
        @test n == 3 && r == v0
        @test _wc_clean(ld)
        # three distinct unbound cells (the order is the differential's: depth-first, left to right)
        ks = [LK._deref_loc(ld, -(r + i))[3] for i in 1:n]
        @test all(k -> LK._deref_loc(ld, k)[1] == LK.DU_CELL, ks) && length(unique(ks)) == 3
        LK.PL_reset_term_refs(ld, v0)
    end
end

@testset "the boundary: a keyed variable bound to a term, decided on terms, counted" begin
    ld, t = _wc_engine(_R[_rs("x"), _rs("y")])
    kv = lk_var(_R, UInt64(4731))
    # f(kv, a): kv a value-table word (laid by hand since L1f f3b-1: a writer binds a keyed variable to a fresh cell now)
    LK.setSlotValue!(ld, t + 1, _rf("f", _rs("x"), _rs("a")))
    ld.gstack[LK.valPtr(ld.slots[t + 1]) + 1] = lk_boundary_word!(ld, kv)
    p0 = ld.cold_pairs
    @test LK.ground_cells(ld, -(t + 1)) == LK.GROUND_BOUNDARY     # kv unbound: not ground
    @test ld.cold_pairs > p0
    LK.Trail!(ld, var_key(kv), _rf("g", _rs("b")))                # kv = g(b)
    p0 = ld.cold_pairs
    @test LK.ground_cells(ld, -(t + 1)) == 0
    @test ld.cold_pairs > p0
    @test _wc_clean(ld)
    kw = lk_var(_R, UInt64(4733))
    LK.setSlotValue!(ld, t + 2, _rf("h", _rs("x"), _rs("x")))     # h(kw, kw), by hand as above
    q = LK.valPtr(ld.slots[t + 2])
    ld.gstack[q + 1] = lk_boundary_word!(ld, kw)
    ld.gstack[q + 2] = lk_boundary_word!(ld, kw)
    p0 = ld.cold_pairs
    v0 = LK.PL_new_term_refs(ld, 0)
    n, r = LK.term_variables_to_termv_cells(ld, t + 1, typemax(Int))
    @test n == 1 && ld.cold_pairs == p0 + 1
    @test _wc_clean(ld)
    LK.PL_reset_term_refs(ld, v0)
end

@testset "the meter: the walks over a term on the stack make no cold export, import or variable read" begin
    X, Y = _rv(1), _rv(2)
    ld, t = _wc_engine(
        _R[_rf("f", X, _rlist((_wi(i) for i in 1:50)...), _rf("g", Y, X), _rs("a"))]
    )
    c0 = _wc_counts(ld)
    @test LK.ground_cells(ld, -(t + 1)) > 0
    v0 = LK.PL_new_term_refs(ld, 0)
    n, _ = LK.term_variables_to_termv_cells(ld, t, typemax(Int))
    @test n == 2
    @test _wc_counts(ld) == c0
    LK.PL_reset_term_refs(ld, v0)
end
