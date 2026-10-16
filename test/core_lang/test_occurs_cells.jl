# ORIGINAL: L1d step 2 — the occurs check on CELLS (pl-prims.c var_occurs_in and
# unify_with_occurs_check as `var_occurs_in_cells`/`unify_with_occurs_check_cells`, src/pl-prims.jl):
# unify_with_occurs_check/2, and =/2 and the head's H_VAR under occurs_check=true/error, unify locations;
# upstream's own occurs-check units run on terms in test_occurs_check.jl unchanged.
# test/core_lang/test_occurs_cells.jl — on every term type:
#   * against swipl through the rules differential, in each mode (false, true, error): a variable
#     against a term containing it (`X = f(X)`), directly and through a head (`p(X, X)` called with
#     `p(Y, f(Y))`), two compounds whose unification binds a variable into its own value (the trail
#     walk: `f(X, Y) = f(Y, g(X))`), the error's ball, unify_with_occurs_check/2 under occurs_check=false;
#   * white-box: after every walk no functor cell carries FIRST_MASK (the marks are cleared);
#   * the boundary: a keyed variable is checked on terms, COUNTED in `cold_pairs`.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

# self(R) :- X = f(X), R = done.   head(R) :- hv(Y, f(Y)), R = done.   hv(X, X).
# trail(R) :- f(X, Y) = f(Y, g(X)), R = done.   uwoc(R) :- unify_with_occurs_check(X, f(X)) -> R = yes ; R = no.
# caught(R) :- catch(X = f(X), E, (E = error(F, _), R = F)).
_oc_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("hv", _rv(1), _rv(1)), nothing),
    (
        _rf("self", _rv(9)),
        _rconj(_rf("=", _rv(1), _rf("f", _rv(1))), _rf("=", _rv(9), _rs("done")))
    ),
    (
        _rf("head", _rv(9)),
        _rconj(_rf("hv", _rv(2), _rf("f", _rv(2))), _rf("=", _rv(9), _rs("done")))
    ),
    (
        _rf("trail", _rv(9)),
        _rconj(_rf("=", _rf("f", _rv(1), _rv(2)), _rf("f", _rv(2), _rf("g", _rv(1)))),
            _rf("=", _rv(9), _rs("done")))
    ),
    (
        _rf("uwoc", _rv(9)),
        _rf(";",
            _rf("->", _rf("unify_with_occurs_check", _rv(1), _rf("f", _rv(1))),
                _rf("=", _rv(9), _rs("yes"))), _rf("=", _rv(9), _rs("no")))
    ),
    (
        _rf("caught", _rv(9)),
        _rf("catch", _rf("=", _rv(1), _rf("f", _rv(1))), _rv(2),
            _rconj(
                _rf("=", _rv(2), _rf("error", _rv(3), _rv(4))), _rf("=", _rv(9), _rv(3))
            ))
    ),
    (
        _rf("caught_trail", _rv(9)),
        _rf("catch",
            _rf("=", _rf("f", _rv(1), _rv(2)), _rf("f", _rv(2), _rf("g", _rv(1)))),
            _rv(5),
            _rconj(
                _rf("=", _rv(5), _rf("error", _rv(3), _rv(4))), _rf("=", _rv(9), _rv(3))
            ))
    )
]
const _OC_GOALS = [
    _rf(n, _rv(50)) for n in ("self", "head", "trail", "uwoc", "caught", "caught_trail")
]

"No functor cell on the global stack carries FIRST_MASK: every occurs walk cleared its marks."
_oc_no_marks(ld) =
    !any(
        p -> LK.isFunctor(ld.gstack[p]) && (ld.gstack[p] & LK.FIRST_MASK) != 0, 1:(ld.gTop)
    )

for (mode, flag) in (("false", LK.OCCURS_CHECK_FALSE), ("true", LK.OCCURS_CHECK_TRUE),
    ("error", LK.OCCURS_CHECK_ERROR))
    @testset "occurs_check=$mode: as swipl, on the cells" begin
        db = _rdb(_oc_clauses())
        db.ld.prolog_flag_occurs_check = flag
        ours = _rlines(db, _OC_GOALS)
        @test _oc_no_marks(db.ld)
        if _R_SWIPL
            theirs = _rswipl(
                _oc_clauses(), _OC_GOALS; extra=":- set_prolog_flag(occurs_check, $mode).\n"
            )
            @test ours == theirs
            if ours != theirs
                k = findfirst(
                    i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours)
                )
                @info "first difference ($mode)" k ours[something(k, 1)] get(
                    theirs, something(k, 1), "—"
                )
            end
        elseif _R_SWIPL_REQUIRED
            @test false
        end
    end
end

@testset "the walk on cells: marks cleared, a cycle through the trail found" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 2)
    pvm = LK.PutVarMap()
    X = _rv(1)
    LK.putSlotValue!(ld, t + 1, X, pvm)
    LK.putSlotValue!(ld, t + 2, _rf("g", _rf("h", X), _rs("a")), pvm)
    px = LK.unRef(ld.slots[t + 1])
    @test LK.var_occurs_in_cells(ld, px, -(t + 2))                   # X occurs in g(h(X), a)
    @test _oc_no_marks(ld)
    @test !LK.var_occurs_in_cells(ld, px, -(t + 1))                  # X in X: false at entry (upstream)
    @test LK.unify_with_occurs_check_cells(ld, -(t + 1), -(t + 2), LK.OCCURS_CHECK_TRUE) ==
        LK.BOOLEX_FALSE
    @test LK.isVar(ld.gstack[px]) && _oc_no_marks(ld)
end

@testset "the boundary: a keyed variable is checked on terms, counted" begin
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 2)
    kv = lk_var(_R, UInt64(4714))
    LK.setSlotValue!(ld, t + 1, kv)
    LK.putSlotValue!(ld, t + 2, _rf("f", _rs("a")))
    p0 = ld.cold_pairs
    @test LK.unify_with_occurs_check_cells(ld, -(t + 1), -(t + 2), LK.OCCURS_CHECK_TRUE) ==
        LK.BOOLEX_TRUE
    @test ld.cold_pairs > p0
    @test lk_eq(LK.resolve_term(ld, LK.deRef(ld, kv)), _rf("f", _rs("a")))
end
