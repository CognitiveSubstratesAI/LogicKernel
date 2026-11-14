# ORIGINAL: QLFROWS's rows — the upstream test is tests/save/test_qlf.pl (swipl-devel 18168e62), testset `qlf_staleness`: whether a .qlf file is
# out of date (boot/init.pl `'$qlf_out_of_date'/3`, `'$qlf_sources_changed'/3`, `'$qlf_source_changed'/3`) over the kernel's `'$qlf_sources'/2`,
# `'$file_hash'/2`, `time_file/2`, `access_file/2`. UNRUN: no Julia was run when this file was written. Rows marked
# `# UNVERIFIED on the kernel: gate decides` are the C code's behaviour, not yet seen on the kernel.
# test/files/test_qlf_stale_swipl.jl — prefix `_QS` / `_qs_`:
#   * Upstream builds its .qlf files with `qcompile/1` (the QLF writer: `$open_wic`, `$qlf_open`: refused by name here), so each case builds the
#     .qlf file BYTE BY BYTE like test_qlf_swipl.jl's `_ql_qlf` (the header saved as the file's own path, the file index at the end, no body: `$qlf_sources/2`
#     reads only those) and sets the times with `touch -d @<seconds>` (upstream's `touch/3` uses set_time_file/3 of library(filesex)).
#   * The Prolog under test is the PIN's boot/init.pl text, copied as is (`_QS_BOOT`: lines 2433-2495 and `'$member'/2`) and compiled by `compileFile`
#     in the boot session; `qs_why/3` and `qs_hash/3` (`_QS_HELPER`) turn the answer into one term, the SAME text runs on the pinned swipl.
#   * The pins (`_QSCase.pin`) are the pinned swipl's (10.1.20, 18168e62) answers on the same bytes, two runs byte-identical
#     (evidence/R2/qlf3rows_work/qs_cases.py); with `swipl` on PATH the live answers are compared with the pins too.
#   * Each testset ends with three CORRUPTIONS: an input that is wrong in one place and whose answer differs from its clean sibling's.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — `$qlf_sources`/`$file_hash` and the boot compilation (src/pl-qlf.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _QS = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_qss(x) = lk_sym(_QS, Symbol(x))
_qsv() = mk_var(_QS, LK.fresh_var_keys!(1))

const _QS_Q0 = 1700000000                           # the time of every .qlf file (seconds); a source gets Q0 plus its offset
const _QS_MAGIC = collect(codeunits("SWI-Prolog .qlf file\n\0"))
const _QS_SIG = UInt8[0x18, 0x44, 0x70, 0x5e, 0x9c]  # VM_SIGNATURE 0xe5ee110c, as the pinned swipl writes it
const _QS_TXT = Dict{Symbol, String}(
    :a42 => "answer(42).\n", :a43 => "answer(43).\n", :p1 => "part(1).\n", :p2 => "part(2).\n",
    :d1 => "% what the compiled file copied\n", :d2 => "% a change to what was copied\n"
)
const _QS_ORIG = Dict{Symbol, Symbol}(:pl => :a42, :part => :p1, :dep => :d1, :other => :a42)  # the content each role had when "compiled"
const _QS_OTHER = "/nonexistent/qs/other.pl"

"The zig-zag, 7 bits per byte (little end first, the last byte has bit 0x80) encoding of `v` (`qlfPutInt64`)."
function _qs_zz(v::Int64)::Vector{UInt8}
    n = (reinterpret(UInt64, v) << 1) ⊻ reinterpret(UInt64, v >> 63)
    out = UInt8[]
    while n >= 0x80
        push!(out, UInt8(n & 0x7f))
        n >>= 7
    end
    push!(out, UInt8(n) | 0x80)
    return out
