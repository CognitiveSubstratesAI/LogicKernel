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
#   * The descriptor fallback: with Julia's stdin an IO the stream layer does not hold (`devnull`), user_input is file descriptor 0 (pl-stream.c STDIO(n, f)).
#   * The finding (S2a, status_board.md, LB7's first run): on a database that is not initialised, the autoloader's `push_input_context` stored
#     `Scurin(ld) === nothing` and `$input_context/1` died on `c.stream::IOSTREAM` (a Julia TypeError). A program consulted there calls member/2 (autoloaded
#     from library(lists)); it now answers as swipl does.
using Test, LogicKernel
const LK = LogicKernel

# FILENO1 (audit D-0436 item 4): the three standard streams answer file_no(0), file_no(1), file_no(2) as swipl does (pl-file.c:4996-5005, Sfileno of
# the S__iob entries): rows 10, 20, 30 of the first table are swipl's answers now (they were pinned `none`, the landed DIVERGES), and a second table (a Prolog
# program of twelve rows, `_PS_FN_PROGRAM`) asks file_no through stream_property/2, current_input/current_output, an enumeration, set_stream(buffer),
# and a standard stream moved between the user_output/user_error aliases. KNOWN DIFFERENCE (rows fn10, fn11, fn12): a stream from open/3 has a descriptor
# in swipl (fn10, fn12 `has`, fn11 an integer >= 3, 10.1.19) and none here: the pins are OURS, the live compare checks swipl's shape instead.
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
# Rows 10, 20, 30 (file_no): file_no(0), file_no(1), file_no(2), the S__iob descriptors (pl-file.c:4996-5005); FILENO1 flipped them from `none`.
const _PS_PINS = String[
    "mode(read)", "alias(user_input)", "input", "none", "eof_action(reset)", "buffer(line)",
    "type(text)", "representation_errors(error)", "newline(posix)", "file_no(0)",
    "mode(write)", "alias(user_output)", "none", "output", "eof_action(eof_code)",
    "buffer(line)",
    "type(text)", "representation_errors(unicode)", "newline(posix)", "file_no(1)",
    "mode(write)", "alias(user_error)", "none", "output", "eof_action(eof_code)",
    "buffer(false)",
    "type(text)", "representation_errors(unicode)", "newline(posix)", "file_no(2)",
    "same", "same", "other", "other"
]

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
    @test count(==("none"), _PS_PINS) == 3                  # `output` of user_input, `input` of user_output and of user_error; the file_no rows answer (FILENO1)
    @test _PS_PINS[[10, 20, 30]] == ["file_no(0)", "file_no(1)", "file_no(2)"]
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
        @test theirs == _PS_PINS                # the pins are swipl's own, every row
        @test ours == theirs
    elseif _PS_SWIPL_REQUIRED
        @test false
    else
        @info "the process streams rows: swipl's live answers not re-checked — `swipl` is not on PATH here."
    end
end

# The second table: file_no and the standard streams, a Prolog program run on ONE engine (the rows restore what they change) and in swipl.
# `{D}` is a scratch directory. Pins: swipl 10.1.19-1-gcbf4e189 (the live compare below re-checks them), except fn10-fn12 (see the head: OURS pinned).
const _PS_FN_PROGRAM = raw"""
fn01(R) :- stream_property(user_input, file_no(R)).
fn02(R) :- stream_property(user_output, file_no(R)).
fn03(R) :- stream_property(user_error, file_no(R)).
fn04(R) :- current_input(S), stream_property(S, file_no(R)).
fn05(R) :- current_output(S), stream_property(S, file_no(R)).
fn06(A) :- stream_property(S, file_no(2)), stream_property(S, alias(A)).
fn07(R) :- set_stream(user_error, buffer(line)), stream_property(user_error, file_no(R0)), set_stream(user_error, buffer(false)), R = R0.
fn08(R) :- stream_property(O, alias(user_output)), stream_property(E, alias(user_error)), set_stream(E, alias(user_output)), stream_property(user_output, file_no(R0)), set_stream(O, alias(user_output)), set_stream(E, alias(user_error)), R = R0.
fn09(R) :- stream_property(O, alias(user_output)), stream_property(E, alias(user_error)), set_stream(O, alias(user_error)), stream_property(user_error, file_no(R0)), set_stream(E, alias(user_error)), set_stream(O, alias(user_output)), R = R0.
fn10(R) :- open('{D}/f10', write, S), ( stream_property(S, file_no(_)) -> R = has ; R = none ), close(S).
fn11(R) :- open('{D}/f11', write, S), set_stream(S, alias(user_output)), ( stream_property(user_output, file_no(R0)) -> true ; R0 = none ), close(S), R = R0.
fn12(R) :- open('{D}/f10', read, S), ( stream_property(S, file_no(_)) -> R = has ; R = none ), close(S).
"""
const _PS_FN_IDS = [
    "fn01",
    "fn02",
    "fn03",
    "fn04",
    "fn05",
    "fn06",
    "fn07",
    "fn08",
    "fn09",
    "fn10",
    "fn11",
    "fn12"
]
const _PS_FN_PINS = [
    "fn01 0", "fn02 1", "fn03 2", "fn04 0", "fn05 1", "fn06 user_error", "fn07 2",
    "fn08 2",     # user_output moved onto Serror: still descriptor 2
    "fn09 1",     # user_error moved onto Soutput: still descriptor 1
    "fn10 none",  # swipl: has
    "fn11 none",  # swipl: 3 (the descriptor of the file)
    "fn12 none"   # swipl: has (an input file stream is no standard input)
]
const _PS_FN_KNOWN = (10, 11, 12)    # the rows that pin OUR answer

