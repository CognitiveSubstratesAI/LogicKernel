# ORIGINAL: a differential of pl-prof.c's predicates (profiler/2, '$profile'/4, '$prof_statistics'/8, '$prof_node'/8, '$prof_sibling_of'/2,
# '$prof_procedure_data'/8, '$prof_exact_ok'/1, reset_profiler/0) against swipl at the pin; test/core_lang/test_coverage_swipl.jl's harness
# test/core_lang/test_prof_swipl.jl — through a PROGRAM: test_prof_swipl.pl holds the rows, each a predicate `tN(R)`; the kernel consults it and
# enumerates every solution of every row, and its lines are compared with test_prof_swipl.out — swipl 10.1.20's own (the pin's), printed by the
# driver below. When `swipl` is on PATH the .out is checked against a live run as well. The rows are STATE ONLY (a state that never profiled: the
# status atoms, the argument checks, the statistics, the node and procedure lookups of an empty tree, reset_profiler): collecting needs signals
# and clocks, a named refusal in the kernel (step PROF1), so a row never starts the profiler. KERNEL-ONLY testsets: the rows `kN` read a
# hand-built call tree (nodes added with `new_call_node!`), the rows `krN` end in the named refusal, and `node_redos`' clamp is checked on
# nodes. UNTESTED when written: nothing compiled (lane F, pl-prof).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _PF_PL = joinpath(@__DIR__, "test_prof_swipl.pl")
const _PF_OUT = joinpath(@__DIR__, "test_prof_swipl.out")

# the rows' names, in the order of the program (`t` for the swipl rows, `k` for the kernel-only tree rows, `kr` for the refusals)
_pf_names(prefix::String) =
    unique([
        String(m[1]) for
        m in eachmatch(Regex("^(" * prefix * "\\d+)\\(R\\) :-", "m"), read(_PF_PL, String))
    ])
# the kernel's lines: `ok` (the program loaded), then each row's name and solutions; `setup` runs after the load, before the rows.
# Returns the lines and the run's local data (the last row's query stays open after a named refusal: the data is thrown away).
function kernel_run(
    ::Type{T}, path::String, names::Vector{String}, setup::Function=(gd, ld) -> nothing
)::Tuple{Vector{String}, LK.PL_local_data{T}} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    setup(gd, ld)
    out = [st === :ok ? "ok" : "exc " * enc(ball::T)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        notported = false
        while (n += 1) <= 100
            rc = try
                LK.PL_next_solution(gd, ld, qid)
            catch e
                e isa LK.NotPortedError || rethrow()
                notported = true
                break
            end
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(T, T[_tls(T, name), lk_answers(ld, (a:a)...)...]))
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
        if notported
            push!(out, "$name notported")    # the query stays open: the caller reads `ld` and drops it
            return out, ld
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, ld
end
kernel_lines(
    ::Type{T}, path::String, names::Vector{String}, setup::Function=(gd, ld) -> nothing
) where {T} =
    first(kernel_run(T, path, names, setup))

# the driver swipl runs to print its lines (the .out is its output)
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
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# ONE extractor for both sides: how many times a line holds an atom (as `enc` writes it)
_pf_count(lines, word) = sum(l -> length(findall(_codes(word), l)), lines; init=0)

@testset "PROF: pl-prof.c's state predicates == swipl's answers (the .out), through a program" begin
    names = _pf_names("t")
    expected = String.(readlines(_PF_OUT))
    # not a vacuous agreement: the .out has `ok` and a line per row, and the rows' own evidence is in it
    @test names == ["t$i" for i in 0:37]
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    body = expected[2:end]
    for w in (
        "type_error",
        "instantiation_error",
        "domain_error",
        "profile_status",
        "profile_node",
        "failed",
        "true"
    )
        @test _pf_count(body, w) >= 1
    end
    kl, ld = kernel_run(_TL, _PF_PL, names)
    @test length(kl) == length(expected)
    for w in (
        "type_error",
        "instantiation_error",
        "domain_error",
        "profile_status",
        "profile_node",
        "failed",
        "true"
    )
        @test _pf_count(kl[2:min(end, length(expected))], w) == _pf_count(body, w)
    end
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end
    @test ld.profile.active == LK.PROF_INACTIVE && isempty(ld.profile.node_table)

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "PROF DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_PF_PL, names) == expected               # the .out is swipl's, still
    end