end
_qs_str(s::String)::Vector{UInt8} = vcat(_qs_zz(Int64(ncodeunits(s))), collect(codeunits(s)))
_qs_be4(n::Int)::Vector{UInt8} = UInt8[(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]
_qs_hdr(save::String)::Vector{UInt8} = vcat(_QS_MAGIC, _qs_zz(Int64(72)), _QS_SIG, _qs_str(save))
"FNV-1a, 64 bit (pl-qlf.c hashStreamContent), over the bytes of a source."
function _qs_fnv(b::Vector{UInt8})::UInt64
    h = 0xcbf29ce484222325
    for c in b
        h = (h ⊻ UInt64(c)) * 0x00000100000001b3
    end
    return h
end

# one case: what the .qlf file records (entries: kind F/L/D, the role of the file, the recorded hash: :ok, :zero, :flip), the three files
# (content symbol or :none, time offset from Q0), the variant of the .qlf file (:good, :sig, :notqlf, :cut, :missing) and swipl's answer
struct _QSCase
    name::String
    kind::Symbol
    entries::Vector{Tuple{Char, Symbol, Symbol}}
    pl::Tuple{Symbol, Int}
    part::Tuple{Symbol, Int}
    dep::Tuple{Symbol, Int}
    qlf::Symbol
    pin::String
end

const _QS_CASES = _QSCase[
    _QSCase("hash_recorded", :hash, [('F', :pl, :ok)], (:a42, -100), (:none, 0), (:none, 0), :good,
            "same"),  # same
    _QSCase("hash_recorded_flipped", :hash, [('F', :pl, :flip)], (:a42, -100), (:none, 0), (:none, 0), :good,
            "differ"),  # differ
    _QSCase("hash_recorded_other_name", :hash, [('F', :other, :ok)], (:a42, -100), (:none, 0), (:none, 0), :good,
            "differ"),  # differ
    _QSCase("hash_recorded_zero", :hash, [('F', :pl, :zero)], (:a42, -100), (:none, 0), (:none, 0), :good,
            "differ"),  # differ
    _QSCase("newer_unchanged", :stale, [('F', :pl, :ok)], (:a42, 10), (:none, 0), (:none, 0), :good,
            "no"),  # no
    _QSCase("changed_newer", :stale, [('F', :pl, :ok)], (:a43, 10), (:none, 0), (:none, 0), :good,
            "old"),  # old
    _QSCase("changed_one_second_later", :stale, [('F', :pl, :ok)], (:a43, 1), (:none, 0), (:none, 0), :good,
            "old"),  # old
    _QSCase("changed_same_second", :stale, [('F', :pl, :ok)], (:a43, 0), (:none, 0), (:none, 0), :good,
            "no"),  # no
    _QSCase("changed_but_older", :stale, [('F', :pl, :ok)], (:a43, -5), (:none, 0), (:none, 0), :good,
            "no"),  # no
    _QSCase("hash_zero_newer", :stale, [('F', :pl, :zero)], (:a42, 10), (:none, 0), (:none, 0), :good,
            "old"),  # old
    _QSCase("hash_flipped_newer", :stale, [('F', :pl, :flip)], (:a42, 10), (:none, 0), (:none, 0), :good,
            "old"),  # old
    _QSCase("pl_under_another_name", :stale, [('F', :other, :ok)], (:a43, 10), (:none, 0), (:none, 0), :good,
            "old"),  # old
    _QSCase("dep_changed", :stale, [('F', :pl, :ok), ('D', :dep, :ok)], (:a42, -100), (:none, 0), (:d2, 1), :good,
            "old"),  # old
    _QSCase("dep_touched", :stale, [('F', :pl, :ok), ('D', :dep, :ok)], (:a42, -100), (:none, 0), (:d1, 10), :good,
            "no"),  # no
    _QSCase("dep_changed_older", :stale, [('F', :pl, :ok), ('D', :dep, :ok)], (:a42, -100), (:none, 0), (:d2, -1), :good,
            "no"),  # no
    _QSCase("consulted_changed", :stale, [('F', :pl, :ok), ('F', :part, :ok)], (:a42, -100), (:p2, 1), (:none, 0), :good,
            "old"),  # old
    _QSCase("consulted_touched", :stale, [('F', :pl, :ok), ('F', :part, :ok)], (:a42, -100), (:p1, 10), (:none, 0), :good,
            "no"),  # no
    _QSCase("consulted_missing", :stale, [('F', :pl, :ok), ('F', :part, :ok)], (:a42, -100), (:none, 0), (:none, 0), :good,
            "no"),  # no
    _QSCase("included_changed", :stale, [('F', :pl, :ok), ('L', :part, :ok)], (:a42, -100), (:p2, 1), (:none, 0), :good,
            "old"),  # old
    _QSCase("included_touched", :stale, [('F', :pl, :ok), ('L', :part, :ok)], (:a42, -100), (:p1, 10), (:none, 0), :good,
            "no"),  # no
    _QSCase("pl_unreadable", :stale, [('F', :pl, :ok)], (:none, 0), (:none, 0), (:none, 0), :good,
            "no"),  # no
    _QSCase("vm_signature_changed", :stale, [('F', :pl, :ok)], (:a42, -100), (:none, 0), (:none, 0), :sig,
            "qfe:[105,110,99,111,109,112,97,116,105,98,108,101,32,86,77,45,115,105,103,110,97,116,117,114,101,32,40,102,105,108,101,58,32,48,120,101,100,101,101,49,49,48,99,59,32,80,114,111,108,111,103,58,32,48,120,101,53,101,101,49,49,48,99,41]"),  # qfe:'incompatible VM-signature (file: 0xedee110c; Prolog: 0xe5ee110c)'
    _QSCase("vm_signature_and_source", :stale, [('F', :pl, :ok)], (:a43, 10), (:none, 0), (:none, 0), :sig,
            "qfe:[105,110,99,111,109,112,97,116,105,98,108,101,32,86,77,45,115,105,103,110,97,116,117,114,101,32,40,102,105,108,101,58,32,48,120,101,100,101,101,49,49,48,99,59,32,80,114,111,108,111,103,58,32,48,120,101,53,101,101,49,49,48,99,41]"),  # qfe:'incompatible VM-signature (file: 0xedee110c; Prolog: 0xe5ee110c)'
    _QSCase("not_a_qlf_file", :stale, [('F', :pl, :ok)], (:a42, -100), (:none, 0), (:none, 0), :notqlf,
            "qfe:[78,111,116,32,97,32,83,87,73,45,80,114,111,108,111,103,32,46,113,108,102,32,102,105,108,101,10]"),  # qfe:'Not a SWI-Prolog .qlf file/n'
    _QSCase("cut_in_magic", :stale, [('F', :pl, :ok)], (:a42, -100), (:none, 0), (:none, 0), :cut,
            "qfe:[78,111,116,32,97,32,83,87,73,45,80,114,111,108,111,103,32,46,113,108,102,32,102,105,108,101,10]"),  # qfe:'Not a SWI-Prolog .qlf file/n'
    _QSCase("no_qlf_file", :stale, [('F', :pl, :ok)], (:a42, -100), (:none, 0), (:none, 0), :missing,
            "err:existence_error/2"),  # err:existence_error/2
]

# the pin's Prolog, copied as is: boot/init.pl 2433-2495 and `'$member'/2` (4419-4424)
const _QS_BOOT = raw"""
'$qlf_out_of_date'(PlFile, QlfFile, Why) :-
    (   access_file(PlFile, read)
    ->  Error = error(Formal,_),
	catch('$qlf_sources'(QlfFile, Sources), Error, true),
	(   nonvar(Formal)              % QlfFile is incompatible
	->  Why = Error
	;   time_file(QlfFile, QlfTime),
	    '$qlf_sources_changed'(PlFile, Sources, QlfTime)
	->  Why = old                   % a source changed
	;   fail                        % QlfFile is up-to-date and ok
	)
    ;   fail                            % can not read .pl; try .qlf
    ).

%!  '$qlf_sources_changed'(+PlFile, +Sources, +QlfTime) is semidet.
%
%   True when PlFile or one of the other Sources of a .qlf file
%   written at QlfTime changed.  PlFile is asked explicitly as it
%   may appear under another name in Sources.  Sources that no longer
%   exist are ignored.

'$qlf_sources_changed'(PlFile, Sources, QlfTime) :-
    '$qlf_source_changed'(PlFile, Sources, QlfTime),
    !.
'$qlf_sources_changed'(PlFile, Sources, QlfTime) :-
    '$member'(Source, Sources),
    arg(1, Source, File),
    File \== PlFile,
    '$qlf_source_changed'(File, Sources, QlfTime),
    !.

%!  '$qlf_source_changed'(+File, +Sources, +QlfTime) is semidet.
%
%   True when the content of File differs from the copy that was
%   compiled into the .qlf file.  The modification time is cheap to
%   ask, but proves nothing: a tree that arrives by checkout, copy,
%   unpack or install carries times of its own, in either direction and
%   at the resolution of the file system it landed on.  So, if the time
%   says File may be newer, the hash the .qlf file records for File in
%   Sources settles it.
%
%   If Sources records no hash for File -- the .qlf file was written by
%   an older version, or File could not be read when it was compiled --
%   the times have the last word, as they had before.
%
%   Note that a file edited in the second its .qlf file was written has
%   the time of that file, so the times do not say "may be newer" and the
%   content is never asked. Loading every .pl file to find out would cost
%   more than it is worth here; qlf_needs_rebuild/1 of
%   library(prolog_qlfmake), which is what a build asks, does compare the
%   content of every source.

'$qlf_source_changed'(File, Sources, QlfTime) :-
    catch(time_file(File, Time), error(_,_), fail),
    Time > QlfTime,
    (   '$member'(Source, Sources),
	arg(1, Source, File),
	arg(2, Source, Hash),
	Hash =\= 0
    ->  \+ '$file_hash'(File, Hash)
    ;   true
    ).

'$member'(El, [H|T]) :-
    '$member_'(T, El, H).

'$member_'(_, El, El).
'$member_'([H|T], El, _) :-
    '$member_'(T, El, H).
"""
const _QS_HELPER = raw"""
qs_why(Pl, Qlf, R) :-
    (   '$qlf_out_of_date'(Pl, Qlf, Why)
    ->  (   Why == old
        ->  R = old
        ;   Why = error(qlf_format_error(_, Msg), _)
        ->  R = qfe(Msg)
        ;   Why = error(F, _)
        ->  functor(F, N, A), R = err(N, A)
        ;   R = other
        )
    ;   R = no
    ).
qs_hash(Pl, Qlf, R) :-
    '$qlf_sources'(Qlf, Sources),
    (   '$member'(source(Pl, H), Sources), H =\= 0, '$file_hash'(Pl, H)
    ->  R = same
    ;   R = differ
    ).
"""
const _QS_SHOW = raw"""
qs_show(qfe(M)) :- !, atom_codes(M, Cs), write('qfe:'), write(Cs).
qs_show(err(N, A)) :- !, write('err:'), write(N), write('/'), write(A).
qs_show(R) :- write(R).
qs_one(Kind, Pl, Qlf) :-
    (   Kind == stale -> qs_why(Pl, Qlf, R) ; qs_hash(Pl, Qlf, R) ),
    qs_show(R), nl.
"""

_qs_touch(path::String, off::Int) = run(`touch -d @$(_QS_Q0 + off) $path`)

"Build the case in the directory `d`: the paths of the .pl file and of the .qlf file."
function _qs_build(c::_QSCase, d::String)::Tuple{String, String}
    mkpath(d)
    paths = Dict{Symbol, String}(
        :pl => joinpath(d, "s.pl"), :part => joinpath(d, "part.pl"), :dep => joinpath(d, "dep.pl"),
        :other => _QS_OTHER
    )
    for (r, (content, off)) in ((:pl, c.pl), (:part, c.part), (:dep, c.dep))
        content === :none && continue
        write(paths[r], _QS_TXT[content])
        _qs_touch(paths[r], off)
    end
    qlf = joinpath(d, "s.qlf")
    c.qlf === :missing && return paths[:pl], qlf
    f = _qs_hdr(qlf)
    offs = Int[]
    for (k, role, hm) in c.entries
        push!(offs, length(f))
        h = _qs_fnv(collect(codeunits(_QS_TXT[_QS_ORIG[role]])))
        h = hm === :zero ? UInt64(0) : hm === :flip ? h ⊻ UInt64(1) : h
        f = vcat(f, UInt8[UInt8(k)], _qs_str(paths[role]), _qs_zz(reinterpret(Int64, h)))
    end
    f = vcat(f, (_qs_be4(o) for o in offs)..., _qs_be4(length(offs)))
    if c.qlf === :sig                                  # upstream's change_vm_signature/1: bit 0 of the last byte of the signature
        f[length(_QS_MAGIC) + length(_qs_zz(Int64(72))) + 5] ⊻= 0x01
    elseif c.qlf === :notqlf
        f = collect(codeunits("not a qlf file\n"))
    elseif c.qlf === :cut
        f = f[1:10]
    end
    write(qlf, f)
    _qs_touch(qlf, 0)
    return paths[:pl], qlf
end

_qs_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"The answer term of `qs_why/3` / `qs_hash/3` as swipl's `qs_show/1` writes it."
function _qs_show(t::_QS)::String
    k = kind(t)
    k === SYM && return String(sym_text(t))
    k === GND && return string(lk_value(t))
    k === VAR && return "_"
    h = String(sym_text(child(t, 1)))
    n = nchildren(t) - 1
    h == "qfe" && n == 1 && return "qfe:" * _qs_codes(String(sym_text(child(t, 2))))
    h == "err" && n == 2 && return "err:" * _qs_show(child(t, 2)) * "/" * _qs_show(child(t, 3))
    return "?" * h
end

"One goal on the `system` predicate `name/length(args)`: its status (:true, :false, :exception) and, for :true, the arguments as answered (`ans[k + 1]` is argument k)."
function _qs_goal(gd, ld, name::String, args::Vector)
    proc = LK.isCurrentProcedure(sym_key(_qss(name)), length(args), LK.MODULE_system(gd))
    proc === nothing && return (:undefined, _QS[])
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, max(length(args), 1))
    for (i, v) in enumerate(args)
        LK.putSlotValue!(ld, a + i, v, LK.PutVarMap())
    end
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a)
    status = :false
    ans = _QS[]
    rc = LK.PL_next_solution(gd, ld, qid)
    if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        status = :true
        ans = [lk_answer(ld, a + i - 1) for i in 1:length(args)]
        pushfirst!(ans, _qss("goal"))
    elseif rc == LK.PL_S_EXCEPTION
        status = :exception
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return (status, ans)
end

