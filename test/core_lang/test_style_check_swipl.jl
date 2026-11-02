# ORIGINAL: a LIVE differential of Q10's `'$style_check'/2` (pl-prims.c:6523-6537) against swipl at the pin — Q10's rows
# test/core_lang/test_style_check_swipl.jl — `'$style_check'(-Old, +New)` (sc01-sc20) against swipl 10.1.19:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_bootpred_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, lk-channel evidence/Q10/q10_rows.out on the
#     Q10 branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * The style set is state shared by the rows: every row that changes it sets it back to 202 (SINGLETON_CHECK |
#     SEMSINGLETON_CHECK | DISCONTIGUOUS_STYLE | NOEFFECT_CHECK, pl-init.c:1663) before it ends, a row that fails after
#     a change restores it inside the row; a row that must fail changes nothing.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through PL_unify_integer and PL_get_integer only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _SC = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_scs(x) = lk_sym(_SC, Symbol(x))


_sc_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _sc_enc(t::_SC, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _sc_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _sc_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _sc_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_sc_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _SC_DRIVER = raw"""
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
function _sc_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _SC_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end



# the program: two facts, so the consult has a clause to compile with the style set as it is (the rows read the set, not the warnings)
const _SC_PROGRAM = raw"""
sc_p(1).
sc_p(2).
"""

# sc01-sc02 the default and the unifying old value; sc03-sc04 old and new in one call, and the new value read back;
# sc05-sc10 the failures that change nothing (old does not unify, new is no int, new out of the C int's range);
# sc11-sc13 the C int's bounds; sc14-sc15 determinism and an unchanged set; sc16-sc20 the failing call after a change
const _SC_CASES = [
    ("sc01", raw"'$style_check'(O, O), R = O"),                          # 202
    ("sc02", raw"'$style_check'(202, 202), R = yes"),
    ("sc03", raw"'$style_check'(O, 5), '$style_check'(P, 202), R = O-P"),  # 202-5
    ("sc04", raw"'$style_check'(_, 0), '$style_check'(P, 202), R = P"),     # 0
    ("sc05", raw"'$style_check'(1, 1), R = yes"),                        # fails: old is 202
    ("sc06", raw"'$style_check'(_, a), '$style_check'(P, P), R = P"),    # fails: new is no integer
    ("sc07", raw"'$style_check'(_, _), R = yes"),                        # fails: new is unbound
    ("sc08", raw"'$style_check'(_, 2.0), R = yes"),                      # fails: a float is no int
    ("sc09", raw"'$style_check'(a, 202), R = yes"),                      # fails: old does not unify
    ("sc10", raw"'$style_check'(_, 2147483648), R = yes"),               # fails: out of the C int's range
    ("sc11", raw"'$style_check'(O, 2147483647), '$style_check'(P, 202), R = O-P"),
    ("sc12", raw"'$style_check'(O, -1), '$style_check'(P, 202), R = O-P"),
    ("sc13", raw"'$style_check'(_, -2147483648), '$style_check'(P, 202), R = P"),
    ("sc14", raw"'$style_check'(_, 202), '$style_check'(P, P), R = P"),
    ("sc15", raw"findall(X, '$style_check'(X, 202), R)"),                # [202]: one answer, no choice point
    (
        "sc16",
        raw"'$style_check'(_, 7), ( '$style_check'(_, b) -> R = yes ; '$style_check'(P, 202), R = no(P) )"
    ),   # no(7)
    (
        "sc17",
        raw"'$style_check'(_, 7), ( '$style_check'(9, 3) -> R = yes ; '$style_check'(P, 202), R = no(P) )"
    ),   # no(7)
    (
        "sc18",
        raw"'$style_check'(_, 7), ( '$style_check'(_, 4.5) -> R = yes ; '$style_check'(P, 202), R = no(P) )"
    ),   # no(7)
    (
        "sc19",
        raw"'$style_check'(O, 2), '$style_check'(P, 202), '$style_check'(Q, Q), R = O-P-Q"
    ),   # 202-2-202
    (
        "sc20",
        raw"'$style_check'(_, 8), '$style_check'(P, P), '$style_check'(_, 202), R = P"
    )       # 8
]

# the driver's whole output, one line per case after `ok`, filled by evidence/Q10/gen_rows.py --fill from swipl 10.1.19
const _SC_PINNED = [
    "ok",
    "t_sc01 c[116,95,115,99,48,49]/1(i202)",
    "t_sc02 c[116,95,115,99,48,50]/1(a[121,101,115])",
    "t_sc03 c[116,95,115,99,48,51]/1(c[45]/2(i202,i5))",
    "t_sc04 c[116,95,115,99,48,52]/1(i0)",
    "t_sc05",
    "t_sc06",
    "t_sc07",
    "t_sc08",
    "t_sc09",
    "t_sc10",
    "t_sc11 c[116,95,115,99,49,49]/1(c[45]/2(i202,i2147483647))",
    "t_sc12 c[116,95,115,99,49,50]/1(c[45]/2(i202,i-1))",
    "t_sc13 c[116,95,115,99,49,51]/1(i-2147483648)",
    "t_sc14 c[116,95,115,99,49,52]/1(i202)",
    "t_sc15 c[116,95,115,99,49,53]/1(c[91,124,93]/2(i202,nil))",
    "t_sc16 c[116,95,115,99,49,54]/1(c[110,111]/1(i7))",
    "t_sc17 c[116,95,115,99,49,55]/1(c[110,111]/1(i7))",
    "t_sc18 c[116,95,115,99,49,56]/1(c[110,111]/1(i7))",
    "t_sc19 c[116,95,115,99,49,57]/1(c[45]/2(c[45]/2(i202,i2),i202))",
    "t_sc20 c[116,95,115,99,50,48]/1(i8)"
]

function _sc_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _SC_CASES]
    text =
        _SC_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _SC_CASES
        ])
    f = joinpath(mktempdir(), "style_check.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _sc_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_SC}()
    ld = LK.PL_local_data{_SC}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _sc_enc(ball::_SC)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_scs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_SC, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _sc_enc(mk_expr(_SC, _SC[_scs(name), lk_answers(ld, (a:a)...)...]))
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

@testset "'\$style_check'/2 as swipl's (sc01-sc20)" begin
    f, names = _sc_file()
    kl, _, _ = _sc_kernel(f, names)
    @test length(kl) == length(_SC_PINNED)
    for (k, p) in zip(kl, _SC_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the style_check rows are not vacuous (sc01-sc20)" begin
    # the program loaded (`ok`); the default 202 is answered; the failing rows have no answer; the raised/changed state is read back
    @test _SC_PINNED[1] == "ok"
    @test count(l -> occursin("i202", l), _SC_PINNED) >= 6
    for id in ("sc05", "sc06", "sc07", "sc08", "sc09", "sc10")
        @test any(l -> l == "t_$id", _SC_PINNED)                               # no answer: the row failed
    end
    for id in (
        "sc01",
        "sc02",
        "sc03",
        "sc04",
        "sc11",
        "sc12",
        "sc13",
        "sc14",
        "sc15",
        "sc16",
        "sc17",
        "sc18",
        "sc19",
        "sc20"
    )
        @test any(l -> startswith(l, "t_$id "), _SC_PINNED)                    # an answer
    end
    @test any(l -> startswith(l, "t_sc04 ") && endswith(l, "(i0)"), _SC_PINNED)      # the new value is read back
    @test any(l -> startswith(l, "t_sc16 ") && endswith(l, "(i7))"), _SC_PINNED)     # a failing call after a change leaves it
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_SC_PINNED) == length(_SC_CASES) + 1
    if swipl === nothing
        @info "Q10 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _sc_file()
        @test _sc_swipl_lines(f, names) == _SC_PINNED
    end
end
