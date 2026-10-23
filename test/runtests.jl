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
# THE GATE SPLIT (user, 2026-10-06; test/term_scope.jl): with LOGICKERNEL_TERM_TYPES=chunk — what
# tools/run_tests.sh sets for a chunk's local gate when no trigger changed — a file declared
# REFERENCE runs on the reference implementation only. Without it (CI, `Pkg.test`), every unit runs.
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
include("term_scope.jl")              # the gate split's declarations (ONE extractor)
include("ci_slices.jl")               # CI's file groups and static-analysis shards

const LK_TEST_DIR = @__DIR__
const LK_TEST_FILES = lk_test_files(LK_TEST_DIR)
"Each term-generic file's declaration (test/term_scope.jl); a missing or bad one stops the suite."
const LK_TERM_SCOPES = lk_term_scopes(LK_TEST_DIR)
"`all` (every unit: CI, a milestone, a trigger changed) or `chunk` (tools/run_tests.sh)."
const LK_TERM_TYPES = get(ENV, "LOGICKERNEL_TERM_TYPES", "all")

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
    for f in LK_TEST_FILES for impl in (
        if haskey(LK_TERM_SCOPES, f)
            lk_units_impls(LK_TERM_SCOPES[f][1], LK_TERM_TYPES, LK_TERM_IMPLS)
        else
            ("",)
        end
    )
]
const LK_SHARD_DIR = get(ENV, "LOGICKERNEL_SHARD_DIR", "")
const LK_SHARD_ID = get(ENV, "LOGICKERNEL_SHARD_ID", "")
const LK_SHARD = !isempty(LK_SHARD_DIR)
const LK_REPLAY = get(ENV, "LOGICKERNEL_REPLAY", "")
# ONE TERM TYPE PER PROCESS (CI's evidence.yml; user, 2026-10-13): LOGICKERNEL_TERM_ONLY=<impl> runs
# that implementation's units alone — the files that are not term-generic go with the reference —
# so three CI jobs run the suite in parallel. Each job writes the units it ran and the full list
# (LOGICKERNEL_UNITS_OUT), and tools/evidence_ci.py checks that the three lists PARTITION the full
# one: a filter that dropped a unit must not read as green.
const LK_TERM_ONLY = get(ENV, "LOGICKERNEL_TERM_ONLY", "")
isempty(LK_TERM_ONLY) || LK_TERM_ONLY in LK_TERM_IMPLS ||
    error(
        "LOGICKERNEL_TERM_ONLY=$(repr(LK_TERM_ONLY)): expected one of $(join(LK_TERM_IMPLS, ", "))"
    )
isempty(LK_TERM_ONLY) || (!LK_SHARD && isempty(LK_REPLAY) && LK_TERM_TYPES == "all") ||
    error(
        "LOGICKERNEL_TERM_ONLY is for a whole run on every term type: not with shards, a replay or LOGICKERNEL_TERM_TYPES=chunk"
    )
"Whether a unit of implementation `impl` (`\"\"`: not term-generic) runs in this process."
lk_term_only(impl)::Bool =
    isempty(LK_TERM_ONLY) || impl == LK_TERM_ONLY ||
    (isempty(impl) && LK_TERM_ONLY == first(LK_TERM_IMPLS))
# THE CI SLICES (D-0059, 2026-10-20; test/ci_slices.jl): LOGICKERNEL_FILE_GROUP=k/G runs the files of
# group k — every unit of each, or under LOGICKERNEL_TERM_ONLY that type's — and never the static
# analysis, which runs in LOGICKERNEL_SA_SHARD=k/N jobs of its own: such a process runs that ONE unit
# (its k-th slice, test/static_analysis_body.jl). Each job writes the units it ran with their pass
# counts (LOGICKERNEL_UNITS_OUT), and tools/evidence_ci.py checks that the jobs PARTITION the suite.
const LK_SA_FILE = joinpath(LK_TEST_DIR, "test_static_analysis.jl")
const LK_GROUPED = !isempty(get(ENV, "LOGICKERNEL_FILE_GROUP", ""))
const LK_FILE_GROUP = lk_slice("LOGICKERNEL_FILE_GROUP")
const LK_SA_ONLY = !isempty(get(ENV, "LOGICKERNEL_SA_SHARD", ""))
const LK_SLICED = LK_GROUPED || LK_SA_ONLY
LK_SLICED && (LK_SHARD || !isempty(LK_REPLAY) || LK_TERM_TYPES != "all") &&
    error(
        "LOGICKERNEL_FILE_GROUP / LOGICKERNEL_SA_SHARD slice a whole CI run: not with shards, a replay or LOGICKERNEL_TERM_TYPES=chunk"
    )
LK_GROUPED && LK_SA_ONLY &&
    error(
        "LOGICKERNEL_FILE_GROUP and LOGICKERNEL_SA_SHARD together: a job is one or the other"
    )
LK_SA_ONLY && !(LK_TERM_ONLY in ("", first(LK_TERM_IMPLS))) &&
    error(
        "LOGICKERNEL_SA_SHARD with LOGICKERNEL_TERM_ONLY=$LK_TERM_ONLY: the static analysis is the reference type's"
    )
