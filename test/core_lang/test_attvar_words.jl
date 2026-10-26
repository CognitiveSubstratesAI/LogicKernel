# ORIGINAL: AV1 — the word layer of attributed variables (audit D-0122, condition 1); upstream tests attributed
# variables only through put_attr/3 and friends, which come with AV2.
# test/core_lang/test_attvar_words.jl — white-box, on every term type, with attributed variables BUILT BY HAND
# (as pl-attvar.c `make_new_attvar` lays one out: a link cell registered on the chain, the attvar word
# `consPtr(&gp[1], TAG_ATTVAR|STG_GLOBAL)`, its attribute list `[]`; the variable bound to a reference to it):
#   * emptyStacks makes the wakeup list's head and tail with PERMANENT, unbound cells (Q1 (a));
#   * the dereferences give an attributed variable its own outcome (`DU_ATTVAR`, `DREF_ATTVAR`, with its
#     position) and RAISE on a word of no known kind, where they read it as a value-table word before AV1;
#   * `linkValI` links an attributed variable by REFERENCE (`_cell_link!`, `_slot_link!`, `_slot_link_loc!`,
#     `=..`'s argument cells) — never a second copy of its word — and raises on a word of no known kind;
#   * the index key of an attributed variable is 0 and `is_var` takes it for a variable (pl-index.c);
#   * `register_attvar` chains the link cells newest first; `Undo!` and the frozen region's release cut the
#     chain back to the new top (`reclaim_attvars`), a link AT the top kept;
#   * `bindConst` binds an unbound cell as `varBindConst` and, since AV3, an attributed variable as
#     `bind_attvar_const` (the cell assigned, a `wakeup/3` registered, `ALERT_WAKEUP` set), reached from the
#     canBind sites AV1 converted (`h_const`, `PL_unify_atomic`). D-0083: until AV3 these asserted the
#     refusal (`_aw_not_ported`: `e isa LK.NotPortedError && e.step == "AV3"`, audit D-0150 item 3).
# The last testset is a LIVE differential: the paths AV1 touched (head unification of lists and compounds,
# first-argument indexing, `=..`, msort/2, the FLI's atomic unification) answer as swipl at the pin. AV1 adds
# no Prolog-visible behaviour, so evidence/av/rows.tsv has no AV1 rows: these rows are regression rows whose
# expected answers are swipl's own, read live.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"A fresh engine (`_rdb`'s) with a foreign frame open."
function _aw_engine()
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    LK.PL_open_foreign_frame(db.ld)
    return db.ld, db
end

"""
Turn the unbound global cell `p` into a reference to a new attributed variable with no attributes, laid
out as pl-attvar.c `make_new_attvar` does; the attvar cell's position.
"""
function _aw_attvar!(ld, p::Int)::Int
    gp = LK.allocGlobalCells!(ld, 3)
    LK.register_attvar(ld, gp)                                      # link_attvar()
    ld.gstack[gp + 2] = ld.atom_nil_w                               # gp[1] = ATOM_nil
    ld.gstack[gp + 1] = LK.consPtr(gp + 2, LK.TAG_ATTVAR | LK.STG_GLOBAL)   # gp[0] = consPtr(&gp[1], …)
    LK._bind_const!(ld, p, LK.makeRefG(gp + 1))                     # Trail(p, makeRefG(gp))
    return gp + 1
end

"A word of no kind the kernel's stacks hold (an upstream float word: the kernel's floats are value-table words)."
_aw_bogus() = LK.consPtr(7, LK.TAG_FLOAT | LK.STG_GLOBAL)

"Whether `f()` raises an `ErrorException` whose message contains `needle`."
function _aw_raises(f, needle::String)::Bool
    try
        f()
    catch e
        return e isa ErrorException && occursin(needle, e.msg)
    end
    return false
end

