# ORIGINAL: R2's S1 gate — stream blobs, user aliases, open/3,4 and close/1,2 (pl-file.c) against swipl 10.1.19; upstream tests them through Prolog (tests/files, tests/core_text), which needs the loader and plunit (R2).
# test/files/test_open_close_swipl.jl — S1's gate (D-0149, design evidence/r2/design/flags_rest.md §4 D10):
#   * ROWS, as a program (the pattern of test/db/test_retract_swipl.jl): each case is a predicate `t_<id>(R)`;
#     the kernel consults the program and enumerates the answers of every `t_<id>/1`, swipl does the same
#     through a driver, and the lines are compared. EVERY expected value is swipl's own answer (the driver
#     runs live, with `LC_ALL=C.UTF-8` so its default encoding is the kernel's UTF-8). Besides the answers
#     each row compares THE FILES it left in the test's directory — their bytes and their permission bits —
#     and the number of streams still open on a file of that directory (the stream blob's leak: a closed
#     stream must leave the table, an unclosed one is counted by both). A stream blob is written `stream`
#     in the answer lines, and the atom `term_to_atom/2` makes of one is compared by its SHAPE,
#     `<stream>(0x…)`: the address is no value anyone compares;
#   * READING, which the program cannot do (the kernel has no read/1 or get_code/2 yet): files with and
#     without a byte order mark are opened with the options the rows list and read through the kernel's
#     own `Sgetcode` on the stream the blob names; swipl's driver prints the same codes with get_code/2;
#     the encoding and the BOM flag are compared too;
#   * WHITE-BOX: the refusals by name (pipe, lock, locale, unicode_atoms, an encoding the stream layer
#     lacks, a newline mode swipl answers unstably), the blob form on a term type with a
#     small payload (a blob is an atom: no payload needed), the stream table's accounting, the blob's
#     identity (a unique atom per stream), and `PL_get_file_name`.
using Test, LogicKernel

const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
# (`Bool` is a grounded value of no SWI type: the blob test must tell it from a stream blob)
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}, Bool})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"

