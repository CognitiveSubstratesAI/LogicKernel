# ORIGINAL: a LIVE differential of the kernel's unification (pl_unify!) against swipl's =/2 under all three occurs_check modes; upstream has no such test.
# test/core_lang/test_unify_swipl.jl — `=/2` against a LIVE swipl, on random pairs, in every mode.
#
# For every pair `A = B` and every `occurs_check` mode (false, true, error) swipl and the kernel
# must give the same OUTCOME: `fail`, `error` (an occurs-check error), `cyclic` (it unified into a
# rational tree — legal when the flag is false), or `ok(A, vs(V1,…,V6))`: the unified left-hand
# term AND the resolved value of every variable of the pair, printed together as `write_canonical/1`
# prints them (repeated variables `A, B, …` by first occurrence, singletons `_`). So the differential
# checks success, failure and errors, and the BINDINGS, up to renaming: what each variable became,
# and which variables became each other.
#
# The pairs are built to be HARD, from one small pool of variables shared by both sides: an
# instance of the first term (its variables bound to small terms, which may contain those variables
# — the source of cycles), a generalisation (subterms replaced by variables), an instance with one
# atomic value changed to a near twin (`1`/`1.0`, `0.0`/`-0.0`, atom `s`/string `"s"`, `a`/`b`, two
# big integers — and `big(1)`/`1`, which are identical and must still unify), CHAINS of variables
# bound to variables, DEEP terms (30–120 levels), a variable bound to a term around itself, and
# independent terms. The atomic values include NaN and big integers.
#
# swipl present ⇒ the differential runs. Absent: an ERROR when LOGICKERNEL_REQUIRE_SWIPL=1 (set by
# tools/run_tests.sh and CI's analysis job), otherwise a LOUD note plus an assertion that it was not
# required — never a silent pass.
using Test, LogicKernel, Random
using LogicKernel:
    PL_local_data,
    pl_unify!,
    Mark,
    Undo!,
    resolve_term,
    OccursCheckError,
    OCCURS_CHECK_FALSE,
    OCCURS_CHECK_TRUE,
    OCCURS_CHECK_ERROR

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _ZT = lk_term_type(Union{Int64, BigInt, Float64, String})
const _ZPOOL = 4                                            # variables V1…V4 shared by both sides
const _ZALL = 6                                             # V5, V6: fresh in some pairs
const _ZBIG = big(2)^70                                     # an integer past Int64
# What the comparison signatures must have met among the rational trees (V5a), about half of a
# measured run (2026-10-05; the testsets' @info lines): the pairs' pool — 9 identical, 3566 variant
# but not identical, 10 ordered; the ground rational trees — 39 identical, 2309 `<`, 2152 `>`.
const _ZCMP_EQ_MIN = 5
const _ZCMP_VAR_MIN = 1500
const _ZCMP_ORD_MIN = 5
const _ZRT_EQ_MIN = 20
const _ZRT_ORD_MIN = 1000
_zs(x::Symbol) = lk_sym(_ZT, x)
_zc(f::Symbol, xs::_ZT...) = mk_expr(_ZT, _ZT[_zs(f), xs...])
_zv(k::Int) = mk_var(_ZT, UInt64(k))

"A random atomic term: atoms, small and big integers, floats with NaN and the signed zeros, a string."
function _zatom(rng)::_ZT
    k = rand(rng, 1:7)
    k == 1 && return _zs(rand(rng, (:a, :b, :s)))
    k == 6 && return rand(rng, (mk_nil(_ZT), _zs(Symbol("[]"))))   # SWI-7's [] vs the atom '[]'
    k == 2 && return lk_gnd(_ZT, rand(rng, (0, 1)))
    k == 3 && return lk_gnd(_ZT, rand(rng, (big(1), _ZBIG)))
    k == 4 && return lk_gnd(_ZT, rand(rng, (0.0, -0.0, 1.0)))
    k == 5 && return lk_gnd(_ZT, NaN)
    return lk_gnd(_ZT, "s")
end

"A random term of depth ≤ `d` over variables `vars`."
function _zrand(rng, d::Int, vars)::_ZT
    r = rand(rng, 1:10)
    if d == 0 || r <= 4
        return rand(rng, 1:3) == 1 ? _zatom(rng) : _zv(rand(rng, vars))
    end
    f, n = rand(rng, ((:f, 1), (:f, 2), (:g, 2)))
    return mk_expr(_ZT, _ZT[_zs(f); [_zrand(rng, d - 1, vars) for _ in 1:n]])
