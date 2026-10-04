# ORIGINAL: live differential of the clause index against swipl, and the indexing contract; upstream has no counterpart (it tests SWI against itself).
# test/db/test_index_swipl.jl — the kernel's port of pl-index.c must behave as SWI-Prolog does.
#
# THREE JUDGES:
#   1. THE CONTRACT (always runs): for every call, the answers through the index equal the answers
#      of a scan of every clause — in order, duplicates kept. Indexing never changes answers.
#   2. LogicKernel#1, PINNED (always runs): SWI's H_VOID_N defect is FIXED in the kernel (user,
#      2026-10-02) — its reproducers get the indexes swipl 10.1.16 fails to build.
#   3. LIVE swipl: random fact programs (static and dynamic, unique / few / variable-heavy /
#      compound / deep arguments) and a random sequence of calls — on dynamic predicates
#      interleaved with retract/1 (first answer), retractall/1 and garbage_collect_clauses, swipl's
#      automatic clause GC switched off so both collect at the same points — run by swipl and by
#      the kernel, in one database. Equal for EVERY operation: the answers, in order, and the clause
#      each retract removed. Equal for every predicate the fix cannot touch — no
#      clause whose head code holds an H_VOID_N — also: each answer's determinism
#      (`call_cleanup(G, Det=true)` — exactly where the index left no clause choice); every index
#      `predicate_property(P, indexed(L))` reports (arguments, position, speedup to the float, list,
#      realised; the bucket count where it does not depend on hash values); the primary index. On
#      the predicates the fix touches the kernel indexes where swipl does not, so their determinism
#      and indexes legitimately differ — and a check fails the day swipl stops showing the defect.
#      A control proves the determinism channel can fail: a run without any index answers the same
#      but is judged different.
using Random
include(joinpath(@__DIR__, "index_testlib.jl"))

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _X = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_xs(n) = lk_sym(_X, Symbol(n))
_xg(v::Int) = lk_gnd(_X, v)
_xe(f, xs...) = mk_expr(_X, _X[_xs(f), xs...])
let n = UInt64(0)
    global _xv() = mk_var(_X, n += 1)
end

# ── the program ─────────────────────────────────────────────────────────────────────────────────
"""
A predicate of the generated program: its clauses and the operations on it, in order — `:call`,
and on a dynamic predicate also `:retract` (the first answer), `:retractall` and `:gc`
(`garbage_collect_clauses`).
"""
struct _XPred
    name::Symbol
    arity::Int
    dynamic::Bool
    heads::Vector{_X}
    ops::Vector{Tuple{Symbol, _X}}
end

"Argument `i` (1-based) of clause `c` under `profile` — the shapes that drive SWI's decisions."
function _xarg(rng::AbstractRNG, profile::Symbol, c::Int, k::Int)::_X
    few() = _xs("a$(rand(rng, 0:k))")
    if profile === :unique_atom
        return _xs("u$c")
    elseif profile === :unique_int
        return _xg(1000 + c)
    elseif profile === :few_atom
        return few()
    elseif profile === :few_int
        return _xg(rand(rng, 0:k))
    elseif profile === :const
        return _xs(:a0)
    elseif profile === :void
        return _xv()
    elseif profile === :mixed_var
        return rand(rng) < 0.75 ? few() : _xv()
    elseif profile === :sparse_var
        return rand(rng) < 0.95 ? _xs("u$c") : _xv()
    elseif profile === :compound_few
        return _xe(:f, few())
    elseif profile === :compound_unique
        return _xe(:f, _xs("u$c"))
    elseif profile === :compound_mixed
        r = rand(rng)
        return if r < 0.4
            _xe(:f, few())
        elseif r < 0.8
            _xe(:g, _xs("u$c"), _xv())
        else
            few()
        end
    elseif profile === :deep                    # one functor, nested keys: list (deep) indexes
        return _xe(:f, _xe(:g, few(), _xs("u$c")), rand(rng) < 0.5 ? few() : _xv())
    end
    error("unknown profile $profile")
end

const _XPROFILES = (
    :unique_atom, :unique_int, :few_atom, :few_int, :const, :void, :mixed_var, :sparse_var,
    :compound_few, :compound_unique, :compound_mixed, :deep
)

