# ORIGINAL: a LIVE three-mode differential of the VM's head unification against swipl (V4a); upstream has no such test.
# test/core_lang/test_head_unify_swipl.jl — random clause heads called with random goals through the
# VIRTUAL MACHINE (`PL_open_query`/`PL_next_solution`, `vm_call`'s path), under every `occurs_check`
# mode (false, true, error), against swipl calling the same clause with the same goal. TERM-GENERIC.
#
# For each case and mode both give the same OUTCOME: `ok N A1 … AN` — the number of answers and
# each answer, the goal with its bindings, printed as `write_canonical/1` prints it (repeated
# variables `A, B, …` by first occurrence, singletons `_`; `cyclic` for a rational tree, legal under
# `false`) — or `err E`, the error term, `error(occurs_check(V, T), context(Name/Arity, _))`, the
# CONTEXT included (user, 2026-10-05). So it compares bindings up to renaming, failures, and errors.
#
# Each case is ONE fact `hI(H1, …, Hk)`, so the clause's whole head runs on a success: the cases that
# succeed under `true` and under `error` must, together, have run EVERY head instruction — the list
# forms and `H_FIRSTVAR` included — because under those two modes the VM reads the compound it built
# where upstream writes into it (decision 3, DIVERGES; user, 2026-10-05: tested, not argued). A few
# two-clause cases pin that an error in the first clause stops the second being tried.
#
# swipl present ⇒ the differential runs; absent ⇒ an error under LOGICKERNEL_REQUIRE_SWIPL=1, else a
# loud note — never a silent pass. swipl 10.1.16 can ABORT in its occurs-check error path
# (LogicKernel#3): it runs in chunks, and a chunk that aborts is re-run one case per process.
using Test, LogicKernel, Random
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))

const _HT = lk_term_type(Union{Int64, BigInt, Float64, String, Rational{BigInt}})
_hs(x::Symbol) = lk_sym(_HT, x)
_hc(f::Symbol, xs::_HT...) = mk_expr(_HT, _HT[_hs(f), xs...])
_hv(k::Int) = mk_var(_HT, UInt64(k))
_hlist(h::_HT, t::_HT) = mk_expr(_HT, _HT[_hs(Symbol("[|]")), h, t])
const _HHEADVARS = 101:105                                 # the clause's variables
const _HGOALVARS = 1:3                                     # the goal's: few, so they alias