end

"`t` with each variable `k` in `m` replaced by `m[k]`."
function _zsubst(t::_ZT, m::Dict{UInt64, _ZT})::_ZT
    kind(t) === VAR && return get(m, var_key(t), t)
    kind(t) === EXPR || return t
    return mk_expr(_ZT, _ZT[_zsubst(child(t, i), m) for i in 1:nchildren(t)])
end

"`t` with each subterm replaced, with probability `p`, by a variable of `vars`."
function _zgeneralise(rng, t::_ZT, p::Float64, vars)::_ZT
    rand(rng) < p && return _zv(rand(rng, vars))
    kind(t) === EXPR || return t
    return mk_expr(
        _ZT,
        _ZT[child(t, 1); [_zgeneralise(rng, child(t, i), p, vars) for i in 2:nchildren(t)]]
    )
end

"The near twin of atomic `t` — another kind or representation of a like value — or `nothing`."
function _ztwin(t::_ZT)::Union{Nothing, _ZT}
    if kind(t) === SYM
        is_nil(t) && return _zs(Symbol("[]"))             # [] vs the atom '[]': they never unify
        n = lk_name(t)
        n === Symbol("[]") && return mk_nil(_ZT)
        n === :s && return lk_gnd(_ZT, "s")               # atom s vs string "s"
        n in (:a, :b) && return _zs(n === :a ? :b : :a)
        return nothing
    end
    v = lk_value(t)
    w = if v isa String
        return _zs(:s)
    elseif v isa Int64
        rand((Float64(v), big(v)))                      # 1 vs 1.0 (apart), 1 vs big(1) (identical)
    elseif v isa BigInt
        v == 1 ? 1 : v + 1
    elseif v === 0.0
        -0.0
    elseif v === -0.0
        0.0
    elseif v === 1.0
        1
    else
        nothing
    end
    return w === nothing ? nothing : lk_gnd(_ZT, w)
end

"`t` with its first atomic value that has a near twin replaced by the twin; `done` if it did."
function _zperturb(t::_ZT, done::Base.RefValue{Bool})::_ZT
    done[] && return t
    if kind(t) === SYM || kind(t) === GND
        w = _ztwin(t)
        w === nothing && return t
        done[] = true
        return w
    end
    kind(t) === EXPR || return t
    return mk_expr(_ZT, _ZT[_zperturb(child(t, i), done) for i in 1:nchildren(t)])
end

"`(pairs, kinds)`: `n` random pairs and how each was built."
function _zpairs(rng, n::Int)
    pairs = Tuple{_ZT, _ZT}[]
    kinds = Symbol[]
    pool = 1:_ZPOOL
    for _ in 1:n
        a = _zrand(rng, 3, pool)
        how = rand(
            rng,
            (
                :instance, :instance, :generalise, :perturbed, :chain, :deep, :self,
                :independent
            )
        )
        if how === :chain                           # f(X1,…,Xn) = f(X2,…,Xn,last): Xi = Xi+1 = …
            n = rand(rng, 3:5)
            xs = [_zv(rand(rng, 1:_ZALL)) for _ in 1:n]
            last = rand(rng, Bool) ? _zatom(rng) : _zv(rand(rng, 1:_ZALL))
            push!(
                pairs,
                (
                    mk_expr(_ZT, _ZT[_zs(:f); xs]),
                    mk_expr(_ZT, _ZT[_zs(:f); xs[2:end]; last])
                )
            )
            push!(kinds, how)
            continue
        elseif how === :deep                        # s^D(X) = s^D'(Y): deep, equal or off by one
            d = rand(rng, 30:120)
            d2 = d + rand(rng, (0, 0, 1, -1))
            l = foldl((t, _) -> _zc(:s, t), 1:d; init=_zv(rand(rng, pool)))
            r = foldl(
                (t, _) -> _zc(:s, t),
                1:d2;
                init=rand(rng, Bool) ? _zatom(rng) : _zv(rand(rng, 1:_ZALL))
            )
            push!(pairs, (l, r))
            push!(kinds, how)
            continue
        end
        b = if how === :instance || how === :perturbed
            m = Dict{UInt64, _ZT}(
                UInt64(k) => _zrand(rng, 1, pool) for k in pool if rand(rng) < 0.6
            )
            inst = _zsubst(a, m)
            how === :perturbed ? _zperturb(inst, Ref(false)) : inst
        elseif how === :generalise
            _zgeneralise(rng, a, 0.3, 1:_ZALL)
        elseif how === :self                        # V = f(…V…): a cycle unless checked
            k = rand(rng, pool)
            push!(pairs, (_zv(k), _zc(:f, _zrand(rng, 1, pool), _zv(k))))
            push!(kinds, how)
            continue
        else
            _zrand(rng, 3, 1:_ZALL)
        end
        push!(pairs, (a, b))
        push!(kinds, how)
    end
    return pairs, kinds
