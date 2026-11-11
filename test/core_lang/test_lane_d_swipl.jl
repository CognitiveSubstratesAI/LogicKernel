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
rout(S) :- outfile(F), open(F, read, S).
wenc(Enc, Codes) :- outfile(F), open(F, write, W, [encoding(Enc)]), forall(member(C, Codes), put_code(W, C)), close(W).
renc(Enc, L) :- outfile(F), open(F, read, S, [encoding(Enc)]), rall(S, L), close(S).
wbytes(Bs) :- wb(W), forall(member(B, Bs), put_byte(W, B)), close(W).
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
    ("d173", raw"open_string(\"abc\", S), seek(S, 1, bof, N), get_code(S, C), close(S), R = N-C"),
    ("d174", raw"open_string(\"abc\", S), seek(S, -1, eof, N), get_code(S, C), close(S), R = N-C"),
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
    ("d189", raw"open_string(\"abc\", S), '$size_stream'(S, N), close(S), R = N"),
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
    ("d208", raw"open_string(\"abc\", S), fill_buffer(S), get_code(S, C), close(S), R = C"),
    ("d209", raw"ra(S, fbal), fill_buffer(fbal), get_code(fbal, C), close(S), R = C"),
    ("d210", raw"open_string(\"abc\", S), get_code(S, _), '$size_stream'(S, N), get_code(S, C), close(S), R = N-C"),
    ("d211", raw"ro(S), get_code(S, _), '$size_stream'(S, N), get_code(S, C), close(S), R = N-C"),
    ("d212", raw"ro(S), read_pending_codes(S, L, []), close(S), R = L"),
    ("d213", raw"ro(S), fill_buffer(S), read_pending_codes(S, L, []), close(S), R = L"),
    ("d214", raw"ro(S), fill_buffer(S), read_pending_codes(S, L, T), close(S), T = [0'z], R = L"),
    ("d215", raw"ro(S), fill_buffer(S), read_pending_chars(S, L, []), close(S), R = L"),
    ("d216", raw"ro(S), fill_buffer(S), read_pending_chars(S, L, [z]), close(S), R = L"),
    ("d217", raw"ro(S), fill_buffer(S), read_pending_codes(S, _, []), get_code(S, C), close(S), R = C"),
    ("d218", raw"ro(S), fill_buffer(S), read_pending_codes(S, _, []), '$stream_property'(S, position(P)), close(S), R = P"),
    ("d219", raw"ro(S), get_code(S, _), get_code(S, _), read_pending_codes(S, L, []), close(S), R = L"),
    ("d220", raw"ro(S), get_code(S, _), fill_buffer(S), read_pending_codes(S, L, []), '$stream_property'(S, position(P)), close(S), R = L-P"),
    ("d221", raw"ro(S), rall(S, _), read_pending_codes(S, L, []), close(S), R = L"),
    ("d222", raw"ro(S), rall(S, _), read_pending_codes(S, L, T), close(S), R = L-T"),
    ("d223", raw"rb(S), fill_buffer(S), read_pending_codes(S, L, []), close(S), R = L"),
    ("d224", raw"ro(S), set_stream(S, encoding(octet)), fill_buffer(S), read_pending_codes(S, L, []), '$stream_property'(S, position(P)), close(S), R = L-P"),
    ("d225", raw"ro(S), set_stream(S, encoding(unicode_be)), fill_buffer(S), read_pending_codes(S, L, []), '$stream_property'(S, position(P)), close(S), R = L-P"),
    ("d226", raw"ro(S), set_stream(S, encoding(unicode_le)), fill_buffer(S), read_pending_codes(S, L, []), close(S), R = L"),
    ("d227", raw"atom_codes(A, [0'a, 233, 0x20ac, 0x1F600, 0'b]), outfile(F), open(F, write, W, [encoding(utf8)]), write(W, A), close(W), open(F, read, S, [encoding(utf8)]), fill_buffer(S), read_pending_codes(S, L, []), '$stream_property'(S, position(P)), close(S), R = L-P"),
    ("d228", raw"atom_codes(A, [0'a, 233, 0x20ac, 0x1F600, 0'b]), outfile(F), open(F, write, W, [encoding(utf8)]), write(W, A), close(W), open(F, read, S, [encoding(utf8)]), fill_buffer(S), read_pending_chars(S, L, []), close(S), atom_chars(X, L), R = X"),
    ("d229", raw"atom_codes(A, [0'a, 0x1F600, 0'b]), outfile(F), open(F, write, W, [encoding(utf16be)]), write(W, A), close(W), open(F, read, S, [encoding(utf16be)]), fill_buffer(S), read_pending_codes(S, L, []), '$stream_property'(S, position(P)), close(S), R = L-P"),
    ("d230", raw"atom_codes(A, [0'a, 0x1F600, 0'b]), outfile(F), open(F, write, W, [encoding(utf16le)]), write(W, A), close(W), open(F, read, S, [encoding(utf16le)]), fill_buffer(S), read_pending_codes(S, L, []), close(S), R = L"),
    ("d231", raw"wb(S), put_byte(S, 0'a), put_byte(S, 13), put_byte(S, 10), put_byte(S, 0'b), close(S), outfile(F), open(F, read, I, [newline(dos)]), fill_buffer(I), read_pending_codes(I, L, []), '$stream_property'(I, position(P)), close(I), R = L-P"),
    ("d232", raw"wb(S), put_byte(S, 0'a), put_byte(S, 13), put_byte(S, 10), put_byte(S, 0'b), close(S), outfile(F), open(F, read, I), fill_buffer(I), read_pending_codes(I, L, []), close(I), R = L"),
    ("d233", raw"wo(S), forall(between(1, 5000, _), put_char(S, a)), close(S), outfile(F), open(F, read, I), fill_buffer(I), read_pending_codes(I, L, []), length(L, N1), fill_buffer(I), read_pending_codes(I, L2, []), length(L2, N2), close(I), R = N1-N2"),
    ("d234", raw"ro(S), fill_buffer(S), ( read_pending_codes(S, [0'x|_], _) -> A = yes ; A = no ), get_code(S, C), close(S), R = A-C"),
    ("d235", raw"ro(S), fill_buffer(S), ( read_pending_codes(S, L, [0'q]) -> A = yes ; A = no ), close(S), R = A-L"),
    ("d236", raw"open_string(\"abc\", S), fill_buffer(S), read_pending_codes(S, L, []), close(S), R = L"),
    ("d237", raw"ra(S, rpal), fill_buffer(rpal), read_pending_codes(rpal, L, []), close(S), R = L"),
    ("d238", raw"cerr(read_pending_codes(foo, _, []), R)"),
    ("d239", raw"cerr(read_pending_codes(_, _, []), R)"),
    ("d240", raw"wo(S), cerr(read_pending_codes(S, _, []), R0), close(S), R = R0"),
    ("d241", raw"ro(S), close(S), cerr(read_pending_codes(S, _, []), R)"),
    ("d242", raw"ro(S), fill_buffer(S), cerr(read_pending_codes(S, [a|b], []), R0), close(S), R = R0"),
    ("d243", raw"ro(S), fill_buffer(S), read_pending_codes(S, L, T), close(S), length(L, N), var(T), R = N"),
    ("d244", raw"ro(S), fill_buffer(S), read_pending_codes(S, L, T), close(S), L = [_,_|R0], R = R0-T"),
    ("d245", raw"atom_codes(A, [0'a, 233, 0x20ac, 0x1F600, 0'b]), outfile(F), open(F, write, W, [encoding(utf8)]), write(W, A), close(W), open(F, read, S, [encoding(utf8)]), fill_buffer(S), read_pending_codes(S, _, []), get_code(S, C), close(S), R = C"),
    ("d246", raw"outfile(F), open(F, write, W, [encoding(utf8)]), put_char(W, a), forall(between(1, 2500, _), put_code(W, 233)), close(W), open(F, read, S, [encoding(utf8)]), fill_buffer(S), read_pending_codes(S, L1, []), length(L1, N1), fill_buffer(S), read_pending_codes(S, L2, []), length(L2, N2), '$stream_property'(S, position(P)), close(S), R = N1-N2-P"),
    ("d247", raw"wb(S), put_byte(S, 0'a), put_byte(S, 13), put_byte(S, 10), put_byte(S, 0'b), close(S), outfile(F), open(F, read, I, [newline(detect)]), '$stream_property'(I, newline(M0)), fill_buffer(I), read_pending_codes(I, L, []), '$stream_property'(I, newline(M1)), close(I), R = M0-M1-L"),
    ("d248", raw"wb(S), put_byte(S, 97), put_byte(S, 255), put_byte(S, 98), close(S), outfile(F), open(F, read, I, [encoding(utf8)]), fill_buffer(I), cerr(read_pending_codes(I, _, []), R0), close(I), R = R0"),
    ("d249", raw"wb(S), put_byte(S, 0xD8), put_byte(S, 0), put_byte(S, 0), put_byte(S, 0x41), close(S), outfile(F), open(F, read, I, [type(binary)]), set_stream(I, encoding(utf16be)), fill_buffer(I), cerr(read_pending_codes(I, _, []), R0), close(I), R = R0"),
    ("d250", raw"ro(S), fill_buffer(S), get_code(S, _), '$stream_property'(S, position(P0)), cerr(read_pending_codes(S, [0'x|_], []), R0), '$stream_property'(S, position(P1)), close(S), R = R0-P0-P1"),
    ("d251", raw"ro(S), set_stream(S, encoding(wchar_t)), fill_buffer(S), read_pending_codes(S, L, []), '$stream_property'(S, position(P)), close(S), R = L-P"),
    ("d252", raw"ro(S), fill_buffer(S), read_pending_codes(S, _, []), fill_buffer(S), read_pending_codes(S, L, []), close(S), R = L"),
    ("d253", raw"wb(S), put_byte(S, 0'a), put_byte(S, 13), put_byte(S, 10), put_byte(S, 0'b), close(S), outfile(F), open(F, read, I, [newline(dos), encoding(iso_latin_1)]), fill_buffer(I), read_pending_codes(I, L, []), '$stream_property'(I, position(P)), close(I), R = L-P"),
    ("d254", raw"ro(S), peek_string(S, 3, X), get_code(S, C), close(S), R = X-C"),
    ("d255", raw"ro(S), peek_string(S, 0, X), close(S), R = X"),
    ("d256", raw"ro(S), peek_string(S, 100, X), close(S), R = X"),
    ("d257", raw"ro(S), peek_string(S, 18, X), close(S), R = X"),
    ("d258", raw"ro(S), peek_string(S, 19, X), close(S), R = X"),
    ("d259", raw"ro(S), fill_buffer(S), peek_string(S, 5, X), close(S), R = X"),
    ("d260", raw"ro(S), peek_string(S, 5, X), '$stream_property'(S, position(P)), close(S), R = X-P"),
    ("d261", raw"ro(S), get_code(S, _), get_code(S, _), peek_string(S, 3, X), get_code(S, C), close(S), R = X-C"),
    ("d262", raw"ro(S), rall(S, _), peek_string(S, 5, X), close(S), R = X"),
    ("d263", raw"ro(S), peek_string(S, 3, X), peek_string(S, 3, Y), close(S), R = X-Y"),
    ("d264", raw"rb(S), peek_string(S, 4, X), string_codes(X, Cs), close(S), R = Cs"),
    ("d265", raw"atom_codes(A, [0'a, 233, 0x20ac, 0x1F600, 0'b]), outfile(F), open(F, write, W, [encoding(utf8)]), write(W, A), close(W), open(F, read, S, [encoding(utf8)]), peek_string(S, 3, X), string_codes(X, Cs), get_code(S, C), close(S), R = Cs-C"),
    ("d266", raw"atom_codes(A, [0'a, 233, 0x20ac, 0x1F600, 0'b]), outfile(F), open(F, write, W, [encoding(utf8)]), write(W, A), close(W), open(F, read, S, [encoding(utf8)]), peek_string(S, 10, X), string_codes(X, Cs), close(S), R = Cs"),
    ("d269", raw"wb(S), put_byte(S, 233), put_byte(S, 0'a), close(S), outfile(F), open(F, read, I, [encoding(iso_latin_1)]), peek_string(I, 1, X), string_codes(X, Cs), close(I), R = Cs"),
    ("d270", raw"wo(S), forall(between(1, 5000, _), put_char(S, a)), close(S), outfile(F), open(F, read, I), peek_string(I, 5000, X), string_length(X, N), close(I), R = N"),
    ("d271", raw"wo(S), forall(between(1, 5000, _), put_char(S, a)), close(S), outfile(F), open(F, read, I), peek_string(I, 6000, X), string_length(X, N), close(I), R = N"),
    ("d272", raw"wo(S), forall(between(1, 5000, _), put_char(S, a)), close(S), outfile(F), open(F, read, I), peek_string(I, 4500, X), get_char(I, C), string_length(X, N), close(I), R = N-C"),
    ("d273", raw"ro(S), cerr(peek_string(S, -1, _), R0), close(S), R = R0"),
    ("d274", raw"ro(S), cerr(peek_string(S, a, _), R0), close(S), R = R0"),
    ("d275", raw"ro(S), cerr(peek_string(S, _, _), R0), close(S), R = R0"),
    ("d276", raw"cerr(peek_string(foo, 3, _), R)"),
    ("d277", raw"cerr(peek_string(_, 3, _), R)"),
    ("d278", raw"wo(S), cerr(peek_string(S, 3, _), R0), close(S), R = R0"),
    ("d279", raw"ro(S), close(S), cerr(peek_string(S, 3, _), R)"),
    ("d280", raw"ro(S), cerr(peek_string(S, 3, \"abd\"), R0), close(S), R = R0"),
    ("d281", raw"ro(S), cerr(peek_string(S, 3, \"abc\"), R0), close(S), R = R0"),
    ("d282", raw"open_string(\"hello\", S), peek_string(S, 3, X), get_code(S, C), close(S), R = X-C"),
    ("d283", raw"open_string(\"hello\", S), peek_string(S, 30, X), close(S), R = X"),
    ("d284", raw"ra(S, pkal), peek_string(pkal, 2, X), close(S), R = X"),
    ("d285", raw"ro(S), peek_string(S, 3, X), string(X), close(S), R = yes"),
    ("d286", raw"ro(S), wo(O), copy_stream_data(S, O), close(S), close(O), outtext(T), R = T"),
    ("d287", raw"ro(S), wo(O), copy_stream_data(S, O, 5), close(S), close(O), outtext(T), R = T"),
    ("d288", raw"ro(S), wo(O), copy_stream_data(S, O, 0), close(S), close(O), outtext(T), R = T"),
    ("d289", raw"ro(S), wo(O), copy_stream_data(S, O, 100), close(S), close(O), outtext(T), R = T"),
    ("d290", raw"ro(S), wo(O), copy_stream_data(S, O, -3), close(S), close(O), outtext(T), R = T"),
    ("d291", raw"ro(S), wo(O), get_code(S, _), copy_stream_data(S, O, 3), get_code(S, C), close(S), close(O), outtext(T), R = T-C"),
    ("d292", raw"ro(S), wo(O), get_code(S, _), copy_stream_data(S, O), close(S), close(O), outtext(T), R = T"),
    ("d293", raw"ro(S), open_null_stream(O), copy_stream_data(S, O), character_count(O, N), close(S), close(O), R = N"),
    ("d294", raw"ro(S), wo(O), cerr(copy_stream_data(S, O, a), R0), close(S), close(O), R = R0"),
    ("d295", raw"ro(S), wo(O), cerr(copy_stream_data(S, O, _), R0), close(S), close(O), R = R0"),
    ("d296", raw"ro(S), wo(O), cerr(copy_stream_data(S, O, 2.5), R0), close(S), close(O), R = R0"),
    ("d297", raw"ro(S), cerr(copy_stream_data(S, S), R0), close(S), R = R0"),
    ("d298", raw"ro(S), wo(O), cerr(copy_stream_data(O, S), R0), close(S), close(O), R = R0"),
    ("d299", raw"wo(O), cerr(copy_stream_data(foo, O), R0), close(O), R = R0"),
    ("d300", raw"ro(S), cerr(copy_stream_data(S, foo), R0), close(S), R = R0"),
    ("d301", raw"ro(S), wo(O), close(O), cerr(copy_stream_data(S, O), R0), close(S), R = R0"),
    ("d302", raw"ro(S), close(S), wo(O), cerr(copy_stream_data(S, O), R0), close(O), R = R0"),
    ("d303", raw"atom_codes(A, [0'a, 233, 0x20ac, 0x1F600, 0'b]), outfile(F), open(F, write, W, [encoding(utf8)]), write(W, A), close(W), open(F, read, S, [encoding(utf8)]), with_output_to(string(X), (current_output(O), copy_stream_data(S, O))), string_codes(X, Cs), close(S), R = Cs"),
    ("d304", raw"wo(S), forall(between(1, 5000, _), put_char(S, a)), close(S), outfile(F), open(F, read, I), with_output_to(string(X), (current_output(O), copy_stream_data(I, O))), string_length(X, N), close(I), R = N"),
    ("d305", raw"ro(S), with_output_to(string(X), (current_output(O), copy_stream_data(S, O, 4))), close(S), R = X"),
    ("d306", raw"ro(S), rall(S, _), wo(O), copy_stream_data(S, O), close(S), close(O), outtext(T), R = T"),
    ("d307", raw"ro(S), wo(O), copy_stream_data(S, O, 5), copy_stream_data(S, O, 5), close(S), close(O), outtext(T), R = T"),
    ("d308", raw"ro(S), open_string(\"zz\", O0), cerr(copy_stream_data(S, O0), R0), close(S), R = R0"),
    ("d309", raw"open_string(\"hello\", S), wo(O), copy_stream_data(S, O, 3), close(S), close(O), outtext(T), R = T"),
    ("d310", raw"noprotocol, R = yes"),
    ("d311", raw"noprotocol, noprotocol, R = twice"),
    ("d312", raw"( protocolling(F) -> R = F ; R = none )"),
    ("d314", raw"with_tty_raw(R = yes)"),
    ("d315", raw"( with_tty_raw(fail) -> R = yes ; R = no )"),
    ("d316", raw"with_tty_raw(member(R, [a, b]))"),
    ("d317", raw"with_tty_raw(atom_length(_, _))"),
    ("d319", raw"open(pipe('printf abc'), read, S), get_char(S, C1), get_char(S, C2), close(S), R = C1-C2"),
    ("d320", raw"open(pipe('printf abc'), read, S), get_char(S, _), cerr(seek(S, 0, bof, X), R0), close(S), R = R0-X"),
    ("d321", raw"open(pipe('printf abc'), read, S, [reposition(false)]), get_char(S, _), cerr(seek(S, 0, current, _), R0), close(S), R = R0"),
    ("d322", raw"open(pipe('printf abc'), read, S), cerr(seek(S, 0, bof, _), R0), close(S), R = R0"),
    ("d323", raw"open(pipe('printf abc'), read, S), cerr('$size_stream'(S, _), R0), close(S), R = R0"),
    ("d324", raw"open(pipe('cat > /dev/null'), write, S), format(S, \"abc\", []), close(S), R = ok"),
    ("d325", raw"open(pipe('printf A'), read, S, [type(binary)]), get_byte(S, B), close(S), R = B"),
    ("d326", raw"cerr(open(pipe(f(x)), read, _), R0), R = R0"),
    ("d327", raw"cerr(open(pipe('true'), append, _), R0), R = R0"),
    ("d328", raw"open(pipe('exit 3'), read, S), get_char(S, C), close(S), R = C"),
    ("d329", raw"open(pipe('printf abc'), read, S), ( stream_property(S, file_name(F)) -> R0 = F ; R0 = nofile ), close(S), R = R0"),
    ("d330", raw"open(pipe('printf abc'), read, S), stream_property(S, reposition(B)), close(S), R = B"),
    ("d331", raw"open(pipe('printf abc'), read, S), '$stream_property'(S, position(P)), close(S), R = P"),
    ("d332", raw"open(pipe('printf \"a\\nb\"'), read, S), get_char(S, _), get_char(S, _), get_char(S, _), '$stream_property'(S, position(P)), close(S), R = P"),
    ("d333", raw"open(pipe('printf abc'), read, S), fill_buffer(S), read_pending_codes(S, L, []), close(S), R = L"),
    ("d334", raw"open(pipe('printf abc'), read, S), peek_string(S, 2, X), get_char(S, C), close(S), R = X-C"),
    ("d335", raw"open(pipe('printf abc'), read, S), wo(O), copy_stream_data(S, O), close(S), close(O), outtext(T), R = T"),
    ("d336", raw"open(pipe('printf abc'), read, S), cerr(seek(S, 100, bof, _), R0), close(S), R = R0"),
    ("d337", raw"open(pipe('printf abc'), read, S), cerr(seek(S, 0, eof, _), R0), close(S), R = R0"),
    ("d338", raw"open(pipe('printf abc'), read, S), seek(S, 1, current, X), get_char(S, C), close(S), R = X-C"),
    ("d339", raw"open(pipe('printf abc'), read, S), get_char(S, _), get_char(S, _), cerr(seek(S, 1, bof, X), R0), get_char(S, C), close(S), R = R0-X-C"),
    ("d340", raw"open(pipe('printf abc'), read, S, [reposition(false)]), cerr(seek(S, 0, bof, _), R0), close(S), R = R0"),
    ("d341", raw"open(pipe('printf abc'), read, S), cerr(set_stream_position(S, '$stream_position'(5, 1, 5, 5)), R0), close(S), R = R0"),
    ("d342", raw"outfile(F), cerr(open(F, write, _, [lock(foo)]), R0), R = R0"),
    ("d343", raw"cerr(open(pipe('true'), read, _, [lock(foo)]), R0), R = R0"),
    ("d344", raw"open_string(\"abc\", S), stream_property(S, reposition(B)), close(S), R = B"),
    ("d345", raw"open_null_stream(S), stream_property(S, reposition(B)), close(S), R = B"),
    ("d346", raw"with_output_to(string(_), (current_output(O), stream_property(O, reposition(B)))), R = B"),
    ("d347", raw"open('/dev/null', read, S), stream_property(S, reposition(B)), close(S), R = B"),
    ("d348", raw"open(pipe('true'), read, S), stream_property(S, reposition(B)), close(S), R = B"),
    ("d349", raw"wo(S), stream_property(S, reposition(B)), close(S), R = B"),
    ("d351", raw"wenc(utf16be, [0'a, 0x1F600, 0'b]), outbytes(L), R = L"),
    ("d352", raw"wenc(utf16le, [0'a, 0x1F600, 0'b]), outbytes(L), R = L"),
    ("d353", raw"wenc(wchar_t, [0'a, 0x1F600]), outbytes(L), R = L"),
    ("d354", raw"wenc(unicode_be, [0'a, 0x20AC]), outbytes(L), R = L"),
    ("d355", raw"wenc(unicode_le, [0'a, 0x20AC]), renc(unicode_le, L), R = L"),
    ("d356", raw"wenc(utf16be, [0'a, 0x1F600, 0xFFFF, 0'b]), renc(utf16be, L), R = L"),
    ("d357", raw"wenc(utf16le, [0x1F600, 0x10FFFF, 0x20AC]), renc(utf16le, L), R = L"),
    ("d358", raw"wenc(wchar_t, [0'a, 0x1F600, 0x10FFFF]), renc(wchar_t, L), R = L"),
    ("d359", raw"outfile(F), open(F, write, W, [encoding(utf16be), bom(true)]), put_code(W, 0'a), close(W), outbytes(L), R = L"),
    ("d360", raw"outfile(F), open(F, write, W, [encoding(utf16le), bom(true)]), put_code(W, 0'a), close(W), outbytes(L), R = L"),
    ("d361", raw"wbytes([0xFF, 0xFE, 0x61, 0, 0x3D, 0xD8, 0x00, 0xDE]), rout(S), rall(S, L), sp(S, encoding(_), E), has(S, bom(true), H), close(S), R = L-E-H"),
    ("d362", raw"wbytes([0xFE, 0xFF, 0, 0x61, 0xD8, 0x3D, 0xDE, 0x00]), rout(S), rall(S, L), sp(S, encoding(_), E), close(S), R = L-E"),
    ("d363", raw"wbytes([0xEF, 0xBB, 0xBF, 0x61, 0xC3, 0xA9]), rout(S), rall(S, L), sp(S, encoding(_), E), close(S), R = L-E"),
    ("d364", raw"wbytes([0xFF, 0xFE, 0x61, 0]), renc(iso_latin_1, L), R = L"),
    ("d365", raw"wbytes([0xDC, 0, 0, 0x61]), outfile(F), open(F, read, S, [encoding(utf16be)]), get_code(S, A), get_code(S, B), close(S), R = A-B"),
    ("d366", raw"wbytes([0xD8, 0, 0, 0x61]), outfile(F), open(F, read, S, [encoding(utf16be)]), get_code(S, A), get_code(S, B), close(S), R = A-B"),
    ("d367", raw"wbytes([0xD8, 0]), outfile(F), open(F, read, S, [encoding(utf16be)]), get_code(S, A), get_code(S, B), close(S), R = A-B"),
    ("d368", raw"wbytes([0, 0x61, 0]), outfile(F), open(F, read, S, [encoding(utf16be)]), get_code(S, A), get_code(S, B), get_code(S, C), close(S), R = [A, B, C]"),
    ("d369", raw"wbytes([0x61, 0, 0]), outfile(F), open(F, read, S, [encoding(wchar_t)]), get_code(S, A), get_code(S, B), close(S), R = A-B"),
    ("d370", raw"outfile(F), open(F, write, W, [encoding(utf16be)]), atom_codes(A, [233, 0x1F600]), writeq(W, A), close(W), outbytes(L), R = L"),
    ("d371", raw"outfile(F), open(F, write, W, [encoding(utf16le)]), atom_codes(X, [0'x, 0x1F600]), format(W, 'foo(bar, ~q).~n', [X]), close(W), open(F, read, S, [encoding(utf16le)]), read(S, T), close(S), R = T"),
    ("d372", raw"wo(W), put_code(W, 0'a), set_stream(W, encoding(utf16be)), put_code(W, 0'b), put_code(W, 0x20AC), close(W), outbytes(L), R = L"),
    ("d373", raw"wenc(utf16be, [0x1F600, 0'a]), outfile(F), open(F, read, S, [encoding(utf16be)]), peek_code(S, A), get_code(S, B), peek_code(S, C), close(S), R = [A, B, C]"),
    ("d374", raw"wenc(utf16be, [0x1F600, 0'a]), outfile(F), open(F, read, S, [encoding(utf16be)]), get_code(S, _), byte_count(S, B), character_count(S, C), get_code(S, _), byte_count(S, B2), close(S), R = [B, C, B2]"),
    ("d375", raw"outfile(F), open(F, write, W, [encoding(utf16be)]), sp(W, encoding(_), E1), close(W), open(F, write, W2, [encoding(unicode_le)]), sp(W2, encoding(_), E2), close(W2), open(F, write, W3, [encoding(wchar_t)]), sp(W3, encoding(_), E3), close(W3), R = [E1, E2, E3]"),
    ("d376", raw"outfile(F), open(F, write, W, [encoding(utf16le)]), atom_codes(C, [0x1F600]), put_char(W, C), nl(W), close(W), outbytes(L), R = L"),
    ("d377", raw"outfile(F), open(F, write, W, [encoding(utf16le), newline(dos)]), put_code(W, 0'a), nl(W), close(W), outbytes(L), R = L"),
    ("d378", raw"wenc(utf16be, [0'a, 0'b, 0'c]), outfile(F), open(F, read, S, [encoding(utf16be)]), seek(S, 4, bof, N), get_code(S, C), close(S), R = N-C"),
    ("d379", raw"outfile(F), open(F, write, W, [encoding(utf16be)]), cerr(put_code(W, 0xD800), R0), catch(close(W), _, true), R = R0"),
    ("d380", raw"outfile(F), cerr(open(F, read, _, [type(binary), encoding(utf16be)]), R)"),
    ("d381", raw"wenc(utf16be, [0'a, 10, 0'b]), outfile(F), open(F, read, S, [encoding(utf16be)]), read_pending_codes(S, L, []), '$stream_property'(S, position(P)), close(S), R = L-P"),
    ("d382", raw"wenc(utf16le, [0x1F600, 0'z]), outfile(F), open(F, read, S, [encoding(utf16le)]), get_char(S, A), peek_char(S, B), close(S), atom_codes(A, Ac), R = Ac-B")
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
    "t_d211 c[116,95,100,50,49,49]/1(c[45]/2(i18,i98))",
    "t_d212 c[116,95,100,50,49,50]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,nil)))))))))))))))))))",
    "t_d213 c[116,95,100,50,49,51]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,nil)))))))))))))))))))",
    "t_d214 c[116,95,100,50,49,52]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,c[91,124,93]/2(i122,nil))))))))))))))))))))",
    "t_d215 c[116,95,100,50,49,53]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],c[91,124,93]/2(a[10],c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],c[91,124,93]/2(a[122],c[91,124,93]/2(a[10],c[91,124,93]/2(a[108],c[91,124,93]/2(a[97],c[91,124,93]/2(a[115],c[91,124,93]/2(a[116],c[91,124,93]/2(a[32],c[91,124,93]/2(a[108],c[91,124,93]/2(a[105],c[91,124,93]/2(a[110],c[91,124,93]/2(a[101],c[91,124,93]/2(a[10],nil)))))))))))))))))))",
    "t_d216 c[116,95,100,50,49,54]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],c[91,124,93]/2(a[10],c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],c[91,124,93]/2(a[122],c[91,124,93]/2(a[10],c[91,124,93]/2(a[108],c[91,124,93]/2(a[97],c[91,124,93]/2(a[115],c[91,124,93]/2(a[116],c[91,124,93]/2(a[32],c[91,124,93]/2(a[108],c[91,124,93]/2(a[105],c[91,124,93]/2(a[110],c[91,124,93]/2(a[101],c[91,124,93]/2(a[10],c[91,124,93]/2(a[122],nil))))))))))))))))))))",
    "t_d217 c[116,95,100,50,49,55]/1(i-1)",
    "t_d218 c[116,95,100,50,49,56]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i18,i4,i0,i18))",
    "t_d219 c[116,95,100,50,49,57]/1(c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,nil)))))))))))))))))",
    "t_d220 c[116,95,100,50,50,48]/1(c[45]/2(c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,nil))))))))))))))))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i18,i4,i0,i18)))",
    "t_d221 c[116,95,100,50,50,49]/1(nil)",
    "t_d222 c[116,95,100,50,50,50]/1(c[45]/2(nil,nil))",
    "t_d223 c[116,95,100,50,50,51]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,nil)))))))))))))))))))",
    "t_d224 c[116,95,100,50,50,52]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,nil)))))))))))))))))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i18,i4,i0,i18)))",
    "t_d225 c[116,95,100,50,50,53]/1(c[45]/2(c[91,124,93]/2(i24930,c[91,124,93]/2(i25354,c[91,124,93]/2(i30841,c[91,124,93]/2(i31242,c[91,124,93]/2(i27745,c[91,124,93]/2(i29556,c[91,124,93]/2(i8300,c[91,124,93]/2(i26990,c[91,124,93]/2(i25866,nil))))))))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i9,i1,i16,i18)))",
    "t_d226 c[116,95,100,50,50,54]/1(c[91,124,93]/2(i25185,c[91,124,93]/2(i2659,c[91,124,93]/2(i31096,c[91,124,93]/2(i2682,c[91,124,93]/2(i24940,c[91,124,93]/2(i29811,c[91,124,93]/2(i27680,c[91,124,93]/2(i28265,c[91,124,93]/2(i2661,nil))))))))))",
    "t_d227 c[116,95,100,50,50,55]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i233,c[91,124,93]/2(i8364,c[91,124,93]/2(i128512,c[91,124,93]/2(i98,nil))))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i5,i1,i6,i11)))",
    "t_d228 c[116,95,100,50,50,56]/1(a[97,233,8364,128512,98])",
    "t_d229 c[116,95,100,50,50,57]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i128512,c[91,124,93]/2(i98,nil))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i3,i1,i4,i8)))",
    "t_d230 c[116,95,100,50,51,48]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i128512,c[91,124,93]/2(i98,nil))))",
    "t_d231 c[116,95,100,50,51,49]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i10,c[91,124,93]/2(i98,nil))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i3,i2,i1,i4)))",
    "t_d232 c[116,95,100,50,51,50]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i13,c[91,124,93]/2(i10,c[91,124,93]/2(i98,nil)))))",
    "t_d233 c[116,95,100,50,51,51]/1(c[45]/2(i4096,i904))",
    "t_d234 c[116,95,100,50,51,52]/1(c[45]/2(a[110,111],i97))",
    "t_d235 c[116,95,100,50,51,53]/1(c[45]/2(a[121,101,115],c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,c[91,124,93]/2(i113,nil)))))))))))))))))))))",
    "t_d236 c[116,95,100,50,51,54]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil))))",
    "t_d237 c[116,95,100,50,51,55]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,nil)))))))))))))))))))",
    "t_d238 c[116,95,100,50,51,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d239 c[116,95,100,50,51,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d240 c[116,95,100,50,52,48]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d241 c[116,95,100,50,52,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d242 c[116,95,100,50,52,50]/1(a[102,97,105,108,101,100])",
    "t_d243 c[116,95,100,50,52,51]/1(c[114,97,105,115,101,100]/1(c[114,101,115,111,117,114,99,101,95,101,114,114,111,114]/1(a[115,116,97,99,107])))",
    "t_d244 c[116,95,100,50,52,52]/1(c[45]/2(c[91,124,93]/2(i99,c[91,124,93]/2(i10,c[91,124,93]/2(i120,c[91,124,93]/2(i121,c[91,124,93]/2(i122,c[91,124,93]/2(i10,c[91,124,93]/2(i108,c[91,124,93]/2(i97,c[91,124,93]/2(i115,c[91,124,93]/2(i116,c[91,124,93]/2(i32,c[91,124,93]/2(i108,c[91,124,93]/2(i105,c[91,124,93]/2(i110,c[91,124,93]/2(i101,c[91,124,93]/2(i10,V0)))))))))))))))),V0))",
    "t_d245 c[116,95,100,50,52,53]/1(i-1)",
    "t_d246 c[116,95,100,50,52,54]/1(c[45]/2(c[45]/2(i2048,i453),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i2501,i1,i2501,i5001)))",
    "t_d247 c[116,95,100,50,52,55]/1(c[45]/2(c[45]/2(a[112,111,115,105,120],a[100,111,115]),c[91,124,93]/2(i97,c[91,124,93]/2(i10,c[91,124,93]/2(i98,nil)))))",
    "t_d248 c[116,95,100,50,52,56]/1(a[102,97,105,108,101,100])",
    "t_d249 c[116,95,100,50,52,57]/1(a[102,97,105,108,101,100])",
    "t_d250 c[116,95,100,50,53,48]/1(c[45]/2(c[45]/2(a[102,97,105,108,101,100],c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i1,i1,i1,i1)),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i1,i1,i1,i1)))",
    "t_d251 c[116,95,100,50,53,49]/1(c[45]/2(c[91,124,93]/2(i174285409,c[91,124,93]/2(i175798648,c[91,124,93]/2(i1953718636,c[91,124,93]/2(i1852402720,nil)))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i4,i1,i0,i16)))",
    "t_d252 c[116,95,100,50,53,50]/1(nil)",
    "t_d253 c[116,95,100,50,53,51]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i10,c[91,124,93]/2(i98,nil))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i3,i2,i1,i4)))",
    "t_d254 c[116,95,100,50,53,52]/1(c[45]/2(s[97,98,99],i97))",
    "t_d255 c[116,95,100,50,53,53]/1(s[])",
    "t_d256 c[116,95,100,50,53,54]/1(s[97,98,99,10,120,121,122,10,108,97,115,116,32,108,105,110,101,10])",
    "t_d257 c[116,95,100,50,53,55]/1(s[97,98,99,10,120,121,122,10,108,97,115,116,32,108,105,110,101,10])",
    "t_d258 c[116,95,100,50,53,56]/1(s[97,98,99,10,120,121,122,10,108,97,115,116,32,108,105,110,101,10])",
    "t_d259 c[116,95,100,50,53,57]/1(s[97,98,99,10,120])",
    "t_d260 c[116,95,100,50,54,48]/1(c[45]/2(s[97,98,99,10,120],c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0)))",
    "t_d261 c[116,95,100,50,54,49]/1(c[45]/2(s[99,10,120],i99))",
    "t_d262 c[116,95,100,50,54,50]/1(s[])",
    "t_d263 c[116,95,100,50,54,51]/1(c[45]/2(s[97,98,99],s[97,98,99]))",
    "t_d264 c[116,95,100,50,54,52]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,c[91,124,93]/2(i10,nil)))))",
    "t_d265 c[116,95,100,50,54,53]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i233,c[91,124,93]/2(i8364,nil))),i97))",
    "t_d266 c[116,95,100,50,54,54]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i233,c[91,124,93]/2(i8364,c[91,124,93]/2(i128512,c[91,124,93]/2(i98,nil))))))",
    "t_d269 c[116,95,100,50,54,57]/1(c[91,124,93]/2(i233,nil))",
    "t_d270 c[116,95,100,50,55,48]/1(i5000)",
    "t_d271 c[116,95,100,50,55,49]/1(i5000)",
    "t_d272 c[116,95,100,50,55,50]/1(c[45]/2(i4500,a[97]))",
    "t_d273 c[116,95,100,50,55,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_d274 c[116,95,100,50,55,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_d275 c[116,95,100,50,55,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d276 c[116,95,100,50,55,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d277 c[116,95,100,50,55,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d278 c[116,95,100,50,55,56]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d279 c[116,95,100,50,55,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d280 c[116,95,100,50,56,48]/1(a[102,97,105,108,101,100])",
    "t_d281 c[116,95,100,50,56,49]/1(a[111,107])",
    "t_d282 c[116,95,100,50,56,50]/1(c[45]/2(s[104,101,108],i104))",
    "t_d283 c[116,95,100,50,56,51]/1(s[104,101,108,108,111])",
    "t_d284 c[116,95,100,50,56,52]/1(s[97,98])",
    "t_d285 c[116,95,100,50,56,53]/1(a[121,101,115])",
    "t_d286 c[116,95,100,50,56,54]/1(a[97,98,99,10,120,121,122,10,108,97,115,116,32,108,105,110,101,10])",
    "t_d287 c[116,95,100,50,56,55]/1(a[97,98,99,10,120])",
    "t_d288 c[116,95,100,50,56,56]/1(a[])",
    "t_d289 c[116,95,100,50,56,57]/1(a[97,98,99,10,120,121,122,10,108,97,115,116,32,108,105,110,101,10])",
    "t_d290 c[116,95,100,50,57,48]/1(a[])",
    "t_d291 c[116,95,100,50,57,49]/1(c[45]/2(a[98,99,10],i120))",
    "t_d292 c[116,95,100,50,57,50]/1(a[98,99,10,120,121,122,10,108,97,115,116,32,108,105,110,101,10])",
    "t_d293 c[116,95,100,50,57,51]/1(i18)",
    "t_d294 c[116,95,100,50,57,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_d295 c[116,95,100,50,57,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d296 c[116,95,100,50,57,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f2.5)))",
    "t_d297 c[116,95,100,50,57,55]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d298 c[116,95,100,50,57,56]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d299 c[116,95,100,50,57,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d300 c[116,95,100,51,48,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[102,111,111])))",
    "t_d301 c[116,95,100,51,48,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d302 c[116,95,100,51,48,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d303 c[116,95,100,51,48,51]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i233,c[91,124,93]/2(i8364,c[91,124,93]/2(i128512,c[91,124,93]/2(i98,nil))))))",
    "t_d304 c[116,95,100,51,48,52]/1(i5000)",
    "t_d305 c[116,95,100,51,48,53]/1(s[97,98,99,10])",
    "t_d306 c[116,95,100,51,48,54]/1(a[])",
    "t_d307 c[116,95,100,51,48,55]/1(a[97,98,99,10,120,121,122,10,108,97])",
    "t_d308 c[116,95,100,51,48,56]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d309 c[116,95,100,51,48,57]/1(a[104,101,108])",
    "t_d310 c[116,95,100,51,49,48]/1(a[121,101,115])",
    "t_d311 c[116,95,100,51,49,49]/1(a[116,119,105,99,101])",
    "t_d312 c[116,95,100,51,49,50]/1(a[110,111,110,101])",
    "t_d314 c[116,95,100,51,49,52]/1(a[121,101,115])",
    "t_d315 c[116,95,100,51,49,53]/1(a[110,111])",
    "t_d316 c[116,95,100,51,49,54]/1(a[97])",
    "t_d317 c[116,95,100,51,49,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_d319 c[116,95,100,51,49,57]/1(c[45]/2(a[97],a[98]))",
    "t_d320 c[116,95,100,51,50,48]/1(c[45]/2(a[111,107],i0))",
    "t_d321 c[116,95,100,51,50,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,112,111,115,105,116,105,111,110],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d322 c[116,95,100,51,50,50]/1(a[111,107])",
    "t_d323 c[116,95,100,51,50,51]/1(c[114,97,105,115,101,100]/1(c[105,111,95,101,114,114,111,114]/2(a[114,101,97,100],a[60,115,116,114,101,97,109,62])))",
    "t_d324 c[116,95,100,51,50,52]/1(a[111,107])",
    "t_d325 c[116,95,100,51,50,53]/1(i65)",
    "t_d326 c[116,95,100,51,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_d327 c[116,95,100,51,50,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,111,117,114,99,101,95,115,105,110,107],c[112,105,112,101]/1(a[116,114,117,101]))))",
    "t_d328 c[116,95,100,51,50,56]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_d329 c[116,95,100,51,50,57]/1(a[110,111,102,105,108,101])",
    "t_d330 c[116,95,100,51,51,48]/1(a[102,97,108,115,101])",
    "t_d331 c[116,95,100,51,51,49]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0))",
    "t_d332 c[116,95,100,51,51,50]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i3,i2,i1,i3))",
    "t_d333 c[116,95,100,51,51,51]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil))))",
    "t_d334 c[116,95,100,51,51,52]/1(c[45]/2(s[97,98],a[97]))",
    "t_d335 c[116,95,100,51,51,53]/1(a[97,98,99])",
    "t_d336 c[116,95,100,51,51,54]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,112,111,115,105,116,105,111,110],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d337 c[116,95,100,51,51,55]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,112,111,115,105,116,105,111,110],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d338 c[116,95,100,51,51,56]/1(c[45]/2(i1,a[98]))",
    "t_d339 c[116,95,100,51,51,57]/1(c[45]/2(c[45]/2(a[111,107],i1),a[98]))",
    "t_d340 c[116,95,100,51,52,48]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,112,111,115,105,116,105,111,110],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d341 c[116,95,100,51,52,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,112,111,115,105,116,105,111,110],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_d342 c[116,95,100,51,52,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[108,111,99,107],a[102,111,111])))",
    "t_d343 c[116,95,100,51,52,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[108,111,99,107],a[102,111,111])))",
    "t_d344 c[116,95,100,51,52,52]/1(a[116,114,117,101])",
    "t_d345 c[116,95,100,51,52,53]/1(a[102,97,108,115,101])",
    "t_d346 c[116,95,100,51,52,54]/1(a[116,114,117,101])",
    "t_d347 c[116,95,100,51,52,55]/1(a[102,97,108,115,101])",
    "t_d348 c[116,95,100,51,52,56]/1(a[102,97,108,115,101])",
    "t_d349 c[116,95,100,51,52,57]/1(a[116,114,117,101])",
    "t_d351 c[116,95,100,51,53,49]/1(c[91,124,93]/2(i0,c[91,124,93]/2(i97,c[91,124,93]/2(i216,c[91,124,93]/2(i61,c[91,124,93]/2(i222,c[91,124,93]/2(i0,c[91,124,93]/2(i0,c[91,124,93]/2(i98,nil)))))))))",
    "t_d352 c[116,95,100,51,53,50]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i0,c[91,124,93]/2(i61,c[91,124,93]/2(i216,c[91,124,93]/2(i0,c[91,124,93]/2(i222,c[91,124,93]/2(i98,c[91,124,93]/2(i0,nil)))))))))",
    "t_d353 c[116,95,100,51,53,51]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i0,c[91,124,93]/2(i0,c[91,124,93]/2(i0,c[91,124,93]/2(i0,c[91,124,93]/2(i246,c[91,124,93]/2(i1,c[91,124,93]/2(i0,nil)))))))))",
    "t_d354 c[116,95,100,51,53,52]/1(c[91,124,93]/2(i0,c[91,124,93]/2(i97,c[91,124,93]/2(i32,c[91,124,93]/2(i172,nil)))))",
    "t_d355 c[116,95,100,51,53,53]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i8364,nil)))",
    "t_d356 c[116,95,100,51,53,54]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i128512,c[91,124,93]/2(i65535,c[91,124,93]/2(i98,nil)))))",
    "t_d357 c[116,95,100,51,53,55]/1(c[91,124,93]/2(i128512,c[91,124,93]/2(i1114111,c[91,124,93]/2(i8364,nil))))",
    "t_d358 c[116,95,100,51,53,56]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i128512,c[91,124,93]/2(i1114111,nil))))",
    "t_d359 c[116,95,100,51,53,57]/1(c[91,124,93]/2(i254,c[91,124,93]/2(i255,c[91,124,93]/2(i0,c[91,124,93]/2(i97,nil)))))",
    "t_d360 c[116,95,100,51,54,48]/1(c[91,124,93]/2(i255,c[91,124,93]/2(i254,c[91,124,93]/2(i97,c[91,124,93]/2(i0,nil)))))",
    "t_d361 c[116,95,100,51,54,49]/1(c[45]/2(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i128512,nil)),c[101,110,99,111,100,105,110,103]/1(a[117,116,102,49,54,108,101])),a[121,101,115]))",
    "t_d362 c[116,95,100,51,54,50]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i128512,nil)),c[101,110,99,111,100,105,110,103]/1(a[117,116,102,49,54,98,101])))",
    "t_d363 c[116,95,100,51,54,51]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i233,nil)),c[101,110,99,111,100,105,110,103]/1(a[117,116,102,56])))",
    "t_d364 c[116,95,100,51,54,52]/1(c[91,124,93]/2(i255,c[91,124,93]/2(i254,c[91,124,93]/2(i97,c[91,124,93]/2(i0,nil)))))",
    "t_d365 c[116,95,100,51,54,53]/1(c[45]/2(i65533,i97))",
    "t_d366 c[116,95,100,51,54,54]/1(c[45]/2(i65533,i-1))",
    "t_d367 c[116,95,100,51,54,55]/1(c[45]/2(i65533,i-1))",
    "t_d368 c[116,95,100,51,54,56]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i65533,c[91,124,93]/2(i-1,nil))))",
    "t_d369 c[116,95,100,51,54,57]/1(c[45]/2(i65533,i-1))",
    "t_d370 c[116,95,100,51,55,48]/1(c[91,124,93]/2(i0,c[91,124,93]/2(i39,c[91,124,93]/2(i0,c[91,124,93]/2(i233,c[91,124,93]/2(i216,c[91,124,93]/2(i61,c[91,124,93]/2(i222,c[91,124,93]/2(i0,c[91,124,93]/2(i0,c[91,124,93]/2(i39,nil)))))))))))",
    "t_d371 c[116,95,100,51,55,49]/1(c[102,111,111]/2(a[98,97,114],a[120,128512]))",
    "t_d372 c[116,95,100,51,55,50]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i0,c[91,124,93]/2(i98,c[91,124,93]/2(i32,c[91,124,93]/2(i172,nil))))))",
    "t_d373 c[116,95,100,51,55,51]/1(c[91,124,93]/2(i128512,c[91,124,93]/2(i128512,c[91,124,93]/2(i97,nil))))",
    "t_d374 c[116,95,100,51,55,52]/1(c[91,124,93]/2(i4,c[91,124,93]/2(i1,c[91,124,93]/2(i6,nil))))",
    "t_d375 c[116,95,100,51,55,53]/1(c[91,124,93]/2(c[101,110,99,111,100,105,110,103]/1(a[117,116,102,49,54,98,101]),c[91,124,93]/2(c[101,110,99,111,100,105,110,103]/1(a[117,116,102,49,54,108,101]),c[91,124,93]/2(c[101,110,99,111,100,105,110,103]/1(a[119,99,104,97,114,95,116]),nil))))",
    "t_d376 c[116,95,100,51,55,54]/1(c[91,124,93]/2(i61,c[91,124,93]/2(i216,c[91,124,93]/2(i0,c[91,124,93]/2(i222,c[91,124,93]/2(i10,c[91,124,93]/2(i0,nil)))))))",
    "t_d377 c[116,95,100,51,55,55]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i0,c[91,124,93]/2(i13,c[91,124,93]/2(i0,c[91,124,93]/2(i10,c[91,124,93]/2(i0,nil)))))))",
    "t_d378 c[116,95,100,51,55,56]/1(c[45]/2(i4,i-1))",
    "t_d379 c[116,95,100,51,55,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i55296)))",
    "t_d380 c[116,95,100,51,56,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,110,99,111,100,105,110,103],a[117,116,102,49,54,98,101])))",
    "t_d381 c[116,95,100,51,56,49]/1(c[45]/2(c[91,124,93]/2(i97,c[91,124,93]/2(i10,c[91,124,93]/2(i98,nil))),c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i3,i2,i1,i6)))",
    "t_d382 c[116,95,100,51,56,50]/1(c[45]/2(c[91,124,93]/2(i128512,nil),a[122]))"
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
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _LD_PINNED) == 111     # raised(…)
    @test count(l -> endswith(l, "/1(a[102,97,105,108,101,100])"), _LD_PINNED) == 13   # failed
    @test count(l -> endswith(l, "/1(a[111,107])"), _LD_PINNED) == 14                 # ok
