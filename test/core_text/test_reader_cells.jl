# ORIGINAL: L1e step e6 — the reader on the global stack (pl-read.c term_stack, readValHandle, build_term,
# the list cells, bind_variable_names/bind_variables/check_singletons on the cells; src/pl-read.jl; the
# workspace's L1_plan/stageL1e_design.md §6). The differentials of what is read stay in test_read_term_swipl.jl
# and test_canonical_readatom_swipl.jl (unchanged). test/core_text/test_reader_cells.jl — on every term type:
#   * white-box: a variable read IS its first cell — each later occurrence references it, and the
#     `variable_names` list's binding references the same cell;
#   * the meter: reading a term with lists, compounds, numbers, a string and the variable options through
#     read_term_from_atom/3 makes no cold export, import, variable read or boundary pair.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_rc_ctx() = LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing)

"An engine, a term reference holding the atom `text`, the result's and the options' references."
function _rc_engine(text::String, opts::_R)
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 3)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, t + 1, _rs(text), pvm)
    LK.putSlotValue!(ld, t + 2, _rv(1), pvm)
    LK.putSlotValue!(ld, t + 3, opts, pvm)
    return ld, t
end
_rc_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)

@testset "white-box: a variable read is its first cell, shared by its occurrences and its name's binding" begin
    ld, t = _rc_engine("f(X, g(X), Y)", _rlist(_rf("variable_names", _rv(2))))
    @test LK.pl_read_term_from_atom3_va(ld, t, 3, _rc_ctx()) == LK.FTRUE
    k, w, _ = LK._deref_loc(ld, -(t + 2))
    @test k == LK.DU_WORD && LK._is_gcompound(w)
    q = LK.valPtr(w)
    _, _, px = LK._deref_loc(ld, q + 1)                      # f's first argument: X's cell
    _, gw, _ = LK._deref_loc(ld, q + 2)
    kx2, _, px2 = LK._deref_loc(ld, LK.valPtr(gw) + 1)      # g(X)'s argument: the same cell
    @test kx2 == LK.DU_CELL && px2 == px
    # variable_names: ['X' = X, 'Y' = Y] — the first pair's value is X's cell
    _, ow, _ = LK._deref_loc(ld, -(t + 3))                   # the options list
    _, vn, _ = LK._deref_loc(ld, LK.valPtr(ow) + 1)          # its element variable_names(L)
    _, lw, _ = LK._deref_loc(ld, LK.valPtr(vn) + 1)          # L
    _, pw, _ = LK._deref_loc(ld, LK.valPtr(lw) + 1)          # the first element 'X' = X
    kv, _, pv = LK._deref_loc(ld, LK.valPtr(pw) + 2)
    @test kv == LK.DU_CELL && pv == px
end

@testset "the meter: read_term_from_atom/3 with the variable options makes no cold traffic" begin
    ld, t = _rc_engine(
        "foo(X, [a, b, 1.5 | T], g(X, \"str\"), 42, [], h(_Y), {c})",
        _rlist(_rf("variable_names", _rv(2)), _rf("variables", _rv(3)))
    )
    c0 = _rc_counts(ld)
    @test LK.pl_read_term_from_atom3_va(ld, t, 3, _rc_ctx()) == LK.FTRUE
    @test LK.PL_is_compound(ld, t + 1)
    @test _rc_counts(ld) == c0
end
