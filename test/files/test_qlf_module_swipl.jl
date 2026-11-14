# ORIGINAL: QLF3's gate (lk-channel evidence/R2/qlf2_handoff.md, QLF3b) — `'$qlf_module'/2` (pl-qlf.c qlf_module, qlfInfo, qlfModuleInfo) and
# the XR reader it uses (loadXR, loadXRc, getAtom, getBlob, getBlobType, qlfGetUInt32, qlfGetDouble, qlfGetString, qlfGetStringW,
# qlfLoadSource, loadInclude, qlfLoadIncludes, pushXrIdTable, popXrIdTable, lookupXrId, storeXrId, PL_put_dict), written from the C
# (swipl-devel 18168e62), UNRUN: no Julia was run when this file was written. Rows marked `# UNVERIFIED on the kernel: gate decides`
# are the C code's behaviour, not yet seen on the kernel.
# test/files/test_qlf_module_swipl.jl — prefix `_QM` / `_qm_`:
#   * QLF files are built byte by byte as `qlfPutInt64` and the XR writer lay them out (the python twin `twin.py`, evidence/R2/qlf3_work,
#     writes the same bytes): the header, then the module record. The answer of `'$qlf_module'(+File, -Dict)` is a dict: it is read by
#     `dict_pairs/3` on the same reference and encoded by ONE extractor (`_qm_enc`, the driver's `enc/1`), pair by pair, the tag first.
#     The pins are the pinned swipl's (10.1.20, 18168e62) on the same files, two runs byte-identical (evidence/R2/qlf3_verify.md); with
#     `swipl` on PATH the live answers are compared with the pins too.
#   * Bound second arguments (a dict made by `dict_create/3`, or a non-dict): the unification of the answer with it.
#   * Error rows by name, with swipl's texts where swipl answers (a `qlf_format_error` ball; the format errors it reports as a fatal
#     error are `ErrorException`s here with the same message; the index in them is read from the file size) and the kernel's texts where
#     swipl ends the process on the input or reads what is there (said at each row).
#   * A corruption row that can fail: every cut of a good file raises, the good file answers.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the XR reader and the module record (src/pl-qlf.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _QM = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_qms(x) = lk_sym(_QM, Symbol(x))
_qmv() = mk_var(_QM, LK.fresh_var_keys!(1))
_qmi(n::Integer) = lk_gnd(_QM, n)

_qm_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes (the ONE extractor of both sides)."
function _qm_enc(t::_QM, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _qm_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _qm_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _qm_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_qm_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

"The elements of the list `t` (`nothing` if `t` is not a proper list of `[|]`/2 cells)."
function _qm_elems(t::_QM)::Union{Nothing, Vector{_QM}}
    out = _QM[]
    while !is_nil(t)
        (kind(t) !== VAR && kind(t) !== SYM && kind(t) !== GND && nchildren(t) == 3) ||
            return nothing
        push!(out, child(t, 2))
        t = child(t, 3)
    end
    return out
end

_qm_pair(k::String, v::_QM) = mk_expr(_QM, _QM[_qms("-"), _qms(k), v])
_qm_pi(n::String, a::Integer) = mk_expr(_QM, _QM[_qms("/"), _qms(n), _qmi(a)])
_qm_list(items::Vector{_QM}; tail::_QM=mk_nil(_QM)) =
    foldr((h, t) -> mk_expr(_QM, _QM[_qms("[|]"), h, t]), items; init=tail)

# ── the bytes: zig-zag integers, strings, the header (as test_qlf_swipl.jl's builder) ──
"The zig-zag, 7 bits per byte (little end first, the last byte has bit 0x80) encoding of `v` (`qlfPutInt64`)."
function _qm_zz(v::Int64)::Vector{UInt8}
    n = (reinterpret(UInt64, v) << 1) ⊻ reinterpret(UInt64, v >> 63)
    out = UInt8[]
    while n >= 0x80
        push!(out, UInt8(n & 0x7f))
        n >>= 7
    end
    push!(out, UInt8(n) | 0x80)
    return out
end
_qm_str(s::String)::Vector{UInt8} =
    vcat(_qm_zz(Int64(ncodeunits(s))), collect(codeunits(s)))
const _QM_SIG = UInt8[0x18, 0x44, 0x70, 0x5e, 0x9c]         # VM_SIGNATURE 0xe5ee110c, as the pinned swipl writes it
const _QM_MAGIC = collect(codeunits("SWI-Prolog .qlf file\n\0"))
"The header of a QLF file of version `ver` saved as `save` (magic, version, signature, the saved name)."
_qm_hdr(save::String, ver::Int=72; sig::Vector{UInt8}=_QM_SIG)::Vector{UInt8} =
    vcat(_QM_MAGIC, _qm_zz(Int64(ver)), sig, _qm_str(save))
"Write the file `name` of version `ver` in `dir`: the header saved under its own path (no path translation), then the body."
function _qm_file(
    dir::String, name::String, ver::Int, body::Vector{UInt8}; sig::Vector{UInt8}=_QM_SIG
)::String
    path = joinpath(dir, name * ".qlf")
    write(path, vcat(_qm_hdr(path, ver; sig), body))
    return path
end

# ── the call: `'$qlf_module'(+File, -Dict)` on a FRESH database (an ErrorException from the format error leaves the query open) ──
const _QM_FLAGS = LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS
"""
`'\$qlf_module'(path, Dict)`; the answer as the one string the pins hold, or the exception the call raised:
`true tag=<enc> | <enc of pair> | ...` (the pairs of `dict_pairs/3`, in its order, each encoded alone), `fail`, `exc <enc of the formal>`;
with `bound` = (tag, pairs) the second argument is the dict `dict_create/3` makes of them and with `arg2` that term: the answer is
`true` or `fail` only.
"""
function _qm_call(
    path::Union{String, _QM};
    bound::Union{Nothing, Tuple{_QM, Vector{_QM}}}=nothing,
    arg2::Union{Nothing, _QM}=nothing,
    translated::Bool=false
)::Union{String, Exception}
    gd = LK.PL_global_data{_QM}()
    ld = LK.PL_local_data{_QM}(gd)
    if translated        # a file that has moved tells `system:'\$translated_source'/2` (as test_qlf_swipl.jl's moved-file rows define it)
        helper = joinpath(mktempdir(), "ts.pl")
        write(helper, "'\$translated_source'(F, T) :- user:assertz(tr_seen(F-T)).\n")
        gd.bootsession = true
        LK.compileFile(gd, ld, nothing, helper) || return "helper failed"
        gd.bootsession = false
    end
    sysm = LK.MODULE_system(gd)
    proc(name, n) = LK.isCurrentProcedure(sym_key(_qms(name)), n, sysm)
    pm = proc("\$qlf_module", 2)
    pm === nothing && return "undefined"
    LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, path isa String ? _qms(path) : path, LK.PutVarMap())      # the slot of the first reference
    if bound !== nothing
        pc = proc("dict_create", 3)
        pc === nothing && return "undefined dict_create"
        dc = LK.PL_new_term_refs(ld, 3)
        tag, pairs = bound
        LK.putSlotValue!(ld, dc + 2, tag, LK.PutVarMap())
        LK.putSlotValue!(ld, dc + 3, _qm_list(pairs), LK.PutVarMap())
        q0 = LK.PL_open_query(gd, ld, nothing, _QM_FLAGS, pc, dc)
        rc0 = LK.PL_next_solution(gd, ld, q0)
        (rc0 == LK.PL_S_TRUE || rc0 == LK.PL_S_LAST) || return "dict_create failed"
        LK.PL_cut_query(ld, q0)                                   # keeps the bindings
        LK.PL_put_term(ld, a + 1, dc)
    elseif arg2 !== nothing
        LK.putSlotValue!(ld, a + 2, arg2, LK.PutVarMap())         # the slot of the second reference
    end
    qid = LK.PL_open_query(gd, ld, nothing, _QM_FLAGS, pm, a)
    rc = try
        LK.PL_next_solution(gd, ld, qid)
    catch ex
        (ex isa ErrorException || ex isa LK.NotPortedError) && return ex
        rethrow()
    end
    if rc == LK.PL_S_EXCEPTION
        ball = lk_answer(ld, LK.PL_exception(ld, qid))
        LK.PL_close_query(ld, qid)
        return "exc " * _qm_enc(child(ball, 2))
    elseif !(rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST)
        LK.PL_close_query(ld, qid)
        return "fail"
    end
    LK.PL_cut_query(ld, qid)                                      # keeps the bindings of the answer
    (bound !== nothing || arg2 !== nothing) && return "true"
    dp = proc("dict_pairs", 3)
    dp === nothing && return "undefined dict_pairs"
    b = LK.PL_new_term_refs(ld, 3)
    LK.PL_put_term(ld, b, a + 1)
    q2 = LK.PL_open_query(gd, ld, nothing, _QM_FLAGS, dp, b)
    rc2 = LK.PL_next_solution(gd, ld, q2)
    (rc2 == LK.PL_S_TRUE || rc2 == LK.PL_S_LAST) || return "dict_pairs failed"
    tag, pl = lk_answers(ld, b + 1, b + 2)
    LK.PL_close_query(ld, q2)
    items = _qm_elems(pl)
    items === nothing && return "dict_pairs: not a list"
    return "true tag=" * _qm_enc(tag) * join(" | " .* _qm_enc.(items))
