# ORIGINAL: a variable whose FIRST occurrence is a test (`==`, `\==`, var/1, nonvar/1) inside `\+` in a branch of `;` — upstream's tests/test.pl `control(not-3)` … `(not-7)` and one case per clause-entry point, against a LIVE swipl under default flags and under `optimise`; tests/test.pl has no mirror file here, so this file shadows no upstream path.
# test/core_lang/test_firstvar_swipl.jl — pl-comp.c compileBodyEQ, compileBodyNEQ, alwaysFirstVar (upstream's 7dba157e and 27c742f0), the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# THE DEFECT THESE GUARD (fixed upstream in 7dba157e and 27c742f0; the kernel carried a defensive
# initialisation of its own until it took both). A test on a variable's first occurrence emitted
# `C_VAR` — or, under `optimise`, only `I_TRUE`/`I_FAIL` — WITHOUT marking the variable as seen. Inside
# `\+` in one branch of `;` the code after the disjunction then assumed the branch had initialised
# it: on the success path of `\+` the variable's cell kept whatever the local stack held.
# `fill4/4` leaves `garbage` in the slots the next frame reuses, as upstream's tests do.
function _rfv_clauses()
    A, B, C, D, E, V, W = (_rv(k) for k in 1:7)
    xyz = _rs("xyz")
    f(x) = _rf("f", x)
    nv(x) = _rf("nonvar", x)
    eq(x, y) = _rf("==", x, y)
    neq(x, y) = _rf("\\==", x, y)
    fill = _rf("fill4", _rs("a"), _rs("b"), _rs("c"), _rs("garbage"))
    fill5 = _rf("fill5", _rs("a"), _rs("b"), _rs("c"), _rs("garbage"), _rs("garbage2"))
    "As `ctl`, for a predicate with TWO such variables: `C = g(V, W)`, both unbound, and distinct."
    ctl2(name, notn) = (
        _rs(name),
        _rconj(
            fill5, _rf(notn, _rv(11), _rv(12), C), _rf("=", C, _rf("g", V, W)),
            _rf("var", V),
            _rf("var", W), neq(V, W)
        )
    )
    "`control(not-N)`: the garbage, the call, and `C = f(V), var(V)`."
    ctl(name, notn) = (
        _rs(name),
        _rconj(fill, _rf(notn, _rv(11), _rv(12), C), _rf("=", C, f(V)), _rf("var", V))
    )
    # one predicate per point that hands a frame to a clause: the only clause, the first of two,
    # after a clause that fails in its own frame, after one that fails in a frame below
    fvbody = _rconj(
        eq(A, B), _rnot(_rconj(eq(D, _rg(1)), neq(E, _rg(2)), eq(A, _rs("zz")))),
        _rf("=", C, _rf("g", D, E))
    )
    fvh(name) = _rf(name, A, B, C)
    other(name) = _rf(name, _rv(21), _rv(22), _rv(23))
    "The garbage, the call with equal arguments, and both cells fresh, unbound and distinct."
    ent(name, p) = (
        _rs(name),
        _rconj(
            fill, _rf(p, _rs("x"), _rs("x"), C), _rf("=", C, _rf("g", V, W)),
            _rf("var", V),
            _rf("var", W), neq(V, W)
        )
    )
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("fill4", _rv(31), _rv(32), _rv(33), _rv(34)), nothing),
        (_rf("one", _rg(2)), nothing),
        # tests/test.pl, 7dba157e: ==/2 and \==/2 inside \+ in a branch of ;
        (_rf("not3", A, B, C),
            _rconj(
                _ror(_rit(_rs("fail"), _rs("true")), _rnot(_rconj(nv(A), eq(D, _rg(1))))),
                _rf("=", C, f(D))
            )),
        (_rf("not4", A, B, C),
            _rconj(
                _ror(_rs("fail"), _rnot(_rconj(nv(A), neq(D, _rg(1))))), _rf("=", C, f(D))
            )),
        (_rf("not5", A, B, C),
            _rconj(
                _ror(_rconj(nv(A), neq(D, _rg(1))), _rnot(_rconj(nv(A), eq(D, _rg(2))))),
                _rf("=", C, f(D))
            )),
        # tests/test.pl, 27c742f0: var/1 and nonvar/1, which the optimiser replaces by true or fail
        (_rf("not6", A, B, C),
            _rconj(
                _ror(_rconj(nv(A), eq(A, xyz)), _rnot(_rconj(nv(A), _rf("var", D)))),
                _rf("=", C, f(D))
            )),
        (_rf("not7", A, B, C),
            _rconj(
                _ror(_rconj(nv(A), eq(A, xyz)), _rnot(_rconj(nv(A), nv(D)))),
                _rf("=", C, f(D))
            )),
        ctl("ctl3", "not3"), ctl("ctl4", "not4"), ctl("ctl5", "not5"), ctl("ctl6", "not6"),
        ctl("ctl7", "not7"),
        # the other shapes of the same two functions, which upstream's units do not reach (each
        # was a SURVIVING mutant of its guard, 2026-10-13): the constant on the LEFT, and two
        # variables, both met here first
        (_rf("fill5", _rv(31), _rv(32), _rv(33), _rv(34), _rv(35)), nothing),
        (_rf("not8", A, B, C),
            _rconj(
                _ror(_rit(_rs("fail"), _rs("true")), _rnot(_rconj(nv(A), eq(_rg(1), D)))),
                _rf("=", C, f(D))
            )),
        (_rf("not9", A, B, C),
            _rconj(
                _ror(_rs("fail"), _rnot(_rconj(nv(A), neq(_rg(1), D)))), _rf("=", C, f(D))
            )),
        (_rf("not10", A, B, C),
            _rconj(
                _ror(_rit(_rs("fail"), _rs("true")), _rnot(_rconj(nv(A), eq(D, E)))),
                _rf("=", C, _rf("g", D, E))
            )),
        (_rf("not11", A, B, C),
            _rconj(
                _ror(_rs("fail"), _rnot(_rconj(nv(A), neq(D, E)))),
                _rf("=", C, _rf("g", D, E))
            )),
        ctl("ctl8", "not8"), ctl("ctl9", "not9"), ctl2("ctl10", "not10"),
        ctl2("ctl11", "not11"),
        (fvh("fvtrust"), fvbody),
        (fvh("fvfirst"), fvbody),
        (_rf("fvfirst", _rs("zz"), _rs("zz"), _rs("zz")), nothing),
        (other("fvshallow"), _rs("fail")), (fvh("fvshallow"), fvbody),
        (other("fvdeep"), _rf("one", _rg(1))), (fvh("fvdeep"), fvbody),
        ent("ent_trust", "fvtrust"), ent("ent_first", "fvfirst"),
        ent("ent_shallow", "fvshallow"),
        ent("ent_deep", "fvdeep")
    ]
