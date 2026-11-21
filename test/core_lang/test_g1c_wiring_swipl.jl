# ORIGINAL: G1-C's wiring of the stack collector into the VM, run against the kernel; the answers of the rows are swipl's (the .out, 10.1.20).
# allow-new-artifact: G1-C (D2), the test of the VM's safe points (docs/g1gc_safe_points.md table A "VM" rows, table C), after test/core_lang/test_g1gc_safe_points.jl
# test/core_lang/test_g1c_wiring_swipl.jl — what G1-C wired, checked on the code (pin 18168e62):
#   * THE ROWS: test_g1c_wiring_swipl.pl's w1-w5 (garbage_collect/0, a 200000-iteration allocating loop, a catch after a deep recursion, the
#     statistics keys, a counted collection) give the .out's answers with `ld.gc_force` off and on; swipl's live when on PATH;
#   * THE VM SITES: w2 under `gc_force` reaches the collector at the `@ENSURE_GLOBAL_SPACE` sites (pl-vmi.c:220-235, ALLOW_GC): a VMI's name is
#     recorded in `ld.gc_safe_hits`, every recorded name is a `SITE` line of the table, and the answer is swipl's;
#   * THE SIGNALS (table C): `raiseGcSignal!` (PL_raise) sets the bit and ALERT_SIGNAL, `handleSignals`/`PL_handle_signals` (pl-setup.c) run
#     `gc_handler` once and clear both; `_dispatch_gc_signal` refuses another number;
#   * THE EXCEPTION POINTS: `resumeAfterException` (pl-wam.c:1966-1977) and `exceptionUnwindGC` (pl-wam.c:1990-1999), `_outofstack_gc`;
#   * `makeMoreStackSpace` (pl-gc.c:4622-4672): the spare, a collection, the local stack's growth, the raise.
#   * THE TWO CALLERS' RETRIES (G1C-KILL, white-box, no .pl row): copy_term_refs' retry after a collection (mutant G1C-K1) and the compiler's
#     CHECK_INTERRUPT at ci.progress 32768 with SIG_GC pending, served by assert_term!'s PL_handle_signals (mutant G1C-P1). A query would
#     serve a raised signal at its first call port (pl-vmi.c:1969), before the compiler sees it, so P1 asserts from Julia; K1's state (garbage
#     below the copy, the inference counter, a limit between the copy's cost with and without the garbage) is built on a bare local data:
#     a Prolog row cannot hold it, the VM's own safe points collect the garbage before copy_term/2 runs.
#   * THE VM'S SIGNAL POINTS (G1-C8, white-box, mutants G1C-A1..A3): a SIG_GC raised from Julia before a solution is served by the one
#     point the run passes next: depart_alerted at a call port (pl-vmi.c:1958-1984), deep_backtrack at a clause retry (pl-vmi.c:6932-6939),
#     I_FREDO at a foreign redo (pl-vmi.c:4765-4773).
# The kill rows are `@test`s INSIDE testsets (a top-level failing `@test` gives no verdict in CI mode).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _GP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

_gcodes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_GP, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _gcodes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _gcodes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _gcodes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _W_ROOT = joinpath(@__DIR__, "..", "..")
const _W_PL = joinpath(@__DIR__, "test_g1c_wiring_swipl.pl")
const _W_OUT = joinpath(@__DIR__, "test_g1c_wiring_swipl.out")
const _W_DOC = joinpath(_W_ROOT, "docs", "g1gc_safe_points.md")
const _W_NAMES = ["w1", "w2", "w3", "w4", "w5"]

# (the table's and the code's extractors: test_g1gc_safe_points.jl's, verbatim)
# the table's `SITE <name> <file> <upstream>` lines: (name, file)
function doc_sites(text::String)::Vector{Tuple{String, String}}
    return [
        (String(m[1]), String(m[2])) for
        m in eachmatch(r"^SITE (\w+) (\S+) (\S+)\s*$"m, text)
    ]
end

