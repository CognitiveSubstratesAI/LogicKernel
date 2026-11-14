# ORIGINAL: RD2b's gate — `$code_class/2` (src/pl-read.jl `pl_code_class2_va`, registered in `PL_predicates_from_read`) against swipl 10.1.20.
# test/core_text/test_code_class_swipl.jl — a program consulted by the kernel's loader whose cases `t_<id>(R)` run IN ORDER in one database
# (the design of test_read_comments_swipl.jl): cl01-cl23 the list of the eight categories (layout, symbol, solo, punct, upper, id_start, id_continue,
# invalid) a code is in, for ASCII letters, digits, symbols, solos, punctuation, layout, Greek letters, a combining mark, a no-break space, an emoji,
# an unassigned code, DEL, NUL and the euro sign; cl30-cl47 the semidet answers and the errors (an unknown category: domain_error(category, _); a
# variable code or category; a category that is not an atom; a code that is no character: -1, a code above U+10FFFF, a surrogate, a multi-character atom,
# a float, a compound, end_of_file).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, LC_ALL=C; two identical runs of the driver); with `swipl` on PATH the live answers are compared
#     with the pins too.
#   * UNVERIFIED on the kernel: written without running the kernel (edit-only step); the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream readers, built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_cls(x) = lk_sym(_CL, Symbol(x))

_cl_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _cl_enc(t::_CL, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        is_blob(t) && return "stream"           # the stream blobs of a permission_error / existence_error
        return is_nil(t) ? "nil" : "a" * _cl_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _cl_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _cl_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_cl_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the driver of test_at_body_swipl.jl (consult, then every answer of each t_<id>/1, `enc`oded)
const _CL_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- blob(T, stream), !, write(stream).
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
function _cl_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _CL_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        withenv("LC_ALL" => "C") do
            read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
        end
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program. The case predicates follow, written by `_cl_file`.
const _CL_PROGRAM = raw"""
"""

# (id, goal), run IN ORDER; `R` is the answer
const _CL_CASES = [
    (
        "cl01",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'a, K)), R)"""
    ),
    (
        "cl02",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'A, K)), R)"""
    ),
    (
        "cl03",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'_, K)), R)"""
    ),
    (
        "cl04",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'+, K)), R)"""
    ),
    (
        "cl05",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0' , K)), R)"""
    ),
    (
        "cl06",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0',, K)), R)"""
    ),
    (
        "cl07",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'(, K)), R)"""
    ),
    (
        "cl08",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'!, K)), R)"""
    ),
    (
        "cl09",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'1, K)), R)"""
    ),
    (
        "cl10",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(955, K)), R)"""
    ),
    (
        "cl11",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(923, K)), R)"""
    ),
    (
        "cl12",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(160, K)), R)"""
    ),
    (
        "cl13",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(768, K)), R)"""
    ),
    (
        "cl14",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(128512, K)), R)"""
    ),
    (
        "cl15",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(127, K)), R)"""
    ),
    (
        "cl16",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(888, K)), R)"""
    ),
    (
        "cl17",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0, K)), R)"""
    ),
    (
        "cl18",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(10, K)), R)"""
    ),
    (
        "cl19",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'|, K)), R)"""
    ),
    (
        "cl20",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'., K)), R)"""
    ),
    (
        "cl21",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(8364, K)), R)"""
    ),
    (
        "cl22",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'%, K)), R)"""
    ),
    (
        "cl23",
        raw"""findall(K, (member(K, [layout,symbol,solo,punct,upper,id_start,id_continue,invalid]), '$code_class'(0'", K)), R)"""
    ),
    (
        "cl30",
        raw"""'$code_class'(a, id_start), R = yes"""
    ),
    (
        "cl31",
        raw"""( '$code_class'(a, upper) -> R = yes ; R = no )"""
    ),
    (
        "cl32",
        raw"""( '$code_class'("A", upper) -> R = yes ; R = no )"""
    ),
    (
        "cl33",
        raw"""'$code_class'(0'a, foo), R = yes"""
    ),
    (
        "cl34",
        raw"""'$code_class'(_, layout), R = yes"""
    ),
    (
        "cl35",
        raw"""'$code_class'(0'a, _), R = yes"""
    ),
    (
        "cl36",
        raw"""'$code_class'(0'a, 1), R = yes"""
    ),
    (
        "cl37",
        raw"""'$code_class'(0'a, "id_start"), R = yes"""
    ),
    (
        "cl38",
        raw"""'$code_class'(-1, layout), R = yes"""
    ),
    (
        "cl39",
        raw"""'$code_class'(1114112, layout), R = yes"""
    ),
    (
        "cl40",
        raw"""'$code_class'(ab, layout), R = yes"""
    ),
    (
        "cl41",
        raw"""'$code_class'(1.5, layout), R = yes"""
    ),
    (
        "cl42",
        raw"""'$code_class'(f(x), layout), R = yes"""
    ),
    (
        "cl43",
        raw"""'$code_class'(end_of_file, layout), R = yes"""
    ),
    (
        "cl44",
        raw"""'$code_class'(foo, bar), R = yes"""
    ),
    (
        "cl45",
        raw"""( '$code_class'(0' , layout) -> R = yes ; R = no )"""
    ),
    (
        "cl46",
        raw"""( '$code_class'(0'\n, layout), '$code_class'(0'\t, layout) -> R = yes ; R = no )"""
    ),
    (
        "cl47",
        raw"""( '$code_class'(55296, invalid) -> R = yes ; R = no )"""
    )
]

