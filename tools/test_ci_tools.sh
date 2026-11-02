#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the tests of tools/ci_triage.sh, tools/battery_table.sh and
# tools/prepush.sh (audit D-0327 item 4). SAVED real answers only (tools/fixtures/ci/<run id>/: the jobs
# answer and the failed-step lines of the job logs of the runs below); a fake `curl` on PATH that fails the
# case when called, so no case reaches the network; a stub warm.sh and a throwaway git repository for prepush.
#
#   tools/test_ci_tools.sh          # exit 0 only if every case passes
#
# The runs (each fixture log starts with a header line naming its run id):
#   41357787404 P1 red (a stale pin: test_rules_swipl.jl:1559)     41364513951 gate/dstack-b7 red
#   41389618471 S2a red (the Tooling jobs)                         41385566338 S2a red (JET, type discipline)
#   41389662396 O1A2 battery (runaway C8/E5, survivors)            41389662918 SSU12 battery (one survivor)
#   41364514173 MOD3a battery, VOID (its Baseline failed)
# Both sides of every guard: a red run and a green one, a void battery and a clean one, a stop and a pass.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/ci_tools.XXXXXX")"
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
same() {   # same NAME EXPECTED GOT — line by line, both sides non-empty, the first differing line named
    local name="$1" want="$2" got="$3" i=0 bad="" w g
    if [ -z "$want" ] || [ -z "$got" ]; then fail=$((fail + 1)); echo "  FAIL $name: an empty side"; return; fi
    local nw ng
    nw="$(printf '%s\n' "$want" | grep -c '')"
    ng="$(printf '%s\n' "$got" | grep -c '')"
    while IFS= read -r w; do
        i=$((i + 1))
        g="$(printf '%s\n' "$got" | sed -n "${i}p")"
        if [ "$w" != "$g" ]; then bad="line $i: got '$g', want '$w'"; break; fi
    done <<< "$want"
    if [ -z "$bad" ] && [ "$nw" != "$ng" ]; then bad="$ng lines, want $nw"; fi
    if [ -z "$bad" ]; then pass=$((pass + 1)); echo "  ok   $name ($nw lines)"
    else fail=$((fail + 1)); echo "  FAIL $name: $bad"; fi
}
nlines() { printf '%s\n' "$1" | grep -c ''; }

# no case may reach the network: curl and gh are fakes that leave a mark
mkdir -p "$W/bin"
cat > "$W/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl called" >> "$FAKE_NET_MARK"
exit 7
EOF
cp "$W/bin/curl" "$W/bin/gh"
chmod +x "$W/bin/curl" "$W/bin/gh"
export FAKE_NET_MARK="$W/net_mark"
export PATH="$W/bin:$PATH"
export LOGICKERNEL_CI_FIXTURE_DIR="$ROOT/tools/fixtures/ci"
TRIAGE="$ROOT/tools/ci_triage.sh"
BAT="$ROOT/tools/battery_table.sh"

# ---------------------------------------------------------------- the fixtures themselves
for run in 41357787404 41364513951 41389618471 41385566338 41389662396 41389662918 41364514173; do
    n="$(ls "$LOGICKERNEL_CI_FIXTURE_DIR/$run"/*.log 2> /dev/null | wc -l)"
    [ "$n" -ge 1 ] && ok "fixture $run: has job logs" 1 1 || ok "fixture $run: has job logs" ">=1" "$n"
    hdrs="$(for f in "$LOGICKERNEL_CI_FIXTURE_DIR/$run"/*.log; do sed -n 1p "$f"; done | grep -c "^# fixture: run $run ")"
    ok "fixture $run: every log carries the run id in its header" "$n" "$hdrs"
