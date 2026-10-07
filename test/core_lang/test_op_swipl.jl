# ORIGINAL: the operator tables (R1b) against swipl 10.1.16; upstream's own units (tests/core_text/test_op.pl) need current_op/3 (V9's non-deterministic built-ins) and the reader (R1d).
# test/core_lang/test_op_swipl.jl — R1b's gate (port_inventory row R1; user, 2026-10-07):
#   * the operators visible from `user` — `system`'s defaults through the super module — as a SET
#     against swipl's `current_op/3` in a fresh swipl, the one difference pinned: `$` (fx 1) is
#     defined by boot/init.pl (Prolog, R2), not by pl-op.c's table;
#   * `currentOperator` and `priorityOperator` by kind;
#   * `op/3` through the query API: every outcome — `ok` or the error term, its context qualified —
#     identical to swipl's, then what it defined; cancelling `+`'s infix kind in `user` hides
#     `system`'s, as test_op.pl's `inherit` unit checks through current_op/3.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _OP = lk_term_type(Union{Int64, Float64, String})
_ops(x) = lk_sym(_OP, Symbol(x))
_opg(v) = lk_gnd(_OP, v)
_opv() = mk_var(_OP, LK.fresh_var_keys!(1))
_opf(f, xs::_OP...) = mk_expr(_OP, _OP[_ops(f), xs...])
_oplist(xs::_OP...) = foldr((h, t) -> _opf("[|]", h, t), xs; init=mk_nil(_OP))

"An atom as `write_canonical/1` writes it: a name of symbol characters bare, else quoted as needed."
function _opatom(t::_OP)::String
    n = String(lk_name(t))
    !is_nil(t) && !isempty(n) && all(in("#\$&*+-./:<=>?@^~\\"), n) && return n
    return lk_atom_text(t)
end

"`t` as `write_canonical/1` writes it, its variables `_` (each occurs once in these terms)."
function _opwrite(t::_OP)::String
    k = kind(t)
    k === VAR && return "_"
    k === SYM && return _opatom(t)
    if k === GND
        v = lk_value(t)
        v isa String && return "\"$v\""
        return string(v)
    end
    return _opwrite(child(t, 1)) * "(" *
           join((_opwrite(child(t, i)) for i in 2:nchildren(t)), ",") *
           ")"
end

"`op(P, T, N)` through the query API in database `gd`: `ok`, `failed` or `err E`."
function _oprun(gd, ld, p::_OP, t::_OP, n::_OP)::String
    proc = LK.isCurrentProcedure(sym_key(_ops(:op)), 3, LK.MODULE_system(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 3)
    ld.slots[a + 1], ld.slots[a + 2], ld.slots[a + 3] = p, t, n
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        "ok"
    elseif rc == LK.PL_S_EXCEPTION
        "err " * _opwrite(LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1]))
    else
        "failed"
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"The operators visible from `user`, as `Name-Type-Priority` texts (swipl's `writeq` of them), sorted."
function _opvisible(gd)::Vector{String}
    b = Tuple{_OP, UInt8, Int16}[]
    LK.scanVisibleOperators!(gd, LK.MODULE_user(gd), nothing, 0, 0x00, b, true)
    out = String[]
    for (n, ty, pr) in b
        pr == 0 && continue                                 # a cancelled operator
        push!(out, "$(lk_name(n))-$(lk_name(LK.operatorTypeToAtom(_OP, ty)))-$pr")
    end
    return sort!(out)
end

const _OP_SWIPL = Sys.which("swipl")
const _OP_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

