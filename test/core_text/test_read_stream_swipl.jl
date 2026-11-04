# ORIGINAL: RD1's gate — read/1,2, read_term/2,3, `$raw_read/1,2` and `$is_named_var/1` (pl-read.c, pl-ext.c) against swipl 10.1.19, as the rows of a consulted program whose cases read from streams.
# test/core_text/test_read_stream_swipl.jl — the stream-reading entry points of pl-read.c (`pl_read2`, `pl_read`, `read_term/2,3`'s option
# scan and stream check, `pl_raw_read2`, `pl_raw_read`, `$is_named_var`), registered in src/pl-read.jl and src/pl-ext.jl:
#   * A PROGRAM consulted by the kernel's loader: helpers that open a string stream (`open_string/2`) or a file stream (`open/3`, written
#     by the program), and cases `t_<id>(R)` run IN ORDER in one database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`.
#     A syntax error's location is read through `rt_serr/2`: the file name and the stream blob are dropped, the numbers kept.
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, LC_ALL=C, two byte-identical runs, evidence/RD1/gen_rows.py of the
#     RD1 branch); with `swipl` on PATH the live answers are compared with the pins too.
#   * KNOWN DIFFERENCE rows (`_RT_KNOWN`): the options the kernel refuses and the syntax errors over an `open_string/2` stream pin the
#     kernel's exact current answer (a `NotPortedError`) beside swipl's (the pin of the same row).
#   * Rows that read the process's standard input (rt21-rt26, rt170, rt171) are UNVERIFIED on the kernel: gate decides (stdin is /dev/null in
#     tools/run_tests.sh and in the driver run).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream readers, built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _RT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_rts(x) = lk_sym(_RT, Symbol(x))

_rt_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _rt_enc(t::_RT, seen::Vector{UInt64}=UInt64[])::String
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
        return is_nil(t) ? "nil" : "a" * _rt_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _rt_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _rt_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_rt_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the driver of test_at_body_swipl.jl (consult, then every answer of each t_<id>/1, `enc`oded)
