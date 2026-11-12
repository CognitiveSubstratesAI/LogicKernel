# ORIGINAL: a differential of pl-zip.c's predicates (zip_open_stream/3, zip_clone/2, zip_close_/2, zip_lock/1, zip_unlock/1, zipper_goto/2,
# zipper_open_current/3, zip_file_info_/3) against swipl at the pin; test/core_lang/test_prof_swipl.jl's harness
# test/core_lang/test_zip1_swipl.jl — through a PROGRAM: test_zip1_swipl.pl holds the rows, each a predicate `tN(R)`; the kernel consults it and
# enumerates every solution of every row, and its lines are compared with test_zip1_swipl.out — swipl 10.1.20's own (the pin's), printed by the
# driver below. When `swipl` is on PATH the .out is checked against a live run as well. No zipper can be made in the kernel (no zip reader or
# deflate), so the rows hand a term that is no zipper, or a bad option list or stream, to the predicates: the answers are the pin's for such
# arguments. KERNEL-ONLY testsets: the rows `kN` ('$rc_handle'/1 fails here, the pin succeeds), the rows `krN` and the Julia-level calls end in
# the named refusal (NotPortedError, step ZIP1), checked with the refusal's culprit and text. UNTESTED when written: nothing compiled
# (lane F, pl-zip).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
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

const _ZP_PL = joinpath(@__DIR__, "test_zip1_swipl.pl")
const _ZP_OUT = joinpath(@__DIR__, "test_zip1_swipl.out")

# the rows' names, in the order of the program (`t` for the swipl rows, `k` for the kernel-only rows, `kr` for the refusals)
_zp_names(prefix::String) =
    unique([
        String(m[1]) for m in
        eachmatch(Regex("^(" * prefix * "\\d+)\\(R\\) :-", "m"), read(_ZP_PL, String))
    ])
# the kernel's lines: `ok` (the program loaded), then each row's name and solutions; `setup` runs
# after the load, before the rows. Returns the lines and the run's local data (the last row's
# query stays open after a named refusal: the data is thrown away).
function kernel_run(
    ::Type{T}, path::String, names::Vector{String}, setup::Function=(gd, ld) -> nothing
)::Tuple{Vector{String}, LK.PL_local_data{T}} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    setup(gd, ld)
    out = [st === :ok ? "ok" : "exc " * enc(ball::T)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        notported = false
        while (n += 1) <= 100
            rc = try
                LK.PL_next_solution(gd, ld, qid)
            catch e
                e isa LK.NotPortedError || rethrow()
                notported = true
                break
            end
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(T, T[_tls(T, name), lk_answers(ld, (a:a)...)...]))
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
        if notported
            push!(out, "$name notported")    # the query stays open: the caller drops `ld`
            return out, ld
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, ld
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
        run = ":- initialization((fz_run('$path', [" * join(names, ",") * "]), halt)).\n"
        write(f, DRIVER * run)
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# ONE extractor for both sides: how many times a line holds an atom (as `enc` writes it)
_zp_count(lines, word) = sum(l -> length(findall(_codes(word), l)), lines; init=0)

@testset "ZIP1: pl-zip.c's predicates on non-zippers and bad options == the .out" begin
    names = _zp_names("t")
    expected = String.(readlines(_ZP_OUT))
    # not a vacuous agreement: the .out has `ok` and a line per row, and the rows' evidence
    @test names == ["t$i" for i in 0:70]
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    body = expected[2:end]
    words = (
        "type_error", "instantiation_error", "domain_error", "existence_error", "zipper",
        "bool", "list", "stream", "encoding", "stream_option", "type", "blob"
    )
    for w in words
        @test _zp_count(body, w) >= 1
    end
    @test _zp_count(body, "zipper") >= 30
    kl, ld = kernel_run(_TL, _ZP_PL, names)
    @test length(kl) == length(expected)
    for w in words
        @test _zp_count(kl[2:min(end, length(expected))], w) == _zp_count(body, w)
    end
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "ZIP1 DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked)."
    else
        @test swipl_lines(_ZP_PL, names) == expected      # the .out is swipl's, still
    end
end

_a(s) = "a" * _codes(s)
_c(f, args...) = "c" * _codes(f) * "/$(length(args))(" * join(args, ",") * ")"
_row(name, sols...) = name * join(" " .* [_c(name, s) for s in sols])

# the kernel opens no resource database: '$rc_handle'/1 fails (the pin answers the zipper blob
# of its boot archive)
@testset "ZIP1: '\$rc_handle'/1 fails (kernel-only: the pin succeeds)" begin
    names = _zp_names("k")
    @test names == ["k0", "k1"]
    kl, ld = kernel_run(_TL, _ZP_PL, names)
    @test kl == ["ok", _row("k0", _a("failed")), _row("k1", _a("no"))]
end