"Each test file's CI group (all but the static analysis), the same in every job."
const LK_GROUP_OF = lk_file_groups(
    [relpath(f, LK_TEST_DIR) for f in LK_TEST_FILES if f != LK_SA_FILE], LK_FILE_GROUP[2],
    lk_unit_costs(joinpath(LK_TEST_DIR, "unit_costs.tsv"))
)
"Whether file `f`'s units are in this process's slice."
lk_in_slice_file(f)::Bool =
    if LK_SA_ONLY
        f == LK_SA_FILE
    elseif LK_GROUPED
        f != LK_SA_FILE && LK_GROUP_OF[relpath(f, LK_TEST_DIR)] == LK_FILE_GROUP[1]
    else
        true
    end
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
    filter(u -> lk_term_only(u[2]) && lk_in_slice_file(u[1]), LK_UNITS)
end
"Claim unit `i` of the shards' queue: an atomic `mkdir`, so exactly one shard gets each unit."
lk_claim(i::Int)::Bool =
    try
        mkdir(joinpath(LK_SHARD_DIR, "claims", string(i)))
        true
    catch
        false
    end
let nall = count(v -> v[1] === :all, values(LK_TERM_SCOPES))
    println(
        "  term types: ",
        LK_TERM_TYPES,
        " — ",
        if LK_TERM_TYPES == "all"
            "every term-generic file on every implementation"
        else
            "$nall of $(length(LK_TERM_SCOPES)) term-generic files on every implementation, the rest on the reference"
        end
    )
end
if LK_SHARD
    write(joinpath(LK_SHARD_DIR, "units_total"), string(length(LK_RUN)))
    write(joinpath(LK_SHARD_DIR, "types_" * LK_SHARD_ID), LK_TERM_TYPES * "\n")  # _check_run
    println("  shard ", LK_SHARD_ID, " of a run with ", length(LK_RUN), " units")
elseif !isempty(LK_REPLAY)
    println("  REPLAY of ", LK_REPLAY, ": ", length(LK_RUN), " units, in order")
elseif LK_SLICED
    println(
        "  CI slice: ",
        if LK_SA_ONLY
            "static analysis shard $(ENV["LOGICKERNEL_SA_SHARD"])"
        else
            "file group $(ENV["LOGICKERNEL_FILE_GROUP"])"
        end,
        " — ", length(LK_RUN), " of ", length(LK_UNITS), " units"
    )
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
        generic = [
            relpath(f, LK_TEST_DIR) for f in LK_TEST_FILES if haskey(LK_TERM_SCOPES, f)
        ]
        @test "core_lang/test_term_interface.jl" in generic
        @test "core_lang/test_unify.jl" in generic
        @test length(generic) >= 20
        @test length(LK_TERM_IMPLS) >= 3
    end
    # How much of each unit is COMPILATION (user, 2026-10-04: "are we using Julia multi
    # threading"): what one process running the units as threads would pay ONCE, and three cold
    # processes pay three times. Julia's own counter, as `@time` reports it.
    Base.cumulative_compile_timing(true)
    ran_rows = Tuple{String, Int, Int, Float64}[]      # (label, passed, broken, seconds): UNITS_OUT
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
            # The leaves' ONE shared empty child vector (src/default_term.jl `_no_children`; user,
            # 2026-10-05) is still empty: every unit is a workload for "nothing pushes to it".
            @test isempty(LogicKernel._no_children(LogicKernel.DefaultTerm))
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
        push!(ran_rows, (label, npass, nbroken, secs))
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
    elseif isempty(LK_REPLAY) && (!LK_SLICED || !isempty(LK_TERM_ONLY))
        # (under LOGICKERNEL_TERM_ONLY each job checks its own type's count — and that the OTHER
        # types' counts are zero: a job that ran another type's units is caught here. A CI SLICE ran
        # only some files, so it checks only the zeros; tools/evidence_ci.py checks the SUMS of a
        # type's slices, from the `stats` line below)
        @testset "the second implementation was exercised, plain and sharing" begin
            for (n, mine) in (
                (s.compounds_plain, LK_TERM_ONLY in ("", "alt")),
                (s.compounds_interned, LK_TERM_ONLY in ("", "alt_interned")),
                (s.shared, LK_TERM_ONLY in ("", "alt_interned"))
            )
                if !LK_SLICED
                    @test (n > 0) == mine
                elseif !mine
                    @test n == 0
                end
            end
        end
    end
    # THE UNIT LIST (CI, tools/evidence_ci.py): which slice this job is, every unit of the suite with
    # its implementation, those this job ran with what each asserted, and the second type's counts
    let out = get(ENV, "LOGICKERNEL_UNITS_OUT", "")
        isempty(out) || open(out, "w") do io
            kind = LK_SA_ONLY ? "sa_shard" : (LK_GROUPED ? "file_group" : "none")
            kn = LK_SA_ONLY ? lk_slice("LOGICKERNEL_SA_SHARD") : LK_FILE_GROUP
            println(io, "slice\t", kind, '\t', kn[1], '\t', kn[2], '\t', LK_TERM_ONLY)
            for u in LK_UNITS
                println(io, "all\t", u[3], '\t', isempty(u[2]) ? first(LK_TERM_IMPLS) : u[2])
            end
            for (label, np, nb, secs) in ran_rows
                println(io, "ran\t", label, '\t', np, '\t', nb, '\t', round(secs; digits=1))
            end
            println(
                io,
                "stats\t",
                s.compounds_plain,
                '\t',
                s.compounds_interned,
                '\t',
                s.shared
            )
        end
    end
end

isempty(LK_JUNIT) || println("  JUnit report: ", write_junit(LK_TS, LK_JUNIT))
Test.finish(LK_TS)                    # prints the summary; throws if anything failed or errored
assert_no_inert_testsets(LK_TS)
