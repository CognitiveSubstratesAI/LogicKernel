# ORIGINAL: findall/3,4 (V9g-b) — the bags of pl-bag.c under boot/bags.pl's clauses — against a LIVE swipl; upstream's tests of findall/3 are in tests/core_lang/test_bags.pl, mirrored when plunit runs (R2), so this file shadows no upstream path.
# test/core_lang/test_findall_swipl.jl — pl-bag.c '$new_findall_bag'/0, '$add_findall_bag'/1,2, '$collect_findall_bag'/2, '$destroy_findall_bag'/0; pl-rec.c compileTermToHeap, copyRecordToGlobal, the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# Every case is a predicate `fN/1`; the differential compares its answers and their determinism.
const _RFA_N = 41
function _rfa_clauses()
    X, Y, Z, L, M, E, A, B, C, N = (_rv(i) for i in 1:10)
    O, P, T = _rv(11), _rv(12), _rv(13)
    fa(t, g, l) = _rf("findall", t, g, l)
    fa4(t, g, l, tl) = _rf("findall", t, g, l, tl)
    c3(g, k, r) = _rf("catch", g, k, r)
    eq(a, b) = _rf("=", a, b)
    pair(a, b) = _rf("-", a, b)
    T_ = _rs("true")
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("p", _rg(1)), nothing), (_rf("p", _rg(2)), nothing),
        (_rf("p", _rg(3)), nothing),
        (_rf("q", _rg(1), _rs("a")), nothing), (_rf("q", _rg(2), _rs("b")), nothing),
        (_rf("q", _rg(1), _rs("c")), nothing),
        (_rf("mem", X, _rcons(X, Y)), nothing),
        (_rf("mem", X, _rcons(Y, Z)), _rf("mem", X, Z)),
        (_rf("gen", X, Y, X), _rf("=<", X, Y)),
        (
            _rf("gen", X, Y, Z),
            _rconj(_rf("<", X, Y), _rf("is", A, _rf("+", X, _rg(1))), _rf("gen", A, Y, Z))
        ),
        (_rf("len", _rnil(), _rg(0)), nothing),
        (
            _rf("len", _rcons(X, Y), N),
            _rconj(_rf("len", Y, M), _rf("is", N, _rf("+", M, _rg(1))))
        ),
        (_rf("last", _rcons(X, _rnil()), X), nothing),
        (_rf("last", _rcons(X, _rcons(Y, Z)), A), _rf("last", _rcons(Y, Z), A)),
        # ── the answers, in order ──
        (_rf("f1", L), fa(X, _rf("p", X), L)),
        (_rf("f2", L), fa(X, _rs("fail"), L)),                              # none: []
        (_rf("f3", L), fa(pair(X, Y), _rf("q", X, Y), L)),
        (_rf("f4", L), fa(Y, _rf("q", _rg(1), Y), L)),
        (_rf("f5", L), fa(X, _rconj(_rf("p", X), _rf(">", X, _rg(1))), L)),
        # ── variables: fresh in every answer, shared inside one, never bound outside ──
        (_rf("f6", L), fa(_rf("f", X, Y, X), _rf("p", Y), L)),
        (_rf("f7", pair(L, Z)), fa(Z, _rf("p", X), L)),
        (_rf("f8", pair(L, X)), fa(X, _rf("p", X), L)),                     # X stays unbound
        (_rf("f9", L), _rconj(eq(Y, _rf("g", Z)), fa(pair(Y, Z), T_, L))),  # [g(A)-A]
        (_rf("f10", L), _rconj(eq(Y, _rf("g", Z)), eq(Z, _rg(1)), fa(Y, T_, L))),
        (_rf("f11", L), fa(X, _rf("mem", X, _rlist(Y, _rf("h", Z, Z), Y, _rg(1.5))), L)),
        # ── nested, and backtracked over ──
        (_rf("f12", L), fa(pair(X, M), _rconj(_rf("p", X), fa(Y, _rf("q", X, Y), M)), L)),
        (
            _rf("f13", pair(X, L)),
            _rconj(_rf("p", X), fa(Y, _rconj(_rf("p", Y), _rf(">=", Y, X)), L))
        ),
        # ── findall/4, and a list that is bound already ──
        (_rf("f14", L), fa4(X, _rf("p", X), L, _rlist(_rs("a"), _rs("b")))),
        (_rf("f15", L), fa4(X, _rf("p", X), L, T)),                         # a partial list
        (_rf("f16", L), fa4(X, _rs("fail"), L, _rs("tail"))),               # the tail itself
        (_rf("f17", X), fa(X, _rf("p", X), _rints(1:3))),
        (_rf("f18", X), fa(X, _rf("p", X), _rints(1:2))),                   # fails
        (_rf("f19", pair(A, B)), fa(X, _rf("p", X), _rcons(A, B))),
        (_rf("f20", X), fa(X, _rf("p", X), _rs("foo"))),                    # fails: no type check
        # ── the goal: control, cut, exceptions, errors ──
        (_rf("f21", L), fa(X, _rconj(_rf("p", X), _rs("!")), L)),           # the cut is local
        (_rf("f22", L), fa(X, _ror(_rf("p", X), eq(X, _rs("z"))), L)),
        (_rf("f23", L), fa(X, _rite(_rf("p", X), T_, eq(X, _rs("none"))), L)),
        (_rf("f24", L), fa(X, _rconj(_rf("p", X), _rnot(eq(X, _rg(2)))), L)),
        (
            _rf("f25", pair(E, L)),         # a ball out of the goal: the bag is closed
            _rconj(
                c3(
                    fa(
                        X,
                        _rconj(_rf("p", X), _rf(">", X, _rg(1)), _rf("throw", _rs("b"))),
                        M
                    ),
                    E,
                    T_
                ),
                fa(Y, _rf("p", Y), L)
            )
        ),
        (_rf("f26", E), c3(fa(X, Y, L), _rf("error", E, Z), T_)),           # an unbound goal
        (_rf("f27", E), c3(fa(X, _rg(1), L), _rf("error", E, Z), T_)),      # not callable
        (
            _rf("f28", E),
            c3(fa(X, _rconj(_rf("p", X), _rg(1)), L), _rf("error", E, Z), T_)
        ),
        (_rf("f29", L), fa(X, _rf(":", _rs("user"), _rf("p", X)), L)),
        # ── many answers ──
        (
            _rf("f30", pair(N, X)),
            _rconj(
                fa(Y, _rf("gen", _rg(1), _rg(300), Y), L),
                _rf("len", L, N),
                _rf("last", L, X)
            )
        ),
        # ── a rational tree is recorded as one ──
        (_rf("f31", L), _rconj(eq(X, _rf("f", X)), fa(X, T_, L))),
        (
            _rf("f32", N),
            _rconj(
                eq(X, _rf("f", X, Y)), fa(X, T_, _rlist(A)), eq(A, _rf("f", B, C)),
                eq(B, _rf("f", M, O)),
                _rite(_rf("==", C, O), eq(N, _rs("one_variable")), eq(N, _rs("two")))
            )
        ),
        # ── the standard order of the fresh variables is the order of upstream's cells (the list is
        # unified with the pattern AFTER findall/3: unified with older variables, the fresh ones
        # would be bound to those, and the order compared would be theirs) ──
        (
            _rf("f33", O),                  # the outer compound's cells come first
            _rconj(
                fa(_rf("f", _rf("g", X), Y), T_, L),
                eq(L, _rlist(_rf("f", _rf("g", A), B))),
                _rf("compare", O, A, B)
            )
        ),
        (
            _rf("f34", pair(O, P)),         # the LAST answer is put back first
            _rconj(
                fa(X, _rf("p", Y), L), eq(L, _rlist(A, B, C)), _rf("compare", O, A, B),
                _rf("compare", P, B, C)
            )
        ),
        (
            _rf("f35", O),                  # a variable lives in its lowest cell
            _rconj(
                fa(_rf("f", _rf("g", Y, X), X, Y), T_, L),
                eq(L, _rlist(_rf("f", _rf("g", A, B), C, N))), _rf("compare", O, A, B)
            )
        ),
        # ── the primitives ──
        (
            _rf("f36", _rf("r", L, A, B)),
            _rconj(
                _rs("\$new_findall_bag"), _rf("\$add_findall_bag", _rs("a"), A),
                _rf("\$add_findall_bag", _rf("f", X), B),
                _rf("\$collect_findall_bag", L, _rlist(_rs("t"))),
                _rs("\$destroy_findall_bag")
            )
        ),
        (
            _rf("f37", L),                  # nothing added: the tail
            _rconj(
                _rs("\$new_findall_bag"), _rf("\$collect_findall_bag", L, _rs("tail")),
                _rs("\$destroy_findall_bag")
            )
        ),
        (_rf("f38", E), c3(_rf("\$add_findall_bag", _rs("x")), E, T_)),     # no bag
        (
            _rf("f39", O),                  # a nested compound's variables come before ITS compounds'
            _rconj(
                fa(_rf("f", _rf("g", _rf("h", X), Y)), T_, L),
                eq(L, _rlist(_rf("f", _rf("g", _rf("h", A), B)))), _rf("compare", O, A, B)
            )
        ),
        (                                   # a cyclic answer (L1f f1a: PL_REC_CYCLE); swipl: yes
            _rf("f40", O),
            _rconj(
                eq(C, _rcons(_rs("a"), C)), fa(C, T_, _rlist(A)),
                _rf(";", _rf("->", _rf("==", A, C), eq(O, _rs("yes"))), eq(O, _rs("no")))
            )
        ),
        (                                   # X met first inside g/1, then lower in f/3: it lives in
            _rf("f41", O),                  # the LOWER cell (copy_record's move); swipl: <
            _rconj(
                fa(_rf("f", _rf("g", X), X, Y), T_, L),
                eq(L, _rlist(_rf("f", Z, A, B))), _rf("compare", O, A, B)
            )
        )
    ]