"A call pattern from clause argument `t`: a variable, a generalisation of `t`, or a fresh value."
function _xgoal_arg(rng::AbstractRNG, t::_X)::_X
    r = rand(rng)
    r < 0.4 && return _xv()
    r < 0.5 && return rand(rng, (_xs(:zz), _xg(99999), _xe(:f, _xs(:zz))))
    return _xgeneralise(rng, t)
end
function _xgeneralise(rng::AbstractRNG, t::_X)::_X
    kind(t) === VAR && return _xv()
    kind(t) === EXPR || return t
    return mk_expr(
        _X,
        _X[
            if i == 1
                child(t, 1)
            else
                (rand(rng) < 0.25 ? _xv() : _xgeneralise(rng, child(t, i)))
            end
            for i in 1:nchildren(t)
        ]
    )
end

"The generated program: `n` predicates, deterministic for a given seed."
function _xprogram(seed::Int, n::Int)::Vector{_XPred}
    rng = Xoshiro(seed)
    preds = _XPred[]
    for p in 1:n
        arity = rand(rng, 1:5)
        ncl = rand(rng, (1, 2, 3, 5, 8, 10, 11, 12, 16, 33, 64, 65, 120, 300))
        profiles = [rand(rng, _XPROFILES) for _ in 1:arity]
        ks = [rand(rng, 1:5) for _ in 1:arity]
        name = Symbol("p$p")
        heads = [
            _xe(name, (_xarg(rng, profiles[i], c, ks[i]) for i in 1:arity)...) for
            c in 1:ncl
        ]
        dynamic = rand(rng, Bool)
        ops = Tuple{Symbol, _X}[]
        for _ in 1:rand(rng, 4:10)
            h = rand(rng, heads)
            push!(
                ops,
                (:call, _xe(name, (_xgoal_arg(rng, child(h, i + 1)) for i in 1:arity)...))
            )
            dynamic || continue
            r = rand(rng)                               # retract, retractall and GC in between
            if r < 0.30
                h = rand(rng, heads)
                pat = _xe(
                    name,
                    (
                        rand(rng) < 0.5 ? _xv() : _xgeneralise(rng, child(h, i + 1))
                        for i in 1:arity
                    )...
                )
                push!(ops, (:retract, pat))
            elseif r < 0.38
                h = rand(rng, heads)
                pat = _xe(
                    name,
                    (
                        rand(rng) < 0.7 ? _xv() : _xgeneralise(rng, child(h, i + 1))
                        for i in 1:arity
                    )...
                )
                push!(ops, (:retractall, pat))
            elseif r < 0.50
                push!(ops, (:gc, _xs(:gc)))
            end
        end
        push!(preds, _XPred(name, arity, dynamic, heads, ops))
    end
    return preds
end

"The LogicKernel#1 reproducers, with the call orders of the issue."
function _xhvoid()::Vector{_XPred}
    hp = [_xe(:hv_p, _xv(), _xv(), _xs("a$i")) for i in 1:100]
    hq = [_xe(:hv_q, _xv(), _xs(:x), _xs("a$i")) for i in 1:100]
    hp4 = [_xe(:hv_p4, _xv(), _xv(), _xs("a$i"), _xs("b$i")) for i in 1:100]
    hq4 = [_xe(:hv_q4, _xv(), _xv(), _xs("a$i"), _xs("b$i")) for i in 1:100]
    return [
        _XPred(:hv_p, 3, true, hp, [(:call, _xe(:hv_p, _xv(), _xv(), _xs(:a50)))]),
        _XPred(:hv_q, 3, true, hq, [(:call, _xe(:hv_q, _xv(), _xv(), _xs(:a50)))]),
        _XPred(
            :hv_p4, 4, true, hp4, [(:call, _xe(:hv_p4, _xv(), _xv(), _xv(), _xs(:b50)))]
        ),
        _XPred(
            :hv_q4, 4, true, hq4,
            [
                (:call, _xe(:hv_q4, _xv(), _xv(), _xs(:a50), _xs(:b50))),
                (:call, _xe(:hv_q4, _xv(), _xv(), _xv(), _xs(:b50)))
            ]
        )
    ]
end