# D-0083: until AV3 the bindConst sites were asserted to REFUSE an attributed variable —
# `_aw_not_ported(f)`: `f()` raises `e isa LK.NotPortedError && e.step == "AV3"` (D-0150 item 3). Since AV3
# they bind it as upstream's `bind_attvar_const` (pl-attvar.c:207-219), which `_aw_binds` asserts.
"""
Whether `f(t, av)` — `av` a FRESH hand-built attributed variable, `t` a term reference to it — returns true
and binds it as `bind_attvar_const` does (AV3): the attvar cell assigned a non-attvar word, a `wakeup/3` on the
list, `ALERT_WAKEUP` set, no error; then everything is undone (`Undo!`, `updateAlerted`).
"""
function _aw_binds(ld, f)::Bool
    m = LK.Mark(ld)
    t, av = _aw_ref_attvar!(ld)
    w = ld.gstack[av]
    h = LK._attvar_head_cell(ld)
    r = f(t, av)
    ok =
        r === true && ld.gstack[av] != w && !LK.isAttVar(ld.gstack[av]) &&
        ld.gstack[h] != 0 &&
        (ld.alerted & LK.ALERT_WAKEUP) != 0 && ld.exception_term == 0
    LK.Undo!(ld, m)
    LK.updateAlerted(ld)
    return ok && ld.gstack[h] == 0 && ld.gstack[h + 1] == 0 && ld.alerted == 0
end

"A new term reference whose cell is turned into an attributed variable: `(t, attvar position)`."
function _aw_ref_attvar!(ld)
    t = LK.PL_new_term_ref(ld)
    return t, _aw_attvar!(ld, LK.unRef(ld.slots[t + 1]))
end

@testset "emptyStacks: the wakeup list's head and tail, PERMANENT unbound cells after the exception's" begin
    ld = LK.PL_local_data{_R}(LK.PL_global_data{_R}())
    perm = LK.SIZEOF_FLIFRAME
    @test (ld.attvar_head, ld.attvar_tail) == (perm + 4, perm + 5)
    h = ld.slots[ld.attvar_head + 1]
    t = ld.slots[ld.attvar_tail + 1]
    @test LK.isRef(h) && LK.isRef(t)
    @test LK.unRef(h) == ld.exception_cells + 4 && LK.unRef(t) == ld.exception_cells + 5
    @test ld.gstack[LK.unRef(h)] == 0 && ld.gstack[LK.unRef(t)] == 0      # the list is empty
    @test ld.attvar_attvars == 0                                          # no attributed variable
    @test ld.tmp_h == perm + 6
end

@testset "deRef: an attributed variable is DU_ATTVAR / DREF_ATTVAR with its cell; an unknown word raises" begin
    ld, _ = _aw_engine()
    t, av = _aw_ref_attvar!(ld)
    k, w, p = LK._deref_loc(ld, -(t + 1))                         # through the slot's reference and the cell's
    @test (k, p) == (LK.DU_ATTVAR, av) && w == ld.gstack[av] && LK.isAttVar(w)
    @test LK._deref_loc(ld, av) == (LK.DU_ATTVAR, w, av)           # the attvar cell itself
    x = LK.unRef(ld.slots[t + 1])
    a = LK.argp_t{_R}(LK.ARGP_GLOBAL, x, ld.placeholder)
    @test LK._argp_deref_word(ld, a) == (LK.DREF_ATTVAR, LK.word(av))
    # a word of no known kind: an internal error, no longer read as a value-table word
    b = LK.allocGlobalCells!(ld, 1)
    ld.gstack[b] = _aw_bogus()
    @test _aw_raises(() -> LK._deref_loc(ld, b), "global cell $b holds")
    @test _aw_raises(
        () -> LK._argp_deref_word(ld, LK.argp_t{_R}(LK.ARGP_GLOBAL, b, ld.placeholder)),
        "global cell $b holds"
    )
    # the known kinds are unchanged: an unbound cell, an atom, a small integer, a value-table word
    c = LK.allocGlobalCells!(ld, 1)
    @test LK._deref_loc(ld, c) == (LK.DU_CELL, LK.word(0), c)
    ld.gstack[c] = LK._atom_word!(ld, _rs("a"))
    @test LK._deref_loc(ld, c)[1] == LK.DU_WORD
    ld.gstack[c] = LK.consInt(Int64(7))
    @test LK._deref_loc(ld, c)[1] == LK.DU_VALUE
    ld.gstack[c] = LK._vword!(ld, _rg("s"))
    @test LK._deref_loc(ld, c)[1] == LK.DU_VALUE
    @test LK._argp_deref_word(ld, LK.argp_t{_R}(LK.ARGP_GLOBAL, c, ld.placeholder)) ==
        (LK.DREF_TERM, LK.word(0))
    # the slot branch (audit D-0150 item 4): `SLOT_VALUE` and a value-table word are DREF_TERM; an unwritten
    # slot (0) or a word of no known kind raises, where both were DREF_TERM before
    s = LK.PL_new_term_ref(ld)
    sa = LK.argp_t{_R}(LK.ARGP_SLOT, s, ld.placeholder)
    ld.slots[s + 1] = LK._vword!(ld, _rg("s"))
    @test LK._argp_deref_word(ld, sa) == (LK.DREF_TERM, LK.word(0))
    ld.slots[s + 1] = LK.SLOT_VALUE
    @test LK._argp_deref_word(ld, sa) == (LK.DREF_TERM, LK.word(0))
    ld.slots[s + 1] = LK.word(0)
    @test _aw_raises(() -> LK._argp_deref_word(ld, sa), "slot word")
    ld.slots[s + 1] = _aw_bogus()
    @test _aw_raises(() -> LK._argp_deref_word(ld, sa), "slot word")
    ld.slots[s + 1] = LK.makeRefG(c)                               # written again: a reference
