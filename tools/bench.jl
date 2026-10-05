#!/usr/bin/env julia
# tools/bench.jl — the per-chunk PERFORMANCE REPORT: each ported primitive against swipl, on the
# same terms, then a profile of the worst.
#
#   julia --project=. tools/bench.jl                     # every case
#   julia --project=. tools/bench.jl variant             # the cases whose name contains "variant"
#   julia --project=. tools/bench.jl --profile=NAME      # profile case NAME (default: worst ratio)
#   julia --project=. tools/bench.jl --no-profile
#
# A STANDING STEP for every chunk, beside the JET/Aqua/AllocCheck gates (user, 2026-10-03) — a
# report, not a pass/fail gate: a new primitive gets a case here, with its swipl goal. It follows
# the workspace's measurement rules: THREE runs from ONE process, the minimum reported and the
# spread shown; every number beside its upstream pair, in µs; profile before attributing a cost.
#
# BenchmarkTools and Profile are not dependencies: they come from the global environment (see
# tools/repl.jl). swipl comes from PATH; without it the report has no upstream column.
using LogicKernel, BenchmarkTools, Profile, Printf
using LogicKernel:
    is_variant_ptr,
    pl_variant_sha1,
    pl_variant_hash,
    pl_term_hash,
    compareStandard,
    PL_local_data,
    pl_unify!,
    pl_unify_with_occurs_check!,
    Mark,
    Undo!,
    PL_global_data,
    lookupProcedure,
    setDynamicDefinition!,
    MODULE_user,
    compileClause,
    assertDefinition!,
    pl_clause!,
    CL_END

# ── fixtures: the same terms in Julia and in Prolog ─────────────────────────────────────────────
const BT = DefaultTerm
_a(x::Symbol) = sym_term(BT, x)
let n = UInt64(0)
    global _v() = mk_var(BT, n += 1)
end
"`f/2` tree of depth `d`, unshared, each leaf a fresh `leaf()` — Prolog `tree/3` below."
_tree(d::Int, leaf)::BT =
    d == 0 ? leaf() : mk_expr(BT, BT[_a(:f), _tree(d - 1, leaf), _tree(d - 1, leaf)])

const DEPTH = 12
const CELLS = 2^(DEPTH + 1) - 1                     # cells per tree: compounds + leaves
const G1, G2 = _tree(DEPTH, () -> _a(:a)), _tree(DEPTH, () -> _a(:a))   # ground
const V1, V2 = _tree(DEPTH, _v), _tree(DEPTH, _v)                       # 2^DEPTH variables each
const LD = PL_local_data{BT}()                                          # the unify cases' bindings

"One attempt, as a search makes it: mark, unify, undo — swipl's `forall/2` undoes the same way."
function _attempt(unify, a::BT, b::BT)::Bool
    m = Mark(LD)
    r = unify(LD, a, b)
    Undo!(LD, m)
    return r
end

"The same attempt with the undo in a `finally`, as the clause enumerations make it."
function _attempt_finally(unify, a::BT, b::BT)::Bool
    m = Mark(LD)
    try
        return unify(LD, a, b)
    finally
        Undo!(LD, m)
    end
end

const SMALL_A, SMALL_B = mk_expr(BT, BT[_a(:f), _v()]), mk_expr(BT, BT[_a(:f), _a(:a)])

# a dynamic predicate cp/2 of 1000 facts cp(I, a), for clause/2 — Prolog `cp/2` below
const CP_GD = PL_global_data{BT}()
const CP_USER = MODULE_user(CP_GD)
const CP_PROC = lookupProcedure(sym_key(_a(:cp)), 2, CP_USER)
const CP_DEF = CP_PROC.definition
setDynamicDefinition!(CP_DEF, true)                            # :- dynamic cp/2.
_cp_compile(h::BT) = compileClause(CP_GD, h, nothing, CP_PROC, CP_USER)
for i in 1:1000
    assertDefinition!(
        CP_GD, CP_DEF, _cp_compile(mk_expr(BT, BT[_a(:cp), gnd_term(BT, i), _a(:a)])),
        CL_END
    )
end
const CP_GOAL = mk_expr(BT, BT[_a(:cp), _v(), _v()])

# compiling: a fact `cp(7, a)`, and the head and variable analysis of nreverse's rule clause
# `app([H|T], L, [H|R]) :- app(T, L, R)` (V1 — its body code is V2, so Julia only, no swipl goal)
const CC_FACT = mk_expr(BT, BT[_a(:cp), gnd_term(BT, 7), _a(:a)])
_cons(h::BT, t::BT)::BT = mk_expr(BT, BT[_a(Symbol("[|]")), h, t])
const APP_H, APP_T, APP_L, APP_R = _v(), _v(), _v(), _v()
const APP_HEAD = mk_expr(BT, BT[_a(:app), _cons(APP_H, APP_T), APP_L, _cons(APP_H, APP_R)])
const APP_BODY = mk_expr(BT, BT[_a(:app), APP_T, APP_L, APP_R])
const APP_PROC = lookupProcedure(sym_key(_a(:app)), 3, CP_USER)
# the whole rule (V2): head, I_ENTER, the body's last call with its LCO block, I_EXIT

