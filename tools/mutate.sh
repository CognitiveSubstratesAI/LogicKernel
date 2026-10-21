#!/usr/bin/env bash
# ORIGINAL: the mutation runs' lane (user, 2026-10-08 and 2026-10-11) — no swipl-devel counterpart.
# tools/mutate.sh — MUTANTS RUN IN A SEPARATE GIT WORKTREE, with a warm daemon of its own; the main
# tree is never touched (Tooling 1, 2026-10-11).
#
#   tools/mutate.sh setup                             # make or refresh the worktree
#   tools/mutate.sh run MUTANTS.py TARGET… [-- ID…]   # setup, then every mutant against the targets
#   tools/mutate.sh run-in-tree MUTANTS.py TARGET… [-- ID…]   # the same, in THIS tree (the old lane)
#   tools/mutate.sh run-parallel N MUTANTS.py TARGET… [-- ID…]   # 2 or 3 workers at once (below)
#   tools/mutate.sh recover                           # after a killed run: both trees
#   tools/mutate.sh status
#   tools/mutate.sh remove                            # when the chunk ends
#
# WHY. A mutant is a deliberately broken line. Applied in the working tree it sat one killed driver
# away from a commit — MEASURED 2026-10-08: a SIGTERM left a mutant in src/pl-fli.jl — and it kept
# the tree and its daemon from anything else for the whole run. So:
# * THE WORKTREE (LOGICKERNEL_MUTANTS_DIR, default ~/code/lk-mutants/worktree — outside the
#   workspace, never under /tmp) is a `git worktree` of this repository on a DETACHED HEAD, at this tree's HEAD, with
#   the chunk's uncommitted work copied over it: every file that differs from HEAD or is untracked
#   (a deleted one removed), and the two ignored files that decide what loads, Manifest.toml and
#   LocalPreferences.toml (tools/mutate_drive.py --sync).
# * THE GUARD: `setup` REFUSES unless both trees then hold the same content — the tree fingerprint
#   of tools/lib_evidence.sh over a non-empty file list, and those two files. A mutant judged on
#   other code than the chunk's proves nothing about the chunk.
# * IT NEVER COMMITS OR PUSHES: `.warm/MUTANT_WORKTREE` marks it, and tools/githooks/pre-commit and
#   pre-push refuse there.
# * ITS OWN DAEMON, in its own depot, capped at LOGICKERNEL_MUTANTS_MEM_MAX (6G): the main tree's
#   daemon, and its preflight, go on meanwhile. NOT beside an evidence run — `run` refuses while
#   one holds the main lane, and tools/run_tests.sh refuses to start one while mutants run.
# * THE DRIVER is tools/mutate_drive.py, the same for every chunk; a chunk keeps its mutant list.
# * THE SENTINEL stays, in whichever tree the mutant is applied: before a mutant the driver saves
#   the file (.warm/MUTATION_ORIGINAL) and writes .warm/MUTATION_IN_PROGRESS — the file, the copy's
#   SHA-256, the mutant — and removes both after restoring it. In the MAIN tree (`run-in-tree`) the
#   commit hook refuses every commit while it exists, so a killed driver fails CLOSED.
#
# PARALLEL (user, D-0059 item 3 / D-0077 item 6, 2026-10-21): `run-parallel N` makes N mutant worktrees,
# "$(LOGICKERNEL_MUTANTS_DIR)-1" … "-N", each with its own daemon and depot, and runs the list's mutants
# round-robin over them (tools/mutate_drive.py, MUTATE_SHARD=k/N): worker k takes every N-th mutant from the
# k-th. NEVER TWO MUTANTS IN ONE TREE: a mutant is applied in its worker's own worktree only, and each worker
# holds its own sentinel. The verdicts are merged in the list's order into MUTATE_OUT/verdicts.tsv
# (`mutate_drive.py --merge`) and are those of a serial run: a mutant's verdict does not depend on the others.
# Each worker runs its own baseline and final baseline (N times a serial run's two): the price of independence.
# THE MEMORY RULE: N workers need N x LOGICKERNEL_MUTANTS_WORKER_MB (2500; a daemon peaked at 1.7 GB RSS,
# measured 2026-10-20) plus 25 % of the machine's memory free (MemAvailable); less is REFUSED (exit 4).
# The daemons are started one after the other (a start precompiles) and sit beside each other only because
# of LOGICKERNEL_WARM_SIBLING_MUTANTS=1 (tools/warm.sh `_other_daemons`): a daemon of ANOTHER checkout still
# refuses a start. The local run is bounded by the machine's 4 cores: 2 or 3, never more.
# TARGETS MUST BE PARALLEL-SAFE (MEASURED 2026-10-21): a target that touches machine-wide state is not.
# tools/test_warm.sh guard creates systemd decoy units that another worker's daemon takes for a foreign
# checkout's: on 3 workers at once one worker's FINAL baseline went red (the verdicts above it prove
# nothing); run serially, the same three mutants were all caught. And parallel is no faster for a target that
# already fills the cores: 790 s serial against 777 s on 2 workers (the same 4 mutants of Tooling4 against
# test_gate_split.jl, identical verdicts); the 3-worker run of tools/mutants/ParmutWarm.py took 551 s against
# 293 s serial (evidence/A-0054/parallel_proof in the audit channel).
#
# `recover` is the way out of a killed run, in BOTH trees, and the only one: deleting a sentinel by
# hand is exactly the step that would let a leftover mutation through. For each tree it checks the
# named file against the SAVED COPY — never against HEAD: mid-chunk the file holds the chunk's own
# uncommitted work, which HEAD does not have and must not be lost — and:
#   * the file equals the copy (its SHA-256): intact; the sentinel and the copy are removed (exit 0);
#   * the file differs: it is restored from the copy, the diff it undid is shown, the SHA-256 is
#     checked again, and only then the sentinel and the copy are removed (exit 0);
#   * the sentinel names no file, or the copy is missing or does not match its SHA-256: REFUSED,
#     the sentinel kept (exit 1) — restore the file by hand from its diff, then run recover again;
#   * no sentinel: nothing to recover; a stray copy is removed (exit 0).
# MUTATE_ROOT overrides the main tree (its tests run on a fixture repository).
set -uo pipefail
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="${MUTATE_ROOT:-$(cd "$TOOLS/.." && pwd)}"
# shellcheck source=/dev/null
. "$TOOLS/lib_evidence.sh"
WT="$(_mutants_dir)"
WT0="$WT"                                       # the base of the parallel workers' worktrees (-1 … -N)

