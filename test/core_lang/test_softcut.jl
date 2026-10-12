# ORIGINAL: V9d's soft-cut `*->` through the VM against swipl, its pools invariant, frame positions and its mutation regressions (SC4/SC13, SC9, SC11') — split out of test_rules_swipl.jl (user, 2026-10-12: mutants target the smallest
# test file holding the killing assertion). test/core_lang/test_softcut.jl
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel
include(joinpath(@__DIR__, "rules_common.jl"))

# ── V9d: the soft-cut ───────────────────────────────────────────────────────────────────────────
# `(A *-> B ; C)`: every answer of A, then B for each; C only when A has none. `C_SOFTCUT` takes
# the condition's own choice point out of the chain, once, and leaves A's choice points alone; its
# record stays in the pool until its stack region is popped — `_rpools_live` is asked AT EVERY
# ANSWER here, and that is the check of the restated invariant.
_rsite(a::_R, b::_R, c::_R) = _ror(_rf("*->", a, b), c)
_rsit(a::_R, b::_R) = _rf("*->", a, b)

"The pinned soft-cut programs: facts `n/1`, `m/1` and one clause per case."
function _rsoft_clauses()
    X, Y, Z, A = (_rv(k) for k in 1:4)
    n(x) = _rf("n", x)
    m(x) = _rf("m", x)
    eq(a, b) = _rf("=", a, b)
    cut = _rs("!")
    return Tuple{_R, Union{Nothing, _R}}[
        (n(_rg(1)), nothing), (n(_rg(2)), nothing), (n(_rg(3)), nothing),
        (m(_rs("a")), nothing), (m(_rs("b")), nothing),
        (_rf("nomatch", _rs("b")), nothing),
        (_rf("deep", X), _rconj(n(X), n(_rv(9)))),
        (_rf("s1", X), _rsite(n(X), _rs("true"), eq(X, _rs("none")))),           # every answer of A
        (_rf("s2", X, Y), _rsite(n(X), m(Y), eq(Y, _rs("none")))),
        (_rf("s3", X), _rsite(_rf("nomatch", X), eq(X, _rs("then")), eq(X, _rs("else")))),
        (_rf("s4", X), _rsite(_rs("fail"), eq(X, _rs("then")), m(X))),            # the else branch
        (
            _rf("s5", X, Y),
            _rsite(_rconj(n(X), _rf(">", X, _rg(1))), eq(Y, X), eq(Y, _rs("no")))
        ),
        (_rf("s6", X), _rsite(_rs("true"), n(X), _rs("fail"))),                   # A leaves no choice
        (_rf("s7", X, Y), _rconj(m(X), _rsite(n(Y), _rs("true"), _rs("fail")))),
        (_rf("s8", X), _rconj(_rsit(n(X), _rs("true")), _rf(">", X, _rg(1)))),    # *-> without else
        (_rf("s9", X), _rsit(_rf("nomatch", X), _rs("true"))),
        (_rf("s9", _rs("second")), nothing),
        (_rf("s10", X, Y), _rsite(_rf("deep", X), eq(Y, _rs("got")), eq(Y, _rs("none")))),
        (
            _rf("s11", X, Y),
            _rsite(
                _rsite(n(X), _rf(">", X, _rg(1)), _rs("fail")),
                eq(Y, _rs("in")),
                eq(Y, _rs("out"))
            )
        ),
        (_rf("s12", X), _rsite(_rconj(n(X), cut), _rs("true"), eq(X, _rs("none")))),      # C_LSCUT
        (
            _rf("s13", X),
            _rsite(_rconj(n(X), cut, _rf(">", X, _rg(1))), _rs("true"), eq(X, _rs("else")))
        ),
        (
            _rf("s14", X, Y),
            _rconj(m(X), _rsite(_rconj(n(Y), cut), _rs("true"), _rs("fail")))
        ),
        (_rf("s15", X), _rconj(_rsit(_rconj(n(X), cut), _rs("true")), m(_rv(8)))),        # C_LCUTIFTHEN
        (_rf("s16", X, Y), _rconj(_rsite(n(X), eq(A, X), _rs("true")), eq(Y, _rf("r", A)))),
        (
            _rf("s17", X, Y),
            _rconj(
                _rsite(_rf("nomatch", X), eq(A, _rg(1)), _rs("true")), eq(Y, _rf("r", A))
            )
        ),
        (_rf("s18", X), _rconj(_rsite(n(X), _rs("true"), _rs("fail")), cut)),             # a cut after it
        (_rf("s19", X), _rnot(_rsite(n(X), _rf(">", X, _rg(5)), _rs("fail")))),
        (
            _rf("s20", X, Y),
            _rsite(n(X), _rsite(m(Y), _rs("true"), _rs("fail")), _rs("fail"))
        ),
        # a last call after a soft-cut that left its record behind: the frame is reused 2,000 times
        (_rf("sloop", X, Y),
            _rsite(_rf(">", X, _rg(0)),
                _rconj(_rf("is", A, _rf("+", X, _rg(-1))), _rf("sloop", A, Y)),
                eq(Y, _rs("done")))),
        # … and a clause choice point resumed in place after one
        (_rf("s21", X), _rconj(_rsite(_rs("true"), _rs("true"), _rs("fail")), _rs("fail"))),
        (_rf("s21", _rs("second")), nothing)
    ]
