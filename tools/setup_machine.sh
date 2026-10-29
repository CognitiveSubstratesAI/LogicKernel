#!/usr/bin/env bash
# ORIGINAL: the fresh-machine setup (audit D-0129 S4, D-0130 item 2) — no swipl-devel counterpart.
# tools/setup_machine.sh — everything a checkout needs to run its gates on a machine that has nothing, in the
# order CI's workflow steps do it (.github/actions/oracle, CI.yml `analysis` and `tooling`, evidence.yml):
#
#   tools/setup_machine.sh            # do every step that is not already done (idempotent)
#   tools/setup_machine.sh --plan     # print the steps and what each would do; change nothing
#   tools/setup_machine.sh --check    # verify the machine: one line per component, exit 1 if one is missing
#   tools/setup_machine.sh --no-oracle    # everything but the swipl build (the slow step, 15-30 minutes)
#
# THE STEPS (each skipped when it is already true; the order is the dependency order):
#   1. system packages (apt): a C/C++ toolchain, cmake, ninja, GMP and zlib headers, git, curl, python3 — the
#      oracle's build and the tooling's scripts. Needs root or sudo; on a machine without apt, install the same by hand.
#   2. Julia 1.13 through juliaup (the channel CI's setup-julia uses): https://install.julialang.org.
#   3. the global Julia environment, as CI installs it: JET, LoweredCodeUtils and Aqua from master (they release
#      together), AllocCheck, JuliaFormatter 2.14.0 (the version CI pins), Revise (the warm daemon loads it).
#   4. the project: `Pkg.instantiate()` in the checkout.
#   5. the oracle: swipl at the pin (tools/SWIPL_VERSION), built by tools/build_oracle.sh into $LK_ORACLE_PREFIX
#      (default ~/swipl-oracle) and checked to BE that build; put $LK_ORACLE_PREFIX/bin on PATH (printed at the end).
#   6. a user systemd manager (`loginctl enable-linger`), where systemd exists: the warm daemon and the capped runs are
#      `systemd-run --user` units. Skipped, with a note, in a container.
# --check verifies 1-6 and runs the quick proof (`using LogicKernel`; the pinned swipl answers) — NOT the test suite.
#
# Tested on a clean ubuntu:24.04 container by .github/workflows/setup.yml (weekly, on a change to this file, by hand).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORACLE="${LK_ORACLE_PREFIX:-$HOME/swipl-oracle}"
mode=do
want_oracle=1
for a in "$@"; do
    case "$a" in
        --plan) mode=plan ;;
        --check) mode=check ;;
        --no-oracle) want_oracle=0 ;;
        -h | --help) sed -n '2,/^set -/p' "$0" | sed 's/^# \{0,1\}//; /^set -/d'; exit 0 ;;
        *) echo "setup_machine: unknown argument $a (see --help)" >&2; exit 2 ;;
    esac
done
export PATH="$HOME/.juliaup/bin:$ORACLE/bin:$PATH"

APT_BASE=(git curl ca-certificates python3)                          # always
APT_BUILD=(build-essential cmake ninja-build libgmp-dev zlib1g-dev pkg-config)   # the oracle's build, when it is still to be built
SUDO=""
[ "$(id -u)" = 0 ] || SUDO="sudo"

apt_wanted() {   # the packages this machine still needs: the base, and the build tools unless the oracle is there (or not wanted)
    printf '%s\n' "${APT_BASE[@]}"
    if [ "$want_oracle" = 1 ] && ! have_oracle; then printf '%s\n' "${APT_BUILD[@]}"; fi
}
have_apt_pkgs() {
    command -v dpkg > /dev/null 2>&1 || return 1
    local p
    for p in $(apt_wanted); do dpkg -s "$p" > /dev/null 2>&1 || return 1; done
}
have_julia() { command -v julia > /dev/null 2>&1 && julia --version 2> /dev/null | grep -q '^julia version 1\.13\.'; }
have_global_tools() {
    have_julia && julia -e 'using Pkg; deps = Pkg.project().dependencies
        want = ["JET", "LoweredCodeUtils", "Aqua", "AllocCheck", "JuliaFormatter", "Revise"]
        exit(all(w -> haskey(deps, w), want) ? 0 : 1)' > /dev/null 2>&1
}
have_project() { have_julia && (cd "$ROOT" && julia --project=. -e 'using Pkg; Pkg.instantiate(); using LogicKernel' > /dev/null 2>&1); }
pin() { # the commit the oracle's version_git names: `oracle:` (the pin with its backports) when there is one
    local o
    o="$(sed -n 's/^oracle:[[:space:]]*//p' "$ROOT/tools/SWIPL_VERSION" | tr -d '[:space:]')"
    [ -n "$o" ] && { printf '%s' "$o"; return; }
    sed -n 's/^commit:[[:space:]]*//p' "$ROOT/tools/SWIPL_VERSION" | tr -d '[:space:]'
}
have_oracle() {
    command -v swipl > /dev/null 2>&1 || return 1
    # the binary's version_git names the pinned commit's abbreviation (tools/lib_evidence.sh `_check_swipl_pin`)
    local vg
    vg="$(swipl -g 'current_prolog_flag(version_git, V), write(V)' -t halt 2> /dev/null)"
    [ -n "$vg" ] && [[ "$(pin)" == *"${vg##*-g}"* ]]
}
have_systemd_user() { command -v systemctl > /dev/null 2>&1 && systemd-run --user --scope --quiet true > /dev/null 2>&1; }
no_systemd() { ! command -v systemctl > /dev/null 2>&1 || ! [ -d /run/systemd/system ]; }   # a container: nothing to enable

