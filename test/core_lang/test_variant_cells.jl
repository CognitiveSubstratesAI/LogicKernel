# ORIGINAL: L1d step 8a — `=@=` on CELLS (pl-variant.c is_variant_ptr, variant, isomorphic, var_id, term_id,
# Root as their `_cells` ports, src/pl-variant.jl; the workspace's L1_plan/stageL1d_design.md §3i). Upstream
# numbers a node by OVERWRITING the cell that holds it (`consVar(n)`, `consCompound_x(n)`) and restores it
# (`reset_terms`); ours numbers it in a side vector by position (`ld.vt_ids`) — a representation-only
# DIVERGES. test/core_lang/test_variant_cells.jl — on every term type:
#   * a differential against swipl through clause bodies: renamings, a variable met twice on one side only,
#     shared subterms through a binding, cyclic terms (one cycle, two mutually recursive, with variables),
#     SWI's numeric identity (`1 =@= 1.0` fails), a long list;
#   * white-box: after every check the side vector is all zero and the node and work stacks empty;
#   * the boundary: a keyed variable's binding is checked on terms, COUNTED, with the right answer;
#   * the meter: `=@=` on two terms on the stack makes no cold export, import or variable read.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_ki(i) = _rg(Int64(i))
_vf(x) = _rg(Float64(x))

"A clause `name :- body, R = ok` — the answer `name(ok)` when the body succeeds."
_vc(name, body...) = (_rf(name, _rv(99)), _rconj(body..., _rf("=", _rv(99), _rs("ok"))))

_vt_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("v", _rv(1), _rv(2)), _rf("=@=", _rv(1), _rv(2))),
    # shared subterms through a binding: f(A, A) with A = g(X), against two cells and one
    _vc("sh1", _rf("=", _rv(1), _rf("g", _rv(2))),
        _rf("=@=", _rf("f", _rv(1), _rv(1)), _rf("f", _rf("g", _rv(3)), _rf("g", _rv(4))))),
    _vc("sh2", _rf("=", _rv(1), _rf("g", _rv(2))),
        _rf("=@=", _rf("f", _rv(1), _rv(1)), _rf("f", _rf("g", _rv(3)), _rf("g", _rv(3))))),
    _vc("sh3", _rf("=", _rv(1), _rf("g", _rv(2))), _rf("=", _rv(5), _rf("g", _rv(3))),
        _rf("=@=", _rf("f", _rv(1), _rv(5), _rv(1)), _rf("f", _rv(5), _rv(1), _rv(5)))),
    # cyclic terms
    _vc("cyc1", _rf("=", _rv(1), _rf("f", _rv(1))), _rf("=", _rv(2), _rf("f", _rv(2))),
        _rf("=@=", _rv(1), _rv(2))),
    _vc("cyc2", _rf("=", _rv(1), _rf("f", _rv(1), _rv(2))), _rf("=", _rv(2), _rf("f", _rv(2), _rv(1))),
        _rf("=", _rv(3), _rf("f", _rv(3), _rv(4))), _rf("=", _rv(4), _rf("f", _rv(4), _rv(3))),
        _rf("=@=", _rv(1), _rv(3))),
    _vc("cyc3", _rf("=", _rv(1), _rf("f", _rv(1), _rs("a"))), _rf("=", _rv(2), _rf("f", _rv(2), _rs("b"))),
        _rf("=@=", _rv(1), _rv(2))),
    _vc("cyc4", _rf("=", _rv(1), _rf("f", _rf("f", _rv(1)))), _rf("=", _rv(2), _rf("f", _rv(2))),
        _rf("=@=", _rv(1), _rv(2))),
    _vc("cyc5", _rf("=", _rv(1), _rf("f", _rv(1), _rv(3))), _rf("=", _rv(2), _rf("f", _rv(2), _rv(4))),
        _rf("=@=", _rv(1), _rv(2))),
    _vc("cyc6", _rf("=", _rv(1), _rf("f", _rv(1), _rv(3), _rv(3))),
        _rf("=", _rv(2), _rf("f", _rv(2), _rv(4), _rv(5))), _rf("=@=", _rv(1), _rv(2))),
    _vc("cyc7", _rf("=", _rv(1), _rf("f", _rv(1), _rv(3))), _rf("=", _rv(2), _rf("f", _rv(2), _rv(3))),
        _rf("=@=", _rf("p", _rv(1), _rv(4)), _rf("p", _rv(2), _rv(3)))),
    # a left cycle met twice against two right cycles: isomorphic on a cycle, which terminates only
    # through Root's union (the first partner's cell and the second's become one class)
    _vc("cyc8", _rf("=", _rv(1), _rf("f", _rv(1))), _rf("=", _rv(2), _rf("f", _rv(2))),
        _rf("=", _rv(3), _rf("f", _rv(3))),
        _rf("=@=", _rf("p", _rv(1), _rv(1)), _rf("p", _rv(2), _rv(3)))),
    # a long list, and one whose elements are fresh variables on one side and one variable on the other
    _vc("long1", _rf("length", _rv(1), _ki(2000)), _rf("length", _rv(2), _ki(2000)),
        _rf("=@=", _rv(1), _rv(2))),
    _vc("long2", _rf("length", _rv(1), _ki(3)), _rf("=@=", _rv(1), _rlist(_rv(4), _rv(4), _rv(4))))
]

