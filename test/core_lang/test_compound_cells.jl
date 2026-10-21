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
    # the reverse map (TRANSITIONAL with the memo): a cell bound to the export through the TERM
    # unifier takes the compound's own word — no copy, no import counted
    c = LK.allocGlobalCells!(ld, 1)
    i0 = ld.cold_imports
    @test LK.do_unify(ld, LK._cell_var(ld, c), t1) == LK.BOOLEX_TRUE
    @test ld.gstack[c] == w && ld.cold_imports == i0
    LK.Undo!(ld, m)                                             # backtrack below p
    @test ld.gterms[p] === nothing && !(p in view(ld.gterm_pos, 1:(ld.ngterm)))   # went with gTop
    @test LK._export_pos(ld, t1) == 0                           # the reverse map's entry is dead with it
    q, _ = _cc_layout!(ld, :g, 1)                               # a DIFFERENT compound at p
    @test q == p
    t2 = LK._compound_term(ld, q)
    @test t2 !== t1                                             # a NEW term, never the old one
    # the stale export stored now is a COPY (an import, counted) — never p's word; both its arguments are the
    # variables of cells freed with p (the export is one level deep: the first cell held `a`, the second was
    # unbound), keyed variables now, each bound to a fresh cell (f3b-1: the cold import of a variable,
    # counted too): the compound and its two variables, 3
    @test LK._compound_word!(ld, t1) != w && ld.cold_imports == i0 + 3
    @test sym_key(child(t2, 1)) == sym_key(_cc_s(:g)) && nchildren(t2) == 2
    LK.DiscardMark(ld, m)
end

# the high-water mark (the audit's D-0010): `gterm_top` is the highest position holding an export,
# so an `Undo!` that frees none is O(1) — and one that frees some leaves it the highest survivor
@testset "the export memo's high-water mark: Undo! scans only below it" begin
    ld, s = _cc_engine()
    m0 = LK.Mark(ld)
    pa, _ = _cc_layout!(ld, :a, 1)
    LK._compound_term(ld, pa)
    @test ld.gterm_top == pa
    m1 = LK.Mark(ld)
    pb, _ = _cc_layout!(ld, :b, 1)
    LK._compound_term(ld, pb)
    pc, _ = _cc_layout!(ld, :c, 1)
    tc = LK._compound_term(ld, pc)
    @test pa < pb < pc && ld.gterm_top == pc && ld.ngterm == 3
    m2 = LK.Mark(ld)
    LK.allocGlobalCells!(ld, 2)                                 # cells, no export, above pc
    LK.Undo!(ld, m2)                                            # frees no export: memo untouched
    LK.DiscardMark(ld, m2)
    @test ld.gterm_top == pc && ld.ngterm == 3 && ld.gterms[pc] === tc
    LK.Undo!(ld, m1)                                            # below pb: b and c go, a stays
    LK.DiscardMark(ld, m1)
    @test ld.gterms[pb] === nothing && ld.gterms[pc] === nothing &&
        ld.gterms[pa] !== nothing
    @test ld.ngterm == 1 && ld.gterm_top == pa                  # the highest survivor
    m3 = LK.Mark(ld)
    pd, _ = _cc_layout!(ld, :d, 2)                              # reuses pb's cells
    @test pd == pb
    LK._compound_term(ld, pd)
    @test ld.gterm_top == pd
    LK.Undo!(ld, m3)
    LK.DiscardMark(ld, m3)
    @test ld.gterms[pd] === nothing && ld.gterm_top == pa && ld.ngterm == 1
    LK.Undo!(ld, m0)                                            # everything: the memo is empty
    LK.DiscardMark(ld, m0)
    @test ld.ngterm == 0 && ld.gterm_top == 0 && ld.gterms[pa] === nothing
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
    # the compound, and (L1f f3b-1) the keyed variable bound to a fresh cell: two imports, counted
    @test LK._is_gcompound(ld.slots[s]) && ld.cold_imports == n0 + 2
    r = LK.resolve_term(ld, LK.slotValue(ld, s))
    x = LK.deRef(ld, _rv(7))                                    # the keyed variable: its cell's
    @test kind(x) === VAR && var_key(x) != UInt64(7)
    @test _rsrc(r) == "f(a,g(1,V$(var_key(x))))"                # the variable IS that cell
    g = LK.valPtr(ld.gstack[LK.valPtr(ld.slots[s]) + 2])        # g(1, X)'s functor cell
    @test LK._deref_loc(ld, g + 2)[1] == LK.DU_CELL             # a cell, no boundary word
end
