# ORIGINAL: lane D (D-0501): the Edinburgh and byte stream predicates of pl-file.c against swipl 10.1.20 (pin 18168e62); UNTESTED when written (nothing compiled)
# test/core_lang/test_lane_d_swipl.jl — set_input/1, set_output/1, get/1,2, get0/1,2, get_char/1, get_byte/1,2, skip/1, put/1,2, put_byte/1,2,
# peek_byte/1,2, peek_code/1,2, peek_char/1, byte_count/2, character_count/2, flush_output/0 and (d070-d097) and open_null_stream/1 (d098-d108) and stream_pair/3 (d109-d127) and seek/4, set_stream_position/2, set_end_of_stream/1 (d128-d184) see/1, seen/0, seeing/1, tell/1, append/1, telling/1, told/0 (pl-file.c, pin lines 3455-3658, 5550, 5709-5811, 5967-6006).
#   * The harness is test_s2a_swipl.jl's: a PROGRAM consulted by the kernel's loader (helper clauses over a data file and an output file) and cases
#     `t_<id>(R)` run IN ORDER in one database, each wrapped in `catch(Goal, error(F, _), R = raised(F))` (a stream blob in F becomes '<stream>').
#   * Every answer line is swipl's, PINNED (swipl 10.1.20-1-g18168e629, two byte-identical runs, 2026-11-11, evidence/S2/lane_d_rows.out); with `swipl` on
#     PATH the live answers are compared with the pins too.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream layer (src/os/pl-file.jl, src/os/pl-stream.jl) over the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _LD = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_lds(x) = lk_sym(_LD, Symbol(x))

