#!/usr/bin/env python3 -I
"""O1B rows generator: renders test/core_lang/test_with_output_to_swipl.jl from the case list below and
the swipl 10.1.19 answers of the same program (run twice, byte-identical). Usage: gen_rows.py <repo> <scratch>"""
import subprocess, sys, os

PROGRAM = r"""
wo_rep(0) :- !.
wo_rep(N) :- write(abcdefghij), N1 is N-1, wo_rep(N1).
wo_u(U) :- atom_codes(U, [97, 8364, 98]).
wo_ball :- throw(ball(1, f(x))).
wo_inner_fail :- write(lost), fail.
wo_inner_throw :- write(lost), throw(e).
wo_deep(0) :- !, write(bottom).
wo_deep(N) :- write(N), N1 is N-1, with_output_to(atom(A), wo_deep(N1)), write(A).
"""

# (id, comment, goal)
CASES = [
 ("w01", "the five sink kinds, each with text written by write/1: atom, string, codes, chars", None),
 ("w01", "", "with_output_to(atom(A), write(hello)), R = A"),
 ("w02", "", "with_output_to(string(S), write(hello)), R = S"),
 ("w03", "", "with_output_to(codes(C), write(ab)), R = C"),
 ("w04", "", "with_output_to(chars(C), write(ab)), R = C"),
 ("w05", "the difference-list sinks: codes(C, T) and chars(C, T) leave T the unbound tail", None),
 ("w05", "", "with_output_to(codes(C, T), write(ab)), T = [120], R = C"),
 ("w06", "", "with_output_to(chars(C, T), write(ab)), T = [z], R = C"),
 ("w07", "nothing written: '' / \"\" / [] and the difference lists with C == T", None),
 ("w07", "", "with_output_to(atom(A), true), R = A"),
 ("w08", "", "with_output_to(string(S), true), R = S"),
 ("w09", "", "with_output_to(codes(C), true), R = C"),
 ("w10", "", "with_output_to(chars(C), true), R = C"),
 ("w11", "", "with_output_to(codes(C, T), true), R = C-T"),
 ("w12", "", "with_output_to(chars(C, T), true), R = C-T"),
 ("w13", "several writes, a newline, numbers; quoting follows the writing predicate", None),
 ("w13", "", "with_output_to(atom(A), (write(a), nl, write(b))), R = A"),
 ("w14", "", "with_output_to(atom(A), write(42)), R = A"),
 ("w15", "", "with_output_to(atom(A), write(1.5)), R = A"),
 ("w16", "", "with_output_to(atom(A), writeq('A b')), R = A"),
 ("w17", "", "with_output_to(atom(A), write_canonical([x, 'Y z'|c])), R = A"),
 ("w18", "", "with_output_to(atom(A), write_term('a b', [quoted(true)])), R = A"),
 ("w19", "a wide character (above 255): atom, codes, chars", None),
 ("w19", "", "wo_u(U), with_output_to(atom(A), write(U)), atom_codes(A, Cs), R = Cs"),
 ("w20", "", "wo_u(U), with_output_to(codes(C), write(U)), R = C"),
 ("w21", "", "wo_u(U), with_output_to(chars(C), write(U)), atom_length(U, L), R = L-C"),
 ("w22", "more than the memory stream's first buffer (3000 characters)", None),
 ("w22", "", "with_output_to(atom(A), wo_rep(300)), atom_length(A, R)"),
 ("w23", "", "with_output_to(codes(C), wo_rep(300)), atom_codes(A, C), atom_length(A, R)"),
 ("w24", "a bound sink: unified with the text after the goal; a mismatch fails", None),
 ("w24", "", "with_output_to(atom(abc), write(abc)), R = yes"),
 ("w25", "", "( with_output_to(atom(abd), write(abc)) -> R = yes ; R = no )"),
 ("w26", "", "with_output_to(codes([97, 98]), write(ab)), R = yes"),
 ("w27", "", "( with_output_to(codes([97, 99]), write(ab)) -> R = yes ; R = no )"),
 ("w28", "", "with_output_to(codes([97|T]), write(abc)), R = T"),
 ("w29", "", "with_output_to(chars([a|T]), write(abc)), R = T"),
 ("w30", "an atom is no integer; a string is no atom", None),
 ("w30", "", "( with_output_to(atom(42), write(42)) -> R = yes ; R = no )"),
 ("w31", "", "( with_output_to(string(abc), write(abc)) -> R = yes ; R = no )"),
 ("w32", "the goal runs once; its bindings stay", None),
 ("w32", "", "with_output_to(atom(A), (X = 1, write(X))), R = X-A"),
 ("w33", "", "findall(X-A, with_output_to(atom(A), (between(1, 3, X), write(X))), R)"),
 ("w34", "", "findall(A, (between(1, 3, X), with_output_to(atom(A), write(X))), R)"),
 ("w35", "", "with_output_to(atom(A), ( true -> write(y) ; write(n) )), R = A"),
 ("w36", "", "with_output_to(atom(A), user:write(q)), R = A"),
 ("w37", "failure inside: with_output_to/2 fails, the sink stays unbound, the output is discarded", None),
 ("w37", "", "( with_output_to(atom(_), (write(x), fail)) -> R = yes ; R = no )"),
 ("w38", "", "( with_output_to(atom(A), wo_inner_fail) ; true ), R = A"),
 ("w39", "", "( with_output_to(atom(_), wo_inner_fail) ; true ), with_output_to(atom(B), write(kept)), R = B"),
 ("w40", "exceptions inside: the ball passes; the output is discarded and the current output is restored", None),
 ("w40", "", "catch(with_output_to(atom(_), wo_inner_throw), E, true), R = E"),
 ("w41", "", "catch(with_output_to(atom(_), wo_inner_throw), _, true), with_output_to(atom(B), write(kept)), R = B"),
 ("w42", "", "catch(with_output_to(atom(A), wo_ball), ball(N, F), true), R = N-F-A"),
 ("w43", "", "catch(with_output_to(atom(_), atom_length(_, _)), error(E, _), true), R = E"),
 ("w44", "", "catch(with_output_to(string(_), (write(a), atom_length(1, a))), error(E, _), true), R = E"),
 ("w45", "nested with_output_to/2: the inner text is the inner sink's, the outer gets the rest", None),
 ("w45", "", "with_output_to(atom(A), (write(a), with_output_to(atom(B), write(b)), write(B), write(c))), R = A-B"),
 ("w46", "", "with_output_to(atom(A), (write(a), ( with_output_to(atom(_), wo_inner_fail) -> true ; true ), write(c))), R = A"),
 ("w47", "", "with_output_to(atom(A), (write(a), catch(with_output_to(atom(_), wo_inner_throw), e, true), write(c))), R = A"),
 ("w48", "", "catch(with_output_to(atom(A), (write(a), with_output_to(atom(_), throw(e)))), E, true), R = E-A"),
 ("w49", "", "with_output_to(atom(A), (write(a), with_output_to(codes(C), write(bc)), write(C))), R = A"),
 ("w50", "", "with_output_to(atom(A), wo_deep(4)), R = A"),
 ("w51", "", "with_output_to(atom(A), write(1)), with_output_to(atom(B), write(2)), R = A-B"),
 ("w52", "an explicit stream written inside is not redirected", None),
 ("w52", "", "with_output_to(atom(A), (write(user_error, zz), write(in))), R = A"),
 ("w53", "", "with_output_to(atom(A), (nl(user_error), write(in))), R = A"),
 ("w54", "a stream sink: user, user_output (nothing written here), user_error (swipl and the kernel write to stderr)", None),
 ("w54", "", "with_output_to(user, true), R = ok"),
 ("w55", "", "with_output_to(user_output, true), R = ok"),
 ("w56", "", "with_output_to(user_error, nl), R = ok"),
 ("w57", "", "with_output_to(user_error, write(x)), with_output_to(atom(A), write(y)), R = A"),
 ("w58", "", "( with_output_to(user_error, fail) -> R = yes ; R = no )"),
 ("w59", "", "catch(with_output_to(user_error, throw(e)), E, true), with_output_to(atom(A), write(y)), R = E-A"),
 ("w60", "sink errors: unbound, not a sink, a number, no such stream, an input stream", None),
 ("w60", "", "catch(with_output_to(_, true), error(E, _), true), R = E"),
 ("w61", "", "catch(with_output_to(foo(_), true), error(E, _), true), R = E"),
 ("w62", "", "catch(with_output_to(1, true), error(E, _), true), R = E"),
 ("w63", "", "catch(with_output_to(nostream, true), error(E, _), true), R = E"),
 ("w64", "", "catch(with_output_to(user_input, true), error(E, _), true), R = E"),
 ("w65", "", "catch(with_output_to(atom(a, b), true), error(E, _), true), R = E"),
 ("w66", "", "catch(with_output_to(codes(a, b, c), true), error(E, _), true), R = E"),
 ("w67", "", "catch(with_output_to(f(x), true), error(E, _), true), R = E"),
 ("w68", "a bad goal: the sink is set up and then discarded", None),
 ("w68", "", "catch(with_output_to(atom(_), _), error(E, _), true), R = E"),
 ("w69", "", "catch(with_output_to(atom(_), 1), error(E, _), true), R = E"),
 ("w70", "", "catch(with_output_to(atom(_), nosuchpred_wo), error(E, _), true), R = E"),
 ("w71", "", "catch(with_output_to(atom(_), 1), error(_, _), true), with_output_to(atom(B), write(kept)), R = B"),
 ("w72", "", "catch(with_output_to(foo(_), true), error(_, _), true), with_output_to(atom(B), write(kept)), R = B"),
]

