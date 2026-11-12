# ORIGINAL: a differential of TR4's compiled tries (pl-trie.c: compile_trie and its emitters, trie_gen_compiled/2,3 on S_TRIE_GEN, '$trie_compile'/2;
# pl-vmi.c: S_TRIE_GEN and the T_* instructions) against swipl at the pin (10.1.20, 18168e62)
# allow-new-artifact: TR4 part 5, the rows of the compiled-trie port, after test/core_lang/test_trie_preds_swipl.{jl,pl,out}
# test/core_lang/test_trie_compiled_swipl.jl — through a PROGRAM (the pattern of test_trie_preds_swipl.jl): test_trie_compiled_swipl.pl holds
# the rows `tN(R)`, the kernel enumerates every solution of every tN/1 and its lines are compared with test_trie_compiled_swipl.out (swipl's
# own, printed by the driver below, two identical runs); when `swipl` is on PATH the .out is checked against a live run as well.
# RUNS ONCE TR2 IS STACKED: the rows t42-t46 call trie_gen/2,3 (TR2's) to compare the compiled answers with the interpreted ones; the kernel's
# check leaves them out while trie_gen/2 is not defined in `system` (the .out still holds swipl's answer: `same`, and a live swipl run checks it).
# KNOWN DIFFERENCES (named; kernel-only testsets at the end):
#   KD-1 trie_gen_compiled/2,3 with a first argument that is neither a trie nor a clause: swipl at the pin overflows the local stack and does
#        not recover (an upstream defect, private register, no row can run it); the kernel raises type_error(trie_or_clause, X) as the C text
#        of S_TRIE_GEN names (instantiation_error for an unbound X: PL_type_error's own rule).
#   KD-2 trie_gen_compiled/2 on a clause reference of a trie with a non-true value: swipl at the pin fails an internal check, no row.
#   KD-3 attributed variables in a key (TR3), conditional answers (T_DELAY: TB4), a table's answer trie (TB3/TB6): named refusals, not here.
#   KD-4 trie_gen_compiled/2 on a MAP trie with an ATOM or small-integer key and a non-variable value: T_VALUE reads the cell above
#        gTop (after T_TRIE_GEN2's `+(Key)`), undefined at the pin (swipl answers `[]` or the key by what an earlier term left
#        there); the kernel reads it as the term's functor word (`_trie_deref_current`): no answer. No row can pin it.
# The kill rows are `@test`s INSIDE testsets (a top-level failing `@test` gives no verdict in CI mode).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_TP, seen::Vector{UInt64}=UInt64[])::String
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

const _TRC_PL = joinpath(@__DIR__, "test_trie_compiled_swipl.pl")
const _TRC_OUT = joinpath(@__DIR__, "test_trie_compiled_swipl.out")

# the rows' names, in the order of a program
_row_names(path::String, re::Regex) =
    unique([String(m[1]) for m in eachmatch(re, read(path, String))])
_trc_names() = _row_names(_TRC_PL, r"^(t\d+)\(R\) :-"m)

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

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd, ld, st = _tp_load(_TP, path)
    return vcat([st], [_tp_row(gd, ld, name) for name in names])
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
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


