# CLASS: test
# ORIGINAL: PCRE1 piece 12 (D)'s gate - `re_foldl_`, `re_portray_` and `re_portray_match_options_` of packages/pcre/pcre4pl.c (packages-pcre a5e4c885;
# src/pl-pcre.jl piece 12). The expected values are derived, none invented: the fold counts and positions from Julia's `eachmatch` on the same library
# (an empty match is reported at every character and at the end, as the C's advance loop does), the portray texts from the C format strings
# (`<regex>(/%Ws/ [`, `%s%s] $capture=%d`, ` $optimise`, ` {N i:name:TYPE ...}`, `%s$start=%lu`) with the option text taken from `re_write_re_options`
# (already pinned by test_pcre_config.jl), or from the PCRE2 documentation (rows say "doc-only"). The folder is a Prolog predicate `pcre:re_call_folder/4`
# defined on the test database with one clause per closure atom (pcre.pl's own clause builds a dict, which is not the subject here). Helpers `_pc_*` are
# copied from test_pcre_match.jl (that file is not included). Nothing here has run (written edit-only): BLIND RISKS the lane settles are (1) a clause
# compiled with `compileClause` into the module `pcre` of the test database calls `is/2`, `throw/1` and `fail` through its super module chain, (2) the
# exception a nested `PL_call_predicate` raised is still pending at the return (PL_Q_PASS_EXCEPTION), (3) the stream term of a memory stream resolves in
# `term_stream_handle`, (4) the match_limit row (`^(a+)+$` on 30 a's + b with no JIT), (5) capture 0's type is CAP_DEFAULT in the printed `{...}` table.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

const _PF_DB = _rdb(Tuple{_R, Union{Nothing, _R}}[])
const _PC_LD = _PF_DB.ld

# the term `text` reads as (a number, an atom, a list, ...)
function _pc_term(ld, text::String)::Int
    t = LK.PL_new_term_ref(ld)
    b = Vector{UInt8}(codeunits(text))
    LK.PL_put_term_from_chars(ld, t, LK.CVT_EXCEPTION | LK.REP_UTF8, b, length(b)) ||
        error("the text does not read: $text")
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
    LK.PL_is_atom(ld, t) &&
        return Symbol(LK.text_string(LK.PL_get_text(ld, t, LK.CVT_ATOM)))
    LK.PL_is_integer(ld, t) && return LK.PL_get_int64(ld, t)
    LK.PL_is_float(ld, t) && return LK.PL_get_float(ld, t)
    if LK.PL_is_pair(ld, t)
        out = Any[]
        h = LK.PL_new_term_ref(ld)
        tl = LK.PL_copy_term_ref(ld, t)
        while LK.PL_get_list(ld, tl, h, tl)
            push!(out, _pc_val(ld, h))
        end
        LK.PL_get_nil(ld, tl) || push!(out, :partial_tail)
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
_q(s::String) = "'" * s * "'"                         # the Prolog text of the atom `s` (no quote or backslash in `s`)
_ex(ps...) = Any[("-", n, v) for (n, v) in ps]       # the expected Name-Value list

# compile `pat` into a fresh re_data (after `setup(re)`): (ok, re, the pending error); the frame is discarded, the compiled code is NOT freed (the caller does)
function _pc_compile(pat::String; setup=re -> nothing)
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
function _pc_re(pat::String; setup=re -> nothing)
    ok, re, exc = _pc_compile(pat; setup)
    ok || error("the pattern does not compile: $pat ($exc)")
    return re
end

# the character position and length of capture `k` (0: the whole match) of the Julia match `m` over `s`
function _pc_crange(s::String, m::RegexMatch, k::Int)
    off = k == 0 ? m.offset : m.offsets[k]
    str = k == 0 ? m.match : m.captures[k]
    return (length(s[1:prevind(s, off)]), length(str))
end

# ---- the folder: `pcre:re_call_folder(Closure, Match, V0, V1)`, one clause per closure atom ----
const _PF_PCRE = LK.lookupModule(_PF_DB.gd, LK.mk_sym(_R, :pcre))
function _pf_add!(head::_R, body::Union{Nothing, _R}=nothing)
    pr = LK.lookupProcedure(LK.mk_sym(_R, :re_call_folder), 4, _PF_PCRE)
    cl = LK.compileClause(_PF_DB.gd, _PF_DB.ld, head, body, pr, _PF_PCRE)
    LK.assertDefinition!(_PF_DB.gd, pr.definition, cl, LK.CL_END)
