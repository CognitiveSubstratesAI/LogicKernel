#!/usr/bin/env bash
# ORIGINAL: no twin in swipl-devel — the rows of the TERM-TYPE MATRIX of the CI mutation battery (MUT3):
# tools/mutate_ci.py's `--impl` / `--impls` and .github/workflows/mutation.yml's impl dimension.
#
#   tools/test_mutate_ci_impl.sh        exit 0 only if every row passes; no Julia, no network, nothing is pushed.
#
# A FAKE `julia` on PATH stands for the test file run (it reads LOGICKERNEL_TERM and the mutated text of src.txt and
# exits 0, or 1 with a failing-test line), so the whole chain plan -> baseline -> one -> collect runs for real in a
# scratch tree. THE ROWS. (1) the matrix expansion (a pure function): mutants x impls, mutant by mutant; the
# default (no --impls) is the one-pair-per-mutant matrix of before; the 256-job limit refuses 257 and takes 256 and
# names `ids`; an unknown term type is refused. (2) one pair: a target runs with LOGICKERNEL_TERM=<impl>; on a
# non-reference type a target that is not term-generic is skipped, and a pair with nothing left is N/A, not run.
# (3) the gather: caught on all three = caught; survived on one = SURVIVED (and the text says on which); a declared
# equivalent must survive on every type (EQUIVALENT REFUTED on one blocks); a baseline red or missing on one type
# makes that type's pairs NO VERDICT and BLOCKS; N/A and a declared equivalent do not block; the exit code.
# (4) the default is the table of before (five columns, files <ID>.json, baseline.json). (5) the table still reads
# through tools/battery_table.py. (6) the workflow parses (PyYAML when the runner has it, text rows always): jobs,
# needs, the matrix of each job, the job names, the inputs. (7) MUTANTS OF THE GATHER: each mutant of mutate_ci.py
# (applied to a COPY, its text must occur exactly once) must turn at least one row of rows (1)-(3) red; the unmutated
# copy must pass them all first (a row that cannot fail proves nothing).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/mutci_impl.XXXXXX")" || exit 3
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
# ok/has/hasnt — one row each; VERBOSE=0 (the mutants' runs) counts the failures in `cf` and prints nothing
VERBOSE=1 cf=0
row_ok() { if [ "$VERBOSE" = 1 ]; then pass=$((pass + 1)); echo "  ok   $1"; fi; }
row_bad() { if [ "$VERBOSE" = 1 ]; then fail=$((fail + 1)); echo "  FAIL $1: $2"; else cf=$((cf + 1)); fi; }
ok() { if [ "$2" = "$3" ]; then row_ok "$1"; else row_bad "$1" "got '$3', want '$2'"; fi; }
has() { if [ -n "$2" ] && printf '%s\n' "$2" | grep -qF -- "$3"; then row_ok "$1"; else row_bad "$1" "no '$3' in: $(printf '%s' "$2" | head -c 400 | tr '\n' '|')"; fi; }
hasnt() { if [ -n "$2" ] && ! printf '%s\n' "$2" | grep -qF -- "$3"; then row_ok "$1"; else row_bad "$1" "unexpected '$3' (or empty) in: $(printf '%s' "$2" | head -c 400 | tr '\n' '|')"; fi; }

# ---- the scratch tree: a fake julia, a source file, two targets, a mutant list ----
mkdir -p "$W/bin"
cat > "$W/bin/julia" << 'EOF'
#!/usr/bin/env bash
# the fake: argv ends with the target; the verdict follows the mutated text of src.txt and LOGICKERNEL_TERM
t="${!#}"
echo "${LOGICKERNEL_TERM:-unset} $t" >> calls.log
src="$(cat src.txt)"
fails() { echo "Test Failed at $t:1"; exit 1; }
case "$src" in
    *X*) fails ;;                                                  # m1: caught on every type
    *Y*) [ "$LOGICKERNEL_TERM" = alt ] && exit 0; fails ;;         # m2: survives on alt
    *Z*) exit 0 ;;                                                 # m3 (declared equivalent): survives everywhere
    *W*) [ "$LOGICKERNEL_TERM" = alt ] && fails; exit 0 ;;         # m4 (declared equivalent): caught on alt
    *V*) fails ;;                                                  # m5: its only target is not term-generic
