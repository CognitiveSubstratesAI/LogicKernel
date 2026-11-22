# ORIGINAL: MISS1's gate — the predicates the missing-C-predicates list left open: the legacy character I/O put/1,2 and get/1,2 of pl-file.c
# (swipl-devel 18168e62: put1/put2 :3505-3517 are put_code's function, get_nonblank :3520-3560) and '$call_no_catch'/1 (pl-pro.c:433-450)
# test/core_lang/test_miss_preds_swipl.jl — put/1,2 and get/1,2 over open_string/2 and with_output_to/2 streams, '$call_no_catch'/1:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run IN ORDER in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the answer lines are the driver's `enc`oded form (test_s2a_swipl.jl's driver).
#   * The expected lines are DERIVED FROM THE C (written blind, nothing was run when they were written): get_nonblank reads codes until
#     `!isBlankW(c)` and unifies the integer with NO type check of the second argument (unlike get_code/2: `get(S, a)` just fails, the
#     consumed character stays consumed), -1 at the end of the stream; put_code evaluates `PL_get_char(chr, &c, false)` BEFORE it looks
#     at the stream (so `put(nosuch, foo)` is the type error, not the existence error). With `swipl` on PATH the live answers are
#     compared with these lines too: a hand-derived line that swipl contradicts is a test fault, to be fixed to swipl's answer.
#   * NOT a row: get/1 and put/1 on the process's standard streams (they read the process's stdin); get/1 and put/1 share the function
#     with the /2 forms (get_nonblank, put_code). MEASURE ON THE LANE: `echo ' x' | swipl -g 'get(C), print(C), nl' -t halt` (120), the
#     same with an empty stdin (-1), and `put(-1)`/`put(1114112)` against the kernel (the latter's answer is not derived here).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through the stream predicates
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _MG = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_mgs(x) = lk_sym(_MG, Symbol(x))

_mg_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _mg_enc(t::_MG, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _mg_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _mg_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _mg_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_mg_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the expected answers' encoders (the driver's `enc` of an integer, an atom, a string, a compound)
_mgi(n::Integer) = "i$n"
_mga(s::String) = "a" * _mg_codes(s)
_mgs_(s::String) = "s" * _mg_codes(s)
_mgc(name::String, args::String...) =
    "c" * _mg_codes(name) * "/$(length(args))(" * join(args, ",") * ")"
_mgraised(f::String) = _mgc("raised", f)

