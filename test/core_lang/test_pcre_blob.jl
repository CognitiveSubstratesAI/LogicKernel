# CLASS: test
# ORIGINAL: PCRE1 piece 13 (E1)'s gate - `get_re`, `get_re_copy`, `re_compile_`, `install_pcre4pl`, the blob type `pcre2_blob` and the eight registered functions of
# packages/pcre/pcre4pl.c (packages-pcre a5e4c885; src/pl-pcre.jl piece 13), and the kernel's blob hook table they stand on (`blob_hooks`, `blob_new!`, `blob_object`,
# the 4-argument `PL_register_blob_type` in src/pl-atom.jl; the `write` hook branch of `writeAtom` in src/pl-write.jl). The expected values are derived, none invented:
# the blob text from the C (`<regex>(0x%x, %s)`, write_pcre) as pinned by test_pcre_save_load.jl, the match results and the fold count from the C's own algorithm as
# the pieces 11 and 12 files pin them (against Julia's Regex on the same library), the kernel rows from the contract in the docstrings of the hook table, and the
# error terms from `PL_type_error`/`PL_error` read back as error(Formal, _). Rows that pin kernel behaviour with no upstream counterpart say "kernel-pinned".
# Helpers `_pc_*` are copied from test_pcre_fold.jl and `_ps_*` from test_pcre_save_load.jl (those files are not included). Nothing here has run (written edit-only):
# BLIND RISKS the lane settles are (1) `PL_put_term` on a fresh output reference shares the variable with the caller's reference (the wrapper rows read the output
# through the caller's reference), (2) the culprit of a type error on a custom blob term is not read (only the formal's name and the type name are compared), (3) a
# number as the pattern raises (CVT_EXCEPTION without CVT_INTEGER), (4) the options error rows: `caseless(foo)` and a non-list raise (the formal is not compared),
# (5) re-saving the loaded regex gives the saved state back (the recompile does not change the option fields), (6) `PL_write_term` of a hooked blob without a write
# hook prints `<type>(0x..)` as the kernel's own types, (7) `ld.atoms.types` holds one registration per type.
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

# ---- the `_ps_*` helpers of test_pcre_save_load.jl: the qlf atom stand-ins and the memory streams ----
function _ps_put_atom(pattern::String, fd)::Bool
    bytes = codeunits(pattern)
    LK.PL_qlf_put_uint32(UInt32(length(bytes)), fd) || return false
    for b in bytes
        LK.PL_qlf_put_uint32(UInt32(b), fd) || return false
    end
    return true
end
function _ps_get_atom(fd)::Union{Nothing, String}
    ok, n = LK.PL_qlf_get_uint32(fd)
    ok || return nothing
    out = UInt8[]
    for _ in 1:n
        ok, b = LK.PL_qlf_get_uint32(fd)
        ok || return nothing
        push!(out, UInt8(b))
    end
    return String(out)
end
function _ps_save(re; put_atom = _ps_put_atom)
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    w = LK.Sopenmem(bufp, sizep, "w")
    ok = LK.re_save_fields(re, w, put_atom)
    LK.Sflush(w)
    out = sizep[] == 0 ? UInt8[] : copy(bufp[][1:sizep[]])
    LK.Sclose(w)
    return (ok, out)
end
_ps_reader(bytes::Vector{UInt8}) = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(copy(bytes)), Ref(length(bytes)), "r")
const _PS_GROUPS = (
    :compile_options_flags, :capture_type, :optimise_flags, :jit_options_flags, :compile_ctx_flags,
    :compile_bsr_flags, :compile_newline_flags, :match_options_flags, :start_flags,
)
_ps_state(re) = [(getfield(re, g).seen, getfield(re, g).flags) for g in _PS_GROUPS]

# ---- the helpers of this file ----
# a fresh database's local data (its atom table holds no blob type yet)
_pb_fresh() = _rdb(Tuple{_R, Union{Nothing, _R}}[]).ld
_pb_term(ld, w) = LK._blob_term!(ld.atoms, ld.atom_symbols, _R, w)
_pb_re(ld, w) = LK.blob_object(ld.atoms, w, LK.pcre2_blob)

# term makers (`ld -> term_t`)
_pb_atom(s::String) = ld -> _pc_term(ld, _q(s))
_pb_text(s::String) = ld -> _pc_term(ld, s)
_pb_fresh_ref() = ld -> LK.PL_new_term_ref(ld)
function _pb_string(s::String)
    return function (ld)
        t = LK.PL_new_term_ref(ld)
        LK.PL_unify_text(ld, t, 0, LK.PL_chars_t(_pc_bytes(s), ncodeunits(s), LK.ENC_UTF8, false), LK.PL_STRING) || error("no string term")
        return t
    end
end
function _pb_blobref(ld0, w)
    return function (ld)
        t = LK.PL_new_term_ref(ld)
        LK.PL_put_atom(ld, t, _pb_term(ld, w))
        return t
    end
