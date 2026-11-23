# CLASS: test
# ORIGINAL: PCRE1 piece 11 (C)'s gate - `re_get_subject`, `re_out_of_range`, `re_put_capname`, `re_put_capval`, `re_unify_match`, `re_error`, `re_copy_for_match`,
# `re_matchsub_` and `re_match_` of packages/pcre/pcre4pl.c (packages-pcre a5e4c885; src/pl-pcre.jl piece 11). The expected values are derived, none invented:
# from the C text (the list order, the unset-group rule, the `\K` guard, the branches of `re_error`, the start-option check), from Julia's `Regex` and
# `Base.PCRE` on the same library (the matched text and captures, the character offsets of a range capture, the text of a PCRE2 error), or from the PCRE2
# documentation alone (rows say "doc-only"). The unit rows hand-build the ovector, no engine call for the capture kinds that need none; the pipeline rows
# compile through `re_compile_impl` (the helper `_pc_compile` is copied from test_pcre_compile.jl: that file is not included). The `\K` guard is tested on a
# hand-built ovector with ovector[0] > ovector[1] ONLY: PCRE2 10.47 (the Julia library) rejects `\K` in a lookaround at compile time (DIVERGES 15), so no
# differential row can reach it. Nothing here has run (written edit-only): BLIND RISKS the lane settles are (1) the error read back for a subject that is not
# text is `type_error(string, _)` (the kernel's `PL_get_text` choice for these flags), (2) `PL_put_term_from_chars` reads "1.5" as a float and "f(x)" as a
# compound in the reference term type, (3) the doc-only rows (trailing unset group, unknown error number, PARTIAL_SOFT on a short subject), (4) `re_error`'s
# default branch text for -24 is `Base.PCRE.err_message(-24)`.
using Test, LogicKernel
const LK = LogicKernel
const PC = Base.PCRE

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _PC_LD = _rdb(Tuple{_R, Union{Nothing, _R}}[]).ld

# the term `text` reads as (a number, an atom, a list, ...)
function _pc_term(ld, text::String)::Int
    t = LK.PL_new_term_ref(ld)
    b = Vector{UInt8}(codeunits(text))
    LK.PL_put_term_from_chars(ld, t, LK.CVT_EXCEPTION | LK.REP_UTF8, b, length(b)) || error("the text does not read: $text")
    return t
end

# The pending error(Formal, _) as (Formal's name, [its atomic arguments]); clears it; nothing when none is pending.
function _pc_exc(ld)
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
                push!(args, txt === nothing ? "?" : LK.text_string(txt))
            end
            r = (LK.sym_text(na[1]), args)
        end
    end
    LK.PL_clear_exception(ld)
    return r
end

# The Julia value of a term: an atom is a Symbol, a string a String, `[]` is :nil, a list a Vector, other compounds (name, args...), a variable :var.
function _pc_val(ld, t::Int)
    LK.PL_is_variable(ld, t) && return :var
    LK.PL_get_nil(ld, t) && return :nil
    LK.PL_is_string(ld, t) && return LK.text_string(LK.PL_get_text(ld, t, LK.CVT_STRING))
    LK.PL_is_atom(ld, t) && return Symbol(LK.text_string(LK.PL_get_text(ld, t, LK.CVT_ATOM)))
    LK.PL_is_integer(ld, t) && return LK.PL_get_int64(ld, t)
    LK.PL_is_float(ld, t) && return LK.PL_get_float(ld, t)
    if LK.PL_is_pair(ld, t)
        out = Any[]
        h = LK.PL_new_term_ref(ld)
        tl = LK.PL_copy_term_ref(ld, t)
        while LK.PL_get_list(ld, tl, h, tl)
            push!(out, _pc_val(ld, h))
        end
        LK.PL_get_nil(ld, tl) || push!(out, :partial_tail)          # a list that does not end in [] (the re_unify_match nil-start row)
        return out
    end
    na = LK.PL_get_name_arity(ld, t)
    na === nothing && return :unknown
    args = Any[]
    a = LK.PL_new_term_ref(ld)
    for i in 1:na[2]
        LK._PL_get_arg(ld, i, t, a)
        push!(args, _pc_val(ld, a))
    end
    return (String(LK.sym_text(na[1])), args...)
end

_pc_bytes(s::String) = Vector{UInt8}(codeunits(s))

