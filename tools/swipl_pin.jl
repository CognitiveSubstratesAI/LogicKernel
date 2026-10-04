# tools/swipl_pin.jl — the swipl a process judges its live differentials against must be the PINNED
# one (tools/SWIPL_VERSION). Included by tools/worker.jl and tools/warm_session.jl, which check it
# WHERE THEY RUN: a check made in another process's environment proves nothing about theirs.
# MEASURED 2026-10-04: systemd started the evidence workers and the warm daemon from the user
# manager's PATH, which found /usr/local/bin/swipl 10.1.12, while the shell that checked the pin
# found the pinned 10.1.16 — so every differential of a sharded run was judged against 10.1.12.

"`nothing` when the `swipl` on this process's PATH is the pinned version; otherwise why not."
function swipl_pin_refusal(root::AbstractString)::Union{Nothing, String}
    f = joinpath(root, "tools", "SWIPL_VERSION")
    pin = isfile(f) ? join(strip.(filter(l -> !startswith(l, "#"), readlines(f)))) : ""
    isempty(pin) && return "tools/SWIPL_VERSION is missing or empty — no pinned swipl"
    have = something(Sys.which("swipl"), "")
    version = isempty(have) ? "" : (
        try
            readchomp(`$have --version`)
        catch
            ""
        end
    )
    occursin("version $pin ", version) && return nothing
    return "swipl must be $pin (tools/SWIPL_VERSION); found: " *
           "$(isempty(version) ? "none" : version) at $(isempty(have) ? "(none on PATH)" : have)"
end