end

"Prolog source of `t`; variable `k` is `V<k>`."
function _zsrc(t::_ZT)::String
    k = kind(t)
    k === VAR && return "V$(var_key(t))"
    k === SYM && return lk_atom_text(t)                 # `[]` bare, the text atom '[]' quoted
    if k === GND
        v = lk_value(t)
        v isa String && return "\"$v\""
        v isa Float64 && isnan(v) && return "1.5NaN"        # SWI's quiet NaN (Julia's `NaN`)
        return string(v)
    end
    return _zsrc(child(t, 1)) * "(" *
           join((_zsrc(child(t, i)) for i in 2:nchildren(t)), ",") *
           ")"
end

"`write_canonical/1` of `t`: repeated variables `A, B, …` by first occurrence, singletons `_`."
function _zcanonical(t::_ZT)::String
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
    function wc(u)::String
        kind(u) === VAR && return get(names, var_key(u), "_")
        kind(u) === EXPR || return _zsrc(u)
        return wc(child(u, 1)) * "(" *
               join((wc(child(u, i)) for i in 2:nchildren(u)), ",") * ")"
    end
    return wc(t)
end

const _ZMODES = ((OCCURS_CHECK_FALSE, "false"), (OCCURS_CHECK_TRUE, "true"),
    (OCCURS_CHECK_ERROR, "error"))

"Whether `t` is ground under the bindings in `ld` — cycle-safe (a compound is visited once)."
function _zground(ld, t::_ZT)::Bool
    seen = IdDict{_ZT, Nothing}()
    todo = _ZT[t]
    while !isempty(todo)
        u = LogicKernel.deRef(ld, pop!(todo))
        kind(u) === VAR && return false
        kind(u) === EXPR || continue
        haskey(seen, u) && continue
        seen[u] = nothing
        append!(todo, (child(u, i) for i in 1:nchildren(u)))
    end
    return true
end

"""
The comparison signature of the pool after a unification, under its bindings (V5a: the standard
order and `=@=` UNDER BINDINGS, rational trees included): for each pair `Vi`, `Vj` (i < j) three
characters — `==` (`e`/`n`), `=@=` (`v`/`n`), and `compare/3`'s order when both are ground, else
`?` (swipl orders variables by address).
"""
function _zcmpsig(ld)::String
    io = IOBuffer()
    for i in 1:_ZALL, j in (i + 1):_ZALL
        x, y = _zv(i), _zv(j)
        print(io, LogicKernel.compareStandard(ld, x, y, true) == 0 ? 'e' : 'n')
        print(io, LogicKernel.is_variant_ptr(ld, x, y) ? 'v' : 'n')
        if _zground(ld, x) && _zground(ld, y)
            print(io, ("<", "=", ">")[LogicKernel.compareStandard(ld, x, y, false) + 2])
        else
            print(io, '?')
        end
    end
    return "cmp(" * String(take!(io)) * ")"
end

"""
The kernel's outcome of `a = b` in `mode`: `fail`, `error`, `cyclic` or `ok(A, vs(…))` — the last
two followed by the pool's comparison signature (`_zcmpsig`); undone after.
"""
function _zkernel(ld, a::_ZT, b::_ZT, mode)::String
    ld.prolog_flag_occurs_check = mode
    m = Mark(ld)
    try
        pl_unify!(ld, a, b) || return "fail"
        sig = _zcmpsig(ld)
        return try
            vs = mk_expr(_ZT, _ZT[_zs(:vs); [resolve_term(ld, _zv(k)) for k in 1:_ZALL]])
            _zcanonical(_zc(:ok, resolve_term(ld, a), vs)) * " " * sig
        catch e
            e isa ArgumentError || rethrow()
            "cyclic " * sig
        end
    catch e
        e isa OccursCheckError || rethrow()
        return "error"
    finally
        Undo!(ld, m)
    end
