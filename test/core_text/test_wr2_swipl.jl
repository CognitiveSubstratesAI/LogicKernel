# ORIGINAL: a differential of WR2's writer part 2 (write_term/2,3's integer_format/float_format and blobs(portray), PL_get_text's CVT_WRITE*) against swipl at the pin
# test/core_text/test_wr2_swipl.jl — three parts:
#   * THE ROWS, through a PROGRAM (the pattern of test/core_lang/test_sys_swipl.jl): test_wr2_swipl.pl holds the rows, each a predicate
#     `tN(R)`; the kernel consults the program and enumerates every solution of every tN/1, and its lines are compared with
#     test_wr2_swipl.out — swipl 10.1.20's own, printed by the driver below. When `swipl` is on PATH the .out is checked against a live run
#     as well, so it cannot go stale. The rows: `integer_format` and `float_format` (writeNumber through do_format: the formats, a bignum,
#     the separating space, the format errors) and `blobs(portray)` (writeAtom through callPortray: a stream and a clause reference are
#     offered to portray/1, a text atom, `[]` and the numbers are not; portray/1 failing, throwing, and not defined; the priority a blob's
#     portray_goal receives (t66: 1200, the option's own 999 is not it); a negative BIGNUM after a symbol character, t64 and t65).
#     A JULIA TESTSET of its own runs t48 and t67 with `gd.halt_cleaning` raised (portray/1 is called up to CLN_PROLOG, not after it).
#   * PL_get_text WITH CVT_WRITE, CVT_WRITEQ, CVT_WRITE_CANONICAL (pl-text.c `case_write`): no kernel caller passes the flags at the pin and
#     swipl cannot answer `PL_get_text` itself, so the expected text is the Prolog EQUIVALENT swipl computes (an equivalent, not the C function
#     itself): `numbervars(T, 0, _, [singletons(true)])` then `write_term(T, [numbervars(true)])` for CVT_WRITE, the same with `quoted(true)` for
#     CVT_WRITEQ, `write_canonical/1` for CVT_WRITE_CANONICAL — on ASCII terms only (write_canonical/1 adds `pattern_syntax_solo`, the C flags
#     do not; so the canonical rows hold no non-ASCII text). The combinations with CVT_LIST and CVT_ATOM are the text swipl's `text_to_string/2`
#     and `atom_string/2` give, else the write. The .out of this part is test_wr2_cvt_swipl.out, printed by the CVT driver below.
#     THE MAPPING from each CVT_* flag to the write options, cited at the pin (swipl-devel 18168e629eab, `git show <pin>:<file>`):
#       - src/os/pl-text.c:372-373   CVT_WRITEQ           -> PL_WRT_QUOTED|PL_WRT_NUMBERVARS   (== writeq/1, src/pl-write.c:3155)
#       - src/os/pl-text.c:374-377   CVT_WRITE_CANONICAL  -> PL_WRT_QUOTED|QUOTE_NON_ASCII|IGNOREOPS|VARNAMES|NODOTINATOM|BRACETERMS
#                                    (== write_canonical/1's flags, src/pl-write.c:3191-3194, MINUS PL_WRT_PATTERN_SYNTAX_SOLO at :3192)
#       - src/os/pl-text.c:378-379   CVT_WRITE (neither)  -> PL_WRT_NUMBERVARS                 (== write/1, src/pl-write.c:3145)
#       - src/os/pl-text.c:382-389   BEGIN_NUMBERVARS(true); numberVars with functor '$VAR'/1, on_attvar AV_SKIP, singletons = PL_is_acyclic(l),
#                                    numbered_check false  (== write_canonical/1's numbering, src/pl-write.c:3182-3187)
#       - the options' effect: PL_WRT_NUMBERVARS|VARNAMES make '$VAR'(N) a name (src/pl-write.c:2414), PL_WRT_IGNOREOPS writes operators
#         canonically (:2472), PL_WRT_QUOTED quotes atoms (:1320), PL_WRT_QUOTE_NON_ASCII quotes a non-ASCII atom (:405).
#     EQUIVALENT-BASED ROWS (D-0457 item 1b): every CVT row below is an equivalent, not the C function. The goal swipl EVALUATES per kind (the
#     CVT driver's `cvt_text/3`): write -> `numbervars(T,0,_,[singletons(true)]), with_output_to(string(S), write_term(T,[numbervars(true)]))`;
#     writeq -> the same with `quoted(true)`; canonical -> `with_output_to(string(S), write_canonical(T))`; list_<m> -> `text_to_string(T,S)` when
#     T is a code/char list else the <m> goal; atom_<m> -> `atom_string(T,S)` when T is an atom else the <m> goal.
#     THE NON-ASCII write_canonical EXCLUSION is a DIVERGES in docs/architecture.md (WR2, owner ENC1): the equivalent `write_canonical/1`
#     differs from the C flags by PL_WRT_PATTERN_SYNTAX_SOLO and runs over the stream's own encoding, while pl-text.c:363-370 tries ISO Latin-1
#     then ENC_WCHAR (the kernel's stream layer is UTF-8 only until ENC1), so no oracle value exists for non-ASCII canonical text.
#   * the kernel's own invariants that no swipl row reaches: the text's length is its code points, the numbervars frame is closed after the
#     call (the term's variables are unbound again), and the numbering of an acyclic term is the singletons' `_`.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
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

