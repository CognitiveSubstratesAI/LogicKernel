# ORIGINAL: L1e step e4 — built-ins on CELLS (pl-prims.c not_unify and can_unify as `pl_not_unify2_va` /
# `can_unify_cells`, functor/3's first read, lengthList; src/pl-prims.jl; the workspace's
# L1_plan/stageL1e_design.md §4). test/core_lang/test_builtins_cells.jl — on every term type:
#   * `\=`/2 against swipl under each occurs_check mode: the shortcut cases (a variable, the same word, two
#     atomic values, kinds that differ) and the full check through `can_unify_cells` (compounds, a shared
#     variable, cyclic terms, the occurs check's error);
#   * functor/3 and length/2 (lengthList) against swipl: compounds, atoms, numbers, partial and improper lists;
#   * the meter: `\=` and functor/3 on terms on the stack make no cold export, import, variable read or pair.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_bc_k(i) = _rg(Int64(i))
_bc_catch(g, e) = _rf("catch", g, _rf("error", e, _rv(90)), _rs("true"))

function _bc_clauses()
    A, B, R = _rv(1), _rv(2), _rv(3)
    return Tuple{_R, Union{Nothing, _R}}[
        (
            _rf("nu", A, B, R),
            _bc_catch(
                _rite(_rf("\\=", A, B), _rf("=", R, _rs("yes")), _rf("=", R, _rs("no"))), R
            )
        ),
        # `X \= f(X)`: unifiable without the occurs check, not with it (true: no; error: the error)
        (
            _rf("nuo", R),
            _bc_catch(
                _rite(
                    _rf("\\=", _rv(5), _rf("f", _rv(5))),
                    _rf("=", R, _rs("yes")),
                    _rf("=", R, _rs("no"))
                ),
                R
            )
        ),
        (
            _rf("nuc", R),
            _rconj(_rf("=", _rv(5), _rf("f", _rv(5))), _rf("=", _rv(6), _rf("f", _rv(6))),
                _rite(
                    _rf("\\=", _rv(5), _rv(6)),
                    _rf("=", R, _rs("yes")),
                    _rf("=", R, _rs("no"))
                ))
        ),
        (
            _rf("fu", A, R),
            _bc_catch(
                _rconj(
                    _rf("functor", A, _rv(6), _rv(7)), _rf("=", R, _rf("-", _rv(6), _rv(7)))
                ),
                R
            )
        ),
        (_rf("len", A, R), _bc_catch(_rf("length", A, R), R))
    ]
end

const _BC_GOALS = let X = _rv(50), Y = _rv(51), R = _rv(60)
    _R[
        _rf("nu", X, _rs("a"), R), _rf("nu", _rs("a"), _rs("a"), R),
        _rf("nu", _rs("a"), _rs("b"), R),
        _rf("nu", _bc_k(1), _rg(1.0), R), _rf("nu", _bc_k(1), _bc_k(1), R),
        _rf("nu", _rg(2.5), _rg(2.5), R),
        _rf("nu", _rs("a"), _rf("f", _rs("a")), R),
        _rf("nu", _rf("f", X, _rs("b")), _rf("f", _rs("a"), Y), R),
        _rf("nu", _rf("f", X, X), _rf("f", _rs("a"), _rs("b")), R),
        _rf("nu", _rf("f", _rs("a")), _rf("g", _rs("a")), R),
        _rf("nuo", R), _rf("nuc", R),
        _rf("fu", _rf("f", _rs("a"), _rs("b")), R), _rf("fu", _rs("atom"), R),
        _rf("fu", _bc_k(7), R),
        _rf("fu", _rg(1.5), R), _rf("fu", _rlist(_rs("a")), R), _rf("fu", X, R),
        _rf("len", _rlist(_rs("a"), _rs("b")), R), _rf("len", _rlist(), R),
        _rf("len", _rcons(_rs("a"), _rs("b")), R),
        _rf("len", _rs("a"), R)
    ]
end

for (mode, flag) in (("false", LK.OCCURS_CHECK_FALSE), ("true", LK.OCCURS_CHECK_TRUE),
    ("error", LK.OCCURS_CHECK_ERROR))
    @testset "\\= / functor / length on cells, occurs_check=$mode, as swipl" begin
        db = _rdb(_bc_clauses())
        db.ld.prolog_flag_occurs_check = flag
        ours = _rlines(db, _BC_GOALS)
        @test count(==("end"), ours) == length(_BC_GOALS)
        @test !any(l -> occursin("existence_error", l), ours)
        if _R_SWIPL
            theirs = _rswipl(
                _bc_clauses(), _BC_GOALS; extra=":- set_prolog_flag(occurs_check, $mode).\n"
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

"An engine with the values of `vs` put into term references; `(ld, t)`."
function _bc_engine(vs::Vector{_R})
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
_bc_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)
_bc_ctx() = LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing)

@testset "the meter: \\= and functor/3 on terms on the stack make no cold traffic" begin
    ld, t = _bc_engine(
        _R[
            _rf("f", _rv(1), _rs("b")), _rf("f", _rs("a"), _rv(2)), _rs("a"), _rg(2.5),
            _rf("g", _rs("x"), _rs("y")),
            _rv(3), _rv(4)
        ]
    )
    c0 = _bc_counts(ld)
    @test LK.pl_not_unify2_va(ld, t, 2, _bc_ctx()) == LK.FFALSE          # f(X, b) \= f(a, Y): unifiable
    @test LK.pl_not_unify2_va(ld, t + 2, 2, _bc_ctx()) == LK.FTRUE       # a \= 2.5
    @test LK.pl_functor3_va(ld, t + 4, 3, _bc_ctx()) == LK.FTRUE         # functor(g(x, y), N, A)
    @test _bc_counts(ld) == c0
end