done
secret="$(grep -rIlE 'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|Bearer [A-Za-z0-9._-]{20,}' "$LOGICKERNEL_CI_FIXTURE_DIR" | wc -l)"
ok "fixtures hold no token-looking text" 0 "$secret"
# the token guard can fail: a token-shaped string generated NOW (never stored) is caught by the same pattern,
# and the scan covers at least one file
mkdir -p "$W/leak"
printf 'x %s%s y\n' "ghp_" "$(printf 'a%.0s' $(seq 1 30))" > "$W/leak/f.log"
tokpat='gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|Bearer [A-Za-z0-9._-]{20,}|[Aa]uthorization:'
ok "token guard: a planted token-shaped string is caught" 1 "$(grep -rIlE "$tokpat" "$W/leak" | wc -l)"
ok "token guard: the fixture scan covers files" ">0" "$([ "$(find "$LOGICKERNEL_CI_FIXTURE_DIR" -type f | wc -l)" -gt 0 ] && echo '>0' || echo 0)"
ok "fixtures hold no Authorization header text" 0 "$(grep -rIlE '[Aa]uthorization:' "$LOGICKERNEL_CI_FIXTURE_DIR" | wc -l)"
ansi="$(grep -rIlP '\x1b\[' "$LOGICKERNEL_CI_FIXTURE_DIR" | wc -l)"
ok "fixtures hold no ANSI colour code" 0 "$ansi"
big="$(find "$LOGICKERNEL_CI_FIXTURE_DIR" -type f -size +300k | wc -l)"
ok "no fixture is over 300 KB" 0 "$big"

# ---------------------------------------------------------------- ci_triage.sh
out="$("$TRIAGE" 41357787404)"; rc=$?
ok "triage P1: exit 1 (a job failed)" 1 "$rc"
same "triage P1 (a stale pin), line by line" "$(cat <<'EOF'
ci_triage: run 41357787404  Evidence (three term types)  gate/p1b  374cddf: 7 of 18 jobs not green
failed jobs: alt_interned · files 1/2; alt · files 1/2; reference · files 1/2; alt_interned; reference; alt; Verdict table
first ##[error]: Process completed with exit code 1.  [alt_interned · files 1/2, alt · files 1/2, reference · files 1/2]
first ##[error]: FAIL: alt_interned_g1: the job did not pass  [alt_interned]
first ##[error]: FAIL: reference_g1: the job did not pass  [reference]
first ##[error]: 2 more distinct lines in the other jobs
distinct failing tests: 2
 1. [Test Failed] test/core_lang/test_rules_swipl.jl:1559  the inline compilers' fall-back calls answer as swipl does (V6b2)
      Expression: LK.PL_next_solution(gd, ld, qid) == LK.PL_S_EXCEPTION
      Evaluated: 2 == -1
      in: alt_interned · files 1/2, alt · files 1/2, reference · files 1/2
 2. [Error During Test] test/core_lang/test_rules_swipl.jl:1519  the inline compilers' fall-back calls answer as swipl does (V6b2)
      Error: slot word 0x0000000000000000: a slot read before it was written, or a word that is no slot word
      in: alt_interned · files 1/2, alt · files 1/2, reference · files 1/2
EOF
)" "$out"
out="$("$TRIAGE" 41364513951)"; rc=$?
ok "triage dstack-b7: exit 1" 1 "$rc"
same "triage dstack-b7, line by line" "$(cat <<'EOF'
ci_triage: run 41364513951  CI  gate/dstack-b7  7408ccc: 4 of 15 jobs not green
failed jobs: Julia 1 · files 3/3; Julia min · files 3/3; Julia min - ubuntu-24.04; Julia 1 - ubuntu-24.04
first ##[error]: Process completed with exit code 1.  [Julia 1 · files 3/3, Julia min · files 3/3]
first ##[error]: FAIL: julia-min_g3: the job did not pass  [Julia min - ubuntu-24.04]
first ##[error]: FAIL: julia-1_g3: the job did not pass  [Julia 1 - ubuntu-24.04]
distinct failing tests: 2
 1. [Test Failed] test/compile/test_ssu_compile_swipl.jl:585  KNOWN DIFFERENCE: a clause for ','/2 (a05, k01) — the kernel's answer pinned, swipl's beside it
      Expression: kl == ["ok", kernel_line]
      Evaluated: ["ok", "t_a05 c[116,95,97,48,53]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[115,116,97,116,105,99,95,11…
      in: Julia 1 · files 3/3, Julia min · files 3/3
 2. [Test Failed] test/files/test_qlf_swipl.jl:448  compileFileList and the boot entry (up to -c; the state after)
      Expression: _ql_list_atoms(kl[2]) == ["additional"]
      Evaluated: ["autoload_off", "additional"] == ["additional"]
      in: Julia 1 · files 3/3, Julia min · files 3/3
EOF
)" "$out"
out="$("$TRIAGE" 41389618471)"; rc=$?
ok "triage S2a Tooling: exit 1" 1 "$rc"
same "triage S2a Tooling jobs, line by line" "$(cat <<'EOF'
ci_triage: run 41389618471  CI  gate/s2a2  b36a947: 4 of 15 jobs not green
failed jobs: Tooling · stale; Tooling · fast; Tooling · main; Tooling suites (warm lane, evidence, oracle cache)
first ##[error]: Process completed with exit code 1.  [Tooling · stale, Tooling · fast, Tooling · main]
first ##[error]: FAIL: shard main: 3 case(s) failed; shard stale: 2 case(s) failed; shard fast: 2 case(s) failed; the shards passed 323 cases, the whole run passes 33…  [Tooling suites (warm lane, evidence, oracle cache)]
distinct failing tests: 8
 1. [FAIL] stale: a daemon-only method restarts the daemon, and the rerun PASSES: exit 1, want 0  [Tooling · stale]
 2. [FAIL] …and the rerun passed: exit 0, want 1  [Tooling · stale]
 3. [FAIL] the pre-check passes on the restored tree: exit 1, want 0  [Tooling · fast]
 4. [FAIL] …and a second run takes under a minute (warm: seconds): exit 1, want 0  [Tooling · fast]
 5. [FAIL] preflight passes on the tree as it is: exit 1, want 0  [Tooling · main]
 6. [JET-test failed] JETBase.jl:1382  | pre-check: JET report_package
      analysed 1: (no Expression line)
      in: Tooling · main
 7. [FAIL] …reaching the static-analysis gate (stubbed here: the tooling seam): exit 0, want 1  [Tooling · main]
 8. [FAIL] …after a REAL fast static pre-check: exit 0, want 1  [Tooling · main]
