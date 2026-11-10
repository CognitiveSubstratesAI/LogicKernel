#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the command line of tools/lib_julia.sh, the local Julia pin (audit D-0465, D-0466).
#
#   tools/julia_pin.sh want                  print the pinned version (tools/WARM_JULIA_VERSION)
#   tools/julia_pin.sh path [gate]           print the PATH with the pinned Julia first (mutate_ci.py sets it)
#   tools/julia_pin.sh run [gate] CMD [ARG…] run CMD under the pinned Julia, e.g. the fuzzer by hand:
#                                            tools/julia_pin.sh run julia --project=. tools/fuzz.jl 5000 300
# Exit 7 and a message on stderr when the pin is not installed, the version found differs, or
# LOGICKERNEL_JULIA_PIN_OFF=1 is set under `gate` (see tools/lib_julia.sh). 64: usage.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/tools/lib_julia.sh"
sub="${1:-}"
shift || true
gate=""
if [ "${1:-}" = gate ]; then gate=gate; shift; fi
case "$sub" in
    want) _julia_pin_want "$ROOT" || { echo "julia_pin: tools/WARM_JULIA_VERSION is missing or holds no version" >&2; exit 7; }; echo ;;
    path) _julia_pin_apply "$ROOT" julia_pin "$gate" || exit $?; printf '%s\n' "$PATH" ;;
    run)
        [ $# -ge 1 ] || { echo "usage: tools/julia_pin.sh run [gate] CMD [ARG…]" >&2; exit 64; }
        _julia_pin_apply "$ROOT" julia_pin "$gate" || exit $?
        exec "$@"
        ;;
    *) echo "usage: tools/julia_pin.sh want | path [gate] | run [gate] CMD [ARG…]" >&2; exit 64 ;;
esac
