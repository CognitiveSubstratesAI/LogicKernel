# MISC-1 handoff (worktree ~/code/lk-misc1, branch wip/misc-1, base c1c104f4)

## Committed (src, 3 commits, julia never run; test_type_discipline.jl and warm.sh check NOT run)
- c14d94a1 UPSTREAM: pl-pro.c $notrace/1: `pl_notrace1_va` in src/pl-pro.jl, registered after `$restore_trace/2`. callProlog with
  PL_Q_CATCH_EXCEPTION|PL_Q_NODEBUG, ex = Ref(0); skiplevel, tracing saved/restored; the NODEBUG debugger switch (debugging off,
  setPrologRunMode!(NORMAL), restore) done inside the predicate because PL_open_query keeps no debugger state (DBG1). Named DIVERGES.
- 57f78dc9 UPSTREAM: pl-write.c $needs_quotes/1: `pl_needs_quotes1_va` in src/pl-write.jl, `PL_get_atom_ex` then `!unquoted_atom`.
- 365f4627 UPSTREAM: pl-proc.c $local_definitions/2 (`pl_local_definitions2_va`: `[main-N]` for a thread-local predicate with
  N>0 clauses, `[]` at 0, fail otherwise; one thread = named DIVERGES) and $addr2line/2 (`pl_addr2line2_va`: PL_get_size_ex then
  `NotPortedError{T}(mk_sym(T,:addr2line), "addr2line/2: the description of a C function address (debug build only)", "REFUSED")`).
  Both appended to `PL_predicates_from_proc` after current_predicate/1.

## Predicates
- WRITTEN: $notrace/1, $needs_quotes/1, $local_definitions/2, $addr2line/2 (refusal).
- SKIPPED: malloc_property/1 (DESIGN QUESTION 1). Pin probe: `predicate_property(system:malloc_property(_),defined)` -> no;
  `current_prolog_flag(malloc,X)` -> ptmalloc. pl-alloc.c registers it only in initTCMalloc (pl-alloc.c:1782), so the pin build
  (ptmalloc) leaves it undefined: `malloc_property(_)` raises existence_error(procedure, malloc_property/1). src/pl-alloc.jl has no
  PL_predicates_from_alloc table and is included BEFORE pl-fli.jl (foreign convention) so a registration there needs a new
  table in pl-ext.jl plus an include-order move. Recommendation: write nothing, keep row t14 (pins the existence_error on both sides).
  Option B: a Julia `malloc_property` over Base.gc_live_bytes etc., LK-ONLY, registered always (diverges from the pin).
- DESIGN QUESTION 2: pin `'$addr2line'(1,_)` FAILS (upstream doc: "fails silently if there is no support"); the brief's refusal
  makes the kernel throw NotPortedError. Recommendation: fail silently like the pin (then drop lk1, the owner row, and the refusal);
  done as briefed for now. Type checks match the pin: type_error(integer,a), domain_error(not_less_than_zero,-1).
- Also found (not mine): `$foreign_predicate_source/2` is registered next to `$addr2line` upstream; owner row says PR1.

