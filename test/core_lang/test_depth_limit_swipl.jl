# ORIGINAL: a LIVE differential of P3's `call_with_depth_limit/3`, `call_with_inference_limit/3` (boot/syspred.pl over pl-prims.c
# `$depth_limit*`, `$inference_limit*`, pl-vmi.c depart_alerted) and `'$urgent_exception'/3` (pl-prims.c) against swipl at the pin — P3's rows
# test/core_lang/test_depth_limit_swipl.jl — dl01-dl26, il01-il25, ue01-ue12 against swipl 10.1.20 (the pin 18168e62):
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_style_check_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (the pin's swipl, ~/.local/swipl-pin1-18168e62/bin/swipl, two identical runs, 2026-11-11); with
#     `swipl` on PATH the live answers are compared with the pins too.
#   * The inference rows keep to limits far from the count (1000 on a goal of a few inferences; 100 on a loop; 100 on 100000 steps; 0, which the
#     wrapper's own overhead exceeds) except il21/il22, the boundary of dl_chain(5): swipl 10.1.20 stops it at 5 and runs it at 6. The kernel
#     counts an inference where upstream does (depart_or_retry_continue) but other counting sites differ: a boundary row that fails on the first
#     run is a counting difference to port, not a row to loosen.
#   * KNOWN DIFFERENCES (dl19, dl20): swipl's `$depth_limit/3` reads a size up to 2^64-1 and adds in `size_t`; the kernel's depth is an `Int`
#     (src/pl-prims.jl pl_depth_limit3_va). dl19 (2^63-1): swipl answers 1, the kernel's sum wraps negative, `representation_error(depth_limit)`;
#     dl20 (2^63): swipl answers 1, `PL_get_size_ex` is the kernel's, `representation_error(size_t)`. The kernel's lines are pinned apart
#     (`_DL_KERNEL_DIFF`). 2^64-1 is not a row: at the pin the sum wraps to the caller's level, the limit is never restored and every later
#     call of the process fails (swipl's own state, not a behaviour to port).
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.

using Test, LogicKernel
const LK = LogicKernel


# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through PL_unify_integer and PL_get_integer only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _DL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_dls(x) = lk_sym(_DL, Symbol(x))


_dl_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _dl_enc(t::_DL, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _dl_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _dl_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _dl_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_dl_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _DL_DRIVER = raw"""
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
function _dl_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _DL_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end




# the program: facts and recursions the limit rows run; dl_loop is the goal the inference limit stops
const _DL_PROGRAM = raw"""
dl_a(0).
dl_nd(1).
dl_nd(2).
dl_nd(3).
dl_chain(0) :- !.
dl_chain(N) :- N1 is N-1, dl_chain(N1).
dl_nonlast(0) :- !.
dl_nonlast(N) :- N1 is N-1, dl_nonlast(N1), true.
dl_ex :- throw(my_ball).
dl_loop :- dl_loop.
dl_nd2(1).
dl_nd2(2) :- dl_loop.
dl_nd3(1).
dl_nd3(2) :- dl_nonlast(5).
:- multifile portray/1.
portray(dl_pt) :- dl_nonlast(20), write(bar).
"""

const _DL_CASES = [
    ("dl01", raw"call_with_depth_limit(true, 1, R)"),   # the least limit
    ("dl02", raw"call_with_depth_limit(dl_a(0), 5, R)"),   # one call
    ("dl03", raw"call_with_depth_limit(dl_chain(3), 100, R)"),   # a tail recursion
    ("dl04", raw"call_with_depth_limit(dl_nonlast(3), 100, R)"),   # a recursion that is no last call
    ("dl05", raw"call_with_depth_limit(dl_nonlast(5), 3, R)"),   # exceeded
    ("dl06", raw"findall(X-R, call_with_depth_limit(dl_nd(X), 5, R), R0), R = R0"),   # answers on redo
    ("dl07", raw"\+ call_with_depth_limit(fail, 10, _), R = failed"),   # the goal fails inside the limit
    (
        "dl08",
        raw"catch(call_with_depth_limit(dl_ex, 5, _), B, true), call_with_depth_limit(dl_nonlast(5), 100, R2), R = B-R2"
    ),   # an exception passes, the limit is restored
    ("dl09", raw"call_with_depth_limit(dl_nonlast(5), 3, R1), dl_nonlast(50), R = R1-ok"),   # no limit after an exceeded one
    (
        "dl10",
        raw"call_with_depth_limit(call_with_depth_limit(dl_nonlast(3), 10, R1), 20, R2), R = R1-R2"
    ),   # nested, both within
    (
        "dl11",
        raw"call_with_depth_limit(call_with_depth_limit(dl_nonlast(8), 3, R1), 20, R2), R = R1-R2"
    ),   # nested, the inner exceeded
    (
        "dl12",
        raw"call_with_depth_limit(call_with_depth_limit(dl_nonlast(8), 20, R1), 3, R2), R = R1-R2"
    ),   # nested, the outer exceeded
    ("dl13", raw"call_with_depth_limit(true, inf, R)"),   # inf is no size
    ("dl14", raw"call_with_depth_limit(true, -1, R)"),   # a negative limit
    ("dl15", raw"call_with_depth_limit(true, foo, R)"),   # no integer
    ("dl16", raw"call_with_depth_limit(true, _, R)"),   # unbound
    (
        "dl17",
        raw"setup_call_cleanup(true, call_with_depth_limit(dl_a(0), 5, _), Det = yes), R = Det"
    ),   # deterministic: the cleanup runs at the exit
    (
        "dl18",
        raw"setup_call_cleanup(true, call_with_depth_limit(dl_nd(_), 5, _), Det = yes), R = Det"
    ),   # a choice point is left
    ("dl19", raw"call_with_depth_limit(true, 9223372036854775807, R)"),   # KNOWN DIFFERENCE 2^63-1
    ("dl20", raw"call_with_depth_limit(true, 9223372036854775808, R)"),   # KNOWN DIFFERENCE 2^63
    ("dl21", raw"call_with_depth_limit(format(atom(A), '~p', [dl_pt]), 6, R0), R = A-R0"),   # a PL_Q_NODEBUG query (the portray hook) runs without the limit
    ("dl22", raw"findall(X-R, call_with_depth_limit(dl_nd3(X), 4, R), R0), R = R0"),   # a redo into a deeper clause: the limit is installed again
    (
        "dl23",
        raw"call_with_depth_limit((format(atom(A), '~p', [dl_pt]), dl_nonlast(50)), 6, R0), R = A-R0"
    ),   # the limit is back after a PL_Q_NODEBUG query
    ("dl24", raw"\+ call_with_depth_limit(fail, 10, _), dl_nonlast(50), R = ok"),   # no limit after a failed goal
    (
        "dl25",
        raw"catch(call_with_depth_limit(dl_ex, 5, _), _, true), dl_nonlast(50), R = ok"
    ),   # no limit after an exception
    ("dl26", raw"call_with_depth_limit(true, 5, _), dl_nonlast(50), R = ok"),   # no limit after a successful goal
    ("il01", raw"call_with_inference_limit(true, 1000, R)"),   # the limit is not reached
    ("il02", raw"findall(X-R, call_with_inference_limit(dl_nd(X), 1000, R), R0), R = R0"),   # true, then ! on the last
    ("il03", raw"call_with_inference_limit(dl_loop, 1000, R)"),   # exceeded
    ("il04", raw"call_with_inference_limit(dl_chain(100000), 100, R)"),   # exceeded in a recursion
    ("il05", raw"call_with_inference_limit(true, infinite, R)"),   # infinite
    ("il06", raw"call_with_inference_limit(true, -1, R)"),   # negative
    ("il07", raw"call_with_inference_limit(true, foo, R)"),   # an atom that is not infinite
    ("il08", raw"call_with_inference_limit(true, _, R)"),   # unbound
    ("il09", raw"call_with_inference_limit(true, 1.5, R)"),   # no integer
    ("il10", raw"catch(call_with_inference_limit(dl_ex, 1000, _), B, true), R = B"),   # an exception passes
    ("il11", raw"call_with_inference_limit(dl_loop, 100, R1), dl_chain(2000), R = R1-ok"),   # no limit after an exceeded one
    (
        "il12",
        raw"call_with_inference_limit(call_with_inference_limit(dl_loop, 100, R1), 100000, R2), R = R1-R2"
    ),   # nested, the inner exceeded
    (
        "il13",
        raw"call_with_inference_limit(call_with_inference_limit(dl_loop, 100000, R1), 100, R2), R = R1-R2"
    ),   # nested, the outer exceeded
    ("il14", raw"findall(X-R, call_with_inference_limit(dl_nd2(X), 1000, R), R0), R = R0"),   # a redo into a looping clause
    ("il15", raw"\+ call_with_inference_limit(fail, 1000, _), R = failed"),   # the goal fails inside the limit
    (
        "il16",
        raw"setup_call_cleanup(true, call_with_inference_limit(dl_a(0), 1000, _), Det = yes), R = Det"
    ),   # deterministic
    (
        "il17",
        raw"setup_call_cleanup(true, call_with_inference_limit(dl_nd(_), 1000, _), Det = yes), R = Det"
    ),   # a choice point is left
    ("il18", raw"call_with_inference_limit(true, 0, R)"),   # limit 0: the overhead is allowed
    (
        "il19",
        raw"call_with_inference_limit(call_with_inference_limit(dl_chain(1000), 100000, R1), 100, R2), R = R1-R2"
    ),   # the lower outer limit stays: it fires inside the inner call
    ("il20", raw"\+ call_with_inference_limit(fail, 100, _), dl_chain(2000), R = ok"),   # no limit after a failed goal
    ("il21", raw"call_with_inference_limit(dl_chain(5), 5, R)"),   # the boundary, one short
    ("il22", raw"call_with_inference_limit(dl_chain(5), 6, R)"),   # the boundary, exact
    ("il23", raw"call_with_inference_limit(true, 100, _), dl_chain(2000), R = ok"),   # no limit after a successful goal
    ("il24", raw"call_with_inference_limit(true, 9223372036854775806, R)"),   # INT64_MAX-1: inferences+limit+2 wraps negative, never reached (unsigned compare)
    ("il25", raw"call_with_inference_limit(true, 9223372036854775807, R)"),   # INT64_MAX (the value of `infinite`): the same wrap
    ("ue01", raw"'$urgent_exception'(foo, error(type_error(a, b), _), R)"),   # error beats other
    ("ue02", raw"'$urgent_exception'(error(type_error(a, b), _), foo, R)"),   # error against other
    ("ue03", raw"'$urgent_exception'(a, b, R)"),   # equal: the first
    (
        "ue04",
        raw"'$urgent_exception'(error(type_error(a, b), _), error(resource_error(r), _), R)"
    ),   # resource beats error
    ("ue05", raw"'$urgent_exception'(error(resource_error(r), _), time_limit_exceeded, R)"),   # timeout beats resource
    ("ue06", raw"'$urgent_exception'(time_limit_exceeded, unwind(foo), R)"),   # unwind beats timeout
    ("ue07", raw"'$urgent_exception'(unwind(abort), unwind(foo), R)"),   # the top-level-unwind request beats unwind
    ("ue08", raw"'$urgent_exception'(unwind(abort), unwind(thread_exit(x)), R)"),   # thread_exit beats the top-level-unwind request
    ("ue09", raw"'$urgent_exception'(unwind(thread_exit(x)), unwind(halt(1)), R)"),   # halt beats thread_exit
    ("ue10", raw"'$urgent_exception'(unwind(halt(1)), unwind(thread_exit(x)), R)"),   # halt stays
    ("ue11", raw"'$urgent_exception'(_, foo, R)"),   # an unbound ball
    ("ue12", raw"( '$urgent_exception'(a, b, b) -> R = yes ; R = no )")    # the third argument is unified with the first on a tie
]

# the driver's whole output, one line per case after `ok`, from swipl at the pin
const _DL_PINNED = [
    "ok",
    "t_dl01 c[116,95,100,108,48,49]/1(i1)",
    "t_dl02 c[116,95,100,108,48,50]/1(i1)",
    "t_dl03 c[116,95,100,108,48,51]/1(i4)",
    "t_dl04 c[116,95,100,108,48,52]/1(i4)",
    "t_dl05 c[116,95,100,108,48,53]/1(a[100,101,112,116,104,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100])",
    "t_dl06 c[116,95,100,108,48,54]/1(c[91,124,93]/2(c[45]/2(i1,i1),c[91,124,93]/2(c[45]/2(i2,i1),c[91,124,93]/2(c[45]/2(i3,i1),nil))))",
    "t_dl07 c[116,95,100,108,48,55]/1(a[102,97,105,108,101,100])",
    "t_dl08 c[116,95,100,108,48,56]/1(c[45]/2(a[109,121,95,98,97,108,108],i6))",
    "t_dl09 c[116,95,100,108,48,57]/1(c[45]/2(a[100,101,112,116,104,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],a[111,107]))",
    "t_dl10 c[116,95,100,108,49,48]/1(c[45]/2(i4,i2))",
    "t_dl11 c[116,95,100,108,49,49]/1(c[45]/2(a[100,101,112,116,104,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],i2))",
    "t_dl12 c[116,95,100,108,49,50]/1(c[45]/2(i9,i2))",
    "t_dl13 c[116,95,100,108,49,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[105,110,102])))",
    "t_dl14 c[116,95,100,108,49,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_dl15 c[116,95,100,108,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111])))",
    "t_dl16 c[116,95,100,108,49,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dl17 c[116,95,100,108,49,55]/1(a[121,101,115])",
    "t_dl18 c[116,95,100,108,49,56]/1(V0) c[116,95,100,108,49,56]/1(V0) c[116,95,100,108,49,56]/1(a[121,101,115])",
    "t_dl19 c[116,95,100,108,49,57]/1(i1)",
    "t_dl20 c[116,95,100,108,50,48]/1(i1)",
    "t_dl21 c[116,95,100,108,50,49]/1(c[45]/2(a[98,97,114],i1))",
    "t_dl22 c[116,95,100,108,50,50]/1(c[91,124,93]/2(c[45]/2(i1,i1),c[91,124,93]/2(c[45]/2(V0,a[100,101,112,116,104,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100]),nil)))",
    "t_dl23 c[116,95,100,108,50,51]/1(c[45]/2(V0,a[100,101,112,116,104,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100]))",
    "t_dl24 c[116,95,100,108,50,52]/1(a[111,107])",
    "t_dl25 c[116,95,100,108,50,53]/1(a[111,107])",
    "t_dl26 c[116,95,100,108,50,54]/1(a[111,107])",
    "t_il01 c[116,95,105,108,48,49]/1(a[33])",
    "t_il02 c[116,95,105,108,48,50]/1(c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i2,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(i3,a[33]),nil))))",
    "t_il03 c[116,95,105,108,48,51]/1(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100])",
    "t_il04 c[116,95,105,108,48,52]/1(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100])",
    "t_il05 c[116,95,105,108,48,53]/1(a[33])",
    "t_il06 c[116,95,105,108,48,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_il07 c[116,95,105,108,48,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116],a[102,111,111])))",
    "t_il08 c[116,95,105,108,48,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_il09 c[116,95,105,108,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_il10 c[116,95,105,108,49,48]/1(a[109,121,95,98,97,108,108])",
    "t_il11 c[116,95,105,108,49,49]/1(c[45]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],a[111,107]))",
    "t_il12 c[116,95,105,108,49,50]/1(c[45]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],a[33]))",
    "t_il13 c[116,95,105,108,49,51]/1(c[45]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],a[33]))",
    "t_il14 c[116,95,105,108,49,52]/1(c[91,124,93]/2(c[45]/2(i1,a[116,114,117,101]),c[91,124,93]/2(c[45]/2(V0,a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100]),nil)))",
    "t_il15 c[116,95,105,108,49,53]/1(a[102,97,105,108,101,100])",
    "t_il16 c[116,95,105,108,49,54]/1(a[121,101,115])",
    "t_il17 c[116,95,105,108,49,55]/1(V0) c[116,95,105,108,49,55]/1(V0) c[116,95,105,108,49,55]/1(a[121,101,115])",
    "t_il18 c[116,95,105,108,49,56]/1(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100])",
    "t_il19 c[116,95,105,108,49,57]/1(c[45]/2(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100],a[33]))",
    "t_il20 c[116,95,105,108,50,48]/1(a[111,107])",
    "t_il21 c[116,95,105,108,50,49]/1(a[105,110,102,101,114,101,110,99,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100])",
    "t_il22 c[116,95,105,108,50,50]/1(a[33])",
    "t_il23 c[116,95,105,108,50,51]/1(a[111,107])",
    "t_il24 c[116,95,105,108,50,52]/1(a[33])",
    "t_il25 c[116,95,105,108,50,53]/1(a[33])",
    "t_ue01 c[116,95,117,101,48,49]/1(c[101,114,114,111,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[97],a[98]),V0))",
    "t_ue02 c[116,95,117,101,48,50]/1(c[101,114,114,111,114]/2(c[116,121,112,101,95,101,114,114,111,114]/2(a[97],a[98]),V0))",
    "t_ue03 c[116,95,117,101,48,51]/1(a[97])",
    "t_ue04 c[116,95,117,101,48,52]/1(c[101,114,114,111,114]/2(c[114,101,115,111,117,114,99,101,95,101,114,114,111,114]/1(a[114]),V0))",
    "t_ue05 c[116,95,117,101,48,53]/1(a[116,105,109,101,95,108,105,109,105,116,95,101,120,99,101,101,100,101,100])",
    "t_ue06 c[116,95,117,101,48,54]/1(c[117,110,119,105,110,100]/1(a[102,111,111]))",
    "t_ue07 c[116,95,117,101,48,55]/1(c[117,110,119,105,110,100]/1(a[97,98,111,114,116]))",
    "t_ue08 c[116,95,117,101,48,56]/1(c[117,110,119,105,110,100]/1(c[116,104,114,101,97,100,95,101,120,105,116]/1(a[120])))",
    "t_ue09 c[116,95,117,101,48,57]/1(c[117,110,119,105,110,100]/1(c[104,97,108,116]/1(i1)))",
    "t_ue10 c[116,95,117,101,49,48]/1(c[117,110,119,105,110,100]/1(c[104,97,108,116]/1(i1)))",
    "t_ue11 c[116,95,117,101,49,49]/1(a[102,111,111])",
    "t_ue12 c[116,95,117,101,49,50]/1(a[110,111])"
]

# the kernel's lines where they differ from swipl's (see the header)
const _DL_KERNEL_DIFF = Dict(
    "t_dl19" => "t_dl19 c[116,95,100,108,49,57]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[100,101,112,116,104,95,108,105,109,105,116])))",
    "t_dl20" => "t_dl20 c[116,95,100,108,50,48]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))"
)
_dl_expected(p::String) = get(_DL_KERNEL_DIFF, first(split(p, ' ')), p)

function _dl_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _DL_CASES]
    text =
        _DL_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _DL_CASES
        ])
    f = joinpath(mktempdir(), "depth_limit.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _dl_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_DL}()
    ld = LK.PL_local_data{_DL}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _dl_enc(ball::_DL)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_dls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_DL, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _dl_enc(mk_expr(_DL, _DL[_dls(name), lk_answers(ld, (a:a)...)...]))
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

@testset "call_with_depth_limit/3, call_with_inference_limit/3, \$urgent_exception/3 as swipl's (dl01-ue12)" begin
    f, names = _dl_file()
    kl, _, _ = _dl_kernel(f, names)
    @test length(kl) == length(_DL_PINNED)
    for (k, p) in zip(kl, _DL_PINNED)
        want = _dl_expected(p)
        k == want || println(stderr, "  ours  ", k, "\n  want  ", want)
        @test k == want
    end
end

@testset "the depth and inference limit rows are not vacuous" begin
    # the program loaded; every row has its answer line; the rows that fail or raise are told apart from those that answer
    @test _DL_PINNED[1] == "ok"
    @test length(_DL_PINNED) == length(_DL_CASES) + 1
    for (id, _) in _DL_CASES
        @test any(l -> startswith(l, "t_$id"), _DL_PINNED)
    end
    @test count(l -> occursin(_dl_codes("depth_limit_exceeded"), l), _DL_PINNED) >= 5      # dl05, dl09, dl11, dl22, dl23
    @test count(l -> occursin(_dl_codes("inference_limit_exceeded"), l), _DL_PINNED) >= 9   # il03, il04, il11-il14, il18, il19, il21
    @test count(l -> occursin("c" * _dl_codes("raised"), l), _DL_PINNED) == 8       # the argument errors (dl13-dl16, il06-il09)
    @test _DL_PINNED[2:end] != [_dl_expected(p) for p in _DL_PINNED[2:end]]     # the known differences change something
    @test length(_DL_KERNEL_DIFF) == 2
    @test any(l -> startswith(l, "t_ue03 ") && endswith(l, "(a[97])"), _DL_PINNED)  # the first of two equal balls
    @test any(l -> startswith(l, "t_ue09 "), _DL_PINNED) &&
        any(l -> startswith(l, "t_ue10 "), _DL_PINNED)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_DL_PINNED) == length(_DL_CASES) + 1
    if swipl === nothing
        @info "P3 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _dl_file()
        @test _dl_swipl_lines(f, names) == _DL_PINNED
    end
end