# a fresh term reference holding the STRING `s` (the kernel's own PL_unify_text, not the code under test)
function _pc_string_term(ld, s::String)::Int
    t = LK.PL_new_term_ref(ld)
    LK.PL_unify_text(ld, t, 0, LK.PL_chars_t(_pc_bytes(s), ncodeunits(s), LK.ENC_UTF8, false), LK.PL_STRING) || error("no string term")
    return t
end
_q(s::String) = "'" * s * "'"                         # the Prolog text of the atom `s` (no quote or backslash in `s`)
_ex(ps...) = Any[("-", n, v) for (n, v) in ps]       # the expected Name-Value list

# compile `pat` into a fresh re_data (after `setup(re)`): (ok, re, the pending error); the frame is discarded, the compiled code is NOT freed (the caller does)
function _pc_compile(pat::String; setup = re -> nothing)
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    re = LK.re_init_data(pat)
    setup(re)
    ok = LK.re_compile_impl(ld, re, _pc_bytes(pat))
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (ok, re, exc)
end

# A compiled regex for a pipeline row; the pattern must compile.
function _pc_re(pat::String; setup = re -> nothing)
    ok, re, exc = _pc_compile(pat; setup)
    ok || error("the pattern does not compile: $pat ($exc)")
    return re
end

# re_matchsub_ (fn = :matchsub, with a result) or re_match_ (fn = :match) of `re` on the subject term `subj` (Prolog text) and the option list text `opts`:
# (the foreign result, the Julia value of the result term or nothing, the pending error); the frame is discarded.
function _pc_run(re, subj::String; opts::String = "[]", fn::Symbol = :matchsub, str::Bool = false)
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    on = str ? _pc_string_term(ld, subj) : _pc_term(ld, subj)
    op = _pc_term(ld, opts)
    val = nothing
    if fn === :matchsub
        res = LK.PL_new_term_ref(ld)
        rc = LK.re_matchsub_(ld, re, on, res, op)
        rc == LK.FTRUE && (val = _pc_val(ld, res))
    else
        rc = LK.re_match_(ld, re, on, op)
    end
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (rc, val, exc)
end

# the character position and length of capture `k` (0: the whole match) of the Julia match `m` over `s`
function _pc_crange(s::String, m::RegexMatch, k::Int)
    off = k == 0 ? m.offset : m.offsets[k]
    str = k == 0 ? m.match : m.captures[k]
    return (length(s[1:prevind(s, off)]), length(str))
end

# The value re_put_capval puts for capture `i` of `ov` over `text` (the re_subject is fresh); the frame is discarded.
function _pc_capval(re, text::String, i::Int, ov::Vector{Csize_t})
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    try
        subj = LK.re_subject(_pc_bytes(text), ncodeunits(text), 0, 0)
        t = LK.PL_new_term_ref(ld)
        ok = LK.re_put_capval(ld, t, re, subj, i, ov)
        return ok ? _pc_val(ld, t) : :failed
    finally
        LK.PL_discard_foreign_frame(ld, fid)
    end
end

# The value re_put_capname puts for capture `i`.
function _pc_capname(re, i::Int)
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_ref(ld)
    ok = LK.re_put_capname(ld, t, re, i)
    v = ok ? _pc_val(ld, t) : :failed
    LK.PL_discard_foreign_frame(ld, fid)
    return v
end

# (the result of re_unify_match onto the term `target` (Prolog text, "" = a fresh variable), the value of the target, the pending error)
function _pc_unify(re, text::String, ovsize::Int, ov::Vector{Csize_t}; target::String = "")
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    subj = LK.re_subject(_pc_bytes(text), ncodeunits(text), 0, 0)
    t = isempty(target) ? LK.PL_new_term_ref(ld) : _pc_term(ld, target)
    ok = LK.re_unify_match(ld, t, re, subj, ovsize, ov)
    val = ok ? _pc_val(ld, t) : nothing
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (ok, val, exc)
end

# (the result of re_error(ec), the pending error)
function _pc_error(ec::Integer)
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    ok = LK.re_error(ld, ec)
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (ok, exc)
end

