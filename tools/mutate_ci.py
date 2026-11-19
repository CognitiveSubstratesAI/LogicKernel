#!/usr/bin/env python3
# ORIGINAL: the mutation battery's CI side (user, 2026-10-13) — no swipl-devel counterpart.
# tools/mutate_ci.py — what .github/workflows/mutation.yml calls. The LOCAL
# driver is tools/mutate_drive.py (a warm daemon, one mutant after another); here every mutant is a
# CI job of its own, so the three steps are separate commands. THE MUTANT LIST AND THE VERDICT RULES
# ARE THE SAME (see mutate_drive.py's header): `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `expect: "hang"`, `site: "<substring>"`, `equivalent: <reason>`, `targets`.
#
#   mutate_ci.py plan MUTANTS.py [ID…]            print `matrix=…`, `count=…` and `targets=…` (the
#                                                 list's own `TARGETS`, space-separated; empty when
#                                                 it names none) for $GITHUB_OUTPUT
#   mutate_ci.py baseline LIMIT_S TARGET…         the targets on the unmutated tree → baseline.json; a RED baseline
#                                                 prints, after `baseline exit N`, its cause (<= 30 lines: the failing
#                                                 file, the first failing test and its message, the Test Summary;
#                                                 `baseline_cause`, D-0709 item 3)
#   mutate_ci.py one MUTANTS.py ID LIMIT_S TARGET…   apply ID, run the targets → <ID>.json, <ID>.log
#   mutate_ci.py collect MUTANTS.py COUNT [ID…]   the verdict table (stdout, verdicts.md); exit 0/1; a red baseline
#                                                 gets ONE `### Baseline cause` section (the same lines, from
#                                                 baseline.log) and every NO VERDICT row points at it
#   mutate_ci.py annotate                         verdicts.md as notice annotations (stdout): a check
#                                                 run's annotations are readable through the API
#                                                 without a token, its job summary and logs are not
#
# A TARGET is a test file, run in a FRESH process on the reference term type
# (`julia --project=. <file>`, LOGICKERNEL_TERM=reference) — or `sh:<command>`.
# THE VERDICT, from exit codes first: a target exits 1 = caught; every target exits 0 = SURVIVED; a
# target cut (time limit or memory cap, below) = TIMEOUT, in the table `TIMEOUT (time)` / `TIMEOUT (memory)`
# (never "caught", unless the mutant expects a hang, below); another code = INVALID. An exit 1 is caught only when a test failed — mutate_drive.py's `judge`, the one
# classifier of both drivers (D-0050): code that did not parse or load = NO VERDICT (does not load);
# a test file with no failing test line = NO VERDICT (no failing test). A mutant declared
# `equivalent` must SURVIVE ("EQUIVALENT (declared)"); caught, its claim was wrong ("EQUIVALENT
# REFUTED"). BLOCKING: SURVIVED, TIMEOUT, INVALID, BADMATCH, EQUIVALENT REFUTED, NO VERDICT (either
# kind, or a missing verdict file), a baseline that is not green. Every record keeps the deciding
# line (`first_failure`: a caught one's first failing test line); the table shows it.
#
# THE MEMORY CAP AND THE CUT (audit D-0852 (4), D-0916 (1)): a mutant that makes a loop grow without bound
# must end as a verdict before the runner dies (a lost runner leaves NO VERDICT and no record). Each target
# runs in its own session; every MUTATE_CI_POLL_S seconds (default 1) the harness sums the resident set of the
# whole process group (and session) from /proc — no psutil — and kills the group with SIGKILL once the sum
# passes MUTATE_CI_MEM_MB (default 5500; the GitHub standard runner has 16 GB, a local capped scope 6 GB).
# The target's output goes to a file, not a pipe: the harness holds no output in memory while it waits, and
# a logged output over 16 MB is kept as its first 4 MB and its last 4 MB. The target's oom_score_adj is
# raised to 1000: if the kernel does pick a victim, it is the target, not the harness. On a host without
# /proc the cap is inactive (a note goes to stderr). The time limit LIMIT_S is unchanged (per target, from
# its start; the clock that counts the tests only, D-0852 (4a), needs a marker the test files do not
# write yet). A cut gives rc "hang" and, in the record, `cut`: kind (`memory` | `time`), the reason (`rss N
# MB at second S` | `limit L s`), the output size at the cut and the last EVIDENCE_LINES lines of the
# output. Before the kill the harness sends SIGQUIT to the group's processes named like julia (comm
# matches MUTATE_CI_SAMPLE_COMM, default `^julia`): Julia dumps its stacks and keeps running; three seconds
# later the tail is taken, so it holds the stack at the cut.
# A CUT IS A KILL only for a mutant that declares `expect="hang"` AND `site="<substring>"` (the function or
# file:line where the hang is) AND whose evidence tail contains that substring: "caught (hang)". Declared
# but no site, or the site not in the evidence: `TIMEOUT (hang declared, site not shown)`, blocking. A time
# cut alone proves nothing (a slow run reaches the limit as well).
import json
import os
import re
import runpy
import signal
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True     # no tools/__pycache__: an untracked file voids the evidence marker
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mutate_drive import judge, noload_hint, run_targets as _run_targets  # noqa: E402 — one classifier, two drivers
from ci_compile_summary import ANCHOR_TEST, ANSI  # noqa: E402 — the compile summary's Julia failure shapes

