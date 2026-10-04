# ORIGINAL: the precompile workload — PrecompileTools runs it while LogicKernel precompiles, so a fresh process starts with the hot paths compiled; swipl-devel is C and has no JIT to warm.
#
# MEASURED before it (2026-10-03, three fresh processes, a quiet machine): `using LogicKernel` took
# 0.02 s, then ~10 s (10.0–13.3) went to JIT these hot paths at their first call — in EVERY fresh
# process. The workload pays that once, at precompile time, for every later process: CI, the test
# runner, a fresh clone.
#
# SMALL AND REPRESENTATIVE (user, 2026-10-03): the hot paths on `DefaultTerm` only — nothing
# test-only, no other term implementation. A developer can switch it off for one checkout, so an edit
# to src/ does not pay it at every precompile: `tools/warm.sh workload off` (PrecompileTools'
# `precompile_workload` preference, in the gitignored LocalPreferences.toml). CI and fresh clones
# keep it.
using PrecompileTools: @compile_workload

"""
The hot paths on `DefaultTerm`, once each: terms, the standard order, unification, `=@=`, the term
hashes, numbers by kind, and the clause database (assert, call through the index, retract). Nothing
test-only, no other term implementation (user, 2026-10-03).
"""
function _precompile_workload()::Nothing
    T = DefaultTerm
    a, b, nil = mk_sym(T, :a), mk_sym(T, :b), mk_nil(T)
    one, half, s = mk_gnd(T, 1), mk_gnd(T, 1.5), mk_gnd(T, "s")
    x, y = mk_var(T, UInt64(1)), mk_var(T, UInt64(2))
    f, cons = mk_sym(T, :f), mk_sym(T, Symbol("[|]"))
    l = mk_expr(T, T[cons, one, mk_expr(T, T[cons, s, nil])])
    t1 = mk_expr(T, T[f, a, x, l, half])
    t2 = mk_expr(T, T[f, y, b, l, half])
    compareStandard(t1, t2)
    compareStandard(t1, t2, true)
    ld = PL_local_data{T}()
    m = Mark(ld)
    pl_unify!(ld, t1, t2)
    Undo!(ld, m)
    pl_unify_with_occurs_check!(ld, t1, t2)
    Undo!(ld, m)
    is_variant_ptr(t1, t2)
    pl_variant_sha1(t1)
    pl_variant_hash(t1)
    pl_term_hash(mk_expr(T, T[f, a, one]))
    number_kind(one) === NUM_INTEGER && int64_value(one)
    number_kind(half) === NUM_FLOAT && float_value(half)
    gd = PL_global_data{T}()
    user = MODULE_user(gd)
    proc = lookupProcedure(sym_key(mk_sym(T, :p)), 2, user)
    def = proc.definition
    setDynamicDefinition!(def, true)
    for i in 1:20
        h = mk_expr(T, T[mk_sym(T, :p), mk_gnd(T, i), i % 2 == 0 ? a : nil])
        assertDefinition!(gd, def, compileClause(gd, h, nothing, proc, user), CL_END)
    end
    lookupBodyProcedure(gd, mk_expr(T, T[mk_sym(T, :p), x, a]), user)
    goal = mk_expr(T, T[mk_sym(T, :p), mk_gnd(T, 7), x])
    pl_clause!(gd, ld, def, goal, _ -> true)
    pl_retract!(gd, ld, def, mk_expr(T, T[mk_sym(T, :p), x, nil]), _ -> false)
    return nothing
end

@compile_workload _precompile_workload()
