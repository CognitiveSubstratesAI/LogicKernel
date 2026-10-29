# ORIGINAL: the load step of tools/pkgtest_way.jl, with the pkgdir guard (audit D-0249 item 1, 2026-10-29) — no
# swipl-devel counterpart.
#
# `Revise.stale_load` loads the MOST RECENT loadable precompile cache of ANY checkout of the package. A Pkg.test-way run
# in checkout B could therefore execute checkout A's code (MOD2, 2026-10-29: a run in lk-mod2 ran lk-s1's code, stack
# frames in lk-s1/src, 39 rows failed). tools/warm_session.jl refuses a package loaded from another directory than its
# checkout; here the refusal is followed by the way out: the run is started again in a fresh process that loads
# normally (NO_STALE), where Julia builds THIS checkout's own cache (a cache of another source path is stale for it).
# LOGICKERNEL_PKGTEST_WAY_NO_STALE=1 stays the explicit override: no stale load at all.
#
#   include("pkgtest_way_load.jl"); pkgtest_way_load("LogicKernel", root, :_no_children, @__FILE__, ARGS)
#
# `probe` names a function of the package whose methods are defined in the package's own src/: a cache can load with the
# right package directory recorded and still carry another checkout's method sources, so the methods' files are judged
# too.

"""
    pkgtest_way_foreign(mod, root, probe) -> Union{Nothing, String}

Why the loaded `mod` does NOT come from the checkout `root` (a sentence), or `nothing` when it does: its package
directory is `root`, and every method of `mod.probe` is defined in `root/src`.
"""
function pkgtest_way_foreign(mod::Module, root::AbstractString, probe::Symbol)
    r = realpath(root)
    d = pkgdir(mod)
    d === nothing && return "the package directory of $(nameof(mod)) is unknown"
    realpath(d) == r || return "the package directory is $(repr(d)), not $(repr(r))"
    isdefined(mod, probe) || return "$(nameof(mod)).$probe is not defined"
    src = joinpath(r, "src") * "/"
    ms = collect(methods(getfield(mod, probe)))
    isempty(ms) && return "$(nameof(mod)).$probe has no method"        # an empty list would pass the loop below
    for m in ms
        f = String(m.file)
        f = isfile(f) ? realpath(f) : abspath(f)
        startswith(f, src) ||
            return "$(nameof(mod)).$probe is defined in $(repr(f)), not under $(repr(src))"
    end
    return nothing
end

"""
    pkgtest_way_load(pkgname, root, probe, script, args) -> Symbol

Start from the last cache as `tools/warm_session.jl` does (a plain `using` of a checkout whose cache is stale
re-precompiles: 18 min measured in a fresh worktree), but only if that cache is this checkout's. Returns `:stale`
(loaded from the last cache and revised), `:normal` (no stale load: the override, or not possible — the caller's
`using` loads or builds the cache). When the cache turned out to be another checkout's, runs `script args...` in a fresh
process with the override set and EXITS with its exit code; the caller never sees that case.
"""
function pkgtest_way_load(
    pkgname::AbstractString, root::AbstractString, probe::Symbol,
    script::AbstractString, args::AbstractVector{<:AbstractString}
)
    get(ENV, "LOGICKERNEL_PKGTEST_WAY_NO_STALE", "") == "1" && return :normal
    mod = nothing
    try
        revise = Base.require(Main, :Revise)
        mod = Base.invokelatest(revise.stale_load, pkgname; throw=true)
    catch e
        println(
            stderr, "pkgtest-way: stale_load not possible (", sprint(showerror, e),
            ") — loading normally"
        )
        return :normal
    end
    why = pkgtest_way_foreign(mod, root, probe)
    why === nothing && return :stale
    println(
        stderr, "pkgtest-way: REFUSED the last cache of ANOTHER checkout (", why,
        ") — building this checkout's own cache in a fresh process"
    )
    env = Dict{String, String}(ENV)
    env["LOGICKERNEL_PKGTEST_WAY_NO_STALE"] = "1"
    cmd = `$(Base.julia_cmd()) --project=$(dirname(Base.active_project())) --startup-file=no $script $args`
    exit(run(ignorestatus(setenv(cmd, env))).exitcode)
end
