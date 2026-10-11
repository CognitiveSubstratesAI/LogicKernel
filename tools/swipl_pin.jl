# tools/swipl_pin.jl — the swipl a process judges its live differentials against must be THE
# ORACLE: the pinned version, built from the pinned commit (tools/SWIPL_VERSION). Included by
# tools/worker.jl and tools/warm_session.jl, which check it
# WHERE THEY RUN: a check made in another process's environment proves nothing about theirs.
# MEASURED 2026-10-04: systemd started the evidence workers and the warm daemon from the user
# manager's PATH, which found /usr/local/bin/swipl 10.1.12, while the shell that checked the pin
# found the pinned 10.1.16 — so every differential of a sharded run was judged against 10.1.12.

"The pin file's value for `key` (`version`, `commit`, `sync-from`), or `\"\"`."
function swipl_pin(root::AbstractString, key::AbstractString)::String
    f = joinpath(root, "tools", "SWIPL_VERSION")
    isfile(f) || return ""
    for l in eachline(f)
        startswith(l, key * ":") && return String(strip(l[(ncodeunits(key) + 2):end]))
    end
    return ""
end

"""
`nothing` when the `swipl` on this process's PATH is THE ORACLE — the pinned version, and a build
of the pinned commit (its `version_git` flag names it; tools/lib_evidence.sh `_check_swipl_pin`
is the same rule in the shell); otherwise why not.
"""
function swipl_pin_refusal(root::AbstractString)::Union{Nothing, String}
    ver, commit = swipl_pin(root, "version"), swipl_pin(root, "commit")
    (isempty(ver) || !occursin(r"^[0-9a-f]{40}$", commit)) &&
        return "tools/SWIPL_VERSION names no pinned version and commit — no oracle"
    have = something(Sys.which("swipl"), "")
    out(args) =
        try
            readchomp(pipeline(`$have $args`; stderr=devnull))
        catch
            ""
        end
    version = isempty(have) ? "" : out(["--version"])
    occursin("version $ver ", version) ||
        return "swipl must be $ver (tools/SWIPL_VERSION); found: " *
               "$(isempty(version) ? "none" : version) at $(isempty(have) ? "(none on PATH)" : have)"
    vg = out(["-g", "current_prolog_flag(version_git, G), writeln(G)", "-t", "halt"])
    m = match(r"-g([0-9a-f]{7,40})$", vg)
    (m !== nothing && startswith(commit, m[1])) && return nothing
    return "the oracle must be a BUILD OF THE PINNED COMMIT $(commit[1:12]) " *
           "(tools/SWIPL_VERSION); the swipl at $have says version_git " *
           "'$(isempty(vg) ? "none" : vg)' — build it: tools/build_oracle.sh PREFIX"
end