"""
SWI-7's `[]` and the text atom `'[]'` as clause keys of one predicate, dynamic and static: they key
APART — `[]` compiles to `H_NIL`, keyed `ATOM_nil`, `'[]'` to an `H_ATOM` — as upstream's two atom
handles do; were they one key, the first argument's assessment would differ from swipl's. Built by
hand rather than drawn: a new profile in the random program moved every later draw, and its
measured coverage (49 of 57 retracts removing a clause) fell to 29 of 35.

The same for FUNCTOR names: `[](K)` and `'[]'(K)` are compounds of two functors in swipl
(`[](a) \\== '[]'(a)`, probed), so their functor keys differ too.
"""
function _xnil()::Vector{_XPred}
    keys = (mk_nil(_X), _xs("[]"), _xs(:a0))
    heads(name) = [_xe(name, keys[1 + (i % 3)], _xg(i)) for i in 1:60]
    calls(name) = [
        (:call, _xe(name, mk_nil(_X), _xv())), (:call, _xe(name, _xs("[]"), _xv())),
        (:call, _xe(name, _xv(), _xg(7)))
    ]
    # [](K), '[]'(K), a0(K): the reserved symbol and the text atom as functor NAMES
    fkey(j, i) = mk_expr(_X, _X[keys[j], _xg(i % 5)])
    fheads(name) = [_xe(name, fkey(1 + (i % 3), i), _xg(i)) for i in 1:60]
    fcalls(name) = [
        (:call, _xe(name, mk_expr(_X, _X[mk_nil(_X), _xv()]), _xv())),
        (:call, _xe(name, mk_expr(_X, _X[_xs("[]"), _xv()]), _xv())),
        (:call, _xe(name, mk_expr(_X, _X[mk_nil(_X), _xg(2)]), _xg(59))),
        (:call, _xe(name, _xv(), _xg(7)))
    ]
    return [
        _XPred(
            :nq_d, 2, true, heads(:nq_d),
            [calls(:nq_d); (:retract, _xe(:nq_d, mk_nil(_X), _xv())); calls(:nq_d)]
        ),
        _XPred(:nq_s, 2, false, heads(:nq_s), calls(:nq_s)),
        _XPred(
            :nqf_d, 2, true, fheads(:nqf_d),
            [
                fcalls(:nqf_d);
                (:retract, _xe(:nqf_d, mk_expr(_X, _X[mk_nil(_X), _xv()]), _xv()));
                fcalls(:nqf_d)
            ]
        ),
        _XPred(:nqf_s, 2, false, fheads(:nqf_s), fcalls(:nqf_s))
    ]
end

