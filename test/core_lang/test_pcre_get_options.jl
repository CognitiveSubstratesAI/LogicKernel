# ORIGINAL: PCRE1 piece 6's gate - `re_get_arg_1_if_any` and `re_get_options` of packages/pcre/pcre4pl.c (packages-pcre a5e4c885, lines 724-860),
# src/pl-pcre.jl. NO oracle and no libpcre2: every expected value is read off the C text (the mode of each table row decides which flag group an
# option writes), each row names the branch it exercises. The option lists are read from text with PL_put_term_from_chars. Nothing here has run
# (written edit-only): BLIND RISKS the lane settles are the kernel's own error terms (PL_get_bool_ex's type_error(bool, X), PL_get_list_ex's
# type_error(list, Tail)) and the text of a 64-bit integer culprit. MEASURE on the oracle: the bare atom `start` (DIVERGES 11 of the file header).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _PG_LD = _rdb(Tuple{_R, Union{Nothing, _R}}[]).ld

function _pg_term(ld, text::String)::Int
    t = LK.PL_new_term_ref(ld)
    b = Vector{UInt8}(codeunits(text))
    LK.PL_put_term_from_chars(ld, t, LK.CVT_EXCEPTION | LK.REP_UTF8, b, length(b)) ||
        error("the text does not read: $text")
    return t
end

# The pending error(Formal, _) as (Formal's name, [its arguments]); clears it; nothing when none is pending.
function _pg_exc(ld)
    ex = LK.PL_exception(ld, 0)
    ex == 0 && return nothing
    f = LK.PL_new_term_ref(ld)
    a = LK.PL_new_term_ref(ld)
    r = nothing
    if LK._PL_get_arg(ld, 1, ex, f)
        na = LK.PL_get_name_arity(ld, f)
        if na !== nothing
            args = String[]
            for i in 1:na[2]
                LK._PL_get_arg(ld, i, f, a)
                txt = LK.PL_get_text(ld, a, LK.CVT_ATOMIC)
                if txt !== nothing
                    push!(args, LK.text_string(txt))
                else
                    nb = LK.PL_get_name_arity(ld, a)
                    push!(
                        args, nb === nothing ? "?" : string(LK.sym_text(nb[1]), "/", nb[2])
                    )
                end
            end
            r = (LK.sym_text(na[1]), args)
        end
    end
    LK.PL_clear_exception(ld)
    return r
end

const _PG_GROUPS = (
    :compile_options_flags, :capture_type, :optimise_flags, :jit_options_flags,
    :compile_ctx_flags,
    :compile_bsr_flags, :compile_newline_flags, :match_options_flags, :start_flags
)
_pg_state(re) = Tuple((getfield(re, g).seen, getfield(re, g).flags) for g in _PG_GROUPS)

# The state of a fresh `re_init_data()` with the groups in `over` (group name => (seen, flags)) replaced.
function _pg_expect(; over...)
    d = Dict{Symbol, Tuple{UInt32, UInt32}}(
        :compile_options_flags => (0, LK.PCRE2_UTF | LK.PCRE2_NO_UTF_CHECK),
        :capture_type => (0, LK.CAP_STRING),
        :optimise_flags => (0, 0), :jit_options_flags => (0, 0),
        :compile_ctx_flags => (0, 0),
        :compile_bsr_flags => (0, 0), :compile_newline_flags => (0, 0),
        :match_options_flags => (0, LK.PCRE2_NO_UTF_CHECK), :start_flags => (0, 0)
    )
    for (k, v) in over
        d[k] = v
    end
    return Tuple(d[g] for g in _PG_GROUPS)
end

# (the result of re_get_options on the list `text`, the state after, the error), the pending error cleared.
function _pg_run(text::String)
    ld = _PG_LD
    fid = LK.PL_open_foreign_frame(ld)
    re = LK.re_init_data()
    t = _pg_term(ld, text)
    ok = LK.re_get_options(ld, t, re)
    exc = _pg_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (ok, _pg_state(re), exc)
end

const _PG_UTFNC = LK.PCRE2_UTF | LK.PCRE2_NO_UTF_CHECK

@testset "re_get_options: the empty list and unknown options leave the defaults (the C ignores an unknown option)" begin
    @test _pg_run("[]") == (true, _pg_expect(), nothing)
    @test _pg_run("[foo(bar), baz, nope(1)]") == (true, _pg_expect(), nothing)
end

