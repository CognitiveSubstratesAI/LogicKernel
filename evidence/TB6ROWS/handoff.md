# TB6-ROWS handoff (agent 1 hit the 150k cap before writing the test file; NOTHING committed on wip/tb6rows yet)

Worktree: ~/code/lk-tb6rows, branch wip/tb6rows = wip/tb6 tip 2e2617c2 (not pushed). No Julia ran. swipl 10.1.20 only.
Scratch (persists, outside the repo): ~/code/lk-tb6rows.scratch/gen/ = groups.py (CHAIN), groups2.py (REEVAL SINGLE FALSECOUNT ABOLISH EXPAND),
groups3.py (DYNERR DYNOK INCRPROP), run.py (runs a group twice through swipl with driver.pl = the TB4-rows `enc` driver, prints the pin lines,
"IDENTICAL" when both runs match), driver.pl. Use: `cd gen; python3 -I run.py groups2 EXPAND`. Also ~/code/lk-tb6rows.pltab.c, .tabling.pl,
.pltrie.c, .idgset.c = `git show 18168e62:<file>` copies of pl-tabling.c, boot/tabling.pl, pl-trie.c, pl-idgset.c; ~/code/lk-tb6rows.scratch/TB3.py.

## Style to copy (read once, 200 lines)
`git -C ~/code/lk-tbland2 show gate/tab1c-r4c:test/core_lang/test_tabling_tb4rows_swipl.jl`: `_TR_enc` (Julia encoder), `_TR_DRIVER` (enc driver),
`_TR_swipl_lines`, `_TR_text` (appends `t_<id>(R) :- catch((Goal), error(SsuE,_), R = raised(SsuE))`), `_TR_load`, `_TR_ask`, `_TR_GROUPS` with
(key,label,program,cases,pins), one fresh database per group, the not-vacuous testset and the live-swipl testset. New file
test/core_lang/test_tabling_tb6rows_swipl.jl: copy these with prefix `_T6_` (test files cannot import each other: a duplicate by necessity).
There is NO tb3rows file in gate/tab1c-r4c; the rows file there are tb4rows/tb4rows2. The existing TB6 file test_tabling_idg_swipl.jl (wip/tb6, rows
idg01-07 differential, idg10-15 white-box) uses a `~q` driver; it stays as is.

