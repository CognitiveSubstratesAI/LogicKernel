# ORIGINAL: a differential of $complete_atom/3, blob_type_property/2, set_blob_type/2, blob_released/1 and current_atom/1 (pl-atom.c) against swipl at the pin; test/core_lang/test_dwim_swipl.jl's harness
# test/core_lang/test_atom_api_swipl.jl — ATOM-API, through a PROGRAM (the pattern of test/core_lang/test_dwim_swipl.jl):
# test_atom_api_swipl.pl holds the rows, each a predicate `aaNN(R)`; the kernel consults the program and enumerates every
# solution of every aaNN/1, and its lines are compared with test_atom_api_swipl.out — swipl 10.1.20's own, printed by the
# driver below (`ok`, then one line per row: its name and every solution; two runs of the driver were byte-identical). When
# `swipl` is on PATH the .out is checked against a live run as well, so it cannot go stale.
#   * aa01-aa21 `$complete_atom/3` (pl-atom.c extendAtom, global_atom, LINESIZ) over the atoms the program holds;
#   * aa22-aa50 blob_type_property/2 (the 11 properties of `text`, `ucs_text`, `reserved_symbol`, the errors, the statistics);
#   * aa51-aa64 set_blob_type/2; aa65-aa78 blob_released/1 and current_atom/1.
# An LK-ONLY testset reads the kernel's own functions (PL_find_blob_type, add_type_live, the type statistics, extendAtom,
# global_atom) and the four refusal API functions (the atom reference counts and their debug tracing: atom GC family).
# UNVERIFIED on the kernel: gate decides (nothing was compiled when these rows were written): every kernel answer.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _AAT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_aas(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

_aa_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function _aa_enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _aa_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _aa_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _aa_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_aa_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _AA_PL = joinpath(@__DIR__, "test_atom_api_swipl.pl")
const _AA_OUT = joinpath(@__DIR__, "test_atom_api_swipl.out")

# the rows' names, in the order of the program
_aa_names() =
    unique([String(m[1]) for m in eachmatch(r"^(aa\d+)\(R\) :-"m, read(_AA_PL, String))])

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function _aa_kernel_lines(
    ::Type{T}, path::String, names::Vector{String}
)::Vector{String} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _aa_enc(ball::T)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_aas(T, name)), 1, LK.MODULE_user(gd))
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
        while (n += 1) <= 100
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        _aa_enc(mk_expr(T, T[_aas(T, name), lk_answers(ld, (a:a)...)...]))
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
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

