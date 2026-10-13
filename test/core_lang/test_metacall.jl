# ORIGINAL: the meta-call of plain goals — a variable goal, call/1 and call/N (V9e-1), against swipl; its own file, so no upstream test file's path (tests/core_lang/test_call.pl) is shadowed.
# test/core_lang/test_metacall.jl — pl-comp.c compileSubClause (I_CALL1, I_CALLN) and pl-vmi.c i_metacall_common are the code under test
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# The program: facts to call, and a caller per call form. `one/1` and `two/2` have answers and a choice.
function _rmc_clauses()
    G, X, Y, Z = (_rv(k) for k in 1:4)
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("p", _rg(1)), nothing), (_rf("p", _rg(2)), nothing),
        (_rf("p", _rg(3)), nothing),
        (_rf("q", _rs("a"), _rg(1)), nothing), (_rf("q", _rs("b"), _rg(2)), nothing),
        (_rf("add", X, Y, Z), _rf("is", Z, _rf("+", X, Y))),
        (_rf("three", X, Y, Z), _rf("=", X, _rf("t", Y, Z))),
        (_rs("nop"), nothing),
        (_rf("four", X, Y, Z, _rv(5)), _rf("=", _rv(5), _rf("f", X, Y, Z))),
        (_rf("v", G), G),                                             # I_CALL1 of a variable
        (_rf("v2", G, X), _rconj(G, _rf("=", X, _rg(9)))),            # …not the last goal
        (_rf("c1", G), _rf("call", G)),                               # call/1
        (_rf("c2", G, X), _rf("call", G, X)),                         # call/2
        (_rf("c3", G, X, Y), _rf("call", G, X, Y)),                   # call/3
        (_rf("c4", G, X, Y, Z), _rf("call", G, X, Y, Z)),             # call/4
        (_rf("c0", X), _rf("call", _rf("q", _rs("a")), X)),             # call/2 with a goal that has arguments
        (_rf("cn", X, Y), _rconj(_rf("call", _rf("add", _rg(1)), X, Y)))
    ]
end

function _rmc_goals()
    X, Y, Z = _rv(51), _rv(52), _rv(53)
    return _R[
        _rf("v", _rf("p", X)), _rf("v", _rs("nop")), _rf("v", _rf("q", X, Y)),
        _rf("v", _rf("p", _rg(2))), _rf("v", _rf("p", _rg(7))),
        _rf("v", _rf(":", _rs("user"), _rf("p", X))),
        _rf("v2", _rf("p", X), Y),
        _rf("c1", _rf("p", X)), _rf("c1", _rs("nop")),
        _rf("c2", _rs("p"), X), _rf("c2", _rf("q", _rs("b")), X),
        _rf("c3", _rs("q"), X, Y), _rf("c3", _rf("add", _rg(1)), _rg(2), X),
        _rf("c3", _rf("add"), _rg(1), _rg(2)) |> x -> _rf(
            "c4", _rs("add"), _rg(1), _rg(2), X
        ),
        _rf("c0", X), _rf("c2", _rf("three", _rg(1), _rg(2)), X),                 # arity 2 + 1 extra
        _rf("c3", _rf("four", _rg(1), _rg(2)), X, Y),                             # arity 2 + 2 extras
        _rf("c4", _rf("four", _rg(1)), X, Y, Z),
        _rf("v", _rf("is", X, _rf("+", _rg(1), _rg(2)))), _rf("v", _rf("atom", _rs("a"))),
        _rf("c2", _rs("atom"), _rs("a")), _rf("c3", _rs("is"), X, _rf("+", _rg(3), _rg(4))),
        _rf("v", _rf("var", X)), _rf("c2", _rs("var"), X),
        # goals qualified to `system`: its built-ins resolve there (user sees them too: no kill)
        _rf("v", _rf(":", _rs("system"), _rf("atom", _rs("a")))),
        _rf("c1", _rf(":", _rs("system"), _rf("atom", _rs("a")))),
        _rf("c2", _rf(":", _rs("system"), _rs("atom")), _rs("a")),
        _rf("c3", _rf(":", _rs("system"), _rs("is")), X, _rf("+", _rg(1), _rg(1))),
        _rf("v", _rf(":", _rs("user"), _rf(":", _rs("system"), _rf("var", X)))),
        _rf("cn", _rg(5), X)
    ]