"The kernel's line of each row of `_PS_FN_PROGRAM`: `fnNN answer` (`fnNN none` for a failure, `fnNN EXC`)."
function _ps_fn_kernel_lines(dir::String, ::Type{T})::Vector{String} where {T}
    f = joinpath(dir, "fn.pl")
    write(f, replace(_PS_FN_PROGRAM, "{D}" => dir))
    gd, ld = _ps_engine(T)
    st, _ = LK.load_file!(gd, ld, f)
    @assert st === :ok
    out = String[]
    for id in _PS_FN_IDS
        goal = mk_expr(T, T[_pss(T, id), mk_var(T, LK.fresh_var_keys!(1))])
        ans = try
            LK.query_answers(ld, goal)
        catch
            nothing
        end
        push!(
            out, if ans === nothing
                "$id EXC"
            elseif isempty(ans)
                "$id none"
            else
                "$id " * _ps_text(child(ans[1], 2))
            end
        )
    end
    return out
end

"The swipl side: the same program consulted, one line per row; a row's answer `~q`."
function _ps_fn_swipl_lines(swipl::String, dir::String)::Vector{String}
    f = joinpath(dir, "fn_swipl.pl")
    write(
        f,
        replace(_PS_FN_PROGRAM, "{D}" => dir) * """
fn_rows :-
    forall(member(N, [$(join(_PS_FN_IDS, ","))]),
      ( G =.. [N, R], ( catch(G, _, R = exc) -> true ; R = none ), format("~w ~q~n", [N, R]) )).
"""
    )
    out = read(
        pipeline(`$swipl -q -f $f -g fn_rows -t halt`; stdin=devnull, stderr=devnull),
        String
    )
    return String.(split(chomp(out), '\n'; keepempty=false))
end

@testset "file_no of the standard streams, FILENO1 (pl-file.c:4996-5005): stream_property/2, current streams, moved aliases; a file stream has none here" begin
    mktempdir() do dir
        ours = _ps_fn_kernel_lines(dir, _PS)
        for (o, p) in zip(ours, _PS_FN_PINS)
            o == p || @info "fn row" ours = o pin = p
        end
        @test ours == _PS_FN_PINS
        @test length(_PS_FN_PINS) == length(_PS_FN_IDS) && all(!isempty, ours)
        # not vacuous: the three descriptors are answered and told apart, and the known-difference rows are the only `none`
        @test Set(_PS_FN_PINS[1:3]) == Set(["fn01 0", "fn02 1", "fn03 2"])
        @test count(endswith(" none"), _PS_FN_PINS) == length(_PS_FN_KNOWN)
        if _PS_SWIPL !== nothing
            theirs = _ps_fn_swipl_lines(_PS_SWIPL, dir)
            @test length(theirs) == length(_PS_FN_PINS)
            keep = setdiff(eachindex(_PS_FN_PINS), collect(_PS_FN_KNOWN))
            @test theirs[keep] == _PS_FN_PINS[keep]
            @test ours[keep] == theirs[keep]
            # the known-difference rows: swipl has a descriptor for an open/3 stream, a number >= 3; here there is none
            @test theirs[10] == "fn10 has"
            @test occursin(r"^fn11 \d+$", theirs[11]) && parse(Int, theirs[11][6:end]) >= 3
            @test theirs[12] == "fn12 has"
        elseif _PS_SWIPL_REQUIRED
            @test false
        end
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

# pl-stream.c:4479-4492 STDIO(n, f): `.handle = (void *)(n)`: upstream's standard stream n is file descriptor n. When Julia's stdin is an IO
# the stream layer does not hold (a runner's wrapper: `devnull`), initIO reads file descriptor 0, and `_std_io` gives stdout 1 and stderr 2
# (fdio names its stream "<fd n>"). Kills PSTREAM-5 (user_input over descriptor 1), which every run with a real stdin cannot see.
@testset "initIO over a Julia stdin the stream layer does not hold: user_input is file descriptor 0; _std_io(…, 1/2) are descriptors 1 and 2" begin
    saved = Base.stdin
    local sin
    try
        Core.eval(Base, :(stdin = devnull))
        @test Base.stdin isa Base.DevNull                              # not vacuous: the fallback is the path taken
        sin = LK.Suser_input(LK.PL_local_data{_PS}(LK.PL_global_data{_PS}()))
    finally
        Core.eval(Base, :(stdin = $saved))
    end
    @test sin.handle.io.name == "<fd 0>"
    @test LK._std_io(devnull, 1).name == "<fd 1>" && LK._std_io(devnull, 2).name == "<fd 2>"
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
