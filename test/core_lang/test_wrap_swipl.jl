# ORIGINAL: a differential of WRAP1's wrapper machinery (pl-wrap.c, S_WRAP/S_CALLWRAPPER of pl-vmi.c, the closure branch of
# i_metacall_common) against swipl at the pin, plus white-box rows on the kernel's supervisor helpers
# test/core_lang/test_wrap_swipl.jl — wrap_predicate/4 (library(prolog_wrap), through '$c_wrap_predicate'/5), calls of a wrapped
# predicate (S_WRAP switches to the wrapped supervisor, S_CALLWRAPPER runs its clause), a closure called through call/N,
# unwrap_predicate/2, '$wrapped_predicate'/2, '$wrapped_implementation'/3, '$closure_predicate'/2 and the printed form of a
# closure (write_closure), through a PROGRAM (the pattern of test/core_lang/test_sys_swipl.jl): test_wrap_swipl.pl holds the rows,
# each a predicate `tN(R)`; the kernel consults the program and enumerates every solution of every tN/1, and its lines are
# compared with test_wrap_swipl.out — swipl 10.1.20's own (pin 18168e62), printed by the driver below (`ok`, then one line per
# row: its name and every solution). When `swipl` is on PATH the .out is checked against a live run as well.
# A row never encodes a closure blob (it has no stable text): it records names, the order of calls and the wrapped goals' results.
# The white-box testsets read the supervisors the kernel built (`closure.supervisor`, `closure.supervisor_crefs`,
# `definition.codes_crefs`) — swipl keeps them in C structures, so the rows are LK-only; the kill rows are `@test`s INSIDE
# testsets (a top-level failing `@test` gives no verdict in CI mode).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _WT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_wts(x) = lk_sym(_WT, Symbol(x))

_cm(s::String) = join(Int.(collect(s)), ",")                    # the codes of `s`, to find INSIDE an atom's code list
_codes(s::String) = "[" * _cm(s) * "]"
function enc(t::_WT, seen::Vector{UInt64}=UInt64[])::String
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

const _WRAP_PL = joinpath(@__DIR__, "test_wrap_swipl.pl")
const _WRAP_OUT = joinpath(@__DIR__, "test_wrap_swipl.out")

# the rows' names, in the order of the program
_wrap_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_WRAP_PL, String))])

# a fresh kernel with `path` consulted: `(gd, ld, "ok" or "exc <ball>")`
function _wt_load(::Type{T}, path::String) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * enc(ball::T))
end

