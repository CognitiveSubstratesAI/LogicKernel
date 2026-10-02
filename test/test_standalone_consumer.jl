# ORIGINAL: the standalone consumer's test — runs swipl-bench programs written against the public API; upstream has no such test.
# test/test_standalone_consumer.jl — LogicKernel used by a CLIENT, through its public API only.
#
# WHY (user, 2026-10-02): "standalone" is a claim about Project.toml until something other than one
# package exercises the interface. The client here is four of swipl-devel's own benchmark programs
# (bench/programs/{derive,nreverse,qsort,poly_10}.jl, ports of the verbatim .pl files beside them),
# written on `DefaultTerm` with exported names only. Three judges, none of them the kernel:
#   1. STANDALONE — their parsed code names nothing LogicKernel does not export;
#   2. INDEPENDENT ORACLES that always run — Julia's own reverse/sort, the polynomial evaluated at
#      points where (1+x+y+z)^10 is known, the derivatives evaluated against hand-derived formulas;
#   3. LIVE swipl — the verbatim upstream programs run on inputs EXTRACTED from their source text,
#      and our results must print exactly as swipl's write_canonical prints its own.
using Test, LogicKernel

const _CB = joinpath(pkgdir(LogicKernel), "bench", "programs")
include("../bench/programs/derive.jl")      # literal paths, so analysis tools can follow them
include("../bench/programs/nreverse.jl")
include("../bench/programs/qsort.jl")
include("../bench/programs/poly_10.jl")

# ── a client-side write_canonical (SWI-Prolog 7 output: operators as functors, `[]` reserved) ────
const _SOLO_SYMCHARS = Set("#\$&*+-./:<=>?@^~\\")
function _atom_text(n::String)::String
    n == "[]" && return "[]"
    occursin(r"^[a-z][A-Za-z0-9_]*$", n) && return n
    !isempty(n) && all(in(_SOLO_SYMCHARS), n) && return n
    n in ("!", ";") && return n
    return "'" * replace(n, "\\" => "\\\\", "'" => "\\'") * "'"
end
_is_cons(t) =
    kind(t) === EXPR && nchildren(t) == 3 && kind(child(t, 1)) === SYM &&
    sym_name(child(t, 1)) === Symbol("[|]")
function canonical(t)::String
    k = kind(t)
    if k === GND
        v = gnd_value(t)
        v isa Int && return string(v)
        error("canonical: only integers occur in these programs, got $(typeof(v))")
    elseif k === SYM
        return _atom_text(String(sym_name(t)))
    elseif k === VAR
        return "_"
    elseif _is_cons(t)
        elems = String[]
        while _is_cons(t)
            push!(elems, canonical(child(t, 2)))
            t = child(t, 3)
        end
        tail = kind(t) === SYM && sym_name(t) === Symbol("[]") ? "" : "|" * canonical(t)
        return "[" * join(elems, ",") * tail * "]"
    end
    return canonical(child(t, 1)) * "(" *
           join([canonical(child(t, i)) for i in 2:nchildren(t)], ",") * ")"
end

# ── judge 1: only exported names ────────────────────────────────────────────────────────────────
function _client_names!(out::Set{Symbol}, ex)
    if ex isa Symbol
        push!(out, ex)
    elseif ex isa Expr
        # `LogicKernel.x` is `Expr(:., :LogicKernel, QuoteNode(:x))`. NOT `using LogicKernel`, which
        # parses as the one-argument module path `Expr(:., :LogicKernel)` — the first version of this
        # guard flagged exactly that, i.e. compared the wrong thing (caught by its own run).
        if ex.head === :. && length(ex.args) == 2 && ex.args[1] === :LogicKernel &&
            ex.args[2] isa QuoteNode
            push!(out, Symbol("LogicKernel.QUALIFIED"))
        end
        foreach(a -> _client_names!(out, a), ex.args)
    end
    return out
end

# ── judge 2: independent oracles ────────────────────────────────────────────────────────────────
"Evaluate a derive/3 expression at x (Float64) — the client's own arithmetic, not the kernel's."
function _deval(t, x::Float64)::Float64
    kind(t) === GND && return Float64(gnd_value(t)::Int)
    kind(t) === SYM && (sym_name(t) === :x ? (return x) : error("unknown symbol"))
    f = sym_name(child(t, 1))
    a = [_deval(child(t, i), x) for i in 2:nchildren(t)]
    f === :+ && return a[1] + a[2]
    f === :* && return a[1] * a[2]
    f === :/ && return a[1] / a[2]
    f === :^ && return a[1]^a[2]
    f === :- && return length(a) == 1 ? -a[1] : a[1] - a[2]
    f === :log && return log(a[1])
    f === :exp && return exp(a[1])
    error("unknown functor $f")
end

"Evaluate a poly/2 result at integer values of x, y, z."
function _peval(t, env::Dict{Symbol, Int})::Int
    kind(t) === GND && return gnd_value(t)::Int
    v = env[sym_name(child(t, 2))]
    s, l = 0, child(t, 3)
    while _is_cons(l)
        term = child(l, 2)
        s += _peval(child(term, 3), env) * v^(gnd_value(child(term, 2))::Int)
        l = child(l, 3)
    end
    return s
end

