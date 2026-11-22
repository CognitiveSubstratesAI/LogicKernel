# ORIGINAL: STREAMS-A's gate — the Edinburgh and ISO byte and character predicates of pl-file.c (swipl-devel 18168e62), against swipl 10.1.20
# test/files/test_streams_a_swipl.jl — prefix `_SA` / `_sa_`. get/1,2, get0/1,2 (pl-file.c:3548-3560, the get_code pair), get_char/1, skip/1, put/1,2,
# put_byte/1,2, get_byte/1,2, peek_byte/1,2, peek_code/1,2, peek_char/1,2, peek_string/3, set_input/1, set_output/1, flush_output/0, fill_buffer/1,
# copy_stream_data/2,3, byte_count/2 and character_count/2, over file streams (text and binary) and string and memory streams (`open_string/2`,
# `with_output_to/2`), the errors included:
#   * A PROGRAM consulted by the kernel's loader — helper clauses over a data file and an output file — and cases `t_<id>(R)` run IN ORDER in one
#     database, each wrapped in `catch(Goal, error(F, _), R = raised(F))` (a stream blob in F becomes '<stream>'; no row answers a blob or a path).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20 at the pin 18168e62, two byte-identical runs under LC_ALL=C.UTF-8, 2026-11-15, evidence/STREAMS-A/
#     streams_a_rows.out); with `swipl` on PATH the live answers are compared with the pins too. A row that answers nothing is a FAILED goal (no answer line).
#   * Written edit-only (no julia in the writing piece): NOT RUN when committed; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream layer (src/os/pl-file.jl, src/os/pl-stream.jl) over the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _SA = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_sas(x) = lk_sym(_SA, Symbol(x))

