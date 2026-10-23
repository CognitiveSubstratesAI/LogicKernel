# ORIGINAL: L1c — compounds on the global stack (pl-data.h: a functor word and its argument cells, referenced by `consPtr(p, TAG_COMPOUND|STG_GLOBAL)`); upstream has no counterpart test (its compounds are always cells).
# test/core_lang/test_compound_cells.jl — white-box, on every term type:
#   * a binding of an argument cell made after the layout, and undone, is seen on the cell;
#   * a term written into a slot is copied onto the stack: a compound word in the slot, the value read back.
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

# f3-3: the export memo and its high-water mark (`gterms`/`ngterm`/`gterm_top`), the reverse map and the
# one-level export (`_compound_term`) went with the keyed variables; what holds on the cells stays
@testset "a binding made after the layout, and undone, is seen on the argument cell" begin
    ld, s = _cc_engine()
    p, w = _cc_layout!(ld, :f, 1)
    m = LK.Mark(ld)
    LK._bind_const!(ld, p + 1, LK._atom_word!(ld, _cc_s(:b)))  # bound after the layout…
    @test ld.gstack[p + 1] == LK._atom_word!(ld, _cc_s(:b))
    LK.Undo!(ld, m)                                             # …and undone on the cell
    @test ld.gstack[p + 1] == LK.word(0) && LK._deref_loc(ld, p + 1)[1] == LK.DU_CELL
    LK.DiscardMark(ld, m)
end

@testset "the import: a term copied onto the stack, read back as its value" begin
    ld, s = _cc_engine()
    t = _rf("f", _cc_s(:a), _rf("g", _rg(Int64(1)), _rv(7)))
    n0 = ld.cold_imports
    LK.setSlotValue!(ld, s, t)
    # the compound, and (Q3) the variable a fresh cell: two imports, counted
    @test LK._is_gcompound(ld.slots[s]) && ld.cold_imports == n0 + 2
    r = lk_answer(ld, s - 1)
    x = child(child(r, 3), 3)
    # the answer's variable is the export's, not the caller's (D-0083: until f3-3 `resolve_term` handed
    # back the caller's `V7` through `import_origin` — old expectation `_rsrc(r) == "f(a,g(1,V7))"`)
    @test kind(x) === VAR && var_key(x) != UInt64(7)
    @test _rsrc(r) == "f(a,g(1,V$(var_key(x))))"
    g = LK.valPtr(ld.gstack[LK.valPtr(ld.slots[s]) + 2])        # g(1, X)'s functor cell
    @test LK._deref_loc(ld, g + 2)[1] == LK.DU_CELL             # a cell, no boundary word
end

# f3-2 (audit D-0111 Q3): the import maps a term's variables per WRITE (`_write_var_word!`'s write-local
# map), so one variable met twice in one write — nested too — is ONE cell, and two writes are two
@testset "the import: one variable twice in one write is one cell" begin
    ld, s = _cc_engine()
    LK.setSlotValue!(ld, s, _rf("h", _rv(8), _rf("k", _rv(8))))
    t2 = LK.PL_new_term_ref(ld)
    LK.setSlotValue!(ld, t2 + 1, _rf("h", _rv(8), _rf("k", _rv(8))))
    r1, r2 = lk_answers(ld, s - 1, t2)                          # one export: shared stays shared
    x1 = child(r1, 2)
    @test kind(x1) === VAR && var_key(child(child(r1, 3), 2)) == var_key(x1)
    @test var_key(child(r2, 2)) == var_key(child(child(r2, 3), 2)) != var_key(x1)
end
