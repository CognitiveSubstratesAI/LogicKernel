#!/usr/bin/env bash
# ORIGINAL: builds the oracle — SWI-Prolog at the pinned commit; no swipl-devel counterpart.
# tools/build_oracle.sh — THE ORACLE IS BUILT FROM THE PINNED COMMIT, here and in CI, by this one
# recipe (user, 2026-10-11). Every live differential is judged against `swipl`; the ports cite one
# upstream commit (tools/SWIPL_VERSION, `commit:`); so the oracle is a build of exactly that
# commit — not a release image some commits away from it — and each gate asserts it
# (tools/lib_evidence.sh `_check_swipl_pin`: the binary's `version_git` names the pinned commit).
#
#   tools/build_oracle.sh PREFIX     # build and install into PREFIX (PREFIX/bin/swipl)
#   tools/build_oracle.sh --key      # the cache key: the commit and a hash of the build flags
#
# BACKPORTS (BP2, audit D-0175/D-0221): when the pin names `backports:` (upstream commits made after
# `commit`, in upstream's order) the build is `commit` WITH THEM cherry-picked, and the pin's `oracle:` line
# names the result. The committer is fixed (name, e-mail, the backport's own author date) so the
# cherry-picked commits are THE SAME COMMITS on every machine: the build's `version_git` then names
# `oracle:`, which the pin checks (tools/lib_evidence.sh `_check_swipl_pin`) compare it to, and a clone
# that lacks a backport fetches it from `origin`.
#
# ORACLE_REPO: what to clone (default: SWI-Prolog's repository; a local clone that has the commit
# is faster). ORACLE_WORK: where to clone and build (default: PREFIX.work; left in place).
# The build is the core system and THREE PACKAGES, Release, with GMP — the FLAGS below are part of the
# cache key, so a changed flag is a new oracle. THE PACKAGES (user, 2026-10-14): plunit, which the
# kernel vendors at the commit the pin names (`plunit:`; packages/plunit), so the oracle runs
# upstream's test files with the same plunit the kernel loads; and its dependency closure as
# upstream's package selection declares it — plunit needs clib, clib needs sgml
# (cmake/PackageSelection.cmake `SWIPL_PKG_DEPS_plunit`, `SWIPL_PKG_DEPS_clib`). Each is
# the submodule commit the pinned swipl-devel commit records; plunit's must equal the pin's.
# ORACLE_PKG_BASE: where the package repositories are (default: SWI-Prolog's on GitHub — the
# submodule URLs are relative, so a local ORACLE_REPO would otherwise look for them beside it).
#
# 🔴 A FULL CLONE, NEVER A PARTIAL ONE, AND THE WHOLE BUILD IN A CAPPED SCOPE. MEASURED 2026-10-11:
# the first version cloned with `--filter=blob:none` from a LOCAL repository. That made an EMPTY
# promisor clone, in which every git command fetches the object it lacks — and the fetch lacks it
# too, and fetches: `git fetch` → `git-upload-pack` → `pack-objects` → `git fetch` → …, thousands
# of small processes, 20 GB in a few minutes, and the kernel's OOM killer took the session and the
# machine. No process was big, so nothing looked like a runaway; and the build ran as a plain
# background command, in no memory-capped unit — the one kind of work here that was not. So:
# no `--filter`; GIT_NO_LAZY_FETCH on every git call; and where user systemd exists the script
# re-runs itself in a scope with a memory ceiling AND a task ceiling (ORACLE_MEM_MAX, 6G;
# ORACLE_TASKS_MAX, 512): a runaway is then one killed job, not a dead machine.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GIT_NO_LAZY_FETCH=1
if [ "${1:-}" != "--key" ] && [ -z "${ORACLE_CAPPED:-}" ] && command -v systemd-run > /dev/null 2>&1 &&
    systemd-run --user --scope true > /dev/null 2>&1; then
    exec env ORACLE_CAPPED=1 systemd-run --user --scope --quiet \
        -p MemoryMax="${ORACLE_MEM_MAX:-6G}" -p MemorySwapMax=0 \
        -p TasksMax="${ORACLE_TASKS_MAX:-512}" "$0" "$@"