end

# the swipl side: the driver of evidence/R2/qlf3_work/drv.pl (`enc/1` as the other tests; `run/1`, `runb/3`, `runv/2`, `rune/1`)
const _QM_DRIVER = raw"""
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
run(F) :-
    (   '$qlf_module'(F, D)
    ->  dict_pairs(D, T, P), write(true), write(' tag='), enc(T),
        forall(member(X, P), ( write(' | '), enc(X) )), nl
    ;   writeln(fail)
    ).
runb(F, Tag, Pairs) :-
    dict_create(D0, Tag, Pairs),
    ( '$qlf_module'(F, D0) -> writeln(true) ; writeln(fail) ).
runv(F, X) :- ( '$qlf_module'(F, X) -> writeln(true) ; writeln(fail) ).
"""

# ── the fixtures: (version, hex of the BODY after the header); the notes are the twin's (evidence/R2/qlf3_work/twin.py) ──
const _QM_FIX = Dict{String, Tuple{Int, String}}(
    # module, source, class, two exports
    "basic" => (
        72,
        "514d03846d6d46942f7372632f6d6d2e706c724081000000000000f83f75864303887573657245040382708245040382718458"
    ),
    # no source: class unbound, exports []
    "nosrc" => (72, "514d03846e6e2d58"),
    # class system; the super (an XR_REF to the module name) is read and dropped
    "super_ref" => (72, "514d03846d332d43038c73797374656d53008158"),
    # 40 functors, one of arity 300, one XR_REF to an earlier functor
    "many" => (
        72,
        "514d03846d342d45040384663080450403846631824504038466328445040384663386450403846634884504038466358a4504038466368c4504038466378e4504038466389045040384663992450403866631309445040386663131964504038666313298450403866631339a450403866631349c450403866631359e45040386663136a045040386663137a245040386663138a445040386663139a645040386663230a845040386663231aa45040386663232ac45040386663233ae45040386663234b045040386663235b245040386663236b445040386663237b645040386663238b845040386663239ba45040386663330bc45040386663331be45040386663332c045040386663333c245040386663334c445040386663335c645040386663336c845040386663337ca45040386663338cc45040386663339ce45040386626967588445008658"
    ),
    # two L include entries (v72: file, hash, owner, parent, line, time) before Q
    "inc72" => (
        72,
        "4c942f7372632f69312e706c1a81942f7372632f6d6d2e706c942f7372632f69312e706c8800000000000004404c942f7372632f69322e706c80942f7372632f6d6d2e706c942f7372632f69322e706c920000000000000c40514d03846d3546942f7372632f6d352e706c82000000000000f03f75864303887573657245040382618058"
    ),
    # v68 include: owner pn line fn as XR entries; v68 F has no hash
    "inc68" => (
        68,
        "4903942f7372632f6d6d2e706c03942f7372632f69312e706c8800820000000000000440514d03846d3646942f7372632f6d362e706c000000000000f03f75864303887573657245040382628258"
    ),
    # XR_NIL and XR_CONS as functor names: []/2 and '[|]'/2
    "nilcons" => (72, "514d03846d372d450401844504028458"),
    # ucs_text blob atoms: the module name (U+03BB m), then (type by XR_REF) the class (two CJK characters)
    "ucs" => (72, "514d0b0c907563735f7465787484cebb6d2d430b008284e4b8ade6968758"),
    # a `text` blob as a functor name: its data is a plain atom
    "blobfun" => (72, "514d03846d382d45040b0c88746578748474788658"),
    # an XR_ATOM holding the Latin-1 byte 0xE9: the atom is U+00E9
    "latin" => (72, "514d03846d392d45040388636166e98258"),
    # the record starts with F (not a module file): fails
    "nonmodule" => (72, "5146616e797468696e67"),
    # two C properties: the second unify fails, so the predicate fails
    "redef_class" => (72, "514d03866d31302d4303887573657243038e6c69627261727958"),
    # two S supers, then C
    "two_s" => (72, "514d03866d31312d5300815303847a7a4303887465737458"),
    # two C properties with the same class: both unify
    "cdup_same" => (72, "514d03866d31322d4303887573657243008258"),
    # source name canonicalised (a/../b), kind S, a line
    "srcline" => (
        72,
        "514d03866d313346a42f7372632f612f2e2e2f622f6d31332e706c8a000000000000f03f531a8158"
    ),
    # an arity above 16 bits
    "ints" => (72, "514d03866d31342d450403827a80450403827960458858"),
    # 70 functors, then XR_REF 132 (two bytes) and XR_REF 2
    "bigref" => (
        72,
        "514d03866d31352d450403846730824504038467318245040384673282450403846733824504038467348245040384673582450403846736824504038467378245040384673882450403846739824504038667313082450403866731318245040386673132824504038667313382450403866731348245040386673135824504038667313682450403866731378245040386673138824504038667313982450403866732308245040386673231824504038667323282450403866732338245040386673234824504038667323582450403866732368245040386673237824504038667323882450403866732398245040386673330824504038667333182450403866733328245040386673333824504038667333482450403866733358245040386673336824504038667333782450403866733388245040386673339824504038667343082450403866734318245040386673432824504038667343382450403866734348245040386673435824504038667343682450403866734378245040386673438824504038667343982450403866735308245040386673531824504038667353282450403866735338245040386673534824504038667353582450403866735368245040386673537824504038667353882450403866735398245040386673630824504038667363182450403866736328245040386673633824504038667363482450403866736358245040386673636824504038667363782450403866736388245040386673639824500048145008258"
    ),
    # byte after the module name is neither - nor F
    "e_srcbyte" => (72, "514d038465315a"),
    # property byte Z
    "e_propbyte" => (72, "514d038465322d5a"),
    # first byte is neither Q, I nor L
    "e_inclbyte" => (72, "5a"),
    # byte after Q is neither M nor F
    "e_topbyte" => (72, "515a"),
    # XR_REF to an id never stored
    "e_unstored" => (72, "514d0085"),
    # XR_REF 0 (ids start at 1)
    "e_zeroref" => (72, "514d0080"),
    # XR code 99
    "e_badcode" => (72, "514d63"),
    # XR_FILE with the index byte x
    "e_fileidx" => (72, "514d038465332d530978"),
    # EOF inside the time of the source
    "e_eofdouble" => (72, "514d0384653446942f7372632f65342e706c82010203"),
    # EOF inside an atom of length 100
    "e_eofatom" => (72, "514d034881616263"),
    # blob type weird
    "e_blobtype" => (72, "514d0b0c8a77656972648278"),
    # EOF inside a wide string
    "e_eofwide" => (72, "514d0b0c907563735f746578748661"),
    # module name is an XR_INT
    "e_modint" => (72, "514d068a"),
    # source name above PATH_MAX
    "e_longpath" => (72, "514d038465354610ce6161616161616161616161616161616161616161"),
    # export entry is an XR_INT
    "e_funint" => (72, "514d038465362d45068a58"),
    # negative arity
    "e_negarity" => (72, "514d038465372d450403826e8158"),
    # functor whose name is an XR_INT
    "e_nonatomname" => (72, "514d038465382d4504068282"),
    # the property loop hits the end of the file
    "e_missingx" => (72, "514d038465392d450403827082"),
    # a real qcompile'd module (swipl 10.1.20, a 4-line module `mm` with p/1, q/2 and +++/2 compiled in a short directory): the body
    # after the header, whose saved name is a temporary file's and is rebuilt here
    "real" => (
        72,
        "514d03846d6d469e2f746d702f716c66782f6d6d2e706c46536d6e1b272902d1424ec4c8debdda41758243038875736572530082450403862b2b2b84450403827082450403827184585000858043820975039e2f746d702f716c66782f6d6d2e706c424ec4c8debdda410089818181018282c258500087804383008900898282818203826182038262c25850008380438400890089828281c25858490500830a00818249050085008e8249050087008e820000003d00000001"
    )
)