@testset "re_get_options: RE_COMP_BOOL options write compile_options_flags (set_flag, the seen mask, RE_NEG)" begin
    @test _pg_run("[caseless(true)]") ==
        (
        true,
        _pg_expect(
            compile_options_flags=(LK.PCRE2_CASELESS, _PG_UTFNC | LK.PCRE2_CASELESS)
        ),
        nothing
    )
    @test _pg_run("[caseless]") ==                                        # no argument: true
        (
        true,
        _pg_expect(
            compile_options_flags=(LK.PCRE2_CASELESS, _PG_UTFNC | LK.PCRE2_CASELESS)
        ),
        nothing
    )
    @test _pg_run("[caseless(false)]") ==                                 # the bit is cleared, seen is set
        (true, _pg_expect(compile_options_flags=(LK.PCRE2_CASELESS, _PG_UTFNC)), nothing)
    @test _pg_run("[utf(false)]") ==                                      # clears the default UTF bit
        (
        true,
        _pg_expect(compile_options_flags=(LK.PCRE2_UTF, LK.PCRE2_NO_UTF_CHECK)),
        nothing
    )
    @test _pg_run("[greedy(false)]") ==                                   # RE_NEG: false sets UNGREEDY
        (
        true,
        _pg_expect(
            compile_options_flags=(LK.PCRE2_UNGREEDY, _PG_UTFNC | LK.PCRE2_UNGREEDY)
        ),
        nothing
    )
    @test _pg_run("[greedy(true)]") ==
        (true, _pg_expect(compile_options_flags=(LK.PCRE2_UNGREEDY, _PG_UTFNC)), nothing)
    @test _pg_run("[caseless(true), caseless(false)]") ==                 # the first value wins
        (
        true,
        _pg_expect(
            compile_options_flags=(LK.PCRE2_CASELESS, _PG_UTFNC | LK.PCRE2_CASELESS)
        ),
        nothing
    )
    @test _pg_run("[caseless(true), dotall(true)]") ==
        (true,
        _pg_expect(
            compile_options_flags=(
                LK.PCRE2_CASELESS | LK.PCRE2_DOTALL,
                _PG_UTFNC | LK.PCRE2_CASELESS | LK.PCRE2_DOTALL)
        ), nothing)
end

@testset "re_get_options: the other flag groups (match, both, context, JIT, optimise)" begin
    # RE_COMP_BOOL | RE_MATCH_BOOL: both groups
    @test _pg_run("[anchored(true)]") == (
        true,
        _pg_expect(
            compile_options_flags=(LK.PCRE2_ANCHORED, _PG_UTFNC | LK.PCRE2_ANCHORED),
            match_options_flags=(
                LK.PCRE2_ANCHORED, LK.PCRE2_NO_UTF_CHECK | LK.PCRE2_ANCHORED
            )),
        nothing)
    # RE_MATCH_BOOL only; RE_NEG
    @test _pg_run("[partial_soft(true)]") ==
        (
        true,
        _pg_expect(
            match_options_flags=(
                LK.PCRE2_PARTIAL_SOFT, LK.PCRE2_NO_UTF_CHECK | LK.PCRE2_PARTIAL_SOFT
            )
        ),
        nothing
    )
    @test _pg_run("[bol(false)]") ==
        (
        true,
        _pg_expect(
            match_options_flags=(LK.PCRE2_NOTBOL, LK.PCRE2_NO_UTF_CHECK | LK.PCRE2_NOTBOL)
        ),
        nothing
    )
    # RE_COMPCTX_BOOL, RE_COMPJIT_BOOL
    @test _pg_run("[extra_match_word(true)]") ==
        (
        true,
        _pg_expect(
            compile_ctx_flags=(LK.PCRE2_EXTRA_MATCH_WORD, LK.PCRE2_EXTRA_MATCH_WORD)
        ),
        nothing
    )
    @test _pg_run("[jit_complete(true)]") ==
        (
        true,
        _pg_expect(jit_options_flags=(LK.PCRE2_JIT_COMPLETE, LK.PCRE2_JIT_COMPLETE)),
        nothing
    )
    # RE_COMP_OPTIMISE: the pair is RE_OPTIMISE / RE_OPTIMISE; optimise and optimize are two rows
    @test _pg_run("[optimise(true)]") ==
        (true, _pg_expect(optimise_flags=(LK.RE_OPTIMISE, LK.RE_OPTIMISE)), nothing)
    @test _pg_run("[optimize]") ==
        (true, _pg_expect(optimise_flags=(LK.RE_OPTIMISE, LK.RE_OPTIMISE)), nothing)
    @test _pg_run("[optimise(false)]") ==
        (true, _pg_expect(optimise_flags=(LK.RE_OPTIMISE, 0)), nothing)
end