end

# re_compile_(Pattern, Regex, Options): (the result, the blob word or nothing, the pending error); `reb` = a maker for the second argument (default fresh)
function _pb_compile(ld, mk::Function; opts::String = "[]", reb::Function = _pb_fresh_ref())
    fid = LK.PL_open_foreign_frame(ld)
    pt = mk(ld)
    rt = reb(ld)
    op = _pc_term(ld, opts)
    rc = LK.re_compile_(ld, pt, rt, op)
    w = nothing
    if rc == LK.FTRUE
        a = LK.PL_get_atom(ld, rt)
        w = LK.blob_handle(a)
    end
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (rc, w, exc)
end
_pb_compile(ld, pat::String; opts::String = "[]") = _pb_compile(ld, _pb_atom(pat); opts)

# re_get_re / re_get_re_copy of the term the maker makes: (the regex or nothing, the pending error)
function _pb_get(ld, mk::Function; copy::Bool = false)
    fid = LK.PL_open_foreign_frame(ld)
    t = mk(ld)
    re = copy ? LK.re_get_re_copy(ld, t) : LK.re_get_re(ld, t)
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (re, exc)
end

# `fn(ld, t0, n, ctx)` (a registered wrapper, or a lambda over the same block) over the arguments the makers make, in one argument block:
# (the result, the Julia values of the argument references afterwards, the pending error)
# (a blob argument is read as :blob: its text is no value)
function _pb_val(ld, r::Int)
    a = LK.PL_get_atom(ld, r)
    a !== nothing && LK.is_blob(a) && return :blob
    return _pc_val(ld, r)
end
function _pb_wrap(fn, mks::Function...; ctx = LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing), after::Function = () -> nothing)
    ld = _PC_LD
    fid = LK.PL_open_foreign_frame(ld)
    refs = Int[mk(ld) for mk in mks]
    t0 = LK.PL_new_term_refs(ld, max(length(refs), 1))
    for (i, r) in enumerate(refs)
        LK.PL_put_term(ld, t0 + i - 1, r)
    end
    rc = fn(ld, t0, length(refs), ctx)
    vals = Any[_pb_val(ld, r) for r in refs]
    after()
    exc = _pc_exc(ld)
    LK.PL_discard_foreign_frame(ld, fid)
    return (rc, vals, exc)
end

# the same with a memory output stream as the FIRST argument: (the result, the text written, the pending error)
function _pb_stream_wrap(fn, extra::Function...)
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    bufsize = Ref(0)
    w = LK.Sopenmem(bufp, bufsize, "w")
    w.encoding = LK.ENC_UTF8
    mks = function (ld)
        t = LK.PL_new_term_ref(ld)
        LK.PL_unify_stream(ld, t, w) || error("PL_unify_stream (output)")
        return t
    end
    text = Ref("")
    rc, _, exc = _pb_wrap(fn, mks, extra...; after = () -> (LK.Sflush(w); text[] = bufp[] === nothing ? "" : String(bufp[][1:bufsize[]])))
    return (rc, text[], exc)
end

# write the blob word `w` through PL_write_term onto user_output: (the result, the text)
function _pb_write(ld, w; flags = 0)
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, 1)
    LK.PL_put_atom(ld, t, _pb_term(ld, w))
    out = IOBuffer()
    LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, out)
    ok = LK.PL_write_term(LK._query_gd(ld), ld, LK.Suser_output(ld), t, 1200, flags)
    LK.Sflush(LK.Suser_output(ld))
    s = String(take!(out))
    LK.PL_discard_foreign_frame(ld, fid)
    return (ok, s)
end

# re_matchsub_ of `re` on the Prolog text `subj`: (the result, the value of the result term)
function _pb_matchsub(re, subj::String; opts::String = "[]")
    rc, vals, _ = _pb_wrap((ld, t0, n, ctx) -> LK.re_matchsub_(ld, re, t0, t0 + 1, t0 + 2), _pb_text(subj), _pb_fresh_ref(), _pb_text(opts))
    return (rc, vals[2])
end

# ---- the folder: `pcre:re_call_folder(count, _, V0, V1)`: V1 is V0 + 1 ----
const _PF_PCRE = LK.lookupModule(_PF_DB.gd, LK.mk_sym(_R, :pcre))
let
    pr = LK.lookupProcedure(LK.mk_sym(_R, :re_call_folder), 4, _PF_PCRE)
    head = _rf("re_call_folder", _rs("count"), _rv(1), _rv(2), _rv(3))
    cl = LK.compileClause(_PF_DB.gd, _PF_DB.ld, head, _rf("is", _rv(3), _rf("+", _rv(2), _rg(1))), pr, _PF_PCRE)
    LK.assertDefinition!(_PF_DB.gd, pr.definition, cl, LK.CL_END)
end

