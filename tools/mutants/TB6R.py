# ORIGINAL: the mutant list of the TB6-ROWS kill rows: a repository list of ours (upstream has no such file).
# tools/mutants/TB6R.py - the mutants whose DEFERRED KILL (tools/mutants/TB6.py: TB6-S6, TB6-C4, TB6-Q5, TB6-P14, TB6-V5, TB6-V6; tools/mutants/TB3.py: TB3-F4, TB3-T2,
# TB3-C2, declared EQUIVALENT until TB6) the rows of test/core_lang/test_tabling_tb6rows_swipl.jl (TR6) carry. Each `old`/`new` is the text of its source list, UNCHANGED
# (TB6.py at wip/tb6 2e2617c2; TB3.py at origin/gate/tab1c-r4, the batch-3 tree: TB3's `old` text lives in that tree only, so those three are judged at the stack = batch 3 + TB6); the TB3
# ones lose their `equivalent` flag: with an IDG they are killable. Ids carry the prefix `TB6R-` so that the source lists' ids stay unique. NOT RUN YET (written edit-only,
# 2026-11-14, nothing compiled): every KILL is read off the rows of TR6 and the pinned swipl 10.1.20 answers (evidence/TB6ROWS/pins.txt), not observed.
# TARGETS: TR6 FIRST (the driver stops at the first failing target), then every file that exercises the mutated source (D-0238): the stack's tabling files through
# start_tabling (TI = the IDG rows, TV TW TA TF = TB1-TB4, TT = the table pools), and for the run-loop mutant the files of TB6.py's own list.
# `@test_broken` rows (SINGLE s02-s04 owner TR4, ABOLISH a02-a08 and EXPAND x02-x05 owner TB5) judge no mutant today (TRIEKEYS k01-k03 are plain @tests since the handler pl_trie_property2_va is ported); the rows that kill are plain @tests.
TR6 = "test/core_lang/test_tabling_tb6rows_swipl.jl"
TI = "test/core_lang/test_tabling_idg_swipl.jl"
TV = "test/core_lang/test_tabling_variant_swipl.jl"
TW = "test/core_lang/test_tabling_worklist_swipl.jl"
TA = "test/core_lang/test_tabling_answers_swipl.jl"
TF = "test/core_lang/test_tabling_wfs_swipl.jl"
TT = "test/core_lang/test_tabling_state_swipl.jl"
TC = "test/core_lang/test_cont_boot_swipl.jl"
TB = "test/db/test_boot_image_swipl.jl"
TM = "test/core_lang/test_tabling_min_swipl.jl"
WR = "test/core_lang/test_wrap_swipl.jl"
ALL = [TR6, TI, TV, TW, TA, TF, TT, TM]                 # every file that reaches the IDG or the answers through start_tabling
WAM = [TR6, TI, TV, TW, TA, TF, TC, TB, TM, TT, WR]    # the run loop: every file of TB6.py's TARGETS
COMP = [TR6, TI]                                        # assert_term!'s PL_CREATE_INCREMENTAL branch is reached only through TR6 and TI
TP = "test/core_lang/test_trie_property_idg_swipl.jl"   # the `'$trie_property'/2` IDG branches (tools/mutants/TBP.py kills the same mutants there)
TG = "test/core_lang/test_trie_gen_swipl.jl"
TZ = "test/core_lang/test_tabling_answer_discard_upstream_swipl.jl"
TRP = [TR6, TP, TG, TZ]                                 # every file that calls `'$trie_property'/2` with an IDG key (TR6 first)
TARGETS = [TR6, TI, TV, TW, TA, TF, TT, TM, TC, TB, WR, TP, TG, TZ]  # every file a mutant lists
TAB = "src/pl-tabling.jl"
MUTANTS = [
    dict(id="TB6R-S6 (= TB6-S6; KILLS: the white-box testset `TB6 S6 white-box` of TR6 (a delete in a block of 4, the add that grows it to 8: block.dead == 1 and idg_set_size 4, the mutant gives 0 and 5) and, once TB5 lands, EXPAND x03 (after abolish_table_subgoals the fifth table revives the dead slot: swipl has 4 edges, the mutant 5))",
         file='src/pl-idgset.jl', targets=ALL,
         old='    nb.dead = b.dead\n',
         new='    nb.dead = 0\n'),
    dict(id="TB6R-C4 (= TB6-C4; KILLS: CHAIN c04 and c09 (`'$idg_thread_space'` 752 = 512 + 3 * 80; the mutant charges 728) and DYNERR v01/v02 (the limit that raises at the dynamic-call edge moves))",
         file='src/pl-incl.jl', targets=ALL,
         old='const SIZEOF_IDG_NODE = 80\n',
         new='const SIZEOF_IDG_NODE = 72\n'),
    dict(id="TB6R-Q5 (= TB6-Q5; KILLS: CHAIN c02 (`'$idg_edge'(T, Dir, D)` with Dir unbound at cp, a node with both a parent and a child: [affected-complete, dependent-dynamic]; the mutant never reaches the dependent set))",
         file='src/pl-tabling.jl', targets=ALL,
         old='            if !state.fixed_dir && dir !== nothing &&\n',
         new='            if false && dir !== nothing &&\n'),
    dict(id="TB6R-P14 (= TB6-P14; KILLS: FALSECOUNT p01 and p06 (`'$idg_set_falsecount'(T, 4294967296)` and 4294967297 raise representation_error(falsecount); the mutant takes them))",
         file='src/pl-tabling.jl', targets=ALL,
         old='            fc > typemax(UInt32) &&\n                return if PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :falsecount))\n                    FTRUE\n                else\n                    FFALSE\n                end\n',
         new='            nothing\n'),
    dict(id='TB6R-V5 (= TB6-V5; KILLS: DYNERR v01 and v02 (a resource_error(private_table_space) at the S_INCR_DYNAMIC edge must unwind; the mutant continues into S_STATIC with the exception set; DYNOK is the control))',
         file='src/pl-wam.jl', targets=WAM,
         old='        ld.exception_term != 0 && @goto b_throw     # THROW_EXCEPTION\n    end\n    @goto S_STATIC                                  # VMI_GOTO(S_STATIC)\n\n    # PORT: pl-vmi.c S_MULTIFILE\n',
         new='    end\n    @goto S_STATIC                                  # VMI_GOTO(S_STATIC)\n\n    # PORT: pl-vmi.c S_MULTIFILE\n'),
    dict(id='TB6R-V6 (= TB6-V6; KILLS: the white-box testset `TB6 V6 white-box` (assert_term! with PL_CREATE_INCREMENTAL on a new predicate: incremental yes; hand-written expectation, swipl cannot answer it))',
         file='src/pl-comp.jl', targets=COMP,
         old='        if (flags & PL_CREATE_INCREMENTAL) != 0\n',
         new='        if (flags & PL_CREATE_INCREMENTAL) == 0\n'),
    dict(id='TB6R-F4 (= TB3-F4; KILLS: REEVAL f02 (assertz(rd(3)), re-call: [1,2,3] and value_count 3, falsecount 0, complete; the mutant leaves IDG_DELETED set on the re-found answers 1 and 2 and reeval_complete deletes them))',
         file='src/pl-tabling.jl', targets=ALL,
         old='                if (nd.flags & TN_IDG_DELETED) != 0\n                    nd.flags &= ~TN_IDG_DELETED\n                    @goto update_dl\n',
         new='                if (nd.flags & TN_IDG_DELETED) != 0\n                    @goto update_dl\n'),
    dict(id="TB6R-T2 (= TB3-T2; KILLS: SINGLE s01 once TR4 compiles tables (a one-answer incremental table takes the trie symbol, `compiled_size` no); partner s02 (@test_broken, owner TR4) shows `yes` for two answers. Until TR4 the kernel's `compiled_size` fails for every table: s01 alone cannot tell the mutant apart, s02-s04 are the rows that will)",
         file='src/pl-tabling.jl', targets=ALL,
         old='    if atrie.value_count == 1 &&\n',
         new='    if atrie.value_count != 1 &&\n'),
    dict(id='TB6R-C2 (= TB3-C2; KILLS: SINGLE s01 with s02-s04 (same as TB3-T2: pl-tabling.c:6270-6279, :12313-12314))',
         file='src/pl-tabling.jl', targets=ALL,
         old='        tbl_single_answer(atrie) != 0 && return trie_symbol(gd, atrie)\n',
         new='        nothing\n'),
    dict(id="TB6R-K1 (TRIEKEYS: idg_dependent_count answers the affected count; KILLS: TRIEKEYS k01-k03 (cp has 1 affected and 1 dependent, cq 0 and 1, cd 1 and 0: r(1,1,..) r(0,1,..) r(1,0,..)); TBP-A2 kills it in TP too)",
         file='src/pl-trie.jl', targets=TRP,
         old='idg_set_size(idg.dependent)) ? FTRUE : FFALSE',
         new='idg_set_size(idg.affected)) ? FTRUE : FFALSE'),
    dict(id="TB6R-K2 (TRIEKEYS: idg_affected_count answers the dependent count; KILLS: TRIEKEYS k01-k03 (cq has 0 affected and 1 dependent, cd 1 and 0); TBP-A1 kills it in TP too)",
         file='src/pl-trie.jl', targets=TRP,
         old='idg_set_size(idg.affected)) ? FTRUE : FFALSE',
         new='idg_set_size(idg.dependent)) ? FTRUE : FFALSE'),
    dict(id="TB6R-K3 (TRIEKEYS: invalidated reads the reevaluated counter; KILLS: TRIEKEYS k02 and k03 (after assertz(cd(2)): invalidated 1, reevaluated 0 on cp and cq); TBP-I1 kills it in TP too)",
         file='src/pl-trie.jl', targets=TRP,
         old='PL_unify_int64(ld, arg, idg.stats_invalidated)',
         new='PL_unify_int64(ld, arg, idg.stats_reevaluated)'),
    dict(id="TB6R-K4 (TRIEKEYS: reevaluated reads the invalidated counter; KILLS: TRIEKEYS k02 (invalidated 1, reevaluated 0) and k03 (cp and cq re-evaluated: 1 and 1, cd 0 and 1); TBP-I2 kills it in TP too)",
         file='src/pl-trie.jl', targets=TRP,
         old='PL_unify_int64(ld, arg, idg.stats_reevaluated)',
         new='PL_unify_int64(ld, arg, idg.stats_invalidated)'),
    dict(id="TB6R-K5 (TRIEKEYS: idg_size omits the size of the dependent set; NOT KILLED by k01-k03: every edge set of those rows holds at most one pointer (the `single` slot, no block), `idg_set_sizeof` is 0 and the sum is 80 = the pin; KILLED by TP tp01 (three dependents make a block: 136 against 80), as TBP-S3)",
         file='src/pl-trie.jl', targets=TRP,
         old='            size += idg_set_sizeof(idg.dependent)\n',
         new=''),
]