end

_rfa_goals() = _R[_rf("f$k", _rv(50 + k)) for k in 1:_RFA_N]

"The kernel's lines for `goals`: the pools checked, no exception pending and no bag open at every answer."
function _rfa_ours(clauses, goals)
    db = _rdb(clauses)
    ours = String[]
    for g in goals
        for (a, det) in _rcall(
            db,
            g;
            at=(qid, k) -> (@test _rpools_live(db.ld) && db.ld.exception_term == 0 &&
                isempty(db.ld.bags))
        )
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
        @test isempty(db.ld.bags)                   # … and none after a failure or an error
    end
    return ours, db
end

@testset "findall/3,4: answers and determinism equal swipl's" begin
    clauses = _rfa_clauses()
    goals = _rfa_goals()
    ours, db = _rfa_ours(clauses, goals)
    @test count(==("end"), ours) == length(goals)
    @test "f1([1,2,3]) det" in ours
    @test "f2([]) det" in ours
    @test "f6([f(A,1,A),f(B,2,B),f(C,3,C)]) det" in ours
    @test "f25(-(b,[1,2,3])) det" in ours
    @test "f30(-(300,300)) det" in ours
    @test count(==("cyclic det"), ours) == 1         # f31: a rational tree, as the driver writes one
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            for k in 1:max(length(ours), length(theirs))
                get(ours, k, "—") == get(theirs, k, "—") && continue
                println(stderr, "  line ", k, "\n    kernel ", get(ours, k, "—"),
                    "\n    swipl  ", get(theirs, k, "—"))
            end
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# White box: the records (pl-rec.c, L1f f1a). `gsize` is exactly the cells `copyRecordToGlobal` lays
# out; a compound met twice is recorded once (`PL_REC_CYCLE`) and is ONE compound in the copy, as
# swipl's (`same_term/2`, probed 2026-10-19: `Z = h(_), findall(g(Z,Z), true, [g(P,Q)]),
# same_term(P,Q)` true; `C = [a|C], findall(C, true, [D]), D = [_|E], same_term(D,E)` true); the
# visited marks are restored; a record survives the undoing of the bindings it was made under; each
# copy has fresh variables. Terms laid out on cells by hand (no `same_term/2` before f1c).
_rec_fw(ld, name, n) = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs(name)), n)
_rec_gw(p) = LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
_rec_aw(ld, name) = LK._atom_word!(ld, _rs(name))
"Lay compound `name/length(args)` out, argument `i` the word `args[i]` (0: unbound); its position."
function _rec_lay!(ld, name, args...)
    p = LK._alloc_compound!(ld, _rec_fw(ld, name, length(args)), length(args))
    for (i, w) in enumerate(args)
        ld.gstack[p + i] = w
    end
    return p