end
_pf_head(name::String, a2, a3, a4) = _rf("re_call_folder", _rs(name), a2, a3, a4)
# count: V1 is V0 + 1
_pf_add!(
    _pf_head("count", _rv(1), _rv(2), _rv(3)), _rf("is", _rv(3), _rf("+", _rv(2), _rg(1)))
)
# collect: V1 = [Match|V0]
_pf_add!(_pf_head("collect", _rv(1), _rv(2), _rcons(_rv(1), _rv(2))))
# keep: V1 = Match (the last match survives)
_pf_add!(_pf_head("keep", _rv(1), _rv(2), _rv(1)))
# never: fails
_pf_add!(_pf_head("never", _rv(1), _rv(2), _rv(3)), _rs("fail"))
# boom: throws foldexc
_pf_add!(_pf_head("boom", _rv(1), _rv(2), _rv(3)), _rf("throw", _rs("foldexc")))

# The pending exception as error(Formal, _)'s (Formal's name, args), else the ball's value (a plain `throw(foldexc)`); clears it.
function _pf_exc(ld)
    ex = LK.PL_exception(ld, 0)
    ex == 0 && return nothing
    ball = _pc_val(ld, ex)
    e = _pc_exc(ld)
    LK.PL_clear_exception(ld)
    return e === nothing ? ball : e
end

# re_foldl_ of `re` on the subject (Prolog text `subj`), closure atom `clos`, start value `v0` (Prolog text), the unified-with term `v` (Prolog text, "" = fresh) and options:
# (the foreign result, the value of V, the pending exception); the frame is discarded.
function _pf_fold(
    re,
    subj::String;
    clos::String="count",
    v0::String="0",
    v::String="",
    opts::String="[]",
    str::Bool=false
)
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    on = if str
        t = LK.PL_new_term_ref(ld)
        LK.PL_unify_text(
            ld,
            t,
            0,
            LK.PL_chars_t(_pc_bytes(subj), ncodeunits(subj), LK.ENC_UTF8, false),
            LK.PL_STRING
        ) || error("no string term")
        t
    else
        _pc_term(ld, subj)
    end
    cl = _pc_term(ld, clos)
    t0 = _pc_term(ld, v0)
    tv = isempty(v) ? LK.PL_new_term_ref(ld) : _pc_term(ld, v)
    op = _pc_term(ld, opts)
    rc = LK.re_foldl_(ld, re, on, cl, t0, tv, op)
    val = rc == LK.FTRUE ? _pc_val(ld, tv) : nothing
    exc = _pf_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (rc, val, exc)
end

# ---- the memory output stream the portray predicates write on ----
function _pf_outstream(ld, t::Int)
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    bufsize = Ref(0)
    w = LK.Sopenmem(bufp, bufsize, "w")
    w.encoding = LK.ENC_UTF8
    LK.PL_unify_stream(ld, t, w) || error("PL_unify_stream (output)")
    return (w, bufp, bufsize)
end
function _pf_written(w, bufp, bufsize)::String
    LK.Sflush(w)
    return bufp[] === nothing ? "" : String(bufp[][1:bufsize[]])
end

# (the foreign result, the text written, the pending error) of re_portray_(stream, re); `stream` = "" is a fresh memory stream, else the Prolog text of the stream term
function _pf_portray(re; stream::String="")
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_ref(ld)
    w = nothing
    if isempty(stream)
        w, bufp, bufsize = _pf_outstream(ld, t)
    else
        t = _pc_term(ld, stream)
    end
    rc = LK.re_portray_(ld, t, re)
    out = w === nothing ? "" : _pf_written(w, bufp, bufsize)
    exc = _pf_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (rc, out, exc)
end

