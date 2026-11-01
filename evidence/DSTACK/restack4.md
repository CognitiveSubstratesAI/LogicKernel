# DSTACK restack4 — landing B re-stacked onto main b9de14d (wip/dstack-b3); STATE FILE for the next agent

Agent 1 (Sonnet) hit the 150k cap after the rebase and the first edits (the dispatcher's STATUS.md print cost ~40k: DO NOT `cat` STATUS.md, read its first 6 lines only).
Worktree ~/code/lk-dstack, branch wip/dstack-b3 (switched from wip/dstack-b2 90543e1 by `git rebase --onto origin/main 568fa9b`, since the A2 commits are
NOT patch-equal to A3 on main: use `--onto` with 568fa9b, not a plain rebase). NEVER force; wip/dstack-b2 untouched.

## Done
1. Rebase: 64 commits on origin/main b9de14d, tip f504ef5 (before my edits). Hand merges: src/LogicKernel.jl (kept `include("pl-string.jl")` then `include("os/pl-fmt.jl")`,
   the earlier commit that added src/pl-fmt.jl at the old path merged both then the move commit fixed it), docs/architecture.md (3 generated-graph hunks: kept both
   sides; `warm.sh inventory` regenerates). pl-global.jl, pl-ext.jl, manifest merged WITHOUT conflict. LD struct tail: ... module_enums, gvar_nb_vars, gvar_grefs,
   gvar_enums, recorded_states, IO_output_stack (struct == constructor by reading the diff vs main; first compile checks). docs/port_inventory.md was not conflicted: regenerate.
2. Uncommitted edits (git diff in the worktree; COMMIT THEM FIRST):
   - src/os/pl-prologflag.jl: `current_prolog_flag_atom(gd, name)::Union{Nothing,T}` typed helper; determinism_error_flag and check_create_flag call it; manifest
     entry `(LK.current_prolog_flag_atom, Tuple{GD, T}, false)` after PL_current_prolog_flag; 3 rows in test_prolog_flag_swipl.jl (near line 805).  [D-0291 (a) part 1]
   - src/os/pl-fmt.jl: prepare_sub_format `fdp = fd.position` local; `Scurout(ld)::IOSTREAM`; end_sub_format `(Scurout(ld)::IOSTREAM).position::IOPOS`; get_chr_from_text had
     no @inbounds already. [D-0291 (a) part 2]  The `~Nd` overflow comment now says DIVERGES flag (k), pl-fmt.c:553-556, pinned by k03. [(e)]
   - test/core_lang/test_format_swipl.jl: `_FM_KNOWN` row k03 (`catch(format(atom(R), "~3000000000d", [1]), error(format(R), _), true)`, kernel "argument overflow", swipl "1");
     testset renamed. [(e)]  NOT RUN yet (the row's swipl answer "1" is the prior agent's claim; the testset checks it live).
   - tools/mutants/O1A.py: C6 equivalent now has file:line (pl-fmt.jl:485, 316-317), new mutant O1A-C8 (overflow check dropped, KILL k03), header note.  [(d), (e)]
   - tools/mutants/O1B.py: TARGETS widened (A6 A8 A9 B1-B4 get TS + TF; E1 gets TS + TSA + TF); Q1/Q2 equivalents with file:line (pl-file.jl:1476, :1556/:1558, pl-fmt.jl:283/285;
     pl-file.jl:1317, pl-stream.jl:1040/1049).  [(d)]  Re-check the line numbers after `warm.sh fmt`.
   - tools/mutants/D1f.py and D1c.py: D1-95 `equivalent` dropped (targets T8 + test_set_flag_swipl.jl, kill sf80), D1-96's argument re-read against this tree (pl-comp.jl:3786-3790,
     :3981, :3770-3777, :3948-3952, :3205-3209, protected_predicate :3564-3572). New tools/mutants/D1g.py = D1-95 + D1-96 only (the list that gets a battery branch). [(c)]
   - tools/mutants/F1B.py: header lines 13-19 rewritten (D1g, exact lines, sf80); still 22 mutants.
3. Validator: /tmp/claude-1000/-home-shivaji1012-code-CognitiveSubstratesAI/7fed74f5-29da-4e48-90d4-1f228fe5bbba/scratchpad/val.py (python3 -I val.py <lists>: old once, new != old, ids unique, targets on disk).
   Result before the anchor edits: only O1A-K1 and the nine stale anchors fail; O1B 23, F1B 22, D1g 2, D1f 101 are clean.

