#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the tests of SUMMARY MODE (audit D-0178 item 1): tools/summarize_log.sh,
# `tools/warm.sh … --summary`, `tools/bench.sh --summary`, tools/ci_wait.sh. FAKE inputs only (fake logs, a fake
# `curl`/`pgrep` on PATH); no daemon, no julia, no network.
#
#   tools/test_summary.sh          # exit 0 only if every case passes
#
# Every guard is tested both ways with both sides non-empty: a PASSING fake run must print a pass verdict
# AND its counts, a FAILING one must print the failure's file:line, the output must stay <= 10 lines, and
# the exit status must be the run's own (a guard that cannot pass, cannot fail or compares the wrong thing
# is useless — CLAUDE.md Health Gate).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/summary.XXXXXX")"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
ok() {   # ok NAME WANT GOT
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: got '$3', want '$2'"; fi
}
has() {   # has NAME TEXT PATTERN — TEXT is non-empty and matches the ERE
    if [ -n "$2" ] && printf '%s\n' "$2" | grep -qE -- "$3"; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: no match for /$3/ in: $(printf '%s' "$2" | head -c 300 | tr '\n' '|')"; fi
}
hasnt() {   # hasnt NAME TEXT PATTERN — TEXT is non-empty and does NOT match
    if [ -n "$2" ] && ! printf '%s\n' "$2" | grep -qE -- "$3"; then pass=$((pass + 1)); echo "  ok   $1"
    else fail=$((fail + 1)); echo "  FAIL $1: unexpected /$3/ (or empty) in: $(printf '%s' "$2" | head -c 300 | tr '\n' '|')"; fi
}
nlines() { printf '%s\n' "$1" | grep -c .; }
S="$ROOT/tools/summarize_log.sh"

# ---------------------------------------------------------------- summarize_log.sh
cat > "$W/pass.log" <<'EOF'
warm lane: test/test_a.jl
Test Summary:     | Pass  Total  Time
warm: test_a.jl   |   12     12  0.4s
EOF
cat > "$W/fail.log" <<'EOF'
Test Failed at /home/x/test/test_a.jl:41
  Expression: foo(1) == 2
   Evaluated: 3 == 2
Error During Test at /home/x/test/test_a.jl:77
  Got exception outside of a @test
Test Summary:     | Pass  Fail  Error  Total  Time
warm: test_a.jl   |   10     1      1     12  0.4s
EOF
out="$("$S" file "$W/pass.log" 0 7)"
has "file pass: PASS verdict" "$out" '^file: PASS in 7s'
has "file pass: counts non-empty" "$out" 'pass 12, fail 0, error 0, total 12'
has "file pass: log path" "$out" "log: $W/pass.log"
hasnt "file pass: no failing section" "$out" 'failing'
out="$("$S" file "$W/fail.log" 1 9)"
has "file fail: FAIL verdict with rc" "$out" '^file: FAIL\(rc=1\) in 9s'
has "file fail: file:line and expression" "$out" 'test_a.jl:41  Expression: foo\(1\) == 2'
has "file fail: error place" "$out" 'test_a.jl:77  Got exception'
has "file fail: counts" "$out" 'pass 10, fail 1, error 1, total 12'
has "file fail: failing count" "$out" 'failing \(2\)'
# rc 0 but no verdict line in the log: NO VERDICT, never PASS (the guard can fail)
printf 'warm lane: something\n' > "$W/noverdict.log"
out="$("$S" file "$W/noverdict.log" 0 3)"
has "rc 0 without a summary row is NO VERDICT" "$out" 'NO VERDICT'
hasnt "...and never PASS" "$out" ': PASS'
: > "$W/empty.log"
out="$("$S" check "$W/empty.log" 0 1)"
has "an empty log is NO VERDICT" "$out" 'NO VERDICT'
out="$("$S" check "$W/missing.log" 1 1)"
has "a missing log is NO VERDICT" "$out" 'NO VERDICT'
# check
printf 'format ok\ncheck: PASS (format, port_check, manifest) in 4s\n' > "$W/check_pass.log"
out="$("$S" check "$W/check_pass.log" 0 4)"
has "check pass" "$out" '^check: PASS in 4s — check: PASS'
printf 'port_check: 2 violations\n  src/x.jl: missing header\ncheck: FAIL (format, port_check, manifest) in 5s\n' > "$W/check_fail.log"
out="$("$S" check "$W/check_fail.log" 1 5)"
has "check fail: verdict" "$out" '^check: FAIL\(rc=1\) in 5s'
has "check fail: no recognised failure => last lines shown" "$out" 'none recognised'
has "check fail: the last log line is shown" "$out" 'check: FAIL \(format'
printf 'x\n' > "$W/check_nov.log"
out="$("$S" check "$W/check_nov.log" 0 5)"
has "check rc 0 without its PASS line is NO VERDICT" "$out" 'NO VERDICT'
# static: JET lines count as failures
printf 'JET-test failed at /x/test/static_analysis_body.jl:12\n  no matching method found for call foo(::Int)\nwarm: test_static_analysis.jl | 3 1 4\n' > "$W/static.log"
out="$("$S" static "$W/static.log" 1 60)"
has "static fail: a JET line is a failing place" "$out" 'no matching method found'
printf 'warm lane: JET started\n' > "$W/static_nov.log"
out="$("$S" static "$W/static_nov.log" 0 60)"
has "static rc 0 without its verdict row is NO VERDICT" "$out" 'NO VERDICT'
# the 10-line cap with many failures
{ for i in $(seq 1 30); do printf 'Test Failed at /x/t.jl:%d\n  Expression: e%d\n' "$i" "$i"; done; } > "$W/many.log"
out="$("$S" file "$W/many.log" 1 2)"
ok "30 failures print <= 10 lines" "1" "$([ "$(nlines "$out")" -le 10 ] && echo 1 || echo 0)"
has "...and say how many more" "$out" '25 more in the log'
has "...and the first failure is there" "$out" 't.jl:1  Expression: e1'
# the cap itself: counts + "n test file(s) run" + 30 failures would be 11 lines; the log line must survive the cut
{ printf 'branch-gate: test/test_a.jl\nTest Summary:     | Pass  Fail  Total  Time\nwarm: test_a.jl   |   10     1     11  0.4s\n'
  for i in $(seq 1 30); do printf 'Test Failed at /x/t.jl:%d\n  Expression: e%d\n' "$i" "$i"; done
  printf 'branch-gate: FAIL in 5s\n'; } > "$W/many2.log"
