# ORIGINAL: S2a's gate (R2 boot C predicates, audit D-0306 item 2) — the stream predicates of pl-file.c the boot files call, against swipl 10.1.19
# test/core_lang/test_s2a_swipl.jl — prompt/2 and prompt1/1 (pl-file.c:3735, :3778), '$push_input_context'/1, '$pop_input_context'/0, '$input_context'/1
# (:1623-1647), flush_output/1 (:5516), ttyflush/0, is_stream/1 (:5476), '$alias_stream'/2 (:5457), get_char/2 (:3676), peek_char/2 (:5954), skip/2 (:3549),
# '$stream_property'/2, '$stream_properties'/2, '$streams_properties'/2 (:5265-5440) and set_stream/2 (:2520), with its refusals' neighbours:
#   * A PROGRAM consulted by the kernel's loader — helper clauses over a data file and an output file — and cases `t_<id>(R)` run IN ORDER in one
#     database, each wrapped in `catch(Goal, error(F, _), R = raised(F))` (a stream blob in F becomes '<stream>'; no row answers a blob or a path).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, two byte-identical runs, 2026-11-01, evidence/S2A/s2a_rows.out); with `swipl` on
#     PATH the live answers are compared with the pins too. NOT in the rows (kernel answers differ from swipl by the audit's DIVERGES): timeout(Seconds),
#     close_on_exec(Bool), alias(Std) of a standard stream, locale(L), unicode_atoms(nfc), and get_single_char/1 (reads the process's stdin).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream layer (src/os/pl-file.jl, src/os/pl-stream.jl) over the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _S2 = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_s2s(x) = lk_sym(_S2, Symbol(x))