# _ours — 0 when $WT is a worktree of $MAIN's repository, marked as its mutant worktree
_ours() {
    [ -d "$WT" ] || return 1
    local a b
    a="$(cd "$MAIN" && realpath "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null)"
    b="$(cd "$WT" && realpath "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null)"
    [ -n "$a" ] && [ "$a" = "$b" ] && [ "$(cat "$WT/.warm/MUTANT_WORKTREE" 2>/dev/null)" = "$MAIN" ]
}

# _same_ignored FILE — 0 when the ignored file FILE is the same in both trees, or in neither
_same_ignored() {
    if [ -f "$MAIN/$1" ]; then cmp -s "$MAIN/$1" "$WT/$1"; else [ ! -e "$WT/$1" ]; fi
}

_setup() {
    local head f n a b
    head="$(git -C "$MAIN" rev-parse --verify --quiet HEAD)" ||
        { echo "mutate: $MAIN has no HEAD" >&2; return 1; }
    if [ -e "$WT" ]; then
        if ! _ours; then
            echo "mutate: REFUSED — $WT exists and is not the mutant worktree of $MAIN" >&2
            return 1
        fi
        if [ -e "$WT/.warm/MUTATION_IN_PROGRESS" ]; then
            echo "mutate: REFUSED — a mutation was left in $WT: tools/mutate.sh recover" >&2
            return 1
        fi
        git -C "$WT" checkout -q --detach -f "$head" || return 1
        git -C "$WT" clean -q -fd || return 1              # an earlier chunk's untracked files
    else
        git -C "$MAIN" worktree add -q --detach "$WT" "$head" || return 1
        mkdir -p "$WT/.warm"
        printf '%s\n' "$MAIN" > "$WT/.warm/MUTANT_WORKTREE"
    fi
    # the chunk's uncommitted work, copied over the checkout
    n="$(python3 "$TOOLS/mutate_drive.py" --sync "$MAIN" "$WT")" || return 1
    # THE GUARD — both sides non-empty: a fingerprint over NO files is still a hash
    a="$(_tree_fp "$MAIN")"
    b="$(_tree_fp "$WT")"
    [ -n "${MUTATE_FAULT_FP:-}" ] && b="$MUTATE_FAULT_FP"      # TEST SEAM (test/test_gate_split.jl)
    if [ "$(git -C "$MAIN" ls-files -co --exclude-standard | wc -l)" -le 0 ] ||
        [ -z "$a" ] || [ "$a" != "$b" ]; then
        echo "mutate: REFUSED — the worktree does not hold the main tree's content (fingerprints ${a:0:12} and ${b:0:12}): a mutant there would be judged on other code" >&2
        return 1
    fi
    for f in Manifest.toml LocalPreferences.toml; do
        _same_ignored "$f" || { echo "mutate: REFUSED — $f differs between the trees" >&2; return 1; }
    done
    echo "mutate: worktree $WT at ${head:0:7}, detached, + $n uncommitted file(s); fingerprint ${a:0:12} on both trees"
}

