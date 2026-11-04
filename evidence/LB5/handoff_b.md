# LB5b writer (Sonnet, EDIT-ONLY, 2026-11-04): `LD->prompt.next`

Base: origin/main 18468130da49c6e3654acc33e400aabab33e262e (LB5 landed). Worktree ~/code/lk-lb5b, branch wip/lb5b.
STATE: the work is STAGED, NOT COMMITTED. The commit hook refused the struct-only commit ("unstaged changes - the index is not what was tested";
it also needs the branch-gate marker, which only a gate agent can write). `git diff --cached --stat`: 5 files, +196/-7 (docs/architecture.md,
src/os/pl-file.jl, src/pl-global.jl, test/core_lang/test_lb5b_prompt.jl (new), tools/mutants/LB5B.py (new)) plus this file once staged.
The code lines are in the staged diff (checked: `git diff --cached src/os/pl-file.jl` shows `i == 0 && (ld.prompt_next = true)`; pl-global.jl shows the field
and the constructor entry).

## What is in it
1. src/pl-global.jl: `prompt_next::Bool` appended LAST in PL_local_data (after event_hook_onthreadexit); constructor entry `false` (comma added to the
   previous last entry); comment "Since R2 LB5b" with the DIVERGES (flag is only set; readers are the toplevel's; removal condition).
   A struct change: the daemon restarts cold at the gate.
2. src/os/pl-file.jl set_stream alias branch: `i == 0 && (ld.prompt_next = true)` after setStandardStream (upstream pl-file.c:2224-2225 at the pin
   cbf4e1896275, read with `git show` from ~/code/swipl-devel-pin). The set_stream DIVERGES block names the readers at the pin (Sread_user pl-file.c:5992-6004,
   PL_write_prompt :1884, wrapIO :6150, pl-os.c, pl-fli.c:5349, pl-pro.c:67): zero of them exist in the kernel (zero matches for PL_write_prompt, Sread_user,
   wrapIO in src/), so the flag is only SET. Owner: the toplevel step (status board row TOP1); removal condition: TOP1 ports those readers.
3. docs/architecture.md: LB5 block "Known differences" item (1) rewritten (the flag is set since LB5b; DIVERGES, owner TOP1, removal condition).
4. test/core_lang/test_lb5b_prompt.jl (new, LK-only white box; swipl cannot read the flag). Nine goal rows pb01-pb09 run through the query API, the flag
   `ld.prompt_next` read after each, then a cleanup goal restores the standard alias. true: an input string stream as user_input (pb01), an OUTPUT stream as
   user_input (pb02; swipl answers ok for that setup, row lb103: upstream tests the alias index only). false: user_output captured+restored (pb03), user_error
   (pb04), a non-standard alias on an input stream (pb05) and on user_input itself (pb06), an input stream as user_output (pb07), a closed stream (pb08,
   existence error before the branch), alias(1) (pb09, error before the branch). Each goal must SUCCEED (error rows are `catch((G, fail), error(..), true)`).
   Fresh local data: flag false; two local data are independent. Non-vacuous guards: exactly pb01 and pb02 set it.
   UNVERIFIED (nothing was run): the existence_error shape of pb08 and the error of pb09 are written as `error(existence_error(_,_),_)` / `error(_,_)`;
   fmt may rewrap the CASES tuples.
5. tools/mutants/LB5B.py (new): 5 mutants, TARGETS = the one new file. A1 drops the set (KILL pb01, pb02); A2 `i >= 0` (pb03, pb04, pb07); A3 `i == 1`
   (pb01..pb03, pb07); A4 non-standard alias sets it (pb05, pb06); B1 constructor default true (fresh-data row). Validated with a throwaway python3 -I
   script: every `old` occurs exactly once, ids unique, targets hold @test/@testset: 5 mutants, 0 problems. Mutants branch name = `mutants/LB5B`.
6. Manifest rows: none (no function added). No `::Any` argument added in src.
7. The D-0164 term grep and the absence-phrase grep over the added lines: zero matches.

## Ready-for-gate list (gate agent)
a. `git diff --cached --stat` to confirm the staged tree; stage this file; the hook needs the marker: run the gate on the staged tree, THEN commit. Split into
   the intended commits only if the hook allows it after the gate (struct commit = src/pl-global.jl alone; the rest as the second); the hook refused a
   partial index, so one commit is the fallback (message: subject + 5-10 lines, struct change = cold daemon restart; the attribution line).
b. warm.sh fmt (the new test file and LB5B.py were never formatted), inventory (port_check), check (cold daemon start inside it), then
   test/core_lang/test_lb5b_prompt.jl on all three term types, test/core_lang/test_lb5_swipl.jl x3 (set_stream alias rows), test_s2a_swipl.jl,
   test_type_discipline.jl, the 4 alloc pins (a struct field: local_stack 386, query 365, zero_exports 239, rules 433 expected unchanged),
   tools/pkgtest_way.sh test/core_lang/test_lb5b_prompt.jl, branch-gate.
c. D-0164 grep over diff and message; push gate/<name>; mutants/LB5B at the SAME SHA (CI battery: 5 mutants, expect 5 killed).
d. Rebase: AUTOLOAD1's A2 appends autoload_nesting/autoload_loop to the same struct and constructor: the later one rebases (append-only conflict at the end
   of the field list and of the constructor). The status board row TOP1 may name `prompt_next` among what the toplevel reads (dispatcher's file; not edited here).

## Daemon
None used (edit-only); none started or stopped by me. Whether a daemon is free is the dispatcher's lanes.conf to say.