# the swipl side: test_s2a_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _MG_DRIVER = raw"""
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
encargs(I, A, T, S0, S) :- call(arg, I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
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
function _mg_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _MG_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(
                addenv(`swipl -q $f`, "LC_ALL" => "C.UTF-8"); stdin=devnull, stderr=devnull
            ),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

const _MG_PROGRAM = raw"""
mg_p(1).
"""

# (id, goal, expected `enc` of R or `nothing` for "the goal failed"), run IN ORDER. Every expected value is derived from the C named in the header.
const _MG_CASES = [
    # put/2, put/1: put_code's function (pl-file.c:3505-3517): PL_get_char(chr, &c, false) first, then the stream
    ("pu01", raw"with_output_to(string(S), (put(97), put(98))), R = S", _mgs_("ab")),
    ("pu02", raw"with_output_to(string(S), put(a)), R = S", _mgs_("a")),   # a one-character atom is a character
    (
        "pu03",
        raw"with_output_to(string(S), (current_output(O), put(O, 104), put(O, 105))), R = S",
        _mgs_("hi")
    ),
    (
        "pu04",
        raw"put(-1)",
        _mgraised(_mgc("type_error", _mga("character"), _mgi(-1)))
    ),   # PL_get_char with eof=false: -1 falls through to the type error
    ("pu05", raw"put(foo)", _mgraised(_mgc("type_error", _mga("character"), _mga("foo")))),   # text of length 3
    ("pu06", raw"put(_)", _mgraised(_mga("instantiation_error"))),
    (
        "pu07",
        raw"put(nosuch, 97)",
        _mgraised(_mgc("existence_error", _mga("stream"), _mga("nosuch")))
    ),
    (
        "pu08",
        raw"put(nosuch, foo)",
        _mgraised(_mgc("type_error", _mga("character"), _mga("foo")))
    ),   # the character is checked BEFORE the stream
    (
        "pu09",
        raw"catch((open_string(abc, S), put(S, 97), R = ok), error(permission_error(A, _, _), _), R = perm(A))",
        _mgc("perm", _mga("output"))
    ),   # put on an input stream
    (
        "pu10",
        raw"with_output_to(string(S), (put(0'a), put(10), put(0'b), current_output(O), line_count(O, L), line_position(O, P))), R = S-L-P",
        _mgc("-", _mgc("-", _mgs_("a\nb"), _mgi(2)), _mgi(1))
    ),   # put(10) is the newline: the position follows the code, as for put_code
    # get/2: get_nonblank (pl-file.c:3520-3560)
    ("ge01", raw"open_string('  ab', S), get(S, C), R = C", _mgi(97)),   # blanks skipped
    (
        "ge02",
        raw"open_string('a b', S), get(S, A), get(S, B), R = A-B",
        _mgc("-", _mgi(97), _mgi(98))
    ),
    ("ge03", raw"open_string('\n\t x', S), get(S, C), R = C", _mgi(120)),   # newline and tab are blank
    ("ge04", raw"open_string('', S), get(S, C), R = C", _mgi(-1)),   # EOF: -1
    ("ge05", raw"open_string('   ', S), get(S, C), R = C", _mgi(-1)),   # only blanks, then EOF
    (
        "ge06",
        raw"open_string(a, S), get(S, A), get(S, B), R = A-B",
        _mgc("-", _mgi(97), _mgi(-1))
    ),
    ("ge07", raw"open_string('  é', S), get(S, C), R = C", _mgi(233)),   # a wide character
    (
        "ge08",
        raw"open_string(ab, S), ( get(S, 98) -> X = yes ; X = no ), get_code(S, C), R = X-C",
        _mgc("-", _mga("no"), _mgi(98))
    ),   # get(S, 98) reads `a`, the unification fails, `a` stays consumed
    ("ge09", raw"open_string(ab, S), get(S, a)", nothing),   # no type check of the second argument: plain failure (get_code/2 raises here)
    ("ge10", raw"open_string(ab, S), get(S, 97), R = ok", _mga("ok")),
    (
        "ge11",
        raw"get(nosuch, _)",
        _mgraised(_mgc("existence_error", _mga("stream"), _mga("nosuch")))
    ),
    ("ge12", raw"get(_, _)", _mgraised(_mga("instantiation_error"))),
    (
        "ge13",
        raw"catch((with_output_to(string(_), (current_output(O), get(O, _))), R = ok), error(permission_error(A, _, _), _), R = perm(A))",
        _mgc("perm", _mga("input"))
    ),   # get on an output stream
    (
        "ge14",
        raw"open_string('a\n  b', S), get(S, A), get(S, B), get(S, C), R = A-B-C",
        _mgc("-", _mgc("-", _mgi(97), _mgi(98)), _mgi(-1))
    ),
    # '$call_no_catch'/1 (pl-pro.c:433-450): callProlog with PL_Q_NORMAL; an exception is restored from and cleared, the truth value is ignored,
    # the predicate always succeeds. The printed message goes to user_error (not compared). callProlog's PL_cut_query keeps the bindings.
    ("cn01", raw"'$call_no_catch'(X = 1), R = X", _mgi(1)),
    ("cn02", raw"'$call_no_catch'(fail), R = ok", _mga("ok")),
    ("cn03", raw"'$call_no_catch'(throw(foo)), R = ok", _mga("ok")),
    ("cn04", raw"'$call_no_catch'(true), R = ok", _mga("ok")),
    ("cn05", raw"'$call_no_catch'(_), R = ok", _mga("ok")),   # callProlog's own instantiation error, also swallowed
    ("cn06", raw"'$call_no_catch'(user:(Y = a)), R = Y", _mga("a")),
]

"The expected lines (the driver's output) of the rows."
_mg_expected() = vcat(
    ["ok"],
    [
        e === nothing ? "t_$id" : "t_$id " * _mgc("t_$id", e) for (id, _, e) in _MG_CASES
    ]
)

function _mg_file(dir::String)::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _, _) in _MG_CASES]
    text =
        _MG_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n"
            for (id, g, _) in _MG_CASES
        ])
    f = joinpath(dir, "miss_preds.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _mg_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_MG}()
    ld = LK.PL_local_data{_MG}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _mg_enc(ball::_MG)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_mgs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_MG, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _mg_enc(mk_expr(_MG, _MG[_mgs(name), lk_answers(ld, (a:a)...)...]))
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
    return out
end

@testset "put/1,2, get/1,2 and '\$call_no_catch'/1 as the C (pu01-pu10, ge01-ge14, cn01-cn06)" begin
    f, names = _mg_file(mktempdir())
    kl = _mg_kernel(f, names)
    ex = _mg_expected()
    @test length(kl) == length(ex)
    for (k, p) in zip(kl, ex)
        k == p || println(stderr, "  ours      ", k, "\n  expected  ", p)
        @test k == p
    end
    # not vacuous: the expectation holds raised errors, `ok` and answers, and one failing row (ge09)
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), ex) == 7    # raised(…)
    @test count(l -> occursin(r"^t_\w+ *$", l), ex) == 1                   # ge09 fails
    @test count(l -> occursin("i-1)", l), ex) == 5                         # -1 in an answer (pu04's character, the EOF answers)
end

@testset "the expected lines are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_mg_expected()) == length(_MG_CASES) + 1
    if swipl === nothing
        @info "MISS1 get/put LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _mg_file(mktempdir())
        @test _mg_swipl_lines(f, names) == _mg_expected()
    end
end
