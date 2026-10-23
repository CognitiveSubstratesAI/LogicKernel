# ORIGINAL: L1e step e4 — `=..`/2, a new port on CELLS (pl-prims.c `univ` at the pin, src/pl-prims.jl
# `pl_univ2_va`; audit D-0020: into e4, on cells, with the error cases as a differential; the workspace's
# L1_plan/stageL1e_design.md §4). test/core_lang/test_univ_cells.jl — on every term type:
#   * a differential against swipl: both directions (decompose a compound, an atom, a number, a string; compose
#     from a list, `[H]` alone, shared variables), partial agreement (`f(a,X) =.. [f,Y,b]`), and every error case
#     of `univ`: instantiation (unbound list, partial list), domain_error(non_empty_list, []), type_error(list),
#     type_error(atomic) (`X =.. [f(a)]`), type_error(atom) (`X =.. [1, a]`), a compound list element;
#   * the kernel's `$expr/n` (a variable head, no swipl counterpart): white-box;
#   * the meter: decomposing and composing on the stack makes no cold import.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_uv_k(i) = _rg(Int64(i))
_uv_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("u", _rv(1), _rv(2), _rv(3)),
        _rf("catch", _rf("=..", _rv(1), _rv(2)), _rf("error", _rv(3), _rv(4)), _rs("true"))),
    # shared variables survive the round trip; partial agreement binds both sides
    (
        _rf("rt", _rv(9)),
        _rconj(_rf("=..", _rf("f", _rv(1), _rv(1), _rv(2)), _rv(3)),
            _rf("=..", _rv(4), _rv(3)), _rf("=", _rv(9), _rv(4)))
    ),
    (
        _rf("pa", _rv(1), _rv(2)),
        _rf("=..", _rf("f", _rs("a"), _rv(1)), _rlist(_rs("f"), _rv(2), _rs("b")))
    )
]

@testset "=../2 on cells, as swipl" begin
    db = _rdb(_uv_clauses())
    X, L, E = _rv(50), _rv(51), _rv(52)
    goals = _R[
        _rf("u", _rf("f", _rs("a"), _uv_k(1), _rg(2.5)), L, E), _rf("u", _rs("atom"), L, E),
        _rf("u", _uv_k(42), L, E), _rf("u", _rg(1.5), L, E), _rf("u", _rg("str"), L, E),
        _rf("u", _rlist(_rs("a"), _rs("b")), L, E),
        _rf("u", X, _rlist(_rs("g"), _rs("x"), _uv_k(3)), E),
        _rf("u", X, _rlist(_rs("a")), E), _rf("u", X, _rlist(_uv_k(5)), E),
        _rf("u", X, _rlist(_rs("."), _rs("h"), _rs("t")), E),
        _rf("u", _rf("f", _rs("a")), _rlist(_rs("f"), _rs("a")), E),
        _rf("u", _rf("f", _rs("a")), _rlist(_rs("g"), _rs("a")), E),
        _rf("u", X, L, E), _rf("u", X, _rcons(_rs("f"), _rv(53)), E),
        _rf("u", X, _rlist(), E),
        _rf("u", X, _rs("notalist"), E), _rf("u", X, _rlist(_rf("f", _rs("a"))), E),
        _rf("u", X, _rlist(_uv_k(1), _rs("a")), E),
        _rf("u", X, _rlist(_rf("f", _rs("a")), _rs("b")), E),
        _rf("u", X, _rlist(_rv(54), _rs("a")), E),
        _rf("u", X, _rcons(_rs("f"), _rcons(_rs("a"), _rs("t"))), E),
        _rf("u", _rf("f", _rs("a")), _rs("bad"), E),
        _rf("rt", _rv(55)), _rf("pa", _rv(56), _rv(57))
    ]
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> occursin("existence_error", l), ours)   # =../2 is registered
    if _R_SWIPL
        theirs = _rswipl(_uv_clauses(), goals)
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

"An engine with the values of `vs` put into term references; `(ld, t)`."
function _uv_engine(vs::Vector{_R})
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
_uv_counts(ld) = ld.cold_imports        # (the export/variable/pair meters went with the keyed variables, f3)
_uv_call(ld, t) =
    LK.pl_univ2_va(ld, t, 2, LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing))

@testset "the meter: =.. on the stack, both directions, makes no cold traffic" begin
    ld, t = _uv_engine(
        _R[
            _rf("f", _rs("a"), _rv(1), _uv_k(3)),
            _rv(2),
            _rv(3),
            _rlist(_rs("g"), _rs("b"), _rv(4))
        ]
    )
    c0 = _uv_counts(ld)
    @test _uv_call(ld, t) == LK.FTRUE                          # f(a, _, 3) =.. L
    @test LK.PL_is_list(ld, t + 1)
    @test _uv_call(ld, t + 2) == LK.FTRUE                      # X =.. [g, b, _]
    @test LK.PL_is_compound(ld, t + 2)
    @test _uv_counts(ld) == c0
end

@testset "white-box: a `\$expr/n` compound (a variable head) gives all its children, the head first" begin
    ld, t = _uv_engine(_R[mk_expr(_R, _R[_rv(9), _rs("a"), _rs("b")]), _rv(2)])
    @test _uv_call(ld, t) == LK.FTRUE
    r = lk_answer(ld, t + 1)
    @test kind(r) === EXPR &&
        LK.compareStandard(child(r, 3), _rlist(_rs("a"), _rs("b")), true) == LK.CMP_EQUAL
end