end

# the kernel-only hand-built tree: 1 = pf/1 (3 calls, 2 exits, 2 fails, 5 ticks) with the children 2 and 3 = pg/1
_a(s) = "a" * _codes(s)
_c(f, args...) = "c" * _codes(f) * "/$(length(args))(" * join(args, ",") * ")"
_row(name, sols...) = name * join(" " .* [_c(name, s) for s in sols])
_pn(k) = _c("\$prof_node", "i$k")

function _pf_tree!(gd::LK.PL_global_data{T}, ld::LK.PL_local_data{T}) where {T}
    defof(name) =
        LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd)).definition
    a = LK.new_call_node!(ld, defof("pf"), LK.PROF_TYPE_DEFAULT)
    b = LK.new_call_node!(ld, defof("pg"), LK.PROF_TYPE_DEFAULT)
    c = LK.new_call_node!(ld, defof("pg"), LK.PROF_TYPE_DEFAULT)
    @assert (a, b, c) == (1, 2, 3)
    na, nb, nc = (LK.prof_node_at(ld, i)::LK.call_node{T} for i in (a, b, c))
    na.calls, na.fails, na.exits, na.ticks, na.siblings = 3, 2, 2, 5, b
    nb.parent, nb.calls, nb.exits, nb.ticks, nb.next = a, 1, 1, 7, c
    nc.parent, nc.calls, nc.exits, nc.ticks = a, 2, 2, 3
    ld.profile.roots = a
    ld.profile.samples = 4
    ld.profile.ticks = 15
    return nothing
end

@testset "PROF: a hand-built call tree is read by the predicates" begin
    names = _pf_names("k")
    @test names == ["k$i" for i in 0:12]
    kl, ld = kernel_run(_TL, _PF_PL, names, _pf_tree!)
    exp = [
        "ok",
        _row("k0", _c("n", _a("pf"), "i3", "i1", "i2", "i0", "i5", "i10")),       # calls, redos = exits+fails-calls, exits, recur, ticks, sibling ticks
        _row("k1", _c("n", _a("pg"), "i1", "i0", "i1", "i0", "i7", "i0")),
        _row("k2", _pn(1)),                                                       # the roots
        _row("k3", _pn(2), _pn(3)),                                               # the children of 1, in the chain's order
        _row("k4", _pn(1)),                                                       # the parent of 3
        _row("k5", _a("failed")),                                                 # 1 has no parent
        _row(
            "k6",
            _c(
                "d", "i5", "i10", "i3", "i1", "i2",
                _c(
                    "[|]",
                    _c("node", _a("<spontaneous>"), "i0", "i5", "i10", "i3", "i1", "i2"),
                    "nil"
                ),
                _a("pg"), "i0", "i10", "i0", "i3", "i0", "i3"
            )
        ),
        _row(
            "k7",
            _c(
                "d", "i10", "i0", "i3", "i0", "i3", "nil", _a("pf"), "i0", "i10", "i0",
                "i3", "i0", "i3"
            )
        ),
        _row("k8", _a("failed")),
        _row(
            "k9", _c("s", "i4", "i15", "i0", "f0.0", "i3", "i0", _a("false"), _a("false"))
        ),
        _row("k10", _c("r", "i0", "i0", "i0", "i0")),
        _row("k11", _c("err", _c("type_error", _a("profile_node"), _pn(1)))),
        _row("k12", _a("failed"))
    ]
    @test kl == exp
end

