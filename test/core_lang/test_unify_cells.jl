# ORIGINAL: L1c sub-commit 4 — `do_unify` over the CELLS (pl-prims.c `do_unify` as `do_unify_cells`,
# src/pl-prims.jl): the VM's `H_VAR`, `B_UNIFY_VV` and `=/2` (`PL_unify`) unify locations — slots and
# global cells — not terms; upstream has no separate test (tests/core_lang/test_unify.pl is on terms
# and runs unchanged). test/core_lang/test_unify_cells.jl — on every term type:
#   * the binding direction (user, 2026-10-15): a slot is never an unbound variable, so only global
#     cells are bound, and of two cells the HIGHER position takes the lower's reference — in both
#     argument orders, with no global → local reference anywhere on the global stack;
#   * the simple cases against swipl through the rules differential: atoms, an atom against a
#     compound, two values (`1 = 1.0` FAILS: SWI's identity), var/var, var/value, value/var; the head
#     path (`H_VAR`) and the body path (`=/2`, `B_UNIFY_VV`);
#   * compounds: equal functors walked left to right, the first failing argument stopping the walk
#     with the bindings made before it in place (upstream's contract: the caller undoes); different
#     functors, different arities;
#   * cycles: `X = f(X), Y = f(Y), X = Y` terminates and succeeds, `X = f(X, a), Y = f(Y, b), X = Y`
#     fails, and every functor cell holds its functor word again afterwards (`exitCyclic`);
#   * Q2 (user, 2026-10-04; kernel-only, swipl cannot read `(X a)`): `(X a) = f(a)` binds `X = f` in
#     both orders, `(X a) = f(a, b)` fails, a `$expr/3` against a list cell;
#   * the boundary: a KEYED variable (a value with no word form, until the stamp falls) on either
#     side is bound on terms;
#   * the meter (condition 3 of the L1c plan): a head unification of a list against a slot makes NO
#     cold export — `cold_exports` unchanged across the call (the flatness pin of test_rules_swipl.jl
#     moves from `6n + 7` to `6n + 4` with this step).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"A fresh engine with a foreign frame and `n` term references; `(db, ld, t)` with slot `t + i` for reference `i`."
function _uc_engine(n::Int)
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, n)
    return db, ld, t
end

"No word on the global stack references the local stack (`TAG_REFERENCE|STG_LOCAL`): no global → local reference."
_uc_no_local_ref(ld) =
    all(
        p -> !(LK.isRef(ld.gstack[p]) && LK.storage(ld.gstack[p]) == LK.STG_LOCAL),
        1:(ld.gTop)
    )

@testset "binding direction: only global cells are bound, the higher to the lower, in both orders" begin
    for order in (1, 2)
        db, ld, t = _uc_engine(2)
        LK.putSlotValue!(ld, t + 1, _rv(1))             # a put: a fresh cell, referenced from the slot
        q = LK.unRef(ld.slots[t + 1])
        p = LK.allocGlobalCells!(ld, 1)                 # a younger cell, referenced from the other slot
        ld.slots[t + 2] = LK.makeRefG(p)
        @test p > q
        rc = if order == 1
            LK.do_unify_cells(ld, -(t + 1), -(t + 2))
        else
            LK.do_unify_cells(ld, -(t + 2), -(t + 1))
        end
        s1, s2 = ld.slots[t + 1], ld.slots[t + 2]
        @test rc == LK.BOOLEX_TRUE
        @test ld.slots[t + 1] == s1 && ld.slots[t + 2] == s2   # no slot is written: a slot is never bound
        @test ld.gstack[p] == LK.makeRefG(q)            # the higher cell points at the lower
        @test LK.isVar(ld.gstack[q])                    # the lower stays the variable
        @test LK.isRef(ld.slots[t + 1]) && LK.isRef(ld.slots[t + 2])   # the slots still references
        @test _uc_no_local_ref(ld)
        # a cell against an atom and against a compound: the cell is bound, the word is the value
        db2, ld2, t2 = _uc_engine(3)
        LK.putSlotValue!(ld2, t2 + 1, _rv(1))
        LK.putSlotValue!(ld2, t2 + 2, _rs("a"))
        LK.putSlotValue!(ld2, t2 + 3, _rf("f", _rg(Int64(1))))
        c = LK.unRef(ld2.slots[t2 + 1])
        args = order == 1 ? (-(t2 + 1), -(t2 + 2)) : (-(t2 + 2), -(t2 + 1))
        @test LK.do_unify_cells(ld2, args...) == LK.BOOLEX_TRUE
        @test LK.isAtomW(ld2.gstack[c]) &&
            lk_eq(LK.resolve_term(ld2, LK.slotValue(ld2, t2 + 1)), _rs("a"))
        LK.putSlotValue!(ld2, t2 + 1, _rv(2))
        c = LK.unRef(ld2.slots[t2 + 1])
        args = order == 1 ? (-(t2 + 1), -(t2 + 3)) : (-(t2 + 3), -(t2 + 1))
        @test LK.do_unify_cells(ld2, args...) == LK.BOOLEX_TRUE
        @test LK._is_gcompound(ld2.gstack[c]) && ld2.gstack[c] == ld2.slots[t2 + 3]   # the SAME compound word
        @test _uc_no_local_ref(ld2)
    end