EOF
)" "$out"
out="$("$TRIAGE" 41385566338)"; rc=$?
ok "triage S2a JET run: exit 1" 1 "$rc"
same "triage S2a JET and type discipline, line by line" "$(cat <<'EOF'
ci_triage: run 41385566338  Evidence (three term types)  gate/s2a2  5aaf169: 11 of 18 jobs not green
failed jobs: static analysis 7/8; static analysis 1/8; reference · files 1/2; static analysis 4/8; static analysis 5/8; static analysis 2/8; static analysis 6/8; static analysis 8/8; static analysis 3/8; reference; Verdict table
first ##[error]: Process completed with exit code 1.  [static analysis 7/8, static analysis 1/8, reference · files 1/2 +6]
first ##[error]: FAIL: reference_g1: the job did not pass  [reference]
first ##[error]: FAIL: reference_g1: the job did not pass; sa_1: the job did not pass; sa_2: the job did not pass; sa_3: the job did not pass; sa_4: the job did not p…  [Verdict table]
distinct failing tests: 4
 1. [JET-test failed] JETBase.jl:1382  JET: zero runtime dispatch on every manifest entry (this shard's)
      analysed 14: _call_stream_property; _fcall_va; boot_from_source!; call_internal_det_foreign; compileFile; discardForeignFrame; pl_dstream_properties2_va; pl_dstream_property2_va; pl_dstreams_properties2_va; query…
      in: static analysis 7/8, static analysis 1/8, static analysis 4/8, static analysis 5/8, static analysis 2/8, static analysis 6/8, static analysis 8/8, static analysis 3/8
 2. [Test Failed] test/test_type_discipline.jl:136  no abstractly typed struct field in LogicKernel
      Expression: isempty(bad)
      Evaluated: isempty(["sprop.fn::Function"])
      in: reference · files 1/2
 3. [JET-test failed] JETBase.jl:1382  JET: no errors anywhere in the package (report_package)
      analysed 1: LogicKernel
      in: static analysis 2/8
 4. [Test Failed] test/static_analysis_body.jl:134  the dispatch check's skips lose nothing
      Expression: length(DISPATCH_MANIFEST) == length(unique(DISPATCH_MANIFEST))
      Evaluated: 3248 == 3245
      in: static analysis 3/8
EOF
)" "$out"
ok "triage JET run: 8 shards' failures are 4 DISTINCT tests, in <= 40 lines" "4" "$(printf '%s\n' "$out" | grep -c '^ *[0-9]*\. \[')"
[ "$(nlines "$out")" -le 40 ] && ok "triage: at most 40 lines" ok ok || ok "triage: at most 40 lines" ok "$(nlines "$out") lines"
hasnt "triage: no ANSI escape in the output" "$out" $'\x1b'
# a green run: nothing to triage, exit 0 (the guard can pass)
mkdir -p "$W/fx/777"
cat > "$W/fx/777/jobs_1.json" <<'EOF'
{"total_count":2,"jobs":[{"id":1,"name":"a","status":"completed","conclusion":"success","workflow_name":"CI","head_branch":"gate/x","head_sha":"0123456789abcdef0123456789abcdef01234567"},
{"id":2,"name":"b","status":"completed","conclusion":"skipped","workflow_name":"CI","head_branch":"gate/x","head_sha":"0123456789abcdef0123456789abcdef01234567"}]}
EOF
out="$(LOGICKERNEL_CI_FIXTURE_DIR="$W/fx" "$TRIAGE" 777)"; rc=$?
ok "triage green run: exit 0" 0 "$rc"
same "triage green run: says so" "ci_triage: run 777  CI  gate/x  0123456: 0 of 2 jobs not green
no failed job (still running, or green)" "$out"
# a failed job whose log cannot be read is named, not skipped
cat > "$W/fx/777/jobs_1.json" <<'EOF'
{"total_count":1,"jobs":[{"id":9,"name":"lost","status":"completed","conclusion":"failure","workflow_name":"CI","head_branch":"gate/x","head_sha":"0123456789abcdef0123456789abcdef01234567"}]}
EOF
out="$(LOGICKERNEL_CI_FIXTURE_DIR="$W/fx" "$TRIAGE" 777)"; rc=$?
ok "triage unreadable log: exit 1" 1 "$rc"
has "triage unreadable log: named" "$out" 'first ##\[error\]: \(log not readable\)  \[lost\]'
# an unknown run is "unreadable" (2), a bad argument is usage (64)
out="$(LOGICKERNEL_CI_FIXTURE_DIR="$W/fx" "$TRIAGE" 888)"; rc=$?
ok "triage unknown run: exit 2" 2 "$rc"
has "triage unknown run: message" "$out" 'run 888: no jobs read'
out="$("$TRIAGE" abc 2>&1)"; rc=$?
ok "triage bad argument: exit 64" 64 "$rc"
out="$("$TRIAGE" 2>&1)"; rc=$?
ok "triage no argument: exit 64" 64 "$rc"
# pagination: a first page of 100 reads the second
python3 -I - "$W/fx" << 'PY'
import json, os, sys
d = sys.argv[1] + "/778"
os.makedirs(d, exist_ok=True)
def job(i, c):
    return {"id": i, "name": "j%d" % i, "status": "completed", "conclusion": c, "workflow_name": "CI", "head_branch": "b", "head_sha": "a" * 40}