end

@testset "linkValI: an attributed variable is linked by reference, never copied; an unknown word raises" begin
    ld, _ = _aw_engine()
    t, av = _aw_ref_attvar!(ld)
    # into a global cell (H_VAR's write mode, B_ARGVAR, bindConsVal)
    g = LK.allocGlobalCells!(ld, 1)
    LK._cell_link!(ld, g, t + 1)
    @test ld.gstack[g] == LK.makeRefG(av)
    # into a slot (B_ARGVAR into a frame, PL_put_term)
    s = LK.PL_new_term_ref(ld)
    LK._slot_link!(ld, s + 1, t + 1)
    @test ld.slots[s + 1] == LK.makeRefG(av)
    # from a dereferenced location (setHandle(h, linkValI(p)))
    s2 = LK.PL_new_term_ref(ld)
    LK._slot_link_loc!(ld, s2 + 1, LK._deref_loc(ld, -(t + 1)))
    @test ld.slots[s2 + 1] == LK.makeRefG(av)
    # a word of no known kind, behind a slot's reference
    b = LK.allocGlobalCells!(ld, 1)
    ld.gstack[b] = _aw_bogus()
    tb = LK.PL_new_term_ref(ld)
    ld.slots[tb + 1] = LK.makeRefG(b)
    @test _aw_raises(() -> LK._cell_link!(ld, g, tb + 1), "global cell $b holds")
    @test _aw_raises(() -> LK._slot_link!(ld, s + 1, tb + 1), "global cell $b holds")
end

@testset "=..: an attributed variable in the list becomes a reference in the new compound" begin
    ld, _ = _aw_engine()
    t = LK.PL_new_term_refs(ld, 2)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, t + 1, _rv(1), pvm)
    LK.putSlotValue!(ld, t + 2, _rlist(_rs("g"), _rv(2)), pvm)
    # the list's second element: an unbound cell, turned into an attributed variable
    _, lw, _ = LK._deref_loc(ld, -(t + 2))
    _, tw, _ = LK._deref_loc(ld, LK.valPtr(lw) + 2)
    hk, _, hp = LK._deref_loc(ld, LK.valPtr(tw) + 1)
    @test hk == LK.DU_CELL
    av = _aw_attvar!(ld, hp)
    ctx = LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    @test LK.pl_univ2_va(ld, t, 2, ctx) == LK.FTRUE              # t =.. [g, Attvar]
    k, w, _ = LK._deref_loc(ld, -(t + 1))
    @test k == LK.DU_WORD && LK._is_gcompound(w)
    @test ld.gstack[LK.valPtr(w) + 1] == LK.makeRefG(av)           # *p++ = needsRef(*h) ? makeRefG(h) : *h
end

