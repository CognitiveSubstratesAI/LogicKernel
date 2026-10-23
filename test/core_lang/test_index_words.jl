# ORIGINAL: L1c sub-commit 5 — first-argument indexing from WORDS (src/pl-index.jl `_argv_key`,
# `_argv_is_var`, `_descend_first_clause!`, the cell argv `argv_cells`); upstream has no separate test
# (pl-index.c's `indexOfWord` reads the cell, as the kernel now does). test/core_lang/test_index_words.jl
# — white-box, on every term type:
#   * the KEY on the words equals the key the COMPILER gives the same term as a clause's head argument
#     (`argKey`, read from its head code — upstream's equality: a clause is selected when its key equals
#     the call's), for every word form a frame argument can hold: an atom (text and reserved `[]`), a
#     compound (symbol head, `[|]/2`, a `$expr/n` wildcard), a value-table value (integer, float,
#     string) and an unbound cell (0); a reference chain is followed. The atom, functor, list and
#     tagged-integer keys are also checked against the words themselves (`_atom_word!`,
#     `lookupFunctorDef`, `FUNCTOR_dot2`, `consInt`). (Until 2026-10-23 the cross-check was the TERM's
#     key, the term `indexOfWord`, deleted with the term path: audit D-0121, design Q1 — the compiler's
#     key is an independent derivation, from the clause code.);
#   * an answer exported and put again keys as the word it came from (`ix_key`);
#   * `_argv_is_var` on the same forms;
#   * the deep descent reads the ARGUMENT CELLS of a compound word (`argv_cells`): their keys equal the
#     compiler's for the same head's arguments;
#   * the meter: a call selected through a deep (second-level) index makes NO cold import, and its
#     answers are swipl's.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))   # `ix_key`

"A fresh engine, a foreign frame and one term reference per value of `vs`, each put; `(ld, t, db)`."
function _iw_engine(vs::Vector{_R})
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v)
    end
    return ld, t, db
end

"The keys the compiler gives the arguments of the clause head `h` in `db` (`argKey` of its code, 0-based)."
function _iw_argkeys(db, h::_R)::Vector{LK.word}
    cl = _radd!(db, h)
    return [LK.argKey(LK.Code(cl, 1), i) for i in 0:(nchildren(h) - 2)]
end

const _IW_VALUES = _R[
    _rs("a"), _rnil(), _rs("[]"), _rg(Int64(7)), _rg(2.5), _rg("str"),
    _rf("f", _rs("a")), _rf("f", _rv(1), _rs("b")), _rlist(_rs("a"), _rs("b")),
    _rf("[|]", _rs("a"), _rs("b")), mk_expr(_R, _R[_rv(2), _rs("a")]),
    _rf("g", _rf("h", _rg(Int64(1))))
]

@testset "the key on the words is the compiler's key of the term" begin
    ld, t, db = _iw_engine(_IW_VALUES)
    av = LK.argv_frame(ld, t)
    ck = _iw_argkeys(db, _rf("iw_k", _IW_VALUES...))     # the same terms as one clause's head
    @test length(ck) == length(_IW_VALUES)
    for (i, v) in enumerate(_IW_VALUES)
        @test LK._argv_key(av, i - 1) == ck[i]
        @test LK._argv_key(av, i - 1) == ix_key(ld, lk_answer(ld, t + i - 1))   # exported, put again
        @test !LK._argv_is_var(av, i - 1)
    end
    # the keys ARE the words (pl-index.c `indexOfWord`: `case TAG_ATOM: break`, a compound's functor)
    @test LK._argv_key(av, 0) == LK._atom_word!(ld, _rs("a"))
    @test LK._argv_key(av, 1) == LK.ATOM_nil
    @test LK._argv_key(av, 2) == LK._atom_word!(ld, _rs("[]"))
    ld.int_word_keys && @test LK._argv_key(av, 3) == LK.consInt(7)    # STG_INLINE: the word
    @test LK._argv_key(av, 6) ==
        LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("f")), 1)
    @test LK._argv_key(av, 7) ==
        LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("f")), 2)
    @test LK._argv_key(av, 8) == LK._argv_key(av, 9) == LK.FUNCTOR_dot2
    @test LK._argv_key(av, 11) ==
        LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("g")), 1)
    # a value's key is a hash: neither 0 nor a functor (`_value_index_key`)
    for i in (4, 5)
        @test LK._argv_key(av, i) != 0 && !LK.isFunctor(LK._argv_key(av, i))
    end
    # [] and '[]' key apart (a reserved symbol and a text atom), as the term keys do
    @test LK._argv_key(av, 1) != LK._argv_key(av, 2)
    # `$expr/n` is a wildcard: key 0, yet not a variable
    @test LK._argv_key(av, 10) == 0
end

@testset "an unbound cell and a reference chain" begin
    ld, t, _ = _iw_engine(_R[_rv(1), _rv(2), _rs("x")])
    av = LK.argv_frame(ld, t)
    @test LK._argv_key(av, 0) == 0 && LK._argv_is_var(av, 0)
    # a reference chain: cell 2 bound to cell 1 (the higher to the lower), cell 1 then to an atom
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 2)) == LK.BOOLEX_TRUE
    @test LK._argv_is_var(av, 1)
    @test LK.do_unify_cells(ld, -(t + 1), -(t + 3)) == LK.BOOLEX_TRUE
    @test LK._argv_key(av, 1) == LK._atom_word!(ld, _rs("x")) && !LK._argv_is_var(av, 1)
end

@testset "the deep descent reads a compound's argument cells" begin
    v = _rf("p", _rf("g", _rs("a")), _rg(Int64(3)), _rlist(_rs("b")))
    ld, t, db = _iw_engine(_R[v])
    w = ld.slots[t + 1]
    @test LK._is_gcompound(w)
    ac = LK.argv_cells(ld, LK.valPtr(w))
    ck = _iw_argkeys(db, v)                             # the compiler's keys of the same head
    @test length(ck) == 3 && all(!=(0), ck)
    for i in 0:2
        @test LK._argv_key(ac, i) == ck[i + 1]
        @test !LK._argv_is_var(ac, i)
    end
    # one level further: the cells of `g(a)`
    k, gw, _ = LK._deref_loc(ld, LK._argv_loc(ac, 0))
    @test k == LK.DU_WORD && LK._is_gcompound(gw)
    @test LK._argv_key(LK.argv_cells(ld, LK.valPtr(gw)), 0) == LK._atom_word!(ld, _rs("a"))
end

# a predicate whose first argument is a compound, selected through the second-level index
_iw_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("iw_p", _rf("f", _rs("a")), _rs("one")), nothing),
    (_rf("iw_p", _rf("f", _rs("b")), _rs("two")), nothing),
    (_rf("iw_p", _rf("g", _rs("a")), _rs("three")), nothing),
    (_rf("iw_p", _rf("f", _rs("c")), _rs("four")), nothing),
    (_rf("iw_p", _rf("f", _rs("b")), _rs("five")), nothing)
]

@testset "the meter: a deep-indexed call makes no cold import, its answers swipl's" begin
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
    i3 = ld.cold_imports
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
    @test ld.cold_imports == i3                         # the index read words: no import
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
end