fi
FLAGS=(-DCMAKE_BUILD_TYPE=Release -DSWIPL_PACKAGES=OFF "-DSWIPL_PACKAGE_LIST=sgml;clib;plunit"
    -DINSTALL_DOCUMENTATION=OFF -DBUILD_TESTING=OFF -DUSE_GMP=ON -DUSE_TCMALLOC=OFF)
PKGS=(sgml clib plunit)
COMMIT="$(sed -n 's/^commit:[[:space:]]*//p' "$ROOT/tools/SWIPL_VERSION" | tr -d '[:space:]')"
if ! printf '%s' "$COMMIT" | grep -qE '^[0-9a-f]{40}$'; then
    echo "build_oracle: tools/SWIPL_VERSION names no pinned commit (a \`commit: <40 hex>\` line)" >&2
    exit 1
fi
read -r -a BACKPORTS <<< "$(sed -n 's/^backports:[[:space:]]*//p' "$ROOT/tools/SWIPL_VERSION")"
ORACLE="$(sed -n 's/^oracle:[[:space:]]*//p' "$ROOT/tools/SWIPL_VERSION" | tr -d '[:space:]')"
WANT="$COMMIT"                                    # the commit the build's version_git must name
if [ "${#BACKPORTS[@]}" -gt 0 ]; then
    for b in "${BACKPORTS[@]}"; do
        printf '%s' "$b" | grep -qE '^[0-9a-f]{40}$' ||
            { echo "build_oracle: tools/SWIPL_VERSION: backport '$b' is not a 40-digit commit" >&2; exit 1; }
    done
    printf '%s' "$ORACLE" | grep -qE '^[0-9a-f]{40}$' ||
        { echo "build_oracle: tools/SWIPL_VERSION names backports but no \`oracle: <40 hex>\` (the commit they make)" >&2; exit 1; }
    WANT="$ORACLE"
elif [ -n "$ORACLE" ]; then
    echo "build_oracle: tools/SWIPL_VERSION names an oracle but no backports" >&2
    exit 1
fi
if [ "${1:-}" = "--key" ]; then
    echo "swipl-${WANT:0:12}-$(printf '%s\n' "${FLAGS[@]}" | sha256sum | cut -c1-12)"
    exit 0
fi
PREFIX="${1:?usage: tools/build_oracle.sh PREFIX | --key}"
case "$PREFIX" in /*) ;; *) PREFIX="$PWD/$PREFIX" ;; esac
REPO="${ORACLE_REPO:-https://github.com/SWI-Prolog/swipl-devel.git}"
WORK="${ORACLE_WORK:-$PREFIX.work}"
mkdir -p "$WORK"
if [ ! -d "$WORK/src/.git" ]; then
    # the whole history and its tags: cmake names the build with `git describe`
    git clone -q --no-checkout "$REPO" "$WORK/src"
fi
if grep -qE '^[[:space:]]*(promisor|partialclonefilter)[[:space:]]*=' "$WORK/src/.git/config"; then
    echo "build_oracle: $WORK/src is a PARTIAL clone — refused (see the header); remove it" >&2
    exit 1
fi
# a clone copies the source's BRANCHES; in a local clone that was only fetched, the commit hangs
# from a remote-tracking ref (MEASURED: the pinned commit was not in the clone) — take those too
git -C "$WORK/src" cat-file -e "$COMMIT^{commit}" 2> /dev/null ||
    git -C "$WORK/src" fetch -q origin '+refs/remotes/origin/*:refs/remotes/upstream/*' || true
git -C "$WORK/src" cat-file -e "$COMMIT^{commit}" 2> /dev/null ||
    { echo "build_oracle: $REPO does not have the pinned commit $COMMIT (fetch it there first)" >&2; exit 1; }
git -C "$WORK/src" -c advice.detachedHead=false checkout -q --detach "$COMMIT"
[ "$(git -C "$WORK/src" rev-parse HEAD)" = "$COMMIT" ] ||
    { echo "build_oracle: the checkout is not at $COMMIT" >&2; exit 1; }
PKG_BASE="${ORACLE_PKG_BASE:-https://github.com/SWI-Prolog}"
for p in "${PKGS[@]}"; do
    git -C "$WORK/src" config "submodule.packages/$p.url" "$PKG_BASE/packages-$p.git"
    git -C "$WORK/src" submodule update -q --init "packages/$p"
    want="$(git -C "$WORK/src" ls-tree HEAD "packages/$p" | awk '{print $3}')"
    [ -n "$want" ] && [ "$(git -C "$WORK/src/packages/$p" rev-parse HEAD)" = "$want" ] ||
        { echo "build_oracle: packages/$p is not at the commit $COMMIT records ($want)" >&2; exit 1; }
done
PLUNIT="$(sed -n 's/^plunit:[[:space:]]*//p' "$ROOT/tools/SWIPL_VERSION" | tr -d '[:space:]')"
[ "$(git -C "$WORK/src/packages/plunit" rev-parse HEAD)" = "$PLUNIT" ] ||
    { echo "build_oracle: packages/plunit at $COMMIT is not the pin's plunit (${PLUNIT:-none})" >&2; exit 1; }