"""
Literal and list keys (V1, L1) in the first argument of one predicate, dynamic and static:
* numbers by kind and storage — a tagged integer (`H_SMALLINT`), an Int64 above the tagged range
  and a big integer (`H_MPZ`), a float (`H_FLOAT`), a rational (`H_MPQ`);
* list cells — `[aN|_]` (`H_LIST`) and `[X|Y]` whose variables recur in the second argument
  (`H_LIST_FF`) — and `'[|]'(a)`, which is no list cell (`H_FUNCTOR`).
`argKey` reads each clause's key from the new instructions, and `indexOfWord` keys each call: both
must come to swipl's determinism and first-argument assessment. Every answer is ground or has
singleton variables only, so it prints as swipl prints it.
"""
function _xlit()::Vector{_XPred}
    L(h, t) = _xe("[|]", h, t)
    function lhead(name, i)::_X
        j = i % 8
        j == 0 && return _xe(name, _xg(i), _xg(i))
        j == 1 && return _xe(name, lk_gnd(_X, 2^56 + i), _xg(i))
        j == 2 && return _xe(name, lk_gnd(_X, big(2)^70 + i), _xg(i))
        j == 3 && return _xe(name, lk_gnd(_X, i + 0.5), _xg(i))
        j == 4 && return _xe(name, lk_gnd(_X, Rational{BigInt}(2i + 1, 2)), _xg(i))
        j == 5 && return _xe(name, L(_xs("a$(i % 3)"), _xv()), _xg(i))
        j == 6 && return (X=_xv(); Y=_xv(); _xe(name, L(X, Y), _xe(:g, X, Y)))
        return _xe(name, _xe("[|]", _xs(:a)), _xg(i))
    end
    heads(name) = [lhead(name, i) for i in 1:64]
    calls(name) = [
        (:call, _xe(name, _xg(16), _xv())),
        (:call, _xe(name, lk_gnd(_X, 2^56 + 9), _xv())),
        (:call, _xe(name, lk_gnd(_X, big(2)^70 + 10), _xv())),
        (:call, _xe(name, lk_gnd(_X, 11.5), _xv())),
        (:call, _xe(name, lk_gnd(_X, Rational{BigInt}(25, 2)), _xv())),
        (:call, _xe(name, L(_xs(:a1), _xs(:b)), _xv())),
        (:call, _xe(name, L(_xs(:a2), mk_nil(_X)), _xv())),
        (:call, _xe(name, _xe("[|]", _xs(:a)), _xv())),
        (:call, _xe(name, _xv(), _xg(13)))
    ]
    # every first argument a list cell, two `H_LIST_FF` clauses among 80: the index goes DEEP into
    # the cell (its head, `1:1` — swipl 10.1.16 builds it here, probed; with 4 of 40 it does not),
    # where an `H_LIST_FF` clause reads upstream's two-void dummy (pl-index.c `skipToTerm`) — a
    # wildcard, so `[a7|t]` still finds it
    function dhead(name, i)::_X
        i in (25, 65) && return (X=_xv(); Y=_xv(); _xe(name, L(X, Y), _xe(:g, X, Y)))
        return _xe(name, L(_xs("a$i"), _xs(:t)), _xg(i))
    end
    dheads(name) = [dhead(name, i) for i in 1:80]
    dcalls(name) = [(:call, _xe(name, L(_xs("a$i"), _xs(:t)), _xv())) for i in (7, 15, 33)]
    return [
        _XPred(
            :lt_d, 2, true, heads(:lt_d),
            [
                calls(:lt_d);
                (:retract, _xe(:lt_d, L(_xs(:a0), _xs(:b)), _xv()));
                calls(:lt_d)
            ]
        ),
        _XPred(:lt_s, 2, false, heads(:lt_s), calls(:lt_s)),
        _XPred(:dl_d, 2, true, dheads(:dl_d), dcalls(:dl_d)),
        _XPred(:dl_s, 2, false, dheads(:dl_s), dcalls(:dl_s))
    ]
end

# ── running it in the kernel ────────────────────────────────────────────────────────────────────
"One `idx` report line's fields."
const _XIdx = Tuple{String, Vector{Int}, Vector{Int}, Float32, Bool, Bool, Int}

"True when a clause of `p` has an H_VOID_N in its head code — where LogicKernel#1's fix applies."
function _xvoid_run(p::IxPred)::Bool
    cref = p.def.impl_clauses.first_clause
    while cref !== nothing
        codes = (cref.clause::LK.Clause{_X}).codes
        pc = LK.Code(codes, 1)
        while pc.pc <= length(codes)
            LK.decode(pc) == LK.H_VOID_N && return true
            pc = LK.stepPC(pc)
        end
        cref = cref.next
    end
    return false
end

"""
Run the program; answers as text lines, index reports, primary indexes, the predicates the
LogicKernel#1 fix can touch, and the predicate of each call. `unindexed`: the oracle.
"""
function _xrun(preds::Vector{_XPred}; unindexed::Bool=false)
    lines = String[]
    idx = _XIdx[]
    pidx = String[]
    goalpred = String[]
    db = IxDB{_X}()                                     # one database, as in swipl
    built = [ix_pred(_X, p.name, p.arity; dynamic=p.dynamic, db=db) for p in preds]
    for (p, b) in zip(preds, built), h in p.heads
        ix_assertz!(b, h)
    end
    affected = Set("$(p.name)/$(p.arity)" for (p, b) in zip(preds, built) if _xvoid_run(b))
    k = 0
    for (p, b) in zip(preds, built), (op, g) in p.ops
        k += 1
        push!(goalpred, "$(p.name)/$(p.arity)")
        if op === :call
            ans = unindexed ? ix_call_unindexed(b, g) : ix_call(b, g)
            for (a, det) in ans
                push!(lines, "$k $(ix_text(a)) $(det ? "det" : "nondet")")
            end
            push!(lines, "$k end")
        elseif op === :retract                          # (retract(G) -> … ; …): first answer
            r = ix_retract!(b, g; after=_ -> false)
            push!(lines, "$k retract $(isempty(r) ? "none" : ix_text(r[1]))")
        elseif op === :retractall
            ix_retractall!(b, g)
            push!(lines, "$k retractall")
        else
            ix_gc!(db)
            push!(lines, "$k gc")
        end
    end
    for (p, b) in zip(preds, built)
        r = LK.unify_index_pattern(b.def)
        pa = "$(p.name)/$(p.arity)"
        if r !== nothing
            for d in r
                push!(
                    idx,
                    (pa, d.arguments, d.position, d.speedup, d.list, d.realised, d.buckets)
                )
            end
        end
        pi = ix_primary_index(b)
        push!(pidx, "$pa $(pi === nothing ? "none" : pi)")
    end
    return (; lines, idx, pidx, affected, goalpred)
