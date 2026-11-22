# COMPEXT3 STATE (read first; the COMP-EXT2 text below is historic)
Commit 1 (6468eeb7) DONE: thread_create/3 refusal, FRG entries $spy/$nospy/thread_create, meta list, manifest, owner row.
NOT yet written: item 2 (rows file test/core_lang/test_compext_swipl.jl + tools/mutants/COMPEXT.py) and item 3 (the $fetch_vm/$xr_member/B_THROW plan).
FOUND, FIXED (uncommitted at this line, folded into the rows commit): lookup_vmi (src/pl-comp.jl) matched the kernel's UPPER-CASE
`:I_ENTER`; swipl's `$vmi_property` names are LOWER-CASE (`i_enter`; `'I_ENTER'` is existence_error(vmi,'I_ENTER')). Now lowercased.
swipl 10.1.20 (the pin binary) probes, in the scratchpad compext/: probe2.out ($predefine_foreign, $vmi_property), probe3.out ($spy/$nospy):
- `$predefine_foreign(pfa/2)` then `$get_predicate_attribute(pfa(_,_),foreign,V)` V=1; errors: `_` instantiation_error, `1/2` type_error(atom,1),
  `pfb/x` type_error(integer,x), `pfb/(-1)` domain_error(not_less_than_zero,-1).
- `$vmi_property`: i_enter break(true) argv([]); i_call argv([lproc]); i_call break(true); i_exit break(true); b_unify_var argv([var]); h_atom argv([data]);
  i_depart argv([lproc]); h_var argv([var]); i_fcalldetva argv([foreign]); i_callatm argv([module,module,proc]); b_functor argv([func]);
  h_string argv([string]); h_float argv([float]); i_callm argv([module,proc]); break(false) on i_enter FAILS; break(foo) type_error(bool,foo);
  nosuch(_) domain_error(vmi_property,nosuch(_)); foo type_error(vmi_property,foo); `_` instantiation_error; unknown vmi existence_error(vmi,nosuch)
  (also h_integer, h_int64, i_usercall0, i_usercalln: not in swipl either); var vmi instantiation_error; 1 type_error(atom,1).
- `$spy(sp(_))` sets attribute spy=1 and flag debug=true, message informational spy(sp(_)); second `$spy` silent; `$nospy` message nospy(sp(_)),
  spy=0, debug stays true; `$nospy(nosuch)` existence_error(procedure,nosuch); `$nospy(nosuch(_))` existence_error(procedure,nosuch(_));
  `$spy(nosuch)` FAILS; `$spy(_)`/`$nospy(_)` instantiation_error; `$spy(sp/1)` fails; `$nospy(1)` type_error(callable,1).
  The kernel without print_message/2 COLLECTS the message on the local data (src/pl-error.jl printMessage), swipl's message_hook sees it: two observers.
STOPPED by a PreToolUse hook block (the agent reported it): `grep -ln ... test/core_lang/*.jl | head` was refused by pre-bash.sh
"BLOCKED: truncating a FILE-LIST enumeration". Next agent: find how tests read ld.messages with the Read tool on ONE file.

# COMP-EXT2 handoff (writer hit the 150k cap; NOTHING COMMITTED, edits are in the worktree, uncommitted)

Worktree ~/code/lk-compext, branch wip/comp-ext at 281ca507. No julia was run. Upstream pin 18168e62; copies of pl-comp.c,
pl-ext.c, pl-pro.c, pl-vmi.c, pl-trace.c, pl-proc.c are in the scratchpad dir `.../scratchpad/compext/`.

## Done in the worktree (uncommitted, unformatted, not parsed)
- src/pl-pro.jl: `pl_notrace1_va` (`'$notrace'/1`, pl-pro.c:392-410) with the registration entry after `$notrace/2`
  (flags VARARGS|TRANSPARENT|NOTRACE) and the header comments updated. main did NOT register it before.
- src/pl-comp.jl: `pl_predefine_foreign1_va` (before compile_predicates), `_CA1_NAMES`, `lookup_vmi`, `pl_vmi_property2_va`;
  registration `$predefine_foreign/1` (before clause/2) and `$vmi_property/2` (after nth_clause/3), as upstream's table order.
- src/pl-proc.jl: `get_procedure_find(gd, ld, descr, how::Int=GP_FIND)` now honours GP_EXISTENCE_ERROR (needed by `$nospy`).
- src/pl-trace.jl: `pl_spy`, `pl_nospy` (pl-trace.c:2342-2379) before `resetTracer`.
- test/static_analysis_manifest.jl: entries for pl_notrace1_va, pl_predefine_foreign1_va, pl_vmi_property2_va.