"A kernel database with the pin's `'$qlf_out_of_date'/3` and the two helpers compiled in the boot session: the database, its local data, `compileFile`'s result."
function _qs_boot()
    gd = LK.PL_global_data{_QS}()
    ld = LK.PL_local_data{_QS}(gd)
    f = joinpath(mktempdir(), "qs_boot.pl")
    write(f, _QS_BOOT * _QS_HELPER)
    gd.bootsession = true
    ok = LK.compileFile(gd, ld, nothing, f)
    gd.bootsession = false
    return gd, ld, ok
end

"The kernel's answer for every case, by name (built in `d`, one directory each)."
function _qs_run_all(d::String)
    gd, ld, ok = _qs_boot()
    got = Dict{String, String}()
    for c in _QS_CASES
        pl, qlf = _qs_build(c, joinpath(d, c.name))
        got[c.name] = try
            st, ans = _qs_goal(gd, ld, c.kind === :stale ? "qs_why" : "qs_hash", _QS[_qss(pl), _qss(qlf), _qsv()])
            st === :true ? _qs_show(ans[4]) : "<" * string(st) * ">"
        catch e
            "<julia: " * sprint(showerror, e) * ">"
        end
    end
    return ok, got
end
const _QS_PIN = Dict{String, String}(c.name => c.pin for c in _QS_CASES)