end

"The answer lines of the calls to predicates the LogicKernel#1 fix cannot touch."
_xuntouched(lines::Vector{String}, run)::Vector{String} =
    [l for l in lines if !(run.goalpred[parse(Int, split(l, ' ')[1])] in run.affected)]

"Without the determinism word: what the indexing contract compares."
_xstrip_det(ls::Vector{String})::Vector{String} =
    [replace(l, r" (det|nondet)$" => "") for l in ls]

# ── running it in swipl ─────────────────────────────────────────────────────────────────────────
const _XDRIVER = raw"""
:- initialization(main, main).
ans(K, G) :-
    forall(( call_cleanup(G, Det=true), ( Det == true -> D = det ; D = nondet ) ),
           ( copy_term(G, C), numbervars(C, 0, _, [singletons(true)]),
             format("~w ", [K]),
             write_term(C, [quoted(true), ignore_ops(true), numbervars(true)]),
             format(" ~w~n", [D]) )),
    format("~w end~n", [K]).
ret(K, G) :-
    (   retract(G)
    ->  copy_term(G, C), numbervars(C, 0, _, [singletons(true)]),
        format("~w retract ", [K]),
        write_term(C, [quoted(true), ignore_ops(true), numbervars(true)]), nl
    ;   format("~w retract none~n", [K])
    ).
rall(K, G) :- retractall(G), format("~w retractall~n", [K]).
gcx(K) :- garbage_collect_clauses, format("~w gc~n", [K]).
report(P/N) :-
    functor(H, P, N),
    (   predicate_property(H, indexed(L))
    ->  forall(member(Dict, L),
               ( get_dict(arguments, Dict, A), get_dict(position, Dict, Pos),
                 get_dict(speedup, Dict, S), get_dict(list, Dict, Li),
                 get_dict(realised, Dict, R), get_dict(buckets, Dict, B),
                 format("idx ~w/~w ~w ~w ~w ~w ~w ~w~n", [P, N, A, Pos, S, Li, R, B]) ))
    ;   true
    ),
    (   '$get_predicate_attribute'(H, primary_index, I) -> true ; I = none ),
    format("pindex ~w/~w ~w~n", [P, N, I]).
"""

"Run the program in swipl: the same three outputs, parsed."
function _xswipl(preds::Vector{_XPred})
    mktempdir() do d
        io = IOBuffer()
        for p in preds
            p.dynamic && println(io, ":- dynamic $(p.name)/$(p.arity).")
        end
        for p in preds, h in p.heads
            p.dynamic || println(io, ix_text(h, ix_var_counts(h)), ".")
        end
        print(io, _XDRIVER)
        println(io, "main :-")
        # clause GC only where the program says, as in the kernel: no automatic collection
        println(io, "    '\$cgc_params'(_, _, _, 0, 1.0e30, 1.0e30),")
        for p in preds, h in p.heads
            p.dynamic && println(io, "    assertz(", ix_text(h, ix_var_counts(h)), "),")
        end
        k = 0
        for p in preds, (op, g) in p.ops
            k += 1
            if op === :call
                println(io, "    ans($k, ", ix_text(g), "),")
            elseif op === :retract
                println(io, "    ret($k, ", ix_text(g), "),")
            elseif op === :retractall
                println(io, "    rall($k, ", ix_text(g), "),")
            else
                println(io, "    gcx($k),")
            end
        end
        println(
            io,
            "    forall(member(PI, [",
            join(("$(p.name)/$(p.arity)" for p in preds), ","),
            "]), report(PI))."
        )
        f = joinpath(d, "prog.pl")
        write(f, take!(io))
        out = split(read(`swipl -q $f`, String), '\n'; keepempty=false)
        lines = String[
            l for l in out if !startswith(l, "idx ") && !startswith(l, "pindex ")
        ]
        pidx = String[l[8:end] for l in out if startswith(l, "pindex ")]
        idx = _XIdx[]
        for l in out
            startswith(l, "idx ") || continue
            m = match(
                r"^idx (\S+) \[([\d,]*)\] \[([\d,]*)\] (\S+) (true|false) (true|false) (\d+)$",
                l
            )
            m === nothing && error("unparsed swipl line: $l")
            ints(s) = isempty(s) ? Int[] : parse.(Int, split(s, ','))
            push!(
                idx,
                (m[1], ints(m[2]), ints(m[3]), Float32(parse(Float64, m[4])),
                    m[5] == "true", m[6] == "true", parse(Int, m[7]))
            )
        end
        return (; lines, idx, pidx)
    end
