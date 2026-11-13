# ORIGINAL: lane D / ENC1: the stream encoding `text` (ENC_ANSI) against swipl 10.1.20 (pin 18168e62) under the C library's locale — pl-stream.c put_code,
# Scanrepresent, Sgetcode (the ENC_ANSI arms), pl-file.c read_pending_input and open/4 `encoding(text)`; the text conversions of pl-text.c / pl-string.c
# (`string_bytes/3` with `text`, PL_text_recode, PL_mb_text, PL_canonicalise_text) are rows of the same file. UNTESTED when written (nothing compiled)
# test/core_lang/test_enc_ansi_swipl.jl — the harness is test_lane_d_swipl.jl's: a PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run IN ORDER in
# one database, each wrapped in `catch(Goal, error(F, _), R = raised(F))`; swipl runs the same program through the driver and the lines are compared.
#   * The kernel never calls `setlocale` (the embedder does): the TEST sets LC_CTYPE itself (`_ea_with_locale`) and restores it; swipl runs with `LC_ALL` set to
#     the same name, so both sides convert under the same locale. Two locales: `C.UTF-8` and `C` (where every byte >= 0x80 is illegal and every character
#     > 0x7f has no representation). The programs are ASCII (a non-ASCII argument of swipl in the C locale is not a program text).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20-1-g18168e629, two byte-identical runs per locale, 2026-11-13); with `swipl` on PATH the live answers
#     are compared with the pins too. When the test host lacks the locale the kernel rows are skipped with an @info, the pins stay asserted.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream layer (src/os/pl-stream.jl, pl-file.jl) and the text layer (pl-text.jl, pl-string.jl) over the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _EA = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_eas(x) = lk_sym(_EA, Symbol(x))

