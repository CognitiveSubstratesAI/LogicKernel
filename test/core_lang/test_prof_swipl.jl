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
    unique([String(m[1]) for m in eachmatch(Regex("^(" * prefix * "\\d+)\\(R\\) :-", "m"), read(_PF_PL, String))])
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
kernel_lines(::Type{T}, path::String, names::Vector{String}, setup::Function=(gd, ld) -> nothing) where {T} =
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
        write(f, DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") * "]), halt)).\n")
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
    for w in ("type_error", "instantiation_error", "domain_error", "profile_status", "profile_node", "failed", "true")
        @test _pf_count(body, w) >= 1
    end
    kl, ld = kernel_run(_TL, _PF_PL, names)
    @test length(kl) == length(expected)
    for w in ("type_error", "instantiation_error", "domain_error", "profile_status", "profile_node", "failed", "true")
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
    defof(name) = LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd)).definition
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
                _c("[|]", _c("node", _a("<spontaneous>"), "i0", "i5", "i10", "i3", "i1", "i2"), "nil"),
                _a("pg"), "i0", "i10", "i0", "i3", "i0", "i3"
            )
        ),
        _row(
            "k7",
            _c(
                "d", "i10", "i0", "i3", "i0", "i3", "nil", _a("pf"), "i0", "i10", "i0", "i3", "i0", "i3"
            )
        ),
        _row("k8", _a("failed")),
        _row("k9", _c("s", "i4", "i15", "i0", "f0.0", "i3", "i0", _a("false"), _a("false"))),
        _row("k10", "i0"),
        _row("k11", _c("err", _c("type_error", _a("profile_node"), _pn(1)))),
        _row("k12", _a("failed")),
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
    @test LK.prof_node_at(ld, a) !== nothing && LK.prof_node_at(ld, 0) === nothing && LK.prof_node_at(ld, a + 1) === nothing
    ld.profile.roots = a
    LK.freeProfileData(ld)
    @test ld.profile.nodes == 0 && LK.prof_node_at(ld, a) === nothing
end