# a branch-gate log carries "warm: <file> | n n time" rows with NO Test Summary header: no zero counts
printf 'branch-gate: test/test_a.jl\nwarm: test_a.jl |  693    693  3m35.5s\nbranch-gate: PASS in 9s\n' > "$W/bg_nohdr.log"
out="$("$S" branch-gate "$W/bg_nohdr.log" 0 9)"
has "branch-gate rows without a header: no counts claimed" "$out" 'counts not in this log'
hasnt "...and no 'pass 0' zeros" "$out" 'pass 0|total 0'
has "...the PASS verdict stands" "$out" '^branch-gate: PASS in 9s'
out="$("$S" branch-gate "$W/many2.log" 1 2)"
ok "counts + files + 30 failures: exactly 10 lines (the cut applied)" "10" "$(nlines "$out")"
has "...the cut keeps the log line last" "$(printf '%s\n' "$out" | tail -1)" "^log: $W/many2.log\$"
# branch-gate: failures live in the per-file log the gate names
cat > "$W/pf.log" <<'EOF'
Test Failed at /x/test/test_b.jl:5
  Expression: bar() == 1
EOF
cat > "$W/bg.log" <<EOF
branch-gate: test/test_b.jl
branch-gate: FAILED — $W/pf.log
branch-gate: FAIL in 30s
EOF
out="$("$S" branch-gate "$W/bg.log" 1 30)"
has "branch-gate fail: reads the named per-file log" "$out" 'test_b.jl:5  Expression: bar\(\) == 1'
has "branch-gate fail: files run" "$out" '1 test file\(s\) run'
printf 'branch-gate: test/test_b.jl\nbranch-gate: PASS in 30s\n' > "$W/bgp.log"
out="$("$S" branch-gate "$W/bgp.log" 0 30)"
has "branch-gate pass" "$out" '^branch-gate: PASS in 30s'
# bench
cat > "$W/bench_ok.log" <<'EOF'
tools/bench.sh: quiet — 0.97 idle over 10s, no julia process
LogicKernel bench — julia 1.13.1
raw numbers: /x/tools/bench_results/2026_abc.tsv
case                         LK µs med (IQR) LK GC µs med (IQR) LK wall−GC med (IQR) swipl µs med (IQR) LK/swipl allocs bytes GC>10%
compare ground             10.00 (   0.10)     0.00 (   0.00)    10.00 (   0.10)     5.00 (   0.10)      2.00       4.0         4 3/30
nreverse                  100.00 (   1.10)     0.00 (   0.00)   100.00 (   1.10)    50.00 (   1.10)      2.00    2945.0      2945
EOF
out="$("$S" bench "$W/bench_ok.log" 0 600)"
has "bench ok: verdict and case count" "$out" '^bench: DONE \(rc=0, 600s\), 2 cases'
has "bench ok: raw numbers path" "$out" 'raw numbers: /x/tools/bench_results/2026_abc.tsv'
has "bench ok: GC flag" "$out" 'compare ground\(3/30\)'
has "bench ok: top allocations" "$out" 'nreverse=2945'
printf 'tools/bench.sh: REFUSED — julia processes are running:\n' > "$W/bench_ref.log"
out="$("$S" bench "$W/bench_ref.log" 3 1)"
has "bench refused" "$out" '^bench: REFUSED \(rc=3, 1s\)'
printf 'LogicKernel bench — julia\n' > "$W/bench_nov.log"
out="$("$S" bench "$W/bench_nov.log" 0 1)"
has "bench rc 0 without raw numbers is NO VERDICT" "$out" 'NO VERDICT'
# ...each half alone is no verdict either: raw numbers without case rows, case rows without raw numbers
printf 'LogicKernel bench — julia\nraw numbers: /x/r.tsv\n' > "$W/bench_noc.log"
out="$("$S" bench "$W/bench_noc.log" 0 1)"
has "bench rc 0, raw numbers but no case rows is NO VERDICT" "$out" 'NO VERDICT'
grep -v '^raw numbers:' "$W/bench_ok.log" > "$W/bench_nor.log"
out="$("$S" bench "$W/bench_nor.log" 0 1)"
has "bench rc 0, case rows but no raw-numbers line is NO VERDICT" "$out" 'NO VERDICT'

