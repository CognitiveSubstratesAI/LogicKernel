# ORIGINAL: group F (reader/writer)'s mutant list — no swipl-devel counterpart.
# tools/mutants/GroupFrw.py — the mutation battery of group F's reader and writer file group (audit D-0123:
# the four refusals ported — callPortray, portray_goal, cycles(true), the cyclic write; wip/groupf-rw,
# 2026-10-23), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format
# is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent`
# (a mutant that must SURVIVE, with the code reason) and `targets`.
#
# Each mutant names the new test that kills it (the comment above it): a testset of the target file.
TARGETS = [
    "test/core_text/test_write_family_swipl.jl",
    "test/core_text/test_write_swipl.jl",
    "test/core_text/test_canonical_readatom_swipl.jl",
    "test/core_lang/test_numbervars_cells.jl",
]
W = "src/pl-write.jl"
R = "src/pl-read.jl"
PR = "src/pl-prims.jl"
WAM = "src/pl-wam.jl"
WF = ["test/core_text/test_write_family_swipl.jl"]
WFS = ["test/core_text/test_write_family_swipl.jl", "test/core_text/test_write_swipl.jl"]
CR = ["test/core_text/test_canonical_readatom_swipl.jl"]
CRNV = ["test/core_text/test_canonical_readatom_swipl.jl", "test/core_lang/test_numbervars_cells.jl"]
MUTANTS = [
    # ── item 3: callPortray (pl-write.c:1955) ──
    # killed by test_write_family_swipl.jl "print/1 with a user portray/1, as swipl" (ours[1] is
    # f(bar,…)) and test_write_swipl.jl "user:portray/1 defined: print/1's flags call it" (ours[2] == "")
    dict(id="GF1 a defined portray/1 is never called", file=W, targets=WFS,
         old='''        _impl_any_defined(pred.definition) || return 0''',
         new='''        return 0'''),
    # killed by "print/1 with a user portray/1, as swipl": print(user_error, g(foo)) writes portray's
    # `bar` on user_output (the current output), not on the write's stream
    dict(id="GF2 portray/1 writes to the current output, not the write's stream", file=W, targets=WF,
         old='''    ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = options.out    # Scurout = options->out''',
         new='''    nothing    # Scurout = options->out'''),
    # killed by "print/1 with a user portray/1, as swipl": ours[7][3] == "ex:oops" (an uncaught raise
    # in portray/1 is the error, not a fall-back write with the exception dropped)
    dict(id="GF3 a raise in portray/1 is a failure, not an error", file=W, targets=WF,
         old='''        rval = -1''',
         new='''        rval = 0'''),
    # ── item 4: portray_goal (pl-write.c:1903 put_write_options, 2967 pl_write_term3) ──
    # killed by "write_term's portray_goal option, as swipl": the goal sees the caller's
    # priority(999) kept in place and a second one appended, where swipl moves it to the end
    dict(id="GF4 put_write_options keeps the caller's priority/1", file=W, targets=WF,
         old='''        if !PL_is_functor(ld, head, mk_sym(T, :priority), 1)''',
         new='''        if true'''),
    # killed by "write_term's portray_goal option, as swipl": ours[4][1] holds priority(999) and
    # priority(499), the subterms' priorities (unbound under the mutant)
    dict(id="GF5 the priority option is not bound to the subterm's priority", file=W, targets=WF,
         old='''        PL_unify_integer(ld, options.prec_opt, prec)''',
         new='''        true'''),
    # killed by "write_term's portray_goal option, as swipl": ours[1][1] == "f(px,y)" (without
    # portray(true) the goal is never called)
    dict(id="GF6 portray_goal does not imply portray(true)", file=W, targets=WF,
         old='''            portray = true''',
         new='''            portray = portray'''),
    # ── item 1: cycles(true), instantiate_template (pl-read.c:6513) ──
    # killed by test_canonical_readatom_swipl.jl "read_term_from_atom/3 with cycles(true), as swipl":
    # the five cyclic shapes' checks fail (all(r -> r[3] == "true", ours[1:5]))
    dict(id="GF7 cycles(true) ignored (the old silent misread)", file=R, targets=CR,
         old='''    if rd.cycles && PL_is_functor(ld, r0, mk_sym(T, Symbol("@")), 2)  # FUNCTOR_at_sign2''',
         new='''    if false && PL_is_functor(ld, r0, mk_sym(T, Symbol("@")), 2)  # FUNCTOR_at_sign2'''),
    # killed by "read_term_from_atom/3 with cycles(true), as swipl": `T = f(A), A == T` fails when
    # X = f(X) is never unified
    dict(id="GF8 a substitution is not unified", file=R, targets=CR,
         old='''            PL_unify(ld, var, value) || return false''',
         new='''            true || return false'''),
    # killed by "read_term_from_atom/3 with cycles(true), as swipl": ours[13] is
    # type_error(list, a) ("invalid template") where the mutant reads `@(X,a)` as X
    dict(id="GF9 a substitutions term that is no list is not an error", file=R, targets=CR,
         old='''    if !PL_is_list(ld, substitutions)''',
         new='''    if false'''),
    # ── item 2: the cyclic write (pl-prims.c:1254-1488, pl-wam.c:1507, pl-write.c:2684) ──
    # killed by test_canonical_readatom_swipl.jl "writing a cyclic term, as swipl": a compound met
    # three times (`X = f(X), Y = g(X, X)`) is listed twice and its functor cell overwritten
    dict(id="GF10 scan_shared does not mark a shared compound FIRST", file=PR, targets=CR,
         old='''                    ld.gstack[q] = d | FIRST_MASK           # set_first(d)''',
         new='''                    ld.gstack[q] = d           # set_first(d)'''),
    # killed by test_numbervars_cells.jl "a cyclic term: write_canonical writes it factorised"
    # (ld.gstack[c + 1] == cyc) and "writing a cyclic term, as swipl" (the last goal: X is still
    # f(X) after the write — `@(…) ok`)
    dict(id="GF11 TrailAssignment! trails nothing: the term is not restored", file=WAM, targets=CRNV,
         old='''    if p <= ld.mark_bar''',
         new='''    if false'''),
    # killed by "writing a cyclic term, as swipl": `h(g(a),g(a),S_1)` — an acyclic shared subterm is
    # put back in place, where the mutant leaves a variable for it
    dict(id="GF12 an acyclic substitution is not put back", file=W, targets=CR,
         old='''            PL_unify(ld, var, value) || return false''',
         new='''            true || return false'''),
]