@testset "qlf_staleness: the table of cases is the upstream testset's, each with swipl's answer (tests/save/test_qlf.pl)" begin
    @test length(_QS_CASES) == 26
    @test length(unique(c.name for c in _QS_CASES)) == length(_QS_CASES)
    @test all(c -> !isempty(c.pin), _QS_CASES)
    # not vacuous: the pins say yes, no, old, a format error, an error of another kind
    pins = Set(c.pin for c in _QS_CASES)
    @test "no" in pins && "old" in pins && "same" in pins && "differ" in pins
    @test count(startswith("qfe:"), pins) == 2 && count(startswith("err:"), pins) == 1
    # the helper text holds the pin's three predicates and the member helper
    @test all(occursin(s, _QS_BOOT) for s in ("'\$qlf_out_of_date'(PlFile", "'\$qlf_sources_changed'(PlFile, Sources, QlfTime) :-", "'\$qlf_source_changed'(File, Sources, QlfTime) :-", "'\$member_'(T, El, H)"))
    mktempdir() do d
        c = first(c for c in _QS_CASES if c.name == "newer_unchanged")
        pl, qlf = _qs_build(c, d)
        # the touch is exact: the source is Q0 + 10 s, the .qlf file Q0 (a rounding there would turn every time row into another)
        @test mtime(pl) == _QS_Q0 + 10 && mtime(qlf) == _QS_Q0
        bytes = read(qlf)
        @test bytes[1:length(_QS_MAGIC)] == _QS_MAGIC && bytes[end - 3:end] == _qs_be4(1)
    end