# name | test function | what the step does
STEPS=(
    "system packages|have_apt_pkgs|apt-get install ${APT_BASE[*]} (+ ${APT_BUILD[*]} while the oracle is to be built)"
    "Julia 1.13 (juliaup)|have_julia|curl -fsSL https://install.julialang.org | sh -s -- --yes --default-channel 1.13"
    "global Julia tools|have_global_tools|Pkg.add JET, LoweredCodeUtils, Aqua (master), AllocCheck, JuliaFormatter 2.14.0, Revise"
    "the project|have_project|julia --project=. -e 'using Pkg; Pkg.instantiate()'"
)
[ "$want_oracle" = 1 ] && STEPS+=("the oracle (swipl at the pin)|have_oracle|tools/build_oracle.sh $ORACLE")
STEPS+=("a user systemd manager|have_systemd_user|loginctl enable-linger (skipped without systemd)")

run_step() {   # run_step NAME
    case "$1" in
        "system packages")
            $SUDO apt-get update -q && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $(apt_wanted) ;;
        "Julia 1.13 (juliaup)")
            curl -fsSL https://install.julialang.org | sh -s -- --yes --default-channel 1.13 ;;
        "global Julia tools")
            julia -e 'using Pkg; Pkg.add([
                PackageSpec(url="https://github.com/JuliaDebug/LoweredCodeUtils.jl", rev="master"),
                PackageSpec(url="https://github.com/aviatesk/JET.jl", rev="master"),
                PackageSpec(url="https://github.com/JuliaTesting/Aqua.jl", rev="master"),
                PackageSpec(name="AllocCheck"),
                PackageSpec(name="JuliaFormatter", version="2.14.0"),
                PackageSpec(name="Revise")])' ;;
        "the project")
            (cd "$ROOT" && julia --project=. -e 'using Pkg; Pkg.instantiate(); using LogicKernel') ;;
        "the oracle (swipl at the pin)")
            "$ROOT/tools/build_oracle.sh" "$ORACLE" ;;
        "a user systemd manager")
            if no_systemd; then echo "  (no systemd here — a container? skipped)"; return 0; fi
            $SUDO loginctl enable-linger "$USER" ;;
    esac
}

fail=0
for s in "${STEPS[@]}"; do
    IFS='|' read -r name test what <<< "$s"
    if "$test"; then state="done"; else state="missing"; fi
    [ "$name" = "a user systemd manager" ] && [ "$state" = missing ] && no_systemd && state="n/a (no systemd)"
    case "$mode" in
        plan) printf '  %-30s %-18s %s\n' "$name" "[$state]" "$what" ;;
        check)
            printf '  %-30s %s\n' "$name" "$state"
            [ "$state" = missing ] && fail=1 ;;
        do)
            if [ "$state" = done ] || [ "$state" = "n/a (no systemd)" ]; then
                printf '  %-30s %s\n' "$name" "$state"
                continue
            fi
            printf '  %-30s running…\n' "$name"
            if ! run_step "$name"; then echo "setup_machine: '$name' failed" >&2; exit 1; fi
            "$test" || [ "$name" = "a user systemd manager" ] || { echo "setup_machine: '$name' ran, but its test still fails" >&2; exit 1; } ;;
    esac
done

case "$mode" in
    plan) echo "setup_machine: plan only — nothing changed" ;;
    check)
        [ "$fail" = 0 ] && echo "setup_machine: the machine is ready" || echo "setup_machine: missing components (run tools/setup_machine.sh)"
        exit "$fail" ;;
    do)
        echo "setup_machine: done. Put these on PATH (your shell profile):"
        echo "  export PATH=\"\$HOME/.juliaup/bin:$ORACLE/bin:\$PATH\""
        echo "  then: tools/setup_machine.sh --check" ;;
esac
