# ORIGINAL: a LIVE differential of copy_term/2, copy_term_nat/2 and duplicate_term/2 against swipl; upstream has no such test.
# test/core_lang/test_copyterm_swipl.jl — pl-copyterm.c's attribute-free path (src/pl-copyterm.jl),
# through the query API, on a program of callers, against a LIVE swipl: the answers (variables
# renamed consistently, one fresh variable per variable), the sharing of variables between the
# arguments of a copied term, bound variables seen through, atomic arguments, failing unification of the
# copy, CYCLIC terms copied as cyclic terms, and a long list (the walk keeps no recursion).
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

function _rct_clauses()
    T, C, X, Y, Z, R, A, B = (_rv(k) for k in 1:8)
    cp(name, g) = (_rf(name, T, C), _rf(g, T, C))
    return Tuple{_R, Union{Nothing, _R}}[
        cp("cp", "copy_term"), cp("nat", "copy_term_nat"), cp("dup", "duplicate_term"),
        # a term built in the body, with bound variables, then copied
        (
            _rf("b1", C),
            _rconj(_rf("=", X, _rf("g", Y)), _rf("=", Y, _rg(1)),
                _rf("copy_term", _rf("f", X, Z, Y), C))
        ),
        (_rf("b2", C), _rconj(_rf("=", X, Y), _rf("copy_term", _rf("f", X, Y, Z), C))),
        # the variables of a copy are distinct from the original's, and shared among themselves
        (
            _rf("v1", R),
            _rconj(_rf("copy_term", _rf("f", X, Y, X), _rf("f", A, B, _rv(9))),
                _rf("copy_term", A, _rv(10)),
                _rf("=", R, _rf("r", _rf("==", A, _rv(9)), _rf("==", A, B))))
        ),
        (
            _rf("v3", R),
            _rconj(_rf("copy_term", _rf("f", X, Y), _rf("f", A, B)),
                _rf(
                    ";",
                    _rf("->", _rf("==", A, B), _rf("=", R, _rs("same"))),
                    _rf("=", R, _rs("distinct"))
                ))
        ),
        (
            _rf("v4", R),
            _rconj(_rf("copy_term", _rf("f", X, X), _rf("f", A, B)),
                _rf(
                    ";",
                    _rf("->", _rf("==", A, B), _rf("=", R, _rs("same"))),
                    _rf("=", R, _rs("distinct"))
                ))
        ),
        # the copy of a term holding X is not X: binding the copy leaves X alone
        (
            _rf("ind", R),
            _rconj(_rf("copy_term", X, Y), _rf("=", Y, _rs("a")),
                _rf(
                    ";",
                    _rf("->", _rf("var", X), _rf("=", R, _rs("original_unbound"))),
                    _rf("=", R, _rs("original_bound"))
                ))
        ),
        # cyclic: a term holding itself through a binding
        (_rf("cyc1", R), _rconj(_rf("=", X, _rf("f", X)), _rf("copy_term", X, R))),
        (
            _rf("cyc2", R),
            _rconj(_rf("=", X, _rf("f", X, Y)), _rf("copy_term", X, A),
                _rf("=", A, _rf("f", B, _rv(9))),
                _rf(
                    ";",
                    _rf("->", _rf("==", B, A), _rf("=", R, _rs("loops"))),
                    _rf("=", R, _rs("other"))
                ))
        ),
        (
            _rf("cyc3", R),
            _rconj(_rf("=", X, _rf("f", X, Y)), _rf("duplicate_term", X, A),
                _rf("=", A, _rf("f", B, _rv(9))),
                _rf(
                    ";",
                    _rf("->", _rf("==", B, A), _rf("=", R, _rs("loops"))),
                    _rf("=", R, _rs("other"))
                ))
        ),
        (
            _rf("cyc4", R),
            _rconj(
                _rf("=", X, _rf("f", Y)),
                _rf("=", Y, _rf("g", X, Z)),
                _rf("copy_term", _rf("h", X, Y, Z), R)
            )
        )
    ]
end

