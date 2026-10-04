# ORIGINAL: live differential of the head compiler against swipl's vm_list; upstream has no counterpart (it tests SWI against itself).
# test/compile/test_head_code_swipl.jl — the clause index reads clause keys from compiled head code
# (src/pl-comp.jl), so the kernel's head code must be SWI's, instruction for instruction: which
# arguments become H_VOID, how runs of voids merge into H_VOID_N and vanish before H_POP and
# I_EXITFACT, H_FIRSTVAR against H_VAR, H_FUNCTOR against H_RFUNCTOR.
#
# Random heads — shared and singleton variables, atoms, small integers, compounds nested three
# deep — are compiled by the kernel and asserted in swipl, whose `vm_list/1` prints its code. The
# instruction sequences must be equal, OPERANDS included where both systems mean the same thing: the
# `H_VOID_N` count and the FRAME SLOT of `H_VAR`/`H_FIRSTVAR` — slots are compacted past voids
# (pl-comp.c `analyse_variables`), so a wrong layout shows here before any frame executes. And
# since V1 L2, every LITERAL operand BY VALUE — the kernel's from the clause's literal table, swipl's
# read back from `vm_list` as terms (atoms and strings by their codes, integers and rationals by
# value, floats by their bits) — and every functor by name and arity; the table's indices, like
# swipl's atom handles, are each system's own and never compared. No name maps since V1's L1:
# integers are `h_smallint`/`h_mpz` by tagged storage, rationals `h_mpq`, floats `h_float`, list
# cells `h_list`/`h_rlist`/`h_list_ff` — a second random sample draws those (`_hlarg`) — and
# `h_list_ff`'s two slots are compared like `h_var`'s.
using Random
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "code_testlib.jl"))
const _H = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
"The database the fresh predicates of this file are compiled in (its global data)."
const _HGD = LK.PL_global_data{_H}()
_hs(n) = lk_sym(_H, Symbol(n))
# Any vector of terms: a comprehension's element type is a LEAF type when the term type is abstract.
_he(f, xs::AbstractVector) = mk_expr(_H, _H[_hs(f); xs])

"A random head argument: a variable from `shared` (or a fresh one), an atom, an int, a compound."
function _harg(rng::AbstractRNG, shared::AbstractVector, depth::Int)::_H
    r = rand(rng)
    if r < 0.3
        return mk_var(_H, rand(rng, UInt64(1):UInt64(1 << 40)))     # almost surely a singleton
    elseif r < 0.45
        return rand(rng, shared)
    elseif r < 0.6
        rand(rng) < 0.25 && return mk_nil(_H)            # SWI-7's []: H_NIL, not H_ATOM
        return _hs(rand(rng, (:a, :b, :c)))
    elseif r < 0.7
        return lk_gnd(_H, rand(rng, 0:9))
    elseif depth < 3
        return _he(
            rand(rng, (:f, :g, :h)),
            [_harg(rng, shared, depth + 1) for _ in 1:rand(rng, 1:3)]
        )
    end
    return _hs(:z)
end

"A list cell `[h|t]` — written `'[|]'(h,t)` by `_htext`, which swipl reads as the same cell."
_hcons(h::_H, t::_H) = mk_expr(_H, _H[_hs("[|]"), h, t])

"Integers at the edges of the tagged range (±2^56) and of Int64, and in between."
const _HINTS = (
    0, 1, -1, 7, 2^31, -2^31 - 1, 2^56 - 1, 2^56, -2^56, -2^56 - 1, typemax(Int64),
    typemin(Int64)
)

