# ORIGINAL: a test of the VM YIELD of swipl-devel 10.1.19 (18168e62): engine_yield/1 (boot/engines.pl over `$engines:'$engine_yield'/2`), the
# instruction I_YIELD (pl-vmi.c:2410-2448), its resume in PL_next_solution (pl-wam.c:3870-3910), PL_yielded (pl-wam.c:3331) and PL_can_yield
# (pl-wam.c:3254-3260), reached through engine_next/2 (pl-thread.c interactor_post_answer_nolock, case YIELD_ENGINE_YIELD).
#   * NO PIN FILE, NO ORACLE RUN WHEN THIS FILE WAS WRITTEN. The harness is the one of test_engines_swipl.jl (rows are clauses `ck_<id>(R)` of ONE
#     program, run by the kernel and, live, by swipl); every expected value is READ FROM THE C and written as a Prolog term. A live mismatch
#     means MY READING OF THE C WAS WRONG: the EXPECTED column is corrected, never the kernel.
#     MEASURE ON THE LANE (first run, once): `swipl -q <driver.pl>` with `:- initialization((fz_run('<program>', [ck_ey01, ...]), halt)).`
#     as `_ey_swipl_lines` does (write the program with `_ey_program(_EY_CASES)`); every line must read `ck_<id> c[..]/1(a[111,107])`.
#     Rows I am least sure of: ey11 (an unbound yield code: pl-error.c ERR_TYPE on a variable is instantiation_error), ey12 (the permission
#     error text of an I_YIELD outside an engine; test_cont_boot_swipl.jl pins the same from the oracle), ey14 (a float and a big integer
#     compared by =@=: the same value on both sides).
#   * The row `eyk1` is the kernel's named DIVERGES (TH1): a type error of I_YIELD that is CAUGHT inside the engine leaves `yield.term` set upstream
#     (a later normal answer would be misread as a yield); the kernel resets `yield_term` and `foreign_frame` before the throw. Kernel only.
#   * The white-box testsets read the raw API (`PL_open_query` with `PL_Q_ALLOW_YIELD`, `PL_yielded`, `PL_can_yield`, the query record).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — engines and the VM yield ride the term layer through the FLI (record, recorded, unify)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _EY = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_eys(x) = lk_sym(_EY, Symbol(x))