@testset "=@= on cells, as swipl" begin
    db = _rdb(_vt_clauses())
    A, B, C, D = _rv(50), _rv(51), _rv(52), _rv(53)
    R = _rv(60)
    goals = _R[
        _rf("v", _rf("f", A, B), _rf("f", C, D)), _rf("v", _rf("f", A, A), _rf("f", C, D)),
        _rf("v", _rf("f", A, B), _rf("f", C, C)), _rf("v", _rf("f", A, B, A), _rf("f", C, D, C)),
        _rf("v", _rf("f", A, _rf("g", B), A), _rf("f", C, _rf("g", C), C)),
        _rf("v", _rf("f", A, B), _rf("f", B, A)), _rf("v", _rf("f", A, B), _rf("f", A, B)),
        _rf("v", A, B), _rf("v", A, A), _rf("v", _rf("f", A), A), _rf("v", A, _rs("a")),
        _rf("v", _ki(1), _vf(1)), _rf("v", _ki(1), _ki(1)), _rf("v", _vf(2.5), _vf(2.5)),
        _rf("v", _rs("a"), _rs("a")), _rf("v", _rs("a"), _rs("b")),
        _rf("v", _rf("f", _rs("a")), _rf("g", _rs("a"))), _rf("v", _rf("f", _rs("a")), _rf("f", _rs("a"), B)),
        _rf("v", _rlist(A, B, _ki(3)), _rlist(C, D, _ki(3))),
        _rf("v", _rlist(A, B, _ki(3)), _rlist(C, D, _vf(3))),
        _rf("sh1", R), _rf("sh2", R), _rf("sh3", R),
        _rf("cyc1", R), _rf("cyc2", R), _rf("cyc3", R), _rf("cyc4", R), _rf("cyc5", R), _rf("cyc6", R),
        _rf("cyc7", R), _rf("cyc8", R), _rf("long1", R), _rf("long2", R)
    ]
    ours = _rlines(db, goals)
    # the kernel's side alone (also without swipl: Pkg.test)
    @test count(==("end"), ours) == length(goals)
    @test !any(l -> startswith(l, "exception("), ours)
    @test "v(f(_,_),f(_,_)) det" in ours && "cyc1(ok) det" in ours && "cyc8(ok) det" in ours && "sh2(ok) det" in ours
    @test !("sh1(ok) det" in ours) && !("cyc3(ok) det" in ours) && !("cyc6(ok) det" in ours)
    if _R_SWIPL
        theirs = _rswipl(_vt_clauses(), goals)
        @test ours == theirs
        if ours != theirs
            for i in eachindex(ours)
                if i > length(theirs) || ours[i] != theirs[i]
                    @info "first difference" i ours[i] get(theirs, i, "—")
                    break
                end
            end
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

"An engine with the values of `vs` put into term references; `(ld, t)` (reference `t + i - 1` is slot `t + i`)."
function _vt_engine(vs::Vector{_R}; pvm=LK.PutVarMap())
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
_vt_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)
"Nothing left numbered: the side vector all zero, the node and work stacks empty."
_vt_clean(ld) = all(iszero, ld.vt_ids) && isempty(ld.vt_nodes) && isempty(ld.vt_agenda.stack)
_vt_check(ld, t, i, j) = LK.is_variant_ptr_cells(ld, -(t + i), -(t + j))

@testset "white-box: the side vector is cleared after every check" begin
    X, Y, Z = _rv(1), _rv(2), _rv(3)
    ld, t = _vt_engine(
        _R[
            _rf("f", X, _rf("g", Y, X), Y), _rf("f", Z, _rf("g", X, Z), X),
            _rf("f", X, _rf("g", Y, X), X)
        ]
    )
    @test _vt_check(ld, t, 1, 2)
    @test _vt_clean(ld)
    @test !_vt_check(ld, t, 1, 3)
    @test _vt_clean(ld)
    @test _vt_check(ld, t, 2, 1)                     # a second check sees no stale number
    @test _vt_clean(ld)
end

@testset "the boundary: a keyed variable's binding, checked on terms, counted" begin
    ld, t = _vt_engine(_R[_rs("x"), _rf("f", _rf("g", _rv(8)), _rs("a"))])
    kv = lk_var(_R, UInt64(4741))
    LK.setSlotValue!(ld, t + 1, _rf("f", kv, _rs("a")))
    LK.Trail!(ld, var_key(kv), _rf("g", _rv(7)))
    p0 = ld.cold_pairs
    @test _vt_check(ld, t, 1, 2)
    @test ld.cold_pairs > p0
    @test _vt_clean(ld)
end

@testset "the meter: =@= on two terms on the stack makes no cold export, import or variable read" begin
    X, Y, U, W = _rv(1), _rv(2), _rv(3), _rv(4)
    ld, t = _vt_engine(
        _R[
            _rf("f", X, _rlist((_ki(i) for i in 1:50)...), _rf("g", Y, X), _rs("a"), _vf(1.5)),
            _rf("f", U, _rlist((_ki(i) for i in 1:50)...), _rf("g", W, U), _rs("a"), _vf(1.5))
        ]
    )
    c0 = _vt_counts(ld)
    @test _vt_check(ld, t, 1, 2)
    @test _vt_counts(ld) == c0
end
