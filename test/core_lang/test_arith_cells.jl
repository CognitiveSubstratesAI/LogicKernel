# ORIGINAL: L1d — arithmetic on CELLS (pl-arith.c `evalExpression`, `valueExpression`, `arithChar`,
# `getCharExpression` and pl-gmp.c `PL_unify_number` on the words: `evalExpression_cells` and friends,
# src/pl-arith.jl, src/pl-gmp.jl; the workspace's L1_plan/stageL1d_design.md §3e). Upstream's own units
# and the random differential stay in test_arith_swipl.jl, unchanged (they reach the cells walk too: a
# put compound is copied onto the stack). test/core_lang/test_arith_cells.jl — on every term type:
#   * a differential against swipl through CLAUSE BODIES (the rules harness), where the VM builds the
#     expressions on the stack: left- and right-nested (2000 deep: the walk's acyclic check runs),
#     arguments reached through bindings and reference chains, integers at the tagged edge (a
#     value-table integer bound, read back and evaluated again, A_ADD_FC's slow path included),
#     floats (`-0.0`), "x" and `[X]` (a code, a one-character atom), the comparisons;
#   * the ERROR differential: which error a bad expression raises first — upstream walks the LAST
#     argument first, then applies the functor;
#   * is/2 with a bound left side (compare: an integer, a float bit for bit, the tagged edge, an atom,
#     a compound) and an unbound one (bind), the binding undone on backtracking;
#   * white-box: the bound word (tagged inside the range, a value-table word past it), the walk's
#     stacks empty after a value and after an error;
#   * the boundary: a keyed variable bound to an expression is evaluated on its term, COUNTED;
#   * the meter (test_zero_exports.jl has the program-level one): one evaluation on the stack makes no
#     cold export, import or variable read.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_ai(i) = _rg(Int64(i))
_ais(x, e) = _rf("is", x, e)
_aplus(a, b) = _rf("+", a, b)
_atimes(a, b) = _rf("*", a, b)
_aminus(a, b) = _rf("-", a, b)
const _AC_MAXT = Int64(LK.PLMAXTAGGEDINT)       # 72057594037927935: the largest tagged integer
const _AC_MINT = Int64(LK.PLMINTAGGEDINT)

