# ORIGINAL: the nightly differential fuzzer (audit D-0125 stream a, D-0127 item 3) — no swipl-devel counterpart.
# tools/fuzz.jl — a random differential, the kernel against the pinned swipl, for CI's nightly job
# (.github/workflows/fuzz.yml) and by hand:
#
#   julia --project=. tools/fuzz.jl [FIRST_SEED [COUNT [OUTDIR [CASES]]]]     # 5000 300 fuzz-out 40
#
# One seed = one program of CASES predicates t0..tN (each `tI(R)` runs one generated goal under catch/3 and
# binds R). The kernel consults the program (LK.load_file!) and enumerates every solution of every tI/1;
# swipl does the same through the driver below; the answers are compared line by line (variables by first
# occurrence). A seed whose lines differ FAILS the run (exit 1): its program and both answers are kept under
# OUTDIR/seed_<n>/, the seed and the first lines are printed, and a `::error` annotation names the seed.
# Exit 2: the oracle is missing or answered nothing (a comparison of nothing with nothing proves nothing).
#
# THE GENERATOR AVOIDS what the kernel does not have yet — retract/1, library(lists) (A-0082; sort/4,
# acyclic_term/1, cyclic_term/1 and retractall/1 came back 2026-10-24): each is a finding of its own, not a nightly failure; remove an avoidance when the
# predicate is ported. A shift count is small (a huge one is group F's InexactError finding, now ported:
# test/core_lang/test_arith_swipl.jl `_A_TOOBIG`). FUZZ_INJECT=1 corrupts one kernel line (the run MUST exit 1:
# tools/test_fuzz.sh).
using Random, LogicKernel
const LK = LogicKernel
const ROOT = dirname(@__DIR__)
const FIRST_SEED = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 5000
const NSEEDS = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 300
const OUTDIR = length(ARGS) >= 3 ? ARGS[3] : "fuzz-out"
const NCASES = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : 40
include(joinpath(ROOT, "test", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_TL, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# error contexts the kernel and swipl name differently for the same call are NOT normalised here: they are mismatches.
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                # a term the kernel cannot export (a cycle) is a line of its own, never a throw that ends the file
                push!(
                    sols,
                    try
                        enc(mk_expr(_TL, _TL[_tls(name), lk_answers(ld, (a:a)...)...]))
                    catch e
                        "export-error " * first(sprint(showerror, e), 80)
                    end
                )
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# ── generator: tools/fuzz_gen.jl (module FuzzGen) ───────────────────────────────────────────────────
include(joinpath(@__DIR__, "fuzz_gen.jl"))
using .FuzzGen: program

# ── driver ──────────────────────────────────────────────────────────────────────────────────────

"The (1-based) line numbers on which the two answers differ; a line one side lacks differs."
function mismatching_lines(sw::Vector{String}, kl::Vector{String})::Vector{Int}
    return [
        i for
        i in 1:max(length(sw), length(kl)) if get(sw, i, nothing) != get(kl, i, nothing)
    ]
end

function main()::Int
    Sys.which("swipl") === nothing &&
        (println(stderr, "fuzz: no swipl on PATH (the oracle)"); return 2)
    mkpath(OUTDIR)
    bad_seeds = Int[]
    cases = 0
    for seed in FIRST_SEED:(FIRST_SEED + NSEEDS - 1)
        text, names = program(seed, NCASES)
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = try
            swipl_lines(f, names)
        catch e
            ["swipl failed: $(sprint(showerror, e))"]
        end
        length(sw) == length(names) + 1 || begin    # `ok` + one line per predicate: swipl answered it all
            println(
                stderr,
                "fuzz: swipl's answer for seed $seed has $(length(sw)) lines, want $(length(names) + 1)"
            )
            return 2
        end
        kl = try
            kernel_lines(f, names)
        catch e
            ["kernel threw: $(sprint(showerror, e))"]
        end
        get(ENV, "FUZZ_INJECT", "") == "1" && length(kl) >= 2 && (kl[2] *= " INJECTED")
        cases += length(names)
        bad = mismatching_lines(sw, kl)
        if !isempty(bad)
            push!(bad_seeds, seed)
            d = joinpath(OUTDIR, "seed_$seed")
            mkpath(d)
            write(joinpath(d, "program.pl"), text)
            write(joinpath(d, "swipl.txt"), join(sw, "\n") * "\n")
            write(joinpath(d, "kernel.txt"), join(kl, "\n") * "\n")
            write(joinpath(d, "mismatching_lines.txt"), join(bad, "\n") * "\n")
            println(
                "::error title=fuzz mismatch, seed $seed::lines $(join(first(bad, 5), ", ")) differ (swipl: $(first(get(sw, bad[1], ""), 100)) | kernel: $(first(get(kl, bad[1], ""), 100)))"
            )
            println(stderr, "fuzz: MISMATCH seed $seed, $(length(bad)) line(s); kept in $d")
        end
    end
    println(
        "fuzz: $NSEEDS seeds from $FIRST_SEED, $cases cases, $(length(bad_seeds)) seed(s) with a mismatch" *
        (isempty(bad_seeds) ? "" : ": " * join(bad_seeds, " "))
    )
    return isempty(bad_seeds) ? 0 : 1
end

exit(main())