end

"""
swipl's outcome of `A = B` for each pair, in each mode: `(outcomes, aborts)`, the outcomes a Dict
`(i, mode) => outcome`.

swipl 10.1.16 ABORTS (SIGABRT, "Cannot report error: no memory" in `PL_error` under
`unify_with_occurs_check`) on this workload in `error` mode, deterministically but depending on what
else the process has loaded and run — measured 2026-10-03; reproducers in the workspace at
docs/tracking/repros/swipl_occurs_check_error_abort/; tracked as LogicKernel#3, docs/upstream_reports.md
(upstream report: pending — when it is fixed, return to one process per mode). So swipl runs in
CHUNKS of pairs, one process each; a chunk that aborts is re-run ONE PAIR PER PROCESS, and every
abort recovered that way is counted and reported (`aborts`), never silently absorbed.
"""
function _zswipl(pairs)
    res = Dict{Tuple{Int, String}, String}()
    aborts = 0
    for (_, mode) in _ZMODES, chunk in Iterators.partition(eachindex(pairs), 100)
        if !_zswipl_run!(res, pairs, collect(chunk), mode)
            aborts += 1
            for i in chunk
                _zswipl_run!(res, pairs, [i], mode) ||
                    error("swipl aborts on pair $i alone in mode $mode")
            end
        end
    end
    length(res) == 3 * length(pairs) ||
        error("swipl answered $(length(res)) of $(3 * length(pairs)) pair×mode cases")
    return res, aborts
end

"""
swipl's outcome of `A = B` for the pairs `idx` with the `occurs_check` flag `mode`, into `res`;
`false` if the swipl process died by a signal (the abort above).
"""
function _zswipl_run!(
    res::Dict{Tuple{Int, String}, String}, pairs, idx::Vector{Int}, mode::String
)::Bool
    prog = IOBuffer()
    println(prog, ":- style_check(-singleton).")
    println(prog, ":- set_prolog_flag(double_quotes, string).")
    vs = "vs(" * join(("V$k" for k in 1:_ZALL), ",") * ")"
    for i in idx
        a, b = pairs[i]
        println(prog, "p($i, $(_zsrc(a)), $(_zsrc(b)), $vs).")
    end
    print(
        prog,
        """
        pc(X, Y, C) :-
            ( X == Y -> E = e ; E = n ), ( X =@= Y -> V = v ; V = n ),
            ( ground(X), ground(Y) -> compare(O, X, Y) ; O = '?' ),
            atomic_list_concat([E, V, O], C).
        cmpsig(Vs, S) :-
            Vs =.. [_|L],
            findall(C, ( nth1(I, L, X), nth1(J, L, Y), I < J, pc(X, Y, C) ), Cs),
            atomic_list_concat(Cs, S0), atomic_list_concat(['cmp(', S0, ')'], S).
        run(Mode) :-
            forall(p(I, A, B, Vs),
                   ( set_prolog_flag(occurs_check, Mode),
                     catch(( A = B -> cmpsig(Vs, S),
                                      ( cyclic_term(A) -> R = cyclic ; R = ok(A, Vs) ) ; R = fail ),
                           error(occurs_check(_, _), _), R = error),
                     set_prolog_flag(occurs_check, false),
                     format("~d ~w ", [I, Mode]), write_canonical(R),
                     ( R == fail -> true ; R == error -> true ; format(" ~w", [S]) ), nl )).
        :- initialization((run($mode), halt)).
        """
    )
    out = IOBuffer()
    proc = mktempdir() do d
        f = joinpath(d, "unify.pl")
        write(f, String(take!(prog)))
        run(pipeline(ignorestatus(`swipl -q $f`); stdout=out, stderr=devnull))
    end
    proc.termsignal != 0 && return false
    success(proc) || error("swipl failed (exit $(proc.exitcode)) on pairs $(first(idx))…")
    n = 0
    for l in eachline(IOBuffer(take!(out)))
        i, m, r = split(l, ' '; limit=3)
        res[(parse(Int, i), String(m))] = String(r)
        n += 1
    end
    n == length(idx) || error("swipl answered $n of $(length(idx)) in mode $mode")
    return true
