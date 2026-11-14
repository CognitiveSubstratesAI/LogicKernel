# ORIGINAL: no swipl-devel counterpart. The kernel side of tools/swipl_tests_run.py (R2 acceptance item (c),
# audit D-0624/D-0625): ONE swipl-devel test file per process. It boots a database from boot/init.pl
# (PL_global_data{T}()), loads tools/swipl_tests_harness.pl, and queries
# `lk_swipl_tests:lk_run_test_file(File)`; the harness prints `LK-RESULT` lines.
#
#   julia --project=<repo> tools/swipl_tests_kernel.jl <abs path of the test file>
#
# Exit 0 whenever the harness ran to its end (the verdict is in the LK-RESULT lines, not the exit status);
# 3 when the harness itself would not load; 64 on a usage error. A Julia exception is printed as
# `LK-RESULT run-error` and exits 0 as well; the driver classifies by the lines, and treats a run with none as ERROR(load).
#
# UNVERIFIED: written without running Julia (a WRITER step); the calls are the README's ("Using it from Julia")
# and `load_file!`'s own (src/pl-wam.jl). The reference term type is the one used: a file's verdict does not depend on it.
using LogicKernel

const T = DefaultTerm

"The goal `lk_swipl_tests:lk_run_test_file('<file>')` as a term."
function _goal(file::String)::T
    call = mk_expr(T, T[mk_sym(T, :lk_run_test_file), mk_sym(T, Symbol(file))])
    return mk_expr(T, T[mk_sym(T, :(:)), mk_sym(T, :lk_swipl_tests), call])
end

function _main(args::Vector{String})::Int
    if length(args) != 1
        println(stderr, "usage: swipl_tests_kernel.jl <test file>")
        return 64
    end
    file = abspath(args[1])
    if !isfile(file)
        println("LK-RESULT not-runnable the test file is not on disk: ", file)
        return 0
    end
    harness = joinpath(@__DIR__, "swipl_tests_harness.pl")
    gd = LogicKernel.PL_global_data{T}()
    ld = LogicKernel.PL_local_data{T}(gd)
    status, _ = load_file!(gd, ld, harness)
    if status !== :ok
        println("LK-RESULT harness-error the harness did not load: ", status)
        return 3
    end
    try
        query_answers(ld, _goal(file); limit=1)
    catch e
        if e isa PrologException
            println("LK-RESULT run-error an uncaught Prolog exception left the harness")
        else
            println("LK-RESULT run-error ", replace(sprint(showerror, e), '\n' => ' '))
        end
    end
    flush(stdout)
    return 0
end

exit(_main(String.(ARGS)))
