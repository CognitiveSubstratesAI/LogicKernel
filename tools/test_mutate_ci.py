#!/usr/bin/env python3
# ORIGINAL: no swipl-devel counterpart — the test of the CAPTURE path of a cut in tools/mutate_ci.py (audit D-0997 (1)).
# Run as `python3 -I tools/test_mutate_ci.py`. Pure python, no Julia: a synthetic SIGQUIT dump of about 300 lines (the loop
# frame near the top, the toplevel include chain last, the shape measured at 286-302 lines) is written to a file and read
# through the REAL `tail_lines(f, EVIDENCE_LINES)`, the call `run_target` makes for a cut's evidence; the record then goes
# through the REAL `hang_verdict`. Not re-implemented here: the tail and the verdict are mutate_ci's own functions.
import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True     # no tools/__pycache__: an untracked file voids the evidence marker (a stale .pyc would also hide an edit of the constant)
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mutate_ci  # noqa: E402

SITE = "_check_ref_chains!"
TOPLEVEL = ["include(mapexpr::Function, mod::Module, _path::String) at ./Base.jl:306",
            "exec_options(opts::Base.JLOptions) at ./client.jl:296",
            "_start() at ./client.jl:531",
            "main(argv::Vector{String}) at ./client.jl:600"]


def dump(with_site, total=300):
    """A fake SIGQUIT dump: preamble, the loop frame at about line 14 (when with_site), ~270 other frames, the toplevel chain last."""
    lines = ["WARNING: sample line %d" % i for i in range(1, 13)]
    lines.append("cmd: julia --project=. test/runtests.jl 1 running 1 of 1")
    lines.append("_check_ref_chains! at src/pl-gc.jl:852" if with_site else "_other_frame! at src/pl-other.jl:852")
    k = 0
    while len(lines) < total - len(TOPLEVEL):
        k += 1
        lines.append("other_frame_%d at src/pl-misc.jl:%d" % (k, k))
    return lines + TOPLEVEL


def capture(lines, n):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "out.log")
        with open(p, "w") as f:
            f.write("\n".join(lines) + "\n")
        with open(p, "rb") as f:
            return mutate_ci.tail_lines(f, n)


def cut_of(lines, kind="time"):
    return dict(kind=kind, reason="limit 600 s", evidence=capture(lines, mutate_ci.EVIDENCE_LINES))


class CapturePath(unittest.TestCase):
    def test_site_at_line_14_is_inside_the_window(self):
        out = dump(True)
        self.assertGreaterEqual(len(out), 295)
        self.assertEqual(out.index("_check_ref_chains! at src/pl-gc.jl:852"), 13)    # line 14
        self.assertEqual(out[-1].split("(")[0], "main")
        self.assertTrue(any(SITE in ln for ln in cut_of(out)["evidence"]))

    def test_declared_hang_with_site_is_caught(self):
        v, _ = mutate_ci.hang_verdict({"expect": "hang", "site": SITE}, cut_of(dump(True)))
        self.assertEqual(v, "caught (hang)")

    def test_declared_hang_site_absent_is_blocking(self):
        v, _ = mutate_ci.hang_verdict({"expect": "hang", "site": SITE}, cut_of(dump(False)))
        self.assertEqual(v, "TIMEOUT (hang declared, site not shown)")

    def test_no_expect_gives_the_kind_of_the_cut(self):
        v, _ = mutate_ci.hang_verdict({"site": SITE}, cut_of(dump(True)))
        self.assertEqual(v, "TIMEOUT (time)")
        v, _ = mutate_ci.hang_verdict({}, cut_of(dump(True), kind="memory"))
        self.assertEqual(v, "TIMEOUT (memory)")

    def test_negative_control_the_old_window_loses_the_site(self):
        # The window is what matters: the SAME output through tail_lines(out, 60) does not hold the site, so the
        # test above (test_declared_hang_with_site_is_caught) FAILS with EVIDENCE_LINES = 60 (checked by hand, D-0997).
        old = capture(dump(True), 60)
        self.assertEqual(len(old), 60)
        self.assertFalse(any(SITE in ln for ln in old))
        v, _ = mutate_ci.hang_verdict({"expect": "hang", "site": SITE}, dict(kind="time", reason="r", evidence=old))
        self.assertEqual(v, "TIMEOUT (hang declared, site not shown)")

    def test_window_holds_a_whole_dump(self):
        self.assertGreaterEqual(mutate_ci.EVIDENCE_LINES, 302)


if __name__ == "__main__":
    unittest.main(verbosity=1)