# the op/3 goals: (P, T, N) as both systems take them, and swipl 10.1.16's outcome (probed
# 2026-10-07), the context `system:op/3`
const _OP_SYSCTX = "context(:(system,/(op,3)),_)"
_operr(f) = "err error($f,$(_OP_SYSCTX))"
const _OP_GOALS = [
    ((_opg(1201), _ops(:xfx), _ops(:foo)), "op(1201,xfx,foo)",
        _operr("domain_error(operator_priority,1201)")),
    ((_opg(-1), _ops(:xfx), _ops(:foo)), "op(-1,xfx,foo)",
        _operr("domain_error(operator_priority,-1)")),
    ((_opg(500), _ops(:xxx), _ops(:foo)), "op(500,xxx,foo)",
        _operr("domain_error(operator_specifier,xxx)")),
    ((_opg(500), _ops(:xfx), _opg(1)), "op(500,xfx,1)", _operr("type_error(list,1)")),
    ((_opv(), _ops(:xfx), _ops(:foo)), "op(_,xfx,foo)", _operr("instantiation_error")),
    ((_opg(500), _opv(), _ops(:foo)), "op(500,_,foo)", _operr("instantiation_error")),
    ((_opg(500), _ops(:xfx), _opv()), "op(500,xfx,_)", _operr("instantiation_error")),
    ((_ops(:a), _ops(:xfx), _ops(:foo)), "op(a,xfx,foo)", _operr("type_error(integer,a)")),
    (
        (_opg(1.5), _ops(:xfx), _ops(:foo)),
        "op(1.5,xfx,foo)",
        _operr("type_error(integer,1.5)")
    ),
    ((_opg(99999999999), _ops(:xfx), _ops(:foo)), "op(99999999999,xfx,foo)",
        _operr("representation_error(int)")),
    ((_opg(500), _ops(:xfx), _ops(",")), "op(500,xfx,',')",
        _operr("permission_error(modify,operator,',')")),
    ((_opg(500), _ops(:xfx), _ops("|")), "op(500,xfx,'|')",
        _operr("permission_error(create,operator,'|')")),
    ((_opg(1100), _ops(:xfy), _ops("|")), "op(1100,xfy,'|')", "ok"),
    ((_opg(0), _ops(:xfx), _ops("|")), "op(0,xfx,'|')", "ok"),
    ((_opg(500), _ops(:xfx), _opf(":", _ops(:system), _ops(:foo))),
        "op(500,xfx,system:foo)",
        "err error(permission_error(redefine,operator,:(system,foo)),context(:(system,/(op,3)),'system operators are protected'))"
    ),
    ((_opg(500), _ops(:xfx), _oplist(_ops(:a), _ops(:b))), "op(500,xfx,[a,b])", "ok"),
    ((_opg(500), _ops(:xfx), _oplist(_ops(:a), _opg(1))), "op(500,xfx,[a,1])",
        _operr("type_error(atom,1)")),
    ((_opg(500), _ops(:xfx), _opf("[|]", _ops(:a), _ops(:b))), "op(500,xfx,[a|b])",
        _operr("type_error(list,b)")),
    ((_opg(500), _ops(:xfx), mk_nil(_OP)), "op(500,xfx,[])", "ok"),
    (
        (_opg(500), _ops(:xfx), _opf(":", _ops(:user), _ops(:bar))),
        "op(500,xfx,user:bar)",
        "ok"
    ),
    ((_opg(-1), _ops(:xfx), _opf(":", _ops(:user), _ops(:baz))), "op(-1,xfx,user:baz)",
        _operr("domain_error(operator_priority,-1)")),
    ((_opg(1), _ops(:xfx), _ops("x y")), "op(1,xfx,'x y')", "ok")
]

@testset "the operators visible from user: system's defaults (pl-op.c)" begin
    gd = LK.PL_global_data{_OP}()
    ours = _opvisible(gd)
    @test length(ours) == 66
    @test "+-fy-200" in ours && "+-yfx-500" in ours && ".-yfx-100" in ours &&
        ":=-xfx-800" in ours
    @test isempty(LK.MODULE_user(gd).operators)             # all of them in `system`
    if _OP_SWIPL !== nothing
        prog = """
            :- initialization(main, main).
            main :- forall(current_op(P, T, N), format("~w-~w-~w~n", [N, T, P])).
            """
        theirs = mktempdir() do d
            f = joinpath(d, "ops.pl")
            write(f, prog)
            sort!(split(chomp(read(`swipl -q $f`, String)), '\n'))
        end
        # the one difference: `$` (fx 1) comes from boot/init.pl (Prolog, R2), not pl-op.c's table
        @test setdiff(theirs, ours) == ["\$-fx-1"]
        @test isempty(setdiff(ours, theirs))
    elseif _OP_SWIPL_REQUIRED
        @test _OP_SWIPL !== nothing                         # LOGICKERNEL_REQUIRE_SWIPL=1
    end
end