# the local stack (V3): `n` frames, each with a choice point, pushed and then popped by one lowering
const ST_LD = PL_local_data{BT}()
LogicKernel.ensureLocalSpace(ST_LD, 1 << 16)                               # grown once, up front
function _stack_frames(ld::PL_local_data{BT}, n::Int)::Nothing
    base = ld.lTop
    for _ in 1:n
        fr = LogicKernel.pushFrame!(ld, ld.lTop)
        ld.lTop = LogicKernel.argFrameP(ld.frames[fr].base, 3)
        LogicKernel.newChoice(ld, LogicKernel.CHP_CLAUSE, fr)
    end
    ld.BFR = 0
    LogicKernel.lowerLTop!(ld, base)
    return nothing
end

const PROLOG_FIXTURES = """
tree(0, Leaf, L) :- !, copy_term(Leaf, L).
tree(N, Leaf, f(A, B)) :- N1 is N-1, tree(N1, Leaf, A), tree(N1, Leaf, B).
fixtures(G1, G2, V1, V2) :-
    tree($DEPTH, a, G1), tree($DEPTH, a, G2), tree($DEPTH, _, V1), tree($DEPTH, _, V2),
    forall(between(1, 1000, I), assertz(cp(I, a))).
:- dynamic cp/2.
"""

# ── cases: (name, Julia thunk, the swipl goal over G1 G2 V1 V2) ─────────────────────────────────
const CASES = [
    ("compare ground", () -> compareStandard(G1, G2), "compare(_, G1, G2)"),
    ("=@= ground", () -> is_variant_ptr(G1, G2), "G1 =@= G2"),
    ("=@= vars", () -> is_variant_ptr(V1, V2), "V1 =@= V2"),
    ("term_hash ground", () -> pl_term_hash(G1), "term_hash(G1, _)"),
    ("variant_sha1 ground", () -> pl_variant_sha1(G1), "variant_sha1(G1, _)"),
    ("variant_sha1 vars", () -> pl_variant_sha1(V1), "variant_sha1(V1, _)"),
    ("variant_hash ground", () -> pl_variant_hash(G1), "variant_hash(G1, _)"),
    ("variant_hash vars", () -> pl_variant_hash(V1), "variant_hash(V1, _)"),
    ("= ground", () -> _attempt(pl_unify!, G1, G2), "G1 = G2"),
    ("= bind vars", () -> _attempt(pl_unify!, V1, G1), "V1 = G1"),
    ("= var-var", () -> _attempt(pl_unify!, V1, V2), "V1 = V2"),
    (
        "occurs-check bind vars",
        () -> _attempt(pl_unify_with_occurs_check!, V1, G1),
        "unify_with_occurs_check(V1, G1)"
    ),
    (
        "clause/2 1000 facts",
        () -> pl_clause!(CP_GD, LD, CP_DEF, CP_GOAL, _ -> true),
        "forall(clause(cp(_, _), true), true)"
    ),
    # Julia only (no swipl goal): compiling a fact, and a rule clause's head with its analysis
    ("compileClause fact", () -> _cp_compile(CC_FACT), ""),
    (
        "rule head + analysis",
        () -> LogicKernel._compile_clause_head!(
            CP_GD, LogicKernel.compileInfo{BT}(3, CP_USER, APP_PROC), APP_HEAD, APP_BODY
        ),
        ""
    ),
    (
        "compileClause rule",
        () -> compileClause(CP_GD, APP_HEAD, APP_BODY, APP_PROC, CP_USER),
        ""
    ),
    # Julia only (no swipl goal): the local stack's primitives
    ("1000 frames + choice points", () -> _stack_frames(ST_LD, 1000), ""),
    # Julia only (no swipl goal): what the `finally` around each enumeration step costs
    ("attempt f(X)=f(a)", () -> _attempt(pl_unify!, SMALL_A, SMALL_B), ""),
    ("attempt + finally", () -> _attempt_finally(pl_unify!, SMALL_A, SMALL_B), "")
]

