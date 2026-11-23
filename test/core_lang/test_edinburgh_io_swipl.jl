# ORIGINAL: Edinburgh I/O (EDIO1): see/1, seen/0, seeing/1, tell/1, append/1, telling/1, told/0 against swipl 10.1.20 (pin 18168e62), pl-file.c:4465-4645; UNTESTED when written (nothing compiled)
# test/core_lang/test_edinburgh_io_swipl.jl — the rows e001-e061 the lane D file (test_lane_d_swipl.jl, d070-d097) does not pin: nested see/tell and the context
#   stack, see/tell on `user`, `user_input` and stream blobs, seen/told with nothing to close, a stream left open by set_input/set_output and found again by
#   findStreamFromFile, the IO_SEE/IO_TELL flags kept apart (tell(F) of a file open for see, open/3 of a file then tell), append/1 on a missing file, tell/1
#   truncating, a closed stream's blob, the argument errors.
#   * e058 reads a see/1 stream kept open by eof_action(reset) (seen does not close it), e059 the same on an OUTPUT stream, where the pin's told closes it
#     all the same (its stream_property still says eof_code); e060 reads 98, not 120: the see stream's first buffer fill precedes tell/1's rewrite.
#   * e061 sets eof_action(reset) on an OUTPUT stream through its ALIAS (not the blob that e059 uses): told does not close it (flush_output on the alias still works), the file holds x.
#   * The harness is test_lane_d_swipl.jl's: a PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run IN ORDER in one database (the cases share
#     state on purpose: e021 leaves the data file's stream open for e054), each wrapped in `catch(Goal, error(F, _), R = raised(F))` (a stream blob in F
#     becomes '<stream>').
#   * Every answer line is swipl's, PINNED (swipl 10.1.20-1-g18168e629, two byte-identical runs on a fresh directory, 2026-11-22, evidence/EDIO1/edio_rows.out);
#     with `swipl` on PATH the live answers are compared with the pins too.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream layer (src/os/pl-file.jl) over the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _ED = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_eds(x) = lk_sym(_ED, Symbol(x))

