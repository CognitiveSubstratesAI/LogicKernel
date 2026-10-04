# tools/warm_session.jl — the WARM LANE's daemon: LogicKernel loaded ONCE under Revise, serving
# snippets from `.warm/` (user, 2026-10-03: "you are supposed to use revise.jl … should be added to
# warm server"). Started and driven by tools/warm.sh — never by hand.
#
# 🔴 ITERATION ONLY, NEVER EVIDENCE (user, 2026-10-03). A long-lived process is where state leaks
# hide — in Core a setting left off in the daemon faked a green result, and a polluted daemon made a
# bisect name the wrong file. Commit evidence is a FRESH `tools/run_tests.sh` process; `warm.sh
# evidence` launches one, and it shares nothing with this daemon.
#
# WHY: in one chunk (Q1) ~8 cold full suites ran at ~10 min each here (2m44s in CI), and a fresh
# process paid ~10 s just to JIT the kernel's hot paths before its first answer (measured). Warm,
# that is paid once per daemon.
#
# THE PROTOCOL (Core's tools/warm_session.jl, whose fixes it keeps): the client writes `.warm/in.jl`,
# then a new number into `.warm/seq`; the daemon runs Revise, then the snippet, writes everything
# printed to `.warm/out.txt`, the verdict to `.warm/status` ("0" completed, "1" threw) and only then
# the number into `.warm/done`.
# * A failed Revise update REFUSES the snippet (status 1): running stale code and reporting it as
#   fresh is the one thing this lane must never do.
# * The verdict is written BEFORE `done`, and a missing verdict reads as failure (tools/warm.sh).
# * Snippets use ABSOLUTE paths (tools/warm.sh writes them so): a relative `include` would resolve
#   against this file's directory, not the project root.
#
# REVISE'S DOCUMENTED LIMITS, and what this daemon does about each (user, 2026-10-03):
# * A STRUCT edit is revised in place on Julia ≥ 1.12 (types can be redefined) — no restart needed.
#   But values built BEFORE the edit stay instances of the old type, test residue accumulates, and an
#   update can fail partway: three reasons the daemon is for iteration and evidence is a fresh process.
# * MACROS, `@generated` functions and TYPE ALIASES (`const Clause{T} = clause{T, definition{T}}`
#   in src/pl-incl.jl) do not propagate to code that already expanded or used them. When a changed
#   src/ file defines any of them, the daemon re-evaluates the whole module (`revise(LogicKernel)`)
#   before the snippet, and refuses the snippet if that fails.
# * A task keeps the world it started in: each snippet runs through `invokelatest`, never in a
#   long-lived task.
# * A precompile in ANOTHER process (an evidence worker, the precompile workload) can rewrite the
#   cache Revise compares edits against; Revise then records a `StaleCacheError` and stops revising
#   that file. The daemon treats any queued Revise error, and any rewritten cache, as a refusal —
#   `tools/warm.sh restart` recovers.
# * Revise notices a REMOVED `include` only for literal paths: src/LogicKernel.jl's includes stay
#   literal `include("pl-x.jl")` lines (and so must any generated include list).
try
    using Revise
catch
    @warn "Revise unavailable — src edits will NOT hot-reload; use `tools/warm.sh restart`"
end
# START FROM THE LAST CACHE (Revise's `stale_load`, docs "tricks"): after src edits a plain `using`
# re-precompiles first (16 s with the precompile workload, 6 s without); `stale_load` loads the most
# recent cache and revises it up to the current source instead. It throws where that cache cannot
# be loaded (another Julia, a changed preference such as the workload switch) — then load normally.
# A checkout COPY (tools/warm.sh with LOGICKERNEL_WARM_DEPOT) loads normally instead: `stale_load`
# takes the most recent cache of ANY checkout of the package, and Revise would then watch that
# checkout's src/ — which the guard below refuses (measured 2026-10-04, parallel mutation copies).
if isdefined(Main, :Revise) && get(ENV, "LOGICKERNEL_WARM_NO_STALE_LOAD", "") != "1"
    try
        Revise.stale_load("LogicKernel"; throw=true)
        println("LogicKernel: loaded from its last cache and revised to the current source")
    catch e
        println(
            "LogicKernel: stale_load not possible ($(sprint(showerror, e))) — loading normally"
        )
    end
end
using LogicKernel, Test

const ROOT = abspath(joinpath(@__DIR__, ".."))
# The `file` runs judge their live differentials against the swipl on THIS process's PATH: it must
# be the pinned one, checked here, where they run (tools/swipl_pin.jl). tools/warm.sh hands the
# daemon its caller's PATH and checks it there too.
include(joinpath(@__DIR__, "swipl_pin.jl"))
let why = swipl_pin_refusal(ROOT)
    why === nothing || error("warm lane: REFUSED to start — ", why)
end
cd(ROOT)
# The second term implementation is loaded once per process into `Main` (test/term_under_test.jl);
# tracked here, so an edit to it reloads like an edit to src/. A STRUCT change in it needs a restart.
if isdefined(Main, :Revise)
    Revise.includet(joinpath(ROOT, "test", "core_lang", "alt_term.jl"))
else
    Base.include(Main, joinpath(ROOT, "test", "core_lang", "alt_term.jl"))
