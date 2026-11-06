# ORIGINAL: S2a3's gate (audit D-0431 item 5) — the three process streams bound when an engine is made (pl-file.c initIO), against swipl 10.1.19
# test/files/test_process_streams_swipl.jl — prefix `_PS` / `_ps_`:
#   * A ROW PER STREAM (user_input, user_output, user_error), asked on an engine that has done nothing yet (its first stream access): ten properties
#     through `'$stream_property'/2` (mode, alias, input, output, eof_action, buffer, type, representation_errors, newline, file_no) and four
#     current_input/current_output against `'$alias_stream'/2` rows, each answer written as text by ONE extractor on both sides. The pins are swipl
#     10.1.19-1-gcbf4e189's (two byte-identical runs, also under LC_ALL=C, 2026-11-06); with `swipl` on PATH the live answers are compared with them
#     too. NOT in the rows (they follow the host, not the stream layer): `reposition` and `tty` (a file, a pipe or a terminal), `encoding`
#     (the locale), `close_on_exec`.
#   * White-box rows from the C code (pl-file.c initIO, pl-stream.c S__iob0): the flags of each stream, the position record the three share, Scurin and
#     Scurout, the table entry of each stream; `_bare_local_data` (the engine setupProlog makes for itself) holds none.
#   * The finding (S2a, status_board.md, LB7's first run): on a database that is not initialised, the autoloader's `push_input_context` stored
#     `Scurin(ld) === nothing` and `$input_context/1` died on `c.stream::IOSTREAM` (a Julia TypeError). A program consulted there calls member/2 (autoloaded
#     from library(lists)); it now answers as swipl does.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the standard streams (src/os/pl-file.jl) over the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _PS = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_pss(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

"The ONE extractor of both sides: an atom's text, an integer, `name(arg, …)` for a compound (what swipl's `~q` writes for these properties)."
function _ps_text(t::T)::String where {T}
    k = kind(t)
    k === SYM && return sym_text(t)
    k === GND && return string(lk_value(t))
    k === VAR && return "_"
    h = child(t, 1)
    return sym_text(h) * "(" * join([_ps_text(child(t, i)) for i in 2:nchildren(t)], ",") *
           ")"
end

"A Prolog list `[a,b,c]` as the vector of its elements' texts (a list is `'[|]'(H, T)` ending in `[]`)."
function _ps_list(t::T)::Vector{String} where {T}
    out = String[]
    while kind(t) === EXPR && nchildren(t) == 3
        push!(out, _ps_text(child(t, 2)))
        t = child(t, 3)
    end
    return out
end

const _PS_ALIASES = (:user_input, :user_output, :user_error)
const _PS_PROPS = (
    (:mode, 1), (:alias, 1), (:input, 0), (:output, 0), (:eof_action, 1), (:buffer, 1),
    (:type, 1), (:representation_errors, 1), (:newline, 1), (:file_no, 1)
)
# (alias, which current stream, the alias it is compared with)
const _PS_CURRENT = (
    (:current_input, :user_input), (:current_output, :user_output),
    (:current_output, :user_error), (:current_input, :user_error)
)

# swipl 10.1.19-1-gcbf4e189, `'$stream_property'(Alias, P)` per alias and property in _PS_PROPS' order, then the four _PS_CURRENT rows.
# KNOWN DIFFERENCE (rows 10, 20, 30: file_no): swipl answers file_no(0), file_no(1), file_no(2) (pl-file.c:4996-5005, swipl 10.1.19: the
# S__iob descriptors); the kernel's stream layer has no OS descriptor, so the landed DIVERGES `stream_file_no_prop` (src/os/pl-file.jl:~2187)
# always fails and the row reads "none". The three rows pin OUR answer; _PS_FILE_NO_SWIPL has swipl's, and the live compare skips these rows.
const _PS_PINS = String[
    "mode(read)", "alias(user_input)", "input", "none", "eof_action(reset)", "buffer(line)",
    "type(text)", "representation_errors(error)", "newline(posix)", "none",
    "mode(write)", "alias(user_output)", "none", "output", "eof_action(eof_code)",
    "buffer(line)",
    "type(text)", "representation_errors(unicode)", "newline(posix)", "none",
    "mode(write)", "alias(user_error)", "none", "output", "eof_action(eof_code)",
    "buffer(false)",
    "type(text)", "representation_errors(unicode)", "newline(posix)", "none",
    "same", "same", "other", "other"
]
const _PS_FILE_NO_ROWS = (10, 20, 30)
const _PS_FILE_NO_SWIPL = ("file_no(0)", "file_no(1)", "file_no(2)")      # swipl 10.1.19, pl-file.c:4996-5005

