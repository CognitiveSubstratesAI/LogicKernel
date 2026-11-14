# ORIGINAL: RD2's gate — the blob read of src/pl-read.jl (`read_blob_start`, `read_blob_resume`, `read_blob_end`, `read_blob_arg`, the option `blob(error|dead|resolve)`) with `newDeadBlob`, `lookupLiveBlob`, `deadBlobType` (src/pl-atom.jl) and the written form of a dead blob (`write_unavailable`, `blob_written_text`, src/pl-write.jl) against swipl 10.1.20.
# test/core_text/test_read_blob_swipl.jl — a program consulted by the kernel's loader whose cases `t_<id>(R)` run IN ORDER in one database (the design of
# test_read_comments_swipl.jl): bl01-bl12 `<type>(...)` read with blob(dead) (type through blob/2, atom/1, the text `~q` and `~w` write), bl20-bl34 syntax
# errors with their character positions and the other values of blob(_), bl40-bl68 in a term, the positions, a stream, equality and order of dead blobs, the type
# tests, write/print/write_canonical/term_to_atom and the round trip, bl70-bl80 blob(resolve): a live stream written as `<stream>(0x...)` is that stream again.
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, LC_ALL=C, two identical runs); with `swipl` on PATH the live answers are compared with the pins too.
#     A blob never appears in an answer: the program turns it into its type (`blob/2`), `atom/1`, and its `~q` and `~w` text.
#   * An address written by the kernel is its blob's atom word, swipl's the pointer: the live rows are PROPERTY rows (T == S, the blob/2 type), not text rows.
#   * UNVERIFIED on the kernel: written without running the kernel (edit-only step); the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream readers, built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _BL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_bls(x) = lk_sym(_BL, Symbol(x))

_bl_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _bl_enc(t::_BL, seen::Vector{UInt64}=UInt64[])::String
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
        return is_nil(t) ? "nil" : "a" * _bl_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _bl_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _bl_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_bl_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the driver of test_at_body_swipl.jl (consult, then every answer of each t_<id>/1, `enc`oded)
const _BL_DRIVER = raw"""
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
function _bl_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _BL_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        withenv("LC_ALL" => "C") do
            read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
        end
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the helpers: `qq_str/2` (a string stream), `qq_ctx/2` (the location of a syntax error: numbers kept, file and stream dropped), `qq_rt/3`, `qq_tt/2`, `qq_st/3` as in test_read_qq_swipl.jl
const _BL_HELPERS = raw"""
qq_str(Text, S) :- open_string(Text, S).
qq_ctx(string(S, P), string(S, P)) :- !.
qq_ctx(stream(_, L, LP, C), stream(L, LP, C)) :- !.
qq_ctx(file(_, L, LP, C), file(L, LP, C)) :- !.
qq_ctx(_, other).
qq_rt(Text, Opts, R) :-
    catch(( read_term_from_atom(Text, T, Opts), R = ok(T) ), error(F, C), ( qq_ctx(C, C1), R = raised(F, C1) )).
qq_tt(Text, R) :-
    catch(( term_to_atom(T, Text), R = ok(T) ), error(F, C), ( qq_ctx(C, C1), R = raised(F, C1) )).
qq_st(Text, Opts, R) :-
    qq_str(Text, S),
    catch(( read_term(S, T, Opts), R = ok(T) ), error(F, C), ( qq_ctx(C, C1), R = raised(F, C1) )).
"""

# the blob rows' helpers: `bl_show/2` turns the blob read into its type, atom/1, and its `~q` and `~w` texts; `bl_rt/3` and `bl_st/3` read from an atom and from a string stream
const _BL_PROGRAM = raw"""
bl_show(T, r(Ty, At, Q, W)) :-
    ( blob(T, Ty0) -> Ty = Ty0 ; Ty = none ),
    ( atom(T) -> At = atom ; At = notatom ),
    format(atom(Q), '~q', [T]),
    format(atom(W), '~w', [T]).
bl_rt(Text, Opts, R) :-
    catch(( read_term_from_atom(Text, T, Opts), bl_show(T, R0), R = ok(R0) ), error(F, C), ( qq_ctx(C, C1), R = raised(F, C1) )).
