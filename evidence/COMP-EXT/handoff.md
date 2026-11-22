# COMPEXT4 STATE (read first; COMPEXT3 and COMP-EXT2 below are history)
Commit 2 (54381a53, `TEST: COMP-EXT rows and mutants`) DONE, no julia run, nothing pushed, `test_type_discipline.jl` and `warm.sh check` NOT run:
- test/core_lang/test_compext_swipl.jl: rows cx01-cx64 (cx01-13 `$notrace/1`, cx14-21 `$predefine_foreign/1`, cx22-50 `$vmi_property/2`,
  cx51-64 `$spy/1` + `$nospy/1`); `_CX_PINNED` = 65 lines (ok + 64) from swipl 10.1.20, TWO runs of the explicit pin binary (capped scope),
  compared identical, by evidence/COMP-EXT/gen_rows.py (rewrites the test file in place; the program/wrapper/cases are parsed from it). cx40 and
  cx58 fail on swipl (a bare line). The messages: the program's own `message_hook/3` clause records `got(Term)` (informational only) on BOTH sides and the
  rows read it back; the kernel is observed a second time by `lk_install_message_collector!(kinds=(:informational,))` + `lk_take_messages!` in
  the white-box testset (`spy(spw(_))`, `nospy(spw(_))`, once each, none for an idle `$nospy`). White-box: the debugger bits, SPY_ME cleared, P_FOREIGN set.
  LK-ONLY testset: `thread_create/3` throws NotPortedError (step "TH1", what names `thread_create/3 (a second thread)`), a comment names TH1 as Phase 1
  and the refusal as a sequencing step (D-0784). Every row is UNVERIFIED on the kernel (no julia): the gate decides.
- Findings the pins show, to check on the kernel at the gate (each a likely mismatch, not yet seen): cx07/cx12: inside `$notrace/1` the debugging bit is off
  (swipl reads 13 = 15 less 2) and after it the debugging bit is restored (cx07 reads 0); `$vmi_property` with an unbound property is an
  instantiation_error (cx44) where the kernel's `PL_error(ERR_TYPE, ..., A2)` must turn a variable culprit into one; cx49/cx50: h_integer and i_usercall0 are
  NOT instructions in swipl (existence_error); the kernel's table declares neither (grep of src/pl-vmi.jl code_info rows), so these two should agree.
- Not in cost tables (test/pkgtest_costs.tsv, test/unit_costs.tsv): a new line `core_lang/test_compext_swipl.jl` is the landing's.
- tools/mutants/COMPEXT.py: 30 mutants (NP-N1..N5 `$notrace/1`, PF-1/2, VM-1..9, SP-1..10, GF-1/2, TC-1/2), each "aimed by <rows>", `old` occurs
  EXACTLY once (python3 -I count over MUTANTS), TARGETS = the new file + test_notrace_swipl.jl + test_bootpred3_swipl.jl + test_debug_flag_swipl.jl +
  test/db/test_nth_clause_swipl.jl. Not run (CI runs the battery once).
- Left: `warm.sh fmt` (the case tuples are written as the formatter writes them, not run), `warm.sh check`, the three-type run of the new file,
  `tools/pkgtest_way.sh test/core_lang/test_compext_swipl.jl`, test_type_discipline.jl, then push `mutants/COMP-EXT` and `gate/comp-ext` at one SHA.