_ed_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _ed_enc(t::_ED, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ed_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ed_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ed_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ed_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_lane_d_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _ED_DRIVER = raw"""
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
function _ed_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _ED_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: helper clauses over the data files (`@DATA@`: "abc\nxyz\nlast line\n", `@DATA2@`: "ABC\n") and three output files (`@OUT@`, `@OUT2@`, and
# `@OUT3@`, which does not exist until a case creates it), all substituted at run time.
const _ED_PROGRAM = raw"""
datafile('@DATA@').
data2('@DATA2@').
outfile('@OUT@').
out2('@OUT2@').
out3('@OUT3@').
ro(S) :- datafile(F), open(F, read, S).
ra(S, A) :- datafile(F), open(F, read, S, [alias(A)]).
wo(S) :- outfile(F), open(F, write, S).
nb(F, F1) :- F =.. [N|As], nbs(As, Bs), F1 =.. [N|Bs].
nbs([], []).
nbs([A|As], [B|Bs]) :- ( blob(A, stream) -> B = '<stream>' ; B = A ), nbs(As, Bs).
cerr(G, R) :- catch(( G -> R = ok ; R = failed ), error(F, _), ( nb(F, F1), R = raised(F1) )).
rall(S, L) :- get_code(S, C), ( C == -1 -> L = [] ; L = [C|T], rall(S, T) ).
rfile(F, T) :- open(F, read, S), rall(S, Cs), close(S), atom_codes(T, Cs).
outtext(T) :- outfile(F), rfile(F, T).
outtext2(T) :- out2(F), rfile(F, T).
out3text(T) :- out3(F), rfile(F, T).
"""

# (id, goal), run IN ORDER
const _ED_CASES = [
    (
        "e001",
        raw"datafile(F), see(F), get_code(A), seen, see(F), get_code(B), seen, R = A-B"
    ),
    ("e002", raw"datafile(F), see(F), seen, seeing(X), R = X"),
    (
        "e003",
        raw"datafile(F), data2(G), see(F), get_code(A), see(G), get_code(B), seen, get_code(C), seen, R = A-B-C"
    ),
    (
        "e004",
        raw"datafile(F), data2(G), see(F), see(G), seen, seeing(S), ( blob(S, stream) -> X = stream ; X = S ), seen, seeing(U), R = X-U"
    ),
    (
        "e005",
        raw"datafile(F), see(F), see(user), seeing(X), see(F), seeing(S), ( blob(S, stream) -> Y = stream ; Y = S ), seen, seeing(Z), R = X-Y-Z"
    ),
    ("e006", raw"datafile(F), see(F), seeing(S), seen, cerr(see(S), R0), R = R0"),
    ("e007", raw"ro(S), see(S), get_code(C), seen, cerr(get_code(S, _), R0), R = C-R0"),
    ("e008", raw"see(user), seen, seeing(X), R = X"),
    ("e009", raw"datafile(F), see(F), seen, seen, seeing(X), R = X"),
    (
        "e010",
        raw"ra(_, edio_al), see(edio_al), get_code(C), seeing(S), ( blob(S, stream) -> X = stream ; X = S ), seen, R = C-X"
    ),
    ("e011", raw"see(user_input), seeing(X), R = X"),
    ("e012", raw"cerr(see(\"abc\"), R)"),
    ("e013", raw"cerr(see([]), R)"),
    ("e014", raw"datafile(F), see(F), see(F), seen, seeing(X), R = X"),
    (
        "e015",
        raw"datafile(F), see(F), get_code(_), set_input(user_input), seen, see(F), get_code(C), seen, R = C"
    ),
    (
        "e016",
        raw"datafile(F), see(F), seeing(S), current_input(I), ( S == I -> R = same ; R = diff ), seen"
    ),
    (
        "e017",
        raw"datafile(F), see(F), seeing(S), see(F), seeing(S2), seen, ( S == S2 -> R = same ; R = diff )"
    ),
    ("e018", raw"cerr(see('/edio_no_dir/x'), R)"),
    (
        "e019",
        raw"datafile(F), see(F), get_code(_), seeing(S), seen, cerr(get_code(S, _), R0), R = R0"
    ),
    (
        "e020",
        raw"datafile(F), see(F), seeing(S), close(S), seeing(X), ( blob(X, stream) -> Y = stream ; Y = X ), seen, seeing(Z), R = Y-Z"
    ),
    ("e021", raw"datafile(F), see(F), ro(P), see(P), seen, seeing(X), R = X"),
    (
        "e030",
        raw"outfile(F), out2(G), tell(F), write(a), tell(G), write(b), told, write(c), told, outtext(T), outtext2(U), R = T-U"
    ),
    (
        "e031",
        raw"outfile(F), tell(F), telling(S), told, telling(U), ( blob(S, stream) -> X = stream ; X = S ), R = X-U"
    ),
    ("e032", raw"told, telling(X), R = X"),
    ("e033", raw"outfile(F), tell(F), told, told, telling(X), R = X"),
    (
        "e034",
        raw"out3(F), append(F), write(ab), told, append(F), write(cd), told, out3text(T), R = T"
    ),
    ("e035", raw"outfile(F), tell(F), write(xyz), told, tell(F), told, outtext(T), R = T"),
    (
        "e036",
        raw"outfile(F), tell(F), append(F), write(q), told, outtext(T), telling(X), R = T-X"
    ),
    (
        "e037",
        raw"outfile(F), tell(F), write(ab), flush_output, see(F), get_code(C), seen, told, R = C"
    ),
    ("e038", raw"tell(user), told, telling(X), R = X"),
    (
        "e039",
        raw"wo(S), tell(S), write(z), told, ( is_stream(S) -> R = open ; R = closed )"
    ),
    ("e040", raw"cerr(tell(1), R)"),
    ("e041", raw"cerr(append(\"abc\"), R)"),
    ("e042", raw"cerr(append(f(x)), R)"),
    ("e043", raw"cerr(tell('/edio_no_dir/x'), R)"),
    ("e044", raw"cerr(append('/edio_no_dir/x'), R)"),
    (
        "e045",
        raw"outfile(F), tell(F), telling(S), current_output(O), ( S == O -> R = same ; R = diff ), told"
    ),
    (
        "e046",
        raw"outfile(F), out2(G), tell(F), telling(A), tell(G), told, telling(B), told, ( A == B -> R = same ; R = diff )"
    ),
    (
        "e047",
        raw"outfile(F), tell(F), telling(S), close(S), telling(X), ( blob(X, stream) -> Y = stream ; Y = X ), told, telling(Z), R = Y-Z"
    ),
    (
        "e048",
        raw"outfile(F), tell(F), write(a), set_output(user_output), told, tell(F), write(b), told, outtext(T), R = T"
    ),
    (
        "e049",
        raw"wo(S), write(S, x), outfile(F), tell(F), write(y), told, close(S), outtext(T), R = T"
    ),
    ("e050", raw"outfile(F), tell(F), telling(S), told, cerr(tell(S), R0), R = R0"),
    (
        "e051",
        raw"outfile(F), tell(F), write(a), tell(F), told, telling(X), outtext(T), R = X-T"
    ),
    ("e052", raw"cerr(tell(_), R)"),
    (
        "e053",
        raw"outfile(F), tell(F), write(h), told, append(F), write(i), told, tell(F), told, append(F), write(j), told, outtext(T), R = T"
    ),
    (
        "e054",
        raw"datafile(F), outfile(G), see(F), tell(G), get_code(C), put_char(x), seen, told, outtext(T), R = C-T"
    ),
    (
        "e055",
        raw"datafile(F), outfile(G), see(F), tell(G), seeing(A0), telling(B0), ( blob(A0, stream) -> A = stream ; A = A0 ), ( blob(B0, stream) -> B = stream ; B = B0 ), seen, told, seeing(C), telling(D), R = C-D-A-B"
    ),
    (
        "e056",
        raw"current_output(O), outfile(F), tell(F), told, ( current_output(O2), O == O2 -> R = same ; R = diff )"
    ),
    (
        "e057",
        raw"current_input(O), datafile(F), see(F), seen, ( current_input(O2), O == O2 -> R = same ; R = diff )"
    ),
    (
        "e058",
        raw"datafile(F), see(F), get_code(A), seeing(S), set_stream(S, eof_action(reset)), seen, see(F), get_code(B), seeing(S2), set_stream(S2, eof_action(eof_code)), seen, R = A-B"
    ),
    (
        "e059",
        raw"outfile(F), tell(F), write(a), telling(S), set_stream(S, eof_action(reset)), told, tell(F), write(b), told, outtext(T), R = T"
    ),
    ("e060", raw"outfile(F), see(F), tell(F), write(x), told, get_code(C), seen, R = C"),
    (
        "e061",
        raw"outfile(F), open(F, write, _, [alias(edio_wal)]), set_stream(edio_wal, eof_action(reset)), tell(edio_wal), write(x), told, flush_output(edio_wal), outtext(T), set_stream(edio_wal, eof_action(eof_code)), close(edio_wal), R = T"
    )
]

# swipl 10.1.20-1-g18168e629's answers to the program and cases above (the driver's lines; evidence/EDIO1/edio_rows.out)
const _ED_PINNED = [
    "ok",
    "t_e001 c[116,95,101,48,48,49]/1(c[45]/2(i97,i97))",
    "t_e002 c[116,95,101,48,48,50]/1(a[117,115,101,114])",
    "t_e003 c[116,95,101,48,48,51]/1(c[45]/2(c[45]/2(i97,i65),i98))",
    "t_e004 c[116,95,101,48,48,52]/1(c[45]/2(a[115,116,114,101,97,109],a[117,115,101,114]))",
    "t_e005 c[116,95,101,48,48,53]/1(c[45]/2(c[45]/2(a[117,115,101,114],a[115,116,114,101,97,109]),a[117,115,101,114]))",
    "t_e006 c[116,95,101,48,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],a[60,115,116,114,101,97,109,62])))",
    "t_e007 c[116,95,101,48,48,55]/1(c[45]/2(i97,c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62]))))",
    "t_e008 c[116,95,101,48,48,56]/1(a[117,115,101,114])",
    "t_e009 c[116,95,101,48,48,57]/1(a[117,115,101,114])",
    "t_e010 c[116,95,101,48,49,48]/1(c[45]/2(i97,a[115,116,114,101,97,109]))",
    "t_e011 c[116,95,101,48,49,49]/1(a[117,115,101,114])",
    "t_e012 c[116,95,101,48,49,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[97,98,99])))",
    "t_e013 c[116,95,101,48,49,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,111,117,114,99,101,95,115,105,110,107],nil)))",
    "t_e014 c[116,95,101,48,49,52]/1(a[117,115,101,114])",
    "t_e015 c[116,95,101,48,49,53]/1(i98)",
    "t_e016 c[116,95,101,48,49,54]/1(a[115,97,109,101])",
    "t_e017 c[116,95,101,48,49,55]/1(a[115,97,109,101])",
    "t_e018 c[116,95,101,48,49,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,111,117,114,99,101,95,115,105,110,107],a[47,101,100,105,111,95,110,111,95,100,105,114,47,120])))",
    "t_e019 c[116,95,101,48,49,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,116,114,101,97,109],a[60,115,116,114,101,97,109,62])))",
    "t_e020 c[116,95,101,48,50,48]/1(c[45]/2(a[117,115,101,114],a[117,115,101,114]))",
    "t_e021 c[116,95,101,48,50,49]/1(a[117,115,101,114])",
    "t_e030 c[116,95,101,48,51,48]/1(c[45]/2(a[97,99],a[98]))",
    "t_e031 c[116,95,101,48,51,49]/1(c[45]/2(a[115,116,114,101,97,109],a[117,115,101,114]))",
    "t_e032 c[116,95,101,48,51,50]/1(a[117,115,101,114])",
    "t_e033 c[116,95,101,48,51,51]/1(a[117,115,101,114])",
    "t_e034 c[116,95,101,48,51,52]/1(a[97,98,99,100])",
    "t_e035 c[116,95,101,48,51,53]/1(a[])",
    "t_e036 c[116,95,101,48,51,54]/1(c[45]/2(a[113],a[117,115,101,114]))",
    "t_e037 c[116,95,101,48,51,55]/1(i97)",
    "t_e038 c[116,95,101,48,51,56]/1(a[117,115,101,114])",
    "t_e039 c[116,95,101,48,51,57]/1(a[99,108,111,115,101,100])",
    "t_e040 c[116,95,101,48,52,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_e041 c[116,95,101,48,52,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[97,98,99])))",
    "t_e042 c[116,95,101,48,52,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_e043 c[116,95,101,48,52,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,111,117,114,99,101,95,115,105,110,107],a[47,101,100,105,111,95,110,111,95,100,105,114,47,120])))",
    "t_e044 c[116,95,101,48,52,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[115,111,117,114,99,101,95,115,105,110,107],a[47,101,100,105,111,95,110,111,95,100,105,114,47,120])))",
    "t_e045 c[116,95,101,48,52,53]/1(a[115,97,109,101])",
    "t_e046 c[116,95,101,48,52,54]/1(a[115,97,109,101])",
    "t_e047 c[116,95,101,48,52,55]/1(c[45]/2(a[117,115,101,114],a[117,115,101,114]))",
    "t_e048 c[116,95,101,48,52,56]/1(a[97,98])",
    "t_e049 c[116,95,101,48,52,57]/1(a[120])",
    "t_e050 c[116,95,101,48,53,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],a[60,115,116,114,101,97,109,62])))",
    "t_e051 c[116,95,101,48,53,49]/1(c[45]/2(a[117,115,101,114],a[97]))",
    "t_e052 c[116,95,101,48,53,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_e053 c[116,95,101,48,53,51]/1(a[106])",
    "t_e054 c[116,95,101,48,53,52]/1(c[45]/2(i97,a[120]))",
    "t_e055 c[116,95,101,48,53,53]/1(c[45]/2(c[45]/2(c[45]/2(a[117,115,101,114],a[117,115,101,114]),a[115,116,114,101,97,109]),a[115,116,114,101,97,109]))",
    "t_e056 c[116,95,101,48,53,54]/1(a[115,97,109,101])",
    "t_e057 c[116,95,101,48,53,55]/1(a[115,97,109,101])",
    "t_e058 c[116,95,101,48,53,56]/1(c[45]/2(i97,i98))",
    "t_e059 c[116,95,101,48,53,57]/1(a[98])",
    "t_e060 c[116,95,101,48,54,48]/1(i98)",
    "t_e061 c[116,95,101,48,54,49]/1(a[120])"
]

const _ED_DATA = "abc\nxyz\nlast line\n"
const _ED_DATA2 = "ABC\n"

"The data files, and the program and cases as one file in `dir` (the paths substituted); the case predicates' names."
function _ed_file(dir::String)::Tuple{String, Vector{String}}
    write(joinpath(dir, "data.txt"), _ED_DATA)
    write(joinpath(dir, "data2.txt"), _ED_DATA2)
    prog = _ED_PROGRAM
    for (k, v) in (
        "@DATA@" => "data.txt", "@DATA2@" => "data2.txt", "@OUT@" => "out.txt",
        "@OUT2@" => "out2.txt", "@OUT3@" => "out3.txt"
    )
        prog = replace(prog, k => joinpath(dir, v))
    end
    names = ["t_$(id)" for (id, _) in _ED_CASES]
    text =
        prog * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), ( nb(SsuE, SsuF), R = raised(SsuF) )).\n"
            for
            (id, g) in _ED_CASES
        ])
    f = joinpath(dir, "edio.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _ed_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_ED}()
    ld = LK.PL_local_data{_ED}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _ed_enc(ball::_ED)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_eds(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_ED, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _ed_enc(mk_expr(_ED, _ED[_eds(name), lk_answers(ld, (a:a)...)...]))
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

@testset "Edinburgh I/O as swipl's (e001-e061)" begin
    f, names = _ed_file(mktempdir())
    kl = _ed_kernel(f, names)
    @test length(kl) == length(_ED_PINNED)
    for (k, p) in zip(kl, _ED_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the pins hold raised errors, `same` and `user` answers and file texts, so the comparison can pass and can fail
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _ED_PINNED) == 13     # raised(…)
    @test count(l -> endswith(l, "(a[115,97,109,101])"), _ED_PINNED) == 6          # same
    @test count(l -> endswith(l, "(a[117,115,101,114])"), _ED_PINNED) == 9         # user
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_ED_PINNED) == length(_ED_CASES) + 1
    if swipl === nothing
        @info "EDIO LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _ed_file(mktempdir())
        @test _ed_swipl_lines(f, names) == _ED_PINNED
    end
end