end

"Index reports in a canonical order: by predicate, position, arguments, speedup."
_xorder(v::Vector{_XIdx})::Vector{_XIdx} = sort(v; by=i -> (i[1], i[3], i[2], i[4]))

"""
Differences between two index reports. Three allowances, each a consequence of the kernel's KEY
VALUES differing from SWI's atom and functor numbers (`indexOfWord`, DIVERGES) — never of logic:
  * BUCKETS: `perfect_size` searches for a collision-free table of at most 32 buckets using the
    keys' hash values, and returns 64 when there is none; below 64 the count is hash-dependent.
  * SPEEDUP to a few ulps: `assess_remove_duplicates` runs Welford's mean/variance over the
    per-key counts in SORTED-KEY order; other key values sum the same counts in another order.
    Uniform counts (standard deviation 0) still compare exactly — most indexes here.
  * ORDER of the deep indexes of one predicate: `add_deep_indexes` walks a list index's buckets.
Everything else — arguments, position, list, realised — must be equal.
"""
function _xidx_diff(ours::Vector{_XIdx}, theirs::Vector{_XIdx})::Vector{String}
    out = String[]
    length(ours) == length(theirs) ||
        push!(out, "index count: ours $(length(ours)), swipl $(length(theirs))")
    for (o, t) in zip(_xorder(ours), _xorder(theirs))
        same =
            o[1:3] == t[1:3] && o[5:6] == t[5:6] &&
            (o[4] == t[4] || isapprox(o[4], t[4]; rtol=4 * eps(Float32))) &&
            (t[7] > 64 ? o[7] == t[7] : o[7] <= 64)
        same || push!(out, "ours $o  swipl $t")
    end
    return out
end

"The first lines where two outputs differ."
function _xline_diff(a::Vector{String}, b::Vector{String})::Vector{String}
    out = String[]
    for i in 1:max(length(a), length(b))
        x = i <= length(a) ? a[i] : "<none>"
        y = i <= length(b) ? b[i] : "<none>"
        x == y || push!(out, "line $i: ours `$x`  swipl `$y`")
        length(out) >= 8 && break
    end
    return out
end

const _XSWIPL = Sys.which("swipl")
const _XSWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"
const _XSEED = 20261002

