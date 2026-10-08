# ORIGINAL: R1f's round-trip differential — the reader (R1d) and the writer (R1e) against swipl 10.1.16, both directions.
# test/core_text/test_roundtrip_swipl.jl — R1f's round trip (port_inventory row R1: "a LIVE round-trip
# differential against swipl, BOTH directions"):
#   * KERNEL WRITES, SWIPL READS: each term the kernel reads (or builds), written by the kernel
#     (term_to_atom/2's writing), read by swipl, is a variant of swipl's own read of the source;
#   * SWIPL WRITES, KERNEL READS: swipl's text of the same term, read by the kernel, is the kernel's
#     term (compared by an encoding that numbers variables by first occurrence);
#   over R1d's and R1e's hand corpora, the four bench programs' clauses (their source texts, cut
#   out by swipl's term positions) and random terms (R1e's generator).
#   * EXCLUSIONS, BY NAME AND COUNTED (user, 2026-10-07), each with its reason, lifted when it goes:
#     a FLOAT (the writer's floats are R1e's rest); upstream #11 (a prefix operator named by
#     letters before an atom starting with a Latin-1 letter: no space) and #12 (`'[]'(X)`,
#     `'()'(X)`: written as a list / a bracket). An excluded #11 or #12 term must FAIL the round
#     trip — so a fix upstream (or here) shows up as a stale exclusion, never silently. Texts
#     either side cannot read (the R1d corpus's syntax errors and refusals) are counted too, and a
#     text holding the character 0 (an atom cannot hold it: R1e's refusal).
using Test, LogicKernel, Random
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "text_corpora_testlib.jl"))
const _RT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_rts(x) = lk_sym(_RT, Symbol(x))
_rt_var() = mk_var(_RT, LK.fresh_var_keys!(1))

const _RT_SWIPL = Sys.which("swipl")
const _RT_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"
const _RT_GD = LK.PL_global_data{_RT}()
const _RT_LD = LK.PL_local_data{_RT}()