_ld_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _ld_enc(t::_LD, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ld_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ld_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ld_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ld_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _LD_DRIVER = raw"""
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
function _ld_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _LD_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: helper clauses over a data file (`@DATA@`, "abc\nxyz\nlast line\n") and an output file (`@OUT@`), both substituted at run time.
const _LD_PROGRAM = raw"""
datafile('@DATA@').
outfile('@OUT@').
ro(S) :- datafile(F), open(F, read, S).
rb(S) :- datafile(F), open(F, read, S, [type(binary)]).
ra(S, A) :- datafile(F), open(F, read, S, [alias(A)]).
wo(S) :- outfile(F), open(F, write, S).
nb(F, F1) :- F =.. [N|As], nbs(As, Bs), F1 =.. [N|Bs].
nbs([], []).
nbs([A|As], [B|Bs]) :- ( blob(A, stream) -> B = '<stream>' ; B = A ), nbs(As, Bs).
cerr(G, R) :- catch(( G -> R = ok ; R = failed ), error(F, _), ( nb(F, F1), R = raised(F1) )).
has(S, P, R) :- ( '$stream_property'(S, P) -> R = yes ; R = no ).
sp(S, P, R) :- ( '$stream_property'(S, P) -> R = P ; R = none ).
fnp(S, R) :- '$stream_property'(S, file_name(F)), datafile(D), ( F == D -> R = same ; R = F ).
mem(X, [X|_]) :- !.
mem(X, [_|T]) :- mem(X, T).
keep([], _, []).
keep([P|Ps], Ns, K) :- functor(P, N, _), ( mem(N, Ns) -> K = [P|K1] ; K = K1 ), keep(Ps, Ns, K1).
hasp([S0-_|_], S) :- S0 == S, !.
hasp([_|T], S) :- hasp(T, S).
cnt(L, N) :- '$skip_list'(N, L, _).
wb(S) :- outfile(F), open(F, write, S, [type(binary)]).
rall(S, L) :- get_code(S, C), ( C == -1 -> L = [] ; L = [C|T], rall(S, T) ).
outtext(T) :- outfile(F), open(F, read, S), rall(S, Cs), close(S), atom_codes(T, Cs).
rbyt(S, L) :- get_byte(S, C), ( C == -1 -> L = [] ; L = [C|T], rbyt(S, T) ).
outbytes(L) :- outfile(F), open(F, read, S, [type(binary)]), rbyt(S, L), close(S).
drain(S) :- get_byte(S, C), ( C == -1 -> true ; drain(S) ).
"""

# (id, goal), run IN ORDER
const _LD_CASES = [
    ("d001", raw"ro(S), get(S, A), get(S, B), close(S), R = A-B"),
    ("d002", raw"ro(S), get_code(S, _), get_code(S, _), get_code(S, _), get(S, C), close(S), R = C"),
    ("d003", raw"ro(S), skip(S, 126), get(S, C), close(S), R = C"),
    ("d004", raw"ro(S), cerr(get(S, foo), R0), close(S), R = R0"),
    ("d005", raw"ro(S), cerr(get(S, 1.5), R0), close(S), R = R0"),
    ("d006", raw"cerr(get(nostream, _), R)"),
    ("d007", raw"current_input(O), ro(S), set_input(S), get(C), set_input(O), close(S), R = C"),
    ("d008", raw"ro(S), cerr(get(S, 98), R0), close(S), R = R0"),
    ("d009", raw"wo(S), cerr(get(S, _), R0), close(S), R = R0"),
    ("d010", raw"rb(S), cerr(get(S, _), R0), close(S), R = R0"),
    ("d011", raw"ro(S), get0(S, A), get0(S, B), close(S), R = A-B"),
    ("d012", raw"current_input(O), ro(S), set_input(S), get0(C), set_input(O), close(S), R = C"),
    ("d013", raw"current_input(O), ro(S), set_input(S), get_char(C), set_input(O), close(S), R = C"),
    ("d014", raw"current_input(O), ro(S), set_input(S), skip(0'z), get_char(C), set_input(O), close(S), R = C"),
    ("d015", raw"current_input(O), ro(S), set_input(S), skip(0'y), get_code(C), set_input(O), close(S), R = C"),
    ("d016", raw"current_input(O), ro(S), set_input(S), cerr(skip(foo), R0), set_input(O), close(S), R = R0"),
    ("d017", raw"wo(S), put(S, 0'a), put(S, 98), close(S), outtext(T), R = T"),
    ("d018", raw"wo(S), put(S, b), put(S, 0'c), close(S), outtext(T), R = T"),
    ("d019", raw"wo(S), cerr(put(S, foo), R0), close(S), R = R0"),
    ("d020", raw"wo(S), cerr(put(S, _), R0), close(S), R = R0"),
    ("d021", raw"wo(S), cerr(put(S, -5), R0), close(S), R = R0"),
    ("d022", raw"current_output(O), wo(S), set_output(S), put(0'q), put(0'r), set_output(O), close(S), outtext(T), R = T"),
    ("d023", raw"ro(S), cerr(put(S, 0'a), R0), close(S), R = R0"),
    ("d024", raw"cerr(put(nostream, 0'a), R)"),
    ("d025", raw"wb(S), put_byte(S, 65), put_byte(S, 255), put_byte(S, 0), close(S), outbytes(L), R = L"),
    ("d026", raw"wb(S), cerr(put_byte(S, 256), R0), close(S), R = R0"),
    ("d027", raw"wb(S), cerr(put_byte(S, -1), R0), close(S), R = R0"),
    ("d028", raw"wb(S), cerr(put_byte(S, a), R0), close(S), R = R0"),
    ("d029", raw"wb(S), cerr(put_byte(S, _), R0), close(S), R = R0"),
    ("d030", raw"wo(S), cerr(put_byte(S, 65), R0), close(S), R = R0"),
    ("d031", raw"current_output(O), wb(S), set_output(S), put_byte(66), put_byte(67), set_output(O), close(S), outbytes(L), R = L"),
    ("d032", raw"cerr(put_byte(nostream, 65), R)"),
    ("d033", raw"rb(S), get_byte(S, A), get_byte(S, B), close(S), R = A-B"),
    ("d034", raw"rb(S), drain(S), get_byte(S, A), get_byte(S, B), close(S), R = A-B"),
    ("d035", raw"ro(S), cerr(get_byte(S, _), R0), close(S), R = R0"),
    ("d036", raw"rb(S), cerr(get_byte(S, foo), R0), close(S), R = R0"),
    ("d037", raw"rb(S), cerr(get_byte(S, 98), R0), close(S), R = R0"),
    ("d038", raw"rb(S), cerr(get_byte(S, 97), R0), close(S), R = R0"),
    ("d039", raw"current_input(O), rb(S), set_input(S), get_byte(B), set_input(O), close(S), R = B"),
    ("d040", raw"cerr(get_byte(nostream, _), R)"),
    ("d041", raw"rb(S), peek_byte(S, A), get_byte(S, B), byte_count(S, N), close(S), R = A-B-N"),
    ("d042", raw"rb(S), peek_byte(S, A), peek_byte(S, B), close(S), R = A-B"),
    ("d043", raw"rb(S), drain(S), peek_byte(S, A), close(S), R = A"),
    ("d044", raw"ro(S), cerr(peek_byte(S, _), R0), close(S), R = R0"),
    ("d045", raw"current_input(O), rb(S), set_input(S), peek_byte(A), get_byte(B), set_input(O), close(S), R = A-B"),
    ("d046", raw"ro(S), peek_code(S, A), get_code(S, B), close(S), R = A-B"),
    ("d047", raw"ro(S), peek_char(S, A), get_char(S, B), close(S), R = A-B"),
    ("d048", raw"current_input(O), ro(S), set_input(S), peek_code(A), peek_char(C), get_code(B), set_input(O), close(S), R = A-C-B"),
    ("d049", raw"current_input(O), ro(S), set_input(S), peek_char(A), get_char(B), set_input(O), close(S), R = A-B"),
    ("d050", raw"rb(S), cerr(peek_code(S, _), R0), close(S), R = R0"),
    ("d051", raw"ro(S), cerr(peek_char(S, 1), R0), close(S), R = R0"),
    ("d052", raw"ro(S), cerr(peek_code(S, 0'b), R0), close(S), R = R0"),
    ("d053", raw"ro(S), get_code(S, _), get_code(S, _), byte_count(S, B), character_count(S, C), close(S), R = B-C"),
    ("d054", raw"cerr(byte_count(nostream, _), R)"),
    ("d055", raw"cerr(character_count(nostream, _), R)"),
    ("d056", raw"ro(S), cerr(byte_count(S, foo), R0), close(S), R = R0"),
    ("d057", raw"current_input(O), ro(S), set_input(S), current_input(X), set_input(O), close(S), ( X == S -> R = same ; R = other )"),
    ("d058", raw"current_output(O), wo(S), set_output(S), current_output(X), set_output(O), close(S), ( X == S -> R = same ; R = other )"),
    ("d059", raw"cerr(set_input(nostream), R)"),
    ("d060", raw"cerr(set_output(nostream), R)"),
    ("d061", raw"wo(S), cerr(set_input(S), R0), close(S), R = R0"),
    ("d062", raw"ro(S), cerr(set_output(S), R0), close(S), R = R0"),
    ("d063", raw"cerr(set_input(_), R)"),
    ("d064", raw"cerr(set_output(_), R)"),
    ("d065", raw"rb(S), cerr(set_input(S), R0), close(S), R = R0"),
    ("d066", raw"flush_output, R = ok"),
    ("d067", raw"current_output(O), wo(S), set_output(S), put(0'x), flush_output, set_output(O), close(S), outtext(T), R = T"),
    ("d068", raw"outfile(F), open(F, write, W, [encoding(utf8)]), put(W, 8364), close(W), open(F, read, S, [encoding(utf8)]), get_code(S, C), byte_count(S, B), character_count(S, N), close(S), R = C-B-N"),
    ("d069", raw"outfile(F), open(F, write, W, [encoding(utf8)]), put(W, 8364), close(W), open(F, read, S, [type(binary)]), peek_byte(S, B), get_byte(S, B2), byte_count(S, N), close(S), R = B-B2-N"),
    ("d070", raw"datafile(F), see(F), get_code(C), seen, R = C"),
    ("d071", raw"datafile(F), see(F), seeing(S), ( blob(S, stream) -> X = stream ; X = S ), seen, R = X"),
    ("d072", raw"current_input(O), datafile(F), see(F), seen, current_input(N), ( O == N -> R = same ; R = diff )"),
    ("d073", raw"seeing(X), R = X"),
    ("d074", raw"see(user), seeing(X), R = X"),
    ("d075", raw"datafile(F), see(F), get_code(A), see(F), get_code(B), seen, R = A-B"),
    ("d076", raw"datafile(F), see(F), get_code(_), seeing(S), see(user), see(S), get_code(C), seen, R = C"),
    ("d077", raw"cerr(see(lane_d_no_such_file), R)"),
    ("d078", raw"cerr(see(_), R)"),
    ("d079", raw"cerr(see(f(x)), R)"),
    ("d080", raw"cerr(see(1), R)"),
    ("d081", raw"seen, R = ok"),
    ("d082", raw"outfile(F), tell(F), put_char(a), write(bcd), told, outtext(T), R = T"),
    ("d083", raw"outfile(F), tell(F), telling(S), ( blob(S, stream) -> X = stream ; X = S ), told, R = X"),
    ("d084", raw"telling(X), R = X"),
    ("d085", raw"tell(user), telling(X), R = X"),
    ("d086", raw"outfile(F), tell(F), write(a), told, append(F), write(b), told, outtext(T), R = T"),
    ("d087", raw"outfile(F), tell(F), write(a), tell(F), write(b), told, outtext(T), R = T"),
    ("d088", raw"current_output(O), outfile(F), tell(F), told, current_output(N), ( O == N -> R = same ; R = diff )"),
    ("d089", raw"cerr(tell(_), R)"),
    ("d090", raw"cerr(tell(f(x)), R)"),
    ("d091", raw"cerr(append(_), R)"),
    ("d092", raw"wo(S), tell(S), write(z), told, outtext(T), R = T"),
    ("d093", raw"cerr(tell('/lane_d_no_such_dir/x'), R)"),
    ("d094", raw"outfile(F), open(F, write, _, [alias(lane_d_al)]), tell(lane_d_al), write(q), told, outtext(T), R = T"),
    ("d095", raw"ra(_, lane_d_a2), see(lane_d_a2), get_code(C), seen, R = C"),
    ("d096", raw"outfile(F), tell(F), write(a), told, tell(F), write(b), told, outtext(T), R = T"),
    ("d097", raw"datafile(F), ro(S), get_code(S, _), see(F), get_code(C), seen, catch(close(S), _, true), R = C"),
    ("d098", raw"open_null_stream(S), write(S, hello), character_count(S, N), close(S), R = N"),
    ("d099", raw"open_null_stream(S), write(S, ab), nl(S), write(S, cde), line_count(S, L), line_position(S, P), close(S), R = L-P"),
    ("d100", raw"open_null_stream(S), ( blob(S, stream) -> R0 = yes ; R0 = no ), close(S), R = R0"),
    ("d101", raw"open_null_stream(S), cerr(get_char(S, _), R0), close(S), R = R0"),
    ("d102", raw"open_null_stream(S), '$stream_property'(S, encoding(E)), close(S), R = E"),
    ("d103", raw"open_null_stream(S), write(S, 'é€'), character_count(S, N), byte_count(S, B), close(S), R = N-B"),
    ("d104", raw"open_null_stream(S), '$stream_property'(S, mode(M)), close(S), R = M"),
    ("d105", raw"open_null_stream(S), sp(S, buffer(_), R0), close(S), R = R0"),
    ("d106", raw"cerr(open_null_stream(foo), R)"),
    ("d107", raw"open_null_stream(S), close(S), cerr(write(S, x), R0), R = R0"),
    ("d108", raw"open_null_stream(S), put_byte(S, 65) -> R = ok ; R = failed"),
    ("d109", raw"ro(I), wo(O), stream_pair(P, I, O), ( blob(P, stream) -> R0 = yes ; R0 = no ), close(P), R = R0"),
    ("d110", raw"ro(I), wo(O), stream_pair(P, I, O), stream_pair(P, I2, O2), ( I == I2, O == O2 -> R0 = same ; R0 = diff ), close(P), R = R0"),
    ("d111", raw"ro(I), wo(O), stream_pair(P, I, O), get_code(P, C), close(P), R = C"),
    ("d112", raw"ro(I), wo(O), stream_pair(P, I, O), put_char(P, a), close(P), outtext(T), R = T"),
    ("d113", raw"cerr(stream_pair(foo, _, _), R)"),
    ("d114", raw"ro(I), cerr(stream_pair(_, I, I), R0), close(I), R = R0"),
    ("d115", raw"ro(I), stream_pair(I, A, B), ( A == I -> R0 = in ; R0 = other ), ( var(B) -> R1 = unbound ; R1 = bound ), close(I), R = R0-R1"),
    ("d116", raw"wo(O), stream_pair(O, A, B), ( B == O -> R0 = out ; R0 = other ), ( var(A) -> R1 = unbound ; R1 = bound ), close(O), R = R0-R1"),
    ("d117", raw"ro(I), wo(O), stream_pair(P, I, O), cerr(line_count(P, _), R0), close(P), R = R0"),
    ("d118", raw"set_prolog_flag(error_ambiguous_stream_pair, true), ro(I), wo(O), stream_pair(P, I, O), cerr(line_count(P, _), R0), set_prolog_flag(error_ambiguous_stream_pair, false), close(P), R = R0"),
    ("d119", raw"ro(I), wo(O), stream_pair(P, I, O), close(P), cerr(stream_pair(P, _, _), R0), R = R0"),
    ("d120", raw"ro(I), wo(O), stream_pair(P, I, O), close(P), cerr(get_code(P, _), R0), R = R0"),
    ("d121", raw"stream_pair(P, user_input, user_output), stream_pair(P, A, B), R = A-B"),
    ("d122", raw"cerr(stream_pair(_, _, _), R)"),
    ("d123", raw"ro(I), cerr(stream_pair(_, I, foo), R0), close(I), R = R0"),
    ("d124", raw"ro(I), wo(O), stream_pair(P, I, O), close(P), cerr(close(P), R0), R = R0"),
    ("d125", raw"ro(I), wo(O), stream_pair(P, I, O), close(I), cerr(get_code(P, _), R0), close(O), R = R0"),
    ("d126", raw"ro(I), wo(O), stream_pair(P, I, O), close(I), put_char(P, z), close(P), outtext(T), R = T"),
    ("d127", raw"ro(I), wo(O), stream_pair(P, I, O), get_code(I, _), get_code(I, _), get_code(I, _), get_code(I, _), line_count(P, N), close(P), R = N"),
    ("d128", raw"ro(S), seek(S, 4, bof, N), get_code(S, C), close(S), R = N-C"),
    ("d129", raw"ro(S), get_code(S, _), seek(S, 2, current, N), get_code(S, C), close(S), R = N-C"),
    ("d130", raw"ro(S), seek(S, -2, eof, N), get_code(S, C), close(S), R = N-C"),
    ("d131", raw"ro(S), seek(S, 0, eof, N), get_code(S, C), close(S), R = N-C"),
    ("d132", raw"cerr(seek(foo, 0, bof, _), R)"),
    ("d133", raw"ro(S), cerr(seek(S, 0, bad, _), R0), close(S), R = R0"),
    ("d134", raw"ro(S), cerr(seek(S, foo, bof, _), R0), close(S), R = R0"),
    ("d135", raw"ro(S), cerr(seek(S, -1, bof, _), R0), close(S), R = R0"),
    ("d136", raw"ro(S), seek(S, 3, bof, N), close(S), R = N"),
    ("d137", raw"open_null_stream(S), seek(S, 5, bof, N), close(S), R = N"),
    ("d138", raw"open_null_stream(S), cerr(seek(S, 1, current, _), R0), close(S), R = R0"),
    ("d139", raw"wo(S), write(S, hello), seek(S, 1, bof, N), write(S, 'E'), close(S), outtext(T), R = N-T"),
    ("d140", raw"ro(S), seek(S, 1, bof, _), line_count(S, L), line_position(S, P), close(S), R = L-P"),
    ("d141", raw"ro(S), get_code(S, _), seek(S, 5, bof, _), '$stream_property'(S, position(P)), close(S), R = P"),
    ("d142", raw"ro(S), rall(S, _), seek(S, 0, bof, _), get_code(S, C), close(S), R = C"),
    ("d143", raw"ro(S), seek(S, 100, bof, N), get_code(S, C), close(S), R = N-C"),
    ("d144", raw"rb(S), seek(S, 1, bof, N), get_byte(S, B), close(S), R = N-B"),
    ("d145", raw"ro(S), set_stream(S, encoding(unicode_be)), seek(S, 2, bof, N), close(S), R = N"),
    ("d146", raw"ro(S), seek(S, 1, bof, N), seek(S, 1, current, M), close(S), R = N-M"),
    ("d147", raw"cerr(seek(_, 0, bof, _), R)"),
    ("d148", raw"cerr(seek(user_input, 0, _, _), R)"),
    ("d149", raw"cerr(seek(user_input, _, bof, _), R)"),
    ("d150", raw"ro(S), cerr(seek(S, 1, bof, 99), R0), close(S), R = R0"),
    ("d151", raw"ro(S), get_code(S, _), get_code(S, _), '$stream_property'(S, position(P)), get_code(S, _), set_stream_position(S, P), get_code(S, C), close(S), R = C"),
    ("d152", raw"ro(S), cerr(set_stream_position(S, foo), R0), close(S), R = R0"),
    ("d153", raw"ro(S), cerr(set_stream_position(S, '$stream_position'(a, 1, 0, 0)), R0), close(S), R = R0"),
    ("d154", raw"cerr(set_stream_position(_, '$stream_position'(0, 1, 0, 0)), R)"),
    ("d155", raw"ro(S), set_stream_position(S, '$stream_position'(4, 2, 0, 4)), line_count(S, L), get_code(S, C), close(S), R = L-C"),
    ("d156", raw"open_null_stream(S), cerr(set_stream_position(S, '$stream_position'(0, 1, 0, 0)), R0), close(S), R = R0"),
    ("d157", raw"ro(S), set_stream_position(S, '$stream_position'(100, 3, 4, 100)), '$stream_property'(S, position(P)), close(S), R = P"),
    ("d158", raw"wo(S), write(S, abc), '$stream_property'(S, position(P)), write(S, def), set_stream_position(S, P), write(S, 'X'), close(S), outtext(T), R = T"),
    ("d159", raw"ro(S), cerr(set_stream_position(S, '$stream_position'(1, 1, 1)), R0), close(S), R = R0"),
    ("d160", raw"ro(S), close(S), cerr(set_stream_position(S, '$stream_position'(0, 1, 0, 0)), R0), R = R0"),
    ("d161", raw"wo(S), write(S, abcdef), seek(S, 3, bof, _), set_end_of_stream(S), close(S), outtext(T), R = T"),
    ("d162", raw"wo(S), write(S, abc), set_end_of_stream(S), close(S), outtext(T), R = T"),
    ("d163", raw"ro(S), cerr(set_end_of_stream(S), R0), close(S), R = R0"),
    ("d164", raw"open_null_stream(S), cerr(set_end_of_stream(S), R0), close(S), R = R0"),
    ("d165", raw"cerr(set_end_of_stream(foo), R)"),
    ("d166", raw"cerr(set_end_of_stream(_), R)"),
    ("d167", raw"cerr(set_end_of_stream(1), R)"),
    ("d168", raw"wo(S), write(S, abcdef), flush_output(S), seek(S, 2, bof, _), set_end_of_stream(S), write(S, 'Z'), close(S), outtext(T), R = T"),
    ("d169", raw"ro(S), get_code(S, _), seek(S, 5, bof, N), get_code(S, C), close(S), R = N-C"),
    ("d170", raw"ro(S), get_code(S, _), get_code(S, _), seek(S, -1, current, N), get_code(S, C), close(S), R = N-C"),
    ("d171", raw"ro(S), set_stream(S, encoding(unicode_be)), seek(S, 2, bof, _), '$stream_property'(S, position(P)), close(S), R = P"),
    ("d172", raw"ro(S), seek(S, 1, bof, _), get_code(S, _), '$stream_property'(S, position(P)), close(S), R = P"),
    ("d173", raw"open_string("abc", S), seek(S, 1, bof, N), get_code(S, C), close(S), R = N-C"),
    ("d174", raw"open_string("abc", S), seek(S, -1, eof, N), get_code(S, C), close(S), R = N-C"),
    ("d175", raw"with_output_to(string(X), (current_output(O), write(abc), seek(O, 1, bof, N), write(z))), R = X-N"),
    ("d176", raw"ro(S), get_code(S, _), seek(S, 100, bof, N), get_code(S, C), close(S), R = N-C"),
    ("d177", raw"ro(S), set_stream(S, record_position(false)), cerr(set_stream_position(S, '$stream_position'(0, 1, 0, 0)), R0), close(S), R = R0"),
    ("d178", raw"ro(S), set_stream(S, record_position(false)), get_code(S, _), get_code(S, _), seek(S, -1, current, N), get_code(S, C), close(S), R = N-C"),
    ("d179", raw"ro(S), set_stream(S, record_position(false)), get_code(S, _), seek(S, 100, bof, N), get_code(S, C), close(S), R = N-C"),
    ("d180", raw"ro(S), set_stream(S, record_position(false)), get_code(S, _), get_code(S, _), seek(S, 0, current, N), close(S), R = N"),
    ("d181", raw"wo(S), write(S, abcdef), set_stream(S, record_position(false)), seek(S, 2, bof, N), write(S, z), close(S), outtext(T), R = N-T"),
    ("d182", raw"wo(S), write(S, abcdef), set_stream(S, record_position(false)), seek(S, 0, current, N), close(S), R = N"),
    ("d183", raw"ro(S), set_stream_position(S, '$stream_position'(1, 3, 7, 4)), get_code(S, C), '$stream_property'(S, position(P)), close(S), R = C-P"),
    ("d184", raw"cerr(set_stream_position(1, '$stream_position'(0, 1, 0, 0)), R)"),
    ("d185", raw"ro(S), '$size_stream'(S, N), close(S), R = N"),
    ("d186", raw"wo(S), write(S, abcd), '$size_stream'(S, N), close(S), R = N"),
    ("d187", raw"wo(S), write(S, abcd), flush_output(S), '$size_stream'(S, N), close(S), R = N"),
    ("d188", raw"open_null_stream(S), '$size_stream'(S, N), close(S), R = N"),
    ("d189", raw"open_string("abc", S), '$size_stream'(S, N), close(S), R = N"),
    ("d190", raw"ro(S), cerr('$size_stream'(S, 5), R0), close(S), R = R0"),
    ("d191", raw"cerr('$size_stream'(foo, _), R)"),
    ("d192", raw"cerr('$size_stream'(_, _), R)"),
    ("d193", raw"cerr('$size_stream'(1, _), R)"),
    ("d194", raw"ro(S), close(S), cerr('$size_stream'(S, _), R)"),
    ("d195", raw"ra(S, szal), '$size_stream'(szal, N), close(S), R = N"),
    ("d196", raw"ro(S), fill_buffer(S), get_code(S, C), close(S), R = C"),
    ("d197", raw"ro(S), fill_buffer(S), fill_buffer(S), get_code(S, C), close(S), R = C"),
    ("d198", raw"ro(S), rall(S, L), fill_buffer(S), get_code(S, C), close(S), R = C-L"),
    ("d199", raw"ro(S), fill_buffer(S), '$stream_property'(S, position(P)), close(S), R = P"),
    ("d200", raw"ro(S), fill_buffer(S), seek(S, 0, current, N), close(S), R = N"),
    ("d201", raw"ro(S), get_code(S, _), fill_buffer(S), get_code(S, C), close(S), R = C"),
    ("d202", raw"ro(S), set_stream(S, buffer(false)), cerr(fill_buffer(S), R0), close(S), R = R0"),
    ("d203", raw"wo(S), cerr(fill_buffer(S), R0), close(S), R = R0"),
    ("d204", raw"open_null_stream(S), cerr(fill_buffer(S), R0), close(S), R = R0"),
    ("d205", raw"cerr(fill_buffer(foo), R)"),
    ("d206", raw"cerr(fill_buffer(_), R)"),
    ("d207", raw"ro(S), close(S), cerr(fill_buffer(S), R)"),
    ("d208", raw"open_string("abc", S), fill_buffer(S), get_code(S, C), close(S), R = C"),
    ("d209", raw"ra(S, fbal), fill_buffer(fbal), get_code(fbal, C), close(S), R = C"),
    ("d210", raw"open_string("abc", S), get_code(S, _), '$size_stream'(S, N), get_code(S, C), close(S), R = N-C"),
    ("d211", raw"ro(S), get_code(S, _), '$size_stream'(S, N), get_code(S, C), close(S), R = N-C")
]

# swipl 10.1.20-1-g18168e629's answers to the program and cases above (the driver's lines; evidence/S2/lane_d_rows.out)
const _LD_PINNED = [
    "ok",
    "t_d001 c[116,95,100,48,48,49]/1(c[45]/2(i97,i98))",
    "t_d002 c[116,95,100,48,48,50]/1(i120)",
    "t_d003 c[116,95,100,48,48,51]/1(i-1)",
    "t_d004 c[116,95,100,48,48,52]/1(a[102,97,105,108,101,100])",
    "t_d005 c[116,95,100,48,48,53]/1(a[102,97,105,108,101,100])",
    "t_d006 c[116,95,100,48,48,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,116,114,101,97,109])))",
    "t_d007 c[116,95,100,48,48,55]/1(i97)",
    "t_d008 c[116,95,100,48,48,56]/1(a[102,97,105,108,101,100])",
    "t_d009 c[116,95,100,48,48,57]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d010 c[116,95,100,48,49,48]/1(a[111,107])",
    "t_d011 c[116,95,100,48,49,49]/1(c[45]/2(i97,i98))",
    "t_d012 c[116,95,100,48,49,50]/1(i97)",
    "t_d013 c[116,95,100,48,49,51]/1(a[97])",
    "t_d014 c[116,95,100,48,49,52]/1(a[10])",
    "t_d015 c[116,95,100,48,49,53]/1(i122)",
    "t_d016 c[116,95,100,48,49,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[102,111,111])))",
    "t_d017 c[116,95,100,48,49,55]/1(a[97,98])",
    "t_d018 c[116,95,100,48,49,56]/1(a[98,99])",
    "t_d019 c[116,95,100,48,49,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[102,111,111])))",
    "t_d020 c[116,95,100,48,50,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d021 c[116,95,100,48,50,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i-5)))",
    "t_d022 c[116,95,100,48,50,50]/1(a[113,114])",
    "t_d023 c[116,95,100,48,50,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d024 c[116,95,100,48,50,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,116,114,101,97,109])))",
    "t_d025 c[116,95,100,48,50,53]/1(c[91,124,93]/2(i65,c[91,124,93]/2(i255,c[91,124,93]/2(i0,nil))))",
    "t_d026 c[116,95,100,48,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,121,116,101],i256)))",
    "t_d027 c[116,95,100,48,50,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,121,116,101],i-1)))",
    "t_d028 c[116,95,100,48,50,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,121,116,101],a[97])))",
    "t_d029 c[116,95,100,48,50,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d030 c[116,95,100,48,51,48]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[111,117,116,112,117,116],a[116,101,120,116,95,115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d031 c[116,95,100,48,51,49]/1(c[91,124,93]/2(i66,c[91,124,93]/2(i67,nil)))",
    "t_d032 c[116,95,100,48,51,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,116,114,101,97,109])))",
    "t_d033 c[116,95,100,48,51,51]/1(c[45]/2(i97,i98))",
    "t_d034 c[116,95,100,48,51,52]/1(c[45]/2(i-1,i-1))",
    "t_d035 c[116,95,100,48,51,53]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[116,101,120,116,95,115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d036 c[116,95,100,48,51,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[102,111,111])))",
    "t_d037 c[116,95,100,48,51,55]/1(a[102,97,105,108,101,100])",
    "t_d038 c[116,95,100,48,51,56]/1(a[111,107])",
    "t_d039 c[116,95,100,48,51,57]/1(i97)",
    "t_d040 c[116,95,100,48,52,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,116,114,101,97,109])))",
    "t_d041 c[116,95,100,48,52,49]/1(c[45]/2(c[45]/2(i97,i97),i1))",
    "t_d042 c[116,95,100,48,52,50]/1(c[45]/2(i97,i97))",
    "t_d043 c[116,95,100,48,52,51]/1(i-1)",
    "t_d044 c[116,95,100,48,52,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[116,101,120,116,95,115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d045 c[116,95,100,48,52,53]/1(c[45]/2(i97,i97))",
    "t_d046 c[116,95,100,48,52,54]/1(c[45]/2(i97,i97))",
    "t_d047 c[116,95,100,48,52,55]/1(c[45]/2(a[97],a[97]))",
    "t_d048 c[116,95,100,48,52,56]/1(c[45]/2(c[45]/2(i97,a[97]),i97))",
    "t_d049 c[116,95,100,48,52,57]/1(c[45]/2(a[97],a[97]))",
    "t_d050 c[116,95,100,48,53,48]/1(a[111,107])",
    "t_d051 c[116,95,100,48,53,49]/1(a[102,97,105,108,101,100])",
    "t_d052 c[116,95,100,48,53,50]/1(a[102,97,105,108,101,100])",
    "t_d053 c[116,95,100,48,53,51]/1(c[45]/2(i2,i2))",
    "t_d054 c[116,95,100,48,53,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,116,114,101,97,109])))",
    "t_d055 c[116,95,100,48,53,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,116,114,101,97,109])))",
    "t_d056 c[116,95,100,48,53,54]/1(a[102,97,105,108,101,100])",
    "t_d057 c[116,95,100,48,53,55]/1(a[115,97,109,101])",
    "t_d058 c[116,95,100,48,53,56]/1(a[115,97,109,101])",
    "t_d059 c[116,95,100,48,53,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,116,114,101,97,109])))",
    "t_d060 c[116,95,100,48,54,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,116,114,101,97,109])))",
    "t_d061 c[116,95,100,48,54,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d062 c[116,95,100,48,54,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d063 c[116,95,100,48,54,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d064 c[116,95,100,48,54,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d065 c[116,95,100,48,54,53]/1(a[111,107])",
    "t_d066 c[116,95,100,48,54,54]/1(a[111,107])",
    "t_d067 c[116,95,100,48,54,55]/1(a[120])",
    "t_d068 c[116,95,100,48,54,56]/1(c[45]/2(c[45]/2(i8364,i3),i1))",
    "t_d069 c[116,95,100,48,54,57]/1(c[45]/2(c[45]/2(i226,i226),i1))",
    "t_d070 c[116,95,100,48,55,48]/1(i97)",
    "t_d071 c[116,95,100,48,55,49]/1(a[115,116,114,101,97,109])",
    "t_d072 c[116,95,100,48,55,50]/1(a[115,97,109,101])",
    "t_d073 c[116,95,100,48,55,51]/1(a[117,115,101,114])",
    "t_d074 c[116,95,100,48,55,52]/1(a[117,115,101,114])",
    "t_d075 c[116,95,100,48,55,53]/1(c[45]/2(i97,i98))",
    "t_d076 c[116,95,100,48,55,54]/1(i98)",
    "t_d077 c[116,95,100,48,55,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,111,117,114,99,101,95,115,105,110,107],a[108,97,110,101,95,100,95,110,111,95,115,117,99,104,95,102,105,108,101])))",
    "t_d078 c[116,95,100,48,55,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d079 c[116,95,100,48,55,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_d080 c[116,95,100,48,56,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_d081 c[116,95,100,48,56,49]/1(a[111,107])",
    "t_d082 c[116,95,100,48,56,50]/1(a[97,98,99,100])",
    "t_d083 c[116,95,100,48,56,51]/1(a[115,116,114,101,97,109])",
    "t_d084 c[116,95,100,48,56,52]/1(a[117,115,101,114])",
    "t_d085 c[116,95,100,48,56,53]/1(a[117,115,101,114])",
    "t_d086 c[116,95,100,48,56,54]/1(a[97,98])",
    "t_d087 c[116,95,100,48,56,55]/1(a[97,98])",
    "t_d088 c[116,95,100,48,56,56]/1(a[115,97,109,101])",
    "t_d089 c[116,95,100,48,56,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d090 c[116,95,100,48,57,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_d091 c[116,95,100,48,57,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d092 c[116,95,100,48,57,50]/1(a[122])",
    "t_d093 c[116,95,100,48,57,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,111,117,114,99,101,95,115,105,110,107],a[47,108,97,110,101,95,100,95,110,111,95,115,117,99,104,95,100,105,114,47,120])))",
    "t_d094 c[116,95,100,48,57,52]/1(a[113])",
    "t_d095 c[116,95,100,48,57,53]/1(i97)",
    "t_d096 c[116,95,100,48,57,54]/1(a[98])",
    "t_d097 c[116,95,100,48,57,55]/1(i97)",
    "t_d098 c[116,95,100,48,57,56]/1(i5)",
    "t_d099 c[116,95,100,48,57,57]/1(c[45]/2(i2,i3))",
    "t_d100 c[116,95,100,49,48,48]/1(a[121,101,115])",
    "t_d101 c[116,95,100,49,48,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d102 c[116,95,100,49,48,50]/1(a[117,116,102,56])",
    "t_d103 c[116,95,100,49,48,51]/1(c[45]/2(i2,i5))",
    "t_d104 c[116,95,100,49,48,52]/1(a[119,114,105,116,101])",
    "t_d105 c[116,95,100,49,48,53]/1(c[98,117,102,102,101,114]/1(a[102,97,108,115,101]))",
    "t_d106 c[116,95,100,49,48,54]/1(c[114,97,105,115,101,100]/1(c[117,110,105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]/1(a[102,111,111])))",
    "t_d107 c[116,95,100,49,48,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d108 c[116,95,100,49,48,56]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[111,117,116,112,117,116],a[116,101,120,116,95,115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d109 c[116,95,100,49,48,57]/1(a[121,101,115])",
    "t_d110 c[116,95,100,49,49,48]/1(a[115,97,109,101])",
    "t_d111 c[116,95,100,49,49,49]/1(i97)",
    "t_d112 c[116,95,100,49,49,50]/1(a[97])",
    "t_d113 c[116,95,100,49,49,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d114 c[116,95,100,49,49,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d115 c[116,95,100,49,49,53]/1(c[45]/2(a[105,110],a[117,110,98,111,117,110,100]))",
    "t_d116 c[116,95,100,49,49,54]/1(c[45]/2(a[111,117,116],a[117,110,98,111,117,110,100]))",
    "t_d117 c[116,95,100,49,49,55]/1(a[111,107])",
    "t_d118 c[116,95,100,49,49,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d119 c[116,95,100,49,49,57]/1(a[111,107])",
    "t_d120 c[116,95,100,49,50,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d121 c[116,95,100,49,50,49]/1(c[45]/2(a[117,115,101,114,95,105,110,112,117,116],a[117,115,101,114,95,111,117,116,112,117,116]))",
    "t_d122 c[116,95,100,49,50,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d123 c[116,95,100,49,50,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d124 c[116,95,100,49,50,52]/1(a[111,107])",
    "t_d125 c[116,95,100,49,50,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d126 c[116,95,100,49,50,54]/1(a[122])",
    "t_d127 c[116,95,100,49,50,55]/1(i2)",
    "t_d128 c[116,95,100,49,50,56]/1(c[45]/2(i4,i120))",
    "t_d129 c[116,95,100,49,50,57]/1(c[45]/2(i3,i10))",
    "t_d130 c[116,95,100,49,51,48]/1(c[45]/2(i16,i101))",
    "t_d131 c[116,95,100,49,51,49]/1(c[45]/2(i18,i-1))",
    "t_d132 c[116,95,100,49,51,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d133 c[116,95,100,49,51,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,101,101,107,95,109,101,116,104,111,100],a[98,97,100])))",
    "t_d134 c[116,95,100,49,51,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111])))",
    "t_d135 c[116,95,100,49,51,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[112,111,115,105,116,105,111,110],i-1)))",
    "t_d136 c[116,95,100,49,51,54]/1(i3)",
    "t_d137 c[116,95,100,49,51,55]/1(i5)",
    "t_d138 c[116,95,100,49,51,56]/1(a[111,107])",
    "t_d139 c[116,95,100,49,51,57]/1(c[45]/2(i1,a[104,69,108,108,111]))",
    "t_d140 c[116,95,100,49,52,48]/1(c[45]/2(i1,i0))",
    "t_d141 c[116,95,100,49,52,49]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i5,i1,i1,i5))",
    "t_d142 c[116,95,100,49,52,50]/1(i97)",
    "t_d143 c[116,95,100,49,52,51]/1(c[45]/2(i100,i-1))",
    "t_d144 c[116,95,100,49,52,52]/1(c[45]/2(i1,i98))",
    "t_d145 c[116,95,100,49,52,53]/1(i2)",
    "t_d146 c[116,95,100,49,52,54]/1(c[45]/2(i1,i2))",
    "t_d147 c[116,95,100,49,52,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d148 c[116,95,100,49,52,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d149 c[116,95,100,49,52,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d150 c[116,95,100,49,53,48]/1(a[102,97,105,108,101,100])",
    "t_d151 c[116,95,100,49,53,49]/1(i99)",
    "t_d152 c[116,95,100,49,53,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,112,111,115,105,116,105,111,110],a[102,111,111])))",
    "t_d153 c[116,95,100,49,53,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,112,111,115,105,116,105,111,110],c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(a[97],i1,i0,i0))))",
    "t_d154 c[116,95,100,49,53,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d155 c[116,95,100,49,53,53]/1(c[45]/2(i2,i120))",
    "t_d156 c[116,95,100,49,53,54]/1(a[111,107])",
    "t_d157 c[116,95,100,49,53,55]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i100,i3,i4,i100))",
    "t_d158 c[116,95,100,49,53,56]/1(a[97,98,99,88,101,102])",
    "t_d159 c[116,95,100,49,53,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,112,111,115,105,116,105,111,110],c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/3(i1,i1,i1))))",
    "t_d160 c[116,95,100,49,54,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d161 c[116,95,100,49,54,49]/1(a[97,98,99])",
    "t_d162 c[116,95,100,49,54,50]/1(a[97,98,99])",
    "t_d163 c[116,95,100,49,54,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d164 c[116,95,100,49,54,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[115,101,116,95,101,110,100,95,111,102,95,115,116,114,101,97,109],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d165 c[116,95,100,49,54,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d166 c[116,95,100,49,54,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d167 c[116,95,100,49,54,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],i1)))",
    "t_d168 c[116,95,100,49,54,56]/1(a[97,98,90])",
    "t_d169 c[116,95,100,49,54,57]/1(c[45]/2(i5,i121))",
    "t_d170 c[116,95,100,49,55,48]/1(c[45]/2(i1,i98))",
    "t_d171 c[116,95,100,49,55,49]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i2,i1,i0,i4))",
    "t_d172 c[116,95,100,49,55,50]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i2,i1,i1,i2))",
    "t_d173 c[116,95,100,49,55,51]/1(c[45]/2(i1,i98))",
    "t_d174 c[116,95,100,49,55,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[112,111,115,105,116,105,111,110],i-1)))",
    "t_d175 c[116,95,100,49,55,53]/1(c[45]/2(s[97,122,99],i1))",
    "t_d176 c[116,95,100,49,55,54]/1(c[45]/2(i100,i-1))",
    "t_d177 c[116,95,100,49,55,55]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,112,111,115,105,116,105,111,110],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d178 c[116,95,100,49,55,56]/1(c[45]/2(i1,i98))",
    "t_d179 c[116,95,100,49,55,57]/1(c[45]/2(i100,i-1))",
    "t_d180 c[116,95,100,49,56,48]/1(i2)",
    "t_d181 c[116,95,100,49,56,49]/1(c[45]/2(i2,a[97,98,122,100,101,102]))",
    "t_d182 c[116,95,100,49,56,50]/1(i6)",
    "t_d183 c[116,95,100,49,56,51]/1(c[45]/2(i120,c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i2,i3,i8,i5)))",
    "t_d184 c[116,95,100,49,56,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,111,114,95,97,108,105,97,115],i1)))",
    "t_d185 c[116,95,100,49,56,53]/1(i18)",
    "t_d186 c[116,95,100,49,56,54]/1(i0)",
    "t_d187 c[116,95,100,49,56,55]/1(i4)",
    "t_d188 c[116,95,100,49,56,56]/1(c[114,97,105,115,101,100]/1(c[105,111,95,101,114,114,111,114]/2(a[119,114,105,116,101],a[60,115,116,114,101,97,109,62])))",
    "t_d189 c[116,95,100,49,56,57]/1(i0)",
    "t_d190 c[116,95,100,49,57,48]/1(a[102,97,105,108,101,100])",
    "t_d191 c[116,95,100,49,57,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d192 c[116,95,100,49,57,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d193 c[116,95,100,49,57,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,111,114,95,97,108,105,97,115],i1)))",
    "t_d194 c[116,95,100,49,57,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d195 c[116,95,100,49,57,53]/1(i18)",
    "t_d196 c[116,95,100,49,57,54]/1(i97)",
    "t_d197 c[116,95,100,49,57,55]/1(i97)",
    "t_d198 c[116,95,100,49,57,56]/1(c[45]/2(i-1,c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,nil))))))))))))))))))))",
    "t_d199 c[116,95,100,49,57,57]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0))",
    "t_d200 c[116,95,100,50,48,48]/1(i0)",
    "t_d201 c[116,95,100,50,48,49]/1(i98)",
    "t_d202 c[116,95,100,50,48,50]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[102,105,108,108,95,98,117,102,102,101,114],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d203 c[116,95,100,50,48,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d204 c[116,95,100,50,48,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d205 c[116,95,100,50,48,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d206 c[116,95,100,50,48,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d207 c[116,95,100,50,48,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d208 c[116,95,100,50,48,56]/1(i97)",
    "t_d209 c[116,95,100,50,48,57]/1(i97)",
    "t_d210 c[116,95,100,50,49,48]/1(c[45]/2(i3,i98))",
    "t_d211 c[116,95,100,50,49,49]/1(c[45]/2(i18,i98))"
]

const _LD_DATA = "abc\nxyz\nlast line\n"

"The data file's text, and the program and cases as one file in `dir` (the data and output paths substituted); the case predicates' names."
function _ld_file(dir::String)::Tuple{String, Vector{String}}
    data = joinpath(dir, "data.txt")
    write(data, _LD_DATA)
    prog = replace(replace(_LD_PROGRAM, "@DATA@" => data), "@OUT@" => joinpath(dir, "out.txt"))
    names = ["t_$(id)" for (id, _) in _LD_CASES]
    text =
        prog * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).\n" for
            (id, g) in _LD_CASES
        ])
    f = joinpath(dir, "lane_d.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _ld_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_LD}()
    ld = LK.PL_local_data{_LD}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _ld_enc(ball::_LD)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_lds(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_LD, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _ld_enc(mk_expr(_LD, _LD[_lds(name), lk_answers(ld, (a:a)...)...]))
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

@testset "Edinburgh and byte stream predicates as swipl's (d001-d127)" begin
    f, names = _ld_file(mktempdir())
    kl = _ld_kernel(f, names)
    @test length(kl) == length(_LD_PINNED)
    for (k, p) in zip(kl, _LD_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the pins hold raised errors, `failed` rows, and answers, so the comparison can pass and can fail
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _LD_PINNED) == 65      # raised(…)
    @test count(l -> endswith(l, "/1(a[102,97,105,108,101,100])"), _LD_PINNED) == 8   # failed
    @test count(l -> endswith(l, "/1(a[111,107])"), _LD_PINNED) == 11                 # ok
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_LD_PINNED) == length(_LD_CASES) + 1
    if swipl === nothing
        @info "LANE D LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _ld_file(mktempdir())
        @test _ld_swipl_lines(f, names) == _LD_PINNED
    end
end
