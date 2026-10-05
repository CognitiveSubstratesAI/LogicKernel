# ORIGINAL: the procedure a body goal calls and the operands that will refer to it (V1; user, 2026-10-04); swipl has no unit test of lookupBodyProcedure, and its call operand is a pointer.
# test/compile/test_call_operands.jl — what a body goal's call instruction will refer to
# (src/pl-comp.jl `lookupBodyProcedure`, `addProcedure!`, `Output_3!`, `Output_an!`, `Output_n!`).
# TERM-GENERIC: runtests.jl runs it on every implementation.
#   * `lookupBodyProcedure` returns the DATABASE's procedure for the goal's functor — the one
#     `lookupProcedure` gives, created if new, shared by every goal with that functor;
#   * it refuses a goal that is not callable with `type_error(callable, Goal)`: `$expr/n` — a call
#     through the meta-call, V9 (user, 2026-10-04) — and what compileSubClause refuses, probed in
#     swipl 10.1.16 (`assertz((p :- 1))`, `(p :- 1.5)`, `(p :- "s")` and `(p :- [])` raise it,
#     `(p :- '[]')` does not); a compound named `[]` is callable (c:3471, `fdef->name != ATOM_nil`);
#   * the clause's procedure table: an operand is a 1-based index into it, each entry the very
#     procedure, as the literal table holds the very terms (DIVERGES: upstream's operand is the
#     pointer);
#   * `Output_3!` and `Output_n!` emit the instruction and every operand word.
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))
include(joinpath(@__DIR__, "..", "term_under_test.jl"))

const _O = lk_term_type(Union{Int64, Float64, String})
_os(n) = lk_sym(_O, Symbol(n))
_oe(xs::_O...) = mk_expr(_O, _O[xs...])
_of(f, xs::_O...) = _oe(_os(f), xs...)
_og(v) = lk_gnd(_O, v)
_ov(k::Int) = lk_var(_O, UInt64(k))

"The culprit of the `type_error(callable, _)` `lookupBodyProcedure` raises for `goal`, or `nothing`."
function _ocallable_error(gd, goal::_O)
    try
        LK.lookupBodyProcedure(gd, goal, LK.MODULE_user(gd))
        return nothing
    catch e
        e isa LK.CallableTypeError{_O} || rethrow()
        return e.culprit
    end
end

@testset "lookupBodyProcedure: the database's procedure for the goal's functor" begin
    gd = LK.PL_global_data{_O}()
    user = LK.MODULE_user(gd)
    q = sym_key(_os(:q))
    @test LK.isCurrentProcedure(q, 2, user) === nothing
    pq = LK.lookupBodyProcedure(gd, _of(:q, _ov(1), _og(1)), user)    # created: q/2 is new
    @test LK.isCurrentProcedure(q, 2, user) === pq
    @test pq === LK.lookupProcedure(_os(:q), 2, user)
    @test LK.lookupBodyProcedure(gd, _of(:q, _og(2), _of(:f, _ov(3))), user) === pq   # shared
    @test LK.lookupBodyProcedure(gd, _of(:q, _ov(1)), user) !== pq      # q/1 is another functor
    a = LK.lookupBodyProcedure(gd, _os(:go), user)                      # an atom goal: go/0
    @test a === LK.lookupProcedure(_os(:go), 0, user)
    LK.setDynamicDefinition!(pq.definition, true)                       # defined: the current one
    @test LK.isDefinedProcedure(gd, pq)
    @test LK.lookupBodyProcedure(gd, _of(:q, _ov(1), _ov(2)), user) === pq
    @test length(user.procedures) == 3
end

@testset "lookupBodyProcedure: callable as compileSubClause decides" begin
    gd = LK.PL_global_data{_O}()
    user = LK.MODULE_user(gd)
    @test _ocallable_error(gd, _os("[]")) === nothing                  # '[]': a text atom
    @test _ocallable_error(gd, _oe(mk_nil(_O), _os(:x))) === nothing    # [](x): named ATOM_nil
    nilx = LK.lookupBodyProcedure(gd, _oe(mk_nil(_O), _os(:x)), user)
    @test nilx === LK.lookupProcedure(mk_nil(_O), 1, user)
    @test nilx !== LK.lookupProcedure(_os("[]"), 1, user)      # not '[]'(x)
    refused = [
        _oe(_ov(1), _os(:a)),                       # $expr/2: a variable head
        _oe(_of(:curry, _os(:f)), _os(:x)),         # $expr/2: a compound head
        _oe(_og(1), _os(:a)),                       # $expr/2: a grounded head
        _oe(),                                      # $expr/0: no head
        _og(1),                                     # swipl: type_error(callable, 1)
        _og(1.5),                                   # swipl: type_error(callable, 1.5)
        _og("s"),                                   # swipl: type_error(callable, "s")
        mk_nil(_O)                                  # swipl: type_error(callable, [])
    ]
    n0 = length(user.procedures)
    for g in refused
        @test _ocallable_error(gd, g) === g
    end
    @test length(user.procedures) == n0             # a refused goal creates no procedure
end

@testset "the procedure table: operands index it, entries are the procedures" begin
    gd = LK.PL_global_data{_O}()
    user = LK.MODULE_user(gd)
    pr = LK.lookupProcedure(_os(:r), 1, user)
    ci = LK.compileInfo{_O}(1, user, pr)
    @test ci.module_ === user && ci.procedure === pr && isempty(ci.procedures)
    pa = LK.lookupBodyProcedure(gd, _of(:a, _ov(1)), user)
    pb = LK.lookupBodyProcedure(gd, _os(:b), user)
    @test LK.addProcedure!(ci, pa) == LK.code(1)
    @test LK.addProcedure!(ci, pb) == LK.code(2)
    @test ci.procedures[1] === pa && ci.procedures[2] === pb
    cl = LK.compileClause(gd, _of(:r, _og(7)), nothing, pr, user)      # a fact calls nothing
    @test cl.procedures isa Vector{LK.Procedure{_O}} && isempty(cl.procedures)
    @test cl.predicate === pr.definition
end

@testset "Output_3!, Output_an!, Output_n!: the instruction, then every operand word" begin
    user = LK.MODULE_user(LK.PL_global_data{_O}())
    ci = LK.compileInfo{_O}(0, user, LK.lookupProcedure(_os(:o), 0, user))
    c, x, y, z = LK.I_ENTER, LK.code(11), LK.code(12), LK.code(13)
    LK.Output_3!(ci, c, x, y, z)
    @test ci.codes == [c, x, y, z]
    LK.Output_n!(ci, c, (x, y), 2)
    LK.Output_n!(ci, c, (z,), 1)
    LK.Output_n!(ci, c, (z,), 0)
    @test ci.codes == [c, x, y, z, c, x, y, c, z, c]
    LK.Output_an!(ci, (x, y, z), 2)
    @test ci.codes[(end - 1):end] == [x, y]
    @test_throws ArgumentError LK.Output_an!(ci, (x,), 2)
end