# the answer lines' encoding of a term (the driver's `enc/3` prints the same); a stream blob is `stream`
function enc(t::_TL, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        is_blob(t) && return blob_type(t) === :stream ? "stream" : "blob"
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# An atom that is a stream's written form is compared by its shape: swipl's address and the kernel's differ.
function _norm(line::AbstractString)::String
    return replace(
        String(line),
        r"a\[([0-9,]+)\]" => function (m)
            try
                txt = String(Char.(parse.(Int, split(m[3:(end - 1)], ','))))
                return if occursin(r"^<stream>\(0x[0-9a-f]+\)$", txt)
                    "astreamform"
                else
                    String(m)
                end
            catch
                return String(m)
            end
        end
    )
end

# ---- the program: swipl's rows (the shapes are rows.pl-style `t_<id>(R)`), `{D}` the test's directory
const _PROGRAM = """
:- dynamic zz_s/1.
ex(G, R) :- catch(( G, R = true ), error(E, C), R = err(E, C)).
mkf(F) :- open(F, write, S), write(S, abc), close(S).
btype(S, B) :- ( atom(S) -> B = atom ; atomic(S) -> B = atomic ; B = other ).
"""

# (id, goal). `ex/2` returns `true` or `err(Formal, Context)`.
const _CASES = [
    # ---- open/3,4: the errors
    ("e01", "ex(open('{D}/none', read, _), R)"),
    ("e02", "ex(open('{D}/nodir/f', write, _), R)"),
    ("e03", "ex(open(_, read, _), R)"),
    ("e04", "ex(open('{D}/f1', _, _), R)"),
    ("e05", "ex(open('{D}/f1', foo, _), R)"),
    ("e06", "ex(open('{D}/f1', 1, _), R)"),
    ("e07", "ex(open(f(x), read, _), R)"),
    ("e08", "ex(open(1, read, _), R)"),
    ("e10", "ex(open('{D}/f1', write, _, foo), R)"),
    ("e11", "ex(open('{D}/f1', write, _, [type(foo)]), R)"),
    ("e12", "ex(open('{D}/f1', write, _, [type(_)]), R)"),
    ("e13", "ex(open('{D}/f1', write, _, [encoding(foo)]), R)"),
    ("e14", "ex(open('{D}/f1', write, _, [type(binary), encoding(utf8)]), R)"),
    ("e15", "ex(open('{D}/f1', write, _, [buffer(foo)]), R)"),
    ("e16", "mkf('{D}/r1'), ex(open('{D}/r1', read, _, [eof_action(foo)]), R)"),
    ("e17", "ex(open('{D}/f1', write, _, [lock(foo)]), R)"),
    ("e18", "ex(open('{D}/f1', write, _, [create(foo)]), R)"),
    ("e19", "ex(open('{D}/f1', write, _, [alias(1)]), R)"),
    ("e20", "ex(open('{D}/f1', write, _, [alias(_)]), R)"),
    ("e21", "ex(open('{D}/f1', write, _, [bom(foo)]), R)"),
    ("e22", "ex(open('{D}/f1', write, _, [alias(user_output)]), R)"),
    ("e23", "ex(open('{D}/f1', write, _, [alias(user_input)]), R)"),
    ("e24", "ex(open('{D}/f1', write, _, [alias(current_output)]), R)"),
    ("e25", "ex(open('{D}/f1', write, _, [alias(a25)|_]), R)"),
    ("e26", "ex(open('{D}', write, _), R)"),                  # EISDIR: existence_error + 'Is a directory'
    ("e27", "ex(open('{D}/f1', write, _, [wait(foo)]), R)"),
    ("e28", "open('{D}/f1', write, S, [foo]), close(S), R = ok"),   # an unknown option is ignored
    ("e29", "ex(( open('{D}/f1', write, S, [create(_)]), close(S) ), R)"),
    ("e30", "ex(open('{D}/sub/f', write, _), R)"),           # a directory without write permission
    ("e31", "ex(open('{D}/f1', write, _, [create([read|_])]), R)"),
    ("e32", string("ex(open('{D}/", "a"^300, "', write, _), R)")),   # ENAMETOOLONG: representation_error(max_path_length)
    ("e33", "ex(open('{D}/loop', read, _), R)"),                       # ELOOP (a symbolic link to itself)
    ("e34", "open('{D}/f1', write, S), close(S), ex(open('{D}/f1', S, _), R)"),             # a blob as the mode
    (
        "e35",
        "open('{D}/f1', write, S), close(S), ex(open('{D}/f1', write, _, [encoding(S)]), R)"
    ),   # a blob as the encoding
    # BP2 (upstream cd67bb35e): an invalid newline mode is domain_error(newline, Mode); detect is for input only
    ("e36", "ex(open('{D}/f1', write, _, [newline(foo)]), R)"),
    ("e37", "ex(open('{D}/f1', write, _, [newline(detect)]), R)"),
    ("e38", "mkf('{D}/r1'), ex(open('{D}/r1', read, _, [newline(foo)]), R)"),
    ("e39", "open('{D}/f1', write, S, [type(binary), newline(foo)]), close(S), R = ok"),   # binary: the option is not looked at
    # BP2 (upstream 7f8024cc7): a file stream's syntax error for an unterminated quote or block comment points at it
    # (file(Path, Line, LinePos, CharNo)); it pointed at the start of the term
    (
        "e40",
        "atom_codes(A, [97,44,10,32,32,39,120]), open('{D}/q1', write, W), write(W, A), close(W), open('{D}/q1', read, S), catch(read_clause(S, _, [syntax_errors(error)]), error(_, C), true), close(S), R = C"
    ),
    (
        "e41",
        "atom_codes(A, [97,44,10,32,32,47,42,32,120]), open('{D}/q1', write, W), write(W, A), close(W), open('{D}/q1', read, S), catch(read_clause(S, _, [syntax_errors(error)]), error(_, C), true), close(S), R = C"
    ),
    # the same unterminated quote, then the NEXT read on the same stream (what the reader resynchronises to): end_of_file
    (
        "e42",
        "atom_codes(A, [97,40,39,120,46,10,98,40,49,41,46,10]), open('{D}/q2', write, W), write(W, A), close(W), open('{D}/q2', read, S), catch(read_clause(S, _, [syntax_errors(error)]), error(_, C), true), catch(read_clause(S, T2, [syntax_errors(error)]), error(E2, C2), T2 = err(E2, C2)), close(S), R = C-T2"
    ),
    (
        "e43",
        "atom_codes(A, [97,40,39,120,46,10,98,40,49,41,46,10]), open('{D}/q2', write, W), write(W, A), close(W), open('{D}/q2', read, S), read_clause(S, _, [syntax_errors(dec10)]), read_clause(S, T2, [syntax_errors(dec10)]), close(S), R = T2"
    ),
    # ---- the blob: its type, identity and order
    ("s01", "open('{D}/f1', write, S), btype(S, B), close(S), R = B"),
    ("s02", "open('{D}/f1', write, S), term_to_atom(S, A), close(S), R = A"),
    (
        "s03",
        "open('{D}/f1', write, S), ( compound(S) -> C = c ; C = nc ), ( var(S) -> V = v ; V = nv ), ( S == S -> I = same ; I = diff ), close(S), R = C-V-I"
    ),
    (
        "s04",
        "open('{D}/f1', write, S1), open('{D}/f2', write, S2), ( S1 == S2 -> R0 = same ; R0 = diff ), ( S1 \\== S2 -> R1 = ne ; R1 = eq ), close(S1), close(S2), R = R0-R1"
    ),
    (
        "s05",
        "open('{D}/f1', write, S), copy_term(S, S2), ( S == S2 -> R0 = same ; R0 = diff ), assertz(zz_s(S)), zz_s(X), ( X == S -> R1 = same ; R1 = diff ), close(S), R = R0-R1"
    ),
    (
        "s06",
        "open('{D}/f1', write, S), compare(O1, S, a), compare(O2, S, \"a\"), compare(O3, S, 1), compare(O4, S, []), compare(O5, S, f(x)), compare(O6, S, S), close(S), R = [O1,O2,O3,O4,O5,O6]"
    ),
    (
        "s07",
        "open('{D}/f1', write, S, [alias(s07)]), btype(S, B), ( S == s07 -> I = alias ; I = blob ), close(s07), R = B-I"
    ),
    ("s08", "open('{D}/f1', write, a8, [alias(a8)]), close(a8), R = ok"),
    (
        "s09",
        "( open('{D}/f1', write, other, [alias(s09)]) -> R0 = yes ; R0 = no ), close(s09), R = R0"
    ),
    (
        "s10",
        "open('{D}/f1', write, S), ( S = S -> R0 = unified ; R0 = not ), close(S), R = R0"
    ),
    (
        "s11",
        "open('{D}/f1', write, S), open('{D}/f2', write, T), ( S = T -> R0 = unified ; R0 = apart ), close(S), close(T), R = R0"
    ),
    (
        "s12",
        "open('{D}/f1', write, S), ( S = foo -> R0 = unified ; R0 = apart ), close(S), R = R0"
    ),
    # ---- writing through a blob and through an alias; the file modes
    (
        "w01",
        "open('{D}/f1', write, _, [alias(w01)]), write(w01, hello), nl(w01), close(w01), R = ok"
    ),
    (
        "w02",
        "open('{D}/f1', write, S), write(S, hello), writeq(S, 'a b'), nl(S), close(S), R = ok"
    ),
    (
        "w03",
        "open('{D}/f1', write, S), write(S, abc), close(S), open('{D}/f1', append, S2), write(S2, def), close(S2), R = ok"
    ),
    (
        "w04",
        "open('{D}/f1', write, S), write(S, abcdef), close(S), open('{D}/f1', update, S2), write(S2, 'XY'), close(S2), R = ok"
    ),
    (
        "w05",
        "open('{D}/f1', write, S, [encoding(utf8), bom(true)]), write(S, '\\u00e9'), close(S), R = ok"
    ),
    (
        "w06",
        "open('{D}/f1', write, S, [encoding(iso_latin_1)]), write(S, '\\u00e9'), close(S), R = ok"
    ),
    (
        "w07",
        "open('{D}/f1', write, S, [type(binary)]), write(S, '\\u00e9a'), close(S), R = ok"
    ),
    (
        "w08",
        "open('{D}/f1', write, S, [newline(dos)]), write(S, 'a\\nb'), close(S), R = ok"
    ),
    (
        "w09",
        "open('{D}/f1', write, S, [encoding(utf8)]), write(S, '\\u00e9'), close(S), R = ok"
    ),
    (
        "w10",
        "mkf('{D}/r1'), open('{D}/r1', read, S), ex(write(S, x), R0), close(S), R = R0"
    ),
    ("w11", "open('{D}/f1', write, S), close(S), ex(write(S, x), R0), R = R0"),
    (
        "w12",
        "open('{D}/f1', write, _, [alias(w12)]), close(w12), ex(write(w12, x), R0), R = R0"
    ),
    ("w13", "open('{D}/f1', write, S, [buffer(line)]), write(S, 'a\\n'), close(S), R = ok"),
    ("w14", "open('{D}/f1', write, S, [buffer(false)]), write(S, ab), close(S), R = ok"),
    ("w15", "open('{D}/f1', write, S, [create([read])]), write(S, ab), close(S), R = ok"),
    ("w16", "open('{D}/f1', write, S, [create([all])]), close(S), R = ok"),
    ("w17", "open('{D}/f1', write, S, [bom(true)]), write(S, ab), close(S), R = ok"),
    ("w18", "open('{D}/f1', write, S, [bom(false), encoding(utf8)]), close(S), R = ok"),
    (
        "w19",
        "open('{D}/f1', append, S, [encoding(utf8), bom(true)]), write(S, a), close(S), open('{D}/f1', append, S2, [encoding(utf8), bom(true)]), write(S2, b), close(S2), R = ok"
    ),
    ("w20", "open(\"{D}/f1\", write, S), write(S, ab), close(S), R = ok"),
    (
        "w21",
        "open('{D}/f1', write, _, [reposition(false), close_on_abort(false), wait(true), type(text), alias(w21)]), close(w21), R = ok"
    ),
    ("w22", "open('{D}/f1', write, S, [create([execute, default])]), close(S), R = ok"),
    ("w23", "open('{D}/f1', write, S, [create([write])]), close(S), R = ok"),
    (
        "w24",
        "open('{D}/f1', write, S1), write(S1, a), open('{D}/f2', write, S2), write(S2, b), close(S2), write(S1, c), close(S1), R = ok"
    ),
    (
        "w25",
        "mkf('{D}/r1'), open('{D}/r1', read, _, [alias(w25)]), ex(write(w25, x), R0), close(w25), R = R0"
    ),
    # ---- close/1,2
    ("c01", "open('{D}/f1', write, S), close(S), ex(close(S), R)"),
    (
        "c02",
        "open('{D}/f1', write, S), close(S, [force(true)]), close(S, [force(true)]), R = ok"
    ),
    ("c03", "open('{D}/f1', write, S), close(S, [force(true)]), ex(close(S), R)"),
    ("c04", "open('{D}/f1', write, _, [alias(c04)]), close(c04), ex(close(c04), R)"),
    ("c05", "ex(close(nostream), R)"),
    ("c06", "ex(close(1), R)"),
    ("c07", "ex(close(_), R)"),
    ("c08", "ex(close(f(x)), R)"),
    ("c09", "close(user_output), close(user_error), R = ok"),
    ("c10", "ex(close(user_output, [force(true)]), R)"),
    ("c11", "open('{D}/f1', write, S), ex(close(S, [force(foo)]), R0), close(S), R = R0"),
    ("c12", "open('{D}/f1', write, S), ex(close(S, foo), R0), close(S), R = R0"),
    ("c13", "open('{D}/f1', write, S), close(S, [bar(1)]), R = ok"),
    (
        "c14",
        "open('{D}/f1', write, _, [alias(c14)]), close(c14), open('{D}/f2', write, _, [alias(c14)]), close(c14), R = reused"
    ),
    ("c15", "open('{D}/f1', write, S, [alias(c15)]), close(S), ex(close(c15), R)"),
    ("c16", "ex(close(protocol), R)"),
    ("c17", "ex(close(user), R)"),
    (
        "c18",
        "open('{D}/f1', write, S), ex(close(S, [force(true)|_]), R0), close(S), R = R0"
    ),
    (
        "c19",
        "open('{D}/f1', write, _, [alias(c19)]), ex(open('{D}/f2', write, _, [alias(c19)]), R0), close(c19), R = R0"
    ),
    ("c20", "close(current_output), R = ok"),
    (
        "c21",
        "open('{D}/f1', write, _, [alias(c21)]), open('{D}/f2', write, T, [alias(c21b)]), close(c21b), ex(close(T), R0), close(c21), R = R0"
    ),
    ("c22", "ex(close(user_error, [force(false)]), R)"),
    # ---- the stream term as a goal argument to a stream-taking built-in
    ("m01", "open('{D}/f1', write, S), ex(nl(S), R0), close(S), R = R0"),
    ("m02", "open('{D}/f1', write, S), ex(print(S, x), R0), close(S), R = R0"),
    ("m03", "ex(write(a, x), R)"),
    ("m04", "ex(write(1, x), R)"),
    ("m05", "ex(write(_, x), R)"),
    # LAST: the stream of an open/3 whose stream argument cannot be unified stays open (uninstantiation_error, 'stream-argument'),
    # and swipl's atom GC may close an unreachable stream any time after: no case follows it
    ("e09", "ex(open('{D}/f1', write, foo), R)")
]

# ---- the kernel's lines: for each case, `<name> <answers>`, `files <name> <file>:<bytes>:<mode> …`, `open <name> <n>`
"The number of streams open on a file under `dir` (the stream table's entries whose file name is there)."
function _open_under(gd, dir::String)::Int
    n = 0
    for s in gd.stream_table
        s === nothing && continue
        s.magic == LK.SIO_MAGIC || continue
        nm = get(gd.stream_filenames, s, nothing)
        nm === nothing && continue
        startswith(sym_text(nm), dir) && (n += 1)
    end
    return n
end

"The files of `dir` as the lines show them: `name:[bytes]:mode`, sorted by name; directories are skipped."
function _files_line(dir::String)::String
    parts = String[]
    for f in sort(readdir(dir))
        p = joinpath(dir, f)
        (
            try
                isfile(p)
            catch
                false
            end
        ) || continue    # a symlink loop (the ELOOP row) is no file
        bytes = read(p)
        push!(
            parts,
            string(
                f, ":[", join(Int.(bytes), ","), "]:", string(stat(p).mode & 0o777; base=8)
            )
        )
    end
    return join(parts, " ")
end

"Remove the regular files of `dir` (the next case starts from an empty directory)."
function _clean(dir::String)
    for f in readdir(dir)
        p = joinpath(dir, f)
        (
            try
                isfile(p)
            catch
                false
            end
        ) && rm(p; force=true)                  # a symlink loop (the ELOOP row) is no file: kept
    end
end

function kernel_lines(path::String, names::Vector{String}, dir::String)::Vector{String}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(_TL, _TL[_tls(name), lk_answers(ld, (a:a)...)...]))
                    catch e
                        "export-error " * first(sprint(showerror, e), 80)
                    end
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
        push!(out, "files $name " * _files_line(dir))
        push!(out, "open $name $(_open_under(gd, dir))")
        _clean(dir)
    end
    return out