@testset "indexing: an attributed variable keys 0 and is a variable for is_var" begin
    ld, _ = _aw_engine()
    f = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("f")), 2)
    q = LK._alloc_compound!(ld, f, 2)                               # f(Attvar, a)
    av = _aw_attvar!(ld, q + 1)
    ld.gstack[q + 2] = LK._atom_word!(ld, _rs("a"))
    v = LK.argv_cells(ld, q)
    @test LK._argv_key(v, 0) == 0                                  # indexOfWord: TAG_ATTVAR → 0
    @test LK._argv_is_var(v, 0)                                    # is_var: canBind(*p)
    @test LK._index_key_loc(ld, LK.DU_ATTVAR, ld.gstack[av], av) == 0
    @test LK._argv_key(v, 1) == LK._atom_word!(ld, _rs("a")) && !LK._argv_is_var(v, 1)
end

@testset "the attributed variables' chain: newest first; Undo! and the frozen release cut it back" begin
    ld = LK.PL_local_data{_R}(LK.PL_global_data{_R}())
    @test ld.attvar_attvars == 0
    g1 = LK.allocGlobalCells!(ld, 1)
    LK.register_attvar(ld, g1)
    @test ld.attvar_attvars == g1 && ld.gstack[g1] == 0             # the chain's end: setVar(*gp)
    m = LK.Mark(ld)                                                # its globaltop is g1: a link AT the top
    @test m.globaltop == g1
    c = LK.allocGlobalCells!(ld, 1)
    av = _aw_attvar!(ld, c)
    g2 = av - 1
    @test ld.attvar_attvars == g2 && ld.gstack[g2] == LK.makeRefG(g1)   # *gp = makeRefG(attvars)
    LK.Undo!(ld, m)
    @test ld.attvar_attvars == g1                                  # the link above the top dropped, g1 kept
    @test ld.gTop == g1
    m0 = LK.Mark(ld)
    LK.Undo!(ld, m0)
    @test ld.attvar_attvars == g1                                  # nothing above: nothing dropped
end

# A SEPARATE engine: were the Undo! phase's chain left dangling (a mutant), the cells it freed are reused here, an
# attributed variable's link cell would be its own chain head and `reclaim_attvars` would loop (AV1-C2 timed out so).
@testset "the attributed variables' chain: the frozen region's release cuts it back, as Undo!" begin
    ld = LK.PL_local_data{_R}(LK.PL_global_data{_R}())
    g1 = LK.allocGlobalCells!(ld, 1)
    LK.register_attvar(ld, g1)
    # the frozen region's release lowers gTop as Undo! does, the chain with it
    m2 = LK.Mark(ld)
    c2 = LK.allocGlobalCells!(ld, 1)
    _aw_attvar!(ld, c2)
    @test ld.attvar_attvars > m2.globaltop
    LK.freezeGlobal!(ld)
    LK._release_frozen!(ld, m2, true)
    @test ld.gTop == m2.globaltop && ld.attvar_attvars == g1
    # reclaim_attvars itself: an empty chain stays empty at any top, 0 included
    ld.attvar_attvars = 0
    LK.reclaim_attvars(ld, 0)
    @test ld.attvar_attvars == 0
end

@testset "bindConst: an unbound cell as varBindConst; an attributed variable as bind_attvar_const (AV3)" begin
    ld, _ = _aw_engine()
    x = LK.allocGlobalCells!(ld, 1)
    m = LK.Mark(ld)
    a = LK._atom_word!(ld, _rs("a"))
    LK.bindConst(ld, x, a)                                         # below the mark: bound and trailed
    @test ld.gstack[x] == a && LK._trail_pos(ld.trail[end]) == x
    LK.Undo!(ld, m)
    @test ld.gstack[x] == 0
    @test _aw_binds(ld, (t, av) -> (LK.bindConst(ld, av, a); ld.gstack[av] == a))   # *av = c
    # the canBind sites AV1 converted reach it: h_const, from a location and from a cell, and PL_unify_atomic
    @test _aw_binds(ld, (t, av) -> LK._unify_const_loc(ld, -(t + 1), _rs("a")))
    @test _aw_binds(ld, (t, av) -> LK._h_const_cell!(ld, av, a) == LK.H_CONST_MATCH)
    @test _aw_binds(ld, (t, av) -> LK.PL_unify_atomic(ld, t, _rs("a")))
    t, av = _aw_ref_attvar!(ld)
    w = ld.gstack[av]
    # h_const's catch-all: a word of no known kind raises, no longer H_CONST_TERMS
    b = LK.allocGlobalCells!(ld, 1)
    ld.gstack[b] = _aw_bogus()
    @test _aw_raises(() -> LK._h_const_cell!(ld, b, a), "global cell $b holds")
    @test ld.gstack[av] == w