# the VM's sites (G1-C6): a code line of `src` (not a comment) calling `@ENSURE_GLOBAL_SPACE(n, :<name>, ..)`, the macro that passes ALLOW_GC
# with its second argument as the site (src/pl-wam.jl, pl-vmi.c:220-235): (name, file)
function src_vm_sites(src::String)::Vector{Tuple{String, String}}
    out = Tuple{String, String}[]
    for f in sort(readdir(src))
        endswith(f, ".jl") || continue
        # over the whole file text: the Blue formatter wraps a long call so that the site name is on the next line (pl-wam.jl: T_FUNCTOR,
        # H_RFUNCTOR, H_RLIST); `^[^#\n]*` keeps a comment line out
        text = read(joinpath(src, f), String)
        for m in eachmatch(r"^[^#\n]*@ENSURE_GLOBAL_SPACE\(\s*[^,]+,\s*:(\w+)"m, text)
            push!(out, (String(m[1]), "src/" * f))
        end
    end
    return out
end

# a fresh kernel with `path` consulted: `(gd, ld, "ok" or "exc <ball>")`
function _tp_load(::Type{T}, path::String) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * enc(ball::T))
end

# the driver's line for the row `name`/1 (every answer, at most 100): the name, then each solution
function _tp_row(
    gd::LK.PL_global_data{T}, ld::LK.PL_local_data{T}, name::String
)::String where {T}
    proc = LK.isCurrentProcedure(sym_key(lk_sym(T, Symbol(name))), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$name undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 100
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                try
                    enc(
                        mk_expr(T, T[lk_sym(T, Symbol(name)), lk_answers(ld, (a:a)...)...])
                    )
                catch e
                    "export-error " * first(sprint(showerror, e), 80)
                end
            )
            rc == LK.PL_S_LAST && break
        elseif rc == LK.PL_S_EXCEPTION
            push!(sols, "exception")
            break
        else
            break
        end
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return "$name" * join(" " .* sols)
end

# every row on a fresh kernel (`force` = ld.gc_force, set after the program is loaded): the lines (`ok`, then each row), each row's recorded
# sites, and the number of collections that ran
function run_rows(path::String, names::Vector{String}; force::Bool)
    gd, ld, st = _tp_load(_GP, path)
    ld.gc_force = force
    lines = String[st]
    hits = Vector{Vector{Symbol}}()
    ncoll = Int(ld.gc.stats.totals.collections)
    for name in names
        empty!(ld.gc_safe_hits)
        push!(lines, _tp_row(gd, ld, name))
        push!(hits, copy(ld.gc_safe_hits))
    end
    return lines, hits, Int(ld.gc.stats.totals.collections) - ncoll
end