@testset "currentOperator and priorityOperator, by kind" begin
    gd = LK.PL_global_data{_OP}()
    plus = _ops("+")
    @test LK.currentOperator(gd, nothing, plus, LK.OP_PREFIX) == (true, LK.OP_FY, 200)
    @test LK.currentOperator(gd, nothing, plus, LK.OP_INFIX) == (true, LK.OP_YFX, 500)
    @test !LK.currentOperator(gd, nothing, plus, LK.OP_POSTFIX)[1]
    @test LK.priorityOperator(gd, nothing, plus) == 500
    @test LK.priorityOperator(gd, nothing, _ops(":-")) == 1200
    @test LK.priorityOperator(gd, nothing, _ops(:foo)) == 0
    @test LK.currentOperator(gd, nothing, _ops(:dynamic), LK.OP_PREFIX) ==
        (true, LK.OP_FX, 1150)
    @test LK.atomToOperatorType(_OP, _ops(:yfx)) == LK.OP_YFX &&
        LK.atomToOperatorType(_OP, _ops(:x)) == 0
    @test lk_name(LK.operatorTypeToAtom(_OP, LK.OP_XFY)) === :xfy
    @test LK.operatorTypeToAtom(_OP, 0x00) === nothing
end

@testset "op/3 through the query API, every outcome as swipl's" begin
    gd = LK.PL_global_data{_OP}()
    ld = LK.PL_local_data{_OP}()
    ours = [_oprun(gd, ld, g...) for (g, _, _) in _OP_GOALS]
    pinned = [w for (_, _, w) in _OP_GOALS]
    bad = [(i, ours[i], pinned[i]) for i in eachindex(ours) if ours[i] != pinned[i]]
    isempty(bad) || foreach(b -> println(stderr, "  differs: ", b), bad)
    @test isempty(bad)
    @test ld.exception_term == 0
    # what it defined, in user
    user = LK.MODULE_user(gd)
    @test LK.currentOperator(gd, user, _ops(:a), LK.OP_INFIX) == (true, LK.OP_XFX, 500)
    @test LK.currentOperator(gd, user, _ops(:b), LK.OP_INFIX) == (true, LK.OP_XFX, 500)
    @test LK.currentOperator(gd, user, _ops(:bar), LK.OP_INFIX) == (true, LK.OP_XFX, 500)
    @test LK.currentOperator(gd, user, mk_nil(_OP), LK.OP_INFIX) == (true, LK.OP_XFX, 500)
    @test LK.currentOperator(gd, user, _ops("|"), LK.OP_INFIX)[1] == false    # op(0, xfx, '|')
    @test !LK.currentOperator(gd, user, _ops(:foo), LK.OP_INFIX)[1]           # nothing defined
    if _OP_SWIPL !== nothing
        prog = IOBuffer()
        println(prog, ":- initialization(main, main).")
        println(prog, "r(G) :- catch((G -> R = ok ; R = failed), E, R = err(E)),")
        println(
            prog, "    ( R = err(X) -> write('err '), write_canonical(X) ; write(R) ), nl."
        )
        println(prog, "main :- ", join(("r($t)" for (_, t, _) in _OP_GOALS), ", "), ".")
        theirs = mktempdir() do d
            f = joinpath(d, "op3.pl")
            write(f, String(take!(prog)))
            split(chomp(read(`swipl -q $f`, String)), '\n')
        end
        # swipl's variables print as `_A`, `_123`: compare with the kernel's `_`
        norm(s) = replace(s, r"_[A-Z0-9][A-Za-z0-9_]*" => "_")
        @test norm.(theirs) == ours
    elseif _OP_SWIPL_REQUIRED
        @test _OP_SWIPL !== nothing
    end
end

@testset "op(0, xfx, +) in user hides system's infix + (test_op.pl `inherit`, without current_op/3)" begin
    gd = LK.PL_global_data{_OP}()
    ld = LK.PL_local_data{_OP}()
    @test _oprun(gd, ld, _opg(0), _ops(:xfx), _ops("+")) == "ok"
    user = LK.MODULE_user(gd)
    @test !LK.currentOperator(gd, user, _ops("+"), LK.OP_INFIX)[1]
    @test LK.currentOperator(gd, LK.MODULE_system(gd), _ops("+"), LK.OP_INFIX)[1]
    @test LK.priorityOperator(gd, user, _ops("+")) == 200     # the prefix kind is still visible
    @test LK.currentOperator(gd, user, _ops("+"), LK.OP_PREFIX) == (true, LK.OP_FY, 200)
    # current_op(_, yfx, +) finds only the cancelled entry: it fails, as upstream's
    b = Tuple{_OP, UInt8, Int16}[]
    LK.scanVisibleOperators!(gd, user, _ops("+"), 0, LK.OP_YFX, b, true)
    @test all(e -> e[3] == 0, b)
    @test _oprun(gd, ld, _opg(500), _ops(:yfx), _ops("+")) == "ok"
    @test LK.currentOperator(gd, user, _ops("+"), LK.OP_INFIX) == (true, LK.OP_YFX, 500)
end
