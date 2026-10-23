# ORIGINAL: L1f f1c — same_term/2 (pl-prims.c PL_same_term, same_term/2; the workspace's
# L1_plan/stageL1f_design.md §2.4) against a LIVE swipl; upstream's own tests of same_term/2 are run when
# plunit runs (R2), so this file shadows no upstream path.
# test/core_lang/test_same_term_swipl.jl — on every term type:
#   * a differential against swipl: an alias, two compounds built alike, atoms, floats, big integers,
#     strings, `1` against `1.0`, two variables and two aliased ones; copy_term/2 sharing a ground term and
#     a ground subterm (COPY_SHARE), duplicate_term/2 not; a variable and a compound met twice in a copy
#     (one copy each); findall/3's answer against the original, a compound met twice in an answer, a cyclic
#     answer (records as upstream's byte code, L1f f1a);
#   * PL_same_term from Julia on the same terms;
#   * on a term type with big integers: `2**70` twice against swipl, and PL_same_term on slots' side values
#     and value-table words (equalIndirect, audit D-0117 (a)).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _ST_PROG = """
st(G, R) :- ( G -> R = true ; R = false ).
s_alias(R) :- X = f(a), st(same_term(X, X), R).
s_built(R) :- st(same_term(f(a), f(a)), R).
s_atom(R) :- st(same_term(a, a), R).
s_float(R) :- X is 1.5, Y is 3.0/2, st(same_term(X, Y), R).
s_big(R) :- X is 2**60, Y is 2**60, st(same_term(X, Y), R).   % indirect (past a tagged integer), Int64
s_string(R) :- st(same_term("abc", "abc"), R).
s_int_float(R) :- X is 1.0, st(same_term(1, X), R).
s_vars(R) :- st(same_term(_, _), R).
s_alias_var(R) :- V = W, st(same_term(V, W), R).
s_copy_ground(R) :- T = f(a), copy_term(T, C), st(same_term(T, C), R).
s_copy_sub(R) :- T = f(g(a), _), copy_term(T, f(G, _)), T = f(G0, _), st(same_term(G, G0), R).
s_dup(R) :- T = f(a), duplicate_term(T, C), st(same_term(T, C), R).
s_copy_var2(R) :- copy_term(f(X, X), f(A, B)), st(same_term(A, B), R).
s_copy_cmp2(R) :- Z = h(_), copy_term(g(Z, Z), g(P, Q)), st(same_term(P, Q), R).
s_bag_orig(R) :- T = f(a), findall(T, true, [A]), st(same_term(T, A), R).
s_bag_twice(R) :- Z = h(_), findall(g(Z, Z), true, [g(P, Q)]), st(same_term(P, Q), R).
s_bag_ground2(R) :- Z = h(a), findall(g(Z, Z), true, [g(P, Q)]), st(same_term(P, Q), R).
s_bag_cyclic(R) :- C = [a|C], findall(C, true, [D]), D = [_|E], st(same_term(D, E), R).
"""

const _ST_GOALS = (
    "s_alias", "s_built", "s_atom", "s_float", "s_big", "s_string", "s_int_float", "s_vars",
    "s_alias_var", "s_copy_ground", "s_copy_sub", "s_dup", "s_copy_var2", "s_copy_cmp2",
    "s_bag_orig", "s_bag_twice", "s_bag_ground2", "s_bag_cyclic"
)

"A database holding `_ST_PROG`."
function _st_db()::_RDB
    db = _RDB()
    f = joinpath(mktempdir(), "st.pl")
    write(f, _ST_PROG)
    st, _, _ = LK.load_file!(db.gd, db.ld, f)
    @assert st === :ok "test_same_term_swipl: the program did not load: $st"
    return db
end

@testset "same_term/2, as swipl" begin
    goals = _R[_rf(n, _rv(60)) for n in _ST_GOALS]
    ours = _rlines(_st_db(), goals)
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> startswith(l, "exception("), ours)
    # the kernel's side alone (also where swipl is absent: Pkg.test) — swipl 10.1.18's answers, probed 2026-10-19
    for (g, r) in (
        ("s_alias", true), ("s_built", false), ("s_atom", true), ("s_float", true),
        ("s_big", true),
        ("s_string", true), ("s_int_float", false), ("s_vars", false),
        ("s_alias_var", true),
        ("s_copy_ground", true), ("s_copy_sub", true), ("s_dup", false),
        ("s_copy_var2", true),
        ("s_copy_cmp2", true), ("s_bag_orig", false), ("s_bag_twice", true),
        ("s_bag_cyclic", true)
    )
        @test "$g($r) det" in ours
    end
    if _R_SWIPL
        theirs = _rswipl(Tuple{_R, Union{Nothing, _R}}[], goals; extra=_ST_PROG)
        @test ours == theirs
        ours == theirs || @info "same_term differential" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "PL_same_term from Julia" begin
    db = _RDB()
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    a, b, c = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test !LK.PL_same_term(ld, a, b)                        # two fresh variables
    ld.slots[b + 1] = ld.slots[a + 1]                       # the same cell
    @test LK.PL_same_term(ld, a, b)
    p = LK._alloc_compound!(
        ld, LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("f")), 1), 1
    )
    ld.gstack[p + 1] = LK._atom_word!(ld, _rs("a"))
    ld.slots[a + 1] = ld.slots[b + 1] = LK.consPtr(p, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    @test LK.PL_same_term(ld, a, b)                         # the same compound
    q = LK._alloc_compound!(
        ld, LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("f")), 1), 1
    )
    ld.gstack[q + 1] = LK._atom_word!(ld, _rs("a"))
    ld.slots[c + 1] = LK.consPtr(q, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    @test !LK.PL_same_term(ld, a, c)                        # another compound, built alike
    ld.slots[a + 1] = LK._vword!(ld, _rg(Int64(2)^60))
    ld.slots[b + 1] = LK._vword!(ld, _rg(Int64(2)^60))
    @test LK.PL_same_term(ld, a, b)                         # two indirects, equal (equalIndirect)
    ld.slots[c + 1] = LK._vword!(ld, _rg(1.0))
    ld.slots[b + 1] = LK.consInt(1)
    @test !LK.PL_same_term(ld, c, b)                        # 1.0 and 1
end

# audit D-0117 (a): two indirects are the same term when `equalIndirect` says so (pl-prims.c:2423 at
# 8e1bc111) — a value-table word or a slot's side value alike. Before 2026-10-23 a side value took
# `===`, so two side values of one big integer were NOT the same term (`BigInt`s are distinct objects).
# On a term type with big integers (the file's own has none until plan step T1).
const _STB = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
const _ST_BIG_PROG = """
st(G, R) :- ( G -> R = true ; R = false ).
s_big70(R) :- X is 2**70, Y is 2**70, st(same_term(X, Y), R).
"""

@testset "same_term/2 on two big integers 2**70, as swipl (audit D-0117 (a))" begin
    gd = LK.PL_global_data{_STB}()
    ld = LK.PL_local_data{_STB}(gd)
    f = joinpath(mktempdir(), "stb.pl")
    write(f, _ST_BIG_PROG)
    st, _, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    ans = LK.query_answers(
        ld, mk_expr(_STB, _STB[lk_sym(_STB, :s_big70), mk_var(_STB, UInt64(1))])
    )
    @test length(ans) == 1 && sym_text(child(ans[1], 2)) == "true"   # swipl 10.1.18: true, probed 2026-10-23
    if _R_SWIPL
        @test _rswipl(
            Tuple{_R, Union{Nothing, _R}}[], _R[_rf("s_big70", _rv(1))]; extra=_ST_BIG_PROG
        ) ==
            ["s_big70(true) det", "end"]
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "PL_same_term on side values and value-table words (audit D-0117 (a))" begin
    gd = LK.PL_global_data{_STB}()
    ld = LK.PL_local_data{_STB}(gd)
    g(v) = lk_gnd(_STB, v)
    LK.PL_open_foreign_frame(ld)
    x, y, z, u, s1, s2, i1 = (LK.PL_new_term_ref(ld) for _ in 1:7)  # older than `inner`: side values
    inner = LK.PL_open_foreign_frame(ld)
    LK.setSlotValue!(ld, x + 1, g(big(2)^70))
    LK.setSlotValue!(ld, y + 1, g(big(2)^70))
    LK.setSlotValue!(ld, u + 1, g(big(2)^70 + 1))
    LK.setSlotValue!(ld, s1 + 1, g("abc"))
    LK.setSlotValue!(ld, i1 + 1, g(1.0))
    for t in (x, y, u, s1, i1)
        @test LK._is_side_word(LK._deref_loc(ld, -(t + 1))[2])
    end
    w = LK.PL_new_term_ref(ld)                              # young: value-table words
    ld.slots[z + 1] = LK._vword!(ld, g(big(2)^70))
    ld.slots[s2 + 1] = LK._vword!(ld, g("abc"))
    ld.slots[w + 1] = LK.consInt(1)
    @test LK.PL_same_term(ld, x, y)                         # two side values, one big integer
    @test LK.PL_same_term(ld, x, z) && LK.PL_same_term(ld, z, x)   # a side value, a value-table word
    @test LK.PL_same_term(ld, s1, s2)                       # one string
    @test LK.PL_same_term(ld, x, x)                         # the same side word
    @test !LK.PL_same_term(ld, x, u)                        # 2**70 and 2**70+1
    @test !LK.PL_same_term(ld, i1, w) && !LK.PL_same_term(ld, w, i1)   # 1.0 and 1 (SWI's identity)
    @test !LK.PL_same_term(ld, x, s1)
    LK.PL_discard_foreign_frame(ld, inner)
end
