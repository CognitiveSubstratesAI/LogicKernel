# ORIGINAL: a LIVE differential of Q10's built-ins (`\=@=/2`, `shell/2`, `current_blob/2`, `$put_token/2`, `$on_signal/4`,
# `$set_prolog_stack/4`, `trim_heap/0`, `trim_stacks/0`, `thread_idle/2`) against swipl at the pin — Q10's rows
# test/core_lang/test_q10_swipl.jl — vr01-cb22 (and sh21, ti14, ti15, pt26) against swipl 10.1.20 (the pin 18168e62):
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_style_check_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (the pin's swipl, ~/.local/swipl-pin1-18168e62/bin/swipl, two identical runs, 2026-11-11); with
#     `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.

using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through PL_unify_integer and PL_get_integer only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _QX = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_qxs(x) = lk_sym(_QX, Symbol(x))


_qx_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _qx_enc(t::_QX, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _qx_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _qx_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _qx_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_qx_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _QX_DRIVER = raw"""
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
function _qx_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _QX_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end




# the program the rows run against
const _QX_PROGRAM = raw"""
q_a(1).
q_handler(_).
q_get(S, R) :- '$on_signal'(S, _, user:R, user:R).
q_set(S, New, Old) :- '$on_signal'(S, _, user:Old, user:New).
q_sig(S, N, R) :-
    '$on_signal'(S, N, user:O, user:O),
    ( O = '$foreign_function'(P), integer(P) -> R = foreign ; R = O ).
q_sigs(S, Max, []) :- S > Max, !.
q_sigs(S, Max, [S-R|T]) :- q_sig(S, _, R), S1 is S+1, q_sigs(S1, Max, T).
q_lim0(1073741824).
q_restore :- q_lim0(L), set_prolog_flag(stack_limit, L).
q_with(G) :- setup_call_cleanup(true, G, q_restore).
q_cur(X) :- current_prolog_flag(stack_limit, X).
q_dive(N) :- N1 is N+1, nb_setval(q_d, N1), q_dive(N1), true.
q_depth(D) :- nb_setval(q_d, 0), catch(q_dive(0), error(resource_error(_), _), true), nb_getval(q_d, D).
q_rel(A, B, R) :- ( A < B -> R = less ; A =:= B -> R = equal ; R = more ).
q_deep(0) :- !.
q_deep(N) :- N1 is N-1, q_deep(N1), true.
q_deepset(0) :- !, set_prolog_flag(stack_limit, 100000).
q_deepset(N) :- N1 is N-1, q_deepset(N1), true.
"""

const _QX_CASES = [
    ("vr01", "( a \\=@= a -> R = yes ; R = no )"),   # equal atoms
    ("vr02", "( a \\=@= b -> R = yes ; R = no )"),   # different atoms
    ("vr03", "( f(A,B) \\=@= f(C,D) -> R = yes ; R = no )"),   # renamed variables
    ("vr04", "( f(A,A) \\=@= f(C,D) -> R = yes ; R = no )"),   # sharing differs
    ("vr05", "( f(A,B) \\=@= f(B,A) -> R = yes ; R = no )"),   # swapped variables
    ("vr06", "( f(A,A) \\=@= f(B,A) -> R = yes ; R = no )"),   # inconsistent renaming
    ("vr07", "( X \\=@= Y -> R = yes ; R = no )"),   # two fresh variables
    ("vr08", "( X \\=@= a -> R = yes ; R = no )"),   # variable and atom
    ("vr09", "( 1 \\=@= 1.0 -> R = yes ; R = no )"),   # swipl identity: 1 and 1.0 differ
    ("vr10", "( \"a\" \\=@= a -> R = yes ; R = no )"),   # string and atom
    ("vr11", "( [A,B|T] \\=@= [C,D|U] -> R = yes ; R = no )"),   # partial lists
    ("vr12", "X = 1, ( f(X) \\=@= f(1) -> R = yes ; R = no )"),   # under the bindings
    ("vr13", "A = f(A), B = f(B), ( A \\=@= B -> R = yes ; R = no )"),   # rational trees
    ("vr14", "put_attr(X, q10_dom, 1), ( X \\=@= Y -> R = yes ; R = no )"),   # an attributed variable
    ("vr15", "( a(A,B,A) \\=@= a(X,Y,Y) -> R = yes ; R = no )"),   # first and third against second and third
    ("vr16", "( call(\\=@=, f(A), f(B)) -> R = yes ; R = no )"),   # called with call/3
    ("vr17", "X is 2**70, Y is 2**70, ( X \\=@= Y -> R = yes ; R = no )"),   # equal big integers
    ("vr18", "( f(A) \\=@= g(A) -> R = yes ; R = no )"),   # different functors
    ("vr19", "( f(A) \\=@= f(A,B) -> R = yes ; R = no )"),   # different arities
    ("vr20", "( f(A,g(B,A)) \\=@= f(C,g(D,C)) -> R = yes ; R = no )"),   # nested sharing
    ("sh01", "shell(true, R)"),   # status 0
    ("sh02", "shell('exit 3', R)"),   # status 3
    ("sh03", "shell(\"exit 4\", R)"),   # a string
    ("sh04", "atom_codes('exit 6', Cs), shell(Cs, R)"),   # a code list
    ("sh05", "shell(_, R)"),   # unbound command
    ("sh06", "shell(f(x), R)"),   # a compound command
    ("sh07", "( shell(true, 1) -> R = yes ; R = no )"),   # the status does not unify
    ("sh08", "( shell(true, 0) -> R = yes ; R = no )"),   # the status unifies
    ("sh09", "shell('exit 300', R)"),   # status modulo 256
    ("sh10", "shell('test \"\$PROLOGCHILD\" = yes', R)"),   # the child has PROLOGCHILD=yes
    ("sh11", "shell('kill -9 \$\$', R)"),   # the shell is killed by a signal
    ("sh12", "shell(false, R)"),   # status 1
    ("sh13", "shell('q10_no_such_command 2>/dev/null', R)"),   # command not found: 127
    ("sh14", "setenv(q10_var, hello), shell('test \"\$q10_var\" = hello', R)"),   # the environment set by setenv/2
    ("sh15", "shell('exit 256', R)"),   # 256 wraps to 0
    ("sh16", "shell('', R)"),   # the empty command
    ("sh17", "shell('exit 2', 2), R = ok"),   # the status given
    ("sh18", "shell('exit 7 # \\u00e9', R)"),   # a non-ASCII character in a comment
    ("sh19", "shell(42, R)"),   # a number as the command: the shell cannot find 42
    ("sh20", "shell('exit 5', R), integer(R)"),   # an integer status
    (
        "sh21",
        "current_prolog_flag(posix_shell, O), setup_call_cleanup(set_prolog_flag(posix_shell, '/bin/true'), shell('exit 3', R), set_prolog_flag(posix_shell, O))"
    ),   # the shell is the flag posix_shell: /bin/true ignores the command and answers 0, /bin/sh would answer 3
    ("ti01", "thread_idle(true, short), R = ok"),   # short
    ("ti02", "thread_idle(true, long), R = ok"),   # long
    ("ti03", "thread_idle(true, other), R = ok"),   # an atom that is neither
    ("ti04", "thread_idle(true, 1), R = ok"),   # a non-atom How
    ("ti05", "thread_idle(true, _), R = ok"),   # an unbound How
    ("ti06", "( thread_idle(fail, short) -> R = yes ; R = no )"),   # a failing goal
    ("ti07", "thread_idle(throw(error(q10_err, _)), short)"),   # a throwing goal
    ("ti08", "thread_idle(X = 1, short), R = X"),   # the goal's bindings stay
    ("ti09", "thread_idle(q_a(X), long), R = X"),   # a program predicate
    ("ti10", "thread_idle(user:q_a(X), long), R = X"),   # a module-qualified goal
    ("ti11", "thread_idle(_, short)"),   # an unbound goal
    ("ti12", "thread_idle(true, short(a))"),   # a compound How
    ("ti13", "thread_idle(q_a(2), short) -> R = yes ; R = no"),   # a goal that fails after a successful How
    (
        "ti14",
        "assertz(q10_m:q10_only(7)), q10_m:thread_idle(q10_only(X), short), R = X"
    ),   # transparent: the goal runs in the context module q10_m, where q10_only/1 is defined
    ("ti15", "thread_idle(q10_only(X), short), R = X"),   # and in user it is not: existence_error
    ("th01", "trim_heap, R = ok"),   # trim_heap succeeds
    ("th02", "trim_stacks, R = ok"),   # trim_stacks succeeds
    ("th03", "trim_stacks, trim_heap, trim_stacks, R = ok"),   # repeated
    ("ss01", "'\$set_prolog_stack'(local, low, O, O), R = O"),   # local low
    ("ss02", "'\$set_prolog_stack'(local, factor, O, O), R = O"),   # local factor
    ("ss03", "'\$set_prolog_stack'(local, spare, O, O), R = O"),   # local spare
    ("ss04", "'\$set_prolog_stack'(local, min_free, O, O), R = O"),   # local min_free
    ("ss05", "'\$set_prolog_stack'(global, low, O, O), R = O"),   # global low
    ("ss06", "'\$set_prolog_stack'(global, factor, O, O), R = O"),   # global factor
    ("ss07", "'\$set_prolog_stack'(global, spare, O, O), R = O"),   # global spare
    ("ss08", "'\$set_prolog_stack'(global, min_free, O, O), R = O"),   # global min_free
    ("ss09", "'\$set_prolog_stack'(trail, low, O, O), R = O"),   # trail low
    ("ss10", "'\$set_prolog_stack'(trail, factor, O, O), R = O"),   # trail factor
    ("ss11", "'\$set_prolog_stack'(trail, spare, O, O), R = O"),   # trail spare
    ("ss12", "'\$set_prolog_stack'(trail, min_free, O, O), R = O"),   # trail min_free
    ("ss13", "'\$set_prolog_stack'(argument, low, O, O), R = O"),   # argument low
    ("ss14", "'\$set_prolog_stack'(argument, factor, O, O), R = O"),   # argument factor
    ("ss15", "'\$set_prolog_stack'(argument, spare, O, O), R = O"),   # argument spare
    ("ss16", "'\$set_prolog_stack'(argument, min_free, O, O), R = O"),   # argument min_free
    ("ss17", "'\$set_prolog_stack'(local, limit, O, O), R = O"),   # limit read (the deprecation warning goes to stderr)
    ("ss18", "'\$set_prolog_stack'(argument, limit, O, O), R = O"),   # limit read through another stack
    ("ss19", "'\$set_prolog_stack'(foo, low, O, O)"),   # an unknown stack
    ("ss20", "'\$set_prolog_stack'(1, low, O, O)"),   # a non-atom stack
    ("ss21", "'\$set_prolog_stack'(local, foo, O, O)"),   # an unknown property
    ("ss22", "'\$set_prolog_stack'(local, 1, O, O)"),   # a non-atom property
    (
        "ss23",
        "'\$set_prolog_stack'(global, low, O1, 40000), '\$set_prolog_stack'(global, low, O2, O2), R = O1-O2"
    ),   # low set and read back
    (
        "ss24",
        "'\$set_prolog_stack'(global, low, O1, 32768), '\$set_prolog_stack'(global, low, O2, O2), R = O1-O2"
    ),   # low restored
    (
        "ss25",
        "'\$set_prolog_stack'(trail, factor, O1, 4), '\$set_prolog_stack'(trail, factor, O2, O2), R = O1-O2"
    ),   # factor set and read back
    (
        "ss26",
        "'\$set_prolog_stack'(trail, factor, O1, 3), '\$set_prolog_stack'(trail, factor, O2, O2), R = O1-O2"
    ),   # factor restored
    (
        "ss27",
        "'\$set_prolog_stack'(trail, spare, O1, 300), '\$set_prolog_stack'(trail, spare, O2, O2), R = O1-O2"
    ),   # trail spare set and read back
    (
        "ss28",
        "'\$set_prolog_stack'(trail, spare, O1, 256), '\$set_prolog_stack'(trail, spare, O2, O2), R = O1-O2"
    ),   # trail spare restored
    (
        "ss29",
        "'\$set_prolog_stack'(global, spare, O1, 600), '\$set_prolog_stack'(global, spare, O2, O2), R = O1-O2"
    ),   # global spare set and read back
    (
        "ss30",
        "'\$set_prolog_stack'(global, spare, O1, 512), '\$set_prolog_stack'(global, spare, O2, O2), R = O1-O2"
    ),   # global spare restored
    (
        "ss31",
        "'\$set_prolog_stack'(argument, min_free, O1, 300), '\$set_prolog_stack'(argument, min_free, O2, O2), R = O1-O2"
    ),   # argument min_free set and read back
    (
        "ss32",
        "'\$set_prolog_stack'(argument, min_free, O1, 256), '\$set_prolog_stack'(argument, min_free, O2, O2), R = O1-O2"
    ),   # argument min_free restored
    ("ss33", "'\$set_prolog_stack'(global, low, O, -1)"),   # a negative size
    ("ss34", "'\$set_prolog_stack'(global, factor, O, a)"),   # a non-integer factor
    ("ss35", "'\$set_prolog_stack'(trail, spare, O, foo)"),   # a non-integer spare
    ("ss36", "( '\$set_prolog_stack'(global, factor, 99, 3) -> R = yes ; R = no )"),   # the old value does not unify
    ("ss37", "'\$set_prolog_stack'(local, limit, O, foo)"),   # a limit that is no size
    (
        "ss38",
        "'\$set_prolog_stack'(trail, min_free, O1, 300), '\$set_prolog_stack'(trail, min_free, O2, O2), '\$set_prolog_stack'(trail, min_free, _, O1), R = O1-O2"
    ),   # trail min_free set, read back, restored
    ("os01", "q_sigs(1, 64, L), R = L"),   # the state of signals 1..64 (a foreign handler reports as foreign)
    ("os02", "q_sig(0, _, R)"),   # signal 0
    ("os03", "q_sig(65, _, R)"),   # signal 65
    ("os04", "'\$on_signal'(40, N, user:O, user:O), R = N-O"),   # name and state of a free signal
    ("os05", "'\$on_signal'(S, hup, user:O, user:O), R = S"),   # hup by name
    ("os06", "'\$on_signal'(S, 'SIGHUP', user:O, user:O), R = S"),   # SIGHUP by name
    ("os07", "'\$on_signal'(S, 'prolog:gc', user:O, user:O), R = S"),   # a virtual signal by name
    ("os08", "'\$on_signal'(S, foo, user:O, user:O), R = S"),   # an unknown name
    ("os09", "'\$on_signal'(S, N, user:O, user:O), R = S"),   # no signal and no name
    ("os10", "'\$on_signal'(1.5, N, user:O, user:O), R = N"),   # a float signal
    ("os11", "( '\$on_signal'(15, foo, user:O, user:O) -> R = yes ; R = no )"),   # a name that is not the signal's
    ("os12", "'\$on_signal'(40, _, O, user:ignore)"),   # an old argument that is no M:T
    ("os13", "'\$on_signal'(40, _, user:O, foo)"),   # a new argument that is no M:T
    ("os14", "q_set(40, ignore, O1), q_get(40, O2), R = O1-O2"),   # default to ignore
    ("os15", "q_set(40, throw, O1), q_get(40, O2), R = O1-O2"),   # ignore to throw
    ("os16", "q_set(40, debug, O1), q_get(40, O2), R = O1-O2"),   # throw to debug
    ("os17", "q_set(40, q_handler, O1), q_get(40, O2), R = O1-O2"),   # debug to a predicate
    ("os18", "q_set(40, default, O1), q_get(40, O2), R = O1-O2"),   # a predicate back to default
    (
        "os19",
        "q_set(41, q_handler, O1), '\$on_signal'(41, _, lists:O2, lists:O2), R = O1-O2"
    ),   # a predicate read back in another module
    (
        "os20",
        "'\$on_signal'(41, _, user:O1, q10_mod:q_other), '\$on_signal'(41, _, user:O2, user:O2), R = O1-O2"
    ),   # a predicate of another module
    ("os21", "q_set(41, throw, O1), q_get(41, O2), q_set(41, default, O3), R = O1-O2-O3"),   # a predicate to throw to default
    ("os22", "q_set(42, default, O1), q_get(42, O2), R = O1-O2"),   # default to default: no change
    (
        "os23",
        "q_get(15, O), q_set(15, O, _), q_get(15, O2), ( O == O2 -> R = same ; R = diff )"
    ),   # a reported foreign handler restored
    ("os24", "q_set(42, '\$foreign_function'(a), _)"),   # a foreign function that is no pointer
    ("os25", "q_set(42, 3, _)"),   # a new state that is an integer
    ("os26", "q_set(42, f(x), _)"),   # a new state that is a compound
    ("os27", "q_set(42, ignore, _), q_set(42, ignore, O), q_set(42, default, _), R = O"),   # ignore twice, then default
    (
        "os28",
        "q_set(42, throw, _), q_set(42, ignore, O), q_get(42, O2), q_set(42, default, _), R = O-O2"
    ),   # throw to ignore
    ("os29", "'\$on_signal'(S, 'SIGTERM', user:O, user:O), R = S"),   # SIGTERM by name
    ("os30", "'\$on_signal'(S, 'SIGfoo', user:O, user:O), R = S"),   # an unknown SIG name
    ("pt01", "with_output_to(string(S), (current_output(O), '\$put_token'(O, ab))), R = S"),   # one atom
    (
        "pt02",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, ab), '\$put_token'(O, cd))), R = S"
    ),   # two alphanumeric tokens: a space between
    (
        "pt03",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, +), '\$put_token'(O, +))), R = S"
    ),   # two symbol-char tokens: a space between
    (
        "pt04",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, ab), '\$put_token'(O, '+'))), R = S"
    ),   # alphanumeric then symbol: none
    (
        "pt05",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, ''), '\$put_token'(O, ab))), R = S"
    ),   # the empty atom writes nothing
    (
        "pt06",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, \"abc\"))), R = S"
    ),   # a string
    ("pt07", "with_output_to(string(S), (current_output(O), '\$put_token'(O, _))), R = S"),   # an unbound token
    ("pt08", "with_output_to(string(S), (current_output(O), '\$put_token'(O, 42))), R = S"),   # an integer token
    (
        "pt09",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, '\\u00e9\\u20ac'))), R = S"
    ),   # a text that is not ISO Latin-1
    (
        "pt10",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, '\\u00e9'))), R = S"
    ),   # an ISO Latin-1 character above 127
    (
        "pt11",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, a), '\$put_token'(O, '\\u00e9'))), R = S"
    ),   # a letter, then a Latin-1 letter
    ("pt12", "'\$put_token'(_, ab)"),   # an unbound stream
    ("pt13", "'\$put_token'(q10_no_stream, ab)"),   # an atom that is no stream
    (
        "pt15",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, 1), '\$put_token'(O, 2))), R = S"
    ),   # two digit tokens
    (
        "pt16",
        "with_output_to(string(S), (current_output(O), put_char(O, x), '\$put_token'(O, y))), R = S"
    ),   # after a character put by put_char/2
    (
        "pt17",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, a), nl(O), '\$put_token'(O, b))), R = S"
    ),   # after a newline
    ("pt18", "with_output_to(string(S), (current_output(O), '\$put_token'(O, []))), R = S"),   # the empty list
    (
        "pt19",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, [0'a]))), R = S"
    ),   # a code list
    (
        "pt20",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, 'a b'), '\$put_token'(O, c))), R = S"
    ),   # only the first and last character of the text matter
    (
        "pt21",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, '\\''), '\$put_token'(O, '\\''))), R = S"
    ),   # two quote characters
    (
        "pt22",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, '('), '\$put_token'(O, a))), R = S"
    ),   # a punctuation token, then a letter
    (
        "pt23",
        "with_output_to(string(S), (current_output(O), '\$put_token'(O, abc))), '\$put_token'(user_error, ''), R = S"
    ),   # the stream alias user_error with an empty text
    ("pt24", "'\$put_token'(1, ab)"),   # an integer is no stream and no alias: domain_error(stream_or_alias, 1), not stream
    ("pt25", "'\$put_token'(f(x), ab)"),   # a compound is no stream either (the same domain: stream_or_alias)
    (
        "pt26",
        "open('/dev/null', write, S, [encoding(ascii)]), catch('\$put_token'(S, '\\u00e9'), error(io_error(W, S2), _), ( S2 == S -> R = io_error(W) ; R = other )), close(S)"
    ),   # the token writes into the buffer, the stream carries an encoding error: the status after the write is raised (streamStatus)
    ("cb01", "current_blob(foo, T), R = T"),   # a text atom: its type
    ("cb02", "current_blob([], T), R = T"),   # the empty list: reserved_symbol
    ("cb03", "( current_blob(\"s\", T) -> R = T ; R = no )"),   # a string is no blob
    ("cb04", "( current_blob(f(x), T) -> R = T ; R = no )"),   # a compound is no blob
    ("cb05", "( current_blob(1, T) -> R = T ; R = no )"),   # a number is no blob
    ("cb06", "( current_blob(foo, text) -> R = yes ; R = no )"),   # an atom and its type
    ("cb07", "( current_blob(foo, stream) -> R = yes ; R = no )"),   # an atom and another type
    ("cb08", "( current_blob(foo, 1) -> R = yes ; R = no )"),   # an atom and a type that is no atom
    ("cb09", "current_blob(_, 1)"),   # a variable blob and a type that is no atom
    ("cb10", "current_blob(_, \"text\")"),   # a variable blob and a string type
    (
        "cb11",
        "open_null_stream(S), ( current_blob(S2, stream), S2 == S -> R = yes ; R = no ), close(S)"
    ),   # a stream is enumerated as a stream blob
    (
        "cb12",
        "findall(X, current_blob(X, reserved_symbol), L), ( memberchk([], L) -> R = yes ; R = no )"
    ),   # the reserved symbols include []
    (
        "cb13",
        "findall(T, current_blob(_, T), Ts), sort(Ts, S), ( memberchk(text, S), memberchk(reserved_symbol, S) -> R = ok ; R = missing )"
    ),   # the types enumerated include text and reserved_symbol
    (
        "cb14",
        "atom_codes(A, \"q10_cb_atom_zz\"), ( current_blob(B, text), B == A -> R = yes ; R = no )"
    ),   # a new text atom is enumerated
    ("cb15", "( current_blob(X, q10_no_such_type) -> R = X ; R = no )"),   # a type no atom has
    ("cb16", "( current_blob(X, text), ! ), atom(X), R = ok"),   # cut after the first solution
    ("cb17", "( current_blob(X, T), X == [] -> R = T ; R = none )"),   # the type found from the atom
    ("cb18", "atom_codes(A, [0'q, 0x20ac]), current_blob(A, T), R = T"),   # a text atom with a wide character: ucs_text
    (
        "cb19",
        "atom_codes(A, [0'q, 0x20ac, 0'z]), ( current_blob(B, ucs_text), B == A -> R = yes ; R = no )"
    ),   # a wide atom is enumerated by its type
    ("cb20", "( current_blob(_, []) -> R = yes ; R = no )"),    # the empty list as the type
    ("cb21", "( current_blob(\"s\", 1) -> R = yes ; R = no )"),   # a string that is no blob, with a type that is no atom: fails, no type_error
    ("cb22", "( current_blob(f(x), 1) -> R = yes ; R = no )"),   # a compound that is no blob, the same
    (
        "th04",
        "q_deep(60000), statistics(local, A), trim_stacks, statistics(local, B), q_rel(A, B, R)"
    ),   # trim_stacks gives the local stack back after a deep recursion: statistics(local) falls (Q10-33; the kernel's local stack size is swipl's byte for byte, 8376184 and 20344, 118648 and 20344 for 1000)
    ("sl01", "q_with((set_prolog_flag(stack_limit, 4194304), q_cur(X))), R = X"),   # set_prolog_flag(stack_limit, N) sets the limit (set_stack_limit); the flag reads it back
    ("sl02", "q_with((set_prolog_flag(stack_limit, 2147483648), q_cur(X))), R = X"),   # a limit above the default
    ("sl03", "q_with(set_prolog_flag(stack_limit, 1000))"),   # a limit below what the stacks hold: permission_error(limit, stacks, Limit) after the trim
    ("sl04", "catch(set_prolog_flag(stack_limit, 1000), _, true), q_cur(X), R = X"),   # and the flag is unchanged after it
    ("sl05", "q_with(set_prolog_flag(stack_limit, 0))"),   # a limit of 0
    ("sl06", "q_with(set_prolog_flag(stack_limit, -1))"),   # a negative limit: representation_error(size_t)
    ("sl07", "q_with(set_prolog_flag(stack_limit, a))"),   # a limit that is no integer
    ("sl08", "q_with(set_prolog_flag(stack_limit, 1.5))"),   # a float limit
    ("sl09", "q_with(set_prolog_flag(stack_limit, _))"),   # an unbound limit
    ("sl10", "q_with(set_prolog_flag(stack_limit, 100000000000000000000))"),   # a limit beyond int64: representation_error(int64_t)
    (
        "sl11",
        "q_with(('\$set_prolog_stack'(global, limit, O, 8388608), q_cur(X))), R = O-X"
    ),   # '$set_prolog_stack'(Stack, limit, Old, New) sets the one combined limit whichever stack is named; Old is the limit before
    ("sl12", "q_with('\$set_prolog_stack'(local, limit, _, 100))"),   # the same below what the stacks hold: permission_error
    (
        "sl13",
        "( '\$set_prolog_stack'(trail, limit, 5, 8388608) -> R0 = yes ; R0 = no ), q_cur(X), R = R0-X"
    ),   # an Old that does not unify fails and leaves the limit as it was
    ("sl14", "q_cur(X), set_prolog_flag(stack_limit, X), q_cur(Y), R = X-Y"),   # the current limit set again
    (
        "sl15",
        "q_with((push_prolog_flag(stack_limit, 4194304), q_cur(X), pop_prolog_flag(stack_limit), q_cur(Y))), R = X-Y"
    ),   # push_prolog_flag and pop_prolog_flag set and restore it
    (
        "sl16",
        "q_with((set_prolog_flag(stack_limit, 1048576), catch(q_dive(0), error(resource_error(K), _), true))), R = K"
    ),   # under the 1 MiB limit a runaway recursion ends in resource_error(stack)
    (
        "sl17",
        "q_with((q_deep(60000), set_prolog_flag(stack_limit, 1048576), q_cur(X))), R = X"
    ),   # a deep recursion that returned, then a limit below the size the stacks grew to: set_stack_limit trims them first, so it is accepted
    ("sl18", "q_with(q_deepset(20000))"),   # a limit below what the stacks hold while they are deep: refused, the trim cannot help
    (
        "sl20",
        "q_with((set_prolog_flag(stack_limit, 1048576), q_depth(D1), set_prolog_flag(stack_limit, 2097152), q_depth(D2))), q_rel(D1, D2, R)"
    ),   # the depth reached before the overflow follows the limit: 1 MiB less than 2 MiB
    ("sl19", "q_with((set_prolog_flag(stack_limit, 2000001), q_cur(X))), R = X")   # KNOWN DIFFERENCE (below)
]

# the driver's whole output, one line per case after `ok`, from swipl at the pin
const _QX_PINNED = [
    "ok",
    "t_vr01 c[116,95,118,114,48,49]/1(a[110,111])",
    "t_vr02 c[116,95,118,114,48,50]/1(a[121,101,115])",
    "t_vr03 c[116,95,118,114,48,51]/1(a[110,111])",
    "t_vr04 c[116,95,118,114,48,52]/1(a[121,101,115])",
    "t_vr05 c[116,95,118,114,48,53]/1(a[110,111])",
    "t_vr06 c[116,95,118,114,48,54]/1(a[121,101,115])",
    "t_vr07 c[116,95,118,114,48,55]/1(a[110,111])",
    "t_vr08 c[116,95,118,114,48,56]/1(a[121,101,115])",
    "t_vr09 c[116,95,118,114,48,57]/1(a[121,101,115])",
    "t_vr10 c[116,95,118,114,49,48]/1(a[121,101,115])",
    "t_vr11 c[116,95,118,114,49,49]/1(a[110,111])",
    "t_vr12 c[116,95,118,114,49,50]/1(a[110,111])",
    "t_vr13 c[116,95,118,114,49,51]/1(a[110,111])",
    "t_vr14 c[116,95,118,114,49,52]/1(a[121,101,115])",
    "t_vr15 c[116,95,118,114,49,53]/1(a[121,101,115])",
    "t_vr16 c[116,95,118,114,49,54]/1(a[110,111])",
    "t_vr17 c[116,95,118,114,49,55]/1(a[110,111])",
    "t_vr18 c[116,95,118,114,49,56]/1(a[121,101,115])",
    "t_vr19 c[116,95,118,114,49,57]/1(a[121,101,115])",
    "t_vr20 c[116,95,118,114,50,48]/1(a[110,111])",
    "t_sh01 c[116,95,115,104,48,49]/1(i0)",
    "t_sh02 c[116,95,115,104,48,50]/1(i3)",
    "t_sh03 c[116,95,115,104,48,51]/1(i4)",
    "t_sh04 c[116,95,115,104,48,52]/1(i6)",
    "t_sh05 c[116,95,115,104,48,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sh06 c[116,95,115,104,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120]))))",
    "t_sh07 c[116,95,115,104,48,55]/1(a[110,111])",
    "t_sh08 c[116,95,115,104,48,56]/1(a[121,101,115])",
    "t_sh09 c[116,95,115,104,48,57]/1(i44)",
    "t_sh10 c[116,95,115,104,49,48]/1(i0)",
    "t_sh11 c[116,95,115,104,49,49]/1(c[114,97,105,115,101,100]/1(c[115,104,101,108,108]/2(c[115,105,103,110,97,108]/1(i9),a[107,105,108,108,32,45,57,32,36,36])))",
    "t_sh12 c[116,95,115,104,49,50]/1(i1)",
    "t_sh13 c[116,95,115,104,49,51]/1(i127)",
    "t_sh14 c[116,95,115,104,49,52]/1(i0)",
    "t_sh15 c[116,95,115,104,49,53]/1(i0)",
    "t_sh16 c[116,95,115,104,49,54]/1(i0)",
    "t_sh17 c[116,95,115,104,49,55]/1(a[111,107])",
    "t_sh18 c[116,95,115,104,49,56]/1(i7)",
    "t_sh19 c[116,95,115,104,49,57]/1(i127)",
    "t_sh20 c[116,95,115,104,50,48]/1(i5)",
    "t_sh21 c[116,95,115,104,50,49]/1(i0)",
    "t_ti01 c[116,95,116,105,48,49]/1(a[111,107])",
    "t_ti02 c[116,95,116,105,48,50]/1(a[111,107])",
    "t_ti03 c[116,95,116,105,48,51]/1(a[111,107])",
    "t_ti04 c[116,95,116,105,48,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_ti05 c[116,95,116,105,48,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ti06 c[116,95,116,105,48,54]/1(a[110,111])",
    "t_ti07 c[116,95,116,105,48,55]/1(c[114,97,105,115,101,100]/1(a[113,49,48,95,101,114,114]))",
    "t_ti08 c[116,95,116,105,48,56]/1(i1)",
    "t_ti09 c[116,95,116,105,48,57]/1(i1)",
    "t_ti10 c[116,95,116,105,49,48]/1(i1)",
    "t_ti11 c[116,95,116,105,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_ti12 c[116,95,116,105,49,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[115,104,111,114,116]/1(a[97]))))",
    "t_ti13 c[116,95,116,105,49,51]/1(a[110,111])",
    "t_ti14 c[116,95,116,105,49,52]/1(i7)",
    "t_ti15 c[116,95,116,105,49,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[113,49,48,95,111,110,108,121],i1))))",
    "t_th01 c[116,95,116,104,48,49]/1(a[111,107])",
    "t_th02 c[116,95,116,104,48,50]/1(a[111,107])",
    "t_th03 c[116,95,116,104,48,51]/1(a[111,107])",
    "t_ss01 c[116,95,115,115,48,49]/1(i0)",
    "t_ss02 c[116,95,115,115,48,50]/1(i0)",
    "t_ss03 c[116,95,115,115,48,51]/1(i1553)",
    "t_ss04 c[116,95,115,115,48,52]/1(i1041)",
    "t_ss05 c[116,95,115,115,48,53]/1(i32768)",
    "t_ss06 c[116,95,115,115,48,54]/1(i3)",
    "t_ss07 c[116,95,115,115,48,55]/1(i512)",
    "t_ss08 c[116,95,115,115,48,56]/1(i256)",
    "t_ss09 c[116,95,115,115,48,57]/1(i32768)",
    "t_ss10 c[116,95,115,115,49,48]/1(i3)",
    "t_ss11 c[116,95,115,115,49,49]/1(i256)",
    "t_ss12 c[116,95,115,115,49,50]/1(i256)",
    "t_ss13 c[116,95,115,115,49,51]/1(i0)",
    "t_ss14 c[116,95,115,115,49,52]/1(i0)",
    "t_ss15 c[116,95,115,115,49,53]/1(i0)",
    "t_ss16 c[116,95,115,115,49,54]/1(i256)",
    "t_ss17 c[116,95,115,115,49,55]/1(i1073741824)",
    "t_ss18 c[116,95,115,115,49,56]/1(i1073741824)",
    "t_ss19 c[116,95,115,115,49,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,97,99,107],a[102,111,111])))",
    "t_ss20 c[116,95,115,115,50,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,97,99,107],i1)))",
    "t_ss21 c[116,95,115,115,50,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,97,99,107,95,112,97,114,97,109,101,116,101,114],a[102,111,111])))",
    "t_ss22 c[116,95,115,115,50,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_ss23 c[116,95,115,115,50,51]/1(c[45]/2(i32768,i40000))",
    "t_ss24 c[116,95,115,115,50,52]/1(c[45]/2(i40000,i32768))",
    "t_ss25 c[116,95,115,115,50,53]/1(c[45]/2(i3,i4))",
    "t_ss26 c[116,95,115,115,50,54]/1(c[45]/2(i4,i3))",
    "t_ss27 c[116,95,115,115,50,55]/1(c[45]/2(i256,i300))",
    "t_ss28 c[116,95,115,115,50,56]/1(c[45]/2(i300,i256))",
    "t_ss29 c[116,95,115,115,50,57]/1(c[45]/2(i512,i600))",
    "t_ss30 c[116,95,115,115,51,48]/1(c[45]/2(i600,i512))",
    "t_ss31 c[116,95,115,115,51,49]/1(c[45]/2(i256,i300))",
    "t_ss32 c[116,95,115,115,51,50]/1(c[45]/2(i300,i256))",
    "t_ss33 c[116,95,115,115,51,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_ss34 c[116,95,115,115,51,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_ss35 c[116,95,115,115,51,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111])))",
    "t_ss36 c[116,95,115,115,51,54]/1(a[110,111])",
    "t_ss37 c[116,95,115,115,51,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111])))",
    "t_ss38 c[116,95,115,115,51,56]/1(c[45]/2(i256,i300))",
    "t_os01 c[116,95,111,115,48,49]/1(c[91,124,93]/2(c[45]/2(i1,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i2,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i3,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i4,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i5,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i6,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i7,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i8,a[116,104,114,111,119]),c[91,124,93]/2(c[45]/2(i9,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i10,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i11,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i12,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i13,a[105,103,110,111,114,101]),c[91,124,93]/2(c[45]/2(i14,a[116,104,114,111,119]),c[91,124,93]/2(c[45]/2(i15,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i16,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i17,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i18,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i19,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i20,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i21,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i22,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i23,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i24,a[116,104,114,111,119]),c[91,124,93]/2(c[45]/2(i25,a[116,104,114,111,119]),c[91,124,93]/2(c[45]/2(i26,a[116,104,114,111,119]),c[91,124,93]/2(c[45]/2(i27,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i28,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i29,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i30,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i31,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i32,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i33,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i34,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i35,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i36,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i37,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i38,a[102,111,114,101,105,103,110]),c[91,124,93]/2(c[45]/2(i39,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i40,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i41,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i42,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i43,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i44,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i45,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i46,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i47,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i48,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i49,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i50,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i51,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i52,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i53,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i54,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i55,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i56,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i57,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i58,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i59,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i60,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i61,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i62,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i63,a[100,101,102,97,117,108,116]),c[91,124,93]/2(c[45]/2(i64,a[100,101,102,97,117,108,116]),nil)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))",
    "t_os02 c[116,95,111,115,48,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],i0)))",
    "t_os03 c[116,95,111,115,48,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],i65)))",
    "t_os04 c[116,95,111,115,48,52]/1(c[45]/2(a[117,110,107,110,111,119,110],a[100,101,102,97,117,108,116]))",
    "t_os05 c[116,95,111,115,48,53]/1(i1)",
    "t_os06 c[116,95,111,115,48,54]/1(i1)",
    "t_os07 c[116,95,111,115,48,55]/1(i33)",
    "t_os08 c[116,95,111,115,48,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],a[102,111,111])))",
    "t_os09 c[116,95,111,115,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_os10 c[116,95,111,115,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],f1.5)))",
    "t_os11 c[116,95,111,115,49,49]/1(a[110,111])",
    "t_os12 c[116,95,111,115,49,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_os13 c[116,95,111,115,49,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[109,101,116,97,95,97,114,103,117,109,101,110,116],a[102,111,111])))",
    "t_os14 c[116,95,111,115,49,52]/1(c[45]/2(a[100,101,102,97,117,108,116],a[105,103,110,111,114,101]))",
    "t_os15 c[116,95,111,115,49,53]/1(c[45]/2(a[105,103,110,111,114,101],a[116,104,114,111,119]))",
    "t_os16 c[116,95,111,115,49,54]/1(c[45]/2(a[116,104,114,111,119],a[100,101,98,117,103]))",
    "t_os17 c[116,95,111,115,49,55]/1(c[45]/2(a[100,101,98,117,103],a[113,95,104,97,110,100,108,101,114]))",
    "t_os18 c[116,95,111,115,49,56]/1(c[45]/2(a[113,95,104,97,110,100,108,101,114],a[100,101,102,97,117,108,116]))",
    "t_os19 c[116,95,111,115,49,57]/1(c[45]/2(a[100,101,102,97,117,108,116],c[58]/2(a[117,115,101,114],a[113,95,104,97,110,100,108,101,114])))",
    "t_os20 c[116,95,111,115,50,48]/1(c[45]/2(a[113,95,104,97,110,100,108,101,114],c[58]/2(a[113,49,48,95,109,111,100],a[113,95,111,116,104,101,114])))",
    "t_os21 c[116,95,111,115,50,49]/1(c[45]/2(c[45]/2(c[58]/2(a[113,49,48,95,109,111,100],a[113,95,111,116,104,101,114]),a[116,104,114,111,119]),a[116,104,114,111,119]))",
    "t_os22 c[116,95,111,115,50,50]/1(c[45]/2(a[100,101,102,97,117,108,116],a[100,101,102,97,117,108,116]))",
    "t_os23 c[116,95,111,115,50,51]/1(a[115,97,109,101])",
    "t_os24 c[116,95,111,115,50,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108,95,104,97,110,100,108,101,114],c[36,102,111,114,101,105,103,110,95,102,117,110,99,116,105,111,110]/1(a[97]))))",
    "t_os25 c[116,95,111,115,50,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,105,103,110,97,108,95,104,97,110,100,108,101,114],i3)))",
    "t_os26 c[116,95,111,115,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,105,103,110,97,108,95,104,97,110,100,108,101,114],c[102]/1(a[120]))))",
    "t_os27 c[116,95,111,115,50,55]/1(a[105,103,110,111,114,101])",
    "t_os28 c[116,95,111,115,50,56]/1(c[45]/2(a[116,104,114,111,119],a[105,103,110,111,114,101]))",
    "t_os29 c[116,95,111,115,50,57]/1(i15)",
    "t_os30 c[116,95,111,115,51,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],a[83,73,71,102,111,111])))",
    "t_pt01 c[116,95,112,116,48,49]/1(s[97,98])",
    "t_pt02 c[116,95,112,116,48,50]/1(s[97,98,32,99,100])",
    "t_pt03 c[116,95,112,116,48,51]/1(s[43,32,43])",
    "t_pt04 c[116,95,112,116,48,52]/1(s[97,98,43])",
    "t_pt05 c[116,95,112,116,48,53]/1(s[97,98])",
    "t_pt06 c[116,95,112,116,48,54]/1(s[97,98,99])",
    "t_pt07 c[116,95,112,116,48,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_pt08 c[116,95,112,116,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],i42)))",
    "t_pt09 c[116,95,112,116,48,57]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[101,110,99,111,100,105,110,103])))",
    "t_pt10 c[116,95,112,116,49,48]/1(s[233])",
    "t_pt11 c[116,95,112,116,49,49]/1(s[97,32,233])",
    "t_pt12 c[116,95,112,116,49,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_pt13 c[116,95,112,116,49,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[113,49,48,95,110,111,95,115,116,114,101,97,109])))",
    "t_pt15 c[116,95,112,116,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],i1)))",
    "t_pt16 c[116,95,112,116,49,54]/1(s[120,32,121])",
    "t_pt17 c[116,95,112,116,49,55]/1(s[97,10,98])",
    "t_pt18 c[116,95,112,116,49,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],nil)))",
    "t_pt19 c[116,95,112,116,49,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[91,124,93]/2(i97,nil))))",
    "t_pt20 c[116,95,112,116,50,48]/1(s[97,32,98,32,99])",
    "t_pt21 c[116,95,112,116,50,49]/1(s[39,32,39])",
    "t_pt22 c[116,95,112,116,50,50]/1(s[40,97])",
    "t_pt23 c[116,95,112,116,50,51]/1(s[97,98,99])",
    "t_pt24 c[116,95,112,116,50,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,111,114,95,97,108,105,97,115],i1)))",
    "t_pt25 c[116,95,112,116,50,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,111,114,95,97,108,105,97,115],c[102]/1(a[120]))))",
    "t_pt26 c[116,95,112,116,50,54]/1(c[105,111,95,101,114,114,111,114]/1(a[119,114,105,116,101]))",
    "t_cb01 c[116,95,99,98,48,49]/1(a[116,101,120,116])",
    "t_cb02 c[116,95,99,98,48,50]/1(a[114,101,115,101,114,118,101,100,95,115,121,109,98,111,108])",
    "t_cb03 c[116,95,99,98,48,51]/1(a[110,111])",
    "t_cb04 c[116,95,99,98,48,52]/1(a[110,111])",
    "t_cb05 c[116,95,99,98,48,53]/1(a[110,111])",
    "t_cb06 c[116,95,99,98,48,54]/1(a[121,101,115])",
    "t_cb07 c[116,95,99,98,48,55]/1(a[110,111])",
    "t_cb08 c[116,95,99,98,48,56]/1(a[110,111])",
    "t_cb09 c[116,95,99,98,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_cb10 c[116,95,99,98,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[116,101,120,116])))",
    "t_cb11 c[116,95,99,98,49,49]/1(a[121,101,115])",
    "t_cb12 c[116,95,99,98,49,50]/1(a[121,101,115])",
    "t_cb13 c[116,95,99,98,49,51]/1(a[111,107])",
    "t_cb14 c[116,95,99,98,49,52]/1(a[121,101,115])",
    "t_cb15 c[116,95,99,98,49,53]/1(a[110,111])",
    "t_cb16 c[116,95,99,98,49,54]/1(a[111,107])",
    "t_cb17 c[116,95,99,98,49,55]/1(a[114,101,115,101,114,118,101,100,95,115,121,109,98,111,108])",
    "t_cb18 c[116,95,99,98,49,56]/1(a[117,99,115,95,116,101,120,116])",
    "t_cb19 c[116,95,99,98,49,57]/1(a[121,101,115])",
    "t_cb20 c[116,95,99,98,50,48]/1(a[110,111])",
    "t_cb21 c[116,95,99,98,50,49]/1(a[110,111])",
    "t_cb22 c[116,95,99,98,50,50]/1(a[110,111])",
    "t_th04 c[116,95,116,104,48,52]/1(a[109,111,114,101])",
    "t_sl01 c[116,95,115,108,48,49]/1(i4194304)",
    "t_sl02 c[116,95,115,108,48,50]/1(i2147483648)",
    "t_sl03 c[116,95,115,108,48,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[108,105,109,105,116],a[115,116,97,99,107,115],i1000)))",
    "t_sl04 c[116,95,115,108,48,52]/1(i1073741824)",
    "t_sl05 c[116,95,115,108,48,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[108,105,109,105,116],a[115,116,97,99,107,115],i0)))",
    "t_sl06 c[116,95,115,108,48,54]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))",
    "t_sl07 c[116,95,115,108,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_sl08 c[116,95,115,108,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_sl09 c[116,95,115,108,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sl10 c[116,95,115,108,49,48]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116])))",
    "t_sl11 c[116,95,115,108,49,49]/1(c[45]/2(i1073741824,i8388608))",
    "t_sl12 c[116,95,115,108,49,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[108,105,109,105,116],a[115,116,97,99,107,115],i100)))",
    "t_sl13 c[116,95,115,108,49,51]/1(c[45]/2(a[110,111],i1073741824))",
    "t_sl14 c[116,95,115,108,49,52]/1(c[45]/2(i1073741824,i1073741824))",
    "t_sl15 c[116,95,115,108,49,53]/1(c[45]/2(i4194304,i1073741824))",
    "t_sl16 c[116,95,115,108,49,54]/1(a[115,116,97,99,107])",
    "t_sl17 c[116,95,115,108,49,55]/1(i1048576)",
    "t_sl18 c[116,95,115,108,49,56]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[108,105,109,105,116],a[115,116,97,99,107,115],i100000)))",
    "t_sl20 c[116,95,115,108,50,48]/1(a[108,101,115,115])",
    "t_sl19 c[116,95,115,108,49,57]/1(i2000001)"
]

# the kernel's lines where they differ from swipl's (see the header)
# KNOWN DIFFERENCE (R2 F1b, checklist): the limit is counted in words here and in bytes in swipl, so a limit that is no multiple of 8 is
# rounded down: `set_prolog_flag(stack_limit, 2000001)` reads back 2000001 in swipl 10.1.20 (the pin), 2000000 here (sl19).
const _QX_KERNEL_DIFF = Dict{String, String}(
    "t_sl19" => "t_sl19 c[116,95,115,108,49,57]/1(i2000000)"
)
_qx_expected(p::String) = get(_QX_KERNEL_DIFF, first(split(p, ' ')), p)

function _qx_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _QX_CASES]
    text =
        _QX_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _QX_CASES
        ])
    f = joinpath(mktempdir(), "q10.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _qx_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_QX}()
    ld = LK.PL_local_data{_QX}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _qx_enc(ball::_QX)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_qxs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_QX, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _qx_enc(mk_expr(_QX, _QX[_qxs(name), lk_answers(ld, (a:a)...)...]))
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

@testset "the Q10 built-ins as swipl's (vr01-cb22)" begin
    f, names = _qx_file()
    kl, _, _ = _qx_kernel(f, names)
    @test length(kl) == length(_QX_PINNED)
    for (k, p) in zip(kl, _QX_PINNED)
        want = _qx_expected(p)
        if startswith(p, "t_cb11 ")
            # NAMED MISSING FOREIGN PREDICATE (audit D-0826 (1)(c)): open_null_stream/1 (pl-file.c:4701-4713, `Snew` over `nullFunctions`; owner
            # `cfile:pl-file.c`) is a missing foreign predicate, so the row raises existence_error(procedure, open_null_stream/1) where swipl answers `yes`.
            # The kernel's answer is pinned by name; `want` (swipl's, the .out) is unchanged and the row passes as "unexpected" the day it lands.
            @test startswith(k, "t_cb11 ") && occursin(_qx_codes("raised"), k) &&
                occursin(_qx_codes("open_null_stream"), k)
            @test_broken k == want
            continue
        end
        k == want || println(stderr, "  ours  ", k, "\n  want  ", want)
        @test k == want
    end
end

@testset "the Q10 rows are not vacuous" begin
    # the program loaded; every row has its answer line; the failing and raising rows are told apart from the answering ones
    @test _QX_PINNED[1] == "ok"
    @test length(_QX_PINNED) == length(_QX_CASES) + 1
    for (id, _) in _QX_CASES
        @test any(l -> startswith(l, "t_$id "), _QX_PINNED)
    end
    @test count(
        l -> startswith(l, "t_sh") && occursin("c" * _qx_codes("raised"), l), _QX_PINNED
    ) == 3      # sh05, sh06, sh11
    @test count(
        l -> startswith(l, "t_vr") && occursin("a" * _qx_codes("yes"), l), _QX_PINNED
    ) >= 9          # the \\=@= rows that answer yes
    @test any(l -> startswith(l, "t_sh11 ") && occursin(_qx_codes("signal"), l), _QX_PINNED)   # a child killed by signal 9
    @test any(l -> startswith(l, "t_ss17 ") && occursin("i1073741824", l), _QX_PINNED)         # the stack limit, 1 GiB in bytes
    @test any(
        l -> startswith(l, "t_th04 ") && occursin("a" * _qx_codes("more"), l), _QX_PINNED
    )   # trim_stacks gives stack back
    @test count(
        l -> startswith(l, "t_sl") && occursin("c" * _qx_codes("permission_error"), l),
        _QX_PINNED
    ) == 4     # sl03, sl05, sl12, sl18: the limit is below what the stacks hold
    @test any(l -> startswith(l, "t_sl01 ") && occursin("i4194304", l), _QX_PINNED)
    @test any(
        l -> startswith(l, "t_pt02 ") && occursin("s" * _qx_codes("ab cd"), l), _QX_PINNED
    )     # the space between two alphanumeric tokens
    @test any(
        l -> startswith(l, "t_pt03 ") && occursin("s" * _qx_codes("+ +"), l), _QX_PINNED
    )       # and between two symbol characters
    @test any(
        l -> startswith(l, "t_pt09 ") && occursin("a" * _qx_codes("encoding"), l),
        _QX_PINNED
    )  # a wide text: representation_error(encoding)
    @test any(l -> startswith(l, "t_pt10 ") && occursin("s[233]", l), _QX_PINNED)                    # the Latin-1 byte 233 as the character 233
    @test any(
        l -> startswith(l, "t_cb01 ") && occursin("a" * _qx_codes("text"), l), _QX_PINNED
    )          # the type of a text atom
    @test any(
        l -> startswith(l, "t_cb02 ") && occursin("a" * _qx_codes("reserved_symbol"), l),
        _QX_PINNED
    )   # and of []
    @test any(
        l -> startswith(l, "t_cb11 ") && occursin("a" * _qx_codes("yes"), l), _QX_PINNED
    )      # the enumeration finds a stream blob
    @test any(
        l -> startswith(l, "t_cb18 ") && occursin("a" * _qx_codes("ucs_text"), l),
        _QX_PINNED
    ) # a wide text atom has its own type
    @test any(
        l ->
            startswith(l, "t_os01 ") && occursin("a" * _qx_codes("foreign"), l) &&
            occursin("a" * _qx_codes("throw"), l),
        _QX_PINNED
    )
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_QX_PINNED) == length(_QX_CASES) + 1
    if swipl === nothing
        @info "Q10 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _qx_file()
        @test _qx_swipl_lines(f, names) == _QX_PINNED
    end
end