# the same for re_portray_match_options_(stream, options)
function _pf_portray_mo(opts::String; stream::String="")
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_ref(ld)
    w = nothing
    if isempty(stream)
        w, bufp, bufsize = _pf_outstream(ld, t)
    else
        t = _pc_term(ld, stream)
    end
    op = _pc_term(ld, opts)
    rc = LK.re_portray_match_options_(ld, t, op)
    out = w === nothing ? "" : _pf_written(w, bufp, bufsize)
    exc = _pf_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (rc, out, exc)
end

# (the text re_write_re_options writes for `re`, the separator it leaves): what the portray predicates must embed
function _pf_opts(re)
    io = IOBuffer()
    sep = Ref("")
    LK.re_write_re_options(io, sep, re)
    return (String(take!(io)), sep[])
end

# The text re_portray_ must write for `re` over `capname` (the C's `cap_type_str` of the regex capture type), with `tail` = the part after `$capture=N`
function _pf_expect(re, pat::String, ctype::String, tail::String)
    otext, sep = _pf_opts(re)
    return string(
        "<regex>(/",
        pat,
        "/ [",
        otext,
        sep,
        ctype,
        "] \$capture=",
        Int(re.capture_size),
        tail,
        ")"
    )
end

@testset "re_foldl_: a count over every match, against Julia's eachmatch" begin
    s = "banana"
    re = _pc_re("a")
    rc, val, exc = _pf_fold(re, _q(s))
    @test rc == LK.FTRUE && exc === nothing
    @test val == length(collect(eachmatch(r"a", s)))
    rc, val, _ = _pf_fold(re, _q(s); v0="10")                                    # the fold starts from V0
    @test rc == LK.FTRUE && val == 13
    rc, val, _ = _pf_fold(re, _q("xyz"))                                          # no match: V is V0
    @test rc == LK.FTRUE && val == 0
    rc, val, _ = _pf_fold(re, _q("xyz"); v0="7")
    @test rc == LK.FTRUE && val == 7
    LK.re_free(re)
end

@testset "re_foldl_: the folder sees each match as the Name-Value list, newest first in a collect" begin
    s = "a1b22c333"
    re = _pc_re("(\\d+)")
    rc, val, exc = _pf_fold(re, _q(s); clos="collect", v0="[]")
    @test rc == LK.FTRUE && exc === nothing
    want = [_ex((0, m.match), (1, m.captures[1])) for m in eachmatch(r"(\d+)", s)]
    @test val == reverse(want)
    @test length(val) == 3
    # `keep` leaves the last match as V
    rc, val, _ = _pf_fold(re, _q(s); clos="keep", v0="none")
    @test rc == LK.FTRUE && val == _ex((0, "333"), (1, "333"))
    # the accumulator's start reaches the first call: collect onto [x] keeps x at the end
    rc, val, _ = _pf_fold(re, _q("1"); clos="collect", v0="[x]")
    @test rc == LK.FTRUE && val == Any[_ex((0, "1"), (1, "1")), :x]
    LK.re_free(re)
end

@testset "re_foldl_: an empty match advances one character, a non-empty one to its end" begin
    # `x*` matches the empty string at every character boundary and at the end: Julia reports the same positions
    for s in ("abc", "", "é", "éa", "a😀b")
        re = _pc_re("x*")
        rc, val, exc = _pf_fold(re, _q(s))
        @test rc == LK.FTRUE && exc === nothing
        @test val == length(collect(eachmatch(r"x*", s)))
        LK.re_free(re)
    end
    # the empty matches' character positions (a range capture counts characters: the advance skips a whole UTF-8 character)
    s = "éa😀"
    re = _pc_re("(?<r_R>x*)")
    rc, val, _ = _pf_fold(re, _q(s); clos="collect", v0="[]")
    @test rc == LK.FTRUE
    starts = [first(_pc_crange(s, m, 1)) for m in eachmatch(r"(?<r>x*)", s)]
    @test [v[2][3] for v in reverse(val)] == [("-", st, 0) for st in starts]
    @test starts == [0, 1, 2, 3]
    LK.re_free(re)
    # a non-empty match is followed from its end: `a*` on "aaa" is "aaa" then the empty match at the end
    s = "aaa"
    re = _pc_re("a*")
    rc, val, _ = _pf_fold(re, _q(s); clos="collect", v0="[]")
    @test rc == LK.FTRUE && val == reverse([_ex((0, m.match)) for m in eachmatch(r"a*", s)])
    @test length(val) == 2
    LK.re_free(re)
    # `a*` on "baab": the empty match at 0, "aa" at 1, the empty match at 3 (after "aa"), the empty match at 4
    s = "baab"
    re = _pc_re("a*")
    rc, val, _ = _pf_fold(re, _q(s); clos="collect", v0="[]")
    @test rc == LK.FTRUE && val == reverse([_ex((0, m.match)) for m in eachmatch(r"a*", s)])
    LK.re_free(re)
