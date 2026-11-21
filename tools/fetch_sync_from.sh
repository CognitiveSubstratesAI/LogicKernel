#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — CI's fetch of the PREVIOUS pin during a sync (audit D-0444 item 1).
#
#   tools/fetch_sync_from.sh [<checkout dir> [<version file>]]
#       defaults: .upstream/swipl-devel  tools/SWIPL_VERSION  (the workflow's working directory is the repository root)
#
# tools/SWIPL_VERSION carries a `sync-from:` line only DURING a sync (the previous pin, which a ported file's
# header may still cite). CI's `.upstream/swipl-devel` is a depth-1 checkout of `commit:` alone, so
# tools/port_check.jl's `git cat-file -e <commit>^{commit}` finds no such commit for those headers
# (COMMIT-MISSING). With the line present this fetches that commit, depth 1, from the checkout's `origin`;
# WITHOUT the line (main between syncs) it prints one line and exits 0: a clean no-op, never a failure.
# A fetch that fails during a sync fails the step (the headers could not be read otherwise).
# THE PIN1 STEP THAT MOVES THE LAST HEADER REMOVES `sync-from:` AND THE WORKFLOW STEPS THAT CALL THIS (and this file).
set -euo pipefail
dir="${1:-.upstream/swipl-devel}"
vf="${2:-tools/SWIPL_VERSION}"
sha="$(sed -n 's/^sync-from:[[:space:]]*//p' "$vf" | tr -d '[:space:]')"
if [ -z "$sha" ]; then
    echo "fetch_sync_from: no sync-from line in $vf, nothing to fetch"
    exit 0
fi
git -C "$dir" fetch --depth 1 origin "$sha"
git -C "$dir" cat-file -e "$sha^{commit}"
echo "fetch_sync_from: $sha is in $dir"