# the driver swipl runs to print its lines (the .out is its output)
const _AA_DRIVER = raw"""
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
function _aa_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _AA_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the value of a row's line (`aaNN c[codes of aaNN]/1(<value>)`), or nothing for a row without an answer
function _aa_val(line::AbstractString, id::AbstractString)
    pre = id * " c" * _aa_codes(String(id)) * "/1("
    startswith(line, pre) || return nothing
    return line[(length(pre) + 1):(end - 1)]
end
_aa_atom(s::String) = "a" * _aa_codes(s)
_aa_pair(a::String, b::String) = "c[45]/2($a,$b)"
_aa_list(xs) = foldr((x, acc) -> "c[91,124,93]/2($x,$acc)", xs; init="nil")
_aa_c(f::String, args::String...) = "c" * _aa_codes(f) * "/$(length(args))(" * join(args, ",") * ")"
_aa_raised(x::String) = _aa_c("raised", x)
_aa_err1(f::String, a::String) = _aa_raised(_aa_c(f, _aa_atom(a)))

# the rows whose swipl answer is "no": the line is the row's name alone
const _AA_FAILING = [
    "aa04", "aa09", "aa10", "aa13", "aa18", "aa31", "aa32", "aa40", "aa44", "aa46", "aa47",
    "aa65", "aa66", "aa67", "aa68", "aa69", "aa71", "aa72", "aa73", "aa74"
]
# the rows whose answer is read off the .out as a value, and what swipl answers (pl-atom.c's documented behaviour)
const _AA_VALUES = Dict(
    "aa07" => _aa_pair("nil", _aa_atom("not_unique")),
    "aa19" => _aa_pair("i1023", _aa_atom("unique")),
    "aa21" => _aa_pair("nil", _aa_atom("not_unique")),
    "aa23" => "i1", "aa24" => "i1", "aa25" => "i0", "aa26" => "i0", "aa27" => "i0",
    "aa28" => _aa_atom("yes"), "aa29" => _aa_atom("yes"), "aa30" => _aa_atom("yes"),
    "aa35" => _aa_atom("yes"), "aa36" => "i2", "aa37" => "i4", "aa39" => _aa_atom("yes"),
    "aa45" => _aa_atom("yes"), "aa48" => _aa_atom("grew"), "aa49" => _aa_atom("grew"),
    "aa50" => _aa_atom("same"), "aa51" => "i7", "aa52" => _aa_atom("yes"),
    "aa70" => _aa_atom("yes"), "aa75" => _aa_atom("yes"), "aa77" => _aa_atom("yes"),
    "aa78" => _aa_atom("yes"),
    "aa22" => _aa_list(
        _aa_atom.(
            [
                "unique", "text", "rank", "padding", "gc_margin", "unregistered",
                "non_garbage", "live", "space"
            ]
        )
    ),
    "aa33" => _aa_list([_aa_atom("text")]), "aa34" => _aa_list([_aa_atom("text")]),
    "aa38" => _aa_list([_aa_atom("ucs_text")]), "aa76" => _aa_list([_aa_atom("x")]),
    "aa11" => _aa_raised(_aa_atom("instantiation_error")),
    "aa58" => _aa_raised(_aa_atom("instantiation_error")),
    "aa60" => _aa_raised(_aa_atom("instantiation_error")),
    "aa61" => _aa_raised(_aa_atom("instantiation_error")),
    "aa08" => _aa_err1("representation_error", "encoding"),
    "aa41" => _aa_raised(_aa_c("existence_error", _aa_atom("blob_type"), _aa_atom("nosuch"))),
    "aa53" => _aa_raised(_aa_c("domain_error", _aa_atom("not_less_than_zero"), "i-1")),
    "aa56" => _aa_raised(_aa_c("type_error", _aa_atom("blob_type_property"), _aa_atom("foo"))),
    "aa57" => _aa_raised(
        _aa_c("domain_error", _aa_atom("blob_type_property"), _aa_c("f", _aa_atom("x")))
    )
)

@testset "ATOM-API: \$complete_atom/3, blob_type_property/2, set_blob_type/2, blob_released/1, current_atom/1 == swipl's answers (the .out), through a program" begin
    names = _aa_names()
    expected = String.(readlines(_AA_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test length(names) == 78 && names == ["aa" * lpad(i, 2, '0') for i in 1:78]
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i]), eachindex(names))
    byid = Dict(names[i] => expected[i + 1] for i in eachindex(names))
    for id in _AA_FAILING
        @test byid[id] == id                                              # swipl answers "no"
    end
    for (id, v) in _AA_VALUES
        @test _aa_val(byid[id], id) == v
    end
    # the answering '$complete_atom' rows answer a code list with the prefix, then unique or not_unique
    @test count(id -> _aa_val(byid[id], id) !== nothing, ["aa0$i" for i in (1, 2, 3, 5, 6, 7)]) == 6
    @test occursin(_aa_atom("not_unique"), byid["aa01"]) && occursin(_aa_atom("unique"), byid["aa02"])
    @test _aa_val(byid["aa14"], "aa14") == _aa_val(byid["aa01"], "aa01")      # the NUL cuts the prefix
    @test count(l -> occursin("[114,97,105,115,101,100]", l), expected) >= 16   # the error rows: `raised(...)`

    kl = _aa_kernel_lines(_AAT, _AA_PL, names)
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "ATOM-API DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test _aa_swipl_lines(_AA_PL, names) == expected                  # the .out is swipl's, still
    end
end

_aa_bytes(s::AbstractString) = Vector{UInt8}(codeunits(s))

@testset "ATOM-API LK-ONLY: the kernel's atom table functions (pl-atom.c PL_find_blob_type, add_type_live, extendAtom, global_atom)" begin
    atoms = LK.do_init_atoms!(LK.atoms_t())

    @testset "PL_find_blob_type (pl-atom.c:624)" begin
        r = LK.PL_find_blob_type(atoms, "text")
        @test r isa LK.blob_registration && r.type === LK.text_atom
        @test LK.PL_find_blob_type(atoms, "nosuch") === nothing
        @test LK.PL_find_blob_type(atoms, "") === nothing
        rs = LK.PL_find_blob_type(atoms, "reserved_symbol")
        @test rs isa LK.blob_registration && rs.type.name == "reserved_symbol"
        @test rs !== r
        # a database holds its own registrations
        other = LK.do_init_atoms!(LK.atoms_t())
        @test LK.PL_find_blob_type(other, "text") !== r
    end

    @testset "type statistics live and space (pl-atom.c:1038 add_type_live)" begin
        reg = LK.PL_find_blob_type(atoms, "text")
        l0, s0 = reg.live, reg.space
        rs0 = LK.PL_find_blob_type(atoms, "reserved_symbol")
        rl, rsp = rs0.live, rs0.space
        name = "aa_qzx_fifteen_"                                  # 15 bytes
        @test length(name) == 15
        w = LK.lookupAtom(atoms, _aa_bytes(name))
        @test reg.live == l0 + 1 && reg.space == s0 + 15
        @test LK.lookupAtom(atoms, _aa_bytes(name)) == w         # found again: nothing counted twice
        @test reg.live == l0 + 1 && reg.space == s0 + 15
        w2 = LK.lookupAtom(atoms, _aa_bytes("aa_qzx_other"))     # 12 bytes
        @test w2 != w && reg.live == l0 + 2 && reg.space == s0 + 27
        # another type's statistics do not move
        rs = LK.PL_find_blob_type(atoms, "reserved_symbol")
        @test (rs.live, rs.space) == (rl, rsp)
        # add_type_live on a fresh registration
        fresh = LK.blob_registration(LK.text_atom, 1, 1, UInt64(0))
        @test (fresh.gc_margin, fresh.unregistered, fresh.non_garbage, fresh.live, fresh.space) ==
            (0, 0, 0, 0, 0)
        @test (fresh.rank, fresh.padding, fresh.atom_name) == (1, 1, UInt64(0))
        a = LK.atomValue(atoms, w)
        LK.add_type_live(fresh, a)
        @test fresh.live == 1 && fresh.space == a.length == 15
        LK.add_type_live(fresh, LK.atomValue(atoms, w2))
        @test fresh.live == 2 && fresh.space == 27
    end

    @testset "global_atom (pl-atom.c) and extendAtom (pl-atom.c:2472)" begin
        w1 = LK.lookupAtom(atoms, _aa_bytes("aa_qzx_lk_one"))
        w2 = LK.lookupAtom(atoms, _aa_bytes("aa_qzx_lk_two"))
        a1 = LK.atomValue(atoms, w1)
        @test LK.global_atom(atoms, a1)                           # it has a reference
        bi = LK.atomValue(atoms, LK.builtin_atom("text"))
        @test LK.ATOM_REF_COUNT(bi.references) == 0 && LK.global_atom(atoms, bi)   # a built-in atom's count is 0: its index decides
        # not found, found and not unique (the common text of `one` and `two` after the prefix), found and unique
        @test LK.extendAtom(atoms, _aa_bytes("aa_qzx_nomatch")) == (false, true, UInt8[])
        found, uniq, common = LK.extendAtom(atoms, _aa_bytes("aa_qzx_lk"))
        @test found && !uniq && String(common) == "_"
        found, uniq, common = LK.extendAtom(atoms, _aa_bytes("aa_qzx_lk_o"))
        @test found && uniq && String(common) == "ne"
        found, uniq, common = LK.extendAtom(atoms, _aa_bytes("aa_qzx_lk_one"))
        @test found && uniq && isempty(common)                    # the prefix is the whole atom
        @test LK.extendAtom(atoms, _aa_bytes("aa_qzx_lk_one_")) == (false, true, UInt8[])   # longer than the atom
        # an atom without references is not offered
        a2 = LK.atomValue(atoms, w2)
        saved = a2.references
        a2.references = LK.ATOM_VALID_REFERENCE
        @test !LK.global_atom(atoms, a2)
        found, uniq, common = LK.extendAtom(atoms, _aa_bytes("aa_qzx_lk"))
        @test found && uniq && String(common) == "_one"
        a2.references = saved
        @test LK.global_atom(atoms, a2)
        # the name is a C string: cut at its first NUL
        LK.lookupAtom(atoms, UInt8[_aa_bytes("aa_qzx_nul")..., 0x00, UInt8('t'), UInt8('l')])
        found, uniq, common = LK.extendAtom(atoms, _aa_bytes("aa_qzx_nu"))
        @test found && uniq && String(common) == "l"
        @test LK.extendAtom(atoms, UInt8[_aa_bytes("aa_qzx_nul")..., 0x00]) == (false, true, UInt8[])
        # strlen < LINESIZ: an atom of 1023 bytes is offered, one of 1024 and one of 1030 are not
        @test LK.LINESIZ == 1024
        LK.lookupAtom(atoms, _aa_bytes("aa_qzx_b3_" * 'x'^1013))
        LK.lookupAtom(atoms, _aa_bytes("aa_qzx_b4_" * 'y'^1014))
        LK.lookupAtom(atoms, _aa_bytes("aa_qzx_b5_" * 'z'^1020))
        found, uniq, common = LK.extendAtom(atoms, _aa_bytes("aa_qzx_b"))
        @test found && uniq && length(common) == 1015 && String(common[1:2]) == "3_"
        @test LK.extendAtom(atoms, _aa_bytes("aa_qzx_b4")) == (false, true, UInt8[])
        @test LK.extendAtom(atoms, _aa_bytes("aa_qzx_b5")) == (false, true, UInt8[])
    end

    @testset "the four refusal API functions (pl-atom.c:1071, :1090, :1591, :1751)" begin
        gd = LK.PL_global_data{_AAT}()
        ld = LK.PL_local_data{_AAT}(gd)
        a = _aas(_AAT, "aa_qzx_refused")
        for (f, name) in (
            (() -> LK.PL_register_atom(ld, a), "PL_register_atom"),
            (() -> LK.PL_unregister_atom(ld, a), "PL_unregister_atom"),
            (
                () -> LK._PL_debug_register_atom(ld, a, "pl-atom.c", 1, "f"),
                "_PL_debug_register_atom"
            ),
            (
                () -> LK._PL_debug_unregister_atom(ld, a, "pl-atom.c", 1, "f"),
                "_PL_debug_unregister_atom"
            )
        )
            e = try
                f()
                nothing
            catch err
                err
            end
            @test e isa LK.NotPortedError
            @test e isa LK.NotPortedError && startswith(e.what, name)
            @test e isa LK.NotPortedError && e.step == "atom GC family, D-0634 D5"
        end
    end
end
