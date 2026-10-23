# ORIGINAL: L1e step e4 — unifiable/3 on CELLS (pl-prims.c unifiable, unify_all_trail_ptrs, unifiable_occurs_check
# as their `_cells` ports, src/pl-prims.jl; the workspace's L1_plan/stageL1e_design.md §4). The substitution list
# is laid out at gTop from the trail, newest binding first, as upstream. test/core_lang/test_unifiable_cells.jl —
# on every term type:
#   * a differential against swipl under each occurs_check mode: a variable against itself, against a term (both
#     sides), compounds binding several variables (the list's ORDER is swipl's), no binding needed, a failure,
#     shared variables, a variable bound to a variable, `X` against `f(X)` (each mode's answer);
#   * the meter: unifiable/3 on terms on the stack makes no cold import (until L1f f3 also no cold export,
#     variable read or boundary pair: those meters went with the keyed variables).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_uf_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("u", _rv(1), _rv(2), _rv(3)),
        _rf(
            "catch",
            _rf("unifiable", _rv(1), _rv(2), _rv(3)),
            _rf("error", _rv(3), _rv(4)),
            _rs("true")
        )),
    # the same variable on both sides; a variable met through a binding
    (_rf("uself", _rv(3)), _rf("unifiable", _rv(1), _rv(1), _rv(3))),
    (
        _rf("uocc", _rv(3)),
        _rf("catch", _rf("unifiable", _rv(1), _rf("f", _rv(1)), _rv(3)),
            _rf("error", _rv(3), _rv(4)), _rs("true"))
    ),
    (
        _rf("ushare", _rv(3)),
        _rf(
            "unifiable",
            _rf("f", _rv(1), _rv(1), _rv(2)),
            _rf("f", _rv(5), _rs("a"), _rv(5)),
            _rv(3)
        )
    )
]

const _UF_GOALS = let X = _rv(50), Y = _rv(51), Z = _rv(52), S = _rv(60)
    _R[
        _rf("u", X, _rs("a"), S), _rf("u", _rs("a"), X, S), _rf("u", X, Y, S),
        _rf("u", _rf("f", X, _rs("b")), _rf("f", _rs("a"), Y), S),
        _rf(
            "u",
            _rf("g", X, Y, Z),
            _rf("g", _rs("a"), _rf("h", _rs("b")), _rlist(_rs("c"))),
            S
        ),
        _rf("u", _rf("f", _rs("a")), _rf("f", _rs("a")), S),
        _rf("u", _rf("f", _rs("a")), _rf("f", _rs("b")), S),
        _rf("u", _rf("f", X, Y), _rf("f", Y, X), S),
        _rf("u", _rlist(X, Y), _rlist(_rg(1.5), _rg(Int64(2))), S),
        _rf("uself", S), _rf("uocc", S), _rf("ushare", S)
    ]
end

for (mode, flag) in (("false", LK.OCCURS_CHECK_FALSE), ("true", LK.OCCURS_CHECK_TRUE),
    ("error", LK.OCCURS_CHECK_ERROR))
    @testset "unifiable/3 on cells, occurs_check=$mode, as swipl" begin
        db = _rdb(_uf_clauses())
        db.ld.prolog_flag_occurs_check = flag
        ours = _rlines(db, _UF_GOALS)
        @test count(==("end"), ours) == length(_UF_GOALS)
        @test !any(l -> occursin("existence_error", l), ours)
        if _R_SWIPL
            theirs = _rswipl(
                _uf_clauses(), _UF_GOALS; extra=":- set_prolog_flag(occurs_check, $mode).\n"
            )
            @test ours == theirs
            if ours != theirs
                k = findfirst(
                    i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours)
                )
                @info "first difference ($mode)" k ours[something(k, 1)] get(
                    theirs, something(k, 1), "—"
                )
            end
        elseif _R_SWIPL_REQUIRED
            @test false
        end
    end
end

@testset "the meter: unifiable/3 on terms on the stack makes no cold traffic" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 3)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, t + 1, _rf("f", _rv(1), _rs("b"), _rv(2)), pvm)
    LK.putSlotValue!(ld, t + 2, _rf("f", _rs("a"), _rv(3), _rv(3)), pvm)
    LK.putSlotValue!(ld, t + 3, _rv(9), pvm)
    c0 = ld.cold_imports
    @test LK.pl_unifiable3_va(
        ld, t, 3, LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    ) == LK.FTRUE
    @test LK.PL_skip_list(ld, t + 2) == (LK.PL_LIST, 3)
    @test ld.cold_imports == c0
    @test LK._deref_loc(ld, -(t + 1))[1] == LK.DU_WORD     # the terms stay unbound by the call
    @test LK._deref_loc(ld, LK.valPtr(LK._deref_loc(ld, -(t + 1))[2]) + 1)[1] == LK.DU_CELL
end