end

const _QS_RUN = try
    mktempdir() do d
        _qs_run_all(d)
    end
catch e
    (false, Dict{String, String}("<error>" => sprint(showerror, e)))
end

@testset "qlf_staleness: the pin's Prolog compiles in the boot session and its three predicates and the helpers exist (UNVERIFIED on the kernel: gate decides)" begin
    @test _QS_RUN[1]
    @test length(_QS_RUN[2]) == length(_QS_CASES)
    @test all(v -> !startswith(v, "<"), values(_QS_RUN[2]))      # no case ended in an exception, a failure or an undefined helper
end

"Compare the kernel's answers for `names` with the pins, one row per case."
function _qs_rows(names::Vector{String})
    for n in names
        @test get(_QS_RUN[2], n, "<none>") == _QS_PIN[n]
    end
end

@testset "qlf_staleness: the hash recorded for a source is the hash of the file (the_hash_recorded_for_a_source_is_the_hash_of_the_file)" begin
    # UNVERIFIED on the kernel: gate decides. Upstream reads a file written by qcompile/1; here the recorded hash is the FNV-1a of the source,
    # built by `_qs_fnv` (checked against the pinned swipl's `$file_hash`: the case says `same`)
    _qs_rows(["hash_recorded"])
    @test _QS_PIN["hash_recorded"] == "same"
    # three corruptions: one bit of the recorded hash flipped, a recorded hash of 0, the source recorded under another name: none is `same`
    for n in ("hash_recorded_flipped", "hash_recorded_zero", "hash_recorded_other_name")
        @test get(_QS_RUN[2], n, "<none>") == "differ"
        @test _QS_PIN[n] == "differ" && _QS_PIN[n] != _QS_PIN["hash_recorded"]
    end