# ── judge 3: the verbatim upstream program, run by swipl ────────────────────────────────────────
"Run `goal` (which binds I and R) in swipl after consulting `file`; return the printed lines."
function _swipl(file::String, goal::String)::Vector{String}
    mktempdir() do d
        drv = joinpath(d, "drv.pl")
        write(
            drv,
            """
 :- initialization(main, main).
 main :- consult('$(replace(file, "'" => "\\'"))'), $goal.
 """
        )
        return filter(!isempty, split(read(`swipl -q $drv`, String), '\n'))
    end
end
"The text between `prefix` and `suffix` in an upstream program — inputs are extracted, not retyped."
function _extract(file::String, prefix::String, suffix::String)::String
    src = read(file, String)
    i = findfirst(prefix, src)
    j = findnext(suffix, src, last(i) + 1)
    return replace(src[(last(i) + 1):(first(j) - 1)], r"\s+" => "")
end

const _SWIPL = Sys.which("swipl")
const _SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

@testset "standalone consumer" begin
    @testset "the client programs use only LogicKernel's exported API" begin
        internal = Set(
            n for n in names(LogicKernel; all=true) if
            isdefined(LogicKernel, n) && !(n in names(LogicKernel))
        )
        # controls: the guard flags a qualified access and an internal name, and NOT a bare `using`
        sc(src) = _client_names!(Set{Symbol}(), Meta.parseall(src))
        @test Symbol("LogicKernel.QUALIFIED") in
            sc("using LogicKernel\ny = LogicKernel.kind(t)")
        @test !(Symbol("LogicKernel.QUALIFIED") in sc("using LogicKernel\ny = kind(t)"))
        @test !isempty(
            intersect(sc("using LogicKernel: _tag_rank\ny = _tag_rank(VAR)"), internal)
        )
        used = Set{Symbol}()
        for f in ("derive.jl", "nreverse.jl", "qsort.jl", "poly_10.jl")
            _client_names!(used, Meta.parseall(read(joinpath(_CB, f), String)))
        end
        @test !(Symbol("LogicKernel.QUALIFIED") in used)      # no `LogicKernel.x` access
        leaked = intersect(used, internal)
        isempty(leaked) || println(stderr, "  internal names used by the client: ", leaked)
        @test isempty(leaked)
        @test issubset(
            (:DefaultTerm, :kind, :child, :nchildren, :sym_name, :gnd_value, :mk_expr,
                :sym_term, :gnd_term, :compareStandard), used)  # the scan saw the API it should
    end

    @testset "independent oracles" begin
        @test canonical(NReverse.top()) == "[" * join(30:-1:1, ",") * "]"
        @test canonical(QSort.top()) == "[" * join(sort(collect(QSort.INPUT)), ",") * "]"
        p = Poly10.top()
        @test _peval(p, Dict(:x => 1, :y => 1, :z => 1)) == 4^10      # (1+1+1+1)^10
        @test _peval(p, Dict(:x => 2, :y => 3, :z => 5)) == 11^10     # (1+2+3+5)^10
        o8, l10, d10 = Derive.top()
        x = 2.0
        f8prime = (x^2 + 2) * (x^3 + 3) + (x + 1) * (2x * (x^3 + 3) + (x^2 + 2) * 3x^2)
        @test _deval(o8, x) ≈ f8prime                                   # d/dx (x+1)(x²+2)(x³+3)
        @test _deval(d10, x) ≈ -8 / x^9                                 # x/x^9 = x^-8
        # no numeric oracle for log10: a 10-fold nested log is negative long before any testable x
        # — that program is judged by the live swipl comparison below
        @test is_ground(o8) && is_ground(l10) && is_ground(d10)
    end

    if _SWIPL !== nothing
        @testset "identical to swipl running the verbatim upstream programs" begin
            dv = joinpath(_CB, "derive.pl")
            ins = [
                _extract(dv, "$p :- d(", ",x,_).") for p in ("ops8", "log10", "divide10")
            ]
            out = _swipl(
                dv,
                "forall(member(I, [$(join(ins, ","))]), (d(I, x, R), " *
                "write_canonical(I), nl, write_canonical(R), nl))"
            )
            ours = [Derive.ops8_input(), Derive.ops8(), Derive.log10_input(),
                Derive.log10(),
                Derive.divide10_input(), Derive.divide10()]
            @test length(out) == 6
            @test out == canonical.(ours)                       # inputs AND derivatives

            nl = _extract(joinpath(_CB, "nreverse.pl"), "nreverse :- nreverse(", ",_).")
            @test _swipl(
                joinpath(_CB, "nreverse.pl"), "nreverse($nl, R), write_canonical(R), nl"
            ) ==
                [canonical(NReverse.top())]
            ql = _extract(joinpath(_CB, "qsort.pl"), "qsort :- qsort(", ",_,[]).")
            @test _swipl(
                joinpath(_CB, "qsort.pl"), "qsort($ql, R, []), write_canonical(R), nl"
            ) ==
                [canonical(QSort.top())]
            @test _swipl(joinpath(_CB, "poly_10.pl"),
                "test_poly(P), poly_exp(10, P, R), write_canonical(R), nl") ==
                [canonical(Poly10.top())]
            @info "standalone consumer: 4 swipl-bench programs agree with $(strip(read(`swipl --version`, String)))"
        end
    elseif _SWIPL_REQUIRED
        error(
            "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the consumer's upstream check would be skipped"
        )
    else
        @info "CONSUMER vs swipl NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
        @testset "swipl comparison skipped only where it is not required" begin
            @test !_SWIPL_REQUIRED
        end
    end
end
