# ORIGINAL: a differential of `~user` in expandVars (pl-os.c :1578-1600, the getpwnam branch) against swipl at the pin; no swipl-devel counterpart.
# test/files/test_expand_user_swipl.jl — through a PROGRAM (the pattern of test_format_predicate_swipl.jl): test_expand_user_swipl.pl holds the
# rows `tN(R)`; the kernel consults it and runs every row once, in order, and its lines are compared with `_EU_EXPECTED`, swipl 10.1.20's own
# (`LC_ALL=C swipl -q` on a driver that prints `tN <answer>`, two byte-identical runs, stderr empty). When `swipl` is on PATH the same program is
# run live as well, so the pinned lines cannot go stale. The user that exists is `root` (home `/root`): that is the Linux layout, and CI is
# ubuntu-24.04 only; `~user` is read through getpwnam with `pw_dir` at byte offset 32 of `struct passwd`, which is the Linux 64-bit layout, so
# the rows run on that platform (the offset function below is checked for the others). The rows cover: `~root` alone, with a path, with a
# doubled slash, a user that does not exist (the error and the fileerrors=false failure), the answer asked twice, `~root` then a missing
# user then `~root` again, and the file_name_variables flag with exists_directory/1.
# UNVERIFIED on the kernel: gate decides
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _EUT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

const _EU_PL = joinpath(@__DIR__, "test_expand_user_swipl.pl")
const _EU_ROWS = 15

# the answer printed as `write_term(T, [quoted(false), ignore_ops(true)])` prints it
function _eu_pr(t)::String
    k = kind(t)
    if k === SYM
        return is_nil(t) ? "[]" : sym_text(t)
    elseif k === GND
        return string(lk_value(t))
    elseif k === VAR
        return "_"
    end
    return _eu_pr(child(t, 1)) * "(" *
           join([_eu_pr(child(t, i)) for i in 2:nchildren(t)], ",") * ")"
end

# the row `name`/1 on the loaded program: its first answer printed, `none` / `exception` when it has none / raises
function _eu_row(gd, ld, name::String)::String
    proc = LK.isCurrentProcedure(sym_key(lk_sym(_EUT, Symbol(name))), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$name undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(_EUT, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    out = "$name none"
    try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            out = "$name " * _eu_pr(lk_answers(ld, a)[1])
        elseif rc == LK.PL_S_EXCEPTION
            out = "$name exception"
        end
    finally
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return out
end

# swipl 10.1.20 (the pin's build), `LC_ALL=C swipl -q`, two identical runs
const _EU_EXPECTED = String[
    "t1 yes(/root)",
    "t2 yes(/root/x)",
    "t3 yes(/root//x)",
    "t4 yes(/root/a/b)",
    "t5 ex(existence_error(user,nosuchuserxyz))",
    "t6 ex(existence_error(user,nosuchuserxyz))",
    "t7 yes(/root)",
    "t8 yes(/root/y)",
    "t9 no",
    "t10 no",
    "t11 yes",
    "t12 ex(existence_error(user,nosuchuserxyz))",
    "t13 no",
    "t14 no",
    "t15 yes"
]

@testset "~user in expandVars (pl-os.c getpwnam branch)" begin
    if Sys.islinux() && Sys.WORD_SIZE == 64
        gd = LK.PL_global_data{_EUT}()
        ld = LK.PL_local_data{_EUT}(gd)
        st, _ = LK.load_file!(gd, ld, _EU_PL)
        @test st === :ok
        got = String[_eu_row(gd, ld, "t$i") for i in 1:_EU_ROWS]
        @test length(got) == length(_EU_EXPECTED) == _EU_ROWS
        for i in eachindex(got)
            @test (i, got[i]) == (i, _EU_EXPECTED[i])
        end

        swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
        if swipl === nothing
            @info "~user DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the pinned lines were checked)."
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
                    ":- initialization((consult('$(_EU_PL)'), forall(between(1, $(_EU_ROWS), N), run(N)), halt)).\n"
                )
                read(pipeline(`$swipl -q $f`; stdin=devnull, stderr=devnull), String)
            end
            @test String[rstrip(l) for l in split(chomp(live), '\n'; keepempty=false)] ==
                _EU_EXPECTED
        end
    else
        @info "~user rows NOT RUN: the pw_dir offset is known on Linux 64-bit only."
    end
end

# the offset of `pw_dir`: known on Linux 64-bit only, `nothing` (the caller refuses by name) everywhere else
@testset "~user: the struct passwd offset is guarded (_passwd_dir_offset)" begin
    @test LK._passwd_dir_offset(true, 64) == 32
    @test LK._passwd_dir_offset(true, 32) === nothing
    @test LK._passwd_dir_offset(false, 64) === nothing
    @test LK._passwd_dir_offset(false, 32) === nothing
end

# the helper on its own: NULL (no such user) is `nothing`; root's home as the libc answers it
@testset "~user: _getpwnam_dir" begin
    if Sys.islinux() && Sys.WORD_SIZE == 64
        @test LK._getpwnam_dir("root", LK._passwd_dir_offset(true, 64)) == "/root"
        @test LK._getpwnam_dir("nosuchuserxyz", LK._passwd_dir_offset(true, 64)) === nothing
    end
end
