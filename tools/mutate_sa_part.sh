#!/usr/bin/env bash
# ORIGINAL: one part of the static analysis as ONE mutation target (audit D-0462) — no swipl-devel counterpart.
# tools/mutate_sa_part.sh [PART] — test/test_static_analysis.jl with only its one-off part PART (default
# `jet_allowlist`, the JET allowlist and the stream family around it) for a mutant list's TARGETS
# (`sh:tools/mutate_sa_part.sh`: a target holds no blank, so the default is the argument). The whole file
# is ~100 min in one process (the 8 Evidence shards, 12-31 min each on 2026-11-10), past a battery job's
# limit; a part alone is minutes. HOW: LOGICKERNEL_SA_SHARD=k/n with k the part's place in `_SA_PARTS`
# (test/static_analysis_body.jl) and n past every place: the parts run are PART alone, the per-entry gates
# analyse their k-th entry only (test/ci_slices.jl `lk_in_slice`). THE EXIT: Julia's, and 2 when the
# counts file (LOGICKERNEL_SA_COUNTS_OUT) does not name PART as the one part that ran — a part that did
# not run passes nothing.
set -u
part="${1:-jet_allowlist}"
cd "$(dirname "$0")/.." || exit 2
k="$(awk '/^const _SA_PARTS = \(/ { on = 1; next } on && /^\)/ { exit } on' test/static_analysis_body.jl |
    tr -d ' \n' | tr ',' '\n' | grep -n -x "\"$part\"" | cut -d: -f1)"
[ -n "$k" ] || { echo "mutate_sa_part: no part \"$part\" in _SA_PARTS"; exit 2; }
counts="$(mktemp "${TMPDIR:-/tmp}/mutate_sa_part_XXXXXX")"
trap 'rm -f "$counts"' EXIT
LOGICKERNEL_SA_SHARD="$k/1000000" LOGICKERNEL_SA_COUNTS_OUT="$counts" \
    julia --project=. --startup-file=no test/test_static_analysis.jl < /dev/null
rc=$?
ran="$(awk -F '\t' '$1 == "part" { printf "%s ", $2 }' "$counts" 2> /dev/null)"   # (not the `parts` line)
echo "=== mutate_sa_part: LOGICKERNEL_SA_SHARD=$k/1000000, parts run: ${ran:-none}, exit $rc"
[ "$rc" -ne 0 ] && exit "$rc"
[ "$ran" = "$part " ] || exit 2
exit 0
