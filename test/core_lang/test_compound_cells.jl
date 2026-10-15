# ORIGINAL: L1c — compounds on the global stack (pl-data.h: a functor word and its argument cells, referenced by `consPtr(p, TAG_COMPOUND|STG_GLOBAL)`) and the transitional term boundary; upstream has no counterpart test (its compounds are always cells).
# test/core_lang/test_compound_cells.jl — white-box, on every term type:
#   * the cold EXPORT memo (TRANSITIONAL, until L1d/L1f; user 2026-10-15): one term per compound —
#     two reads give the SAME term (the term-level cycle detectors recognise a revisit by it) — and
#     it is tied to the stack: a compound at position p exported, `Undo!` below it, a DIFFERENT
#     compound laid out at p → a NEW term, never the old one;
#   * the export is one level deep: its arguments are the argument cells' variables, so a binding
#     made after the export, and undone, is seen through them;
#   * the cold IMPORT copies a term onto the stack: a compound word in the slot, the value read back.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "rules_common.jl"))

_cc_s(n) = lk_sym(_R, Symbol(n))
"An engine on its own database, and one term reference's slot on it."
function _cc_engine()
    ld = LK.PL_local_data{_R}(LK.PL_global_data{_R}())
    return ld, LK.PL_new_term_refs(ld, 1) + 1
end
"Lay out `name/n` on the global stack with unbound arguments; its position and word."
function _cc_layout!(ld, name::Symbol, n::Int)
    f = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _cc_s(name)), n)
    p = LK._alloc_compound!(ld, f, n)
    return p, LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
end

@testset "the export memo: one term per compound, tied to the stack" begin
    ld, s = _cc_engine()
    m = LK.Mark(ld)
    p, w = _cc_layout!(ld, :f, 2)
    ld.gstack[p + 1] = LK._atom_word!(ld, _cc_s(:a))
    t1 = LK._compound_term(ld, p)
    @test LK._compound_term(ld, p) === t1                       # the same term: identity kept
    @test ld.gterms[p] === t1 && p in view(ld.gterm_pos, 1:(ld.ngterm))
    LK.Undo!(ld, m)                                             # backtrack below p
    @test ld.gterms[p] === nothing && !(p in view(ld.gterm_pos, 1:(ld.ngterm)))   # went with gTop
    q, _ = _cc_layout!(ld, :g, 1)                               # a DIFFERENT compound at p
    @test q == p
    t2 = LK._compound_term(ld, q)
    @test t2 !== t1                                             # a NEW term, never the old one
    @test sym_key(child(t2, 1)) == sym_key(_cc_s(:g)) && nchildren(t2) == 2
    LK.DiscardMark(ld, m)
end

@testset "the export is one level deep: its arguments are the cells' variables" begin
    ld, s = _cc_engine()
    p, w = _cc_layout!(ld, :f, 1)
    t = LK._compound_term(ld, p)
    @test kind(child(t, 2)) === VAR && var_key(child(t, 2)) == LK._cell_key(ld, p + 1)
    m = LK.Mark(ld)
    LK._bind_const!(ld, p + 1, LK._atom_word!(ld, _cc_s(:b)))  # bound after the export…
    @test sym_key(LK.deRef(ld, child(t, 2))) == sym_key(_cc_s(:b))
    LK.Undo!(ld, m)                                             # …and undone: seen through it
    @test kind(LK.deRef(ld, child(t, 2))) === VAR
    @test LK._compound_term(ld, p) === t                        # the compound itself lives on
    LK.DiscardMark(ld, m)
end

@testset "the import: a term copied onto the stack, read back as its value" begin
    ld, s = _cc_engine()
    t = _rf("f", _cc_s(:a), _rf("g", _rg(Int64(1)), _rv(7)))
    n0 = ld.cold_imports
    LK.setSlotValue!(ld, s, t)
    @test LK._is_gcompound(ld.slots[s]) && ld.cold_imports == n0 + 1
    r = LK.resolve_term(ld, LK.slotValue(ld, s))
    @test _rsrc(r) == "f(a,g(1,V7))"                            # the keyed variable kept as itself
end