json.dump({"total_count": 101, "jobs": [job(i, "success") for i in range(1, 101)]}, open(d + "/jobs_1.json", "w"))
json.dump({"total_count": 101, "jobs": [job(101, "failure")]}, open(d + "/jobs_2.json", "w"))
open(d + "/101.log", "w").write("2026-01-01T00:00:00.0000000Z x: Test Failed at /home/runner/work/LogicKernel/LogicKernel/test/a.jl:5\n2026-01-01T00:00:00.0000001Z   Expression: 1 == 2\n2026-01-01T00:00:00.0000002Z    Evaluated: 1 == 2\n2026-01-01T00:00:00.0000003Z ##[error]Process completed with exit code 1.\n")
PY
out="$(LOGICKERNEL_CI_FIXTURE_DIR="$W/fx" "$TRIAGE" 778)"; rc=$?
ok "triage page 2: the job on it is found (exit 1)" 1 "$rc"
same "triage page 2, line by line" "ci_triage: run 778  CI  b  aaaaaaa: 1 of 101 jobs not green
failed jobs: j101
first ##[error]: Process completed with exit code 1.  [j101]
distinct failing tests: 1
 1. [Test Failed] test/a.jl:5  x
      Expression: 1 == 2
      Evaluated: 1 == 2
      in: j101" "$out"