_ac_clauses() = Tuple{_R, Union{Nothing, _R}}[
    # ev(E, X) :- X is E.        ev2(L, E) :- L is E.        lt_e(A, B) :- A + 1 < B * 2.  (and >=, =:=)
    (_rf("ev", _rv(1), _rv(2)), _ais(_rv(2), _rv(1))),
    (_rf("ev2", _rv(1), _rv(2)), _ais(_rv(1), _rv(2))),
    (
        _rf("lt_e", _rv(1), _rv(2)),
        _rf("<", _aplus(_rv(1), _ai(1)), _atimes(_rv(2), _ai(2)))
    ),
    (_rf("ge_e", _rv(1), _rv(2)), _rf(">=", _aminus(_rv(1), _rv(2)), _ai(0))),
    (_rf("eq_e", _rv(1), _rv(2)), _rf("=:=", _rv(1), _aplus(_rv(2), _ai(0)))),
    # lbuild(N, E): ((((0+1)+2)+…)+N), rbuild(N, E): N+(…+(1+0)) — built by the VM on the stack
    (_rf("lbuild", _ai(0), _ai(0)), _rs("!")),
    (
        _rf("lbuild", _rv(1), _aplus(_rv(2), _rv(1))),
        _rconj(_ais(_rv(3), _aminus(_rv(1), _ai(1))), _rf("lbuild", _rv(3), _rv(2)))
    ),
    (_rf("rbuild", _ai(0), _ai(0)), _rs("!")),
    (
        _rf("rbuild", _rv(1), _aplus(_rv(1), _rv(2))),
        _rconj(_ais(_rv(3), _aminus(_rv(1), _ai(1))), _rf("rbuild", _rv(3), _rv(2)))
    ),
    (
        _rf("lnest", _rv(1), _rv(2)),
        _rconj(_rf("lbuild", _rv(1), _rv(3)), _ais(_rv(2), _rv(3)))
    ),
    (
        _rf("rnest", _rv(1), _rv(2)),
        _rconj(_rf("rbuild", _rv(1), _rv(3)), _ais(_rv(2), _rv(3)))
    ),
    # refs(X): the arguments through a reference chain (A = B, B = C, C = 2) and a bound compound D
    (
        _rf("refs", _rv(9)),
        _rconj(_rf("=", _rv(1), _rv(2)), _rf("=", _rv(2), _rv(3)),
            _rf("=", _rv(3), _ai(2)),
            _rf("=", _rv(4), _atimes(_rv(1), _rv(3))),
            _ais(_rv(9), _aminus(_aplus(_atimes(_rv(4), _ai(10)), _rv(1)), _rv(3))))
    ),
    # mixed(X): a float bound in a cell, an integer, unary minus
    (
        _rf("mixed", _rv(9)),
        _rconj(_rf("=", _rv(1), _rg(1.5)), _rf("=", _rv(2), _ai(2)),
            _ais(_rv(9), _aplus(_atimes(_rv(1), _rv(2)), _rf("-", _rv(2)))))
    ),
    # edge(X, Y, Z): past the tagged range (a value-table integer in a cell), read back by A_ADD_FC's
    # slow path (Y is X - 1) and by the walk (Z is X * 2 - X); the negative edge too
    (
        _rf("edge", _rv(1), _rv(2), _rv(3)),
        _rconj(_ais(_rv(1), _aplus(_ai(_AC_MAXT), _ai(1))),
            _ais(_rv(2), _aminus(_rv(1), _ai(1))),
            _ais(_rv(3), _aminus(_atimes(_rv(1), _ai(2)), _rv(1))))
    ),
    (
        _rf("nedge", _rv(1), _rv(2)),
        _rconj(
            _ais(_rv(1), _aminus(_ai(_AC_MINT), _ai(1))),
            _ais(_rv(2), _aplus(_rv(1), _ai(1)))
        )
    ),
    # chars(X): "a" + [0'b] + [c]
    (
        _rf("chars", _rv(9)),
        _ais(
            _rv(9),
            _aplus(_aplus(_rg("a"), _rcons(_ai(98), _rnil())), _rcons(_rs("c"), _rnil()))
        )
    ),
    # an error from a value bound on the stack: Y = foo, X is 1 + Y
    (
        _rf("err_b", _rv(9)),
        _rconj(_rf("=", _rv(1), _rs("foo")), _ais(_rv(9), _aplus(_ai(1), _rv(1))))
    ),
    # is/2 with its left side bound on the stack (compare, never bind)
    (
        _rf("bl_int", _rv(9)),
        _rconj(_rf("=", _rv(1), _ai(3)), _ais(_rv(1), _aplus(_ai(1), _ai(2))))
    ),
    (
        _rf("bl_fl", _rv(9)),
        _rconj(_rf("=", _rv(1), _ai(3)), _ais(_rv(1), _atimes(_rg(1.5), _ai(2))))
    ),
    (
        _rf("bl_ff", _rv(9)),
        _rconj(_rf("=", _rv(1), _rg(3.0)), _ais(_rv(1), _atimes(_rg(1.5), _ai(2))))
    ),
    (
        _rf("bl_nz", _rv(9)),
        _rconj(_rf("=", _rv(1), _rg(-0.0)), _ais(_rv(1), _atimes(_rg(-0.0), _ai(1))))
    ),
    (
        _rf("bl_pz", _rv(9)),
        _rconj(_rf("=", _rv(1), _rg(0.0)), _ais(_rv(1), _atimes(_rg(-0.0), _ai(1))))
    ),
    (
        _rf("bl_edge", _rv(9)),
        _rconj(_ais(_rv(1), _aplus(_ai(_AC_MAXT), _ai(1))),
            _ais(_rv(1), _aminus(_ai(_AC_MAXT), _ai(-1))))
    ),
    (_rf("bl_atom", _rv(9)), _rconj(_rf("=", _rv(1), _rs("a")), _ais(_rv(1), _ai(1)))),
    (
        _rf("bl_cmp", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("f", _rs("x"))), _ais(_rv(1), _ai(1)))
    ),
    # backtracking: the binding is undone (a tagged word, a value-table word)
    (
        _rf("bt", _rv(9)),
        _rconj(_rf(";", _rf("=", _rv(1), _ai(1)), _rf("=", _rv(1), _ai(2))),
            _ais(_rv(9), _atimes(_rv(1), _ai(10))))
    ),
    (
        _rf("bt_edge", _rv(9)),
        _rconj(_rf(";", _rf("=", _rv(1), _ai(_AC_MAXT)), _rf("=", _rv(1), _ai(1))),
            _ais(_rv(9), _aplus(_rv(1), _ai(1))))
    )
]