## Pinned facts (swipl 10.1.20, two identical runs each; the pin lines are what run.py prints; PRE = prelude of groups.py)
PRE: tm_yn/2, tp(G,T) = '$tbl_existing_variant_table'(0,user:G,T,_,_), ts(G,S) status or none, fcn(G,F) falsecount or none, dirs(G,Dir,L).
Observers that exist at the pin (verified by `git show 18168e62:` greps): '$idg_edge'/3, '$idg_false_edge'/3, '$idg_falsecount'/2, '$idg_set_falsecount'/2,
'$idg_forced'/1, '$idg_thread_summary'/3 (nodes, edges), '$idg_thread_space'/2 (bytes), '$idg_predicate_edges'/3, '$tbl_reeval_wait'/2, '$trie_property'/2
(keys incl. idg_affected_count, idg_dependent_count, idg_size, invalidated, reevaluated, compiled_size, value_count), abolish_all_tables/0,
abolish_module_tables/1, abolish_table_subgoals/1, abolish_nonincremental_tables/0.
Decoded results (the enc lines are in run.py output; regenerate):
- CHAIN (cq over cp over dynamic cd, all incremental): c01 [1]; c02 `'$idg_edge'(Tcp, Dir, D)` Dir UNBOUND = [affected-complete, dependent-dynamic]
  (KILLS TB6-Q5); c03 (cq aff [], dep [complete]; cp aff [complete], dep [dynamic]; cd aff [complete], dep []); c04 summary nodes 3, edges 2,
  space 752 = 512 (registry block 64*8) + 3*80 (KILLS TB6-C4: kernel SIZEOF_IDG_NODE = 80 = swipl's idg_size); c05 after assertz(cd(2)): falsecounts cd=1 cp=1 cq=1,
  statuses cd dynamic, cp invalid, cq invalid; c06 `$idg_false_edge` of cq [invalid], of cp [dynamic]; c07 re-call cq [1,2], falsecounts 0 0, complete;
  c08 retract(cd(1)) then cq [2], fc 0, complete; c09 summary 3-2-752.
- REEVAL (rt over rd(1),rd(2)): f01 [1,2] value_count 2; f02 assertz(rd(3)): fc 1, invalid; re-call [1,2,3], value_count 3, fc 0, complete (KILLS TB3-F4: with the
  IDG_DELETED flag not cleared in tbl_add_answer_found, the re-added answers 1,2 are deleted at reeval_complete); f03 retract(rd(2)): [1,3], 2; f04 summary 2 nodes 1 edge, '$tbl_reeval_wait' complete; f05 [1,3].
- SINGLE (s1 one answer incr, s2 two answers incr, s3 one answer NON-incremental): `$trie_property(T, compiled_size(_))` after two calls:
  s01 [1] [1] no; s02 [1,2] [1,2] yes; s03 [1] [1] yes; s04 (assertz(sd1(9)): two answers) yes. KILLS TB3-T2 and TB3-C2 (a single-answer incremental table
  takes the trie symbol, no compiled clause: pl-tabling.c:6270-6279, :12313-12314). KERNEL: `$trie_property(compiled_size)` always fails before TR4
  (pl-trie.jl:3085, "no clause before TR4"), so s02 s03 s04 are `@test_broken` with owner TR4 (compile_trie, pl-trie.c:4462-5190, compiled_size :4301-4310); s01 is a plain
  @test (passes today; a mutant that compiles it throws NotPorted before TR4, and shows compiled_size after).
- FALSECOUNT: p01 after a call, `'$idg_set_falsecount'(T, 4294967296)` raised(representation_error(falsecount)) (KILLS TB6-P14); p02 4294967295 accepted (fc 4294967295, status
  invalid), back to 0 complete; p03 -1 raised(domain_error(not_less_than_zero,-1)); p04 unbound raised(instantiation_error); p05 `a` raised(type_error(integer,a));
  p06 4294967297 raised(representation_error(falsecount)); p07 18446744073709551616 raised(representation_error(size_t)); p08 fc 0.
- ABOLISH (ap over dynamic ad, aq over ap, an = non-incremental table; summ = r(N,E,Bytes); alls = r(Sad,Sap,Saq,San)): a01 [1] [1,2] r(3,2,752) r(dynamic,complete,complete,complete);
  a02 abolish_all_tables r(0,0,0)... summary r(0,0,0) all none (NOTE bytes 0? the pin says i0,i0,i0 for a02 and i512 for a04: re-run to read exactly); a03 re-call aq: [1] r(3,2,752) r(dynamic,complete,complete,none);
  a04 abolish_module_tables(user) r(0,0,512) all none; a05 (re-call, abolish_table_subgoals(ap(_))): aq stays, ad and ap gone: r(1,0,592) r(none,none,complete,complete);
  a06 abolish_nonincremental_tables: an goes, aq stays; a07 abolish_module_tables(nosuchmodule) no change; a08 abolish_table_subgoals(aq(_)) r(0,0,512) all none.
  NEEDS TB5 ('$tbl_destroy_table', '$tbl_abolish_local_tables'): check whether wip/tb6's stack has them (`grep -n 'PL_extension("\$tbl_destroy_table' src/*.jl` in the stack tree;
  I had just started that check); if not, this group is `@test_broken` owner TB5 (the C builtin `$tbl_destroy_table`, pl-tabling.c) and TB6 for the IDG half.
- EXPAND (KILLS TB6-S6): six incremental tables t1..t6 over one dynamic xd (one `:- table tN/1 as incremental.` per line; a comma list loses `as incremental`).
  summ = r(Nodes,Edges) ONLY (bytes depend on malloc reuse of the freed node in swipl: x03 gave 968 not 1000, the same pointer revives the dead slot; edge counts are the same either way).
  x01 (t1..t4 called) r(r(5,4),4); x02 abolish_table_subgoals(t3(_)) r(r(4,3),3); x03 call t5 r(r(5,4),4); x04 call t6 r(r(6,5),5); x05 assertz(xd(2)) fc t1=1 t5=1, t3 none.
  Kernel: after the dead slot, t5 grows the block with dead carried (nb.dead = b.dead); the mutant gives edges 5 at x03. Re-run `python3 -I run.py groups2 EXPAND` and keep the lines.
  CAVEAT for the kernel: x03's growth only happens in the kernel; to be sure the pin is not malloc-dependent I compared: both swipl paths give 4 edges.
- DYNERR / DYNOK (KILL TB6-V5): table_space tuned in a FRESH process: limit 1508 raises resource_error(private_table_space) at the dynamic-call edge (d's node exists, p's table gone):
  v01 raised(resource_error(private_table_space)), v02 r(1,0,none,dynamic), v03 (limit 1e9, re-call) r([1],2,1,complete,dynamic); DYNOK limit 1516: v01 [1], v02 r(2,1,complete,dynamic), v03 same.
  Exact table_space parity of the kernel pool with swipl is assumed (TB0 rows pin it); a kernel mismatch shows as a failing pair, not a defect of the row. Scan used: fresh `swipl` per limit 1000..2500, window 1508|1516.
- INCRPROP: i01 `assertz(wb_plain(1))` then predicate_property incremental no, dynamic yes (r(no,yes)); i02 id incr yes dyn yes, plain incr no dyn yes, ip incr yes.
  V6 (KILLS TB6-V6): swipl CANNOT answer: PL_CREATE_INCREMENTAL reaches assert_term only through C `PL_assert` (pl-comp.c:9241, :4915-4917; assertz/asserta/assert pass 0: :5078 :5086 :5107 :5121).
  White-box Julia row: `LK.assert_term!(gd, ld, t, 0, LK.CL_END, nothing, nothing, LK.PL_CREATE_INCREMENTAL)` on a new `wb_inc(1)` (build t with the helpers of test_assert_cells.jl:~100),
  then ask `inc_prop(wb_inc(_))` and `dyn_prop(wb_inc(_))`: hand-written expectation yes, yes, with the C reference in a comment; control: the same call with flags 0 on `wb_plain2`: incremental no;
  the same call with the flag on the ALREADY DEFINED `wb_plain` (i01): stays no (`flags && !isDefinedProcedure`, pl-comp.c:4915).
- TB3-C4 note: TB6-C4 is killed by c04/c09 (space 752) and DYNERR.

## Mutants and rows (what to write into tools/mutants/TB6R.py or `kills_rows` notes; the format of TB6.py: dict(id, file, old, new, targets); copy the `old/new` from TB6.py for TB6-S6 C4 Q5 P14 V5 V6 and from TB3.py for TB3-F4/T2/C2; targets = [the new file] + the files of TB6.py's TARGETS)
TB6-Q5 -> CHAIN c02; TB6-C4 -> CHAIN c04/c09; TB6-S6 -> EXPAND x03; TB6-P14 -> FALSECOUNT p01 p06; TB6-V5 -> DYNERR v01 v02; TB6-V6 -> INCRPROP white-box;
TB3-F4 -> REEVAL f02; TB3-T2 and TB3-C2 -> SINGLE s01 (kills only with TR4 or by a NotPorted throw), partner s02 (broken, owner TR4).
Remaining DEFERRED-by-TB6-ROWS ids of TB6.py: only those six (S6 C4 Q5 P14 V5 V6); the others are owner TB2/TB3/TB4/TB7/TH1.

## GAPS found (report these)
1. wip/tb6 does NOT implement the `invalidated`, `reevaluated`, `idg_affected_count`, `idg_dependent_count`, `idg_size` keys of `'$trie_property'/2` (pl-trie.c:4326-4345):
   pl-trie.jl (as in gate/tab1c-r4c) ends the function with "invalidated, reevaluated, idg_*: no IDG before TB6" and wip/tb6 has only the atoms (pl-atom.jl:470-472, 1539-1541). A TB6 step is missing (owner: TB6, the C builtin `$trie_property`'s IDG branch). Rows for it: pin from swipl:
   after cq/cp chain, cp: idg_affected_count 1, idg_dependent_count 1, invalidated 0, reevaluated 0, idg_size 80 (swipl: `idg_size=80` with one dependent), after assertz(cd(2)) invalidated 1, after re-call reevaluated 1 (REEVAL-like; my first experiment: p over d, a=0 d=1 inv 0 reev 0 size 80; after assertz inv 1; after re-call reev 1).
   Write these as `@test_broken` rows (owner TB6, builtin `$trie_property` idg keys).
2. `trie_property/2` (Prolog, boot/syspred.pl:1306) needs current_blob/2 (Q10): rows use `$trie_property/2` directly (D-0713 item 2).

## What is left (a new agent): (1) re-run the generators and write the test file with the groups above (copy the tb4rows helpers with prefix `_T6_`; per-case broken set `_T6_BROKEN = Dict("SINGLE/s02"=>"owner ...")`,
   `@test_broken` for those lines; the not-vacuous testset: every pin non-empty, the CHAIN c02 pin has both `affected` and `dependent` atoms, EXPAND x03 edges != x04 edges, DYNERR != DYNOK; the live-swipl testset like tb4rows);
   (2) the white-box V6 testset; (3) parse check `julia --startup-file=no -e 'Meta.parseall(read(ARGS[1],String))' <file>` (parse only); (4) tools/mutants/TB6R.py; (5) commit on wip/tb6rows
   (`git -C /home/shivaji1012/code/lk-tb6rows add ...` and `commit` in two calls, category ADDED:, `# allow-absence-claim: <reason>` if the hook asks) with the attribution line; no push.

## STATE after agent 2 (2026-11-14): STEPS 1-5 DONE, committed on wip/tb6rows, NOT pushed, nothing compiled or run
- test/core_lang/test_tabling_tb6rows_swipl.jl (parse-only checked: PARSE OK): groups CHAIN REEVAL SINGLE FALSECOUNT ABOLISH EXPAND DYNERR DYNOK INCRPROP TRIEKEYS
  (pins PRINTED by emit.py from swipl 10.1.20, two identical runs: evidence/TB6ROWS/pins.txt, generators evidence/TB6ROWS/gen/), the V6 white-box testset (hand-written yes/yes,
  no/yes, no/yes, C citations pl-comp.c:9241 :4915-4917), an S6 white-box testset (dead count carried by grow_block, pl-idgset.c:250), the not-vacuous testset, the live-swipl testset.
- `@test_broken` (per case, `_T6_BROKEN`): SINGLE s02-s04 owner TR4; ABOLISH a02-a08 and EXPAND x02-x05 owner TB5 ($tbl_destroy_table/1, $tbl_abolish_local_tables/0 cannot be
  found in the kernel: git grep on wip/tb6 returns only docs/r2_*.tsv rows and a comment); TRIEKEYS k01-k03 owner TB6 ($trie_property idg_* / invalidated / reevaluated keys).
- tools/mutants/TB6R.py: 9 mutants (TB6R-S6 C4 Q5 P14 V5 V6, TB6R-F4 T2 C2 = TB3's, `equivalent` dropped), TARGETS first = the new file.
- NOT VERIFIED: nothing ran on the kernel; TB3's `old` texts occur once in origin/gate/tab1c-r4's src only (zero times in wip/tb6's); TB6R is judged at the stack.
