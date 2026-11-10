# ORIGINAL: JETGW's mutant list — no swipl-devel counterpart.
# tools/mutants/JETGW2.py — the mutation battery of the JET gateway fix (audit D-0462): `S_read`'s one allowed runtime dispatch
# (`Sread_user` on a `Union{Nothing, AbstractLocalData}`, audit D-0433) is an inference barrier, `@max_methods 1` on `Sread_user`
# and its fallback method on the union (src/os/pl-file.jl), so inference does not enter `Sread_user` with the term type free;
# the call's result is asserted `::Int` (src/os/pl-stream.jl S_read). Run ONCE, in CI (.github/workflows/mutation.yml). The
# format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL:
#   SA = `sh:tools/mutate_sa_part.sh`: test/test_static_analysis.jl with its `jet_allowlist` part alone (the whole file is ~100 min
#   in one process, past a battery job's limit; the Evidence shards run the whole of it on the gate branch). In that part:
#   SA-BARRIER = `S_read`'s analysis with `skip_noncompileable_calls=false` holds the one allowed report (test/static_analysis_body.jl,
#   the testset "JET allowlist", the line after "THE BARRIER"); SA-FAMILY = the family pin `S_read` at 1 report (the loop over
#   JET_DISPATCH_FAMILY, `@test length(rs) == expected`).
#   TW = test/core_lang/test_top1b_wrap_swipl.jl: the testset "a freed registry entry reads -1" (`SIO_FERR` set after the read).
# TARGETS (audit D-0238): every test file that runs the mutated code and can see its effect. At run time `Sread_user` is reached only
# through a wrapped stream (`wrapIO`, set_prolog_IO/3): TW alone wraps one (test_top1_prompt_swipl.jl calls PL_write_prompt by hand,
# not through S_read). The barrier itself is seen only by JET: the jet_allowlist part (SA), and the per-entry dispatch check of the
# Evidence shards, whose entries reach S_read on main without a report in the default mode.
# Every `old` was counted EXACTLY once in its file at the WIP commit by a python3 -I script (no Julia ran). RE-FIT any `old` that
# `tools/warm.sh fmt` rewraps.
SA = "sh:tools/mutate_sa_part.sh"
TW = "test/core_lang/test_top1b_wrap_swipl.jl"
TARGETS = [SA, TW]
F = "src/os/pl-file.jl"
S = "src/os/pl-stream.jl"
MUTANTS = [
    dict(id="JETGW-1 no @max_methods on Sread_user: inference enters it from S_read with T free (KILL SA-BARRIER)",
         file=F, targets=TARGETS,
         old="Base.Experimental.@max_methods 1 function Sread_user end\n",
         new="function Sread_user end\n"),
    dict(id="JETGW-2 the fallback is narrowed back to ::Nothing: one method matches the abstract call, inferred with T free (KILL SA-BARRIER)",
         file=F, targets=TARGETS,
         old="    ::Union{Nothing, AbstractLocalData}, ::IOSTREAM, ::wrappedIO, ::Vector{UInt8}, ::Int,\n",
         new="    ::Nothing, ::IOSTREAM, ::wrappedIO, ::Vector{UInt8}, ::Int,\n"),
    dict(id="JETGW-3 a freed registry entry reads as end of file, not an error (KILL TW: SIO_FERR is not set)",
         file=F, targets=TARGETS,
         old="    ::Int\n)::Int = -1\n",
         new="    ::Int\n)::Int = 0\n"),
    dict(id="JETGW-4 S_read's call result is not asserted ::Int: the return conversion is a second dispatch (KILL SA-FAMILY)",
         file=S, targets=TARGETS,
         old="        return Sread_user(w.table[w.ld], s, w, mem, from, size)::Int   # (the barrier: src/os/pl-file.jl `Sread_user`)\n",
         new="        return Sread_user(w.table[w.ld], s, w, mem, from, size)   # (the barrier: src/os/pl-file.jl `Sread_user`)\n"),
]