const _RT_DRIVER = raw"""
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
function _rt_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _RT_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        withenv("LC_ALL" => "C") do
            read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
        end
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: the stream openers and the error-location helpers; `@RTDIR@` is the directory of the scratch file (the test's temp
# directory; evidence/RD1/rt_tmp for the generator). The case predicates follow, written by `_rt_file`.
const _RT_PROGRAM = raw"""
rt_path(P) :- atom_concat('@RTDIR@', '/rt.txt', P).
rt_str(Text, S) :- open_string(Text, S).
rt_file(Text, S) :- rt_path(P), open(P, write, O), write(O, Text), close(O), open(P, read, S).
rt_bin(Text, S) :- rt_path(P), open(P, write, O), write(O, Text), close(O), open(P, read, S, [type(binary)]).
rt_out(S) :- rt_path(P), open(P, write, S).
rt_ctx(file(_, L, LP, C), file(L, LP, C)) :- !.
rt_ctx(stream(_, L, LP, C), stream(L, LP, C)) :- !.
rt_ctx(_, other).
rt_serr(G, R) :- catch((G, R = ok), error(F, C), (rt_ctx(C, C1), R = raised(F, C1))).
rt_serr_formal(G, R) :- catch((G, R = ok), error(F, _), R = raised(F)).
"""

# (id, goal), run IN ORDER; `R` is the answer
const _RT_CASES = [
    # read/2 from a string stream and a file stream
    (
        "rt01",
        raw"""rt_str('foo(X,Y,X). bar.', S), read(S,A), read(S,B), read(S,C), read(S,D), R = [A,B,C,D]"""
    ),
    ("rt02", raw"""rt_str('42.', S), read(S,T), R = T"""),
    (
        "rt03",
        raw"""rt_str('f("ab", \'c d\', 0\'a, 1.5, [1,2|T], - 1, -(1), 1r3).', S), read(S,T), R = T"""
    ),
    ("rt04", raw"""rt_str('', S), read(S,A), read(S,B), R = [A,B]"""),
    (
        "rt05",
        raw"""rt_str('   % only a comment\n /* and another */ ', S), read(S,T), R = T"""
    ),
    ("rt06", raw"""rt_str('foo(1).', S), read(S, foo(2)), R = yes"""),
    ("rt07", raw"""rt_str('a. b.', S), read(S,_), read(S,b), R = yes"""),
    ("rt08", raw"""T = foo(_), rt_str('foo(7).', S), read(S,T), R = T"""),
    ("rt09", raw"""rt_str('X.', S), read(S,T), R = T"""),
    ("rt10", raw"""rt_str('f(X,Y,X).', S), read(S,T), R = T"""),
    ("rt11", raw"""rt_str('a.', S), close(S), read(S,_), R = yes"""),
    ("rt12", raw"""read(_, _), R = yes"""),
    ("rt13", raw"""read(foo, _), R = yes"""),
    ("rt14", raw"""rt_out(S), read(S,_), R = yes"""),
    ("rt15", raw"""rt_bin('A', S), read(S,_), R = yes"""),
    ("rt16", raw"""rt_bin('', S), read(S,T), R = T"""),
    ("rt17", raw"""rt_bin('foo(X). ', S), read(S,T), R = T"""),
    (
        "rt18",
        raw"""rt_file('foo(X, Y).\nbar.\n', S), read(S,A), read(S,B), read(S,C), R = [A,B,C]"""
    ),
    ("rt19", raw"""rt_str('a. b.', S), read(S, a), read(S, c), R = yes"""),
    ("rt20", raw"""rt_str('a. b.', S), read(S, f(_)), R = yes"""),
    # read/1, read_term/2 and read/2 on user_input: stdin is /dev/null
    ("rt21", raw"""read(T), R = T"""),
    ("rt22", raw"""read(user_input, T), R = T"""),
    ("rt23", raw"""read_term(T, [variable_names(Vs)]), R = T-Vs"""),
    ("rt24", raw"""read_term(user_input, T, [syntax_errors(error)]), R = T"""),
    ("rt25", raw"""read_term(T, foo), R = T"""),
    ("rt26", raw"""read_term(T, [variable_names(Vs)|_]), R = T-Vs"""),
    # read_term/3: variable_names, variables, singletons
    (
        "rt30",
        raw"""rt_str('foo(X,Y,X,_Z,_).', S), read_term(S,T,[variable_names(V)]), R = T-V"""
    ),
    (
        "rt31",
        raw"""rt_str('foo(X,Y,X,_Z,_).', S), read_term(S,T,[variables(V)]), R = T-V"""
    ),
    (
        "rt32",
        raw"""rt_str('foo(X,Y,X,_Z,_).', S), read_term(S,T,[singletons(V)]), R = T-V"""
    ),
    (
        "rt33",
        raw"""rt_str('foo(X,Y,X,_Z,_).', S), read_term(S,T,[variable_names(N),variables(V),singletons(G)]), R = T-N-V-G"""
    ),
    (
        "rt34",
        raw"""rt_str('foo(X,Y,X,_).', S), read_term(S,T,[singletons(warning)]), R = T"""
    ),
    (
        "rt35",
        raw"""rt_str('foo(X,_Y,_Y,__Z).', S), read_term(S,T,[singletons(G)]), R = T-G"""
    ),
    (
        "rt36",
        raw"""rt_str('foo(a,b).', S), read_term(S,T,[variable_names(N),variables(V),singletons(G)]), R = T-N-V-G"""
    ),
    (
        "rt37",
        raw"""rt_str('', S), read_term(S,T,[variable_names(N),variables(V),singletons(G),subterm_positions(P),term_position(TP)]), R = T-N-V-G-P-TP"""
    ),
    ("rt38", raw"""rt_str('f(X).', S), read_term(S,T,[variable_names(['X'=1])]), R = T"""),
    ("rt39", raw"""rt_str('f(X).', S), read_term(S,T,[variable_names(foo)]), R = T"""),
    ("rt40", raw"""rt_str('f(X).', S), read_term(S,T,[variables(foo)]), R = T"""),
    (
        "rt41",
        raw"""rt_str('f(X,Y).', S), read_term(S,T,[variable_names(['X'=A|B])]), R = T-A-B"""
    ),
    (
        "rt42",
        raw"""rt_str('f(X).', S), read_term(S,T,[variable_names(N),variable_names(M)]), R = T-N-M"""
    ),
    # read_term/3: option errors
    ("rt50", raw"""rt_str('f(X).', S), read_term(S,T,foo), R = T"""),
    ("rt51", raw"""rt_str('f(X).', S), read_term(S,T,[variable_names(V)|_]), R = T-V"""),
    ("rt52", raw"""rt_str('f(X).', S), read_term(S,T,[variable_names(V)|foo]), R = T-V"""),
    ("rt53", raw"""rt_str('f(X).', S), read_term(S,T,[_|foo]), R = T"""),
    ("rt54", raw"""rt_str('f(X).', S), read_term(S,T,[foo(bar)]), R = T"""),
    ("rt55", raw"""rt_str('f(X).', S), read_term(S,T,[foo]), R = T"""),
    ("rt56", raw"""rt_str('f(X).', S), read_term(S,T,[syntax_errors(_)]), R = T"""),
    ("rt57", raw"""rt_str('f(X).', S), read_term(S,T,[syntax_errors(bar)]), R = T"""),
    ("rt58", raw"""rt_str('f(X).', S), read_term(S,T,[double_quotes(1)]), R = T"""),
    ("rt59", raw"""rt_str('f(X).', S), read_term(S,T,[double_quotes(foo)]), R = T"""),
    ("rt60", raw"""rt_str('f(X).', S), read_term(S,T,[cycles(maybe)]), R = T"""),
    ("rt61", raw"""rt_str('f(X).', S), read_term(S,T,[module(1)]), R = T"""),
    ("rt62", raw"""rt_str('f(X).', S), read_term(S,T,[module(_)]), R = T"""),
    ("rt63", raw"""rt_str('f(X).', S), read_term(S,T,[back_quotes(foo)]), R = T"""),
    ("rt64", raw"""rt_str('f(X).', S), read_term(S,T,[character_escapes(maybe)]), R = T"""),
    ("rt65", raw"""rt_str('f(X).', S), read_term(S,T,[term_position(foo)]), R = T"""),
    ("rt66", raw"""rt_str('f(X).', S), read_term(S,T,[subterm_positions(foo)]), R = T"""),
    (
        "rt67",
        raw"""rt_str('f(X).', S), read_term(S,T,[variable_names(V),variable_names(W)]), R = T-V-W"""
    ),
    (
        "rt68",
        raw"""rt_str('f(X).', S), read_term(S,T,[variable_names(V), module(M)]), R = T-V-M"""
    ),
    # read_term/3: stream errors
    ("rt70", raw"""read_term(_, T, []), R = T"""),
    ("rt71", raw"""read_term(foo, T, []), R = T"""),
    ("rt72", raw"""rt_out(S), read_term(S, T, []), R = T"""),
    ("rt73", raw"""rt_bin('A', S), read_term(S, T, []), R = T"""),
    ("rt74", raw"""rt_bin('f(X). ', S), read_term(S, T, [variable_names(V)]), R = T-V"""),
    ("rt75", raw"""rt_str('a.', S), close(S), read_term(S, T, []), R = T"""),
    ("rt76", raw"""read_term(1, T, []), R = T"""),
    ("rt77", raw"""read_term(f(x), T, []), R = T"""),
    # read_term/3: syntax_errors
    ("rt80", raw"""rt_file('a b. c.', S), read_term(S,T,[syntax_errors(fail)]), R = T"""),
    ("rt81", raw"""rt_file('a b. c.', S), read_term(S,T,[syntax_errors(quiet)]), R = T"""),
    ("rt82", raw"""rt_file('a b. c.', S), read_term(S,T,[syntax_errors(dec10)]), R = T"""),
    ("rt83", raw"""rt_file('a b. c.', S), read_term(S,T,[syntax_errors(error)]), R = T"""),
    ("rt84", raw"""rt_file('a b. c.', S), catch(read(S,_), _, true), read(S,T), R = T"""),
    (
        "rt85",
        raw"""rt_file('a b. c.', S), ( read_term(S,_,[syntax_errors(fail)]) -> true ; true ), read_term(S,U,[]), R = U"""
    ),
    (
        "rt86",
        raw"""rt_file('a b. c.', S), ( read_term(S,_,[syntax_errors(quiet)]) -> true ; true ), read_term(S,U,[]), R = U"""
    ),
    # syntax errors on a file stream: the ball and its location
    ("rt100", raw"""rt_serr((rt_file('a b.', S), read(S,_)), R)"""),
    ("rt101", raw"""rt_serr((rt_file('foo(.', S), read(S,_)), R)"""),
    ("rt102", raw"""rt_serr((rt_file('foo(', S), read(S,_)), R)"""),
    ("rt103", raw"""rt_serr((rt_file('\'abc', S), read(S,_)), R)"""),
    ("rt104", raw"""rt_serr((rt_file('foo(X,Y)', S), read(S,_)), R)"""),
    ("rt105", raw"""rt_serr((rt_file('f(a,).', S), read(S,_)), R)"""),
    ("rt106", raw"""rt_serr((rt_file('1 2.', S), read(S,_)), R)"""),
    ("rt107", raw"""rt_serr((rt_file(').', S), read(S,_)), R)"""),
    ("rt108", raw"""rt_serr((rt_file('a :- :- b.', S), read(S,_)), R)"""),
    ("rt109", raw"""rt_serr((rt_file('\n\n  foo bar baz.', S), read(S,_)), R)"""),
    ("rt110", raw"""rt_serr((rt_file('"abc', S), read(S,_)), R)"""),
    ("rt111", raw"""rt_serr((rt_file('a. b c. d.', S), read(S,_), read(S,_)), R)"""),
    ("rt112", raw"""rt_serr((rt_file('f(\'\\q\').', S), read(S,_)), R)"""),
    ("rt114", raw"""rt_serr((rt_file('foo.bar', S), read(S,_), read(S,_)), R)"""),
    ("rt115", raw"""rt_serr((rt_file('X = [a,b', S), read(S,_)), R)"""),
    (
        "rt116",
        raw"""rt_serr((rt_file('a b.', S), read_term(S,_,[syntax_errors(error)])), R)"""
    ),
    (
        "rt117",
        raw"""rt_serr((rt_file('a b.', S), read_term(S,_,[syntax_errors(bar)])), R)"""
    ),
    (
        "rt118",
        raw"""rt_serr((rt_file('a b.', S), read_term(S,_,[term_position(P), subterm_positions(Q)])), R)"""
    ),
    # positions
    (
        "rt130",
        raw"""rt_str('  foo(X, bar).', S), read_term(S,T,[term_position(P)]), R = T-P"""
    ),
    (
        "rt131",
        raw"""rt_str('  foo(X, bar).', S), read_term(S,T,[subterm_positions(P)]), R = T-P"""
    ),
    (
        "rt132",
        raw"""rt_file('  foo(X, bar).', S), read_term(S,T,[term_position(P)]), R = T-P"""
    ),
    ("rt133", raw"""rt_str('\n\n  x.', S), read_term(S,T,[term_position(P)]), R = T-P"""),
    (
        "rt134",
        raw"""rt_str('foo(a,b). x', S), read_term(S,T,[subterm_positions(P)]), R = T-P"""
    ),
    (
        "rt135",
        raw"""rt_str('[a,b|C]. ', S), read_term(S,T,[subterm_positions(P)]), R = T-P"""
    ),
    (
        "rt136",
        raw"""rt_str('- 1 + {x} - "s" - \'q\'(Z) - [].', S), read_term(S,T,[subterm_positions(P)]), R = T-P"""
    ),
    (
        "rt137",
        raw"""rt_str('a. b.\nc.', S), read_term(S,_,[term_position(P1)]), read_term(S,_,[term_position(P2)]), read_term(S,_,[term_position(P3)]), R = [P1,P2,P3]"""
    ),
    (
        "rt138",
        raw"""rt_file('a. b.\nc.', S), read_term(S,_,[term_position(P1)]), read_term(S,_,[term_position(P2)]), read_term(S,_,[term_position(P3)]), R = [P1,P2,P3]"""
    ),
    (
        "rt139",
        raw"""rt_str('x.', S), read_term(S,_,[]), read_term(S,T,[term_position(P),subterm_positions(Q)]), R = T-P-Q"""
    ),
    (
        "rt140",
        raw"""rt_str('"s" + \'a b\' + 0\'c + 1.5 + a(B).', S), read_term(S,T,[subterm_positions(P)]), R = T-P"""
    ),
    (
        "rt141",
        raw"""rt_str('(a , b) :- {c}.', S), read_term(S,T,[subterm_positions(P)]), R = T-P"""
    ),
    ("rt142", raw"""rt_str('\\+ a.', S), read_term(S,T,[subterm_positions(P)]), R = T-P"""),
    (
        "rt143",
        raw"""rt_str('f(- , a).', S), read_term(S,T,[subterm_positions(P)]), R = T-P"""
    ),
    ("rt144", raw"""rt_str('[].', S), read_term(S,T,[subterm_positions(P)]), R = T-P"""),
    # the other options
    (
        "rt150",
        raw"""rt_str('f("ab", `cd`).', S), read_term(S,T,[double_quotes(codes)]), R = T"""
    ),
    (
        "rt151",
        raw"""rt_str('f("ab", `cd`).', S), read_term(S,T,[double_quotes(atom)]), R = T"""
    ),
    (
        "rt152",
        raw"""rt_str('f("ab", `cd`).', S), read_term(S,T,[double_quotes(string), back_quotes(string)]), R = T"""
    ),
    (
        "rt153",
        raw"""rt_str('f("ab", `cd`).', S), read_term(S,T,[double_quotes(chars)]), R = T"""
    ),
    (
        "rt155",
        raw"""rt_str('f("ab", `cd`).', S), read_term(S,T,[back_quotes(codes)]), R = T"""
    ),
    (
        "rt156",
        raw"""rt_str('f(\'a\\nb\').', S), read_term(S,T,[character_escapes(false)]), R = T"""
    ),
    (
        "rt157",
        raw"""rt_str('f(\'a\\nb\').', S), read_term(S,T,[character_escapes(true)]), R = T"""
    ),
    (
        "rt158",
        raw"""rt_str('f(X) :- X = @(Y, [Y=f(Y)]).', S), read_term(S,T,[cycles(true)]), R = T"""
    ),
    (
        "rt159",
        raw"""rt_str('f(X,X).', S), read_term(S,T,[cycles(true), variable_names(V)]), R = T-V"""
    ),
    ("rt160", raw"""rt_str('[a|b].', S), read_term(S,T,[dotlists(true)]), R = T"""),
    ("rt161", raw"""rt_str('\'[|]\'(a,b).', S), read_term(S,T,[dotlists(true)]), R = T"""),
    ("rt162", raw"""rt_str('foo:bar.', S), read_term(S,T,[module(user)]), R = T"""),
    (
        "rt164",
        raw"""rt_serr((rt_file('a +++ b.', S), read_term(S,_,[module(nomod)])), R)"""
    ),
    (
        "rt165",
        raw"""rt_str('f(X, Y).', S), read_term(S,T,[variable_names(V), module(user), double_quotes(codes), syntax_errors(error)]), R = T-V"""
    ),
    ("rt166", raw"""rt_str('f(\'$VAR\'(1), "x").', S), read_term(S,T,[]), R = T"""),
    ("rt167", raw"""rt_str('x.', S), read_term(S,T,[end_of_file(foo)]), R = T"""),
    (
        "rt168",
        raw"""rt_str('x. y.', S), read_term(S,T,[]), read_term(S,U,[]), read_term(S,V,[]), read_term(S,W,[]), R = [T,U,V,W]"""
    ),
    # $raw_read/1,2
    ("rt170", raw"""'$raw_read'(user_input, T), R = T"""),
    ("rt171", raw"""'$raw_read'(T), R = T"""),
    ("rt172", raw"""rt_str('foo( X ,b ) . bar', S), '$raw_read'(S, T), R = T"""),
    ("rt173", raw"""rt_str('0\' . foo', S), '$raw_read'(S, T), R = T"""),
    ("rt174", raw"""rt_str('/* c */ a % x\n . ', S), '$raw_read'(S, T), R = T"""),
    ("rt175", raw"""rt_str('', S), '$raw_read'(S, T), R = T"""),
    (
        "rt177",
        raw"""rt_str('foo( X ,b ) . bar( Y ) . ', S), '$raw_read'(S, A), '$raw_read'(S, B), '$raw_read'(S, C), R = [A,B,C]"""
    ),
    (
        "rt178",
        raw"""rt_str('\'a. b\'. "x. y". c.', S), '$raw_read'(S, A), '$raw_read'(S, B), '$raw_read'(S, C), R = [A,B,C]"""
    ),
    ("rt179", raw"""rt_str('foo(  X,\n   b)  .', S), '$raw_read'(S, T), R = T"""),
    ("rt180", raw"""rt_str('end_of_file.', S), '$raw_read'(S, T), R = T"""),
    ("rt181", raw"""rt_str('a. b.', S), '$raw_read'(S, _), read(S, T), R = T"""),
    ("rt182", raw"""rt_str('a. b.', S), read(S, _), '$raw_read'(S, T), R = T"""),
    ("rt183", raw"""rt_str('f(X, Y, X) :- g(Y).', S), '$raw_read'(S, T), R = T"""),
    ("rt185", raw"""rt_serr((rt_file('\'abc', S), '$raw_read'(S, _)), R)"""),
    ("rt186", raw"""rt_serr((rt_file('a', S), '$raw_read'(S, _)), R)"""),
    ("rt188", raw"""'$raw_read'(_, T), R = T"""),
    ("rt189", raw"""'$raw_read'(foo, T), R = T"""),
    ("rt190", raw"""rt_out(S), '$raw_read'(S, T), R = T"""),
    ("rt191", raw"""rt_bin('foo. ', S), '$raw_read'(S, T), R = T"""),
    ("rt192", raw"""rt_str('a. b.', S), '$raw_read'(S, f(_)), R = yes"""),
    ("rt193", raw"""rt_str('a . ', S), '$raw_read'(S, 'a'), R = yes"""),
    ("rt194", raw"""rt_str('"abc".', S), '$raw_read'(S, T), R = T"""),
    ("rt195", raw"""rt_str('[ a , b | C ] . ', S), '$raw_read'(S, T), R = T"""),
    ("rt196", raw"""rt_str('a.b. c.', S), '$raw_read'(S, T), R = T"""),
    ("rt197", raw"""rt_str('f(0\'a, 0\'\\n, 0\'\'\'). ', S), '$raw_read'(S, T), R = T"""),
    ("rt198", raw"""rt_str('1.5 + 2.0e3 . ', S), '$raw_read'(S, T), R = T"""),
    ("rt199", raw"""rt_str('a %c\n.\n', S), '$raw_read'(S, T), R = T"""),
    # $is_named_var/1
    ("rt200", raw"""'$is_named_var'('X'), R = yes"""),
    ("rt201", raw"""'$is_named_var'('_X'), R = yes"""),
    ("rt202", raw"""'$is_named_var'('_1'), R = yes"""),
    ("rt203", raw"""'$is_named_var'('__a'), R = yes"""),
    ("rt204", raw"""'$is_named_var'('_'), R = yes"""),
    ("rt205", raw"""'$is_named_var'('_a'), R = yes"""),
    ("rt206", raw"""'$is_named_var'('Foo'), R = yes"""),
    ("rt207", raw"""'$is_named_var'([]), R = yes"""),
    ("rt208", raw"""'$is_named_var'(1), R = yes"""),
    ("rt209", raw"""'$is_named_var'(f(x)), R = yes"""),
    ("rt210", raw"""'$is_named_var'(_), R = yes"""),
    ("rt211", raw"""'$is_named_var'("Foo"), R = yes"""),
    ("rt212", raw"""'$is_named_var'(foo), R = yes"""),
    ("rt213", raw"""'$is_named_var'('_G123'), R = yes"""),
    ("rt214", raw"""'$is_named_var'('Xa1'), R = yes"""),
    ("rt215", raw"""'$is_named_var'(''), R = yes"""),
    ("rt216", raw"""'$is_named_var'('_Z'), R = yes"""),
    ("rt217", raw"""char_code(A, 233), '$is_named_var'(A), R = yes"""),
    (
        "rt218",
        raw"""char_code(C, 201), atom_concat(C, a, A), '$is_named_var'(A), R = yes"""
    ),
    ("rt219", raw"""'$is_named_var'('1X'), R = yes"""),
    # the read option blob(Mode) (pl-read.c atom_to_blob_mode_ex, blob_syntax_available, scan_blob_name): the modes error, dead,
    # resolve, a domain error for another atom; `<type>(` is claimed only with dead/resolve and when `<` is not a prefix operator
    ("rt303", raw"""rt_str('f(X).', S), read_term(S,T,[blob(error)]), R = T"""),
    ("rt305", raw"""rt_str('f(X).', S), read_term(S,T,[blob(dead)]), R = T"""),
    ("rt306", raw"""rt_str('f(X).', S), read_term(S,T,[blob(resolve)]), R = T"""),
    ("rt307", raw"""rt_str('f.', S), read_term(S,T,[blob(foo)]), R = T"""),
    ("rt308", raw"""rt_str('f.', S), read_term(S,T,[blob(1)]), R = T"""),
    ("rt309", raw"""rt_str('f.', S), read_term(S,T,[blob(_)]), R = T"""),
    ("rt310", raw"""rt_str('<>(1).', S), read_term(S,T,[blob(dead)]), R = T"""),
    (
        "rt311",
        raw"""op(200, fy, rtm:(<)), rt_str('<a>(f).', S), read_term(S,T,[blob(dead),module(rtm)]), R = T"""
    ),
    ("rt312", raw"""rt_str('a < b.', S), read_term(S,T,[blob(dead)]), R = T"""),
    ("rt313", raw"""rt_str('<(1).', S), read_term(S,T,[blob(resolve)]), R = T"""),
    (
        "rt314",
        raw"""rt_file('<a>(1).', S), rt_serr_formal(read_term(S,T,[blob(error)]), R)"""
    ),
    (
        "rt315",
        raw"""op(200, xfy, rtm:(>)), rt_str('a <b>(c).', S), read_term(S,T,[blob(dead),module(rtm)]), R = T"""
    ),
    (
        "rt316",
        raw"""rt_file('X = <a>.', S), rt_serr_formal(read_term(S,T,[blob(dead)]), R)"""
    ),
    ("rt317", raw"""rt_file('<a>(1).', S), rt_serr_formal(read_term(S,T,[]), R)"""),
    ("rt318", raw"""rt_str('f.', S), read_clause(S,T,[blob(foo)]), R = T"""),
    ("rt319", raw"""rt_str('f(X).', S), read_clause(S,T,[blob(dead)]), R = T"""),
    # rt315 and rt316 never reach the tokeniser's blob test (audit D-0376, the in-tree runs of RD1-F2 and RD1-F6): rt311 leaves `<` a prefix
    # operator in module rtm, so blob_syntax_available is false there; `a>.` is one symbol atom, so rt316's raw read ends in end_of_file.
    # rt322: a fresh module (infix `<` only) and an operator position; rt323: the `>` is followed by layout, not by `(`
    (
        "rt322",
        raw"""op(200, xfy, rtn:(>)), rt_str('a <b>(c).', S), read_term(S,T,[blob(dead),module(rtn)]), R = T"""
    ),
    (
        "rt323",
        raw"""rt_file('X = <a> .', S), rt_serr_formal(read_term(S,T,[blob(dead)]), R)"""
    )
]

# KNOWN DIFFERENCE rows: (id, goal, the kernel's exact answer). swipl's answer is in `_RT_PINNED` (the rows after the cases), compared live too.
#   rt300-rt302, rt304: read_term/3 options the kernel REFUSES with a `NotPortedError` (src/pl-read.jl `read_term_from_stream`, R1's decision);
#   swipl answers the term (and for comments/quasi_quotations the collected lists).
#   the rest: a syntax error read from an `open_string/2` stream: swipl's ball carries `stream(S, Line, LinePos, CharNo)`; the kernel's
#   `unify_location` (src/pl-read.jl) throws `NotPortedError` for a stream that is neither a file nor a string stream (the stream
#   table). The kernel pins below are READ from the source, NOT RUN: the gate agent confirms or fixes them at the first run.
const _RT_KNOWN = [
    (
        "rt87",
        raw"""rt_str('a b. c.', S), read_term(S,T,[syntax_errors(fail)]), R = T""",
        "t_rt87 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt88",
        raw"""rt_str('a b. c.', S), read_term(S,T,[syntax_errors(quiet)]), R = T""",
        "t_rt88 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt89",
        raw"""rt_str('a b. c.', S), read_term(S,T,[syntax_errors(dec10)]), R = T""",
        "t_rt89 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt120",
        raw"""rt_serr_formal((rt_str('a b.', S), read(S,_)), R)""",
        "t_rt120 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt121",
        raw"""rt_serr_formal((rt_str('foo(.', S), read(S,_)), R)""",
        "t_rt121 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt122",
        raw"""rt_serr_formal((rt_str('foo(', S), read(S,_)), R)""",
        "t_rt122 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt123",
        raw"""rt_serr_formal((rt_str('\'abc', S), read(S,_)), R)""",
        "t_rt123 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt124",
        raw"""rt_serr_formal((rt_str('foo(X,Y)', S), read_term(S,_,[])), R)""",
        "t_rt124 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt176",
        raw"""rt_str('a', S), '$raw_read'(S, T), R = T""",
        "t_rt176 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt184",
        raw"""rt_str('\'abc', S), '$raw_read'(S, T), R = T""",
        "t_rt184 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt300",
        raw"""rt_str('f(X).', S), read_term(S,T,[comments(C)]), R = T-C""",
        "t_rt300 jlerr NotPortedError read_term's comments option"
    ),
    (
        "rt301",
        raw"""rt_str('f(X).', S), read_term(S,T,[var_prefix(true)]), R = T""",
        "t_rt301 jlerr NotPortedError read_term's var_prefix option"
    ),
    (
        "rt302",
        raw"""rt_str('f(X).', S), read_term(S,T,[quasi_quotations(Q)]), R = T-Q""",
        "t_rt302 jlerr NotPortedError read_term's quasi_quotations option"
    ),
    (
        "rt304",
        raw"""rt_str('f(X).', S), read_term(S,T,[unicode_atoms(accept)]), R = T""",
        "t_rt304 jlerr NotPortedError read_term's unicode_atoms option"
    ),
    # blob(dead|resolve) on `<type>(…)`: swipl reads a dead blob (its type is the answer); the kernel has no blob object: refused when read
    # (DIVERGES in src/pl-read.jl `atom_to_blob_mode_ex`; owner: the blob step). UNVERIFIED on the kernel: gate decides.
    (
        "rt320",
        raw"""rt_str('<a-b>(x, "y").', S), read_term(S,T,[blob(dead)]), blob(T, Ty), R = Ty""",
        "t_rt320 jlerr NotPortedError read: a blob <type>(…)"
    ),
    (
        "rt321",
        raw"""rt_str('<a-b>(x).', S), read_term(S,T,[blob(resolve)]), blob(T, Ty), R = Ty""",
        "t_rt321 jlerr NotPortedError read: a blob <type>(…)"
    ),
    (
        "rt113",
        raw"""rt_serr((rt_file('/* abc', S), read(S,_)), R)""",
        "t_rt113 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt154",
        raw"""rt_str('f("ab", `cd`).', S), read_term(S,T,[back_quotes(symbol_char)]), R = T""",
        "t_rt154 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt163",
        raw"""rt_str('a +++ b.', S), read_term(S,T,[module(nomod)]), R = T""",
        "t_rt163 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt169",
        raw"""rt_str('x.y', S), read_term(S,T,[]), R = T""",
        "t_rt169 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    ),
    (
        "rt187",
        raw"""rt_serr((rt_file('/* abc', S), '$raw_read'(S, _)), R)""",
        "t_rt187 jlerr NotPortedError unify_location: a stream's location, stream(S, L, LP, C)"
    )
]

const _RT_PINNED = [
    "ok",
    "t_rt01 c[116,95,114,116,48,49]/1(c[91,124,93]/2(c[102,111,111]/3(V0,V1,V0),c[91,124,93]/2(a[98,97,114],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil)))))",
    "t_rt02 c[116,95,114,116,48,50]/1(i42)",
    "t_rt03 c[116,95,114,116,48,51]/1(c[102]/8(s[97,98],a[99,32,100],i97,f1.5,c[91,124,93]/2(i1,c[91,124,93]/2(i2,V0)),c[45]/1(i1),c[45]/1(i1),q1r3))",
    "t_rt04 c[116,95,114,116,48,52]/1(c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil)))",
    "t_rt05 c[116,95,114,116,48,53]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_rt06",
    "t_rt07 c[116,95,114,116,48,55]/1(a[121,101,115])",
    "t_rt08 c[116,95,114,116,48,56]/1(c[102,111,111]/1(i7))",
    "t_rt09 c[116,95,114,116,48,57]/1(V0)",
    "t_rt10 c[116,95,114,116,49,48]/1(c[102]/3(V0,V1,V0))",
    "t_rt11 c[116,95,114,116,49,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],stream)))",
    "t_rt12 c[116,95,114,116,49,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt13 c[116,95,114,116,49,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_rt14 c[116,95,114,116,49,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],stream)))",
    "t_rt15 c[116,95,114,116,49,53]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101])))",
    "t_rt16 c[116,95,114,116,49,54]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_rt17 c[116,95,114,116,49,55]/1(c[102,111,111]/1(V0))",
    "t_rt18 c[116,95,114,116,49,56]/1(c[91,124,93]/2(c[102,111,111]/2(V0,V1),c[91,124,93]/2(a[98,97,114],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil))))",
    "t_rt19",
    "t_rt20",
    "t_rt21 c[116,95,114,116,50,49]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_rt22 c[116,95,114,116,50,50]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_rt23 c[116,95,114,116,50,51]/1(c[45]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil))",
    "t_rt24 c[116,95,114,116,50,52]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_rt25 c[116,95,114,116,50,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_rt26 c[116,95,114,116,50,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt30 c[116,95,114,116,51,48]/1(c[45]/2(c[102,111,111]/5(V0,V1,V0,V2,V3),c[91,124,93]/2(c[61]/2(a[88],V0),c[91,124,93]/2(c[61]/2(a[89],V1),c[91,124,93]/2(c[61]/2(a[95,90],V2),nil)))))",
    "t_rt31 c[116,95,114,116,51,49]/1(c[45]/2(c[102,111,111]/5(V0,V1,V0,V2,V3),c[91,124,93]/2(V0,c[91,124,93]/2(V1,c[91,124,93]/2(V2,c[91,124,93]/2(V3,nil))))))",
    "t_rt32 c[116,95,114,116,51,50]/1(c[45]/2(c[102,111,111]/5(V0,V1,V0,V2,V3),c[91,124,93]/2(c[61]/2(a[89],V1),c[91,124,93]/2(c[61]/2(a[95,90],V2),nil))))",
    "t_rt33 c[116,95,114,116,51,51]/1(c[45]/2(c[45]/2(c[45]/2(c[102,111,111]/5(V0,V1,V0,V2,V3),c[91,124,93]/2(c[61]/2(a[88],V0),c[91,124,93]/2(c[61]/2(a[89],V1),c[91,124,93]/2(c[61]/2(a[95,90],V2),nil)))),c[91,124,93]/2(V0,c[91,124,93]/2(V1,c[91,124,93]/2(V2,c[91,124,93]/2(V3,nil))))),c[91,124,93]/2(c[61]/2(a[89],V1),c[91,124,93]/2(c[61]/2(a[95,90],V2),c[91,124,93]/2(c[61]/2(a[95],V3),nil)))))",
    "t_rt34 c[116,95,114,116,51,52]/1(c[102,111,111]/4(V0,V1,V0,V2))",
    "t_rt35 c[116,95,114,116,51,53]/1(c[45]/2(c[102,111,111]/4(V0,V1,V1,V2),c[91,124,93]/2(c[61]/2(a[88],V0),c[91,124,93]/2(c[61]/2(a[95,95,90],V2),nil))))",
    "t_rt36 c[116,95,114,116,51,54]/1(c[45]/2(c[45]/2(c[45]/2(c[102,111,111]/2(a[97],a[98]),nil),nil),nil))",
    "t_rt37 c[116,95,114,116,51,55]/1(c[45]/2(c[45]/2(c[45]/2(c[45]/2(c[45]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil),nil),nil),c[45]/2(i-1,i10)),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i-1,i1,i-1,i0)))",
    "t_rt38 c[116,95,114,116,51,56]/1(c[102]/1(i1))",
    "t_rt39",
    "t_rt40",
    "t_rt41 c[116,95,114,116,52,49]/1(c[45]/2(c[45]/2(c[102]/2(V0,V1),V0),c[91,124,93]/2(c[61]/2(a[89],V1),nil)))",
    "t_rt42 c[116,95,114,116,52,50]/1(c[45]/2(c[45]/2(c[102]/1(V0),V1),c[91,124,93]/2(c[61]/2(a[88],V0),nil)))",
    "t_rt50 c[116,95,114,116,53,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_rt51 c[116,95,114,116,53,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt52 c[116,95,114,116,53,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[108,105,115,116],a[102,111,111])))",
    "t_rt53 c[116,95,114,116,53,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt54 c[116,95,114,116,53,52]/1(c[102]/1(V0))",
    "t_rt55 c[116,95,114,116,53,53]/1(c[102]/1(V0))",
    "t_rt56 c[116,95,114,116,53,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt57 c[116,95,114,116,53,55]/1(c[102]/1(V0))",
    "t_rt58 c[116,95,114,116,53,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_rt59 c[116,95,114,116,53,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[100,111,117,98,108,101,95,113,117,111,116,101,115],a[102,111,111])))",
    "t_rt60 c[116,95,114,116,54,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[109,97,121,98,101])))",
    "t_rt61 c[116,95,114,116,54,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_rt62 c[116,95,114,116,54,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt63 c[116,95,114,116,54,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[98,97,99,107,95,113,117,111,116,101,115],a[102,111,111])))",
    "t_rt64 c[116,95,114,116,54,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[109,97,121,98,101])))",
    "t_rt65",
    "t_rt66",
    "t_rt67 c[116,95,114,116,54,55]/1(c[45]/2(c[45]/2(c[102]/1(V0),V1),c[91,124,93]/2(c[61]/2(a[88],V0),nil)))",
    "t_rt68 c[116,95,114,116,54,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt70 c[116,95,114,116,55,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt71 c[116,95,114,116,55,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_rt72 c[116,95,114,116,55,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],stream)))",
    "t_rt73 c[116,95,114,116,55,51]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101])))",
    "t_rt74 c[116,95,114,116,55,52]/1(c[45]/2(c[102]/1(V0),c[91,124,93]/2(c[61]/2(a[88],V0),nil)))",
    "t_rt75 c[116,95,114,116,55,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],stream)))",
    "t_rt76 c[116,95,114,116,55,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,111,114,95,97,108,105,97,115],i1)))",
    "t_rt77 c[116,95,114,116,55,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,111,114,95,97,108,105,97,115],c[102]/1(a[120]))))",
    "t_rt80",
    "t_rt81",
    "t_rt82 c[116,95,114,116,56,50]/1(a[99])",
    "t_rt83 c[116,95,114,116,56,51]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])))",
    "t_rt84 c[116,95,114,116,56,52]/1(a[99])",
    "t_rt85 c[116,95,114,116,56,53]/1(a[99])",
    "t_rt86 c[116,95,114,116,56,54]/1(a[99])",
    "t_rt100 c[116,95,114,116,49,48,48]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[102,105,108,101]/3(i1,i2,i1)))",
    "t_rt101 c[116,95,114,116,49,48,49]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,99,108,97,117,115,101]),c[102,105,108,101]/3(i1,i4,i3)))",
    "t_rt102 c[116,95,114,116,49,48,50]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101]),c[102,105,108,101]/3(i1,i4,i3)))",
    "t_rt103 c[116,95,114,116,49,48,51]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(c[101,110,100,95,111,102,95,102,105,108,101,95,105,110,95,113,117,111,116,101,100]/1(a[39])),c[102,105,108,101]/3(i1,i0,i0)))",
    "t_rt104 c[116,95,114,116,49,48,52]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101]),c[102,105,108,101]/3(i1,i8,i7)))",
    "t_rt105 c[116,95,114,116,49,48,53]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[99,97,110,110,111,116,95,115,116,97,114,116,95,116,101,114,109]),c[102,105,108,101]/3(i1,i4,i3)))",
    "t_rt106 c[116,95,114,116,49,48,54]/1(a[111,107])",
    "t_rt107 c[116,95,114,116,49,48,55]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[99,97,110,110,111,116,95,115,116,97,114,116,95,116,101,114,109]),c[102,105,108,101]/3(i1,i0,i0)))",
    "t_rt108 c[116,95,114,116,49,48,56]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,99,108,97,115,104]),c[102,105,108,101]/3(i1,i4,i3)))",
    "t_rt109 c[116,95,114,116,49,48,57]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[102,105,108,101]/3(i3,i6,i7)))",
    "t_rt110 c[116,95,114,116,49,49,48]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(c[101,110,100,95,111,102,95,102,105,108,101,95,105,110,95,113,117,111,116,101,100]/1(a[34])),c[102,105,108,101]/3(i1,i0,i0)))",
    "t_rt111 c[116,95,114,116,49,49,49]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[102,105,108,101]/3(i1,i5,i4)))",
    "t_rt112 c[116,95,114,116,49,49,50]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(c[117,110,100,101,102,105,110,101,100,95,99,104,97,114,95,101,115,99,97,112,101]/1(a[113])),c[102,105,108,101]/3(i1,i4,i3)))",
    "t_rt114 c[116,95,114,116,49,49,52]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101]),c[102,105,108,101]/3(i1,i7,i6)))",
    "t_rt115 c[116,95,114,116,49,49,53]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101]),c[102,105,108,101]/3(i1,i8,i7)))",
    "t_rt116 c[116,95,114,116,49,49,54]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[102,105,108,101]/3(i1,i2,i1)))",
    "t_rt117",
    "t_rt118 c[116,95,114,116,49,49,56]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[102,105,108,101]/3(i1,i2,i1)))",
    "t_rt130 c[116,95,114,116,49,51,48]/1(c[45]/2(c[102,111,111]/2(V0,a[98,97,114]),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i2,i1,i2,i2)))",
    "t_rt131 c[116,95,114,116,49,51,49]/1(c[45]/2(c[102,111,111]/2(V0,a[98,97,114]),c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i2,i13,i2,i5,c[91,124,93]/2(c[45]/2(i6,i7),c[91,124,93]/2(c[45]/2(i9,i12),nil)))))",
    "t_rt132 c[116,95,114,116,49,51,50]/1(c[45]/2(c[102,111,111]/2(V0,a[98,97,114]),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i2,i1,i2,i2)))",
    "t_rt133 c[116,95,114,116,49,51,51]/1(c[45]/2(a[120],c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i4,i3,i2,i4)))",
    "t_rt134 c[116,95,114,116,49,51,52]/1(c[45]/2(c[102,111,111]/2(a[97],a[98]),c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i8,i0,i3,c[91,124,93]/2(c[45]/2(i4,i5),c[91,124,93]/2(c[45]/2(i6,i7),nil)))))",
    "t_rt135 c[116,95,114,116,49,51,53]/1(c[45]/2(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],V0)),c[108,105,115,116,95,112,111,115,105,116,105,111,110]/4(i0,i7,c[91,124,93]/2(c[45]/2(i1,i2),c[91,124,93]/2(c[45]/2(i3,i4),nil)),c[45]/2(i5,i6))))",
    "t_rt136 c[116,95,114,116,49,51,54]/1(c[45]/2(c[45]/2(c[45]/2(c[45]/2(c[43]/2(c[45]/1(i1),c[123,125]/1(a[120])),s[115]),c[113]/1(V0)),nil),c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i29,i25,i26,c[91,124,93]/2(c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i24,i16,i17,c[91,124,93]/2(c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i15,i10,i11,c[91,124,93]/2(c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i9,i4,i5,c[91,124,93]/2(c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i3,i0,i1,c[91,124,93]/2(c[45]/2(i2,i3),nil)),c[91,124,93]/2(c[98,114,97,99,101,95,116,101,114,109,95,112,111,115,105,116,105,111,110]/3(i6,i9,c[45]/2(i7,i8)),nil))),c[91,124,93]/2(c[115,116,114,105,110,103,95,112,111,115,105,116,105,111,110]/2(i12,i15),nil))),c[91,124,93]/2(c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i18,i24,i18,i21,c[91,124,93]/2(c[45]/2(i22,i23),nil)),nil))),c[91,124,93]/2(c[45]/2(i27,i29),nil)))))",
    "t_rt137 c[116,95,114,116,49,51,55]/1(c[91,124,93]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),c[91,124,93]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i3,i1,i3,i3),c[91,124,93]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i6,i2,i0,i6),nil))))",
    "t_rt138 c[116,95,114,116,49,51,56]/1(c[91,124,93]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),c[91,124,93]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i3,i1,i3,i3),c[91,124,93]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i6,i2,i0,i6),nil))))",
    "t_rt139 c[116,95,114,116,49,51,57]/1(c[45]/2(c[45]/2(a[101,110,100,95,111,102,95,102,105,108,101],c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i1,i1,i1,i2)),c[45]/2(i1,i12)))",
    "t_rt140 c[116,95,114,116,49,52,48]/1(c[45]/2(c[43]/2(c[43]/2(c[43]/2(c[43]/2(s[115],a[97,32,98]),i99),f1.5),c[97]/1(V0)),c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i30,i24,i25,c[91,124,93]/2(c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i23,i18,i19,c[91,124,93]/2(c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i17,i12,i13,c[91,124,93]/2(c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i11,i4,i5,c[91,124,93]/2(c[115,116,114,105,110,103,95,112,111,115,105,116,105,111,110]/2(i0,i3),c[91,124,93]/2(c[45]/2(i6,i11),nil))),c[91,124,93]/2(c[45]/2(i14,i17),nil))),c[91,124,93]/2(c[45]/2(i20,i23),nil))),c[91,124,93]/2(c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i26,i30,i26,i27,c[91,124,93]/2(c[45]/2(i28,i29),nil)),nil)))))",
    "t_rt141 c[116,95,114,116,49,52,49]/1(c[45]/2(c[58,45]/2(c[44]/2(a[97],a[98]),c[123,125]/1(a[99])),c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i14,i8,i10,c[91,124,93]/2(c[112,97,114,101,110,116,104,101,115,101,115,95,116,101,114,109,95,112,111,115,105,116,105,111,110]/3(i0,i7,c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i1,i6,i3,i4,c[91,124,93]/2(c[45]/2(i1,i2),c[91,124,93]/2(c[45]/2(i5,i6),nil)))),c[91,124,93]/2(c[98,114,97,99,101,95,116,101,114,109,95,112,111,115,105,116,105,111,110]/3(i11,i14,c[45]/2(i12,i13)),nil)))))",
    "t_rt142 c[116,95,114,116,49,52,50]/1(c[45]/2(c[92,43]/1(a[97]),c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i4,i0,i2,c[91,124,93]/2(c[45]/2(i3,i4),nil))))",
    "t_rt143 c[116,95,114,116,49,52,51]/1(c[45]/2(c[102]/2(a[45],a[97]),c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i8,i0,i1,c[91,124,93]/2(c[45]/2(i2,i3),c[91,124,93]/2(c[45]/2(i6,i7),nil)))))",
    "t_rt144 c[116,95,114,116,49,52,52]/1(c[45]/2(nil,c[45]/2(i0,i2)))",
    "t_rt150 c[116,95,114,116,49,53,48]/1(c[102]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i98,nil)),c[91,124,93]/2(i99,c[91,124,93]/2(i100,nil))))",
    "t_rt151 c[116,95,114,116,49,53,49]/1(c[102]/2(a[97,98],c[91,124,93]/2(i99,c[91,124,93]/2(i100,nil))))",
    "t_rt152 c[116,95,114,116,49,53,50]/1(c[102]/2(s[97,98],s[99,100]))",
    "t_rt153 c[116,95,114,116,49,53,51]/1(c[102]/2(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil)),c[91,124,93]/2(i99,c[91,124,93]/2(i100,nil))))",
    "t_rt155 c[116,95,114,116,49,53,53]/1(c[102]/2(s[97,98],c[91,124,93]/2(i99,c[91,124,93]/2(i100,nil))))",
    "t_rt156 c[116,95,114,116,49,53,54]/1(c[102]/1(a[97,92,110,98]))",
    "t_rt157 c[116,95,114,116,49,53,55]/1(c[102]/1(a[97,10,98]))",
    "t_rt158 c[116,95,114,116,49,53,56]/1(c[58,45]/2(c[102]/1(V0),c[61]/2(V0,c[64]/2(V1,c[91,124,93]/2(c[61]/2(V1,c[102]/1(V1)),nil)))))",
    "t_rt159 c[116,95,114,116,49,53,57]/1(c[45]/2(c[102]/2(V0,V0),c[91,124,93]/2(c[61]/2(a[88],V0),nil)))",
    "t_rt160 c[116,95,114,116,49,54,48]/1(c[91,124,93]/2(a[97],a[98]))",
    "t_rt161 c[116,95,114,116,49,54,49]/1(c[91,124,93]/2(a[97],a[98]))",
    "t_rt162 c[116,95,114,116,49,54,50]/1(c[58]/2(a[102,111,111],a[98,97,114]))",
    "t_rt164 c[116,95,114,116,49,54,52]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[102,105,108,101]/3(i1,i2,i1)))",
    "t_rt165 c[116,95,114,116,49,54,53]/1(c[45]/2(c[102]/2(V0,V1),c[91,124,93]/2(c[61]/2(a[88],V0),c[91,124,93]/2(c[61]/2(a[89],V1),nil))))",
    "t_rt166 c[116,95,114,116,49,54,54]/1(c[102]/2(c[36,86,65,82]/1(i1),s[120]))",
    "t_rt167 c[116,95,114,116,49,54,55]/1(a[120])",
    "t_rt168 c[116,95,114,116,49,54,56]/1(c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil)))))",
    "t_rt170 c[116,95,114,116,49,55,48]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_rt171 c[116,95,114,116,49,55,49]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_rt172 c[116,95,114,116,49,55,50]/1(a[102,111,111,40,32,88,32,44,98,32,41])",
    "t_rt173 c[116,95,114,116,49,55,51]/1(a[48,39,32])",
    "t_rt174 c[116,95,114,116,49,55,52]/1(a[97])",
    "t_rt175 c[116,95,114,116,49,55,53]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_rt177 c[116,95,114,116,49,55,55]/1(c[91,124,93]/2(a[102,111,111,40,32,88,32,44,98,32,41],c[91,124,93]/2(a[98,97,114,40,32,89,32,41],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil))))",
    "t_rt178 c[116,95,114,116,49,55,56]/1(c[91,124,93]/2(a[39,97,46,32,98,39],c[91,124,93]/2(a[34,120,46,32,121,34],c[91,124,93]/2(a[99],nil))))",
    "t_rt179 c[116,95,114,116,49,55,57]/1(a[102,111,111,40,32,32,88,44,10,32,32,32,98,41])",
    "t_rt180 c[116,95,114,116,49,56,48]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_rt181 c[116,95,114,116,49,56,49]/1(a[98])",
    "t_rt182 c[116,95,114,116,49,56,50]/1(a[98])",
    "t_rt183 c[116,95,114,116,49,56,51]/1(a[102,40,88,44,32,89,44,32,88,41,32,58,45,32,103,40,89,41])",
    "t_rt185 c[116,95,114,116,49,56,53]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(c[101,110,100,95,111,102,95,102,105,108,101,95,105,110,95,113,117,111,116,101,100]/1(a[39])),c[102,105,108,101]/3(i1,i0,i0)))",
    "t_rt186 c[116,95,114,116,49,56,54]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101]),c[102,105,108,101]/3(i1,i1,i0)))",
    "t_rt188 c[116,95,114,116,49,56,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt189 c[116,95,114,116,49,56,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_rt190 c[116,95,114,116,49,57,48]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],stream)))",
    "t_rt191 c[116,95,114,116,49,57,49]/1(a[102,111,111])",
    "t_rt192",
    "t_rt193 c[116,95,114,116,49,57,51]/1(a[121,101,115])",
    "t_rt194 c[116,95,114,116,49,57,52]/1(a[34,97,98,99,34])",
    "t_rt195 c[116,95,114,116,49,57,53]/1(a[91,32,97,32,44,32,98,32,124,32,67,32,93])",
    "t_rt196 c[116,95,114,116,49,57,54]/1(a[97,46,98])",
    "t_rt197 c[116,95,114,116,49,57,55]/1(a[102,40,48,39,97,44,32,48,39,92,110,44,32,48,39,39,39,41])",
    "t_rt198 c[116,95,114,116,49,57,56]/1(a[49,46,53,32,43,32,50,46,48,101,51])",
    "t_rt199 c[116,95,114,116,49,57,57]/1(a[97])",
    "t_rt200 c[116,95,114,116,50,48,48]/1(a[121,101,115])",
    "t_rt201",
    "t_rt202",
    "t_rt203",
    "t_rt204",
    "t_rt205 c[116,95,114,116,50,48,53]/1(a[121,101,115])",
    "t_rt206 c[116,95,114,116,50,48,54]/1(a[121,101,115])",
    "t_rt207 c[116,95,114,116,50,48,55]/1(a[121,101,115])",
    "t_rt208 c[116,95,114,116,50,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_rt209 c[116,95,114,116,50,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_rt210 c[116,95,114,116,50,49,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt211 c[116,95,114,116,50,49,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[70,111,111])))",
    "t_rt212 c[116,95,114,116,50,49,50]/1(a[121,101,115])",
    "t_rt213",
    "t_rt214 c[116,95,114,116,50,49,52]/1(a[121,101,115])",
    "t_rt215 c[116,95,114,116,50,49,53]/1(a[121,101,115])",
    "t_rt216",
    "t_rt217 c[116,95,114,116,50,49,55]/1(a[121,101,115])",
    "t_rt218 c[116,95,114,116,50,49,56]/1(a[121,101,115])",
    "t_rt219 c[116,95,114,116,50,49,57]/1(a[121,101,115])",
    "t_rt303 c[116,95,114,116,51,48,51]/1(c[102]/1(V0))",
    "t_rt305 c[116,95,114,116,51,48,53]/1(c[102]/1(V0))",
    "t_rt306 c[116,95,114,116,51,48,54]/1(c[102]/1(V0))",
    "t_rt307 c[116,95,114,116,51,48,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[98,108,111,98],a[102,111,111])))",
    "t_rt308 c[116,95,114,116,51,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_rt309 c[116,95,114,116,51,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rt310 c[116,95,114,116,51,49,48]/1(c[60,62]/1(i1))",
    "t_rt311 c[116,95,114,116,51,49,49]/1(c[62]/2(c[60]/1(a[97]),a[102]))",
    "t_rt312 c[116,95,114,116,51,49,50]/1(c[60]/2(a[97],a[98]))",
    "t_rt313 c[116,95,114,116,51,49,51]/1(c[60]/1(i1))",
    "t_rt314 c[116,95,114,116,51,49,52]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])))",
    "t_rt315 c[116,95,114,116,51,49,53]/1(c[60]/2(a[97],c[62]/2(a[98],a[99])))",
    "t_rt316 c[116,95,114,116,51,49,54]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101])))",
    "t_rt317 c[116,95,114,116,51,49,55]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])))",
    "t_rt318 c[116,95,114,116,51,49,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[98,108,111,98],a[102,111,111])))",
    "t_rt319 c[116,95,114,116,51,49,57]/1(c[102]/1(V0))",
    "t_rt322 c[116,95,114,116,51,50,50]/1(c[60]/2(a[97],c[62]/2(a[98],a[99])))",
    "t_rt323 c[116,95,114,116,51,50,51]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])))",
    "t_rt87",
    "t_rt88",
    "t_rt89 c[116,95,114,116,56,57]/1(a[99])",
    "t_rt120 c[116,95,114,116,49,50,48]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])))",
    "t_rt121 c[116,95,114,116,49,50,49]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,99,108,97,117,115,101])))",
    "t_rt122 c[116,95,114,116,49,50,50]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101])))",
    "t_rt123 c[116,95,114,116,49,50,51]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(c[101,110,100,95,111,102,95,102,105,108,101,95,105,110,95,113,117,111,116,101,100]/1(a[39]))))",
    "t_rt124 c[116,95,114,116,49,50,52]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101])))",
    "t_rt176 c[116,95,114,116,49,55,54]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101])))",
    "t_rt184 c[116,95,114,116,49,56,52]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(c[101,110,100,95,111,102,95,102,105,108,101,95,105,110,95,113,117,111,116,101,100]/1(a[39]))))",
    "t_rt300 c[116,95,114,116,51,48,48]/1(c[45]/2(c[102]/1(V0),nil))",
    "t_rt301 c[116,95,114,116,51,48,49]/1(c[102]/1(a[88]))",
    "t_rt302 c[116,95,114,116,51,48,50]/1(c[45]/2(c[102]/1(V0),nil))",
    "t_rt304 c[116,95,114,116,51,48,52]/1(c[102]/1(V0))",
    "t_rt320 c[116,95,114,116,51,50,48]/1(a[97,45,98])",
    "t_rt321 c[116,95,114,116,51,50,49]/1(a[97,45,98])",
    "t_rt113 c[116,95,114,116,49,49,51]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101,95,105,110,95,98,108,111,99,107,95,99,111,109,109,101,110,116]),c[115,116,114,101,97,109]/3(i1,i0,i0)))",
    "t_rt154 c[116,95,114,116,49,53,52]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])))",
    "t_rt163 c[116,95,114,116,49,54,51]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])))",
    "t_rt169 c[116,95,114,116,49,54,57]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101])))",
    "t_rt187 c[116,95,114,116,49,56,55]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101,95,105,110,95,98,108,111,99,107,95,99,111,109,109,101,110,116]),c[115,116,114,101,97,109]/3(i1,i0,i0)))"
]

"The program and cases as one file (in `dir`); the case predicates' names."
function _rt_file(dir::String)::Tuple{String, Vector{String}}
    ids = vcat([id for (id, _) in _RT_CASES], [id for (id, _, _) in _RT_KNOWN])
    goals = vcat([g for (_, g) in _RT_CASES], [g for (_, g, _) in _RT_KNOWN])
    names = ["t_$(id)" for id in ids]
    text =
        replace(_RT_PROGRAM, "@RTDIR@" => dir) * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in zip(ids, goals)
        ])
    f = joinpath(dir, "rd1.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's. A Julia exception out of a row is its line: `jlerr <type> <what>`."
function _rt_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_RT}()
    ld = LK.PL_local_data{_RT}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _rt_enc(ball::_RT)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_rts(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        rld = LK.PL_local_data{_RT}(gd)        # a fresh engine per row: a Julia exception leaves no frame behind
        try
            fid = LK.PL_open_foreign_frame(rld)
            a = LK.PL_new_term_refs(rld, 1)
            LK.putSlotValue!(rld, a + 1, mk_var(_RT, LK.fresh_var_keys!(1)), LK.PutVarMap())
            qid = LK.PL_open_query(
                gd, rld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
            )
            n = 0
            while (n += 1) <= 50
                rc = LK.PL_next_solution(gd, rld, qid)
                if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                    push!(
                        sols,
                        _rt_enc(
                            mk_expr(_RT, _RT[_rts(name), lk_answers(rld, (a:a)...)...])
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

@testset "read/1,2, read_term/2,3, \$raw_read/1,2, \$is_named_var/1 as swipl's (rt01-rt219, rt300-rt323)" begin
    mktempdir() do dir
        f, names = _rt_file(dir)
        kl = _rt_kernel(f, names)
        ncase = length(_RT_CASES)
        @test length(kl) == length(_RT_PINNED)
        # the rows that are answers of the program: the kernel's line is swipl's pinned line
        for (k, p) in zip(kl[1:(1 + ncase)], _RT_PINNED[1:(1 + ncase)])
            k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
            @test k == p
        end
        # KNOWN DIFFERENCE rows: the kernel's exact current answer (swipl's is the pin of the same row, compared live below)
        for (j, (id, _, kpin)) in enumerate(_RT_KNOWN)
            k = kl[1 + ncase + j]
            k == kpin || println(stderr, "  ours  ", k, "\n  known ", kpin)
            @test k == kpin
            @test _RT_PINNED[1 + ncase + j] == "t_$id" ||
                startswith(_RT_PINNED[1 + ncase + j], "t_$id ")
            @test _RT_PINNED[1 + ncase + j] != kpin
        end
    end
    # not vacuous: the pins hold terms read, raised errors, failures and end_of_file, so the comparison can pass and can fail
    nraised = count(l -> occursin("c[114,97,105,115,101,100]", l), _RT_PINNED)       # raised(...)
    @test nraised >= 60
    @test count(
        l -> occursin("a[101,110,100,95,111,102,95,102,105,108,101]", l), _RT_PINNED
    ) >= 10    # end_of_file
    @test count(l -> !occursin(' ', l), _RT_PINNED[2:end]) >= 10                     # the rows that fail: no answer
    @test count(
        l -> occursin("c[115,121,110,116,97,120,95,101,114,114,111,114]/1(", l), _RT_PINNED
    ) >= 25    # syntax_error(...)
    @test count(
        l -> occursin(
            "c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(", l
        ),
        _RT_PINNED
    ) >= 7    # '$stream_position'/4
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_RT_PINNED) == length(_RT_CASES) + length(_RT_KNOWN) + 1
    if swipl === nothing
        @info "RD1 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        mktempdir() do dir
            f, names = _rt_file(dir)
            @test _rt_swipl_lines(f, names) == _RT_PINNED
        end
    end
end