# ---------------------------------------------------------------- battery_table.sh
out="$("$BAT" 41389662396)"; rc=$?
ok "battery O1A2: exit 1 (survivors, a declared equivalent, no verdict)" 1 "$rc"
same "battery O1A2 (runaway C8/E5), line by line" "$(cat <<'EOF'
battery_table: run 41389662396  Mutation battery  mutants/O1A2
baseline: green, 2475 s
131 mutants: caught 120, SURVIVED 8, EQUIVALENT (declared) 1, NO VERDICT 2
121 of 131 decided; blocking: O1A-A1, O1A-A5, O1A-A6, O1A-C8, O1A-D7, O1A-E5, O1A-I2, O1A-I21, O1A-J6, O1A-K4
SURVIVED  O1A-A1  outchr stores a code point above 0x7f as one byte when rubber is pending: emit_rubber decodes garbage (KILL f…
SURVIVED  O1A-A5  outstring buffers `len` characters as one: a later fill point is placed wrongly (KILL f52, f61)
SURVIVED  O1A-A6  outstring does not advance the column over the bytes (KILL f50, f54)
SURVIVED  O1A-D7  ~Ns does not cut a Latin-1 text to N characters (KILL f79)
SURVIVED  O1A-I2  formatFloat's default for h is 6 digits (KILL f33)
SURVIVED  O1A-I21  a rational ~Ne does not correct the exponent of an exact power of ten (KILL f39, f95)
SURVIVED  O1A-J6  the double path's ~g prints the fixed form with a digit too many (KILL f32)
SURVIVED  O1A-K4  a call-back that wrote straight to the stream leaves the current output on the format stream (KILL f65, f66)
EQUIVALENT O1A-C6  the guard `here < flen` of the backquote argument (c is the character at `here`, so it holds whenever c is a backquote) — declared equivalent, pending audit: src/os/pl-fmt.jl:485 (do_format's `elseif c == Int('`') && here < flen`) — read, not run: c is `get_chr_from_text(fmt, here)` (the line befor…
NO VERDICT O1A-C8  a numeric argument past `int` is not refused: the kernel's raise of f…  | job: Process completed with exit code 143.
NO VERDICT O1A-E5  ~1r is a valid radix (KILL e06)  | job: Process completed with exit code 143.
EOF
)" "$out"
[ "$(nlines "$out")" -le 60 ] && ok "battery O1A2: at most 60 lines" ok ok || ok "battery O1A2: at most 60 lines" ok "$(nlines "$out") lines"
has "battery O1A2: the runaway's last error line is shown" "$out" 'NO VERDICT O1A-C8 .*job: Process completed with exit code 143\.'
ok "battery O1A2: the declared equivalent's argument is cut at 300 characters" 1 "$(printf '%s\n' "$out" | grep -c '^EQUIVALENT O1A-C6 .\{200,311\}…$')"
out="$("$BAT" 41389662918)"; rc=$?
ok "battery SSU12: exit 1 (one survivor)" 1 "$rc"
same "battery SSU12, line by line" "$(cat <<'EOF'
battery_table: run 41389662918  Mutation battery  mutants/SSU12
baseline: green, 68 s
28 mutants: caught 27, SURVIVED 1, EQUIVALENT (declared) 0, NO VERDICT 0
27 of 28 decided; blocking: SSU1-T1
SURVIVED  SSU1-T1  retract/1 without the CLAUSE_SSU_FLAGS test: `retract((F => true))` removes the fact F (KILL a22, a23, a24)
EOF
)" "$out"
out="$("$BAT" 41364514173)"; rc=$?
ok "battery MOD3a (void): exit 2" 2 "$rc"
same "battery MOD3a: VOID and stop, line by line" "$(cat <<'EOF'
battery_table: run 41364514173  Mutation battery  mutants/MOD3a
VOID: baseline failed (job 125021793389, conclusion failure): Process completed with exit code 1. (the line before: baseline exit 1)
no verdict of this run counts; fix the unmutated tree and run the battery again
EOF
)" "$out"
hasnt "battery MOD3a: no mutant verdict is printed after VOID" "$out" 'caught|SURVIVED  '
# a clean battery: every mutant caught, exit 0 (the guard can pass); both jobs success
mkdir -p "$W/fx/801"
cat > "$W/fx/801/jobs_1.json" <<'EOF'
{"total_count":4,"jobs":[
{"id":11,"name":"Plan","status":"completed","conclusion":"success","workflow_name":"Mutation battery","head_branch":"mutants/Z","head_sha":"b"},
{"id":12,"name":"Baseline (unmutated)","status":"completed","conclusion":"success","workflow_name":"Mutation battery","head_branch":"mutants/Z","head_sha":"b"},
{"id":13,"name":"Z-1","status":"completed","conclusion":"success","workflow_name":"Mutation battery","head_branch":"mutants/Z","head_sha":"b"},
{"id":14,"name":"Verdict table","status":"completed","conclusion":"success","workflow_name":"Mutation battery","head_branch":"mutants/Z","head_sha":"b"}]}
EOF
cat > "$W/fx/801/14.log" <<'EOF'
2026-01-01T00:00:00.0000000Z ## Mutation battery — tools/mutants/Z.py
2026-01-01T00:00:00.0000001Z Baseline (unmutated targets): **green**, 12 s
2026-01-01T00:00:00.0000002Z | mutant | verdict | time | what it breaks | first failing test line |
2026-01-01T00:00:00.0000003Z |---|---|---|---|---|
2026-01-01T00:00:00.0000004Z | Z-1 | caught | 5 s | a thing (KILL t1) | t: Test Failed at test/t.jl:3 |
2026-01-01T00:00:00.0000005Z | Z-2 | caught | 6 s | another (KILL t2) | t: Test Failed at test/t.jl:4 |
2026-01-01T00:00:00.0000006Z **2 of 2 decided; blocking: none**
EOF
out="$(LOGICKERNEL_CI_FIXTURE_DIR="$W/fx" "$BAT" 801)"; rc=$?
ok "battery clean: exit 0" 0 "$rc"
same "battery clean, line by line" "battery_table: run 801  Mutation battery  mutants/Z
baseline: green, 12 s
2 mutants: caught 2, SURVIVED 0, EQUIVALENT (declared) 0, NO VERDICT 0
2 of 2 decided; blocking: none" "$out"
# the same run with a survivor, or a declared equivalent, in an all-success run: exit 1 each (the guard can fail
# on the table alone, not only through the verdict job's conclusion)
for kind in "SURVIVED" "EQUIVALENT (declared)"; do
    case "$kind" in SURVIVED) n=1;; *) n=2;; esac
    mkdir -p "$W/fx/802$n"
    cp "$W/fx/801/jobs_1.json" "$W/fx/802$n/jobs_1.json"
    sed "s/| Z-2 | caught |/| Z-2 | $kind |/" "$W/fx/801/14.log" > "$W/fx/802$n/14.log"
    out="$(LOGICKERNEL_CI_FIXTURE_DIR="$W/fx" "$BAT" "802$n")"; rc=$?
    ok "battery $kind in an all-success run: exit 1" 1 "$rc"
    has "battery $kind: counted" "$out" "$(printf '%s' "$kind" | cut -c1-4)"
