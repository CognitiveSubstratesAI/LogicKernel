#!/usr/bin/env bash
# ORIGINAL: the vendoring of swipl-devel's boot/ and library/ (R2 LB4 chunk a, audit D-0286 item 1) — no swipl-devel counterpart.
# tools/vendor_swipl.sh — writes vendor/swipl-devel from the pinned swipl-devel commit, byte for byte:
#
#   tools/vendor_swipl.sh manifest      tools/swipl_vendor_blobs.txt: `git ls-tree -r <pin> boot library LICENSE`
#                                       (the generated INDEX.pl lines, below its GENERATED marker, are kept)
#   tools/vendor_swipl.sh boot          vendor/swipl-devel/boot/*.pl, LICENSE and PIN
#   tools/vendor_swipl.sh library       vendor/swipl-devel/library/**
#   tools/vendor_swipl.sh verify [PATH…]  every vendored file's (or those under the PATHs) `git hash-object --no-filters` against `git ls-tree`
#
# THE PIN is `commit:` of tools/SWIPL_VERSION; the upstream checkout is ~/dev-zone/swipl-devel or
# LOGICKERNEL_UPSTREAM_SWIPL_DEVEL (its HEAD is NOT the pin: every file is read with `git show <pin>:<path>`, never from the working tree).
# A vendored file is NEVER edited (test/test_vendored_swipl.jl holds each to the manifest): a fix goes in the port, or in a D-entry naming the
# upstream change. A BUMP of the pin re-runs this script, then tools/gen_library_index.sh, in the sync's own commit.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
up="${LOGICKERNEL_UPSTREAM_SWIPL_DEVEL:-$HOME/dev-zone/swipl-devel}"
pin="$(sed -n 's/^commit:[[:space:]]*//p' "$root/tools/SWIPL_VERSION" | tr -d '[:space:]')"
version="$(sed -n 's/^version:[[:space:]]*//p' "$root/tools/SWIPL_VERSION" | tr -d '[:space:]')"
dest="$root/vendor/swipl-devel"
manifest="$root/tools/swipl_vendor_blobs.txt"
marker='# GENERATED'

[[ "$pin" =~ ^[0-9a-f]{40}$ ]] || { echo "vendor_swipl: no commit: in tools/SWIPL_VERSION" >&2; exit 2; }
git -C "$up" cat-file -e "$pin^{commit}" || { echo "vendor_swipl: $up has no commit $pin" >&2; exit 2; }

# the upstream blobs of one pathspec: `mode blob id<TAB>path`
tree() { git -C "$up" ls-tree -r "$pin" -- "$@"; }

# write one upstream path into the vendor tree, binary-safe (no EOL conversion, no filters)
put() {
    local path="$1"
    mkdir -p "$dest/$(dirname "$path")"
    git -C "$up" show "$pin:$path" > "$dest/$path"
}

case "${1:-}" in
manifest)
    keep=""
    if [[ -f "$manifest" ]] && grep -qF "$marker" "$manifest"; then
        keep="$(sed -n "/^$marker/,\$p" "$manifest")"
    fi
    {
        echo "# SWI-Prolog/swipl-devel $pin — every file vendored at vendor/swipl-devel, as \`git ls-tree -r\` lists it: mode, type, blob id,"
        echo "# path (upstream's own path: boot/, library/, LICENSE). Written by tools/vendor_swipl.sh; test/test_vendored_swipl.jl holds the"
        echo "# vendored files to these blob ids (git's SHA-1 of \"blob <size>\\0<content>\")."
        tree boot library LICENSE
        if [[ -n "$keep" ]]; then
            echo "$keep"
        else
            echo "$marker — not in upstream's tree: the five INDEX.pl files (tools/gen_library_index.sh)"
        fi
    } > "$manifest"
    ;;
boot)
    tree boot | cut -f2 | while read -r p; do put "$p"; done
    put LICENSE
    {
        echo "# The upstream commit the files beside this one were copied from, byte for byte (tools/vendor_swipl.sh)."
        echo "commit: $pin"
        echo "version: $version"
        echo "upstream: https://github.com/SWI-Prolog/swipl-devel"
    } > "$dest/PIN"
    ;;
library)
    tree library | cut -f2 | while read -r p; do put "$p"; done
    ;;
verify)
    bad=0
    while IFS=$'\t' read -r meta path; do
        id="$(awk '{print $3}' <<< "$meta")"
        got="$(git hash-object --no-filters "$dest/$path" 2>/dev/null || echo missing)"
        [[ "$got" == "$id" ]] || { echo "DIFFERS: $path ($got, upstream $id)"; bad=1; }
    done < <(shift; if (($# )); then tree "$@"; else tree boot library LICENSE; fi)
    exit $bad
    ;;
*)
    sed -n '2,12p' "${BASH_SOURCE[0]}" >&2
    exit 2
    ;;
esac
