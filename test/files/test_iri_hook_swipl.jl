# ORIGINAL: a differential of the IRI hook (pl-file.c call_iri_hook, iri_hook_va, iri_hook; its callers in os/pl-files.c) against swipl at the pin
# test/files/test_iri_hook_swipl.jl — time_file/2, size_file/2, access_file/2, exists_file/1 and exists_directory/1 on an IRI (`foo://x`),
# through a PROGRAM (the pattern of test_lb2b_swipl.jl): test_iri_hook_swipl.pl registers a handler of the scheme `foo` as boot/iri.pl's
# `register_iri_scheme/3` directive does (a clause of `'$iri':iri_scheme_handler/2`) and holds the rows `tN(R)`; the kernel consults it and runs
# every row once, in order, and its lines are compared with `_IRI_EXPECTED`, swipl 10.1.20's own (the driver below, two byte-identical
# runs). When `swipl` is on PATH the same program is run live as well, so the pinned lines cannot go stale. The rows cover: the three
# answers (float, integer, Boolean) and what a wrong one raises (`type_error` of PL_get_float_ex, PL_get_int64_ex, PL_get_bool_ex), a
# failing and a throwing handler, the `access(Mode)` mapping (write, append, execute, search, exist, file, directory), an unknown scheme
# (`existence_error(iri_scheme, bar)`), and last what the handler saw: the action, and the IRI as a STRING.
# UNVERIFIED on the kernel: gate decides
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _IT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

const _IRI_PL = joinpath(@__DIR__, "test_iri_hook_swipl.pl")
const _IRI_ROWS = 46

# the answer printed as `write_term(T, [quoted(true), ignore_ops(true)])` prints it (atoms of the rows need no quotes)
function _iri_pr(t)::String
    k = kind(t)
    if k === SYM
        return is_nil(t) ? "[]" : sym_text(t)
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "\"" * String(v) * "\""
        return string(v)
    elseif k === VAR
        return "_"
    end
    return _iri_pr(child(t, 1)) * "(" * join([_iri_pr(child(t, i)) for i in 2:nchildren(t)], ",") * ")"
end

# the row `name`/1 on the loaded program: its first answer printed, `none` / `exception` when it has none / raises
function _iri_row(gd, ld, name::String)::String
    proc = LK.isCurrentProcedure(sym_key(lk_sym(_IT, Symbol(name))), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$name undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(_IT, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    out = "$name none"
    try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            out = "$name " * _iri_pr(lk_answers(ld, a)[1])
        elseif rc == LK.PL_S_EXCEPTION
            out = "$name exception"
        end
    finally
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return out
end

# swipl 10.1.20 (the pin's build), `swipl -q` on a driver that consults the program and prints `tN <answer>` per row, two identical runs
const _IRI_EXPECTED = String[
    "t1 yes(12.5)",
    "t2 yes(3.0)",
    "t3 no",
    "t4 ex(type_error(float,abc))",
    "t5 ball(oops)",
    "t6 yes(42)",
    "t7 ex(type_error(integer,1.5))",
    "t8 ex(type_error(integer,abc))",
    "t9 yes",
    "t10 no",
    "t11 ex(type_error(bool,maybe))",
    "t12 no",
    "t13 yes",
    "t14 yes",
    "t15 yes",
    "t16 yes",
    "t17 yes",
    "t18 yes",
    "t19 yes",
    "t20 no",
    "t21 yes",
    "t22 no",
    "t23 ex(existence_error(iri_scheme,bar))",
    "t24 ex(existence_error(iri_scheme,bar))",
    "t25 ex(existence_error(iri_scheme,bar))",
    "t26 ex(existence_error(iri_scheme,bar))",
    "t27 yes",
    "t28 ex(domain_error(io_mode,badmode))",
    "t29 -(time,\"foo://x\")",
    "t30 -(time,\"foo://int\")",
    "t31 -(size,\"foo://x\")",
    "t32 -(size,\"foo://big\")",
    "t33 -(access(read),\"foo://x/yes\")",
    "t34 -(access(read),\"foo://bad\")",
    "t35 -(access(exist),\"foo://x/yes\")",
    "t36 -(access(file),\"foo://x/yes\")",
    "t37 -(access(file),\"foo://x/no\")",
    "t38 -(access(directory),\"foo://x/yes\")",
    "t39 -(access(directory),\"foo://x/no\")",
    "t40 none",
    "t41 -(access(write),\"foo://x/yes\")",
    "t42 -(access(write),\"foo://x/yes\")",
    "t43 -(access(execute),\"foo://x/yes\")",
    "t44 -(access(execute),\"foo://x/yes\")",
    "t45 no",
    "t46 no"
]

@testset "iri_hook: time_file, size_file, access_file, exists_file, exists_directory on an IRI (pl-file.c iri_hook, pl-files.c)" begin
    gd = LK.PL_global_data{_IT}()
    ld = LK.PL_local_data{_IT}(gd)
    st, _ = LK.load_file!(gd, ld, _IRI_PL)
    @test st === :ok
    got = String[_iri_row(gd, ld, "t$i") for i in 1:_IRI_ROWS]
    @test length(got) == length(_IRI_EXPECTED) == _IRI_ROWS
    for i in eachindex(got)
        @test (i, got[i]) == (i, _IRI_EXPECTED[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "iri_hook DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the pinned lines were checked)."
    else
        drv = raw"""
pr(T) :- write_term(T, [quoted(true), ignore_ops(true)]).
run(N) :- atom_concat(t, N, Name), G =.. [Name, R], format("~w ", [Name]),
    ( catch(findall(R, G, Rs), _, Rs = [exception]) -> true ; Rs = [none] ),
    forall(member(X, Rs), (pr(X), write(' '))), nl.
"""
        live = mktempdir() do d
            f = joinpath(d, "drv.pl")
            write(
                f,
                drv * ":- initialization((consult('$(_IRI_PL)'), forall(between(1, $(_IRI_ROWS), N), run(N)), halt)).\n"
            )
            read(pipeline(`$swipl -q $f`; stdin=devnull, stderr=devnull), String)
        end
        @test String[rstrip(l) for l in split(chomp(live), '\n'; keepempty=false)] == _IRI_EXPECTED
    end
end

# `iri_hook` before the `$iri` handler exists is upstream's sysError; IRI_OPEN is the other site's (left refused): white-box rows on the function
@testset "iri_hook: the operations the callers use answer a value or nothing" begin
    gd = LK.PL_global_data{_IT}()
    ld = LK.PL_local_data{_IT}(gd)
    st, _ = LK.load_file!(gd, ld, _IRI_PL)
    @test st === :ok
    ld.GD = gd                                                  # a query sets it; this row calls the function itself
    l0 = ld.lTop
    @test LK.iri_hook(ld, "foo://x", LK.IRI_TIME) === 12.5
    @test LK.iri_hook(ld, "foo://x", LK.IRI_SIZE) === 42
    @test LK.iri_hook(ld, "foo://x/yes", LK.IRI_ACCESS, LK.ACCESS_READ) === true
    @test LK.iri_hook(ld, "foo://x/no", LK.IRI_ACCESS, LK.ACCESS_READ) === false
    @test LK.iri_hook(ld, "foo://fail", LK.IRI_TIME) === nothing
    @test_throws ErrorException LK.iri_hook(ld, "foo://x", LK.IRI_OPEN)
    @test ld.lTop == l0                                         # every call closed its foreign frame, also the one that raised
end