# custom blob types (the registration is per database, every row that registers them uses a fresh one)
const _PB_HOOKED = LK.PL_blob_t(UInt32(0), "pcre_test_hooked")
const _PB_PLAIN = LK.PL_blob_t(UInt32(0), "pcre_test_plain")
const _PB_LATE = LK.PL_blob_t(UInt32(0), "pcre_test_late")
const _PB_LOOK = LK.PL_blob_t(UInt32(0), "pcre_test_look")
const _PB_NOWRITE = LK.PL_blob_t(UInt32(0), "pcre_test_nowrite")

# ======================================================================================================================
# (a) the registration of the regex type
@testset "re_register_blob / install_pcre4pl: the regex type with its five hooks, once per database" begin
    ld = _pb_fresh()
    @test LK.pcre2_blob.name == "regex"
    @test LK.pcre2_blob.flags == UInt32(0)                       # not unique, not text
    @test LK._blob_registration(ld.atoms, LK.pcre2_blob) === nothing
    reg = LK.re_register_blob(ld.atoms)
    @test reg.type === LK.pcre2_blob
    h = reg.hooks
    @test h !== nothing && isempty(h.objects)
    @test h.acquire === LK.re_acquire_pcre
    @test h.release === LK.re_free
    @test h.write === LK.re_write_text
    @test h.save === LK.re_save_fields
    @test h.load === LK.re_load_pcre
    @test LK.re_register_blob(ld.atoms) === reg                  # a second call is the same registration
    @test LK.install_pcre4pl(ld) === nothing
    @test LK._blob_registration(ld.atoms, LK.pcre2_blob) === reg
    @test count(r -> r.type === LK.pcre2_blob, ld.atoms.types) == 1
    ld2 = _pb_fresh()                                            # another database has its own table
    @test LK._blob_registration(ld2.atoms, LK.pcre2_blob) === nothing
    LK.install_pcre4pl(ld2)
    reg2 = LK._blob_registration(ld2.atoms, LK.pcre2_blob)
    @test reg2 !== reg && reg2.hooks !== h && isempty(reg2.hooks.objects)
    # the acquire hook of the C stores the symbol in a field nobody reads: here it does nothing (doc-only, DIVERGES 32)
    @test LK.re_acquire_pcre(LK.re_init_data("a"), UInt64(1)) === nothing
end

# ======================================================================================================================
# (b) the kernel's hook table (kernel-pinned: there is no upstream counterpart)
@testset "blob_hooks: the keyword constructor leaves every slot out and the object table empty" begin
    h = LK.blob_hooks()
    @test h.acquire === nothing && h.release === nothing && h.write === nothing && h.save === nothing && h.load === nothing
    @test h.objects isa Vector{Any} && isempty(h.objects)
    f = x -> x
    h2 = LK.blob_hooks(write = f)
    @test h2.write === f && h2.acquire === nothing && h2.release === nothing && h2.save === nothing && h2.load === nothing
    h3 = LK.blob_hooks(acquire = f, release = f, save = f, load = f)
    @test h3.acquire === f && h3.release === f && h3.save === f && h3.load === f && h3.write === nothing
    @test h2.objects !== h3.objects                              # one table per hooks value
end

@testset "blob_new! / blob_object: the object by serial, the type test, the acquire hook" begin
    ld = _pb_fresh()
    atoms = ld.atoms
    acq = Any[]
    hooks = LK.blob_hooks(acquire = (o, w) -> push!(acq, (o, w)))
    reg = LK.PL_register_blob_type(atoms, _PB_HOOKED, UInt64(0), hooks)
    @test reg.hooks === hooks && reg.type === _PB_HOOKED
    obj = "payload"
    w1 = LK.blob_new!(atoms, _PB_HOOKED, obj)
    @test length(acq) == 1 && acq[1][1] === obj && acq[1][2] == w1       # acquire is called once, with the object and the word
    @test length(hooks.objects) == 1 && hooks.objects[1] === obj
    @test LK.blob_object(atoms, w1, _PB_HOOKED) === obj
    w2 = LK.blob_new!(atoms, _PB_HOOKED, obj)                    # the type is not unique: one word per call, also for one object
    @test w2 != w1 && length(hooks.objects) == 2 && length(acq) == 2
    @test acq[2][2] == w2
    @test LK.blob_object(atoms, w2, _PB_HOOKED) === obj
    obj2 = ["other"]
    w3 = LK.blob_new!(atoms, _PB_HOOKED, obj2)
    @test length(hooks.objects) == 3
    @test LK.blob_object(atoms, w3, _PB_HOOKED) === obj2          # the serial names the object
    @test LK.blob_object(atoms, w1, _PB_HOOKED) === obj           # the older blobs still name theirs
    @test LK.blob_object(atoms, w2, _PB_HOOKED) === obj
    # a blob of another type is no object of this type, in either direction
    LK.PL_register_blob_type(atoms, _PB_PLAIN, UInt64(0))
    wp, _ = LK.lookupBlob(atoms, collect(reinterpret(UInt8, Int64[1])), 8, _PB_PLAIN)
    @test LK.blob_object(atoms, wp, _PB_HOOKED) === nothing
    @test LK.blob_object(atoms, w1, _PB_PLAIN) === nothing       # the type is registered but has no hooks
    # a type without hooks cannot make hooked blobs
    @test_throws ArgumentError LK.blob_new!(atoms, _PB_PLAIN, "x")
    @test_throws ArgumentError LK.blob_new!(atoms, _PB_LATE, "x")      # not registered at all
    @test length(hooks.objects) == 3
