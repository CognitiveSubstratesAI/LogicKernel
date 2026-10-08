# ORIGINAL: R1f's gate — the minimal loader (boot/init.jl `load_file!`, over read_clause, '$record_clause'/3, the source files and '$set_predicate_attribute'/3) against swipl 10.1.16's consult/1.
# test/files/test_load_swipl.jl — R1f's gate (user, 2026-10-07: "1a 2a 3a 4 yes", with additions):
#   * THE MESSAGES: each case file consulted by the kernel and by swipl, the messages swipl would
#     print compared as TERMS — swipl's captured with `user:message_hook/3` — with the load's
#     status (an exception that ended it, as consult/1 raises it) and, after it, every solution
#     of the case's predicates and whether each is dynamic. One NAMED exclusion, counted: swipl's
#     `compiler_warnings` (the compiler's variable analysis is not ported). One NAMED normalisation, counted: an
#     error a directive's goal raises has the context `system:'$c_call_prolog'/0` (the query's top
#     frame) where swipl's is `system:catch/3` (boot's wrapper; boot/init.jl `execute_directive!`);
#   * THE BENCH PROGRAMS loaded from their .pl files, their answers compared with swipl's;
#   * THE REFUSALS (decision 4): DCG rules, term_expansion, module/use_module/include/
#     initialization, conditional compilation, a reconsult, a directive that needs the meta-call,
#     a second file redefining a predicate — each an explicit `NotPortedError`.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

const _TL_SWIPL = Sys.which("swipl")
const _TL_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

# The differential's encoding of a term (the read differential's): `V<n>` the n-th variable by first
# occurrence, `nil` for `[]`, `a[codes]` an atom, `s[codes]` a string, numbers, `c[codes]/N(args)`.
function _tl_enc(t::_TL, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        is_nil(t) && return "nil"
        return "a" * _tl_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tl_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    hs = is_nil(h) ? "c[]" : "c" * _tl_codes(sym_text(h))
    return hs * "/$(nchildren(t) - 1)(" *
           join([_tl_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end
_tl_codes(s::String)::String = "[" * join(Int.(collect(s)), ",") * "]"

# swipl's messages excluded from the comparison, by name: `compiler_warnings(Clause, Warnings)` —
# the compiler's variable analysis (multitons, branch singletons) is not ported (src/pl-comp.jl).
const _TL_EXCLUDED = String[]

# The named normalisation: a directive goal's error context — swipl's boot calls the goal from
# catch/3; the kernel from the query's top frame. Counted.
const _TL_NORMALISED = Ref(0)
function _tl_normalise(t::_TL)::_TL
    if kind(t) === EXPR && nchildren(t) == 3 && kind(child(t, 1)) === SYM &&
        sym_text(child(t, 1)) == "context"
        c = child(t, 2)
        if kind(c) === EXPR && nchildren(c) == 3 && sym_text(child(c, 1)) == ":" &&
            kind(child(c, 3)) === EXPR && sym_text(child(child(c, 3), 1)) == "/" &&
            kind(child(child(c, 3), 2)) === SYM &&
            sym_text(child(child(c, 3), 2)) == "\$c_call_prolog"
            _TL_NORMALISED[] += 1
            catch3 = mk_expr(
                _TL,
                _TL[
                    _tls(":"),
                    _tls("system"),
                    mk_expr(_TL, _TL[_tls("/"), _tls("catch"), lk_gnd(_TL, 3)])
                ]
            )
            return mk_expr(_TL, _TL[child(t, 1), catch3, child(t, 3)])
        end
    end
    kind(t) === EXPR || return t
    return mk_expr(_TL, _TL[_tl_normalise(child(t, i)) for i in 1:nchildren(t)])
end

"Load `path` with the kernel: the lines the swipl driver prints for the same file."
function _tl_kernel(path::String, preds::Vector{Tuple{String, Int}})::Vector{String}
    gd, ld = LK.PL_global_data{_TL}(), LK.PL_local_data{_TL}()
    st, ball, msgs = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _tl_enc(_tl_normalise(ball::_TL))]
    for (k, m) in msgs
        push!(out, string(k) * " " * _tl_enc(_tl_normalise(m)))
    end
    for (name, arity) in preds
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), arity, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name/$arity undefined")
            continue
        end
        dyn = (proc.definition.flags & LK.P_DYNAMIC) != 0 ? "dynamic" : "static"
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, max(arity, 1))
        for i in 1:arity
            ld.slots[a + i] = mk_var(_TL, LK.fresh_var_keys!(1))
        end
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        while true
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                g = if arity == 0
                    _tls(name)
                else
                    mk_expr(
                        _TL,
                        _TL[
                            _tls(name),
                            (LK.resolve_term(ld, ld.slots[a + i]) for i in 1:arity)...
                        ]
                    )
                end
                push!(sols, _tl_enc(g))
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
        push!(out, "$name/$arity $dyn" * join(" " .* sols))
    end
    return out