done
# a battery still running: pending (3), never a verdict
sed -i 's/"id":12,"name":"Baseline (unmutated)","status":"completed","conclusion":"success"/"id":12,"name":"Baseline (unmutated)","status":"in_progress","conclusion":null/' "$W/fx/801/jobs_1.json"
out="$(LOGICKERNEL_CI_FIXTURE_DIR="$W/fx" "$BAT" 801)"; rc=$?
ok "battery pending baseline: exit 3" 3 "$rc"
has "battery pending baseline: says PENDING" "$out" 'PENDING: the Baseline job is in_progress'
# a run that is no battery
out="$(LOGICKERNEL_CI_FIXTURE_DIR="$LOGICKERNEL_CI_FIXTURE_DIR" "$BAT" 41357787404)"; rc=$?
ok "battery on a CI run (no Baseline job): exit 2" 2 "$rc"
has "battery on a CI run: says so" "$out" 'no Baseline job in this run'
out="$("$BAT" x1 2>&1)"; rc=$?
ok "battery bad argument: exit 64" 64 "$rc"

# ---------------------------------------------------------------- no network, no secret
ok "no case called curl or gh" "none" "$([ -e "$FAKE_NET_MARK" ] && echo called || echo none)"

# ---------------------------------------------------------------- prepush.sh (stub warm.sh, throwaway repository)
PRE="$ROOT/tools/prepush.sh"
idt=(GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.invalid)
mkrepo() {   # mkrepo DIR — a repository whose origin/main is the base commit
    local R="$1" c
    mkdir -p "$R/src" "$R/test"
    git init -q -b main "$R"
    printf 'f(x) = x\n' > "$R/src/a.jl"
    printf '# KNOWN DIFFERENCE: foo/2 is interim\n@test true\n' > "$R/test/t.jl"
    git -C "$R" add -A
    c="$(env "${idt[@]}" git -C "$R" commit-tree "$(git -C "$R" write-tree)" -m base)"
    git -C "$R" update-ref refs/heads/main "$c"
    git -C "$R" update-ref refs/remotes/origin/main "$c"
    git -C "$R" reset -q --hard main
}
commit() {   # commit DIR MESSAGE — everything staged becomes one commit on main
    local R="$1" c
    git -C "$R" add -A
    c="$(env "${idt[@]}" git -C "$R" commit-tree "$(git -C "$R" write-tree)" -p HEAD -m "$2")"
    git -C "$R" update-ref refs/heads/main "$c"
    git -C "$R" reset -q --hard main
}
cat > "$W/warm_stub.sh" <<'EOF'
#!/usr/bin/env bash
# stands for tools/warm.sh: records its calls; STUB_DOWN, STUB_FAIL (a subcommand), STUB_REWRITE (a subcommand
# that rewrites a tracked file) steer it
echo "$*" >> "$STUB_LOG"
[ "$1" = status ] && { [ "${STUB_DOWN:-}" = 1 ] && exit 3; echo "warm lane: running (stub)"; exit 0; }
[ "${STUB_FAIL:-}" = "$1" ] && { echo "stub: $1 failed: something specific"; exit 1; }
[ "${STUB_REWRITE:-}" = "$1" ] && printf 'rewritten by %s\n' "$1" >> "$STUB_REPO/src/a.jl"
exit 0
EOF
chmod +x "$W/warm_stub.sh"
R="$W/repo"
mkrepo "$R"
printf 'f(x) = x\ng(x) = x # registers foo/2\n' > "$R/src/a.jl"
commit "$R" "ADDED: g"
export STUB_LOG="$W/stub.log" STUB_REPO="$R"
runpre() { : > "$STUB_LOG"; LOGICKERNEL_PREPUSH_WARM="$W/warm_stub.sh" LOGICKERNEL_PREPUSH_REPO="$R" "$PRE" "$@" 2>&1; }
out="$(runpre S1)"; rc=$?
ok "prepush all passing: exit 0" 0 "$rc"
same "prepush: the stub saw the steps in the playbook order" "status
inventory
fmt
check
file test/static_analysis_fast.jl" "$(cat "$STUB_LOG")"
has "prepush: ALL PASSED line" "$out" '^prepush: ALL PASSED for S1 at [0-9a-f]{7} \(1 commit\(s\) over origin/main\)'
has "prepush: the stale-pin hunt lists the hit naming a name the diff adds" "$out" 'test/t.jl:1:# KNOWN DIFFERENCE: foo/2 is interim'
has "prepush: next command, ls-remote first" "$out" 'git ls-remote origin refs/heads/gate/S1'
has "prepush: next command, rename and bare push" "$out" 'git branch -m .* gate/S1 && git push -u origin gate/S1'
hasnt "prepush: never --no-verify, never force" "$out" '\-\-no-verify|\-\-force'
# the warm lane is down: loud, exit 3, nothing run
out="$(STUB_DOWN=1 runpre S1)"; rc=$?
ok "prepush warm lane down: exit 3" 3 "$rc"
has "prepush warm lane down: says so and how to start it" "$out" 'NOT up; nothing was run'
ok "prepush warm lane down: only status was asked" "status" "$(cat "$STUB_LOG")"
# a failing step stops there and is named; later steps are not run
out="$(STUB_FAIL=check runpre S1)"; rc=$?
ok "prepush check fails: exit 1" 1 "$rc"
has "prepush check fails: named" "$out" '^prepush: FAILED at check'
has "prepush check fails: its output is shown" "$out" 'stub: check failed: something specific'
ok "prepush check fails: the static pre-check did not run" "status
inventory
fmt
check" "$(cat "$STUB_LOG")"
out="$(STUB_FAIL=file runpre S1)"; rc=$?
ok "prepush static pre-check fails: exit 1" 1 "$rc"
has "prepush static pre-check fails: named" "$out" '^prepush: FAILED at static'
# fmt rewrites a tracked file: stop, say to commit it
out="$(STUB_REWRITE=fmt runpre S1)"; rc=$?
ok "prepush fmt rewrote a file: exit 1" 1 "$rc"
has "prepush fmt rewrote a file: named" "$out" '^prepush: FAILED at fmt'
has "prepush fmt rewrote a file: the file is listed" "$out" 'M src/a.jl'
git -C "$R" reset -q --hard main
out="$(STUB_REWRITE=inventory runpre S1)"; rc=$?
ok "prepush inventory rewrote a file: exit 1" 1 "$rc"
has "prepush inventory rewrote a file: named" "$out" '^prepush: FAILED at inventory'
git -C "$R" reset -q --hard main
# a dirty tree and an untracked file stop it before any step
printf 'x\n' >> "$R/src/a.jl"
out="$(runpre S1)"; rc=$?
ok "prepush dirty tree: exit 1" 1 "$rc"
has "prepush dirty tree: named" "$out" '^prepush: FAILED at 0 clean tree'
ok "prepush dirty tree: no warm step ran" "status" "$(cat "$STUB_LOG")"
git -C "$R" reset -q --hard main
printf 'x\n' > "$R/src/new.jl"
out="$(runpre S1)"; rc=$?
ok "prepush untracked file: exit 1" 1 "$rc"
has "prepush untracked file: listed" "$out" 'src/new.jl'
rm -f "$R/src/new.jl"
# the D-0164 term grep: an added line, then a commit message (assembled so this file does not match itself)
term='cra''sh'
printf 'h(x) = x # this %s the process\n' "$term" >> "$R/src/a.jl"
commit "$R" "ADDED: h"
out="$(runpre S1)"; rc=$?
ok "prepush D-0164 term in the diff: exit 1" 1 "$rc"
has "prepush D-0164 term in the diff: named" "$out" '^prepush: FAILED at D-0164 term grep'
has "prepush D-0164 term in the diff: the line is shown" "$out" "this $term the process"
mkrepo "$W/repo2"
R="$W/repo2"; STUB_REPO="$R"
printf 'k(x) = x\n' >> "$R/src/a.jl"
commit "$R" "ADDED: k, the $term of the old path"
out="$(runpre S2)"; rc=$?
ok "prepush D-0164 term in a commit message: exit 1" 1 "$rc"
has "prepush D-0164 term in a message: named" "$out" '^prepush: FAILED at D-0164 term grep'
# no step, no name: usage
out="$("$PRE" 2>&1)"; rc=$?
ok "prepush without a step: exit 64" 64 "$rc"
# the script itself: no gate marker, no hook bypass, no push
body="$(grep -v '^ *#' "$PRE")"
hasnt "prepush code: no --no-verify" "$body" '\-\-no-verify'
hasnt "prepush code: executes no push" "$body" '^ *(git|command git) push'
hasnt "prepush code: no marker file is written" "$body" 'marker'

