#!/usr/bin/env bash
# ORIGINAL: the oracle cache's own tests (user, 2026-10-12: every guard mutation-proved) — no
# swipl-devel counterpart. tools/test_oracle_cache.sh — exit 0 only if every case passes.
#
# The REAL swipl is a COUNTING STAND-IN that runs the real one, so a hit is proved by the counter
# not moving, and a cache that "hits" on the wrong thing by the answer being wrong.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REAL="$(command -v swipl)"
[ -n "$REAL" ] || { echo "test_oracle_cache: no swipl on PATH"; exit 1; }
W="$(mktemp -d "${TMPDIR:-/tmp}/oc.XXXXXX")"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
cat > "$W/bin/swipl" <<SH
#!/usr/bin/env bash
echo x >> "$W/count"
exec "$REAL" "\$@"
SH
chmod +x "$W/bin/swipl"
export PATH="$ROOT/tools/oracle_cache:$W/bin:$PATH"
export LOGICKERNEL_ORACLE_CACHE_DIR="$W/cache" LOGICKERNEL_ORACLE_STATS="$W/stats" LOGICKERNEL_ORACLE_PIN=aaaaaaaaaaaaaaaaaaaa
fail=0
ok() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: got '$1', want '$2'"; fail=1; fi; }
calls() { [ -f "$W/count" ] && wc -l < "$W/count" | tr -d ' ' || echo 0; }
last() { tail -1 "$W/stats"; }
prog() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/r.pl"; }

prog "$W/a" 'main :- X is 6*7, write(X), nl.'
out1="$(swipl -q -g main -t halt "$W/a/r.pl" < /dev/null)"; c1=$(calls)
ok "$out1/$(last)" "42/miss" "a first call runs the real swipl and is a miss"
prog "$W/b" 'main :- X is 6*7, write(X), nl.'
out2="$(swipl -q -g main -t halt "$W/b/r.pl" < /dev/null)"
ok "$out2/$(last)/$(calls)" "42/hit/$c1" "the same program in ANOTHER directory is a hit; the real swipl is not run"
prog "$W/c" 'main :- X is 6*8, write(X), nl.'
ok "$(swipl -q -g main -t halt "$W/c/r.pl" < /dev/null)/$(last)" "48/miss" "other program text is a miss"
printf 'extra(1).\n' > "$W/c/other.pl"
swipl -q -g main -t halt "$W/c/r.pl" < /dev/null > /dev/null
ok "$(last)" "miss" "a sibling file in the directory changes the key"

# the directory in an error message is the CURRENT run's
prog "$W/d" 'main :- write(hi), nl.
foo(.'
e1="$(swipl -q -g main -t halt "$W/d/r.pl" 2>&1 < /dev/null)"
prog "$W/e" 'main :- write(hi), nl.
foo(.'
e2="$(swipl -q -g main -t halt "$W/e/r.pl" 2>&1 < /dev/null)"
ok "$(last)" "hit" "a merged-stream call hits"
case "$e2" in *"$W/e/r.pl"*) r=current ;; *) r=stale ;; esac
case "$e2" in *"$W/d/"*) r=stale ;; esac
ok "$r" "current" "a hit puts back the CURRENT directory (was: ${e1:0:0}tokenised)"

n=$(calls); swipl -q -g main -t halt "$W/e/r.pl" < /dev/null 2> "$W/o2" > "$W/o1"
ok "$(calls)/$(last)" "$((n + 1))/miss" "the same program with stdout and stderr apart is a miss, not the merged entry"

prog "$W/k" 'main :- write(a), nl, flush_output, format(user_error, "b~n", []), write(c), nl, flush_output, format(user_error, "d~n", []).'
m1="$(swipl -q -g main -t halt "$W/k/r.pl" 2>&1 < /dev/null)"; m2="$(swipl -q -g main -t halt "$W/k/r.pl" 2>&1 < /dev/null)"
ok "$(echo $m1)/$(echo $m2)/$(last)" "a b c d/a b c d/hit" "a merged stream keeps its interleaving on a hit"

# the exit code
prog "$W/f" 'main :- halt(3).'
swipl -q -g main -t halt "$W/f/r.pl" < /dev/null; r1=$?
swipl -q -g main -t halt "$W/f/r.pl" < /dev/null; r2=$?
ok "$r1/$r2/$(last)" "3/3/hit" "the exit code is kept"
prog "$W/g" 'main :- halt(130).'
swipl -q -g main -t halt "$W/g/r.pl" < /dev/null; swipl -q -g main -t halt "$W/g/r.pl" < /dev/null
ok "$(last)" "bypass" "an exit code of 124 or more is never cached (the second call is not a hit)"
n=$(calls); swipl -q -g main -t halt "$W/g/r.pl" < /dev/null
ok "$(calls)" "$((n + 1))" "…so the real swipl runs again"