@testset "re_get_subject: an atom, a code list, and what is not text" begin
    ld = _PC_LD
    function gs(text; str = false)
        fid = LK.PL_open_foreign_frame(ld)
        subj = LK.re_subject(UInt8[1, 2], 2, 5, 7)           # init_subject must reset all four fields
        ok = LK.re_get_subject(ld, str ? _pc_string_term(ld, text) : _pc_term(ld, text), subj)
        exc = _pc_exc(ld)
        LK.PL_discard_foreign_frame(ld, fid)
        return (ok, subj, exc)
    end
    ok, subj, exc = gs(_q("abc"))
    @test ok && exc === nothing
    @test subj.subject == _pc_bytes("abc") && subj.length == 3 && subj.charp == 0 && subj.bytep == 0
    ok, subj, _ = gs(_q("héllo"))                           # UTF-8 bytes, the length in BYTES
    @test ok && subj.subject == _pc_bytes("héllo") && subj.length == ncodeunits("héllo") && subj.length == 6
    ok, subj, _ = gs(_q(""))
    @test ok && isempty(subj.subject) && subj.length == 0
    ok, subj, _ = gs("[104, 233, 0x1F600]")                 # a code list: h, é (2 bytes), one 4-byte code
    @test ok && subj.subject == _pc_bytes("hé\U1F600") && subj.length == 7
    ok, subj, exc = gs("héllo"; str = true)                  # a string
    @test ok && exc === nothing && subj.subject == _pc_bytes("héllo") && subj.length == 6
    ok, subj, exc = gs("f(x)")                              # CVT_EXCEPTION: not text
    @test !ok && exc !== nothing && exc[1] == "type_error" && exc[2][1] == "string"
    ok, subj, exc = gs("42")                                # no CVT_NUMBER
    @test !ok && exc == ("type_error", ["string", "42"])
    ok, subj, exc = gs("_")                                 # unbound
    @test !ok && exc !== nothing
end

@testset "re_out_of_range: domain_error(offset, Index)" begin
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    @test !LK.re_out_of_range(ld, 7)
    @test _pc_exc(ld) == ("domain_error", ["offset", "7"])
    LK.PL_discard_foreign_frame(ld, fid)
end

@testset "re_put_capname: the name's atom, the number for an unnamed or no name table" begin
    re = LK.re_init_data("")
    @test _pc_capname(re, 0) == 0 && _pc_capname(re, 3) == 3                       # no table: the integer
    re.capture_names = [LK.re_cap_how(nothing, LK.CAP_DEFAULT), LK.re_cap_how("n", LK.CAP_DEFAULT), LK.re_cap_how("é", LK.CAP_INTEGER)]
    @test _pc_capname(re, 0) == 0                                                  # an unnamed entry: its number
    @test _pc_capname(re, 1) === :n
    @test _pc_capname(re, 2) === Symbol("é")
end