# ---------------------------------------------------------------- ci_api.sh and the token (audit D-0338 item 3)
# A fake git (credential fill answers a token made up NOW) and a fake curl that records argv, stdin, and
# writes a log: the token reaches curl on stdin only, never in argv, the output, a file left behind.
mkdir -p "$W/tokbin" "$W/tmpd"
FAKETOK="tk$(printf 'q%.0s' $(seq 1 24))"
REALGIT="$(command -v git)"
cat > "$W/tokbin/git" <<EOF
#!/usr/bin/env bash
case "\$*" in
    *credential*) printf 'protocol=https\nhost=github.com\nusername=u\npassword=$FAKETOK\n';;
    *) exec "$REALGIT" "\$@";;
esac
EOF
cat > "$W/tokbin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TOK_ARGV"
cat >> "$TOK_STDIN"
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
[ -n "$out" ] && printf 'a log line\n' > "$out"
printf '200'
EOF
chmod +x "$W/tokbin/git" "$W/tokbin/curl"
: > "$W/tok_argv"; : > "$W/tok_stdin"
got="$(env -u LOGICKERNEL_CI_FIXTURE_DIR PATH="$W/tokbin:$PATH" TMPDIR="$W/tmpd" TOK_ARGV="$W/tok_argv" TOK_STDIN="$W/tok_stdin" ROOT="$ROOT" \
    bash -c '. "$ROOT/tools/ci_api.sh"; ci_job_log 123 777' 2>&1)"
ok "ci_api: the log comes back" "a log line" "$got"
ok "ci_api: the token reached curl on stdin" 1 "$(grep -c "$FAKETOK" "$W/tok_stdin")"
ok "ci_api: the token is not in curl's argv" 0 "$(grep -c "$FAKETOK" "$W/tok_argv")"
ok "ci_api: curl was called (the argv side is non-empty)" 1 "$([ -s "$W/tok_argv" ] && echo 1 || echo 0)"
ok "ci_api: the token is not in the output" 0 "$(printf '%s' "$got" | grep -c "$FAKETOK")"
ok "ci_api: no temp file is left behind" 0 "$(ls "$W/tmpd" | wc -l)"
ok "ci_api: the token is stored in no file under tools/" 0 "$(grep -rIlF "$FAKETOK" "$ROOT/tools" | wc -l)"

echo "tools/test_ci_tools.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