# ── swipl: three timed runs of each goal, after calibrating the loop to ≥ 0.1 s ─────────────────
function swipl_times(cases)::Dict{String, NTuple{3, Float64}}
    out = Dict{String, NTuple{3, Float64}}()
    Sys.which("swipl") === nothing && return out
    prog = IOBuffer()
    print(prog, PROLOG_FIXTURES)
    print(
        prog,
        """
        time_s(Goal, N, T) :-
            garbage_collect, statistics(cputime, T0),
            forall(between(1, N, _), Goal), statistics(cputime, T1), T is T1 - T0.
        calib(Goal, N0, N) :-
            time_s(Goal, N0, T), ( T >= 0.1 -> N = N0 ; N1 is N0 * 2, calib(Goal, N1, N) ).
        bench(Name, Goal) :-
            calib(Goal, 1, N),
            time_s(Goal, N, T1), time_s(Goal, N, T2), time_s(Goal, N, T3),
            U1 is T1 / N * 1.0e6, U2 is T2 / N * 1.0e6, U3 is T3 / N * 1.0e6,
            format("~w\\t~6f\\t~6f\\t~6f~n", [Name, U1, U2, U3]).
        main :-
            fixtures(G1, G2, V1, V2),
        """
    )
    timed = [(name, goal) for (name, _, goal) in cases if !isempty(goal)]
    isempty(timed) && return out
    for (i, (name, goal)) in enumerate(timed)
        sep = i == length(timed) ? ".\n" : ",\n"
        print(prog, "    bench('", name, "', (", goal, "))", sep)
    end
    print(prog, ":- initialization((main, halt)).\n")
    text = mktempdir() do d
        f = joinpath(d, "bench.pl")
        write(f, String(take!(prog)))
        read(`swipl -q $f`, String)
    end
    for l in eachline(IOBuffer(text))
        p = split(l, '\t')
        length(p) == 4 || error("tools/bench.jl: unexpected swipl output: $l")
        out[p[1]] = (parse(Float64, p[2]), parse(Float64, p[3]), parse(Float64, p[4]))
    end
    return out
end

# ── Julia: three BenchmarkTools runs of each thunk, median of each ──────────────────────────────
function julia_times(f)
    f()
    ts = Float64[]
    local b
    for _ in 1:3
        b = @benchmark $f() seconds = 1 evals = 1
        push!(ts, median(b).time / 1e3)
    end
    return (ts[1], ts[2], ts[3]), b.allocs, b.memory
end

function main(args)
    filt = filter(a -> !startswith(a, "--"), args)
    cases = [c for c in CASES if isempty(filt) || any(f -> occursin(f, c[1]), filt)]
    isempty(cases) && error("tools/bench.jl: no case matches $(filt)")
    k = findfirst(a -> startswith(a, "--profile="), args)
    prof = k === nothing ? "" : String(split(args[k], '='; limit=2)[2])
    sw = swipl_times(cases)
    swv = isempty(sw) ? "no swipl on PATH" : strip(read(`swipl --version`, String))
    println("LogicKernel bench — julia $(VERSION), pid $(getpid()), $swv")
    @printf("load average %.2f; fixtures: f/2 trees of %d cells\n", Sys.loadavg()[1], CELLS)
    @printf(
        "%-22s %-26s %-26s %8s %8s %9s\n", "case", "LogicKernel µs (3 runs)",
        "swipl µs (3 runs)", "LK/swipl", "allocs", "bytes"
    )
    ratios = Dict{String, Float64}()
    for (name, f, _) in cases
        jt, allocs, bytes = julia_times(f)
        st = get(sw, name, nothing)
        js = join((@sprintf("%.2f", t) for t in jt), " ")
        ss = st === nothing ? "—" : join((@sprintf("%.2f", t) for t in st), " ")
        r = st === nothing ? NaN : minimum(jt) / minimum(st)
        ratios[name] = r
        @printf("%-22s %-26s %-26s %8.2f %8d %9d", name, js, ss, r, allocs, bytes)
        spread = maximum(jt) / minimum(jt)
        spread > 1.15 && @printf("   ⚠ LK runs spread %.0f%%", (spread - 1) * 100)
        println()
    end
    "--no-profile" in args && return nothing
    target = prof
    if isempty(target)
        known = filter(p -> !isnan(p[2]), collect(ratios))
        isempty(known) && return nothing
        target = first(sort(known; by=p -> -p[2]))[1]
    end
    i = findfirst(c -> c[1] == target, cases)
    i === nothing && error("tools/bench.jl: --profile=$target names no case run")
    f = cases[i][2]
    Profile.clear()
    t0 = time()
    Profile.@profile while time() - t0 < 2.0
        f()
    end
    buf = IOBuffer()
    Profile.print(
        IOContext(buf, :displaysize => (1000, 200)); format=:flat, sortedby=:count, C=false
    )
    rows = Tuple{Int, Int, String}[]                # (count, self, line)
    for l in eachline(IOBuffer(take!(buf)))
        p = split(l)
        length(p) >= 4 || continue
        c, o = tryparse(Int, p[1]), tryparse(Int, p[2])
        (c === nothing || o === nothing) && continue
        # LogicKernel's frames, and any frame with SELF time except the idle profiler task's
        (occursin("@LogicKernel", l) || (o > 0 && !occursin("task.jl", l))) || continue
        push!(rows, (c, o, l))
    end
    sort!(rows; by=r -> -r[1])
    println(
        "\n── profile: $target (flat; LogicKernel frames + frames with self time, top 25) ──"
    )
    println(" Count  Self  File:Line Function")
    for (_, _, l) in first(rows, 25)
        println(l)
    end
    return nothing
end

main(ARGS)
