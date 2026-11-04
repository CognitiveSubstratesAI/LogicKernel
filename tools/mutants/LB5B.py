# ORIGINAL: LB5b's mutant list — an LK-only list.
# tools/mutants/LB5B.py — the mutation battery of LB5b (`LD->prompt.next`: src/pl-global.jl field `prompt_next`, set by pl-file.c
# set_stream/2's alias(user_input) branch at :2224-2225, src/os/pl-file.jl), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as LB5.py): `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `equivalent` and `targets`. Killed by test/core_lang/test_lb5b_prompt.jl (rows pb01-pb09 and the fresh-data row named in
# each id's KILL). Verdicts: written by the battery, not yet run. Every `old` was checked to occur exactly once at the writer's
# base (origin/main 18468130 plus the LB5b edits), a text count, no Julia.
# TARGETS (audit D-0238, brief of the LB5b writer): the one new file. The flag has exactly one reader, the new file's `ld.prompt_next`
# (nothing in the kernel writes a prompt: the readers are the toplevel's, status board row TOP1), so no other test file can tell a mutant of
# the flag from the original. Other files that run set_stream(S, alias(user_input)) (test_lb5_swipl.jl lb099, lb100, lb103; test_s2a_swipl.jl)
# read the stream's behaviour, never the flag, and are left out. test/core_lang/test_lb5b_prompt.jl holds @testset and @test.
# NOT LISTED (each with its reason):
#   * the field's type or position in the struct: a struct change, not a mutant of a statement.
PB = ["test/core_lang/test_lb5b_prompt.jl"]
TARGETS = PB
F = "src/os/pl-file.jl"
G = "src/pl-global.jl"
MUTANTS = [
    dict(id="LB5B-A1 set_stream alias(user_input) does not set the flag (KILL pb01, pb02)",
         file=F, targets=PB,
         old="            i == 0 && (ld.prompt_next = true)       # changed Sinput: prompt! (pl-file.c:2224-2225)\n",
         new="            nothing\n"),
    dict(id="LB5B-A2 every standard alias sets the flag: `i >= 0` (KILL pb03, pb04, pb07)",
         file=F, targets=PB,
         old="i == 0 && (ld.prompt_next = true)",
         new="i >= 0 && (ld.prompt_next = true)"),
    dict(id="LB5B-A3 the wrong standard stream sets the flag: `i == 1` (user_output) (KILL pb01, pb02, pb03, pb07)",
         file=F, targets=PB,
         old="i == 0 && (ld.prompt_next = true)",
         new="i == 1 && (ld.prompt_next = true)"),
    dict(id="LB5B-A4 a non-standard alias sets the flag (KILL pb05, pb06)",
         file=F, targets=PB,
         old="        aliasStream(gd, s, alias)\n        return true\n",
         new="        aliasStream(gd, s, alias)\n        ld.prompt_next = true\n        return true\n"),
    dict(id="LB5B-B1 the local data starts with the flag set (KILL the fresh-data rows)",
         file=G, targets=PB,
         old="        false                                   # prompt.next:",
         new="        true                                    # prompt.next:"),
]