end

@testset "PL_register_blob_type with hooks: a type registered without them gets them, a type with hooks keeps its first" begin
    ld = _pb_fresh()
    atoms = ld.atoms
    r0 = LK.PL_register_blob_type(atoms, _PB_LATE, UInt64(0))
    @test r0.hooks === nothing
    h1 = LK.blob_hooks()
    r1 = LK.PL_register_blob_type(atoms, _PB_LATE, UInt64(0), h1)
    @test r1 === r0 && r0.hooks === h1
    h2 = LK.blob_hooks()
    r2 = LK.PL_register_blob_type(atoms, _PB_LATE, UInt64(0), h2)
    @test r2 === r0 && r0.hooks === h1                           # the first hooks stay
    @test count(r -> r.type === _PB_LATE, atoms.types) == 1
    # a type registered by `lookupBlob` (an unknown type) gets its hooks later
    lookupw, _ = LK.lookupBlob(atoms, UInt8[1, 2, 3], 3, _PB_LOOK)
    rl = LK._blob_registration(atoms, _PB_LOOK)
    @test rl !== nothing && rl.hooks === nothing
    hl = LK.blob_hooks()
    @test LK.PL_register_blob_type(atoms, _PB_LOOK, UInt64(0), hl) === rl
    @test rl.hooks === hl
    # the kernel's own types are registered by the 3-argument form and have no hooks
    @test all(r -> r.type === _PB_LATE || r.type === _PB_LOOK || r.hooks === nothing, atoms.types)
end

# ======================================================================================================================
# (c) the write hook, through PL_write_term
@testset "writeAtom: a hooked type with a write hook is written as the hook's text, one without as <type>(0x..)" begin
    ld = _pb_fresh()
    atoms = ld.atoms
    LK.PL_register_blob_type(atoms, _PB_HOOKED, UInt64(0), LK.blob_hooks(write = o -> "W:" * o))
    LK.PL_register_blob_type(atoms, _PB_NOWRITE, UInt64(0), LK.blob_hooks())
    LK.PL_register_blob_type(atoms, _PB_PLAIN, UInt64(0))
    w = LK.blob_new!(atoms, _PB_HOOKED, "hello")
    for flags in (0, LK.PL_WRT_QUOTED)
        ok, s = _pb_write(ld, w; flags)
        @test ok && s == "W:hello"
    end
    w2 = LK.blob_new!(atoms, _PB_HOOKED, "bye")                  # the text names the object, not the first one of the type
    @test _pb_write(ld, w2) == (true, "W:bye")
    @test _pb_write(ld, w) == (true, "W:hello")
    wn = LK.blob_new!(atoms, _PB_NOWRITE, "x")
    for flags in (0, LK.PL_WRT_QUOTED)
        ok, s = _pb_write(ld, wn; flags)
        @test ok && occursin(r"^<pcre_test_nowrite>\(0x[0-9a-f]+\)$", s)
    end
    wp, _ = LK.lookupBlob(atoms, UInt8[7], 1, _PB_PLAIN)
    for flags in (0, LK.PL_WRT_QUOTED)
        ok, s = _pb_write(ld, wp; flags)
        @test ok && occursin(r"^<pcre_test_plain>\(0x[0-9a-f]+\)$", s)
    end
end

@testset "writeAtom: a regex blob is written <regex>(0x<serial>, <pattern>)" begin
    ld = _pb_fresh()
    rc, w, exc = _pb_compile(ld, "a.c")
    @test rc == LK.FTRUE && exc === nothing
    re = _pb_re(ld, w)
    expect = string("<regex>(0x", string(re.serial, base = 16), ", a.c)")
    for flags in (0, LK.PL_WRT_QUOTED)
        @test _pb_write(ld, w; flags) == (true, expect)
    end
    # the text is the object's own: a second regex writes its own pattern and serial
    rc, w2, _ = _pb_compile(ld, "x(y)")
    re2 = _pb_re(ld, w2)
    @test _pb_write(ld, w2) == (true, string("<regex>(0x", string(re2.serial, base = 16), ", x(y))"))
    @test _pb_write(ld, w) == (true, expect)
end