end

# the rules differential: the head path (H_VAR, a variable's second occurrence) and the body path
_uc_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("same", _rv(1), _rv(1)), nothing),                               # same(X, X).
    (_rf("u_aa", _rv(9)), _rf("=", _rs("a"), _rs("a"))),                   # u_aa(_) :- a = a.
    (_rf("u_ab", _rv(9)), _rf("=", _rs("a"), _rs("b"))),                   # fails
    (_rf("u_af", _rv(9)), _rf("=", _rs("a"), _rf("f", _rs("a")))),         # fails
    (_rf("u_11", _rv(9)), _rf("=", _rg(Int64(1)), _rg(Int64(1)))),         # 1 = 1
    (_rf("u_1f", _rv(9)), _rf("=", _rg(Int64(1)), _rg(1.0))),              # 1 = 1.0 FAILS (SWI's identity)
    (_rf("u_vv", _rv(1), _rv(2)), _rf("=", _rv(1), _rv(2))),               # u_vv(X, Y) :- X = Y.
    (_rf("u_vc", _rv(1)), _rf("=", _rv(1), _rg(Int64(7)))),                # u_vc(X) :- X = 7.
    (_rf("u_cv", _rv(1)), _rf("=", _rg(Int64(7)), _rv(1))),                # u_cv(X) :- 7 = X.
    (
        _rf("u_ff", _rv(1), _rv(2)),
        _rf("=", _rf("f", _rv(1), _rs("b")), _rf("f", _rs("a"), _rv(2)))
    ),
    (_rf("u_fg", _rv(9)), _rf("=", _rf("f", _rs("a")), _rf("g", _rs("a")))),           # fails
    (_rf("u_f12", _rv(9)), _rf("=", _rf("f", _rs("a")), _rf("f", _rs("a"), _rs("b")))), # fails
    (
        _rf("u_part", _rv(1)),
        _rf("=", _rf("f", _rv(1), _rs("b")), _rf("f", _rs("a"), _rs("c")))
    ), # fails after X = a
    (
        _rf("c_ok", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("f", _rv(1))), _rf("=", _rv(2), _rf("f", _rv(2))),
            _rf("=", _rv(1), _rv(2)))
    ),                                       # X = f(X), Y = f(Y), X = Y
    (
        _rf("c_no", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("f", _rv(1), _rs("a"))),
            _rf("=", _rv(2), _rf("f", _rv(2), _rs("b"))), _rf("=", _rv(1), _rv(2)))
    ),   # fails
    (
        _rf("c_list", _rv(1)),
        _rconj(_rf("=", _rv(1), _rlist(_rg(Int64(1)), _rv(2))),
            _rf("=", _rv(2), _rlist(_rg(Int64(2)), _rg(Int64(3)))))
    )          # X = [1|Y], Y = [2, 3]
]