_s2_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _s2_enc(t::_S2, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _s2_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _s2_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _s2_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_s2_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _S2_DRIVER = raw"""
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
function _s2_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _S2_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: helper clauses over a data file (`@DATA@`, "abc\nxyz\nlast line\n") and an output file (`@OUT@`), both substituted at run time.
# No row answers a stream blob or a path: errors go through `nb/2` (a blob argument becomes '<stream>'), a file name is compared with `==`.
const _S2_PROGRAM = raw"""
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
p1str :- prompt1("s").
fnstr(S) :- set_stream(S, file_name("str")).
ctxd(D1, D2) :-
    '$input_context'(L0), cnt(L0, N0), '$push_input_context'(ctx), '$input_context'(L1), cnt(L1, N1),
    '$pop_input_context', '$input_context'(L2), cnt(L2, N2), D1 is N1-N0, D2 is N2-N0.
ctxe(R) :-
    '$push_input_context'(ctx2), '$input_context'([E|_]), '$pop_input_context',
    functor(E, Nm, A), call(arg, 1, E, T), R = Nm/A/T.
ctxo(T1, T2) :-
    '$push_input_context'(ca), '$push_input_context'(cb), '$input_context'([E1, E2|_]),
    '$pop_input_context', '$pop_input_context', call(arg, 1, E1, T1), call(arg, 1, E2, T2).
aliasbl(S, R) :- '$alias_stream'(zz1, S2), ( S2 == S -> R = same ; R = other ).
spairs(S, R) :-
    '$streams_properties'(alias(zz4), L), cnt(L, N), L = [S0-V|_], '$alias_stream'(zz4, SB),
    ( SB == S0 -> W = same ; W = other ), S = S0, R = N-W-V.
"""

# (id, goal), run IN ORDER
const _S2_CASES = [
    # s001-s006: prompt/2 (pl-file.c:3735): the old prompt comes back, the new one is set, a same-atom call keeps it, a non-atom raises
    ("s001", raw"prompt(_, abc), prompt(O, def), R = O"),
    ("s002", raw"prompt(_, x), prompt(A, A), prompt(B, B), R = A-B"),
    ("s003", raw"prompt(_, 123)"),
    ("s004", raw"prompt(_, f(x))"),
    ("s005", raw"prompt(_, abc), prompt(foo, N), R = N"),
    ("s006", raw"prompt(_, '|: '), prompt(O, O), R = O"),
    # s007-s011: prompt1/1 (pl-file.c:3778): atom, string, number accepted; unbound fails; a compound raises
    ("s007", raw"prompt1(abc), R = ok"),
    ("s008", raw"p1str, R = ok"),
    ("s009", raw"prompt1(12), R = ok"),
    ("s010", raw"cerr(prompt1(_), R)"),
    ("s011", raw"prompt1(f(x))"),
    # s012-s016: the input context trio ($push_input_context/1, $pop_input_context/0, $input_context/1; pl-file.c:1623-1647)
    ("s012", raw"ctxd(D1, D2), R = D1-D2"),
    ("s013", raw"ctxe(R)"),
    ("s014", raw"ctxo(T1, T2), R = T1-T2"),
    ("s015", raw"'$push_input_context'(f(x))"),
    ("s016", raw"'$push_input_context'(_)"),
    # s017-s025: flush_output/1 (pl-file.c:5516), ttyflush/0
    ("s017", raw"flush_output(user_output), R = ok"),
    ("s018", raw"flush_output(nosuch)"),
    ("s019", raw"flush_output(_)"),
    ("s020", raw"flush_output(foo(x))"),
    ("s021", raw"ro(S), cerr(flush_output(S), R0), close(S), R = R0"),
    ("s022", raw"wo(S), flush_output(S), close(S), R = ok"),
    ("s023", raw"wo(S), close(S), cerr(flush_output(S), R)"),
    ("s024", raw"cerr(flush_output(user_input), R)"),
    ("s025", raw"ttyflush, R = ok"),
    # s026-s031: is_stream/1 (pl-file.c:5476)
    ("s026", raw"( is_stream(user_input) -> R = yes ; R = no )"),
    ("s027", raw"( is_stream(nosuch) -> R = yes ; R = no )"),
    ("s028", raw"( is_stream(_) -> R = yes ; R = no )"),
    ("s029", raw"( is_stream(f(x)) -> R = yes ; R = no )"),
    (
        "s030",
        raw"ro(S), ( is_stream(S) -> A = yes ; A = no ), close(S), ( is_stream(S) -> B = yes ; B = no ), R = A-B"
    ),
    ("s031", raw"( is_stream(user_error) -> R = yes ; R = no )"),
    # s032-s037: $alias_stream/2 (pl-file.c:5457)
    ("s032", raw"'$alias_stream'(user_output, S), ( is_stream(S) -> R = yes ; R = no )"),
    ("s033", raw"'$alias_stream'(nosuch, _), R = found"),
    ("s034", raw"'$alias_stream'(1, _)"),
    ("s035", raw"'$alias_stream'(_, _)"),
    ("s036", raw"ro(S), set_stream(S, alias(zz1)), aliasbl(S, R0), close(S), R = R0"),
    (
        "s037",
        raw"ro(S), set_stream(S, alias(zz2)), close(S), cerr('$alias_stream'(zz2, _), R)"
    ),
    # s038-s060: get_char/2 (3676), peek_char/2 (5954), skip/2 (3549) over a file stream
    (
        "s038",
        raw"ro(S), get_char(S, A), get_char(S, B), peek_char(S, P), get_char(S, C), close(S), R = [A, B, P, C]"
    ),
    (
        "s039",
        raw"ro(S), get_char(S, _), get_char(S, _), get_char(S, _), get_char(S, N), close(S), R = N"
    ),
    ("s040", raw"ro(S), skip(S, 120), get_char(S, C), close(S), R = C"),
    ("s041", raw"ro(S), skip(S, y), get_char(S, C), close(S), R = C"),
    (
        "s042",
        raw"ro(S), skip(S, 33), get_char(S, C1), get_char(S, C2), close(S), R = C1-C2"
    ),
    ("s043", raw"ro(S), skip(S, 33), peek_char(S, C), close(S), R = C"),
    (
        "s044",
        raw"ro(S), set_stream(S, eof_action(error)), skip(S, 33), get_char(S, C1), cerr(get_char(S, _), R0), close(S), R = C1-R0"
    ),
    (
        "s045",
        raw"ro(S), set_stream(S, eof_action(reset)), skip(S, 33), get_char(S, C1), get_char(S, C2), close(S), R = C1-C2"
    ),
    ("s046", raw"ro(S), cerr(get_char(S, 1), R0), close(S), R = R0"),
    ("s047", raw"ro(S), cerr(get_char(S, ab), R0), close(S), R = R0"),
    ("s048", raw"ro(S), cerr(peek_char(S, 1), R0), close(S), R = R0"),
    ("s049", raw"ro(S), cerr(skip(S, foo), R0), close(S), R = R0"),
    ("s050", raw"ro(S), cerr(skip(S, 1.5), R0), close(S), R = R0"),
    ("s051", raw"wo(S), cerr(get_char(S, _), R0), close(S), R = R0"),
    ("s052", raw"get_char(nosuch, _)"),
    ("s053", raw"get_char(_, _)"),
    ("s054", raw"peek_char(nosuch, _)"),
    ("s055", raw"skip(nosuch, 97)"),
    # UNVERIFIED on the kernel: gate decides — a binary stream under get_char/2 (the SIO_TEXT test)
    (
        "s056",
        raw"ro(S), set_stream(S, type(binary)), cerr(get_char(S, _), R0), close(S), R = R0"
    ),
    ("s057", raw"rb(S), cerr(get_char(S, _), R0), close(S), R = R0"),
    (
        "s058",
        raw"ro(S), get_char(S, _), get_char(S, _), get_char(S, _), get_char(S, _), '$stream_property'(S, position(P)), close(S), R = P"
    ),
    (
        "s059",
        raw"ro(S), peek_char(S, _), '$stream_property'(S, position(P)), close(S), R = P"
    ),
    (
        "s060",
        raw"ro(S), sp(S, end_of_stream(E0), _), skip(S, 33), sp(S, end_of_stream(E1), _), get_char(S, _), sp(S, end_of_stream(E2), _), close(S), R = [E0, E1, E2]"
    ),
    # s061-s083: $stream_property/2 (5265), $stream_properties/2 (5344), $streams_properties/2 (5387), property by property
    ("s061", raw"ro(S), sp(S, mode(_), R0), close(S), R = R0"),
    ("s062", raw"ro(S), has(S, input, A), has(S, output, B), close(S), R = A-B"),
    (
        "s063",
        raw"wo(S), has(S, input, A), has(S, output, B), sp(S, mode(_), M), close(S), R = A-B-M"
    ),
    ("s064", raw"ro(S), sp(S, eof_action(_), R0), close(S), R = R0"),
    ("s065", raw"ro(S), sp(S, type(_), R0), close(S), R = R0"),
    ("s066", raw"ro(S), sp(S, buffer(_), R0), close(S), R = R0"),
    ("s067", raw"ro(S), sp(S, newline(_), R0), close(S), R = R0"),
    ("s068", raw"ro(S), fnp(S, R0), close(S), R = R0"),
    ("s069", raw"ra(S, zz3), sp(zz3, alias(_), R0), close(S), R = R0"),
    ("s070", raw"ro(S), sp(S, close_on_abort(_), R0), close(S), R = R0"),
    ("s071", raw"ro(S), sp(S, representation_errors(_), R0), close(S), R = R0"),
    ("s072", raw"ro(S), sp(S, write_errors(_), R0), close(S), R = R0"),
    ("s073", raw"ro(S), sp(S, unicode_atoms(_), R0), close(S), R = R0"),
    ("s074", raw"ro(S), sp(S, error(_), R0), close(S), R = R0"),
    ("s075", raw"ro(S), sp(S, position(_), R0), close(S), R = R0"),
    # UNVERIFIED on the kernel: gate decides — the answers below depend on the locale (encoding) or on the file layer (buffer size, reposition, timeout)
    ("s076", raw"ro(S), sp(S, encoding(_), R0), close(S), R = R0"),
    ("s077", raw"ro(S), sp(S, buffer_size(_), R0), close(S), R = R0"),
    ("s078", raw"ro(S), sp(S, reposition(_), R0), close(S), R = R0"),
    ("s079", raw"ro(S), sp(S, timeout(_), R0), close(S), R = R0"),
    (
        "s080",
        raw"ro(S), '$stream_properties'(S, L), keep(L, [mode, input, eof_action, type, buffer, close_on_abort, newline, representation_errors, write_errors, unicode_atoms, end_of_stream, error], K), close(S), R = K"
    ),
    ("s081", raw"ra(S, zz4), spairs(S0, R0), close(S0), R = R0"),
    ("s082", raw"'$streams_properties'(alias(nosuch), L), R = L"),
    (
        "s083",
        raw"ro(S), '$streams_properties'(mode(read), L), ( hasp(L, S) -> A = yes ; A = no ), '$streams_properties'(mode(write), L2), ( hasp(L2, S) -> B = yes ; B = no ), close(S), R = A-B"
    ),
    # s084-s088: $stream_property/2 on the wrong argument
    ("s084", raw"ro(S), cerr('$stream_property'(S, bogus(_)), R0), close(S), R = R0"),
    ("s085", raw"cerr('$stream_property'(nosuch, mode(_)), R)"),
    ("s086", raw"ro(S), close(S), cerr('$stream_property'(S, mode(_)), R)"),
    ("s087", raw"cerr('$stream_properties'(nosuch, _), R)"),
    ("s088", raw"cerr('$stream_properties'(_, _), R)"),
    # s089-s133: set_stream/2 (2520), attribute by attribute
    ("s089", raw"ro(S), set_stream(S, alias(zz5)), has(S, alias(zz5), A), close(S), R = A"),
    ("s090", raw"ro(S), cerr(set_stream(S, alias(_)), R0), close(S), R = R0"),
    ("s091", raw"ro(S), cerr(set_stream(S, alias(1)), R0), close(S), R = R0"),
    (
        "s092",
        raw"ro(S), set_stream(S, buffer(line)), sp(S, buffer(_), R0), close(S), R = R0"
    ),
    (
        "s093",
        raw"ro(S), set_stream(S, buffer(false)), sp(S, buffer(_), R0), close(S), R = R0"
    ),
    (
        "s094",
        raw"ro(S), set_stream(S, buffer(full)), sp(S, buffer(_), R0), close(S), R = R0"
    ),
    ("s095", raw"ro(S), cerr(set_stream(S, buffer(bad)), R0), close(S), R = R0"),
    (
        "s096",
        raw"wo(S), set_stream(S, buffer_size(100)), sp(S, buffer_size(_), R0), close(S), R = R0"
    ),
    ("s097", raw"wo(S), cerr(set_stream(S, buffer_size(0)), R0), close(S), R = R0"),
    ("s098", raw"wo(S), cerr(set_stream(S, buffer_size(a)), R0), close(S), R = R0"),
    (
        "s099",
        raw"ro(S), set_stream(S, eof_action(reset)), sp(S, eof_action(_), R0), close(S), R = R0"
    ),
    ("s100", raw"ro(S), cerr(set_stream(S, eof_action(bad)), R0), close(S), R = R0"),
    ("s101", raw"wo(S), cerr(set_stream(S, eof_action(reset)), R0), close(S), R = R0"),
    ("s102", raw"ro(S), set_stream(S, type(binary)), sp(S, type(_), R0), close(S), R = R0"),
    ("s103", raw"rb(S), set_stream(S, type(text)), sp(S, type(_), R0), close(S), R = R0"),
    ("s104", raw"ro(S), cerr(set_stream(S, type(foo)), R0), close(S), R = R0"),
    (
        "s105",
        raw"ro(S), set_stream(S, close_on_abort(false)), sp(S, close_on_abort(_), R0), close(S), R = R0"
    ),
    ("s106", raw"ro(S), cerr(set_stream(S, close_on_abort(foo)), R0), close(S), R = R0"),
    (
        "s107",
        raw"ro(S), set_stream(S, record_position(false)), sp(S, position(_), R0), close(S), R = R0"
    ),
    (
        "s108",
        raw"ro(S), set_stream(S, record_position(false)), cerr(set_stream(S, line_position(3)), R0), close(S), R = R0"
    ),
    (
        "s109",
        raw"wo(S), set_stream(S, line_position(3)), sp(S, position(_), R0), close(S), R = R0"
    ),
    ("s110", raw"wo(S), cerr(set_stream(S, line_position(a)), R0), close(S), R = R0"),
    (
        "s111",
        raw"ro(S), set_stream(S, record_position(false)), set_stream(S, record_position(true)), sp(S, position(_), R0), close(S), R = R0"
    ),
    (
        "s112",
        raw"ro(S), set_stream(S, file_name(abc)), sp(S, file_name(_), R0), close(S), R = R0"
    ),
    ("s113", raw"ro(S), fnstr(S), sp(S, file_name(_), R0), close(S), R = R0"),
    ("s114", raw"ro(S), cerr(set_stream(S, tty(true)), R0), close(S), R = R0"),
    ("s115", raw"ro(S), cerr(set_stream(S, tty(foo)), R0), close(S), R = R0"),
    (
        "s116",
        raw"ro(S), set_stream(S, encoding(octet)), sp(S, encoding(_), E), sp(S, type(_), T), close(S), R = E-T"
    ),
    (
        "s117",
        raw"rb(S), set_stream(S, encoding(utf8)), sp(S, encoding(_), E), sp(S, type(_), T), close(S), R = E-T"
    ),
    ("s118", raw"ro(S), cerr(set_stream(S, encoding(bogus)), R0), close(S), R = R0"),
    # UNVERIFIED on the kernel: gate decides — encoding(bom) on a file without a BOM (ScheckBOM)
    ("s119", raw"ro(S), cerr(set_stream(S, encoding(bom)), R0), close(S), R = R0"),
    (
        "s120",
        raw"ro(S), set_stream(S, unicode_atoms(error)), sp(S, unicode_atoms(_), R0), close(S), R = R0"
    ),
    ("s121", raw"ro(S), cerr(set_stream(S, unicode_atoms(bogus)), R0), close(S), R = R0"),
    (
        "s122",
        raw"wo(S), set_stream(S, representation_errors(xml)), sp(S, representation_errors(_), R0), close(S), R = R0"
    ),
    (
        "s123",
        raw"wo(S), set_stream(S, representation_errors(prolog)), sp(S, representation_errors(_), R0), close(S), R = R0"
    ),
    (
        "s124",
        raw"wo(S), cerr(set_stream(S, representation_errors(bogus)), R0), close(S), R = R0"
    ),
    (
        "s125",
        raw"wo(S), set_stream(S, write_errors(ignore)), sp(S, write_errors(_), R0), close(S), R = R0"
    ),
    ("s126", raw"wo(S), cerr(set_stream(S, write_errors(bogus)), R0), close(S), R = R0"),
    (
        "s127",
        raw"wo(S), set_stream(S, newline(dos)), sp(S, newline(_), R0), close(S), R = R0"
    ),
    ("s128", raw"wo(S), cerr(set_stream(S, newline(bad)), R0), close(S), R = R0"),
    ("s129", raw"ro(S), cerr(set_stream(S, foo(x)), R0), close(S), R = R0"),
    ("s130", raw"ro(S), cerr(set_stream(S, foo), R0), close(S), R = R0"),
    ("s131", raw"ro(S), cerr(set_stream(S, 1), R0), close(S), R = R0"),
    ("s132", raw"ro(S), cerr(set_stream(S, _), R0), close(S), R = R0"),
    ("s133", raw"cerr(set_stream(_, tty(true)), R)"),
    ("s134", raw"cerr(set_stream(nosuch, tty(true)), R)"),
    ("s135", raw"ro(S), close(S), cerr(set_stream(S, tty(true)), R)"),
    (
        "s136",
        raw"ro(S), set_stream(S, timeout(infinite)), sp(S, timeout(_), R0), close(S), R = R0"
    ),
    ("s137", raw"ro(S), cerr(set_stream(S, timeout(foo)), R0), close(S), R = R0")
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines; evidence/S2A/s2a_rows.out)
const _S2_PINNED = [
    "ok",
    "t_s001 c[116,95,115,48,48,49]/1(a[97,98,99])",
    "t_s002 c[116,95,115,48,48,50]/1(c[45]/2(a[120],a[120]))",
    "t_s003 c[116,95,115,48,48,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i123)))",
    "t_s004 c[116,95,115,48,48,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_s005",
    "t_s006 c[116,95,115,48,48,54]/1(a[124,58,32])",
    "t_s007 c[116,95,115,48,48,55]/1(a[111,107])",
    "t_s008 c[116,95,115,48,48,56]/1(a[111,107])",
    "t_s009 c[116,95,115,48,48,57]/1(a[111,107])",
    "t_s010 c[116,95,115,48,49,48]/1(a[111,107])",
    "t_s011 c[116,95,115,48,49,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120]))))",
    "t_s012 c[116,95,115,48,49,50]/1(c[45]/2(i1,i0))",
    "t_s013 c[116,95,115,48,49,51]/1(c[47]/2(c[47]/2(a[105,110,112,117,116],i4),a[99,116,120,50]))",
    "t_s014 c[116,95,115,48,49,52]/1(c[45]/2(a[99,98],a[99,97]))",
    "t_s015 c[116,95,115,48,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_s016 c[116,95,115,48,49,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_s017 c[116,95,115,48,49,55]/1(a[111,107])",
    "t_s018 c[116,95,115,48,49,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_s019 c[116,95,115,48,49,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_s020 c[116,95,115,48,50,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,111,114,95,97,108,105,97,115],c[102,111,111]/1(a[120]))))",
    "t_s021 c[116,95,115,48,50,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_s022 c[116,95,115,48,50,50]/1(a[111,107])",
    "t_s023 c[116,95,115,48,50,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_s024 c[116,95,115,48,50,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[119,114,105,116,101],a[115,116,114,101,97,109],a[117,115,101,114,95,105,110,112,117,116])))",
    "t_s025 c[116,95,115,48,50,53]/1(a[111,107])",
    "t_s026 c[116,95,115,48,50,54]/1(a[121,101,115])",
    "t_s027 c[116,95,115,48,50,55]/1(a[110,111])",
    "t_s028 c[116,95,115,48,50,56]/1(a[110,111])",
    "t_s029 c[116,95,115,48,50,57]/1(a[110,111])",
    "t_s030 c[116,95,115,48,51,48]/1(c[45]/2(a[121,101,115],a[110,111]))",
    "t_s031 c[116,95,115,48,51,49]/1(a[121,101,115])",
    "t_s032 c[116,95,115,48,51,50]/1(a[121,101,115])",
    "t_s033",
    "t_s034 c[116,95,115,48,51,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_s035 c[116,95,115,48,51,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_s036 c[116,95,115,48,51,54]/1(a[115,97,109,101])",
    "t_s037 c[116,95,115,48,51,55]/1(a[102,97,105,108,101,100])",
    "t_s038 c[116,95,115,48,51,56]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],c[91,124,93]/2(a[99],nil)))))",
    "t_s039 c[116,95,115,48,51,57]/1(a[10])",
    "t_s040 c[116,95,115,48,52,48]/1(a[121])",
    "t_s041 c[116,95,115,48,52,49]/1(a[122])",
    "t_s042 c[116,95,115,48,52,50]/1(c[45]/2(a[101,110,100,95,111,102,95,102,105,108,101],a[101,110,100,95,111,102,95,102,105,108,101]))",
    "t_s043 c[116,95,115,48,52,51]/1(a[101,110,100,95,111,102,95,102,105,108,101])",
    "t_s044 c[116,95,115,48,52,52]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[105,110,112,117,116],a[112,97,115,116,95,101,110,100,95,111,102,95,115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_s045 c[116,95,115,48,52,53]/1(c[45]/2(a[101,110,100,95,111,102,95,102,105,108,101],a[101,110,100,95,111,102,95,102,105,108,101]))",
    "t_s046 c[116,95,115,48,52,54]/1(a[102,97,105,108,101,100])",
    "t_s047 c[116,95,115,48,52,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[97,98])))",
    "t_s048 c[116,95,115,48,52,56]/1(a[102,97,105,108,101,100])",
    "t_s049 c[116,95,115,48,52,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[102,111,111])))",
    "t_s050 c[116,95,115,48,53,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],f1.5)))",
    "t_s051 c[116,95,115,48,53,49]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[114,101,97,100],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_s052 c[116,95,115,48,53,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_s053 c[116,95,115,48,53,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_s054 c[116,95,115,48,53,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_s055 c[116,95,115,48,53,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_s056 c[116,95,115,48,53,54]/1(a[111,107])",
    "t_s057 c[116,95,115,48,53,55]/1(a[111,107])",
    "t_s058 c[116,95,115,48,53,56]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i4,i2,i0,i4))",
    "t_s059 c[116,95,115,48,53,57]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0))",
    "t_s060 c[116,95,115,48,54,48]/1(c[91,124,93]/2(a[110,111,116],c[91,124,93]/2(a[97,116],c[91,124,93]/2(a[112,97,115,116],nil))))",
    "t_s061 c[116,95,115,48,54,49]/1(c[109,111,100,101]/1(a[114,101,97,100]))",
    "t_s062 c[116,95,115,48,54,50]/1(c[45]/2(a[121,101,115],a[110,111]))",
    "t_s063 c[116,95,115,48,54,51]/1(c[45]/2(c[45]/2(a[110,111],a[121,101,115]),c[109,111,100,101]/1(a[119,114,105,116,101])))",
    "t_s064 c[116,95,115,48,54,52]/1(c[101,111,102,95,97,99,116,105,111,110]/1(a[101,111,102,95,99,111,100,101]))",
    "t_s065 c[116,95,115,48,54,53]/1(c[116,121,112,101]/1(a[116,101,120,116]))",
    "t_s066 c[116,95,115,48,54,54]/1(c[98,117,102,102,101,114]/1(a[102,117,108,108]))",
    "t_s067 c[116,95,115,48,54,55]/1(c[110,101,119,108,105,110,101]/1(a[112,111,115,105,120]))",
    "t_s068 c[116,95,115,48,54,56]/1(a[115,97,109,101])",
    "t_s069 c[116,95,115,48,54,57]/1(c[97,108,105,97,115]/1(a[122,122,51]))",
    "t_s070 c[116,95,115,48,55,48]/1(c[99,108,111,115,101,95,111,110,95,97,98,111,114,116]/1(a[116,114,117,101]))",
    "t_s071 c[116,95,115,48,55,49]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114,115]/1(a[101,114,114,111,114]))",
    "t_s072 c[116,95,115,48,55,50]/1(c[119,114,105,116,101,95,101,114,114,111,114,115]/1(a[101,114,114,111,114]))",
    "t_s073 c[116,95,115,48,55,51]/1(c[117,110,105,99,111,100,101,95,97,116,111,109,115]/1(a[97,99,99,101,112,116]))",
    "t_s074 c[116,95,115,48,55,52]/1(c[101,114,114,111,114]/1(a[102,97,108,115,101]))",
    "t_s075 c[116,95,115,48,55,53]/1(c[112,111,115,105,116,105,111,110]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0)))",
    "t_s076 c[116,95,115,48,55,54]/1(c[101,110,99,111,100,105,110,103]/1(a[117,116,102,56]))",
    "t_s077 c[116,95,115,48,55,55]/1(c[98,117,102,102,101,114,95,115,105,122,101]/1(i4096))",
    "t_s078 c[116,95,115,48,55,56]/1(c[114,101,112,111,115,105,116,105,111,110]/1(a[116,114,117,101]))",
    "t_s079 c[116,95,115,48,55,57]/1(c[116,105,109,101,111,117,116]/1(a[105,110,102,105,110,105,116,101]))",
    "t_s080 c[116,95,115,48,56,48]/1(c[91,124,93]/2(c[109,111,100,101]/1(a[114,101,97,100]),c[91,124,93]/2(a[105,110,112,117,116],c[91,124,93]/2(c[101,110,100,95,111,102,95,115,116,114,101,97,109]/1(a[110,111,116]),c[91,124,93]/2(c[101,114,114,111,114]/1(a[102,97,108,115,101]),c[91,124,93]/2(c[101,111,102,95,97,99,116,105,111,110]/1(a[101,111,102,95,99,111,100,101]),c[91,124,93]/2(c[116,121,112,101]/1(a[116,101,120,116]),c[91,124,93]/2(c[98,117,102,102,101,114]/1(a[102,117,108,108]),c[91,124,93]/2(c[99,108,111,115,101,95,111,110,95,97,98,111,114,116]/1(a[116,114,117,101]),c[91,124,93]/2(c[117,110,105,99,111,100,101,95,97,116,111,109,115]/1(a[97,99,99,101,112,116]),c[91,124,93]/2(c[110,101,119,108,105,110,101]/1(a[112,111,115,105,120]),c[91,124,93]/2(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114,115]/1(a[101,114,114,111,114]),c[91,124,93]/2(c[119,114,105,116,101,95,101,114,114,111,114,115]/1(a[101,114,114,111,114]),nil)))))))))))))",
    "t_s081 c[116,95,115,48,56,49]/1(c[45]/2(c[45]/2(i1,a[115,97,109,101]),c[97,108,105,97,115]/1(a[122,122,52])))",
    "t_s082 c[116,95,115,48,56,50]/1(nil)",
    "t_s083 c[116,95,115,48,56,51]/1(c[45]/2(a[121,101,115],a[110,111]))",
    "t_s084 c[116,95,115,48,56,52]/1(a[102,97,105,108,101,100])",
    "t_s085 c[116,95,115,48,56,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_s086 c[116,95,115,48,56,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_s087 c[116,95,115,48,56,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_s088 c[116,95,115,48,56,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_s089 c[116,95,115,48,56,57]/1(a[121,101,115])",
    "t_s090 c[116,95,115,48,57,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_s091 c[116,95,115,48,57,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_s092 c[116,95,115,48,57,50]/1(c[98,117,102,102,101,114]/1(a[108,105,110,101]))",
    "t_s093 c[116,95,115,48,57,51]/1(c[98,117,102,102,101,114]/1(a[102,97,108,115,101]))",
    "t_s094 c[116,95,115,48,57,52]/1(c[98,117,102,102,101,114]/1(a[102,117,108,108]))",
    "t_s095 c[116,95,115,48,57,53]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[98,117,102,102,101,114],a[98,97,100])))",
    "t_s096 c[116,95,115,48,57,54]/1(c[98,117,102,102,101,114,95,115,105,122,101]/1(i100))",
    "t_s097 c[116,95,115,48,57,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,111,110,101],i0)))",
    "t_s098 c[116,95,115,48,57,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_s099 c[116,95,115,48,57,57]/1(c[101,111,102,95,97,99,116,105,111,110]/1(a[114,101,115,101,116]))",
    "t_s100 c[116,95,115,49,48,48]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,111,102,95,97,99,116,105,111,110],a[98,97,100])))",
    "t_s101 c[116,95,115,49,48,49]/1(a[111,107])",
    "t_s102 c[116,95,115,49,48,50]/1(c[116,121,112,101]/1(a[98,105,110,97,114,121]))",
    "t_s103 c[116,95,115,49,48,51]/1(c[116,121,112,101]/1(a[116,101,120,116]))",
    "t_s104 c[116,95,115,49,48,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[116,121,112,101],a[102,111,111])))",
    "t_s105 c[116,95,115,49,48,53]/1(c[99,108,111,115,101,95,111,110,95,97,98,111,114,116]/1(a[102,97,108,115,101]))",
    "t_s106 c[116,95,115,49,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[102,111,111])))",
    "t_s107 c[116,95,115,49,48,55]/1(a[110,111,110,101])",
    "t_s108 c[116,95,115,49,48,56]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[108,105,110,101,95,112,111,115,105,116,105,111,110],a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_s109 c[116,95,115,49,48,57]/1(c[112,111,115,105,116,105,111,110]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i3,i0)))",
    "t_s110 c[116,95,115,49,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_s111 c[116,95,115,49,49,49]/1(c[112,111,115,105,116,105,111,110]/1(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0)))",
    "t_s112 c[116,95,115,49,49,50]/1(c[102,105,108,101,95,110,97,109,101]/1(a[97,98,99]))",
    "t_s113 c[116,95,115,49,49,51]/1(c[102,105,108,101,95,110,97,109,101]/1(a[115,116,114]))",
    "t_s114 c[116,95,115,49,49,52]/1(a[111,107])",
    "t_s115 c[116,95,115,49,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[102,111,111])))",
    "t_s116 c[116,95,115,49,49,54]/1(c[45]/2(c[101,110,99,111,100,105,110,103]/1(a[111,99,116,101,116]),c[116,121,112,101]/1(a[98,105,110,97,114,121])))",
    "t_s117 c[116,95,115,49,49,55]/1(c[45]/2(c[101,110,99,111,100,105,110,103]/1(a[117,116,102,56]),c[116,121,112,101]/1(a[116,101,120,116])))",
    "t_s118 c[116,95,115,49,49,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[101,110,99,111,100,105,110,103],a[98,111,103,117,115])))",
    "t_s119 c[116,95,115,49,49,57]/1(a[102,97,105,108,101,100])",
    "t_s120 c[116,95,115,49,50,48]/1(c[117,110,105,99,111,100,101,95,97,116,111,109,115]/1(a[101,114,114,111,114]))",
    "t_s121 c[116,95,115,49,50,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[117,110,105,99,111,100,101,95,97,116,111,109,115],a[98,111,103,117,115])))",
    "t_s122 c[116,95,115,49,50,50]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114,115]/1(a[120,109,108]))",
    "t_s123 c[116,95,115,49,50,51]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114,115]/1(a[112,114,111,108,111,103]))",
    "t_s124 c[116,95,115,49,50,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114,115],a[98,111,103,117,115])))",
    "t_s125 c[116,95,115,49,50,53]/1(c[119,114,105,116,101,95,101,114,114,111,114,115]/1(a[105,103,110,111,114,101]))",
    "t_s126 c[116,95,115,49,50,54]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[119,114,105,116,101,95,101,114,114,111,114,115],a[98,111,103,117,115])))",
    "t_s127 c[116,95,115,49,50,55]/1(c[110,101,119,108,105,110,101]/1(a[100,111,115]))",
    "t_s128 c[116,95,115,49,50,56]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,101,119,108,105,110,101],a[98,97,100])))",
    "t_s129 c[116,95,115,49,50,57]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,97,116,116,114,105,98,117,116,101],c[102,111,111]/1(a[120]))))",
    "t_s130 c[116,95,115,49,51,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,97,116,116,114,105,98,117,116,101],a[102,111,111])))",
    "t_s131 c[116,95,115,49,51,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109,95,97,116,116,114,105,98,117,116,101],i1)))",
    "t_s132 c[116,95,115,49,51,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_s133 c[116,95,115,49,51,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_s134 c[116,95,115,49,51,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[110,111,115,117,99,104])))",
    "t_s135 c[116,95,115,49,51,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_s136 c[116,95,115,49,51,54]/1(c[116,105,109,101,111,117,116]/1(a[105,110,102,105,110,105,116,101]))",
    "t_s137 c[116,95,115,49,51,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,111,97,116],a[102,111,111])))"
]

const _S2_DATA = "abc\nxyz\nlast line\n"

"The data file's text, and the program and cases as one file in `dir` (the data and output paths substituted); the case predicates' names."
function _s2_file(dir::String)::Tuple{String, Vector{String}}
    data = joinpath(dir, "data.txt")
    write(data, _S2_DATA)
    prog = replace(
        replace(_S2_PROGRAM, "@DATA@" => data), "@OUT@" => joinpath(dir, "out.txt")
    )
    names = ["t_$(id)" for (id, _) in _S2_CASES]
    text =
        prog * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).\n"
            for
            (id, g) in _S2_CASES
        ])
    f = joinpath(dir, "s2a.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _s2_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_S2}()
    ld = LK.PL_local_data{_S2}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _s2_enc(ball::_S2)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_s2s(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_S2, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _s2_enc(mk_expr(_S2, _S2[_s2s(name), lk_answers(ld, (a:a)...)...]))
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

@testset "prompt, input context, flush_output, is_stream, get_char/peek_char/skip, stream properties and set_stream as swipl's (s001-s137)" begin
    f, names = _s2_file(mktempdir())
    kl = _s2_kernel(f, names)
    @test length(kl) == length(_S2_PINNED)
    for (k, p) in zip(kl, _S2_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the pins hold raised errors (50), `yes` answers, mode(…) properties and two failing rows (s005, s033 have no answer line),
    # so the comparison can pass and can fail
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _S2_PINNED) == 50      # raised(…)
    @test count(l -> endswith(l, "/1(a[121,101,115])"), _S2_PINNED) >= 4              # yes
    @test count(l -> occursin("c[109,111,100,101]/1", l), _S2_PINNED) == 3             # mode(…)
    @test count(l -> occursin(r"^t_s\d+ *$", l), _S2_PINNED) == 2                      # failed rows
    @test count(l -> occursin("c[116,121,112,101]/1", l), _S2_PINNED) >= 5            # type(…)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_S2_PINNED) == length(_S2_CASES) + 1
    if swipl === nothing
        @info "S2a LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _s2_file(mktempdir())
        @test _s2_swipl_lines(f, names) == _S2_PINNED
    end
end