# ======================================================================================================================
# (d) get_re, get_re_copy
@testset "re_get_re: the regex of a regex blob, else type_error(regex, T)" begin
    ld = _pb_fresh()
    rc, w, _ = _pb_compile(ld, "a(b)c")
    @test rc == LK.FTRUE
    re = _pb_re(ld, w)
    got, exc = _pb_get(ld, _pb_blobref(ld, w))
    @test exc === nothing && got === re && got.pattern == "a(b)c"
    # an atom, a number
    got, exc = _pb_get(ld, _pb_atom("foo"))
    @test got === nothing && exc == ("type_error", ["regex", "foo"])
    got, exc = _pb_get(ld, _pb_text("3"))
    @test got === nothing && exc == ("type_error", ["regex", "3"])
    # a blob of another type, with and without hooks
    LK.PL_register_blob_type(ld.atoms, _PB_HOOKED, UInt64(0), LK.blob_hooks())
    wh = LK.blob_new!(ld.atoms, _PB_HOOKED, re)                  # even one that names a re_data
    got, exc = _pb_get(ld, _pb_blobref(ld, wh))
    @test got === nothing && exc !== nothing && exc[1] == "type_error" && exc[2][1] == "regex"
    LK.PL_register_blob_type(ld.atoms, _PB_PLAIN, UInt64(0))
    wp, _ = LK.lookupBlob(ld.atoms, collect(reinterpret(UInt8, Int64[1])), 8, _PB_PLAIN)
    got, exc = _pb_get(ld, _pb_blobref(ld, wp))
    @test got === nothing && exc !== nothing && exc[1] == "type_error" && exc[2][1] == "regex"
    # a second regex blob names its own regex
    rc, w2, _ = _pb_compile(ld, "zz")
    got2, _ = _pb_get(ld, _pb_blobref(ld, w2))
    @test got2 !== re && got2.pattern == "zz"
end

@testset "re_get_re_copy: a copy with the match and start flags reset, the blob's regex untouched" begin
    ld = _pb_fresh()
    rc, w, _ = _pb_compile(ld, "a(b)c")
    re = _pb_re(ld, w)
    re.match_options_flags.seen = UInt32(5)
    re.match_options_flags.flags = UInt32(0x77)
    re.start_flags.seen = UInt32(3)
    re.start_flags.flags = UInt32(9)
    cp, exc = _pb_get(ld, _pb_blobref(ld, w); copy = true)
    @test exc === nothing && cp !== nothing
    @test cp !== re && cp.code == re.code && cp.pattern == re.pattern && cp.capture_size == re.capture_size
    @test (cp.match_options_flags.seen, cp.match_options_flags.flags) == (0, LK.PCRE2_NO_UTF_CHECK)
    @test (cp.start_flags.seen, cp.start_flags.flags) == (0, 0)
    @test cp.match_options_flags !== re.match_options_flags
    @test (re.match_options_flags.seen, re.match_options_flags.flags) == (5, 0x77)      # the original keeps its flags
    @test (re.start_flags.seen, re.start_flags.flags) == (3, 9)
    @test _ps_state(cp)[[1, 2, 3, 4, 5, 6, 7]] == _ps_state(re)[[1, 2, 3, 4, 5, 6, 7]]  # the compile-side groups are copied
    cpn, exc = _pb_get(ld, _pb_atom("foo"); copy = true)
    @test cpn === nothing && exc == ("type_error", ["regex", "foo"])
end

# ======================================================================================================================
# (e) re_compile_
@testset "re_compile_: atom, string and code-list patterns make a regex blob" begin
    ld = _pb_fresh()
    reg = nothing
    words = UInt64[]
    for (mk, pat) in (
            (_pb_atom("a(b)c"), "a(b)c"), (_pb_string("a(b)c"), "a(b)c"), (_pb_text("[97,40,98,41,99]"), "a(b)c"),
            (_pb_atom("é+"), "é+"),
        )
        rc, w, exc = _pb_compile(ld, mk)
        @test rc == LK.FTRUE && exc === nothing
        reg === nothing && (reg = LK._blob_registration(ld.atoms, LK.pcre2_blob))     # compiled, never installed: the compile registers the type
        @test reg !== nothing && reg.hooks !== nothing
        re = _pb_re(ld, w)
        @test re isa LK.re_data && re.pattern == pat && re.code != C_NULL
        @test re.capture_size == (pat == "a(b)c" ? 1 : 0)
        push!(words, w)
    end
    @test length(unique(words)) == 4
    @test length(reg.hooks.objects) == 4                         # one object per blob, in order
    @test all(i -> reg.hooks.objects[i] === _pb_re(ld, words[i]), 1:4)
    # the blob is a blob of the regex type with the hooked text (the kernel sees `regex`)
    @test LK.atomValue(ld.atoms, words[1]).type === LK.pcre2_blob
    # a compiled pattern matches (the code is the pattern's)
    re = _pb_re(ld, words[1])
    @test _pb_matchsub(re, "'xabcx'") == (LK.FTRUE, _ex((0, "abc"), (1, "b")))
    @test _pb_matchsub(re, "'xyz'")[1] == LK.FFALSE
    re4 = _pb_re(ld, words[4])
    @test _pb_matchsub(re4, "'xééy'") == (LK.FTRUE, _ex((0, "éé")))