# the driver swipl runs to print its lines (the .out is its output; the text of test_trie_gen_swipl.jl's DRIVER)
const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(100, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'))
end

@testset "G1-C: the rows w1-w5 answer as swipl, gc_force off and on" begin
    expected = String.(readlines(_W_OUT))
    names = unique([
        String(m[1]) for m in eachmatch(r"^(w\d+)\(R\) :-"m, read(_W_PL, String))
    ])
    @test names == _W_NAMES
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test !any(l -> occursin(r"export-error|undefined| exception$", l), expected)
    off_lines, off_hits, off_coll = run_rows(_W_PL, names; force=false)
    on_lines, on_hits, on_coll = run_rows(_W_PL, names; force=true)
    @test length(off_lines) == length(expected) == length(on_lines)
    for i in eachindex(expected)
        @test (i, off_lines[i]) == (i, expected[i])                   # the flag off: swipl's answers
        @test (i, on_lines[i]) == (i, expected[i])                    # the flag on: the same answers
    end
    @test all(isempty, off_hits)                                      # the flag off: nothing recorded
    @test off_coll > 0 && on_coll > 0                                 # garbage_collect/0 (w1, w3, w5) collects either way
    table = Set(Symbol(first(s)) for s in doc_sites(read(_W_DOC, String)))
    @test !isempty(table)
    for i in eachindex(names)
        @test (names[i], all(s -> s in table, on_hits[i])) == (names[i], true)   # every recorded site is a SITE line
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "G1-C DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_W_PL, names) == expected
    end
end

# w2 calls no foreign ALLOW_GC site (arg/3, is/2 pass none): under gc_force every collection of its run is a VM site's, entered when the global
# stack's vector is full (`hasStackSpace` false); the vector starts at 1024 cells and doubles when an allocation passes its end (`_growGlobalStack!`), and fills again.
@testset "G1-C: w2 under gc_force collects at the VM's @ENSURE_GLOBAL_SPACE sites, each recorded by its VMI name" begin
    vmtable = Set(Symbol(first(s)) for s in src_vm_sites(joinpath(_W_ROOT, "src")))
    table = Set(Symbol(first(s)) for s in doc_sites(read(_W_DOC, String)))
    @test length(vmtable) == 15 && issubset(vmtable, table)
    expected = String.(readlines(_W_OUT))
    lines, hits, coll = run_rows(_W_PL, ["w2"]; force=true)
    @test lines == expected[[1, 3]]                                   # ok, w2 40000200000
    @test coll > 0                                                    # the collector ran inside the loop
    @test !isempty(hits[1])
    @test !isempty(intersect(Set(hits[1]), vmtable))                  # at a VM site
    @test all(s -> s in table, hits[1])
    @test count(s -> s in vmtable, hits[1]) == length(hits[1])        # and only there (no foreign site in w2)
end

@testset "G1-C: raiseGcSignal!, handleSignals and PL_handle_signals (pl-fli.c PL_raise, pl-setup.c:1193-1270)" begin
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    LK.allocGlobalCells!(ld, 4)                                       # garbage for the collection
    @test ld.gc.sig_pending == 0 && !LK.is_signalled(ld)
    @test LK.PL_handle_signals(ld) == 0                               # nothing pending: 0, nothing runs
    @test LK.handleSignals(ld) == 0
    c0 = Int(ld.gc.stats.totals.collections)
    @test LK.raiseGcSignal!(ld, LK.SIG_GC)
    @test ld.gc.sig_pending == UInt64(1) << (LK.SIG_GC - LK.SIG_PROLOG_OFFSET)
    @test (ld.alerted & LK.ALERT_SIGNAL) != 0 && LK.is_signalled(ld) &&
        LK.pendingGcSignal(ld, LK.SIG_GC)
    @test LK.handleSignals(ld) == 1                                   # one signal handled
    @test ld.gc.sig_pending == 0 && !LK.is_signalled(ld)
    @test (ld.alerted & LK.ALERT_SIGNAL) == 0                         # updateAlerted after `done`
    @test Int(ld.gc.stats.totals.collections) == c0 + 1               # gc_handler ran the collector once
    # through PL_handle_signals
    @test LK.raiseGcSignal!(ld, LK.SIG_GC)
    @test LK.PL_handle_signals(ld) == 1
    @test ld.gc.sig_pending == 0 && (ld.alerted & LK.ALERT_SIGNAL) == 0
    @test Int(ld.gc.stats.totals.collections) == c0 + 2
    # an exception pending: -1, the signal kept
    @test LK.raiseGcSignal!(ld, LK.SIG_GC)
    ld.exception_term = ld.exception_bin
    @test LK.handleSignals(ld) == -1
    @test LK.pendingGcSignal(ld, LK.SIG_GC)
    @test Int(ld.gc.stats.totals.collections) == c0 + 2
    ld.exception_term = 0
    @test LK.clearGcSignal!(ld, LK.SIG_GC) && !LK.is_signalled(ld)
    # dispatch_signal: only the collector's two signals have a handler here
    @test_throws LK.NotPortedError LK._dispatch_gc_signal(ld, LK.SIG_PROLOG_OFFSET + 20)
end

@testset "G1-C: resumeAfterException and exceptionUnwindGC (pl-wam.c:1966-1977, :1990-1999); _outofstack_gc" begin
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    @test LK._outofstack_gc(ld, :global) && LK._outofstack_gc(ld, :trail)   # init_stack(.., gc): global and trail true
    @test !LK._outofstack_gc(ld, :local)                                      # local false
    # SIG_GC pending: the out-of-stack's gced_sizes reset, considerGarbageCollect true -> trim requested for the next time
    ld.gc.global_policy.gced_size = 123
    ld.gc.trail_policy.gced_size = 45
    ld.exception_processing = true
    ld.outofstack = :global
    ld.trim_stack_requested = false
    LK.raiseGcSignal!(ld, LK.SIG_GC)
    LK.resumeAfterException(ld, true, :global)
    @test ld.gc.global_policy.gced_size == 0 && ld.gc.trail_policy.gced_size == 0
    @test ld.trim_stack_requested                                     # LD->trim_stack_requested = true (next time with resize)
    @test !ld.exception_processing && ld.outofstack === nothing && ld.exception_term == 0
    LK.clearGcSignal!(ld, LK.SIG_GC)
    # no signal, no out-of-stack, no inference since the last collection: no collection due -> trimStacks(false) clears the request
    ld.trim_stack_requested = true
    ld.gc.inferences = ld.statistics.inferences
    LK.resumeAfterException(ld, true, nothing)
    @test !ld.trim_stack_requested
    @test !ld.exception_processing && ld.outofstack === nothing
    # exceptionUnwindGC, no collection due (an exception processed: considerGarbageCollect's (*) does not fire; the bare stacks are below
    # SMALLSTACK): the gced_sizes reset, the trim requested, nothing collected
    ld.gc.global_policy.gced_size = 7
    ld.gc.trail_policy.gced_size = 8
    ld.trim_stack_requested = false
    ld.exception_processing = true
    c0 = Int(ld.gc.stats.totals.collections)
    LK.exceptionUnwindGC(ld)
    @test ld.gc.global_policy.gced_size == 0 && ld.gc.trail_policy.gced_size == 0
    @test ld.trim_stack_requested
    @test Int(ld.gc.stats.totals.collections) == c0
    # with SIG_GC pending a collection (GC_EXCEPTION) runs (gc_stat_end! then writes the gced_sizes) and clears the signal
    ld.trim_stack_requested = false
    LK.raiseGcSignal!(ld, LK.SIG_GC)
    LK.exceptionUnwindGC(ld)
    # the request is SERVED by the collection: garbageCollect ends in `trimStacks(LD->trim_stack_requested)` (pl-gc.c:4549) and trimStacks
    # starts with `LD->trim_stack_requested = false` (pl-setup.c:1715), pin 18168e62: so the flag is false after a collected unwind
    @test !ld.trim_stack_requested
    @test Int(ld.gc.stats.totals.collections) == c0 + 1
    @test !LK.pendingGcSignal(ld, LK.SIG_GC)                          # garbageCollect clears SIG_GC
    ld.exception_processing = false
end

@testset "G1-C: makeMoreStackSpace (pl-gc.c:4622-4672): spare, collection, growth, raise" begin
    # ALLOW_GC with an inference since the last collection: the collector runs, true
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    LK.allocGlobalCells!(ld, 4)
    ld.statistics.inferences = ld.gc.inferences + 1
    c0 = Int(ld.gc.stats.totals.collections)
    @test LK.makeMoreStackSpace(ld, LK.GLOBAL_OVERFLOW, LK.ALLOW_GC)
    @test Int(ld.gc.stats.totals.collections) == c0 + 1
    @test ld.exception_term == 0 && ld.outofstack === nothing
    # ALLOW_SHIFT only, GLOBAL_OVERFLOW: no collection, nothing grows (the global stack's limit), the overflow is raised
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    ld.statistics.inferences = ld.gc.inferences + 1
    c0 = Int(ld.gc.stats.totals.collections)
    @test !LK.makeMoreStackSpace(ld, LK.GLOBAL_OVERFLOW, LK.ALLOW_SHIFT)
    @test Int(ld.gc.stats.totals.collections) == c0
    @test ld.exception_term != 0 && ld.outofstack === :global && ld.exception_processing
    # ALLOW_GC but no inference since the last collection: no collection; nothing grows: raised
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    ld.gc.inferences = ld.statistics.inferences
    c0 = Int(ld.gc.stats.totals.collections)
    @test !LK.makeMoreStackSpace(ld, LK.GLOBAL_OVERFLOW, LK.ALLOW_GC)
    @test Int(ld.gc.stats.totals.collections) == c0
    @test ld.outofstack === :global
    # an exception being processed with the global spare kept: the spare is released, true, no collection
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    @test ld.global_spare != 0
    ld.exception_processing = true
    ld.statistics.inferences = ld.gc.inferences + 1
    c0 = Int(ld.gc.stats.totals.collections)
    @test LK.makeMoreStackSpace(ld, LK.GLOBAL_OVERFLOW, LK.ALLOW_GC)
    @test ld.global_spare == 0 && Int(ld.gc.stats.totals.collections) == c0
    # LOCAL_OVERFLOW with ALLOW_SHIFT: the local stack grows (growStacks(1, 0, 0)), true. A fresh stack has room, and grow_stacks keeps the size
    # while the stack has room (pl-gc.c:5369-5500, nextStackSize pl-gc.c:5271: newsize == oldsize, nothing grows, the overflow is raised), as
    # growStacks! does (src/pl-gc.jl:171 `need <= lMax`): the row first fills the local stack so that the growth path is reached
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    ld.lTop = ld.lMax                                          # the stack is full: the 1 position asked for (growStacks(1, 0, 0)) does not fit
    before = ld.lMax + ld.local_spare
    @test LK.makeMoreStackSpace(ld, LK.LOCAL_OVERFLOW, LK.ALLOW_SHIFT)
    @test ld.lMax + ld.local_spare > before
    @test ld.exception_term == 0
end

# G1C-K1: copy_term/2's retry. The garbage (4000 unbound cells nothing refers to) lies BELOW the term; the limit is set so that the copy
# fits the stacks only once the garbage is collected: the first `do_copy_term_cells` pass runs out (rc < 0), the frame is discarded, and
# `makeMoreStackSpace(GLOBAL_OVERFLOW, ALLOW_SHIFT | ALLOW_GC)` collects (an inference since the last collection) and the copy runs again
# (pl-copyterm.c:847). Without ALLOW_GC the overflow is raised and the copy fails.
function _k1_build(m::Int, garbage::Int)
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    LK.allocGlobalCells!(ld, garbage)                                 # the garbage, below the term
    f = lk_sym(_GP, :f)
    # g(f(V1), ..., f(Vm)): not ground, so copy_term/2 (COPY_SHARE) copies every f/1 and g/m
    t = mk_expr(
        _GP,
        _GP[
            lk_sym(_GP, :g), (mk_expr(_GP, _GP[f, lk_var(_GP, UInt64(i))]) for i in 1:m)...
        ]
    )
    from = LK.PL_new_term_ref(ld)
    to = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, from + 1, t, LK.PutVarMap())
    while ld.gTop + 1 >= length(ld.gstack)                            # the vector not exactly full: the
        LK.allocGlobalCells!(ld, 1)                                   # entry check (`gTop + 1` past it) would collect
    end
    ld.statistics.inferences = ld.gc.inferences + 1                   # an inference since the last collection
    return ld, from, to