end

const DIR = joinpath(ROOT, ".warm")
const SRC = joinpath(ROOT, "src")

# Revise's own audit trail and its "not watching" failure (docs "debugging"): every action it takes
# is logged, and the daemon reports them per snippet; a src/ directory Revise does not watch would be
# a daemon that is never revised — so it refuses to start.
const RLOG = isdefined(Main, :Revise) ? Revise.debug_logger() : nothing
if isdefined(Main, :Revise) && !haskey(Revise.watched_files, SRC)
    error(
        "warm lane: Revise is not watching $SRC — edits would never be revised; refusing to start"
    )
end

"src/ files and their modification times, to see which ones changed since the last snippet."
_src_mtimes() =
    Dict(f => mtime(joinpath(SRC, f)) for f in readdir(SRC) if endswith(f, ".jl"))

"""
Whether file `path` defines something Revise does not propagate to code that already used it — a
macro, a `@generated` function, or a type alias (`const Name{…} = type{…}`; a container constant
matches too, which costs only an extra re-evaluation) —
so that an edit to it needs the whole module re-evaluated.
"""
_needs_module_revise(path::AbstractString)::Bool = occursin(
    r"^\s*macro\s|@generated|^\s*const\s+[A-Za-z_]\w*(\{[^}]*\})?\s*=\s*[A-Za-z_][\w.]*\{"m,
    read(path, String)
)

"Why Revise must not be trusted for this snippet, or `nothing`: queued errors, a rewritten cache."
function _revise_state_refusal()
    R = Main.Revise
    if isdefined(R, :queue_errors) && !isempty(R.queue_errors)
        return "Revise has queued errors (a file it could not revise): $(join(string.(last.(first.(keys(R.queue_errors)))), ", "))"
    elseif isdefined(R, :rewritten_caches) && !isempty(R.rewritten_caches)
        return "a precompile cache was rewritten by another process ($(join(string.(R.rewritten_caches), ", "))) — edits to it can no longer be revised; tools/warm.sh restart"
    end
    return nothing
end
const INF, OUTF, SEQF = joinpath(DIR, "in.jl"),
joinpath(DIR, "out.txt"),
joinpath(DIR, "seq")
const DONE, STATUSF = joinpath(DIR, "done"), joinpath(DIR, "status")

function _serve()
    mkpath(DIR)
    rm(INF; force=true)
    rm(DONE; force=true)
    rm(STATUSF; force=true)
    seen = isfile(SEQF) ? strip(read(SEQF, String)) : ""
    mtimes = _src_mtimes()
    write(joinpath(DIR, "ready"), string(getpid()))
    println("WARM LANE READY (LogicKernel, pid $(getpid()))")
    flush(stdout)
    while true
        if isfile(SEQF) && isfile(INF)
            n = strip(read(SEQF, String))
            if n != seen && !isempty(n)
                seen = n
                code = read(INF, String)
                revise_fail = nothing
                note = ""
                if isdefined(Main, :Revise)
                    now = _src_mtimes()
                    changed = [f for (f, t) in now if get(mtimes, f, 0.0) != t]
                    mtimes = now
                    try
                        Base.invokelatest(Main.Revise.revise; throw=true)
                        if any(f -> _needs_module_revise(joinpath(SRC, f)), changed)
                            note = "revise(LogicKernel): a changed file defines a macro, a @generated function or a type alias — $(join(changed, ", "))\n"
                            Base.invokelatest(Main.Revise.revise, LogicKernel)
                        end
                    catch e
                        revise_fail = (e, catch_backtrace())
                    end
                    if revise_fail === nothing
                        why = Base.invokelatest(_revise_state_refusal)
                        why === nothing || (revise_fail = (ErrorException(why), nothing))
                    end
                    # what Revise did since the last snippet, from its own log
                    acts = Base.invokelatest(Main.Revise.actions, RLOG)
                    nev = count(r -> r.message == "Eval", acts)
                    ndel = count(r -> r.message == "DeleteMethod", acts)
                    if !isempty(changed) || nev + ndel > 0
                        note *=
                            "revised: $nev eval(s), $ndel method deletion(s); changed src/: " *
                            (isempty(changed) ? "none" : join(changed, ", ")) * "\n"
                    end
                    empty!(RLOG.logs)
                end
                status = 0
                open(OUTF, "w") do io
                    redirect_stdout(io) do
                        redirect_stderr(io) do
                            print(io, note)
                            if revise_fail !== nothing
                                println(io, "REVISE FAILED — refusing to run this snippet:")
                                if revise_fail[2] === nothing
                                    showerror(io, revise_fail[1])
                                else
                                    showerror(io, revise_fail[1], revise_fail[2])
                                end
                                println(io)
                                status = 1
                            else
                                try
                                    Base.invokelatest(
                                        Base.include_string, Main, code,
                                        joinpath(DIR, "snippet_$n.jl")
                                    )
                                catch e
                                    showerror(io, e, catch_backtrace())
                                    println(io)
                                    status = 1
                                end
                            end
                        end
                    end
                end
                write(STATUSF, string(status))      # BEFORE `done`
                write(DONE, n)
            end
        end
        sleep(0.1)
    end
end

_serve()