end

@testset "re_compile_: two compiles of one pattern are two blobs, two regexes" begin
    ld = _pb_fresh()
    _, w1, _ = _pb_compile(ld, "p")
    n1 = length(LK._blob_registration(ld.atoms, LK.pcre2_blob).hooks.objects)
    _, w2, _ = _pb_compile(ld, "p")
    n2 = length(LK._blob_registration(ld.atoms, LK.pcre2_blob).hooks.objects)
    @test (n1, n2) == (1, 2)
    @test w1 != w2
    r1, r2 = _pb_re(ld, w1), _pb_re(ld, w2)
    @test r1 !== r2 && r1.serial != r2.serial && r1.code != r2.code
    @test r1.pattern == r2.pattern == "p"
end

@testset "re_compile_: the options reach the compile" begin
    ld = _pb_fresh()
    _, w0, _ = _pb_compile(ld, "abc")
    re0 = _pb_re(ld, w0)
    @test re0.compile_options_flags.flags & LK.PCRE2_CASELESS == 0
    @test re0.capture_type.flags == UInt32(LK.CAP_STRING)
    rc, wc, exc = _pb_compile(ld, "abc"; opts = "[caseless(true)]")
    @test rc == LK.FTRUE && exc === nothing
    rec = _pb_re(ld, wc)
    @test rec.compile_options_flags.flags & LK.PCRE2_CASELESS != 0
    @test _pb_matchsub(rec, "'xABCx'") == (LK.FTRUE, _ex((0, "ABC")))      # caseless in the compiled code
    @test _pb_matchsub(re0, "'xABCx'")[1] == LK.FFALSE
    rc, wa, _ = _pb_compile(ld, "(a)"; opts = "[capture_type(atom)]")
    @test rc == LK.FTRUE
    @test _pb_re(ld, wa).capture_type.flags == UInt32(LK.CAP_ATOM)
    # the compile flags are those of re_compile_'s own options, not the matcher's: a bad option stops the compile
    n = length(LK._blob_registration(ld.atoms, LK.pcre2_blob).hooks.objects)
    rc, w, exc = _pb_compile(ld, "abc"; opts = "[caseless(foo)]")
    @test rc == LK.FFALSE && w === nothing && exc !== nothing
    rc, w, exc = _pb_compile(ld, "abc"; opts = "foo")             # not a list
    @test rc == LK.FFALSE && w === nothing && exc !== nothing
    @test length(LK._blob_registration(ld.atoms, LK.pcre2_blob).hooks.objects) == n    # no blob was made
end

@testset "re_compile_: the pattern errors" begin
    ld = _pb_fresh()
    # a NUL byte
    rc, w, exc = _pb_compile(ld, _pb_text("[97,0,98]"))
    @test rc == LK.FFALSE && w === nothing && exc == ("representation_error", ["nul_byte"])
    # a syntax error
    rc, w, exc = _pb_compile(ld, "(")
    @test rc == LK.FFALSE && w === nothing && exc !== nothing && exc[1] == "syntax_error"
    # not text
    rc, w, exc = _pb_compile(ld, _pb_text("3"))
    @test rc == LK.FFALSE && w === nothing && exc !== nothing
    rc, w, exc = _pb_compile(ld, _pb_text("f(x)"))
    @test rc == LK.FFALSE && w === nothing && exc !== nothing
    # the second argument is already a different atom: no unification, no error
    rc, w, exc = _pb_compile(ld, _pb_atom("a"); reb = _pb_atom("foo"))
    @test rc == LK.FFALSE && exc === nothing
end

# ======================================================================================================================
# (f) save and load through the hooks
@testset "re_load_pcre: a saved regex loads as a new blob with the same fields and a fresh compile" begin
    ld = _pb_fresh()
    LK.install_pcre4pl(ld)
    rc, w, _ = _pb_compile(ld, "a(b)c"; opts = "[caseless(true)]")
    @test rc == LK.FTRUE
    re = _pb_re(ld, w)
    hooks = LK._blob_registration(ld.atoms, LK.pcre2_blob).hooks
    ok, bytes = _ps_save(re)
    @test ok
    @test bytes[1] == 0x81                                       # the version
    r = _ps_reader(bytes)
    w2 = hooks.load(ld, r, _ps_get_atom)                          # the hook is re_load_pcre
    @test w2 != 0 && w2 != w
    re2 = _pb_re(ld, w2)
    @test re2 !== re && re2.pattern == "a(b)c" && re2.capture_size == 1
    @test _ps_state(re2) == _ps_state(re)
    @test re2.code != C_NULL && re2.code != re.code
    @test re2.serial != re.serial
    @test length(hooks.objects) == 2
    @test _pb_matchsub(re2, "'xABCx'") == (LK.FTRUE, _ex((0, "ABC"), (1, "B")))
    @test _pb_write(ld, w2) == (true, string("<regex>(0x", string(re2.serial, base = 16), ", a(b)c)"))
    LK.Sclose(r)
    # the save hook is re_save_fields
    ok2, bytes2 = _ps_save(re2)
    @test ok2 && bytes2[2:end] == bytes[2:end]
    # a version other than 1 loads as 0 (the word 0 is the C's (atom_t)0)
    bad = copy(bytes)
    bad[1] = 0x82
    rb = _ps_reader(bad)
    @test LK.re_load_pcre(ld, rb, _ps_get_atom) == 0
    LK.Sclose(rb)
    @test length(hooks.objects) == 2
    # an atom reader that fails
    @test LK.re_load_pcre(ld, _ps_reader(bytes), fd -> nothing) == 0
    @test length(hooks.objects) == 2
    # a pattern that does not compile: 0, with the syntax error pending
    badre = LK.re_init_data("(")
    ok3, bytes3 = _ps_save(badre)
    @test ok3
    w3 = LK.re_load_pcre(ld, _ps_reader(bytes3), _ps_get_atom)
    @test w3 == 0
    exc = _pc_exc(ld)
    @test exc !== nothing && exc[1] == "syntax_error"
    @test length(hooks.objects) == 2
