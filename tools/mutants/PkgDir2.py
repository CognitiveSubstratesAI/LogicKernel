# ORIGINAL: PkgDir's mutant list — no swipl-devel counterpart.
# tools/mutants/PkgDir2.py — the mutation battery of the pkgdir guard of the Pkg.test-way run (audit D-0249 item 1,
# 2026-10-29): tools/pkgtest_way_load.jl refuses a precompile cache of ANOTHER checkout (MOD2: a run in lk-mod2
# executed lk-s1's code) and runs again in a fresh process that builds this checkout's own cache; the explicit
# override LOGICKERNEL_PKGTEST_WAY_NO_STALE=1 stays. Run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `equivalent` and `targets`.
#
# Subject: a guard must be able to FAIL — each mutant is one of the ways it is useless: it never runs / its verdict is
# dropped, it cannot fail (accepts any cache, an empty method list), or it compares the wrong thing (another
# directory, another source tree), and the fallback may do nothing, load the foreign cache anyway, or lose the exit code.
# TARGETS = EVERY test file that exercises the mutated code (D-0238): tools/pkgtest_way_load.jl and the driver
# tools/pkgtest_way.jl run for real only in test/test_gate_split.jl (the stub packages); the Pkg.test-way run of
# tools/warm.sh `check` (tools/test_warm.sh) runs the driver on a changed test file but is not a test/ file.
#
# NOT listed on purpose: the child's override set to "" instead of "1" — the fresh process would refuse again and
# start another one, forever (a fork loop in the mutant run).
TARGETS = ["test/test_gate_split.jl"]
T = TARGETS
L = "tools/pkgtest_way_load.jl"
D = "tools/pkgtest_way.jl"
MUTANTS = [
    # ── the verdict: is the loaded cache this checkout's? ──
    dict(id="PD1 the verdict is dropped: any cache is accepted", file=L, targets=T,
         old='''    why === nothing && return :stale''',
         new='''    return :stale'''),
    dict(id="PD2 the package directory is compared with the wrong directory", file=L, targets=T,
         old='''    realpath(d) == r || return''',
         new='''    realpath(d) == dirname(r) || return'''),
    dict(id="PD3 the package directory is not compared at all", file=L, targets=T,
         old='''    realpath(d) == r || return "the package directory is $(repr(d)), not $(repr(r))"''',
         new='''    realpath(d) == realpath(d) || return "the package directory is $(repr(d)), not $(repr(r))"'''),
    dict(id="PD4 an unknown package directory passes", file=L, targets=T,
         old='''    d === nothing && return "the package directory of $(nameof(mod)) is unknown"''',
         new='''    d === nothing && return nothing'''),
    dict(id="PD5 the root argument is ignored (the working directory is this checkout)", file=L, targets=T,
         old='''    r = realpath(root)''',
         new='''    r = realpath(pwd())'''),
    dict(id="PD6 the methods' files are not judged", file=L, targets=T,
         old='''        startswith(f, src) ||
            return''',
         new='''        true ||
            return'''),
    dict(id="PD7 the methods' files are compared with another directory", file=L, targets=T,
         old='''    src = joinpath(r, "src") * "/"''',
         new='''    src = joinpath(r, "test") * "/"'''),
    dict(id="PD8 a probe with no method passes", file=L, targets=T,
         old='''    isempty(ms) && return "$(nameof(mod)).$probe has no method"''',
         new='''    isempty(ms) && return nothing'''),
    dict(id="PD9 a probe that is not defined passes", file=L, targets=T,
         old='''    isdefined(mod, probe) || return "$(nameof(mod)).$probe is not defined"''',
         new='''    isdefined(mod, probe) || return nothing'''),
    # ── the fallback ──
    dict(id="PD10 the refusal runs nothing in a fresh process", file=L, targets=T,
         old='''    exit(run(ignorestatus(setenv(cmd, env))).exitcode)''',
         new='''    exit(0)'''),
    dict(id="PD11 the refusal is printed and the foreign cache used anyway", file=L, targets=T,
         old='''        ") — building this checkout's own cache in a fresh process"
    )''',
         new='''        ") — building this checkout's own cache in a fresh process"
    )
    return :stale'''),
    dict(id="PD12 the fresh process's exit code is lost", file=L, targets=T,
         old='''    exit(run(ignorestatus(setenv(cmd, env))).exitcode)''',
         new='''    (run(ignorestatus(setenv(cmd, env))); exit(0))'''),
    dict(id="PD13 the fresh process runs another script", file=L, targets=T,
         old='''--startup-file=no $script $args`''',
         new='''--startup-file=no $(@__FILE__) $args`'''),
    dict(id="PD14 the fresh process gets no arguments", file=L, targets=T,
         old='''--startup-file=no $script $args`''',
         new='''--startup-file=no $script`'''),
    # ── the explicit override and the start from the last cache ──
    dict(id="PD15 the NO_STALE override is ignored", file=L, targets=T,
         old='''    get(ENV, "LOGICKERNEL_PKGTEST_WAY_NO_STALE", "") == "1" && return :normal''',
         # bounded: the first process ignores the override, the child it spawns (override set, _PD15 already set) honours it
         # (a plain `false && ...` makes the child refuse and re-spawn forever: it shut a CI runner down)
         new='''    get(ENV, "LOGICKERNEL_PKGTEST_WAY_NO_STALE", "") == "1" && (ENV["_PD15"] = get(ENV, "_PD15", "") * "x"; length(ENV["_PD15"]) > 1) && return :normal'''),
    dict(id="PD16 the override is on for any value", file=L, targets=T,
         old='''    get(ENV, "LOGICKERNEL_PKGTEST_WAY_NO_STALE", "") == "1" && return :normal''',
         new='''    haskey(ENV, "LOGICKERNEL_PKGTEST_WAY_NO_STALE") && return :normal'''),
    dict(id="PD17 the stale load is never tried (every run loads normally)", file=L, targets=T,
         old='''    mod = nothing
    try''',
         new='''    mod = nothing
    return :normal
    try'''),
    # ── the driver ──
    dict(id="PD18 the driver does not call the guard", file=D, targets=T,
         old='''pkgtest_way_load("LogicKernel", joinpath(@__DIR__, ".."), :_no_children, @__FILE__, ARGS)''',
         new='''nothing'''),
    dict(id="PD19 the driver names another checkout's root", file=D, targets=T,
         old='''pkgtest_way_load("LogicKernel", joinpath(@__DIR__, ".."), :_no_children, @__FILE__, ARGS)''',
         new='''pkgtest_way_load("LogicKernel", joinpath(@__DIR__, "..", "test"), :_no_children, @__FILE__, ARGS)'''),
    dict(id="PD20 the driver stale-loads without the guard", file=D, targets=T,
         old='''pkgtest_way_load("LogicKernel", joinpath(@__DIR__, ".."), :_no_children, @__FILE__, ARGS)''',
         new='''Base.invokelatest(Base.require(Main, :Revise).stale_load, "LogicKernel"; throw=true)'''),
]
