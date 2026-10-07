# ORIGINAL: the module path (V5c) unit by unit; its differentials against swipl are the qualified contexts of test_builtins_swipl.jl, test_assert_swipl.jl, test_arith_swipl.jl and the others, and MQ6 in test_rules_swipl.jl.
# test/core_lang/test_module_path.jl — V5c's units (port_inventory row V5; as decided since Q-A, and
# by the user, 2026-10-07):
#   * the module table: `system` (index 1, a system module, `unknown` = error) and `user` (index 2,
#     its super `system`), a REAL vector R2 will add to; any other name refused until R2;
#   * a definition's module is its index; `getUnknownModule` inherits through the supers;
#   * `autoImport` links a super's definition into the module's procedure; a defined procedure
#     keeps its own, a `P_AUTOLOAD` one imports nothing; `trapUndefined` installs `S_UNDEF` when
#     nothing is found;
#   * `unify_definition`: unqualified from its own module (or a system module under
#     `GP_HIDESYSTEM`), else `Module:…`; `GP_QUALIFY`; a head of fresh variables without
#     `GP_NAMEARITY`;
#   * `PL_strip_module_ex`: the innermost atom qualifier, a module that is no atom
#     (`type_error(module, M)`), a variable (`instantiation_error`), a plain term (the given module,
#     or `user`), a cyclic chain (`type_error(acyclic_term, …)`), and an unknown module refused.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MP = lk_term_type(Union{Int64, Float64, String})
_mps(x) = lk_sym(_MP, Symbol(x))
_mpf(f, xs::_MP...) = mk_expr(_MP, _MP[_mps(f), xs...])
_mpv() = mk_var(_MP, LK.fresh_var_keys!(1))

@testset "the module table: system, then user, its super" begin
    gd = LK.PL_global_data{_MP}()
    @test length(gd.modules) == 2
    sys, user = gd.modules
    @test sys === LK.MODULE_system(gd) && user === LK.MODULE_user(gd)
    @test (sys.index, user.index) == (1, 2)
    @test lk_name(sys.atom) === :system && lk_name(user.atom) === :user
    syntax = LK.M_CHARESCAPE | LK.DBLQ_STRING | LK.BQ_CODES | LK.O_RATIONAL_SYNTAX   # since R1c
    @test sys.flags == (syntax | LK.M_SYSTEM | UInt32(LK.UNKNOWN_ERROR)) &&
        isempty(sys.supers)
    @test user.flags == syntax && user.supers == [sys.index]
    @test LK.isCurrentModule(gd.modules, _mps(:user)) === user
    @test LK.isCurrentModule(gd.modules, _mps(:nomod)) === nothing
    @test LK.lookupModule(gd, _mps(:system)) === sys                # found, not created
    err = try
        LK.lookupModule(gd, _mps(:mm))
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError{_MP} && err.step == "R2"         # until module/2 (R2)
    @test length(gd.modules) == 2
    # the unknown flag: system's own, inherited by user
    @test LK.getUnknownModule(gd, sys) == LK.UNKNOWN_ERROR
    @test LK.inheritUnknown(gd, user) == LK.UNKNOWN_ERROR
    # a definition's module is its module's index
    @test LK.lookupProcedure(_mps(:p), 1, user).definition.module_ == user.index
    @test gd.procedures_dc_call_prolog0.definition.module_ == sys.index
    @test gd.procedures_equals2.definition.module_ == sys.index
end

@testset "autoImport and trapUndefined" begin
    gd = LK.PL_global_data{_MP}()
    sys, user = LK.MODULE_system(gd), LK.MODULE_user(gd)
    sysdef = LK.isCurrentProcedure(sym_key(_mps(:rational)), 1, sys).definition
    # nothing in user yet: autoImport creates the procedure and links system's definition
    @test LK.autoImport(gd, _mps(:rational), 1, user) === sysdef
    up = LK.isCurrentProcedure(sym_key(_mps(:rational)), 1, user)
    @test up !== nothing && up.definition === sysdef
    # an undefined user procedure is linked the same way, by trapUndefined
    p = LK.lookupProcedure(_mps(:string), 1, user)
    own = p.definition
    @test own.module_ == user.index
    got = LK.trapUndefined(gd, own)
    @test got === LK.isCurrentProcedure(sym_key(_mps(:string)), 1, sys).definition
    @test p.definition === got
    # a defined user procedure keeps its own: no import
    q = LK.lookupProcedure(_mps(:atom), 1, user)
    LK.setDynamicDefinition!(q.definition, true)                     # defined: P_DYNAMIC
    @test LK.autoImport(gd, _mps(:atom), 1, user) === q.definition
    # an explicit autoload import of its own imports nothing
    r = LK.lookupProcedure(_mps(:var), 1, user)
    r.definition.flags |= LK.P_AUTOLOAD
    @test LK.autoImport(gd, _mps(:var), 1, user) === nothing
    # nothing to import: trapUndefined keeps the definition and installs S_UNDEF
    u = LK.lookupProcedure(_mps(:nowhere), 0, user)
    @test u.definition.codes[1] == LK.S_VIRGIN
    @test LK.trapUndefined(gd, u.definition) === u.definition
    @test u.definition.codes[1] == LK.S_UNDEF
    @test LK.getProcDefinedDefinition(gd, u.definition) === u.definition