@testset "the simple cases and compounds, as swipl: the head path and the body path" begin
    db = _rdb(_uc_clauses())
    goals = _R[
        _rf("same", _rs("a"), _rv(50)), _rf("same", _rv(50), _rs("a")),             # H_VAR: a cell against an atom
        _rf("same", _rf("f", _rv(51)), _rv(50)), _rf("same", _rv(50), _rf("f", _rv(51))),   # … against a compound
        _rf("same", _rf("f", _rg(Int64(1))), _rf("f", _rv(50))),                     # H_VAR: compound against compound
        _rf("same", _rf("f", _rs("a")), _rf("g", _rs("a"))),                           # fails
        _rf("same", _rlist(_rg(Int64(1)), _rg(Int64(2))), _rlist(_rv(50), _rv(51))),
        _rf("same", _rg(Int64(1)), _rg(1.0)),                                          # fails: 1 is not 1.0
        _rf("u_aa", _rv(50)), _rf("u_ab", _rv(50)), _rf("u_af", _rv(50)),
        _rf("u_11", _rv(50)),
        _rf("u_1f", _rv(50)), _rf("u_vv", _rv(50), _rv(51)), _rf("u_vv", _rs("x"), _rv(51)),
        _rf("u_vc", _rv(50)), _rf("u_cv", _rv(50)), _rf("u_ff", _rv(50), _rv(51)),
        _rf("u_fg", _rv(50)),
        _rf("u_f12", _rv(50)), _rf("u_part", _rv(50)), _rf("c_ok", _rv(50)),
        _rf("c_no", _rv(50)),
        _rf("c_list", _rv(50))
    ]
    ours = _rlines(db, goals)
    @test ours[1:4] == ["same(a,a) det", "end", "same(a,a) det", "end"]
    if _R_SWIPL
        theirs = _rswipl(_uc_clauses(), goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "a failing argument stops the walk with the earlier bindings in place (upstream's contract)" begin
    db, ld, t = _uc_engine(2)
    X = _rv(1)
    LK.putSlotValue!(ld, t + 1, _rf("f", X, _rs("b")))
    LK.putSlotValue!(ld, t + 2, _rf("f", _rs("a"), _rs("c")))
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 2)) == LK.BOOLEX_FALSE
    # X's cell holds `a`: not undone by do_unify itself (the put compound's first argument cell
    # references X's own cell, as the import lays out a live variable: dereference the location)
    p = LK.valPtr(ld.slots[t + 1])
    k, w, _ = LK._deref_loc(ld, p + 1)
    @test k == LK.DU_WORD && LK.isAtomW(w) &&
        lk_eq(LK.resolve_term(ld, LK.slotValue(ld, t + 1)), _rf("f", _rs("a"), _rs("b")))
    # different functors, different arities: false, nothing bound
    db2, ld2, t2 = _uc_engine(3)
    LK.putSlotValue!(ld2, t2 + 1, _rf("f", _rv(1)))
    LK.putSlotValue!(ld2, t2 + 2, _rf("g", _rs("a")))
    LK.putSlotValue!(ld2, t2 + 3, _rf("f", _rs("a"), _rs("b")))
    @test LK.do_unify_cells(ld2, -(t2 + 1), -(t2 + 2)) == LK.BOOLEX_FALSE
    @test LK.do_unify_cells(ld2, -(t2 + 1), -(t2 + 3)) == LK.BOOLEX_FALSE
    @test LK._deref_loc(ld2, LK.valPtr(ld2.slots[t2 + 1]) + 1)[1] == LK.DU_CELL   # still unbound
end

"The functor words at every compound position of the global stack (a reference there is a cycle link left behind)."
_uc_functor_cells(ld) =
    Dict(p => ld.gstack[p] for p in 1:(ld.gTop) if LK.isFunctor(ld.gstack[p]))

@testset "cycles: rational trees terminate, and every functor cell is restored (exitCyclic)" begin
    db, ld, t = _uc_engine(2)
    X, Y = _rv(1), _rv(2)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, t + 1, X, pvm)
    LK.putSlotValue!(ld, t + 2, _rf("f", X), pvm)                 # X = f(X)
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 2)) == LK.BOOLEX_TRUE
    u = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, u + 1, Y, pvm)
    LK.putSlotValue!(ld, u + 2, _rf("f", Y), pvm)                 # Y = f(Y)
    @test LK.do_unify_cells(ld, -(u + 1), -(u + 2)) == LK.BOOLEX_TRUE
    before = _uc_functor_cells(ld)
    @test LK.do_unify_cells(ld, -(t + 1), -(u + 1)) == LK.BOOLEX_TRUE   # X = Y: terminates
    @test isempty(ld.cycle_cells) && isempty(ld.cycle_saved)
    @test _uc_functor_cells(ld) == before                          # no link left behind
    # X = f(X, a), Y = f(Y, b): fails, functor cells restored
    db2, ld2, t2 = _uc_engine(4)
    pvm2 = LK.PutVarMap()
    LK.putSlotValue!(ld2, t2 + 1, X, pvm2)
    LK.putSlotValue!(ld2, t2 + 2, _rf("f", X, _rs("a")), pvm2)
    LK.putSlotValue!(ld2, t2 + 3, Y, pvm2)
    LK.putSlotValue!(ld2, t2 + 4, _rf("f", Y, _rs("b")), pvm2)
    @test LK.do_unify_cells(ld2, -(t2 + 1), -(t2 + 2)) == LK.BOOLEX_TRUE
    @test LK.do_unify_cells(ld2, -(t2 + 3), -(t2 + 4)) == LK.BOOLEX_TRUE
    before2 = _uc_functor_cells(ld2)
    @test LK.do_unify_cells(ld2, -(t2 + 1), -(t2 + 3)) == LK.BOOLEX_FALSE
    @test isempty(ld2.cycle_cells) && _uc_functor_cells(ld2) == before2