@testset "re_put_capval: kinds over a hand ovector" begin
    # "xéy": x at byte 0, é at bytes 1-2, y at byte 3; groups: 0 = all, 1 = é, 2 = y
    s = "xéy"
    ov = Csize_t[0, 4, 1, 3, 3, 4]
    re = LK.re_init_data("")                                                      # capture_type: string
    @test _pc_capval(re, s, 0, ov) == "xéy" && _pc_capval(re, s, 1, ov) == "é" && _pc_capval(re, s, 2, ov) == "y"
    re.capture_type.flags = UInt32(LK.CAP_ATOM)
    @test _pc_capval(re, s, 1, ov) === Symbol("é") && _pc_capval(re, s, 2, ov) === :y
    re.capture_type.flags = UInt32(LK.CAP_RANGE)                                   # (character start) - (character length)
    @test _pc_capval(re, s, 0, ov) == ("-", 0, 3) && _pc_capval(re, s, 1, ov) == ("-", 1, 1) && _pc_capval(re, s, 2, ov) == ("-", 2, 1)
    # a name table's type wins over the regex's capture type, unless it is the default
    re.capture_type.flags = UInt32(LK.CAP_STRING)
    re.capture_names = [LK.re_cap_how(nothing, LK.CAP_DEFAULT), LK.re_cap_how("g", LK.CAP_ATOM), LK.re_cap_how("h", LK.CAP_RANGE)]
    @test _pc_capval(re, s, 0, ov) == "xéy"
    @test _pc_capval(re, s, 1, ov) === Symbol("é")
    @test _pc_capval(re, s, 2, ov) == ("-", 2, 1)
    # a group that did not participate is the empty text at the start of the match (cstart is UNSET; cend is not read)
    re = LK.re_init_data("")
    unset = Csize_t[1, 3, LK.PCRE2_UNSET, LK.PCRE2_UNSET]
    @test _pc_capval(re, s, 1, unset) == ""
    re.capture_type.flags = UInt32(LK.CAP_ATOM)
    @test _pc_capval(re, s, 1, unset) === Symbol("")
    re.capture_type.flags = UInt32(LK.CAP_RANGE)
    @test _pc_capval(re, s, 1, unset) == ("-", 1, 0)
    # the term kinds read the text as Prolog text (a number by the C's own rule)
    t = "42 1.5 f(x)"
    ovt = Csize_t[0, 11, 0, 2, 3, 6, 7, 11]
    for (ty, i, expect) in (
            (LK.CAP_INTEGER, 1, parse(Int, "42")), (LK.CAP_NUMBER, 1, parse(Int, "42")), (LK.CAP_FLOAT, 2, parse(Float64, "1.5")),
            (LK.CAP_TERM, 3, ("f", :x)), (LK.CAP_TERM, 1, parse(Int, "42")),
        )
        re = LK.re_init_data("")
        re.capture_type.flags = UInt32(ty)
        @test _pc_capval(re, t, i, ovt) == expect
    end
    re = LK.re_init_data("")                                                      # UTF-8 text is read as UTF-8 (an atom, not a variable `Ã©`)
    re.capture_type.flags = UInt32(LK.CAP_TERM)
    @test _pc_capval(re, "é", 0, Csize_t[0, 2]) === Symbol("é")
    @test _pc_capval(re, "f(", 0, Csize_t[0, 2]) === :failed                        # text that does not read: the put fails, no error is raised
    # an unknown capture type (here: the default, 0, with no name table) is an error: the C's assert(0), `error` here (DIVERGES 27)
    re = LK.re_init_data("")
    re.capture_type.flags = UInt32(LK.CAP_DEFAULT)
    @test_throws ErrorException _pc_capval(re, s, 1, ov)
end

@testset "re_unify_match: the Name-Value list, in group order" begin
    re = LK.re_init_data("")
    re.capture_names = [LK.re_cap_how(nothing, LK.CAP_DEFAULT), LK.re_cap_how("a", LK.CAP_DEFAULT)]
    ok, val, exc = _pc_unify(re, "abc", 2, Csize_t[0, 3, 1, 2])
    @test ok && exc === nothing
    @test val == _ex((0, "abc"), (:a, "b"))
    ok, val, _ = _pc_unify(re, "abc", 1, Csize_t[1, 3, 1, 2])                      # only ovsize pairs are read
    @test ok && val == _ex((0, "bc"))
    # the target is unified, not overwritten
    ok, val, exc = _pc_unify(re, "abc", 1, Csize_t[0, 3]; target = "foo")
    @test !ok && exc === nothing
    # an empty match at the end of the subject (start == end): the guard is a strict `>`
    ok, val, exc = _pc_unify(re, "abc", 1, Csize_t[3, 3])
    @test ok && exc === nothing && val == _ex((0, ""))
    ok, val, exc = _pc_unify(re, "abc", 1, Csize_t[2, 3])
    @test ok && val == _ex((0, "c"))
    # a capture whose value cannot be put fails the whole unification, no error
    re2 = LK.re_init_data("")
    re2.capture_type.flags = UInt32(LK.CAP_TERM)
    ok, val, exc = _pc_unify(re2, "f(", 1, Csize_t[0, 2])
    @test !ok && val === nothing && exc === nothing
    # the \K guard (C 1625-1633): a start after the end is a representation error (hand-built ovector; DIVERGES 15: 10.47 never produces one)
    ok, val, exc = _pc_unify(re, "abc", 2, Csize_t[2, 1, 0, 3])
    @test !ok && val === nothing
    @test exc == ("representation_error", ["\\K used assertion to set the match start after its end"])
    ok, _, exc = _pc_unify(re, "abc", 1, Csize_t[3, 0])
    @test !ok && exc !== nothing && exc[1] == "representation_error"
end

