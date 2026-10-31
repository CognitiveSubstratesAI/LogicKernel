# FUZZGEN — handoff (audit D-0267; agent 2026-10-31)

STEP: extend the fuzz generator with B_ARGVAR-class shapes. Tools only: no engine code, no mutants.
WORKTREE ~/code/lk-lb2, branch wip/fuzzgen off origin/main c390eac. Gate branch: gate/fuzzgen ONLY.

## State (2026-10-31, continuation agent; lk-lb2 daemon up)
GREEN so far on the lk-lb2 daemon: `warm.sh file test/test_fuzz_shapes.jl` 87/87 (a non-term-generic file runs ONCE, no
impl loop), `test_type_discipline.jl` 33/33, `fmt` (2 files rewritten), `check` PASS (its Pkg.test-way run: peak 279 MiB).
The previous agent's code ran correctly the first time. MEASURED over seeds 1000:1199 (1942 shape cases = 0.243 of 8000,
per seed 3..17, every tag ok, `ok` is a Bool): shapes dn 1242, inter 1290, nd 1352 (both terms); families 146 (eq) ..
214 (copy_term); ctx goal 1171, head 771; attr before 167, mid 167, head 231, none 1377. Thresholds unchanged (MIN 30,
fraction 0.18..0.32); the measured numbers are in the test's comment.

MUTATION PROOF of the shape-count guard (by hand, on copies in the agent's scratch dir, run in the daemon; CONTROL = the
unmutated copy passes): A = family "eq" dropped from AV_FAMILIES -> KILLED (3 fails: the eq count < MIN, pred set
equality, Set(AV_FAMILIES)==Set(_FS_PREDS)); B = both shapes of every case fixed to "nd" -> KILLED (3 fails: dn and inter
counts, shape set equality); C = attr mode "mid" never drawn -> KILLED (2 fails: mid count, attr set equality).
Both sides non-empty through ONE extractor (fz_tags) is kept: the counts and the doctored texts go through it.

## Files
- tools/fuzz_gen.jl (NEW, module FuzzGen, needs Random only): the old generator moved verbatim out of tools/fuzz.jl,
  `program(seed, ncases, pct=25)` now draws every generic goal from Xoshiro(seed) exactly as before, and replaces
  `pct` percent of the cases by SHAPE CASES drawn from a second stream Xoshiro(seed xor SHAPE_SALT). pct=0 = the old
  program byte for byte. Shape cases end with a tag comment `%fz ctx=… shape=… shape2=… pred=… attr=… ord=… terms=T1;T2`.
  Also the extractor `fz_tags(text)` (re-derives each term's class with a small parser `av_classes`, checks the terms
  are in the goal or the `fzhN` head, the family's predicate is in the goal, put_attr present iff attr != none).
- tools/fuzz.jl: the generator block replaced by `include("fuzz_gen.jl")`, `using .FuzzGen: program`; 5th arg
  SHAPE_PCT (default 25). The lines the FuzzCi mutants (FZ1-FZ4) rewrite are untouched.
- test/test_fuzz_shapes.jl (NEW, non-term-generic): counts over seeds 1000:1199 per shape (both terms), family,
  ctx, attr mode (each >= 30, hard-coded expected names, set equality), all tags `ok`, fraction 0.18..0.32;
  av_classes on written-out terms; doctored texts turn a good tag bad (6 doctorings); pct=0 has no tags and the
  untagged lines of the default program are pct=0 lines; seed 300945's t16 line is still in the pct=0 program.

## SHAPES added (term level / contexts)
- term: nd (nested occurrence first, direct later, same outer compound), dn (reverse), inter (v1 nd + v2 dn in one
  outer term, 2-3 variables); outer = f/g/h/k of any arity or a list; nested wrapper k(V), g(V,a), g(a,V), [V],
  h(a,V,b), k(g(V,c)); fillers between.
- contexts: goal body (inline terms) and clause HEAD `fzhN(T1,T2).` called with unbound args (H_VAR write mode).
- families: compare/3, compare of two variables of one term (compare_vars), msort/2, sort/4 (@< @> @=< @>=),
  @< / @> chain, ==, copy_term/2, term_variables/2, bagof (free variables, Q4 shape), setof with ^.
- attributed variables: put_attr(V, fz, 1) on a variable of the terms BEFORE they are built (attr=before), after
  (attr=mid: T1, T2 built first), after the head call (attr=head). Not with bagof/setof (their witness unification
  would call a hook the program does not define).

## Gates run (2026-10-31)
- DONE green: warm.sh file test_fuzz_shapes.jl (87/87) and test_type_discipline.jl (33/33); fmt; check (incl. the Pkg.test-way
  run, 279 MiB); tools/test_fuzz.sh 7/7 (the new generator at the default 25 %, through the real kernel and swipl on 2 seeds x 10
  cases); mutation proof above; branch-gate PASS 937 s (fuzz_shapes, gate_split, lint_globals, port_check, type_discipline);
  term grep (D-0164) over the diff and the files: nothing.
- NOT RUN LOCALLY (cold-start hook; the CI Fuzz run on fuzz-ci-test/fuzzgen replaces it): `julia --project=. tools/fuzz.jl 300945 1` and the 300-seed real run: the cold-start hook blocks the bare julia
  line, and an in-daemon replacement was refused by the permission classifier. The dispatcher decides: push a
  `fuzz-ci-test/<name>` branch at the gate SHA (fuzz.yml runs on it; seeds 5000, 300) or a workflow_dispatch of fuzz.yml on
  gate/fuzzgen with first_seed 300945 / count 300.

COMMENT FIX: the moved comment on kind 19 (a stale claim about retract) was deleted outright (dispatcher decision); fmt, check and branch-gate re-run after it.
