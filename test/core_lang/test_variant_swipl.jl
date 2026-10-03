# ORIGINAL: a LIVE differential of is_variant_ptr (=@=) and the variant digests against swipl; upstream has no such test.
# test/core_lang/test_variant_swipl.jl — `=@=` against a LIVE swipl, on random pairs.
#
# swipl decides `A =@= B` for every pair; `is_variant_ptr` must agree on each, and the digests must
# follow the answer: variants ⇒ the same `variant_sha1` and `variant_hash`; non-variants ⇒ a
# different `variant_sha1` (up to key collisions, src/pl-termhash.jl DIVERGES 1). The grounded values
# include pairs that are `==` without being identical — `1`/`1.0`, `0.0`/`-0.0` — which SWI keeps
# apart and so must the kernel.
#
# The pairs are built to be HARD: a renaming of the first term (a variant), the same with one
# variable merged into another or split from it, or with one functor or atom changed (the same
# shape, not a variant — measured: without the relabelled pairs a mutation that stopped comparing
# functors survived 1500 pairs), a term sharing
# variables with the first, or an independent term — all from one small pool of variables, so the
# two sides share variables as upstream's units do.
#
# swipl present ⇒ the differential runs. Absent: an ERROR when LOGICKERNEL_REQUIRE_SWIPL=1 (set by
# tools/run_tests.sh and CI's analysis job), otherwise a LOUD note plus an assertion that it was not
# required — never a silent pass.
using Test, LogicKernel, Random
using LogicKernel: is_variant_ptr, pl_variant_sha1, pl_variant_hash

const _VT = DefaultTerm
const _VNVARS = 4

"A random term of depth ≤ `d`, its variables from `vars`."
function _vrand(rng, d::Int, vars::Vector{Int})::_VT
    r = rand(rng, 1:10)
    if d == 0 || r <= 4
        k = rand(rng, 1:6)
        k <= 3 && return mk_var(_VT, UInt64(rand(rng, vars)))
        k == 4 && return sym_term(_VT, rand(rng, (:a, :b, :f)))
        k == 5 && return gnd_term(_VT, rand(rng, (0, 1, 2)))
        return gnd_term(_VT, rand(rng, (0.0, -0.0, 1.0, 2.5, "s")))
    end
    f, n = rand(rng, ((:f, 1), (:f, 2), (:g, 2), (:h, 3)))
    return mk_expr(_VT, _VT[sym_term(_VT, f); [_vrand(rng, d - 1, vars) for _ in 1:n]])
end

"`t` with every variable renamed by `m` (a variable not in `m` is kept)."
function _vrename(t::_VT, m::Dict{UInt64, UInt64})::_VT
    kind(t) === VAR && return mk_var(_VT, get(m, var_key(t), var_key(t)))
    kind(t) === EXPR || return t
    return mk_expr(_VT, _VT[_vrename(child(t, i), m) for i in 1:nchildren(t)])
end

"`t` with the LAST occurrence of variable `a` replaced by variable `b`; `seen` counts down to it."
function _vsplit(t::_VT, a::UInt64, b::UInt64, seen::Base.RefValue{Int})::_VT
    if kind(t) === VAR
        var_key(t) == a || return t
        seen[] -= 1
        return seen[] == 0 ? mk_var(_VT, b) : t
    end
    kind(t) === EXPR || return t
    return mk_expr(_VT, _VT[_vsplit(child(t, i), a, b, seen) for i in 1:nchildren(t)])
end

"`t` with its first `f/2` head made `g/2`, or else its first atom `a` made `b`; `done` says whether it changed."
function _vrelabel(t::_VT, done::Base.RefValue{Bool}, heads::Bool)::_VT
    done[] && return t
    k = kind(t)
    if k === SYM && !heads && sym_name(t) === :a
        done[] = true
        return sym_term(_VT, :b)
    end
    k === EXPR || return t
    if heads && nchildren(t) == 3 && sym_name(child(t, 1)) === :f
        done[] = true
        return mk_expr(_VT, _VT[sym_term(_VT, :g); [child(t, i) for i in 2:3]])
    end
    return mk_expr(_VT, _VT[_vrelabel(child(t, i), done, heads) for i in 1:nchildren(t)])
end

"The `==` twin SWI keeps apart from `v`: `0`↔`0.0`, `1`↔`1.0`, `0.0`↔`-0.0`; `nothing` if none."
function _vtwin(v)::Union{Nothing, Int64, Float64}
    v isa Int64 && v in (0, 1) && return Float64(v)
    v isa Float64 && v === 1.0 && return 1
    v isa Float64 && v === 0.0 && return -0.0
    v isa Float64 && v === -0.0 && return 0.0
    return nothing
end

"`t` with its first grounded value that has an `==` twin replaced by the twin; `done` says if it did."
function _vreground(t::_VT, done::Base.RefValue{Bool})::_VT
    done[] && return t
    if kind(t) === GND
        w = _vtwin(gnd_value(t))
        w === nothing && return t
        done[] = true
        return gnd_term(_VT, w)
    end
    kind(t) === EXPR || return t
    return mk_expr(_VT, _VT[_vreground(child(t, i), done) for i in 1:nchildren(t)])
end

"How often variable `a` occurs in `t`."
_voccurs(t::_VT, a::UInt64)::Int =
    if kind(t) === VAR
        Int(var_key(t) == a)
    elseif kind(t) === EXPR
        sum((_voccurs(child(t, i), a) for i in 1:nchildren(t)); init=0)
    else
        0
    end