end

@testset "re_foldl_: the start option and the match options reach the loop" begin
    s = "banana"
    re = _pc_re("a")
    rc, val, _ = _pf_fold(re, _q(s); opts="[start(2)]")
    @test rc == LK.FTRUE && val == length(collect(eachmatch(r"a", s[3:end])))
    @test re.start_flags.flags == 0 && re.start_flags.seen == 0                      # the loop works on a copy: the source regex is untouched
    rc, val, _ = _pf_fold(re, _q(s); opts="[start(6)]")
    @test rc == LK.FTRUE && val == 0
    # a start beyond the subject: domain_error(offset, 99); no fold ran
    rc, val, exc = _pf_fold(re, _q(s); opts="[start(99)]")
    @test rc == LK.FFALSE && exc == ("domain_error", ["offset", "99"])
    # the start is in characters
    rc, val, _ = _pf_fold(_pc_re("é"), _q("ééé"); opts="[start(1)]")
    @test rc == LK.FTRUE && val == 2
    # anchored: every attempt must start exactly where the previous match ended (PCRE2 ANCHORED, doc-only)
    rc, val, _ = _pf_fold(re, _q("aab"); opts="[anchored(true)]")
    @test rc == LK.FTRUE && val == 2
    rc, val, _ = _pf_fold(re, _q("baa"); opts="[anchored(true)]")
    @test rc == LK.FTRUE && val == 0
    # capture_type reaches unify_match
    rcap = _pc_re("(\\w)")
    rc, val, _ = _pf_fold(
        rcap, _q("ab"); clos="keep", v0="none", opts="[capture_type(atom)]"
    )
    @test rc == LK.FTRUE && val == _ex((0, :b), (1, :b))
    @test rcap.capture_type.flags == LK.CAP_DEFAULT                                  # the option went to the copy, not the source
    LK.re_free(rcap)
    LK.re_free(re)
end

@testset "re_foldl_: a result bound beforehand is unified, not overwritten" begin
    re = _pc_re("a")
    rc, val, _ = _pf_fold(re, _q("aaa"); v="3")
    @test rc == LK.FTRUE && val == 3
    rc, _, exc = _pf_fold(re, _q("aaa"); v="4")                                   # 3 matches, not 4: plain failure
    @test rc == LK.FFALSE && exc === nothing
    rc, _, exc = _pf_fold(re, _q("xyz"); v0="5", v="6")                         # the no-match branch unifies too
    @test rc == LK.FFALSE && exc === nothing
    rc, val, _ = _pf_fold(re, _q("xyz"); v0="5", v="5")
    @test rc == LK.FTRUE && val == 5
    LK.re_free(re)
    # the loop that ends on the empty match at the end of the subject unifies too: `x*` on "ab" has 3 matches
    rex = _pc_re("x*")
    rc, val, _ = _pf_fold(rex, _q("ab"); v="3")
    @test rc == LK.FTRUE && val == 3
    rc, _, exc = _pf_fold(rex, _q("ab"); v="4")
    @test rc == LK.FFALSE && exc === nothing
    LK.re_free(rex)
end