OUT = "mutation-out"
EVIDENCE_LINES = 60                       # the output tail kept as the evidence of a cut
SAMPLE_WAIT_S = 3.0                       # SIGQUIT to the stack dump
LOG_CAP = 16 << 20                        # a longer log is kept as its first and its last LOG_KEEP bytes
LOG_KEEP = 4 << 20
CUTS = []                                 # the cuts of the targets run since the last reset, in order
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


def load(path, only):
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


def proc_group(pgid):
    """[(pid, comm, rss_bytes)] of every process in process group PGID or session PGID, from /proc
    (fields 5 and 6 of /proc/<pid>/stat, parsed after the LAST `)`: a comm may hold blanks and parentheses)."""
    page = os.sysconf("SC_PAGE_SIZE")
    members = []
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open("/proc/%s/stat" % d) as f:
                st = f.read()
            rest = st[st.rindex(")") + 2:].split()
            if int(rest[2]) == pgid or int(rest[3]) == pgid:
                members.append((int(d), st[st.index("(") + 1:st.rindex(")")], int(rest[21]) * page))
        except (OSError, ValueError, IndexError):
            continue                                   # gone while we looked
    return members


def tail_lines(f, n):
    """The last N lines of an open binary file, read from its end (never the whole file)."""
    pos = f.seek(0, 2)
    buf = b""
    while pos > 0 and buf.count(b"\n") <= n:
        step = min(65536, pos)
        pos -= step
        f.seek(pos)
        buf = f.read(step) + buf
    return buf.decode(errors="replace").splitlines()[-n:]


def read_log(f):
    """The output file as text; over LOG_CAP bytes its first and last LOG_KEEP bytes with a note between."""
    size = f.seek(0, 2)
    f.seek(0)
    if size <= LOG_CAP:
        return f.read().decode(errors="replace")
    head = f.read(LOG_KEEP)
    f.seek(size - LOG_KEEP)
    return (head.decode(errors="replace") + "\n[... %d bytes of output cut by mutate_ci ...]\n" % (size - 2 * LOG_KEEP)
            + f.read().decode(errors="replace"))


def _own_oom_victim():
    """In the target, before exec: the kernel's first victim (a raise of oom_score_adj needs no privilege)."""
    try:
        with open("/proc/self/oom_score_adj", "w") as f:
            f.write("1000")
    except OSError:
        pass