@testset "re_error: every branch" begin
    # no match and partial: false without an error
    @test _pc_error(LK.PCRE2_ERROR_NOMATCH) == (false, nothing)
    @test _pc_error(LK.PCRE2_ERROR_PARTIAL) == (false, nothing)
    for (ec, what) in (
            (LK.PCRE2_ERROR_NOMEMORY, "memory"), (LK.PCRE2_ERROR_MATCHLIMIT, "match_limit"), (LK.PCRE2_ERROR_DEPTHLIMIT, "depth_limit"),
            (LK.PCRE2_ERROR_HEAPLIMIT, "heap_limit"), (LK.PCRE2_ERROR_JIT_STACKLIMIT, "jit_stack"),
        )
        @test _pc_error(ec) == (false, ("resource_error", [what]))
    end
    @test _pc_error(LK.PCRE2_ERROR_BADOFFSET) == (false, ("representation_error", ["regex-offset"]))
    # the UTF-8 error range -3 .. -23 is representation_error(utf8), both ends and the middle; -24 is outside it
    for ec in (LK.PCRE2_ERROR_UTF8_ERR1, Cint(-10), LK.PCRE2_ERROR_UTF8_ERR21)
        @test _pc_error(ec) == (false, ("representation_error", ["utf8"]))
    end
    # NULL, BADOPTION, BADMAGIC and the default: the library's own text of the code (Base.PCRE on the same library)
    for ec in (LK.PCRE2_ERROR_NULL, LK.PCRE2_ERROR_BADOPTION, LK.PCRE2_ERROR_BADMAGIC, Cint(-24))
        @test _pc_error(ec) == (false, ("representation_error", [PC.err_message(ec)]))
    end
    # doc-only (pcre2api: an unknown error number makes pcre2_get_error_message fail): the text is "regex"
    @test _pc_error(Cint(-1000)) == (false, ("representation_error", ["regex"]))
end

@testset "re_copy_for_match: own flag pairs, match flags reset, the rest shared" begin
    re = _pc_re("(?<n>a)")
    re.match_options_flags.seen = UInt32(1)
    re.match_options_flags.flags = UInt32(0x55)
    re.start_flags.seen = UInt32(1)
    re.start_flags.flags = UInt32(4)
    re.compile_options_flags.flags |= LK.PCRE2_CASELESS
    for (k, g) in enumerate((:compile_options_flags, :capture_type, :optimise_flags, :jit_options_flags, :compile_ctx_flags, :compile_bsr_flags, :compile_newline_flags))
        getfield(re, g).seen |= UInt32(k)                      # distinct, nonzero seen and flags in every non-match group
        getfield(re, g).flags |= UInt32(0x100 * k)
    end
    c = LK.re_copy_for_match(re)
    for g in (:compile_options_flags, :capture_type, :optimise_flags, :jit_options_flags, :compile_ctx_flags, :compile_bsr_flags, :compile_newline_flags)
        @test (getfield(c, g).seen, getfield(c, g).flags) == (getfield(re, g).seen, getfield(re, g).flags) && getfield(c, g) !== getfield(re, g)
    end
    @test c.match_options_flags.seen == 0 && c.match_options_flags.flags == LK.PCRE2_NO_UTF_CHECK
    @test c.start_flags.seen == 0 && c.start_flags.flags == 0
    @test c.compile_options_flags !== re.compile_options_flags && c.match_options_flags !== re.match_options_flags && c.start_flags !== re.start_flags
    @test c.pattern == re.pattern && c.serial == re.serial && c.capture_size == re.capture_size && c.code == re.code && c.code != C_NULL
    @test c.capture_names === re.capture_names
    c.compile_options_flags.flags = UInt32(0)                                      # the copy is its own
    @test re.compile_options_flags.flags & LK.PCRE2_CASELESS != 0
    @test re.match_options_flags.flags == 0x55 && re.start_flags.flags == 4          # the source is not reset
    LK.re_free(re)
end