end

@testset "G1C-K1: copy_term_refs collects and retries when the copy overflows the limit with garbage below" begin
    opts = LK.cp_options(LK.COPY_SHARE | LK.COPY_ATTRS)
    margin = 2000
    ld1, from1, to1 = _k1_build(3000, 4000)                           # unlimited: the copy's cost
    g0 = ld1.gTop
    @test LK.copy_term_refs(ld1, from1, to1, opts)
    cost = ld1.gTop - g0
    @test cost > 4 * margin                                           # the entry check (`+ 1`) is far from the limit
    ld, from, to = _k1_build(3000, 4000)                              # the same state
    ld.stacks_limit = LK._stacks_in_use(ld, 0) + cost - margin        # the copy overflows; with the garbage gone it fits
    @test LK._stacks_in_use(ld, 1) <= ld.stacks_limit                 # the entry's ensureGlobalSpace passes: no collection there
    @test LK._stacks_in_use(ld, cost) > ld.stacks_limit
    c0 = Int(ld.gc.stats.totals.collections)
    @test LK.copy_term_refs(ld, from, to, opts)                       # the retry's collection made room: true
    @test Int(ld.gc.stats.totals.collections) == c0 + 1               # makeMoreStackSpace's collection, once
    @test ld.exception_term == 0 && ld.outofstack === nothing && !ld.exception_processing