"A random number of every kind: Int64 and BigInt integers, canonical rationals, floats."
function _hnum(rng::AbstractRNG)::_H
    r = rand(rng)
    r < 0.35 && return lk_gnd(_H, rand(rng, _HINTS))
    r < 0.45 && return lk_gnd(_H, rand(rng, (big(5), big(2)^56, -big(2)^70, big(2)^63)))
    r < 0.65 &&
        return lk_gnd(_H, Rational{BigInt}(rand(rng, (1 // 3, -5 // 7, 7 // 2, 2 // 9))))
    r < 0.85 && return lk_gnd(_H, rand(rng, (2.5, -0.0, 1.0e20, 3.0, 0.1, 5.0e-324)))
    r < 0.92 && return lk_gnd(_H, rand(rng, ("", "abc", "it's", "q\"x")))   # strings: h_string
    return lk_gnd(_H, rand(rng, -100:100))
end

"A random literal or list head argument (V1, L1): numbers of every kind, lists, `'[|]'/1`."
function _hlarg(rng::AbstractRNG, shared::AbstractVector, depth::Int)::_H
    r = rand(rng)
    if r < 0.15
        return mk_var(_H, rand(rng, UInt64(1):UInt64(1 << 40)))
    elseif r < 0.35
        return rand(rng, shared)
    elseif r < 0.55
        return _hnum(rng)
    elseif r < 0.62
        return rand(rng) < 0.5 ? mk_nil(_H) : _hs(rand(rng, ("[]", "a", "[|]")))
    elseif depth < 3
        rand(rng) < 0.1 && return _he("[|]", [_hlarg(rng, shared, depth + 1)])   # no list cell
        t = rand(rng) < 0.5 ? mk_nil(_H) : _hlarg(rng, shared, depth + 1)
        for _ in 1:rand(rng, 1:3)
            t = _hcons(_hlarg(rng, shared, depth + 1), t)
        end
        return t
    end
    return _hs(:z)
end

"Prolog text: a variable occurring once prints `_`, the others `V<key>`."
function _htext(t, counts::Dict{UInt64, Int})::String
    k = kind(t)
    k === VAR && return counts[var_key(t)] == 1 ? "_" : "V$(var_key(t))"
    k === EXPR || return ix_text(t)
    return ix_text(child(t, 1)) * "(" *
           join([_htext(child(t, i), counts) for i in 2:nchildren(t)], ",") * ")"
end
function _hcount!(c::Dict{UInt64, Int}, t)::Dict{UInt64, Int}
    if kind(t) === VAR
        c[var_key(t)] = get(c, var_key(t), 0) + 1
    elseif kind(t) === EXPR
        foreach(i -> _hcount!(c, child(t, i)), 1:nchildren(t))
    end
    return c
end

"`head` compiled as a clause of its predicate in this file's database (never asserted)."
function _hclause(head::_H)::LK.Clause{_H}
    user = LK.MODULE_user(_HGD)
    proc = LK.lookupProcedure(sym_key(child(head, 1)), nchildren(head) - 1, user)
    return LK.compileClause(_HGD, head, nothing, proc, user)
end

"""
The kernel's head code of `head`: instruction names, with the operands where both systems mean
the same thing — `h_void_n(N)` its count, `h_var(N)`/`h_firstvar(N)` the frame slot — and, since
V1 L2, every LITERAL by value from the clause's literal table (`_hlit`) and every functor by its
head symbol's literal and its arity: the table's INDICES are the kernel's own and never compared.
"""
function _hcode(head::_H)::Vector{String}
    cl = _hclause(head)
    return _hcode_of(cl.codes, cl.literals)
end

"The frame size the kernel compiles `head` to: the clause's `variables` (and `prolog_vars`)."
function _hframe(head::_H)::Tuple{Int, Int}
    cl = _hclause(head)
    return (Int(cl.variables), Int(cl.prolog_vars))
end

# The swipl side: `vm_list/1`'s text is read back AS TERMS by swipl itself, and each operand written
# by value — atoms and strings as code lists, numbers by kind, floats in their shortest round-trip
# form (`~h`, whose bits Julia compares), functors as name and arity.
const _HSWIPL_RENDER =
    raw"""
hc_show(PI) :-
    with_output_to(string(S), vm_list(PI)),
    split_string(S, "\n", "", Ls),
    append(_, [L0|Rest], Ls), sub_string(L0, 0, _, _, "clause 1 ("), !,
    forall(( member(L, Rest), hc_line(L, I) ), ( hc_render(I, Out), writeln(Out) )).
hc_line(L, I) :-
    split_string(L, "", " ", [T]), sub_string(T, B, 1, _, " "), !,
    sub_string(T, 0, B, _, Num), number_string(_, Num),
    B1 is B + 1, sub_string(T, B1, _, 0, Rest), term_string(I, Rest).
""" * _HSWIPL_OPS

"swipl's code for each of `heads`, from `vm_list/1`, operands by value."
function _hswipl(heads::Vector{String}, names::Vector{String})::Vector{Vector{String}}
    mktempdir() do d
        f = joinpath(d, "hc.pl")
        write(
            f,
            ":- initialization(main, main).\n" * _HSWIPL_RENDER * "main :-\n" *
            join(["    assertz($h)" for h in heads], ",\n") * ",\n" *
            "    forall(member(PI, [" * join(names, ",") *
            "]), (hc_show(PI), writeln('@@end'))).\n"
        )
        out = split(read(pipeline(`swipl -q $f`; stderr=devnull), String), '\n')
        res = Vector{String}[]
        cur = String[]
        for l in out
            if l == "@@end"
                push!(res, cur)
                cur = String[]
            elseif !isempty(l)
                push!(cur, _hswipl_floats(l))
            end
        end
        return res
    end
end

const _HSWIPL = Sys.which("swipl")
const _HSWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

@testset "head code vs swipl vm_list" begin
    rng = Xoshiro(20261002)
    heads = _H[]
    for k in 1:300
        shared = [mk_var(_H, UInt64(10_000 * k + j)) for j in 1:3]
        push!(heads, _he("hc$k", [_harg(rng, shared, 1) for _ in 1:rand(rng, 1:6)]))
    end
    # V1, L1: literal and list heads, a second sample (the first keeps its draws)
    for k in 1:300
        shared = [mk_var(_H, UInt64(20_000_000 + 10_000 * k + j)) for j in 1:3]
        push!(heads, _he("hl$k", [_hlarg(rng, shared, 1) for _ in 1:rand(rng, 1:5)]))
    end
    ours = [_hcode(h) for h in heads]
    # …and it reaches every new instruction
    for i in (
        "h_smallint", "h_mpz", "h_mpq", "h_float", "h_string", "h_nil", "h_list", "h_rlist"
    )
        @test any(c -> any(x -> x == i || startswith(x, i * "("), c), ours)
    end
    @test any(c -> any(startswith("h_list_ff("), c), ours)
    # the sample exercises every merge: void runs, voids dropped before H_POP and I_EXITFACT
    @test any(c -> any(startswith("h_void_n"), c), ours)
    @test any(
        c -> any(i -> c[i] == "h_pop" && i > 1 && c[i - 1] != "h_pop", eachindex(c)), ours
    )
    # (`h_var`/`h_firstvar` carry their slot, so they are matched by prefix)
    @test any(c -> any(startswith("h_rfunctor("), c), ours) &&
        any(c -> any(startswith("h_firstvar("), c), ours)
    @test any(c -> any(startswith("h_var("), c), ours)
    # a hand-checked case: p(_,_,a) is h_void_n(2), h_atom, i_exitfact (swipl vm_list, LogicKernel#1)
    @test _hcode(_he(:p, [mk_var(_H, UInt64(1)), mk_var(_H, UInt64(2)), _hs(:a)])) ==
        ["h_void_n(2)", "h_atom($(_ha("a")))", "i_exitfact"]
    # slots are COMPACTED past voids (pl-comp.c analyse_variables, `n + argvars - body_voids`),
    # pinned with swipl 10.1.16's vm_list: p(f(_A,B,B)) puts B in slot 1, not 2 ...
    vA, vB = mk_var(_H, UInt64(1)), mk_var(_H, UInt64(2))
    @test _hcode(_he(:p, [_he(:f, [vA, vB, vB])])) == [
        "h_functor($(_hF("f", 3)))", "h_void", "h_firstvar(1)", "h_var(1)", "h_pop",
        "i_exitfact"
    ]
    # ... and q(X,g(_,Y,_,Y),X) puts Y in slot 3: of the variables numbered above the arity
    # (_ 3, Y 4, _ 5), the void before Y is not a slot
    vX, vY = mk_var(_H, UInt64(3)), mk_var(_H, UInt64(4))
    @test _hcode(
        _he(:q, [vX, _he(:g, [mk_var(_H, UInt64(5)), vY, mk_var(_H, UInt64(6)), vY]), vX])
    ) == [
        "h_void", "h_functor($(_hF("g", 4)))", "h_void", "h_firstvar(3)", "h_void",
        "h_var(3)", "h_pop", "h_var(0)", "i_exitfact"
    ]
    # ... and ONLY voids above the arity are compacted — an argument keeps its slot whatever it
    # holds: p(_, f(_,Y,Y)) puts Y in slot 2 (argument 0's void is not counted, f's `_` is). A fix
    # that also counted argument voids would say 1, and the two cases above would not notice.
    vY2 = mk_var(_H, UInt64(7))
    @test _hcode(
        _he(:p, [mk_var(_H, UInt64(8)), _he(:f, [mk_var(_H, UInt64(9)), vY2, vY2])])
    ) ==
        [
        "h_void", "h_functor($(_hF("f", 3)))", "h_void", "h_firstvar(2)", "h_var(2)",
        "h_pop", "i_exitfact"
    ]
    # the frame is sized by the SAME count (pl-comp.c: prolog_vars = variables =
    # nvars + arity + argvars - body_voids): the arguments, then the compacted variables. The
    # expected values come from that formula, not from swipl: no predicate exposes a clause's
    # variable count — only the QLF writer serialises it (pl-qlf.c:2915-2916) and a captured
    # continuation's arity reflects it (pl-cont.c:475), which needs a body, not a fact.
    # lists (user, 2026-10-04): `[a|T]`, `'[|]'(a,T)` and `[a,b]` — the first two are ONE term to
    # both systems — and the integer split by tagged storage, pinned with swipl 10.1.16's vm_list
    vT, vX2, vY3 = mk_var(_H, UInt64(11)), mk_var(_H, UInt64(12)), mk_var(_H, UInt64(13))
    lists = [
        ("lp1([a|T])", _he(:lp1, [_hcons(_hs(:a), vT)])),
        ("lp2('[|]'(a,T))", _he(:lp2, [_hcons(_hs(:a), vT)])),
        ("lp3([a,b])", _he(:lp3, [_hcons(_hs(:a), _hcons(_hs(:b), mk_nil(_H)))])),
        ("lp4([X|Y],f(X,Y))", _he(:lp4, [_hcons(vX2, vY3), _he(:f, [vX2, vY3])])),
        ("lp5(f(a,[b]))", _he(:lp5, [_he(:f, [_hs(:a), _hcons(_hs(:b), mk_nil(_H))])])),
        (
            "lp6(72057594037927935,72057594037927936)",
            _he(:lp6, [lk_gnd(_H, 2^56 - 1), lk_gnd(_H, 2^56)])
        ),
        (
            "lp7(-72057594037927936,-72057594037927937)",
            _he(:lp7, [lk_gnd(_H, -2^56), lk_gnd(_H, -2^56 - 1)])
        )
    ]
    a, b, f2 = "h_atom($(_ha("a")))", "h_atom($(_ha("b")))", "h_functor($(_hF("f", 2)))"
    want = [
        ["h_list", a, "h_pop", "i_exitfact"],
        ["h_list", a, "h_pop", "i_exitfact"],
        ["h_list", a, "h_rlist", b, "h_nil", "h_pop", "i_exitfact"],
        ["h_list_ff(2,3)", f2, "h_var(2)", "h_var(3)", "h_pop", "i_exitfact"],
        [f2, a, "h_rlist", b, "h_nil", "h_pop", "i_exitfact"],
        ["h_smallint(i:72057594037927935)", "h_mpz(i:72057594037927936)", "i_exitfact"],
        ["h_smallint(i:-72057594037927936)", "h_mpz(i:-72057594037927937)", "i_exitfact"]
    ]
    @test [_hcode(h) for (_, h) in lists] == want
    @test _hcode(lists[1][2]) == _hcode(lists[2][2])
    @test _hframe(_he(:p, [_he(:f, [vA, vB, vB])])) == (2, 2)
    @test _hframe(
        _he(:q, [vX, _he(:g, [mk_var(_H, UInt64(5)), vY, mk_var(_H, UInt64(6)), vY]), vX])
    ) == (4, 4)
    @test _hframe(
        _he(:p, [mk_var(_H, UInt64(8)), _he(:f, [mk_var(_H, UInt64(9)), vY2, vY2])])
    ) == (3, 3)
    if _HSWIPL !== nothing
        @testset "identical to swipl" begin
            texts = [_htext(h, _hcount!(Dict{UInt64, Int}(), h)) for h in heads]
            names = ["$(lk_name(child(h, 1)))/$(nchildren(h) - 1)" for h in heads]
            theirs = _hswipl(texts, names)
            @test length(theirs) == length(heads)
            bad = [
                k for k in eachindex(heads) if k > length(theirs) || ours[k] != theirs[k]
            ]
            for k in bad[1:min(end, 5)]
                println(stderr, "  ", texts[k], "\n    ours  ", ours[k], "\n    swipl ",
                    k <= length(theirs) ? theirs[k] : "<missing>")
            end
            @test isempty(bad)
            # the pinned heads, live: swipl compiles the very same sequences
            theirs_l = _hswipl(
                first.(lists),
                ["$(lk_name(child(h, 1)))/$(nchildren(h) - 1)" for (_, h) in lists]
            )
            @test theirs_l == want
        end
    elseif _HSWIPL_REQUIRED
        error(
            "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the head-code differential would be skipped"
        )
    else
        @info "HEAD CODE vs swipl NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
        @testset "swipl comparison skipped only where it is not required" begin
            @test !_HSWIPL_REQUIRED
        end
    end
end
