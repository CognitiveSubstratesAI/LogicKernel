# ORIGINAL: RD2a's gate — the comments collector (`comments(C)` of read_term/3 and read_clause/3), eof_action(error) at raw_read2, `var_prefix(P)`, and `process_comment(true)` with `prolog:comment_hook/4` (src/pl-read.jl `add_comment`, `raw_read2`, `callCommentHook`, `read_clause`, `read_term_from_stream`) against swipl 10.1.20.
# test/core_text/test_read_comments_swipl.jl — a program consulted by the kernel's loader whose cases `t_<id>(R)` run IN ORDER in one database
# (the design of test_read_stream_swipl.jl): rc01-rc21 the comments(C) option of read_term/3 (a block comment before, inside and after the term, a run
# of %-lines as ONE comment, a nested block comment, a file stream, a stream without positions: `-`-Str, comments(foo) that cannot unify, syntax errors);
# rc30-rc36 eof_action(error): reading past the end raises permission_error(input, past_end_of_stream, S); rc40-rc50 var_prefix; rc60-rc68 read_clause/3
# comments(C) and process_comment(Bool) before any hook is made; rh01-rh11 the hook (`rt_hook_on` asserts clauses of prolog:comment_hook/4 that record
# their four arguments, and one that throws on `/* boom */`).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, LC_ALL=C, from evidence/RD2/gen_comments.py of the audit channel); with `swipl` on PATH the live
#     answers are compared with the pins too.
#   * NOT here: a blob `<type>(...)` (test_read_blob_swipl.jl), quasi-quotations and read_term's quasi_quotations option (test_read_qq_swipl.jl), both read
#     since RD2; unicode_atoms stays refused (pinned in test_read_positions_swipl.jl and test_canonical_readatom_swipl.jl).
#   * UNVERIFIED on the kernel: written without running the kernel (edit-only step); the gate decides.
#   * swipl 10.1.20 FAILS read_clause/3 when a hook is defined and a syntax error is retried (observed on `% c\nf(a b).\n% d\ng(_).`); the kernel retries
#     cleanly (src/pl-read.jl read_clause DIVERGES): no row, the difference is recorded in docs/architecture.md.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream readers, built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _RC = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_rcs(x) = lk_sym(_RC, Symbol(x))

_rc_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _rc_enc(t::_RC, seen::Vector{UInt64}=UInt64[])::String
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
        return is_nil(t) ? "nil" : "a" * _rc_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _rc_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _rc_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_rc_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the driver of test_at_body_swipl.jl (consult, then every answer of each t_<id>/1, `enc`oded)
const _RC_DRIVER = raw"""
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
function _rc_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _RC_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        withenv("LC_ALL" => "C") do
            read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
        end
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: the stream openers, the error-location helper and the comment hook maker; `@RTDIR@` is the scratch directory. The case predicates follow, written by `_rc_file`.
const _RC_PROGRAM = raw"""
rt_path(P) :- atom_concat('@RTDIR@', '/rt.txt', P).
rt_str(Text, S) :- open_string(Text, S).
rt_nopos(Text, S) :- open_string(Text, S), set_stream(S, record_position(false)).
rt_file(Text, S) :- rt_path(P), open(P, write, O), write(O, Text), close(O), open(P, read, S).
rt_ctx(file(_, L, LP, C), file(L, LP, C)) :- !.
rt_ctx(stream(_, L, LP, C), stream(L, LP, C)) :- !.
rt_ctx(_, other).
rt_serr(G, R) :- catch((G, R = ok), error(F, C), (rt_ctx(C, C1), R = raised(F, C1))).
:- dynamic rt_seen/4, rt_hook_done/0.
rt_hook_on :-
    retractall(rt_seen(_,_,_,_)),
    (   rt_hook_done -> true
    ;   dynamic(prolog:comment_hook/4),
        assertz((prolog:comment_hook(C, _, _, _) :- C = [_-"/* boom */"|_], !, throw(error(rt_boom, _)))),
        assertz((prolog:comment_hook(C, P, T, V) :- user:assertz(rt_seen(C, P, T, V)))),
        assertz(rt_hook_done)
    ).
