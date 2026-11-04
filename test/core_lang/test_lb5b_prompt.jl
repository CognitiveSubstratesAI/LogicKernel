# ORIGINAL: a white-box test of LB5b's `LD->prompt.next` (`ld.prompt_next`, src/pl-global.jl), set by set_stream/2 (src/os/pl-file.jl)
# test/core_lang/test_lb5b_prompt.jl — upstream pl-file.c:2224-2225, in set_stream's `alias(name)` branch:
#     if ( (i=standardStreamIndexFromName(alias)) >= 0 ) { setStandardStream(i, s); if ( i == 0 ) LD->prompt.next = true; ... }
#   * swipl cannot read `LD->prompt.next` from Prolog, so the rows are LK-only, without a swipl differential. The goals are the
#     ones test_lb5_swipl.jl (lb097-lb106) already compares with swipl (the stream predicates' answers); this file reads the flag
#     after each, with `ld.prompt_next`.
#   * One database, one local data; before each row the flag is cleared; the goal runs (it must SUCCEED: an error row catches the
#     expected error and fails otherwise, so a row that raised nothing does not pass); the flag is read; then the row's cleanup
#     goal puts the standard alias back (a row never leaves user_input captured).
#   * Expected flag: true for EVERY stream installed as user_input (an input stream, and an output stream: swipl answers `ok` for
#     lb103 and the kernel does the same, upstream tests the alias index only); false for user_output, user_error, a non-standard
#     alias, an error, and a closed stream.
#   * DIVERGES (docs/architecture.md, LB5 block, "Known differences" (1)): the flag is only SET; upstream's readers (Sread_user,
#     PL_write_prompt) are the toplevel's (status board row TOP1).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through set_stream/2
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _PB = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_pbs(x) = lk_sym(_PB, Symbol(x))

# (id, goal, the flag after the goal, the cleanup goal)
const _PB_CASES = [
    (
        "pb01",
        raw"open_string(x, S), set_stream(user_input, alias(lb5b_saved)), set_stream(S, alias(user_input))",
        true,
        raw"set_stream(lb5b_saved, alias(user_input))"
    ),   # an input string stream becomes user_input
    (
        "pb02",
        raw"current_output(O), set_stream(user_input, alias(lb5b_saved)), set_stream(O, alias(user_input))",
        true,
        raw"set_stream(lb5b_saved, alias(user_input))"
    ),   # an OUTPUT stream becomes user_input (swipl: ok, row lb103): upstream tests the alias index only
    (
        "pb03",
        raw"current_output(OO), with_output_to(string(_), ( current_output(M), set_stream(M, alias(user_output)), set_stream(OO, alias(user_output)) ))",
        false,
        raw"true"
    ),   # user_output captured and restored: index 1
    (
        "pb04",
        raw"set_stream(user_error, alias(lb5b_saved_err)), with_output_to(string(_), ( current_output(M), set_stream(M, alias(user_error)), set_stream(lb5b_saved_err, alias(user_error)) ))",
        false,
        raw"true"
    ),   # user_error captured and restored: index 2
    (
        "pb05",
        raw"open_string(x, S), set_stream(S, alias(lb5b_in))",
        false,
        raw"true"
    ),   # a non-standard alias of an input stream
    (
        "pb06",
        raw"set_stream(user_input, alias(lb5b_ui))",
        false,
        raw"true"
    ),   # a non-standard alias of the user_input stream itself: the alias index is -1
    (
        "pb07",
        raw"open_string(x, S), current_output(OO), set_stream(S, alias(user_output)), set_stream(OO, alias(user_output))",
        false,
        raw"true"
    ),   # an input stream installed as user_output (swipl: ok, row lb104), then put back
    (
        "pb08",
        raw"open_string(x, S), close(S), catch((set_stream(S, alias(user_input)), fail), error(existence_error(_, _), _), true)",
        false,
        raw"true"
    ),   # a closed stream: the existence error is raised before the alias branch
    (
        "pb09",
        raw"current_output(O), catch((set_stream(O, alias(1)), fail), error(_, _), true)",
        false,
        raw"true"
    )   # alias(1): PL_get_atom_ex raises before the alias branch
]

"The program: one `t_<id>/1` (the goal) and one `c_<id>/1` (its cleanup) per case."
function _pb_file()::String
    text = join([
        "t_$(id)(_) :- $g.\nc_$(id)(_) :- $c.\n" for (id, g, _, c) in _PB_CASES
    ])
    f = joinpath(mktempdir(), "lb5b_rows.pl")
    write(f, text)
    return f
end

"Call `name/1` once in `user`: `:succeeded`, `:failed` or `:exception` (not `:true`/`:false`: those parse as Bool literals) (the goal's bindings are discarded; its effects on the streams stay)."
function _pb_call(gd, ld, name::String)::Symbol
    proc = LK.isCurrentProcedure(sym_key(_pbs(name)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return :undefined
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_PB, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        :succeeded
    elseif rc == LK.PL_S_EXCEPTION
        :exception
    else
        :failed
    end
end

@testset "LD->prompt.next: set by set_stream(S, alias(user_input)) (pl-file.c:2224-2225)" begin
    gd = LK.PL_global_data{_PB}()
    ld = LK.PL_local_data{_PB}(gd)
    @test ld.prompt_next === false                      # a fresh local data: zero, as pl-global.c leaves it
    st, _ = LK.load_file!(gd, ld, _pb_file())
    @test st === :ok
    # The standard streams are opened the first time one is asked for (initIO's DIVERGES, src/os/pl-file.jl): a goal whose FIRST
    # stream use is `set_stream(user_input, alias(_))` raises existence_error(stream, user_input) on a fresh local data (measured
    # 2026-11-04; upstream opens them at start-up). Open them here, as swipl's start-up has done; the flag rows are not about that.
    LK._initIO(ld)
    flags = Bool[]
    for (id, _, want, _) in _PB_CASES
        ld.prompt_next = false
        @test _pb_call(gd, ld, "t_$id") === :succeeded       # the goal ran to its end (an error row raised its error)
        push!(flags, ld.prompt_next)
        @test ld.prompt_next === want
        @test _pb_call(gd, ld, "c_$id") === :succeeded       # the cleanup put the standard alias back
    end
    # not vacuous: both outcomes occur, and the rows that must set it are the ones that install user_input
    @test count(flags) == 2
    @test count(!, flags) == length(_PB_CASES) - 2
    @test [id for ((id, _, _, _), f) in zip(_PB_CASES, flags) if f] == ["pb01", "pb02"]
end

@testset "LD->prompt.next: a second local data is independent" begin
    gd = LK.PL_global_data{_PB}()
    ld1 = LK.PL_local_data{_PB}(gd)
    ld2 = LK.PL_local_data{_PB}(gd)
    ld1.prompt_next = true
    @test ld2.prompt_next === false
end
