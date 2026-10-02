# ORIGINAL: live differential of the head compiler against swipl's vm_list; upstream has no counterpart (it tests SWI against itself).
# test/compile/test_head_code_swipl.jl — the clause index reads clause keys from compiled head code
# (src/pl-comp.jl), so the kernel's head code must be SWI's, instruction for instruction: which
# arguments become H_VOID, how runs of voids merge into H_VOID_N and vanish before H_POP and
# I_EXITFACT, H_FIRSTVAR against H_VAR, H_FUNCTOR against H_RFUNCTOR.
#
# Random heads — shared and singleton variables, atoms, small integers, compounds nested three
# deep — are compiled by the kernel and asserted in swipl, whose `vm_list/1` prints its code. The
# instruction sequences must be equal, `H_VOID_N` counts included. Only the instruction NAMES are
# compared: operands are atom, functor and frame-slot numbers private to each system. Two names
# map, because the term interface has no integer type (src/pl-comp.jl, `compileArgument!`):
# swipl's `h_smallint` is the kernel's `h_atom`.
using Random
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))

const _H = DefaultTerm
_hs(n) = sym_term(_H, Symbol(n))
_he(f, xs::Vector{_H}) = mk_expr(_H, _H[_hs(f); xs])

"A random head argument: a variable from `shared` (or a fresh one), an atom, an int, a compound."
function _harg(rng::AbstractRNG, shared::Vector{_H}, depth::Int)::_H
    r = rand(rng)
    if r < 0.3
        return mk_var(_H, rand(rng, UInt64(1):UInt64(1 << 40)))     # almost surely a singleton
    elseif r < 0.45
        return rand(rng, shared)
    elseif r < 0.6
        return _hs(rand(rng, (:a, :b, :c)))
    elseif r < 0.7
        return gnd_term(_H, rand(rng, 0:9))
    elseif depth < 3
        return _he(
            rand(rng, (:f, :g, :h)),
            [_harg(rng, shared, depth + 1) for _ in 1:rand(rng, 1:3)]
        )
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

"The kernel's head code of `head`: instruction names, `h_void_n(N)` with its count."
function _hcode(head::_H)::Vector{String}
    def = LK.lookupProcedure(_H, sym_key(child(head, 1)), nchildren(head) - 1, UInt64(0))
    codes = LK.compileClause(def, head).codes
    out = String[]
    pc = LK.Code(codes, 1)
    while pc.pc <= length(codes)
        op = LK.decode(pc)
        name = lowercase(String(LK.codeTable(op).name))
        push!(out, op == LK.H_VOID_N ? "$name($(codes[pc.pc + 1]))" : name)
        pc = LK.stepPC(pc)
    end
    return out
end

"swipl's code for each of `heads`, from `vm_list/1`."
function _hswipl(heads::Vector{String}, names::Vector{String})::Vector{Vector{String}}
    mktempdir() do d
        f = joinpath(d, "hc.pl")
        write(
            f,
            ":- initialization(main, main).\nmain :-\n" *
            join(["    assertz($h)" for h in heads], ",\n") * ",\n" *
            "    forall(member(PI, [" * join(names, ",") *
            "]), (vm_list(PI), writeln('@@end'))).\n"
        )
        out = split(read(pipeline(`swipl -q $f`; stderr=devnull), String), '\n')
        res = Vector{String}[]
        cur = String[]
        inclause = false
        for l in out
            if startswith(l, "clause 1 (")
                inclause = true
                cur = String[]
            elseif l == "@@end"
                push!(res, cur)
                inclause = false
            elseif inclause &&
                (m = match(r"^\s+\d+ ([a-z_]+)(\((.*)\))?\s*$", l)) !== nothing
                name = m[1] == "h_smallint" ? "h_atom" : m[1]
                push!(cur, name == "h_void_n" ? "h_void_n($(m[3]))" : name)
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
    ours = [_hcode(h) for h in heads]
    # the sample exercises every merge: void runs, voids dropped before H_POP and I_EXITFACT
    @test any(c -> any(startswith("h_void_n"), c), ours)
    @test any(
        c -> any(i -> c[i] == "h_pop" && i > 1 && c[i - 1] != "h_pop", eachindex(c)), ours
    )
    @test any(c -> "h_rfunctor" in c, ours) && any(c -> "h_firstvar" in c, ours)
    @test any(c -> "h_var" in c, ours)
    # a hand-checked case: p(_,_,a) is h_void_n(2), h_atom, i_exitfact (swipl vm_list, LogicKernel#1)
    @test _hcode(_he(:p, [mk_var(_H, UInt64(1)), mk_var(_H, UInt64(2)), _hs(:a)])) ==
        ["h_void_n(2)", "h_atom", "i_exitfact"]
    if _HSWIPL !== nothing
        @testset "identical to swipl" begin
            texts = [_htext(h, _hcount!(Dict{UInt64, Int}(), h)) for h in heads]
            names = ["hc$k/$(nchildren(h) - 1)" for (k, h) in enumerate(heads)]
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