# the pinned swipl answers (10.1.20, 18168e62; evidence/R2/qlf3_verify.md): the answer line of `run/1` (`true tag=<enc> | <pair> | ...` or `fail`),
# `true`/`fail` of the bound rows (`runb/3`, `runv/2`), `missing` = the two arguments of the existence_error
const _QM_PINS = Dict{String, String}(
    "basic" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],a[117,115,101,114]) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[112],i1),c[91,124,93]/2(c[47]/2(a[113],i2),nil))) | c[45]/2(a[102,105,108,101],a[47,115,114,99,47,109,109,46,112,108]) | c[45]/2(a[109,111,100,117,108,101],a[109,109])",
    "nosrc" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],V0) | c[45]/2(a[101,120,112,111,114,116,115],nil) | c[45]/2(a[109,111,100,117,108,101],a[110,110])",
    "super_ref" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],a[115,121,115,116,101,109]) | c[45]/2(a[101,120,112,111,114,116,115],nil) | c[45]/2(a[109,111,100,117,108,101],a[109,51])",
    "many" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],V0) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[102,48],i0),c[91,124,93]/2(c[47]/2(a[102,49],i1),c[91,124,93]/2(c[47]/2(a[102,50],i2),c[91,124,93]/2(c[47]/2(a[102,51],i3),c[91,124,93]/2(c[47]/2(a[102,52],i4),c[91,124,93]/2(c[47]/2(a[102,53],i5),c[91,124,93]/2(c[47]/2(a[102,54],i6),c[91,124,93]/2(c[47]/2(a[102,55],i7),c[91,124,93]/2(c[47]/2(a[102,56],i8),c[91,124,93]/2(c[47]/2(a[102,57],i9),c[91,124,93]/2(c[47]/2(a[102,49,48],i10),c[91,124,93]/2(c[47]/2(a[102,49,49],i11),c[91,124,93]/2(c[47]/2(a[102,49,50],i12),c[91,124,93]/2(c[47]/2(a[102,49,51],i13),c[91,124,93]/2(c[47]/2(a[102,49,52],i14),c[91,124,93]/2(c[47]/2(a[102,49,53],i15),c[91,124,93]/2(c[47]/2(a[102,49,54],i16),c[91,124,93]/2(c[47]/2(a[102,49,55],i17),c[91,124,93]/2(c[47]/2(a[102,49,56],i18),c[91,124,93]/2(c[47]/2(a[102,49,57],i19),c[91,124,93]/2(c[47]/2(a[102,50,48],i20),c[91,124,93]/2(c[47]/2(a[102,50,49],i21),c[91,124,93]/2(c[47]/2(a[102,50,50],i22),c[91,124,93]/2(c[47]/2(a[102,50,51],i23),c[91,124,93]/2(c[47]/2(a[102,50,52],i24),c[91,124,93]/2(c[47]/2(a[102,50,53],i25),c[91,124,93]/2(c[47]/2(a[102,50,54],i26),c[91,124,93]/2(c[47]/2(a[102,50,55],i27),c[91,124,93]/2(c[47]/2(a[102,50,56],i28),c[91,124,93]/2(c[47]/2(a[102,50,57],i29),c[91,124,93]/2(c[47]/2(a[102,51,48],i30),c[91,124,93]/2(c[47]/2(a[102,51,49],i31),c[91,124,93]/2(c[47]/2(a[102,51,50],i32),c[91,124,93]/2(c[47]/2(a[102,51,51],i33),c[91,124,93]/2(c[47]/2(a[102,51,52],i34),c[91,124,93]/2(c[47]/2(a[102,51,53],i35),c[91,124,93]/2(c[47]/2(a[102,51,54],i36),c[91,124,93]/2(c[47]/2(a[102,51,55],i37),c[91,124,93]/2(c[47]/2(a[102,51,56],i38),c[91,124,93]/2(c[47]/2(a[102,51,57],i39),c[91,124,93]/2(c[47]/2(a[98,105,103],i300),c[91,124,93]/2(c[47]/2(a[102,50],i2),nil))))))))))))))))))))))))))))))))))))))))))) | c[45]/2(a[109,111,100,117,108,101],a[109,52])",
    "inc72" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],a[117,115,101,114]) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[97],i0),nil)) | c[45]/2(a[102,105,108,101],a[47,115,114,99,47,109,53,46,112,108]) | c[45]/2(a[109,111,100,117,108,101],a[109,53])",
    "inc68" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],a[117,115,101,114]) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[98],i1),nil)) | c[45]/2(a[102,105,108,101],a[47,115,114,99,47,109,54,46,112,108]) | c[45]/2(a[109,111,100,117,108,101],a[109,54])",
    "nilcons" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],V0) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(nil,i2),c[91,124,93]/2(c[47]/2(a[91,124,93],i2),nil))) | c[45]/2(a[109,111,100,117,108,101],a[109,55])",
    "ucs" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],a[20013,25991]) | c[45]/2(a[101,120,112,111,114,116,115],nil) | c[45]/2(a[109,111,100,117,108,101],a[955,109])",
    "blobfun" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],V0) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[116,120],i3),nil)) | c[45]/2(a[109,111,100,117,108,101],a[109,56])",
    "latin" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],V0) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[99,97,102,233],i1),nil)) | c[45]/2(a[109,111,100,117,108,101],a[109,57])",
    "nonmodule" => "fail",
    "redef_class" => "fail",
    "two_s" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],a[116,101,115,116]) | c[45]/2(a[101,120,112,111,114,116,115],nil) | c[45]/2(a[109,111,100,117,108,101],a[109,49,49])",
    "cdup_same" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],a[117,115,101,114]) | c[45]/2(a[101,120,112,111,114,116,115],nil) | c[45]/2(a[109,111,100,117,108,101],a[109,49,50])",
    "srcline" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],V0) | c[45]/2(a[101,120,112,111,114,116,115],nil) | c[45]/2(a[102,105,108,101],a[47,115,114,99,47,98,47,109,49,51,46,112,108]) | c[45]/2(a[109,111,100,117,108,101],a[109,49,51])",
    "ints" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],V0) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[122],i0),c[91,124,93]/2(c[47]/2(a[121],i70000),nil))) | c[45]/2(a[109,111,100,117,108,101],a[109,49,52])",
    "bigref" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],V0) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[103,48],i1),c[91,124,93]/2(c[47]/2(a[103,49],i1),c[91,124,93]/2(c[47]/2(a[103,50],i1),c[91,124,93]/2(c[47]/2(a[103,51],i1),c[91,124,93]/2(c[47]/2(a[103,52],i1),c[91,124,93]/2(c[47]/2(a[103,53],i1),c[91,124,93]/2(c[47]/2(a[103,54],i1),c[91,124,93]/2(c[47]/2(a[103,55],i1),c[91,124,93]/2(c[47]/2(a[103,56],i1),c[91,124,93]/2(c[47]/2(a[103,57],i1),c[91,124,93]/2(c[47]/2(a[103,49,48],i1),c[91,124,93]/2(c[47]/2(a[103,49,49],i1),c[91,124,93]/2(c[47]/2(a[103,49,50],i1),c[91,124,93]/2(c[47]/2(a[103,49,51],i1),c[91,124,93]/2(c[47]/2(a[103,49,52],i1),c[91,124,93]/2(c[47]/2(a[103,49,53],i1),c[91,124,93]/2(c[47]/2(a[103,49,54],i1),c[91,124,93]/2(c[47]/2(a[103,49,55],i1),c[91,124,93]/2(c[47]/2(a[103,49,56],i1),c[91,124,93]/2(c[47]/2(a[103,49,57],i1),c[91,124,93]/2(c[47]/2(a[103,50,48],i1),c[91,124,93]/2(c[47]/2(a[103,50,49],i1),c[91,124,93]/2(c[47]/2(a[103,50,50],i1),c[91,124,93]/2(c[47]/2(a[103,50,51],i1),c[91,124,93]/2(c[47]/2(a[103,50,52],i1),c[91,124,93]/2(c[47]/2(a[103,50,53],i1),c[91,124,93]/2(c[47]/2(a[103,50,54],i1),c[91,124,93]/2(c[47]/2(a[103,50,55],i1),c[91,124,93]/2(c[47]/2(a[103,50,56],i1),c[91,124,93]/2(c[47]/2(a[103,50,57],i1),c[91,124,93]/2(c[47]/2(a[103,51,48],i1),c[91,124,93]/2(c[47]/2(a[103,51,49],i1),c[91,124,93]/2(c[47]/2(a[103,51,50],i1),c[91,124,93]/2(c[47]/2(a[103,51,51],i1),c[91,124,93]/2(c[47]/2(a[103,51,52],i1),c[91,124,93]/2(c[47]/2(a[103,51,53],i1),c[91,124,93]/2(c[47]/2(a[103,51,54],i1),c[91,124,93]/2(c[47]/2(a[103,51,55],i1),c[91,124,93]/2(c[47]/2(a[103,51,56],i1),c[91,124,93]/2(c[47]/2(a[103,51,57],i1),c[91,124,93]/2(c[47]/2(a[103,52,48],i1),c[91,124,93]/2(c[47]/2(a[103,52,49],i1),c[91,124,93]/2(c[47]/2(a[103,52,50],i1),c[91,124,93]/2(c[47]/2(a[103,52,51],i1),c[91,124,93]/2(c[47]/2(a[103,52,52],i1),c[91,124,93]/2(c[47]/2(a[103,52,53],i1),c[91,124,93]/2(c[47]/2(a[103,52,54],i1),c[91,124,93]/2(c[47]/2(a[103,52,55],i1),c[91,124,93]/2(c[47]/2(a[103,52,56],i1),c[91,124,93]/2(c[47]/2(a[103,52,57],i1),c[91,124,93]/2(c[47]/2(a[103,53,48],i1),c[91,124,93]/2(c[47]/2(a[103,53,49],i1),c[91,124,93]/2(c[47]/2(a[103,53,50],i1),c[91,124,93]/2(c[47]/2(a[103,53,51],i1),c[91,124,93]/2(c[47]/2(a[103,53,52],i1),c[91,124,93]/2(c[47]/2(a[103,53,53],i1),c[91,124,93]/2(c[47]/2(a[103,53,54],i1),c[91,124,93]/2(c[47]/2(a[103,53,55],i1),c[91,124,93]/2(c[47]/2(a[103,53,56],i1),c[91,124,93]/2(c[47]/2(a[103,53,57],i1),c[91,124,93]/2(c[47]/2(a[103,54,48],i1),c[91,124,93]/2(c[47]/2(a[103,54,49],i1),c[91,124,93]/2(c[47]/2(a[103,54,50],i1),c[91,124,93]/2(c[47]/2(a[103,54,51],i1),c[91,124,93]/2(c[47]/2(a[103,54,52],i1),c[91,124,93]/2(c[47]/2(a[103,54,53],i1),c[91,124,93]/2(c[47]/2(a[103,54,54],i1),c[91,124,93]/2(c[47]/2(a[103,54,55],i1),c[91,124,93]/2(c[47]/2(a[103,54,56],i1),c[91,124,93]/2(c[47]/2(a[103,54,57],i1),c[91,124,93]/2(c[47]/2(a[103,54,53],i1),c[91,124,93]/2(c[47]/2(a[103,48],i1),nil))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))) | c[45]/2(a[109,111,100,117,108,101],a[109,49,53])",
    "b_right" => "true",
    "b_vartag" => "true",
    "b_othertag" => "fail",
    "b_wrongclass" => "fail",
    "b_wrongexports" => "fail",
    "b_extrakey" => "fail",
    "b_nofile" => "fail",
    "b_varclass" => "true",
    "b_openexports" => "true",
    "b_wrongname" => "fail",
    "b_nosrc_right" => "true",
    "b_nosrc_file" => "fail",
    "v_atom" => "fail",
    "v_int" => "fail",
    "v_nil" => "fail",
    "real" => "true tag=a[35] | c[45]/2(a[99,108,97,115,115],a[117,115,101,114]) | c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[43,43,43],i2),c[91,124,93]/2(c[47]/2(a[112],i1),c[91,124,93]/2(c[47]/2(a[113],i2),nil)))) | c[45]/2(a[102,105,108,101],a[47,116,109,112,47,113,108,102,120,47,109,109,46,112,108]) | c[45]/2(a[109,111,100,117,108,101],a[109,109])",
    "missing" => "a[115,111,117,114,99,101,95,115,105,110,107] a[47,110,111,110,101,120,105,115,116,101,110,116,47,122,122,122,46,113,108,102]"
)

# the rows swipl answers (every fixture but the `e_` rows) and the kernel-only error rows
const _QM_ANSWERABLE = sort!(String[k for k in keys(_QM_FIX) if !startswith(k, "e_")])
const _QM_ERRORS = sort!(String[k for k in keys(_QM_FIX) if startswith(k, "e_")])
_qm_body(name::String)::Vector{UInt8} = hex2bytes(_QM_FIX[name][2])
_qm_write(dir::String, name::String)::String =
    _qm_file(dir, name, _QM_FIX[name][1], _qm_body(name))

"The second argument bound before the call: (row, base fixture, :dict with (tag, pairs) or :arg with the term, the Prolog goal text, FILE = the path)."
function _qm_bound_rows()
    pq = _qm_list(_QM[_qm_pi("p", 1), _qm_pi("q", 2)])
    qp = _qm_list(_QM[_qm_pi("q", 2), _qm_pi("p", 1)])
    hash = _qms("#")
    function mkpairs(;
        mod="mm",
        cls=_qms("user"),
        exps=pq,
        file::Union{Nothing, String}="/src/mm.pl",
        extra::Bool=false
    )
        out = _QM[
            _qm_pair("module", _qms(mod)), _qm_pair("class", cls), _qm_pair("exports", exps)
        ]
        file === nothing || push!(out, _qm_pair("file", _qms(file)))
        extra && push!(out, _qm_pair("zz", _qmi(1)))
        return out
    end
    return Tuple{String, String, Symbol, Any, String}[
        ("b_right", "basic", :dict, (hash, mkpairs()),
            "runb(FILE, #, [module-mm, class-user, exports-[p/1,q/2], file-'/src/mm.pl'])"),
        ("b_vartag", "basic", :dict, (_qmv(), mkpairs()),
            "runb(FILE, _, [module-mm, class-user, exports-[p/1,q/2], file-'/src/mm.pl'])"),
        ("b_othertag", "basic", :dict, (_qms("foo"), mkpairs()),
            "runb(FILE, foo, [module-mm, class-user, exports-[p/1,q/2], file-'/src/mm.pl'])"
        ),
        ("b_wrongclass", "basic", :dict, (hash, mkpairs(; cls=_qms("foo"))),
            "runb(FILE, #, [module-mm, class-foo, exports-[p/1,q/2], file-'/src/mm.pl'])"),
        ("b_wrongexports", "basic", :dict, (hash, mkpairs(; exps=qp)),
            "runb(FILE, #, [module-mm, class-user, exports-[q/2,p/1], file-'/src/mm.pl'])"),
        ("b_extrakey", "basic", :dict, (hash, mkpairs(; extra=true)),
            "runb(FILE, #, [module-mm, class-user, exports-[p/1,q/2], file-'/src/mm.pl', zz-1])"
        ),
        ("b_nofile", "basic", :dict, (hash, mkpairs(; file=nothing)),
            "runb(FILE, #, [module-mm, class-user, exports-[p/1,q/2]])"),
        ("b_varclass", "basic", :dict, (hash, mkpairs(; cls=_qmv())),
            "runb(FILE, #, [module-mm, class-_, exports-[p/1,q/2], file-'/src/mm.pl'])"),
        ("b_openexports", "basic", :dict,
            (hash, mkpairs(; exps=_qm_list(_QM[_qm_pi("p", 1)]; tail=_qmv()))),
            "runb(FILE, #, [module-mm, class-user, exports-[p/1|_], file-'/src/mm.pl'])"),
        ("b_wrongname", "basic", :dict, (hash, mkpairs(; mod="xx")),
            "runb(FILE, #, [module-xx, class-user, exports-[p/1,q/2], file-'/src/mm.pl'])"),
        ("b_nosrc_right", "nosrc", :dict,
            (hash, mkpairs(; mod="nn", cls=_qmv(), exps=mk_nil(_QM), file=nothing)),
            "runb(FILE, #, [module-nn, class-_, exports-[]])"),
        ("b_nosrc_file", "nosrc", :dict,
            (hash, mkpairs(; mod="nn", cls=_qmv(), exps=mk_nil(_QM), file="/x")),
            "runb(FILE, #, [module-nn, class-_, exports-[], file-'/x'])"),
        ("v_atom", "basic", :arg, _qms("foo"), "runv(FILE, foo)"),
        ("v_int", "basic", :arg, _qmi(42), "runv(FILE, 42)"),
        ("v_nil", "basic", :arg, mk_nil(_QM), "runv(FILE, [])")
    ]
end

"The kernel's answer of one bound row on the file `path`."
function _qm_bound_call(path::String, kind::Symbol, x)
    kind === :dict && return _qm_call(path; bound=(x[1]::_QM, x[2]::Vector{_QM}))
    return _qm_call(path; arg2=x::_QM)
end

@testset "'\$qlf_module'/2: the pinned table is complete and every answer has the shape the extractor reads" begin
    rows = _qm_bound_rows()
    names = Set(vcat(_QM_ANSWERABLE, String[r[1] for r in rows], ["missing"]))
    @test Set(keys(_QM_PINS)) == names
    @test length(_QM_ANSWERABLE) == 18 && length(_QM_ERRORS) == 18 && length(rows) == 15
    trues = String[v for (k, v) in _QM_PINS if startswith(v, "true tag")]
    @test length(trues) == 16                                    # the answerable rows that load: all but `nonmodule` and `redef_class`
    @test all(startswith("true tag=a[35] | "), trues)            # the tag is `#` (ATOM_dyndict), then the pairs in standard order of the keys
    @test _QM_PINS["nonmodule"] == "fail" && _QM_PINS["redef_class"] == "fail"
    @test count(==("true"), String[_QM_PINS[r[1]] for r in rows]) == 5 &&
        count(==("fail"), String[_QM_PINS[r[1]] for r in rows]) == 10
    # the pairs are the four keys in standard order (class, exports, file, module) or three where the file is missing
    @test all(v -> count(" | ", v) in (3, 4), trues)
end

@testset "'\$qlf_module'/2 answers the module record: the pinned swipl's dict for every fixture (pl-qlf.c qlfModuleInfo, loadXR)" begin
    # UNVERIFIED on the kernel: gate decides
    mktempdir() do d
        got = String[]
        for name in _QM_ANSWERABLE
            r = _qm_call(_qm_write(d, name))
            @test r isa String
            r isa String || continue
            @test r == _QM_PINS[name]                           # both sides through `_qm_enc`
            push!(got, r)
        end
        @test length(got) == length(_QM_ANSWERABLE) && all(!isempty, got)
        @test count(startswith("true tag=a[35]"), got) == 16 && count(==("fail"), got) == 2    # not vacuous: loading rows and failing rows
        # named rows: the exports are Name/Arity in the order of the file; the class is unbound without a `C`; the file is the F entry's name
        @test occursin("c[47]/2(a[112],i1)", _QM_PINS["basic"]) && occursin(
            "a[99,108,97,115,115],a[117,115,101,114])",
            got[findfirst(==("basic"), _QM_ANSWERABLE)]
        )
        @test occursin(
            "c[45]/2(a[99,108,97,115,115],V0)", got[findfirst(==("nosrc"), _QM_ANSWERABLE)]
        )
        @test !occursin("a[102,105,108,101]", got[findfirst(==("nosrc"), _QM_ANSWERABLE)])
        # an XR_REF of two bytes (qlfGetUInt32's second byte): the 132nd id is `g65/1`, the 2nd `g0/1`
        big = got[findfirst(==("bigref"), _QM_ANSWERABLE)]
        @test occursin(
            "c[47]/2(a[103,54,53],i1),c[91,124,93]/2(c[47]/2(a[103,48],i1),nil)", big
        )
        @test count("i1)", big) == 72                            # 70 functors and the two references, no id mixed up
        # a version 99 file loads like version 72 (the reader has no upper bound), a version 68 file has no hash in `F` and an XR include
        ver, hex = _QM_FIX["basic"]
        @test _qm_call(_qm_file(d, "v99", 99, hex2bytes(hex))) == _QM_PINS["basic"]
    end
end

@testset "'\$qlf_module'/2 with the second argument bound: the answer is unified with it (pl-qlf.c qlfModuleInfo ends in PL_unify)" begin
    # UNVERIFIED on the kernel: gate decides
    mktempdir() do d
        rows = _qm_bound_rows()
        files = Dict{String, String}(
            b => _qm_write(d, b) for b in unique(String[r[2] for r in rows])
        )
        got = String[]
        for (name, base, kind, x, _) in rows
            r = _qm_bound_call(files[base], kind, x)
            @test r == _QM_PINS[name]
            push!(got, r isa String ? r : "exception")
        end
        @test length(got) == 15 && all(g -> g in ("true", "fail"), got)
        @test count(==("true"), got) == 5 && count(==("fail"), got) == 10        # both outcomes, so each row can fail
    end
end

@testset "'\$qlf_module'/2 against the live swipl on the same files (when swipl is on PATH)" begin
    if Sys.which("swipl") === nothing
        # the no-swipl branch: the pinned table is the evidence, and says what it pins
        @test length(_QM_PINS) == 34 && _QM_PINS["basic"] != _QM_PINS["nosrc"] &&
            !isempty(_QM_PINS["real"])
    else
        mktempdir() do d
            rows = _qm_bound_rows()
            files = Dict{String, String}(n => _qm_write(d, n) for n in _QM_ANSWERABLE)
            drv = joinpath(d, "drv.pl")
            write(drv, _QM_DRIVER)
            calls = vcat(
                String["run('$(files[n])')" for n in _QM_ANSWERABLE],
                String[replace(r[5], "FILE" => "'$(files[r[2]])'") for r in rows]
            )
            names = vcat(_QM_ANSWERABLE, String[r[1] for r in rows])
            goal = "consult('$drv')," * join(calls, ",")
            out = read(
                pipeline(`swipl -q -g $goal -t halt`; stdin=devnull, stderr=devnull), String
            )
            lines = String.(split(chomp(out), '\n'; keepempty=false))
            @test length(lines) == length(names)
            length(lines) == length(names) || return nothing
            for (n, l) in zip(names, lines)
                @test l == _QM_PINS[n]
                r = if n in _QM_ANSWERABLE
                    _qm_call(files[n])
                else
                    rw = rows[findfirst(x -> x[1] == n, rows)]
                    _qm_bound_call(files[rw[2]], rw[3], rw[4])
                end
                @test r == l                                    # swipl and the kernel, one extractor
            end
        end
    end
end

@testset "'\$qlf_module'/2 errors by name: swipl's texts where it answers, the kernel's where it cannot (loadXRc, qlfLoadError, getBlobType)" begin
    # UNVERIFIED on the kernel: gate decides
    mktempdir() do d
        qfe(f, m) =
            "exc " * _qm_enc(mk_expr(_QM, _QM[_qms("qlf_format_error"), _qms(f), _qms(m)]))
        fmt(p) = "$p: QLF format error at index = "
        # the format error of C's qlfLoadError: swipl ends the process on these files (fatal error) after printing
        # `<path>: QLF format error at index = <n> (src/pl-qlf.c:<line>)`; here an ErrorException with that message
        # (no source position: DIVERGES at qlfLoadError), the index being the number of bytes read, which is the file's size
        for n in (
            "e_srcbyte",
            "e_propbyte",
            "e_inclbyte",
            "e_topbyte",
            "e_unstored",
            "e_zeroref",
            "e_modint",
            "e_missingx"
        )
            p = _qm_write(d, n)
            r = _qm_call(p)
            @test r isa ErrorException
            @test r isa ErrorException && r.msg == fmt(p) * string(filesize(p))
        end
        # the other fatal errors of the reader, swipl's messages
        for (n, want) in (
            ("e_badcode", p -> "Illegal XR entry at index $(filesize(p) - 1): 99"),
            ("e_fileidx", p -> "Illegal XR file index $(filesize(p) - 1): x"),
            ("e_eofdouble", p -> "Unexpected end-of-file in QLT file"),
            (
                "e_eofatom",
                p -> "Unexpected EOF on intermediate code file at offset $(filesize(p))"
            ),
            ("e_eofwide", p -> "Unexpected EOF in UCS atom"),
            ("e_longpath", p -> "Invalid QLF: illegal string")
        )
            p = _qm_write(d, n)
            r = _qm_call(p)
            @test r isa ErrorException
            @test r isa ErrorException && r.msg == want(p)
        end
        # an unknown blob type: swipl ends the process on this input (fatal error); the kernel refuses by name
        r = _qm_call(_qm_write(d, "e_blobtype"))
        @test r isa LK.NotPortedError
        @test r isa LK.NotPortedError && occursin("weird", r.what)
        # swipl reads what is there, or reports a later index: the kernel's text is pinned up to the index
        for n in ("e_funint", "e_negarity", "e_nonatomname")
            p = _qm_write(d, n)
            r = _qm_call(p)
            @test r isa ErrorException
            @test r isa ErrorException && startswith(r.msg, fmt(p))
        end
        @test length(_QM_ERRORS) == 18                         # every e_ fixture is named above: 8 + 6 + 1 + 3
        # the Prolog errors of the header (swipl's own balls, `error(qlf_format_error(File, Message), _)`), same bytes
        ver, hex = _QM_FIX["basic"]
        body = hex2bytes(hex)
        v5 = _qm_file(d, "v5", 5, body)
        badsig = _qm_file(d, "badsig", 72, body; sig=UInt8[1, 2, 3, 4, 0x85])
        badmagic = joinpath(d, "badmagic.qlf")
        write(
            badmagic,
            vcat(collect(codeunits("not a qlf file at all\n\0")), zeros(UInt8, 40))
        )
        empty = joinpath(d, "empty.qlf")
        write(empty, UInt8[])
        magic_only = joinpath(d, "magic_only.qlf")
        write(magic_only, _QM_MAGIC)
        @test _qm_call(v5) == qfe(v5, "incompatible version (file: 5, Prolog: 72)")
        @test _qm_call(badsig) == qfe(
            badsig, "incompatible VM-signature (file: 0xd7bf9f7f; Prolog: 0xe5ee110c)"
        )
        @test _qm_call(badmagic) == qfe(badmagic, "Not a SWI-Prolog .qlf file\n")
        @test _qm_call(empty) == qfe(empty, "Not a SWI-Prolog .qlf file\n")
        @test _qm_call(magic_only) ==
            qfe(magic_only, "incompatible version (file: -64, Prolog: 72)")
        # a file that is missing (swipl: existence_error(source_sink, File)), a file name that is unbound (instantiation error)
        missing_file = "/nonexistent/zzz.qlf"
        @test _QM_PINS["missing"] ==
            _qm_enc(_qms("source_sink")) * " " * _qm_enc(_qms(missing_file))
        @test _qm_call(missing_file) ==
            "exc " * _qm_enc(
            mk_expr(
                _QM, _QM[_qms("existence_error"), _qms("source_sink"), _qms(missing_file)]
            )
        )
        @test _qm_call(_qmv()) == "exc " * _qm_enc(_qms("instantiation_error"))
    end
end

@testset "'\$qlf_module'/2 corruption: the good file answers, every cut of it raises, a flipped property byte raises (a row that can fail)" begin
    # UNVERIFIED on the kernel: gate decides
    mktempdir() do d
        ver, hex = _QM_FIX["basic"]
        body = hex2bytes(hex)
        good = _qm_file(d, "good", ver, body)
        @test _qm_call(good) == _QM_PINS["basic"]
        hl = length(_qm_hdr(good, ver))
        full = read(good)
        @test length(full) == hl + length(body)
        # cuts in the header and a spread of cuts in the body, the last one byte short of the file
        cuts = unique(
            vcat(
                [0, 10, length(_QM_MAGIC), hl - 1, hl],
                round.(Int, range(hl, hl + length(body) - 1; length=24))
            )
        )
        @test length(cuts) >= 20 && maximum(cuts) == length(full) - 1
        raised = Bool[]
        cut = joinpath(d, "cut.qlf")
        for c in cuts
            write(cut, full[1:c])
            r = _qm_call(cut)
            push!(raised, r isa Exception || (r isa String && startswith(r, "exc")))
        end
        @test all(raised) && length(raised) == length(cuts)
        # the C of the class property flipped to Z: a format error where the Z was read (header + 31 bytes of the body + 1)
        pat = "43038875736572"
        @test length(collect(eachmatch(Regex(pat), hex))) == 1
        off = (first(findfirst(pat, hex)) - 1) ÷ 2
        @test off == 31
        flipped = _qm_file(
            d, "flipped", ver, hex2bytes(replace(hex, pat => "5a" * pat[3:end]; count=1))
        )
        r = _qm_call(flipped)
        @test r isa ErrorException
        @test r isa ErrorException &&
            r.msg == "$flipped: QLF format error at index = $(hl + off + 1)"
    end
end

@testset "'\$qlf_module'/2 of a QLF file that has moved: the F entry's name is translated (pushPathTranslation, qlfFixSourcePath)" begin
    # UNVERIFIED on the kernel: gate decides. swipl 10.1.20 (evidence/R2/qlf3_verify.md section 4): saved as `/old/place#/moved.qlf`,
    # loaded from a temporary directory `<dir>`, the source `/old/place#/x/mm.pl` is told as `<dir>/x/mm.pl`; the other pairs are as saved.
    mktempdir() do d
        body = hex2bytes(
            "514d03846d6d46a62f6f6c642f706c616365232f782f6d6d2e706c724081000000000000f83f75864303887573657245040382708258"
        )
        moved = joinpath(d, "moved.qlf")
        write(moved, vcat(_qm_hdr("/old/place#/moved.qlf"), body))
        same = _qm_file(d, "same", 72, body)                    # saved under its own name: no translation, the saved path stays
        cls = "c[45]/2(a[99,108,97,115,115],a[117,115,101,114])"
        exps = "c[45]/2(a[101,120,112,111,114,116,115],c[91,124,93]/2(c[47]/2(a[112],i1),nil))"
        mod = "c[45]/2(a[109,111,100,117,108,101],a[109,109])"
        file(f) = _qm_enc(_qm_pair("file", _qms(f)))
        want(f) = "true tag=a[35] | $cls | $exps | $(file(f)) | $mod"
        r = _qm_call(moved; translated=true)
        @test r == want(joinpath(d, "x", "mm.pl"))
        r2 = _qm_call(same; translated=true)
        @test r2 == want("/old/place#/x/mm.pl")
        @test r isa String && r2 isa String && r != r2          # the translation is what tells them apart
    end
end