# what a refusal row raises: (culprit text, what, step), or nothing without a NotPortedError
function refusal_of(::Type{T}, row::String) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, _ = LK.load_file!(gd, ld, _ZP_PL)
    @assert st === :ok
    proc = LK.isCurrentProcedure(sym_key(_tls(T, row)), 1, LK.MODULE_user(gd))
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    try
        LK.PL_next_solution(gd, ld, qid)
    catch e
        e isa LK.NotPortedError || rethrow()
        return (sym_text(e.culprit), e.what, e.step)
    end
    return nothing
end

# `r` is a refusal of `culprit` at step ZIP1 whose text starts with `prefix`
_zp_is(r, culprit, prefix) =
    r !== nothing && r[1] == culprit && startswith(r[2], prefix) && r[3] == "ZIP1"

# no zipper can be made: what reaches minizip is a named refusal, at the place upstream's first
# minizip call stands
@testset "ZIP1: zip_open_stream/3 and zipper_open_new_file_in_zip/4 are refused" begin
    for row in ("kr0", "kr1", "kr2", "kr3", "kr4", "kr5", "kr6")
        kl, ld = kernel_run(_TL, _ZP_PL, [row])
        @test kl == ["ok", "$row notported"]
    end
    # an output stream: the writer (zipOpen2_64, upstream's branch of SIO_OUTPUT); an input
    # stream: the reader (unzOpen2_64)
    for row in ("kr0", "kr2")
        @test _zp_is(refusal_of(_TL, row), "zip_open_stream", "zipOpen2_64")
    end
    @test _zp_is(refusal_of(_TL, "kr1"), "zip_open_stream", "unzOpen2_64")
    # zipper_open_new_file_in_zip/4 refuses at entry: before the zipper, whatever the arguments
    entry = "a zip entry writer"
    for row in ("kr3", "kr4", "kr5", "kr6")
        @test _zp_is(refusal_of(_TL, row), "zipper_open_new_file_in_zip", entry)
    end
end

# the three refusals that are Julia functions (their callers: the resource database of
# pl-init.c, pl-load.c)
@testset "ZIP1: zip_open_archive, zip_open_archive_mem and SopenZIP are refused" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    function refused(f)
        try
            f()
        catch e
            e isa LK.NotPortedError || rethrow()
            return (sym_text(e.culprit), e.what, e.step)
        end
        return nothing
    end
    r = refused(() -> LK.zip_open_archive(ld, "x.zip", LK.RC_RDONLY))
    @test _zp_is(r, "zip_open_archive", "zip_open_archive: unzOpen2_64")
    r = refused(() -> LK.zip_open_archive_mem(ld, UInt8[0x50, 0x4b], LK.RC_RDONLY))
    @test _zp_is(r, "zip_open_archive_mem", "zip_open_archive_mem: unzOpen2_64")
    r = refused(() -> LK.SopenZIP(ld, LK.zipper(), "entry", LK.RC_RDONLY))
    @test _zp_is(r, "SopenZIP", "SopenZIP: a stream on a zip entry")
end

# get_zipper: no term is a zipper; rc_strerror and the RC_* flags of pl-zip.h
@testset "ZIP1: get_zipper; rc_strerror; the RC_* flags; the tables of registration, options" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    t = LK.PL_new_term_ref(ld)
    LK.PL_put_atom(ld, t, mk_sym(_TL, :foo))
    @test LK.get_zipper(ld, t) === nothing
    @test LK.rc_strerror(0) == "Unknown resource error"
    @test LK.rc_strerror(7) == "Unknown resource error"
    flags = (LK.RC_RDONLY, LK.RC_WRONLY, LK.RC_CREATE, LK.RC_TRUNC, LK.RC_RDWR)
    @test flags == (1, 2, 4, 8, 3)
    @test all(x -> x isa Int, flags)
    got = [(e.predicate_name, e.arity) for e in LK.PL_predicates_from_zip]
    @test got == [
        ("zip_open_stream", 3), ("zip_clone", 2), ("zip_close_", 2), ("zip_lock", 1),
        ("zip_unlock", 1), ("zipper_open_new_file_in_zip", 4), ("zipper_goto", 2),
        ("zipper_open_current", 3), ("zip_file_info_", 3),
        ("\$rc_handle", 1)
    ]
    @test all(e -> e.flags == LK.PL_FA_VARARGS, LK.PL_predicates_from_zip)
    @test [(o.name, o.type) for o in LK.zip_open_stream_options] ==
        [(:close_parent, LK.OPT_BOOL)]
    @test [(o.name, o.type) for o in LK.zipopen3_options] == [
        (:type, LK.OPT_ATOM), (:encoding, LK.OPT_ATOM), (:bom, LK.OPT_BOOL),
        (:release, LK.OPT_BOOL), (:reposition, LK.OPT_BOOL)
    ]
end