# _wenv CMD… — CMD with the worktree daemon's settings: a depot of its own, its memory cap
_wenv() {
    env LOGICKERNEL_WARM_DEPOT="$WT/.warm/depot" \
        LOGICKERNEL_TEST_MEM_MAX="${LOGICKERNEL_MUTANTS_MEM_MAX:-6G}" \
        LOGICKERNEL_WARM_HEAP_HINT="${LOGICKERNEL_MUTANTS_HEAP_HINT:-4G}" "$@"
}

# _run TREE MUTANTS TARGET… [-- ID…]
_run() {
    local tree="$1" mutants
    shift
    [ $# -ge 2 ] || { echo "usage: tools/mutate.sh run MUTANTS.py TARGET… [-- ID…]" >&2; return 2; }
    [ -f "$1" ] || { echo "mutate: no such mutant list: $1" >&2; return 2; }
    mutants="$(realpath "$1")"
    shift
    if [ "$tree" = "$MAIN" ]; then
        exec "$MAIN/tools/warm.sh" locked python3 "$MAIN/tools/mutate_drive.py" "$MAIN" "$mutants" "$@"
    fi
    if _evidence_running "$MAIN"; then
        echo "mutate: REFUSED — an evidence run holds the main lane: mutants do not share the machine with it (exit 5)" >&2
        return 5
    fi
    _setup || return 1
    cd "$WT" || return 1
    _wenv tools/warm.sh start || return 1
    _wenv tools/warm.sh locked python3 "$WT/tools/mutate_drive.py" "$WT" "$mutants" "$@"
}

# _par_dirs N — the worktrees of an N-worker run
_par_dirs() { local k; for k in $(seq 1 "$1"); do echo "$WT0-$k"; done; }

# _run_parallel N MUTANTS TARGET… [-- ID…]
_run_parallel() {
    local n="${1:-}" mutants out k rc=0 avail total per need pids=() rcs=()
    shift
    case "$n" in 2 | 3) ;; *) echo "usage: tools/mutate.sh run-parallel N(2|3) MUTANTS.py TARGET… [-- ID…]" >&2; return 2 ;; esac
    [ $# -ge 2 ] || { echo "usage: tools/mutate.sh run-parallel N MUTANTS.py TARGET… [-- ID…]" >&2; return 2; }
    [ -f "$1" ] || { echo "mutate: no such mutant list: $1" >&2; return 2; }
    mutants="$(realpath "$1")"
    shift
    if _evidence_running "$MAIN"; then
        echo "mutate: REFUSED — an evidence run holds the main lane: mutants do not share the machine with it (exit 5)" >&2
        return 5
    fi
    # THE MEMORY RULE (TEST SEAMS: the three LOGICKERNEL_MUTANTS_* numbers)
    avail="${LOGICKERNEL_MUTANTS_AVAIL_MB:-$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)}"
    total="${LOGICKERNEL_MUTANTS_TOTAL_MB:-$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)}"
    per="${LOGICKERNEL_MUTANTS_WORKER_MB:-2500}"
    need=$((n * per + total / 4))
    if [ "${avail:-0}" -lt "$need" ]; then
        echo "mutate: REFUSED — $n workers need ~$need MB free ($n x $per + 25% of $total), $avail MB are available (exit 4)" >&2
        return 4
    fi
    out="${MUTATE_OUT:-$(dirname "$mutants")}"
    for k in $(seq 1 "$n"); do
        mkdir -p "$out/par$k"
        rm -f "$out/par$k/verdicts.tsv"
        # one after the other: each start precompiles into the worker's own depot
        (WT="$WT0-$k"; _setup && cd "$WT" && _wenv env LOGICKERNEL_WARM_SIBLING_MUTANTS=1 tools/warm.sh start) || return 1
    done
    for k in $(seq 1 "$n"); do
        (
            WT="$WT0-$k"
            cd "$WT" || exit 1
            MUTATE_SHARD="$k/$n" MUTATE_OUT="$out/par$k" _wenv env LOGICKERNEL_WARM_SIBLING_MUTANTS=1 \
                tools/warm.sh locked python3 "$WT/tools/mutate_drive.py" "$WT" "$mutants" "$@" > "$out/par$k/driver.log" 2>&1
        ) &
        pids+=($!)
    done
    for k in $(seq 0 $((n - 1))); do
        wait "${pids[$k]}"; rcs+=($?)
    done
    for k in $(seq 1 "$n"); do echo "--- worker $k (exit ${rcs[$((k - 1))]}):"; tail -n 4 "$out/par$k/driver.log"; done
    for r in "${rcs[@]}"; do [ "$r" -ge 2 ] && rc=2; done           # a baseline not green, a crash
    local args=() ; for k in $(seq 1 "$n"); do args+=("$out/par$k"); done
    python3 "$TOOLS/mutate_drive.py" --merge "$mutants" "$out" "${args[@]}"
    local mrc=$?
    [ "$rc" -eq 2 ] && return 2
    return "$mrc"
}

