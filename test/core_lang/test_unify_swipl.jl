# ORIGINAL: a LIVE differential of the kernel's unification (pl_unify!) against swipl's =/2 under all three occurs_check modes; upstream has no such test.
# test/core_lang/test_unify_swipl.jl — `=/2` against a LIVE swipl, on random pairs, in every mode.
#
# For every pair `A = B` and every `occurs_check` mode (false, true, error) swipl and the kernel
# must give the same OUTCOME: `fail`, `error` (an occurs-check error), `cyclic` (it unified into a
# rational tree — legal when the flag is false), or `ok(A)` with the unified left-hand term printed
# as `write_canonical/1` prints it (repeated variables `A, B, …` by first occurrence, singletons `_`).
# So the differential checks success, failure and errors, and the BINDINGS: which variables became
# which terms, and which became each other.
#
# The pairs are built to be HARD, from one small pool of variables shared by both sides: an
# instance of the first term (its variables bound to small terms, which may contain those variables
# — the source of cycles), a generalisation (subterms replaced by variables), an instance with one
# atomic value changed (`1`/`1.0`, `0.0`/`-0.0`, `a`/`b`), a variable bound to a term around itself,
# and independent terms.
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

const _ZT = DefaultTerm
const _ZPOOL = 4                                            # variables V1…V4 shared by both sides
_zs(x::Symbol) = sym_term(_ZT, x)
_zc(f::Symbol, xs::_ZT...) = mk_expr(_ZT, _ZT[_zs(f), xs...])
_zv(k::Int) = mk_var(_ZT, UInt64(k))

"A random atomic term."
function _zatom(rng)::_ZT
    k = rand(rng, 1:4)
    k == 1 && return _zs(rand(rng, (:a, :b)))
    k == 2 && return gnd_term(_ZT, rand(rng, (0, 1)))
    k == 3 && return gnd_term(_ZT, rand(rng, (0.0, -0.0, 1.0)))
    return gnd_term(_ZT, "s")
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

"`t` with its first atomic value that has a near twin replaced by the twin; `done` if it did."
function _zperturb(t::_ZT, done::Base.RefValue{Bool})::_ZT
    done[] && return t
    if kind(t) === SYM && sym_name(t) in (:a, :b)
        done[] = true
        return _zs(sym_name(t) === :a ? :b : :a)
    elseif kind(t) === GND
        v = gnd_value(t)
        w = if v isa Int64
            Float64(v)
        elseif v === 0.0
            -0.0
        elseif v === -0.0
            0.0
        elseif v === 1.0
            1
        else
            nothing
        end
        w === nothing && return t
        done[] = true
        return gnd_term(_ZT, w)
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
            rng, (:instance, :instance, :generalise, :perturbed, :self, :independent)
        )
        b = if how === :instance || how === :perturbed
            m = Dict(UInt64(k) => _zrand(rng, 1, pool) for k in pool if rand(rng) < 0.6)
            inst = _zsubst(a, m)
            how === :perturbed ? _zperturb(inst, Ref(false)) : inst
        elseif how === :generalise
            _zgeneralise(rng, a, 0.3, 1:(_ZPOOL + 2))
        elseif how === :self                        # V = f(…V…): a cycle unless checked
            k = rand(rng, pool)
            push!(pairs, (_zv(k), _zc(:f, _zrand(rng, 1, pool), _zv(k))))
            push!(kinds, how)
            continue
        else
            _zrand(rng, 3, 1:(_ZPOOL + 2))
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
    k === SYM && return string(sym_name(t))
    if k === GND
        v = gnd_value(t)
        return v isa String ? "\"$v\"" : string(v)
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

"The kernel's outcome of `a = b` in `mode`: `fail`, `error`, `cyclic` or `ok(…)`; undone after."
function _zkernel(ld, a::_ZT, b::_ZT, mode)::String
    ld.prolog_flag_occurs_check = mode
    m = Mark(ld)
    try
        pl_unify!(ld, a, b) || return "fail"
        return try
            "ok(" * _zcanonical(resolve_term(ld, a)) * ")"
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
swipl's outcome of `A = B` for each pair, in each mode: a Dict `(i, mode) => outcome`. ONE swipl
PROCESS PER MODE: swipl 10.1.16 ABORTS (SIGABRT, "Cannot report error: no memory" in `PL_error`
under `unify_with_occurs_check`) when this workload raises occurs-check errors after the other
modes' runs in the same process — measured 2026-10-03, reproducer in the workspace at
docs/tracking/repros/swipl_occurs_check_error_abort/. A fresh process per mode gives every answer.
"""
function _zswipl(pairs)::Dict{Tuple{Int, String}, String}
    res = Dict{Tuple{Int, String}, String}()
    for (_, mode) in _ZMODES
        _zswipl_mode!(res, pairs, mode)
    end
    length(res) == 3 * length(pairs) ||
        error("swipl answered $(length(res)) of $(3 * length(pairs)) pair×mode cases")
    return res
end

"swipl's outcome of `A = B` for each pair with the `occurs_check` flag `mode`, into `res`."
function _zswipl_mode!(res::Dict{Tuple{Int, String}, String}, pairs, mode::String)::Nothing
    prog = IOBuffer()
    println(prog, ":- style_check(-singleton).")
    println(prog, ":- set_prolog_flag(double_quotes, string).")
    for (i, (a, b)) in enumerate(pairs)
        println(prog, "p($i, $(_zsrc(a)), $(_zsrc(b))).")
    end
    print(
        prog,
        """
        run(Mode) :-
            forall(p(I, A, B),
                   ( set_prolog_flag(occurs_check, Mode),
                     catch(( A = B -> ( cyclic_term(A) -> R = cyclic ; R = ok(A) ) ; R = fail ),
                           error(occurs_check(_, _), _), R = error),
                     set_prolog_flag(occurs_check, false),
                     format("~d ~w ", [I, Mode]), write_canonical(R), nl )).
        :- initialization((run($mode), halt)).
        """
    )
    out = mktempdir() do d
        f = joinpath(d, "unify.pl")
        write(f, String(take!(prog)))
        read(`swipl -q $f`, String)
    end
    n = 0
    for l in eachline(IOBuffer(out))
        i, m, r = split(l, ' '; limit=3)
        res[(parse(Int, i), String(m))] = String(r)
        n += 1
    end
    n == length(pairs) ||
        error("swipl answered $n of $(length(pairs)) in mode $mode:\n$out")
    return nothing
end

const _ZSWIPL = Sys.which("swipl")
const _ZSWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

if _ZSWIPL !== nothing
    @testset "=/2 == live swipl =/2 in every occurs_check mode" begin
        pairs, kinds = _zpairs(Xoshiro(20261003), 1500)
        theirs = _zswipl(pairs)
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
        @test count(==(:perturbed), kinds) >= 150
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