end

# swipl's side. `enc/3` as the kernel's `enc` (a stream blob is `stream`); after each case the driver prints the files
# it left (bytes read in binary, the mode by stat(1)) and the number of streams still open on a file under Dir.
const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- blob(T, stream), !, write(stream).
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
fz_files(Name, Dir) :-
    directory_files(Dir, Fs0), msort(Fs0, Fs),
    format("files ~w ", [Name]),
    findall(Item, ( member(F, Fs), F \== '.', F \== '..', atomic_list_concat([Dir, '/', F], P), exists_file(P),
                    open(P, read, S, [type(binary)]), read_stream_to_codes(S, Cs), close(S),
                    process_create(path(stat), ['-c', '%a', P], [stdout(pipe(O))]),
                    read_string(O, _, M0), close(O), split_string(M0, "", "\n", [M]),
                    format(atom(Item), "~w:~w:~w", [F, Cs, M]) ), Items),
    atomic_list_concat(Items, ' ', Line), write(Line), nl.
fz_open(Name, Dir) :-
    findall(S, ( stream_property(S, file_name(F)), sub_atom(F, 0, _, _, Dir) ), L),
    length(L, N), format("open ~w ~w~n", [Name, N]).
fz_clean(Dir) :-
    directory_files(Dir, Fs),
    forall(( member(F, Fs), F \== '.', F \== '..', atomic_list_concat([Dir, '/', F], P), exists_file(P) ), delete_file(P)).
