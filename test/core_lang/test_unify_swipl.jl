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

"The kernel's outcome of `a = b` in `mode`: `fail`, `error`, `cyclic` or `ok(A, vs(…))`; undone after."
function _zkernel(ld, a::_ZT, b::_ZT, mode)::String
    ld.prolog_flag_occurs_check = mode
    m = Mark(ld)
    try
        pl_unify!(ld, a, b) || return "fail"
        return try
            vs = mk_expr(_ZT, _ZT[_zs(:vs); [resolve_term(ld, _zv(k)) for k in 1:_ZALL]])
            _zcanonical(_zc(:ok, resolve_term(ld, a), vs))
        catch e
            e isa ArgumentError || rethrow()
            "cyclic"
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
        run(Mode) :-
            forall(p(I, A, B, Vs),
                   ( set_prolog_flag(occurs_check, Mode),
                     catch(( A = B -> ( cyclic_term(A) -> R = cyclic ; R = ok(A, Vs) ) ; R = fail ),
                           error(occurs_check(_, _), _), R = error),
                     set_prolog_flag(occurs_check, false),
                     format("~d ~w ", [I, Mode]), write_canonical(R), nl )).
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
        for (i, (a, b)) in enumerate(pairs), (mode, name) in _ZMODES
            ours = _zkernel(ld, a, b, mode)
            sw = theirs[(i, name)]
            key = (
                name, ours == "fail" || ours == "error" || ours == "cyclic" ? ours : "ok"
            )
            tally[key] = get(tally, key, 0) + 1
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
        for k in (:perturbed, :chain, :deep, :generalise, :self)
            @test count(==(k), kinds) >= 150
        end
        src = [_zsrc(a) * " = " * _zsrc(b) for (a, b) in pairs]
        @test count(s -> occursin("1.5NaN", s), src) >= 100           # NaN
        @test count(s -> occursin(string(_ZBIG), s), src) >= 100      # big integers
        @test count(s -> occursin("\"s\"", s) && occursin(r"\bs\b(?!\")", s), src) >= 20   # s and "s"
        @test count(s -> occursin("-0.0", s), src) >= 50
        @info "=/2 agrees with $(strip(read(`swipl --version`, String))) on $(length(pairs)) pairs × 3 modes: $(sort(collect(tally)))"
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