_ea_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _ea_enc(t::_EA, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ea_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ea_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ea_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ea_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the driver of test_lane_d_swipl.jl (consult, then every answer of each t_<id>/1, `enc`oded)
const _EA_DRIVER = raw"""
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
"swipl's lines for `names` after consulting `path`, run under `LC_ALL=loc` (a file argument: ASCII, so any locale reads it)."
function _ea_swipl_lines(path::String, names::Vector{String}, loc::String)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _EA_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") * "]), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => loc); stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: an output file (`@OUT@`) written and read back in the encoding `text` and as bytes; the helper names say what they do
const _EA_PROGRAM = raw"""
outfile('@OUT@').
nb(F, F1) :- F =.. [N|As], nbs(As, Bs), F1 =.. [N|Bs].
nbs([], []).
nbs([A|As], [B|Bs]) :- ( blob(A, stream) -> B = '<stream>' ; B = A ), nbs(As, Bs).
cerr(G, R) :- catch(( G -> R = ok ; R = failed ), error(F, _), ( nb(F, F1), R = raised(F1) )).
rall(S, L) :- get_code(S, C), ( C == -1 -> L = [] ; L = [C|T], rall(S, T) ).
rbyt(S, L) :- get_byte(S, C), ( C == -1 -> L = [] ; L = [C|T], rbyt(S, T) ).
wbytes(Bs) :- outfile(F), open(F, write, W, [type(binary)]), forall(member(B, Bs), put_byte(W, B)), close(W).
outbytes(L) :- outfile(F), open(F, read, S, [type(binary)]), rbyt(S, L), close(S).
wtext(Cs) :- outfile(F), open(F, write, W, [encoding(text)]), forall(member(C, Cs), put_code(W, C)), close(W).
rtext(L) :- outfile(F), open(F, read, S, [encoding(text)]), rall(S, L), close(S).
rpend(Bs, R) :- wbytes(Bs), outfile(F), open(F, read, S, [encoding(text)]), call_cleanup(rpend1(S, R), close(S)).
rpend1(S, r(L1, L2, CC, BC)) :- read_pending_codes(S, L1, []), read_pending_codes(S, L2, []), character_count(S, CC), byte_count(S, BC).
wq(T) :- outfile(F), open(F, write, W, [encoding(text)]), call_cleanup(writeq(W, T), close(W)).
wqs(Cs) :- atom_codes(A, Cs), wq(A).
wqt(Cs) :- string_codes(S, Cs), wq(S).
sbd(Bs, Cs) :- string_bytes(S, Bs, text), string_codes(S, Cs).
sbe(Cs, Bs) :- string_codes(S, Cs), string_bytes(S, Bs, text).
"""

"The program and cases as one file in `dir` (the output path substituted); the case predicates' names."
function _ea_file(dir::String, cases::Vector{Tuple{String, String}})::Tuple{String, Vector{String}}
    prog = replace(_EA_PROGRAM, "@OUT@" => joinpath(dir, "out.txt"))
    names = ["t_$(id)" for (id, _) in cases]
    text =
        prog * join([
            "t_$(id)(R) :- catch(($g), error(EaE, _), ( nb(EaE, EaF), R = raised(EaF) )).\n" for
            (id, g) in cases
        ])
    f = joinpath(dir, "enc_ansi.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's."
function _ea_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_EA}()
    ld = LK.PL_local_data{_EA}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _ea_enc(ball::_EA)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_eas(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_EA, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _ea_enc(mk_expr(_EA, _EA[_eas(name), lk_answers(ld, (a:a)...)...]))
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

"Run `f()` with the process's LC_CTYPE set to `loc` and restore the old one; `false` (f not run) when the host has no such locale."
function _ea_with_locale(f::Function, loc::String)::Bool
    old = ccall(:setlocale, Cstring, (Cint, Ptr{Cvoid}), 0, C_NULL)    # LC_CTYPE = 0 (glibc)
    oldname = old == C_NULL ? "C" : unsafe_string(old)
    got = ccall(:setlocale, Cstring, (Cint, Cstring), 0, loc)
    got == C_NULL && return false
    try
        f()
    finally
        ccall(:setlocale, Cstring, (Cint, Cstring), 0, oldname)
    end
    return true
end

# (id, goal), run IN ORDER, under C.UTF-8
const _EA_U_CASES = Tuple{String, String}[
    ("u01", raw"wtext([0'a, 0xe9, 0x20ac, 0x1F600]), outbytes(L), R = L"),
    ("u02", raw"wtext([0'a, 0xe9, 0x20ac, 0x1F600]), rtext(L), R = L"),
    ("u03", raw"wtext([0'a]), outfile(F), open(F, read, S, [encoding(text)]), '$stream_property'(S, encoding(E)), close(S), R = E"),
    ("u04", raw"wbytes([97, 0xc3]), rtext(L), R = L"),
    ("u05", raw"wbytes([97, 0, 98]), rtext(L), R = L"),
    ("u06", raw"wbytes([0xc3, 0x28, 98]), rtext(L), R = L"),
    ("u07", raw"wbytes([0xe2, 0x82, 0xac, 13, 10, 0xf0, 0x9f, 0x98, 0x80]), rtext(L), R = L"),
    ("u08", raw"wbytes([97, 0xff, 98]), rtext(L), R = L"),
    ("u09", raw"wbytes([]), rtext(L), R = L"),
    ("u10", raw"rpend([97, 0xc3, 0xa9, 98], R)"),
    ("u11", raw"rpend([97, 0xe2, 0x82], R)"),
    ("u12", raw"rpend([97, 0, 98, 0xc3, 0xa9], R)"),
    ("u13", raw"cerr(rpend([0xc3, 0x28], _), R)"),
    ("u14", raw"rpend([0xe2, 0x82, 0xac, 13, 10, 98], R)"),
    ("u15", raw"rpend([0xf0, 0x9f, 0x98, 0x80, 0x61], R)"),
    ("u16", raw"rpend([97, 98, 99], R)"),
    ("u17", raw"wqs([0'c, 0'a, 0'f, 0xe9]), outbytes(L), R = L"),
    ("u18", raw"wqs([0x20ac]), outbytes(L), R = L"),
    ("u19", raw"wqs([0'a, 0x20, 0xe9]), outbytes(L), R = L"),
    ("u20", raw"wqt([0'a, 0xe9, 0x20ac, 0x1F600]), outbytes(L), R = L"),
    ("u21", raw"wqt([0'a, 0xe9, 0x20ac, 0x1F600]), rtext(L), R = L"),
    ("u22", raw"wtext([]), outbytes(L), R = L"),
    ("u23", raw"outfile(F), open(F, write, W, [encoding(text)]), put_code(W, 0), close(W), outbytes(L), R = L")
]
# swipl's answers (the first line is the consult's), under LC_ALL=C.UTF-8
const _EA_U_PINNED = [
    "ok",
    "t_u01 c[116,95,117,48,49]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i195,c[91,124,93]/2(i169,c[91,124,93]/2(i226,c[91,124,93]/2(i130,c[91,124,93]/2(i172,c[91,124,93]/2(i240,c[91,124,93]/2(i159,c[91,124,93]/2(i152,c[91,124,93]/2(i128,nil)))))))))))",
    "t_u02 c[116,95,117,48,50]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i233,c[91,124,93]/2(i8364,c[91,124,93]/2(i128512,nil)))))",
    "t_u03 c[116,95,117,48,51]/1(a[116,101,120,116])",
    "t_u04 c[116,95,117,48,52]/1(c[91,124,93]/2(i97,nil))",
    "t_u05 c[116,95,117,48,53]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i0,c[91,124,93]/2(i98,nil))))",
    "t_u06 c[116,95,117,48,54]/1(c[91,124,93]/2(i65533,c[91,124,93]/2(i65533,nil)))",
    "t_u07 c[116,95,117,48,55]/1(c[91,124,93]/2(i8364,c[91,124,93]/2(i13,c[91,124,93]/2(i10,c[91,124,93]/2(i128512,nil)))))",
    "t_u08 c[116,95,117,48,56]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i65533,c[91,124,93]/2(i98,nil))))",
    "t_u09 c[116,95,117,48,57]/1(nil)",
    "t_u10 c[116,95,117,49,48]/1(c[114]/4(c[91,124,93]/2(i97,c[91,124,93]/2(i233,c[91,124,93]/2(i98,nil))),nil,i3,i4))",
    "t_u11 c[116,95,117,49,49]/1(c[114]/4(c[91,124,93]/2(i97,nil),nil,i1,i1))",
    "t_u12 c[116,95,117,49,50]/1(c[114]/4(c[91,124,93]/2(i97,nil),nil,i1,i1))",
    "t_u13 c[116,95,117,49,51]/1(a[102,97,105,108,101,100])",
    "t_u14 c[116,95,117,49,52]/1(c[114]/4(c[91,124,93]/2(i8364,c[91,124,93]/2(i13,c[91,124,93]/2(i10,c[91,124,93]/2(i98,nil)))),nil,i4,i6))",
    "t_u15 c[116,95,117,49,53]/1(c[114]/4(c[91,124,93]/2(i128512,c[91,124,93]/2(i97,nil)),nil,i2,i5))",
    "t_u16 c[116,95,117,49,54]/1(c[114]/4(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil))),nil,i3,i3))",
    "t_u17 c[116,95,117,49,55]/1(c[91,124,93]/2(i99,c[91,124,93]/2(i97,c[91,124,93]/2(i102,c[91,124,93]/2(i195,c[91,124,93]/2(i169,nil))))))",
    "t_u18 c[116,95,117,49,56]/1(c[91,124,93]/2(i226,c[91,124,93]/2(i130,c[91,124,93]/2(i172,nil))))",
    "t_u19 c[116,95,117,49,57]/1(c[91,124,93]/2(i39,c[91,124,93]/2(i97,c[91,124,93]/2(i32,c[91,124,93]/2(i195,c[91,124,93]/2(i169,c[91,124,93]/2(i39,nil)))))))",
    "t_u20 c[116,95,117,50,48]/1(c[91,124,93]/2(i34,c[91,124,93]/2(i97,c[91,124,93]/2(i195,c[91,124,93]/2(i169,c[91,124,93]/2(i226,c[91,124,93]/2(i130,c[91,124,93]/2(i172,c[91,124,93]/2(i240,c[91,124,93]/2(i159,c[91,124,93]/2(i152,c[91,124,93]/2(i128,c[91,124,93]/2(i34,nil)))))))))))))",
    "t_u21 c[116,95,117,50,49]/1(c[91,124,93]/2(i34,c[91,124,93]/2(i97,c[91,124,93]/2(i233,c[91,124,93]/2(i8364,c[91,124,93]/2(i128512,c[91,124,93]/2(i34,nil)))))))",
    "t_u22 c[116,95,117,50,50]/1(nil)",
    "t_u23 c[116,95,117,50,51]/1(c[91,124,93]/2(i0,nil))"
]

# (id, goal), run IN ORDER, under the C locale
const _EA_C_CASES = Tuple{String, String}[
    ("c01", raw"outfile(F), open(F, write, W, [encoding(text)]), cerr(put_code(W, 0xe9), R0), cerr(close(W), R1), R = R0-R1"),
    ("c02", raw"wtext([0'a, 0'b]), outbytes(L), R = L"),
    ("c03", raw"wbytes([97, 233, 98, 0xc3, 0xa9]), rtext(L), R = L"),
    ("c04", raw"rpend([97, 98, 99], R)"),
    ("c05", raw"cerr(rpend([0xc3, 0x28], _), R)"),
    ("c06", raw"cerr(wqs([0'c, 0'a, 0'f, 0xe9]), R0), outbytes(L), R = R0-L"),
    ("c07", raw"cerr(wqs([0x20ac]), R0), outbytes(L), R = R0-L"),
    ("c08", raw"cerr(wqs([0'a, 0x20, 0xe9]), R0), outbytes(L), R = R0-L"),
    ("c09", raw"cerr(wqt([0'a, 0xe9]), R0), outbytes(L), R = R0-L"),
    ("c10", raw"outfile(F), open(F, write, W, [encoding(text)]), cerr(put_code(W, 0x20ac), R0), cerr(put_code(W, 0'a), R1), cerr(close(W), R2), outbytes(L), R = r(R0, R1, R2, L)"),
    ("c11", raw"cerr(rpend([97, 0xe9], _), R)"),
    ("c12", raw"wbytes([97, 0, 98]), rtext(L), R = L")
]
# swipl's answers, under LC_ALL=C
const _EA_C_PINNED = [
    "ok",
    "t_c01 c[116,95,99,48,49]/1(c[45]/2(c[114,97,105,115,101,100]/1(c[105,111,95,101,114,114,111,114]/2(a[119,114,105,116,101],a[60,115,116,114,101,97,109,62])),a[111,107]))",
    "t_c02 c[116,95,99,48,50]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i98,nil)))",
    "t_c03 c[116,95,99,48,51]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i65533,c[91,124,93]/2(i98,c[91,124,93]/2(i65533,c[91,124,93]/2(i65533,nil))))))",
    "t_c04 c[116,95,99,48,52]/1(c[114]/4(c[91,124,93]/2(i97,c[91,124,93]/2(i98,c[91,124,93]/2(i99,nil))),nil,i3,i3))",
    "t_c05 c[116,95,99,48,53]/1(a[102,97,105,108,101,100])",
    "t_c06 c[116,95,99,48,54]/1(c[45]/2(a[111,107],c[91,124,93]/2(i39,c[91,124,93]/2(i99,c[91,124,93]/2(i97,c[91,124,93]/2(i102,c[91,124,93]/2(i92,c[91,124,93]/2(i120,c[91,124,93]/2(i69,c[91,124,93]/2(i57,c[91,124,93]/2(i92,c[91,124,93]/2(i39,nil))))))))))))",
    "t_c07 c[116,95,99,48,55]/1(c[45]/2(c[114,97,105,115,101,100]/1(c[105,111,95,101,114,114,111,114]/2(a[119,114,105,116,101],a[60,115,116,114,101,97,109,62])),nil))",
    "t_c08 c[116,95,99,48,56]/1(c[45]/2(a[111,107],c[91,124,93]/2(i39,c[91,124,93]/2(i97,c[91,124,93]/2(i32,c[91,124,93]/2(i92,c[91,124,93]/2(i120,c[91,124,93]/2(i69,c[91,124,93]/2(i57,c[91,124,93]/2(i92,c[91,124,93]/2(i39,nil)))))))))))",
    "t_c09 c[116,95,99,48,57]/1(c[45]/2(a[111,107],c[91,124,93]/2(i34,c[91,124,93]/2(i97,c[91,124,93]/2(i92,c[91,124,93]/2(i120,c[91,124,93]/2(i69,c[91,124,93]/2(i57,c[91,124,93]/2(i92,c[91,124,93]/2(i34,nil))))))))))",
    "t_c10 c[116,95,99,49,48]/1(c[114]/4(c[114,97,105,115,101,100]/1(c[105,111,95,101,114,114,111,114]/2(a[119,114,105,116,101],a[60,115,116,114,101,97,109,62])),a[111,107],a[111,107],c[91,124,93]/2(i97,nil)))",
    "t_c11 c[116,95,99,49,49]/1(a[102,97,105,108,101,100])",
    "t_c12 c[116,95,99,49,50]/1(c[91,124,93]/2(i97,c[91,124,93]/2(i0,c[91,124,93]/2(i98,nil))))"
]

"Compare the kernel's lines with the pins, row by row, in the locale `loc`; the not-vacuous counts are the caller's."
function _ea_compare(loc::String, cases, pinned)::Bool
    return _ea_with_locale(loc) do
        f, names = _ea_file(mktempdir(), cases)
        kl = _ea_kernel(f, names)
        @test length(kl) == length(pinned)
        for (k, p) in zip(kl, pinned)
            k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
            @test k == p
        end
    end
end

@testset "ENC_ANSI under C.UTF-8: put_code, Sgetcode, read_pending_codes, writeq (pl-stream.c, pl-file.c) as swipl's" begin
    @test length(_EA_U_PINNED) == length(_EA_U_CASES) + 1
    ran = _ea_compare("C.UTF-8", _EA_U_CASES, _EA_U_PINNED)
    ran || @info "ENC_ANSI C.UTF-8 KERNEL ROWS NOT RUN: the host has no C.UTF-8 locale"
    # not vacuous: the pins hold raised errors, failed rows and answers, so the comparison can pass and can fail
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _EA_U_PINNED) == 0     # raised(…)
    @test count(l -> endswith(l, "/1(a[102,97,105,108,101,100])"), _EA_U_PINNED) == 1   # failed
end

@testset "ENC_ANSI under the C locale: a byte >= 0x80 is illegal and a character > 0x7f has no representation (as swipl's)" begin
    @test length(_EA_C_PINNED) == length(_EA_C_CASES) + 1
    ran = _ea_compare("C", _EA_C_CASES, _EA_C_PINNED)
    ran || @info "ENC_ANSI C-locale KERNEL ROWS NOT RUN: setlocale(LC_CTYPE, \"C\") failed"
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _EA_C_PINNED) == 3
    @test count(l -> endswith(l, "/1(a[102,97,105,108,101,100])"), _EA_C_PINNED) == 2
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_EA_U_PINNED) > 1 && length(_EA_C_PINNED) > 1
    if swipl === nothing
        @info "ENC_ANSI LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        for (loc, cases, pinned) in (("C.UTF-8", _EA_U_CASES, _EA_U_PINNED), ("C", _EA_C_CASES, _EA_C_PINNED))
            f, names = _ea_file(mktempdir(), cases)
            @test _ea_swipl_lines(f, names, loc) == pinned
        end
    end
end

# KERNEL-ONLY rows: the libc wrappers of src/os/pl-stream.jl and `Scanrepresent`. The expected values are libc's own, read with Python's ctypes
# (wcrtomb / mbrtowc / mbsnrtowcs under each locale, 2026-11-13: the C library is the oracle, swipl calls the same functions).
@testset "the libc wrappers and Scanrepresent under the process's LC_CTYPE (kernel-only: libc's values)" begin
    @test LK.PL_MB_LEN_MAX == 16 && LK.MBSTATE_WORDS == 2
    s = LK.IOSTREAM()
    st = LK.stream_mbstate!(s)
    @test st == zeros(UInt64, LK.MBSTATE_WORDS)
    @test LK.stream_mbstate!(s) === st                  # made once, kept (upstream's `if ( !s->mbstate )`)
    s.encoding = LK.ENC_ANSI
    z() = zeros(UInt64, LK.MBSTATE_WORDS)
    ranu = _ea_with_locale("C.UTF-8") do
        @test LK._wcrtomb(Int(0x41), z()) == UInt8[0x41]
        @test LK._wcrtomb(Int(0xe9), z()) == UInt8[0xc3, 0xa9]
        @test LK._wcrtomb(Int(0x20ac), z()) == UInt8[0xe2, 0x82, 0xac]
        @test LK._wcrtomb(Int(0x1F600), z()) == UInt8[0xf0, 0x9f, 0x98, 0x80]
        @test LK._wcrtomb(0, z()) == UInt8[0x00]
        @test LK._wcrtomb(Int(0xD800), z()) === nothing      # a surrogate has no UTF-8 form
        @test LK.Scanrepresent(Int(0x20ac), s) == 0 && LK.Scanrepresent(Int(0x1F600), s) == 0
        @test LK.Scanrepresent(Int(0xD800), s) == -1
        stx = z()                                       # one byte at a time, the state carries the partial sequence
        @test LK._mbrtowc(UInt8[0xe2, 0x82, 0xac], 1, 1, stx) == (-2, 0)
        @test LK._mbrtowc(UInt8[0xe2, 0x82, 0xac], 2, 1, stx) == (-2, 0)
        @test LK._mbrtowc(UInt8[0xe2, 0x82, 0xac], 3, 1, stx) == (1, 0x20ac)
        @test LK._mbrtowc(UInt8[0xff], 1, 1, z()) == (-1, 0)
        @test LK._mbrtowc(UInt8[0x00], 1, 1, z()) == (0, 0)
        @test LK._mbrtowc(UInt8[0xc3, 0xa9, 0x62], 1, 3, z()) == (2, 0xe9)
        @test LK._mbsnrtowcs_count(UInt8[97, 0xc3, 0xa9, 98], 4, z()) == 3
        @test LK._mbsnrtowcs_count(UInt8[97, 0xe2, 0x82], 3, z()) == 1      # an incomplete tail is not counted
        @test LK._mbsnrtowcs_count(UInt8[0xc3, 0x28], 2, z()) == -1
        @test LK._mbsnrtowcs_count(UInt8[97, 0, 98], 3, z()) == 1           # libc stops at the NUL
    end
    ran_c = _ea_with_locale("C") do
        @test LK._wcrtomb(Int(0x41), z()) == UInt8[0x41]
        @test LK._wcrtomb(Int(0xe9), z()) === nothing
        @test LK._wcrtomb(Int(0x20ac), z()) === nothing
        @test LK.Scanrepresent(Int(0x41), s) == 0
        @test LK.Scanrepresent(Int(0xe9), s) == -1
        @test LK.Scanrepresent(Int(0x20ac), s) == -1
        @test LK._mbrtowc(UInt8[0xe9], 1, 1, z()) == (-1, 0)
        @test LK._mbrtowc(UInt8[0x41], 1, 1, z()) == (1, 0x41)
        @test LK._mbsnrtowcs_count(UInt8[97, 98], 2, z()) == 2
        @test LK._mbsnrtowcs_count(UInt8[97, 0xe9], 2, z()) == -1
    end
    ranu || @info "libc wrapper rows under C.UTF-8 NOT RUN: no such locale on this host"
    ran_c || @info "libc wrapper rows under C NOT RUN"
    # the stream's encoding decides: a non-ANSI stream ignores the locale
    s2 = LK.IOSTREAM()
    s2.encoding = LK.ENC_ISO_LATIN_1
    @test LK.Scanrepresent(Int(0xe9), s2) == 0 && LK.Scanrepresent(Int(0x20ac), s2) == -1
end