fz_run(File, Dir, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), ( fz_pred(N), fz_files(N, Dir), fz_open(N, Dir), fz_clean(Dir) )).
"""

"Run swipl on a program file with `LC_ALL=C.UTF-8` (the kernel's encoding is UTF-8); its output lines."
function swipl_lines(path::String, names::Vector{String}, dir::String)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', '$dir', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C.UTF-8"); stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# ---- the kernel's calls, one built-in at a time (the white-box testsets and the read-side differential)
"Call the system predicate `name` on `args`: `(status, answers)`; status `:true`, `:false`, `:exception` (the ball is the answer) or `:notported`."
function kcall(gd::LK.PL_global_data{T}, ld, name::String, args::Vector{T}) where {T}
    proc = LK.isCurrentProcedure(
        sym_key(lk_sym(T, Symbol(name))), length(args), LK.MODULE_system(gd)
    )
    @assert proc !== nothing "no system predicate $name/$(length(args))"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    pvm = LK.PutVarMap()
    for (i, x) in enumerate(args)
        LK.putSlotValue!(ld, a + i, x, pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    status = :false
    ans = T[]
    try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            status = :true
            ans = lk_answers(ld, [a + i - 1 for i in 1:length(args)]...)
        elseif rc == LK.PL_S_EXCEPTION
            status = :exception
            ans = T[lk_answer(ld, LK.PL_exception(ld, qid))]
        end
    catch e
        e isa LK.NotPortedError || rethrow()
        status = :notported
    end
    status === :notported || LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return status, ans
end

_swipl() = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")

# the directory the cases work in: a subdirectory `sub` without write permission (case e30)
function _with_dir(f::Function)
    dir = mktempdir()
    sub = joinpath(dir, "sub")
    mkdir(sub)
    chmod(sub, 0o555)
    symlink("loop", joinpath(dir, "loop"))              # a symbolic link to itself (ELOOP; not a regular file: kept by _clean)
    try
        return f(dir)
    finally
        chmod(sub, 0o755)
        rm(dir; recursive=true, force=true)
    end
end

@testset "open/3,4 and close/1,2 == live swipl, through a program; the files and the open streams too" begin
    if _swipl() === nothing
        @info "OPEN/CLOSE DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test length(_CASES) >= 90 && allunique(first.(_CASES)) && _CASES[end][1] == "e09"     # the table is whole
    else
        _with_dir() do dir
            names = ["t_$(id)" for (id, _) in _CASES]
            text =
                _PROGRAM * join(["t_$(id)(R) :- ( $g -> true ).\n" for (id, g) in _CASES])
            text = replace(text, "{D}" => dir)
            f = joinpath(mktempdir(), "p.pl")
            write(f, text)
            kl = kernel_lines(f, names, dir)
            _clean(dir)
            sw = swipl_lines(f, names, dir)
            @test length(sw) == 3 * length(names) + 1 && sw[1] == "ok"
            @test length(kl) == length(sw)
            for (k, s) in zip(kl, sw)
                @test (_norm(k)) == (_norm(s))
            end
            # not a vacuous agreement: each kind of answer and effect is in swipl's own lines
            @test count(l -> occursin("astreamform", _norm(l)), sw) >= 1           # s02: the written form
            @test count(l -> occursin(_codes("existence_error"), l), sw) >= 8
            @test count(l -> occursin(_codes("permission_error"), l), sw) >= 4
            @test count(l -> occursin(_codes("domain_error"), l), sw) >= 6
            @test count(l -> occursin(_codes("already closed"), l), sw) >= 2      # swipl 10.1.19 answers it for two rows (c01, one more)
            @test count(l -> occursin(_codes("max_symbolic_links"), l), sw) == 1       # e33: ELOOP, the link is still there
            @test count(l -> occursin(_codes("max_path_length"), l), sw) >= 1          # e32: ENAMETOOLONG
            @test count(l -> occursin(_codes("stream-argument"), l), sw) == 1
            @test count(l -> occursin(_codes("uninstantiation_error"), l), sw) == 1
            @test any(l -> startswith(l, "files t_w05 f1:[239,187,191,195,169]:"), sw)  # BOM + é
            @test any(l -> startswith(l, "files t_w08 f1:[97,13,10,98]:"), sw)           # newline(dos)
            @test any(l -> startswith(l, "files t_w03 f1:[97,98,99,100,101,102]:"), sw)  # append
            @test any(l -> startswith(l, "files t_w04 f1:[88,89,99,100,101,102]:"), sw)  # update
            @test any(l -> startswith(l, "files t_w15 f1:[97,98]:"), sw)               # create([read]): a mode of its own
            @test last(sw) == "open t_e09 1"                                           # e09's stream stays open
            # no case that closes its own streams leaves one open: every count but e09's (the last) is 0
            opens = [parse(Int, last(split(l))) for l in sw if startswith(l, "open ")]
            @test all(==(0), opens[1:(end - 1)]) && opens[end] == 1
            @test opens ==
                [parse(Int, last(split(l))) for l in kl if startswith(l, "open ")]
        end
    end
end

# ---- READING: the options swipl's get_code/2 sees against the kernel's Sgetcode on the stream the blob names
# (id, the file's bytes, the option list as text)
const _READ_CASES = [
    ("r01", UInt8[0x61, 0x62, 0x63], "[]"),
    ("r02", UInt8[0xef, 0xbb, 0xbf, 0xc3, 0xa9], "[]"),
    ("r03", UInt8[0xef, 0xbb, 0xbf, 0xc3, 0xa9], "[bom(false)]"),
    ("r04", UInt8[0xc3, 0xa9], "[encoding(iso_latin_1)]"),
    ("r05", UInt8[0xc3, 0xa9], "[type(binary)]"),
    ("r06", UInt8[], "[]"),
    ("r07", UInt8[0x61, 0x62, 0x0d, 0x0a, 0x63, 0x64], "[newline(dos)]"),
    ("r08", UInt8[0xef, 0xbb, 0xbf, 0xc3, 0xa9], "[encoding(utf8)]"),
    ("r09", UInt8[0xc3, 0xa9, 0x61], "[]"),
    ("r10", UInt8[0xef, 0xbb, 0xbf, 0x61], "[eof_action(reset), reposition(false)]"),
    ("r11", UInt8[0x61, 0x62], "[close_on_abort(false)]"),
    ("r12", UInt8[0x61, 0x62, 0x0d, 0x0a, 0x63, 0x64], "[newline(detect)]")
]
const _READ_DRIVER = raw"""
fz_read(Id, File, Opts) :-
    open(File, read, S, Opts),
    findall(C, ( between(1, 8, _), get_code(S, C) ), Cs),
    stream_property(S, encoding(E)),
    ( stream_property(S, bom(B)) -> true ; B = false ),
    close(S), format("~w ~w ~w ~w~n", [Id, Cs, E, B]).