# the collection is a named refusal (swipl starts its profiler there): what ran before the refusal stays
@testset "PROF: starting the profiler and reading the exact clock are refused by name" begin
    for row in ("kr0", "kr1", "kr2", "kr3", "kr4", "kr5")
        kl, ld = kernel_run(_TL, _PF_PL, [row])
        @test kl == ["ok", "$row notported"]
        @test ld.profile.active == LK.PROF_INACTIVE
    end
    # profiler/2 without '$profile'/4 gives the sample period its default before the refusal
    kl, ld = kernel_run(_TL, _PF_PL, ["kr0"])
    @test ld.profile.sample_period == LK.DEFAULT_SAMPLE_PERIOD
    # '$profile'/4 sets its options and resets the data before it starts: rate 100 is a 10000 usec period, ports `false`
    kl, ld = kernel_run(_TL, _PF_PL, ["kr3"])
    @test ld.profile.sample_period == 10000 && ld.profile.ports_control == LK.PROFC_FALSE
    kl, ld = kernel_run(_TL, _PF_PL, ["kr5"])
    @test ld.profile.sample_period == 250000 && ld.profile.ports_control == LK.PROFC_TRUE
end

# a node's redos are its exits and fails beyond its calls (a call still running counts none)
@testset "PROF: node_redos clamps at zero" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    n = LK.call_node{_TL}(nothing, LK.PROF_TYPE_DEFAULT)
    @test LK.node_redos(n) == 0
    n.calls, n.exits, n.fails = 5, 1, 0
    @test LK.node_redos(n) == 0
    n.calls, n.exits, n.fails = 1, 3, 1
    @test LK.node_redos(n) == 3
    n.calls, n.exits, n.fails = 2, 1, 1
    @test LK.node_redos(n) == 0
    # a freed tree leaves no live node
    a = LK.new_call_node!(ld, nothing, LK.PROF_TYPE_DEFAULT)
    @test LK.prof_node_at(ld, a) !== nothing && LK.prof_node_at(ld, 0) === nothing &&
        LK.prof_node_at(ld, a + 1) === nothing
    ld.profile.roots = a
    LK.freeProfileData(ld)
    @test ld.profile.nodes == 0 && LK.prof_node_at(ld, a) === nothing
end

# ── the call tree's builders (pl-prof.c's second half: profCall, profResumeParent, profExit, profFail, lookback): kernel-only, no caller in
# the VM, so the testsets drive them. The nodes are indexes (1 = the first node made); `_nc` reads (calls, exits, fails, recur) of one.
function _pf_env(::Type{T}, ports::Int) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, _ = LK.load_file!(gd, ld, _PF_PL)
    @assert st === :ok
    defof(name) =
        LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd)).definition
    ld.profile.ports_control = ports
    return gd, ld, defof("pf"), defof("pg")
end
_nc(ld, i) = (n=LK.prof_node_at(ld, i); (n.calls, n.exits, n.fails, n.recur))

@testset "PROF: the tree builders, ports_control FALSE (no exits or fails counted)" begin
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_FALSE)
    @test LK.profCall(ld, pf) == 1 && ld.profile.current == 1 && ld.profile.roots == 1 &&
        ld.profile.nodes == 1
    @test LK.profCall(ld, pf) == 1 && _nc(ld, 1) == (1, 0, 0, 1)                 # direct recursion: the same node, `recur`
    @test LK.profCall(ld, pg) == 2 && ld.profile.current == 2
    @test LK.prof_node_at(ld, 2).parent == 1 && LK.prof_node_at(ld, 1).siblings == 2
    LK.profExit(ld, 2)
    @test ld.profile.current == 1 && _nc(ld, 2) == (1, 0, 0, 0)                  # FALSE: the exit is not counted
    @test LK.profCall(ld, pg) == 2 && _nc(ld, 2) == (2, 0, 0, 0) && ld.profile.nodes == 2   # the sibling is found again
    LK.profFail(ld, 1)
    @test ld.profile.current == 1 && _nc(ld, 2)[3] == 0                          # FALSE: the fail is not counted
    @test !ld.profile.accounting && ld.profile.samples == 0                      # not exact: no clock, no sample
end