# swipl 10.1.20, LC_ALL=C: the lines of the driver (two identical runs)
const _CL_PINNED = [
    "ok",
    "t_cl01 c[116,95,99,108,48,49]/1(c[91,124,93]/2(a[105,100,95,115,116,97,114,116],c[91,124,93]/2(a[105,100,95,99,111,110,116,105,110,117,101],nil)))",
    "t_cl02 c[116,95,99,108,48,50]/1(c[91,124,93]/2(a[117,112,112,101,114],c[91,124,93]/2(a[105,100,95,115,116,97,114,116],c[91,124,93]/2(a[105,100,95,99,111,110,116,105,110,117,101],nil))))",
    "t_cl03 c[116,95,99,108,48,51]/1(c[91,124,93]/2(a[117,112,112,101,114],c[91,124,93]/2(a[105,100,95,115,116,97,114,116],c[91,124,93]/2(a[105,100,95,99,111,110,116,105,110,117,101],nil))))",
    "t_cl04 c[116,95,99,108,48,52]/1(c[91,124,93]/2(a[115,121,109,98,111,108],nil))",
    "t_cl05 c[116,95,99,108,48,53]/1(c[91,124,93]/2(a[108,97,121,111,117,116],nil))",
    "t_cl06 c[116,95,99,108,48,54]/1(c[91,124,93]/2(a[112,117,110,99,116],nil))",
    "t_cl07 c[116,95,99,108,48,55]/1(c[91,124,93]/2(a[112,117,110,99,116],nil))",
    "t_cl08 c[116,95,99,108,48,56]/1(c[91,124,93]/2(a[115,111,108,111],nil))",
    "t_cl09 c[116,95,99,108,48,57]/1(c[91,124,93]/2(a[105,100,95,99,111,110,116,105,110,117,101],nil))",
    "t_cl10 c[116,95,99,108,49,48]/1(c[91,124,93]/2(a[105,100,95,115,116,97,114,116],c[91,124,93]/2(a[105,100,95,99,111,110,116,105,110,117,101],nil)))",
    "t_cl11 c[116,95,99,108,49,49]/1(c[91,124,93]/2(a[117,112,112,101,114],c[91,124,93]/2(a[105,100,95,115,116,97,114,116],c[91,124,93]/2(a[105,100,95,99,111,110,116,105,110,117,101],nil))))",
    "t_cl12 c[116,95,99,108,49,50]/1(c[91,124,93]/2(a[105,110,118,97,108,105,100],nil))",
    "t_cl13 c[116,95,99,108,49,51]/1(c[91,124,93]/2(a[105,100,95,99,111,110,116,105,110,117,101],nil))",
    "t_cl14 c[116,95,99,108,49,52]/1(c[91,124,93]/2(a[115,111,108,111],nil))",
    "t_cl15 c[116,95,99,108,49,53]/1(c[91,124,93]/2(a[105,110,118,97,108,105,100],nil))",
    "t_cl16 c[116,95,99,108,49,54]/1(c[91,124,93]/2(a[105,110,118,97,108,105,100],nil))",
    "t_cl17 c[116,95,99,108,49,55]/1(c[91,124,93]/2(a[105,110,118,97,108,105,100],nil))",
    "t_cl18 c[116,95,99,108,49,56]/1(c[91,124,93]/2(a[108,97,121,111,117,116],nil))",
    "t_cl19 c[116,95,99,108,49,57]/1(c[91,124,93]/2(a[112,117,110,99,116],nil))",
    "t_cl20 c[116,95,99,108,50,48]/1(c[91,124,93]/2(a[115,121,109,98,111,108],nil))",
    "t_cl21 c[116,95,99,108,50,49]/1(c[91,124,93]/2(a[115,111,108,111],nil))",
    "t_cl22 c[116,95,99,108,50,50]/1(c[91,124,93]/2(a[115,111,108,111],nil))",
    "t_cl23 c[116,95,99,108,50,51]/1(nil)",
    "t_cl30 c[116,95,99,108,51,48]/1(a[121,101,115])",
    "t_cl31 c[116,95,99,108,51,49]/1(a[110,111])",
    "t_cl32 c[116,95,99,108,51,50]/1(a[121,101,115])",
    "t_cl33 c[116,95,99,108,51,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[99,97,116,101,103,111,114,121],a[102,111,111])))",
    "t_cl34 c[116,95,99,108,51,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cl35 c[116,95,99,108,51,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cl36 c[116,95,99,108,51,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_cl37 c[116,95,99,108,51,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[105,100,95,115,116,97,114,116])))",
    "t_cl38 c[116,95,99,108,51,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i-1)))",
    "t_cl39 c[116,95,99,108,51,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i1114112)))",
    "t_cl40 c[116,95,99,108,52,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[97,98])))",
    "t_cl41 c[116,95,99,108,52,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],f1.5)))",
    "t_cl42 c[116,95,99,108,52,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],c[102]/1(a[120]))))",
    "t_cl43 c[116,95,99,108,52,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[101,110,100,95,111,102,95,102,105,108,101])))",
    "t_cl44 c[116,95,99,108,52,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[102,111,111])))",
    "t_cl45 c[116,95,99,108,52,53]/1(a[121,101,115])",
    "t_cl46 c[116,95,99,108,52,54]/1(a[121,101,115])",
    "t_cl47 c[116,95,99,108,52,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i55296)))"
]