@testset "re_foldl_: subjects (code list, string) and errors read before the loop" begin
    re = _pc_re("é")
    rc, val, _ = _pf_fold(re, "[104, 233, 106, 233]")                               # "héjé" as codes
    @test rc == LK.FTRUE && val == 2
    rc, val, _ = _pf_fold(re, "héjé"; str=true)
    @test rc == LK.FTRUE && val == 2
    rc, _, exc = _pf_fold(re, "f(x)")
    @test rc == LK.FFALSE && exc !== nothing && exc[1] == "type_error"
    rc, _, exc = _pf_fold(re, _q("é"); opts="foo")                                  # the options are read after the subject
    @test rc == LK.FFALSE && exc !== nothing && exc[1] == "type_error"
    rc, _, exc = _pf_fold(re, "f(x)"; opts="foo")                                   # both bad: the subject's error comes first
    @test rc == LK.FFALSE && exc !== nothing && exc[2][1] == "string"
    # a failed read stops before any call of the folder: the pattern `x*` would match the empty subject and `boom` would raise foldexc
    rex = _pc_re("x*")
    rc, _, exc = _pf_fold(rex, "f(x)"; clos="boom")
    @test rc == LK.FFALSE && exc !== nothing && exc != :foldexc
    rc, _, exc = _pf_fold(rex, _q("a"); clos="boom", opts="foo")
    @test rc == LK.FFALSE && exc !== nothing && exc != :foldexc
    LK.re_free(rex)
    LK.re_free(re)
end

@testset "re_foldl_: the folder's failure and exception end the fold" begin
    re = _pc_re("a")
    rc, _, exc = _pf_fold(re, _q("banana"); clos="never")
    @test rc == LK.FFALSE && exc === nothing
    rc, _, exc = _pf_fold(re, _q("banana"); clos="boom")
    @test rc == LK.FFALSE && exc == :foldexc                                        # PL_Q_PASS_EXCEPTION: the ball reaches the caller
    # a closure with no clause: existence_error of the procedure, passed on
    rc, _, exc = _pf_fold(re, _q("banana"); clos="nosuchclosure")
    @test rc == LK.FFALSE
    # no match, no call: the failing folder is never reached, V is V0
    rc, val, exc = _pf_fold(re, _q("xyz"); clos="boom", v0="7")
    @test rc == LK.FTRUE && val == 7 && exc === nothing
    LK.re_free(re)
end

@testset "re_foldl_: a match error is raised after the earlier matches were folded" begin
    # the library's default match limit is hit by nested quantifiers with no way to match (blind: relies on the default limit, no JIT here)
    re = _pc_re(string("^(a+)+", '$'))
    rc, _, exc = _pf_fold(re, _q("a"^30 * "b"))
    @test rc == LK.FFALSE && exc == ("resource_error", ["match_limit"])
    LK.re_free(re)
end