function _rct_goals()
    X, Y, Z = _rv(51), _rv(52), _rv(53)
    f(a...) = _rf("f", a...)
    goals = _R[]
    for name in ("cp", "nat", "dup")
        append!(
            goals,
            _R[
                _rf(name, f(X, Y, X), Z), _rf(name, _rs("a"), Z), _rf(name, _rg(1), Z),
                _rf(name, _rg(1.5), Z),
                _rf(name, _rg("s"), Z), _rf(name, X, Z), _rf(name, _rnil(), Z),
                _rf(name, _rlist(X, Y, X, _rg(1)), Z), _rf(name, f(f(X), f(Y), f(X, Y)), Z),
                _rf(name, f(_rg(1), _rs("a"), f(_rs("b"))), Z),              # ground
                _rf(name, f(X, Y), f(_rs("a"), _rs("b"))),                    # copy unifies
                _rf(name, f(X, X), f(_rs("a"), _rs("b"))),                    # …or does not
                _rf(name, f(X, Y), _rf("g", Z)),                              # …other functor
                _rf(name, _rs("a"), _rs("b")),
                _rf(name, _rints(1:20_000), Z)                                # a long list
            ]
        )
    end
    for n in ("b1", "b2", "v1", "v3", "v4", "ind", "cyc1", "cyc2", "cyc3", "cyc4")
        push!(goals, _rf(n, X))
    end
    return goals
end

@testset "copy_term/2, copy_term_nat/2, duplicate_term/2 equal swipl's" begin
    clauses = _rct_clauses()
    goals = _rct_goals()
    db = _rdb(clauses)
    ours = String[]
    for g in goals
        for (a, det) in _rcall(db, g; at=(qid, k) -> (@test _rpools_live(db.ld)))
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
    end
    @test count(==("end"), ours) == length(goals)
    @test count(endswith(" det"), ours) > 40
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

# Sharing, which a query cannot see (a term is a value): `copy_term/2` shares a GROUND subterm and
# rebuilds one with a variable; `duplicate_term/2` copies every compound — pl-copyterm.c's
# `COPY_SHARE` against its absence. Read through the walk itself, by identity.
# (not on `alt_interned`, which interns every ground compound: a copy IS the original there)
if LK_TERM_IMPL != "alt_interned"
    @testset "copy_term shares ground compounds; duplicate_term copies every one" begin
        ld = LK.PL_local_data{_R}()
        ground = _rf("f", _rg(1), _rf("g", _rs("a")))
        open_ = _rf("f", _rv(1), _rf("g", _rs("a")))
        share, dup = LK.cp_options(true), LK.cp_options(false)
        @test LK.copy_term(ld, ground, share) === ground
        @test LK.copy_term(ld, ground, dup) !== ground
        @test LK.compareStandard(LK.copy_term(ld, ground, dup), ground, true) == 0
        c = LK.copy_term(ld, open_, share)
        @test c !== open_ && child(c, 3) === child(open_, 3)        # the ground part is shared
        @test var_key(child(c, 2)) != var_key(child(open_, 2))      # the variable is renamed
        # a bound variable is seen through: the copy holds its value, and the compound is rebuilt
        ld.bindings[UInt64(5)] = _rg(7)
        b = LK.copy_term(ld, _rf("f", _rv(5)), share)
        @test child(b, 2) === _rg(7)
    end

    # The built-ins' own choice of options, by identity again: `copy_term/2` hands back a ground argument
    # as it is, `duplicate_term/2` copies it (called as the dispatch calls them, on term references).
    @testset "the built-ins: copy_term/2 shares a ground argument, duplicate_term/2 does not" begin
        ld = LK.PL_local_data{_R}()
        ctx = LK.foreign_context{_R}(0, UInt(0), nothing)
        ground = _rf("f", _rg(1), _rf("g", _rs("a")))
        for (i, (fn, shared)) in enumerate((
            (LK.pl_copy_term2_va, true), (LK.pl_copy_term_nat2_va, true),
            (LK.pl_duplicate_term2_va, false)
        ))
            fid = LK.PL_open_foreign_frame(ld)
            t0 = LK.PL_new_term_refs(ld, 2)
            LK.putSlotValue!(ld, t0 + 1, ground)
            LK.putSlotValue!(ld, t0 + 2, _rv(70 + i))                  # a variable of its own: bindings persist
            @test fn(ld, t0, 2, ctx) == LK.FTRUE
            out = LK.deRef(ld, LK.slotValue(ld, t0 + 2))
            @test (out === ground) == shared
            @test LK.compareStandard(out, ground, true) == 0
            LK.PL_close_foreign_frame(ld, fid)
        end
    end
end
