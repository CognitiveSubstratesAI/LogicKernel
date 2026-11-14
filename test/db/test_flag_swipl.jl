# ORIGINAL: FL1b part 2 (audit D-0550) — get_flag/2, set_flag/2 and current_flag/1 of pl-flag.c (src/pl-flag.jl) against swipl at the pin (18168e62); UNTESTED, nothing compiled.
# test/db/test_flag_swipl.jl — the answers and errors of the global flags (`flag/3`'s table), as a PROGRAM consulted by the kernel's loader with cases
# `t_<id>(R)` run IN ORDER in one database (the flags are global: each case names its own keys), each wrapped in `catch(Goal, error(E, _), R = raised(E))`.
#   * Every answer line is swipl's, PINNED (the pin's swipl 10.1.20, one run of the driver below over the same program); with `swipl` on PATH the
#     live answers are compared with the pins too. The enumeration order of `current_flag/1` is the hash table's upstream (unspecified): the cases
#     that enumerate sort what they collect.
#   * The kernel's integers: V_INTEGER holds every Int64 where upstream's is the tagged range (+-2^56): fg18/fg19, fg28-fg31 pin the pin's
#     `representation_error(int64_t)` at the boundary.
#   * The LK-ONLY testset states what only the kernel can: the table (`gd.flags_table`, `gd.flags_order`) and the type each flag holds.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the global flags (src/pl-flag.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _FG = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_fgs(x) = lk_sym(_FG, Symbol(x))

