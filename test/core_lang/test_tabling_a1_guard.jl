# ORIGINAL: WHITE-BOX kill row of TAB1 TB4 mutant A1 (tools/mutants/TB4.py `TB4-A1`; audit D-0635 item 3 R13, D-0642 item 2): the recursion guard of
# `answer_completion(ld, scc)` (src/pl-tabling.jl, PORT of pl-tabling.c answer_completion: `if (LD->tabling.in_answer_completion) return true; /* not recursive! */`).
# NO PROLOG ROUTE FOUND in ~1050 random programs; WHITE-BOX: 12 of the ~1050 programs reached answer completion at all, and in none did a nested
# evaluation reach it a second time (the same situation as TB4-W1 and TB4-U6, which also use white-box rows). So the guard's state is put in place by
# hand, as the engine has it while `call_answer_completion` runs: `ld.tabling.in_answer_completion = true`, and a component with a worklist that IS an
# answer-completion candidate (undefined answer, a positive delay among its dependents, not answer completed).
#   * The guarded call must return `true` at once: no candidate is called and the flag stays set. With the mutant (`false && return true`) the candidate
#     IS called: `call_answer_completion` resets the flag to false and, the hand-built trie having no variant (`unify_skeleton` answers false), the call
#     answers false: each of those fails the row. (The database has the boot image, so `'$tabling':answer_completion/2` EXISTS and its lookup cannot be
#     the witness; the witness is the ANSWER of the call, read through ONE extractor `_a1_run` on every side.)
#   * The OTHER side, through the same builder and the same extractor: the very same state with the flag clear DOES call the candidate (it answers
#     `false`, the candidate path's answer here, not the `true` of a pass over no candidate: so the row is not a guard that cannot fail), and a worklist
#     that is not a candidate answers `true` with the flag set or clear.
#   * The Prolog side has no row (see above).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the component, worklist and trie are built by hand from kernel structs; the term type only parameterises them
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TA1 = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_ta1s(x) = lk_sym(_TA1, Symbol(x))

"An opaque child key for the number `k`: an atom-tagged word (never a variable key), as test_trie_swipl.jl's `_tk`."
_a1_tk(k::Integer)::UInt64 = LK.consTagged(k, LK.TAG_ATOM | LK.STG_STATIC)

"""
A database, a local data, a component and its one worklist `wl`, built by hand. `candidate` makes `wl` an answer-completion candidate
(pl-tabling.c is_ac_candidate_wl): an undefined answer, not answer completed, and a delay on an answer node whose delay info holds a
POSITIVE delay (a delay with a non-zero answer); otherwise `wl` is already answer completed, so it is no candidate.
"""
function _a1_state(candidate::Bool)
    gd = LK.PL_global_data{_TA1}()
    ld = LK.PL_local_data{_TA1}(gd)
    tr = LK.trie_create(_TA1)
    LK.trie_serial!(gd, tr)
    nid = LK.insert_child(tr, 1, _a1_tk(5))
    tr.nodes[nid].value = _a1_tk(6)                              # an answer with a value (has_positive_dl: `value == 0` is false)
    di = LK.delay_info(
        tr.serial, UInt32(0), [LK.delay_set(0, 1, UInt32(1))], [LK.delay(tr.serial, nid)]
    )
    LK.set_node_delayinfo(gd, tr, nid, di)
    wl = LK.tbl_worklist{_TA1}()
    wl.table = tr.serial
    wl.undefined = 1
    wl.answer_completed = !candidate
    push!(wl.delays, LK.delay(tr.serial, nid))
    c = LK.tbl_component{_TA1}()
    c.created_worklists = LK.worklist_set{LK.tbl_worklist{_TA1}}()
    push!(c.created_worklists.members, wl)
    return gd, ld, c, wl
end

"Run `answer_completion(ld, c)`: its answer, or the exception it raised (an exception is never `true` or `false`, so it fails every row that reads it)."
function _a1_run(ld::LK.PL_local_data{_TA1}, c::LK.tbl_component{_TA1})
    return try
        LK.answer_completion(ld, c)
    catch e
        e
    end
end

@testset "TB4-A1 white-box: answer_completion inside answer completion returns true at once (the recursion guard)" begin
    # the non-empty side: the state IS a candidate, so only the guard keeps the candidate from being called
    gd, ld, c, wl = _a1_state(true)
    @test LK.is_ac_candidate_wl(gd, wl)
    @test !wl.answer_completed && wl.undefined == 1 && length(wl.delays) == 1
    @test c.created_worklists.members[1] === wl
    @test !ld.tabling.in_answer_completion
    ld.tabling.in_answer_completion = true                 # call_answer_completion's `in_answer_completion = true`
    r = _a1_run(ld, c)
    @test r === true                                       # kills TB4-A1: the mutant calls the candidate (false, or an exception)
    @test ld.tabling.in_answer_completion                  # call_answer_completion resets it to false: not entered
    @test ld.tabling.component === nothing && !ld.tabling.has_scheduling_component
    @test LK.is_ac_candidate_wl(gd, wl)                    # the guarded call changed nothing about the candidate
end

@testset "TB4-A1 white-box: the same state with the flag clear calls the candidate (the row can fail)" begin
    gd, ld, c, wl = _a1_state(true)
    @test LK.is_ac_candidate_wl(gd, wl)
    @test !ld.tabling.in_answer_completion
    r = _a1_run(ld, c)
    @test r === false                                      # the candidate WAS called: call_answer_completion answers false (the trie has no variant)
    @test !ld.tabling.in_answer_completion                 # and it reset the flag
end

@testset "TB4-A1 white-box: a worklist that is no candidate is not called, flag set or clear" begin
    for flag in (false, true)
        gd, ld, c, wl = _a1_state(false)
        @test wl.answer_completed && wl.undefined == 1
        @test !LK.is_ac_candidate_wl(gd, wl)
        ld.tabling.in_answer_completion = flag
        @test _a1_run(ld, c) === true
        @test ld.tabling.in_answer_completion == flag
    end
end