@testset "re_matchsub_: captures as Name-Value pairs, against Julia's Regex" begin
    s = "2023-Nov"
    re = _pc_re("(\\d+)-(\\w+)")
    m = match(r"(\d+)-(\w+)", s)
    rc, val, exc = _pc_run(re, _q(s))
    @test rc == LK.FTRUE && exc === nothing
    @test val == _ex((0, m.match), (1, m.captures[1]), (2, m.captures[2]))
    LK.re_free(re)

    # typed named captures: y_I integer, m_A atom; the whole match (no name) is the regex's capture type (string)
    re = _pc_re("(?<y_I>\\d+)-(?<m_A>\\w+)")
    m = match(r"(?<y>\d+)-(?<m>\w+)", s)
    rc, val, _ = _pc_run(re, _q(s))
    @test rc == LK.FTRUE && val == _ex((0, m.match), (:y, parse(Int, m[:y])), (:m, Symbol(m[:m])))
    LK.re_free(re)

    # all seven type letters
    subj = "12 1.5 7 f(x) zz q w"
    re = _pc_re("(?<i_I>\\d+) (?<f_F>[\\d.]+) (?<n_N>\\d+) (?<t_T>f\\(x\\)) (?<r_R>z+) (?<s_S>q) (?<a_A>w)")
    m = match(r"(?<i>\d+) (?<f>[\d.]+) (?<n>\d+) (?<t>f\(x\)) (?<r>z+) (?<s>q) (?<a>w)", subj)
    rc, val, _ = _pc_run(re, _q(subj))
    zz = findfirst("zz", subj)
    @test rc == LK.FTRUE
    @test val == _ex(
        (0, subj), (:i, parse(Int, m[:i])), (:f, parse(Float64, m[:f])), (:n, parse(Int, m[:n])), (:t, ("f", :x)),
        (:r, ("-", first(zz) - 1, length(zz))), (:s, m[:s]), (:a, Symbol(m[:a]))
    )
    LK.re_free(re)
end

@testset "re_matchsub_: a group that did not take part, and a trailing one" begin
    re = _pc_re("(a)|(b)")
    m = match(r"(a)|(b)", "xb")
    @test m.captures[1] === nothing && m.captures[2] == "b"
    rc, val, _ = _pc_run(re, _q("xb"))                       # group 1 is unset: the empty text at the match start
    @test rc == LK.FTRUE && val == _ex((0, m.match), (1, ""), (2, m.captures[2]))
    LK.re_free(re)
    # doc-only (pcre2api: the match count is one more than the highest SET group): a trailing unset group is not in the list
    re = _pc_re("(a)|b")
    rc, val, _ = _pc_run(re, _q("b"))
    @test rc == LK.FTRUE && val == _ex((0, "b"))
    LK.re_free(re)
end

@testset "re_matchsub_: capture ranges count characters, in descending group order with the cached position" begin
    s = "aébbbc"
    re = _pc_re("(é)(b+)"; setup = re -> (re.capture_type.flags = UInt32(LK.CAP_RANGE)))
    m = match(r"(é)(b+)", s)
    rc, val, _ = _pc_run(re, _q(s))
    @test rc == LK.FTRUE
    @test val == _ex(((0, ("-", _pc_crange(s, m, 0)...))), (1, ("-", _pc_crange(s, m, 1)...)), (2, ("-", _pc_crange(s, m, 2)...)))
    @test _pc_crange(s, m, 2) == (2, 3)
    LK.re_free(re)
end

@testset "re_matchsub_: the options reach the copy and the source regex is untouched" begin
    s = "2023-Nov"
    re = _pc_re("(\\d+)-(\\w+)")
    rc, val, _ = _pc_run(re, _q(s); opts = "[capture_type(atom)]")
    @test rc == LK.FTRUE && val == _ex((0, Symbol("2023-Nov")), (1, Symbol("2023")), (2, :Nov))
    @test re.capture_type.flags == LK.CAP_STRING               # the copy took the option
    rc, val, _ = _pc_run(re, _q("12-34"); opts = "[capture_type(term)]")
    @test rc == LK.FTRUE && val == _ex((0, ("-", 12, 34)), (1, 12), (2, 34))
    # the start option is in characters; the copy's start is reset first, so a stale source value does not count
    re.start_flags.flags = UInt32(99)
    rc, val, exc = _pc_run(re, _q(s))
    @test rc == LK.FTRUE && exc === nothing && val[1] == ("-", 0, s)
    @test re.start_flags.flags == 99 && re.start_flags.seen == 0
    LK.re_free(re)
end

@testset "re_matchsub_: the start option, in characters" begin
    re = _pc_re("b")
    rc, val, exc = _pc_run(re, _q("éb"); opts = "[start(1)]")
    @test rc == LK.FTRUE && val == _ex((0, "b")) && exc === nothing
    rc, val, exc = _pc_run(re, _q("éb"); opts = "[start(2)]")                    # at the end: allowed, no match
    @test rc == LK.FFALSE && exc === nothing
    rc, val, exc = _pc_run(re, _q("éb"); opts = "[start(3)]")                    # past the end: out_of_range
    @test rc == LK.FFALSE && exc == ("domain_error", ["offset", "3"])
    LK.re_free(re)
    re = _pc_re("^b")                                                            # Julia: ^ does not match at a non-zero start
    @test match(r"^b", "ab", 2) === nothing
    rc, _, exc = _pc_run(re, _q("ab"); opts = "[start(1)]")
    @test rc == LK.FFALSE && exc === nothing
    rc, _, _ = _pc_run(re, _q("b"))
    @test rc == LK.FTRUE
    LK.re_free(re)