@testset "re_get_options: the named options (bsr, newline, capture_type)" begin
    @test _pg_run("[bsr(unicode)]") == (true, _pg_expect(compile_bsr_flags=(3, 1)), nothing)
    @test _pg_run("[bsr2(anycrlf)]") ==
        (true, _pg_expect(compile_bsr_flags=(3, 2)), nothing)
    @test _pg_run("[newline(crlf)]") ==
        (true, _pg_expect(compile_newline_flags=(7, 3)), nothing)
    @test _pg_run("[newline2(nul)]") ==
        (true, _pg_expect(compile_newline_flags=(7, 6)), nothing)
    @test _pg_run("[capture_type(atom)]") ==
        (true, _pg_expect(capture_type=(7, LK.CAP_ATOM)), nothing)
    @test _pg_run("[capture_type(range)]") ==
        (true, _pg_expect(capture_type=(7, LK.CAP_RANGE)), nothing)
    # a second capture_type is ignored
    @test _pg_run("[capture_type(atom), capture_type(term)]") ==
        (true, _pg_expect(capture_type=(7, LK.CAP_ATOM)), nothing)
    # an unknown value is type_error(option, Option); the flags stay
    @test _pg_run("[capture_type(nope)]") ==
        (false, _pg_expect(), ("type_error", ["option", "capture_type/1"]))
    @test _pg_run("[bsr(1)]") == (false, _pg_expect(), ("type_error", ["atom", "1"]))
    # compat has no value in PCRE2
    @test _pg_run("[compat(javascript)]") ==
        (false, _pg_expect(), ("type_error", ["option", "compat/1"]))
end

@testset "re_get_options: start(N) (PL_get_uint64_ex, the 32-bit mask, first value wins)" begin
    @test _pg_run("[start(5)]") == (true, _pg_expect(start_flags=(1, 5)), nothing)
    @test _pg_run("[start(0)]") == (true, _pg_expect(start_flags=(1, 0)), nothing)
    @test _pg_run("[start(5), start(7)]") == (true, _pg_expect(start_flags=(1, 5)), nothing)
    @test _pg_run("[start(4294967295)]") ==
        (true, _pg_expect(start_flags=(1, 0xffffffff)), nothing)
    @test _pg_run("[start(4294967296)]") ==
        (false, _pg_expect(), ("domain_error", ["int32", "4294967296"]))
    @test _pg_run("[start(-1)]") ==
        (false, _pg_expect(), ("domain_error", ["not_less_than_zero", "-1"]))
    @test _pg_run("[start(a)]") == (false, _pg_expect(), ("type_error", ["integer", "a"]))
    @test _pg_run("[start(18446744073709551616)]") ==
        (false, _pg_expect(), ("representation_error", ["uint64_t"]))
    @test _pg_run("[start]") == (false, _pg_expect(), ("type_error", ["integer", "start"]))   # DIVERGES 11
end

@testset "re_get_options: malformed options and lists, and an error stops the scan" begin
    @test _pg_run("[1]") == (false, _pg_expect(), ("type_error", ["option", "1"]))
    @test _pg_run("[f(a,b)]") == (false, _pg_expect(), ("type_error", ["option", "f/2"]))
    @test _pg_run("[\"s\"]") == (false, _pg_expect(), ("type_error", ["option", "s"]))
    @test _pg_run("foo") == (false, _pg_expect(), ("type_error", ["list", "foo"]))
    @test _pg_run("[caseless(true)|b]") ==                                   # the first option is applied, then the tail is no list
        (
        false,
        _pg_expect(
            compile_options_flags=(LK.PCRE2_CASELESS, _PG_UTFNC | LK.PCRE2_CASELESS)
        ),
        ("type_error", ["list", "b"])
    )
    @test _pg_run("[caseless(maybe), ucp(true)]") ==
        (false, _pg_expect(), ("type_error", ["bool", "maybe"]))
end

@testset "re_get_arg_1_if_any (pcre4pl.c get_arg_1_if_any)" begin
    ld = _PG_LD
    fid = LK.PL_open_foreign_frame(ld)
    r = LK.re_get_arg_1_if_any(ld, _pg_term(ld, "caseless(true)"))
    @test r !== nothing && LK.sym_text(r[1]) == "caseless" && r[2] == 1 && r[3] != 0
    r = LK.re_get_arg_1_if_any(ld, _pg_term(ld, "caseless"))
    @test r !== nothing && LK.sym_text(r[1]) == "caseless" && r[2] == 0 && r[3] == 0
    @test LK.re_get_arg_1_if_any(ld, _pg_term(ld, "f(a,b)")) === nothing
    @test _pg_exc(ld) == ("type_error", ["option", "f/2"])
    @test LK.re_get_arg_1_if_any(ld, _pg_term(ld, "7")) === nothing
    @test _pg_exc(ld) == ("type_error", ["option", "7"])
    LK.PL_discard_foreign_frame(ld, fid)
end