## NOT done (next agent, in this order)
A. Apply the anchor re-fits (the python edit that would do it was blocked by the cap hook, NOTHING of it ran):
   - tools/mutants/O1A.py O1A-K1: old `    if fstate.pending_rubber == 0 && fdp !== nothing && fdp.linepos == COLUMN(fstate)`, new `    if true && fdp !== nothing && fdp.linepos == COLUMN(fstate)`.
   - MOD3a.py MOD3a-S1: old `    elseif tm === ci.module_                                   # if ( tm == ci->module )\n`, new `    elseif true\n` (list lines 76-77, file pl-comp.jl).
   - MOD3a-S2: old `    if is_call && ci.colon_context.type == TM_NONE && ci.at_context.type == TM_NONE\n`, new `    if is_call && ci.at_context.type == TM_NONE\n`.
   - SSU1.py SSU1-R4: old `    return clause_ndet(ld, A1, A2, A3, A4, PL__ac, PL__ctx, IS_RULE)\n`, new the same with IS_CLAUSE.
   - SSU1-S1: old `    if meta || (def.flags & P_SSU_DET) != 0         # ison(def, P_SSU_DET|P_DET) (P_DET: see above)\n`, new `    if meta\n`.
   - V9f.py MK4 (file src/pl-attvar.jl): old `            _slot_copy!(ld, s + 1, ld.exception_term + 1)   # *valTermRef(s) = *valTermRef(exception_term)\n            ld.exception_term = 0\n`, new the first line only.
   - MK16: old `            push!(di.argp, _atom_word!(ld, mk_sym(T, Symbol("\$catch"))))\n`, new `            push!(di.argp, _atom_word!(ld, mk_sym(T, :true)))\n`.
   - MK22: DROP the entry (copy_exception lost its trail copy in L1e e5); say so in the V9f.py header.
   - MD7 (pl-wam.jl): old `    determinism_error(ld, FR, ld.BFR, :nondet)\n` (indent 4), new `    nothing\n`.
   - MD21 (pl-error.jl): old `_err_atom(ld, found), _err_atom(ld, mk_sym(T, :goal))\n`, new `..., :guard))\n` (keep what the entry's new has now, re-applied to the new text).
   Check each against the real source text (the review's re-fits were verified on b2; main moved only by A), then run val.py on all 8 lists.
B. D-0291 (f): read against swipl: the pl-fmt.jl bodies and the redirect bodies in pl-file.jl:1300-1600 vs ~/code/swipl-devel-pin/src/os/pl-fmt.c and pl-file.c (pin 8609e216; the oracle is
   10.1.19 cbf4e189/e032366), the sf01-sf89 row-to-mutant map of F1B.py (each KILL id exists in test_set_flag_swipl.jl; a file-level check by python), D1c/D1f line numbers (done above).
C. Text fixes: docs/architecture.md:3231 (determinism_error is read from the flag table by `determinism_error_flag`; the F1b block "written, not yet gated" -> final state),
   phrase wording: evidence/O1/handoff.md:121 (done in the re-stack), evidence/DSTACK/handoff.md and split.md (same phrase), the MAXRUBBER docstring in pl-fmt.jl (the word for one column)
   -> "span"; architecture.md:5950 (flag k now pinned by k03: reword "row and mutant are NOT ..."). Optional (review 2.3): F1B mutants for S_UNDEF unknown=fail/warning,
   setVarPrefix read in pl-read.jl, print_write_options flag-table branch; at least list them in the NOT LISTED header with reasons.
D. Gates (daemon logickernel-warm-b4dc834e in ~/code/lk-dstack is NOT RUNNING; `tools/warm.sh status` says "not running". lk-lb3 and lk-lb4a hold two daemons; mine is the third:
   `cd ~/code/lk-dstack` in its own call, then `LOGICKERNEL_WARM_THIRD=1 tools/warm.sh start  # allow-restart: cold start after the struct change`, needs MemAvailable >= 12 GB;
   read warm.sh lines 110-200 for the exact form). Cold compile ~17-30 min. Then `warm.sh fmt` for committed files = `warm.sh send` (HEAD-diff only), `warm.sh inventory`, `warm.sh check`
   (JET on the SHA, D-0282), rows x3 (test_format_swipl.jl, test_with_output_to_swipl.jl, test_set_flag_swipl.jl, test_prolog_flag_swipl.jl, test_module_enum_swipl.jl, the sf rows), type
   discipline x3, `tools/pkgtest_way.sh <file>` one at a time, alloc pins x3, branch-gate --summary, term grep, D-0294 dry run (val.py) on the FORMATTED tree, the DISPATCH_MANIFEST
   uniqueness probe `[e for e in DISPATCH_MANIFEST if count(==(e), DISPATCH_MANIFEST) > 1]` must be empty, root suite on the final SHA (D-0296 item 4: three tests that count user procedures
   already fixed on main).
E. Push: git fetch; main unmoved?; channel pull + new D-entries; push gate/dstack-b3 + mutants/O1A, O1B, F1B, D1g, MOD3a, SSU1, V9f at the SAME SHA (none of those names exists on origin 2026-11-01;
   re-check `git ls-remote --heads origin 'gate/*' 'mutants/*'`); ONE capped background `tools/ci_wait.sh --timeout 10800 <sha>`; end the turn; on wake check EACH run:
   `ghg run list --commit <sha> -R CognitiveSubstratesAI/LogicKernel --json databaseId,workflowName,headBranch,status,conclusion`.

## Rules reminders for the next agent
Do not cat STATUS.md (first 6 lines only). `git grep` instead of `grep -r` on src (the CODEMAP hook blocks `grep -r`). lanes.conf is dispatcher-only (D-0225): the brief's "update the lk-dstack row"
conflicts with it; the row is the dispatcher's. Trailer: Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>.