@testset "arithmetic on cells, as swipl: values, errors, bound and unbound left sides" begin
    db = _rdb(_ac_clauses())
    X, Y = _rv(50), _rv(51)
    goals = _R[
        _rf("ev", _aplus(_ai(1), _ai(2)), X),
        _rf("ev", _atimes(_aplus(_ai(1), _ai(2)), _aminus(_ai(10), _rf("-", _ai(4)))), X),
        _rf("ev", _rf("<<", _ai(1), _ai(60)), X),
        _rf("ev", _rf(">>", _rf("-", _ai(1000)), _ai(3)), X),
        _rf("ev", _aplus(_rg(0.5), _ai(1)), X),
        _rf("ev", _rcons(_ai(120), _rnil()), X),
        _rf("ev", _rg("z"), X),
        _rf("lnest", _ai(10), X), _rf("rnest", _ai(10), X),
        _rf("lnest", _ai(2000), X), _rf("rnest", _ai(2000), X),
        _rf("refs", X), _rf("mixed", X), _rf("edge", X, Y, _rv(52)), _rf("nedge", X, Y),
        _rf("chars", X),
        _rf("lt_e", _ai(1), _ai(2)), _rf("lt_e", _ai(3), _ai(1)),
        _rf("lt_e", _rg(1.5), _ai(2)),
        _rf("ge_e", _ai(5), _ai(5)), _rf("ge_e", _ai(4), _ai(5)),
        _rf("eq_e", _ai(5), _ai(5)), _rf("eq_e", _rg(5.0), _ai(5)),
        _rf("eq_e", _ai(5), _ai(6)),
        # which error first: the LAST argument is evaluated first
        _rf("ev", _aplus(_aplus(_ai(1), _rs("a")), _rv(60)), X),       # 1 + a + _: instantiation
        _rf("ev", _aplus(_rf("foo", _ai(1)), _rv(61)), X),              # foo(1) + _: instantiation
        _rf("ev", _aplus(_rv(62), _rs("foo")), X),                      # _ + foo: foo/0
        _rf("ev", _aplus(_rs("a"), _rf("foo", _ai(1))), X),             # a + foo(1): foo/1
        _rf("ev", _aplus(_rf("foo", _rs("a")), _ai(1)), X),             # foo(a) + 1: a/0 before foo/1
        _rf("ev", _aplus(_rs("[]"), _ai(1)), X),                        # the text atom '[]'
        _rf("ev", _aplus(_rnil(), _ai(1)), X),                          # []
        _rf("ev", _rcons(_rs("a"), _rcons(_rs("b"), _rnil())), X),      # [a,b]: one character
        _rf("ev", _rcons(_rv(63), _rnil()), X),                         # [_]
        _rf("ev", _rcons(_rs("ab"), _rnil()), X),                       # [ab]
        _rf("ev", _aplus(_rg("ab"), _ai(1)), X),                        # "ab"
        _rf("ev", _rf("f", _ai(1), _ai(2), _ai(3)), X),                 # f/3
        _rf("err_b", X),
        _rf("bl_int", X), _rf("bl_fl", X), _rf("bl_ff", X), _rf("bl_nz", X),
        _rf("bl_pz", X),
        _rf("bl_edge", X), _rf("bl_atom", X), _rf("bl_cmp", X),
        _rf("ev2", _ai(3), _aplus(_ai(1), _ai(2))),
        _rf("ev2", _ai(4), _aplus(_ai(1), _ai(2))),
        _rf("bt", X), _rf("bt_edge", X)
    ]
    ours = _rlines(db, goals)
    # the kernel's side alone (also where swipl is absent: Pkg.test)
    @test count(==("end"), ours) == length(goals)
    @test "ev(+(1,2),3) det" in ours
    @test "lnest(2000,2001000) det" in ours && "rnest(2000,2001000) det" in ours
    @test "refs(40) det" in ours && "mixed(1.0) det" in ours
    @test "edge(72057594037927936,72057594037927935,72057594037927936) det" in ours
    @test "chars(294) det" in ours
    @test count(l -> startswith(l, "exception(instantiation_error)"), ours) == 3   # [_]: PL_error's unbound culprit
    @test "exception(type_error(evaluable,/(foo,1))) det" in ours
    @test "exception(type_error(evaluable,/(a,0))) det" in ours
    @test "bt(10) nondet" in ours && "bt(20) det" in ours
    @test "bt_edge(72057594037927936) nondet" in ours && "bt_edge(2) det" in ours
    @test "bl_ff(V9) det" in ours || "bl_ff(_) det" in ours
    @test !any(l -> startswith(l, "bl_fl(") || startswith(l, "bl_pz("), ours)
    if _R_SWIPL
        theirs = _rswipl(_ac_clauses(), goals)
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

"An engine with the values of `vs` put into term references; `(ld, t)` (reference `i` is slot `t + i`)."
function _ac_engine(vs::Vector{_R}; pvm=LK.PutVarMap())
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
_ac_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)