"""

function _enc_name(e::LK.IOENC)::String
    for (n, x) in LK.encoding_names
        x == e && return String(n)
    end
    return string(e)
end

@testset "reading what open/3,4 opened: the BOM, the encoding, the newline mode == live swipl" begin
    if _swipl() === nothing
        @info "OPEN READ DIFFERENTIAL NOT RUN: `swipl` is not on PATH here."
        @test length(_READ_CASES) >= 12 && allunique(first.(_READ_CASES))     # the table is whole
    else
        dir = mktempdir()
        try
            gd = LK.PL_global_data{_TL}()
            ld = LK.PL_local_data{_TL}(gd)
            v() = mk_var(_TL, LK.fresh_var_keys!(1))
            kl = String[]
            drv = _READ_DRIVER
            ids = String[]
            for (id, bytes, opts) in _READ_CASES
                p = joinpath(dir, id)
                write(p, bytes)
                optst, ans = kcall(gd, ld, "term_to_atom", _TL[v(), lk_gnd(_TL, opts)])
                @test optst === :true
                st, oa = kcall(gd, ld, "open", _TL[_tls(p), _tls(:read), v(), ans[1]])
                @test st === :true
                blob = oa[3]
                s = LK.get_stream_handle(ld, blob, LK.SH_ALIAS | LK.SH_INPUT)
                @test s !== nothing
                # the stream's own flags, which the codes do not show: each is the option's effect
                id == "r05" && @test (s.flags & LK.SIO_TEXT) == 0               # type(binary)
                id == "r10" && @test s.position === nothing                      # reposition(false)
                id == "r10" && @test (s.flags & LK.SIO_NOFEOF) != 0              # eof_action(reset)
                id == "r11" && @test (s.flags & LK.SIO_NOCLOSE) != 0             # close_on_abort(false)
                id == "r01" &&
                    @test (s.flags & LK.SIO_NOCLOSE) == 0 && s.position !== nothing
                codes = [LK.Sgetcode(s) for _ in 1:8]
                bom = (s.flags & LK.SIO_BOM) != 0
                push!(kl, "$id $(codes) $(_enc_name(s.encoding)) $bom")
                st, _ = kcall(gd, ld, "close", _TL[blob])
                @test st === :true
                drv *= "t_$id :- fz_read('$id', '$p', $opts).\n"
                push!(ids, id)
            end
            # a UTF-16 BOM is recognised and its encoding taken (the stream layer then refuses to read: NotPortedError)
            for (id, bytes) in (
                ("r13", UInt8[0xff, 0xfe, 0x61, 0x00]),
                ("r14", UInt8[0xfe, 0xff, 0x00, 0x61])
            )
                p = joinpath(dir, id)
                write(p, bytes)
                st, oa = kcall(gd, ld, "open", _TL[_tls(p), _tls(:read), v()])
                @test st === :true
                s = LK.get_stream_handle(ld, oa[3], LK.SH_ALIAS | LK.SH_INPUT)
                push!(kl, "$id [] $(_enc_name(s.encoding)) $((s.flags & LK.SIO_BOM) != 0)")
                kcall(gd, ld, "close", _TL[oa[3]])
                drv *= "t_$id :- open('$p', read, S), stream_property(S, encoding(E)), ( stream_property(S, bom(B)) -> true ; B = false ), close(S), format(\"~w [] ~w ~w~n\", ['$id', E, B]).\n"
                push!(ids, id)
            end
            f = joinpath(mktempdir(), "r.pl")
            write(
                f,
                drv * ":- initialization(( " * join(["t_$id" for id in ids], ", ") *
                ", halt)).\n"
            )
            sw = String.(
                split(
                    chomp(
                        read(
                            pipeline(
                                addenv(`swipl -q $f`, "LC_ALL" => "C.UTF-8"); stderr=devnull
                            ),
                            String
                        )
                    ), '\n'; keepempty=false
                )
            )
            kl2 = [replace(l, ", " => ",") for l in kl]
            @test length(sw) == length(kl2)
            @test kl2 == sw
            @test any(l -> startswith(l, "r02 ") && endswith(l, " true"), sw)       # a BOM was seen
            @test any(l -> startswith(l, "r03 [65279,233,-1"), sw)                 # bom(false): U+FEFF is data
            @test any(l -> startswith(l, "r13 [] utf16le"), sw) &&
                any(l -> startswith(l, "r14 [] utf16be"), sw)
        finally
            rm(dir; recursive=true, force=true)
        end
    end
end

# ---- WHITE-BOX: what has no swipl row, each with its reason
@testset "refusals by name: pipes, locks, locales, unicode_atoms and encodings the kernel lacks" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    dir = mktempdir()
    try
        f = _tls(joinpath(dir, "f1"))
        v() = mk_var(_TL, LK.fresh_var_keys!(1))
        function opts(text::String)
            st, a = kcall(gd, ld, "term_to_atom", _TL[v(), lk_gnd(_TL, text)])
            @assert st === :true
            return a[1]
        end
        # swipl opens these (a pipe, a lock, a locale, utf16le, `text`); the kernel
        # refuses them BY NAME, before it opens a file (nothing is created)
        for (mode, o) in (
            (:write, "[lock(write)]"), (:write, "[lock(shared)]"),
            (:write, "[locale(foo)]"),
            (:write, "[unicode_atoms(nfc)]"), (:write, "[encoding(utf16le)]"),
            (:write, "[encoding(text)]"), (:write, "[encoding(wchar_t)]")
        )
            ldx = LK.PL_local_data{_TL}(gd)             # a refusal leaves its query open: a local data each
            st, _ = kcall(gd, ldx, "open", _TL[f, _tls(mode), v(), opts(o)])
            @test (o, st) == (o, :notported)
        end
        pipe = mk_expr(_TL, _TL[_tls(:pipe), lk_gnd(_TL, "true")])
        st, _ = kcall(gd, LK.PL_local_data{_TL}(gd), "open", _TL[pipe, _tls(:read), v()])
        @test st === :notported
        @test !ispath(joinpath(dir, "f1"))
    finally
        rm(dir; recursive=true, force=true)
    end
end

@testset "the blob form on a term type with a small payload: a stream blob is an atom, no payload needed" begin
    T0 = lk_term_type(Union{Int64, Float64, String})
    gd = LK.PL_global_data{T0}()
    ld = LK.PL_local_data{T0}(gd)
    dir = mktempdir()
    try
        p = lk_sym(T0, Symbol(joinpath(dir, "f1")))
        v() = mk_var(T0, LK.fresh_var_keys!(1))
        st, a = kcall(gd, ld, "open", T0[p, lk_sym(T0, :write), v()])
        @test st === :true && is_blob(a[3]) && blob_type(a[3]) === :stream
        st, _ = kcall(gd, ld, "close", T0[a[3]])
        @test st === :true
        st, a = kcall(
            gd, ld, "open",
            T0[
                p, lk_sym(T0, :write), v(),
                mk_expr(
                    T0,
                    T0[
                        lk_sym(T0, Symbol("[|]")),
                        mk_expr(T0, T0[lk_sym(T0, :alias), lk_sym(T0, :zzalias)]),
                        mk_nil(T0)
                    ]
                )
            ]
        )
        @test st === :true && sym_text(a[3]) == "zzalias"
        st, _ = kcall(gd, ld, "close", T0[lk_sym(T0, :zzalias)])
        @test st === :true
    finally
        rm(dir; recursive=true, force=true)
    end
end

@testset "the stream table: a closed stream leaves it, an unclosed one stays; a blob names its stream" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    dir = mktempdir()
    try
        f(n) = _tls(joinpath(dir, n))
        v() = mk_var(_TL, LK.fresh_var_keys!(1))
        live() = count(!isnothing, gd.stream_table)
        @test live() == 0
        st, a1 = kcall(gd, ld, "open", _TL[f("a"), _tls(:write), v()])
        st2, a2 = kcall(gd, ld, "open", _TL[f("a"), _tls(:write), v()])
        @test st === :true && st2 === :true
        b1, b2 = a1[3], a2[3]
        @test is_blob(b1) && is_blob(b2) && blob_type(b1) === :stream &&
            blob_type(b2) === :stream
        @test blob_handle(b1) != blob_handle(b2) && atomic_compare(b1, b2) != 0   # two streams, two blobs
        @test atomic_compare(b1, b1) == 0
        @test live() == 2
        s1 = LK.get_stream_handle(ld, b1, LK.SH_ALIAS | LK.SH_OUTPUT)
        @test s1 isa LK.IOSTREAM && (s1.flags & LK.SIO_OUTPUT) != 0 &&
            s1.magic == LK.SIO_MAGIC
        @test lk_eq(LK.fileNameStream(gd, s1), _tls(joinpath(dir, "a")))
        st, _ = kcall(gd, ld, "close", _TL[b1])
        @test st === :true
        @test live() == 1 && s1.magic == LK.SIO_CMAGIC && s1.context != 0     # closed: out of the table, marked
        @test LK.fileNameStream(gd, s1) === nothing                          # …and its file name forgotten
        # the blob of a closed stream names no stream; asking is existence_error(stream, Blob)
        ref1 = LK._stream_ref_of(ld, b1)
        @test ref1 isa LK.stream_ref && ref1.read == 0 && ref1.write != 0
        @test LK._stream_of(gd, ref1.write) === nothing
        st, ball = kcall(gd, ld, "close", _TL[b1])
        @test st === :exception
        @test occursin(_codes("already closed"), enc(ball[1]))
        # close/2 with force(true) closes the stream itself
        s2 = LK.get_stream_handle(ld, b2, LK.SH_ALIAS | LK.SH_OUTPUT)
        st, _ = kcall(
            gd, ld, "close",
            _TL[
                b2,
                mk_expr(
                    _TL,
                    _TL[
                        _tls("[|]"), mk_expr(_TL, _TL[_tls(:force), _tls(:true)]),
                        mk_nil(_TL)
                    ]
                )
            ]
        )
        @test st === :true && live() == 0 && s2.magic == LK.SIO_CMAGIC
        # a term that is no stream blob (a text atom, a grounded value, a blob of another type) names none
        @test LK._stream_ref_of(ld, lk_gnd(_TL, true)) === nothing
        @test LK._stream_ref_of(ld, lk_gnd(_TL, "abc")) === nothing
        @test LK._stream_ref_of(ld, _tls(:abc)) === nothing
        otype = LK.PL_blob_t(LK.PL_BLOB_UNIQUE, "s1_other")
        ow, _ = LK.lookupBlob(ld.atoms, UInt8[1, 2, 3], 3, otype)
        @test LK._stream_ref_of(ld, LK._blob_term!(ld.atoms, ld.atom_symbols, _TL, ow)) ===
            nothing
        st, _ = kcall(gd, ld, "close", _TL[lk_gnd(_TL, true)])
        @test st === :exception
        # an alias: the first alias is the stream's name for open/3, and closing frees it
        st, a3 = kcall(
            gd, ld, "open",
            _TL[
                f("b"), _tls(:write), v(),
                mk_expr(
                    _TL,
                    _TL[
                        _tls("[|]"), mk_expr(_TL, _TL[_tls(:alias), _tls(:zalias)]),
                        mk_nil(_TL)
                    ]
                )
            ]
        )
        @test st === :true && sym_text(a3[3]) == "zalias" && live() == 1
        @test haskey(gd.stream_aliases, sym_key(_tls(:zalias)))
        st, _ = kcall(gd, ld, "close", _TL[_tls(:zalias)])
        @test st === :true && live() == 0 && isempty(gd.stream_aliases)
        @test isempty(gd.stream_alias_names)
    finally
        rm(dir; recursive=true, force=true)
    end
end

@testset "PL_get_file_name: atoms, strings and code lists; the 0-code and the flags" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    function name_of(x::_TL)
        fid = LK.PL_open_foreign_frame(ld)
        t = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, t + 1, x, LK.PutVarMap())
        r = LK.PL_get_file_name(ld, t, 0)
        ex = ld.exception_term != 0
        ex && LK.PL_clear_exception(ld)
        LK.PL_close_foreign_frame(ld, fid)
        return r, ex
    end
    @test name_of(_tls("a/b")) == ("a/b", false)
    @test name_of(lk_gnd(_TL, "c/d")) == ("c/d", false)
    @test name_of(lk_gnd(_TL, "x\0y")) == (nothing, true)             # domain_error(file_name, …): swipl, c.f. the row e-series
    @test name_of(lk_gnd(_TL, "é")) == ("é", false)
    @test name_of(mk_expr(_TL, _TL[_tls("f"), _tls("x")])) == (nothing, true)     # type_error(string, f(x)) (e07)
    codes233 = mk_expr(_TL, _TL[_tls("[|]"), lk_gnd(_TL, 233), mk_nil(_TL)])
    @test name_of(codes233) == ("é", false)                            # a code list: its characters, as UTF-8
    @test name_of(lk_gnd(_TL, "a"^4095)) == ("a"^4095, false)
    @test name_of(lk_gnd(_TL, "a"^4096)) == (nothing, true)          # representation_error(max_path_length)
    @test_throws LK.NotPortedError LK.PL_get_file_name(ld, LK.PL_new_term_ref(ld), 1)
end

@testset "Sopen_file's how string: the letters it knows, EINVAL for the rest" begin
    dir = mktempdir()
    try
        p = joinpath(dir, "f")
        for how in ("wz", "wl", "wL", "x", "", "rq", "wm78", "wm7", "wmab7")
            s, errno = LK.Sopen_file(p, how)
            @test s === nothing && errno == LK.EINVAL
            @test !ispath(p)                                        # nothing was created
        end
        s, errno = LK.Sopen_file(p, "wm644")
        @test s isa LK.IOSTREAM && errno == 0
        LK.Sclose(s)
        @test filemode(p) & 0o777 == (0o644 & ~LK._current_umask())
        s, errno = LK.Sopen_file(p, "rb")
        @test s isa LK.IOSTREAM && (s.flags & LK.SIO_TEXT) == 0 &&
            s.encoding == LK.ENC_OCTET
        LK.Sclose(s)
        s, errno = LK.Sopen_file(joinpath(dir, "nodir", "f"), "w")
        @test s === nothing && errno == LK.ENOENT
    finally
        rm(dir; recursive=true, force=true)
    end
end

@testset "create(Modes): the file gets the bits upstream ors together, less the umask — kernel and swipl, three umasks" begin
    # the program rows run under the CALLER's umask (CI's 022 hides 777 vs 755): here the umask is set, to 0, 022 and 077
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    dir = mktempdir()
    old = ccall(:umask, Cuint, (Cuint,), 0x00000000)
    try
        v() = mk_var(_TL, LK.fresh_var_keys!(1))
        n = 0
        function kernel_mode(modes::String)
            n += 1
            st, oa = kcall(
                gd, ld, "term_to_atom", _TL[v(), lk_gnd(_TL, "[create($modes)]")]
            )
            @assert st === :true
            p = joinpath(dir, "k$n")
            st, a = kcall(gd, ld, "open", _TL[_tls(p), _tls(:write), v(), oa[1]])
            @assert st === :true
            kcall(gd, ld, "close", _TL[a[3]])
            return filemode(p) & 0o777
        end
        function swipl_mode(modes::String)
            n += 1
            p = joinpath(dir, "s$n")
            goal = "open('$p', write, S, [create($modes)]), close(S)"
            run(
                pipeline(
                    `$(_swipl()) -q -g $goal -t halt`; stdin=devnull, stdout=devnull,
                    stderr=devnull
                )
            )
            return filemode(p) & 0o777
        end
        cases = (
            ("[all]", 0o777), ("[read,write]", 0o666), ("[read]", 0o444),
            ("[write]", 0o666), ("[execute]", 0o111), ("[read,execute]", 0o555),
            ("[default]", 0o666), ("[]", 0o000)
        )
        checked = 0
        for um in (0o000, 0o022, 0o077), (modes, bits) in cases
            ccall(:umask, Cuint, (Cuint,), Cuint(um))
            km = kernel_mode(modes)
            @test km == Int(bits) & ~Int(um)           # (octal literals are sized by their digits: UInt8, UInt16)
            _swipl() === nothing || @test swipl_mode(modes) == km      # swipl's own answer, same umask
            checked += 1
        end
        @test checked == 24
    finally
        ccall(:umask, Cuint, (Cuint,), old)
        rm(dir; recursive=true, force=true)
    end
end

@testset "the options set the stream's flags; closing keeps the standard streams and puts the current ones back" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    dir = mktempdir()
    try
        v() = mk_var(_TL, LK.fresh_var_keys!(1))
        listt(items::Vector{_TL}) = foldr(
            (h, t) -> mk_expr(_TL, _TL[_tls("[|]"), h, t]), items; init=mk_nil(_TL)
        )
        opt(n::Symbol, x::Symbol) = mk_expr(_TL, _TL[_tls(n), _tls(x)])
        function openflags(mode::Symbol, o::_TL)
            st, a = kcall(gd, ld, "open", _TL[_tls(joinpath(dir, "f")), _tls(mode), v(), o])
            @assert st === :true
            s = LK.get_stream_handle(ld, a[3], LK.SH_ALIAS)
            kcall(gd, ld, "close", _TL[a[3]])
            return s.flags
        end
        # eof_action sets the flags of a READ stream (the file is made by the first open); upstream: set_eof_action
        openflags(:write, listt(_TL[]))
        fe = openflags(:read, listt(_TL[opt(:eof_action, :error)]))
        @test (fe & LK.SIO_FEOF2ERR) != 0 && (fe & LK.SIO_NOFEOF) == 0
        fe = openflags(:read, listt(_TL[opt(:eof_action, :reset)]))
        @test (fe & LK.SIO_NOFEOF) != 0 && (fe & LK.SIO_FEOF2ERR) == 0
        fe = openflags(:read, listt(_TL[opt(:eof_action, :eof_code)]))
        @test (fe & (LK.SIO_NOFEOF | LK.SIO_FEOF2ERR)) == 0
        # buffer sets the buffering of a WRITE stream
        for (b, flag) in
            ((:full, LK.SIO_FBUF), (:line, LK.SIO_LBUF), (Symbol("false"), LK.SIO_NBUF))
            fl = openflags(:write, listt(_TL[opt(:buffer, b)]))
            @test (fl & (LK.SIO_FBUF | LK.SIO_LBUF | LK.SIO_NBUF)) == flag
        end
        fl = openflags(
            :write,
            listt(_TL[opt(:encoding, :utf8), mk_expr(_TL, _TL[_tls(:bom), _tls(:true)])])
        )
        @test (fl & LK.SIO_BOM) != 0                                # SwriteBOM
        fl = openflags(
            :write,
            listt(
                _TL[
                    opt(:encoding, :utf8),
                    mk_expr(_TL, _TL[_tls(:bom), _tls(Symbol("false"))])
                ]
            )
        )
        @test (fl & LK.SIO_BOM) == 0
        fl = openflags(:append, listt(_TL[]))
        @test (fl & LK.SIO_APPEND) != 0 && (fl & LK.SIO_OUTPUT) != 0
        fl = openflags(:update, listt(_TL[]))
        @test (fl & LK.SIO_UPDATE) != 0
        fl = openflags(:read, listt(_TL[]))
        @test (fl & LK.SIO_INPUT) != 0 && (fl & LK.SIO_TEXT) != 0

        # the standard streams are flushed, never closed, by close/1 and close(S, [force(true)])
        LK._initIO(ld)
        uo, ue = LK.Suser_output(ld), LK.Suser_error(ld)
        @test uo isa LK.IOSTREAM && ue isa LK.IOSTREAM
        for which in (:user_output, :user_error)
            st, _ = kcall(gd, ld, "close", _TL[_tls(which)])
            @test st === :true
        end
        st, _ = kcall(
            gd, ld, "close",
            _TL[
                _tls(:user_output), listt(_TL[mk_expr(_TL, _TL[_tls(:force), _tls(:true)])])
            ]
        )
        @test st === :true
        @test LK.Suser_output(ld) === uo && uo.magic == LK.SIO_MAGIC
        @test LK.Suser_error(ld) === ue && ue.magic == LK.SIO_MAGIC

        # a stream that is the current output when it is closed: the current output is the user output again
        # (set_output/1 is not ported: the local data is set the way it would be)
        st, a = kcall(gd, ld, "open", _TL[_tls(joinpath(dir, "g")), _tls(:write), v()])
        s = LK.get_stream_handle(ld, a[3], LK.SH_ALIAS)
        ld.IO_streams[LK.SNO_CURRENT_OUTPUT + 1] = s
        @test LK.Scurout(ld) === s
        st, _ = kcall(gd, ld, "close", _TL[a[3]])
        @test st === :true && LK.Scurout(ld) === LK.Suser_output(ld)
    finally
        rm(dir; recursive=true, force=true)
    end
end

# The standard streams over whatever Julia's stdin, stdout and stderr are (MOD2's CI red, D-0245: under CI's Pkg.test
# user_error did not exist, `existence_error(stream, user_error)`): upstream's standard stream n is file descriptor n
# whatever it is (pl-stream.c S__iob0). stream_property/2 is not ported: the alias is reached through nl/1, which
# resolves it as every stream argument does (get_stream_handle), and white-box through get_stream_handle itself.
@testset "the standard streams exist whatever Base.stdin/stdout/stderr are; nl(user_error) finds its stream" begin
    @info "the process's stdio" typeof(Base.stdin) typeof(Base.stdout) typeof(Base.stderr)
    nl_on(gd, ld, a::Symbol) = first(kcall(gd, ld, "nl", _TL[_tls(a)]))
    # the process's own stdio, as the runner left it
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    @test nl_on(gd, ld, :user_error) === :true
    @test nl_on(gd, ld, :user_output) === :true
    for (which, io) in enumerate((Base.stdin, Base.stdout, Base.stderr))
        s = ld.IO_streams[which]
        @test s isa LK.IOSTREAM
        @test LK.get_stream_handle(ld, _tls(LK.standardStreams[which]), LK.SH_ALIAS) === s
        # an IO the stream layer holds is the stream's own IO; any other gives way to the file descriptor
        if io isa Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint}
            @test s.handle.io === io
        else
            @test s.handle.io isa IOStream && s.handle.io.name == "<fd $(which - 1)>"
        end
    end
    # a Base.stderr of a type the stream layer cannot hold (a wrapper, as a runner may put there): user_error is the
    # OS file descriptor 2 itself, never an existence error
    old = Base.stderr
    setglobal!(Base, :stderr, IOContext(old, :lk_test => true))
    try
        @test !(Base.stderr isa Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint})
        gd2 = LK.PL_global_data{_TL}()
        ld2 = LK.PL_local_data{_TL}(gd2)
        @test nl_on(gd2, ld2, :user_error) === :true
        s = LK.Suser_error(ld2)
        @test s isa LK.IOSTREAM &&
            LK.get_stream_handle(ld2, _tls(:user_error), LK.SH_ALIAS) === s
        @test s.handle isa LK.Sjulia_io && s.handle.io isa IOStream &&
            s.handle.io.name == "<fd 2>"
        @test (s.flags & LK.SIO_ISATTY) == 0 && (s.flags & LK.SIO_NBUF) != 0
        # a standard stream put back after its stream was closed (restoreStandardStream) is file descriptor 2 too
        r = LK.restoreStandardStream(ld2, LK.SNO_USER_ERROR)
        @test r isa LK.IOSTREAM && r === LK.Suser_error(ld2) && r !== s
        @test r.handle.io isa IOStream && r.handle.io.name == "<fd 2>"
    finally
        setglobal!(Base, :stderr, old)
    end
end