esac
[ -f "red_${LOGICKERNEL_TERM}" ] && fails                          # the unmutated tree: red where the flag file says
exit 0
EOF
chmod 755 "$W/bin/julia"
mkdir -p "$W/work"
cat > "$W/work/t_gen.jl" << 'EOF'
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
EOF
echo '@test true' > "$W/work/t_plain.jl"
echo 'A B C D E' > "$W/work/src.orig"
cat > "$W/work/list.py" << 'EOF'
TARGETS = ["t_plain.jl", "t_gen.jl"]
MUTANTS = [
    dict(id="m1 caught on every type", file="src.txt", old="A", new="X"),
    dict(id="m2 survives on alt", file="src.txt", old="B", new="Y"),
    dict(id="m3 equivalent, survives", file="src.txt", old="C", new="Z", equivalent="the C is dead"),
    dict(id="m4 equivalent, caught on alt", file="src.txt", old="D", new="W", equivalent="the D is dead"),
    dict(id="m5 plain target only", file="src.txt", old="E", new="V", targets=["t_plain.jl"]),
]
EOF

# py DIR CODE — Python on DIR's mutate_ci.py as a module (no bytecode, isolated)
py() { python3 -B -I -c "import sys; sys.path.insert(0, sys.argv[1]); import mutate_ci as m
$2" "$1"; }
# run_ci TOOLDIR ARG... — the tool in the scratch tree, outside CI's pin (GITHUB_ACTIONS), the fake julia first
run_ci() {
    local dir="$1"
    shift
    (cd "$W/work" && GITHUB_ACTIONS=true PATH="$W/bin:$PATH" python3 -B -I "$dir/mutate_ci.py" "$@")
}
fresh() { rm -rf "$W/work/mutation-out" "$W/work/calls.log" "$W/work"/red_*; cp "$W/work/src.orig" "$W/work/src.txt"; }
one_pair() { cp "$W/work/src.orig" "$W/work/src.txt"; run_ci "$@" > /dev/null 2>&1; }

# make_list N PATH — a list of N mutants
make_list() {
    python3 -B -I -c 'import sys
n = int(sys.argv[1])
print("MUTANTS = [")
for i in range(n):
    print("    dict(id=\"k%d t\", file=\"src.txt\", old=\"A\", new=\"X\")," % i)
print("]")' "$1" > "$2"
}

# ---- rows 1-4, as functions over a tool directory (the mutants run one of them on a copy) ----
checks() { checks_plan "$1"; checks_flow "$1"; }
checks_plan() {
    local T="$1" out rc
    # (1) the matrix expansion
    ok "expand: mutant by mutant, every type" "[('a', 'reference'), ('a', 'alt'), ('b', 'reference'), ('b', 'alt')]" \
        "$(py "$T" "print(m.expand(['a','b'], ['reference','alt']))")"
    ok "expand: no impls = one pair per mutant (the matrix of before)" "[('a', None), ('b', None)]" \
        "$(py "$T" "print(m.expand(['a','b'], None))")"
    ok "parse_impls: blanks and commas, each once, in order" "['alt', 'reference']" \
        "$(py "$T" "print(m.parse_impls('alt, reference alt'))")"
    ok "parse_impls: an unknown type is refused" "refused" \
        "$(py "$T" "
try:
    m.parse_impls('reference alto')
except SystemExit as e:
    print('refused' if 'alto' in str(e) else str(e))")"
    out="$(run_ci "$T" plan --impls "reference alt alt_interned" list.py 2> /dev/null)"
    has "plan: 5 mutants x 3 types = 15 pairs" "$out" "pairs=15"
    has "plan: the count stays the mutants'" "$out" "count=5"
    has "plan: job name of a pair (JSON-escaped, fromJson decodes it)" "$out" '"job": "mutant m2 \u00b7 alt"'
    has "plan: the types for the gather" "$out" "impls=reference alt alt_interned"
    has "plan: one Baseline per type, named" "$out" '"job": "Baseline (unmutated) \u00b7 alt_interned"'
    has "plan: the list's own targets" "$out" "targets=t_plain.jl t_gen.jl"
    out="$(run_ci "$T" plan list.py 2> /dev/null)"
    hasnt "plan without --impls: the matrix of before (no impl key)" "$out" '"impl"'
    hasnt "plan without --impls: no pairs line" "$out" "pairs="
    has "plan without --impls: names only" "$out" 'matrix={"include": [{"name": "m1"}, {"name": "m2"}'
    make_list 256 "$W/work/l256.py"
    make_list 257 "$W/work/l257.py"
    run_ci "$T" plan --impls reference l256.py > /dev/null 2>&1; rc=$?
    ok "plan: 256 pairs are the limit, taken" 0 "$rc"
    out="$(run_ci "$T" plan --impls reference l257.py 2>&1)"; rc=$?
    ok "plan: 257 pairs are refused" 1 "$rc"
    has "plan: ...and the message names the split by ids" "$out" "split the list by \`ids\`"
    make_list 85 "$W/work/l85.py"
    make_list 86 "$W/work/l86.py"
    run_ci "$T" plan --impls "reference alt alt_interned" l85.py > /dev/null 2>&1; rc=$?
    ok "plan: 85 mutants x 3 types = 255 are taken" 0 "$rc"
    run_ci "$T" plan --impls "reference alt alt_interned" l86.py > /dev/null 2>&1; rc=$?
    ok "plan: 86 mutants x 3 types = 258 are refused" 1 "$rc"

}
checks_flow() {
    local T="$1" out rc
    # (2) one pair
    fresh
    one_pair "$T" one --impl alt list.py m1 10 t_plain.jl t_gen.jl
    ok "one --impl alt: the record is m1.alt.json" yes "$([ -f "$W/work/mutation-out/m1.alt.json" ] && echo yes || echo no)"
    has "one --impl alt: LOGICKERNEL_TERM=alt reached the target" "$(cat "$W/work/calls.log")" "alt t_gen.jl"
    hasnt "one --impl alt: a target that is not term-generic is skipped" "$(cat "$W/work/calls.log")" "t_plain.jl"
    fresh
    one_pair "$T" one --impl reference list.py m1 10 t_plain.jl t_gen.jl
    has "one --impl reference: every target runs on the reference type" "$(cat "$W/work/calls.log")" "reference t_plain.jl"
    fresh
    one_pair "$T" one --impl alt_interned list.py m5 10 t_plain.jl
    out="$(cat "$W/work/mutation-out/m5.alt_interned.json" 2> /dev/null)"
    has "one: nothing term-generic left = N/A" "$out" '"verdict": "N/A (no term-generic target)"'
    ok "one: ...and nothing was run" "no" "$([ -f "$W/work/calls.log" ] && echo yes || echo no)"

    # (3) the gather, over a whole battery: baselines, then every (mutant, type) pair
    fresh
    for i in reference alt alt_interned; do run_ci "$T" baseline --impl "$i" 10 t_plain.jl t_gen.jl > /dev/null 2>&1; done
    for m in m1 m2 m3 m4 m5; do
        for i in reference alt alt_interned; do one_pair "$T" one --impl "$i" list.py "$m" 10 t_plain.jl t_gen.jl; done
    done
    out="$(run_ci "$T" collect --impls "reference alt alt_interned" list.py 5 2>&1)"; rc=$?
    ok "collect: a blocked battery exits 1" 1 "$rc"
    has "collect: the baselines are green" "$out" "Baseline (unmutated targets): **green**"
    has "collect: m1 caught on all three" "$out" "| m1 | caught |"
    has "collect: ...and the line says on which" "$out" "caught on: reference alt alt_interned"
    has "collect: m2 SURVIVED on alt is a SURVIVED mutant" "$out" "| m2 | SURVIVED |"
    has "collect: ...with where it survived and where it was caught" "$out" "SURVIVED on alt; caught on: reference alt_interned"
    has "collect: m3 declared equivalent survives on every type" "$out" "| m3 | EQUIVALENT (declared) |"
    has "collect: m4 equivalent but caught on alt is REFUTED" "$out" "| m4 | EQUIVALENT REFUTED |"
    has "collect: ...naming the type" "$out" "EQUIVALENT REFUTED on alt; EQUIVALENT (declared) on: reference alt_interned"
    has "collect: m5 is caught where it can run, N/A elsewhere" "$out" "caught on: reference; N/A (no term-generic target) on: alt alt_interned"
    has "collect: only m2 and m4 block" "$out" "**3 of 5 decided; blocking: m2, m4**"
    has "collect: the pairs that are not caught follow" "$out" "| m2 | alt | SURVIVED |"
    hasnt "collect: ...and a caught pair is not listed" "$out" "| m1 | alt |"
    cp "$W/work/mutation-out/verdicts.md" "$W/verdicts_full.md"
    out="$(run_ci "$T" collect --impls "reference alt alt_interned" list.py 3 m1 m3 m5 2>&1)"; rc=$?
    ok "collect: caught, a declared equivalent and an N/A do not block (exit 0)" 0 "$rc"
    has "collect: ...and nothing blocks" "$out" "**3 of 3 decided; blocking: none**"
    # a type's pair file gone (a job that died) is no verdict
    rm -f "$W/work/mutation-out/m1.alt_interned.json"
    out="$(run_ci "$T" collect --impls "reference alt alt_interned" list.py 1 m1 2>&1)"; rc=$?
    ok "collect: a pair without its record blocks" 1 "$rc"
    has "collect: ...as NO VERDICT, naming the type" "$out" "NO VERDICT on alt_interned; caught on: reference alt"
    # the baseline red on ONE type
    fresh
    touch "$W/work/red_alt"
    for i in reference alt alt_interned; do run_ci "$T" baseline --impl "$i" 10 t_plain.jl t_gen.jl > /dev/null 2>&1; rc=$?; echo "$i $rc" >> "$W/brc.txt"; done
    has "baseline: red only on alt exits 1 there" "$(cat "$W/brc.txt")" "alt 1"
    has "baseline: ...and 0 on the others" "$(cat "$W/brc.txt")" "alt_interned 0"
    rm -f "$W/brc.txt"
    for i in reference alt alt_interned; do one_pair "$T" one --impl "$i" list.py m1 10 t_plain.jl t_gen.jl; done
    out="$(run_ci "$T" collect --impls "reference alt alt_interned" list.py 1 m1 2>&1)"; rc=$?
    ok "collect: a baseline red on one type blocks (exit 1)" 1 "$rc"
    has "collect: the table says no verdict counts" "$out" "NOT GREEN — no verdict below counts"
    has "collect: ...per type" "$out" "Baseline per term type: reference green; alt NOT GREEN; alt_interned green"
    has "collect: the pair is NO VERDICT, not caught" "$out" "NO VERDICT (baseline red on alt) on alt; caught on: reference alt_interned"
    # a baseline never run on one type
    fresh
    for i in reference alt; do run_ci "$T" baseline --impl "$i" 10 t_plain.jl t_gen.jl > /dev/null 2>&1; done
    for i in reference alt alt_interned; do one_pair "$T" one --impl "$i" list.py m1 10 t_plain.jl t_gen.jl; done
    out="$(run_ci "$T" collect --impls "reference alt alt_interned" list.py 1 m1 2>&1)"; rc=$?
    ok "collect: a missing baseline blocks (exit 1)" 1 "$rc"
    has "collect: ...and is named" "$out" "alt_interned missing"
    # (4) the default is the table of before
    fresh
    run_ci "$T" baseline 10 t_plain.jl t_gen.jl > /dev/null 2>&1
    one_pair "$T" one list.py m1 10 t_plain.jl t_gen.jl
    ok "default: baseline.json and m1.json, no type in the name" "yes yes" \
        "$([ -f "$W/work/mutation-out/baseline.json" ] && echo -n yes || echo -n no) $([ -f "$W/work/mutation-out/m1.json" ] && echo yes || echo no)"
    has "default: the target ran on the reference type" "$(cat "$W/work/calls.log")" "reference t_plain.jl"
    out="$(run_ci "$T" collect list.py 1 m1 2>&1)"; rc=$?
    ok "default collect: exit 0" 0 "$rc"
    has "default collect: the five-column table" "$out" "| mutant | verdict | time | what it breaks | first failing test line |"
    hasnt "default collect: no impls column" "$out" "| impls |"
}

checks "$ROOT/tools"
cp "$W/verdicts_full.md" "$W/verdicts_keep.md"

# (5) the table reads through battery_table.py
bt="$(python3 -B -I -c "
import sys
sys.path.insert(0, sys.argv[1])
import battery_table as bt
lines = open(sys.argv[2]).read().splitlines()
base, rows, summary = bt.table_of(lines)
print(len(rows), rows[1][0], rows[1][1], '|', base.startswith('Baseline (unmutated targets): **green**'), '|', summary)
print(bt.desc(rows[1]))" "$ROOT/tools" "$W/verdicts_keep.md")"
has "battery_table.py: five rows, the survivor read as SURVIVED" "$bt" "5 m2 SURVIVED | True | **3 of 5 decided; blocking: m2, m4**"
has "battery_table.py: the what-it-breaks text carries the impls" "$bt" "SURVIVED on alt; caught on: reference alt_interned | survives on alt"

# (5b) battery_table.py judges the Baseline of EVERY term type: the first one that did not succeed, else the last
bj="$(python3 -B -I -c "
import sys
sys.path.insert(0, sys.argv[1])
import battery_table as bt
J = lambda n, c: {'name': n, 'id': n, 'status': 'completed', 'conclusion': c}
green = [J('Baseline (unmutated) · reference', 'success'), J('Baseline (unmutated) · alt', 'success')]
red = [J('Baseline (unmutated) · reference', 'success'), J('Baseline (unmutated) · alt', 'failure'), J('Baseline (unmutated) · alt_interned', 'success')]
print(bt.find_baseline(green)['name'], '|', bt.find_baseline(red)['name'], '|', bt.find_baseline([J('Plan', 'success')]))" "$ROOT/tools")"
ok "battery_table.py: a red Baseline of ONE type is the one judged; all green = the last; none = None" \
    "Baseline (unmutated) · alt | Baseline (unmutated) · alt | None" "$bj"

# (6) the workflow
WF="$ROOT/.github/workflows/mutation.yml"
wf="$(cat "$WF")"
has "workflow: the impls input, default all three" "$wf" 'default: "reference alt alt_interned"'
has "workflow: IMPLS defaults to all three for a push" "$wf" "IMPLS: \${{ inputs.impls || 'reference alt alt_interned' }}"
has "workflow: plan gets --impls" "$wf" 'plan --impls "$IMPLS"'
has "workflow: baseline gets --impl per matrix entry" "$wf" 'baseline --impl "$IMPL"'
has "workflow: one gets --impl per matrix entry" "$wf" 'one --impl "$IMPL"'
has "workflow: collect gets --impls" "$wf" 'collect --impls "$IMPLS"'
has "workflow: the 256-job note and the cost note are in the header" "$wf" "a list of 30 mutants is 90 jobs"
has "workflow: ...and the 85-mutant limit" "$wf" "more than 85 mutants on three types"
if python3 -I -c 'import yaml' 2> /dev/null; then
    y="$(python3 -I -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
j = d["jobs"]
print(sorted(j))
print(j["verdicts"]["needs"], j["mutant"]["needs"], j["baseline"]["needs"])
print(j["mutant"]["name"], "|", j["baseline"]["name"])
print(j["mutant"]["strategy"]["matrix"], "|", j["baseline"]["strategy"]["matrix"])
print(j["mutant"]["strategy"]["fail-fast"], j["baseline"]["strategy"]["fail-fast"], j["mutant"]["strategy"]["max-parallel"])
print(sorted(d[True]["workflow_dispatch"]["inputs"]), list(d[True]["push"]["branches"]))
print([s.get("with", {}).get("name") for s in j["mutant"]["steps"] if "upload-artifact" in s.get("uses", "")])
print([s.get("with", {}).get("name") for s in j["baseline"]["steps"] if "upload-artifact" in s.get("uses", "")])' "$WF")"
    has "workflow (yaml): the four jobs" "$y" "['baseline', 'mutant', 'plan', 'verdicts']"
    has "workflow (yaml): verdicts waits for plan, baseline and mutant" "$y" "['plan', 'baseline', 'mutant']"
    has "workflow (yaml): both fan-out jobs are named from the matrix entry" "$y" '${{ matrix.job }} | ${{ matrix.job }}'
    has "workflow (yaml): the mutant matrix is the plan's pairs, the baseline's the plan's types" "$y" \
        "fromJson(needs.plan.outputs.matrix) }} | \${{ fromJson(needs.plan.outputs.impl_matrix)"
    has "workflow (yaml): no fail-fast, max-parallel 20" "$y" "False False 20"
    has "workflow (yaml): the old inputs still work, the new one is added; the push trigger stays" "$y" \
        "['ids', 'impls', 'limit_s', 'mutants', 'targets'] ['mutants/**']"
    has "workflow (yaml): the mutant artifact is per pair" "$y" "'verdict-\${{ matrix.name }}-\${{ matrix.impl }}'"
    has "workflow (yaml): the baseline artifact is per type" "$y" "'verdict-baseline-\${{ matrix.impl }}'"
else
    echo "  NOTE no PyYAML on this python: the yaml rows are skipped, the text rows above ran"
fi

# (7) MUTANTS OF THE GATHER — each applied to a copy of tools/mutate_ci.py; the rows above are the oracle
mkdir -p "$W/mut"
cp "$ROOT/tools/mutate_drive.py" "$ROOT/tools/julia_pin.sh" "$W/mut/"
mutant() {   # mutant KIND NAME OLD NEW — a copy with OLD (exactly once) replaced; KIND's rows (plan|flow) must show a failure
    local kind="$1" name="$2" old="$3" new="$4" n
    cp "$ROOT/tools/battery_table.py" "$W/mut/" 2> /dev/null
    n="$(python3 -B -I -c '
import sys
s = open(sys.argv[1]).read()
old, new = sys.argv[2], sys.argv[3]
if s.count(old) != 1:
    print("BAD %d" % s.count(old))
    sys.exit(0)
open(sys.argv[4], "w").write(s.replace(old, new))
print("OK")' "$ROOT/tools/mutate_ci.py" "$old" "$new" "$W/mut/mutate_ci.py")"
    if [ "$n" != OK ]; then
        fail=$((fail + 1))
        echo "  FAIL mutant $name: its text occurs $n times in tools/mutate_ci.py"
        return
    fi
    local keep_v="$VERBOSE"
    VERBOSE=0 cf=0
    "checks_$kind" "$W/mut" > /dev/null 2>&1
    local got="$cf"
    VERBOSE="$keep_v"
    if [ "$got" -gt 0 ]; then pass=$((pass + 1)); echo "  ok   mutant $name: $got row(s) turned red"
    else fail=$((fail + 1)); echo "  FAIL mutant $name: SURVIVED the rows"; fi
}
# the unmutated copy first: green on every row (else a red mutant proves nothing)
cp "$ROOT/tools/mutate_ci.py" "$W/mut/mutate_ci.py"
VERBOSE=0 cf=0
checks "$W/mut" > /dev/null 2>&1
VERBOSE=1
ok "unmutated copy: every row green" 0 "$cf"
mutant flow "gather: a blocking pair no longer blocks the mutant" "    if bad:
        worst" "    if False:
        worst"
mutant flow "gather: the blocking groups lose their wording" '["%s on %s" % (v, " ".join(groups[v])) for v in bad]' '["%s on: %s" % (v, " ".join(groups[v])) for v in bad]'
mutant flow "gather: only a SURVIVED verdict blocks" "return v.startswith(BLOCKING)" "return v.startswith(BLOCKING[:1])"
mutant flow "gather: a red baseline is not read" 'if base is None or base.get("exit") != 0:' 'if base is None:'
mutant flow "gather: one green baseline is enough" "base_ok = all(ok.values())" "base_ok = any(ok.values())"
mutant flow "gather: a pair record lost is read as the mutant's" 'recs = {i: read(stem(name, i)) for i in keys}' 'recs = {i: read(stem(name, None)) for i in keys}'
mutant plan "matrix: only the first type is expanded" "for i in (impls or [None])]" "for i in (impls or [None])[:1]]"
mutant plan "matrix: the limit is one too high" "if npairs > MATRIX_MAX:" "if npairs > MATRIX_MAX + 1:"
mutant plan "matrix: the limit is one too low" "if npairs > MATRIX_MAX:" "if npairs >= MATRIX_MAX:"
mutant flow "run: LOGICKERNEL_TERM stays reference" 'LOGICKERNEL_TERM=impl or "reference")' 'LOGICKERNEL_TERM="reference")'
mutant flow "run: a target that is not term-generic runs on every type" "return [t for t in targets if is_generic(t, root)], [t for t in targets if not is_generic(t, root)]" "return list(targets), []"
mutant flow "run: the pair's record is named like the mutant's" "key = stem(name, impl)" "key = name"
mutant flow "verdict: a survivor of a declared equivalent is SURVIVED" 'return "EQUIVALENT (declared)" if declared else "SURVIVED"' 'return "SURVIVED"'
mutant flow "verdict: a declared equivalent that is caught stays caught" 'return "EQUIVALENT REFUTED" if declared else "caught"' 'return "caught"'
mutant flow "verdict: N/A is not given when nothing term-generic is left" "    if not run:
        record.update(verdict=NA" "    if False:
        record.update(verdict=NA"

echo "tools/test_mutate_ci_impl.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