end

@testset "meta-call of plain goals: answers and determinism equal swipl's" begin
    clauses = _rmc_clauses()
    goals = _rmc_goals()
    db = _rdb(clauses)
    ours = _rlines(db, goals)
    @test count(==("end"), ours) == length(goals)
    @test length(ours) > length(goals) + 10
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# The error formal a goal raises, as the kernel raises it: `error(Formal, _)` → `Formal`'s canonical
# text; `no_error` when it answers or fails.
function _rmc_formal(db::_RDB, goal::_R)::String
    f = _rmc_formal_term(db, goal)
    return f === nothing ? "no_error" : _rcanonical(f)
end

"The formal of the error `goal` raises, or `nothing`."
function _rmc_formal_term(db::_RDB, goal::_R)::Union{Nothing, _R}
    gd, ld = db.gd, db.ld
    _, n = _rfunctor(goal)
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, n)
    for i in 1:n
        ld.slots[args + i] = child(goal, i + 1)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, _rproc(db, goal),
        args
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = if rc == LK.PL_S_EXCEPTION
        e = LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1])
        child(e, 2)
    else
        nothing
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

@testset "meta-call of plain goals: the errors equal swipl's" begin
    X = _rv(61)
    clauses = _rmc_clauses()
    goals = _R[
        _rf("v", X), _rf("c1", X), _rf("c2", X, _rg(1)), _rf("c3", _rs("p"), X, X),
        _rf("v", _rg(1)), _rf("c1", _rg(1)),
        _rf("v", _rs("nosuch")), _rf("c1", _rf("nosuch", X)),
        _rf("c3", _rs("nosuch"), X, X),
        _rf("v", _rf(":", _rg(1), _rf("p", X))),                           # a qualifier that is no module
        _rf("v", _rf(":", X, _rf("p", _rg(1)))),
        _rf("c1", _rf("add", _rg(1), _rs("a"), X)),                        # an error inside the goal
        # system does not see user's predicates: the module of the goal decides (kills MC10)
        _rf("v", _rf(":", _rs("system"), _rf("p", X))),
        _rf("c2", _rf(":", _rs("system"), _rs("p")), X),
        _rf("c1", _rf(":", _rs("system"), _rf("nosuch", X))),
        _rf("v", _rg(1.5)), _rf("v", _rs("[]")),
        _rf("v", _rf("f", (_rg(1) for _ in 1:(LK.MAXARITY + 1))...)),       # arity over the maximum
        _rf("c2", _rf("f", (_rg(1) for _ in 1:LK.MAXARITY)...), _rg(1))     # …only with call/2's extra
    ]
    db = _rdb(clauses)
    ours = [_rmc_formal(db, g) for g in goals]
    @test ours[1] == "instantiation_error" && ours[5] == "type_error(callable,1)"
    if _R_SWIPL
        main = join(
            (
                "t($(_rsrc(g)))" for g in goals
            ), ", "
        )
        driver = """
        t(G) :- catch((r(G) -> true ; true), error(F, _), (write_canonical(F), nl)), flush_output.
        t(_).
        main :- $main.
        """
        theirs = _rswipl(clauses, (); main_text=driver)
        # r/1 prints the answers; only the error formals are compared
        theirs = [
            l for
            l in theirs if !endswith(l, " det") && !endswith(l, " nondet") && l != "end"
        ]
        @test ours == theirs
        ours == theirs || @info "errors differ" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# ── random programs: callers that reach their goals through a variable goal, call/N and a bound