end

# ── GROUND RATIONAL TREES (V5a): `==`, `=@=` and `compare/3` under bindings, where the order of
# cyclic terms needs upstream's `compare_descend` ────────────────────────────────────────────────
# Each case binds V1, V2, V3, in turn, to a random COMPOUND over those three variables and a few
# atoms — so every variable ends up ground, most of them cyclic — and compares the three pairs.

"A random compound of depth ≤ `d` over V1…V`nv` and a few atoms (every leaf position may be a variable)."
function _zrt(rng, d::Int, nv::Int=3)::_ZT
    f = rand(rng, ((:f, 1), (:f, 2), (:g, 2), (:h, 3)))
    kids = _ZT[]
    for _ in 1:f[2]
        r = rand(rng)
        push!(
            kids,
            if d > 1 && r < 0.35
                _zrt(rng, d - 1, nv)
            elseif r < 0.75
                _zv(rand(rng, 1:nv))
            else
                rand(rng, (_zs(:a), _zs(:b), lk_gnd(_ZT, 1)))
            end
        )
    end
    return _zc(f[1], kids...)
end

"The kernel's signatures for the cases: the three pairs of V1…V3 after binding them, undone after."
function _zrt_kernel(ld, cases)::Vector{String}
    out = String[]
    for c in cases
        m = Mark(ld)
        for k in 1:3
            pl_unify!(ld, _zv(k), c[k]) || error("_zrt_kernel: V$k = … failed")
        end
        io = IOBuffer()
        for (i, j) in ((1, 2), (1, 3), (2, 3))
            x, y = _zv(i), _zv(j)
            print(io, LogicKernel.compareStandard(ld, x, y, true) == 0 ? 'e' : 'n')
            print(io, LogicKernel.is_variant_ptr(ld, x, y) ? 'v' : 'n')
            print(io, ("<", "=", ">")[LogicKernel.compareStandard(ld, x, y, false) + 2])
        end
        push!(out, String(take!(io)))
        Undo!(ld, m)
    end
    return out
end

"swipl's signatures for the cases (the same three pairs, `occurs_check=false`)."
function _zrt_swipl(cases)::Vector{String}
    prog = IOBuffer()
    println(prog, ":- style_check(-singleton).")
    for (i, c) in enumerate(cases)
        println(prog, "r($i, V1, V2, V3, $(_zsrc(c[1])), $(_zsrc(c[2])), $(_zsrc(c[3]))).")
    end
    print(
        prog,
        """
        pc(X, Y, C) :-
            ( X == Y -> E = e ; E = n ), ( X =@= Y -> V = v ; V = n ), compare(O, X, Y),
            atomic_list_concat([E, V, O], C).
        run :-
            forall(r(I, V1, V2, V3, T1, T2, T3),
                   ( V1 = T1, V2 = T2, V3 = T3,
                     pc(V1, V2, A), pc(V1, V3, B), pc(V2, V3, C),
                     format("~d ~w~w~w~n", [I, A, B, C]) )).
        :- initialization((run, halt)).
        """
    )
    text = mktempdir() do d
        f = joinpath(d, "rt.pl")
        write(f, String(take!(prog)))
        read(`swipl -q $f`, String)
    end
    res = fill("", length(cases))
    for l in eachline(IOBuffer(text))
        i, sig = split(l, ' '; limit=2)
        res[parse(Int, i)] = sig
    end
    any(isempty, res) &&
        error("swipl answered $(count(!isempty, res)) of $(length(cases)) cases")
    return res
end

