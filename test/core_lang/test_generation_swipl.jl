# ORIGINAL: a differential of clause/2 and retract/1 against swipl at the pin; test_dbg1_swipl.jl's harness (a program, a .out of swipl's answers, a live check).
# UPSTREAM: pl-comp.c clause/2 (setGenerationFrameVal(environment_frame, dref->generation), :7413) and pl-proc.c retract/1 (:3180), swipl-devel 18168e62.
# test/core_lang/test_generation_swipl.jl — ASSERT-GEN (audit D-0713 (3)): clause/2 and retract/1 store the predicate access object's generation in
# the frame; upstream does not compare it with the generation the frame took at the call. The kernel had `@assert dref.generation ==
# generationFrame(frame)` at both sites (a probe showed it fires for clause/2 on a predicate declared `autoload/2`, whose library `trapUndefined`
# loads between the call and the access object); it is replaced by the store alone. The rows:
#   * test_generation_swipl.pl holds the cases `p1aN`..`p1cN` (a: autoload in clause/2 and retract/1, b: a wakeup between the call and the first
#     clause, c: an erase listener); the kernel consults the program afresh for EVERY case (the cases assert foo/1) and enumerates the case's
#     answers (at most 20), the answer being the string the program printed;
#   * test_generation_swipl.out holds swipl 10.1.20's answers, `id<TAB>answer`, two byte-identical runs of the driver below; when `swipl` is on PATH
#     the .out is checked against a live run as well, so it cannot go stale;
#   * the cases whose comment starts with [autoload-decl] run with `:- autoload(library(lists), [append/3, last/2, subtract/3]).` in front of the
#     program, on both sides (the declaration is what makes clause/2 autoload in swipl).
# A row that RAISES (a Julia exception out of the case) is a failed row, not a stopped file: the helper hands the exception back.
# If a row of the autoload group differs from swipl's answer, that is a DIFFERENCE of the autoloader (R2 owner: AUTOLOAD1 / LB5, library(lists) through
# the library index), not of this step: the row stays an `@test` with swipl's answer, and the owner flips the failing ids to `@test_broken` with its name.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — clause/2 and retract/1 (src/pl-comp.jl, src/pl-proc.jl) built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

const _GN_PL = joinpath(@__DIR__, "test_generation_swipl.pl")
const _GN_OUT = joinpath(@__DIR__, "test_generation_swipl.out")
const _GN_AUTO = ":- autoload(library(lists), [append/3, last/2, subtract/3]).\n"

# the cases, in the order of the program; the ones that run with the declaration (ONE extractor for the kernel's side and swipl's)
_gn_ids() = [String(m[1]) for m in eachmatch(r"^(p1[a-z]+\d+)\(R\) :-"m, read(_GN_PL, String))]
_gn_autoids() =
    [String(m[1]) for m in eachmatch(r"^%% (p1[a-z]+\d+): \[autoload-decl\]"m, read(_GN_PL, String))]
_gn_program(id::String) = (id in _gn_autoids() ? _GN_AUTO : "") * read(_GN_PL, String)
function _gn_pins()::Dict{String, String}
    d = Dict{String, String}()
    for l in eachline(_GN_OUT)
        id, ans = split(l, '\t'; limit=2)
        d[String(id)] = String(ans)
    end
    return d
end

_gn_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
# an answer that is not a string, as test_dbg1_swipl.jl's `enc` writes it
function _gn_enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _gn_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _gn_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _gn_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_gn_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end
# the text of an answer: the string the program printed, else `enc:` of the term
function _gn_text(t::T)::String where {T}
    if kind(t) === GND
        v = lk_value(t)
        v isa AbstractString && return String(v)
    end
    return "enc:" * _gn_enc(t)
end

# one case on a FRESH database: the answers joined by " ;; ", `no` for none; a Julia exception is HANDED BACK (the row fails, the file goes on)
function gn_ask(::Type{T}, id::String)::Union{String, Exception} where {T}
    try
        f = joinpath(mktempdir(), "generation.pl")
        write(f, _gn_program(id))
        gd = LK.PL_global_data{T}()
        ld = LK.PL_local_data{T}(gd)
        st, ball = LK.load_file!(gd, ld, f)
        st === :ok || return "the program did not load: $st " * (ball === nothing ? "" : _gn_enc(ball::T))
        proc = LK.isCurrentProcedure(sym_key(lk_sym(T, Symbol(id))), 1, LK.MODULE_user(gd))
        (proc === nothing || !LK.isDefinedProcedure(gd, proc)) &&
            return "the case predicate $id/1 is not defined"
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 20
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(sols, _gn_text(lk_answer(ld, a)))
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                ex = LK.PL_exception(ld, qid)
                push!(sols, "query exception " * (ex == 0 ? "?" : _gn_enc(lk_answer(ld, ex))))
                break
            else
                break
            end
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        return isempty(sols) ? "no" : join(sols, " ;; ")
    catch e
        return e isa Exception ? e : ErrorException(string(e))
    end
end

# swipl's side: the driver of one case in one process (the .out is its output)
const _GN_DRIVER = raw"""
pr_main(Id) :-
    catch(( findall(R, limit(20, call(Id, R)), Rs),
            (   Rs == [] -> Out = "no" ;   atomic_list_concat(Rs, ' ;; ', Out) ) ),
          E,
          format(string(Out), "uncaught ~q", [E])),
    format("~w~n", [Out]).
"""
function gn_swipl(swipl::String, id::String)::String
    return mktempdir() do d
        drv = joinpath(d, "drv.pl")
        prog = joinpath(d, "prog.pl")
        write(drv, _GN_DRIVER)
        write(prog, _gn_program(id))
        goal = "consult(['$prog','$drv']), pr_main($id)"
        out = read(
            pipeline(
                addenv(`$swipl -q -g $goal -t halt`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull
            ),
            String,
        )
        return chomp(out)
    end
end

@testset "ASSERT-GEN: clause/2 and retract/1 store the access object's generation (pl-comp.c:7413, pl-proc.c:3180) == swipl's answers" begin
    ids = _gn_ids()
    auto = _gn_autoids()
    pins = _gn_pins()
    # not a vacuous agreement: a pin per case, the autoload group is the eight declared cases, and the pins carry the evidence
    @test length(ids) == 38 && length(unique(ids)) == length(ids)
    @test sort(collect(keys(pins))) == sort(ids)
    @test auto == ["p1a$i" for i in 12:19]
    @test count(id -> occursin("append(", pins[id]), auto) >= 6        # swipl loads library(lists) inside clause/2 and answers its clauses
    @test pins["p1b1"] == "[1,2,3,9]" && pins["p1b2"] == "[1,3]" && pins["p1b13"] == "[2-true,3-true,9-true]"   # the wakeup's assert/retract is seen

    res = Dict{String, Union{String, Exception}}(id => gn_ask(_TL, id) for id in ids)

    # THE ASSERT IS GONE: no case raises, and above all not clause/2 on a predicate declared autoload/2 (the loaded library moved the generation
    # between the call and the access object; the old `@assert` raised AssertionError there)
    @test all(id -> !(res[id] isa Exception), auto)
    @test all(id -> !(res[id] isa Exception), ids)
    # the kernel's answer text is swipl's, case by case (one extractor over both: the strings the program printed)
    for id in ids
        @test (id, res[id]) == (id, pins[id])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "ASSERT-GEN DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        for id in ids
            @test (id, gn_swipl(swipl, id)) == (id, pins[id])           # the .out is swipl's, still
        end
    end
end