# functor name, over nondeterministic facts; answers, determinism and the record pools (checked at
# every answer) ────────────────────────────────────────────────────────────────────────────────────
function _rmc_random(seed::Int)
    rng = MersenneTwister(seed)
    consts = _R[_rg(1), _rg(2), _rg(3), _rs("a"), _rs("b")]
    pick() = consts[rand(rng, 1:length(consts))]
    nf = 4
    clauses = Tuple{_R, Union{Nothing, _R}}[]
    for f in 1:nf, _ in 1:rand(rng, 1:3)                          # f1/1, f2/2, f3/1, f4/2: facts
        ar = f % 2 == 1 ? 1 : 2
        push!(clauses, (_rf("f$f", (pick() for _ in 1:ar)...), nothing))
    end
    arity(f) = f % 2 == 1 ? 1 : 2
    goals = _R[]
    for k in 1:12
        A, B, G, H = _rv(1), _rv(2), _rv(3), _rv(4)
        vars = _R[A, B]
        arg() = rand(rng) < 0.7 ? vars[rand(rng, 1:2)] : pick()
        parts = _R[]
        for _ in 1:rand(rng, 1:3)
            f = rand(rng, 1:nf)
            ar = arity(f)
            args = _R[arg() for _ in 1:ar]
            form = rand(rng, 1:5)
            if form == 1
                push!(parts, _rf("f$f", args...))
            elseif form == 2                                      # a variable goal bound just before
                push!(parts, _rf("=", G, _rf("f$f", args...)), G)
            elseif form == 3                                      # call/1
                push!(parts, _rf("call", _rf("f$f", args...)))
            elseif form == 4                                      # call/N: the last arguments extra
                nx = rand(rng, 1:ar)
                push!(
                    parts,
                    _rf(
                        "call",
                        ar == nx ? _rs("f$f") : _rf("f$f", args[1:(ar - nx)]...),
                        args[(ar - nx + 1):ar]...
                    )
                )
            else                                                  # the name from a variable
                push!(parts, _rf("=", H, _rs("f$f")), _rf("call", H, args...))
            end
        end
        body = length(parts) == 1 ? parts[1] : _rconj(parts...)
        push!(clauses, (_rf("m$k", A, B), body))
        push!(
            goals,
            _rf(
                "m$k",
                rand(rng) < 0.5 ? _rv(11) : pick(),
                rand(rng) < 0.5 ? _rv(12) : pick()
            )
        )
    end
    return clauses, goals
end

@testset "meta-call of plain goals: random callers equal swipl's, the pools live at every answer" begin
    allc = Tuple{_R, Union{Nothing, _R}}[]
    ours = String[]
    theirs = String[]
    nans = 0
    for seed in 20261020:20261139
        clauses, goals = _rmc_random(seed)
        db = _rdb(clauses)
        for g in goals
            for (a, det) in _rcall(db, g; at=(qid, k) -> (@test _rpools_live(db.ld)))
                push!(ours, a * (det ? " det" : " nondet"))
                nans += 1
            end
            push!(ours, "end")
        end
        if _R_SWIPL
            append!(theirs, _rswipl(clauses, goals))
        end
    end
    @test nans > 300 && nans < 100_000
    if _R_SWIPL
        @test ours == theirs
        ours == theirs || @info "first difference" findfirst(
            i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours)
        )
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

@testset "meta-call: what stays refused until V9e-2 (control constructs under call/1)" begin
    X, Y = _rv(71), _rv(72)
    db = _rdb(_rmc_clauses())
    for g in (
        _rf("c1", _rf(",", _rf("p", X), _rf("p", Y))),
        _rf("c1", _rf(";", _rs("nop"), _rs("nop"))),
        _rf("c1", _rf("->", _rs("nop"), _rs("nop"))), _rf("c1", _rf("\\+", _rs("nop"))),
        _rf("v", _rf("*->", _rs("nop"), _rs("nop"))),
        _rf("v", _rf("call", (_rs("nop") for _ in 1:9)...))                # call/9: compiled
    )
        @test_throws LK.NotPortedError _rcall(db, g)
    end
    # call/8 is no control: it resolves a procedure like any other (existence error here)
    @test _rmc_formal(db, _rf("v", _rf("call", (_rs("nop") for _ in 1:8)...))) != "no_error"
end

