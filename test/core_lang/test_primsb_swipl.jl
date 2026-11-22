# ORIGINAL: a LIVE differential of PRIMS-B's copy predicates — copy_term/4, copy_term_nat/4, size_abstract_term/3
# (pl-copyterm.c) — against swipl at the pin: rows b43-b45 (the size errors), c01-c43. (term_hash/2, variant_hash/2 and
# term_hash/4 are test_term_hash_pred_swipl.jl's.)
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(E, _), R = raised(E))`; the driver is test_p2_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, the pin binary, swipl-devel 18168e62; two runs byte-identical); with `swipl` on PATH the live answers
#     are compared with the pins too.
#   * b43-b45 the size error rows of size_abstract_term/3 (its size argument is checked first, as upstream: pl-copyterm.c
#     PRED_IMPL size_abstract_term).
#   * c01-c26 copy_term/4 and copy_term_nat/4 (only the variables of the first argument copied; attributed variables, shared
#     subterms, variables of a copied attribute); c30-c43 size_abstract_term/3 (the abstract depth, attributes, shared variables).
#     Kernel and swipl answers are equal (no known difference).
#   * UNVERIFIED on the kernel: gate decides (nothing was compiled when these rows were written): every kernel answer.

using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the predicates ride the term layer through export_cells and PL_unify_integer
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _PB = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_pbs(x) = lk_sym(_PB, Symbol(x))

_pb_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"The atom `s` as the driver's `enc/1` writes it."
_pb_a(s::String) = "a" * _pb_codes(s)

"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _pb_enc(t::_PB, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : _pb_a(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _pb_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _pb_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_pb_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_p2_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _PB_DRIVER = raw"""
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
function _pb_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _PB_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

const _PB_CASES = [
    ("b43", raw"size_abstract_term(foo, a, _)"),
    ("b44", raw"size_abstract_term(-1, a, _)"),
    ("b45", raw"size_abstract_term(_, a, _)")
]

const _PB_COPY_CASES = [
    ("c01", raw"copy_term([X], f(X,Y), Vs, T), Vs = [V], T = f(V2, Z), V == V2, V \== X, Z == Y, R = yes"),
    ("c02", raw"copy_term([X], f(X,Y,X), Vs, T), T = f(A,B,C), A == C, B == Y, A \== X, Vs = [A], R = yes"),
    ("c03", raw"copy_term([], f(X), Vs, T), Vs = [], T = f(Z), Z == X, R = yes"),
    ("c04", raw"size_abstract_term(1, f(g(h(a)),b), T), R = T"),
    ("c05", raw"size_abstract_term(0, f(a,b), T), R = T"),
    ("c06", raw"size_abstract_term(100, f(a,b), T), R = T"),
    ("c07", raw"size_abstract_term(3, [a,b,c,d,e,f], T), R = T"),
    ("c08", raw"copy_term([X], f(X,Y), Vs, T), R = Vs-T"),
    ("c09", raw"copy_term([X,Y], g(X,Y,Z,X), Vs, T), R = Vs-T"),
    ("c10", raw"copy_term([a,X], f(X), Vs, T), R = Vs-T"),
    ("c11", raw"copy_term(g(X,h(Y)), f(X,Y,Z), Vs, T), R = Vs-T"),
    ("c12", raw"copy_term(V, f(X), Vs, T), Vs \== V, T = f(Z), Z == X, R = yes"),
    ("c13", raw"put_attr(X, a, 1), copy_term([X], f(X), Vs, T), Vs = [V], get_attr(V, a, A), R = A"),
    ("c14", raw"put_attr(X, a, 1), copy_term_nat([X], f(X), Vs, T), Vs = [V], ( get_attr(V, a, _) -> R = attr ; R = noattr )"),
    ("c15", raw"put_attr(X, a, 1), copy_term([], f(X), Vs, T), T = f(Z), ( Z == X -> R = same ; R = differ )"),
    ("c16", raw"put_attr(X, a, g(Y)), copy_term([X], f(X), Vs, T), Vs = [V], get_attr(V, a, g(W)), ( W == Y -> R = same ; R = differ )"),
    ("c17", raw"copy_term_nat([X], f(X,Y), Vs, T), Vs = [V], T = f(V2, Z), V == V2, V \== X, Z == Y, R = yes"),
    ("c18", raw"put_attr(X, a, 1), copy_term_nat([], f(X), Vs, T), T = f(Z), ( Z == X -> R = same ; R = differ )"),
    ("c19", raw"S = h(X), copy_term([X], f(S,S), Vs, T), T = f(A,B), ( same_term(A, B) -> R = shared ; R = apart )"),
    ("c20", raw"S = h(a), copy_term([X], f(X,S,S), Vs, T), T = f(_,A,B), ( same_term(A, S), same_term(B, S) -> R = shared ; R = apart )"),
    ("c21", raw"copy_term([X], f(X,X), Vs, T), T = f(A,B), A == B, Vs = [V], V == A, R = yes"),
    ("c22", raw"copy_term_nat([X,Y], f(X,Y), Vs, T), R = Vs-T"),
    ("c23", raw"copy_term([X], f(Y), Vs, T), R = Vs-T"),
    ("c24", raw"copy_term(foo, bar, Vs, T), R = Vs-T"),
    ("c25", raw"copy_term([X], X, Vs, T), Vs = [V], T == V, V \== X, R = yes"),
    ("c26", raw"copy_term([X], f(X), [a], T), R = T"),
    ("c30", raw"size_abstract_term(2, f(g(h(a)),b), T), R = T"),
    ("c31", raw"put_attr(X, a, 1), size_abstract_term(5, f(X), T), T = f(V), get_attr(V, a, A), R = A"),
    ("c32", raw"size_abstract_term(2, f(X,Y,X), T), R = T"),
    ("c33", raw"size_abstract_term(0, a, T), R = T"),
    ("c34", raw"size_abstract_term(0, X, T), R = T"),
    ("c35", raw"size_abstract_term(3, f(g(a),h(b),i(c)), T), R = T"),
    ("c36", raw"size_abstract_term(2, [a,b,c], T), R = T"),
    ("c37", raw"size_abstract_term(1, f(g(a),g(b)), T), R = T"),
    ("c38", raw"S = g(h(a)), size_abstract_term(2, f(S,S), T), R = T"),
    ("c39", raw"size_abstract_term(1, f(a), T), R = T"),
    ("c40", raw"size_abstract_term(2, f(g(a,b),h(c)), T), R = T"),
    ("c41", raw"size_abstract_term(4, f(g(X),h(X)), T), T = f(g(A),h(B)), ( A == B -> R = same ; R = differ )"),
    ("c42", raw"size_abstract_term(1, f(g(X)), T), R = T"),
    ("c43", raw"size_abstract_term(1, f(g(X)), T), T = f(A), ( A == X -> R = same ; R = fresh )")
]

# the driver's whole output, one line per case after `ok`, from swipl 10.1.20 (the pin binary, swipl-devel 18168e62; two runs byte-identical)
const _PB_PINNED = [
    "ok",
    "t_b43 c[116,95,98,52,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111])))",
    "t_b44 c[116,95,98,52,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_b45 c[116,95,98,52,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))"
]

const _PB_COPY_PINNED = [
    "ok",
    "t_c01 c[116,95,99,48,49]/1(a[121,101,115])",
    "t_c02 c[116,95,99,48,50]/1(a[121,101,115])",
    "t_c03 c[116,95,99,48,51]/1(a[121,101,115])",
    "t_c04 c[116,95,99,48,52]/1(c[102]/2(c[103]/1(V0),a[98]))",
    "t_c05 c[116,95,99,48,53]/1(c[102]/2(a[97],a[98]))",
    "t_c06 c[116,95,99,48,54]/1(c[102]/2(a[97],a[98]))",
    "t_c07 c[116,95,99,48,55]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],c[91,124,93]/2(a[100],V0)))))",
    "t_c08 c[116,95,99,48,56]/1(c[45]/2(c[91,124,93]/2(V0,nil),c[102]/2(V0,V1)))",
    "t_c09 c[116,95,99,48,57]/1(c[45]/2(c[91,124,93]/2(V0,c[91,124,93]/2(V1,nil)),c[103]/4(V0,V1,V2,V0)))",
    "t_c10 c[116,95,99,49,48]/1(c[45]/2(c[91,124,93]/2(a[97],c[91,124,93]/2(V0,nil)),c[102]/1(V0)))",
    "t_c11 c[116,95,99,49,49]/1(c[45]/2(c[103]/2(V0,c[104]/1(V1)),c[102]/3(V0,V1,V2)))",
    "t_c12 c[116,95,99,49,50]/1(a[121,101,115])",
    "t_c13 c[116,95,99,49,51]/1(i1)",
    "t_c14 c[116,95,99,49,52]/1(a[110,111,97,116,116,114])",
    "t_c15 c[116,95,99,49,53]/1(a[115,97,109,101])",
    "t_c16 c[116,95,99,49,54]/1(a[100,105,102,102,101,114])",
    "t_c17 c[116,95,99,49,55]/1(a[121,101,115])",
    "t_c18 c[116,95,99,49,56]/1(a[115,97,109,101])",
    "t_c19 c[116,95,99,49,57]/1(a[115,104,97,114,101,100])",
    "t_c20 c[116,95,99,50,48]/1(a[115,104,97,114,101,100])",
    "t_c21 c[116,95,99,50,49]/1(a[121,101,115])",
    "t_c22 c[116,95,99,50,50]/1(c[45]/2(c[91,124,93]/2(V0,c[91,124,93]/2(V1,nil)),c[102]/2(V0,V1)))",
    "t_c23 c[116,95,99,50,51]/1(c[45]/2(c[91,124,93]/2(V0,nil),c[102]/1(V1)))",
    "t_c24 c[116,95,99,50,52]/1(c[45]/2(a[102,111,111],a[98,97,114]))",
    "t_c25 c[116,95,99,50,53]/1(a[121,101,115])",
    "t_c26 c[116,95,99,50,54]/1(c[102]/1(a[97]))",
    "t_c30 c[116,95,99,51,48]/1(c[102]/2(c[103]/1(c[104]/1(a[97])),a[98]))",
    "t_c31 c[116,95,99,51,49]/1(i1)",
    "t_c32 c[116,95,99,51,50]/1(c[102]/3(V0,V1,V0))",
    "t_c33 c[116,95,99,51,51]/1(a[97])",
    "t_c34 c[116,95,99,51,52]/1(V0)",
    "t_c35 c[116,95,99,51,53]/1(c[102]/3(c[103]/1(a[97]),c[104]/1(a[98]),c[105]/1(a[99])))",
    "t_c36 c[116,95,99,51,54]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil))))",
    "t_c37 c[116,95,99,51,55]/1(c[102]/2(c[103]/1(a[97]),c[103]/1(a[98])))",
    "t_c38 c[116,95,99,51,56]/1(c[102]/2(c[103]/1(c[104]/1(a[97])),c[103]/1(c[104]/1(a[97]))))",
    "t_c39 c[116,95,99,51,57]/1(c[102]/1(a[97]))",
    "t_c40 c[116,95,99,52,48]/1(c[102]/2(c[103]/2(a[97],a[98]),c[104]/1(a[99])))",
    "t_c41 c[116,95,99,52,49]/1(a[115,97,109,101])",
    "t_c42 c[116,95,99,52,50]/1(c[102]/1(c[103]/1(V0)))",
    "t_c43 c[116,95,99,52,51]/1(a[102,114,101,115,104])"
]

"The program's text for `cases`, each wrapped as the driver expects."
_pb_text(cases) =
    join([
        "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for (id, g) in cases
    ])

function _pb_file(cases)::Tuple{String, Vector{String}}
    f = joinpath(mktempdir(), "primsb.pl")
    write(f, _pb_text(cases))
    return f, ["t_$(id)" for (id, _) in cases]
end

"""
The kernel's lines for `names` after consulting `path`, as the driver writes swipl's, and the `NotPortedError`s met
(a refused predicate ends the run: the line is `<name> notported`, the database is thrown away).
"""
function _pb_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_PB}()
    ld = LK.PL_local_data{_PB}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _pb_enc(ball::_PB)]
    refused = LK.NotPortedError[]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_pbs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_PB, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = try
                LK.PL_next_solution(gd, ld, qid)
            catch e
                e isa LK.NotPortedError || rethrow()
                push!(refused, e)
                push!(out, "$name notported")
                return out, refused                  # the run's ld is thrown away: the query stays open
            end
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _pb_enc(mk_expr(_PB, _PB[_pbs(name), lk_answers(ld, (a:a)...)...]))
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
    return out, refused
end

"The answer part of the pinned line of case `id` (empty: the case failed)."
function _pb_answer(pins::Vector{String}, id::String)::String
    for l in pins
        startswith(l, "t_$id") || continue
        return l == "t_$id" ? "" : String(split(l, ' '; limit=2)[2])
    end
    error("no pinned line for $id")
end
"An answer line as `t_<id>(R)` writes `R = word`: the case's functor and one atom."
_pb_word(w::String) = "/1(" * _pb_a(w) * ")"

@testset "PRIMS-B the size_abstract_term/3 size errors as swipl's (b43-b45)" begin
    f, names = _pb_file(_PB_CASES)
    kl, refused = _pb_kernel(f, names)
    @test isempty(refused)
    @test length(kl) == length(_PB_PINNED)
    for (k, p) in zip(kl, _PB_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "PRIMS-B copy_term/4, copy_term_nat/4 and size_abstract_term/3 as swipl's (c01-c43)" begin
    f, names = _pb_file(_PB_COPY_CASES)
    kl, refused = _pb_kernel(f, names)
    @test isempty(refused)
    @test length(kl) == length(_PB_COPY_PINNED)
    for (k, p) in zip(kl, _PB_COPY_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the PRIMS-B rows are not vacuous" begin
    @test _PB_PINNED[1] == "ok" && _PB_COPY_PINNED[1] == "ok"
    @test length(_PB_PINNED) == length(_PB_CASES) + 1
    @test length(_PB_COPY_PINNED) == length(_PB_COPY_CASES) + 1
    pin(id) = _pb_answer(_PB_PINNED, id)
    # the size error rows raise
    for id in ("b43", "b44", "b45")
        @test occursin("[114,97,105,115,101,100]", pin(id))
    end
    # the copy rows' answers (swipl's): every row answers, none raises, and the checks say what they check
    rp(id) = _pb_answer(_PB_COPY_PINNED, id)
    for (id, _) in _PB_COPY_CASES
        @test rp(id) != ""
        @test !occursin("raised", rp(id))
    end
    for id in ("c01", "c02", "c03", "c12", "c17", "c21", "c25")
        @test endswith(rp(id), _pb_word("yes"))
    end
    @test endswith(rp("c13"), "/1(i1)") && endswith(rp("c31"), "/1(i1)")       # the attribute is copied
    @test endswith(rp("c14"), _pb_word("noattr"))                                 # copy_term_nat/4 drops it
    for id in ("c15", "c18", "c41")
        @test endswith(rp(id), _pb_word("same"))
    end
    @test endswith(rp("c16"), _pb_word("differ"))             # a variable in a copied attribute is copied
    for id in ("c19", "c20")
        @test endswith(rp(id), _pb_word("shared"))
    end
    @test endswith(rp("c43"), _pb_word("fresh"))
    # the abstract depth: beyond it a compound is a variable
    @test occursin("V0", rp("c04")) && occursin("c[103]/1(V0)", rp("c04"))
    @test !occursin("V0", rp("c30")) && !occursin("V0", rp("c35"))
end

@testset "the PRIMS-B pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_PB_PINNED) == length(_PB_CASES) + 1
    if swipl === nothing
        @info "PRIMS-B LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _pb_file(_PB_CASES)
        @test _pb_swipl_lines(f, names) == _PB_PINNED
        f, names = _pb_file(_PB_COPY_CASES)
        @test _pb_swipl_lines(f, names) == _PB_COPY_PINNED
    end
end