"A fresh engine on a fresh database: nothing has asked for a stream yet."
function _ps_engine(::Type{T}) where {T}
    gd = LK.PL_global_data{T}()
    return gd, LK.PL_local_data{T}(gd)
end

"The first answer of `goal` on `ld` as `_ps_text` writes its `idx`-th child's argument `arg`, or \"none\"."
function _ps_first(ld, goal, path::Tuple)::String
    ans = LK.query_answers(ld, goal)
    isempty(ans) && return "none"
    t = ans[1]
    for i in path
        t = child(t, i)
    end
    return _ps_text(t)
end

"The 34 answer lines of `_PS_PINS`, each from its own fresh engine (the first stream access of that engine)."
function _ps_kernel_rows(::Type{T})::Vector{String} where {T}
    rows = String[]
    sp = _pss(T, "\$stream_property")
    for a in _PS_ALIASES, (n, ar) in _PS_PROPS
        _, ld = _ps_engine(T)
        p = if ar == 0
            _pss(T, n)
        else
            mk_expr(T, T[_pss(T, n), mk_var(T, LK.fresh_var_keys!(1))])
        end
        goal = mk_expr(T, T[sp, _pss(T, a), p])
        push!(rows, _ps_first(ld, goal, (3,)))
    end
    for (cur, alias) in _PS_CURRENT
        _, ld = _ps_engine(T)
        s = mk_var(T, LK.fresh_var_keys!(1))
        s2 = mk_var(T, LK.fresh_var_keys!(1))
        conj = mk_expr(
            T,
            T[
                _pss(T, ","), mk_expr(T, T[_pss(T, cur), s]),
                mk_expr(T, T[_pss(T, "\$alias_stream"), _pss(T, alias), s2])
            ]
        )
        ans = LK.query_answers(ld, conj)
        # the answer binds both to stream blobs: the same blob (one handle) is `same`
        a = length(ans) == 1 ? child(ans[1], 2) : nothing
        b = length(ans) == 1 ? child(ans[1], 3) : nothing
        c1, c2 = a === nothing ? (nothing, nothing) : (child(a, 2), child(b, 3))
        push!(
            rows,
            if c1 !== nothing && is_blob(c1) && is_blob(c2) &&
                blob_handle(c1) == blob_handle(c2)
                "same"
            else
                "other"
            end
        )
    end
    return rows
end

