# ORIGINAL: L1c sub-commit 5 — first-argument indexing from WORDS (src/pl-index.jl `_argv_key`,
# `_argv_is_var`, `_descend_first_clause!`, the cell argv `argv_cells`); upstream has no separate test
# (pl-index.c's `indexOfWord` reads the cell, as the kernel now does). test/core_lang/test_index_words.jl
# — white-box, on every term type:
#   * the KEY on the words equals `indexOfWord` of the term the word stands for, for every word form a
#     frame argument can hold: an atom (text and reserved `[]`), a compound (symbol head, `[|]/2`, a
#     `$expr/n` wildcard), a value-table value (integer, float, string), an unbound cell (0), and the
#     boundary (a keyed variable bound, and unbound); a reference chain is followed;
#   * `_argv_is_var` on the same forms;
#   * the deep descent reads the ARGUMENT CELLS of a compound word (`argv_cells`): their keys equal the
#     term's children's;
#   * the meter: a call selected through a deep (second-level) index makes NO cold export, and its
#     answers are swipl's.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"A fresh engine, a foreign frame and one term reference per value of `vs`, each put; `(ld, t)`."
function _iw_engine(vs::Vector{_R})
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v)
    end
    return ld, t
end

const _IW_VALUES = _R[
    _rs("a"), _rnil(), _rs("[]"), _rg(Int64(7)), _rg(2.5), _rg("str"),
    _rf("f", _rs("a")), _rf("f", _rv(1), _rs("b")), _rlist(_rs("a"), _rs("b")),
    _rf("[|]", _rs("a"), _rs("b")), mk_expr(_R, _R[_rv(2), _rs("a")]),
    _rf("g", _rf("h", _rg(Int64(1))))
]

@testset "the key on the words is indexOfWord's key of the term" begin
    ld, t = _iw_engine(_IW_VALUES)
    av = LK.argv_frame(ld, t)
    for (i, v) in enumerate(_IW_VALUES)
        @test LK._argv_key(av, i - 1) ==
            LK.indexOfWord(LK.resolve_term(ld, LK.slotValue(ld, t + i)))
        @test LK._argv_key(av, i - 1) == LK.indexOfWord(v)
        @test !LK._argv_is_var(av, i - 1)
    end
    # [] and '[]' key apart (a reserved symbol and a text atom), as the term keys do
    @test LK._argv_key(av, 1) != LK._argv_key(av, 2)
    # `$expr/n` is a wildcard: key 0, yet not a variable
    @test LK._argv_key(av, 10) == 0
end

@testset "an unbound cell, a reference chain, and the boundary (keyed variables)" begin
    ld, t = _iw_engine(_R[_rv(1), _rv(2), _rs("x")])
    av = LK.argv_frame(ld, t)
    @test LK._argv_key(av, 0) == 0 && LK._argv_is_var(av, 0)
    # a reference chain: cell 2 bound to cell 1 (the higher to the lower), cell 1 then to an atom
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 2)) == LK.BOOLEX_TRUE
    @test LK._argv_is_var(av, 1)
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 3)) == LK.BOOLEX_TRUE
    @test LK._argv_key(av, 1) == LK.indexOfWord(_rs("x")) && !LK._argv_is_var(av, 1)
    # the boundary: a keyed variable in a slot's side value, unbound then bound
    kv = lk_var(_R, UInt64(4711))
    LK.setSlotValue!(ld, t + 1, kv)
    @test LK._argv_is_var(av, 0) && LK._argv_key(av, 0) == 0
    LK.Trail!(ld, var_key(kv), _rf("f", _rs("a")))
    @test !LK._argv_is_var(av, 0) &&
        LK._argv_key(av, 0) == LK.indexOfWord(_rf("f", _rs("a")))
end