# ---------------------------------------------------------------- warm.sh --summary (isolated copy of the tools)
mkdir -p "$W/tree/tools" "$W/tree/test"
cp "$ROOT"/tools/warm.sh "$ROOT"/tools/lib_evidence.sh "$ROOT"/tools/summarize_log.sh "$W/tree/tools/"
out="$("$W/tree/tools/warm.sh" file test/test_nothing.jl --summary)"
rc=$?
ok "warm.sh file --summary exits with the command's own status (2: no such file)" "2" "$rc"
has "warm.sh file --summary prints the verdict" "$out" '^file: FAIL\(rc=2\)'
has "warm.sh file --summary writes the full log, and names it" "$out" "log: $W/tree/.warm/summary_file_test_nothing.log"
ok "the full log holds the real message" "1" "$(grep -c 'no such file' "$W/tree/.warm/summary_file_test_nothing.log")"
ok "warm.sh --summary output is <= 10 lines" "1" "$([ "$(nlines "$out")" -le 10 ] && echo 1 || echo 0)"
plain="$("$W/tree/tools/warm.sh" file test/test_nothing.jl 2>&1)"; prc=$?
ok "the plain run has the same status" "2" "$prc"
has "the plain run still prints its message" "$plain" 'no such file'

# ---------------------------------------------------------------- bench.sh --summary (a fake pgrep: a julia runs)
mkdir -p "$W/bin" "$W/tree2/tools"
cp "$ROOT"/tools/bench.sh "$ROOT"/tools/summarize_log.sh "$W/tree2/tools/"
printf '#!/usr/bin/env bash\n[ "$1" = "-a" ] && echo "999 julia fake" ; exit 0\n' > "$W/bin/pgrep"
chmod +x "$W/bin/pgrep"
out="$(PATH="$W/bin:$PATH" "$W/tree2/tools/bench.sh" --summary)"
rc=$?
ok "bench.sh --summary exits with the refusal status" "3" "$rc"
has "bench.sh --summary prints REFUSED" "$out" '^bench: REFUSED \(rc=3'
has "bench.sh --summary names its log" "$out" "log: $W/tree2/.warm/summary_bench.log"