# the swipl side: a driver of the same shape, one line per row
const _PS_DRIVER = raw"""
ps_rows :-
    forall(member(A, [user_input, user_output, user_error]),
      forall(member(N/Ar, [mode/1, alias/1, input/0, output/0, eof_action/1, buffer/1, type/1, representation_errors/1, newline/1, file_no/1]),
        ( functor(P, N, Ar),
          ( '$stream_property'(A, P) -> format("~q", [P]) ; write(none) ), nl ))),
    forall(member(G-B, [current_input(S)-user_input, current_output(S)-user_output, current_output(S)-user_error, current_input(S)-user_error]),
        ( call(G), '$alias_stream'(B, S2), ( S == S2 -> write(same) ; write(other) ), nl )).
"""
function _ps_swipl_rows(swipl::String)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(f, _PS_DRIVER)
        read(
            pipeline(`$swipl -q -f $f -g ps_rows -t halt`; stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

const _PS_SWIPL = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
const _PS_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

@testset "the pins are non-empty and have the rows' shape" begin
    @test length(_PS_PINS) == length(_PS_ALIASES) * length(_PS_PROPS) + length(_PS_CURRENT)
    @test count(==("none"), _PS_PINS) == 6                  # `output` of user_input, `input` of user_output and of user_error, the three file_no (known difference)
    @test all(i -> _PS_PINS[i] == "none", _PS_FILE_NO_ROWS)
    @test count(==("same"), _PS_PINS) == 2 && count(==("other"), _PS_PINS) == 2
end

@testset "a row per stream: user_input, user_output, user_error on an engine's first stream access (pl-file.c initIO)" begin
    ours = _ps_kernel_rows(_PS)
    @test length(ours) == length(_PS_PINS) && all(!isempty, ours)
    for (i, (o, p)) in enumerate(zip(ours, _PS_PINS))
        o == p || @info "row $i" ours = o pin = p
    end
    @test ours == _PS_PINS
    if _PS_SWIPL !== nothing
        theirs = _ps_swipl_rows(_PS_SWIPL)
        @test length(theirs) == length(_PS_PINS)
        @test tuple(theirs[collect(_PS_FILE_NO_ROWS)]...) == _PS_FILE_NO_SWIPL      # swipl's own answer for the known-difference rows
        keep = setdiff(eachindex(_PS_PINS), _PS_FILE_NO_ROWS)                # the live compare skips exactly the file_no rows
        @test theirs[keep] == _PS_PINS[keep]    # the pins are swipl's own
        @test ours[keep] == theirs[keep]
    elseif _PS_SWIPL_REQUIRED
        @test false
    else
        @info "the process streams rows: swipl's live answers not re-checked — `swipl` is not on PATH here."
    end
end

# pl-stream.c:4488-4490 STDIO_STREAMS: the flags of S__iob0's three streams (SIO_ISATTY only where Julia's stream is a terminal)
_ps_flags(::Type{T}, i::Int) where {T} =
    if i == LK.SNO_USER_INPUT
        LK.SIO_STDIO | LK.SIO_LBUF | LK.SIO_INPUT | LK.SIO_NOFEOF
    elseif i == LK.SNO_USER_OUTPUT
        LK.SIO_STDIO | LK.SIO_LBUF | LK.SIO_OUTPUT | LK.SIO_REPPLU
    else
        LK.SIO_STDIO | LK.SIO_NBUF | LK.SIO_OUTPUT | LK.SIO_REPPLU
    end

@testset "the engine's own three streams: flags, positions, current streams, table entries (pl-file.c initIO, pl-stream.c S__iob0)" begin
    gd0 = LK.PL_global_data{_PS}()
    live0 = count(!isnothing, gd0.stream_table)
    @test live0 == 0                                                   # the copy starts with no live stream
    ld = LK.PL_local_data{_PS}(gd0)
    @test ld.IO_initialised
    sin, sout, serr = LK.Suser_input(ld), LK.Suser_output(ld), LK.Suser_error(ld)
    @test sin isa LK.IOSTREAM && sout isa LK.IOSTREAM && serr isa LK.IOSTREAM
    @test sin !== sout && sout !== serr && sin !== serr
    for (i, s) in
        ((LK.SNO_USER_INPUT, sin), (LK.SNO_USER_OUTPUT, sout), (LK.SNO_USER_ERROR, serr))
        want = _ps_flags(_PS, i) & ~LK.SIO_ISATTY
        @test (s.flags & ~LK.SIO_ISATTY) == want
        @test s.magic == LK.SIO_MAGIC
    end
    # Sinput->position = &Sinput->posbuf, Soutput->position = &Sinput->posbuf, Serror->position = &Sinput->posbuf
    @test sin.position === sin.posbuf && sout.position === sin.posbuf &&
        serr.position === sin.posbuf
    # Scurin = Sinput, Scurout = Soutput, Sprotocol = NULL
    @test LK.Scurin(ld) === sin && LK.Scurout(ld) === sout &&
        ld.IO_streams[LK.SNO_PROTOCOL + 1] === nothing
    # getStreamContext(Sinput), (Soutput), (Serror): "add for enumeration"
    @test count(!isnothing, gd0.stream_table) == live0 + 3
    @test all(s -> gd0.stream_table[s.context] === s, (sin, sout, serr))
    # a second engine on the database has streams of its own, also in the table
    ld2 = LK.PL_local_data{_PS}(gd0)
    @test LK.Suser_input(ld2) !== nothing && LK.Suser_input(ld2) !== sin
    @test count(!isnothing, gd0.stream_table) == live0 + 6
    # the engine setupProlog makes for itself opens none: the booted template keeps an empty table
    bare = LK._bare_local_data(gd0)
    @test !bare.IO_initialised && all(isnothing, bare.IO_streams)
    @test count(!isnothing, gd0.stream_table) == live0 + 6
    @test count(!isnothing, LK.gd_template(_PS).stream_table) == 0
end

@testset "the autoloader on a database whose engine has done nothing: member/2 from library(lists) (S2a finding)" begin
    gd, ld = _ps_engine(_PS)
    @test LK.Scurin(ld) !== nothing                                    # not vacuous: what the autoloader's push stores
    f = joinpath(mktempdir(), "ps_autoload.pl")
    write(
        f,
        "r1(L) :- findall(X, member(X, [a,b,c]), L).\n" *
        ":- member(X, [q]), assertz(seen(X)).\n"
    )
    st, _ = LK.load_file!(gd, ld, f)
    @test st === :ok
    goal = mk_expr(_PS, _PS[_pss(_PS, "r1"), mk_var(_PS, LK.fresh_var_keys!(1))])
    ans = LK.query_answers(ld, goal)
    @test length(ans) == 1 && _ps_list(child(ans[1], 2)) == ["a", "b", "c"]
    seen = LK.query_answers(
        ld, mk_expr(_PS, _PS[_pss(_PS, "seen"), mk_var(_PS, LK.fresh_var_keys!(1))])
    )
    @test length(seen) == 1 && _ps_text(child(seen[1], 2)) == "q"
    @test isempty(ld.input_context_stack) && LK.Scurin(ld) === LK.Suser_input(ld)    # the autoloader popped what it pushed
end