@testset "the deep descent reads a compound's argument cells" begin
    v = _rf("p", _rf("g", _rs("a")), _rg(Int64(3)), _rlist(_rs("b")))
    ld, t = _iw_engine(_R[v])
    w = ld.slots[t + 1]
    @test LK._is_gcompound(w)
    ac = LK.argv_cells(ld, LK.valPtr(w))
    for i in 0:2
        @test LK._argv_key(ac, i) == LK.indexOfWord(child(v, i + 2))
        @test !LK._argv_is_var(ac, i)
    end
    # one level further: the cells of `g(a)`
    k, gw, _ = LK._deref_loc(ld, LK._argv_loc(ac, 0))
    @test k == LK.DU_WORD && LK._is_gcompound(gw)
    @test LK._argv_key(LK.argv_cells(ld, LK.valPtr(gw)), 0) == LK.indexOfWord(_rs("a"))
end

# a predicate whose first argument is a compound, selected through the second-level index
_iw_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("iw_p", _rf("f", _rs("a")), _rs("one")), nothing),
    (_rf("iw_p", _rf("f", _rs("b")), _rs("two")), nothing),
    (_rf("iw_p", _rf("g", _rs("a")), _rs("three")), nothing),
    (_rf("iw_p", _rf("f", _rs("c")), _rs("four")), nothing),
    (_rf("iw_p", _rf("f", _rs("b")), _rs("five")), nothing)
]

@testset "the meter: a deep-indexed call makes no cold export, its answers swipl's" begin
    db = _rdb(_iw_clauses())
    ld = db.ld
    goals = _R[_rf("iw_p", _rf("f", _rs("b")), _rv(9)),
        _rf("iw_p", _rf("g", _rv(8)), _rv(9)),
        _rf("iw_p", _rv(7), _rs("four"))]
    ours = _rlines(db, goals)                           # (this run also builds the indexes)
    @test [replace(l, r" (det|nondet)$" => "") for l in ours[1:3]] ==
        ["iw_p(f(b),two)", "iw_p(f(b),five)", "end"]    # (determinism: from swipl, below)
    if _R_SWIPL
        @test ours == _rswipl(_iw_clauses(), goals)
    elseif _R_SWIPL_REQUIRED
        @test false
    end
    # the search alone: open the query on the frame and step it, no copy-out
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, _rf("f", _rs("b")))
    LK.putSlotValue!(ld, a + 2, _rv(9))
    e3, i3 = ld.cold_exports, ld.cold_imports
    qid = LK.PL_open_query(db.gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS,
        _rproc(db, goals[1]), a)
    n = 0
    while true
        rc = LK.PL_next_solution(db.gd, ld, qid)
        (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
        n += 1
        rc == LK.PL_S_LAST && break
    end
    @test n == 2
    @test ld.cold_exports == e3                         # the index read words: no export…
    @test ld.cold_imports == i3                         # …and no import (the boundary is cold)
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "a compound at the boundary descends through a counted import onto the stack" begin
    # a keyed variable bound to a compound TERM: the descent puts it onto the stack (the cold import,
    # counted) and walks its cells — the frame form never descends into a term argv
    db = _rdb(_iw_clauses())
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 2)
    kv = lk_var(_R, UInt64(4712))
    LK.setSlotValue!(ld, t + 1, kv)
    LK.Trail!(ld, var_key(kv), _rf("f", _rs("b")))
    LK.putSlotValue!(ld, t + 2, _rv(9))
    @test LK._argv_key(LK.argv_frame(ld, t), 0) == LK.indexOfWord(_rf("f", _rs("b")))
    i0 = ld.cold_imports
    qid = LK.PL_open_query(db.gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS,
        _rproc(db, _rf("iw_p", _rv(1), _rv(2))), t)
    out = String[]
    while true
        rc = LK.PL_next_solution(db.gd, ld, qid)
        (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
        push!(out, _rcanonical(LK.resolve_term(ld, LK.slotValue(ld, t + 2))))
        rc == LK.PL_S_LAST && break
    end
    @test out == ["two", "five"]
    @test ld.cold_imports > i0                          # the descent imported: COUNTED, cold
    @test LK.deRef(ld, kv) === _rf("f", _rs("b")) ||        # the frame's own argument untouched:
        lk_eq(LK.resolve_term(ld, LK.deRef(ld, kv)), _rf("f", _rs("b")))   # the copy was only read
    LK.PL_close_query(ld, qid)
end