"""
Families V1…Vn (n in 2:4) bound to random compounds over themselves, and a pair `(i, j)` in each
where the FAST walk's order is wrong: it followed a cyclic link and the sound descent decides the
other way (`compare_std` must then take `compare_descend`'s answer, as swipl does). Rare — about one
family in 1300 — so they are searched for: `want` of them, from at most `cap` families.
"""
function _zdescend_cases(rng, want::Int, cap::Int)
    ld = PL_local_data{_ZT}()
    cases = Tuple{Vector{_ZT}, Int, Int}[]
    tries = 0
    while length(cases) < want && tries < cap
        tries += 1
        nv = rand(rng, 2:4)
        ts = [_zrt(rng, 3, nv) for _ in 1:nv]
        m = Mark(ld)
        for k in 1:nv
            pl_unify!(ld, _zv(k), ts[k])
        end
        for i in 1:nv, j in (i + 1):nv
            rc, linked = LogicKernel.compare_fast(
                ld, _zv(i), _zv(j), LogicKernel.CMP_MODE_ORDER
            )
            (linked && rc != 0) || continue
            rc2, _, _ = LogicKernel.compare_descend(
                ld, _zv(i), _zv(j), LogicKernel.CMP_MODE_ORDER
            )
            if rc2 != LogicKernel.CMP_INCOMPARABLE && rc2 != rc
                push!(cases, (ts, i, j))
                break
            end
        end
        Undo!(ld, m)
    end
    return cases, tries
end

"The kernel's `compare/3` order (`<`, `=`, `>`) of each case's pair, through `compareStandard`."
function _zdescend_kernel(cases)::Vector{Char}
    ld = PL_local_data{_ZT}()
    out = Char[]
    for (ts, i, j) in cases
        m = Mark(ld)
        for k in eachindex(ts)
            pl_unify!(ld, _zv(k), ts[k])
        end
        push!(out, "<=>"[LogicKernel.compareStandard(ld, _zv(i), _zv(j), false) + 2])
        Undo!(ld, m)
    end
    return out
end

"swipl's `compare/3` order of each case's pair."
function _zdescend_swipl(cases)::Vector{Char}
    prog = IOBuffer()
    println(prog, ":- style_check(-singleton).")
    for (n, (ts, i, j)) in enumerate(cases)
        eqs = join(("V$k = $(_zsrc(t))" for (k, t) in enumerate(ts)), ", ")
        println(prog, "d($n) :- $eqs, compare(O, V$i, V$j), format(\"~d ~w~n\", [$n, O]).")
    end
    println(
        prog, ":- initialization((forall(between(1, $(length(cases)), N), d(N)), halt))."
    )
    text = mktempdir() do d
        f = joinpath(d, "descend.pl")
        write(f, String(take!(prog)))
        read(`swipl -q $f`, String)
    end
    res = fill(' ', length(cases))
    for l in eachline(IOBuffer(text))
        n, o = split(l, ' ')
        res[parse(Int, n)] = o[1]
    end
    any(==(' '), res) &&
        error("swipl answered $(count(!=(' '), res)) of $(length(cases)) cases")
    return res
end

const _ZSWIPL = Sys.which("swipl")
const _ZSWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

