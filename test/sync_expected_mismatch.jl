# ORIGINAL: the upstream sync's expected-mismatch list (user, 2026-10-11); it exists only while a sync lasts.
# test/sync_expected_mismatch.jl — WHAT MAY DIFFER FROM THE ORACLE WHILE THE PIN MOVES.
#
# A sync moves the pin and the oracle FIRST (tools/SWIPL_VERSION), then ports upstream's changes
# file by file. Between the two, the kernel still does what the OLD upstream did wherever upstream
# changed, so the live differentials find mismatches — every one of which a known upstream commit
# explains. This file is the list of them: each entry names the test file, the case, and the
# upstream fix whose port clears it.
#   * A differential routes its mismatches through `sync_unexpected` (a list of them) or
#     `sync_mismatch` (one check): a mismatch ON the list is expected; any other FAILS as before.
#   * An entry that did NOT mismatch is stale, and an error: every file that uses the list ends
#     with `@test isempty(sync_stale(<file>))`. So when a fix is ported, its entries MUST go.
#   * test/test_gate_split.jl holds the list to the sync: it exists exactly while
#     tools/SWIPL_VERSION has a `sync-from:` line, every entry names a test file that checks it
#     and a fix commit, and no test file uses it without an entry. The sync's last commit deletes
#     this file.
# LOGICKERNEL_SYNC_DISCOVER=<file>: every mismatch is taken as expected and written to <file>
# (`test file<TAB>case`) — how the list is drawn up after the oracle moves; never set in a gate.
using SHA

"`(file, case, fix)`: in test file `file` (relative to test/), `case` differs from the oracle until upstream's `fix` is ported."
const SYNC_EXPECTED = Tuple{String, String, String}[]

"The cases of `file` that upstream's `fix` (a commit, or `a+b` where both are needed) clears."
function sync_cases(file::String, fix::String, cases::Vector{String})::Nothing
    append!(SYNC_EXPECTED, [(file, c, fix) for c in cases])
    return nothing
end

const _SYNC_HIT = Set{Tuple{String, String}}()
const _SYNC_DISCOVER = get(ENV, "LOGICKERNEL_SYNC_DISCOVER", "")

"A case's key: itself when short, else its start and a hash of all of it."
function sync_key(case::AbstractString)::String
    s = String(case)
    return if length(s) <= 100
        s
    else
        first(s, 60) * "… sha1:" * bytes2hex(sha1(s))[1:16]
    end
end

"True — and recorded — when `case` of test file `file` is on the list: a mismatch the sync has not cleared yet."
function sync_mismatch(file::AbstractString, case::AbstractString)::Bool
    k = (String(file), sync_key(case))
    if !isempty(_SYNC_DISCOVER)
        k in _SYNC_HIT ||
            open(io -> println(io, k[1], '\t', repr(k[2])), _SYNC_DISCOVER, "a")
        push!(_SYNC_HIT, k)
        return true
    end
    any(e -> e[1] == k[1] && e[2] == k[2], SYNC_EXPECTED) || return false
    push!(_SYNC_HIT, k)
    return true
end

"""
The mismatches of `bad` that are NOT on the list — the unexpected ones. A mismatch's key is the
WHOLE of it (`key`, default `string`): the case, the kernel's result and swipl's. So an entry
clears exactly one difference, and a case that starts to differ in another way fails.
"""
function sync_unexpected(file::AbstractString, bad::AbstractVector; key=string)
    # drawing up the list: each mismatch whole, beside its key, to classify it by the fix behind it
    isempty(_SYNC_DISCOVER) || open(_SYNC_DISCOVER * ".detail", "a") do io
        for b in bad
            println(io, file, '\t', repr(sync_key(key(b))), '\t', repr(string(b)))
        end
    end
    return filter(b -> !sync_mismatch(file, key(b)), bad)
end

"""
The entries of `file` that did not mismatch in this run: stale — their fix is in, or they never
differed. NONE where there is no `swipl` to compare with (Pkg.test's environment, CI's `test`
jobs): the differentials do not run there, so nothing was compared and nothing can be stale.
MEASURED 2026-10-11 (CI run 38156167094): without this, every entry read as stale in the two
jobs that have no swipl, while every local gate — which always has one — was green.
"""
function sync_stale(file::AbstractString)::Vector{String}
    Sys.which("swipl") === nothing && return String[]
    return [
        e[2] for e in SYNC_EXPECTED if e[1] == file && !((e[1], e[2]) in _SYNC_HIT)
    ]
end

# ── the list ─────────────────────────────────────────────────────────────────────────────────────
# EMPTY since the sync's fifth commit (2026-10-11): every upstream fix is ported and no differential
# differs from the oracle. 906 entries at the pin's move; the last eight left with 85d0cc2.