end

@testset "qlf_staleness: a newer source is out of date only if its content changed (a_source_that_is_newer_but_unchanged..., and_one_whose_content_changed_is)" begin
    # UNVERIFIED on the kernel: gate decides
    _qs_rows(["newer_unchanged", "changed_newer", "changed_one_second_later", "changed_same_second", "changed_but_older", "pl_unreadable"])
    # the clean sibling says `no` (newer and unchanged); a changed one 1 s newer says `old`; the same time or an older one says `no` (the time says the file cannot be newer)
    @test _QS_PIN["newer_unchanged"] == "no" && _QS_PIN["changed_newer"] == "old" && _QS_PIN["changed_same_second"] == "no"
    @test get(_QS_RUN[2], "changed_one_second_later", "<none>") == "old"
    # three corruptions of the recorded hash and of the name: each turns the clean `no` into `old` (the hash no longer settles it, the times do)
    _qs_rows(["hash_zero_newer", "hash_flipped_newer", "pl_under_another_name"])
    for n in ("hash_zero_newer", "hash_flipped_newer", "pl_under_another_name")
        @test get(_QS_RUN[2], n, "<none>") == "old" && get(_QS_RUN[2], n, "<none>") != get(_QS_RUN[2], "newer_unchanged", "<none>")
    end
