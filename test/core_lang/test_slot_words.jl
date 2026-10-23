# ORIGINAL: L1b stages C5 and C6a — the local stack's slots hold WORDS (pl-data.h): a reference to a global cell, an atom word, or `SLOT_VALUE` with the value in the slot's own side entry; upstream has no counterpart test (its frames always hold words).
# test/core_lang/test_slot_words.jl — white-box, on every term type:
#   * a symbol, a number and a compound are words since L1e e1/L1c (until L1f f3 this file also pinned
#     the boundary: a cell variable or a KEYED variable stored in a slot — the keyed variables went in f3);
#   * a fresh cell from a slot builds no term of its own and adds no value-table entry;
#   * a copied `SLOT_VALUE` (a grounded side value, D-0024/f3's Q1 (b)) carries its value: overwriting
#     the source leaves the copy as it was;
#   * `_slot_link!` (`linkValI` on words): an unbound cell gives its reference, a cell bound to a cell
#     the reference of the unbound one, a cell bound to an atom or a compound that word;
#   * a slot never written (the word 0) is refused on its read;
#   * the local stack's growth keeps `slots` and `slot_values` the same length, the new words 0.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _SW = lk_term_type(Union{Int64, Float64, String})
_sw_sym(n) = lk_sym(_SW, Symbol(n))
_sw_f(x) = mk_expr(_SW, _SW[_sw_sym(:f), x])
"Three fresh term references' slots on a new engine."
function _sw_engine()
    ld = LK.PL_local_data{_SW}(LK.PL_global_data{_SW}())
    r = LK.PL_new_term_refs(ld, 3)
    return ld, r + 1, r + 2, r + 3                              # term reference t is slot t + 1
end

@testset "a symbol, a number and a compound are the slot's words" begin
    ld, a, b, _ = _sw_engine()
    # since L1e e1 a slot holds any word: a symbol its atom word, a small integer its tagged word, a
    # float a value-table word (these references lie above the engine's base foreign frame)
    # (test_slot_indirects.jl: the older-reference rule)
    for (x, form) in (
        (_sw_sym(:foo), LK.isAtomW), (LK.mk_nil(_SW), LK.isAtomW),
        (lk_gnd(_SW, Int64(7)), LK.isTaggedIntW), (lk_gnd(_SW, 2.5), LK._is_vword)
    )
        LK.setSlotValue!(ld, b, x)
        @test form(ld.slots[b])
        @test lk_eq(lk_answer(ld, b - 1), x)
    end
    # a compound is copied onto the global stack (L1c): a compound WORD
    LK.setSlotValue!(ld, a, _sw_f(_sw_sym(:x)))
    @test LK._is_gcompound(ld.slots[a]) && lk_eq(lk_answer(ld, a - 1), _sw_f(_sw_sym(:x)))
end

@testset "a fresh cell from a slot builds no term and no value-table entry" begin
    ld, a, _, _ = _sw_engine()
    n0, g0 = length(ld.vtable), ld.gTop
    p = LK._slot_new_var!(ld, a)
    @test p == g0 + 1 && ld.gTop == g0 + 1 && length(ld.vtable) == n0
    @test ld.slots[a] == LK.makeRefG(p) && LK.isVar(ld.gstack[p])
end

@testset "a copied SLOT_VALUE carries its value" begin
    ld, a, b, _ = _sw_engine()
    # a side value since L1f f3 (Q1 (b)): a grounded value in a reference OLDER than the innermost
    # foreign frame (D-0024; until f3 also the boundary's compound)
    fid = LK.PL_open_foreign_frame(ld)
    x = lk_gnd(_SW, 1.5)
    LK.setSlotValue!(ld, b, lk_gnd(_SW, 9.5))                   # b's side entry holds another value
    LK.setSlotValue!(ld, a, x)
    @test ld.slots[a] == ld.slots[b] == LK.SLOT_VALUE
    LK._slot_copy!(ld, b, a)
    LK.setSlotValue!(ld, a, _sw_sym(:other))
    @test ld.slots[b] == LK.SLOT_VALUE && lk_eq(ld.slot_values[b], x)
    LK._slot_new_var!(ld, a)                                    # a reference copies as a word
    LK._slot_copy!(ld, b, a)
    @test ld.slots[b] == ld.slots[a]
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "_slot_link! follows the words as linkValI follows the terms" begin
    ld, a, b, c = _sw_engine()
    p1 = LK._slot_new_var!(ld, a)
    LK._slot_link!(ld, b, a)                                    # unbound: its reference
    @test ld.slots[b] == ld.slots[a] == LK.makeRefG(p1)
    p2 = LK._slot_new_var!(ld, c)
    LK._bind_const!(ld, p1, LK.makeRefG(p2))                    # a cell bound to a cell: the link
    LK._slot_link!(ld, b, a)                                    # reaches the unbound one
    @test ld.slots[b] == LK.makeRefG(p2)
    foo = LK._atom_word!(ld, _sw_sym(:foo))
    LK._bind_const!(ld, p2, foo)                                # … and that one to an atom
    LK._slot_link!(ld, b, a)
    @test ld.slots[b] == foo
    ld2, c, d, e = _sw_engine()
    p3 = LK._slot_new_var!(ld2, c)
    LK.setSlotValue!(ld2, d, _sw_f(_sw_sym(:y)))                # a compound: cells (L1c), its word
    LK._bind_const!(ld2, p3, ld2.slots[d])
    LK._slot_link!(ld2, e, c)
    @test LK._is_gcompound(ld2.slots[e]) && lk_eq(lk_answer(ld2, e - 1), _sw_f(_sw_sym(:y)))