if _ZSWIPL !== nothing
    @testset "=/2 == live swipl =/2 in every occurs_check mode" begin
        pairs, kinds = _zpairs(Xoshiro(20261003), 2000)
        theirs, aborts = _zswipl(pairs)
        aborts > 0 &&
            @warn "swipl ABORTED in $aborts chunk(s) (its occurs-check error path; see _zswipl); those pairs were re-run one per process"
        ld = PL_local_data{_ZT}()
        bad = String[]
        tally = Dict{Tuple{String, String}, Int}()
        cmpt = Dict(:cyclic_eq => 0, :cyclic_variant_not_eq => 0, :cyclic_ordered => 0)
        for (i, (a, b)) in enumerate(pairs), (mode, name) in _ZMODES
            ours = _zkernel(ld, a, b, mode)
            sw = theirs[(i, name)]
            head = first(split(ours, ' '))
            key = (
                name, head == "fail" || head == "error" || head == "cyclic" ? head : "ok"
            )
            tally[key] = get(tally, key, 0) + 1
            m = match(r"cmp\(([^)]*)\)$", ours)
            if m !== nothing && head == "cyclic"
                sig = m[1]
                for k in 1:3:length(sig)
                    sig[k] == 'e' && (cmpt[:cyclic_eq] += 1)
                    sig[k] == 'n' && sig[k + 1] == 'v' &&
                        (cmpt[:cyclic_variant_not_eq] += 1)
                    sig[k + 2] in "<>" && (cmpt[:cyclic_ordered] += 1)
                end
            end
            ours == sw ||
                push!(bad, "[$name] $(_zsrc(a)) = $(_zsrc(b)): swipl $sw, kernel $ours")
        end
        foreach(b -> println(stderr, "  DIVERGES: ", b), first(bad, 20))
        @test isempty(bad)
        @test isempty(ld.trail) && isempty(ld.bindings)     # every attempt undone
        # the data exercised every outcome the modes can give
        @test get(tally, ("false", "ok"), 0) >= 300 &&
            get(tally, ("false", "fail"), 0) >= 150
        @test get(tally, ("false", "cyclic"), 0) >= 100     # rational trees, made and kept
        @test get(tally, ("true", "cyclic"), 0) == 0        # the occurs check prevents them
        @test get(tally, ("error", "error"), 0) >= 100
        # the comparisons UNDER BINDINGS met rational trees: equal, variant but not equal, ordered
        @test cmpt[:cyclic_eq] >= _ZCMP_EQ_MIN &&
            cmpt[:cyclic_variant_not_eq] >= _ZCMP_VAR_MIN &&
            cmpt[:cyclic_ordered] >= _ZCMP_ORD_MIN
        for k in (:perturbed, :chain, :deep, :generalise, :self)
            @test count(==(k), kinds) >= 150
        end
        src = [_zsrc(a) * " = " * _zsrc(b) for (a, b) in pairs]
        @test count(s -> occursin("1.5NaN", s), src) >= 100           # NaN
        @test count(s -> occursin(string(_ZBIG), s), src) >= 100      # big integers
        @test count(s -> occursin("\"s\"", s) && occursin(r"\bs\b(?!\")", s), src) >= 20   # s and "s"
        @test count(s -> occursin("-0.0", s), src) >= 50
        @info "=/2 agrees with $(strip(read(`swipl --version`, String))) on $(length(pairs)) pairs × 3 modes: $(sort(collect(tally))); comparisons on rational trees: $(cmpt)"
    end
    @testset "ground rational trees: ==, =@= and compare/3 under bindings == live swipl" begin
        rng = Xoshiro(20261005)
        cases = [(_zrt(rng, 3), _zrt(rng, 3), _zrt(rng, 3)) for _ in 1:1500]
        ld = PL_local_data{_ZT}()
        ours = _zrt_kernel(ld, cases)
        theirs = _zrt_swipl(cases)
        bad = [
            "V1 = $(_zsrc(c[1])), V2 = $(_zsrc(c[2])), V3 = $(_zsrc(c[3])): swipl $t, kernel $o"
            for (c, o, t) in zip(cases, ours, theirs) if o != t
        ]
        foreach(b -> println(stderr, "  DIVERGES: ", b), first(bad, 20))
        @test isempty(bad)
        @test isempty(ld.trail) && isempty(ld.bindings)
        # the data reached each answer: identical, and both orders (ground: `=@=` is `==`)
        sigs = join(ours)
        n_eq = count(k -> sigs[k] == 'e', 1:3:length(sigs))
        n_lt = count(==('<'), sigs)
        n_gt = count(==('>'), sigs)
        @info "ground rational trees: $(length(cases)) cases; == $n_eq, < $n_lt, > $n_gt"
        @test n_eq >= _ZRT_EQ_MIN && n_lt >= _ZRT_ORD_MIN && n_gt >= _ZRT_ORD_MIN
    end
    @testset "compare/3 where the fast walk's order is wrong: compare_descend's == live swipl" begin
        cases, tries = _zdescend_cases(Xoshiro(20261006), 25, 100_000)
        @info "compare_descend cases: $(length(cases)) found in $tries families"
        @test length(cases) == 25                   # the data reaches the descent, 25 times
        ours = _zdescend_kernel(cases)
        theirs = _zdescend_swipl(cases)
        for (c, o, t) in zip(cases, ours, theirs)
            o == t || println(
                stderr, "  DIVERGES: ",
                join(("V$k = $(_zsrc(x))" for (k, x) in enumerate(c[1])), ", "),
                ", compare(O, V$(c[2]), V$(c[3])): swipl $t, kernel $o"
            )
        end
        @test ours == theirs
    end
elseif _ZSWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the =/2 differential would be skipped"
    )
else
    @info "=/2 DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "=/2 differential skipped only where it is not required" begin
        @test !_ZSWIPL_REQUIRED
    end
end