"The program and cases as one file (in `dir`); the case predicates' names."
function _cl_file(dir::String)::Tuple{String, Vector{String}}
    ids = [id for (id, _) in _CL_CASES]
    goals = [g for (_, g) in _CL_CASES]
    names = ["t_$(id)" for id in ids]
    text =
        _CL_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in zip(ids, goals)
        ])
    f = joinpath(dir, "p.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's. A Julia exception out of a row is its line: `jlerr <type> <what>`."
function _cl_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_CL}()
    ld = LK.PL_local_data{_CL}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _cl_enc(ball::_CL)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_cls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        rld = LK.PL_local_data{_CL}(gd)        # a fresh engine per row: a Julia exception leaves no frame behind
        try
            fid = LK.PL_open_foreign_frame(rld)
            a = LK.PL_new_term_refs(rld, 1)
            LK.putSlotValue!(rld, a + 1, mk_var(_CL, LK.fresh_var_keys!(1)), LK.PutVarMap())
            qid = LK.PL_open_query(
                gd, rld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
            )
            n = 0
            while (n += 1) <= 50
                rc = LK.PL_next_solution(gd, rld, qid)
                if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                    push!(
                        sols,
                        _cl_enc(
                            mk_expr(_CL, _CL[_cls(name), lk_answers(rld, (a:a)...)...])
                        )
                    )
                    rc == LK.PL_S_LAST && break
                elseif rc == LK.PL_S_EXCEPTION
                    push!(sols, "exception")
                    break
                else
                    break
                end
            end
            LK.PL_close_query(rld, qid)
            LK.PL_close_foreign_frame(rld, fid)
        catch e
            sols = [
                "jlerr $(nameof(typeof(e)))" * (e isa LK.NotPortedError ? " $(e.what)" : "")
            ]
        end
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end


@testset "'\$code_class'/2 as swipl's (cl01-cl47)" begin
    mktempdir() do dir
        f, names = _cl_file(dir)
        kl = _cl_kernel(f, names)
        @test length(kl) == length(_CL_PINNED)
        for (k, p) in zip(kl, _CL_PINNED)
            k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
            @test k == p
        end
    end
    # not vacuous: every category is somewhere in the pins, with the errors and the failure
    for cat in ("layout", "symbol", "solo", "punct", "upper", "id_start", "id_continue", "invalid")
        @test any(l -> occursin("a" * _cl_codes(cat), l), _CL_PINNED)
    end
    @test count(l -> occursin("c[116,121,112,101,95,101,114,114,111,114]", l), _CL_PINNED) >= 8    # type_error
    @test count(l -> occursin("c[100,111,109,97,105,110,95,101,114,114,111,114]", l), _CL_PINNED) >= 1   # domain_error
    @test count(l -> occursin("a[110,111]", l), _CL_PINNED) >= 1                                     # failed
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_CL_PINNED) == length(_CL_CASES) + 1
    if swipl === nothing
        @info "RD2b LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        mktempdir() do dir
            f, names = _cl_file(dir)
            @test _cl_swipl_lines(f, names) == _CL_PINNED
        end
    end
end