"Prolog source of `t`; variable `k` is `V<k>`."
function _vsrc(t::_VT)::String
    k = kind(t)
    k === VAR && return "V$(var_key(t))"
    k === SYM && return string(sym_name(t))
    if k === GND
        v = gnd_value(t)
        return v isa String ? "\"$v\"" : string(v)
    end
    return _vsrc(child(t, 1)) * "(" *
           join((_vsrc(child(t, i)) for i in 2:nchildren(t)), ",") * ")"
end

"`(pairs, kinds)`: `n` random pairs and how each was built."
function _vpairs(rng, n::Int)
    pairs = Tuple{_VT, _VT}[]
    kinds = Symbol[]
    pool = collect(1:_VNVARS)
    for _ in 1:n
        t1 = _vrand(rng, 3, pool)
        how = rand(
            rng,
            (
                :renamed,
                :renamed,
                :merged,
                :split,
                :relabelled,
                :regrounded,
                :sharing,
                :independent
            )
        )
        if how === :renamed                     # a permutation of the pool: a variant
            m = Dict(UInt64(a) => UInt64(b) for (a, b) in zip(pool, shuffle(rng, pool)))
            t2 = _vrename(t1, m)
        elseif how === :merged                  # one variable of t1 becomes another of t1
            occ = shuffle(rng, [UInt64(v) for v in pool if _voccurs(t1, UInt64(v)) > 0])
            t2 = length(occ) >= 2 ? _vrename(t1, Dict(occ[1] => occ[2])) : t1
        elseif how === :split                   # one occurrence of a repeated variable: fresh
            rep = [UInt64(v) for v in pool if _voccurs(t1, UInt64(v)) >= 2]
            t2 = if isempty(rep)
                t1
            else
                a = rand(rng, rep)
                _vsplit(t1, a, UInt64(_VNVARS + 1), Ref(_voccurs(t1, a)))
            end
        elseif how === :regrounded              # a variant but for one `==` twin: not one in SWI
            m = Dict(UInt64(a) => UInt64(b) for (a, b) in zip(pool, shuffle(rng, pool)))
            t2 = _vreground(_vrename(t1, m), Ref(false))
        elseif how === :relabelled              # a variant but for one symbol: not a variant
            m = Dict(UInt64(a) => UInt64(b) for (a, b) in zip(pool, shuffle(rng, pool)))
            done = Ref(false)
            t2 = _vrelabel(_vrename(t1, m), done, true)
            done[] || (t2 = _vrelabel(t2, done, false))
        elseif how === :sharing
            t2 = _vrand(rng, 3, pool)
        else
            t2 = _vrand(rng, 3, [_VNVARS + 1, _VNVARS + 2])
        end
        push!(pairs, (t1, t2))
        push!(kinds, how)
    end
    return pairs, kinds
end

"swipl's `A =@= B` for each pair, as Bools."
function _swipl_variant(pairs)::Vector{Bool}
    prog = IOBuffer()
    println(prog, ":- style_check(-singleton).")
    println(prog, ":- set_prolog_flag(double_quotes, string).")
    for (i, (a, b)) in enumerate(pairs)
        println(prog, "p($i, $(_vsrc(a)), $(_vsrc(b))).")
    end
    println(
        prog,
        "main :- forall(p(I, A, B), (A =@= B -> format(\"~d 1~n\", [I]) ; format(\"~d 0~n\", [I])))."
    )
    println(prog, ":- initialization((main, halt)).")
    out = mktempdir() do d
        f = joinpath(d, "variant.pl")
        write(f, String(take!(prog)))
        read(`swipl -q $f`, String)
    end
    ans = fill(false, length(pairs))
    seen = 0
    for l in eachline(IOBuffer(out))
        i, r = parse.(Int, split(l))
        ans[i] = r == 1
        seen += 1
    end
    seen == length(pairs) || error("swipl answered $seen of $(length(pairs)) pairs:\n$out")
    return ans
end

const _VSWIPL = Sys.which("swipl")
const _VSWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

if _VSWIPL !== nothing
    @testset "=@= and the variant digests == live swipl =@= on random pairs" begin
        pairs, kinds = _vpairs(Xoshiro(20261003), 2000)
        theirs = _swipl_variant(pairs)
        bad = String[]
        for (i, (a, b)) in enumerate(pairs)
            ours = is_variant_ptr(a, b)
            sha = pl_variant_sha1(a) == pl_variant_sha1(b)
            mur = pl_variant_hash(a) == pl_variant_hash(b)
            if ours != theirs[i] || sha != theirs[i] || (theirs[i] && !mur)
                push!(
                    bad,
                    "$(_vsrc(a)) =@= $(_vsrc(b)): swipl $(theirs[i]), ours $ours, " *
                    "sha1 equal $sha, hash equal $mur"
                )
            end
        end
        foreach(b -> println(stderr, "  DIVERGES: ", b), first(bad, 20))
        @test isempty(bad)
        # the data exercised both answers, on the hard pairs too
        @test count(theirs) >= 300 && count(!, theirs) >= 300
        hard(k) = count(i -> !theirs[i] && kinds[i] === k, eachindex(pairs))
        @test hard(:merged) + hard(:split) >= 100   # same shape, not a variant
        @test hard(:relabelled) >= 100              # a variant but for one functor or atom
        @test hard(:regrounded) >= 100              # a variant but for 1/1.0 or 0.0/-0.0
        renamed = [
            theirs[i] && kinds[i] === :renamed && compareStandard(pairs[i]...) != 0 for
            i in eachindex(pairs)
        ]
        @test count(renamed) >= 100                 # variants whose variables really were renamed
        @info "=@= agrees with $(strip(read(`swipl --version`, String))) on $(length(pairs)) pairs ($(count(theirs)) variants)"
    end
elseif _VSWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the =@= differential would be skipped"
    )
else
    @info "=@= DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "=@= differential skipped only where it is not required" begin
        @test !_VSWIPL_REQUIRED
    end
end