DRIVER = r'''
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
'''

def rows():
    return [(i, c, g) for (i, c, g) in CASES if g is not None]

def file_text():
    names = ["t_%s" % i for (i, c, g) in rows()]
    text = PROGRAM + "".join("t_%s(R) :- catch((%s), error(SsuE, _), R = raised(SsuE)).\n" % (i, g) for (i, c, g) in rows())
    return names, text

def swipl(scratch, tag):
    names, text = file_text()
    f = os.path.join(scratch, "wo.pl"); open(f, "w", encoding="utf-8").write(text)
    d = os.path.join(scratch, "drv.pl")
    open(d, "w", encoding="utf-8").write(DRIVER + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (f, ",".join(names)))
    r = subprocess.run(["swipl", "-q", d], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    out = r.stdout.decode("utf-8")
    open(os.path.join(scratch, "run_%s.out" % tag), "w", encoding="utf-8").write(out)
    return out

if __name__ == "__main__":
    repo, scratch = sys.argv[1], sys.argv[2]
    a = swipl(scratch, "1"); b = swipl(scratch, "2")
    assert a == b, "two swipl runs differ"
    lines = [l for l in a.split("\n") if l != ""]
    names, _ = file_text()
    assert len(lines) == len(names) + 1, (len(lines), len(names))
    open(os.path.join(repo, "evidence/O1B/wo_rows.out"), "w", encoding="utf-8").write(a)
    print("ok", len(lines))

HEADER = r'''# ORIGINAL: O1B's gate (lk-channel evidence/r2/design/flags_rest.md §4 O1, H10) — with_output_to/2 and the output redirect (pl-file.c
# `setupOutputRedirect`, `closeOutputRedirect`, `discardOutputRedirect`, `pushOutputContext`, `popOutputContext`, `with_output_to`),
# against swipl 10.1.19; the rows are tests/core_lang/test_with_output_to_swipl.jl:
#   * A PROGRAM consulted by the kernel's loader — a few helper clauses (`wo_*`) — and cases `t_<id>(R)` run IN ORDER in one
#     database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the answers are encoded by `_wo_enc`.
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, two runs byte-identical, 2026-10-31, lk-channel
#     evidence/O1B/wo_rows.out in the O1B branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * The rows use only write/1, writeq/1, write_canonical/1, write_term/2, nl/0,1 as the writing predicates (format/2,3 is O1A's).
#   * Rows marked `UNVERIFIED on the kernel: gate decides` depend on a kernel error or builtin the writer could not judge.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the redirect (src/os/pl-redirect.jl), built on the stream layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _WO = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_wos(x) = lk_sym(_WO, Symbol(x))

_wo_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _wo_enc(t::_WO, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _wo_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _wo_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _wo_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_wo_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the driver of test_at_body_swipl.jl (consult, then every answer of each t_<id>/1, `enc`oded)
const _WO_DRIVER = raw"""
@@DRIVER@@"""
function _wo_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _WO_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: helpers the rows call (the writing predicates are the kernel's own)
const _WO_PROGRAM = raw"""@@PROGRAM@@"""

# (id, goal), run IN ORDER
const _WO_CASES = [
@@CASES@@
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; lk-channel evidence/O1B/wo_rows.out)
const _WO_PINNED = [
@@PINS@@
]

"The program and cases as one file; the case predicates' names."
function _wo_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _WO_CASES]
    text =
        _WO_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _WO_CASES
        ])
    f = joinpath(mktempdir(), "wo.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _wo_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_WO}()
    ld = LK.PL_local_data{_WO}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _wo_enc(ball::_WO)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_wos(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_WO, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _wo_enc(mk_expr(_WO, _WO[_wos(name), lk_answers(ld, (a:a)...)...]))
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

@testset "with_output_to/2 and the output redirect as swipl's (w01-w72)" begin
    f, names = _wo_file()
    kl, _, ld = _wo_kernel(f, names)
    @test length(kl) == length(_WO_PINNED)
    for (k, p) in zip(kl, _WO_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the sink rows answer text of every kind, the failure and exception rows answer something other than the text
    # written, and the pins hold both kinds of answer, so the comparison can pass and can fail
    @test count(l -> occursin("/1(a[", l), _WO_PINNED) >= 25                             # an atom answer
    @test count(l -> occursin("/1(s[", l), _WO_PINNED) >= 1                              # a string answer
    @test count(l -> occursin("c[91,124,93]/2(i", l), _WO_PINNED) >= 5                   # a code list
    @test count(l -> occursin("c[116,121,112,101,95,101,114,114,111,114]/2(", l), _WO_PINNED) >= 5   # type_error(output, _) and kin
    @test _WO_PINNED[findfirst(startswith("t_w22 "), _WO_PINNED)] == "t_w22 c[116,95,119,50,50]/1(i3000)"
    @test _WO_PINNED[findfirst(startswith("t_w39 "), _WO_PINNED)] ==
          "t_w39 c[116,95,119,51,57]/1(a[107,101,112,116])"   # the failed redirect leaves the output where it was
    # white-box: after every row the current output is user_output again and no redirect is left on the stack
    @test isempty(ld.IO_output_stack)
    @test LK.Scurout(ld) === LK.Suser_output(ld)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_WO_PINNED) == length(_WO_CASES) + 1
    if swipl === nothing
        @info "O1B LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _wo_file()
        @test _wo_swipl_lines(f, names) == _WO_PINNED
    end
end
'''

UNVERIFIED = {"w44", "w64", "w70", "w43", "w68", "w69"}

def render(repo):
    out = open(os.path.join(repo, "evidence/O1B/wo_rows.out"), encoding="utf-8").read()
    pins = ",\n".join('    "%s"' % l for l in out.split("\n") if l != "")
    cs = []
    for (i, c, g) in CASES:
        if g is None:
            cs.append("    # %s: %s" % (i, c))
        else:
            tag = "  # UNVERIFIED on the kernel: gate decides" if i in UNVERIFIED else ""
            cs.append('    ("%s", raw"%s"),%s' % (i, g, tag))
    body = HEADER.replace("@@DRIVER@@", DRIVER.lstrip("\n")).replace("@@PROGRAM@@", PROGRAM).replace("@@CASES@@", "\n".join(cs)).replace("@@PINS@@", pins)
    open(os.path.join(repo, "test/core_lang/test_with_output_to_swipl.jl"), "w", encoding="utf-8").write(body)

if __name__ == "__main__" and len(sys.argv) > 3 and sys.argv[3] == "render":
    render(sys.argv[1])