end

# ======================================================================================================================
# (g) the eight registered functions over a compiled blob
@testset "the wrappers: re_matchsub_, re_match_ over a regex blob" begin
    ld = _PC_LD
    rc, w, _ = _pb_compile(ld, "a(b)c")
    @test rc == LK.FTRUE
    blob = _pb_blobref(ld, w)
    re = _pb_re(ld, w)
    rc, vals, exc = _pb_wrap(LK.pl_re_matchsub_4_va, blob, _pb_atom("xabcx"), _pb_fresh_ref(), _pb_text("[]"))
    @test rc == LK.FTRUE && exc === nothing
    @test Set(v[3] for v in vals[3]) == Set(["abc", "b"])
    direct = _pb_matchsub(re, "'xabcx'")
    @test direct[1] == LK.FTRUE && vals[3] == direct[2]
    rc, _, exc = _pb_wrap(LK.pl_re_match_3_va, blob, _pb_atom("xabcx"), _pb_text("[]"))
    @test rc == LK.FTRUE && exc === nothing
    rc, _, exc = _pb_wrap(LK.pl_re_match_3_va, blob, _pb_atom("xyz"), _pb_text("[]"))
    @test rc == LK.FFALSE && exc === nothing
    # a non-regex first argument: the type error, no match
    rc, _, exc = _pb_wrap(LK.pl_re_match_3_va, _pb_atom("foo"), _pb_atom("xabcx"), _pb_text("[]"))
    @test rc == LK.FFALSE && exc == ("type_error", ["regex", "foo"])
    rc, _, exc = _pb_wrap(LK.pl_re_matchsub_4_va, _pb_atom("foo"), _pb_atom("xabcx"), _pb_fresh_ref(), _pb_text("[]"))
    @test rc == LK.FFALSE && exc == ("type_error", ["regex", "foo"])
end

@testset "the wrappers: re_compile/3" begin
    ld = _PC_LD
    rc, vals, exc = _pb_wrap(LK.pl_re_compile3_va, _pb_atom("a.c"), _pb_fresh_ref(), _pb_text("[]"))
    @test rc == LK.FTRUE && exc === nothing
    @test vals[2] == :blob                                        # the second argument is bound to a blob
    rc, _, exc = _pb_wrap(LK.pl_re_compile3_va, _pb_atom("("), _pb_fresh_ref(), _pb_text("[]"))
    @test rc == LK.FFALSE && exc !== nothing && exc[1] == "syntax_error"
    # the options are the third argument and the blob the second
    rc, vals, _ = _pb_wrap(LK.pl_re_compile3_va, _pb_atom("abc"), _pb_fresh_ref(), _pb_text("[caseless(true)]"))
    @test rc == LK.FTRUE
    t = LK.PL_new_term_ref(ld)
    rc, vals2, _ = _pb_wrap(
        LK.pl_re_compile3_va, _pb_atom("abc"), (l -> (LK.PL_put_variable(l, t); t)), _pb_text("[caseless(true)]")
    )
    @test rc == LK.FTRUE
    a = LK.PL_get_atom(ld, t)
    @test a !== nothing && LK.is_blob(a)
    re = _pb_re(ld, LK.blob_handle(a))
    @test re !== nothing && re.compile_options_flags.flags & LK.PCRE2_CASELESS != 0
end