end

# ── AV1b (audit D-0150 item 1): the one-line canBind sites the census marked for AV1 ─────────────────────────
# Each converted site, on a hand-built attributed variable: a bind reaches `bindConst`, which binds it with a
# wakeup since AV3 (`_aw_binds`; until AV3 refused, the NotPortedError naming AV3 — D-0083 note at
# `_aw_binds`); a type test answers "variable". Upstream lines at the pin cbf4e189.

"The pending exception's formal term, read on the cells (no export): an atom's name, else `:compound`."
function _aw_formal(ld)
    ld.exception_term == 0 && return nothing
    _, b, _ = LK._deref_loc(ld, -(ld.exception_term + 1))
    _, f, _ = LK._deref_loc(ld, LK.valPtr(b) + 1)                 # error(Formal, _)
    return LK.isAtomW(f) ? lk_name(LK._atom_value(ld, f)) : :compound
end

"The position of the unbound cell at argument `i` of the compound term reference `t` holds."
function _aw_arg_cell(ld, t, i::Int)::Int
    _, w, _ = LK._deref_loc(ld, -(t + 1))
    k, _, p = LK._deref_loc(ld, LK.valPtr(w) + i)
    @assert k == LK.DU_CELL
    return p
end

@testset "AV1b: the FLI's and compare/3's canBind sites bind an attributed variable through bindConst" begin
    ld, _ = _aw_engine()
    h, tl = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test _aw_binds(ld, (t, av) -> LK.PL_unify_list(ld, t, h, tl))             # pl-fli.c:3652, :3673
    @test _aw_binds(ld, (t, av) -> LK.PL_unify_functor(ld, t, _rs("f"), 2))    # pl-fli.c:3210, :3229
    @test _aw_binds(ld, (t, av) -> LK.PL_unify_functor(ld, t, _rs("f"), 0))    # … :3232 (arity 0)
    f2 = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("f")), 2)
    @test _aw_binds(ld, (t, av) -> LK.PL_unify_compound(ld, t, f2))            # pl-fli.c:3175, :3195
    @test _aw_binds(ld, (t, av) -> LK.PL_unify_integer(ld, t, 5))              # pl-fli.c:3460, :3462
    @test _aw_binds(ld, (t, av) -> LK.unify_int64_ex(ld, t, 5, true))          # … not a type error
    n = LK.number()
    n.type = LK.V_INTEGER
    n.i = 7                                     # a small integer skips the isVar fast path (pl-gmp.c:1507)
    @test _aw_binds(ld, (t, av) -> LK.PL_unify_number(ld, t, n))               # pl-gmp.c:1512, :1519
    n.type = LK.V_FLOAT
    n.f = 2.5
    @test _aw_binds(ld, (t, av) -> LK.PL_unify_number(ld, t, n))
    # compare/3 (pl-prims.c:2199 canBind(*d), :2227 PL_unify_atom): the order is to be bound, not given —
    # no type_error(atom, _) (`_aw_binds` asserts no pending exception)
    ctx = LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    pvm = LK.PutVarMap()
    @test _aw_binds(
        ld,
        (t, av) -> begin
            c = LK.PL_new_term_refs(ld, 3)
            ld.slots[c + 1] = LK.makeRefG(av)
            LK.putSlotValue!(ld, c + 2, _rs("a"), pvm)
            LK.putSlotValue!(ld, c + 3, _rs("b"), pvm)
            LK.pl_compare3_va(ld, c, 3, ctx) == LK.FTRUE &&
                ld.gstack[av] == LK._atom_word!(ld, _rs("<"))
        end
    )
    # the unbound cell: the same paths still bind it (bindConst → varBindConst)
    c2 = LK.PL_new_term_refs(ld, 3)
    LK.putSlotValue!(ld, c2 + 1, _rv(9), pvm)
    LK.putSlotValue!(ld, c2 + 2, _rs("a"), pvm)
    LK.putSlotValue!(ld, c2 + 3, _rs("b"), pvm)
    @test LK.pl_compare3_va(ld, c2, 3, ctx) == LK.FTRUE
    k2, w2, _ = LK._deref_loc(ld, -(c2 + 1))
    @test k2 == LK.DU_WORD && w2 == LK._atom_word!(ld, _rs("<"))
    u = LK.PL_new_term_ref(ld)
    @test LK.PL_unify_functor(ld, u, _rs("g"), 1) && LK.PL_is_compound(ld, u)