const _WR2_PL = joinpath(@__DIR__, "test_wr2_swipl.pl")
const _WR2_OUT = joinpath(@__DIR__, "test_wr2_swipl.out")
const _WR2_CVT_OUT = joinpath(@__DIR__, "test_wr2_cvt_swipl.out")

# the rows' names, in the order of the program
_wr2_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_WR2_PL, String))])

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions. `before(gd, name)` runs before a row's query (the halt
# rows set `gd.halt_cleaning` there), `after(gd, name)` after it.
function kernel_lines(
    path::String, names::Vector{String}; after::Function=(gd, name) -> nothing,
    before::Function=(gd, name) -> nothing
)::Vector{String}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    for name in names
        before(gd, name)
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
        while (n += 1) <= 100
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
        after(gd, name)
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

# the driver swipl runs to print its lines (the .out is its output)
const DRIVER = raw"""
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
    catch(findnsols(100, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


@testset "WR2: integer_format, float_format and blobs(portray) == swipl's answers (the .out), through a program" begin
    names = _wr2_names()
    expected = String.(readlines(_WR2_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test length(names) >= 60
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test any(l -> occursin(_codes("1,234,567"), l), expected)            # ~D
    @test any(l -> occursin(_codes("12.34"), l), expected)                # ~2d
    @test any(l -> occursin(_codes("3.14"), l), expected)                 # ~2f
    @test any(l -> occursin("61,32,45,49", l), expected)                   # the separating space ("= -1")
    @test any(l -> occursin(_codes("format_argument_type"), l), expected) # a format error
    @test any(l -> occursin(_codes("not enough arguments"), l), expected)
    @test count(l -> occursin("60,83,62", l), expected) >= 4              # portray/1 called for a blob ("<S>")
    @test any(l -> occursin(_codes("portray_oops"), l), expected)         # a portray/1 that throws
    @test any(l -> occursin("prefix_ok", l) || occursin(_codes("prefix_ok"), l), expected)  # a blob portray/1 declined

    kl = kernel_lines(_WR2_PL, names)
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "WR2 ROWS NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_WR2_PL, names) == expected                  # the .out is swipl's, still
    end
end

# ── callPortray's and writeAtom's halt tests (pl-write.c callPortray: `GD->halt.cleaning > CLN_PROLOG` returns 0, "avoid dangerous callbacks") ──
# A JULIA row: swipl cannot be put into its own halt sequence from a program, so the values during CLN_FOREIGN have no oracle; what a program can
# ask swipl is the NORMAL answer of the two rows run here, and that is the .out's line: portray/1 IS called while `halt_cleaning <= CLN_PROLOG`
# (the run before the halt, and CLN_PROLOG itself, the first stage of PL_cleanup: Prolog still runs), and is NOT called after it (CLN_FOREIGN).
#   t67: `portray(foo) :- write(bar)` under `write_term(f(foo), [portray(true)])`: `f(bar)`, and `f(foo)` once the halt is past CLN_PROLOG
#        (callPortray's test, src/pl-write.jl:1318: kills WR2-C1 (no test: portray/1 IS called in CLN_FOREIGN) and WR2-C2 (`>=`: not called in CLN_PROLOG));
#   t48: a stream blob with `blobs(portray)` and portray/1 writing `<S>` for a stream: `<S>` also in CLN_PROLOG (writeAtom's own test,
#        src/pl-write.jl:869, `<=`: kills WR2-P12, whose `<` offers no blob to portray/1 in CLN_PROLOG, so the blob is written `<stream>(0x...)`).
function _wr2_expected(name)
    ex = String.(readlines(_WR2_OUT))
    return ex[findfirst(l -> startswith(l, name * " "), ex)]
end
# a row's line when its one answer is the string `text` (the format of the .out: `tN c<codes of tN>/1(s<codes of text>)`)
_wr2_line(name, text) = name * " c" * _codes(name) * "/1(s" * _codes(text) * ")"

@testset "WR2: portray/1 during halt: gd.halt_cleaning <= CLN_PROLOG calls it, > CLN_PROLOG does not (C1, C2, P12)" begin
    # the rows are in the .out and answer what the control says
    @test _wr2_expected("t67") == _wr2_line("t67", "f(bar)")
    @test _wr2_expected("t48") == _wr2_line("t48", "<S>")
    rows = ["t48", "t67"]
    for level in (LK.CLN_NORMAL, LK.CLN_PROLOG)
        kl = kernel_lines(_WR2_PL, rows; before=(gd, name) -> (gd.halt_cleaning = level))
        @test kl == ["ok", _wr2_expected("t48"), _wr2_expected("t67")]       # portray/1 is called: <S>, f(bar)
    end
    # CLN_FOREIGN and after: portray/1 is not called for the atom foo (WR2-C1: it would answer f(bar))
    for level in (LK.CLN_FOREIGN, LK.CLN_IO, LK.CLN_DATA)
        kl = kernel_lines(_WR2_PL, ["t67"]; before=(gd, name) -> (gd.halt_cleaning = level))
        @test kl == ["ok", _wr2_line("t67", "f(foo)")]
    end
end

# ── PL_get_text with CVT_WRITE* ────────────────────────────────────────────────────────────────────
# (name, kind, source text). kind: write, writeq, canonical (CVT_WRITE, CVT_WRITEQ, CVT_WRITE_CANONICAL alone); list_<m> and atom_<m>:
# CVT_LIST or CVT_ATOM with CVT_WRITE (m = write) or CVT_WRITEQ (m = writeq).
const _CVT_ASCII = String[
    "foo", "'a b'", "f(X, Y, X)", "f(A, _B)", "f(X, _, X, Y)", "'\$VAR'(3)",
    "'\$VAR'('Foo')", "'\$VAR'(x)",
    "- (1)", "-(-(1))", "1 - 2", "f(- 1)", "a:b:c", "[1,2|T]", "{a,b}", "\"str\"", "1.5",
    "f('A', 'b c', \"q\")",
    "a+b*c", "(a,b)", "'hello world'(x)", "[]", "'[]'", "{}", "f(;, '|', [])", "f(a;b)",
    "\\+a", "a=..b", "1.0e10",
    "123456789012345678901234567890", "[a,[b,[c|D]]]", "'\\n'", "f(\"a\\nb\")", "p :- q, r",
    "- a", "1 rdiv 3"
]
const _CVT_UNICODE = String[
    "'é'(λ)", "'日本語'", "f('Éa', \"ü\")", "'x y'(1)", "'\$VAR'('Éa')"
]
const _CVT_COMBOS = Tuple{String, String}[
    ("list_write", "[0'a, 0'b, 0'c]"), ("list_writeq", "[0'a, 0'b]"),
    ("list_write", "[a|T]"), ("list_writeq", "f(X)"),
    ("list_write", "[a, b]"), ("list_writeq", "[]"), ("atom_writeq", "'a b'"),
    ("atom_writeq", "f(X, Y, X)"),
    ("atom_write", "'a b'"), ("atom_write", "\"str\""), ("atom_writeq", "[]")
]
const _CVT_ROWS = let rows = Tuple{String, String, String}[], n = 0
    for s in _CVT_ASCII, k in ("write", "writeq", "canonical")
        push!(rows, ("r$(n += 1)", k, s))
    end
    for s in _CVT_UNICODE, k in ("write", "writeq")
        push!(rows, ("r$(n += 1)", k, s))
    end
    for (k, s) in _CVT_COMBOS
        push!(rows, ("r$(n += 1)", k, s))
    end
    rows
end

const _CVT_FLAGS = Dict(
    "write" => LK.CVT_WRITE, "writeq" => LK.CVT_WRITEQ,
    "canonical" => LK.CVT_WRITE_CANONICAL,
    "list_write" => LK.CVT_LIST | LK.CVT_WRITE,
    "list_writeq" => LK.CVT_LIST | LK.CVT_WRITEQ,
    "atom_write" => LK.CVT_ATOM | LK.CVT_WRITE, "atom_writeq" =>
        LK.CVT_ATOM | LK.CVT_WRITEQ
)

# the Prolog equivalents swipl computes (see the header)
const _CVT_DRIVER = raw"""
cvt_text(write, T, S) :- numbervars(T, 0, _, [singletons(true)]),
    with_output_to(string(S), write_term(T, [numbervars(true)])).