## DEC1 STATE (written by the DEC1 agent; no julia run, nothing formatted or compiled)
- Commit 1: `unify_vmi(gd, ld, t, bp::Code{T}, procedures, crefs)` + `unify_functor(ld, t, name::T, arity, how)` (src/pl-comp.jl, before the
  PL_predicates_from_comp table), manifest entries, owner row for the CA1_AFUNC refusal (AR1). The DIVERGES per operand kind are in its header comment.
  Kinds: VAR/FVAR/CHP, INTEGER/JUMP (`*_SMALLINT` ops read the tagged word through `valInt`), FLOAT/MPZ/MPQ/STRING (literal index),
  WORD, DATA (per instruction: packed atom_operand / literal index / atom word), FUNC (packed functor_operand / functor word), MODULE (index, 0 = unbound),
  LPROC, PROC, CLAUSEREF (`clause(<dbref>)`), FOREIGN (dispatch index), TRIE_NODE (upstream's `default`: returns `nothing`), AFUNC (REFUSED BY NAME).
  D_BREAK is not declared in the kernel: the `break(Instr)` branch is left out.
- UNVERIFIED (needs the first run): JUMP operands (are they upstream's offsets?), the packed-atom/literal reading for every instruction that has CA1_DATA,
  `functor_literal` name for `H_FUNCTOR`, the compile of the file. swipl 10.1.20 shows e.g. `h_smallint(1)`, `i_call(g/2)`, `i_departm(lists,lists:append/3)`,
  `a_add_fc(1,0,1)`, `b_unify_exit`, `i_enter`, `i_exitfact`, `h_functor(foo/2)`, `h_var(1)`, `h_firstvar(2)`, `b_void`.

## DEC1 PIECE 2 STATE (UNCOMMITTED in the worktree at the hand-back: the 150k cap blocked the commit step)
- Piece 2, committed by the dispatcher after DEC1's context cap as `UPSTREAM: pl-comp.c $fetch_vm (swipl-devel 18168e62)` (comments state what the code does, positively):
  * src/pl-comp.jl: `pl_fetch_vm4_va` (before the PL_predicates_from_comp table; clause ref -> clause.codes/literals/procedures; else get_functor(GF_PROCEDURE) +
    resolveProcedure -> def.codes, `supervisor_crefs`, `supervisorLength`), registered after `$vmi_property` as `PL_FA_TRANSPARENT | PL_FA_VARARGS`.
  * src/pl-supervisor.jl: `supervisorLength(cd::PL_code_data, base)` at the end (a non-shared block = its vector length; a shared block walked to I_EXIT).
  * test/static_analysis_manifest.jl: entries for `pl_fetch_vm4_va` and `supervisorLength` (alloc flag false).
- NOT written: the ROWS (cx65+ in test/core_lang/test_compext_swipl.jl; evidence/COMP-EXT/gen_rows.py asserts `len(cases) == 64`: raise it to the new count, run it with
  the scratchpad as cwd: it writes cx_rows.* and rewrites `_CX_PINNED` in place from two capped swipl runs) and the MUTANTS (tools/mutants/COMPEXT.py, "aimed by <rows>", exactly-once `old`,
  NO equivalent= field, TARGETS as the file's other mutants). The `_CX_PROGRAM` needs the added clauses; the probe program is scratchpad/compext/f2.pl (NOT yet run: it was the
  next call). Row plan: a `vm_all(Ref, L)` helper (loop `'$fetch_vm'(Ref, PC, N, I)` until failure); `clause(H, _, Ref), vm_all(Ref, R)` for a fact with an atom (`vf1(a)`),
  a small int, a nil, a compound `f(X,X)`, a float, a string; rules `vg(X)`, `vg(X), !, vg(X)`, `Y is X+1, vg(Y)`, `X = foo(_,bar)`, `lists:append(X,[],_)`;
  the error forms on a clause reference (PC -1, 99, `a`, unbound) and the end of code (PC == length fails); a bound NextPC/Instruction that mismatches fails; the supervisor of a
  never-called predicate (`'$fetch_vm'(vq1(_), 0, N, I)`, expect `1-s_virgin` as swipl showed for `f/1`, then `i_exit`, then fail at 2, domain_error at 3).
  The h_string/h_mpz offsets (NextPC) differ in the kernel (one literal word; swipl inline block): compare the instruction LISTS only (offset-independent through vm_all), not N, for those.
- swipl 10.1.20 facts seen in a probe (f1.pl): `h_smallint(1)`, `h_atom(a)`, `h_float(2.5)`, `h_string("s")`, `h_mpz(100000000000000000000)`, `i_exitfact`;
  `i_enter, b_var0, b_smallint(3), i_call(g/2), i_cut, a_add_fc(1,0,1), b_eq_vc(1,2), b_unify_var(0), h_functor(foo/2), h_var(1), h_firstvar(2), h_pop, b_unify_exit, b_unify_vc(2,bar), b_void, b_void, b_void, i_departm(lists,lists:append/3), i_exit`.
- Left after the rows: the commit of the rows (+ handoff), then the dispatcher's gates (fmt, check, three-type run of the changed test file, pkgtest_way, test_type_discipline.jl).

## PLAN (separate steps, NOT started): `$fetch_vm/4`, `$xr_member/2`, B_THROW
Upstream: swipl-devel 18168e62, copies in the scratchpad `compext/` (pl-comp.c, pl-vmi.c). Both predicates need ONE shared piece first: an OPERAND DECODER
for a clause's code (the kernel's operands are table INDEXES, src/pl-vmi.jl header "OPERANDS"; upstream's are pointers/words), and a walk by `stepPC`
(src/pl-comp.jl:5613-5616, already ported: `Code{T}(codes, literals, pc)`, `pc + 1 + codeTable(op).arguments`).
1. STEP DEC1 (the decoder, ~1 piece): `unify_vmi(ld, t, bp)` = pl-comp.c:7889-8068 at the pin (`D_BREAK` -> `break(Instr)` with `replacedBreak`; zero-argument
   instruction -> the name atom, LOWER-CASE as `lookup_vmi`; else `Name(Arg1..3)` with `PL_FUNCTOR_CHARS, ci->name`). Per operand kind (`ca1_name` order, the
   kernel's `_CA1_NAMES` in src/pl-comp.jl):
   - CA1_VAR/FVAR/CHP: `VARNUM(*bp++)` as an integer (kernel: `VARNUM`, src/pl-incl.jl:1602);
   - CA1_INTEGER/JUMP: the signed word as int64; CA1_WORD: `code_get_word` (the kernel has no 2-word operand: a divergence to name, int64 from the one word);
   - CA1_FLOAT: kernel operand = literal index -> the literal's float (DIVERGES: upstream reads CODES_PER_DOUBLE words);
   - CA1_DATA: kernel operand = literal index -> `PL_unify_atomic` of the literal term (upstream: the word); CA1_STRING/MPZ/MPQ likewise (upstream
     `globalIndirectFromCode`, c:8040-8043: kernel literal index);
   - CA1_FUNC: kernel operand = `functor_operand` word (src/pl-comp.jl:1467; literal index | arity | functor index; the `$expr/n` case is literal 0) ->
     `Name/Arity` (`unify_functor(.., GP_NAMEARITY)`: the kernel's `unify_functor` src/pl-comp.jl:3474 takes a `Definition`, so a functor variant is to add);
   - CA1_MODULE: module INDEX -> `gd.modules[i].atom`; a 0 index (the clause's module, upstream NULL for I_DEPARTAM) leaves the cell unbound, as c:8000-8006;
   - CA1_LPROC / CA1_PROC: index into the clause's procedure table (`clause.procedures[i].definition`) -> `Name/Arity` (LPROC, `functor` only) or the qualified
     `unify_definition(MODULE_user, .., GP_QUALIFY|GP_NAMEARITY)` (PROC; src/pl-comp.jl:3497 takes a `head` and `thehead`, check its how-flags);
   - CA1_CLAUSEREF: index into `codes_crefs` -> `clause(Ptr)` (`PL_POINTER`: the kernel's clause reference is a dbref: use the dbref constructor of src/pl-dbref.jl);
   - CA1_FOREIGN: `dladdr` has no kernel counterpart: DIVERGES, `PL_put_pointer` fallback of c:8021-8024 (name the reason); CA1_AFUNC: the arithmetic function table
     (`functorArithFunction`) is the kernel's `ar_*` table: look it up first.
   Row source: `'$fetch_vm'` answers from swipl 10.1.20 for a small clause set (a fact, a rule with a call, a cut, an `is`), pinned twice as COMP-EXT.
2. STEP FETCHVM (`$fetch_vm/4`, pl-comp.c:8151-8206, PL_FA_TRANSPARENT; registration c:9276): `PL_is_dbref(from)` (src/pl-dbref.jl:207) with `PL_get_clref` (:246) ->
   `clause.codes`, `code_size`; else `get_functor(from, GF_PROCEDURE)` (src/pl-proc.jl:2065) + `resolveProcedure` (:271) -> `definition.codes` (the SUPERVISOR code,
   null -> fail) and `supervisorLength(base)`, which the kernel LACKS (add, upstream pl-supervisor.c `supervisorLength`: the walk to the supervisor's last instruction; read it
   there first). Errors: `PL_get_intptr_ex(offset)`, `domain_error(program_counter, Offset)` for offset <0 or >len, false at == len, `PL_unify_int64(NextPC, next-base)`.
   Needs DEC1. Rows: `'$fetch_vm'(Clause, 0, N, I)` over an instruction stream of a pinned program; the error forms.
3. STEP XRMEMBER (`$xr_member/2`, pl-comp.c:7697-7849, PL_FA_NONDETERMINISTIC; registration c:9282): enumerates (unbound Term; redo state `i = (pc<<3)+an`,
   ForeignRedoInt) or tests (bound Term: atomic -> CA1_DATA/MODULE; functor -> CA1_FUNC with `fd != FUNCTOR_colon2`; else `get_procedure(.., GP_FINDHERE|GP_TYPE_QUIET)`
   against CA1_PROC/LPROC via `wouldBindToDefinition`, c:7664-7693 at the pin, a walk up `module->supers` with `isCurrentProcedure`, `getUnknownModule`).
   Every kind is the DEC1 operand, read per kind (kernel: literal index / functor_operand / module index / procedure index). The nondeterminism rides the kernel's NF1
   foreign redo (`ForeignRedoInt`); `getUnknownModule(def->module) == UNKNOWN_FAIL`, `PROC_DEFINED` and `impl.any.defined` must be found in the kernel first
   (CODEMAP; none were searched). Needs DEC1 for the enumeration order (an order a row can pin: `findall(X, '$xr_member'(Ref, X), L)`).
4. B_THROW (pl-vmi.c:4955-4959 `VMI(B_THROW, 0, 0, ())`: `PL_raise_exception(consTermRef(argFrameP(lTop, 0)))` then `THROW_EXCEPTION`; the `b_throw` helper follows at
   :4961-, with findCatcher/rewrite) is NOT declared in the kernel's code table (no `B_THROW` in src/pl-vmi.jl, none in src/pl-wam.jl) and `throw/1`'s path in the kernel
   was NOT read by this step. First read: how the kernel's `throw/1` (and `I_CALLCLEANUP`'s) raise, then decide whether B_THROW is a table entry plus a run-loop case
   (read pl-comp.c's emitter of it at the pin first) or stays refused by name. No outcome here.
   Then `$vmi_property(b_throw, break(B))` / `argv([])` rows become possible (swipl: pin them first).
Order: DEC1 -> FETCHVM -> XRMEMBER; B_THROW independent and last.

# COMPEXT3 STATE (history; COMP-EXT2 text below it is older)
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