end

function _rsoft_goals()
    X, Y = _rv(101), _rv(102)
    return _R[
        _rf("s1", X), _rf("s1", _rg(2)), _rf("s1", _rg(9)), _rf("s2", X, Y), _rf("s3", X),
        _rf("s4", X), _rf("s5", X, Y), _rf("s6", X), _rf("s7", X, Y), _rf("s8", X),
        _rf("s9", X),
        _rf("s10", X, Y), _rf("s11", X, Y), _rf("s12", X), _rf("s13", X), _rf("s14", X, Y),
        _rf("s15", X), _rf("s16", X, Y), _rf("s17", X, Y), _rf("s18", X), _rf("s19", X),
        _rf("s20", X, Y), _rf("sloop", _rg(2000), Y), _rf("s21", X)
    ]
end

"A random body of `,`, `;`, `->`, `*->` and `\\+` with `!` anywhere."
function _rsoftbody(rng, vars::Vector{_R}, depth::Int)::_R
    r = rand(rng)
    if depth < 4 && r < 0.22
        return _rsite(_rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1),
            _rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.3
        return _rsit(_rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.38
        return _rite(_rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1),
            _rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.45
        return _rnot(_rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.53
        return _ror(_rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1))
    elseif depth < 4 && r < 0.75
        return _rf(",", _rsoftbody(rng, vars, depth + 1), _rsoftbody(rng, vars, depth + 1))
    end
    rand(rng) < 0.15 && return _rs("!")
    return _rorbody(rng, vars, 4)                                   # a goal
end

"Random predicates `rs<i>/k` of one or two clauses, a soft-cut at the top, and goals on them."
function _rsoft_random(rng, count::Int)
    clauses = Tuple{_R, Union{Nothing, _R}}[]
    goals = _R[]
    key = 80_000
    for i in 1:count
        k = rand(rng, 1:3)
        for _ in 1:rand(rng, 1:2)
            vars = _R[_rv(key + j) for j in 1:rand(rng, k:(k + 2))]
            key += 10
            cond = _rf(
                ",", _rf(rand(rng, ("n", "m")), rand(rng, vars)),
                _rsoftbody(rng, vars, 2)
            )
            body = if rand(rng) < 0.7
                _rsite(cond, _rsoftbody(rng, vars, 2), _rsoftbody(rng, vars, 2))
            else
                _rsit(cond, _rsoftbody(rng, vars, 2))
            end
            r = rand(rng)
            if r < 0.3
                body = _rf(",", body, _rsoftbody(rng, vars, 2))
            elseif r < 0.6
                body = _rf(",", _rf("n", vars[1]), body)        # a choice point made BEFORE
            end
            push!(clauses, (mk_expr(_R, _R[_rs("rs$i"); vars[1:k]]), body))
        end
        fresh = _R[_rv(key + j) for j in 1:k]
        key += 10
        push!(goals, mk_expr(_R, _R[_rs("rs$i"); fresh]))
        bound = copy(fresh)
        bound[1] = rand(rng, (_rg(1), _rs("a"), _rg(3)))
        push!(goals, mk_expr(_R, _R[_rs("rs$i"); bound]))
    end
    return clauses, goals
end

# The pinned programs' answers, from the run in which the whole list was identical to swipl's.
const _R_SOFT_PINNED = Dict{Int, Vector{String}}(
    1 => ["s1(1) nondet", "s1(2) nondet", "s1(3) det"],
    2 => ["s1(2) det"],
    3 => String[],
    4 => [
        "s2(1,a) nondet",
        "s2(1,b) nondet",
        "s2(2,a) nondet",
        "s2(2,b) nondet",
        "s2(3,a) nondet",
        "s2(3,b) det"
    ],
    5 => String[],
    6 => ["s4(a) nondet", "s4(b) det"],
    7 => ["s5(2,2) nondet", "s5(3,3) det"],
    8 => ["s6(1) nondet", "s6(2) nondet", "s6(3) det"],
    9 => [
        "s7(a,1) nondet",
        "s7(a,2) nondet",
        "s7(a,3) nondet",
        "s7(b,1) nondet",
        "s7(b,2) nondet",
        "s7(b,3) det"
    ],
    10 => ["s8(2) nondet", "s8(3) det"],
    11 => ["s9(b) nondet", "s9(second) det"],
    12 => [
        "s10(1,got) nondet",
        "s10(1,got) nondet",
        "s10(1,got) nondet",
        "s10(2,got) nondet",
        "s10(2,got) nondet",
        "s10(2,got) nondet",
        "s10(3,got) nondet",
        "s10(3,got) nondet",
        "s10(3,got) det"
    ],
    13 => ["s11(2,in) nondet", "s11(3,in) det"],
    14 => ["s12(1) det"],
    15 => ["s13(else) det"],
    16 => ["s14(a,1) nondet", "s14(b,1) det"],
    17 => ["s15(1) nondet", "s15(1) det"],
    18 => ["s16(1,r(1)) nondet", "s16(2,r(2)) nondet", "s16(3,r(3)) det"],
    19 => ["s17(b,r(1)) det"],
    20 => ["s18(1) det"],
    21 => ["s19(_) det"],
    22 => [
        "s20(1,a) nondet",
        "s20(1,b) nondet",
        "s20(2,a) nondet",
        "s20(2,b) nondet",
        "s20(3,a) nondet",
        "s20(3,b) det"
    ],
    23 => ["sloop(2000,done) det"],
    24 => ["s21(second) det"]
)

@testset "the soft-cut: every answer and its determinism are swipl's (V9d)" begin
    clauses = _rsoft_clauses()
    goals = _rsoft_goals()
    npinned = length(goals)
    rc, rg = _rq3_keep(20261017, "rs", _rsoft_random(Xoshiro(20261017), 250)...)
    append!(clauses, rc)
    append!(goals, rg)
    db = _rdb(clauses)
    ops = Set{UInt64}()
    for (h, _) in clauses
        cref = _rproc(db, h).definition.impl_clauses.first_clause
        while cref !== nothing
            union!(ops, _rops(cref.clause))
            cref = cref.next
        end
    end
    @test all(in(ops), (LK.C_SOFTIF, LK.C_SOFTCUT, LK.C_SOFTIFTHEN, LK.C_SCUT, LK.C_LSCUT))
    # the kernel's lines, with the pools checked AT EVERY ANSWER (the restated invariant), and how
    # many answers were given while a record C_SOFTCUT unlinked was still in the pool
    ours = String[]
    live = Bool[]
    held = 0
    for g in goals
        for (a, det) in _rcall(
            db, g;
            at=(qid, k) -> begin
                push!(live, _rpools_live(db.ld))
                held += any(i -> db.ld.choices[i].unlinked, 1:(db.ld.nchoices))
            end
        )
            push!(ours, a * (det ? " det" : " nondet"))
        end
        push!(ours, "end")
    end
    @test !isempty(live) && all(live)
    @test held > 50                                     # the check met such records, often
    @test db.ld.nchoices == 0 && db.ld.nframes == 0     # and every one was reclaimed in the end
    ends = findall(==("end"), ours)
    answers(i) = ours[(i == 1 ? 1 : ends[i - 1] + 1):(ends[i] - 1)]        # of the i-th goal
    # pinned from the run in which the whole list was identical to swipl's
    for i in 1:npinned
        want = get(_R_SOFT_PINNED, i, ["?"])
        answers(i) == want || println(stderr, "  PIN ", i, " => ", repr(answers(i)), ",")
        @test answers(i) == want
    end
    ndet = count(endswith(" nondet"), ours)
    @info "soft-cut programs: $(length(goals)) queries, $(length(ours) - length(goals)) answers ($ndet non-deterministic); $held answers with an unlinked record in the pool"
    @test ndet > 100 && count(endswith(" det"), ours) > 100
    if _R_SWIPL
        theirs = _rswipl(clauses, goals)
        @test ours == theirs
        if ours != theirs
            k = findfirst(i -> i > length(theirs) || ours[i] != theirs[i], eachindex(ours))
            @info "first difference" k ours[something(k, 1)] get(
                theirs, something(k, 1), "—"
            )
        end
    end
end

# Where a frame lands around a soft-cut, read with the real `prolog_current_frame/1` on both
# sides: `C_SOFTCUT` does not lower `lTop`, so after it the next frame lands ABOVE the condition's
# choice point, dead or not — the hard `->` beside each case lands below.
function _rsoft_pos_clauses()
    F0, F1 = _rv(1), _rv(2)
    pcf(v) = _rf("prolog_current_frame", v)
    return [
        (_rs("z"), nothing), (_rs("nd2"), nothing), (_rs("nd2"), nothing),
        (_rf("nomatch", _rs("b")), nothing),
        (_rf("qn", F1), _rconj(pcf(F1), _rs("z"))), (_rf("qn", _rv(20)), nothing),
        (
            _rf("sthen0", F0, F1),
            _rconj(pcf(F0), _rsite(_rs("z"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (
            _rf("hthen0", F0, F1),
            _rconj(pcf(F0), _rite(_rs("z"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (
            _rf("sthen", F0, F1),
            _rconj(pcf(F0), _rsite(_rs("nd2"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (
            _rf("hthen", F0, F1),
            _rconj(pcf(F0), _rite(_rs("nd2"), _rf("qn", F1), _rs("z")), _rs("z"))
        ),
        (_rf("selse", F0, F1),
            _rconj(
                pcf(F0), _rsite(_rf("nomatch", _rs("a")), _rs("z"), _rf("qn", F1)), _rs("z")
            )),
        (_rf("safter", F0, F1),
            _rconj(pcf(F0), _rsite(_rs("z"), _rs("z"), _rs("z")), _rf("qn", F1), _rs("z"))),
        (_rf("sit", F0, F1), _rconj(pcf(F0), _rsit(_rs("nd2"), _rf("qn", F1)), _rs("z")))
    ]
end
const _R_SOFTPOS = [
    (:sthen0, 20), (:hthen0, 11), (:sthen, 37), (:hthen, 11), (:selse, 11), (:safter, 20),
    (:sit, 28)
]

@testset "around a soft-cut the next frame lands where swipl's does (C_SOFTIF, C_SOFTCUT)" begin
    clauses = _rsoft_pos_clauses()
    db = _rdb(clauses)
    ours = Int[]
    for (n, _) in _R_SOFTPOS
        ans = _rcall(db, _rf(n, _rv(90), _rv(91)))
        m = match(r"^\w+\((-?\d+),(-?\d+)\)$", ans[1][1])     # the first answer: n(A,B)
        push!(ours, parse(Int, m[2]) - parse(Int, m[1]))
    end
    ours == last.(_R_SOFTPOS) || println(stderr, "  soft-cut positions, kernel: ", ours)
    @test ours == last.(_R_SOFTPOS)
    if _R_SWIPL
        main =
            "main :- " *
            join(
                ("$n(A$n, B$n), D$n is B$n - A$n, writeln(D$n)" for (n, _) in _R_SOFTPOS),
                ", "
            ) * "."
        theirs = parse.(Int, _rswipl(clauses, (); main_text=main))
        theirs == last.(_R_SOFTPOS) ||
            println(stderr, "  soft-cut positions, swipl: ", theirs)
        @test theirs == last.(_R_SOFTPOS)
    end
end

# ── soft-cut mutation regression: a cut inside a `*->` condition, AFTER the soft-cut (SC4) ───────
# The slot `C_SOFTCUT` negates (to −ref(P), P = the else-choice's parent) is read by `C_LSCUT` to
# know how far a `!` in the condition cuts: baseline cuts to P's parent, removing the condition's
# first choice; without the negation (SC4) the cut reaches the wrong record and the condition's
# first choice survives, so backtracking yields extra solutions. The shape: a condition that
# succeeds more than once with a cut that runs on a later success, binding the head var to the
# condition var so an extra solution shows by value (mutation 2026-10-12, V9d_softcut_mutation).
# (`sc9`'s tail call after the soft-cut compiles to I_DEPART — the LCO path whose reclaim SC9
# removes — checked structurally here; the growth itself is the "soft-cut loop … stays flat" test.)
function _rscreg_clauses()
    X, R, Y = _rv(1), _rv(3), _rv(2)
    n(x) = _rf("n", x)
    eq(a, b) = _rf("=", a, b)
    return Tuple{_R, Union{Nothing, _R}}[
        (n(_rg(1)), nothing), (n(_rg(2)), nothing), (n(_rg(3)), nothing),
        (_rf("deep2", X), n(X)),
        # sc4: ( ( n(X), ( X > 1, ! ; true ) ) *-> R = X ; R = no ) — swipl: R in {1, 2}
        (
            _rf("sc4", R),
            _rsite(
                _rconj(n(X), _ror(_rconj(_rf(">", X, _rg(1)), _rs("!")), _rs("true"))),
                eq(R, X), eq(R, _rs("no"))
            )
        ),
        (_rf("sc9", X, R),
            _rconj(_rsite(_rs("true"), eq(R, _rs("a")), eq(R, _rs("b"))), _rf("deep2", X)))
    ]
end

@testset "soft-cut regression: a cut in a *-> condition after the soft-cut (SC4)" begin
    db = _rdb(_rscreg_clauses())
    sc9ops = Set{UInt64}()
    cref = _rproc(db, _rf("sc9", _rv(80), _rv(81))).definition.impl_clauses.first_clause
    while cref !== nothing
        union!(sc9ops, _rops(cref.clause))
        cref = cref.next
    end
    @test LK.I_DEPART in sc9ops && LK.C_SOFTCUT in sc9ops
    # SC4: the cut keeps the condition's first choice, so an extra R appears (or C_LSCUT throws)
    sc4 = [a for (a, _) in _rcall(db, _rf("sc4", _rv(90)))]
    @test sc4 == ["sc4(1)", "sc4(2)"]              # not sc4(3): the ! removed X=3
    if _R_SWIPL
        ours4 = [a * (d ? " det" : " nondet") for (a, d) in _rcall(db, _rf("sc4", _rv(90)))]
        push!(ours4, "end")
        @test ours4 == _rswipl(_rscreg_clauses(), [_rf("sc4", _rv(90))])
    end
    # sc9 answers + pools (the flatness test is the growth kill; this pins the answers)
    live = Bool[]
    sc9 = String[]
    for (a, det) in _rcall(
        db, _rf("sc9", _rv(90), _rv(91)); at=(qid, k) -> push!(live, _rpools_live(db.ld))
    )
        push!(sc9, a * (det ? " det" : " nondet"))
    end
    @test all(live) && sc9 == ["sc9(1,a) nondet", "sc9(2,a) nondet", "sc9(3,a) det"]
end

# SC11': dropUnlinkedChoices! asserts no LIVE record above p. Build a choice record above p that is
# NOT unlinked and require the AssertionError — the guard-turned-assert that obsoletes mutant SC11
# (a future call site that broke "no live record above p" would be caught here, not silent).
@testset "dropUnlinkedChoices! asserts no live record above p (SC11')" begin
    ld = _RDB().ld
    ch = LK.newChoice(ld, LK.CHP_JUMP, 0)              # a fresh choice record on the pool
    ld.choices[ch].base = ld.lTop + 100               # above any p we pass
    ld.choices[ch].unlinked = false                   # LIVE — must not be reclaimed
    @test_throws AssertionError LK.dropUnlinkedChoices!(ld, ld.lTop)
    ld.choices[ch].unlinked = true                    # unlinked: now it reclaims, no throw
    LK.dropUnlinkedChoices!(ld, ld.lTop)
    @test ld.nchoices == ch - 1
end

# V9d soft-cut, SC9: the I_DEPART reclaim. `lco()` emits the L_NOLCO block only when every
# argument is simple and none overwrites another; a COMPOUND arg (`sl`, `f(K)`) or a SWAP (`sw`,
# `B, A`) makes it bail, so the clause ends in a plain `I_DEPART` that runs its own LCO check. The
# soft-cut `( p2(X) *-> X == 2 ; true )` unlinks its else-choice in the MIDDLE branch (p2's choice
# is above it); `X == 2` fails for X=1, backtracks into p2, whose last clause pops p2's choice, and
# X=2 succeeds — so at the tail call `BFR <= FR` while the unlinked record is still above the frame.
# That is exactly where I_DEPART's `dropUnlinkedChoices!` is needed (SC9). Flat baseline; SC9 grows.
function _ri_depart_clauses()
    N, N1, A, B, K, X = (_rv(k) for k in 1:6)
    sc(c, t, e) = _ror(_rf("*->", c, t), e)
    cond = sc(_rf("p2", X), _rf("==", X, _rg(2)), _rs("true"))
    return Tuple{_R, Union{Nothing, _R}}[
        (_rf("p2", _rg(1)), nothing), (_rf("p2", _rg(2)), nothing),
        (_rf("sl", _rg(0), _rv(9)), _rs("!")),
        (
            _rf("sl", N, _rf("f", K)),
            _rconj(
                cond, _rf("is", N1, _rf("-", N, _rg(1))), _rf("sl", N1, _rf("f", K))
            )
        ),
        (_rf("sw", _rg(0), _rv(9), _rv(8)), _rs("!")),
        (
            _rf("sw", N, A, B),
            _rconj(
                cond, _rf("is", N1, _rf("-", N, _rg(1))), _rf("sw", N1, B, A)
            )
        )
    ]
end

@testset "flatness: a soft-cut whose plain-I_DEPART tail call reuses its frame stays flat (V9d, SC9)" begin
    db = _rdb(_ri_depart_clauses())
    # both recursive clauses end in a PLAIN I_DEPART (the LCO path SC9 removes the reclaim from),
    # not the L_NOLCO block — assert it, else `lco()` accepts shapes upstream rejects
    for (name, args) in (("sl", 2), ("sw", 3))
        ops = Set{UInt64}()
        cref =
            _rproc(db, mk_expr(_R, _R[_rs(name); [_rv(80 + i) for i in 1:args]])).definition.impl_clauses.first_clause
        while cref !== nothing
            union!(ops, _rops(cref.clause))
            cref = cref.next
        end
        @test LK.I_DEPART in ops && LK.C_SOFTCUT in ops
        @test !(LK.L_NOLCO in ops)
    end
    for (name, g) in (("sl", n -> _rf("sl", _rg(n), _rf("f", _rv(1)))),
        ("sw", n -> _rf("sw", _rg(n), _rg(7), _rg(8))))
        marks = Dict(k => _rhighwater(db, g(k)) for k in (10^3, 10^4, 10^5))
        @test marks[10 ^ 3][1] == marks[10 ^ 4][1] == marks[10 ^ 5][1]   # SC9: grows with N
        @info "$name (plain I_DEPART through *->), high-water qid+$(marks[10 ^ 3][1])"
    end
    @test db.ld.nchoices == 0 && db.ld.nframes == 0
end
