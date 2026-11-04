# G9 boot probe 2 (writer 10): needs a TEMPORARY run-tree-only edit of src/pl-qlf.jl addClauseWic: wrap assert_term! in
# try/catch, a NotPortedError pushed as (:probe, "<file>:<line> <error>") onto ld.messages and the clause = nothing (reverted after).
using LogicKernel
const LK = LogicKernel
let T = LK.Term{Union{Int64, Float64, String, BigInt, Rational{BigInt}}}
    gd = LK.setupProlog(T)
    ld = LK.PL_local_data{T}(gd)
    home = LK.sym_text(LK.current_prolog_flag_atom(gd, LK.mk_sym(T, :home)))
    t0 = time()
    rc = try
        LK.boot_from_source!(gd, ld, [joinpath(home, "boot", "init.pl")])
    catch e
        bt = catch_backtrace()
        println("EXC ", first(sprint(showerror, e), 400))
        for (i, fr) in enumerate(stacktrace(bt))
            i > 10 && break
            println("  ", first(string(fr), 200))
        end
        :exc
    end
    println("rc=", rc, " t=", round(time() - t0; digits=1), " nmsg=", length(ld.messages))
    np = 0
    for (k, m) in ld.messages
        if k === :probe
            np += 1
            np <= 40 && println("NP ", first(string(m), 260))
        end
    end
    println("NP total ", np)
    no = 0
    for (k, m) in ld.messages
        k === :probe && continue
        no += 1
        no <= 40 && println(k, " ", first(string(m), 260))
    end
    println("other total ", no)
    global _G9 = (gd, ld)
end