@testset "PROF: the tree builders, ports_control TRUE: exits and fails" begin
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_TRUE)
    @test LK.profCall(ld, pf) == 1 && LK.profCall(ld, pg) == 2
    LK.profExit(ld, 2)
    @test ld.profile.current == 1 && _nc(ld, 2) == (1, 1, 0, 0) &&
        _nc(ld, 1) == (1, 0, 0, 0)
    LK.profExit(ld, 1)                                                           # the exit of a root: resumes nothing
    @test ld.profile.current == 0 && _nc(ld, 1) == (1, 1, 0, 0)
    @test LK.profCall(ld, pf) == 1 && _nc(ld, 1) == (2, 1, 0, 0) && ld.profile.nodes == 2   # a root is found again
    @test LK.profCall(ld, pg) == 2 && _nc(ld, 2) == (2, 1, 0, 0)
    LK.profFail(ld, 1)                                                           # 2 failed back to its parent's choicepoint
    @test ld.profile.current == 1 && _nc(ld, 2) == (2, 1, 1, 0) && _nc(ld, 1)[3] == 0
    LK.profFail(ld, 0)                                                           # 1 failed with no choicepoint left
    @test ld.profile.current == 0 && _nc(ld, 1) == (2, 1, 1, 0)
end

@testset "PROF: the siblings and the roots are chains: a node is found behind others" begin
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_TRUE)
    t0 = LK.isCurrentProcedure(sym_key(_tls(_TL, "t0")), 1, LK.MODULE_user(gd)).definition
    @test LK.profCall(ld, pf) == 1 && LK.profCall(ld, pg) == 2
    LK.profExit(ld, 2)
    @test LK.profCall(ld, t0) == 3 && LK.prof_node_at(ld, 3).next == 2 &&
        LK.prof_node_at(ld, 1).siblings == 3
    LK.profExit(ld, 3)
    @test LK.profCall(ld, pg) == 2 && _nc(ld, 2) == (2, 1, 0, 0) && ld.profile.nodes == 3     # found behind t0
    LK.profExit(ld, 2)
    LK.profExit(ld, 1)
    @test ld.profile.current == 0
    @test LK.profCall(ld, pg) == 4 && LK.prof_node_at(ld, 4).next == 1 &&
        ld.profile.roots == 4 && ld.profile.nodes == 4
    LK.profExit(ld, 4)
    @test LK.profCall(ld, pf) == 1 && _nc(ld, 1) == (2, 1, 0, 0) && ld.profile.nodes == 4    # a root found behind another
end

@testset "PROF: accounting is on between begin and end" begin
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_TRUE)
    @test !ld.profile.accounting
    LK.prof_accounting_begin(ld)
    @test ld.profile.accounting && ld.profile.samples == 0
    LK.prof_accounting_end(ld)
    @test !ld.profile.accounting
end

@testset "PROF: the tree builders, ports_control CLASSIC: exits and fails counted as TRUE" begin
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_CLASSIC)
    @test LK.profCall(ld, pf) == 1 && LK.profCall(ld, pg) == 2
    LK.profExit(ld, 2)
    @test _nc(ld, 2) == (1, 1, 0, 0) && ld.profile.current == 1
    LK.profFail(ld, 0)
    @test _nc(ld, 1)[3] == 1 && ld.profile.current == 0
end

@testset "PROF: indirect recursion is folded unless ports_control is TRUE" begin
    # pf -> pg -> pf -> pg: under CLASSIC the second pg is the first one again (its recursion counted), under TRUE a node of its own
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_CLASSIC)
    @test LK.profCall(ld, pf) == 1 && LK.profCall(ld, pg) == 2
    @test LK.profCall(ld, pf) == 3 && LK.prof_node_at(ld, 3).parent == 2         # the root 1 has no parent: no fold yet
    @test LK.profCall(ld, pg) == 2 && ld.profile.current == 2 &&
        _nc(ld, 2) == (1, 0, 0, 1) && ld.profile.nodes == 3
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_TRUE)
    @test LK.profCall(ld, pf) == 1 && LK.profCall(ld, pg) == 2 && LK.profCall(ld, pf) == 3
    @test LK.profCall(ld, pg) == 4 && ld.profile.current == 4 && ld.profile.nodes == 4
    @test LK.prof_node_at(ld, 4).parent == 3 && _nc(ld, 2) == (1, 0, 0, 0)
