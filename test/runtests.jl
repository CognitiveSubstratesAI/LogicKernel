# ORIGINAL: the suite driver Julia's Pkg.test requires (swipl-devel's counterpart is tests/test.pl, a Prolog driver).
# test/runtests.jl — LogicKernel's suite.
#
# DISCOVERY, NOT A LIST. Every `test_*.jl` anywhere under `test/` runs; nothing has to be registered
# here, so a new subsystem's tests cannot be written and then silently never run. Other `.jl` files
# (helpers, fixtures, the conformance suite's library files) are NOT run on their own.
#
# ONE FRESH MODULE PER FILE. A suite that `include`s every file into one module lets two files'
# helpers collide by name — the later definition silently replaces the earlier, and a file passes
# alone and fails in the suite — a failure that is expensive to diagnose because every theory about
# the code is wrong; the cause is the suite's shape. Each file therefore starts with its own
# `using Test, LogicKernel` and owns its names.
#
# THE INERT GUARD runs last: a leaf testset that passed zero assertions fails the suite, so a test
# that degraded to skips — an absent `swipl` for the compare/3 differential, say — cannot read as green.
#
# TERM-GENERIC FILES RUN ONCE PER TERM IMPLEMENTATION. A file that includes test/term_under_test.jl
# reaches the kernel only through the term interface, so it runs on the reference type AND on the
# deliberately different second implementation, plain and sharing ground compounds
# (`LK_TERM_IMPLS`); those runs' test sets are named `<file> [alt]` and `<file> [alt_interned]`.
#
# UNITS, AND THREE WAYS TO RUN THEM. A unit is one file on one term implementation. With no
# environment (CI, `Pkg.test`) every unit runs here, in order. tools/run_tests.sh runs the suite as
# SHARDS (user, 2026-10-03): several fresh processes that CLAIM units from a queue they share — an
# atomic `mkdir` per unit in LOGICKERNEL_SHARD_DIR, a directory made fresh for each run — costliest
# first, so a shard that finishes early takes the next unit and the shards balance themselves. Each
# shard LOGS the exact sequence it ran (`seq_<id>.tsv`), and LOGICKERNEL_REPLAY=<that file> runs the
# same sequence again, in order, in one process: a failure that depends on what ran before it is
# reproducible. The checks that span every unit — each claimed exactly once, the second
# implementation exercised — are the coordinator's (tools/run_tests.sh), from the files written here.
using Test
using LogicKernel

include("inert_testset_guard.jl")
include("term_under_test.jl")         # LK_TERM_IMPLS — the one list of implementations

const LK_TEST_DIR = @__DIR__
const LK_TEST_FILES = sort!([
    joinpath(dir, f) for (dir, _, files) in walkdir(LK_TEST_DIR) for
    f in files if startswith(f, "test_") && endswith(f, ".jl")
])
const LK_TERM_GENERIC_RX = r"^include\(joinpath\(@__DIR__, \"\.\.\", \"term_under_test\.jl\"\)\)"m
lk_term_generic(f::String)::Bool = occursin(LK_TERM_GENERIC_RX, read(f, String))

# ── the units ────────────────────────────────────────────────────────────────────────────────────
"Every unit, `(file, implementation, label)`, in the order of discovery."
const LK_UNITS = [
    (
        f,
        impl,
        if impl in ("", "reference")
            relpath(f, LK_TEST_DIR)
        else
            "$(relpath(f, LK_TEST_DIR)) [$impl]"
        end
    )
    for f in LK_TEST_FILES for impl in (lk_term_generic(f) ? LK_TERM_IMPLS : ("",))
]
const LK_SHARD_DIR = get(ENV, "LOGICKERNEL_SHARD_DIR", "")
const LK_SHARD_ID = get(ENV, "LOGICKERNEL_SHARD_ID", "")
const LK_SHARD = !isempty(LK_SHARD_DIR)
const LK_REPLAY = get(ENV, "LOGICKERNEL_REPLAY", "")
# Costliest first, for the shards' queue: the static-analysis gate (JET, AllocCheck), then the live
# swipl differentials, then the rest — measured costs replace this order once the [unit] timings exist.
_lk_cost_rank(label) =
    occursin("static_analysis", label) ? 0 : (occursin("_swipl", label) ? 1 : 2)
"The units this process runs, in its order."
const LK_RUN = if LK_SHARD
    sort(LK_UNITS; by=u -> _lk_cost_rank(u[3]))
elseif !isempty(LK_REPLAY)
    let byname = Dict(u[3] => u for u in LK_UNITS)
        [byname[split(l, '\t')[2]] for l in eachline(LK_REPLAY) if !isempty(strip(l))]
    end
else
    LK_UNITS
end
"Claim unit `i` of the shards' queue: an atomic `mkdir`, so exactly one shard gets each unit."
lk_claim(i::Int)::Bool =
    try
        mkdir(joinpath(LK_SHARD_DIR, "claims", string(i)))
        true
    catch
        false
    end
if LK_SHARD
    write(joinpath(LK_SHARD_DIR, "units_total"), string(length(LK_RUN)))
    println("  shard ", LK_SHARD_ID, " of a run with ", length(LK_RUN), " units")
