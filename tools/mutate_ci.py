#!/usr/bin/env python3
# ORIGINAL: the mutation battery's CI side (user, 2026-10-13) — no swipl-devel counterpart.
# tools/mutate_ci.py — what .github/workflows/mutation.yml calls. The LOCAL
# driver is tools/mutate_drive.py (a warm daemon, one mutant after another); here every mutant is a
# CI job of its own, so the three steps are separate commands. THE MUTANT LIST AND THE VERDICT RULES
# ARE THE SAME (see mutate_drive.py's header): `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `expect: "hang"`, `equivalent: <reason>`, `targets`.
#
#   mutate_ci.py plan MUTANTS.py [ID…]            print `matrix=…`, `count=…`, `targets=…` (the
#                                                 list's own `TARGETS`, space-separated; empty when
#                                                 it names none) and `shards=…` (the warm battery's matrix, N =
#                                                 max(1, min(6, ceil(count/6)))) for $GITHUB_OUTPUT
#   mutate_ci.py baseline LIMIT_S TARGET…         the targets on the unmutated tree → baseline.json
#   mutate_ci.py one MUTANTS.py ID LIMIT_S TARGET…   apply ID, run the targets → <ID>.json, <ID>.log
#   mutate_ci.py warm MUTANTS.py K N LIMIT_S [TARGET…]   SHARD K of N on the WARM DAEMON (audit D-0530): run as
#                                                 `tools/warm.sh locked python3 tools/mutate_ci.py warm …` after
#                                                 `tools/warm.sh start`; the shard takes every N-th selected mutant from the
#                                                 K-th (mutate_drive.in_shard), applies it, runs the targets through
#                                                 `tools/warm.sh file` (Revise hot-reloads the edit), restores the file, and
#                                                 writes the same <ID>.json/.log as `one`. Shard 1 runs the baseline FIRST
#                                                 (baseline.json); every shard ends with a closing baseline (closing-K.json): a
#                                                 red one turns that shard's warm records into NO VERDICT. A mutant of the list
#                                                 marked `"fresh": True` runs in a fresh process, as `one` does it (a declared
#                                                 escape hatch for a mutant the warm daemon decides differently). IDS (the
#                                                 environment, space-separated) selects like `plan`'s ID arguments.
#                                                 LOGICKERNEL_REQUIRE_SWIPL=1 with no swipl on PATH: exit 1 before any target, baseline.json RED
#                                                 (D-0536 item 2; tools/warm.sh hands the daemon the LOGICKERNEL_REQUIRE_* variables).
#   mutate_ci.py check-baseline                   exit 1 unless mutation-out/baseline.json (shard 1's) is there and green
#   mutate_ci.py collect MUTANTS.py COUNT [ID…]   the verdict table (stdout, verdicts.md); exit 0/1
#   mutate_ci.py annotate                         verdicts.md as notice annotations (stdout): a check
#                                                 run's annotations are readable through the API
#                                                 without a token, its job summary and logs are not
#
# A TARGET is a test file, run in a FRESH process on the reference term type
# (`julia --project=. <file>`, LOGICKERNEL_TERM=reference) — or `sh:<command>`.
# THE VERDICT, from exit codes first: a target exits 1 = caught; every target exits 0 = SURVIVED; a
# target past LIMIT_S = TIMEOUT (never "caught", unless the mutant expects a hang); another code =
# INVALID. An exit 1 is caught only when a test failed — mutate_drive.py's `judge`, the one
# classifier of both drivers (D-0050): code that did not parse or load = NO VERDICT (does not load);
# a test file with no failing test line = NO VERDICT (no failing test). A mutant declared
# `equivalent` must SURVIVE ("EQUIVALENT (declared)"); caught, its claim was wrong ("EQUIVALENT
# REFUTED"). BLOCKING: SURVIVED, TIMEOUT, INVALID, BADMATCH, EQUIVALENT REFUTED, NO VERDICT (either
# kind, or a missing verdict file), a baseline that is not green. Every record keeps the deciding
# line (`first_failure`: a caught one's first failing test line); the table shows it.
import json
import os
import runpy
import shutil
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True     # no tools/__pycache__: an untracked file voids the evidence marker
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mutate_drive import in_shard, judge, noload_hint, run_targets as _run_targets  # noqa: E402 — one classifier, two drivers