end

# G1C-P1: the compiler's CHECK_INTERRUPT (pl-comp.c:971-974). SIG_GC is raised, then assert_term! is called from Julia (no query: a query
# serves the signal at its first call port) with a clause whose head has 40252 compound nodes (p/1, g/250, 250 h/160, 40000 f/1), so the
# analysis' progress passes 32768: the compile returns CHECK_INTERRUPT, assert_term! serves the signal (PL_handle_signals: one collection)
# and compiles again.
@testset "G1C-P1: assert_term! serves SIG_GC raised before a clause the compiler walks past progress 32768" begin
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    LK.PL_open_foreign_frame(ld)
    LK.allocGlobalCells!(ld, 4)                                       # garbage for the collection
    f = mk_expr(_GP, _GP[lk_sym(_GP, :f), lk_sym(_GP, :a)])
    h = mk_expr(_GP, _GP[lk_sym(_GP, :h), fill(f, 160)...])
    g = mk_expr(_GP, _GP[lk_sym(_GP, :g), fill(h, 250)...])
    t = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, t + 1, mk_expr(_GP, _GP[lk_sym(_GP, :p), g]), LK.PutVarMap())
    @test LK.raiseGcSignal!(ld, LK.SIG_GC) && LK.is_signalled(ld)
    c0 = Int(ld.gc.stats.totals.collections)
    @test LK.assert_term!(gd, ld, t, LK.CL_END) !== nothing
    @test ld.gc.sig_pending == 0 && !LK.is_signalled(ld)              # served inside assert_term!
    @test (ld.alerted & LK.ALERT_SIGNAL) == 0
    @test Int(ld.gc.stats.totals.collections) == c0 + 1               # PL_handle_signals' collection, once