end

@testset "AV1b: the type tests take an attributed variable for a variable" begin
    ld, _ = _aw_engine()
    t, av = _aw_ref_attvar!(ld)
    u = LK.PL_new_term_ref(ld)                                            # an unbound cell
    @test LK.PL_is_variable(ld, t) && LK.PL_is_variable(ld, u)             # pl-fli.h:280 canBind(w)
    # the split slot test: I_VAR/I_NONVAR ask canBind (pl-vmi.c:3204, :3239), I_CATCH/I_CALLCLEANUP isVar
    # (pl-vmi.c:4896, :4830)
    @test LK._slot_can_bind(ld, t + 1) && LK._slot_can_bind(ld, u + 1)
    @test !LK._slot_is_var(ld, t + 1) && LK._slot_is_var(ld, u + 1)
    # ground/1: the root (pl-prims.c:884) and inside a compound (ph_ground, :862) — the attvar's cell
    @test LK.ground_cells(ld, -(t + 1)) == av
    f2 = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("f")), 2)
    q = LK._alloc_compound!(ld, f2, 2)                                    # f(a, Attvar)
    ld.gstack[q + 1] = LK._atom_word!(ld, _rs("a"))
    ld.gstack[q + 2] = LK.word(0)
    av2 = _aw_attvar!(ld, q + 2)
    g = LK.allocGlobalCells!(ld, 1)
    ld.gstack[g] = LK.consPtr(q, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    @test LK.ground_cells(ld, g) == av2
    @test (ld.gstack[q] & LK.MARK_MASK) == 0                               # unmarked again
    # codes_or_chars_to_buffer: a partial list, never "no list", never a value-table read
    pvm = LK.PutVarMap()
    _, r0 = LK.codes_or_chars_to_buffer(ld, t, false)
    @test r0.status == LK.CVT_partial                                      # pl-codelist.c:89 canBind(list)
    l1 = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, l1 + 1, _rlist(_rv(1)), pvm)                      # [Attvar]
    a1 = _aw_attvar!(ld, _aw_arg_cell(ld, l1, 1))
    b1, r1 = LK.codes_or_chars_to_buffer(ld, l1, false)
    @test b1 === nothing && r1.status == LK.CVT_partial && r1.culprit == a1   # :76 canBind(*arg)
    l2 = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, l2 + 1, _rlist(_rg(97), _rv(2)), pvm)             # [0'a, Attvar]
    _, lw2, _ = LK._deref_loc(ld, -(l2 + 1))
    _, tw2, _ = LK._deref_loc(ld, LK.valPtr(lw2) + 2)
    k2, _, p2 = LK._deref_loc(ld, LK.valPtr(tw2) + 1)
    @test k2 == LK.DU_CELL
    a2 = _aw_attvar!(ld, p2)
    b2, r2 = LK.codes_or_chars_to_buffer(ld, l2, false)
    @test b2 === nothing && r2.status == LK.CVT_partial && r2.culprit == a2   # :120 canBind(*arg)
    l3 = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, l3 + 1, _rcons(_rg(97), _rv(3)), pvm)             # [0'a|Attvar]
    _aw_attvar!(ld, _aw_arg_cell(ld, l3, 2))
    b3, r3 = LK.codes_or_chars_to_buffer(ld, l3, false)
    @test b3 === nothing && r3.status == LK.CVT_partial                    # :164 canBind(list)
    # evalExpression's default (pl-arith.c:1061, ERR_PTR_TYPE): an instantiation error, as swipl answers
    # `put_attr(X, a, 1), Y is X` and `… Y is X + 1` (probed at 10.1.19)
    r = LK.number()
    @test !LK.valueExpression(ld, t, r) && _aw_formal(ld) === :instantiation_error
    LK.PL_clear_exception(ld)
    e = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, e + 1, _rf("+", _rv(4), _rg(1)), pvm)            # Attvar + 1: the walk re-enters
    _aw_attvar!(ld, _aw_arg_cell(ld, e, 1))
    @test !LK.valueExpression(ld, e, r) && _aw_formal(ld) === :instantiation_error
    LK.PL_clear_exception(ld)
    @test isempty(ld.arith_cells) && ld.arith_top == 0