OUT = "mutation-out"
BLOCKING = ("SURVIVED", "TIMEOUT", "INVALID", "BADMATCH", "EQUIVALENT REFUTED", "NO VERDICT")


def pin_julia():
    """The LOCAL Julia pin (audit D-0465, D-0466; tools/lib_julia.sh): put the Julia of tools/WARM_JULIA_VERSION first
    on PATH for every target, or exit 7 (not installed / another version / LOGICKERNEL_JULIA_PIN_OFF=1, which a
    mutation path never accepts). In CI (GITHUB_ACTIONS=true) setup-julia's own version runs: nothing to do."""
    if os.environ.get("GITHUB_ACTIONS") == "true":
        return
    sh = os.path.join(os.path.dirname(os.path.abspath(__file__)), "julia_pin.sh")
    r = subprocess.run([sh, "path", "gate"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(r.returncode)
    os.environ["PATH"] = r.stdout.strip()


def resolve_list(path):
    """A scratch battery branch `perf/bat-<X>` (GATESPEED, audit D-0529) names the list tools/mutants/<X>.py: the
    workflow's `tools/<ref_name>.py` is mapped here (a push to `mutants/<X>` already is that path)."""
    pre = "tools/perf/bat-"
    if path.startswith(pre) and path.endswith(".py"):
        return "tools/mutants/" + path[len(pre):]
    return path


def load(path, only):
    path = resolve_list(path)
    # CISTATUS (audit D-0262): the first argument is the mutant list as a PATH in the repository
    # (the workflow input `mutants`: tools/mutants/<step>.py), never a bare step name — three
    # dispatches of 2026-10-30 named `ARGVAR2` and died here with a bare FileNotFoundError.
    if not os.path.isfile(path):
        sys.exit("mutate_ci: no mutant list at %r — give the PATH of the step's list in the repository, "
                 "tools/mutants/<step>.py (e.g. tools/mutants/ARGVAR2.py), not a bare step name" % path)
    mutants = runpy.run_path(path)["MUTANTS"]
    names = [m["id"].split()[0] for m in mutants]
    if len(set(names)) != len(names):
        sys.exit("mutate_ci: two mutants share a name in %s" % path)
    unknown = set(only) - set(names)
    if unknown:
        sys.exit("mutate_ci: no such mutant: %s" % ", ".join(sorted(unknown)))
    return [m for m in mutants if not only or m["id"].split()[0] in only]


def run_target(target, limit):
    """(exit code or "hang", output) of one target in a fresh process GROUP: past the limit the whole
    group is killed — a test's own children (swipl) hold the output pipe open otherwise, and the
    read would wait for them."""
    env = dict(os.environ, LOGICKERNEL_TERM="reference")
    cmd = ["julia", "--project=.", "--startup-file=no", target]
    if target.startswith("sh:"):
        cmd = ["bash", "-c", target[3:]]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         env=env, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=limit)
        return p.returncode, out
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, _ = p.communicate()
        return "hang", out


def run_targets(targets, limit):
    """mutate_drive.py's `run_targets`, each target in a fresh process: (result, log, line)."""
    def run1(t):
        rc, out = run_target(t, limit)
        return judge(t, rc, out, os.getcwd())[0], out
    return _run_targets(targets, run1, os.getcwd())


def write(name, record, log):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(record, f)
    with open(os.path.join(OUT, name + ".log"), "w") as f:
        f.write(log)


def plan(argv):
    mutants = load(argv[0], argv[1:])
    if not mutants:
        sys.exit("mutate_ci: the plan is empty")
    matrix = {"include": [{"name": m["id"].split()[0]} for m in mutants]}
    print("matrix=" + json.dumps(matrix))
    print("count=%d" % len(mutants))
    # the list's own targets: what a run started by a push (no inputs) uses
    targets = runpy.run_path(resolve_list(argv[0])).get("TARGETS", [])
    if any(" " in t or "\n" in t for t in targets):
        sys.exit("mutate_ci: a target of TARGETS holds a blank")
    print("targets=" + " ".join(targets))
    n = shard_count(len(mutants))
    print("shards=" + json.dumps({"include": [{"shard": k, "of": n} for k in range(1, n + 1)]}))
    return 0


def shard_count(count):
    """The warm battery's shards: one per 6 mutants, at least 1, at most 6."""
    return max(1, min(6, -(-count // 6)))


def baseline(argv):
    limit, targets = int(argv[0]), argv[1:]
    if not targets:
        sys.exit("mutate_ci: no target")
    t0 = time.time()
    rc, log, _ = run_targets(targets, limit)
    write("baseline", {"name": "baseline", "exit": rc, "seconds": round(time.time() - t0)}, log)
    print("baseline exit", rc)
    return 0 if rc == 0 else 1


def verdict_of(m, rc):
    """A mutant's verdict string from its targets' result (`one` and `warm` share it)."""
    declared = bool(m.get("equivalent"))
    if rc == "noload":
        return "NO VERDICT (does not load)"
    if rc == "notest":
        return "NO VERDICT (no failing test)"
    if rc == 1:
        return "EQUIVALENT REFUTED" if declared else "caught"
    if rc == "hang":
        return "caught (hang)" if m.get("expect") == "hang" else "TIMEOUT"
    if rc == 0:
        return "EQUIVALENT (declared)" if declared else "SURVIVED"
    return "INVALID"


def one(argv):
    path, name, limit, targets = argv[0], argv[1], int(argv[2]), argv[3:]
    (m,) = load(path, [name])
    targets = m.get("targets") or targets
    if not targets:
        sys.exit("mutate_ci: no target")
    with open(m["file"]) as f:
        src = f.read()
    record = {"name": name, "id": m["id"], "equivalent": m.get("equivalent", "")}
    if src.count(m["old"]) != 1:
        record.update(verdict="BADMATCH", seconds=0,
                      note="`old` occurs %d times in %s" % (src.count(m["old"]), m["file"]))
        write(name, record, "")
        print(name, "BADMATCH")
        return 0
    with open(m["file"], "w") as f:
        f.write(src.replace(m["old"], m["new"]))
    t0 = time.time()
    rc, log, why = run_targets(targets, limit)
    verdict = verdict_of(m, rc)
    why = "; ".join(x for x in (why, noload_hint(m, verdict)) if x)
    record.update(verdict=verdict, exit=rc, seconds=round(time.time() - t0), first_failure=why)
    write(name, record, log)
    print(name, verdict, "—", why or "-")
    return 0                                            # the verdict is data: `collect` judges


def warm_run1(limit, root, impl):
    """mutate_drive.py main()'s `run1` (lines 126-140), for CI's shard: a test file goes through the warm daemon
    (`tools/warm.sh file TARGET IMPL`, WARM_TIMEOUT_S=limit); a `sh:` target runs fresh, as in the local driver; a
    target past the limit (rc -9, or the lane's exit 2) restarts the daemon and is a "hang"."""
    def run1(target):
        if target.startswith("sh:"):
            rc, out = run_target(target, limit)
            return judge(target, rc, out, root)[0], out
        env = dict(os.environ, WARM_TIMEOUT_S=str(limit))
        try:
            r = subprocess.run(["tools/warm.sh", "file", target, impl], cwd=root, capture_output=True, text=True,
                               timeout=limit + 120, env=env)
            rc, out = r.returncode, r.stdout + r.stderr
        except subprocess.TimeoutExpired:
            rc, out = -9, ""
        if rc == -9 or rc == 2:                         # timed out: the daemon is still busy
            subprocess.run(["tools/warm.sh", "restart"], cwd=root, capture_output=True)
            return "hang", out
        return judge(target, rc, out, root)[0], out
    return run1


def run_mutant(m, name, targets, run, driver):
    """Apply the mutant (its text must occur exactly once: else BADMATCH), run the targets through `run`
    (targets -> (result, log, line)), restore the file, write <name>.json/.log; returns the record."""
    with open(m["file"]) as f:
        src = f.read()
    record = {"name": name, "id": m["id"], "equivalent": m.get("equivalent", ""), "driver": driver}
    if src.count(m["old"]) != 1:
        record.update(verdict="BADMATCH", seconds=0,
                      note="`old` occurs %d times in %s" % (src.count(m["old"]), m["file"]))
        write(name, record, "")
        print(name, "BADMATCH", flush=True)
        return record
    with open(m["file"], "w") as f:
        f.write(src.replace(m["old"], m["new"]))
    t0 = time.time()
    try:
        rc, log, why = run(targets)
    finally:
        with open(m["file"], "w") as f:                 # the next mutant starts from the original text
            f.write(src)
    verdict = verdict_of(m, rc)
    why = "; ".join(x for x in (why, noload_hint(m, verdict)) if x)
    record.update(verdict=verdict, exit=rc, seconds=round(time.time() - t0), first_failure=why)
    write(name, record, log)
    print(name, verdict, "—", why or "-", "(%s, %d s)" % (driver, record["seconds"]), flush=True)
    return record


def oracle_missing():
    """Why the warm shape must not run (audit D-0536 item 2), or "": LOGICKERNEL_REQUIRE_SWIPL=1 (the workflow's switch:
    a missing oracle is an error, never a skipped differential) and no `swipl` on PATH. The suites' own required-checks
    fire in the daemon too (tools/warm.sh hands it the LOGICKERNEL_REQUIRE_* variables), but a daemon started without them
    would skip those tests GREEN: this is the wrapper's own check, before any target, so the baseline is RED."""
    if os.environ.get("LOGICKERNEL_REQUIRE_SWIPL") == "1" and shutil.which("swipl") is None:
        return "LOGICKERNEL_REQUIRE_SWIPL=1 but swipl is not on PATH: every differential would be skipped"
    return ""


def warm(argv):
    path, k, n, limit, targets = argv[0], int(argv[1]), int(argv[2]), int(argv[3]), argv[4:]
    if not 1 <= k <= n:
        sys.exit("mutate_ci: warm: shard %d of %d" % (k, n))
    if not targets:
        sys.exit("mutate_ci: no target")
    mutants = load(path, os.environ.get("IDS", "").split())
    root, impl = os.getcwd(), os.environ.get("MUTATE_IMPL", "reference")
    warm_run = lambda tgts: _run_targets(tgts, warm_run1(limit, root, impl), root)
    fresh_run = lambda tgts: run_targets(tgts, limit)
    why = oracle_missing()
    if why:                                             # RED before any target: a skipped test is a failure in the warm shape
        print("::error title=oracle::%s: no verdict counts" % why)
        if k == 1:
            write("baseline", {"name": "baseline", "exit": 2, "seconds": 0, "driver": "warm"}, why + "\n")
        return 1
    if k == 1:                                          # the unmutated tree first, on the warm daemon (D-0374: red voids the battery)
        t0 = time.time()
        rc, log, _ = warm_run(targets)
        write("baseline", {"name": "baseline", "exit": rc, "seconds": round(time.time() - t0), "driver": "warm"}, log)
        print("baseline exit", rc, flush=True)
        if rc != 0:
            print("::error title=baseline::the unmutated targets are not green on the warm daemon: no verdict counts")
            return 1
    records = []
    for i, m in enumerate(mutants, 1):
        if not in_shard(i, (k, n)):
            continue
        name = m["id"].split()[0]
        fresh = bool(m.get("fresh"))
        records.append(run_mutant(m, name, m.get("targets") or targets, fresh_run if fresh else warm_run,
                                  "fresh" if fresh else "warm"))
    t0 = time.time()                                    # the closing baseline: a daemon that degraded turns the verdicts above into noise
    rc, log, _ = warm_run(targets)
    write("closing-%d" % k, {"name": "closing-%d" % k, "exit": rc, "seconds": round(time.time() - t0), "driver": "warm"}, log)
    print("closing baseline exit", rc, flush=True)
    if rc != 0:
        print("::error title=closing baseline::shard %d: the unmutated targets are red after its mutants — its warm verdicts are NO VERDICT" % k)
        for r in records:
            if r.get("driver") == "warm" and r["verdict"] != "BADMATCH":
                r["first_failure"] = "closing baseline red (was: %s); %s" % (r["verdict"], r.get("first_failure", ""))
                r["verdict"] = "NO VERDICT (closing baseline red)"
                with open(os.path.join(OUT, r["name"] + ".json"), "w") as f:
                    json.dump(r, f)
    return 0                                            # the verdict is data: `collect` judges


def check_baseline(argv):
    """The cheap `Baseline (unmutated)` job: shard 1's baseline.json, from the artifacts, green or not."""
    p = os.path.join(OUT, "baseline.json")
    if not os.path.isfile(p):
        print("::error title=baseline::no baseline.json: shard 1 died before it wrote its baseline")
        return 1
    with open(p) as f:
        b = json.load(f)
    if b.get("exit") != 0:
        print("::error title=baseline::the unmutated targets are not green (exit %s, %s s): no verdict of this battery counts"
              % (b.get("exit"), b.get("seconds")))
        return 1
    print("baseline green, %s s (%s)" % (b.get("seconds"), b.get("driver", "fresh")))
    for name in sorted(x for x in os.listdir(OUT) if x.startswith("closing-") and x.endswith(".json")):
        with open(os.path.join(OUT, name)) as f:
            c = json.load(f)
        print("%s: exit %s, %s s" % (name[:-5], c.get("exit"), c.get("seconds")))
    return 0


def collect(argv):
    # an empty COUNT is a failed Plan step (its output `count` was never written): say so
    if not argv[1].strip().isdigit():
        sys.exit("mutate_ci: collect: COUNT is %r — the Plan step gave no mutant count (it failed, "
                 "see its log: usually a mutants input that is not tools/mutants/<step>.py)" % argv[1])
    path, count, only = argv[0], int(argv[1]), argv[2:]
    mutants = load(path, only)
    if len(mutants) != count:
        sys.exit("mutate_ci: the plan had %d mutants, the list now gives %d" % (count, len(mutants)))
    rows, blocked = [], []

    def read(name):
        p = os.path.join(OUT, name + ".json")
        if not os.path.isfile(p):
            return None
        with open(p) as f:
            return json.load(f)

    base = read("baseline")
    base_ok = base is not None and base.get("exit") == 0
    for m in mutants:
        name = m["id"].split()[0]
        r = read(name) or {"verdict": "NO VERDICT", "seconds": 0}
        v = r["verdict"]
        if v.startswith(BLOCKING) or not base_ok:
            blocked.append(name)
        what = m["id"][len(name):].strip()
        if m.get("equivalent"):
            what += " — declared equivalent, pending audit: " + m["equivalent"]
        rows.append("| %s | %s | %s s | %s | %s |" % (name, v, r.get("seconds", 0), what.replace("|", "\\|"),
                                                   (r.get("first_failure") or "").replace("|", "\\|")))
    lines = ["## Mutation battery — %s" % path, "",
             "Baseline (unmutated targets): **%s**%s" % (
                 "green" if base_ok else "NOT GREEN — no verdict below counts",
                 "" if base is None else ", %s s" % base.get("seconds", 0)), "",
             "| mutant | verdict | time | what it breaks | first failing test line |",
             "|---|---|---|---|---|"] + rows + [""]
    n = len(mutants)
    lines.append("**%d of %d decided; blocking: %s**" % (
        n - len(blocked), n, ", ".join(blocked) if blocked else "none"))
    text = "\n".join(lines) + "\n"
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "verdicts.md"), "w") as f:
        f.write(text)
    sys.stdout.write(text)
    return 1 if blocked or not base_ok else 0


ANNOTATIONS_MAX, ANNOTATION_CHARS = 10, 4000          # GitHub: 10 notices per step; a short message


def annotate(argv):
    """verdicts.md as `::notice` workflow commands, the rows packed in order into at most
    ANNOTATIONS_MAX messages of at most ANNOTATION_CHARS characters each, numbered "verdicts i/n";
    a row that does not fit is cut, and every annotation is printed — none dropped."""
    with open(os.path.join(OUT, "verdicts.md")) as f:
        rows = [ln[:ANNOTATION_CHARS] for ln in f.read().splitlines() if ln.strip()]
    parts, cur = [], ""
    for ln in rows:
        if cur and len(cur) + 1 + len(ln) > ANNOTATION_CHARS:
            parts.append(cur)
            cur = ""
        cur = ln if not cur else cur + "\n" + ln
    parts.append(cur)
    if len(parts) > ANNOTATIONS_MAX:
        print("mutate_ci: annotate: %d parts, GitHub shows %d" % (len(parts), ANNOTATIONS_MAX), file=sys.stderr)
    esc = lambda t: t.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    for i, part in enumerate(parts, 1):
        print("::notice title=verdicts %d/%d::%s" % (i, len(parts), esc(part)))
    return 0 if len(parts) <= ANNOTATIONS_MAX else 1


if __name__ == "__main__":
    commands = {"plan": plan, "baseline": baseline, "one": one, "warm": warm, "check-baseline": check_baseline,
                "collect": collect, "annotate": annotate}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit("usage: mutate_ci.py plan|baseline|one|warm|check-baseline|collect|annotate … (see the header)")
    if sys.argv[1] in ("baseline", "one", "warm"):      # the commands that start a Julia
        pin_julia()
    sys.exit(commands[sys.argv[1]](sys.argv[2:]))