end

@testset "qlf_staleness: dependencies, consulted and included files (loading_finds_a_changed_dependency/consulted_file/included_file, but_not_one_that_was_only_touched)" begin
    # UNVERIFIED on the kernel: gate decides
    _qs_rows(["dep_changed", "dep_touched", "dep_changed_older", "consulted_changed", "consulted_touched", "consulted_missing", "included_changed", "included_touched"])
    @test _QS_PIN["dep_changed"] == "old" && _QS_PIN["consulted_changed"] == "old" && _QS_PIN["included_changed"] == "old"
    # three corruptions, each against its changed sibling: touched only (a newer time, the same content), older than the .qlf file, a source that is gone
    for (bad, good) in (("dep_touched", "dep_changed"), ("consulted_touched", "consulted_changed"), ("included_touched", "included_changed"),
                        ("dep_changed_older", "dep_changed"), ("consulted_missing", "consulted_changed"))
        @test get(_QS_RUN[2], bad, "<none>") == "no"
        @test get(_QS_RUN[2], bad, "<none>") != get(_QS_RUN[2], good, "<none>")
    end
end

@testset "qlf_staleness: a .qlf file of another VM, or none, is reported before the sources are looked at (a_qlf_file_of_another_vm_is_incompatible, also_if_its_source_changed, a_file_that_is_no_qlf_file_is_out_of_date)" begin
    # UNVERIFIED on the kernel: gate decides
    _qs_rows(["vm_signature_changed", "vm_signature_and_source", "not_a_qlf_file", "cut_in_magic", "no_qlf_file"])
    @test _QS_PIN["vm_signature_changed"] == _QS_PIN["vm_signature_and_source"]      # the source does not matter
    @test startswith(_QS_PIN["vm_signature_changed"], "qfe:") && startswith(_QS_PIN["not_a_qlf_file"], "qfe:")
    # three corruptions of one file: the signature, the whole file, the cut file: each differs from the clean `no`
    for n in ("vm_signature_changed", "not_a_qlf_file", "cut_in_magic", "no_qlf_file")
        @test get(_QS_RUN[2], n, "<none>") != get(_QS_RUN[2], "newer_unchanged", "<none>")
        @test !startswith(get(_QS_RUN[2], n, "<none>"), "<")
    end
    # swipl's two messages, whole: the signature of the file (bit 0 of its last byte flipped) and the one of this VM; the text of a file that is no .qlf file
    @test _QS_PIN["vm_signature_changed"] == "qfe:" * _qs_codes("incompatible VM-signature (file: 0xedee110c; Prolog: 0xe5ee110c)")
    @test _QS_PIN["not_a_qlf_file"] == "qfe:" * _qs_codes("Not a SWI-Prolog .qlf file\n")
end

@testset "qlf_staleness: the live swipl gives the same answers on the same files (when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "QLFROWS LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        mktempdir() do d
            calls = String[]
            for c in _QS_CASES
                pl, qlf = _qs_build(c, joinpath(d, "live_" * c.name))
                push!(calls, "qs_one($(c.kind), '$pl', '$qlf')")
            end
            drv = joinpath(d, "drv.pl")
            write(drv, _QS_HELPER * _QS_SHOW * ":- initialization((" * join(calls, ", ") * ", halt)).\n")
            out = read(pipeline(`swipl -q $drv`; stdin=devnull, stderr=devnull), String)
            lines = String.(split(chomp(out), '\n'; keepempty=false))
            @test length(lines) == length(_QS_CASES)
            length(lines) == length(_QS_CASES) || return
            for (c, l) in zip(_QS_CASES, lines)
                @test l == c.pin
                @test get(_QS_RUN[2], c.name, "<none>") == l            # swipl and the kernel
            end
        end
    end
end
