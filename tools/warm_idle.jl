# tools/warm_idle.jl — WHEN the warm daemon's idle exit is held (audit D-0461 item 3a, 2026-11-09).
# Included by tools/warm_session.jl; also a command (`julia --startup-file=no tools/warm_idle.jl
# check NOW LAST IDLE_S HOLD QUEUE_FILE MAX_S`, printing `exit` or `stay`) so that
# tools/test_warm.sh judges THIS function without a daemon.
#
# WHY: a fresh daemon costs ~1900 s more than a warm one (start 317 s, JET 423 s against 14 s, the
# first test file's JIT 150-230 s: evidence/TOOLS/profile_summary.md), and lane daemons were found
# idle-exited between two gates. The idle exit (user, 2026-10-14) stays the default: with
# LOGICKERNEL_WARM_IDLE_HOLD_QUEUE=1 the daemon does NOT exit while a gate branch is QUEUED.
#
# THE QUEUE is an explicit file, not lanes.conf: its rows are free text (an agent id, a step with
# its whole history, `LANDED`, `free`, `GATE`, in no fixed place), so no rule over them is reliable.
# The file (LOGICKERNEL_WARM_QUEUE_FILE, default ~/code/gate_queue.txt, written by the dispatcher)
# holds one gate branch per line — `gate/wr2b` — blank lines and `#` comments ignored; the dispatcher
# deletes a line when the branch lands. A missing or unreadable file is an EMPTY queue.
#
# THE CEILING: a stale line must not hold ~3.9 GB for days (the very incident the idle exit answers),
# so a hold ends LOGICKERNEL_WARM_IDLE_HOLD_MAX_S (43200 = 12 h) after the last request whatever the
# queue says; 0 = no ceiling. `warm.sh stop` is untouched: it stops the unit, a hold only changes
# what the daemon does when it would exit by itself.

"The gate branches queued in `file`: its non-blank, non-comment lines, stripped. Empty if unreadable."
function idle_hold_queue(file::AbstractString)::Vector{String}
    isfile(file) || return String[]
    try
        entries = String[]
        for l in eachline(file)
            s = strip(first(split(l, '#'; limit=2)))
            isempty(s) || push!(entries, String(s))
        end
        return entries
    catch
        return String[]
    end
end

"""
Whether the daemon must exit now: it has been idle MORE than `idle_s` seconds and it is not held.
Held = `hold` on, a queued gate branch in `queue`, and the idleness still within `max_s` (0: no limit).
"""
function idle_exit_due(
    now::Real, last_request::Real, idle_s::Real, hold::Bool, queue, max_s::Real
)::Bool
    now - last_request > idle_s || return false
    hold && !isempty(queue) && (max_s <= 0 || now - last_request <= max_s) && return false
    return true
end

if abspath(PROGRAM_FILE) == @__FILE__
    a = ARGS
    if length(a) == 7 && a[1] == "check"
        now, last, idle_s, max_s = (parse(Float64, a[i]) for i in (2, 3, 4, 7))
        q = idle_hold_queue(a[6])
        println(idle_exit_due(now, last, idle_s, a[5] == "1", q, max_s) ? "exit" : "stay")
    else
        println(stderr, "usage: warm_idle.jl check NOW LAST IDLE_S HOLD QUEUE_FILE MAX_S")
        exit(2)
    end
end
