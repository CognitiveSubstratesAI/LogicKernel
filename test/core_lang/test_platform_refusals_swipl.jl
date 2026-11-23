# ORIGINAL: R2's LB5-LB7 gate — the refusals by name of pl-load.c and pl-apple.c (+ the pins of PushTty/PopTty, pl-os.c); no swipl-devel counterpart.
# test/core_lang/test_platform_refusals_swipl.jl — what the kernel answers TODAY to a predicate the pin's swipl does not define on Linux
# (`$activate_static_extension/1`: only a build with `O_STATIC_EXTENSIONS` has it; `apple_current_locale_identifier/1`: macOS only):
# a NotPortedError that names the predicate and the pin's lines, where swipl answers existence_error(procedure, Name/1). Each
# row is a KNOWN DIFFERENCE pinned with swipl's exact answer (the pin's own swipl, queried 2026-11-11), and checked against live swipl
# when it is on PATH. UNTESTED when written (nothing compiled, LB5-LB7 relay 11).
# INT-FIX-24: row p01 no longer meets a refusal. src/pl-load.jl is now the real static-extension form (JSON1: the `static_extensions`
# table, `pl_activate_static_extension1_va`), so `'$activate_static_extension'(foo)` is an ordinary Prolog error. The expected term
# is what that function returns for a name that is not in the table: `PL_error(ld, ERR_EXISTENCE, foreign_extension, A1)`, i.e.
# `error(existence_error(foreign_extension, foo), _)` (pl-load.jl:58; test_json_native_swipl.jl checks the same for `nosuch`).
# swipl's own answer in the pin (built without static extensions) is still existence_error(procedure, ...): the live comparison stays.
using Test, LogicKernel

const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}, Bool})
_tls(x) = lk_sym(_TL, Symbol(x))

# the cases: id, goal, the name the kernel's refusal carries, the pin lines its `what` holds, the owner step, the pin's swipl answer,
# and `nothing` (a refusal: NotPortedError) or the (type, object) of the existence_error the kernel now answers
const _PR_CASES = [
    (
        "p01", "'\$activate_static_extension'(foo)", "activate_static_extension",
        "pl-load.c:450-540", "LB5-LB7",
        "existence_error(procedure,'\$activate_static_extension'/1)",
        ("foreign_extension", "foo")      # the kernel's own answer since JSON1: existence_error(foreign_extension, foo), no refusal
    ),
    (
        "p02", "apple_current_locale_identifier(_)", "apple_current_locale_identifier",
        "pl-apple.c:56-79", "APPLE1",
        "existence_error(procedure,apple_current_locale_identifier/1)",
        nothing                          # still a NotPortedError
    )
]

"The exception the kernel raises running `goal` (a call of a predicate that is refused by name), or `nothing`."
function _pr_kernel(goal::String)
    f = joinpath(mktempdir(), "pr.pl")
    write(f, "t_pr(R) :- ( $goal ), R = done.\n")
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    st === :ok || return ErrorException("load")
    proc = LK.isCurrentProcedure(sym_key(_tls("t_pr")), 1, LK.MODULE_user(gd))
    proc === nothing && return ErrorException("undefined")
    try
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        rc = LK.PL_next_solution(gd, ld, qid)
        res = rc == LK.PL_S_EXCEPTION ? lk_answer(ld, LK.PL_exception(ld, qid)) : nothing
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        return res
    catch e
        return e
    end
end

"swipl's answer to `goal`: the printed error formal of `catch(Goal, error(E, _), true)`."
function _pr_swipl(goal::String)::String
    d = mktempdir()
    f = joinpath(d, "drv.pl")
    write(
        f,
        ":- initialization((catch(($goal), error(E, _), true), print(E), nl, halt)).\n"
    )
    return strip(read(pipeline(`swipl -q $f`; stderr=devnull), String))
end

@testset "the refusals by name of pl-load.c and pl-apple.c (known differences)" begin
    for (id, goal, name, pin, step, swipl_says, kernel_ext) in _PR_CASES
        @testset "$id $name" begin
            err = _pr_kernel(goal)
            if kernel_ext !== nothing
                # a Prolog error term (the exception of the query), not a thrown refusal: error(existence_error(Type, Obj), _)
                @test err isa _TL
                if err isa _TL
                    f = child(err, 2)
                    @test sym_text(child(f, 1)) == "existence_error"
                    @test sym_text(child(f, 2)) == kernel_ext[1] &&
                        sym_text(child(f, 3)) == kernel_ext[2]
                end
            else
                @test err isa LK.NotPortedError              # the kernel names the predicate (swipl: existence_error)
            end
            if err isa LK.NotPortedError
                @test kind(err.culprit) === SYM && sym_text(err.culprit) == name
                @test err.step == step
                @test occursin(name, err.what)
                @test occursin(pin, err.what)                # the pin's lines are in the text
            end
            swipl =
                get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
            if swipl !== nothing
                @test _pr_swipl(goal) == swipl_says          # swipl's own answer, live
            end
        end
    end
    @test allunique(first.(_PR_CASES)) && length(_PR_CASES) == 2
end
