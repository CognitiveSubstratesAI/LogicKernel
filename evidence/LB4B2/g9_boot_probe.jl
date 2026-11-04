# G9 boot probe (writer 9): send with /home/shivaji1012/code/lk-lb4b2-run/tools/warm.sh send <this file>
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
            i > 8 && break
            println("  ", first(string(fr), 200))
        end
        :exc
    end
    println("rc=", rc, " t=", round(time() - t0; digits=1), " nmsg=", length(ld.messages))
    for (k, m) in Iterators.take(ld.messages, 25)
        println(k, " ", first(string(m), 300))
    end
    global _G9 = (gd, ld)
end