def kill_group(pgid):
    """SIGKILL to the whole group and to the other members of its session."""
    for pid, _, _ in proc_group(pgid):
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    try:
        os.killpg(pgid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def run_target(target, limit):
    """(exit code or "hang", output) of one target in a fresh process GROUP: past the limit, or past
    MUTATE_CI_MEM_MB of resident memory in the group, the whole group is killed — a test's own children
    (swipl) hold the output open otherwise, and the read would wait for them. A cut appends a dict to CUTS
    (see the header) and a `=== CUT` line to the output. The output goes to a file: the harness stays small."""
    env = dict(os.environ, LOGICKERNEL_TERM="reference")
    cap = float(os.environ.get("MUTATE_CI_MEM_MB", "5500")) * (1 << 20)
    poll = float(os.environ.get("MUTATE_CI_POLL_S", "1"))
    comm = re.compile(os.environ.get("MUTATE_CI_SAMPLE_COMM", r"^julia"))
    cmd = ["julia", "--project=.", "--startup-file=no", target]
    if target.startswith("sh:"):
        cmd = ["bash", "-c", target[3:]]
    if not os.path.isdir("/proc/self"):
        sys.stderr.write("mutate_ci: no /proc: the memory cap is inactive\n")
    with tempfile.TemporaryFile() as out:
        p = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, env=env, start_new_session=True,
                             preexec_fn=_own_oom_victim)
        t0, cut = time.monotonic(), None
        while True:
            try:
                p.wait(timeout=max(0.01, min(poll, limit - (time.monotonic() - t0))))
                return p.returncode, read_log(out)
            except subprocess.TimeoutExpired:
                pass
            secs = time.monotonic() - t0
            rss = sum(r for _, _, r in proc_group(p.pid))
            if rss > cap:
                cut = dict(kind="memory", reason="rss %d MB at second %d" % (rss >> 20, secs), rss_mb=rss >> 20)
                break
            if secs >= limit:
                cut = dict(kind="time", reason="limit %s s" % limit)
                break
        # the stack at the cut: SIGQUIT makes Julia dump its stacks and keep running
        julias = [pid for pid, c, _ in proc_group(p.pid) if comm.search(c)]
        for pid in julias:
            try:
                os.kill(pid, signal.SIGQUIT)
            except (ProcessLookupError, PermissionError):
                pass
        t1 = time.monotonic()
        while julias and time.monotonic() - t1 < SAMPLE_WAIT_S:
            time.sleep(0.25)
            if sum(r for _, _, r in proc_group(p.pid)) > cap * 1.25:   # still growing: no more waiting
                break
        cut["seconds"] = round(time.monotonic() - t0)
        cut["output_bytes"] = out.seek(0, 2)
        cut["evidence"] = tail_lines(out, EVIDENCE_LINES)
        kill_group(p.pid)
        p.wait()
        CUTS.append(cut)
        log = read_log(out) + "\n=== CUT (%s): %s; output %d bytes ===\n" % (cut["kind"], cut["reason"], cut["output_bytes"])
        return "hang", log


PRECOMPILE_LIMIT = int(os.environ.get("MUTATE_CI_PRECOMPILE_LIMIT", "3600"))
LAST_PRECOMPILE = {"seconds": None}