end

"Whether the kernel REFUSES `goal` (a `NotPortedError` out of the foreign predicate), the goal run in a fresh database."
function _ld_refuses(goal::String)::Bool
    dir = mktempdir()
    f = joinpath(dir, "refuse.pl")
    write(f, "t_refuse(_) :- $goal.\n")
    gd = LK.PL_global_data{_LD}()
    ld = LK.PL_local_data{_LD}(gd)
    st, _, _ = LK.load_file!(gd, ld, f)
    st === :ok || return false
    proc = LK.isCurrentProcedure(sym_key(_lds("t_refuse")), 1, LK.MODULE_user(gd))
    proc === nothing && return false
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_LD, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a)
    refused = try
        LK.PL_next_solution(gd, ld, qid)
        false
    catch e
        e isa LK.NotPortedError || rethrow()
        true
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return refused
end

# Named refusals (NotPortedError): swipl answers these (its `tee` copies the standard streams into the protocol file), the kernel has no
# `tee`: no pin to compare, the refusal itself is the row. Each goal names the pin's file:line (pin 18168e62).
@testset "named refusals: protocol/1, protocola/1 (pl-file.c:3747, 3753: openProtocol 2080)" begin
    @test _ld_refuses("protocol('/dev/null')")
    @test _ld_refuses("protocola('/dev/null')")
    # the same refusal raises before the file is touched: a goal that cannot be a file is refused too
    @test _ld_refuses("protocol(_)")
    # not vacuous: the neighbouring predicates that ARE ported answer (rows d310-d312)
    @test !_ld_refuses("noprotocol")
    @test !_ld_refuses("\\+ protocolling(_)")