end
"A list cell `[h|t]` laid out; its position."
function _rec_cons!(ld, h, t)
    p = LK._alloc_compound!(ld, ld.functor_dot2, 2)
    ld.gstack[p + 1] = h
    ld.gstack[p + 2] = t
    return p
end
"Record the word `w` from a fresh slot and copy it back: (record, cells laid, the copy's slot)."
function _rec_round(ld, w)
    t = LK.PL_new_term_ref(ld)
    ld.slots[t + 1] = w
    r = LK.compileTermToHeap(ld, t)
    out = LK.PL_new_term_ref(ld)
    g0 = ld.gTop
    @test LK.copyRecordToGlobal(ld, out, r)
    return r, ld.gTop - g0, out
end
_rec_out(ld, out) = _rcanonical(LK.resolve_term(ld, LK.slotValue(ld, out + 1)))

@testset "records: gsize, sharing, cycles, variables, values, the boundary (L1f f1a)" begin
    db = _RDB()
    ld = db.ld
    fid = LK.PL_open_foreign_frame(ld)
    # a compound met twice: recorded once, one compound in the copy (5 cells, not 7)
    ph = _rec_lay!(ld, "h", 0)
    pg = _rec_lay!(ld, "g", _rec_gw(ph), _rec_gw(ph))
    r, used, out = _rec_round(ld, _rec_gw(pg))
    @test r.gsize == 5 && used == 5 && r.nvars == 1 && r.term === nothing
    q = LK.valPtr(ld.slots[out + 1])
    @test ld.gstack[q + 1] == ld.gstack[q + 2] != _rec_gw(ph)          # same_term(P, Q), a new h/1
    @test ld.gstack[LK.valPtr(ld.gstack[q + 1]) + 1] == 0               # its argument unbound
    @test ld.gstack[ph] == _rec_fw(ld, "h", 1) && ld.gstack[pg] == _rec_fw(ld, "g", 2)   # unvisit
    @test ld.gstack[ph + 1] == 0                                        # restoreVars
    # a list: 3 cells per cell
    pl = _rec_cons!(ld, _rec_aw(ld, "a"),
        _rec_gw(
            _rec_cons!(
                ld,
                _rec_aw(ld, "b"),
                _rec_gw(_rec_cons!(ld, _rec_aw(ld, "c"), ld.atom_nil_w))
            )
        ))
    r, used, out = _rec_round(ld, _rec_gw(pl))
    @test r.gsize == 9 && used == 9 && r.nvars == 0 &&
        _rec_out(ld, out) == "[a,b,c]"
    # a cyclic list C = [a|C]: one cell, its tail the copy itself
    pc = _rec_cons!(ld, _rec_aw(ld, "a"), 0)
    ld.gstack[pc + 2] = _rec_gw(pc)
    r, used, out = _rec_round(ld, _rec_gw(pc))
    q = LK.valPtr(ld.slots[out + 1])
    @test r.gsize == 3 && used == 3 && ld.gstack[q + 2] == _rec_gw(q) &&
        ld.gstack[pc] == ld.functor_dot2
    # f(X, Y, X): two variables, X's second occurrence a reference to its first cell
    pf = _rec_lay!(ld, "f", 0, 0, 0)
    ld.gstack[pf + 3] = LK.makeRefG(pf + 1)
    r, used, out = _rec_round(ld, _rec_gw(pf))
    q = LK.valPtr(ld.slots[out + 1])
    @test r.gsize == 4 && used == 4 && r.nvars == 2
    @test ld.gstack[q + 1] == 0 && ld.gstack[q + 2] == 0 &&
        ld.gstack[q + 3] == LK.makeRefG(q + 1)
    @test ld.gstack[pf + 1] == 0 && ld.gstack[pf + 2] == 0 &&
        ld.gstack[pf + 3] == LK.makeRefG(pf + 1)
    # f(g(X), X): X met first in g/1 (laid above f/2's cells), then in f/2's second cell — the
    # variable moves to the LOWER cell (copy_record's "wrong way"), g/1's argument references it
    pgx = _rec_lay!(ld, "g", 0)
    pf = _rec_lay!(ld, "f", _rec_gw(pgx), LK.makeRefG(pgx + 1))
    r, used, out = _rec_round(ld, _rec_gw(pf))
    q = LK.valPtr(ld.slots[out + 1])
    qg = LK.valPtr(ld.gstack[q + 1])
    @test r.gsize == 5 && used == 5 && r.nvars == 1 && qg > q + 2
    @test ld.gstack[q + 2] == 0 && ld.gstack[qg + 1] == LK.makeRefG(q + 2)
    # a value-table word: recorded as its value, put back boxed in the block (2 + 1 cells)
    pv = _rec_lay!(ld, "f", LK._vword!(ld, _rg(1.5)))
    r, used, out = _rec_round(ld, _rec_gw(pv))
    q = LK.valPtr(ld.slots[out + 1])
    w = ld.gstack[q + 1]
    @test r.gsize == 3 && used == 3 && length(r.values) == 1
    @test LK._is_vword(w) && ld.vbox[LK.valPtr(w)] == q + 2 && _rec_out(ld, out) == "f(1.5)"
    # roots: a value (its box), a variable (its cell), an atom (nothing), a small integer (nothing)
    r, used, out = _rec_round(ld, LK._vword!(ld, _rg(2.5)))
    @test r.gsize == 1 && used == 1 && _rec_out(ld, out) == "2.5"
    pv = LK.allocGlobalCells!(ld, 1)
    r, used, out = _rec_round(ld, LK.makeRefG(pv))
    @test r.gsize == 1 && used == 1 && r.nvars == 1
    @test LK.isRef(ld.slots[out + 1]) && LK.unRef(ld.slots[out + 1]) != pv &&
        ld.gstack[LK.unRef(ld.slots[out + 1])] == 0
    r, used, out = _rec_round(ld, _rec_aw(ld, "a"))
    @test r.gsize == 0 && used == 0 && ld.slots[out + 1] == _rec_aw(ld, "a")
    r, used, out = _rec_round(ld, LK.consInt(-1234567))
    @test r.gsize == 0 && used == 0 && ld.slots[out + 1] == LK.consInt(-1234567)
    # a record survives the undoing of the bindings it was made under; each copy is fresh
    pb = _rec_lay!(ld, "f", 0, 0)
    m = LK.Mark(ld)
    LK._bind_const!(ld, pb + 2, _rec_aw(ld, "b"))
    t = LK.PL_new_term_ref(ld)
    ld.slots[t + 1] = _rec_gw(pb)
    r = LK.compileTermToHeap(ld, t)
    LK.Undo!(ld, m)
    @test ld.gstack[pb + 2] == 0                        # the binding undone
    a, b = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK.copyRecordToGlobal(ld, a, r) && LK.copyRecordToGlobal(ld, b, r)
    @test _rec_out(ld, a) == "f(_,b)" && _rec_out(ld, b) == "f(_,b)"
    @test ld.slots[a + 1] != ld.slots[b + 1]              # two copies, two compounds
    # THE BOUNDARY (TRANSITIONAL, F1-Q5): a keyed variable's value-table word — recorded on terms,
    # counted in `cold_pairs`, `gsize` 0
    pk = _rec_lay!(ld, "f", LK._vword!(ld, _rv(77)))
    n0 = ld.cold_pairs
    r, used, out = _rec_round(ld, _rec_gw(pk))
    @test r.term !== nothing && r.gsize == 0 && ld.cold_pairs == n0 + 1
    @test startswith(_rec_out(ld, out), "f(")
    LK.PL_close_foreign_frame(ld, fid)
end

# KNOWN DIFFERENCE, pinned (R2 checklist: "boot/bags.pl in its module `'\$bags'`"):
#   kernel: `context(system:findall_loop/4, _)` — the stand-in's clauses are `system`'s
#   swipl 10.1.18: `context('\$bags':findall_loop/4, _)` (probed)
@testset "an unbound goal: the error's context names the stand-in's module (R2)" begin
    X, Y, L, E = _rv(1), _rv(2), _rv(3), _rv(4)
    db = _rdb([
        (
        _rf("ctx", E),
        _rf("catch", _rf("findall", X, Y, L), _rf("error", _rv(5), E), _rs("true"))
    )
    ])
    @test [a for (a, _) in _rcall(db, _rf("ctx", _rv(51)))] ==
        ["ctx(context(:(system,/(findall_loop,4)),_))"]
end