@testset "re_portray_: the debug text of a compiled regex" begin
    re = _pc_re("(a)b")
    rc, out, exc = _pf_portray(re)
    @test rc == LK.FTRUE && exc === nothing
    @test out == _pf_expect(re, "(a)b", "CAP_DEFAULT", " {1 0:CAP_DEFAULT 1:CAP_DEFAULT}")
    @test startswith(out, "<regex>(/(a)b/ [") &&
        endswith(out, "] \$capture=1 {1 0:CAP_DEFAULT 1:CAP_DEFAULT})")
    LK.re_free(re)

    # no groups: no `{...}` table
    re = _pc_re("ab")
    rc, out, _ = _pf_portray(re)
    @test rc == LK.FTRUE && out == _pf_expect(re, "ab", "CAP_DEFAULT", "") &&
        endswith(out, "\$capture=0)")
    LK.re_free(re)

    # named and typed groups: the name between the number and the type, an unnamed group by number and type
    re = _pc_re("(?<z>a)(?<b_I>b)(c)")
    rc, out, _ = _pf_portray(re)
    @test rc == LK.FTRUE
    @test endswith(
        out, "\$capture=3 {3 0:CAP_DEFAULT 1:z:CAP_DEFAULT 2:b:CAP_INTEGER 3:CAP_DEFAULT})"
    )
    @test out == _pf_expect(
        re,
        "(?<z>a)(?<b_I>b)(c)",
        "CAP_DEFAULT",
        " {3 0:CAP_DEFAULT 1:z:CAP_DEFAULT 2:b:CAP_INTEGER 3:CAP_DEFAULT}"
    )
    LK.re_free(re)

    # an unnamed group's own type is printed (the entry is set by hand: no pattern gives an unnamed group a type)
    re = _pc_re("(a)b")
    re.capture_names[2].type = LK.CAP_RANGE
    rc, out, _ = _pf_portray(re)
    @test rc == LK.FTRUE && endswith(out, " {1 0:CAP_DEFAULT 1:CAP_RANGE})")
    LK.re_free(re)

    # the regex capture type is printed by name
    re = _pc_re("ab"; setup=re -> (re.capture_type.flags = UInt32(LK.CAP_ATOM)))
    rc, out, _ = _pf_portray(re)
    @test rc == LK.FTRUE && out == _pf_expect(re, "ab", "CAP_ATOM", "") &&
        occursin("CAP_ATOM] \$capture=0)", out)
    LK.re_free(re)

    # the optimise flag adds ` $optimise` (after the capture count, before the table)
    re = _pc_re("(a)b"; setup=re -> (re.optimise_flags.flags = LK.RE_OPTIMISE))
    rc, out, _ = _pf_portray(re)
    @test rc == LK.FTRUE
    @test out == _pf_expect(
        re, "(a)b", "CAP_DEFAULT", " \$optimise {1 0:CAP_DEFAULT 1:CAP_DEFAULT}"
    )
    @test occursin("\$capture=1 \$optimise {1 ", out)
    LK.re_free(re)

    # a pattern with non-ASCII characters is written as its characters on a UTF-8 stream
    re = _pc_re("é(a)")
    rc, out, _ = _pf_portray(re)
    @test rc == LK.FTRUE && startswith(out, "<regex>(/é(a)/ [") &&
        out == _pf_expect(re, "é(a)", "CAP_DEFAULT", " {1 0:CAP_DEFAULT 1:CAP_DEFAULT}")
    LK.re_free(re)

    # the options come from re_write_re_options: a changed compile option shows in the text
    re = _pc_re("(a)b"; setup=re -> (re.compile_options_flags.flags |= LK.PCRE2_CASELESS))
    rc, out, _ = _pf_portray(re)
    @test rc == LK.FTRUE && occursin("CASELESS", out) &&
        out == _pf_expect(re, "(a)b", "CAP_DEFAULT", " {1 0:CAP_DEFAULT 1:CAP_DEFAULT}")
    LK.re_free(re)
end

@testset "re_portray_: the source regex is untouched, the stream must be an output stream" begin
    re = _pc_re("(a)b")
    re.start_flags.flags = UInt32(5)
    rc, out1, _ = _pf_portray(re)
    rc2, out2, _ = _pf_portray(re)
    @test rc == LK.FTRUE && rc2 == LK.FTRUE && out1 == out2
    @test re.start_flags.flags == 5
    # not a stream: the error of PL_get_stream, nothing written, the regex untouched
    rc, out, exc = _pf_portray(re; stream="no_such_stream_alias")
    @test rc == LK.FFALSE && exc !== nothing
    LK.re_free(re)
end

@testset "re_portray_match_options_: the match options and `\$start`" begin
    # no regex here: the text of a code-less regex, then `$start=N` (the compile options are not shown)
    rc, out, exc = _pf_portray_mo("[]")
    @test rc == LK.FTRUE && exc === nothing
    @test out == "<no re_compiled> \$start=0"
    rc, out, _ = _pf_portray_mo("[start(3)]")
    @test rc == LK.FTRUE && out == "<no re_compiled> \$start=3"
    # a match option shows in the options text, before `$start`
    rc, out, _ = _pf_portray_mo("[anchored(true), start(2)]")
    re = LK.re_init_data("")
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    @test LK.re_get_options(ld, _pc_term(ld, "[anchored(true), start(2)]"), re)
    LK.PL_discard_foreign_frame(ld, fid)
    otext, sep = _pf_opts(re)
    @test rc == LK.FTRUE && occursin("ANCHORED", out)
    @test out == string(otext, sep, "\$start=2") && endswith(out, " \$start=2")
    # the options are read before anything is written: a bad option list writes nothing and is an error
    rc, out, exc = _pf_portray_mo("foo")
    @test rc == LK.FFALSE && out == "" && exc !== nothing && exc[1] == "type_error"
    rc, out, exc = _pf_portray_mo("[start(-1)]")
    @test rc == LK.FFALSE && out == "" && exc !== nothing
    # not a stream
    rc, out, exc = _pf_portray_mo("[]"; stream="no_such_stream_alias")
    @test rc == LK.FFALSE && exc !== nothing
end