# the driver's line for the row `name`/1 (every answer, at most 100): the name, then each solution
function _wt_row(
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

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd, ld, st = _wt_load(_WT, path)
    return vcat([st], [_wt_row(gd, ld, name) for name in names])
end

# the driver swipl runs to print its lines (the .out is its output; the text of test_sys_swipl.jl's DRIVER)
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

# expected lines, built from pieces (the answers are swipl's, read from the .out): an atom, an integer, a list, a compound
_ea(s::String) = "a" * _codes(s)
_ei(n::Integer) = "i$n"
_el(items::Vector{String}) =
    foldr((x, acc) -> "c[91,124,93]/2($x,$acc)", items; init="nil")
_ec(f::String, args::String...) =
    "c" * _codes(f) * "/$(length(args))(" * join(args, ",") * ")"
_er(name::String, answer::String) = "$name " * _ec(name, answer)
_ed(xs::String...) = foldl((a, b) -> _ec("-", a, b), xs)        # `X1-X2-...-Xn` (left nested, as `-` is yfx)
_ep(m::String, n::String, a::Integer) = _ec(":", _ea(m), _ec("/", _ea(n), _ei(a)))   # `m:n/a`

# GUARD of every testset that CALLS a wrapped predicate or a closure (WRAP1-M15b). The closure's number is the copy's definition
# (`impl_foreign_function`, src/pl-wrap.jl: `_impl_any_defined` reads it); a copy without one is an undefined predicate, and a
# call of the wrapped predicate then goes `trapUndefined` -> `autoImport` -> the wrapped predicate -> its wrapper -> the copy ...
# a LOOP inside PL_next_solution (constant memory, no stack overflow, no resource error: measured, the CI time limit), which no
# test line can interrupt. So the check runs FIRST, on a program that only CREATES a closure (`wrap_predicate/4` calls nothing
# wrapped), and every testset that calls a wrapped predicate runs only when it holds; else the testset below fails at once.
const _COPIES_OK = try
    let
        f = tempname() * ".pl"
        write(f, "cp_p(1).\ncp_w(ok) :- wrap_predicate(cp_p(_), n1, W, W).\n")
        gd, ld, st = _wt_load(_WT, f)
        rm(f)
        st == "ok" && _wt_row(gd, ld, "cp_w") == _er("cp_w", _ea("ok")) &&
            !isempty(gd.closure_refs) &&
            all(c -> LK._impl_any_defined(c.def), gd.closure_refs)
    end
catch
    # A mutant that makes the guard program itself throw (WRAP1-M3b, M15c, M17: an assertion, a
    # BoundsError, a supervisor error) must FAIL the guard testset below (a verdict: caught), not
    # stop the file at load (NO VERDICT, "does not load", which blocks the battery).
    false
end
@testset "WRAP1 guard: a closure's copy is a defined predicate (else no row that calls a wrapped predicate runs)" begin
    @test _COPIES_OK
end

_COPIES_OK &&
    @testset "WRAP1: wrappers, closures and their predicates == swipl's answers (the .out), through a program" begin
        names = _wrap_names()
        expected = String.(readlines(_WRAP_OUT))
        # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
        @test length(names) >= 19
        @test length(expected) == length(names) + 1 && expected[1] == "ok"
        @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
        @test any(
            l -> occursin(_codes("type_error"), l) && occursin(_codes("closure"), l),
            expected
        )     # '$closure_predicate'/2
        @test any(
            l -> occursin(_codes("existence_error"), l) && occursin(_codes("undef11"), l),
            expected
        ) # the WRAPPED predicate
        @test any(l -> occursin(_cm("<closure>(p15/1)(7)"), l), expected)                              # write_closure
        @test any(l -> occursin(_cm("<closure>(m15:p15m/1)(8)"), l), expected)                         # ... with a module
        @test !any(l -> occursin(r"export-error|undefined| exception$", l), expected)

        kl = kernel_lines(_WRAP_PL, names)
        @test length(kl) == length(expected)
        for i in eachindex(kl)
            @test (i, kl[i]) == (i, expected[i])
        end

        swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
        if swipl === nothing
            @info "WRAP DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
        else
            @test swipl_lines(_WRAP_PL, names) == expected             # the .out is swipl's, still
        end
    end

# The kill rows: the answers of single rows, built from pieces here and equal to the .out's (swipl's); each fails on its own
# when the one thing it names breaks, so a mutant shows as a named verdict and not only as a changed line of the file.
_COPIES_OK && @testset "WRAP1 kill rows: each row's answer, by name" begin
    names = _wrap_names()
    gd, ld, st = _wt_load(_WT, _WRAP_PL)
    @test st == "ok"
    row(n) = _wt_row(gd, ld, n)
    l12 = _el([_ei(1), _ei(2)])
    # S_WRAP / S_CALLWRAPPER over a two-clause and a SINGLE-clause predicate (the wrapped supervisor's side table, not the wrapper's)
    @test row("t0") == _er("t0", _ec("-", l12, l12))
    @test row("t1") == _er("t1", _ec("-", _el([_ei(5)]), _el([_ei(5)])))
    # the last registered wrapper runs outermost, and each runs in and out of the wrapped call
    @test row("t2") == _er(
        "t2",
        _ec(
            "-",
            _el([_ei(1)]),
            _el([_ea("b_in"), _ea("a_in"), _ea("a_out"), _ea("b_out")])
        )
    )
    # a second wrap of a name replaces its body and keeps its place
    @test row("t3") == _er(
        "t3",
        _ec(
            "-",
            _ec("-", _el([_ei(1)]), _el([_ea("old2"), _ea("new1")])),
            _el([_ea("w2"), _ea("w1")])
        )
    )
    # unwrap_predicate/2: a named wrapper goes, an unbound name removes the outermost, then it fails
    @test row("t4") == _er(
        "t4",
        _ec(
            "-",
            _ec(
                "-",
                _ec("-", _ec("-", _el([_ea("w2")]), _ea("w2")), "nil"),
                _el([_ei(1)])
            ),
            _ea("no")
        )
    )
    # '$wrapped_predicate'/2 lists outermost first; a plain predicate fails
    @test row("t5") == _er(
        "t5", _ec("-", _el([_ea("w3"), _ea("w2"), _ea("w1")]), _ea("plain"))
    )
    # the closure atom through call/N (a wrapper adding to the wrapped result): 5 * 2 + 1
    @test row("t8") == _er("t8", _ei(11))
    # a predicate changed by assert/retract after it was wrapped
    @test row("t12") == _er(
        "t12",
        _ec(
            "-",
            _ec("-", _ec("-", _el([_ei(1)]), _el([_ei(1), _ei(2)])), _el([_ei(2)])),
            _el([_ea("w"), _ea("w"), _ea("w")])
        )
    )
    # a wrapped nondeterministic predicate: every solution, one wrapper call per call
    @test row("t14") == _er(
        "t14", _ec("-", _el([_ei(1), _ei(2), _ei(3)]), _el([_ea("call")]))
    )
    # wrapped foreign predicates: the deterministic and the nondeterministic (the retry through the wrapper)
    @test row("t17") == _er(
        "t17", _ec("-", _ec("-", _ea("wrapped"), _ei(3)), _el([_ea("w")]))
    )
    @test row("t18") == _er(
        "t18",
        _ec(
            "-",
            _ec("-", _ea("wrapped"), _el([_ei(1), _ei(2), _ei(3)])),
            _el([_ea("w")])
        )
    )
    # '$wrapped_implementation'/3: the goal as seen from the wrapper `Name` (the answers of the predicate and the wrappers inside it),
    # a name without wrapper fails, a nullary predicate: Y-L2-Y2-L1-Q-Z = [a,b]-[w1]-[a,b]-[]-none-true
    @test row("t6") == _er(
        "t6",
        _ed(
            _el([_ea("a"), _ea("b")]),
            _el([_ea("w1")]),
            _el([_ea("a"), _ea("b")]),
            "nil",
            _ea("none"),
            _ea("true")
        )
    )
    # '$closure_predicate'/2 gives `user:p7/1` and `m7:p7m/1` (GP_QUALIFY | GP_NAMEARITY), and a type error for a non-closure
    @test row("t7") == _er(
        "t7",
        _ec(
            "-",
            _el([_ep("user", "p7", 1), _ep("m7", "p7m", 1)]),
            _ec("type_error", _ea("closure"), _ea("foo"))
        )
    )
    # exceptions through a wrapper: outside, caught by the wrapper, rethrown
    @test row("t9") == _er(
        "t9",
        _ed(
            _ea("oops"),
            _ea("succeeded"),
            _ec("again", _ea("oops_c")),
            _el([_ec("caught", _ea("oops_b")), _ec("rethrow", _ea("oops_c"))])
        )
    )
    # a wrapper that fails, one that never calls the wrapped goal, a wrapped goal that fails
    @test row("t10") == _er(
        "t10",
        _ed(_ea("no"), _ea("yes"), _ea("no"), _el([_ea("skipped"), _ea("before")]))
    )
    # an undefined wrapped predicate: the existence error names the WRAPPED predicate, the wrapper never ran
    @test row("t11") == _er(
        "t11",
        _ec(
            "-",
            _ec("existence_error", _ea("procedure"), _ec("/", _ea("undef11"), _ei(1))),
            "nil"
        )
    )
    # call/1 of the closure compound runs, call/2 of it is a type error `callable`
    @test row("t13") == _er("t13", _el([_ea("callable")]))
    # current_predicate_wrapper/4 lists the names (outermost first), `wrapped(_)` is no property, an unwrap shortens the list
    @test row("t16") == _er(
        "t16",
        _ed(_el([_ea("w2"), _ea("w1")]), "nil", _el([_ea("w2")]))
    )
    # a wrapped two-clause predicate with `[]` and `[_|_]` first arguments (S_LIST through the wrapped supervisor's side table)
    @test row("t19") == _er(
        "t19",
        _ec("-", _ec("-", _ea("nil"), _ea("cons")), _el([_ea("w"), _ea("w")]))
    )
    # unwrap_predicate/2 retracts the wrapper's clause: the clauses of `$wrap$p20` left after the first and the second unwrap
    @test row("t20") == _er("t20", _ec("-", _ei(1), _ei(0)))
    # a clause reference is a blob but no closure: a type error `callable` for call/1 of it, of a compound named by it, and with call/2
    @test row("t21") == _er(
        "t21", _ed(_ea("callable"), _ea("callable"), _ea("callable"))
    )
    # WRAP1-M7 (DBG1 landed prolog_frame_attribute/3): the frame S_CALLWRAPPER runs the wrapper clause in reports the WRAPPER's predicate.
    # swipl 10.1.20 answers k22 (a row of the .pl that is no `tN`, so the driver's list and the .out leave it out) with
    # ['$wrap$p22'/1] (user module: unqualified). The row runs on a load of its own, and a throw (a kernel that lacks the
    # attribute, a refusal) is a failed test, not an error that stops the file.
    @test try
        gd22, ld22, st22 = _wt_load(_WT, _WRAP_PL)
        st22 == "ok" &&
            _wt_row(gd22, ld22, "k22") ==
            _er("k22", _el([_ec("/", _ea("\$wrap\$p22"), _ei(1))]))
    catch
        false
    end
    # the printed form of a closure
    @test occursin(_codes("call(<closure>(p15/1)(7))"), row("t15"))
    @test occursin(_codes("call(<closure>(m15:p15m/1)(8))"), row("t15"))
end

# ---- white-box rows: the supervisors the kernel built (LK-only) ----
const _WB_PL = """
wb_p(1).
wb_q(1).
wb_q(2).
wb_plain(1).
wb_r1(ok) :- wrap_predicate(wb_p(_), n1, W, W).
wb_r2(Ys) :- findall(Y, wb_p(Y), Ys).
wb_r3(ok) :- wrap_predicate(wb_q(_), n1, W, W), wrap_predicate(wb_q(_), n2, V, V).
wb_r4(Ys) :- findall(Y, wb_q(Y), Ys).
wb_r5(ok) :- unwrap_predicate(wb_q/1, n2).
wb_r6(Ys) :- findall(Y, wb_q(Y), Ys).
wb_u(1).
wb_r7(ok) :- wrap_predicate(wb_u(_), n1, W, W), wrap_predicate(wb_u(_), n2, V, V).
wb_r8(Ys) :- findall(Y, wb_u(Y), Ys).
wb_r9(ok) :- unwrap_predicate(wb_u/1, n1).
wb_r10(Ys) :- findall(Y, wb_u(Y), Ys).
"""

function _wb_def(gd::LK.PL_global_data{T}, name::String, arity::Int=1) where {T}
    proc = LK.isCurrentProcedure(
        sym_key(lk_sym(T, Symbol(name))), arity, LK.MODULE_user(gd)
    )
    @assert proc !== nothing
    return proc.definition
end

# the closure of the wrapper at the head of `codes`
function _wb_closure(gd::LK.PL_global_data{T}, codes::Vector{LK.code}) where {T}
    i = LK.skipWrapperPrefix(codes)
    @assert LK.isCallWrapper(codes[i])
    return LK.closure_of_word(gd, codes[i + 2])::LK.closure{T}
end

_COPIES_OK &&
    @testset "WRAP1 white-box: closures, supervisor_crefs, innermost_supervisor, unwrap" begin
        f = tempname() * ".pl"
        write(f, _WB_PL)
        gd, ld, st = _wt_load(_WT, f)
        rm(f)
        @test st == "ok"
        ok(n, name) = _wt_row(gd, ld, name) == "$name " * _ec(name, n)

        @testset "a wrapped single-clause predicate" begin
            @test ok(_ea("ok"), "wb_r1")
            d = _wb_def(gd, "wb_p")
            i = LK.skipWrapperPrefix(d.codes)
            @test d.codes[i] == LK.S_CALLWRAPPER
            c = _wb_closure(gd, d.codes)
            @test c.predicate === d
            # the closure's number: `impl_foreign_function` of its definition is its index in `gd.closure_refs` (what
            # `_impl_any_defined` reads, and S_WRAP finds the closure by)
            @test c.def.impl_foreign_function == findfirst(x -> x === c, gd.closure_refs)
            @test c.def.impl_foreign_function != 0
            @test LK._impl_any_defined(c.def)
            # `<closure>` of its blob: the wrapper names it, `closure_of_word` finds it again
            @test LK.closure_of_word(gd, d.codes[i + 2]) === c
            # before the first call the wrapped supervisor is the virgin one; S_WRAP creates the real one (and stores both parts)
            @test c.supervisor === d.code_data.virgin
            @test LK.supervisor_crefs(gd, d, d.codes) === d.codes_crefs
            @test ok(_el([_ei(1)]), "wb_r2")
            @test c.supervisor !== d.code_data.virgin
            @test c.supervisor[1] != LK.S_VIRGIN
            @test length(c.supervisor_crefs) >= 1                  # the single clause of wb_p is in the CLOSURE's table ...
            @test c.supervisor_crefs !== d.codes_crefs             # ... which is not the wrapper's table
            @test LK.supervisor_crefs(gd, d, c.supervisor) === c.supervisor_crefs
            @test LK.supervisor_crefs(gd, d, d.codes) === d.codes_crefs
            @test_throws ErrorException LK.supervisor_crefs(gd, d, LK.code[LK.S_VIRGIN])
            codes, crefs = LK.innermost_supervisor(gd, d)
            @test codes === c.supervisor && crefs === c.supervisor_crefs
        end

        @testset "a predicate without wrapper" begin
            p = _wb_def(gd, "wb_plain")
            @test LK.supervisor_crefs(gd, p, p.codes) === p.codes_crefs
            @test_throws ErrorException LK.supervisor_crefs(gd, p, LK.code[LK.S_VIRGIN])
            codes, crefs = LK.innermost_supervisor(gd, p)
            @test codes === p.codes && crefs === p.codes_crefs
        end

        @testset "two wrappers, then unwrap of the outer one" begin
            @test ok(_ea("ok"), "wb_r3")
            @test ok(_el([_ei(1), _ei(2)]), "wb_r4")
            d = _wb_def(gd, "wb_q")
            c2 = _wb_closure(gd, d.codes)                          # the last registered: outermost
            @test c2.supervisor !== d.code_data.virgin             # the supervisor of c2 is the n1 wrapper
            c1 = _wb_closure(gd, c2.supervisor)
            @test c1.predicate === d && c2.predicate === d
            @test LK.supervisor_crefs(gd, d, d.codes) === d.codes_crefs
            @test LK.supervisor_crefs(gd, d, c2.supervisor) === c2.supervisor_crefs
            @test LK.supervisor_crefs(gd, d, c1.supervisor) === c1.supervisor_crefs
            @test c1.supervisor[1] != LK.S_VIRGIN                  # S_WRAP created the real supervisor
            codes, crefs = LK.innermost_supervisor(gd, d)
            @test codes === c1.supervisor && crefs === c1.supervisor_crefs
            saved_codes, saved_crefs = c2.supervisor, c2.supervisor_crefs
            @test ok(_ea("ok"), "wb_r5")                           # unwrap_predicate(wb_q/1, n2)
            # unwrap installs BOTH the code and its side table back
            @test d.codes === saved_codes
            @test d.codes_crefs === saved_crefs
            @test LK.supervisor_crefs(gd, d, d.codes) === d.codes_crefs
            @test _wb_closure(gd, d.codes) === c1
            @test ok(_el([_ei(1), _ei(2)]), "wb_r6")               # still runs, through n1 only
            codes, crefs = LK.innermost_supervisor(gd, d)
            @test codes === c1.supervisor && crefs === c1.supervisor_crefs
        end

        # unwrap of the INNER wrapper, after both ran (each closure holds a real supervisor; the side table
        # of a SINGLE clause predicate is non-empty): the outer closure takes over the inner one's code AND
        # its side table (pl-wrap.c: `*cp = cls->def.impl.wrapped.supervisor`), through
        # `holder.supervisor_crefs` of unwrap_predicate/2. The program row t4 unwraps the inner wrapper
        # before either ran (virgin supervisor, empty side table), so it cannot see the side table.
        @testset "unwrap of the inner wrapper after both wrappers ran" begin
            @test ok(_ea("ok"), "wb_r7")
            d = _wb_def(gd, "wb_u")
            c2 = _wb_closure(gd, d.codes)
            c1 = _wb_closure(gd, c2.supervisor)
            # BOUND: a closure's copy without a number (`_impl_any_defined` false) is an undefined predicate: a call of the
            # wrapped predicate resolves it (`trapUndefined`, `autoImport`) to the wrapped predicate itself, whose wrapper calls
            # the closure again, round and round until the stack overflows (WRAP1-M15b ran into the CI time limit). The rows
            # that call `wb_u` run only when both copies are defined; else this row fails at once.
            defined = LK._impl_any_defined(c1.def) && LK._impl_any_defined(c2.def)
            @test defined
            if defined
                @test ok(_el([_ei(1)]), "wb_r8")
                @test c1.supervisor[1] != LK.S_VIRGIN
                @test length(c1.supervisor_crefs) >= 1
                saved_codes, saved_crefs = c1.supervisor, c1.supervisor_crefs
                @test ok(_ea("ok"), "wb_r9")                       # unwrap_predicate(wb_u/1, n1)
                @test _wb_closure(gd, d.codes) === c2
                @test c2.supervisor === saved_codes
                @test c2.supervisor_crefs === saved_crefs
                @test LK.supervisor_crefs(gd, d, c2.supervisor) === c2.supervisor_crefs
                @test ok(_el([_ei(1)]), "wb_r10")                  # runs on, through n2 only
            end
        end

        @testset "get_procedure_resolve_head" begin
            head(name) =
                mk_expr(
                    _WT, _WT[lk_sym(_WT, Symbol(name)), mk_var(_WT, LK.fresh_var_keys!(1))]
                )
            put(v) =
                (
                    t=LK.PL_new_term_ref(ld);
                    LK.putSlotValue!(ld, t + 1, v, LK.PutVarMap());
                    t
                )
            d = _wb_def(gd, "wb_q")
            h = LK.PL_new_term_ref(ld)
            proc = LK.get_procedure_resolve_head(gd, ld, put(head("wb_q")), h)
            @test proc !== nothing && proc.definition === d
            @test LK.PL_get_name_arity(ld, h)[2] == 1               # the stripped head
            # module-qualified: the same procedure
            q = mk_expr(
                _WT, _WT[lk_sym(_WT, Symbol(":")), lk_sym(_WT, :user), head("wb_q")]
            )
            proc2 = LK.get_procedure_resolve_head(gd, ld, put(q), 0)
            @test proc2 !== nothing && proc2.definition === d
            # an undefined head: GP_RESOLVE creates the procedure, undefined
            proc3 = LK.get_procedure_resolve_head(gd, ld, put(head("wb_nowhere")), 0)
            @test proc3 !== nothing && !LK.isDefinedProcedure(gd, proc3)
        end
    end

# A QUERY opened on a wrapped non-deterministic foreign predicate. The wrapper body `W` is a call of a variable goal
# (`I_USERCALL0`, not a last call), so the foreign frame is a CHILD of the query's frame: the retry's `FR` is the wrapper's
# frame, not the foreign one, and it goes through `deep_backtrack` (src/pl-wam.jl, the WRAP1 line of the `P_FOREIGN` branch:
# the site of WRAP1-M14b). `shallow_backtrack`'s foreign branch (WRAP1-M14a) needs `FR == ch.frame`: a query opened on the
# CLOSURE of the wrapped predicate (the next testset). Both sites re-derive the foreign supervisor by `innermost_supervisor`,
# not by `DEF.codes` (the wrapper's code).
@testset "WRAP1: a query on a wrapped between/3 retries through the foreign supervisor (deep_backtrack)" begin
    f = tempname() * ".pl"
    write(f, "wb_nd(ok) :- wrap_predicate(system:between(_, _, _), n1, W, W).\n")
    gd, ld, st = _wt_load(_WT, f)
    rm(f)
    @test st == "ok"
    @test _wt_row(gd, ld, "wb_nd") == "wb_nd " * _ec("wb_nd", _ea("ok"))
    proc = LK.isCurrentProcedure(sym_key(lk_sym(_WT, :between)), 3, LK.MODULE_system(gd))
    @test proc !== nothing
    d = proc.definition
    @test LK.isCallWrapper(d.codes[LK.skipWrapperPrefix(d.codes)])          # wrapped: its supervisor is the wrapper's
    # BOUND (WRAP1-M15b: the CI time limit): a closure's copy without a number is an undefined predicate that resolves, on a call,
    # to the wrapped predicate itself (`autoImport`), whose wrapper calls the closure again until the stack overflows. The query
    # opens only when the closure's copy is defined; else this row fails at once.
    ci = findlast(c -> c.predicate === d, gd.closure_refs)
    @test ci !== nothing && LK._impl_any_defined(gd.closure_refs[ci].def)
    if ci !== nothing && LK._impl_any_defined(gd.closure_refs[ci].def)
        pvm = LK.PutVarMap()
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 3)
        LK.putSlotValue!(ld, a + 1, mk_gnd(_WT, Int64(1)), pvm)
        LK.putSlotValue!(ld, a + 2, mk_gnd(_WT, Int64(3)), pvm)
        LK.putSlotValue!(ld, a + 3, mk_var(_WT, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        got = Any[]
        rcs = Int[]
        while length(got) < 10
            rc = LK.PL_next_solution(gd, ld, qid)
            push!(rcs, rc)
            (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
            push!(got, lk_value(lk_answers(ld, a + 2)[1]))
            rc == LK.PL_S_LAST && break
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        codes, _ = LK.innermost_supervisor(gd, d)                               # after the first call: S_WRAP made it
        @test codes !== d.codes && codes[1] == LK.I_FOPENNDET                   # the foreign supervisor, inside the wrapper
        @test got == [1, 2, 3]
        @test !(LK.PL_S_EXCEPTION in rcs)
        @test LK.live_states(ld) == 0
    end
end

# A QUERY opened on the CLOSURE of a wrapped between/3 (the copy `S_WRAP` runs; a C caller of `PL_call_predicate` on a closure
# gets this): its frame becomes the wrapped predicate's foreign frame, so the retry arrives at `shallow_backtrack` with
# `FR == ch.frame` and a `P_FOREIGN` predicate, whose code the kernel re-derives by `innermost_supervisor` (WRAP1-M14a), not by
# `DEF.codes` (the wrapper's code, as the wrapped predicate's definition holds it).
@testset "WRAP1: a query on the closure of a wrapped between/3 retries through the foreign supervisor (shallow_backtrack)" begin
    f = tempname() * ".pl"
    write(f, "wb_nd(ok) :- wrap_predicate(system:between(_, _, _), n1, W, W).\n")
    gd, ld, st = _wt_load(_WT, f)
    rm(f)
    @test st == "ok"
    @test _wt_row(gd, ld, "wb_nd") == "wb_nd " * _ec("wb_nd", _ea("ok"))
    proc = LK.isCurrentProcedure(sym_key(lk_sym(_WT, :between)), 3, LK.MODULE_system(gd))
    @test proc !== nothing
    d = proc.definition
    i = findlast(c -> c.predicate === d, gd.closure_refs)
    @test i !== nothing
    cproc = LK.procedure(gd.closure_refs[i].def, UInt32(0), UInt32(0))      # a procedure on the closure's copy
    # BOUND: a copy without a number (`_impl_any_defined` false) resolves, on a call, to the wrapped predicate itself (`autoImport`),
    # whose wrapper calls the closure again without end until the stack overflows (WRAP1-M15b: the CI time limit). The query
    # opens only on a defined copy; else this row fails at once.
    @test LK._impl_any_defined(cproc.definition)
    if LK._impl_any_defined(cproc.definition)
        pvm = LK.PutVarMap()
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 3)
        LK.putSlotValue!(ld, a + 1, mk_gnd(_WT, Int64(1)), pvm)
        LK.putSlotValue!(ld, a + 2, mk_gnd(_WT, Int64(3)), pvm)
        LK.putSlotValue!(ld, a + 3, mk_var(_WT, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, cproc, a
        )
        got = Any[]
        rcs = Int[]
        while length(got) < 10
            rc = LK.PL_next_solution(gd, ld, qid)
            push!(rcs, rc)
            (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
            push!(got, lk_value(lk_answers(ld, a + 2)[1]))
            rc == LK.PL_S_LAST && break
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        @test got == [1, 2, 3]
        @test !(LK.PL_S_EXCEPTION in rcs)
        @test LK.live_states(ld) == 0
    end
end