## COMPEXT3 commit 1 (committed): items 1-4 below are DONE (thread_create/3 refusal, FRG entries, manifest, owner row). Rows/mutants (item 5) and the $fetch_vm plan: not yet written.

## (historic) NOT yet written
1. src/pl-thread.jl: append `pl_thread_create(ld, goal, id, options)` throwing
   `NotPortedError{T}(mk_sym(T, :thread_create), "thread_create/3 (a second thread)", "TH1")` (`# PORT: pl-thread.c pl_thread_create`,
   `# DIVERGES: REFUSED BY NAME, owner TH1`).
2. src/pl-ext.jl: FRG table entries `$spy/1`, `$nospy/1` (PL_FA_TRANSPARENT; before dwim_match/3, pl-ext.c:143-144) and
   `thread_create/3` (TRANSPARENT|ISO; between write_canonical/2 and thread_self/1, pl-ext.c:183); add `("thread_create", 3, "0?+")`
   to the `PL_meta_predicate` list (after thread_idle); extend the header comment ("Since COMPEXT2 ...").
3. test/static_analysis_manifest.jl: `(LK.pl_spy, Tuple{LD, Int}, false)`, `(LK.pl_nospy, ...)`, `(LK.pl_thread_create, Tuple{LD, Int, Int, Int}, false)`,
   `(LK.get_procedure_find, Tuple{GD, LD, Int, Int}, false)` (next to the existing Tuple{GD, LD, Int} entry, line ~2098).
4. docs/r2_owners.tsv: remove the now-stale `pred:` owner lines of the registered predicates (`$notrace/1`, `$predefine_foreign/1`,
   `$vmi_property/2`, `$spy/1`, `$nospy/1`, `thread_create/3` -> replace by the exact-key refusal row
   `refusal:src/pl-thread.jl::pl_thread_create::thread_create/3 (a second thread)<TAB>TH1<TAB>note`); check each exists first.
5. Rows: test/core_lang/test_compext_swipl.jl (driver like test_p2_swipl.jl / test_notrace_swipl.jl; three term types; swipl twice,
   capped; pins for `'$predefine_foreign'(foo/2)` + `'$get_predicate_attribute'(foo(_,_), foreign, V)`, `'$vmi_property'(I_ENTER, break(B))`,
   `argv(L)`, the three error forms, `'$notrace'(G)` restoring tracing/skip level, `'$spy'`/`'$nospy'` with a message_hook collector,
   `'$nospy'(nosuch)` existence_error) + LK-ONLY rows for the thread_create refusal; mutants tools/mutants/COMPEXT.py ("aimed by <rows>",
   exactly-once `old`, TARGETS = the new file + test_notrace_swipl.jl + test_bootpred3_swipl.jl + test_debug_flag_swipl.jl + test_nth_clause_swipl.jl).
6. Commits, one per upstream file, subject `UPSTREAM: <file> <predicates> (swipl-devel 18168e62)`, body 3-6 lines incl. "test_type_discipline.jl
   and warm.sh check NOT run", then the Co-Authored-By line. Stage all, commit in a separate call.

## Left for a separate step, with the reason
- `$fetch_vm/4`, `$xr_member/2` (pl-comp.c): both call `unify_vmi` / walk a clause's code by `stepPC` and operand kind; the kernel has no
  `unify_vmi` and its operands are table INDEXES (literals, procedures, modules: src/pl-vmi.jl header), so each needs a decoder of its own:
  not one narrow step. Owner stays as in docs/r2_owners.tsv (cfile:pl-comp / pred rows). Also needs `wouldBindToDefinition`, `supervisorLength`.
- B_THROW: NOT STARTED (VMI(B_THROW) in pl-vmi.c at the pin not read; no outcome).
- `$break_pc/3`, `$break_at/3`, `$addr2line/2`, `$local_definitions/2`: skipped as briefed.

## Facts learnt
- CODEMAP rows 259, 348, 363 do not cover these files; the hook is satisfied by reading them whole (sed -n Np | fold).
- `$spy/$nospy` are pl-trace.c functions registered by pl-ext.c's FRG table; `SPY_ME` is read by nothing in the VM (no tracer: DBG1), the
  existing refusal "spy points (GP_RESOLVE)" in pl_set_predicate_attribute3_va is for `$set_predicate_attribute(spy)` and is untouched.
- A daemon: none used by this agent (no julia).
