# Generator of the pins of test/core_lang/test_top1_prompt_swipl.jl: reads the cases (_TP_CASES) from the test file by the ONE extractor
# below, drives swipl 10.1.19 on a PSEUDO-TERMINAL (Sread_terminal writes the prompt only for a tty input, pl-os.c:2171-2185), chunk by chunk,
# twice (every swipl call under timeout 20), requires the two transcripts to be byte-identical, writes evidence/TOP1/top1_rows.out and puts the
# lines between the PINS-BEGIN/PINS-END markers of the test file.
# A case is a list of steps (";;"-separated); a step is `p1|p2|chunk|after` : the prompt1/1 atom ("-" = not called), the prompt/2 atom ("-" =
# not called), the line the terminal delivers (ends in \n), the text the goal writes after reading it. "\n" is a newline in every field.
# The transcript of a case: n+1 segments (the output before the first chunk; the output after each chunk), each as its character codes.
# Usage (from the worktree root): python3 -I evidence/TOP1/gen_top1_rows.py
import os, pty, re, select, subprocess, sys, tempfile, termios, time
T = "test/core_lang/test_top1_prompt_swipl.jl"
DRIVER = r"""
mark(D, N) :- atomic_list_concat([D, '/m', N], F), open(F, write, S), close(S).
run(D, T) :- mark(D, 0), run(D, 1, T).
run(_, _, []).
run(D, N, [s(A,B,C)|T]) :-
    ( A == '-' -> true ; prompt1(A) ),
    ( B == '-' -> true ; prompt(_, B) ),
    read_line_to_string(user_input, _),
    write(C), flush_output,
    mark(D, N), N1 is N+1,
    run(D, N1, T).
"""
def decode(f): return f.replace("\\n", "\n")
def parse(spec): return [[decode(x) for x in st.split("|")] for st in spec.split(";;")]
def cases_of(src):
    # JuliaFormatter may split an entry over lines
    return re.findall(r'^    \(\s*"(tp\d+)",\s*raw"(.*?)"\s*\),?$', src, re.M)
def q(a): return "'" + a.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n") + "'"
def goal_of(steps, md):
    return "run(" + q(md) + ",[" + ",".join("s(%s,%s,%s)" % tuple(q(x) if k != 3 else q(x) for k, x in enumerate((p1, p2, af))) for p1, p2, ch, af in steps) + "])"
def drain(fd, t):
    out = b""
    while True:
        r, _, _ = select.select([fd], [], [], t)
        if not r: break
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d
    return out.decode().replace("\r\n", "\n")
def wait_mark(fd, md, n, limit=15.0):
    # the driver's marker file m<n> says swipl got that far; select() on the pty is the wait (no sleep)
    f = os.path.join(md, "m%d" % n); t = time.time(); out = b""
    while not os.path.exists(f):
        assert time.time() - t < limit, "swipl did not reach marker %d" % n
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: out += os.read(fd, 4096)
            except OSError: break
    return out.decode().replace("\r\n", "\n")
def session(drv, steps):
    md = tempfile.mkdtemp(dir=os.path.dirname(drv))
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("timeout", ["timeout", "20", "swipl", "-q", "-g", goal_of(steps, md), "-t", "halt", drv])
    attr = termios.tcgetattr(fd); attr[3] &= ~termios.ECHO; termios.tcsetattr(fd, termios.TCSANOW, attr)
    segs = [wait_mark(fd, md, 0) + drain(fd, 0.5)]
    for k, (p1, p2, ch, af) in enumerate(steps):
        os.write(fd, ch.encode())
        segs.append(wait_mark(fd, md, k + 1) + drain(fd, 0.5))
    try: os.close(fd)
    except OSError: pass
    os.waitpid(pid, 0)
    return segs
def enc(segs): return ";".join(",".join(str(ord(c)) for c in s) for s in segs)
if __name__ == "__main__":
    src = open(T).read()
    cases = cases_of(src)
    assert len(cases) >= 12, len(cases)
    with tempfile.TemporaryDirectory() as d:
        drv = os.path.join(d, "drv.pl"); open(drv, "w").write(DRIVER)
        def run():
            return ["%s %s" % (i, enc(session(drv, parse(spec)))) for i, spec in cases]
        a, b = run(), run()
    assert a == b, "two swipl runs differ"
    # non-vacuity: every case has n+1 segments and some prompt text was written in the whole set
    for (i, spec), l in zip(cases, a):
        assert len(l.split(" ", 1)[1].split(";")) == len(parse(spec)) + 1, i
    assert any(len(l.split(" ", 1)[1].replace(";", "")) > 0 for l in a)
    open("evidence/TOP1/top1_rows.out", "w").write("\n".join(a) + "\n")
    pins = "".join('    "%s"%s\n' % (l, "," if k < len(a) - 1 else "") for k, l in enumerate(a))
    s2 = re.sub(r"# PINS-BEGIN\n.*?# PINS-END\n", lambda m: "# PINS-BEGIN\n" + pins + "# PINS-END\n", src, flags=re.S)
    open(T, "w").write(s2)
    print("pins:", len(a))