end

@testset "a slot never written is refused on its read" begin
    ld, _, _, _ = _sw_engine()
    p = length(ld.slots)
    @test ld.slots[p] == 0
    @test_throws ErrorException LK._deref_loc(ld, -p)
end

@testset "the local stack grows both vectors, the new words 0" begin
    ld, _, _, _ = _sw_engine()
    n = length(ld.slots)
    @test length(ld.slot_values) == n
    LK._resize_local!(ld, 2n)
    @test length(ld.slots) == length(ld.slot_values) == 2n
    @test all(iszero, view(ld.slots, (n + 1):(2n)))
end

# ── a SLOT_VALUE across choice points (review, 2026-10-15) ─────────────────────────────────────────
# A slot has ONE side entry, so a slot overwritten after a choice point and read again after
# backtracking would read the new value. Nothing restores a slot word — the trail names global cells
# only, as upstream's never names a frame cell it cannot `setVar` — so the guard
# is that no writer overwrites a slot still live below a choice point: last-call reuse only when no
# choice point is newer than the frame (`I_DEPART`), a retried clause rewrites its variable slots
# only, a call/N, catch/3, setup_call_cleanup/3 or findall/3 writes the NEXT frame's arguments. Each
# case holds compounds (no word form: `SLOT_VALUE`) in argument and variable slots across a choice
# point inside the callee and reads them after backtracking into it; the answers are swipl's.
include(joinpath(@__DIR__, "rules_common.jl"))

"The programs: `q/2` leaves a choice point; each `sv*` reads its compounds after backtracking."
function _sw_choice_clauses()
    X, Y, Z, R, H, T = (_rv(k) for k in 1:6)
    q(a, b) = _rf("q", a, b)
    eq(a, b) = _rf("=", a, b)
    pair(a, b) = _rf("-", a, b)
    return Tuple{_R, Union{Nothing, _R}}[
        (q(X, _rf("a", X)), nothing), (q(X, _rf("b", X)), nothing),
        (_rf("s", Z, X, R), eq(R, pair(Z, X))),
        # the last call while q/2's choice point is newer than the frame: no reuse of X's slot
        (_rf("sv_lco", X, R), _rconj(q(X, Z), _rf("s", Z, X, R))),
        # the same through the L_NOLCO block (the arguments stay in place: the block is compiled) — no reuse
        # (L1e e1 assertion, audit D-0031: L_NOLCO's reuse is an overwrite point the review did not name)
        (_rf("s2", X, R, Z), eq(R, pair(Z, X))),
        (_rf("sv_nolco", X, R), _rconj(q(X, Z), _rf("s2", X, R, Z))),
        # a retried clause: the first writes a variable slot and fails, the second reads X
        (_rf("sv_retry", X, R),
            _rconj(eq(Y, _rf("g", X)), q(Y, Z), eq(Z, _rs("never")), eq(R, _rg(1)))),
        (_rf("sv_retry", X, R), eq(R, X)),
        # variable slots filled from a caller's compound (H_FIRSTVAR, read mode)
        (_rf("sv_head", _rcons(H, T), R), _rconj(q(H, Z), eq(R, pair(pair(Z, H), T)))),
        # a disjunction writes its branch's slots; the other branch reads X
        (
            _rf("sv_or", X, R),
            _rconj(_ror(eq(Y, _rf("l", X)), eq(Y, _rf("r", X))), eq(R, pair(Y, X)))
        ),
        (_rf("sv_call", X, R), _rconj(_rf("call", _rs("q"), X, Z), eq(R, pair(Z, X)))),
        (
            _rf("sv_catch", X, R),
            _rconj(_rf("catch", q(X, Z), _rv(7), _rs("true")), eq(R, pair(Z, X)))
        ),
        (_rf("sv_scc", X, R),
            _rconj(
                _rf("setup_call_cleanup", _rs("true"), q(X, Z), _rs("true")),
                eq(R, pair(Z, X))
            )),
        (_rf("sv_findall", X, R), _rconj(_rf("findall", Z, q(X, Z), Y), eq(R, pair(Y, X))))
    ]
end

@testset "a SLOT_VALUE read after backtracking is the value it held at the choice point (swipl)" begin
    clauses = _sw_choice_clauses()
    A, B = _rf("f", _rg(1)), _rf("h", _rs("c"))
    goals = _R[
        _rf(n, A, _rv(100)) for
        n in (
            "sv_lco", "sv_nolco", "sv_retry", "sv_or", "sv_call", "sv_catch", "sv_scc",
            "sv_findall"
        )
    ]
    push!(goals, _rf("sv_head", _rcons(A, B), _rv(100)))
    ours = _rlines(_rdb(clauses), goals)
    if _R_SWIPL
        @test ours == _rswipl(clauses, goals)
    else
        @test_skip "swipl is not on PATH: the answers are not compared"
    end
    @test count(==("end"), ours) == length(goals)
end