end

@testset "re_match_: no result term, options, and a failed match" begin
    re = _pc_re("a.c")
    rc, val, exc = _pc_run(re, _q("xabcx"); fn = :match)
    @test rc == LK.FTRUE && val === nothing && exc === nothing
    @test occursin(r"a.c", "xabcx")
    rc, _, exc = _pc_run(re, _q("xAbCx"); fn = :match)
    @test rc == LK.FFALSE && exc === nothing                                     # no match: false, no error
    rc, _, _ = _pc_run(_pc_re("a.c"; setup = re -> (re.compile_options_flags.flags |= LK.PCRE2_CASELESS)), _q("xAbCx"); fn = :match)
    @test rc == LK.FTRUE
    rc, _, _ = _pc_run(re, _q("abcd"); opts = "[anchored(true)]", fn = :match)
    @test rc == LK.FTRUE
    rc, _, _ = _pc_run(re, _q("zabc"); opts = "[anchored(true)]", fn = :match)
    @test rc == LK.FFALSE
    LK.re_free(re)
    # doc-only (pcre2api): a partial match is reported as PCRE2_ERROR_PARTIAL, which re_error maps to false
    re = _pc_re("abc")
    rc, _, exc = _pc_run(re, _q("ab"); opts = "[partial_soft(true)]", fn = :match)
    @test rc == LK.FFALSE && exc === nothing
    LK.re_free(re)
end

@testset "re_matchsub_: a code-list subject, and errors in the subject or the options" begin
    re = _pc_re("é")
    rc, val, _ = _pc_run(re, "[104, 233, 106]")                                   # "héj" as codes
    @test rc == LK.FTRUE && val == _ex((0, "é"))
    rc, val, exc = _pc_run(re, "f(x)")
    @test rc == LK.FFALSE && exc !== nothing && exc[1] == "type_error"
    rc, val, exc = _pc_run(re, _q("é"); opts = "foo")                             # the options are read after the subject
    @test rc == LK.FFALSE && exc !== nothing && exc[1] == "type_error"
    rc, val, exc = _pc_run(re, "f(x)"; opts = "foo")                              # both bad: the subject's error comes first
    @test rc == LK.FFALSE && exc !== nothing && exc[2][1] == "string"
    LK.re_free(re)
    # a failed subject or option read stops the match: the pattern `x*` would match the empty subject
    rex = _pc_re("x*")
    rc, _, exc = _pc_run(rex, "f(x)")
    @test rc == LK.FFALSE && exc !== nothing
    rc, _, exc = _pc_run(rex, _q("a"); opts = "foo")
    @test rc == LK.FFALSE && exc !== nothing
    rc, val, _ = _pc_run(rex, _q("a"))                                            # control: it does match
    @test rc == LK.FTRUE && val == _ex((0, ""))
    LK.re_free(rex)
    # a STRING subject
    re = _pc_re("é+")
    rc, val, _ = _pc_run(re, "aééb"; str = true)
    @test rc == LK.FTRUE && val == _ex((0, "éé"))
    LK.re_free(re)
end

@testset "re_matchsub_: the start offset is where the search begins; a match error is raised" begin
    re = _pc_re("a")
    rc, _, exc = _pc_run(re, _q("ab"); opts = "[start(1)]")                       # `a` is only at character 0
    @test rc == LK.FFALSE && exc === nothing
    rc, _, _ = _pc_run(re, _q("ab"); opts = "[start(0)]")
    @test rc == LK.FTRUE
    LK.re_free(re)
    # the library's default match limit is hit by nested quantifiers with no way to match (blind: relies on the default limit, no JIT here)
    re = _pc_re(string("^(a+)+", '$'))
    rc, _, exc = _pc_run(re, _q("a"^30 * "b"); fn = :match)
    @test rc == LK.FFALSE && exc == ("resource_error", ["match_limit"])
    LK.re_free(re)
end