end

const _RFV_GOALS = _R[
    _rs(n) for n in (
        "ctl3", "ctl4", "ctl5", "ctl6", "ctl7", "ctl8", "ctl9", "ctl10", "ctl11",
        "ent_trust",
        "ent_first", "ent_shallow", "ent_deep"
    )
]

"A database holding `clauses`, compiled with the `optimise` flag as given."
function _rfv_db(clauses, optimise::Bool)::_RDB
    db = _RDB()
    db.ld.prolog_flag_optimise = optimise
    for (h, b) in clauses
        _radd!(db, h, b)
    end
    return db
end

for (optimise, flag) in ((false, "default flags"), (true, "optimise = true"))
    @testset "a first occurrence under \\+ in a branch of ;: answers equal swipl's, $flag" begin
        clauses = _rfv_clauses()
        db = _rfv_db(clauses, optimise)
        ours = String[]
        for g in _RFV_GOALS
            for (a, det) in _rcall(db, g; at=(qid, k) -> (@test _rpools_live(db.ld)))
                push!(ours, a * (det ? " det" : " nondet"))
            end
            push!(ours, "end")
        end
        # every answer once: the variable after the disjunction is unbound
        @test count(==("end"), ours) == length(_RFV_GOALS)
        @test length(ours) == 2 * length(_RFV_GOALS)
        if _R_SWIPL
            extra = optimise ? ":- set_prolog_flag(optimise, true).\n" : ""
            theirs = _rswipl(clauses, _RFV_GOALS; extra=extra)
            @test ours == theirs
            ours == theirs ||
                println(stderr, "  ", flag, "\n    kernel ", ours, "\n    swipl  ", theirs)
        elseif _R_SWIPL_REQUIRED
            @test false
        end
    end
end

# Under `optimise` the test on the first occurrence is gone from the code — and the variable is
# initialised all the same (`alwaysFirstVar`, pl-comp.c): `C_VAR` follows the `I_TRUE`/`I_FAIL`.
@testset "under optimise a replaced test still initialises its variable (alwaysFirstVar)" begin
    db = _rfv_db(_rfv_clauses(), true)
    for (p, replaced) in (("not6", :I_TRUE), ("not7", :I_FAIL))
        cl =
            _rproc(db, _rf(p, _rv(81), _rv(82), _rv(83))).definition.impl_clauses.first_clause.clause
        ops = [LK.codeTable(o).name for o in _rops(cl)]
        # the replaced test, and right after it the variable's initialisation
        @test any(k -> ops[k] === replaced && ops[k + 1] === :C_VAR, 1:(length(ops) - 1))
        # the test on D is not compiled: one I_NONVAR (on A, twice seen: `nonvar(A)` twice) and no I_VAR
        @test !(:I_VAR in ops) && count(==(:I_NONVAR), ops) == 2
    end
end