end

@testset "PROF: a predicate with P_NOPROFILE leaves the tree alone; a stale node pointer is ignored" begin
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_TRUE)
    pg.flags |= LK.P_NOPROFILE
    @test LK.profCall(ld, pg) == 0 && ld.profile.nodes == 0 && ld.profile.current == 0 &&
        ld.profile.roots == 0
    @test LK.profCall(ld, pf) == 1
    @test LK.profCall(ld, pg) == 1 && ld.profile.nodes == 1 && ld.profile.current == 1   # the current node, nothing made
    @test LK.profCall(ld, pf) == 1 && _nc(ld, 1) == (1, 0, 0, 1)
    LK.profResumeParent(ld, 99)                                                  # not a node: ignored whole
    LK.profExit(ld, 99)
    LK.profExit(ld, 0)
    @test ld.profile.current == 1 && _nc(ld, 1) == (1, 0, 0, 1)
    LK.profResumeParent(ld, 0)                                                   # a null node is a node-less parent: valid
    @test ld.profile.current == 0 && _nc(ld, 1) == (1, 1, 0, 1)
end

@testset "PROF: lookback walks the parent chain; profSetHandle" begin
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_TRUE)
    @test LK.profCall(ld, pf) == 1 && LK.profCall(ld, pg) == 2 && LK.profCall(ld, pf) == 3
    @test LK.lookback(ld, 3, 1) && LK.lookback(ld, 3, 3) && LK.lookback(ld, 2, 1)
    @test !LK.lookback(ld, 1, 3) && !LK.lookback(ld, 1, 2) && !LK.lookback(ld, 0, 1) &&
        !LK.lookback(ld, 3, 0)
    LK.profFailToCP(ld, 3, 1)                                                    # 3 and 2 failed, 1 is the common ancestor
    @test _nc(ld, 3)[3] == 1 && _nc(ld, 2)[3] == 1 && _nc(ld, 1)[3] == 0
    LK.profFailToCP(ld, 1, 1)                                                    # already there: nothing fails
    @test _nc(ld, 1)[3] == 0
    n = LK.prof_node_at(ld, 3)
    LK.profSetHandle(n, pg)
    @test n.handle === pg
end

@testset "PROF: the exact modes run up to the clock and are refused there, by name" begin
    for mode in (LK.PROF_WALL_EXACT, LK.PROF_CPU_EXACT)
        gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_TRUE)
        ld.profile.active = mode
        @test_throws LK.NotPortedError LK.profCall(ld, pf)
        @test ld.profile.samples == 1 && ld.profile.nodes == 0               # the sample was counted, the clock refused first
        @test_throws LK.NotPortedError LK.prof_accounting_end(ld)
        @test_throws LK.NotPortedError LK.prof_charge(ld, 0, true)
    end
    gd, ld, pf, pg = _pf_env(_TL, LK.PROFC_TRUE)
    ld.profile.active = LK.PROF_CPU
    @test LK.profCall(ld, pf) == 1 && ld.profile.samples == 0                    # a sampled mode never reads the clock here
    for f in (
        LK.prof_clock,
        LK.prof_mono_ns,
        LK.prof_thread_cpu_ns,
        LK.prof_clock_per_ns,
        LK.thread_prof_ticks,
        LK.prof_convert_clock
    )
        @test_throws LK.NotPortedError f(ld)
    end
    @test_throws LK.NotPortedError LK.prof_close_window(ld, 0, nothing, 0)
    @test_throws LK.NotPortedError LK.PL_register_profile_type(ld, "x")
    @test_throws LK.NotPortedError LK.PL_prof_call(ld, 0, 0)
    @test_throws LK.NotPortedError LK.PL_prof_exit(ld, 0)
    @test LK._llround(2.5) == 3 && LK._llround(-2.5) == -3 && LK._llround(2.4) == 2 &&
        LK._llround(0.5) == 1
end