end

@testset "AV1b: var/1 and nonvar/1 in a body (I_VAR, I_NONVAR) take an attributed variable for a variable" begin
    gd = LK.PL_global_data{_R}()
    ld = LK.PL_local_data{_R}(gd)
    f = joinpath(mktempdir(), "v.pl")
    write(f, "v(X) :- var(X).\nnv(X) :- nonvar(X).\n")
    st, _, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    function call_on_attvar(name::String)
        proc = LK.isCurrentProcedure(sym_key(_rs(name)), 1, LK.MODULE_user(gd))
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_R, LK.fresh_var_keys!(1)), LK.PutVarMap())
        _aw_attvar!(ld, LK._deref_loc(ld, -(a + 1))[3])
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        rc = LK.PL_next_solution(gd, ld, qid)
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        return rc
    end
    @test call_on_attvar("v") in (LK.PL_S_TRUE, LK.PL_S_LAST)             # pl-vmi.c:3204 canBind
    @test call_on_attvar("nv") == LK.PL_S_FALSE                            # pl-vmi.c:3239 !canBind
end

# ── the live differential: the paths AV1 touched answer as swipl ────────────────────────────────────────────
_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_R, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_R}()
    ld = LK.PL_local_data{_R}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_R)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_rs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_R, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(sols, enc(mk_expr(_R, _R[_rs(name), lk_answers(ld, (a:a)...)...])))
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the helper clauses the cases call: list and compound heads (H_LIST/H_RLIST, H_LIST_FF, H_FUNCTOR), a
# constant head (h_const) and first-argument indexing over atoms, a compound and an unbound argument
const _AW_HELPERS = """
h1([H|T], H, T).
h2(f(X, Y), X, Y).
h3([A, B], A-B).
h4(a, 1).
h4(b, 2).
h4(f(_), 3).
h4(_, 4).
h5(x).
"""
const _AW_CASES = [
    "h1(L, x, [y]), R = L",                                  # H_RLIST on an unbound argument: bindConst
    "h1([p, q], H, T), R = H/T",                             # H_RLIST read mode
    "h2(Z, 1, 2), R = Z",                                    # H_FUNCTOR write mode
    "h3(L, P), L = [u, v], R = P",                           # H_LIST_FF
    "findall(K-V, h4(K, V), R)",                             # indexing: every clause
    "findall(V, h4(f(z), V), R)",                            # indexing on a compound key
    "findall(V, h4(b, V), R)",                               # … on an atom key
    "( h5(X) -> R = X ; R = none )",                         # h_const on an unbound cell
    "( h5(y) -> R = yes ; R = no )",                         # h_const against another atom
    "X =.. [g, A, B, A], R = X",                             # =..: the arguments' cells linked
    "msort([c, b, a, b], R)",                                # put_sort_list
    "functor(foo(a, b), N, A), R = N/A",                     # PL_unify_integer on an unbound cell
    "catch(functor(_, _, _), error(E, _), R = E)"            # an error row: its formal term
]

@testset "the paths AV1 touched == live swipl, through a program" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "AV1 DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        names = ["t$(i - 1)" for i in eachindex(_AW_CASES)]
        text =
            _AW_HELPERS *
            join(["t$(i - 1)(R) :- ($g).\n" for (i, g) in enumerate(_AW_CASES)])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = swipl_lines(f, names)
        kl = kernel_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test kl == sw
        # not a vacuous agreement: swipl's own lines hold a four-answer row, a variable and the error row
        @test any(l -> startswith(l, "t4 ") && occursin("i4", l), sw)
        @test any(l -> occursin("V0", l), sw)
        @test any(l -> startswith(l, "t12 ") && occursin("105,110,115", l), sw)   # `ins…`: instantiation_error
    end
end