_sa_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _sa_enc(t::_SA, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _sa_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _sa_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _sa_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_sa_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _SA_DRIVER = raw"""
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
function _sa_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _SA_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: helper clauses over a data file (`@DATA@`, "abc\nxyz\nlast line\n") and an output file (`@OUT@`), both substituted at run time.
const _SA_PROGRAM = raw"""
datafile('@DATA@').
outfile('@OUT@').
ro(S) :- datafile(F), open(F, read, S).
rb(S) :- datafile(F), open(F, read, S, [type(binary)]).
ra(S, A) :- datafile(F), open(F, read, S, [alias(A)]).
wo(S) :- outfile(F), open(F, write, S).
wb(S) :- outfile(F), open(F, write, S, [type(binary)]).
rdo(S) :- outfile(F), open(F, read, S).
rbo(S) :- outfile(F), open(F, read, S, [type(binary)]).
wbytes(L) :- wb(S), forall(member(B, L), put_byte(S, B)), close(S).
codes(S, L) :- get_code(S, C), ( C == -1 -> L = [] ; L = [C|T], codes(S, T) ).
rdall(L) :- rdo(S), codes(S, L), close(S).
rdout(L) :- rdo(S), get_char(S, A), get_char(S, B), get_char(S, C), close(S), L = [A, B, C].
str(T, S) :- open_string(T, S).
strc(Cs, S) :- atom_codes(A, Cs), open_string(A, S).
ws(G, S) :- with_output_to(string(S), G).
inp(T, O, S) :- current_input(O), open_string(T, S), set_input(S).
outp(O, S) :- set_input(O), close(S).
nb(F, F1) :- F =.. [N|As], nbs(As, Bs), F1 =.. [N|Bs].
nbs([], []).
nbs([A|As], [B|Bs]) :- ( blob(A, stream) -> B = '<stream>' ; B = A ), nbs(As, Bs).
cerr(G, R) :- catch(( G -> R = ok ; R = failed ), error(F, _), ( nb(F, F1), R = raised(F1) )).
"""

# (id, goal), run IN ORDER
const _SA_CASES = [
    ("sa001", raw"ro(S), get(S, A), get(S, B), close(S), R = [A, B]"),
    ("sa002", raw"ro(S), skip(S, 99), get(S, A), get(S, B), close(S), R = A-B"),
    ("sa003", raw"str('  \n\t q', S), get(S, A), close(S), R = A"),
    ("sa004", raw"str('   ', S), get(S, A), close(S), R = A"),
    ("sa005", raw"str('', S), get(S, A), get(S, B), close(S), R = A-B"),
    ("sa006", raw"str(ab, S), get(S, 97), close(S), R = ok"),
    ("sa007", raw"str(ab, S), ( get(S, 98) -> R0 = yes ; R0 = no ), close(S), R = R0"),
    ("sa008", raw"str(ab, S), cerr(get(S, a), R0), close(S), R = R0"),
    ("sa009", raw"str(ab, S), cerr(get(S, foo), R0), close(S), R = R0"),
    ("sa010", raw"cerr(get(_, _), R)"),
    ("sa011", raw"cerr(get(nosuch, _), R)"),
    ("sa012", raw"wo(S), cerr(get(S, _), R0), close(S), R = R0"),
    ("sa013", raw"rb(S), cerr(get(S, _), R0), close(S), R = R0"),
    ("sa014", raw"inp('  x', O, S), get(A), outp(O, S), R = A"),
    ("sa015", raw"inp('  x', O, S), cerr(get(1.5), R0), outp(O, S), R = R0"),
    ("sa016", raw"str(ab, S), get0(S, A), get0(S, B), get0(S, C), close(S), R = [A, B, C]"),
    ("sa017", raw"strc([233, 8364], S), get0(S, A), get0(S, B), close(S), R = A-B"),
    ("sa018", raw"inp(xy, O, S), get0(A), get0(B), get0(C), outp(O, S), R = [A, B, C]"),
    ("sa019", raw"inp(xy, O, S), get_char(A), get_char(B), get_char(C), outp(O, S), R = [A, B, C]"),
    ("sa020", raw"inp(x, O, S), cerr(get_char(1), R0), outp(O, S), R = R0"),
    ("sa021", raw"inp(x, O, S), cerr(get_char(ab), R0), outp(O, S), R = R0"),
    ("sa022", raw"inp(abcdef, O, S), skip(99), get_char(C), outp(O, S), R = C"),
    ("sa023", raw"inp(abcdef, O, S), skip(c), get_char(C), outp(O, S), R = C"),
    ("sa024", raw"inp(abc, O, S), skip(122), get_char(C), outp(O, S), R = C"),
    ("sa025", raw"cerr(skip(_), R)"),
    ("sa026", raw"cerr(skip(ab), R)"),
    ("sa027", raw"ws((put(104), put(105)), S), R = S"),
    ("sa028", raw"ws((put(97), put(b), put(99)), S), R = S"),
    ("sa029", raw"ws(put(8364), S), R = S"),
    ("sa030", raw"cerr(put(_), R)"),
    ("sa031", raw"cerr(put(-1), R)"),
    ("sa032", raw"cerr(put(ab), R)"),
    ("sa033", raw"cerr(put(1.5), R)"),
    ("sa034", raw"ws((current_output(O), put(O, 120), put(O, 121)), S), R = S"),
    ("sa035", raw"ro(S), cerr(put(S, 65), R0), close(S), R = R0"),
    ("sa036", raw"wb(S), cerr(put(S, 65), R0), close(S), R = R0"),
    ("sa037", raw"cerr(put(nosuch, 65), R)"),
    ("sa038", raw"wo(S), put(S, 65), put(S, 10), close(S), rdout(R)"),
    ("sa039", raw"wbytes([1, 255, 0]), rbo(S), get_byte(S, A), get_byte(S, B), get_byte(S, C), get_byte(S, D), close(S), R = [A, B, C, D]"),
    ("sa040", raw"wb(S), cerr(put_byte(S, 256), R0), close(S), R = R0"),
    ("sa041", raw"wb(S), cerr(put_byte(S, -1), R0), close(S), R = R0"),
    ("sa042", raw"wb(S), cerr(put_byte(S, a), R0), close(S), R = R0"),
    ("sa043", raw"wb(S), cerr(put_byte(S, _), R0), close(S), R = R0"),
    ("sa044", raw"wo(S), cerr(put_byte(S, 65), R0), close(S), R = R0"),
    ("sa045", raw"ro(S), cerr(put_byte(S, 65), R0), close(S), R = R0"),
    ("sa046", raw"cerr(put_byte(65), R)"),
    ("sa047", raw"cerr(put_byte(256), R)"),
    ("sa048", raw"wb(S), put_byte(S, 7), byte_count(S, B), character_count(S, C), close(S), R = B-C"),
    ("sa049", raw"wb(S), put_byte(S, 7), put_byte(S, 8), close(S), cerr(put_byte(S, 9), R)"),
    ("sa050", raw"wbytes([5, 6]), rbo(S), peek_byte(S, A), peek_byte(S, B), get_byte(S, C), peek_byte(S, D), get_byte(S, E), peek_byte(S, F), close(S), R = [A, B, C, D, E, F]"),
    ("sa051", raw"wbytes([5]), rbo(S), peek_byte(S, A), byte_count(S, B), get_byte(S, C), byte_count(S, D), close(S), R = [A, B, C, D]"),
    ("sa052", raw"ro(S), cerr(get_byte(S, _), R0), close(S), R = R0"),
    ("sa053", raw"wo(S), cerr(get_byte(S, _), R0), close(S), R = R0"),
    ("sa054", raw"wbytes([5]), rbo(S), cerr(get_byte(S, a), R0), close(S), R = R0"),
    ("sa055", raw"wbytes([5]), rbo(S), cerr(get_byte(S, 300), R0), close(S), R = R0"),
    ("sa056", raw"wbytes([5]), rbo(S), get_byte(S, 5), get_byte(S, -1), close(S), R = ok"),
    ("sa057", raw"wbytes([5]), rbo(S), set_stream(S, eof_action(error)), get_byte(S, _), get_byte(S, E1), cerr(get_byte(S, _), R0), close(S), R = E1-R0"),
    ("sa058", raw"cerr(get_byte(_), R)"),
    ("sa059", raw"inp(x, O, S), cerr(get_byte(_), R0), outp(O, S), R = R0"),
    ("sa060", raw"wbytes([9, 8]), current_input(O), rbo(S), set_input(S), get_byte(A), peek_byte(B), get_byte(C), set_input(O), close(S), R = [A, B, C]"),
    ("sa061", raw"wbytes([9]), rbo(S), set_stream(S, buffer(false)), cerr(peek_byte(S, _), R0), close(S), R = R0"),
    ("sa062", raw"rb(S), cerr(get_byte(S, 1), R0), close(S), R = R0"),
    ("sa063", raw"wbytes([200]), rbo(S), peek_byte(S, A), close(S), R = A"),
    ("sa064", raw"ro(S), peek_code(S, A), get_code(S, B), peek_code(S, C), close(S), R = [A, B, C]"),
    ("sa065", raw"str('', S), peek_code(S, A), close(S), R = A"),
    ("sa066", raw"strc([233, 8364], S), peek_code(S, A), get_code(S, _), peek_code(S, B), close(S), R = A-B"),
    ("sa067", raw"str(a, S), ( peek_code(S, 97) -> R0 = yes ; R0 = no ), close(S), R = R0"),
    ("sa068", raw"str('', S), ( peek_code(S, -1) -> R0 = yes ; R0 = no ), close(S), R = R0"),
    ("sa069", raw"wo(S), cerr(peek_code(S, _), R0), close(S), R = R0"),
    ("sa070", raw"rb(S), cerr(peek_code(S, _), R0), close(S), R = R0"),
    ("sa071", raw"ro(S), cerr(peek_byte(S, _), R0), close(S), R = R0"),
    ("sa072", raw"ro(S), set_stream(S, buffer(false)), cerr(peek_code(S, _), R0), close(S), R = R0"),
    ("sa073", raw"inp(xy, O, S), peek_char(A), get_char(B), peek_char(C), outp(O, S), R = [A, B, C]"),
    ("sa074", raw"inp(xy, O, S), peek_code(A), get_code(B), peek_code(C), outp(O, S), R = [A, B, C]"),
    ("sa075", raw"str(a, S), cerr(peek_char(S, 1), R0), close(S), R = R0"),
    ("sa076", raw"str(a, S), cerr(peek_char(S, foo), R0), close(S), R = R0"),
    ("sa077", raw"ro(S), peek_code(S, _), character_count(S, A), line_count(S, B), close(S), R = A-B"),
    ("sa078", raw"ro(S), skip(S, 99), peek_code(S, _), line_count(S, L), line_position(S, P), close(S), R = L-P"),
    ("sa079", raw"ro(S), cerr(peek_code(S, 1.5), R0), close(S), R = R0"),
    ("sa080", raw"wo(S), close(S), cerr(peek_code(S, _), R)"),
    ("sa081", raw"cerr(peek_code(_, _), R)"),
    ("sa082", raw"current_input(O), str(q, S), set_input(S), current_input(C), ( C == S -> A = same ; A = other ), set_input(O), close(S), R = A"),
    ("sa083", raw"ro(S), cerr(set_output(S), R0), close(S), R = R0"),
    ("sa084", raw"wo(S), cerr(set_input(S), R0), close(S), R = R0"),
    ("sa085", raw"cerr(set_input(_), R)"),
    ("sa086", raw"cerr(set_input(nosuch), R)"),
    ("sa087", raw"cerr(set_output(foo(x)), R)"),
    ("sa088", raw"current_output(O), wo(S), set_output(S), put(104), put(105), set_output(O), close(S), rdout(R)"),
    ("sa089", raw"current_input(O), ra(S, zzi), set_input(zzi), current_input(C), ( C == S -> R0 = same ; R0 = other ), set_input(O), close(S), R = R0"),
    ("sa090", raw"wo(S), close(S), cerr(set_output(S), R)"),
    ("sa091", raw"current_output(O), wo(S), set_output(S), put(65), flush_output, set_output(O), close(S), rdout(R)"),
    ("sa092", raw"flush_output, R = ok"),
    ("sa093", raw"current_output(O), wo(S), set_output(S), current_output(C), ( C == S -> A = same ; A = other ), set_output(O), close(S), current_output(D), ( D == O -> B = same ; B = other ), R = A-B"),
    ("sa094", raw"current_output(O), wo(S), set_output(S), tab(2), put_char(x), set_output(O), close(S), rdout(R)"),
    ("sa095", raw"ro(S), fill_buffer(S), get_char(S, A), close(S), R = A"),
    ("sa096", raw"wo(S), cerr(fill_buffer(S), R0), close(S), R = R0"),
    ("sa097", raw"ro(S), set_stream(S, buffer(false)), cerr(fill_buffer(S), R0), close(S), R = R0"),
    ("sa098", raw"str('', S), cerr(fill_buffer(S), R0), close(S), R = R0"),
    ("sa099", raw"str(hello, S), fill_buffer(S), peek_code(S, A), close(S), R = A"),
    ("sa100", raw"cerr(fill_buffer(_), R)"),
    ("sa101", raw"ro(S), fill_buffer(S), fill_buffer(S), get_char(S, A), close(S), R = A"),
    ("sa102", raw"str(hello, I), ws((current_output(O), copy_stream_data(I, O)), S), close(I), R = S"),
    ("sa103", raw"str(hello, I), ws((current_output(O), copy_stream_data(I, O, 3)), S), get_char(I, C), close(I), R = S-C"),
    ("sa104", raw"str(hello, I), ws((current_output(O), copy_stream_data(I, O, 0)), S), get_char(I, C), close(I), R = S-C"),
    ("sa105", raw"str(hello, I), ws((current_output(O), copy_stream_data(I, O, 100)), S), close(I), R = S"),
    ("sa106", raw"str(hello, I), ws((current_output(O), copy_stream_data(I, O, -1)), S), get_char(I, C), close(I), R = S-C"),
    ("sa107", raw"str(hello, I), cerr(ws((current_output(O), copy_stream_data(I, O, a)), _), R0), close(I), R = R0"),
    ("sa108", raw"str(hello, I), cerr(ws((current_output(O), copy_stream_data(I, O, _)), _), R0), close(I), R = R0"),
    ("sa109", raw"ro(I), wo(O), copy_stream_data(I, O), close(I), close(O), rdall(R)"),
    ("sa110", raw"strc([233, 8364, 120], I), wo(O), copy_stream_data(I, O), close(I), close(O), rdall(R)"),
    ("sa111", raw"wo(O), cerr(copy_stream_data(O, O), R0), close(O), R = R0"),
    ("sa112", raw"ro(I), cerr(copy_stream_data(I, I), R0), close(I), R = R0"),
    ("sa113", raw"wbytes([65, 66]), rbo(I), ws((current_output(O), copy_stream_data(I, O)), S), close(I), R = S"),
    ("sa114", raw"cerr(copy_stream_data(_, _), R)"),
    ("sa115", raw"cerr(copy_stream_data(nosuch, user_output), R)"),
    ("sa116", raw"ro(I), wo(O), copy_stream_data(I, O, 5), close(I), close(O), rdall(R)"),
    ("sa117", raw"ro(I), wo(O), copy_stream_data(I, O, 4), get_char(I, C), close(I), close(O), rdall(L), R = L-C"),
    ("sa118", raw"str('hello world', S), peek_string(S, 5, T), get_char(S, C), close(S), R = T-C"),
    ("sa119", raw"str(abc, S), peek_string(S, 10, T), close(S), R = T"),
    ("sa120", raw"str(abc, S), peek_string(S, 0, T), close(S), R = T"),
    ("sa121", raw"ro(S), peek_string(S, 4, T), close(S), R = T"),
    ("sa122", raw"ro(S), get_char(S, _), peek_string(S, 2, T), get_char(S, C), close(S), R = T-C"),
    ("sa123", raw"ro(S), cerr(peek_string(S, a, _), R0), close(S), R = R0"),
    ("sa124", raw"ro(S), cerr(peek_string(S, -1, _), R0), close(S), R = R0"),
    ("sa125", raw"ro(S), cerr(peek_string(S, _, _), R0), close(S), R = R0"),
    ("sa126", raw"wo(S), cerr(peek_string(S, 1, _), R0), close(S), R = R0"),
    ("sa127", raw"strc([233, 8364, 120], S), peek_string(S, 2, T), string_codes(T, Cs), close(S), R = Cs"),
    ("sa128", raw"ro(S), peek_string(S, 100, T), get_char(S, C), close(S), string_length(T, N), R = N-C"),
    ("sa129", raw"str(abc, S), peek_string(S, 2, T), peek_string(S, 3, U), close(S), R = T-U"),
    ("sa130", raw"cerr(peek_string(nosuch, 1, _), R)"),
    ("sa131", raw"ro(S), peek_string(S, 2, ab), close(S), R = ok"),
    ("sa132", raw"ro(S), get_char(S, _), get_char(S, _), byte_count(S, B), character_count(S, C), close(S), R = B-C"),
    ("sa133", raw"strc([233, 8364], S), get_char(S, _), get_char(S, _), cerr((byte_count(S, B), character_count(S, C), R1 = B-C), R0), close(S), R = R1-R0"),
    ("sa134", raw"wo(S), put(S, 233), put(S, 8364), close(S), rdo(T), get_char(T, _), get_char(T, _), byte_count(T, B), character_count(T, C), close(T), R = B-C"),
    ("sa135", raw"cerr(byte_count(nosuch, _), R)"),
    ("sa136", raw"cerr(character_count(_, _), R)"),
    ("sa137", raw"str(ab, S), cerr(byte_count(S, _), R0), close(S), R = R0"),
    ("sa138", raw"ro(S), cerr(byte_count(S, a), R0), close(S), R = R0"),
    ("sa139", raw"ro(S), skip(S, 10), byte_count(S, B), character_count(S, C), line_count(S, L), close(S), R = [B, C, L]"),
    ("sa140", raw"ro(S), close(S), cerr(character_count(S, _), R)"),
    ("sa141", raw"wbytes([5, 6]), rbo(S), cerr(get_byte(S, -1), R0), get_byte(S, B), close(S), R = R0-B"),
    ("sa142", raw"wbytes([5, 6]), rbo(S), cerr(get_byte(S, end_of_file), R0), get_byte(S, B), close(S), R = R0-B")
]

# swipl 10.1.20 (pin 18168e62)'s answers to the program and cases above (the driver's lines; evidence/STREAMS-A/streams_a_rows.out)
const _SA_PINNED = [
    "ok",
    "t_sa001 c[116,95,115,97,48,48,49]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,nil)))",
    "t_sa002 c[116,95,115,97,48,48,50]/1(c[45]/2(i120,i121))",
    "t_sa003 c[116,95,115,97,48,48,51]/1(i113)",
    "t_sa004 c[116,95,115,97,48,48,52]/1(i-1)",
    "t_sa005 c[116,95,115,97,48,48,53]/1(c[45]/2(i-1,i-1))",
    "t_sa006 c[116,95,115,97,48,48,54]/1(a[111,107])",
    "t_sa007 c[116,95,115,97,48,48,55]/1(a[110,111])",
    "t_sa008 c[116,95,115,97,48,48,56]/1(a[102,97,105,108,101,100])",
    "t_sa009 c[116,95,115,97,48,48,57]/1(a[102,97,105,108,101,100])",
    "t_sa010 c[116,95,115,97,48,49,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa011 c[116,95,115,97,48,49,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_sa012 c[116,95,115,97,48,49,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa013 c[116,95,115,97,48,49,51]/1(a[111,107])",
    "t_sa014 c[116,95,115,97,48,49,52]/1(i120)",
    "t_sa015 c[116,95,115,97,48,49,53]/1(a[102,97,105,108,101,100])",
    "t_sa016 c[116,95,115,97,48,49,54]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i-1,nil))))",
    "t_sa017 c[116,95,115,97,48,49,55]/1(c[45]/2(i233,i8364))",
    "t_sa018 c[116,95,115,97,48,49,56]/1(c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i-1,nil))))",
    "t_sa019 c[116,95,115,97,48,49,57]/1(c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil))))",
    "t_sa020 c[116,95,115,97,48,50,48]/1(a[102,97,105,108,101,100])",
    "t_sa021 c[116,95,115,97,48,50,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[97,98])))",
    "t_sa022 c[116,95,115,97,48,50,50]/1(a[100])",
    "t_sa023 c[116,95,115,97,48,50,51]/1(a[100])",
    "t_sa024 c[116,95,115,97,48,50,52]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_sa025 c[116,95,115,97,48,50,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa026 c[116,95,115,97,48,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[97,98])))",
    "t_sa027 c[116,95,115,97,48,50,55]/1(s[104,105])",
    "t_sa028 c[116,95,115,97,48,50,56]/1(s[97,98,99])",
    "t_sa029 c[116,95,115,97,48,50,57]/1(s[8364])",
    "t_sa030 c[116,95,115,97,48,51,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa031 c[116,95,115,97,48,51,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i-1)))",
    "t_sa032 c[116,95,115,97,48,51,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[97,98])))",
    "t_sa033 c[116,95,115,97,48,51,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],f1.5)))",
    "t_sa034 c[116,95,115,97,48,51,52]/1(s[120,121])",
    "t_sa035 c[116,95,115,97,48,51,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa036 c[116,95,115,97,48,51,54]/1(a[111,107])",
    "t_sa037 c[116,95,115,97,48,51,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_sa038 c[116,95,115,97,48,51,56]/1(c[91,124,93]/2(a[65],c[91,124,93]/2(a[10],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil))))",
    "t_sa039 c[116,95,115,97,48,51,57]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i255,c[91,124,93]/2(i0,c[91,124,93]/2(i-1,nil)))))",
    "t_sa040 c[116,95,115,97,48,52,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,121,116,101],i256)))",
    "t_sa041 c[116,95,115,97,48,52,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,121,116,101],i-1)))",
    "t_sa042 c[116,95,115,97,48,52,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,121,116,101],a[97])))",
    "t_sa043 c[116,95,115,97,48,52,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa044 c[116,95,115,97,48,52,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[111,117,116,112,117,116],a[116,101,120,116,95,115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa045 c[116,95,115,97,48,52,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa046 c[116,95,115,97,48,52,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[111,117,116,112,117,116],a[116,101,120,116,95,115,116,114,101,97,109],a[99,117,114,114,101,110,116,95,111,117,116,112,117,116])))",
    "t_sa047 c[116,95,115,97,48,52,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,121,116,101],i256)))",
    "t_sa048 c[116,95,115,97,48,52,56]/1(c[45]/2(i1,i1))",
    "t_sa049 c[116,95,115,97,48,52,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa050 c[116,95,115,97,48,53,48]/1(c[91,124,93]/2(i5,c[91,124,93]/2(i5,c[91,124,93]/2(i5,c[91,124,93]/2(i6,c[91,124,93]/2(i6,c[91,124,93]/2(i-1,nil)))))))",
    "t_sa051 c[116,95,115,97,48,53,49]/1(c[91,124,93]/2(i5,c[91,124,93]/2(i0,c[91,124,93]/2(i5,c[91,124,93]/2(i1,nil)))))",
    "t_sa052 c[116,95,115,97,48,53,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[116,101,120,116,95,115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa053 c[116,95,115,97,48,53,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa054 c[116,95,115,97,48,53,52]/1(a[102,97,105,108,101,100])",
    "t_sa055 c[116,95,115,97,48,53,53]/1(a[102,97,105,108,101,100])",
    "t_sa056 c[116,95,115,97,48,53,54]/1(a[111,107])",
    "t_sa057 c[116,95,115,97,48,53,55]/1(c[45]/2(i-1,c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[112,97,115,116,95,101,110,100,95,111,102,95,115,116,114,101,97,109],a[60,115,116,114,101,97,109,62]))))",
    "t_sa058 c[116,95,115,97,48,53,56]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[116,101,120,116,95,115,116,114,101,97,109],a[99,117,114,114,101,110,116,95,105,110,112,117,116])))",
    "t_sa059 c[116,95,115,97,48,53,57]/1(a[111,107])",
    "t_sa060 c[116,95,115,97,48,54,48]/1(c[91,124,93]/2(i9,c[91,124,93]/2(i8,c[91,124,93]/2(i8,nil))))",
    "t_sa061 c[116,95,115,97,48,54,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[112,101,101,107],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa062 c[116,95,115,97,48,54,50]/1(a[102,97,105,108,101,100])",
    "t_sa063 c[116,95,115,97,48,54,51]/1(i200)",
    "t_sa064 c[116,95,115,97,48,54,52]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i97,c[91,124,93]/2(i98,nil))))",
    "t_sa065 c[116,95,115,97,48,54,53]/1(i-1)",
    "t_sa066 c[116,95,115,97,48,54,54]/1(c[45]/2(i233,i8364))",
    "t_sa067 c[116,95,115,97,48,54,55]/1(a[121,101,115])",
    "t_sa068 c[116,95,115,97,48,54,56]/1(a[121,101,115])",
    "t_sa069 c[116,95,115,97,48,54,57]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa070 c[116,95,115,97,48,55,48]/1(a[111,107])",
    "t_sa071 c[116,95,115,97,48,55,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[116,101,120,116,95,115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa072 c[116,95,115,97,48,55,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[112,101,101,107],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa073 c[116,95,115,97,48,55,51]/1(c[91,124,93]/2(a[120],c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],nil))))",
    "t_sa074 c[116,95,115,97,48,55,52]/1(c[91,124,93]/2(i120,c[91,124,93]/2(i120,c[91,124,93]/2(i121,nil))))",
    "t_sa075 c[116,95,115,97,48,55,53]/1(a[102,97,105,108,101,100])",
    "t_sa076 c[116,95,115,97,48,55,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[102,111,111])))",
    "t_sa077 c[116,95,115,97,48,55,55]/1(c[45]/2(i0,i1))",
    "t_sa078 c[116,95,115,97,48,55,56]/1(c[45]/2(i1,i3))",
    "t_sa079 c[116,95,115,97,48,55,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],f1.5)))",
    "t_sa080 c[116,95,115,97,48,56,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa081 c[116,95,115,97,48,56,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa082 c[116,95,115,97,48,56,50]/1(a[115,97,109,101])",
    "t_sa083 c[116,95,115,97,48,56,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa084 c[116,95,115,97,48,56,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa085 c[116,95,115,97,48,56,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa086 c[116,95,115,97,48,56,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_sa087 c[116,95,115,97,48,56,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,111,114,95,97,108,105,97,115],c[102,111,111]/1(a[120]))))",
    "t_sa088 c[116,95,115,97,48,56,56]/1(c[91,124,93]/2(a[104],c[91,124,93]/2(a[105],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil))))",
    "t_sa089 c[116,95,115,97,48,56,57]/1(a[111,116,104,101,114])",
    "t_sa090 c[116,95,115,97,48,57,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa091 c[116,95,115,97,48,57,49]/1(c[91,124,93]/2(a[65],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],c[91,124,93]/2(a[101,110,100,95,111,102,95,102,105,108,101],nil))))",
    "t_sa092 c[116,95,115,97,48,57,50]/1(a[111,107])",
    "t_sa093 c[116,95,115,97,48,57,51]/1(c[45]/2(a[115,97,109,101],a[115,97,109,101]))",
    "t_sa094 c[116,95,115,97,48,57,52]/1(c[91,124,93]/2(a[32],c[91,124,93]/2(a[32],c[91,124,93]/2(a[120],nil))))",
    "t_sa095 c[116,95,115,97,48,57,53]/1(a[97])",
    "t_sa096 c[116,95,115,97,48,57,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa097 c[116,95,115,97,48,57,55]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[102,105,108,108,95,98,117,102,102,101,114],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa098 c[116,95,115,97,48,57,56]/1(a[111,107])",
    "t_sa099 c[116,95,115,97,48,57,57]/1(i104)",
    "t_sa100 c[116,95,115,97,49,48,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa101 c[116,95,115,97,49,48,49]/1(a[97])",
    "t_sa102 c[116,95,115,97,49,48,50]/1(s[104,101,108,108,111])",
    "t_sa103 c[116,95,115,97,49,48,51]/1(c[45]/2(s[104,101,108],a[108]))",
    "t_sa104 c[116,95,115,97,49,48,52]/1(c[45]/2(s[],a[104]))",
    "t_sa105 c[116,95,115,97,49,48,53]/1(s[104,101,108,108,111])",
    "t_sa106 c[116,95,115,97,49,48,54]/1(c[45]/2(s[],a[104]))",
    "t_sa107 c[116,95,115,97,49,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_sa108 c[116,95,115,97,49,48,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa109 c[116,95,115,97,49,48,57]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,nil)))))))))))))))))))",
    "t_sa110 c[116,95,115,97,49,49,48]/1(c[91,124,93]/2(i233,c[91,124,93]/2(i8364,c[91,124,93]/2(i120,nil))))",
    "t_sa111 c[116,95,115,97,49,49,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa112 c[116,95,115,97,49,49,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa113 c[116,95,115,97,49,49,51]/1(s[65,66])",
    "t_sa114 c[116,95,115,97,49,49,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa115 c[116,95,115,97,49,49,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_sa116 c[116,95,115,97,49,49,54]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,nil))))))",
    "t_sa117 c[116,95,115,97,49,49,55]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,nil)))),a[120]))",
    "t_sa118 c[116,95,115,97,49,49,56]/1(c[45]/2(s[104,101,108,108,111],a[104]))",
    "t_sa119 c[116,95,115,97,49,49,57]/1(s[97,98,99])",
    "t_sa120 c[116,95,115,97,49,50,48]/1(s[])",
    "t_sa121 c[116,95,115,97,49,50,49]/1(s[97,98,99,10])",
    "t_sa122 c[116,95,115,97,49,50,50]/1(c[45]/2(s[98,99],a[98]))",
    "t_sa123 c[116,95,115,97,49,50,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_sa124 c[116,95,115,97,49,50,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_sa125 c[116,95,115,97,49,50,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa126 c[116,95,115,97,49,50,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa127 c[116,95,115,97,49,50,55]/1(c[91,124,93]/2(i233,c[91,124,93]/2(i8364,nil)))",
    "t_sa128 c[116,95,115,97,49,50,56]/1(c[45]/2(i18,a[97]))",
    "t_sa129 c[116,95,115,97,49,50,57]/1(c[45]/2(s[97,98],s[97,98,99]))",
    "t_sa130 c[116,95,115,97,49,51,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_sa131",
    "t_sa132 c[116,95,115,97,49,51,50]/1(c[45]/2(i2,i2))",
    "t_sa133 c[116,95,115,97,49,51,51]/1(c[45]/2(c[45]/2(i5,i2),a[111,107]))",
    "t_sa134 c[116,95,115,97,49,51,52]/1(c[45]/2(i5,i2))",
    "t_sa135 c[116,95,115,97,49,51,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_sa136 c[116,95,115,97,49,51,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sa137 c[116,95,115,97,49,51,55]/1(a[111,107])",
    "t_sa138 c[116,95,115,97,49,51,56]/1(a[102,97,105,108,101,100])",
    "t_sa139 c[116,95,115,97,49,51,57]/1(c[91,124,93]/2(i4,c[91,124,93]/2(i4,c[91,124,93]/2(i2,nil))))",
    "t_sa140 c[116,95,115,97,49,52,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_sa141 c[116,95,115,97,49,52,49]/1(c[45]/2(a[102,97,105,108,101,100],i6))",
    "t_sa142 c[116,95,115,97,49,52,50]/1(c[45]/2(a[102,97,105,108,101,100],i6))"
]

const _SA_DATA = "abc\nxyz\nlast line\n"

"The data file's text, and the program and cases as one file in `dir` (the data and output paths substituted); the case predicates' names."
function _sa_file(dir::String)::Tuple{String, Vector{String}}
    data = joinpath(dir, "data.txt")
    write(data, _SA_DATA)
    prog = replace(
        replace(_SA_PROGRAM, "@DATA@" => data), "@OUT@" => joinpath(dir, "out.txt")
    )
    names = ["t_$(id)" for (id, _) in _SA_CASES]
    text =
        prog * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).\n"
            for
            (id, g) in _SA_CASES
        ])
    f = joinpath(dir, "streams_a.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _sa_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_SA}()
    ld = LK.PL_local_data{_SA}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _sa_enc(ball::_SA)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_sas(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_SA, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _sa_enc(mk_expr(_SA, _SA[_sas(name), lk_answers(ld, (a:a)...)...]))
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

@testset "get/put/peek/get_byte/put_byte/set_input/set_output/fill_buffer/copy_stream_data/peek_string/byte_count as swipl's (sa001-sa142)" begin
    f, names = _sa_file(mktempdir())
    kl = _sa_kernel(f, names)
    @test length(kl) == length(_SA_PINNED)
    for (k, p) in zip(kl, _SA_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the pins hold raised errors (56), permission errors (20), type_error(byte, _) answers (4) and 1 failing row(s),
    # so the comparison can pass and can fail
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _SA_PINNED) == 56      # raised(…)
    @test count(l -> occursin("c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3", l), _SA_PINNED) == 20  # permission_error(…)
    @test count(l -> occursin("c[116,121,112,101,95,101,114,114,111,114]/2(a[98,121,116,101]", l), _SA_PINNED) == 4  # type_error(byte, _)
    @test count(l -> occursin(r"^t_sa\d+ *$", l), _SA_PINNED) == 1                    # failed rows
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_SA_PINNED) == length(_SA_CASES) + 1
    if swipl === nothing
        @info "STREAMS-A LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _sa_file(mktempdir())
        @test _sa_swipl_lines(f, names) == _SA_PINNED
    end
end