"The encoding of `t`: variables by first occurrence, atoms by codes (the read differential's)."
function _rt_enc(t::_RT, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        i === nothing && (push!(seen, var_key(t)); i=length(seen))
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tc_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tc_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        return "F" * string(reinterpret(UInt64, Float64(v)); base=16)
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tc_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_rt_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

"Run `name` on `args` through the query API: `(:ok, answers)`, `(:fail, _)`, `(:error, _)`, `(:notported, _)`."
function _rt_call(name::String, args::Vector{_RT})
    gd, ld = _RT_GD, _RT_LD
    proc = LK.isCurrentProcedure(sym_key(_rts(name)), length(args), LK.MODULE_system(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    for (i, x) in enumerate(args)
        ld.slots[a + i] = x
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    out = try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            (:ok, [LK.resolve_term(ld, ld.slots[a + i]) for i in 1:length(args)])
        elseif rc == LK.PL_S_EXCEPTION
            (:error, _RT[])
        else
            (:fail, _RT[])
        end
    catch e
        e isa LK.NotPortedError || rethrow()
        (:notported, _RT[])
    end
    out[1] === :notported || LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"The kernel's read of `text`, or `nothing`."
function _rt_read(text::String)::Union{Nothing, _RT}
    rc, ans = _rt_call("term_to_atom", _RT[_rt_var(), lk_gnd(_RT, text)])   # (a string: a text may hold 0)
    return rc === :ok ? ans[1] : nothing
end

"The kernel's text of `t` (term_to_atom/2), or `nothing` when the writer refuses it."
function _rt_write(t::_RT)::Union{Nothing, String}
    rc, ans = _rt_call("term_to_atom", _RT[t, _rt_var()])
    return rc === :ok ? sym_text(ans[2]) : nothing
end

# ── the named exclusions ────────────────────────────────────────────────────────────────────────

_rt_has(p, t) =
    p(t) || (kind(t) === EXPR && any(i -> _rt_has(p, child(t, i)), 1:nchildren(t)))

_rt_float(t) = kind(t) === GND && lk_value(t) isa AbstractFloat

# #11: a compound Op(A), `Op` a prefix operator whose name ends in a letter or digit, `A` an atom
# written unquoted whose first character is a Latin-1 letter (128-255) of a single-byte atom
function _rt_issue11(t)
    kind(t) === EXPR && nchildren(t) == 2 || return false
    op, a = child(t, 1), child(t, 2)
    (kind(op) === SYM && kind(a) === SYM && !is_reserved_symbol(a)) || return false
    found, _, _ = LK.currentOperator(_RT_GD, nothing, op, LK.OP_PREFIX)
    found || return false
    on, an = sym_text(op), sym_text(a)
    (isempty(on) || isempty(an)) && return false
    return LK.f_is_prolog_identifier_continue(Int(last(on))) &&
           0x80 <= Int(an[1]) <= 0xff &&
           all(c -> Int(c) <= 0xff, an) && LK.unquoted_atom(a)
end

# #12: a compound of one argument named by the text atom '[]' or '()'
_rt_issue12(t) =
    kind(t) === EXPR && nchildren(t) == 2 && kind(child(t, 1)) === SYM &&
    !is_reserved_symbol(child(t, 1)) && sym_text(child(t, 1)) in ("[]", "()")

# a text holding the character 0: term_to_atom/2's text is then an atom with a 0, which the term
# interface's atoms cannot hold (R1e's named refusal)
_rt_nul(t) =
    (
        kind(t) === GND && lk_value(t) isa AbstractString &&
        occursin('\0', String(lk_value(t)))
    ) ||
    (kind(t) === SYM && occursin('\0', sym_text(t)))

"The reason `t` is excluded, or `nothing`."
_rt_exclusion(t::_RT) =
    if _rt_has(_rt_float, t)
        :float
    elseif _rt_has(_rt_nul, t)
        :nul
    elseif _rt_has(_rt_issue11, t)
        :issue11
    elseif _rt_has(_rt_issue12, t)
        :issue12
    else
        nothing
    end

# ── swipl's side ────────────────────────────────────────────────────────────────────────────────

const _RT_DRIVER = raw"""
:- op(0, fx, $).
dec(a(Cs), A, _) :- !, atom_codes(A, Cs).
dec(nil, [], _) :- !.
dec(i(N), N, _) :- !.
dec(q(N, D), Q, _) :- !, Q is N rdiv D.
dec(s(Cs), S, _) :- !, string_codes(S, Cs).
dec(v(K), V, Vs) :- !, nth0(K, Vs, V).
dec(cn(As), T, Vs) :- !, decl(As, Xs, Vs), compound_name_arguments(T, [], Xs).
dec(c(Cs, As), T, Vs) :- atom_codes(N, Cs), decl(As, Xs, Vs), compound_name_arguments(T, N, Xs).
decl([], [], _).
decl([A|As], [X|Xs], Vs) :- dec(A, X, Vs), decl(As, Xs, Vs).
% swipl's text of T, then the verdict on the kernel's text Ks (`none`: the kernel wrote none)
out(T, Ks) :-
    term_to_atom(T, W), atom_codes(W, WC), format("~w ", [WC]),
    (   Ks == none -> write(none)
    ;   atom_codes(KA, Ks),
        (   catch(term_to_atom(T2, KA), _, fail)
        ->  ( T2 =@= T -> write(same) ; write(different) )
        ;   write(unreadable)
        )
    ), nl.
rt(Cs, Ks) :- atom_codes(A, Cs),
    ( catch(term_to_atom(T, A), _, fail) -> out(T, Ks) ; writeln('unreadable none') ).
re(Enc, Ks) :- length(Vs, 8), dec(Enc, T, Vs), out(T, Ks).
% the clauses of a source file, as their source texts (cut out by the term positions)
clauses(File) :-
    read_file_to_string(File, Str, []),
    setup_call_cleanup(open(File, read, In), clauses(In, Str), close(In)).
clauses(In, Str) :-
    read_term(In, T, [term_position(P)]),
    (   T == end_of_file
    ->  true
    ;   stream_position_data(char_count, P, B), character_count(In, E),
        L is E - B, sub_string(Str, B, L, _, S0), split_string(S0, "", " \t\n.", [S1]),
        string_codes(S1, Cs), format("~w~n", [Cs]),
        clauses(In, Str)
    ).
"""

function _rt_swipl(goals::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "rt.pl")
        write(f, _RT_DRIVER * ":- initialization((" * join(goals, ", ") * ", halt)).\n")
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

_rt_text(l::AbstractString) =
    String(Char.(parse.(Int, split(l[2:(end - 1)], ','; keepempty=false))))

"""
The round trip of `items` — each `(label, swipl goal prefix, kernel term or nothing)` — both
directions: `(passed, excluded::Dict, failures)`.
"""
function _rt_run(items)
    ktexts = [t === nothing ? nothing : _rt_write(t) for (_, _, t) in items]
    goals = [
        g * (k === nothing ? "none" : _tc_codes(k)) * ")" for
        ((_, g, _), k) in zip(items, ktexts)
    ]
    lines = _rt_swipl(goals)
    @test length(lines) == length(items)
    excluded = Dict{Symbol, Int}()
    stale = String[]
    bad = String[]
    passed = 0
    for (k, ((label, _, t), kt, line)) in enumerate(zip(items, ktexts, lines))
        sw, verdict = split(line, ' ')
        if t === nothing || sw == "unreadable"
            # unreadable on either side (the R1d corpus's errors and refusals): the read
            # differential compares those; both must agree that it is unreadable
            (t === nothing) == (sw == "unreadable") ||
                push!(bad, "$label: read by one side only (kernel $(t !== nothing))")
            excluded[:unreadable] = get(excluded, :unreadable, 0) + 1
            continue
        end
        reason = _rt_exclusion(t)
        # direction 2: swipl writes, the kernel reads
        back = _rt_read(_rt_text(sw))
        ok2 = back !== nothing && _rt_enc(back) == _rt_enc(t)
        ok1 = verdict == "same"
        if reason !== nothing
            excluded[reason] = get(excluded, reason, 0) + 1
            # an excluded defect must still break the trip (kernel writes, swipl reads)
            reason in (:issue11, :issue12) && ok1 &&
                push!(stale, "$label ($reason): passes now")
            continue
        end
        if ok1 && ok2
            passed += 1
        else
            push!(
                bad,
                "$label: kernel→swipl $(verdict), swipl→kernel $(ok2) — kernel $(repr(kt)), swipl $(repr(_rt_text(sw)))"
            )
        end
    end
    for b in bad[1:min(end, 10)]
        println(stderr, "  ROUND TRIP FAILS: ", b)
    end
    for s in stale
        println(stderr, "  STALE EXCLUSION: ", s)
    end
    @test isempty(bad)
    @test isempty(stale)
    return (passed, excluded)
end

if _RT_SWIPL !== nothing
    @testset "the hand corpora (R1d, R1e): both directions" begin
        texts = unique(vcat(_TR_CORPUS, _TW_CORPUS))
        items = [(repr(s), "rt(" * _tc_codes(s) * ", ", _rt_read(s)) for s in texts]
        passed, excluded = _rt_run(items)
        println(stderr, "  hand corpora: $passed round-tripped; excluded: $excluded")
        @test passed > 350
        @test get(excluded, :float, 0) > 0              # the corpora hold floats
        @test get(excluded, :issue11, 0) > 0            # `dynamic é` …
        @test get(excluded, :issue12, 0) > 0            # `'[]'(a)`, `'()'(a)`
    end

    @testset "the four bench programs' clauses: both directions" begin
        files = [
            joinpath(pkgdir(LK), "bench", "programs", p * ".pl")
            for p in ("nreverse", "derive", "qsort", "poly_10")
        ]
        texts = String[]
        for f in files
            lines = _rt_swipl(["clauses('$f')"])
            append!(texts, _rt_text.(lines))
        end
        @test length(texts) >= 30                      # (31 clauses and directives)
        # poly_10's operator first, as the file declares it
        @test _rt_call(
            "op", _RT[lk_gnd(_RT, Int64(700)), _rts("xfx"), _rts("less_than")]
        )[1] === :ok
        items = [
            (repr(s), "op(700, xfx, less_than), rt(" * _tc_codes(s) * ", ", _rt_read(s)) for
            s in texts
        ]
        passed, excluded = _rt_run(items)
        println(stderr, "  bench clauses: $passed round-tripped; excluded: $excluded")
        # THE CONDITION (decision 1b): no float in the four programs — and nothing else excluded
        @test isempty(excluded)
        @test passed == length(texts)
    end

    @testset "random terms (R1e's generator): both directions" begin
        rng = MersenneTwister(20261009)
        items = Tuple{String, String, _RT}[]
        for _ in 1:2000
            vars = _RT[_rt_var() for _ in 1:4]
            enc, t = _tc_gen(_RT, rng, 4, vars)
            push!(items, (enc, "re(" * enc * ", ", t))
        end
        passed, excluded = _rt_run(items)
        println(stderr, "  random terms: $passed round-tripped; excluded: $excluded")
        @test passed > 1800
        @test get(excluded, :float, 0) == 0             # the generator makes no float
    end
elseif _RT_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the round trip would be skipped"
    )
else
    @info "ROUND-TRIP DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "round trip skipped only where it is not required" begin
        @test !_RT_SWIPL_REQUIRED
    end
end