# the answers of single rows, built from pieces (equal to the .out's, which is swipl's)
_codes2(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
_ea(s::String) = "a" * _codes2(s)
_ei(n::Integer) = "i$n"
_el(items::Vector{String}) = foldr((x, acc) -> "c[91,124,93]/2($x,$acc)", items; init="nil")
_ec(f::String, args::String...) =
    "c" * _codes2(f) * "/$(length(args))(" * join(args, ",") * ")"
_row(name::String, ans::String) = "$name c$(_codes2(name))/1($ans)"


# does the kernel define trie_gen/2 (TR2)?  The rows that compare against it run only then.
function _has_trie_gen(gd::LK.PL_global_data{T}) where {T}
    p = LK.isCurrentProcedure(sym_key(lk_sym(T, :trie_gen)), 2, LK.MODULE_system(gd))
    return p !== nothing && LK.isDefinedProcedure(gd, p)
end
const _TR2_ROWS = ["t42", "t43", "t44", "t45", "t46"]   # runs once TR2 is stacked

# GUARD of every testset that CALLS trie_gen_compiled/2,3 (TR4-I1, the M15b pattern of test_wrap_swipl.jl). These two predicates hold
# supervisor code only: `initTries!(gd)` (src/pl-trie.jl) gives each the shared `S_TRIE_GEN` supervisor and locks it. A predicate without it keeps
# `S_VIRGIN`; the definition holds no clause, so `S_VIRGIN` (src/pl-wam.jl) calls `setDefaultSupervisor`, which answers `true` for a locked
# supervisor and installs nothing, and the VM runs `S_VIRGIN` again: a LOOP inside PL_next_solution (no stack growth, no error), which no test
# line can interrupt. So the check runs FIRST, on the database alone (it reads the two definitions and calls neither predicate), and
# every testset that calls them runs only when it holds; else the testset below fails at once.
const _SUPERVISOR_OK = try
    let
        gd = LK.PL_global_data{_TP}()
        m = LK.MODULE_system(gd)
        all(2:3) do a
            p = LK.isCurrentProcedure(sym_key(lk_sym(_TP, :trie_gen_compiled)), a, m)
            p !== nothing && p.definition.codes === gd.code_data.trie_gen &&
                (p.definition.flags & LK.P_LOCKED_SUPERVISOR) != 0
        end
    end
catch
    # A mutant that makes the guard itself throw must FAIL the guard testset below (a verdict: caught), not stop the file at load.
    false
end
@testset "TR4 guard: trie_gen_compiled/2,3 carry the shared S_TRIE_GEN supervisor, locked (else no row that calls them runs)" begin
    @test _SUPERVISOR_OK
end

_SUPERVISOR_OK &&
    @testset "TR4: trie_gen_compiled/2,3, '\$trie_compile'/2 == swipl's answers (the .out), through a program" begin
        names = _trc_names()
        expected = String.(readlines(_TRC_OUT))
        @test length(names) >= 40
        @test length(expected) == length(names) + 1 && expected[1] == "ok"
        @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
        @test !any(l -> occursin(r"export-error|undefined| exception$", l), expected)
        @test !any(l -> occursin(r"0x[0-9a-f]{6}", l), expected)
        @test all(n -> n in names, _TR2_ROWS)
        @test count(l -> occursin(_codes("type_error"), l), expected) >= 1
        @test count(l -> occursin(_codes("existence_error"), l), expected) >= 1
        @test any(l -> occursin(_codes("instantiation_error"), l), expected)

        gd0 = LK.PL_global_data{_TP}()
        has2 = _has_trie_gen(gd0)
        run_names = has2 ? names : filter(n -> !(n in _TR2_ROWS), names)
        kl = kernel_lines(_TRC_PL, run_names)
        exp_run = [
            expected[1];
            [expected[i + 1] for i in eachindex(names) if names[i] in run_names]
        ]
        @test length(kl) == length(exp_run)
        for i in eachindex(kl)
            @test (i, kl[i]) == (i, exp_run[i])
        end
        has2 ||
            @info "TRIE-COMPILED: the rows $(join(_TR2_ROWS, ", ")) need trie_gen/2 (TR2): not run in the kernel (runs once TR2 is stacked)"

        swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
        if swipl === nothing
            @info "TRIE-COMPILED DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
        else
            @test swipl_lines(_TRC_PL, names) == expected
        end
    end

# The kill rows: single rows, each fails on its own when the one thing it names breaks.
_SUPERVISOR_OK &&
    @testset "TR4 kill rows: answers of single rows" begin
        names = filter(n -> !(n in _TR2_ROWS), _trc_names())
        kl = Dict(zip(["ok"; names], kernel_lines(_TRC_PL, names)))
        @test kl["t0"] == _row(
            "t0", _el([_ec("f", _ei(1)), _ec("f", _ei(2)), _ec("g", _ea("a")), _ea("b")])
        )   # key-only: the four shapes
        @test kl["t2"] == _row("t2", _el([_ei(1), _ei(2)]))                                 # a pattern prunes the other functor
        @test kl["t3"] == _row("t3", _el([_ec("f", _ea("a")), _ec("f", _ea("c"))]))          # a bound Value: the leaves with it
        @test kl["t4"] == _row("t4", _ea("no"))                                             # an empty trie
        @test kl["t5"] == _row("t5", _ea("no"))
        @test kl["t12"] ==
            _row(
            "t12", _el([_ei(-1), _ei(0), _ei(1), _ei(-7), _ea("x"), _ea("y"), _ei(7)])
        )   # T_SMALLINT / T_ATOM
        @test kl["t16"] == _row(
            "t16",
            _ec("-", _el([_ec("f", _ei(1)), _ec("f", _ei(2))]),
                _el([_ec("f", _ei(1)), _ec("f", _ei(2)), _ec("f", _ei(3))]))
        )   # an insert discards the clause
        @test kl["t17"] == _row(
            "t17",
            _ec("-", _el([_ec("f", _ei(1)), _ec("f", _ei(2)), _ec("f", _ei(3))]),
                _el([_ec("f", _ei(1)), _ec("f", _ei(3))]))
        )                    # a delete discards it too
        @test kl["t18"] == _row("t18", _ec("-", _ei(50), _ei(1275)))
        @test kl["t19"] == _row("t19", _ec("-", _ei(1000), _ei(500500)))                      # 1000 keys: the long code
        @test kl["t20"] == _row("t20", _ea("clause"))                                       # '$trie_compile' answers a clause
        @test kl["t21"] == _row("t21", _ea("isfail"))                                       # and the atom fail for an empty trie
        @test kl["t29"] ==
            _row("t29", _ec("-", _ec("-", _ea("isfail"), _ea("no")), _ea("no")))   # fail as the first argument: failure
        @test kl["t23"] == _row("t23", _el([_ei(1), _ei(2)]))                               # a clause as the first argument
        @test kl["t39"] == _row("t39", "nil")                                               # key-only on non-true values: no answer
        @test kl["t53"] == _row("t53", _el([_ec("f", _ei(1))]))                             # a variable value takes the key's functor word
        @test kl["t54"] == _row("t54", _el([_ea("a")]))                                     # ... and the cell above gTop
        @test kl["t55"] == _row("t55", _el([_ec("f", _ei(5))]))                             # functor, float, string, small int: no match
        @test kl["t40"] == _row(
            "t40",
            _ec("-", _el([_ec("f", _ei(1))]), _el([_ec("f", _ei(1)), _ec("f", _ei(2))]))
        )   # the discarded clause still answers
        @test kl["t41"] ==
            _row("t41", _ec("-", _el([_ec("-", _ec("f", _ei(1)), _ea("a"))]), "nil"))
        @test kl["t47"] == _row("t47", _ea("shared"))                                       # T_VAR in a value: the repeated variable is one variable
        @test kl["t48"] == _row(
            "t48",
            _el([
                _ec(
                    "-",
                    _ec("f", _ei(1)),
                    _ec("a", _ec("b", _ec("c", _ec("d", _ei(1)))), _ei(2))
                ),
                _ec(
                    "-",
                    _ec("f", _ei(2)),
                    _ec("a", _ec("b", _ec("c", _ec("d", _ei(2)))), _ei(3))
                )])
        )   # a deep value: T_POP/T_POPN
        @test kl["t49"] == _row(
            "t49",
            _el([
                _ec(
                    "-",
                    _ec("f", _ei(1)),
                    _ec("w", "s[115,116,114]", "f2.5", "i100000000000000000000", _ea("x"))
                )
            ])
        )   # indirects in a value
        @test kl["t50"] == _row("t50", _el([_ei(1)]))                                       # T_CHECKWAKEUP: the hook runs for each answer
        @test kl["t51"] == _row("t51", _ea("same"))                                         # a clause reference is made once
        @test kl["t52"] == _row(
            "t52",
            _el([
                _ec("f", _ea("a"), _ec("g", _ei(1)), _ea("c")),
                _ec("f", _ea("a"), _ec("g", _ei(2)), _ea("c"))
            ])
        )   # a compound at a non-first argument
        @test kl["t36"] ==
            _row("t36", _el([_ec("-", _ei(1), _ei(1)), _ec("-", _ei(2), _ei(2))]))   # a shared variable in the call
    end

# KD-1: the first argument is neither a trie nor a clause — the kernel's answer (swipl overflows its stack here: NO swipl answer).
_SUPERVISOR_OK &&
    @testset "TR4 KD-1: trie_gen_compiled/2,3 on a non-trie raises type_error(trie_or_clause, X)" begin
        prog = """
        ek(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), ( E = type_error(A, B) -> R = te(A, B) ; E = instantiation_error -> R = inst ; R = other )).
        k1(R) :- ek(trie_gen_compiled(foo, _), R).
        k2(R) :- ek(trie_gen_compiled(foo, _, _), R).
        k3(R) :- ek(trie_gen_compiled(_, _), R).
        k4(R) :- ek(trie_gen_compiled(1, _), R).
        """
        mktempdir() do d
            f = joinpath(d, "kd1.pl")
            write(f, prog)
            kl = kernel_lines(f, ["k1", "k2", "k3", "k4"])
            @test kl[1] == "ok"
            @test kl[2] ==
                "k1 c[107,49]/1(c[116,101]/2(a[116,114,105,101,95,111,114,95,99,108,97,117,115,101],a[102,111,111]))"
            @test kl[3] ==
                "k2 c[107,50]/1(c[116,101]/2(a[116,114,105,101,95,111,114,95,99,108,97,117,115,101],a[102,111,111]))"
            @test kl[4] == "k3 c[107,51]/1(a[105,110,115,116])"
            @test kl[5] ==
                "k4 c[107,52]/1(c[116,101]/2(a[116,114,105,101,95,111,114,95,99,108,97,117,115,101],i1))"
        end
    end