"A random constant: atoms, `[]`, small and big integers, a rational, floats with the signed zeros, a string."
function _hatom(rng)::_HT
    k = rand(rng, 1:9)
    k == 1 && return _hs(rand(rng, (:a, :b)))
    k == 2 && return mk_nil(_HT)
    k == 3 && return lk_gnd(_HT, rand(rng, (0, 1, -3)))
    k == 4 && return lk_gnd(_HT, big(2)^70)
    k == 5 && return lk_gnd(_HT, rand(rng, (big(1) // 3, big(-2) // 3)))
    k == 6 && return lk_gnd(_HT, rand(rng, (0.0, -0.0, 1.5)))
    k == 7 && return lk_gnd(_HT, "s")
    return _hs(rand(rng, (:a, :b)))
end

"A random head argument of depth ≤ `d`: constants, the clause's variables, lists, compounds."
function _hterm(rng, d::Int)::_HT
    r = rand(rng)
    if d == 0 || r < 0.35
        return rand(rng) < 0.45 ? _hv(rand(rng, _HHEADVARS)) : _hatom(rng)
    elseif r < 0.55
        return _hlist(_hterm(rng, d - 1), _hterm(rng, d - 1))
    end
    f, n = rand(rng, ((:f, 1), (:g, 2), (:h, 3)))
    return mk_expr(_HT, _HT[_hs(f); [_hterm(rng, d - 1) for _ in 1:n]])
end

"A random goal term of depth ≤ `d` over the goal's variables."
function _hgterm(rng, d::Int)::_HT
    r = rand(rng)
    if d == 0 || r < 0.4
        return rand(rng) < 0.5 ? _hv(rand(rng, _HGOALVARS)) : _hatom(rng)
    elseif r < 0.55
        return _hlist(_hgterm(rng, d - 1), _hgterm(rng, d - 1))
    end
    f, n = rand(rng, ((:f, 1), (:g, 2)))
    return mk_expr(_HT, _HT[_hs(f); [_hgterm(rng, d - 1) for _ in 1:n]])
end

"`t` with each variable `k` in `m` replaced by `m[k]`."
function _hsubst(t::_HT, m::Dict{UInt64, _HT})::_HT
    kind(t) === VAR && return get(m, var_key(t), t)
    kind(t) === EXPR || return t
    return mk_expr(_HT, _HT[_hsubst(child(t, i), m) for i in 1:nchildren(t)])
end

"`t` with each subterm replaced, with probability `p`, by one of the goal's variables."
function _hgeneralise(rng, t::_HT, p::Float64)::_HT
    rand(rng) < p && return _hv(rand(rng, _HGOALVARS))
    kind(t) === EXPR || return t
    return mk_expr(
        _HT, _HT[child(t, 1); [_hgeneralise(rng, child(t, i), p) for i in 2:nchildren(t)]]
    )
end

"A goal argument against head argument `h`: an instance, a generalisation, a variable, or another term."
function _hgoal_arg(rng, h::_HT)::_HT
    how = rand(rng, (:instance, :instance, :generalise, :generalise, :var, :other))
    if how === :instance
        m = Dict{UInt64, _HT}(UInt64(k) => _hgterm(rng, 1) for k in _HHEADVARS)
        return _hsubst(h, m)
    elseif how === :generalise
        m = Dict{UInt64, _HT}(UInt64(k) => _hgterm(rng, 1) for k in _HHEADVARS)
        return _hgeneralise(rng, _hsubst(h, m), 0.3)
    elseif how === :var
        return _hv(rand(rng, _HGOALVARS))
    end
    return _hgterm(rng, 2)
end

"`n` random cases and the pinned ones: `(clauses, goal)`, the predicate named by the goal."
function _hcases(rng, n::Int)
    cases = Tuple{Vector{_HT}, _HT}[]
    for i in 1:n
        k = rand(rng, 1:4)
        args = [_hterm(rng, 3) for _ in 1:k]
        name = Symbol("h$i")
        goal = mk_expr(_HT, _HT[_hs(name); [_hgoal_arg(rng, a) for a in args]])
        push!(cases, (_HT[mk_expr(_HT, _HT[_hs(name); args])], goal))
    end
    # pinned: the shapes the occurs check is about (V4a research, probed in swipl 10.1.16)
    X, Y, A, B = _hv(101), _hv(102), _hv(1), _hv(2)
    push!(cases, ([_hc(:po1, X, _hc(:f, X))], _hc(:po1, A, A)))              # r(X, f(X)) as r(V, V)
    push!(cases, ([_hc(:po2, X, Y, _hc(:f, Y, X))], _hc(:po2, A, A, A)))     # p3(X,Y,f(Y,X))
    push!(cases, ([_hc(:po3, _hc(:f, X), X)], _hc(:po3, A, A)))              # p(f(X), X)
    push!(cases, ([_hc(:po4, X, X)], _hc(:po4, B, _hc(:f, B))))              # p(X, X) as p(B, f(B))
    push!(
        cases, ([_hc(:po5, _hlist(X, Y), _hc(:f, X, Y))], _hc(:po5, A, _hc(:f, _hs(:a), B)))
    )  # H_LIST_FF
    push!(cases, ([_hc(:po9, _hlist(X, Y), _hc(:f, X, Y))], _hc(:po9, A, _hc(:f, B, A))))  # … a cycle
    push!(
        cases, ([_hc(:pa9, _hlist(X, Y), _hc(:f, X, Y))], _hc(:pa9, _hlist(_hs(:a), B), A))
    )   # … a list
    push!(cases, ([_hc(:po6, _hc(:g, X, Y), Y, X)], _hc(:po6, A, A, A)))     # w(g(X,Y),Y,X)
    # an error in clause 1 stops clause 2; an error comes before a later argument's failure
    push!(
        cases, ([_hc(:po7, _hc(:f, X), X), _hc(:po7, _hv(103), _hv(104))], _hc(:po7, A, A))
    )
    push!(cases, ([_hc(:po8, _hc(:f, X), X, _hs(:a))], _hc(:po8, A, A, _hs(:b))))
    return cases
end

"An atom as `write_canonical/1` writes it: a name made only of symbol characters bare (`/`)."
function _hatom_text(t::_HT)::String
    n = String(lk_name(t))
    !is_nil(t) && !isempty(n) && all(in("#\$&*+-./:<=>?@^~\\"), n) && return n
    return lk_atom_text(t)
end

"""
`t` written as `write_canonical/1` writes it, each variable by `var(t)`: lists in bracket notation
(`[a,b]`, `[a|T]`), compounds `f(…)`, atoms quoted as needed.
"""
function _hwrite(t::_HT, var)::String
    k = kind(t)
    k === VAR && return var(t)
    k === SYM && return _hatom_text(t)
    if k === GND
        v = lk_value(t)
        v isa String && return "\"$v\""
        v isa Rational && return "$(numerator(v))r$(denominator(v))"
        return string(v)
    end
    if is_pair(t)
        elems = String[]
        while is_pair(t)
            push!(elems, _hwrite(child(t, 2), var))
            t = child(t, 3)
        end
        tail = is_nil(t) ? "" : "|" * _hwrite(t, var)
        return "[" * join(elems, ",") * tail * "]"
    end
    return _hwrite(child(t, 1), var) * "(" *
           join((_hwrite(child(t, i), var) for i in 2:nchildren(t)), ",") * ")"
end

"Prolog source of `t`; variable `k` is `V<k>`."
_hsrc(t::_HT)::String = _hwrite(t, v -> "V$(var_key(v))")

"`write_canonical/1` of `t`: repeated variables `A, B, …` by first occurrence, singletons `_`."
function _hcanonical(t::_HT)::String
    counts = Dict{UInt64, Int}()
    order = UInt64[]
    function count!(u)
        if kind(u) === VAR
            c = get(counts, var_key(u), 0)
            c == 0 && push!(order, var_key(u))
            counts[var_key(u)] = c + 1
        elseif kind(u) === EXPR
            foreach(i -> count!(child(u, i)), 1:nchildren(u))
        end
    end
    count!(t)
    names = Dict{UInt64, String}()
    for k in order
        counts[k] > 1 && (names[k] = string('A' + length(names)))
    end
    return _hwrite(t, u -> get(names, var_key(u), "_"))
end

const _HMODES = ((LK.OCCURS_CHECK_FALSE, "false"), (LK.OCCURS_CHECK_TRUE, "true"),
    (LK.OCCURS_CHECK_ERROR, "error"))

"""
The VM's outcome of calling `goal` (its predicate `p`) in `mode`: `ok N A1 … AN` or `err E` — with
`PL_Q_CATCH_EXCEPTION`, the error read back with `PL_exception`, as a caller does.
"""
function _hvm(p::IxPred{_HT}, goal::_HT, mode)::String
    gd, ld = p.db.gd, p.db.ld
    ld.prolog_flag_occurs_check = mode
    fid = LK.PL_open_foreign_frame(ld)
    ar = nchildren(goal) - 1
    args = LK.PL_new_term_refs(ld, ar)
    for i in 1:ar
        ld.slots[args + i] = child(goal, i + 1)
    end
    flags = LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS
    qid = LK.PL_open_query(gd, ld, nothing, flags, p.proc, args)
    answers = String[]
    out = ""
    while true
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            a = try
                _hcanonical(LK.resolve_term(ld, goal))
            catch e
                e isa ArgumentError || rethrow()
                "cyclic"
            end
            push!(answers, a)
        else
            if rc == LK.PL_S_EXCEPTION
                ex = LK.PL_exception(ld, qid)
                out = "err " * _hcanonical(LK.resolve_term(ld, ld.slots[ex + 1]))
            end
            break
        end
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    ld.prolog_flag_occurs_check = LK.OCCURS_CHECK_FALSE
    isempty(out) || return out
    return strip("ok $(length(answers)) " * join(answers, " "))
end

# the driver swipl runs for one chunk of cases (the mode is appended as its own line)
const _HSWIPL_DRIVER = raw"""
out(X) :- ( cyclic_term(X) -> write(cyclic) ; write_canonical(X) ).
run(Mode) :-
    forall(case(I, G),
           ( set_prolog_flag(occurs_check, Mode),
             catch(( findall(G, G, L), R = ok(L) ), error(E, C), R = err(error(E, C))),
             set_prolog_flag(occurs_check, false),
             format("~d ~w ", [I, Mode]),
             ( R = ok(L1) -> length(L1, N), format("ok ~d", [N]),
                             forall(member(A, L1), ( write(' '), out(A) ))
             ; R = err(Ex), write('err '), write_canonical(Ex) ),
             nl )).
"""

"""
swipl's outcomes for the cases `idx` in `mode`, into `res`; `false` if swipl died by a signal.
`prelude` is loaded before the cases (a flag the clauses are compiled under).
"""
function _hswipl_run!(
    res::Dict{Tuple{Int, String}, String}, cases, idx::Vector{Int}, mode::String;
    prelude::String=""
)::Bool
    prog = IOBuffer()
    print(prog, prelude)
    println(prog, ":- style_check(-singleton).")
    println(prog, ":- set_prolog_flag(double_quotes, string).")
    println(prog, ":- discontiguous case/2.")
    for i in idx
        clauses, goal = cases[i]
        foreach(c -> println(prog, _hsrc(c), "."), clauses)
        println(prog, "case($i, ", _hsrc(goal), ").")
    end
    print(prog, _HSWIPL_DRIVER)
    println(prog, ":- initialization((run(" * mode * "), halt)).")
    out = IOBuffer()
    proc = mktempdir() do d
        f = joinpath(d, "heads.pl")
        write(f, String(take!(prog)))
        run(pipeline(ignorestatus(`swipl -q $f`); stdout=out, stderr=devnull))
    end
    proc.termsignal != 0 && return false
    success(proc) || error("swipl failed (exit $(proc.exitcode)) on cases $(first(idx))…")
    n = 0
    for l in eachline(IOBuffer(take!(out)))
        i, m, r = split(l, ' '; limit=3)
        res[(parse(Int, i), String(m))] = String(r)
        n += 1
    end
    n == length(idx) || error("swipl answered $n of $(length(idx)) in mode $mode")
    return true
end

"swipl's outcomes for every case in every mode, and how many chunks aborted (LogicKernel#3)."
function _hswipl(cases; prelude::String="")
    res = Dict{Tuple{Int, String}, String}()
    aborts = 0
    for (_, mode) in _HMODES, chunk in Iterators.partition(eachindex(cases), 100)
        if !_hswipl_run!(res, cases, collect(chunk), mode; prelude=prelude)
            aborts += 1
            for i in chunk
                _hswipl_run!(res, cases, [i], mode; prelude=prelude) ||
                    error("swipl aborts on case $i alone in mode $mode")
            end
        end
    end
    return res, aborts
end

"The instructions of clause `cl`'s code."
function _hinstructions(cl::LK.Clause{_HT})::Set{UInt64}
    s = Set{UInt64}()
    pc = LK.Code(cl, 1)
    while pc.pc <= length(cl.codes)
        push!(s, LK.decode(pc))
        pc = LK.stepPC(pc)
    end
    return s
end

const _HSWIPL = Sys.which("swipl")
const _HSWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"
const _HHEAD_INSTRUCTIONS = (
    LK.H_ATOM, LK.H_SMALLINT, LK.H_NIL, LK.H_FLOAT, LK.H_MPZ, LK.H_MPQ, LK.H_STRING,
    LK.H_VOID,
    LK.H_VOID_N, LK.H_VAR, LK.H_FIRSTVAR, LK.H_FUNCTOR, LK.H_RFUNCTOR, LK.H_LIST,
    LK.H_RLIST,
    LK.H_POP, LK.H_LIST_FF
)

@testset "head unification through the VM vs swipl, in every occurs_check mode" begin
    cases = _hcases(MersenneTwister(20261005), 400)
    db = IxDB{_HT}()
    preds = IxPred{_HT}[]
    for (clauses, goal) in cases
        p = ix_pred(_HT, lk_name(child(goal, 1)), nchildren(goal) - 1; db=db)
        foreach(c -> ix_assertz!(p, c), clauses)
        push!(preds, p)
    end
    ours = Dict{Tuple{Int, String}, String}()
    for (mode, m) in _HMODES, i in eachindex(cases)
        ours[(i, m)] = _hvm(preds[i], cases[i][2], mode)
    end
    named(name) = findfirst(c -> lk_name(child(c[2], 1)) === name, cases)

    @testset "the data exercises every head instruction, in every mode" begin
        for (_, m) in _HMODES
            ran = Set{UInt64}()
            for i in eachindex(cases)
                (length(cases[i][1]) == 1 && startswith(ours[(i, m)], "ok 1")) || continue
                union!(ran, _hinstructions(preds[i].def.impl_clauses.first_clause.clause))
            end
            missing = [LK.codeTable(c).name for c in _HHEAD_INSTRUCTIONS if !(c in ran)]
            isempty(missing) || println(stderr, "  not run under $m: ", missing)
            @test isempty(missing)
        end
        # a compound head argument met an unbound goal argument and the call succeeded — the builder
        # under `false`, the read over a fresh compound under `true`/`error` — in every mode
        unbound(i) = any(
            j ->
                kind(child(cases[i][2], j)) === VAR &&
                kind(child(cases[i][1][1], j)) === EXPR,
            2:nchildren(cases[i][2])
        )
        for (_, m) in _HMODES
            @test count(
                i -> unbound(i) && startswith(ours[(i, m)], "ok 1"), eachindex(cases)
            ) >
                20
        end
        @test count(i -> startswith(ours[(i, "error")], "err"), eachindex(cases)) > 5
        @test count(i -> occursin("cyclic", ours[(i, "false")]), eachindex(cases)) > 3
    end

    @testset "pinned: an error in clause 1 stops clause 2, and comes before a later failure" begin
        @test startswith(ours[(named(:po7), "false")], "ok 2 ")
        @test ours[(named(:po7), "true")] == "ok 1 po7(A,A)"   # clause 2; the goal's aliasing kept
        @test ours[(named(:po7), "error")] ==
            "err error(occurs_check(A,f(A)),context(/(po7,2),_))"
        @test ours[(named(:po8), "error")] ==
            "err error(occurs_check(A,f(A)),context(/(po8,3),_))"
        @test startswith(ours[(named(:po9), "error")], "err error(occurs_check(")
        @test ours[(named(:po8), "true")] == "ok 0" &&
            ours[(named(:po8), "false")] == "ok 0"
    end

    if _HSWIPL !== nothing
        @testset "identical to swipl" begin
            theirs, aborts = _hswipl(cases)
            bad = [
                (i, m) for i in eachindex(cases) for (_, m) in _HMODES if
                ours[(i, m)] != theirs[(i, m)]
            ]
            for (i, m) in bad[1:min(end, 6)]
                println(stderr, "  case $i ($m): ", join(_hsrc.(cases[i][1]), ". "), " ?- ",
                    _hsrc(cases[i][2]), "\n    ours  ", ours[(i, m)], "\n    swipl ",
                    theirs[(i, m)])
            end
            @test isempty(bad)
            @test length(theirs) == 3 * length(cases)
            @info "head unification: $(length(cases)) cases × 3 modes identical to swipl; $aborts chunk(s) re-run one by one after a swipl abort (LogicKernel#3)"
        end
    elseif _HSWIPL_REQUIRED
        error(
            "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the head differential would be skipped"
        )
    else
        @info "HEAD UNIFICATION vs swipl NOT RUN: `swipl` is not on PATH here."
        @testset "swipl comparison skipped only where it is not required" begin
            @test !_HSWIPL_REQUIRED
        end
    end
end

# ── body unification in every mode (V9a; user, 2026-10-06) ──────────────────────────────────────
# The inline unification family (`B_UNIFY_*`, `B_EQ_*`, `B_NEQ_*`, `I_TRUE`, `I_FAIL`, `C_VAR`)
# through the VM, against swipl consulting the same clauses, in every `occurs_check` mode. Under
# `true`/`error` upstream turns every body unification into a call of `=/2` (`slow_unify`), so an
# error's context is `system:(=)/2`, on both sides since V5c gave definitions their module. Since V9b a leading `ArgVar = Term` moves into the head (`optimise_unify`): every case runs
# with the flag on (swipl's default) and off, each against swipl under the same flag. PINNED (user,
# 2026-10-06, 3a): `X = f(X)` with `X` a first occurrence is cyclic under `false`, fails under
# `true` and raises under `error`; and the cyclic term compared with itself (`==`, `compare/3`).
_hbr(h::_HT, b::_HT) = _hc(Symbol(":-"), h, b)
_hbc(gs::_HT...) = foldr((a, b) -> _hc(Symbol(","), a, b), gs)
const _HB_CASES =
    let X = _hv(101), Y = _hv(102), Z = _hv(103), O = _hv(104), W = _hv(105), A = _hv(1),
        B = _hv(2)

        [
            # (clauses, goal): FIRSTVAR, cyclic; VAR + H_VAR, cyclic; VV; FV + VC; FC + EQ_VC; NEQ_VC
            (
                [_hbr(_hc(:hb1, X), _hbc(_hc(:(=), Y, _hc(:f, Y)), _hc(:(=), X, Y)))],
                _hc(:hb1, A)
            ),
            ([_hbr(_hc(:hb2, X), _hc(:(=), X, _hc(:f, X)))], _hc(:hb2, A)),
            ([_hbr(_hc(:hb3, X, Y), _hc(:(=), X, Y))], _hc(:hb3, A, _hc(:g, A))),
            ([_hbr(_hc(:hb3b, X, Y), _hc(:(=), X, Y))], _hc(:hb3b, A, _hc(:g, B))),
            (
                [_hbr(_hc(:hb4, X), _hbc(_hc(:(=), Y, X), _hc(:(=), Y, _hs(:a))))],
                _hc(:hb4, A)
            ),
            (
                [_hbr(_hc(:hb4b, X), _hbc(_hc(:(=), Y, X), _hc(:(=), Y, _hs(:a))))],
                _hc(:hb4b, _hs(:b))
            ),
            (
                [_hbr(_hc(:hb5, W), _hbc(_hc(:(=), X, _hs(:a)), _hc(:(==), X, _hs(:a))))],
                _hc(:hb5, A)
            ),
            ([_hbr(_hc(:hb6, X), _hc(Symbol("\\=="), X, _hs(:a)))], _hc(:hb6, A)),
            ([_hbr(_hc(:hb6b, X), _hc(Symbol("\\=="), X, _hs(:a)))], _hc(:hb6b, _hs(:a))),
            # I_TRUE, I_FAIL; a void side; ==/\\== on two variables
            ([_hbr(_hc(:hb7, W), _hbc(_hs(Symbol("true")), _hs(:fail)))], _hc(:hb7, A)),
            ([_hbr(_hc(:hb8, X), _hc(:(=), Z, X))], _hc(:hb8, A)),
            ([_hbr(_hc(:hb10, X, Y), _hc(:(==), X, Y))], _hc(:hb10, A, A)),
            ([_hbr(_hc(:hb10b, X, Y), _hc(:(==), X, Y))], _hc(:hb10b, A, B)),
            ([_hbr(_hc(:hb10c, X, Y), _hc(Symbol("\\=="), X, Y))], _hc(:hb10c, A, B)),
            # FF, then VF and VC through the shared variable; X = Y with Y first (VF); C_VAR (==, first)
            (
                [
                    _hbr(
                        _hc(:hb11, X),
                        _hbc(_hc(:(=), Y, Z), _hc(:(=), Y, X), _hc(:(=), Z, _hs(:c)))
                    )
                ],
                _hc(:hb11, A)),
            ([_hbr(_hc(:hb12, X), _hbc(_hc(:(=), X, Y), _hc(:(==), Y, X)))], _hc(:hb12, A)),
            ([_hbr(_hc(:hb13, X), _hbc(_hc(:(==), X, Y), _hc(:(=), Y, X)))], _hc(:hb13, A)),
            # a cyclic list; two terms cyclic through each other; Term = Term (a call of =/2)
            ([_hbr(_hc(:hb14, X), _hc(:(=), X, _hlist(_hs(:a), X)))], _hc(:hb14, A)),
            (
                [
                    _hbr(
                        _hc(:hb15, X, Y),
                        _hbc(_hc(:(=), X, _hc(:g, Y)), _hc(:(=), Y, _hc(:h, X)))
                    )
                ],
                _hc(:hb15, A, B)),
            ([_hbr(_hc(:hb16, X), _hc(:(=), _hc(:f, X), _hc(:f, _hs(:a))))], _hc(:hb16, A)),
            # the cyclic term compared with itself, and with another cyclic term equal to it (3a)
            (
                [
                    _hbr(_hc(:hb9c, X), _hbc(_hc(:(=), Y, _hc(:f, Y)), _hc(:(=), X, Y))),
                    _hbr(
                        _hc(:hb9, O),
                        _hbc(_hc(:hb9c, Y), _hc(:(==), Y, Y), _hc(:compare, O, Y, Y))
                    )
                ], _hc(:hb9, A)),
            (
                [
                    _hbr(_hc(:hb9d, X), _hbc(_hc(:(=), Y, _hc(:f, Y)), _hc(:(=), X, Y))),
                    _hbr(_hc(:hb9b, O),
                        _hbc(
                            _hc(:hb9d, Y),
                            _hc(:hb9d, Z),
                            _hc(:(==), Y, Z),
                            _hc(:compare, O, Y, Z)
                        ))
                ], _hc(:hb9b, A))
        ]
    end
const _HB_FAMILY = (
    LK.B_UNIFY_FIRSTVAR, LK.B_UNIFY_VAR, LK.B_UNIFY_EXIT, LK.B_UNIFY_FF, LK.B_UNIFY_VF,
    LK.B_UNIFY_FV, LK.B_UNIFY_VV, LK.B_UNIFY_FC, LK.B_UNIFY_VC, LK.B_EQ_VV, LK.B_EQ_VC,
    LK.B_NEQ_VV, LK.B_NEQ_VC, LK.C_VAR, LK.I_FAIL, LK.I_TRUE
)

"The kernel's outcomes of `_HB_CASES` in every mode, compiled under `optimise_unify` `ou`, and the instructions compiled."
function _hb_ours(ou::Bool)
    db = IxDB{_HT}()
    db.ld.prolog_flag_optimise_unify = ou
    preds = IxPred{_HT}[]
    ran = Set{UInt64}()
    for (clauses, goal) in _HB_CASES
        for c in clauses
            h, b = child(c, 2), child(c, 3)
            p = ix_pred(_HT, lk_name(child(h, 1)), nchildren(h) - 1; db=db)
            cl = LK.compileClause(db.gd, db.ld, h, b, p.proc, LK.MODULE_user(db.gd))
            LK.assertDefinition!(db.gd, p.def, cl, LK.CL_END)
            union!(ran, _hinstructions(cl))
        end
        push!(preds, ix_pred(_HT, lk_name(child(goal, 1)), nchildren(goal) - 1; db=db))
    end
    ours = Dict{Tuple{Int, String}, String}()
    for (mode, m) in _HMODES, i in eachindex(_HB_CASES)
        ours[(i, m)] = _hvm(preds[i], _HB_CASES[i][2], mode)
    end
    return ours, ran
end

@testset "body unification through the VM vs swipl, in every occurs_check mode (V9a, V9b)" begin
    ours, ran = _hb_ours(true)
    oursf, ranf = _hb_ours(false)
    missing = [LK.codeTable(c).name for c in _HB_FAMILY if !(c in ranf)]
    isempty(missing) || println(stderr, "  not compiled: ", missing)
    @test isempty(missing)                                  # without moves, every instruction
    @test LK.B_UNIFY_VAR in ranf && !(LK.B_UNIFY_VAR in ran)   # hb2's X = f(X) moves (V9b)
    named(n) = findfirst(c -> lk_name(child(c[2], 1)) === n, _HB_CASES)
    @testset "pinned (3a): X = f(X), X first, in each mode; the cycle compared with itself" begin
        @test ours[(named(:hb1), "false")] == "ok 1 cyclic"
        @test ours[(named(:hb1), "true")] == "ok 0"
        @test startswith(ours[(named(:hb1), "error")], "err error(occurs_check(")
        @test endswith(ours[(named(:hb1), "error")], "context(:(system,/(=,2)),_))")
        @test ours[(named(:hb9), "false")] == "ok 1 hb9(=)"
        @test ours[(named(:hb9b), "false")] == "ok 1 hb9b(=)"
        @test ours[(named(:hb2), "false")] == "ok 1 cyclic"
        @test ours[(named(:hb2), "true")] == "ok 0"
        # hb2's X = f(X) is MOVED into the head (V9b): its error is the head's, naming the
        # clause's predicate; under the flag false it is the body's, naming =/2 — as swipl's
        @test endswith(ours[(named(:hb2), "error")], "context(/(hb2,1),_))")
        @test endswith(oursf[(named(:hb2), "error")], "context(:(system,/(=,2)),_))")
    end
    if _HSWIPL !== nothing
        @testset "identical to swipl, the flag on and off" begin
            for (o, prelude) in (
                (ours, ""), (oursf, ":- set_prolog_flag(optimise_unify, false).\n")
            )
                theirs, _ = _hswipl(_HB_CASES; prelude=prelude)
                bad = [
                    (i, m) for i in eachindex(_HB_CASES) for (_, m) in _HMODES if
                    o[(i, m)] != theirs[(i, m)]
                ]
                for (i, m) in bad[1:min(end, 6)]
                    println(stderr, "  case $i ($m) ", repr(prelude), ": ",
                        join(_hsrc.(_HB_CASES[i][1]), ". "), " ?- ", _hsrc(_HB_CASES[i][2]),
                        "\n    ours  ", o[(i, m)], "\n    swipl ", theirs[(i, m)])
                end
                @test isempty(bad)
                @test length(theirs) == 3 * length(_HB_CASES)
            end
        end
    elseif _HSWIPL_REQUIRED
        error(
            "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the body differential would be skipped"
        )
    end
end