_ey_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _ey_enc(t::_EY, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ey_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ey_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ey_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ey_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _EY_DRIVER = raw"""
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

function _ey_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _EY_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# A row: (id, setup, goal, expected, live). The goal sets `R0` on success; when it fails R0 is `failed`; an `error(E, _)` it raises is
# `raised(E)` (the goal is wrapped in catch/3, which undoes its bindings: the engine handles are made in SETUP, outside the catch).
# `$` is in the text of the rows that call the private predicate `$engines:$engine_yield/2`: they are raw strings.
const _EY_CASES = [
    # the yield term comes back from engine_next/2, the next call resumes after the yield (pl-vmi.c I_YIELD; pl-wam.c resume)
    (
        "ey01", "engine_create(X, (member(X,[a,b]), engine_yield(y(X))), E)",
        "engine_next(E,A1), engine_next(E,A2), engine_next(E,A3), engine_next(E,A4), ( engine_next(E,_) -> F = y ; F = n ), R0 = [A1,A2,A3,A4,F]",
        "[y(a),a,y(b),b,n]", true
    ),
    # what is yielded: an unbound variable, a shared variable, a binding made before the yield (yield.term links argument 1)
    (
        "ey02", "engine_create(_, engine_yield(_), E)",
        "engine_next(E,A), ( var(A) -> R0 = isvar ; R0 = nonvar )", "isvar", true
    ),
    (
        "ey03", "engine_create(_, engine_yield(f(X,X,_)), E)",
        "engine_next(E,A), A = f(P,Q,_), ( P == Q -> R0 = shared ; R0 = distinct )", "shared",
        true
    ),
    ("ey04", "engine_create(X, (X = 1, engine_yield(X)), E)", "engine_next(E,A), R0 = A", "1", true),
    # the reified form: yields are answers (`the/1`), the end is `no`
    (
        "ey05", "engine_create(_, (engine_yield(a), engine_yield(b)), E)",
        "engine_next_reified(E,A), engine_next_reified(E,B), engine_next_reified(E,C), engine_next_reified(E,D), R0 = [A,B,C,D]",
        "[the(a),the(b),the(_),no]", true
    ),
    # yield, then engine_post/3 delivers a term that the engine fetches after the yield
    (
        "ey06",
        "engine_create(_, (engine_yield(a), engine_fetch(F), engine_yield(f(F))), E)",
        "engine_next(E,A), engine_post(E,foo,B), R0 = A-B", "a-f(foo)", true
    ),
    # a yield deeper in the stack: under findall/3 (frames and a younger choice point above the engine's query)
    (
        "ey07",
        "engine_create(L, findall(X, (member(X,[1,2]), engine_yield(y(X))), L), E)",
        "engine_next(E,A), engine_next(E,B), engine_next(E,C), R0 = [A,B,C]",
        "[y(1),y(2),[1,2]]", true
    ),
    # the yield and the control constructs: a catch/3 around it, a cut after it
    (
        "ey08",
        "engine_create(_, catch((engine_yield(1), throw(oops)), oops, engine_yield(caught)), E)",
        "engine_next(E,A), engine_next(E,B), R0 = [A,B]", "[1,caught]", true
    ),
    (
        "ey09", "engine_create(X, (member(X,[1,2,3]), engine_yield(X), !), E)",
        "engine_next(E,A), engine_next(E,B), ( engine_next(E,_) -> F = y ; F = n ), R0 = [A,B,F]",
        "[1,1,n]", true
    ),
    # a yield code that is not an integer: the type error of I_YIELD (pl-vmi.c:2441-2447), raised in the engine and carried to the caller
    (
        "ey10", raw"engine_create(_, '$engines':'$engine_yield'(a,foo), E)",
        "engine_next(E,_)", "raised(type_error(integer,foo))", true
    ),
    (
        "ey11", raw"engine_create(_, '$engines':'$engine_yield'(a,_), E)",
        "engine_next(E,_)", "raised(instantiation_error)", true
    ),
    # a yield from a query that did not ask for it (the main thread's query): the permission error of I_YIELD
    (
        "ey12", "true", "engine_yield(x)", "raised(permission_error(execute,vmi,'I_YIELD'))",
        true
    ),
    # an engine inside an engine, the inner one yields
    (
        "ey13",
        "engine_create(_, (engine_create(_, engine_yield(in), I), engine_next(I,Z), engine_yield(out(Z))), E)",
        "engine_next(E,A), R0 = A", "out(in)", true
    ),
    # a number of every kind through the yield: a float and a big integer
    (
        "ey14", "engine_create(_, engine_yield(g(2.5, 12345678901234567890)), E)",
        "engine_next(E,A), R0 = A", "g(2.5, 12345678901234567890)", true
    ),
    # destroy while yielded: the query is closed with its yield foreign frame still open
    (
        "ey15", "engine_create(_, (engine_yield(1), engine_yield(2)), E)",
        "engine_next(E,A), engine_destroy(E), catch(engine_next(E,_), error(Err,_), true), R0 = A-Err",
        "1-existence_error(engine,E)", true
    ),
    # many yields from one engine, each resuming where the last stopped
    (
        "ey16",
        "engine_create(_, (between(1,200,I), engine_yield(I), fail ; true), E)",
        "numlist(1,200,N), findall(A, (member(_,N), engine_next(E,A)), L), ( L == N -> R0 = ok ; R0 = bad )",
        "ok", true
    ),
    # the named DIVERGES (TH1), kernel only: a type error CAUGHT in the engine does not leave `yield_term` set
    (
        "eyk1",
        raw"engine_create(X, (catch('$engines':'$engine_yield'(a,foo), _, true), member(X,[a,b])), E)",
        "engine_next(E,A), engine_next(E,B), R0 = A-B", "a-b", false
    )
]

"The program of `cases`: one clause `ck_<id>(R)` per row (R is `ok`, or `bad(Got)`)."
function _ey_program(cases)::String
    return join(
        [
            "ck_$(c[1])(R) :- $(c[2]), ( catch(($(c[3])), error(SsuE, _), R0 = raised(SsuE)) -> true ; R0 = failed ), " *
            "( R0 =@= ($(c[4])) -> R = ok ; R = bad(R0) ).\n" for c in cases
        ]
    )
end

"The line a passing row gives: the driver's `enc` of `ck_<id>(ok)`."
_ey_ok_line(id) = "ck_$id c$(_ey_codes("ck_$id"))/1(a[111,107])"

function _ey_file(cases)::Tuple{String, Vector{String}}
    f = joinpath(mktempdir(), "engine_yield.pl")
    write(f, _ey_program(cases))
    return f, ["ck_$(c[1])" for c in cases]
end

"A fresh kernel with the file consulted: `(gd, ld, first line of the driver's output)`."
function _ey_load(path::String)
    gd = LK.PL_global_data{_EY}()
    ld = LK.PL_local_data{_EY}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * _ey_enc(ball::_EY))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _ey_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_eys(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_EY, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, _ey_enc(mk_expr(_EY, _EY[_eys(pred), lk_answers(ld, (a:a)...)...])))
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
    return pred * join(" " .* sols)
end

"The kernel's lines for `names` after consulting `path`."
function _ey_kernel(path::String, names::Vector{String})
    gd, ld, st = _ey_load(path)
    out = [st]
    for name in names
        push!(out, _ey_ask(gd, ld, name))
    end
    return out, gd, ld
end

function _ey_check(cases)
    f, names = _ey_file(cases)
    kl, gd, ld = _ey_kernel(f, names)
    @test kl[1] == "ok"
    @test length(kl) == length(cases) + 1
    for (c, line) in zip(cases, kl[2:end])
        want = _ey_ok_line(c[1])
        line == want || println(stderr, "  row $(c[1]): ours  ", line, "\n          wanted ", want)
        @test line == want
    end
    return gd, ld
end

@testset "engine_yield/1 and the VM yield as pl-vmi.c's (C-derived rows, kernel)" begin
    _ey_check(_EY_CASES)
end

@testset "the yield rows are not vacuous" begin
    ids = [c[1] for c in _EY_CASES]
    @test length(unique(ids)) == length(ids)
    for c in _EY_CASES
        @test !isempty(c[3]) && !isempty(c[4]) && c[4] != "_"    # a row whose expectation cannot fail
    end
    for n in 1:16
        @test "ey" * lpad(n, 2, '0') in ids
    end
    @test count(c -> !c[5], _EY_CASES) == 1                 # eyk1 is the only kernel-only row
    @test _ey_ok_line("ey01") == "ck_ey01 c[99,107,95,101,121,48,49]/1(a[111,107])"
    # the rows that call the private predicate carry the `$` of its name: a raw string that a mistaken interpolation would have emptied
    @test count(c -> occursin("\$engine_yield", c[2]), _EY_CASES) == 3
end

@testset "the yield rows are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "ENGINE YIELD LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        live = filter(c -> c[5], _EY_CASES)
        f, names = _ey_file(live)
        lines = _ey_swipl_lines(f, names)
        @test length(lines) == length(live) + 1
        @test lines[1] == "ok"
        for (c, line) in zip(live, lines[2:end])
            line == _ey_ok_line(c[1]) || println(stderr, "  swipl row $(c[1]): ", line)
            @test line == _ey_ok_line(c[1])
        end
    end
end

# WHITE-BOX: the raw API. A query opened with `PL_Q_ALLOW_YIELD | PL_Q_EXT_STATUS` returns the yield code from PL_next_solution, `PL_yielded`
# names the term reference of the yielded term, the next PL_next_solution resumes (pl-wam.c:3870-3910) and clears `yield_term`.
const _EY_WB = raw"""
ey_wb(X) :- engine_yield(f(X)), X = 1.
ey_wb2(_) :- '$engines':'$engine_yield'(g(1), 300).
ey_wb3(_) :- engine_yield(x).
"""

"Consult the white-box program; return `(gd, ld)`."
function _ey_wb_load()
    f = joinpath(mktempdir(), "ey_wb.pl")
    write(f, _EY_WB)
    gd, ld, st = _ey_load(f)
    @test st == "ok"
    return gd, ld
end

"Open a query on `pred/1` with an unbound argument: `(fid, a, qid)`."
function _ey_wb_open(gd, ld, pred::String, flags::UInt32)
    proc = LK.isCurrentProcedure(sym_key(_eys(pred)), 1, LK.MODULE_user(gd))
    @test proc !== nothing && LK.isDefinedProcedure(gd, proc)
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_EY, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, flags, proc, a)
    return fid, a, qid
end

const _EY_FLAGS = LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS | LK.PL_Q_ALLOW_YIELD

@testset "engine yield: white-box (the yield code, PL_yielded, the resume, PL_can_yield)" begin
    gd, ld = _ey_wb_load()
    @test !LK.PL_can_yield(ld)                          # no query open
    fid, a, qid = _ey_wb_open(gd, ld, "ey_wb", _EY_FLAGS)
    q = ld.queries[LK.QueryFromQid(ld, qid)]
    @test q.yield_term == 0                             # PL_open_query: qf->yield.term = 0
    @test LK.PL_can_yield(ld)                           # the innermost query was opened with PL_Q_ALLOW_YIELD
    rc = LK.PL_next_solution(gd, ld, qid)
    @test rc == 256                                     # the yield code of engine_yield/1
    t = LK.PL_yielded(ld, qid)
    @test t != 0
    @test q.yield_term == t
    @test _ey_enc(lk_answers(ld, t)[1]) == "c[102]/1(V0)"   # f(_): the yielded term, argument 1 of the instruction
    rc = LK.PL_next_solution(gd, ld, qid)               # resumes after the yield: X = 1, then the clause exits
    @test rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
    @test q.yield_term == 0                             # the resume cleared it
    @test _ey_enc(lk_answers(ld, a)[1]) == "i1"
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test !LK.PL_can_yield(ld)                          # the query is closed
end

@testset "engine yield: white-box (a code of the caller's choice, 300)" begin
    gd, ld = _ey_wb_load()
    fid, a, qid = _ey_wb_open(gd, ld, "ey_wb2", _EY_FLAGS)
    rc = LK.PL_next_solution(gd, ld, qid)
    @test rc == 300                                     # `Code must be an integer >= 256`: the value is returned as it is
    t = LK.PL_yielded(ld, qid)
    @test t != 0
    @test _ey_enc(lk_answers(ld, t)[1]) == "c[103]/1(i1)"
    rc = LK.PL_next_solution(gd, ld, qid)
    @test rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end

@testset "engine yield: white-box (a query that did not ask to yield refuses, PL_can_yield is false)" begin
    gd, ld = _ey_wb_load()
    fid, a, qid = _ey_wb_open(gd, ld, "ey_wb3", LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS)
    @test !LK.PL_can_yield(ld)
    rc = LK.PL_next_solution(gd, ld, qid)
    @test rc == LK.PL_S_EXCEPTION                       # permission_error(execute, vmi, 'I_YIELD')
    @test LK.PL_yielded(ld, qid) == 0
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end

@testset "engine yield: white-box (a yielded query is closed, the record of the next one starts clean)" begin
    gd, ld = _ey_wb_load()
    fid, a, qid = _ey_wb_open(gd, ld, "ey_wb", _EY_FLAGS)
    q1 = ld.queries[LK.QueryFromQid(ld, qid)]
    @test LK.PL_next_solution(gd, ld, qid) == 256
    @test q1.yield_term != 0
    LK.PL_close_query(ld, qid)                          # closed while yielded: its yield foreign frame goes with it
    LK.PL_close_foreign_frame(ld, fid)
    fid2, a2, qid2 = _ey_wb_open(gd, ld, "ey_wb", _EY_FLAGS)
    q2 = ld.queries[LK.QueryFromQid(ld, qid2)]
    @test q2 === q1                                     # pushQuery! reuses the record of the same depth (the pool)
    @test q2.yield_term == 0                            # PL_open_query resets it: a stale one would read as a resume
    @test LK.PL_next_solution(gd, ld, qid2) == 256      # the first call of the new query runs from the start
    @test _ey_enc(lk_answers(ld, LK.PL_yielded(ld, qid2))[1]) == "c[102]/1(V0)"
    LK.PL_close_query(ld, qid2)
    LK.PL_close_foreign_frame(ld, fid2)
end