@testset "the wrappers: re_foldl_ counts the matches" begin
    ld = _PC_LD
    rc, w, _ = _pb_compile(ld, "ab")
    @test rc == LK.FTRUE
    blob = _pb_blobref(ld, w)
    rc, vals, exc = _pb_wrap(
        LK.pl_re_foldl_6_va, blob, _pb_atom("abab"), _pb_text("count"), _pb_text("0"), _pb_fresh_ref(), _pb_text("[]")
    )
    @test rc == LK.FTRUE && exc === nothing
    @test vals[5] == 2
    rc, _, exc = _pb_wrap(
        LK.pl_re_foldl_6_va, _pb_atom("foo"), _pb_atom("abab"), _pb_text("count"), _pb_text("0"), _pb_fresh_ref(), _pb_text("[]")
    )
    @test rc == LK.FFALSE && exc == ("type_error", ["regex", "foo"])
end

@testset "the wrappers: re_portray and re_portray_match_options write what the term-level functions write" begin
    ld = _PC_LD
    rc, w, _ = _pb_compile(ld, "a(b)c")
    @test rc == LK.FTRUE
    re = _pb_re(ld, w)
    blob = _pb_blobref(ld, w)
    rcd, direct, excd = _pb_stream_wrap((l, t0, n, ctx) -> LK.re_portray_(l, t0, re))
    @test rcd == LK.FTRUE && excd === nothing
    @test startswith(direct, "<regex>(/a(b)c/ [") && endswith(direct, ")")
    rcw, viaw, excw = _pb_stream_wrap(LK.pl_re_portray_2_va, blob)
    @test rcw == LK.FTRUE && excw === nothing && viaw == direct
    # a non-regex second argument: the regex error
    rcw, viaw, excw = _pb_stream_wrap(LK.pl_re_portray_2_va, _pb_atom("foo"))
    @test rcw == LK.FFALSE && excw == ("type_error", ["regex", "foo"]) && viaw == ""
    # the match options: the same text through the wrapper (the second argument is the option list)
    rcd, directo, excd = _pb_stream_wrap((l, t0, n, ctx) -> LK.re_portray_match_options_(l, t0, t0 + 1), _pb_text("[anchored(true)]"))
    @test rcd == LK.FTRUE && excd === nothing
    rcw, viao, excw = _pb_stream_wrap(LK.pl_re_portray_match_options2_va, _pb_text("[anchored(true)]"))
    @test rcw == LK.FTRUE && excw === nothing && viao == directo
end

@testset "the wrappers: re_config_ and re_config_choice" begin
    ld = _PC_LD
    rcd, valsd, excd = _pb_wrap((l, t0, n, ctx) -> LK.re_config_(l, t0), _pb_text("version(_)"))
    @test rcd == LK.FTRUE && excd === nothing
    rcw, valsw, excw = _pb_wrap(LK.pl_re_config_1_va, _pb_text("version(_)"))
    @test rcw == LK.FTRUE && excw === nothing
    @test valsw == valsd && valsw[1][1] == "version" && valsw[1][2] != :var
    # the nondeterministic one: the first answer is the first row, the retry value the direct function's
    rcd, valsd, _ = _pb_wrap((l, t0, n, ctx) -> LK.re_config_choice_(l, t0, ctx), _pb_fresh_ref())
    rcw, valsw, excw = _pb_wrap(LK.pl_re_config_choice1_va, _pb_fresh_ref())
    @test rcw == rcd && rcw != LK.FFALSE && rcw != LK.FTRUE && excw === nothing
    @test valsw == valsd && valsw[1][1] == "bsr2"
end

# ======================================================================================================================
# (h) the table
@testset "PL_predicates_from_pcre: the eight predicates in the C's order, registered in system" begin
    tab = LK.PL_predicates_from_pcre
    @test [(e.predicate_name, e.arity) for e in tab] == [
        ("re_config_", 1), ("re_compile", 3), ("re_match_", 3), ("re_matchsub_", 4), ("re_foldl_", 6),
        ("re_config_choice", 1), ("re_portray", 2), ("re_portray_match_options", 2),
    ]
    @test [e.function_ for e in tab] == Any[
        LK.pl_re_config_1_va, LK.pl_re_compile3_va, LK.pl_re_match_3_va, LK.pl_re_matchsub_4_va, LK.pl_re_foldl_6_va,
        LK.pl_re_config_choice1_va, LK.pl_re_portray_2_va, LK.pl_re_portray_match_options2_va,
    ]
    @test [e.flags for e in tab] == [
        LK.PL_FA_VARARGS, LK.PL_FA_VARARGS, LK.PL_FA_VARARGS, LK.PL_FA_VARARGS, LK.PL_FA_VARARGS,
        LK.PL_FA_NONDETERMINISTIC | LK.PL_FA_VARARGS, LK.PL_FA_VARARGS, LK.PL_FA_VARARGS,
    ]
    @test LK.PL_predicates_from_pcre in LK._PRED_TABLES
    gd = LK.PL_global_data{_R}()
    m = LK.MODULE_system(gd)
    for e in tab
        proc = LK.isCurrentProcedure(sym_key(lk_sym(_R, Symbol(e.predicate_name))), e.arity, m)
        @test proc !== nothing && LK.isDefinedProcedure(gd, proc)
    end
end
