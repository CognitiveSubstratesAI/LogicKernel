#!/usr/bin/env bash
# ORIGINAL: the autoload indexes of the vendored library (R2 LB4 chunk a, audit D-0286 item 1; design evidence/r2/design/loader_boot.md LD6) — no swipl-devel counterpart.
# tools/gen_library_index.sh — writes the five INDEX.pl files of vendor/swipl-devel/library and their lines in tools/swipl_vendor_blobs.txt.
#
# Upstream's build writes them with the oracle itself: cmake/LibIndex.cmake:17-28 runs `make_library_index('<home>/<dir>')` for each
# directory of src/CMakeLists.txt:120-121 SWIPL_DATA_INDEXED_DIRS (library, library/clp, library/dcg, library/unicode, library/lynx). So
# does this script, with the swipl on PATH (the oracle at the pin: tools/swipl_pin.jl asserts its version where the gates run): over
# a COPY of the vendored library in a scratch directory (the oracle never writes into vendor/), then the five files are copied back.
# The output depends on the vendored files alone (make_library_index/1 lists `*.pl` sorted by expand_file_name/2 and reads each
# file's module header), so a second run over the same files is byte-identical; test/test_vendored_swipl.jl holds each file to its blob
# line and every entry to a file that is there. A BUMP of the pin re-runs tools/vendor_swipl.sh, then this script, in the sync's commit.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor="$root/vendor/swipl-devel"
manifest="$root/tools/swipl_vendor_blobs.txt"
marker='# GENERATED'
dirs=(library library/clp library/dcg library/unicode library/lynx)

[[ -d "$vendor/library" ]] || { echo "gen_library_index: no $vendor/library (tools/vendor_swipl.sh library first)" >&2; exit 2; }
grep -qF "$marker" "$manifest" || { echo "gen_library_index: $manifest has no GENERATED marker (tools/vendor_swipl.sh manifest first)" >&2; exit 2; }
command -v swipl > /dev/null || { echo "gen_library_index: no swipl on PATH" >&2; exit 2; }

mkdir -p "$root/.warm"
scratch="$(mktemp -d "${TMPDIR:-$root/.warm}/gen_library_index.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cp -r "$vendor/library" "$scratch/library"
find "$scratch/library" -name INDEX.pl -delete          # a stale one would be "up to date": the index is rebuilt from the files

goals=""
for d in "${dirs[@]}"; do
    goals+="make_library_index('$scratch/$d'),"
done
swipl -g "${goals}true" -t halt

# the manifest: upstream's lines stay, the generated section is written again
tmp="$scratch/manifest"
sed -n "/^$marker/q;p" "$manifest" > "$tmp"
echo "$marker — not in upstream's tree: the five INDEX.pl files (tools/gen_library_index.sh)" >> "$tmp"
for d in "${dirs[@]}"; do
    [[ -s "$scratch/$d/INDEX.pl" ]] || { echo "gen_library_index: the oracle wrote no $d/INDEX.pl" >&2; exit 1; }
    cp "$scratch/$d/INDEX.pl" "$vendor/$d/INDEX.pl"
    printf '100644 blob %s\t%s\n' "$(git hash-object --no-filters "$vendor/$d/INDEX.pl")" "$d/INDEX.pl" >> "$tmp"
done
cp "$tmp" "$manifest"