@testset "clause index vs swipl" begin
    program = vcat(_xprogram(_XSEED, 60), _xhvoid(), _xnil(), _xlit())
    ours = _xrun(program)
    oracle = _xrun(program; unindexed=true)

    @testset "the contract: indexing never changes answers" begin
        @test _xstrip_det(ours.lines) == _xstrip_det(oracle.lines)
        @test count(l -> !endswith(l, " end"), ours.lines) > 500       # the data exercises it
        # the program builds hash, multi-argument and deep indexes, realised and virtual
        @test any(i -> length(i[2]) > 1, ours.idx)
        @test any(i -> !isempty(i[3]), ours.idx)
        @test any(i -> i[5], ours.idx) && any(i -> !i[6], ours.idx)
        # and retract, retractall and clause GC run between the calls (measured: 57 retracts, 49
        # of them removing a clause; 16 retractalls; 23 collections)
        ret = filter(l -> occursin(" retract ", l), ours.lines)
        @test count(l -> !endswith(l, " none"), ret) >= 30
        @test count(l -> endswith(l, " retractall"), ours.lines) >= 8
        @test count(l -> endswith(l, " gc"), ours.lines) >= 10
        @info "index differential mutations: $(count(l -> !endswith(l, " none"), ret)) of $(length(ret)) retracts removed a clause; $(count(l -> endswith(l, " retractall"), ours.lines)) retractalls; $(count(l -> endswith(l, " gc"), ours.lines)) collections"
    end

    @testset "LogicKernel#1 pinned: the H_VOID_N defect is fixed" begin
        hv(pa) = [i[2:4] for i in ours.idx if i[1] == pa]
        @test hv("hv_p/3") == [([3], Int[], 100.0f0)]  # p(_,_,a50): indexed (swipl 10.1.16: none)
        @test hv("hv_q/3") == [([3], Int[], 100.0f0)]
        @test hv("hv_p4/4") == [([4], Int[], 100.0f0)]
        @test sort(hv("hv_q4/4")) ==                   # q4(_,_,a50,b50) first, then q4(_,_,_,b50):
            [([3], Int[], 100.0f0), ([4], Int[], 100.0f0)]  # (swipl: none, and stays so)
        # the fix only narrows: p(_,_,a50) is now deterministic, with the same single answer
        k = findfirst(==("hv_p/3"), ours.goalpred)
        @test [l for l in ours.lines if startswith(l, "$k ")] ==
            ["$k hv_p(_,_,a50) det", "$k end"]
        @test "hv_p/3" in ours.affected && "hv_q4/4" in ours.affected
        @test !("hv_q/3" in ours.affected)            # q(_,x,a): one void, no H_VOID_N
    end

    if _XSWIPL !== nothing
        @testset "identical to swipl (but where LogicKernel#1 is fixed)" begin
            theirs = _xswipl(program)
            # every call: the same answers, in order
            d = _xline_diff(_xstrip_det(ours.lines), _xstrip_det(theirs.lines))
            isempty(d) || foreach(x -> println(stderr, "  answers: ", x), d)
            @test isempty(d)
            # every call the fix cannot touch: the same determinism too
            our_u, their_u = _xuntouched(ours.lines, ours), _xuntouched(theirs.lines, ours)
            d = _xline_diff(our_u, their_u)
            isempty(d) || foreach(x -> println(stderr, "  determinism: ", x), d)
            @test isempty(d)
            untouched(v) = [i for i in v if !(i[1] in ours.affected)]
            oi, ti = untouched(ours.idx), untouched(theirs.idx)
            di = _xidx_diff(oi, ti)
            isempty(di) ||
                foreach(x -> println(stderr, "  indexed: ", x), di[1:min(end, 8)])
            @test isempty(di)
            keep(v) = [l for l in v if !(split(l, ' ')[1] in ours.affected)]
            @test keep(ours.pidx) == keep(theirs.pidx)
            # the carve-out stays narrow: most predicates, calls and indexes are compared in full
            nuntouched = length(program) - length(ours.affected)
            @test nuntouched >= 30
            @test count(l -> !endswith(l, " end"), our_u) > 1500
            pairs = collect(zip(_xorder(oi), _xorder(ti)))
            exact = count(((o, t),) -> o[4] == t[4], pairs)
            @test length(pairs) == length(ti) > 80
            @test exact >= 0.9 * length(pairs)
            # the defect is still swipl's: the day swipl indexes these, revisit LogicKernel#1
            @test !any(i -> i[1] in ("hv_p/3", "hv_q4/4"), theirs.idx)
            # and the fix shows: on the predicates it touches, the kernel narrows where swipl cannot
            @test _xuntouched(theirs.lines, ours) != theirs.lines
            @test _xstrip_det(ours.lines) == _xstrip_det(theirs.lines) &&
                ours.lines != theirs.lines
            # control: with no index at all the answers are the same, the determinism is not
            @test !isempty(_xline_diff(_xuntouched(oracle.lines, ours), their_u))
            @info "clause index: $(length(theirs.lines)) answer lines identical; $(nuntouched) of $(length(program)) predicates also identical in determinism and indexes ($(length(pairs)) indexes, $exact bit-identical speedups); the other $(length(ours.affected)) carry LogicKernel#1's fix — vs $(strip(read(`swipl --version`, String)))"
        end
    elseif _XSWIPL_REQUIRED
        error(
            "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the index differential would be skipped"
        )
    else
        @info "INDEX vs swipl NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
        @testset "swipl comparison skipped only where it is not required" begin
            @test !_XSWIPL_REQUIRED
        end
    end
end
