# ORIGINAL: Tooling4's mutant list — no swipl-devel counterpart.
# tools/mutants/Tooling4.py — the mutation battery of the CI-sharding batch (D-0059, D-0068), run ONCE,
# at the batch's close, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The
# format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` (a mutant that must SURVIVE, with the code reason) and `targets`.
#
# Subject: the gather (tools/evidence_ci.py), the slicing (test/ci_slices.jl) and the superseded
# cancel of tools/ci_status.sh — every one of them a guard that must be able to FAIL.
TARGETS = [
    "test/test_gate_split.jl",
]
EV = "tools/evidence_ci.py"
SL = "test/ci_slices.jl"
CS = "tools/ci_status.sh"
T = ["test/test_gate_split.jl"]
MUTANTS = [
    # ── tools/ci_status.sh: the superseded cancel (D-0071: each condition shown by a fixture) ──
    dict(id="TS1 a cancelled run is never superseded", file=CS, targets=T,
         old='''    if r["conclusion"] != "cancelled" or not r.get("created_at"):
        return False''',
         new='''    return False'''),
    dict(id="TS2 a failure is superseded too", file=CS, targets=T,
         old='''    if r["conclusion"] != "cancelled" or not r.get("created_at"):''',
         new='''    if r["conclusion"] not in ("cancelled", "failure") or not r.get("created_at"):'''),
    dict(id="TS3 a timed_out run is superseded too", file=CS, targets=T,
         old='''    if r["conclusion"] != "cancelled" or not r.get("created_at"):''',
         new='''    if r["conclusion"] not in ("cancelled", "timed_out") or not r.get("created_at"):'''),
    dict(id="TS4 the later run need not be later", file=CS, targets=T,
         old='''        and (o.get("created_at") or "") > r["created_at"]''',
         new='''        and (o.get("created_at") or "") != r["created_at"]'''),
    dict(id="TS5 the later run may be of another workflow (the match dropped)", file=CS, targets=T,
         old='''o is not r and wf(o) == wf(r) and o["head_sha"] == r["head_sha"]''',
         new='''o is not r and o["head_sha"] == r["head_sha"]'''),
    dict(id="TS6 the later run may be of another commit (the sha match dropped)", file=CS, targets=T,
         old='''o is not r and wf(o) == wf(r) and o["head_sha"] == r["head_sha"]''',
         new='''o is not r and wf(o) == wf(r)'''),
    dict(id="TS7 the later run may be on another ref (the ref match dropped)", file=CS, targets=T,
         old='''        and o.get("head_branch") == r.get("head_branch")
''',
         new='''
'''),
    dict(id="TS8 the later run may have ANY conclusion but success", file=CS, targets=T,
         old='''o["status"] == "completed" and o["conclusion"] == "success"''',
         new='''o["status"] == "completed" and o["conclusion"] != "success"'''),
    dict(id="TS9 the later run need not have a conclusion at all", file=CS, targets=T,
         old='''o["status"] == "completed" and o["conclusion"] == "success"''',
         new='''o["status"] == "completed"'''),
    dict(id="TS10 a cancelled run without a timestamp can be superseded", file=CS, targets=T,
         old='''    if r["conclusion"] != "cancelled" or not r.get("created_at"):''',
         new='''    if r["conclusion"] != "cancelled":'''),
    dict(id="TS11 the workflow is told by name alone, not by id", file=CS, targets=T,
         old='''    return r.get("workflow_id") or r["name"]''',
         new='''    return r["name"]'''),
    # ── tools/evidence_ci.py: the partition ──
    dict(id="EV1 the partition does not flag a unit run twice", file=EV, targets=T,
         old='''        if twice:
            self.problems.append("%s: run by two jobs''',
         new='''        if False:
            self.problems.append("%s: run by two jobs'''),
    dict(id="EV2 the partition does not flag a unit run by no job", file=EV, targets=T,
         old='''        if missed:
            self.problems.append("%s: %d unit(s) run by NO job''',
         new='''        if False:
            self.problems.append("%s: %d unit(s) run by NO job'''),
    dict(id="EV3 the partition does not flag a unit run outside its slice", file=EV, targets=T,
         old='''        if extra:
            self.problems.append("%s: run but not its to run''',
         new='''        if False:
            self.problems.append("%s: run but not its to run'''),
    dict(id="EV4 an empty suite is accepted", file=EV, targets=T,
         old='''        if not full:
            self.problems.append("the full unit list is EMPTY")''',
         new='''        if False:
            self.problems.append("the full unit list is EMPTY")'''),
    dict(id="EV5 jobs that enumerated a different suite are accepted", file=EV, targets=T,
         old='''            if u["all"] != full:''',
         new='''            if False:'''),
    dict(id="EV6 a job that ran as another slice is accepted", file=EV, targets=T,
         old='''        if u["slice"] != want:''',
         new='''        if False:'''),
    dict(id="EV7 a job without a unit list is accepted", file=EV, targets=T,
         old='''            self.problems.append("%s: no unit list" % job)''',
         new='''            pass'''),
    dict(id="EV8 a job that did not pass is accepted", file=EV, targets=T,
         old='''            if "passed" not in text:''',
         new='''            if False:'''),
    dict(id="EV9 a job without a verdict row is accepted", file=EV, targets=T,
         old='''            self.problems.append("%s: no verdict row (the job died before writing one)" % job)''',
         new='''            pass'''),
    # ── tools/evidence_ci.py: the static analysis's shards ──
    dict(id="EV10 a shard that analysed nothing is accepted", file=EV, targets=T,
         old='''                    if ran == 0:''',
         new='''                    if False:'''),
    dict(id="EV11 the shards' counts need not sum to the manifest's", file=EV, targets=T,
         old='''            if sums[key] != full:''',
         new='''            if False:'''),
    dict(id="EV12 a shard that ran another shard's slice is accepted", file=EV, targets=T,
         old='''                if f[0] == "shard" and (f[1], f[2]) != (str(k), str(shards)):''',
         new='''                if False:'''),
    dict(id="EV13 a one-off part run twice is accepted", file=EV, targets=T,
         old='''                if c != 1:''',
         new='''                if c == 0:'''),
    dict(id="EV14 a one-off part run by no shard is accepted", file=EV, targets=T,
         old='''                if c != 1:''',
         new='''                if c > 1:'''),
    dict(id="EV15 a shard missing its counts file is accepted", file=EV, targets=T,
         old='''                self.problems.append("sa_%d: no counts (the analysis did not run to its end)" % k)''',
         new='''                pass'''),
    dict(id="EV16 a shard that ran more than the analysis is accepted", file=EV, targets=T,
         old='''            if u is not None and [r[0] for r in u["ran"]] != [SA_LABEL]:''',
         new='''            if False:'''),
    dict(id="EV17 shards with different lists of parts are accepted", file=EV, targets=T,
         old='''                elif seen["parts"] != parts_all:''',
         new='''                elif False:'''),
    dict(id="EV18 a zero full count is accepted", file=EV, targets=T,
         old='''        if not totals.get("dispatch") or not totals.get("alloc"):''',
         new='''        if False:'''),
    # ── tools/evidence_ci.py: the second implementation's counts ──
    dict(id="EV19 an AltTerm slice that wrote no counts is accepted", file=EV, targets=T,
         old='''        if not got or any(s is None for s in got):''',
         new='''        if not got:'''),
    dict(id="EV20 a type that built no compound of its kind is accepted", file=EV, targets=T,
         old='''            if v == 0:
                self.problems.append("%s: no %s compound built over its slices"''',
         new='''            if v < 0:
                self.problems.append("%s: no %s compound built over its slices"'''),
    dict(id="EV21 the suite without the static analysis is accepted", file=EV, targets=T,
         old='''        if SA_LABEL not in full:''',
         new='''        if False:'''),
    dict(id="EV22 the unit costs include the static analysis", file=EV, targets=T,
         old='''                if f != SA_LABEL:
                    costs[f]''',
         new='''                if True:
                    costs[f]'''),
    # ── test/ci_slices.jl ──
    dict(id="SL1 an unset slice is not the whole run", file=SL, targets=T,
         old='''    isempty(s) && return (1, 1)''',
         new='''    isempty(s) && return (1, 2)'''),
    dict(id="SL2 a slice with k > n is accepted", file=SL, targets=T,
         old='''    1 <= k <= n || error''',
         new='''    1 <= k || error'''),
    dict(id="SL3 a slice with k = 0 is accepted", file=SL, targets=T,
         old='''    1 <= k <= n || error''',
         new='''    k <= n || error'''),
    dict(id="SL4 the k-th slice starts one item late", file=SL, targets=T,
         old='''(i - 1) % kn[2] == kn[1] - 1''',
         new='''i % kn[2] == kn[1] - 1'''),
    dict(id="SL5 a file with no cost counts as zero", file=SL, targets=T,
         old='''    cost(f) = get(costs, f, median)''',
         new='''    cost(f) = get(costs, f, 0.0)'''),
    dict(id="SL6 the heaviest file goes last", file=SL, targets=T,
         old='''sort(files; by=f -> (-cost(f), f))''',
         new='''sort(files; by=f -> (cost(f), f))'''),
    dict(id="SL7 a file goes into the group with the MOST load", file=SL, targets=T,
         old='''        k = argmin(load)''',
         new='''        k = argmax(load)'''),
    dict(id="SL8 the assignment depends on the order the files came in", file=SL, targets=T,
         old='''sort(files; by=f -> (-cost(f), f))''',
         new='''sort(files; by=f -> -cost(f), alg=QuickSort)'''),
    dict(id="SL9 a cost table line is read without skipping comments", file=SL, targets=T,
         old='''        (isempty(strip(l)) || startswith(l, '#')) && continue''',
         new='''        isempty(strip(l)) && continue'''),
]
