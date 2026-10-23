# ORIGINAL: L1d step 4 — TAGGED SMALL INTEGERS (pl-data.h `consInt`, `TAG_INTEGER|STG_INLINE`): an
# integer in the tagged range (`PLMINTAGGEDINT..PLMAXTAGGEDINT`, -2^56..2^56-1) is its own WORD — in
# a cell, a slot and a `*_SMALLINT` operand — and one past either end stays a value-table word
# (upstream's indirect). test/core_lang/test_tagged_ints.jl — on every term type:
#   * the words: 0, ±1 and the range's ends are tagged and read back as the same integer; one past
#     each end is not tagged;
#   * THE INDEX (user, 2026-10-16): clauses p(V, kI) with V at the edges — the key a clause gets at
#     assert (its head code, `argKey`) EQUALS the key read at call from a cell holding the integer's
#     word (`_index_key_loc`); each call's first candidate is its own clause and no clause choice is
#     left (the index hit);
#   * through the VM: t_i(Y) :- L = [V], L = [X], p(X, Y) — X then names the list cell holding V's
#     word, so the call's first argument is read on the WORDS — answers as swipl, deterministically;
#   * the ladder at the edges against swipl: =, ==, compare/3 and @< between small integers, the
#     integers one past the edges, and floats (`1 = 1.0` fails, as SWI's identity);
#   * arithmetic on the words: `Y is X + 1` (A_ADD_FC) across the top edge gives the indirect
#     integer, `X =< Y` (valueExpression) at the edges, against swipl.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))

const _TI_MIN = LK.PLMINTAGGEDINT                   # -2^56 (swipl 10.1.16: h_smallint, probed)
const _TI_MAX = LK.PLMAXTAGGEDINT                   #  2^56 - 1
# the edges, and one past each end (an indirect: H_MPZ, a value-table word)
const _TI_VALUES = Int64[0, 1, -1, _TI_MIN, _TI_MAX, _TI_MIN - 1, _TI_MAX + 1]
_ti_tagged(v::Int64)::Bool = _TI_MIN <= v <= _TI_MAX
_ti_tag(i::Int) = _rs("k$i")

@testset "the words: tagged inside the range, an indirect one past either end" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    for v in _TI_VALUES
        w = LK._word_of!(ld, _rg(v))
        @test LK.isTaggedIntW(w) == _ti_tagged(v)
        _ti_tagged(v) && @test LK.valInt(w) == v && w == LK.consInt(v)
        # read back as the same integer (an Int64 payload), in a cell (f3-3: the word in a term
        # reference, read off it — `_cell_value` went with the boundary)
        r = LK.PL_new_term_ref(ld)
        ld.slots[r + 1] = w
        @test gnd_equal(lk_answer(ld, r), _rg(v))
    end
end

@testset "the index: the key at assert equals the key at call, at the tagged range's edges" begin
    p = ix_pred(_R, :p, 2)
    for (i, v) in enumerate(_TI_VALUES)
        ix_assertz!(p, _rf("p", _rg(v), _ti_tag(i)))
    end
    LK.reconsiderIndexes!(p.def)
    LK.update_primary_index!(p.def)
    p.virgin = false
    ld = p.db.ld
    for (i, v) in enumerate(_TI_VALUES)
        # the call's first argument: a global cell holding the integer's WORD, referenced from the
        # frame's first argument slot, as the VM leaves it after `L = [V], L = [X]`
        q = LK.allocGlobalCells!(ld, 1)
        ld.gstack[q] = LK._word_of!(ld, _rg(v))
        base = LK.argFrameP(ld.lTop, 0)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, base + 1, _rv(1), pvm)
        LK.putSlotValue!(ld, base + 2, _rv(2), pvm)
        ld.slots[base + 1] = LK.makeRefG(q)
        argv = LK.argv_frame(ld, base)
        key_call = LK._argv_key(argv, 0)
        @test !LK._argv_is_var(argv, 0)
        @test key_call == LK.indexOfWord(ld, _rg(v))            # the term's key: the clause's function
        chp = LK.ClauseChoice{_R}(nothing, LK.word(0))
        c = LK.firstClause!(ld, argv, LK.global_generation(p.db.gd), p.def, chp)
        @test c !== nothing && c.key == key_call            # the key at assert == the key at call
        @test c !== nothing &&
            lk_eq(
            ix_answer(ld, _rf("p", _rg(v), _rv(3)), c.clause), _rf("p", _rg(v), _ti_tag(i))
        )   # … its own clause
        @test chp.cref === nothing                          # … and no clause choice left
    end