end

@testset "unify_definition: qualified unless it is the context's, or hidden as a system's" begin
    gd = LK.PL_global_data{_MP}()
    sys, user = LK.MODULE_system(gd), LK.MODULE_user(gd)
    ud = LK.lookupProcedure(_mps(:p), 2, user).definition
    sd = LK.isCurrentProcedure(sym_key(_mps(:compare)), 3, sys).definition
    pi(n, a) = _mpf("/", _mps(n), lk_gnd(_MP, a))
    q(m, t) = _mpf(":", _mps(m), t)
    @test lk_eq(LK.unify_definition(gd, user, ud, LK.GP_NAMEARITY), pi(:p, 2))
    @test lk_eq(
        LK.unify_definition(gd, user, sd, LK.GP_NAMEARITY), q(:system, pi(:compare, 3))
    )
    @test lk_eq(
        LK.unify_definition(gd, user, sd, LK.GP_NAMEARITY | LK.GP_HIDESYSTEM),
        pi(:compare, 3)
    )
    @test lk_eq(LK.unify_definition(gd, sys, sd, LK.GP_NAMEARITY), pi(:compare, 3))
    @test lk_eq(
        LK.unify_definition(gd, user, ud, LK.GP_NAMEARITY | LK.GP_QUALIFY),
        q(:user, pi(:p, 2))
    )
    h = LK.unify_definition(gd, user, ud, 0)                         # a head of fresh variables
    @test lk_name(child(h, 1)) === :p && nchildren(h) == 3 &&
        kind(child(h, 2)) === VAR && kind(child(h, 3)) === VAR &&
        var_key(child(h, 2)) != var_key(child(h, 3))
    z = LK.lookupProcedure(_mps(:z), 0, user).definition
    @test lk_eq(LK.unify_definition(gd, sys, z, 0), q(:user, _mps(:z)))
end

@testset "PL_strip_module_ex" begin
    gd = LK.PL_global_data{_MP}()
    sys, user = LK.MODULE_system(gd), LK.MODULE_user(gd)
    "Strip the term `t` with module `m` given: `(ok, module, plain, the pending formal)`."
    function strip(t, m=0)
        ld = LK.PL_local_data{_MP}()
        r = LK.PL_new_term_refs(ld, 2)
        ld.slots[r + 1] = t
        ok, mod = LK.PL_strip_module_ex(gd, ld, r, m, r + 1)
        formal =
            ld.exception_term == 0 ? nothing : child(ld.slots[ld.exception_term + 1], 2)
        return (ok, mod, ld.slots[r + 2], formal)
    end
    ok, m, plain, _ = strip(_mpf(":", _mps(:user), _mps(:foo)))
    @test ok && m == user.index && lk_eq(plain, _mps(:foo))
    ok, m, plain, _ = strip(_mpf(":", _mps(:user), _mpf(":", _mps(:system), _mps(:foo))))
    @test ok && m == sys.index && lk_eq(plain, _mps(:foo))           # the innermost
    ok, m, plain, _ = strip(_mps(:foo))                              # plain: user
    @test ok && m == user.index && lk_eq(plain, _mps(:foo))
    ok, m, _, _ = strip(_mps(:foo), sys.index)                       # plain, a module given
    @test ok && m == sys.index
    ok, _, _, formal = strip(_mpf(":", lk_gnd(_MP, 1), _mps(:x)))
    @test !ok && lk_eq(formal, _mpf("type_error", _mps(:module), lk_gnd(_MP, 1)))
    ok, _, _, formal = strip(_mpf(":", _mpv(), _mps(:x)))
    @test !ok && lk_eq(formal, _mps(:instantiation_error))
    err = try
        strip(_mpf(":", _mps(:mm), _mps(:x)))
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError{_MP} && err.step == "R2"
    # a cyclic chain X = user:X: stripModuleName gives up after 100 levels
    ld = LK.PL_local_data{_MP}()
    X = _mpv()
    @test LK.pl_unify!(ld, X, _mpf(":", _mps(:user), X))
    ok, _, _ = LK.stripModuleName(ld, X)
    @test !ok &&
        lk_name(child(child(ld.slots[ld.exception_term + 1], 2), 2)) === :acyclic_term
end