end

# open/4's lock(Lock) option: pl-file.c:4290-4310 (the `l`/`L` + `r`/`w` letters of `how`), pl-stream.c Sopen_file's fcntl(F_SETLK[W]). The kernel
# has no fcntl locks (Sopen_file answers EINVAL for `l`/`L`), the option is a named refusal after its domain check (rows d342, d343).
# Slock/Sunlock/StryLock/Sshare (pl-stream.c:345-395, thread mutex and the `locks` count) have no twin: one thread, DIVERGES comments say so.
@testset "named refusals: open/4's lock(Lock) option (pl-file.c:4290-4310)" begin
    @test _ld_refuses("open('/dev/null', read, _, [lock(read)])")
    @test _ld_refuses("open('/dev/null', read, _, [lock(shared)])")
    @test _ld_refuses("open('/dev/null', write, _, [lock(write)])")
    @test _ld_refuses("open('/dev/null', write, _, [lock(exclusive)])")
    @test !_ld_refuses("open('/dev/null', read, S, [lock(none)]), close(S)")
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

# ENC_ANSI (open/4 encoding(text), pl-file.c encoding_names `text`; pl-stream.c put_code/Sgetcode ENC_ANSI arms: wcrtomb/mbrtowc under the
# C library's locale): a named refusal, swipl answers it from the locale (ENC1). The UTF-16 and wchar_t encodings are PORTED (rows d351-d382).
@testset "named refusal: open/4 with encoding(text) (ENC_ANSI, locale conversion)" begin
    @test _ld_refuses("open('/dev/null', read, S, [encoding(text)]), close(S)")
    @test _ld_refuses("open('/dev/null', write, S, [encoding(text)]), close(S)")
    # set_stream/2 reaches the same encoding on an open stream: the refusal is then put_code's and Sgetcode's
    @test _ld_refuses("open('/dev/null', write, S), set_stream(S, encoding(text)), put_code(S, 0'a), close(S)")
    @test _ld_refuses("open('/dev/null', read, S), set_stream(S, encoding(text)), get_code(S, _), close(S)")
    # not vacuous: the ported neighbours are accepted
    @test !_ld_refuses("open('/dev/null', write, S), set_stream(S, encoding(utf16le)), put_code(S, 0'a), close(S)")
    @test !_ld_refuses("open('/dev/null', read, S), set_stream(S, encoding(utf16be)), get_code(S, _), close(S)")
    @test !_ld_refuses("open('/dev/null', read, S, [encoding(utf16be)]), close(S)")
    @test !_ld_refuses("open('/dev/null', read, S, [encoding(wchar_t)]), close(S)")
end