@testset "white-box: the bound word, the walk's stacks empty after a value and an error" begin
    ld, t = _ac_engine(_R[_rv(1), _rv(2), _rv(3)])
    n = LK.number()
    n.type = LK.V_INTEGER
    n.i = _AC_MAXT
    @test LK.PL_unify_number(ld, t, n)
    k, w, _ = LK._deref_loc(ld, -(t + 1))
    @test k == LK.DU_VALUE && LK.isTaggedIntW(w) && LK.valInt(w) == _AC_MAXT     # varBindConst
    n.i = _AC_MAXT + 1
    @test LK.PL_unify_number(ld, t + 1, n)
    k, w, _ = LK._deref_loc(ld, -(t + 2))
    @test k == LK.DU_VALUE && !LK.isTaggedIntW(w)                                # an indirect
    @test LK.int64_value(LK._value_term(ld, w)) == _AC_MAXT + 1
    @test LK.PL_unify_number(ld, t + 1, n)                                       # bound: compare
    n.i = _AC_MAXT
    @test !LK.PL_unify_number(ld, t + 1, n) && LK.PL_unify_number(ld, t, n)
    n.type = LK.V_FLOAT
    n.f = 2.5
    @test LK.PL_unify_number(ld, t + 2, n) && LK.PL_unify_number(ld, t + 2, n)
    n.f = 2.25
    @test !LK.PL_unify_number(ld, t + 2, n)
    @test !LK.PL_unify_number(ld, t, n)                                      # an int vs a float
    # term reference `t + i - 1` is slot `t + i`. The stacks after a value and after an error (the walk's term_stack, the pooled numbers)
    ld, t = _ac_engine(
        _R[
            _aplus(_atimes(_ai(2), _ai(3)), _rf("-", _ai(1))),
            _aplus(_ai(1), _rf("foo", _rv(1)))
        ]
    )
    r = LK.number()
    @test LK.valueExpression(ld, t, r) && r.type == LK.V_INTEGER && r.i == 5
    @test isempty(ld.arith_cells) && ld.arith_top == 0
    @test !LK.valueExpression(ld, t + 1, r)
    @test isempty(ld.arith_cells) && ld.arith_top == 0
end

@testset "the boundary: a keyed variable bound to an expression, evaluated on its term, counted" begin
    ld, t = _ac_engine(_R[_rs("x"), _rs("y")])
    kv = lk_var(_R, UInt64(4719))
    lk_side_value!(ld, t + 1, kv)                                       # (the boundary: built since L1f f3b-1)
    LK.Trail!(ld, var_key(kv), _aplus(_ai(1), _ai(2)))                 # kv = 1 + 2: a store entry
    r = LK.number()
    p0 = ld.cold_pairs
    @test LK.valueExpression(ld, t, r) && r.i == 3
    @test ld.cold_pairs == p0 + 1                                       # the boundary, COUNTED
    # inside a walk: (kw * 2) on the stack, kw a value-table word holding a keyed variable (stored
    # unbound — a put would copy a bound one away), bound afterwards in the store (since L1f f3b-1 a
    # writer binds a keyed variable to a cell: the word is laid by hand, as `_word_of!` laid it before)
    kw = lk_var(_R, UInt64(4723))
    LK.setSlotValue!(ld, t + 2, _atimes(_rs("x"), _ai(2)))
    ld.gstack[LK.valPtr(ld.slots[t + 2]) + 1] = lk_boundary_word!(ld, kw)
    LK.Trail!(ld, var_key(kw), _aplus(_ai(1), _ai(2)))
    p0 = ld.cold_pairs
    @test LK.valueExpression(ld, t + 1, r) && r.i == 6
    @test ld.cold_pairs == p0 + 1
    # is/2's binding at the boundary: an unbound keyed variable is bound through its key
    ku = lk_var(_R, UInt64(4721))
    lk_side_value!(ld, t + 1, ku)
    p0 = ld.cold_pairs
    @test LK.PL_unify_number(ld, t, r)
    @test ld.cold_pairs == p0 + 1
    @test LK.int64_value(LK.deRef(ld, ku)) == 6
end

@testset "the meter: an evaluation on the stack makes no cold export, import or variable read" begin
    X = _rv(1)
    ld, t = _ac_engine(
        _R[
            X,
            _aplus(_atimes(X, _ai(3)), _aminus(_rcons(_ai(97), _rnil()), _rg(0.5))),
            _rv(2)
        ];
        pvm=LK.PutVarMap()
    )
    n = LK.number()
    n.type = LK.V_INTEGER
    n.i = 7
    @test LK.PL_unify_number(ld, t, n)                              # X = 7, bound on its cell
    c0 = _ac_counts(ld)
    r = LK.number()
    @test LK.valueExpression(ld, t + 1, r) && r.type == LK.V_FLOAT && r.f == 117.5
    @test LK.PL_unify_number(ld, t + 2, r)
    @test _ac_counts(ld) == c0
end