end

const _TL_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
:- dynamic seen/2.
user:message_hook(T, K, _) :- ( K == warning ; K == error ), assertz(seen(K, T)), fail.
pred(N/A) :-
    functor(G, N, A),
    (   \+ current_predicate(N/A)
    ->  format("~w/~w undefined~n", [N, A])
    ;   ( predicate_property(G, dynamic) -> D = (dynamic) ; D = static ),
        format("~w/~w ~w", [N, A, D]),
        catch(forall(G, (write(' '), enc(G))), _, write(' exception')), nl
    ).
run(File, Preds) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(retract(seen(K, T)),
           (   T = compiler_warnings(_, Ws)
           ->  findall(F, (member(W, Ws), functor(W, F, _)), Fs), format("excluded ~w ~w~n", [K, Fs])
           ;   write(K), write(' '), enc(T), nl
           )),
    forall(member(P, Preds), pred(P)).
"""

"swipl's lines for consulting `path`, then the predicates `preds`."
function _tl_swipl(path::String, preds::Vector{Tuple{String, Int}})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        ps = "[" * join(["'$n'/$a" for (n, a) in preds], ",") * "]"
        write(f, _TL_DRIVER * ":- initialization((run('$path', $ps), halt)).\n")
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# The case files: (name, text, predicates to compare afterwards).
const _TL_CASES = [
    ("directives",
        ":- atom_number(abc, Z).\n:- atom_number(X, Y).\n:- Y is foo + 1.\n" *
        ":- undefined_pred_xyz.\n:- atom_number('12', N), N > 5.\n" *
        ":- atom_number('3', N), N > 5.\n:- atom_number('4', N), N > 3, atom(N).\n" *
        ":- X = f(Y), Y = 1, X == f(1).\n",
        Tuple{String, Int}[]),
    ("dynamic",
        ":- dynamic counter/1.\ncounter(0).\n:- assertz(counter(1)).\n:- dynamic foo.\n" *
        ":- dynamic atom/1.\n:- dynamic [d1/0, d2/1], (d3/2, d4//1).\n:- dynamic 3/1.\n" *
        ":- dynamic d5/(-1), d6/a, d7//x, f(x)/1, 'Q'/0, [d8/0|t].\nd2(a).\n:- dynamic(X).\n" *
        "d9(1).\n",
        [("counter", 1), ("d1", 0), ("d2", 1), ("d3", 2), ("d4", 3)]),
    ("builtins",
        "atom(x).\natom_number(a, 1).\nvar(1).\n'=='(a, b).\nmine(1).\n",
        [("atom_number", 2), ("mine", 1)]),
    ("static",
        "p(1).\n:- assertz(p(2)).\np(3).\n:- assertz(q(1)).\n",
        [("p", 1), ("q", 1)]),
    ("style",
        "p(1).\nq.\np(2).\nr(X) :- true.\ns(_X).\nt(_x).\nu(__z).\nv(_A, _A).\nw(X, X).\n" *
        ":- discontiguous dd/1.\ndd(1).\nq2.\ndd(2).\nx(A, B, C) :- y(A).\n",
        [("p", 1), ("dd", 1), ("x", 3)]),
    ("syntax",
        "a(1).\nb( .\nc(3).\nx y z.\nf(a,).\ng(1) :- .\nh(\"s\").\n'quoted'(2).\n",
        [("a", 1), ("c", 1), ("h", 1), ("quoted", 1)]),
    ("comma, [] and a variable",
        "(a, b).\n[].\nok(1).\nX.\nafter(1).\n",
        [("ok", 1), ("after", 1)]),
    ("throw",
        "before(1).\n:- throw(foo).\nafter(1).\n",
        [("before", 1), ("after", 1)]),
    ("operators",
        ":- op(700, xfx, less_than).\na less_than b.\n:- op(200, xfy, ^^).\n" *
        "x ^^ y ^^ z.\n:- op(700, xfx, foo), op(0, xfx, foo).\nfoo(1, 2).\n",
        [("less_than", 2), ("^^", 2), ("foo", 2)]),
    ("text",
        "é(1).\n'hello world'(2).\nlist([a, \"s\", 0'c, 1r3, -7]).\n" *
        "big(123456789012345678901234567890).\n",
        [("é", 1), ("hello world", 1), ("list", 1), ("big", 1)]),
    ("a built-in called, then defined",
        ":- atom_number('1', X), X == 1.\natom_number(b, 2).\n",
        [("atom_number", 2)]),
    ("a static predicate asserted into",
        "late(0).\n:- assertz(late(9)).\n:- assertz(fresh(1)).\n",
        [("late", 1), ("fresh", 1)])
]

if _TL_SWIPL !== nothing
    @testset "consulting a file, as swipl: messages, status, the predicates after" begin
        _TL_NORMALISED[] = 0
        empty!(_TL_EXCLUDED)
        mktempdir() do d
            for (i, (name, text, preds)) in enumerate(_TL_CASES)
                path = joinpath(d, "case$i.pl")
                write(path, text)
                ours = _tl_kernel(path, preds)
                theirs = _tl_swipl(path, preds)
                ex = filter(l -> startswith(l, "excluded "), theirs)
                append!(_TL_EXCLUDED, ex)
                theirs = filter(l -> !startswith(l, "excluded "), theirs)
                if ours != theirs
                    println(stderr, "  DIVERGES (", name, "):")
                    for k in 1:max(length(ours), length(theirs))
                        o = k <= length(ours) ? ours[k] : "—"
                        s = k <= length(theirs) ? theirs[k] : "—"
                        o == s || println(stderr, "    kernel ", o, "\n    swipl  ", s)
                    end
                end
                @test ours == theirs
            end
        end
        # the named normalisation is used, and only for directive goals' errors
        @test 1 <= _TL_NORMALISED[] <= 4
        # the NAMED, COUNTED exclusion: the compiler's own warnings (pl-comp.c's variable analysis,
        # `VD_*`: not ported) — exactly the one this corpus provokes, `v(_A, _A)`'s multiton
        @test _TL_EXCLUDED == ["excluded warning [multiton]"]
    end

    @testset "the bench programs, loaded from their .pl files: the answers swipl gives" begin
        prog(n) = joinpath(pkgdir(LK), "bench", "programs", n * ".pl")
        goals = [
            (
                "nreverse",
                "nreverse",
                "nreverse([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30], L)"
            ),
            ("derive", "d", "d((x+1)*((^(x,2)+2)*(^(x,3)+3)),x,D)"),
            ("derive", "d", "d(log(log(log(log(log(log(log(log(log(log(x)))))))))),x,D)"),
            ("derive", "d", "d(((((((((x/x)/x)/x)/x)/x)/x)/x)/x)/x,x,D)"),
            (
                "qsort",
                "qsort",
                "qsort([27,74,17,33,94,18,46,83,65,2,32,53,28,85,99,47,28,82,6,11,55,29,39,81,90,37,10,0,66,51,7,21,85,27,31,63,75,4,95,99,11,28,61,74,18,92,40,53,59,8],R,[])"
            ),
            ("poly_10", "test_poly", "test_poly(P)")
        ]
        for (p, _, goal) in goals
            gd, ld = LK.PL_global_data{_TL}(), LK.PL_local_data{_TL}()
            st, _, msgs = LK.load_file!(gd, ld, prog(p))
            @test st === :ok && isempty(msgs)
            # the goal, read by the kernel and run through the query API
            t2a = LK.isCurrentProcedure(
                sym_key(_tls("term_to_atom")), 2, LK.MODULE_system(gd)
            )
            fid = LK.PL_open_foreign_frame(ld)
            a = LK.PL_new_term_refs(ld, 2)
            ld.slots[a + 1] = mk_var(_TL, LK.fresh_var_keys!(1))
            ld.slots[a + 2] = _tls(goal)
            q = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, t2a, a)
            @test LK.PL_next_solution(gd, ld, q) != LK.PL_S_FALSE
            g = LK.resolve_term(ld, ld.slots[a + 1])
            LK.PL_close_query(ld, q)
            proc = LK.isCurrentProcedure(
                child(g, 1) |> sym_key, nchildren(g) - 1, LK.MODULE_user(gd)
            )
            b = LK.PL_new_term_refs(ld, nchildren(g) - 1)
            for i in 2:nchildren(g)
                ld.slots[b + i - 1] = child(g, i)
            end
            q2 = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_NORMAL, proc, b)
            rc = LK.PL_next_solution(gd, ld, q2)
            ours = if rc == LK.PL_S_FALSE
                "fails"
            else
                _tl_enc(
                    mk_expr(
                        _TL,
                        _TL[
                            child(g, 1),
                            (LK.resolve_term(ld, ld.slots[b + i - 1]) for
                             i in 2:nchildren(g))...
                        ]
                    )
                )
            end
            LK.PL_close_query(ld, q2)
            LK.PL_close_foreign_frame(ld, fid)
            theirs = mktempdir() do d
                f = joinpath(d, "b.pl")
                write(
                    f,
                    _TL_DRIVER *
                    ":- initialization((consult('$(prog(p))'), ( $goal -> enc(($goal)) ; write(fails) ), nl, halt)).\n"
                )
                chomp(read(pipeline(`swipl -q $f`; stderr=devnull), String))
            end
            @test ours == theirs
        end
    end
elseif _TL_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the loader differential would be skipped"
    )
else
    @info "LOADER DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "loader differential skipped only where it is not required" begin
        @test !_TL_SWIPL_REQUIRED
    end
end

@testset "a loaded predicate is static, with its file and lines; the file's record" begin
    mktempdir() do d
        path = joinpath(d, "src.pl")
        write(path, "a(1).\n\na(2) :-\n    true.\nb.\n")
        gd, ld = LK.PL_global_data{_TL}(), LK.PL_local_data{_TL}()
        st, _, msgs = LK.load_file!(gd, ld, path)
        @test st === :ok && isempty(msgs)
        sf = gd.files_array[1]
        @test sym_text(sf.name) == abspath(path) && sf.index == 1 && sf.count == 1
        @test sf.number_of_clauses == 3 && sf.current_procedure === nothing
        pa = LK.isCurrentProcedure(sym_key(_tls("a")), 1, LK.MODULE_user(gd))
        @test (pa.definition.flags & LK.P_DYNAMIC) == 0
        @test (pa.definition.flags & LK.FILE_ASSIGNED) != 0 && pa.source_no == 1
        @test pa in sf.procedures
        lines = Int[]
        c = pa.definition.impl_clauses.first_clause
        while c !== nothing
            cl = c.clause
            push!(lines, Int(cl.line_no))
            @test cl.source_no == 1 && cl.owner_no == 1
            c = c.next
        end
        @test lines == [1, 3]
    end
end

@testset "the refusals: explicit, never a silent misload" begin
    notported(text) = mktempdir() do d
        path = joinpath(d, "r.pl")
        write(path, text)
        gd, ld = LK.PL_global_data{_TL}(), LK.PL_local_data{_TL}()
        try
            LK.load_file!(gd, ld, path)
            false
        catch e
            e isa LK.NotPortedError || rethrow()
            true
        end
    end
    @test notported("a --> b.\n")                               # DCG (boot/dcg.pl)
    @test notported(":- module(m, []).\n")
    @test notported(":- use_module(library(lists)).\n")
    @test notported(":- ensure_loaded(x).\n")
    @test notported(":- include(x).\n")
    @test notported(":- initialization(main).\n")
    @test notported(":- if(true).\na.\n:- endif.\n")             # conditional compilation
    @test notported(":- else.\n")
    @test notported(":- (a ; b).\n")                            # the meta-call: V9
    @test notported(":- (a -> b).\n")
    @test notported(":- \\+ a.\n")
    @test notported(":- true.\n")
    @test notported(":- call(atom, a).\n")
    @test notported("term_expansion(a, b).\nx.\n")              # expand_term (R2)
    @test notported(":- dynamic(p/1 as incremental).\n")
    @test notported(":- thread_local p/1.\n")
    @test notported(":- encoding(utf8).\n")
    # a reconsult: the same file twice
    mktempdir() do d
        path = joinpath(d, "twice.pl")
        write(path, "a.\n")
        gd, ld = LK.PL_global_data{_TL}(), LK.PL_local_data{_TL}()
        @test LK.load_file!(gd, ld, path)[1] === :ok
        @test_throws LK.NotPortedError LK.load_file!(gd, ld, path)
    end
    # a file clause for a predicate asserted before (no file): swipl warns and abolishes (R2)
    @test notported(":- assertz(q(1)).\nq(2).\n")
    # a second file defining a predicate the first defined: swipl warns and abolishes (R2)
    mktempdir() do d
        p1, p2 = joinpath(d, "one.pl"), joinpath(d, "two.pl")
        write(p1, "s(1).\n")
        write(p2, "s(2).\n")
        gd, ld = LK.PL_global_data{_TL}(), LK.PL_local_data{_TL}()
        @test LK.load_file!(gd, ld, p1)[1] === :ok
        @test_throws LK.NotPortedError LK.load_file!(gd, ld, p2)
        @test ld.messages[end][1] === :warning &&
            sym_text(child(ld.messages[end][2], 1)) == "redefined_procedure"
    end
end