end

# G1C-A1..A3: the VM's signal points a query reaches from Julia. SIG_GC is raised before a call of PL_next_solution, and the program makes
# ONE point the first the run passes before the next answer:
#   * depart_alerted (pl-vmi.c:1958-1984): raised before the first solution, the query's call port (`depart_or_retry_continue`, alerted);
#   * deep_backtrack (pl-vmi.c:6932-6939): raised between a_wrap/1's two solutions. The retry is a_two/1's second clause; the query's frame is
#     a_wrap's, not the choice point's, so shallow_backtrack passes it to deep_backtrack; the clause is a fact and `true` compiles to I_TRUE
#     (src/pl-comp.jl, ATOM_true), so only I_TRUE and I_EXIT follow the retry;
#   * I_FREDO (pl-vmi.c:4765-4773): raised between a_btw/1's two solutions, the redo of the foreign between/3 (PL_FA_NONDETERMINISTIC),
#     reached through deep_backtrack's CHP_JUMP arm, which jumps straight to it; again only I_TRUE follows.
# Each row on a fresh kernel; after the answer that follows the raise the signal is gone and ONE collection ran (gc_handler).
const _A_PL_TEXT = """
a_two(1).
a_two(2).
a_wrap(X) :- a_two(X), true.
a_btw(X) :- between(1, 3, X), true.
"""

# `name(X)` on a fresh kernel with _A_PL_TEXT loaded, SIG_GC raised before the `raise_at`-th call of PL_next_solution; per call:
# (rc, sig_pending after it, collections since the load)
function _a_query(path::String, name::String, raise_at::Int, nsol::Int)
    gd, ld, st = _tp_load(_GP, path)
    proc = LK.isCurrentProcedure(sym_key(lk_sym(_GP, Symbol(name))), 1, LK.MODULE_user(gd))
    c0 = Int(ld.gc.stats.totals.collections)
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_GP, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    out = Tuple{Int, UInt64, Int}[]
    for i in 1:nsol
        i == raise_at && LK.raiseGcSignal!(ld, LK.SIG_GC)
        rc = LK.PL_next_solution(gd, ld, qid)
        push!(out, (Int(rc), ld.gc.sig_pending, Int(ld.gc.stats.totals.collections) - c0))
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return st, proc !== nothing, out
end

@testset "G1C-A: a raised SIG_GC is served at depart_alerted, deep_backtrack and I_FREDO" begin
    T_ = Int(LK.PL_S_TRUE)
    L_ = Int(LK.PL_S_LAST)
    mktempdir() do d
        path = joinpath(d, "g1c_a.pl")
        write(path, _A_PL_TEXT)
        # depart_alerted (G1C-A1): raised before the first call, served at the query's call port
        st, found, out = _a_query(path, "a_wrap", 1, 2)
        @test st == "ok" && found
        @test out[1] == (T_, UInt64(0), 1)                            # served before the first answer, one collection
        @test out[2] == (L_, UInt64(0), 1)                            # a_two(2), the last clause: the last answer
        # deep_backtrack (G1C-A3): raised between the answers, served at the retry of a_two/1's second clause
        st, found, out = _a_query(path, "a_wrap", 2, 2)
        @test st == "ok" && found
        @test out[1] == (T_, UInt64(0), 0)                            # before the raise: 0 collections
        @test out[2] == (L_, UInt64(0), 1)
        # I_FREDO (G1C-A2): raised between the answers, served at between/3's redo
        st, found, out = _a_query(path, "a_btw", 2, 2)
        @test st == "ok" && found
        @test out[1] == (T_, UInt64(0), 0)
        @test out[2][2:3] == (UInt64(0), 1)
        @test out[2][1] == T_                                         # X = 2: between/3 keeps its choice for 3
    end
end