cvt_text(writeq, T, S) :- numbervars(T, 0, _, [singletons(true)]),
    with_output_to(string(S), write_term(T, [quoted(true), numbervars(true)])).
cvt_text(canonical, T, S) :- with_output_to(string(S), write_canonical(T)).
cvt_text(list_write, T, S) :- cvt_list(write, T, S).
cvt_text(list_writeq, T, S) :- cvt_list(writeq, T, S).
cvt_text(atom_write, T, S) :- cvt_atom(write, T, S).
cvt_text(atom_writeq, T, S) :- cvt_atom(writeq, T, S).
cvt_list(M, T, S) :- ( is_list(T), catch(text_to_string(T, S0), _, fail) -> S = S0 ; cvt_text(M, T, S) ).
cvt_atom(M, T, S) :- ( atom(T) -> atom_string(T, S) ; cvt_text(M, T, S) ).
cvt_row(N, K, Src) :- term_to_atom(T, Src),
    \+ \+ ( cvt_text(K, T, S), string_codes(S, Cs), format("~w ~w~n", [N, Cs]) ).
cvt_run(File) :- consult(File), forall(row(N, K, Src), cvt_row(N, K, Src)).
"""

function _cvt_swipl_lines()::Vector{String}
    out = mktempdir() do d
        rows = joinpath(d, "rows.pl")
        write(
            rows,
            join([
                "row($n, $k, '$(replace(s, "\\" => "\\\\", "'" => "\\'"))').\n" for
                (n, k, s) in _CVT_ROWS
            ])
        )
        f = joinpath(d, "drv.pl")
        write(f, _CVT_DRIVER * ":- initialization((cvt_run('$rows'), halt)).\n")
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the kernel's text of `src` under `flags`: (its code points, whether `text.length` is their count, its encoding, its `canonical` field, whether the
# term's first argument is a variable again afterwards)
const _CVT_GD = LK.PL_global_data{_TL}()
const _CVT_LD = LK.PL_local_data{_TL}(_CVT_GD)
function _cvt_kernel(src::String, flags::UInt32)
    gd = _CVT_GD
    ld = _CVT_LD
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(ld, a + 2, lk_gnd(_TL, src), pvm)
    proc = LK.isCurrentProcedure(sym_key(_tls("term_to_atom")), 2, LK.MODULE_system(gd))
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    result = nothing
    if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        txt = LK.PL_get_text(ld, a, flags)
        if txt !== nothing
            s = String(copy(txt.text))
            result = (Int[Int(c) for c in s], txt.length == length(s), txt.encoding)
            result = (result..., txt.canonical)
        end
        # the numbervars frame is closed: the term's first argument, a variable when it was read, is a variable again
        v = LK.PL_new_term_ref(ld)
        isvar = LK._PL_get_arg(ld, 1, a, v) && LK.PL_is_variable(ld, v)
        result === nothing || (result = (result..., isvar))
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return result
end

function _cvt_kernel_lines()::Vector{String}
    out = String[]
    for (n, k, s) in _CVT_ROWS
        r = _cvt_kernel(s, UInt32(_CVT_FLAGS[k]))
        r === nothing && (push!(out, "$n NOTEXT"); continue)
        push!(out, "$n [" * join(r[1], ",") * "]")
    end
    return out
end

@testset "WR2: PL_get_text CVT_WRITE, CVT_WRITEQ, CVT_WRITE_CANONICAL == the Prolog equivalents swipl computes" begin
    expected = String.(readlines(_WR2_CVT_OUT))
    @test length(_CVT_ROWS) >= 120
    @test length(expected) == length(_CVT_ROWS)
    @test all(i -> startswith(expected[i], _CVT_ROWS[i][1] * " "), eachindex(_CVT_ROWS))
    # the corpus has non-ASCII rows and variables, and a row per kind
    @test any(l -> occursin(",955", l) || occursin("[955", l), expected)             # a lambda
    @test count(r -> r[2] == "canonical", _CVT_ROWS) == length(_CVT_ASCII)           # a row per term and kind
    @test count(r -> r[2] == "write", _CVT_ROWS) > length(_CVT_ASCII)

    kl = _cvt_kernel_lines()
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "WR2 CVT ROWS NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test _cvt_swipl_lines() == expected
    end
end

@testset "WR2: PL_get_text CVT_WRITE*: the kernel's invariants" begin
    # the length is the code points'; the encoding is UTF-8 and not canonical (the approved DIVERGES); the variables are unbound afterwards
    for (src, flags) in (
        ("f(X, Y, X)", LK.CVT_WRITE), ("'日本語'(λ)", LK.CVT_WRITEQ),
        ("g('é', Z)", LK.CVT_WRITE),
        ("h(A, \"s\")", LK.CVT_WRITE_CANONICAL)
    )
        r = _cvt_kernel(src, UInt32(flags))
        @test r !== nothing
        r === nothing && continue
        @test r[2]                                                    # text.length == the code points
        @test r[3] == LK.ENC_UTF8
        @test !r[4]                                                   # a UTF-8 text is never `canonical` (pl-text.jl:29; WR2-T19: tagged canonical)
    end
    # a variable written twice: the SAME name; once: `_` (singletons)
    r = _cvt_kernel("f(X, Y, X)", UInt32(LK.CVT_WRITE))
    @test r !== nothing && String(Char.(r[1])) == "f(A,_,A)"
    r = _cvt_kernel("f(X, Y, X)", UInt32(LK.CVT_WRITE))
    @test r !== nothing && r[5]                                       # END_NUMBERVARS: the first argument is a variable again
    r = _cvt_kernel("f(a, Y, X)", UInt32(LK.CVT_WRITEQ))
    @test r !== nothing && !r[5]                                      # (a control: its first argument is `a`)
    # WR2-T9, a LITERAL row (no oracle): CVT_WRITE_CANONICAL writes with PL_WRT_QUOTE_NON_ASCII (pl-text.c:374-377), so a non-ASCII atom is QUOTED
    # (pl-write.jl:186): `'é'('λ')`; the oracle rows are ASCII only (write_canonical/1 adds pattern_syntax_solo, header). swipl's own, as a cross-check made
    # by hand at the pin: `write_term('é'(λ), [quoted(true), quote_non_ascii(true), ignore_ops(true)])` and `write_canonical('é'(λ))` both print `'é'('λ')`.
    r = _cvt_kernel("'é'(λ)", UInt32(LK.CVT_WRITE_CANONICAL))
    @test r !== nothing && String(Char.(r[1])) == "'é'('λ')"
    # WR2-T13, a LITERAL row: the text of the string "a\0" under CVT_WRITE is [97,0]: the EOS written after the text (Sputcode(EOS)) is what the strip
    # at pl-text.jl:97 removes, so the text's own NUL stays. The equivalent swipl computes for CVT_WRITE (header) agrees, at the pin: `T = "a\0",
    # numbervars(T,0,_,[singletons(true)]), with_output_to(string(S), write_term(T,[numbervars(true)])), string_codes(S,C)` is C = [97,0].
    r = _cvt_kernel("\"a\\0\"", UInt32(LK.CVT_WRITE))
    @test r !== nothing && r[1] == [97, 0]
    # CVT_WRITE alone on an atom is written, not refused (it threw NotPortedError before WR2)
    @test _cvt_kernel("foo", UInt32(LK.CVT_WRITE)) !== nothing
end