_status() {
    local m="no mutation in progress"
    [ -e "$MAIN/.warm/MUTATION_IN_PROGRESS" ] && m="MUTATION IN PROGRESS"
    echo "main tree:  $MAIN — $m"
    if _ours; then
        m="no mutation in progress"
        [ -e "$WT/.warm/MUTATION_IN_PROGRESS" ] && m="MUTATION IN PROGRESS"
        echo "worktree:   $WT at $(git -C "$WT" rev-parse --short HEAD) — $m"
        (cd "$WT" && tools/warm.sh status) || true
    else
        echo "worktree:   none at $WT"
    fi
}

_remove() {
    if [ ! -e "$WT" ]; then
        echo "mutate: no worktree at $WT"
        return 0
    fi
    _ours || { echo "mutate: REFUSED — $WT is not the mutant worktree of $MAIN" >&2; return 1; }
    if _lane_held "$WT"; then
        echo "mutate: REFUSED — a run holds the worktree's lane" >&2
        return 1
    fi
    (cd "$WT" && tools/warm.sh stop > /dev/null 2>&1)
    git -C "$MAIN" worktree remove --force "$WT" || return 1
    git -C "$MAIN" worktree prune
    echo "mutate: worktree $WT removed"
}

# _recover TREE
_recover() {
    local ROOT="$1"
    local SENTINEL="$ROOT/.warm/MUTATION_IN_PROGRESS" SAVED="$ROOT/.warm/MUTATION_ORIGINAL"
    if [ ! -e "$SENTINEL" ]; then
        [ -e "$SAVED" ] && rm -f "$SAVED"
        echo "mutate: $ROOT: no mutation in progress — nothing to recover"
        return 0
    fi
    local file sha mutant
    file="$(sed -n 's/^file=//p' "$SENTINEL")"
    sha="$(sed -n 's/^sha256=//p' "$SENTINEL")"
    mutant="$(sed -n 's/^mutant=//p' "$SENTINEL")"
    if [ -z "$file" ] || [ -z "$sha" ]; then
        echo "mutate: REFUSED — the sentinel names no file or no SHA-256:" >&2
        sed 's/^/    /' "$SENTINEL" >&2
        return 1
    fi
    if [ ! -e "$SAVED" ] || [ "$(sha256sum < "$SAVED" | cut -d' ' -f1)" != "$sha" ]; then
        echo "mutate: REFUSED — the copy saved before mutant '$mutant' is missing or not the one the" >&2
        echo "  sentinel records; restore $file by hand (git diff it), then run recover again." >&2
        return 1
    fi
    if [ "$(sha256sum < "$ROOT/$file" | cut -d' ' -f1)" = "$sha" ]; then
        echo "mutate: $file is intact (mutant '$mutant' was restored before the driver stopped)"
    else
        echo "mutate: $file still holds mutant '$mutant' — restoring it from the saved copy:"
        diff "$ROOT/$file" "$SAVED" | sed 's/^/    /'
        cp "$SAVED" "$ROOT/$file"
        if [ "$(sha256sum < "$ROOT/$file" | cut -d' ' -f1)" != "$sha" ]; then
            echo "mutate: REFUSED — $file does not match the saved copy after the restore" >&2
            return 1
        fi
        echo "mutate: $file restored"
    fi
    rm -f "$SENTINEL" "$SAVED"                      # first the sentinel, then the copy
    echo "mutate: $ROOT: sentinel removed"
    return 0
}

cmd="${1:-}"
shift || true
case "$cmd" in
    setup) _setup ;;
    run) _run "$WT" "$@" ;;
    run-in-tree) _run "$MAIN" "$@" ;;
    run-parallel) _run_parallel "$@" ;;
    recover)
        rc=0
        _recover "$MAIN" || rc=1
        for WT in "$WT0" $(_par_dirs 3); do
            if _ours; then _recover "$WT" || rc=1; fi
        done
        exit "$rc"
        ;;
    status) _status ;;
    remove)
        rc=0
        for WT in "$WT0" $(_par_dirs 3); do
            { [ ! -e "$WT" ] && [ "$WT" != "$WT0" ]; } && continue
            _remove || rc=1
        done
        exit "$rc"
        ;;
    *) sed -n '2,11p' "$0"; exit 2 ;;
esac
