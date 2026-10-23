# ORIGINAL: L1e step e1 — a slot holds any word (pl-data.h: a frame cell holds an indirect's word too; the
# workspace's L1_plan/stageL1e_design.md §1). A grounded value stored in a term reference becomes a VALUE-TABLE
# WORD in the slot — except in a reference OLDER than the innermost foreign frame, whose rewind would drop the
# entry while the reference lives on: there it stays the slot's own side value (`SLOT_VALUE`), so its read is
# defined (upstream's is not: PL_put_float writes the reference untrailed and its float's cells are freed).
# A slot-to-slot link copies a value-table word as upstream copies an indirect (`*to = linkValI(from)`).
# test/core_lang/test_slot_indirects.jl (beside test_slot_words.jl, L1b's slot layout) — on every term type:
#   * THE PROBE FIRST (audit D-0024; evidence/A-0020 in the channel): a reference taken outside a foreign
#     frame, written inside it, the frame rewound, the reference read — then new values made, and read again:
#     the value written, both times;
#   * white-box: a reference made INSIDE the innermost frame holds the value-table word (no side value); one
#     older than it holds `SLOT_VALUE`; each reads back its value;
#   * the VM side (the review of 2026-10-15 in test_slot_words.jl, with FLOATS — value-table words now — where
#     it used compounds): floats held in argument and variable slots across a choice point inside the callee,
#     read after backtracking into it; the answers are swipl's;
#   * the meter: an arithmetic loop passing floats as call arguments makes no boundary pair (the L1d pin
#     `(0, 0, 0, 100)` in test_zero_exports.jl falls to 0);
#   * f3-1 (audit D-0110, f3's Q1 (b)): a side value is READ AS A VALUE — `_deref_loc` gives `DU_VALUE` and
#     its side word, never the boundary — so reading one through the FLI's readers and unifiers, the VM's
#     tests, the arithmetic walk, the copy and the record makes no boundary pair (`cold_pairs` unchanged),
#     and a cell bound to one holds a value-table word, never the side word.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _SW_VALUES = (
    ("float", () -> _rg(1.5)),
    ("small integer", () -> _rg(Int64(7))),
    ("atom", () -> _rs("abc"))
)

_sw_same(a, b) = LK.compareStandard(a, b, true) == LK.CMP_EQUAL

@testset "the probe: an older term reference written inside a rewound foreign frame keeps its value" begin
    for (label, mk) in _SW_VALUES
        v = mk()
        db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
        ld = db.ld
        outer = LK.PL_open_foreign_frame(ld)
        t = LK.PL_new_term_ref(ld)                       # older than the inner frame
        inner = LK.PL_open_foreign_frame(ld)
        LK.setSlotValue!(ld, t + 1, v)
        LK.PL_rewind_foreign_frame(ld, inner)
        LK.PL_close_foreign_frame(ld, inner)
        r = lk_answer(ld, t)
        u = LK.PL_new_term_ref(ld)                       # values made after the rewind reuse the room
        LK.setSlotValue!(ld, u + 1, _rg(99.25))
        r2 = lk_answer(ld, t)
        @test _sw_same(r, v)
        @test _sw_same(r2, v)
        LK.PL_discard_foreign_frame(ld, outer)
    end
end

@testset "white-box: a reference inside the innermost frame holds the value's word; an older one its side value" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    outer = LK.PL_open_foreign_frame(ld)
    old = LK.PL_new_term_ref(ld)
    inner = LK.PL_open_foreign_frame(ld)
    young = LK.PL_new_term_ref(ld)
    LK.setSlotValue!(ld, young + 1, _rg(2.5))
    LK.setSlotValue!(ld, old + 1, _rg(3.5))
    @test ld.slots[young + 1] != LK.SLOT_VALUE           # a value-table word
    @test !LK.isRef(ld.slots[young + 1]) && !LK.isAtomW(ld.slots[young + 1])
    @test ld.slots[old + 1] == LK.SLOT_VALUE             # older than `inner`: its own side value
    @test _sw_same(lk_answer(ld, young), _rg(2.5))
    @test _sw_same(lk_answer(ld, old), _rg(3.5))
    k, w, _ = LK._deref_loc(ld, -(young + 1))
    @test k == LK.DU_VALUE && w == ld.slots[young + 1]
    # a small integer is its tagged word and an atom its atom word, wherever the reference lies
    LK.setSlotValue!(ld, old + 1, _rg(Int64(5)))
    @test LK.isTaggedIntW(ld.slots[old + 1])
    LK.setSlotValue!(ld, old + 1, _rs("zz"))
    @test LK.isAtomW(ld.slots[old + 1])
    LK.PL_discard_foreign_frame(ld, inner)
    LK.PL_discard_foreign_frame(ld, outer)
end