@testset "meta-call: a reserved symbol is no goal" begin
    # swipl cannot be asked: a reserved symbol (pl-ressymbol.c) has no text to write, so the expected
    # formal is stated here — upstream's `isCallableAtom` is false for it, and `call_type_error` follows
    db = _rdb(_rmc_clauses())
    r = LK.mk_reserved_symbol(_R, :reserved_goal)
    rc = mk_expr(_R, _R[r, _rg(1)])
    for (goal, culprit) in ((_rf("v", r), r), (_rf("v", rc), rc), (_rf("c2", r, _rg(1)), r))
        f = _rmc_formal_term(db, goal)
        @test f !== nothing && nchildren(f) == 3
        @test f !== nothing && lk_name(child(f, 1)) === :type_error &&
            lk_name(child(f, 2)) === :callable &&
            LK.compareStandard(child(f, 3), culprit, true) == 0
    end
end

@testset "meta-call: a system built-in is called without a procedure made in user" begin
    # `resolveProcedure` finds the procedure visible through user's super module, `system`, instead of
    # making an undefined one in `user` (pl-proc.c): after the calls `user` has no `atom/1` or `is/2`
    db = _rdb(_rmc_clauses())
    for g in (_rf("v", _rf("atom", _rs("a"))), _rf("v", _rf("is", _rv(81), _rg(3))))
        @test length(_rcall(db, g)) == 1
    end
    for (n, ar) in (("atom", 1), ("is", 2))
        @test LK.isCurrentProcedure(sym_key(_rs(n)), ar, db.user) === nothing
    end
end

# A Module:Goal chain that loops — `X = user:X, call(X)` — makes `stripModule` FAIL: upstream's
# `i_metacall_common` takes `THROW_EXCEPTION` with `type_error(acyclic_term, X)` (raised in
# `stripModuleName`), X cyclic. Neither side can write a cyclic culprit canonically, so each reports
# the formal's name, its type argument and whether the culprit is cyclic. `call(1:true)` is the other
# path — `call_type_error` (`1` is no module): `type_error(atom, 1)`, acyclic.
# The error a goal raises, read with `deRef` only: name, type argument, and whether the culprit is
# cyclic — `resolve_term` (which `_rmc_formal_term` uses) refuses a rational tree.
function _rmc_type_error_shape(db::_RDB, goal::_R)::String
    gd, ld = db.gd, db.ld
    fid = LK.PL_open_foreign_frame(ld)
    args = LK.PL_new_term_refs(ld, 0)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, _rproc(db, goal),
        args
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = "no_error"
    if rc == LK.PL_S_EXCEPTION
        fd = LK.deRef(ld, child(LK.deRef(ld, ld.slots[LK.PL_exception(ld, qid) + 1]), 2))
        out = string(
            lk_name(child(fd, 1)), " ", lk_name(LK.deRef(ld, child(fd, 2))), " ",
            LK.is_acyclic(ld, child(fd, 3)) ? "acyclic" : "cyclic"
        )
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

@testset "meta-call: a looping Module:Goal raises type_error(acyclic_term, Goal), as swipl" begin
    X = _rv(1)
    clauses = Tuple{_R, Union{Nothing, _R}}[
        (_rs("cyc1"), _rconj(_rf("=", X, _rf(":", _rs("user"), X)), _rf("call", X))),
        (
            _rs("cyc2"),
            _rconj(
                _rf("=", X, _rf(":", _rs("user"), _rf(":", _rs("user"), X))), _rf("call", X)
            )
        ),
        (_rs("cycv"), _rconj(_rf("=", X, _rf(":", _rs("user"), X)), X)),             # I_CALL1 of a variable
        (_rs("num"), _rf("call", _rf(":", _rg(1), _rs("true"))))
    ]
    db = _rdb(clauses)
    ours = [_rmc_type_error_shape(db, _rs(g)) for g in ("cyc1", "cyc2", "cycv", "num")]
    @test ours[1] == "type_error acyclic_term cyclic" &&
        ours[4] == "type_error atom acyclic"
    if _R_SWIPL
        driver = """
        t(G) :- catch((call(G) -> write(no_error) ; write(failed)), error(type_error(T, C), _),
                      (write(type_error), write(' '), write(T), (cyclic_term(C) -> write(' cyclic') ; write(' acyclic')))), nl.
        main :- t(cyc1), t(cyc2), t(cycv), t(num).
        """
        theirs = _rswipl(clauses, (); main_text=driver)
        @test ours == theirs
        ours == theirs || @info "looping Module:Goal" ours theirs
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end