elseif !isempty(LK_REPLAY)
    println("  REPLAY of ", LK_REPLAY, ": ", length(LK_RUN), " units, in order")
end

# Visibility: what each subsystem folder contributes, zeros included.
for d in sort!(filter(isdir, readdir(LK_TEST_DIR; join=true)))
    n = count(f -> startswith(f, d * "/"), LK_TEST_FILES)
    println("  test/", basename(d), ": ", n, " file(s)")
end

# THE ROOT TEST SET IS OPENED BY HAND, not with `@testset`, so its results can be written as JUnit
# XML (Codecov Test Analytics) EVEN WHEN SOMETHING FAILED — a top-level `@testset` throws before
# anyone can read its tree. `Test.finish` below then prints the summary and throws exactly as before.
include("junit_report.jl")
const LK_JUNIT = get(ENV, "LOGICKERNEL_JUNIT", "")
const LK_TS = Test.DefaultTestSet("LogicKernel")
# Julia 1.13's test-set stack is a ScopedValue: `Test.@with_testset` (there is no push_testset).
Test.@with_testset LK_TS begin
    # Positive control on discovery itself: an empty file list would make every check below vacuous.
    @testset "discovery found the package-level files" begin
        rel = [relpath(f, LK_TEST_DIR) for f in LK_TEST_FILES]
        @test "test_package.jl" in rel
        @test "test_lint_globals.jl" in rel
    end
    # …and on the term-generic files: the conformance suite itself must be one of them, or the
    # second implementation is never checked against it.
    @testset "discovery found the term-generic files" begin
        generic = [relpath(f, LK_TEST_DIR) for f in LK_TEST_FILES if lk_term_generic(f)]
        @test "core_lang/test_term_interface.jl" in generic
        @test "core_lang/test_unify.jl" in generic
        @test length(generic) >= 20
        @test length(LK_TERM_IMPLS) >= 3
    end
    # How much of each unit is COMPILATION (user, 2026-10-04: "are we using Julia multi
    # threading"): what one process running the units as threads would pay ONCE, and three cold
    # processes pay three times. Julia's own counter, as `@time` reports it.
    Base.cumulative_compile_timing(true)
    for (i, (f, impl, label)) in enumerate(LK_RUN)
        LK_SHARD && !lk_claim(i) && continue                   # another shard took it
        t0 = time_ns()
        c0 = Base.cumulative_compile_time_ns()[1]
        uts = @testset "$label" begin
            # A `module … end` expression, not `Module(name)`: only the former defines the
            # module's own `include`/`eval`, which a test file calling `include(...)` needs.
            name = Symbol("LKTest_", replace(label, r"[^A-Za-z0-9]" => "_"))
            m = Core.eval(Main, Expr(:module, true, name, Expr(:block)))
            if isempty(impl)
                Base.include(m, f)
            else
                withenv(() -> Base.include(m, f), "LOGICKERNEL_TERM" => impl)
            end
        end
        secs = (time_ns() - t0) / 1e9
        csecs = (Base.cumulative_compile_time_ns()[1] - c0) / 1e9
        # …and what the unit ASSERTED, so two runs compare unit by unit, not by a total that two
        # compensating changes could keep equal (user, 2026-10-04: "pass identically before and after")
        tc = Test.get_test_counts(uts)
        npass, nbroken = tc.passes + tc.cumulative_passes, tc.broken + tc.cumulative_broken
        println(
            "  [unit] ", label, "  ", round(secs; digits=1), " s  (compiling ",
            round(csecs; digits=1), " s)  ", npass, " passed, ", nbroken, " broken"
        )
        LK_SHARD && open(
            io -> println(
                io,
                i,
                '\t',
                label,
                '\t',
                round(secs; digits=2),
                '\t',
                round(csecs; digits=2),
                '\t',
                npass,
                '\t',
                nbroken
            ),
            joinpath(LK_SHARD_DIR, "seq_$LK_SHARD_ID.tsv"), "a"
        )
    end
    # …and the `[alt]` and `[alt_interned]` runs really ran their own types: each counts the
    # compounds it builds, so a selector that fell back to another type — running it twice, green —
    # leaves a count at zero. And the interned type really SHARED: separately built ground twins
    # came back as one object, or the third run proves nothing about sharing. A shard ran only some
    # units, so it writes its counts and the coordinator checks their SUM.
    s = Main.LKAltTerm.alt_stats()
    println("  AltTerm: ", s)            # how much sharing the [alt_interned] runs exercised
    if LK_SHARD
        write(joinpath(LK_SHARD_DIR, "stats_$LK_SHARD_ID"),
            "$(s.compounds_plain) $(s.compounds_interned) $(s.shared)\n")
    elseif isempty(LK_REPLAY)
        @testset "the second implementation was exercised, plain and sharing" begin
            @test s.compounds_plain > 0
            @test s.compounds_interned > 0
            @test s.shared > 0
        end
    end
end

isempty(LK_JUNIT) || println("  JUnit report: ", write_junit(LK_TS, LK_JUNIT))
Test.finish(LK_TS)                    # prints the summary; throws if anything failed or errored
assert_no_inert_testsets(LK_TS)