@testset "white-box: a link from a cell holding a value-table word shares the word, no new entry" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    fr = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_ref(ld)
    b = LK.PL_new_term_ref(ld)
    p = LK._slot_new_var!(ld, a + 1)                     # a's slot references a fresh cell…
    w = LK._vword!(ld, _rg(4.75))                        # …bound to a float's value-table word
    ld.gstack[p] = w
    n = length(ld.vtable)
    LK._slot_link!(ld, b + 1, a + 1)                     # *to = linkValI(from): the indirect shared
    @test ld.slots[b + 1] == w
    @test length(ld.vtable) == n
    @test _sw_same(lk_answer(ld, b), _rg(4.75))
    LK.PL_discard_foreign_frame(ld, fr)
end

const _SW_AR = """
sw_loop(0) :- !.
sw_loop(N) :- D is N + 0.5, D > 0.25, E is D * 2, E =:= D + D, N1 is N - 1, sw_loop(N1).
sw_top :- sw_loop(40).
"""

@testset "the meter: floats passed as call arguments make no boundary pair" begin
    gd = LK.PL_global_data{_R}()
    ld = LK.PL_local_data{_R}(gd)
    f = joinpath(mktempdir(), "sw_loop.pl")
    write(f, _SW_AR)
    st, _, msgs = LK.load_file!(gd, ld, f)
    @test st === :ok && isempty(msgs)
    function q()
        proc = LK.lookupProcedure(lk_sym(_R, :sw_top), 0, LK.MODULE_user(gd))
        fid = LK.PL_open_foreign_frame(ld)
        qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, proc, 0)
        rc = LK.PL_next_solution(gd, ld, qid)
        LK.PL_close_query(ld, qid)
        LK.PL_discard_foreign_frame(ld, fid)
        return rc
    end
    @test q() == LK.PL_S_TRUE
    c1 = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)
    @test q() == LK.PL_S_TRUE
    @test (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs) .- c1 ==
        (0, 0, 0, 0)
end

"`test_slot_words.jl`'s choice-point programs with FLOATS in the slots (value-table words since e1)."
function _si_choice_clauses()
    X, Y, Z, R, H, T = (_rv(k) for k in 1:6)
    q(a, b) = _rf("q", a, b)
    eq(a, b) = _rf("=", a, b)
    pair(a, b) = _rf("-", a, b)
    return Tuple{_R, Union{Nothing, _R}}[
        (q(X, _rf("a", X)), nothing), (q(X, _rf("b", X)), nothing),
        (_rf("s", Z, X, R), eq(R, pair(Z, X))),
        (_rf("si_lco", X, R), _rconj(q(X, Z), _rf("s", Z, X, R))),
        (_rf("si_retry", X, R),
            _rconj(
                _rf("is", Y, _rf("+", X, _rg(1.0))),
                q(Y, Z),
                eq(Z, _rs("never")),
                eq(R, _rg(1))
            )),
        (_rf("si_retry", X, R), eq(R, X)),
        (_rf("si_head", _rcons(H, T), R), _rconj(q(H, Z), eq(R, pair(pair(Z, H), T)))),
        (
            _rf("si_or", X, R),
            _rconj(
                _ror(
                    _rf("is", Y, _rf("*", X, _rg(2.0))), _rf("is", Y, _rf("*", X, _rg(3.0)))
                ),
                eq(R, pair(Y, X)))
        ),
        (_rf("si_call", X, R), _rconj(_rf("call", _rs("q"), X, Z), eq(R, pair(Z, X)))),
        (
            _rf("si_catch", X, R),
            _rconj(_rf("catch", q(X, Z), _rv(7), _rs("true")), eq(R, pair(Z, X)))
        ),
        (_rf("si_findall", X, R), _rconj(_rf("findall", Z, q(X, Z), Y), eq(R, pair(Y, X))))
    ]
end