bl_st(Text, Opts, R) :-
    qq_str(Text, S),
    catch(( read_term(S, T, Opts), bl_show(T, R0), R = ok(R0) ), error(F, C), ( qq_ctx(C, C1), R = raised(F, C1) )).
"""

# (id, goal), run IN ORDER; `R` is the answer
const _BL_CASES = [
    (
        "bl01",
        raw"""bl_rt('<clause>(0x123)', [blob(dead)], R)"""
    ),
    (
        "bl02",
        raw"""bl_rt('<foo>(0x123)', [blob(dead)], R)"""
    ),
    (
        "bl03",
        raw"""bl_rt('<foo>()', [blob(dead)], R)"""
    ),
    (
        "bl04",
        raw"""bl_rt('<foo>(a, f(b))', [blob(dead)], R)"""
    ),
    (
        "bl05",
        raw"""bl_rt('<foo>(a+b, [x|y], "s", ''q q'')', [blob(dead)], R)"""
    ),
    (
        "bl06",
        raw"""bl_rt('<foo>(1)', [blob(resolve)], R)"""
    ),
    (
        "bl07",
        raw"""bl_rt('<foo>( 0x123 )', [blob(dead)], R)"""
    ),
    (
        "bl08",
        raw"""bl_rt('<1>(1)', [blob(dead)], R)"""
    ),
    (
        "bl09",
        raw"""bl_rt('<fo.o>(1)', [blob(dead)], R)"""
    ),
    (
        "bl10",
        raw"""bl_rt('<>(1)', [blob(dead)], R)"""
    ),
    (
        "bl11",
        raw"""bl_rt('<foo>(1) ', [blob(dead)], R)"""
    ),
    (
        "bl12",
        raw"""bl_rt('<foo>(\xE4\\x20AC\)', [blob(dead)], R)"""
    ),
    (
        "bl20",
        raw"""bl_rt('<foo>(a,', [blob(dead)], R)"""
    ),
    (
        "bl21",
        raw"""bl_rt('<foo>(a', [blob(dead)], R)"""
    ),
    (
        "bl22",
        raw"""bl_rt('<foo>(a,,b)', [blob(dead)], R)"""
    ),
    (
        "bl23",
        raw"""bl_rt('<foo>(,)', [blob(dead)], R)"""
    ),
    (
        "bl24",
        raw"""bl_rt('<foo>(a b)', [blob(dead)], R)"""
    ),
    (
        "bl25",
        raw"""bl_rt('<foo>(f(', [blob(dead)], R)"""
    ),
    (
        "bl26",
        raw"""bl_rt('<foo>(0x123)', [], R)"""
    ),
    (
        "bl27",
        raw"""bl_rt('<foo>(0x123)', [blob(error)], R)"""
    ),
    (
        "bl28",
        raw"""bl_rt('<foo>(0x123)', [blob(bad)], R)"""
    ),
    (
        "bl29",
        raw"""bl_rt('<foo>(0x123)', [blob(_)], R)"""
    ),
    (
        "bl30",
        raw"""bl_rt('<a b>(1)', [blob(dead)], R)"""
    ),
    (
        "bl31",
        raw"""bl_rt('<foo> (1)', [blob(dead)], R)"""
    ),
    (
        "bl32",
        raw"""bl_rt('<foo>(1', [blob(resolve)], R)"""
    ),
    (
        "bl33",
        raw"""bl_rt('<foo>', [blob(dead)], R)"""
    ),
    (
        "bl34",
        raw"""bl_rt('<foo>(1) 2', [blob(dead)], R)"""
    ),
    (
        "bl40",
        raw"""read_term_from_atom('f(<foo>(0x123), <bar>(1))', T, [blob(dead)]), T = f(A, B), bl_show(A, RA), bl_show(B, RB), R = RA-RB"""
    ),
    (
        "bl41",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead), subterm_positions(P)]), bl_show(T, R0), R = R0-P"""
    ),
    (
        "bl42",
        raw"""read_term_from_atom('f(<foo>(0x123), x)', T, [blob(dead), subterm_positions(P)]), T = f(A, _), bl_show(A, R0), R = R0-P"""
    ),
    (
        "bl43",
        raw"""read_term_from_atom('<foo>(a, f(b))', T, [blob(dead), subterm_positions(P)]), bl_show(T, R0), R = R0-P"""
    ),
    (
        "bl44",
        raw"""read_term_from_atom('<foo>()', T, [blob(dead), subterm_positions(P)]), bl_show(T, R0), R = R0-P"""
    ),
    (
        "bl45",
        raw"""read_term_from_atom('[<foo>(1), a]', T, [blob(dead), subterm_positions(P)]), T = [A|_], bl_show(A, R0), R = R0-P"""
    ),
    (
        "bl46",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead), term_position(P)]), bl_show(T, R0), R = R0-P"""
    ),
    (
        "bl47",
        raw"""bl_st('<foo>(0x123). x.', [blob(dead)], R)"""
    ),
    (
        "bl48",
        raw"""qq_str('<foo>(0x123). x.', S), read_term(S, A, [blob(dead)]), read_term(S, B, []), bl_show(A, RA), R = RA-B"""
    ),
    (
        "bl49",
        raw"""bl_st('<foo>(a,', [blob(dead)], R)"""
    ),
    (
        "bl50",
        raw"""bl_st('<foo>(0x123). x.', [], R)"""
    ),
    (
        "bl51",
        raw"""bl_st('\n <foo>(a,\n b', [blob(dead)], R)"""
    ),
    (
        "bl52",
        raw"""read_term_from_atom('X = <foo>(1)', T, [blob(dead), variable_names(Vs)]), T = (_ = B), bl_show(B, RB), R = RB-Vs"""
    ),
    (
        "bl53",
        raw"""read_term_from_atom('<foo>(1) + <foo>(1)', T, [blob(dead)]), T = (A + B), ( A == B -> R = same ; R = differ )"""
    ),
    (
        "bl54",
        raw"""read_term_from_atom('<foo>(1) + <foo>(1)', T, [blob(dead)]), T = (A + B), compare(O, A, B), R = O"""
    ),
    (
        "bl55",
        raw"""read_term_from_atom('<foo>(1) + <foo>(1)', T, [blob(dead)]), T = (A + B), ( A @< B -> R = lt ; R = notlt )"""
    ),
    (
        "bl56",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), ( atom(T) -> R = atom ; atomic(T) -> R = atomic ; R = other )"""
    ),
    (
        "bl57",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), ( callable(T) -> R = callable ; compound(T) -> R = compound ; R = other )"""
    ),
    (
        "bl58",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), ( blob(T, text) -> R = text ; blob(T, foo) -> R = foo ; R = other )"""
    ),
    (
        "bl59",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), catch(atom_length(T, _), error(type_error(Ty, _), _), R = Ty)"""
    ),
    (
        "bl61",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), with_output_to(atom(A), print(T)), R = A"""
    ),
    (
        "bl62",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), with_output_to(atom(A), write_canonical(T)), R = A"""
    ),
    (
        "bl63",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), with_output_to(atom(A), write_term(T, [quoted(true)])), R = A"""
    ),
    (
        "bl64",
        raw"""read_term_from_atom('f(<foo>(a, f(b)))', T, [blob(dead)]), with_output_to(atom(A), writeq(T)), R = A"""
    ),
    (
        "bl65",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), term_to_atom(T, A), R = A"""
    ),
    (
        "bl66",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), with_output_to(atom(A), write_term(T, [blobs(portray)])), R = A"""
    ),
    (
        "bl67",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), format(atom(A), '~q', [T]), bl_rt(A, [blob(dead)], R)"""
    ),
    (
        "bl68",
        raw"""read_term_from_atom('<foo>(0x123)', T, [blob(dead)]), copy_term(T, U), ( T == U -> R = same ; R = differ )"""
    ),
    (
        "bl70",
        raw"""current_output(S), format(atom(A), '~q', [S]), read_term_from_atom(A, T, [blob(resolve)]), ( T == S -> R = resolved ; R = not_resolved )"""
    ),
    (
        "bl71",
        raw"""current_output(S), format(atom(A), '~q', [S]), read_term_from_atom(A, T, [blob(dead)]), ( T == S -> R = same ; R = differ )"""
    ),
    (
        "bl72",
        raw"""current_output(S), format(atom(A), '~q', [S]), read_term_from_atom(A, T, [blob(dead)]), blob(T, Ty), R = Ty"""
    ),
    (
        "bl73",
        raw"""current_output(S), format(atom(A), '~q', [S]), read_term_from_atom(A, T, [blob(resolve)]), blob(T, Ty), R = Ty"""
    ),
    (
        "bl74",
        raw"""current_output(S), format(atom(A), '~q', [S]), read_term_from_atom(A, _, [blob(error)]), R = no_error"""
    ),
    (
        "bl75",
        raw"""open_string('x', S1), open_string('y', S2), format(atom(A1), '~q', [S1]), format(atom(A2), '~q', [S2]), atomic_list_concat(['f(', A1, ', ', A2, ')'], A), read_term_from_atom(A, T, [blob(resolve)]), T = f(X1, X2), ( X1 == S1, X2 == S2 -> R = both ; R = other )"""
    ),
    (
        "bl76",
        raw"""open_string('x', S1), format(atom(A1), '~q', [S1]), close(S1), read_term_from_atom(A1, T, [blob(resolve)]), ( T == S1 -> R = same ; R = differ )"""
    ),
    (
        "bl77",
        raw"""bl_rt('<stream>(0x1)', [blob(resolve)], R)"""
    ),
    (
        "bl78",
        raw"""bl_rt('<stream>(0x1)', [blob(dead)], R)"""
    ),
    (
        "bl79",
        raw"""bl_rt('<stream>(0x1, a)', [blob(resolve)], R)"""
    ),
    (
        "bl80",
        raw"""open_string('x', S), format(atom(A0), '~q', [S]), sub_atom(A0, B, _, 0, Tail), sub_atom(A0, 0, B, _, Head), Head == '<stream>', atom_concat('<foo>', Tail, A), read_term_from_atom(A, T, [blob(resolve)]), ( T == S -> R = resolved ; R = not_resolved )"""
    )
]

# swipl 10.1.20, LC_ALL=C: the lines of the driver
const _BL_PINNED = [
    "ok",
    "t_bl01 c[116,95,98,108,48,49]/1(c[111,107]/1(c[114]/4(a[99,108,97,117,115,101],a[110,111,116,97,116,111,109],a[60,99,108,97,117,115,101,62,40,48,120,49,50,51,41],a[60,99,108,97,117,115,101,62,40,48,120,49,50,51,41])))",
    "t_bl02 c[116,95,98,108,48,50]/1(c[111,107]/1(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,48,120,49,50,51,41],a[60,102,111,111,62,40,48,120,49,50,51,41])))",
    "t_bl03 c[116,95,98,108,48,51]/1(c[111,107]/1(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,41],a[60,102,111,111,62,40,41])))",
    "t_bl04 c[116,95,98,108,48,52]/1(c[111,107]/1(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,97,44,32,102,40,98,41,41],a[60,102,111,111,62,40,97,44,32,102,40,98,41,41])))",
    "t_bl05 c[116,95,98,108,48,53]/1(c[111,107]/1(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,97,43,98,44,32,91,120,124,121,93,44,32,34,115,34,44,32,39,113,32,113,39,41],a[60,102,111,111,62,40,97,43,98,44,32,91,120,124,121,93,44,32,34,115,34,44,32,39,113,32,113,39,41])))",
    "t_bl06 c[116,95,98,108,48,54]/1(c[111,107]/1(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,49,41],a[60,102,111,111,62,40,49,41])))",
    "t_bl07 c[116,95,98,108,48,55]/1(c[111,107]/1(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,32,48,120,49,50,51,32,41],a[60,102,111,111,62,40,32,48,120,49,50,51,32,41])))",
    "t_bl08 c[116,95,98,108,48,56]/1(c[111,107]/1(c[114]/4(a[49],a[110,111,116,97,116,111,109],a[60,49,62,40,49,41],a[60,49,62,40,49,41])))",
    "t_bl09 c[116,95,98,108,48,57]/1(c[111,107]/1(c[114]/4(a[102,111,46,111],a[110,111,116,97,116,111,109],a[60,102,111,46,111,62,40,49,41],a[60,102,111,46,111,62,40,49,41])))",
    "t_bl10 c[116,95,98,108,49,48]/1(c[111,107]/1(c[114]/4(a[110,111,110,101],a[110,111,116,97,116,111,109],a[60,62,40,49,41],a[60,62,40,49,41])))",
    "t_bl11 c[116,95,98,108,49,49]/1(c[111,107]/1(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,49,41],a[60,102,111,111,62,40,49,41])))",
    "t_bl12 c[116,95,98,108,49,50]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,228,8364,41,32,46,32],i6)))",
    "t_bl20 c[116,95,98,108,50,48]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,99,108,97,117,115,101]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,97,44,32,46,32],i8)))",
    "t_bl21 c[116,95,98,108,50,49]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,97,32,46,32],i7)))",
    "t_bl22 c[116,95,98,108,50,50]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[113,117,111,116,101,100,95,112,117,110,99,116,117,97,116,105,111,110]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,97,44,44,98,41,32,46,32],i7)))",
    "t_bl23 c[116,95,98,108,50,51]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[113,117,111,116,101,100,95,112,117,110,99,116,117,97,116,105,111,110]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,44,41,32,46,32],i5)))",
    "t_bl24 c[116,95,98,108,50,52]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,97,32,98,41,32,46,32],i7)))",
    "t_bl25 c[116,95,98,108,50,53]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,99,108,97,117,115,101]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,102,40,32,46,32],i8)))",
    "t_bl26 c[116,95,98,108,50,54]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,48,120,49,50,51,41,32,46,32],i0)))",
    "t_bl27 c[116,95,98,108,50,55]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,48,120,49,50,51,41,32,46,32],i0)))",
    "t_bl28 c[116,95,98,108,50,56]/1(c[114,97,105,115,101,100]/2(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[98,108,111,98],a[98,97,100]),a[111,116,104,101,114]))",
    "t_bl29 c[116,95,98,108,50,57]/1(c[114,97,105,115,101,100]/2(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114],a[111,116,104,101,114]))",
    "t_bl30 c[116,95,98,108,51,48]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,97,32,98,62,40,49,41,32,46,32],i0)))",
    "t_bl31 c[116,95,98,108,51,49]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,32,40,49,41,32,46,32],i0)))",
    "t_bl32 c[116,95,98,108,51,50]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,49,32,46,32],i7)))",
    "t_bl33 c[116,95,98,108,51,51]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,32,46,32],i0)))",
    "t_bl34 c[116,95,98,108,51,52]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,105,110,103]/2(s[60,102,111,111,62,40,49,41,32,50,32,46,32],i8)))",
    "t_bl40 c[116,95,98,108,52,48]/1(c[45]/2(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,48,120,49,50,51,41],a[60,102,111,111,62,40,48,120,49,50,51,41]),c[114]/4(a[98,97,114],a[110,111,116,97,116,111,109],a[60,98,97,114,62,40,49,41],a[60,98,97,114,62,40,49,41])))",
    "t_bl41 c[116,95,98,108,52,49]/1(c[45]/2(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,48,120,49,50,51,41],a[60,102,111,111,62,40,48,120,49,50,51,41]),c[45]/2(i0,i12)))",
    "t_bl42 c[116,95,98,108,52,50]/1(c[45]/2(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,48,120,49,50,51,41],a[60,102,111,111,62,40,48,120,49,50,51,41]),c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5(i0,i18,i0,i1,c[91,124,93]/2(c[45]/2(i2,i14),c[91,124,93]/2(c[45]/2(i16,i17),nil)))))",
    "t_bl43 c[116,95,98,108,52,51]/1(c[45]/2(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,97,44,32,102,40,98,41,41],a[60,102,111,111,62,40,97,44,32,102,40,98,41,41]),c[45]/2(i0,i14)))",
    "t_bl44 c[116,95,98,108,52,52]/1(c[45]/2(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,41],a[60,102,111,111,62,40,41]),c[45]/2(i0,i7)))",
    "t_bl45 c[116,95,98,108,52,53]/1(c[45]/2(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,49,41],a[60,102,111,111,62,40,49,41]),c[108,105,115,116,95,112,111,115,105,116,105,111,110]/4(i0,i13,c[91,124,93]/2(c[45]/2(i1,i9),c[91,124,93]/2(c[45]/2(i11,i12),nil)),a[110,111,110,101])))",
    "t_bl46 c[116,95,98,108,52,54]/1(c[45]/2(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,48,120,49,50,51,41],a[60,102,111,111,62,40,48,120,49,50,51,41]),V0))",
    "t_bl47 c[116,95,98,108,52,55]/1(c[111,107]/1(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,48,120,49,50,51,41],a[60,102,111,111,62,40,48,120,49,50,51,41])))",
    "t_bl48 c[116,95,98,108,52,56]/1(c[45]/2(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,48,120,49,50,51,41],a[60,102,111,111,62,40,48,120,49,50,51,41]),a[120]))",
    "t_bl49 c[116,95,98,108,52,57]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101]),c[115,116,114,101,97,109]/3(i1,i8,i7)))",
    "t_bl50 c[116,95,98,108,53,48]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100]),c[115,116,114,101,97,109]/3(i1,i1,i0)))",
    "t_bl51 c[116,95,98,108,53,49]/1(c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[101,110,100,95,111,102,95,102,105,108,101]),c[115,116,114,101,97,109]/3(i3,i1,i12)))",
    "t_bl52 c[116,95,98,108,53,50]/1(c[45]/2(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,49,41],a[60,102,111,111,62,40,49,41]),c[91,124,93]/2(c[61]/2(a[88],V0),nil)))",
    "t_bl53 c[116,95,98,108,53,51]/1(a[100,105,102,102,101,114])",
    "t_bl54 c[116,95,98,108,53,52]/1(a[60])",
    "t_bl55 c[116,95,98,108,53,53]/1(a[108,116])",
    "t_bl56 c[116,95,98,108,53,54]/1(a[97,116,111,109,105,99])",
    "t_bl57 c[116,95,98,108,53,55]/1(a[111,116,104,101,114])",
    "t_bl58 c[116,95,98,108,53,56]/1(a[102,111,111])",
    "t_bl59 c[116,95,98,108,53,57]/1(a[115,116,114,105,110,103])",
    "t_bl61 c[116,95,98,108,54,49]/1(a[60,102,111,111,62,40,48,120,49,50,51,41])",
    "t_bl62 c[116,95,98,108,54,50]/1(a[60,102,111,111,62,40,48,120,49,50,51,41])",
    "t_bl63 c[116,95,98,108,54,51]/1(a[60,102,111,111,62,40,48,120,49,50,51,41])",
    "t_bl64 c[116,95,98,108,54,52]/1(a[102,40,60,102,111,111,62,40,97,44,32,102,40,98,41,41,41])",
    "t_bl65 c[116,95,98,108,54,53]/1(a[60,102,111,111,62,40,48,120,49,50,51,41])",
    "t_bl66 c[116,95,98,108,54,54]/1(a[60,102,111,111,62,40,48,120,49,50,51,41])",
    "t_bl67 c[116,95,98,108,54,55]/1(c[111,107]/1(c[114]/4(a[102,111,111],a[110,111,116,97,116,111,109],a[60,102,111,111,62,40,48,120,49,50,51,41],a[60,102,111,111,62,40,48,120,49,50,51,41])))",
    "t_bl68 c[116,95,98,108,54,56]/1(a[115,97,109,101])",
    "t_bl70 c[116,95,98,108,55,48]/1(a[114,101,115,111,108,118,101,100])",
    "t_bl71 c[116,95,98,108,55,49]/1(a[100,105,102,102,101,114])",
    "t_bl72 c[116,95,98,108,55,50]/1(a[115,116,114,101,97,109])",
    "t_bl73 c[116,95,98,108,55,51]/1(a[115,116,114,101,97,109])",
    "t_bl74 c[116,95,98,108,55,52]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])))",
    "t_bl75 c[116,95,98,108,55,53]/1(a[98,111,116,104])",
    "t_bl76 c[116,95,98,108,55,54]/1(a[115,97,109,101])",
    "t_bl77 c[116,95,98,108,55,55]/1(c[111,107]/1(c[114]/4(a[115,116,114,101,97,109],a[110,111,116,97,116,111,109],a[60,115,116,114,101,97,109,62,40,48,120,49,41],a[60,115,116,114,101,97,109,62,40,48,120,49,41])))",
    "t_bl78 c[116,95,98,108,55,56]/1(c[111,107]/1(c[114]/4(a[115,116,114,101,97,109],a[110,111,116,97,116,111,109],a[60,115,116,114,101,97,109,62,40,48,120,49,41],a[60,115,116,114,101,97,109,62,40,48,120,49,41])))",
    "t_bl79 c[116,95,98,108,55,57]/1(c[111,107]/1(c[114]/4(a[115,116,114,101,97,109],a[110,111,116,97,116,111,109],a[60,115,116,114,101,97,109,62,40,48,120,49,44,32,97,41],a[60,115,116,114,101,97,109,62,40,48,120,49,44,32,97,41])))",
    "t_bl80 c[116,95,98,108,56,48]/1(a[110,111,116,95,114,101,115,111,108,118,101,100])"
]

"The program and cases as one file (in `dir`); the case predicates' names."
function _bl_file(dir::String, program::String, cases)::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in cases]
    text =
        replace(program, "@RTDIR@" => dir) * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for (id, g) in cases
        ])
    f = joinpath(dir, "rd2.pl")
    write(f, text)
    return f, names
end
"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's. A Julia exception out of a row is its line: `jlerr <type> <what>`."
function _bl_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_BL}()
    ld = LK.PL_local_data{_BL}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _bl_enc(ball::_BL)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_bls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        rld = LK.PL_local_data{_BL}(gd)        # a fresh engine per row: a Julia exception leaves no frame behind
        try
            fid = LK.PL_open_foreign_frame(rld)
            a = LK.PL_new_term_refs(rld, 1)
            LK.putSlotValue!(rld, a + 1, mk_var(_BL, LK.fresh_var_keys!(1)), LK.PutVarMap())
            qid = LK.PL_open_query(
                gd, rld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
            )
            n = 0
            while (n += 1) <= 50
                rc = LK.PL_next_solution(gd, rld, qid)
                if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                    push!(
                        sols,
                        _bl_enc(
                            mk_expr(_BL, _BL[_bls(name), lk_answers(rld, (a:a)...)...])
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



@testset "<type>(...) read with blob(dead|resolve), its written form and its type as swipl's (bl01-bl80)" begin
    mktempdir() do dir
        f, names = _bl_file(dir, _BL_HELPERS * _BL_PROGRAM, _BL_CASES)
        kl = _bl_kernel(f, names)
        @test length(kl) == length(_BL_PINNED)
        for (k, p) in zip(kl, _BL_PINNED)
            k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
            @test k == p
        end
    end
    # not vacuous: the pins hold answers and raised errors, and the rows that fail (no answer at all)
    @test length(_BL_PINNED) == length(_BL_CASES) + 1
    @test _BL_PINNED[1] == "ok"
    @test count(l -> occursin("c[111,107]/1(", l), _BL_PINNED) >= 14
    @test count(l -> occursin(" c[114,97,105,115,101,100]/", l), _BL_PINNED) >= 18
    @test count(l -> occursin("c[114]/4(", l), _BL_PINNED) >= 20       # the `r/4` answers of bl_show/2
    @test count(l -> occursin("c[114,97,105,115,101,100]/2(c[115,121,110,116,97,120", l), _BL_PINNED) >= 10   # the syntax errors
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_BL_PINNED) == length(_BL_CASES) + 1

    if swipl === nothing
        @info "RD2 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        mktempdir() do dir
            f, names = _bl_file(dir, _BL_HELPERS * _BL_PROGRAM, _BL_CASES)
            @test _bl_swipl_lines(f, names) == _BL_PINNED
        end
    end
end