## Uncommitted in the worktree (the dispatcher commits it; the cap hook stopped me before the commit)
- test/core_lang/test_misc1_swipl.pl (written, untracked): rows t0-t14 + LK-ONLY lk1. A python cleanup edit was BLOCKED before
  running, so apply these 7 text edits (assert each occurs once):
  1. `nt_goal(( X = 1 ; X = 2 )) :- var(X).` -> without ` :- var(X)` (same for the `member(X,[a,b]), !` and `Y = g(Z), Z = 2` goals)
  2. t14's comment: replace "which defines no malloc_property/1" wording with: `% pl-alloc.c registers malloc_property/1 under tcmalloc only (initTCMalloc); the pin's allocator is ptmalloc, so the call raises existence_error(procedure, malloc_property/1), which the kernel raises as well`
  3. header "(no .out line, the test pins the kernel's refusal)" -> "(its answer is the kernel's refusal, pinned in the .jl, with no line in the .out)"
  4. lk1 comment "(no description is available)" -> "(the description cannot be read)"
  5. t10 comment -> "% a static or a dynamic predicate, an undefined one, a term that is no head: the call fails"
  Wording: the commit hook refuses absence-claim phrases (the list is in the repo's CLAUDE.md hook section); state positively what the code does instead.
  DECISIONS (dispatcher, 2026-11-15, taking the writer's recommendations, both the faithful answer at the pin): (1) malloc_property/1: write nothing for it (the pin binary does not define it; row t14 pins the existence_error); the SCOPE absent list counted it as missing, which is a counting error to report to the audit. (2) `$addr2line(1,_)`: make it FAIL silently as the pin does: drop the NotPortedError refusal, the LK-ONLY row lk1 and the owner row (item 7 of the plan below is dropped); keep the type_error(integer) and domain_error(not_less_than_zero) checks.
- Pin probe of every row idea (run with `LC_ALL=C systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=0 -p TasksMax=64 ~/.local/bin/swipl -q`): needs_quotes: abc u, 'Abc' q, [] q, '' q, 'a b' q, + u, '{}' u, ',' q, '|' q, ; u, ! u, '[]' q; errors type_error(atom,1|"s"|f(x)), instantiation_error for a var; $notrace: throw(foo)->foo, var goal -> instantiation_error, 1 -> type_error(callable,1), member once -> a; debug flag true-false-true (true outside, false inside, true after); ntm:$notrace(ntp(X)) -> 7; $addr2line(a,_) type_error(integer,a), (-1,_) domain_error(not_less_than_zero,-1), (1,_) fails.

## Left to do (plan)
1. Apply the edits above; write test/core_lang/test_misc1_swipl.jl modelled on test_dwim_swipl.jl (copy enc, kernel_lines, DRIVER,
   swipl_lines; names regex `^(t\d+)\(R\) :-`; lk rows `^(lk\d+)\(R\) :-` run on the kernel only, expected `lk1 notported`;
   guards: 15 rows, .out has `ok` + 15 lines, `_count` of q and u in t0 both >= 10, t3 agreement (Q == W in every t3 answer), both sides one extractor).
2. Generate test_misc1_swipl.out: extract DRIVER from the .jl, write drv.pl in the scratchpad, run twice under the systemd-run scope
   above (variables on the shell line, LC_ALL=C, `~/.local/bin/swipl -q drv.pl`), cmp byte-identical, keep as .out. Python: no env copy.
3. Commit `TEST: MISC-1 rows` (3-6 line body incl. "test_type_discipline.jl and warm.sh check NOT run", Co-Authored-By line).
4. test/db/test_boot_image_swipl.jl line 158: `_BI_KERNEL_MISSING_FOREIGN = 322` -> 318 (four foreign `system` rows registered: $notrace/1,
   $needs_quotes/1, $local_definitions/2, $addr2line/2) and prepend "322 before MISC-1 registered ..." to the comment chain; this file is changed
   so it needs the 3 term types and `tools/pkgtest_way.sh` by the gate.
5. tools/mutants/MISC1.py (read tools/mutants/DICT.py lines 1-40 for the format): ids unique, "aimed by <rows>", never KILL, each `old` once
   (python3 -I via runpy), no `equivalent=`; TARGETS = core_lang/test_misc1_swipl.jl (+ test_bootpred3_swipl.jl for $notrace/2-neighbours is not
   needed; add test_dwim? no). Candidates: `!unquoted_atom(a)` -> `unquoted_atom(a)`; `PL_Q_CATCH_EXCEPTION | PL_Q_NODEBUG` -> `PL_Q_CATCH_EXCEPTION`;
   drop the `ld.debugstatus_debugging = debugSave` restore; drop `ld.debugstatus_tracing = traceSave`; `if cc != 0` -> `if cc != 1`;
   `(def.flags & P_THREAD_LOCAL) == 0 && return FFALSE` removed; `PL_put_atom(ld, tit, mk_sym(T, :main))` -> `:other`; `!rval && ex[] != 0` -> `rval && ex[] != 0`.
6. Cost lines `core_lang/test_misc1_swipl.jl<TAB>estimate` in test/pkgtest_costs.tsv and test/unit_costs.tsv (path order, copied from the
   test_dwim_swipl.jl neighbour; say so in the commit).
7. Owner row in docs/r2_owners.tsv for the refusal, key as the generator prints it: `refusal:src/pl-proc.jl::pl_addr2line2_va::` +
   the first 60 characters of the squeezed what string ("addr2line/2: the description of a C function address (debug build only)"
   -> "addr2line/2: the description of a C function address (debug build "), TAB `REFUSED` TAB note "debug build only"; insert in the refusal block (keys sorted by file).
   Verify the key with tools/r2_status.jl logic (`r2_refusal_rows`: `refusal:$file::$fn::` * first(what, 60), file = `src/pl-proc.jl`).
8. Manifest entries in test/static_analysis_manifest.jl (small window around a neighbour entry) for the new functions; commit `TEST: MISC-1 mutants, cost lines and owner rows`.
9. Gate order after: fmt, check (with Pkg.test way), the three files on three term types, test_type_discipline.jl, mutants/MISC-1 push, branch-gate, crash-term grep, gate/misc-1 + mutants/MISC-1 at one SHA. Dispatcher does these (julia not run by this agent).

## Daemon
No daemon used or started by this agent; lanes.conf untouched.