@testset "floats in slots read after backtracking are the values they held at the choice point (swipl)" begin
    clauses = _si_choice_clauses()
    A, B = _rg(1.5), _rg(2.25)
    goals = _R[
        _rf(n, A, _rv(100)) for
        n in ("si_lco", "si_retry", "si_or", "si_call", "si_catch", "si_findall")
    ]
    push!(goals, _rf("si_head", _rcons(A, _rcons(B, _rnil())), _rv(100)))
    ours = _rlines(_rdb(clauses), goals)
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> startswith(l, "exception("), ours)
    if _R_SWIPL
        @test ours == _rswipl(clauses, goals)
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "f3-1 (audit D-0110): a side value is read as a value — no boundary pair through the readers" begin
    X = _rv(1)
    db = _rdb(
        Tuple{_R, Union{Nothing, _R}}[
            (_rf("si_f1", X), _rconj(_rf("float", X), _rf("=:=", X, _rg(1.5))))
        ]
    )
    ld = db.ld
    outer = LK.PL_open_foreign_frame(ld)
    f = LK.PL_new_term_ref(ld)                           # older than `inner`: side values
    b = LK.PL_new_term_ref(ld)
    s = LK.PL_new_term_ref(ld)
    o = LK.PL_new_term_ref(ld)
    inner = LK.PL_open_foreign_frame(ld)
    LK.setSlotValue!(ld, f + 1, _rg(1.5))
    LK.setSlotValue!(ld, b + 1, _rg(Int64(1) << 60))   # past the tagged range: an indirect
    LK.setSlotValue!(ld, s + 1, _rg("abc"))
    for t in (f, b, s)
        @test ld.slots[t + 1] == LK.SLOT_VALUE
        k, w, p = LK._deref_loc(ld, -(t + 1))
        @test k == LK.DU_VALUE && LK._is_side_word(w) && LK.valPtr(w) == t + 1 && p == 0
    end
    c0 = ld.cold_pairs
    # the type tests: the FLI's, which are also the VM's (`@TYPE_TEST`: I_FLOAT runs `PL_is_float`, …;
    # I_VAR/I_NONVAR run `_slot_is_var`)
    @test LK.PL_is_float(ld, f) && !LK.PL_is_float(ld, b) && !LK.PL_is_float(ld, s)
    @test LK.PL_is_integer(ld, b) && !LK.PL_is_integer(ld, f)
    @test LK.PL_is_rational(ld, b) && !LK.PL_is_rational(ld, f)
    @test LK.PL_is_number(ld, f) && LK.PL_is_number(ld, b) && !LK.PL_is_number(ld, s)
    @test LK.PL_is_string(ld, s) && !LK.PL_is_string(ld, f)
    @test all(t -> LK.PL_is_atomic(ld, t), (f, b, s))
    @test !any(
        t ->
            LK.PL_is_variable(ld, t) || LK.PL_is_atom(ld, t) || LK.PL_is_compound(ld, t) ||
            LK.PL_is_callable(ld, t),
        (f, b, s)
    )
    @test !LK._slot_is_var(ld, f + 1)
    # the getters
    @test LK.PL_get_long(ld, b) == 1 << 60 && LK.PL_get_long(ld, f) === nothing
    @test LK.PL_get_integer(ld, b) === nothing
    @test LK.PL_get_atom(ld, f) === nothing && LK.PL_get_name_arity(ld, s) === nothing
    # the unifiers: a constant, an integer, the value itself, another value, a fresh variable
    @test LK.PL_unify_atomic(ld, f, _rg(1.5)) && !LK.PL_unify_atomic(ld, f, _rg(2.5))
    @test LK.PL_unify_integer(ld, b, 1 << 60) && !LK.PL_unify_integer(ld, b, 7)
    @test LK.PL_unify(ld, f, f) && !LK.PL_unify(ld, f, b)
    v = LK.PL_new_term_ref(ld)
    @test LK.PL_unify(ld, v, f)
    kv, wv, _ = LK._deref_loc(ld, -(v + 1))
    @test kv == LK.DU_VALUE && LK._is_vword(wv)          # the cell holds a value-table word, not the side word
    @test LK.PL_is_float(ld, v) && LK.PL_compare(ld, v, f) == LK.CMP_EQUAL
    @test LK.PL_same_term(ld, f, f) && !LK.PL_same_term(ld, f, b)
    # the VM's constant tests on the slot (H_FLOAT, B_UNIFY_VC: `_unify_const_loc`; B_EQ_VC: `_identical_atomic`)
    @test LK._unify_const_loc(ld, -(f + 1), _rg(1.5)) &&
        !LK._unify_const_loc(ld, -(f + 1), _rg(2.5))
    @test LK._identical_atomic(ld, -(f + 1), _rg(1.5))
    # the arithmetic: the fast path and the walk
    n = LK._number_alloc!(ld)
    @test LK.valueExpression(ld, f, n) && n.type == LK.V_FLOAT && n.f == 1.5
    @test LK.evalExpression_cells(ld, b, n) && n.type == LK.V_INTEGER && n.i == 1 << 60
    LK._number_free!(ld, 1)
    # a link into another reference: the value (into an older one, its side value again)
    @test first(LK.PL_strip_module_ex(db.gd, ld, f, 0, o))
    @test ld.slots[o + 1] == LK.SLOT_VALUE && LK.PL_compare(ld, o, f) == LK.CMP_EQUAL
    # the copy and the record
    c = LK.PL_new_term_ref(ld)
    @test LK.copy_term_refs(ld, f, c, LK.cp_options(true))
    @test LK.PL_is_float(ld, c) && LK.PL_compare(ld, c, f) == LK.CMP_EQUAL
    r = LK.compileTermToHeap(ld, s)
    @test r.term === nothing                             # recorded on the words, as its value
    rr = LK.PL_new_term_ref(ld)
    @test LK.copyRecordToGlobal(ld, rr, r)
    @test LK.PL_is_string(ld, rr) && LK.PL_compare(ld, rr, s) == LK.CMP_EQUAL
    # the VM: a query whose argument is the side value
    qid = LK.PL_open_query(
        db.gd, ld, nothing, LK.PL_Q_NORMAL, _rproc(db, _rf("si_f1", X)), f
    )
    @test LK.PL_next_solution(db.gd, ld, qid) in (LK.PL_S_TRUE, LK.PL_S_LAST)
    LK.PL_close_query(ld, qid)
    @test ld.cold_pairs == c0                            # no boundary pair (D-0110 item 2)
    LK.PL_discard_foreign_frame(ld, inner)
    LK.PL_discard_foreign_frame(ld, outer)
end
