# ORIGINAL: a differential of format_predicate/2 and current_format_predicate/2 (pl-fmt.c :249-325) and of the user directive in do_format
# (:596-621) against swipl at the pin; no swipl-devel counterpart.
# test/core_lang/test_format_predicate_swipl.jl — through a PROGRAM (the pattern of test_iri_hook_swipl.jl): test_format_predicate_swipl.pl
# holds the rows `tN(R)`; the kernel consults it and runs every row once, in order, and its lines are compared with `_FP_EXPECTED`,
# swipl 10.1.20's own (the driver below, `LC_ALL=C`, two byte-identical runs). When `swipl` is on PATH the same program is run live
# as well, so the pinned lines cannot go stale. The rows cover: the argument of a directive (none, `~3x`, the character form, `*`,
# negative, the colon), a call that needs more or fewer arguments than the list holds, the arities 1, 2 and 3, a procedure of
# another module, replacing a directive, a predicate that fails and one that throws, a predicate that writes a newline, the
# column machinery (`~t`, `~N|` with a user directive between), the built-in directives `~a` and `~c` taken over (last: the table
# is global state), and the errors of format_predicate/2 (type and instantiation errors, arity 0, a non-callable). The first argument
# of current_format_predicate/2 is answered as the pinned swipl answers (pl-fmt.c:300-304 at 18168e62): rows t19-t21 pin the answers
# to a bound character and t22 the answer to an unbound one.
# UNVERIFIED on the kernel: gate decides
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _FPT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

const _FP_PL = joinpath(@__DIR__, "test_format_predicate_swipl.pl")
const _FP_ROWS = 56

# the answer printed as `write_term(T, [quoted(false), ignore_ops(true)])` prints it
function _fp_pr(t)::String
    k = kind(t)
    if k === SYM
        return is_nil(t) ? "[]" : sym_text(t)
    elseif k === GND
        return string(lk_value(t))
    elseif k === VAR
        return "_"
    end
    return _fp_pr(child(t, 1)) * "(" *
           join([_fp_pr(child(t, i)) for i in 2:nchildren(t)], ",") * ")"
end

# the row `name`/1 on the loaded program: its first answer printed, `none` / `exception` when it has none / raises
function _fp_row(gd, ld, name::String)::String
    proc = LK.isCurrentProcedure(sym_key(lk_sym(_FPT, Symbol(name))), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$name undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(_FPT, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    out = "$name none"
    try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            out = "$name " * _fp_pr(lk_answers(ld, a)[1])
        elseif rc == LK.PL_S_EXCEPTION
            out = "$name exception"
        end
    finally
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return out
end

# swipl 10.1.20 (the pin's build), `LC_ALL=C swipl -q` on a driver that consults the program and prints `tN <answer>` per row, two identical runs
const _FP_EXPECTED = String[
    "t1 yes",
    "t2 yes(a<default|v>b)",
    "t3 yes(<3|v>)",
    "t4 yes(<122|v>)",
    "t5 yes(<5|v>)",
    "t6 yes(<-3|v>)",
    "t7 yes(<default|v>)",
    "t8 yes(<default|p><default|q>)",
    "t9 ex(format(not enough arguments))",
    "t10 ex(format(too many arguments))",
    "t11 yes",
    "t12 yes(ay(default)bc)",
    "t13 yes",
    "t14 yes((2,p,q))",
    "t15 ex(format(not enough arguments))",
    "t16 yes",
    "t17 yes({default|k})",
    "t18 yes(m2:fp_w/2,user:fp_x/2,user:fp_y/1,user:fp_z/3)",
    "t19 no",
    "t20 no",
    "t21 no",
    "t22 yes(ok)",
    "t23 yes(4)",
    "t24 yes",
    "t25 yes",
    "t26 yes(m2)",
    "t27 yes(ok)",
    "t28 ex(type_error(character,1.5))",
    "t29 ex(instantiation_error)",
    "t30 ex(type_error(character,xy))",
    "t31 yes",
    "t32 yes(<default|v>)",
    "t33 ex(domain_error(format_predicate,fp_noargs))",
    "t34 ex(type_error(callable,3))",
    "t35 ex(instantiation_error)",
    "t36 yes",
    "t37 yes([default|v])",
    "t38 yes(ok)",
    "t39 yes(5)",
    "t40 yes",
    "t41 no",
    "t42 yes",
    "t43 ball(oops)",
    "t44 yes",
    "t45 yes(ss)",
    "t46 [5-q,default-r]",
    "t47 yes",
    "t48 yes(abv/vcd)",
    "t49 yes( [default|v])",
    "t50 yes([default|v] end)",
    "t51 yes(p[default|q]r)",
    "t52 yes",
    "t53 yes([default|v])",
    "t54 yes",
    "t55 yes(<default|65><3|66>)",
    "t56 yes(m2:fp_w/2,user:fp_col/2,user:fp_fail/2,user:fp_seen/2,user:fp_x/2,user:fp_x/2,user:fp_x2/2,user:fp_x2/2,user:fp_y/1,user:fp_z/3)"
]

@testset "format_predicate/2, current_format_predicate/2 and the user directive of format/2,3 (pl-fmt.c)" begin
    gd = LK.PL_global_data{_FPT}()
    ld = LK.PL_local_data{_FPT}(gd)
    st, _ = LK.load_file!(gd, ld, _FP_PL)
    @test st === :ok
    @test isempty(gd.format_predicates)                          # no user directive before the first row
    got = String[_fp_row(gd, ld, "t$i") for i in 1:_FP_ROWS]
    @test length(got) == length(_FP_EXPECTED) == _FP_ROWS
    for i in eachindex(got)
        @test (i, got[i]) == (i, _FP_EXPECTED[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "format_predicate DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the pinned lines were checked)."
    else
        drv = raw"""
pr(T) :- write_term(T, [quoted(false), ignore_ops(true)]).
run(N) :- atom_concat(t, N, Name), G =.. [Name, R], format("~w ", [Name]),
    ( catch(findall(R, G, Rs), _, Rs = [exception]) -> true ; Rs = [none] ),
    forall(member(X, Rs), (pr(X), write(' '))), nl.
"""
        live = mktempdir() do d
            f = joinpath(d, "drv.pl")
            write(
                f,
                drv *
                ":- initialization((consult('$(_FP_PL)'), forall(between(1, $(_FP_ROWS), N), run(N)), halt)).\n"
            )
            read(pipeline(`$swipl -q $f`; stdin=devnull, stderr=devnull), String)
        end
        @test String[rstrip(l) for l in split(chomp(live), '\n'; keepempty=false)] ==
            _FP_EXPECTED
    end
end

# white box: the table after the rows (the characters in the order the rows set them; a replaced character keeps its place)
@testset "format_predicate/2: the table gd.format_predicates" begin
    gd = LK.PL_global_data{_FPT}()
    ld = LK.PL_local_data{_FPT}(gd)
    st, _ = LK.load_file!(gd, ld, _FP_PL)
    @test st === :ok
    for i in 1:_FP_ROWS
        _fp_row(gd, ld, "t$i")
    end
    tbl = gd.format_predicates
    @test [c for (c, _) in tbl] == Int.(collect("xyzmjulvac"))
    @test [p.definition.arity for (_, p) in tbl] == [2, 1, 3, 2, 2, 2, 2, 2, 2, 2]
    @test [sym_text(p.definition.name) for (_, p) in tbl] ==
        [
        "fp_x2",
        "fp_y",
        "fp_z",
        "fp_w",
        "fp_x",
        "fp_fail",
        "fp_col",
        "fp_seen",
        "fp_x2",
        "fp_x"
    ]
end