rt_seen_all(L) :- findall(C-P-T-V, rt_seen(C, P, T, V), L).
"""

# (id, goal), run IN ORDER; `R` is the answer. rc*: the options; rh*: the hook (rt_hook_on makes it, once, so rh* come last)
const _RC_CASES = [
    (
        "rc01",
        raw"""rt_str('/* a */ f(X). % c', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc02",
        raw"""rt_str('% one\nf(X).', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc03",
        raw"""rt_str('% a\n% b\n\nf.', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc04",
        raw"""rt_str('% a\n\n% b\nf.', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc05",
        raw"""rt_str('f(/* x */ a, % y\n b).', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc06",
        raw"""rt_str('/* a /* b */ c */ g.', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc07",
        raw"""rt_str('f(X). % c', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc08",
        raw"""rt_str('% only\n', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc09",
        raw"""rt_str('/* \x3bb\\n */ f.', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc10",
        raw"""rt_file('x.\n/* a */\n% b\nf.\n', S), read(S,_), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc11",
        raw"""rt_nopos('/* a */ f. % c', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc12",
        raw"""rt_nopos('% a\n% b\nf.', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc13",
        raw"""rt_str('/* a */ f.', S), read_term(S,T,[comments(foo)]), R = T"""
    ),
    (
        "rc14",
        raw"""rt_str('f.', S), read_term(S,T,[comments(foo)]), R = T"""
    ),
    (
        "rc15",
        raw"""rt_str('% a\nf.', S), read_term(S,T,[comments([X|Y])]), R = T-X-Y"""
    ),
    (
        "rc16",
        raw"""rt_str('% a\nf(X,Y).', S), read_term(S,T,[comments(C), variable_names(Vs)]), R = T-Vs-C"""
    ),
    (
        "rc17",
        raw"""rt_serr((rt_str('/* a */ f(.', S), read_term(S,_,[comments(_)])), R)"""
    ),
    (
        "rc18",
        raw"""rt_serr((rt_str('/* abc', S), read_term(S,_,[comments(_)])), R)"""
    ),
    (
        "rc19",
        raw"""rt_str('f(a /b). % c', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc20",
        raw"""rt_str('a. % b\n% c\nd.', S), read_term(S,A,[comments(C1)]), read_term(S,B,[comments(C2)]), R = A-B-C1-C2"""
    ),
    (
        "rc21",
        raw"""rt_str('/* a */ /* b */ f.', S), read_term(S,T,[comments(C), term_position(P)]), R = T-C-P"""
    ),
    (
        "rc30",
        raw"""rt_str('a.', S), set_stream(S, eof_action(error)), read(S,A), read(S,B), R = [A,B]"""
    ),
    (
        "rc31",
        raw"""rt_str('a.', S), set_stream(S, eof_action(error)), read(S,_), read(S,_), read(S,C), R = C"""
    ),
    (
        "rc32",
        raw"""rt_str('a.', S), set_stream(S, eof_action(error)), '$raw_read'(S,_), '$raw_read'(S,_), '$raw_read'(S,C), R = C"""
    ),
    (
        "rc33",
        raw"""rt_str('a.', S), set_stream(S, eof_action(eof_code)), read(S,A), read(S,B), read(S,C), R = [A,B,C]"""
    ),
    (
        "rc34",
        raw"""rt_str('a.', S), set_stream(S, eof_action(error)), read(S,_), read(S,_), read_term(S,C,[comments(Cs)]), R = C-Cs"""
    ),
    (
        "rc35",
        raw"""rt_str('a.', S), set_stream(S, eof_action(error)), read_clause(S,_,[]), read_clause(S,_,[]), read_clause(S,C,[]), R = C"""
    ),
    (
        "rc36",
        raw"""rt_str('% c\n', S), set_stream(S, eof_action(error)), read(S,A), read(S,B), R = [A,B]"""
    ),
    (
        "rc40",
        raw"""rt_str('f(X, _Y, _, _).', S), read_term(S,T,[var_prefix(true)]), R = T"""
    ),
    (
        "rc41",
        raw"""rt_str('f(X, _Y, _, _).', S), read_term(S,T,[var_prefix(false)]), R = T"""
    ),
    (
        "rc42",
        raw"""rt_str('f(X, ?Y, _Z, ?).', S), read_term(S,T,[var_prefix('?')]), R = T"""
    ),
    (
        "rc43",
        raw"""rt_str('f(X).', S), read_term(S,T,[var_prefix(bad)]), R = T"""
    ),
    (
        "rc44",
        raw"""rt_str('f(X).', S), read_term(S,T,[var_prefix(1)]), R = T"""
    ),
    (
        "rc45",
        raw"""rt_str('f(X).', S), read_term(S,T,[var_prefix(_)]), R = T"""
    ),
    (
        "rc46",
        raw"""rt_str('f(X, _Y).', S), read_term(S,T,[var_prefix(true), variable_names(Vs)]), R = T-Vs"""
    ),
    (
        "rc47",
        raw"""rt_str('f(X, _Y, _).', S), read_clause(S,T,[var_prefix(true)]), R = T"""
    ),
    (
        "rc48",
        raw"""rt_str('f(X).', S), read_clause(S,T,[var_prefix(bad)]), R = T"""
    ),
    (
        "rc49",
        raw"""rt_str('f(X, ?Y, _Z).', S), read_clause(S,T,[var_prefix('?'), variable_names(Vs)]), R = T-Vs"""
    ),
    (
        "rc50",
        raw"""rt_str('f(X, _Y).', S), read_term(S,T,[var_prefix(true), module(user)]), R = T"""
    ),
    (
        "rc60",
        raw"""rt_str('% c\nf(X, X).', S), read_clause(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc61",
        raw"""rt_str('% c\nf(X, X).', S), read_clause(S,T,[comments(C), process_comment(false)]), R = T-C"""
    ),
    (
        "rc62",
        raw"""rt_str('% c\nf(X, X).', S), read_clause(S,T,[]), R = T"""
    ),
    (
        "rc63",
        raw"""rt_str('/* c */ f(X, X).', S), read_clause(S,T,[comments(C), term_position(P)]), R = T-C-P"""
    ),
    (
        "rc64",
        raw"""rt_str('% c\nf(X, X).', S), read_clause(S,T,[process_comment(true)]), R = T"""
    ),
    (
        "rc65",
        raw"""rt_str('f(X, X).', S), read_clause(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc66",
        raw"""rt_str('% only\n', S), read_clause(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc67",
        raw"""rt_nopos('% c\nf(_).', S), read_clause(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "rc68",
        raw"""rt_str('f(X, X).', S), read_clause(S,T,[process_comment(true)]), R = T"""
    ),
    (
        "rh01",
        raw"""rt_hook_on, rt_str('% c\nf(X, X).', S), read_clause(S,T,[]), rt_seen_all(R0), R = T-R0"""
    ),
    (
        "rh02",
        raw"""rt_hook_on, rt_str('% c\nf(X, Y, X).', S), read_clause(S,T,[variable_names(Vs)]), rt_seen_all(R0), R = T-Vs-R0"""
    ),
    (
        "rh03",
        raw"""rt_hook_on, rt_str('% c\nf(X, X).', S), read_clause(S,T,[process_comment(false)]), rt_seen_all(R0), R = T-R0"""
    ),
    (
        "rh04",
        raw"""rt_hook_on, rt_str('f(X, X).', S), read_clause(S,T,[]), rt_seen_all(R0), R = T-R0"""
    ),
    (
        "rh05",
        raw"""rt_hook_on, rt_str('% c\nf(X, X).', S), read_clause(S,T,[comments(C)]), rt_seen_all(R0), R = T-C-R0"""
    ),
    (
        "rh06",
        raw"""rt_hook_on, rt_str('% c\nf(X, X).', S), read_clause(S,T,[term_position(P)]), rt_seen_all(R0), R = T-P-R0"""
    ),
    (
        "rh07",
        raw"""rt_hook_on, rt_str('/* boom */ f(_).', S), read_clause(S,T,[]), R = T"""
    ),
    (
        "rh08",
        raw"""rt_hook_on, rt_str('/* a */ % b\nf(X, X).', S), read_clause(S,T,[]), rt_seen_all(R0), R = T-R0"""
    ),
    (
        "rh10",
        raw"""rt_hook_on, rt_str('% c\nf(X, X).', S), read_clause(S,T,[process_comment(true), comments(C)]), rt_seen_all(R0), R = T-C-R0"""
    ),
    (
        "rh11",
        raw"""rt_hook_on, rt_str('% c\nf(X, X).', S), read_clause(S,T,[]), rt_seen_all(R0), read_term(S,U,[]), R = T-U-R0"""
    )
]

# swipl 10.1.20, LC_ALL=C: the lines of the driver (tools in evidence/RD2/gen_comments.py of the lk-channel)
const _RC_PINNED = [
    "ok",
    "t_rc01 c[116,95,114,99,48,49]/1(c[45]/2(c[102]/1(V0),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[47,42,32,97,32,42,47]),nil)))",
    "t_rc02 c[116,95,114,99,48,50]/1(c[45]/2(c[102]/1(V0),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,111,110,101]),nil)))",
    "t_rc03 c[116,95,114,99,48,51]/1(c[45]/2(a[102],c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,97,10,37,32,98]),nil)))",
    "t_rc04 c[116,95,114,99,48,52]/1(c[45]/2(a[102],c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,97]),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i5,i3,i0,i0),s[37,32,98]),nil))))",
    "t_rc05 c[116,95,114,99,48,53]/1(c[45]/2(c[102]/2(a[97],a[98]),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i2,i1,i2,i0),s[47,42,32,120,32,42,47]),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i13,i1,i13,i0),s[37,32,121]),nil))))",
    "t_rc06 c[116,95,114,99,48,54]/1(c[45]/2(a[103],c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[47,42,32,97,32,47,42,32,98,32,42,47,32,99,32,42,47]),nil)))",
    "t_rc07 c[116,95,114,99,48,55]/1(c[45]/2(c[102]/1(V0),nil))",
    "t_rc08 c[116,95,114,99,48,56]/1(c[45]/2(a[101,110,100,95,111,102,95,102,105,108,101],c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,111,110,108,121]),nil)))",
    "t_rc09 c[116,95,114,99,48,57]/1(c[45]/2(a[102],c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[47,42,32,955,10,32,42,47]),nil)))",
    "t_rc10 c[116,95,114,99,49,48]/1(c[45]/2(a[102],c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i3,i2,i0,i0),s[47,42,32,97,32,42,47]),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i11,i3,i0,i0),s[37,32,98]),nil))))",
    "t_rc11 c[116,95,114,99,49,49]/1(c[45]/2(a[102],c[91,124,93]/2(c[45]/2(a[45],s[47,42,32,97,32,42,47]),nil)))",
    "t_rc12 c[116,95,114,99,49,50]/1(c[45]/2(a[102],c[91,124,93]/2(c[45]/2(a[45],s[37,32,97,10,37,32,98]),nil)))",
    "t_rc13",
    "t_rc14",
    "t_rc15 c[116,95,114,99,49,53]/1(c[45]/2(c[45]/2(a[102],c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,97])),nil))",
    "t_rc16 c[116,95,114,99,49,54]/1(c[45]/2(c[45]/2(c[102]/2(V0,V1),c[91,124,93]/2(c[61]/2(a[88],V0),c[91,124,93]/2(c[61]/2(a[89],V1),nil))),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,97]),nil)))",
    "t_rc17 c[116,95,114,99,49,55]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,99,108,97,117,115,101]),c[115,116,114,101,97,109]/3(i1,i10,i9)))",
    "t_rc18 c[116,95,114,99,49,56]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101,95,105,110,95,98,108,111,99,107,95,99,111,109,109,101,110,116]),c[115,116,114,101,97,109]/3(i1,i0,i0)))",
    "t_rc19 c[116,95,114,99,49,57]/1(c[45]/2(c[102]/1(c[47]/2(a[97],a[98])),nil))",
    "t_rc20 c[116,95,114,99,50,48]/1(c[45]/2(c[45]/2(c[45]/2(a[97],a[100]),nil),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i3,i1,i3,i0),s[37,32,98,10,37,32,99]),nil)))",
    "t_rc21 c[116,95,114,99,50,49]/1(c[45]/2(c[45]/2(a[102],c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[47,42,32,97,32,42,47]),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i8,i1,i8,i0),s[47,42,32,98,32,42,47]),nil))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i16,i1,i16,i16)))",
    "t_rc30 c[116,95,114,99,51,48]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil)))",
    "t_rc31 c[116,95,114,99,51,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[112,97,115,116,95,101,110,100,95,111,102,95,115,116,114,101,97,109],stream)))",
    "t_rc32 c[116,95,114,99,51,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[112,97,115,116,95,101,110,100,95,111,102,95,115,116,114,101,97,109],stream)))",
    "t_rc33 c[116,95,114,99,51,51]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil))))",
    "t_rc34 c[116,95,114,99,51,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[112,97,115,116,95,101,110,100,95,111,102,95,115,116,114,101,97,109],stream)))",
    "t_rc35 c[116,95,114,99,51,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[112,97,115,116,95,101,110,100,95,111,102,95,115,116,114,101,97,109],stream)))",
    "t_rc36 c[116,95,114,99,51,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[112,97,115,116,95,101,110,100,95,111,102,95,115,116,114,101,97,109],stream)))",
    "t_rc40 c[116,95,114,99,52,48]/1(c[102]/4(a[88],V0,V1,V2))",
    "t_rc41 c[116,95,114,99,52,49]/1(c[102]/4(V0,V1,V2,V3))",
    "t_rc42 c[116,95,114,99,52,50]/1(c[102]/4(a[88],V0,a[95,90],a[63]))",
    "t_rc43 c[116,95,114,99,52,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[118,97,114,95,112,114,101,102,105,120],a[98,97,100])))",
    "t_rc44 c[116,95,114,99,52,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_rc45 c[116,95,114,99,52,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_rc46 c[116,95,114,99,52,54]/1(c[45]/2(c[102]/2(a[88],V0),c[91,124,93]/2(c[61]/2(a[95,89],V0),nil)))",
    "t_rc47 c[116,95,114,99,52,55]/1(c[102]/3(a[88],V0,V1))",
    "t_rc48 c[116,95,114,99,52,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[118,97,114,95,112,114,101,102,105,120],a[98,97,100])))",
    "t_rc49 c[116,95,114,99,52,57]/1(c[45]/2(c[102]/3(a[88],V0,a[95,90]),c[91,124,93]/2(c[61]/2(a[63,89],V0),nil)))",
    "t_rc50 c[116,95,114,99,53,48]/1(c[102]/2(a[88],V0))",
    "t_rc60 c[116,95,114,99,54,48]/1(c[45]/2(c[102]/2(V0,V0),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,99]),nil)))",
    "t_rc61 c[116,95,114,99,54,49]/1(c[45]/2(c[102]/2(V0,V0),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,99]),nil)))",
    "t_rc62 c[116,95,114,99,54,50]/1(c[102]/2(V0,V0))",
    "t_rc63 c[116,95,114,99,54,51]/1(c[45]/2(c[45]/2(c[102]/2(V0,V0),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[47,42,32,99,32,42,47]),nil)),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i8,i1,i8,i8)))",
    "t_rc64 c[116,95,114,99,54,52]/1(c[102]/2(V0,V0))",
    "t_rc65 c[116,95,114,99,54,53]/1(c[45]/2(c[102]/2(V0,V0),nil))",
    "t_rc66 c[116,95,114,99,54,54]/1(c[45]/2(a[101,110,100,95,111,102,95,102,105,108,101],c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,111,110,108,121]),nil)))",
    "t_rc67 c[116,95,114,99,54,55]/1(c[45]/2(c[102]/1(V0),c[91,124,93]/2(c[45]/2(a[45],s[37,32,99]),nil)))",
    "t_rc68 c[116,95,114,99,54,56]/1(c[102]/2(V0,V0))",
    "t_rh01 c[116,95,114,104,48,49]/1(c[45]/2(c[102]/2(V0,V0),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,99]),nil),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i4,i2,i0,i4)),c[102]/2(V1,V1)),nil),nil)))",
    "t_rh02 c[116,95,114,104,48,50]/1(c[45]/2(c[45]/2(c[102]/3(V0,V1,V0),c[91,124,93]/2(c[61]/2(a[88],V0),c[91,124,93]/2(c[61]/2(a[89],V1),nil))),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,99]),nil),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i4,i2,i0,i4)),c[102]/3(V2,V3,V2)),c[91,124,93]/2(c[61]/2(a[88],V2),c[91,124,93]/2(c[61]/2(a[89],V3),nil))),nil)))",
    "t_rh03 c[116,95,114,104,48,51]/1(c[45]/2(c[102]/2(V0,V0),nil))",
    "t_rh04 c[116,95,114,104,48,52]/1(c[45]/2(c[102]/2(V0,V0),nil))",
    "t_rh05 c[116,95,114,104,48,53]/1(c[45]/2(c[45]/2(c[102]/2(V0,V0),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,99]),nil)),nil))",
    "t_rh06 c[116,95,114,104,48,54]/1(c[45]/2(c[45]/2(c[102]/2(V0,V0),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i4,i2,i0,i4)),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,99]),nil),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i4,i2,i0,i4)),c[102]/2(V1,V1)),nil),nil)))",
    "t_rh07 c[116,95,114,104,48,55]/1(c[114,97,105,115,101,100]/1(a[114,116,95,98,111,111,109]))",
    "t_rh08 c[116,95,114,104,48,56]/1(c[45]/2(c[102]/2(V0,V0),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[47,42,32,97,32,42,47]),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i8,i1,i8,i0),s[37,32,98]),nil)),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i12,i2,i0,i12)),c[102]/2(V1,V1)),nil),nil)))",
    "t_rh10 c[116,95,114,104,49,48]/1(c[45]/2(c[45]/2(c[102]/2(V0,V0),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,99]),nil)),nil))",
    "t_rh11 c[116,95,114,104,49,49]/1(c[45]/2(c[45]/2(c[102]/2(V0,V0),a[101,110,100,95,111,102,95,102,105,108,101]),c[91,124,93]/2(c[45]/2(c[45]/2(c[45]/2(c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,99]),nil),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i4,i2,i0,i4)),c[102]/2(V1,V1)),nil),nil)))"
]

"The program and cases as one file (in `dir`); the case predicates' names."
function _rc_file(dir::String)::Tuple{String, Vector{String}}
    ids = [id for (id, _) in _RC_CASES]
    goals = [g for (_, g) in _RC_CASES]
    names = ["t_$(id)" for id in ids]
    text =
        replace(_RC_PROGRAM, "@RTDIR@" => dir) * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in zip(ids, goals)
        ])
    f = joinpath(dir, "rd1.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's. A Julia exception out of a row is its line: `jlerr <type> <what>`."
function _rc_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_RC}()
    ld = LK.PL_local_data{_RC}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _rc_enc(ball::_RC)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_rcs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        rld = LK.PL_local_data{_RC}(gd)        # a fresh engine per row: a Julia exception leaves no frame behind
        try
            fid = LK.PL_open_foreign_frame(rld)
            a = LK.PL_new_term_refs(rld, 1)
            LK.putSlotValue!(rld, a + 1, mk_var(_RC, LK.fresh_var_keys!(1)), LK.PutVarMap())
            qid = LK.PL_open_query(
                gd, rld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
            )
            n = 0
            while (n += 1) <= 50
                rc = LK.PL_next_solution(gd, rld, qid)
                if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                    push!(
                        sols,
                        _rc_enc(
                            mk_expr(_RC, _RC[_rcs(name), lk_answers(rld, (a:a)...)...])
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


@testset "comments(C), eof_action(error), var_prefix, prolog:comment_hook/4 as swipl's (rc01-rh11)" begin
    mktempdir() do dir
        f, names = _rc_file(dir)
        kl = _rc_kernel(f, names)
        @test length(kl) == length(_RC_PINNED)
        for (k, p) in zip(kl, _RC_PINNED)
            k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
            @test k == p
        end
    end
    # not vacuous: the pins hold collected comments with and without a position, the hook's records, the errors and the failures
    sp = "c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4("    # '$stream_position'/4
    @test count(l -> occursin(sp, l), _RC_PINNED) >= 25
    @test count(l -> occursin("c[45]/2(a[45],s[", l), _RC_PINNED) >= 3             # the `-`-Str of a stream without positions
    @test count(l -> occursin("past_end_of_stream", l), _RC_PINNED) >= 5
    @test count(l -> occursin("var_prefix", l) || occursin("c[100,111,109,97,105,110", l), _RC_PINNED) >= 2
    @test count(l -> startswith(l, "t_rh") && occursin(sp, l), _RC_PINNED) >= 6    # the hook saw the position
    @test count(l -> !occursin(' ', l), _RC_PINNED[2:end]) >= 2                    # the rows that fail
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_RC_PINNED) == length(_RC_CASES) + 1
    if swipl === nothing
        @info "RD2 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        mktempdir() do dir
            f, names = _rc_file(dir)
            @test _rc_swipl_lines(f, names) == _RC_PINNED
        end
    end
end
