# ORIGINAL: L1e step e3 — the FLI writers on CELLS (pl-fli.c PL_unify_atomic, PL_unify_list, PL_unify_functor,
# PL_unify_arg, PL_cons_list, PL_unify_integer as their cell paths, src/pl-fli.jl; the workspace's
# L1_plan/stageL1e_design.md §3). test/core_lang/test_fli_unify_cells.jl — on every term type:
#   * a differential against swipl through the built-ins that call them: functor/3 (both directions, errors),
#     term_variables/2,3 (an unbound result, a partly bound one), compare/3, atom_number/2, findall/3's result
#     list, `$skip_list/3`, and a binding undone by backtracking;
#   * white-box: a failed comparison of a value makes no value-table entry; a rewound frame leaves the cell
#     PL_unify_list bound unbound again (the trail);
#   * the meter: the writers on terms on the stack make no cold export, import, variable read or boundary pair.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_fu_k(i) = _rg(Int64(i))
"`catch(G, error(E, _), true)` with E the answer's last argument."
_fu_catch(g, e) = _rf("catch", g, _rf("error", e, _rv(90)), _rs("true"))

function _fu_clauses()
    T, N, A, L, O, R = (_rv(k) for k in 1:6)
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("fn", N, A, T), _fu_catch(_rf("functor", T, N, A), T)),
        (_rf("fd", T, N, A), _rf("functor", T, N, A)),
        (_rf("tv", T, L), _rf("term_variables", T, L)),
        (_rf("tv3", T, L, R), _rf("term_variables", T, L, R)),
        (_rf("cmp", A, N, O), _rf("compare", O, A, N)),
        (_rf("an", A, N), _fu_catch(_rf("atom_number", A, N), N)),
        (_rf("fa", L), _rf("findall", _rv(7), _ror(_rf("=", _rv(7), _rs("a")), _ror(_rf("=", _rv(7), _fu_k(2)), _rf("=", _rv(7), _rf("g", _rv(8))))), L)),
        (_rf("sk", L, N, R), _rf("\$skip_list", N, L, R)),
        (_rf("bt", T), _ror(_rconj(_rf("functor", T, _rs("f"), _fu_k(2)), _rs("fail")), _rs("true")))
    ]
end

@testset "the FLI writers on cells, as swipl" begin
    db = _rdb(_fu_clauses())
    X, Y, Z, V = _rv(50), _rv(51), _rv(52), _rv(53)
    goals = _R[
        _rf("fn", _rs("f"), _fu_k(3), V), _rf("fn", _rs("a"), _fu_k(0), V), _rf("fn", _fu_k(7), _fu_k(0), V),
        _rf("fn", _rg(1.5), _fu_k(0), V), _rf("fn", _rs("f"), _fu_k(-1), V), _rf("fn", _rf("g", _rs("x")), _fu_k(1), V),
        _rf("fd", _rf("f", _rs("a"), X), Y, Z), _rf("fd", _rs("atom"), Y, Z), _rf("fd", _fu_k(12), Y, Z),
        _rf("fd", _rf("f", _rs("a"), X), _rs("f"), _fu_k(2)), _rf("fd", _rf("f", _rs("a"), X), _rs("g"), _fu_k(2)),
        _rf("tv", _rf("f", X, _rf("g", Y, X), Z), V), _rf("tv", _rs("a"), V),
        _rf("tv", _rf("f", X, Y), _rlist(_rv(54), _rv(55))), _rf("tv", _rf("f", X, Y), _rcons(_rv(54), _rv(55))),
        _rf("tv", _rf("f", X), _rlist()), _rf("tv3", _rf("f", X, Y), V, _rlist(_rs("z"))),
        _rf("cmp", _fu_k(1), _fu_k(2), V), _rf("cmp", _rs("b"), _rs("a"), V), _rf("cmp", _rs("a"), _rs("a"), _rs("=")),
        _rf("cmp", _rs("a"), _rs("a"), _rs("<")),
        _rf("an", _rs("12"), V), _rf("an", _rs("1.5e3"), V), _rf("an", _rs("x1"), V), _rf("an", _rs("12"), _fu_k(12)),
        _rf("fa", V), _rf("sk", _rlist(_rs("a"), _rs("b")), V, _rv(56)), _rf("sk", _rcons(_rs("a"), _rv(57)), V, _rv(56)),
        _rf("bt", V)
    ]
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> occursin("existence_error", l), ours)   # every built-in here is ported
    @test "bt(_) det" in ours                              # the binding undone by backtracking
    if _R_SWIPL
        theirs = _rswipl(_fu_clauses(), goals)
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
function _fu_engine(vs::Vector{_R})
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
_fu_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)

@testset "white-box: a failed value comparison makes no entry; a rewound PL_unify_list leaves the cell unbound" begin
    ld, t = _fu_engine(_R[_rg(2.5), _rv(1), _rv(2), _rv(3)])
    n = length(ld.vtable)
    @test !LK.PL_unify_atomic(ld, t, _rg(3.5))
    @test length(ld.vtable) == n
    @test LK.PL_unify_atomic(ld, t, _rg(2.5))
    fr = LK.PL_open_foreign_frame(ld)
    @test LK.PL_unify_list(ld, t + 1, t + 2, t + 3)
    k, w, _ = LK._deref_loc(ld, -(t + 2))
    @test k == LK.DU_WORD && LK._is_gcompound(w)
    LK.PL_rewind_foreign_frame(ld, fr)
    LK.PL_close_foreign_frame(ld, fr)
    @test LK._deref_loc(ld, -(t + 2))[1] == LK.DU_CELL
end

@testset "the meter: the writers on terms on the stack make no cold traffic" begin
    ld, t = _fu_engine(_R[_rv(1), _rv(2), _rv(3), _rf("f", _rs("a"), _rv(4)), _rv(5), _rs("x"), _rv(6), _rv(7)])
    c0 = _fu_counts(ld)
    @test LK.PL_unify_functor(ld, t, _rs("g"), 2)            # binds
    @test LK.PL_unify_functor(ld, t, _rs("g"), 2)            # checks
    @test !LK.PL_unify_functor(ld, t, _rs("h"), 2)
    @test LK.PL_unify_list(ld, t + 1, t + 6, t + 7)
    @test LK.PL_unify_atomic(ld, t + 6, _rs("hd"))
    @test !LK.PL_unify_arg(ld, 1, t + 3, t + 5)              # f(a, _)'s first argument is a, not x
    @test LK.PL_unify_arg(ld, 2, t + 3, t + 5)               # its second, a variable, becomes x
    @test !LK.PL_unify_arg(ld, 3, t + 3, t + 5)              # no third argument
    @test LK.PL_cons_list(ld, t + 4, t + 5, t + 2)
    @test LK.PL_is_list(ld, t + 4)
    @test LK.PL_unify_integer(ld, t + 2, 7)
    @test _fu_counts(ld) == c0
end
