# UPSTREAM: pl-gc.c pl_garbage_collect, pl-thread.c pl_thread_self, pl-mutex.c pl_with_mutex (swipl-devel cbf4e189) — BOOTPRED's rows
# test/core_lang/test_bootpred_swipl.jl — `'$garbage_collect'/1`, thread_self/1 and with_mutex/2 against swipl 10.1.19 (the pl-dict.c rows
# are a later block of this file):
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_at_body_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, 2026-10-31, lk-channel evidence/BOOTPRED/bootpred_rows.out in the
#     BOOTPRED branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
#   * KNOWN DIFFERENCES (single-thread forms, pinned separately below): with_mutex/2 does not examine its mutex.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the three built-ins ride the term layer only through PL_unify_atom and callProlog; every type in CI
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _BP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_bps(x) = lk_sym(_BP, Symbol(x))

_bp_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _bp_enc(t::_BP, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _bp_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _bp_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _bp_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_bp_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _BP_DRIVER = raw"""
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
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function _bp_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _BP_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: three facts for the once/1 rows
const _BP_PROGRAM = raw"""
p(1).
p(2).
p(3).
"""

# bp01-bp08 thread_self/1; bp09-bp19 with_mutex/2; bp20-bp26 '$garbage_collect'/1
const _BP_CASES = [
    ("bp01", raw"thread_self(R)"),                                       # main
    ("bp02", raw"thread_self(main), R = yes"),
    ("bp03", raw"thread_self(other), R = yes"),                          # fails
    ("bp04", raw"findall(X, thread_self(X), R)"),                        # [main]: one answer, no choice point
    ("bp05", raw"thread_self(1), R = yes"),                              # fails
    ("bp06", raw"thread_self(T), atom(T), R = T"),
    ("bp07", raw"thread_self(T), T == main, R = ok"),
    ("bp08", raw"with_mutex(m, thread_self(R))"),
    ("bp09", raw"with_mutex(m, R = 1)"),
    ("bp10", raw"findall(X, with_mutex(m, p(X)), R)"),                   # once/1: [1]
    ("bp11", raw"with_mutex(m, fail), R = x"),                           # fails
    ("bp12", raw"catch(with_mutex(m, throw(oops)), E, R = caught(E))"),
    ("bp13", raw"with_mutex(m, (p(X), X > 1)), R = X"),                  # 2: the goal backtracks inside
    ("bp14", raw"with_mutex(m, with_mutex(m, R = n))"),                  # nested, same mutex
    ("bp15", raw"with_mutex(m, p(X)), X > 1, R = X"),                    # fails: once/1 gave 1 only
    ("bp16", raw"with_mutex(m, (X = f(Y), Y = 1)), R = X"),              # bindings stay
    ("bp17", raw"with_mutex(m, context_module(R))"),                     # user
    ("bp18", raw"with_mutex(m, nosuchpred_bp(R))"),                      # existence_error(procedure, …)
    ("bp19", raw"with_mutex(m, true), with_mutex(n, R = two)"),
    ("bp20", raw"'$garbage_collect'(0), R = ok"),
    ("bp21", raw"'$garbage_collect'(foo), R = ok"),                      # d is read only under O_DEBUG
    ("bp22", raw"'$garbage_collect'(_), R = ok"),
    ("bp23", raw"findall(x, '$garbage_collect'(0), R)"),                 # [x]: deterministic
    ("bp24", raw"X = f(Y, Z), Y = 1, '$garbage_collect'(0), R = X-Z"),   # bindings survive
    ("bp25", raw"'$garbage_collect'(0), '$garbage_collect'(1), R = twice"),
    ("bp26", raw"length(L, 3), '$garbage_collect'(0), R = L"),
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; lk-channel evidence/BOOTPRED/bootpred_rows.out)
const _BP_PINNED = [
    "ok",
    "t_bp01 c[116,95,98,112,48,49]/1(a[109,97,105,110])",
    "t_bp02 c[116,95,98,112,48,50]/1(a[121,101,115])",
    "t_bp03",
    "t_bp04 c[116,95,98,112,48,52]/1(c[91,124,93]/2(a[109,97,105,110],nil))",
    "t_bp05",
    "t_bp06 c[116,95,98,112,48,54]/1(a[109,97,105,110])",
    "t_bp07 c[116,95,98,112,48,55]/1(a[111,107])",
    "t_bp08 c[116,95,98,112,48,56]/1(a[109,97,105,110])",
    "t_bp09 c[116,95,98,112,48,57]/1(i1)",
    "t_bp10 c[116,95,98,112,49,48]/1(c[91,124,93]/2(i1,nil))",
    "t_bp11",
    "t_bp12 c[116,95,98,112,49,50]/1(c[99,97,117,103,104,116]/1(a[111,111,112,115]))",
    "t_bp13 c[116,95,98,112,49,51]/1(i2)",
    "t_bp14 c[116,95,98,112,49,52]/1(a[110])",
    "t_bp15",
    "t_bp16 c[116,95,98,112,49,54]/1(c[102]/1(i1))",
    "t_bp17 c[116,95,98,112,49,55]/1(a[117,115,101,114])",
    "t_bp18 c[116,95,98,112,49,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[110,111,115,117,99,104,112,114,101,100,95,98,112],i1))))",
    "t_bp19 c[116,95,98,112,49,57]/1(a[116,119,111])",
    "t_bp20 c[116,95,98,112,50,48]/1(a[111,107])",
    "t_bp21 c[116,95,98,112,50,49]/1(a[111,107])",
    "t_bp22 c[116,95,98,112,50,50]/1(a[111,107])",
    "t_bp23 c[116,95,98,112,50,51]/1(c[91,124,93]/2(a[120],nil))",
    "t_bp24 c[116,95,98,112,50,52]/1(c[45]/2(c[102]/2(i1,V0),V0))",
    "t_bp25 c[116,95,98,112,50,53]/1(a[116,119,105,99,101])",
    "t_bp26 c[116,95,98,112,50,54]/1(c[91,124,93]/2(V0,c[91,124,93]/2(V1,c[91,124,93]/2(V2,nil))))"
]

function _bp_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _BP_CASES]
    text =
        _BP_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _BP_CASES
        ])
    f = joinpath(mktempdir(), "bootpred.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _bp_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_BP}()
    ld = LK.PL_local_data{_BP}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _bp_enc(ball::_BP)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_bps(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_BP, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _bp_enc(mk_expr(_BP, _BP[_bps(name), lk_answers(ld, (a:a)...)...]))
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
        push!(out, "$name" * join(" " .* sols))
    end
    return out, gd, ld
end

@testset "thread_self/1, with_mutex/2, \$garbage_collect/1 as swipl's (bp01-bp26)" begin
    f, names = _bp_file()
    kl, _, _ = _bp_kernel(f, names)
    @test length(kl) == length(_BP_PINNED)
    for (k, p) in zip(kl, _BP_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: `main` answers, the failing rows have no answer, the raised row holds the existence error, the throw row `caught(oops)`
    @test count(l -> occursin("a[109,97,105,110]", l), _BP_PINNED) >= 4            # main
    @test any(l -> l == "t_bp03", _BP_PINNED)                                      # no answer: the row failed
    @test any(l -> startswith(l, "t_bp18 ") && occursin("c[114,97,105,115,101,100]", l), _BP_PINNED)   # raised(…)
    @test any(l -> startswith(l, "t_bp12 ") && occursin("c[99,97,117,103,104,116]", l), _BP_PINNED)    # caught(…)
    # once/1: bp10 holds [1] alone
    @test any(
        l -> startswith(l, "t_bp10 ") && endswith(l, "c[91,124,93]/2(i1,nil))"), _BP_PINNED
    )
end

# KNOWN DIFFERENCE (single-thread form, pl-mutex.c:768-772): swipl 10.1.19 examines the mutex argument (`get_mutex`); the kernel does not.
@testset "with_mutex/2 does not examine its mutex (the single-thread form; swipl's answers in the comments)" begin
    # swipl: with_mutex(_, true) raises instantiation_error; with_mutex(1.5, true) raises type_error(mutex, 1.5)
    f = joinpath(mktempdir(), "bootpred_diff.pl")
    write(
        f,
        "t_d1(R) :- with_mutex(_, R = z).\nt_d2(R) :- with_mutex(1.5, R = z).\n"
    )
    kl, _, _ = _bp_kernel(f, ["t_d1", "t_d2"])
    @test kl[2] == "t_d1 c[116,95,100,49]/1(a[122])"
    @test kl[3] == "t_d2 c[116,95,100,50]/1(a[122])"
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_BP_PINNED) == length(_BP_CASES) + 1
    if swipl === nothing
        @info "BOOTPRED LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _bp_file()
        @test _bp_swipl_lines(f, names) == _BP_PINNED
    end
end