def precompile_tree():
    """THE MUTATED TREE IS PRECOMPILED ONCE, BEFORE THE TARGETS, under a limit of its own (audit D-0852 (4), D-0888 (3)): the
    target limit then counts the tests, not the package load and precompile, which on a loaded host read as TIMEOUT (TB5-P7 and
    PR1-R7 on 2026-11-17: 1500 s, caught in 1075 s and 935 s at 4000 s). Past its limit, or past the memory cap of a target (MUTATE_CI_MEM_MB:
    the group's RSS polled as run_target does, oom_score_adj 1000), the precompile is killed and the targets compile for
    themselves, as before: they are capped too. Only in a Julia project (a Project.toml in the working directory).
    Seconds, or None."""
    LAST_PRECOMPILE["seconds"] = None
    if not os.path.isfile("Project.toml"):
        return None
    t0 = time.monotonic()
    cap = float(os.environ.get("MUTATE_CI_MEM_MB", "5500")) * (1 << 20)      # the SAME memory cap as a target (MEMCAP-2)
    poll = float(os.environ.get("MUTATE_CI_POLL_S", "1"))
    p = subprocess.Popen(["julia", "--project=.", "--startup-file=no", "-e", "using Pkg; Pkg.precompile()"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
                         preexec_fn=_own_oom_victim)
    while True:
        try:
            p.wait(timeout=max(0.01, min(poll, PRECOMPILE_LIMIT - (time.monotonic() - t0))))
            break
        except subprocess.TimeoutExpired:
            pass
        if (time.monotonic() - t0 >= PRECOMPILE_LIMIT
                or sum(r for _, _, r in proc_group(p.pid)) > cap):    # past its limit or the cap: killed, the targets compile for themselves
            kill_group(p.pid)
            p.wait()
            break
    LAST_PRECOMPILE["seconds"] = round(time.monotonic() - t0)
    return LAST_PRECOMPILE["seconds"]


def run_targets(targets, limit):
    """mutate_drive.py's `run_targets`, each target in a fresh process: (result, log, line)."""
    if any(not t.startswith("sh:") for t in targets):      # a Julia target: precompile first (the limit counts the tests)
        precompile_tree()
    def run1(t):
        rc, out = run_target(t, limit)
        return judge(t, rc, out, os.getcwd())[0], out
    return _run_targets(targets, run1, os.getcwd())


REACH_LINE = re.compile(r"^MUTREACH (\S+) (\d+)\s*$", re.M)
REACH_BUDGET = int(os.environ.get("MUTATE_CI_REACH_BUDGET", "5400"))


def reach_probe(name):
    """A Julia statement that COUNTS its executions in the process environment (a `const` defined during a running top-level
    block is not visible to the calls inside it: Julia's world age) and prints the total at exit, once per process:
    `MUTREACH <name> <n>`. One line, no dollar sign."""
    x = re.sub(r"\W", "_", name)
    return ('let _k = "MR_%s", _v = get(ENV, _k, nothing); _v === nothing && atexit(() -> println(stderr, "MUTREACH %s ", '
            'get(ENV, _k, "0"))); ENV[_k] = string(_v === nothing ? 1 : parse(Int, _v) + 1) end' % (x, x))


def reach_pass(m, src, name, targets, limit):
    """How often the targets REACH the mutated line (audit D-0849, D-0868 (2)(c): a mutant that survives through a line no
    target reaches proves nothing): the ORIGINAL code with a counter in front of `old`, each target in a fresh process, the
    counts summed over their `MUTREACH` lines. None when the count cannot be read: the probe does not load (`old` is not at a
    statement start) or a target fails or hangs under it (the counter, not the mutation, is then in doubt)."""
    with open(m["file"], "w") as f:
        f.write(src.replace(m["old"], reach_probe(name) + "\n" + m["old"]))
    rc, log, _ = run_targets(targets, limit)
    with open(m["file"], "w") as f:                      # the file as it was found
        f.write(src)
    if rc != 0:
        return None
    x = re.sub(r"\W", "_", name)
    return sum(int(n) for who, n in REACH_LINE.findall(log) if who == x)


MAX_CAUSE_LINES = 30
RAN_LINE = re.compile(r"^=== (.+): exit (\S+)$")      # run_targets' header of each target's output
SUMMARY_LINE = re.compile(r"\s*Test Summary:")
LOAD_ERROR = re.compile(r"\s*(?:ERROR: )*(?:LoadError|ParseError|ERROR:)")


def baseline_cause(log):
    """THE ONE EXTRACTOR of a red baseline's cause (audit D-0709 item 3): from the log `baseline` wrote (the targets'
    output, each under a `=== TARGET: exit RC` header), the lines that say WHY, at most MAX_CAUSE_LINES: the first target
    that did not exit 0 (the failing file), the first `Test Failed at` / `Error During Test at` block (its `Expression:`,
    `Evaluated:` and error lines, up to the stack trace or 20 lines), the `Test Summary` block (13 lines); for a target that did not load the
    first `ERROR:` / `LoadError` / `ParseError` line with two after it; else the last five non-blank lines. A log in
    which every target exited 0 gives [] (a green baseline prints nothing extra)."""
    lines = [ANSI.sub("", x).rstrip() for x in log.splitlines()]
    heads = [(i, m) for i, m in ((i, RAN_LINE.match(x)) for i, x in enumerate(lines)) if m]
    red = next(((i, m) for i, m in heads if m.group(2) != "0"), None)
    if red is None:
        return []
    start = red[0]
    end = next((i for i, _ in heads if i > start), len(lines))
    sec = lines[start + 1 : end]
    out = ["failing file: %s (exit %s)" % (red[1].group(1), red[1].group(2))]
    found = False
    for i, ln in enumerate(sec):
        if ANCHOR_TEST.match(ln):
            out.append(ln.strip())
            for x in sec[i + 1 : i + 21]:
                if ANCHOR_TEST.match(x) or x.strip().startswith("Stacktrace:") or not x.strip():
                    break
                out.append(x.rstrip())
            found = True
            break
    if not found:
        for i, ln in enumerate(sec):
            if LOAD_ERROR.match(ln):
                out += [x.rstrip() for x in sec[i : i + 3] if x.strip()]
                found = True
                break
    for i, ln in enumerate(sec):
        if SUMMARY_LINE.match(ln):
            out.append(ln.strip())
            for x in sec[i + 1 : i + 13]:
                if not x.strip():
                    break
                out.append(x.rstrip())
            found = True
            break
    if not found:
        out += [x.strip() for x in sec if x.strip()][-5:]
    return [x[:300] for x in out][:MAX_CAUSE_LINES]


def hang_verdict(m, cut):
    """(verdict, why) of a mutant whose target was cut (`cut`: the dict run_target appended to CUTS, or None).
    `expect="hang"` + `site` + the site in the evidence = "caught (hang)"; anything else is a blocking TIMEOUT."""
    kind = cut["kind"] if cut else "time"
    why = ("cut (%s): %s" % (kind, cut["reason"])) if cut else "cut"
    site = m.get("site") or ""
    if m.get("expect") != "hang":
        return "TIMEOUT (%s)" % kind, why
    shown = bool(site and cut and any(site in ln for ln in cut.get("evidence", [])))
    if shown:
        return "caught (hang)", "%s; site %r shown in the evidence" % (why, site)
    return "TIMEOUT (hang declared, site not shown)", "%s; %s" % (
        why, "site %r not in the last %d lines" % (site, EVIDENCE_LINES) if site else "no `site` declared")


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
    targets = runpy.run_path(argv[0]).get("TARGETS", [])
    if any(" " in t or "\n" in t for t in targets):
        sys.exit("mutate_ci: a target of TARGETS holds a blank")
    print("targets=" + " ".join(targets))
    return 0


def baseline(argv):
    limit, targets = int(argv[0]), argv[1:]
    if not targets:
        sys.exit("mutate_ci: no target")
    t0 = time.time()
    rc, log, _ = run_targets(targets, limit)
    write("baseline", {"name": "baseline", "exit": rc, "seconds": round(time.time() - t0)}, log)
    print("baseline exit", rc)
    if rc != 0:                       # the cause in the JOB LOG: the artifact needs a token to read (D-0709 item 3)
        print("\n".join(baseline_cause(log) or ["(no failing file in the baseline log)"]))
    return 0 if rc == 0 else 1


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
    del CUTS[:]
    rc, log, why = run_targets(targets, limit)
    declared = bool(m.get("equivalent"))
    cut = CUTS[0] if CUTS else None
    if rc == "noload":
        verdict = "NO VERDICT (does not load)"
    elif rc == "notest":
        verdict = "NO VERDICT (no failing test)"
    elif rc == 1:
        verdict = "EQUIVALENT REFUTED" if declared else "caught"
    elif rc == "hang":
        verdict, why = hang_verdict(m, cut)
    elif rc == 0:
        verdict = "EQUIVALENT (declared)" if declared else "SURVIVED"
    else:
        verdict = "INVALID"
    why = "; ".join(x for x in (why, noload_hint(m, verdict)) if x)
    record.update(verdict=verdict, exit=rc, seconds=round(time.time() - t0), first_failure=why,
                  precompile_seconds=LAST_PRECOMPILE["seconds"])     # `seconds` includes it: the limit does not
    if cut:
        record["cut"] = cut
    if verdict in ("EQUIVALENT (declared)", "SURVIVED") and not os.environ.get("MUTATE_CI_NO_REACH"):
        # a survivor: does any target execute the mutated line at all? (audit D-0849). The pass is a SECOND run of the targets: a slow
        # survivor must not push the job past its timeout (a cancelled job uploads nothing, so the verdict would be lost too: TB5-E9 on
        # 2026-11-17, normal run ~48 min, cancelled at the 120-minute timeout): the pass runs only when twice the normal run fits in
        # MUTATE_CI_REACH_BUDGET (default 5400 s), else it is recorded as skipped.
        normal = round(time.time() - t0)
        if normal * 2 > REACH_BUDGET:
            record.update(reach=None, reach_seconds=0,
                          reach_note="skipped: the normal run took %d s, a second run would pass the job budget of %d s" % (normal, REACH_BUDGET))
        else:
            t1 = time.time()
            record.update(reach=reach_pass(m, src, name, targets, limit), reach_seconds=round(time.time() - t1))
    write(name, record, log)
    print(name, verdict, "—", why or "-")
    return 0                                            # the verdict is data: `collect` judges


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
    cause = []
    if not base_ok:                   # once, from the ONE extractor; the NO VERDICT rows below point at it
        lp = os.path.join(OUT, "baseline.log")
        if os.path.isfile(lp):
            with open(lp, errors="replace") as f:
                cause = baseline_cause(f.read())
        cause = cause or ["no baseline log: the Baseline job wrote no record%s" % (
            "" if base is None else " of its failing file (exit %s)" % base.get("exit"))]
    for m in mutants:
        name = m["id"].split()[0]
        r = read(name) or {"verdict": "NO VERDICT", "seconds": 0}
        v = r["verdict"]
        if v.startswith(BLOCKING) or not base_ok:
            blocked.append(name)
        what = m["id"][len(name):].strip()
        if m.get("equivalent"):
            what += " — declared equivalent, pending audit: " + m["equivalent"]
        shown = r.get("first_failure") or ""
        if cause and v.startswith("NO VERDICT"):
            shown = "baseline red, " + cause[0]
        if "reach" in r:                  # a survivor: does ANY target execute the mutated line? (audit D-0849)
            n = r["reach"]
            shown = (shown + " " if shown else "") + (
                "[reach skipped: slow target]" if n is None and str(r.get("reach_note", "")).startswith("skipped") else
                "[reach unknown]" if n is None else "[NOT REACHED by the targets]" if n == 0 else "[reached %d times]" % n)
        rows.append("| %s | %s | %s s | %s | %s |" % (name, v, r.get("seconds", 0), what.replace("|", "\\|"),
                                                   shown.replace("|", "\\|")))
    lines = ["## Mutation battery — %s" % path, "",
             "Baseline (unmutated targets): **%s**%s" % (
                 "green" if base_ok else "NOT GREEN — no verdict below counts",
                 "" if base is None else ", %s s" % base.get("seconds", 0)), ""] + (
        ["### Baseline cause", "", "~~~"] + [x.replace("~~~", "---") for x in cause] + ["~~~", ""] if cause else []
    ) + ["| mutant | verdict | time | what it breaks | first failing test line |",
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
    commands = {"plan": plan, "baseline": baseline, "one": one, "collect": collect, "annotate": annotate}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit("usage: mutate_ci.py plan|baseline|one|collect|annotate … (see the header)")
    if sys.argv[1] in ("baseline", "one"):      # the commands that start a Julia
        pin_julia()
    sys.exit(commands[sys.argv[1]](sys.argv[2:]))