# ---------------------------------------------------------------- ci_wait.sh (a fake curl: responses by call number)
SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
cat > "$W/bin/curl" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$W/n" 2>/dev/null || echo 0) + 1 )); echo \$n >> "$W/calls"; echo \$n > "$W/n"
f="$W/resp.\$n"; [ -f "\$f" ] || f="$W/resp.last"
cat "\$f"
EOF
chmod +x "$W/bin/curl"
export LOGICKERNEL_CI_WAIT_TESTING=1 LOGICKERNEL_CI_WAIT_INTERVAL_S=1
job() {   # job ID NAME STATUS CONCLUSION
    printf '{"id": %s, "name": "%s", "status": "%s", "conclusion": %s, "html_url": "https://x/job/%s"}' \
        "$1" "$2" "$3" "$([ "$4" = null ] && echo null || echo "\"$4\"")" "$1"
}
runs() { local s="" j; for j in "$@"; do s+="${s:+,}$j"; done; printf '{"total_count": %d, "check_runs": [%s]}' "$#" "$s"; }
waiter() {   # waiter [args…] — resets the fake curl's counter
    rm -f "$W/n" "$W/calls"
    PATH="$W/bin:$PATH" "$ROOT/tools/ci_wait.sh" --repo o/r "$@" "$SHA"
}
runs "$(job 1 'Tooling · main' completed success)" "$(job 2 'Evidence' completed success)" > "$W/resp.last"
out="$(waiter --timeout 5)"; rc=$?
ok "ci_wait: all green exits 0" "0" "$rc"
has "ci_wait: GREEN verdict and counts" "$out" 'aaaaaaa GREEN after [0-9]+s — 2 job\(s\): 2 green, 0 red, 0 pending'
runs "$(job 1 'Tooling · main' completed failure)" "$(job 2 'Evidence' in_progress null)" "$(job 3 'Fmt' completed success)" > "$W/resp.last"
out="$(waiter --timeout 5)"; rc=$?
ok "ci_wait: a failed job exits 1 at once (another still running)" "1" "$rc"
has "ci_wait: RED verdict" "$out" ' RED after '
has "ci_wait: the failed job and its URL" "$out" 'Tooling · main +completed +failure +https://x/job/1'
has "ci_wait: the running job is listed" "$out" 'Evidence +in_progress'
hasnt "ci_wait: the green job is not listed" "$out" 'Fmt'
ok "ci_wait: red was decided on the first call" "1" "$(grep -c . "$W/calls")"
# polling: in progress, then green on the second call
runs "$(job 1 'Evidence' in_progress null)" > "$W/resp.1"
runs "$(job 1 'Evidence' completed success)" > "$W/resp.last"
out="$(waiter --timeout 10)"; rc=$?
ok "ci_wait: pending then green exits 0" "0" "$rc"
ok "ci_wait: it called the API twice" "2" "$(grep -c . "$W/calls")"
rm -f "$W/resp.1"
# a re-run: the latest run of a job name counts
runs "$(job 1 'Evidence' completed failure)" "$(job 5 'Evidence' completed success)" > "$W/resp.last"
out="$(waiter --timeout 5)"; rc=$?
ok "ci_wait: a green re-run supersedes the older red job" "0" "$rc"
runs "$(job 5 'Evidence' completed failure)" "$(job 1 'Evidence' completed success)" > "$W/resp.last"
out="$(waiter --timeout 5)"; rc=$?
ok "ci_wait: ...and a newer red re-run is red" "1" "$rc"
# timeout
runs "$(job 1 'Evidence' in_progress null)" > "$W/resp.last"
out="$(waiter --timeout 2)"; rc=$?
ok "ci_wait: still running at the timeout exits 2" "2" "$rc"
has "ci_wait: TIMEOUT is said, with the state" "$out" 'TIMEOUT, last state: PENDING|TIMEOUT'
has "ci_wait: the pending job is named" "$out" 'Evidence +in_progress'
printf '{"total_count": 0, "check_runs": []}' > "$W/resp.last"
out="$(waiter --timeout 2)"; rc=$?
ok "ci_wait: no check at all until the timeout exits 2" "2" "$rc"
has "ci_wait: ...as NO CHECKS YET" "$out" 'NO CHECKS YET|TIMEOUT'
# unreadable
printf '{"message": "API rate limit exceeded"}' > "$W/resp.last"
out="$(waiter --timeout 30)"; rc=$?
ok "ci_wait: an unreadable answer 3 times exits 3" "3" "$rc"
has "ci_wait: ...naming the answer" "$out" 'unreadable 3 times.*rate limit'
ok "ci_wait: ...after exactly 3 calls" "3" "$(grep -c . "$W/calls")"
# many red jobs: the cap
args=(); for i in $(seq 1 40); do args+=("$(job "$i" "Job $i" completed failure)"); done
runs "${args[@]}" > "$W/resp.last"
out="$(waiter --timeout 5)"; rc=$?
ok "ci_wait: 40 red jobs exit 1" "1" "$rc"
ok "ci_wait: ...print <= 10 lines" "1" "$([ "$(nlines "$out")" -le 10 ] && echo 1 || echo 0)"
has "ci_wait: ...and say how many are left out" "$out" 'more not green'
out="$(waiter --timeout 5 --all)"
ok "ci_wait --all lists every job" "41" "$(nlines "$out")"
# interval floor: without the testing seam a short interval is raised to 300 s (one call, then a timeout on the next sleep)
runs "$(job 1 'Evidence' in_progress null)" > "$W/resp.last"; rm -f "$W/n" "$W/calls"
out="$(env -u LOGICKERNEL_CI_WAIT_TESTING LOGICKERNEL_CI_WAIT_INTERVAL_S=1 PATH="$W/bin:$PATH" "$ROOT/tools/ci_wait.sh" --repo o/r --timeout 3 "$SHA" < /dev/null)"; rc=$?
ok "ci_wait: the 300 s floor means one call, then TIMEOUT (exit 2)" "2" "$rc"
ok "ci_wait: ...exactly one API call" "1" "$(grep -c . "$W/calls")"

echo "test_summary: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