end

# t_i(Y) :- L = [V_i], L = [X], p(X, Y).   X is bound to the list cell holding V_i's word, so the
# call of p/2 reads its first argument on the words; vt(I, Y) calls t_I.
_ti_clauses() = vcat(
    Tuple{_R, Union{Nothing, _R}}[
        (_rf("p", _rg(v), _ti_tag(i)), nothing) for (i, v) in enumerate(_TI_VALUES)
    ],
    Tuple{_R, Union{Nothing, _R}}[
        (
            _rf("t$i", _rv(9)),
            _rconj(_rf("=", _rv(1), _rlist(_rg(v))), _rf("=", _rv(1), _rlist(_rv(2))),
                _rf("p", _rv(2), _rv(9)))
        ) for (i, v) in enumerate(_TI_VALUES)],
    Tuple{_R, Union{Nothing, _R}}[
        # the ladder: unify, identity, order — each through a clause body (B_UNIFY, B_EQ_VV, …)
        (_rf("u_t", _rv(1), _rv(2)), _rf("=", _rv(1), _rv(2))),
        (_rf("eq_t", _rv(1), _rv(2)), _rf("==", _rv(1), _rv(2))),
        (_rf("cmp_t", _rv(1), _rv(2), _rv(3)), _rf("compare", _rv(3), _rv(1), _rv(2))),
        (_rf("lt_t", _rv(1), _rv(2)), _rf("@<", _rv(1), _rv(2))),
        # arithmetic: A_ADD_FC (`Y is X + 1`, `Y is X - 1`) and valueExpression (`=<`)
        (_rf("inc_t", _rv(1), _rv(2)), _rf("is", _rv(2), _rf("+", _rv(1), _rg(Int64(1))))),
        (_rf("dec_t", _rv(1), _rv(2)), _rf("is", _rv(2), _rf("-", _rv(1), _rg(Int64(1))))),
        (_rf("le_t", _rv(1), _rv(2)), _rf("=<", _rv(1), _rv(2)))
    ])

@testset "through the VM: a first argument read on the words answers as swipl, deterministically" begin
    db = _rdb(_ti_clauses())
    goals = _R[_rf("t$i", _rv(50)) for i in eachindex(_TI_VALUES)]
    ours = _rlines(db, goals)
    if _R_SWIPL
        @test ours == _rswipl(_ti_clauses(), goals)
    elseif _R_SWIPL_REQUIRED
        @test false
    end
    # each answer exits deterministically (the lines carry the exit, which swipl's compare too):
    # swipl indexes p/2's first argument (JIT, seven distinct integer keys) — pinned on our side
    # as well, so the index hit is checked where swipl is absent
    @test all(l -> l == "end" || endswith(l, " det"), ours)
    @test count(==("end"), ours) == length(goals) && length(ours) == 2 * length(goals)
end

@testset "the ladder and arithmetic at the edges, as swipl" begin
    vals = _R[_rg(v) for v in _TI_VALUES]
    append!(vals, _R[_rg(1.0), _rg(-0.0), _rg(Float64(_TI_MAX))])
    goals = _R[]
    for a in vals, b in vals
        push!(
            goals,
            _rf("u_t", a, b),
            _rf("eq_t", a, b),
            _rf("cmp_t", a, b, _rv(50)),
            _rf("lt_t", a, b)
        )
    end
    for v in _TI_VALUES
        push!(goals, _rf("inc_t", _rg(v), _rv(50)), _rf("dec_t", _rg(v), _rv(50)),
            _rf("le_t", _rg(v), _rg(_TI_MAX)), _rf("le_t", _rg(_TI_MAX + 1), _rg(v)))
    end
    db = _rdb(_ti_clauses())
    ours = _rlines(db, goals)
    # the kernel's side alone (also where swipl is absent: Pkg.test): every goal ends (an error at the
    # range's edge would be a line too, so no "no exception" claim here)
    @test count(==("end"), ours) == length(goals)
    if _R_SWIPL
        theirs = _rswipl(_ti_clauses(), goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k goals[something(k, 1)] ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end