# bypasses
prog "$W/h" 'main :- X is random(100), X >= 0, write(ok), nl.'
swipl -q -g main -t halt "$W/h/r.pl" < /dev/null > /dev/null
ok "$(last)" "bypass" "a program that reads the random generator is a bypass"
swipl -q -g "write('/x'), nl" -t halt < /dev/null > /dev/null
ok "$(last)" "bypass" "an argument with a / that is no file is a bypass"
swipl --version > /dev/null; n=$(calls); v="$(swipl --version)"; ok "$(calls)/${v:0:5}" "$((n + 1))/SWI-P" "--version always asks the real oracle (a second call too)"

# stdin and the pin are in the key
prog "$W/j" 'main :- read(X), write(got(X)), nl.'
printf 'a.\n' | swipl -q -g main -t halt "$W/j/r.pl" > /dev/null; printf 'b.\n' | swipl -q -g main -t halt "$W/j/r.pl" > /dev/null
ok "$(last)" "miss" "other stdin is a miss"
o="$(printf 'b.\n' | swipl -q -g main -t halt "$W/j/r.pl")"
ok "$o/$(last)" "got(b)/hit" "the same stdin is a hit"
n=$(calls)
LOGICKERNEL_ORACLE_PIN=bbbbbbbbbbbbbbbbbbbb swipl -q -g main -t halt "$W/a/r.pl" < /dev/null > /dev/null
ok "$(calls)/$(last)" "$((n + 1))/miss" "another pin is a miss"
n=$(calls)
LOGICKERNEL_ORACLE_PIN=aaaaaaaaaaaaxxxxxxxx swipl -q -g main -t halt "$W/a/r.pl" < /dev/null > /dev/null
ok "$(calls)/$(last)" "$((n + 1))/miss" "a pin that shares its first 12 characters is a miss: the key holds the whole pin"
n=$(calls); LOGICKERNEL_ORACLE_CACHE=0 swipl -q -g main -t halt "$W/a/r.pl" < /dev/null > /dev/null
ok "$(calls)" "$((n + 1))" "LOGICKERNEL_ORACLE_CACHE=0 runs the real swipl"
n=$(calls); env -u LOGICKERNEL_ORACLE_PIN swipl -q -g main -t halt "$W/a/r.pl" < /dev/null > /dev/null
ok "$(calls)" "$((n + 1))" "no pin: the real swipl, nothing cached"

# the real binary's identity is in the key
touch -d '2001-01-01' "$W/bin/swipl"
n=$(calls); swipl -q -g main -t halt "$W/a/r.pl" < /dev/null > /dev/null
ok "$(calls)" "$((n + 1))" "another binary (its mtime) is a miss"

# the evidence workers are systemd units with their own environment: the shim's variables must be passed
for v in LOGICKERNEL_ORACLE_PIN LOGICKERNEL_ORACLE_STATS LOGICKERNEL_ORACLE_CACHE_DIR; do
    n=$(grep -c -- "-E $v=" "$ROOT/tools/lib_evidence.sh")
    ok "$n" "1" "_spawn_worker passes $v to the worker unit"
done

# one environment for both spawners (2026-10-13: the preflight's pool was spawned without it, and the
# evidence run that claimed the pool showed 0/0/0): `_oracle_env` exports the pin, the shim on PATH once,
# and the stats file; tools/warm.sh's pool calls it; tools/run_tests.sh folds the pool's count
oe="$( (
    . "$ROOT/tools/lib_evidence.sh"
    PATH="/usr/bin:/bin"; unset LOGICKERNEL_ORACLE_PIN LOGICKERNEL_ORACLE_CACHE
    _oracle_env "$ROOT" "$W/pool_stats"; _oracle_env "$ROOT" "$W/pool_stats"
    n=$(printf '%s' "$PATH" | tr ':' '\n' | grep -c -x "$ROOT/tools/oracle_cache")
    printf '%s|%s|%s' "${#LOGICKERNEL_ORACLE_PIN}" "$n" "$LOGICKERNEL_ORACLE_STATS"
) )"
ok "$oe" "40|1|$W/pool_stats" "_oracle_env exports the 40-character pin, the shim on PATH exactly once, the stats file"
oe0="$( ( . "$ROOT/tools/lib_evidence.sh"; unset LOGICKERNEL_ORACLE_PIN; LOGICKERNEL_ORACLE_CACHE=0 _oracle_env "$ROOT" x; printf '%s' "${LOGICKERNEL_ORACLE_PIN:-none}" ) )"
ok "$oe0" "none" "…and nothing under LOGICKERNEL_ORACLE_CACHE=0"
n=$(sed -n '/^_pool() {/,/^}/p' "$ROOT/tools/warm.sh" | grep -c '_oracle_env "$ROOT" "$(_oracle_pool_stats "$ROOT")"')
ok "$n" "1" "tools/warm.sh's pool exports the oracle environment before it spawns"
n=$(grep -c 'cat "$(_oracle_pool_stats "$ROOT")" >> "$LOGICKERNEL_ORACLE_STATS"' "$ROOT/tools/run_tests.sh")
ok "$n" "1" "tools/run_tests.sh folds the pool's count into its own"

[ $fail -eq 0 ] && echo "test_oracle_cache: all cases pass" || echo "test_oracle_cache: FAILED"
exit $fail