# the backports, in order, as the same commits everywhere (the header)
for b in "${BACKPORTS[@]}"; do
    git -C "$WORK/src" cat-file -e "$b^{commit}" 2> /dev/null ||
        git -C "$WORK/src" fetch -q origin "$b" 2> /dev/null ||
        { echo "build_oracle: the backport $b is in neither the clone nor its origin" >&2; exit 1; }
    GIT_COMMITTER_NAME="LogicKernel oracle" GIT_COMMITTER_EMAIL="oracle@logickernel.invalid" \
        GIT_COMMITTER_DATE="$(git -C "$WORK/src" show -s --format=%aI "$b")" \
        git -C "$WORK/src" -c commit.gpgsign=false cherry-pick "$b" > "$WORK/cherry-pick.log" 2>&1 ||
        { cat "$WORK/cherry-pick.log" >&2; echo "build_oracle: the backport $b does not apply on $COMMIT" >&2; exit 1; }
done
[ "$(git -C "$WORK/src" rev-parse HEAD)" = "$WANT" ] ||
    { echo "build_oracle: the checkout with its backports is $(git -C "$WORK/src" rev-parse HEAD), the pin's oracle: is $WANT" >&2; exit 1; }
GEN=()
command -v ninja > /dev/null 2>&1 && GEN=(-G Ninja)
cmake -S "$WORK/src" -B "$WORK/build" "${GEN[@]}" "${FLAGS[@]}" -DCMAKE_INSTALL_PREFIX="$PREFIX" > "$WORK/cmake.log" 2>&1 ||
    { tail -30 "$WORK/cmake.log" >&2; exit 1; }
cmake --build "$WORK/build" -j "$(nproc)" > "$WORK/build.log" 2>&1 ||
    { tail -40 "$WORK/build.log" >&2; exit 1; }
cmake --install "$WORK/build" > "$WORK/install.log" 2>&1 ||
    { tail -30 "$WORK/install.log" >&2; exit 1; }
got="$("$PREFIX/bin/swipl" -g "current_prolog_flag(version_git, G), writeln(G)" -t halt)"
echo "build_oracle: $("$PREFIX/bin/swipl" --version) — version_git $got — in $PREFIX"
case "$got" in
    *-g*) [ "${WANT#"${got##*-g}"}" != "$WANT" ] ||
        { echo "build_oracle: the build's version_git ($got) does not name $WANT" >&2; exit 1; } ;;
    *) echo "build_oracle: the build has no version_git naming a commit ($got)" >&2; exit 1 ;;
esac
echo "build_oracle: the clone and the build are in $WORK (not needed once installed)"