end

@testset "Q2: a compound with a variable head unifies child by child (kernel-only)" begin
    # KNOWN DIFFERENCE, pinned (user, 2026-10-04): swipl cannot read `(X a)`; the kernel's `$expr/n`
    # unifies with any compound of n children, heads included
    X = _rv(1)
    for order in (1, 2)
        db, ld, t = _uc_engine(2)
        LK.putSlotValue!(ld, t + 1, mk_expr(_R, _R[X, _rs("a")]))      # (X a)
        LK.putSlotValue!(ld, t + 2, _rf("f", _rs("a")))                # f(a)
        args = order == 1 ? (-(t + 1), -(t + 2)) : (-(t + 2), -(t + 1))
        @test LK.do_unify_cells(ld, args...) == LK.BOOLEX_TRUE
        r = LK.resolve_term(ld, LK.slotValue(ld, t + 1))
        @test kind(r) === EXPR && lk_eq(child(r, 1), _rs("f")) &&
            lk_eq(child(r, 2), _rs("a"))
        @test isempty(ld.cycle_cells) && _uc_no_local_ref(ld)
    end
    db, ld, t = _uc_engine(3)
    LK.putSlotValue!(ld, t + 1, mk_expr(_R, _R[X, _rs("a")]))
    LK.putSlotValue!(ld, t + 2, _rf("f", _rs("a"), _rs("b")))          # (X a) = f(a, b): fails
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 2)) == LK.BOOLEX_FALSE
    LK.putSlotValue!(ld, t + 3, _rlist(_rs("a"), _rs("b")))            # [a, b] = '[|]'(a, [b])
    LK.putSlotValue!(ld, t + 1, mk_expr(_R, _R[_rv(2), _rs("a"), _rv(3)]))   # (Y a Z): a $expr/3
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 3)) == LK.BOOLEX_TRUE
    r = LK.resolve_term(ld, LK.slotValue(ld, t + 1))
    @test lk_eq(child(r, 1), _rs("[|]")) && lk_eq(child(r, 3), _rlist(_rs("b")))
end

@testset "the boundary: a keyed variable on either side is bound on terms" begin
    db, ld, t = _uc_engine(3)
    kv = lk_var(_R, UInt64(4242))                                  # a KEYED variable: no cell
    LK.setSlotValue!(ld, t + 1, kv)                                # a slot's side value
    LK.putSlotValue!(ld, t + 2, _rs("a"))
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 2)) == LK.BOOLEX_TRUE
    @test lk_eq(LK.deRef(ld, kv), _rs("a"))                        # bound in the store
    m = LK.Mark(ld)
    LK.setSlotValue!(ld, t + 1, lk_var(_R, UInt64(4243)))
    LK.putSlotValue!(ld, t + 3, _rf("f", _rv(1)))
    @test LK.do_unify_cells(ld, -(t + 3), -(t + 1)) == LK.BOOLEX_TRUE   # a compound against a keyed variable
    @test lk_eq(LK.resolve_term(ld, LK.deRef(ld, lk_var(_R, UInt64(4243)))),
        LK.resolve_term(ld, LK.slotValue(ld, t + 3)))
    LK.Undo!(ld, m)
    # a cell bound to a keyed variable: a value-table word; unified with an atom, the keyed variable is bound
    LK.putSlotValue!(ld, t + 1, _rv(7))
    LK.Trail!(ld, var_key(LK.slotValue(ld, t + 1)), lk_var(_R, UInt64(4244)))
    LK.putSlotValue!(ld, t + 2, _rs("b"))
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 2)) == LK.BOOLEX_TRUE
    @test lk_eq(LK.deRef(ld, lk_var(_R, UInt64(4244))), _rs("b"))
end

@testset "the meter: a head unification of a list makes no cold export" begin
    db = _rdb(_uc_clauses())
    ld = db.ld
    goal = _rf("same", _rlist(_rg(Int64(1)), _rg(Int64(2)), _rg(Int64(3))), _rv(50))
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, args + 1, child(goal, 2))
    LK.putSlotValue!(ld, args + 2, child(goal, 3))
    e0 = ld.cold_exports
    qid = LK.PL_open_query(
        db.gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, goal), args
    )
    rc = LK.PL_next_solution(db.gd, ld, qid)
    @test rc == LK.PL_S_LAST
    @test ld.cold_exports == e0                                    # H_VAR unified on the cells
    @test ld.slots[args + 2] == ld.slots[args + 1] ||              # R references the list itself …
        (
        LK.isRef(ld.slots[args + 2]) &&
        ld.gstack[LK.unRef(ld.slots[args + 2])] == ld.slots[args + 1]
    )
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
end