_fg_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _fg_enc(t::_FG, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _fg_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _fg_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _fg_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_fg_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _FG_DRIVER = raw"""
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
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function _fg_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _FG_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# (id, goal), run IN ORDER; the keys are the cases' own (the flags are global)
const _FG_CASES = [
    ("fg01", raw"get_flag(fg_k1, R)"),
    ("fg02", raw"set_flag(fg_k2, abc), get_flag(fg_k2, R)"),
    ("fg03", raw"set_flag(fg_k3, 42), get_flag(fg_k3, R)"),
    ("fg04", raw"set_flag(fg_k4, 2.5), get_flag(fg_k4, R)"),
    ("fg05", raw"set_flag(fg_k5, 1), set_flag(fg_k5, a), get_flag(fg_k5, R)"),
    ("fg06", raw"set_flag(fg_k6, a), set_flag(fg_k6, 7), get_flag(fg_k6, R)"),
    ("fg07", raw"set_flag(fg_k7, 1.5), set_flag(fg_k7, 3), get_flag(fg_k7, R)"),
    ("fg08", raw"set_flag(fg_k8, 100000000000000000000)"),
    ("fg09", raw"X is 1 rdiv 3, set_flag(fg_k9, X)"),
    ("fg10", raw"set_flag(fg_k10, f(x))"),
    ("fg11", raw"""set_flag(fg_k11, "str"), R = ok"""),
    ("fg12", raw"set_flag(fg_k12, _)"),
    ("fg13", raw"get_flag(1.5, R)"),
    ("fg14", raw"get_flag(_, R)"),
    ("fg15", raw"get_flag(f(x), R0), set_flag(f(y), 5), get_flag(f(z), R1), R = R0-R1"),
    ("fg16", raw"set_flag(3, a), get_flag(3, R0), get_flag(4, R1), R = R0-R1"),
    ("fg17", raw"get_flag(fg_k3, 42), \+ get_flag(fg_k3, 43), R = ok"),
    ("fg18", raw"set_flag(fg_k18, 9223372036854775807), get_flag(fg_k18, R)"),
    ("fg19", raw"set_flag(fg_k19, -9223372036854775808), get_flag(fg_k19, R)"),
    ("fg20", raw"set_flag(fg_k20, []), get_flag(fg_k20, R)"),
    ("fg21", raw"findall(K, (current_flag(K), atom(K), sub_atom(K, 0, 4, _, fg_k)), L0), msort(L0, R)"),
    ("fg22", raw"current_flag(fg_k2), \+ current_flag(fg_nokey), R = ok"),
    ("fg23", raw"\+ current_flag(fg_new1), get_flag(fg_new1, _), current_flag(fg_new1), R = ok"),
    ("fg24", raw"current_flag(1.5)"),
    ("fg25", raw"set_flag(g(a, b), 1), findall(K, (current_flag(K), compound(K), K = g(_, _)), R)"),
    ("fg26", raw"findall(K, (current_flag(K), integer(K)), L0), msort(L0, R)"),
    ("fg27", raw"set_flag(fg_k27, 1), set_flag(fg_k27, 2.0), set_flag(fg_k27, b), get_flag(fg_k27, R)"),
    ("fg28", raw"set_flag(fg_k28, 72057594037927935), get_flag(fg_k28, R)"),
    ("fg29", raw"set_flag(fg_k29, 72057594037927936)"),
    ("fg30", raw"set_flag(fg_k30, -72057594037927936), get_flag(fg_k30, R)"),
    ("fg31", raw"set_flag(fg_k31, -72057594037927937)")
]

# the answers the pin's swipl gives: the driver's first line, then one line per case
const _FG_PINNED = [
    # PINS-BEGIN
    "ok",
    "t_fg01 c[116,95,102,103,48,49]/1(i0)",
    "t_fg02 c[116,95,102,103,48,50]/1(a[97,98,99])",
    "t_fg03 c[116,95,102,103,48,51]/1(i42)",
    "t_fg04 c[116,95,102,103,48,52]/1(f2.5)",
    "t_fg05 c[116,95,102,103,48,53]/1(a[97])",
    "t_fg06 c[116,95,102,103,48,54]/1(i7)",
    "t_fg07 c[116,95,102,103,48,55]/1(i3)",
    "t_fg08 c[116,95,102,103,48,56]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116])))",
    "t_fg09 c[116,95,102,103,48,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,97,103,95,118,97,108,117,101],q1r3)))",
    "t_fg10 c[116,95,102,103,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,97,103,95,118,97,108,117,101],c[102]/1(a[120]))))",
    "t_fg11 c[116,95,102,103,49,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[102,108,97,103,95,118,97,108,117,101],s[115,116,114])))",
    "t_fg12 c[116,95,102,103,49,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_fg13 c[116,95,102,103,49,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],f1.5)))",
    "t_fg14 c[116,95,102,103,49,52]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_fg15 c[116,95,102,103,49,53]/1(c[45]/2(i0,i5))",
    "t_fg16 c[116,95,102,103,49,54]/1(c[45]/2(a[97],i0))",
    "t_fg17 c[116,95,102,103,49,55]/1(a[111,107])",
    "t_fg18 c[116,95,102,103,49,56]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116])))",
    "t_fg19 c[116,95,102,103,49,57]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116])))",
    "t_fg20 c[116,95,102,103,50,48]/1(nil)",
    "t_fg21 c[116,95,102,103,50,49]/1(c[91,124,93]/2(a[102,103,95,107,49],c[91,124,93]/2(a[102,103,95,107,49,48],c[91,124,93]/2(a[102,103,95,107,49,49],c[91,124,93]/2(a[102,103,95,107,49,50],c[91,124,93]/2(a[102,103,95,107,49,56],c[91,124,93]/2(a[102,103,95,107,49,57],c[91,124,93]/2(a[102,103,95,107,50],c[91,124,93]/2(a[102,103,95,107,50,48],c[91,124,93]/2(a[102,103,95,107,51],c[91,124,93]/2(a[102,103,95,107,52],c[91,124,93]/2(a[102,103,95,107,53],c[91,124,93]/2(a[102,103,95,107,54],c[91,124,93]/2(a[102,103,95,107,55],c[91,124,93]/2(a[102,103,95,107,56],c[91,124,93]/2(a[102,103,95,107,57],nil))))))))))))))))",
    "t_fg22 c[116,95,102,103,50,50]/1(a[111,107])",
    "t_fg23 c[116,95,102,103,50,51]/1(a[111,107])",
    "t_fg24 c[116,95,102,103,50,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[107,101,121],f1.5)))",
    "t_fg25 c[116,95,102,103,50,53]/1(c[91,124,93]/2(c[103]/2(V0,V1),nil))",
    "t_fg26 c[116,95,102,103,50,54]/1(c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil)))",
    "t_fg27 c[116,95,102,103,50,55]/1(a[98])",
    "t_fg28 c[116,95,102,103,50,56]/1(i72057594037927935)",
    "t_fg29 c[116,95,102,103,50,57]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116])))",
    "t_fg30 c[116,95,102,103,51,48]/1(i-72057594037927936)",
    "t_fg31 c[116,95,102,103,51,49]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116])))"
    # PINS-END
]

"The program and cases as one file; the case predicates' names."
function _fg_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _FG_CASES]
    text = join([
        "t_$(id)(R) :- catch(($g), error(FgE, _), R = raised(FgE)).\n" for
        (id, g) in _FG_CASES
    ])
    f = joinpath(mktempdir(), "flags.pl")
    write(f, text)
    return f, names
end

"The kernel's answers to the query `name(R)` in `gd`: the encoded lines, at most 50 answers; a Julia exception propagates."
function _fg_query(gd, ld, name::String)::String
    proc = LK.isCurrentProcedure(sym_key(_fgs(name)), 1, LK.MODULE_user(gd))
    if proc === nothing || !LK.isDefinedProcedure(gd, proc)
        return "$name undefined"
    end
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_FG, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    try
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _fg_enc(mk_expr(_FG, _FG[_fgs(name), lk_answers(ld, (a:a)...)...]))
                )
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
    finally
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    return "$name" * join(" " .* sols)
end

"The kernel's lines for `names` after consulting `path` on the booted database."
function _fg_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_FG}()
    ld = LK.PL_local_data{_FG}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _fg_enc(ball::_FG)]
    for name in names
        push!(out, _fg_query(gd, ld, name))
    end
    return out, gd, ld
end

@testset "the global flags as swipl's (fg01-fg31)" begin
    # UNVERIFIED on the kernel: gate decides (fg09 reads `1 rdiv 3`; fg21 and fg25 use sub_atom/5 and findall/3 over current_flag/1)
    f, names = _fg_file()
    kl, _, _ = _fg_kernel(f, names)
    @test length(kl) == length(_FG_PINNED)
    for (k, p) in zip(kl, _FG_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the pins hold both kinds of answer through the one extractor
    raised = "c" * _fg_codes("raised")
    @test count(l -> occursin(raised, l), _FG_PINNED) >= 12
    @test count(l -> !occursin(raised, l) && startswith(l, "t_"), _FG_PINNED) >= 12
    @test any(
        l ->
            startswith(l, "t_fg08 ") && occursin(
                "c" * _fg_codes("representation_error") * "/1(a" * _fg_codes("int64_t"), l
            ),
        _FG_PINNED
    )
end

# LK-ONLY: the table and the flag a call leaves (swipl has no field to read)
@testset "LK-ONLY: get_flag/2 and set_flag/2 write the flag table" begin
    # UNVERIFIED on the kernel: gate decides
    path = joinpath(mktempdir(), "wb.pl")
    write(
        path,
        "w_get(R) :- get_flag(fgw_a, R).\n" *
        "w_int(R) :- set_flag(fgw_a, 6), R = ok.\n" *
        "w_atm(R) :- set_flag(fgw_a, abc), R = ok.\n" *
        "w_flt(R) :- set_flag(fgw_a, 2.5), R = ok.\n" *
        "w_err(R) :- catch(set_flag(fgw_a, f(x)), error(_, _), R = ok).\n" *
        "w_fun(R) :- set_flag(fgw_f(1, 2), 1), R = ok.\n"
    )
    gd = LK.PL_global_data{_FG}()
    ld = LK.PL_local_data{_FG}(gd)
    st, _ = LK.load_file!(gd, ld, path)
    @test st === :ok
    ok = "a" * _fg_codes("ok") * ")"
    n0 = length(gd.flags_table)
    @test length(gd.flags_order) == n0
    # a get on a fresh key makes the flag, an integer 0
    @test endswith(_fg_query(gd, ld, "w_get"), "i0)")
    @test length(gd.flags_table) == n0 + 1 && length(gd.flags_order) == n0 + 1
    fl = gd.flags_order[end]
    @test fl.type == LK.FLG_INTEGER && fl.i == 0
    @test gd.flags_table[fl.key] === fl
    # each setter replaces the type and value of the SAME flag
    @test endswith(_fg_query(gd, ld, "w_int"), ok)
    @test fl.type == LK.FLG_INTEGER && fl.i == 6
    @test endswith(_fg_query(gd, ld, "w_atm"), ok)
    @test fl.type == LK.FLG_ATOM && fl.a == _fgs("abc")
    @test endswith(_fg_query(gd, ld, "w_flt"), ok)
    @test fl.type == LK.FLG_FLOAT && fl.f == 2.5
    # a refused value leaves the flag as it was
    @test endswith(_fg_query(gd, ld, "w_err"), ok)
    @test fl.type == LK.FLG_FLOAT && fl.f == 2.5
    @test length(gd.flags_table) == n0 + 1
    # a compound's key is its functor: a second flag, enumerated after the first
    @test endswith(_fg_query(gd, ld, "w_fun"), ok)
    @test length(gd.flags_table) == n0 + 2 && length(gd.flags_order) == n0 + 2
    @test gd.flags_order[end].key != fl.key
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_FG_PINNED) == length(_FG_CASES) + 1
    if swipl === nothing
        @info "FL1b LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _fg_file()
        @test _fg_swipl_lines(f, names) == _FG_PINNED
    end
end
