# ORIGINAL: a LIVE differential of the debugger status that `'$notrace'/2` and `'$restore_trace'/2` save and restore (pl-pro.c:311-390),
# against swipl at the pin; audit D-0431 item 2 (DBG1-SMALL). Rows nt01-nt22:
#   * A PROGRAM of cases `t_<id>(R)` consulted by the kernel's loader and run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_bootpred3_swipl.jl's (`enc`oded answers).
#   * Every row saves the state first (`'$notrace'(F0, S0)`) and restores it last, so a row leaves the next one what it found.
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, lk-channel evidence/DBG1SMALL/nt_rows.out; generator
#     evidence/DBG1SMALL/gen_rows.py); with `swipl` on PATH the live answers are compared with the pins too.
#   * No KNOWN DIFFERENCE: the tracing and debugging bits, the skip level (-1: SKIP_VERY_DEEP, -2: SKIP_REDO_IN_SKIP) and the run mode
#     are read and written on the local data's `debugstatus_*`. What the kernel does not have is the tracer that READS them (DBG1).
#   * The rows pass `debugging` and `tracing` only to `'$notrace'/2`, `'$restore_trace'/2`, `current_prolog_flag/2`, `set_prolog_flag/2`,
#     `catch/3` and the unifications, so swipl does not enter the tracer (stdin is /dev/null).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _NT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_nts(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

_nt_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _nt_enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _nt_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _nt_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _nt_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_nt_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test_bootpred3_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _NT_DRIVER = raw"""
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
function _nt_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _NT_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: nothing to define (the rows are the built-ins and the flag `debug`)
const _NT_PROGRAM = raw"""
nt_dummy.
"""

# nt01-nt03: the tracing and debugging bits are saved, then switched off; nt04-nt07: the skip level (a count, -1, -2, 2^32, 2^63-1);
# nt08-nt09: `'$notrace'/2` clears the status and sets the normal run mode; nt10-nt12: the flag `debug` is the debugging status;
# nt13-nt15: a later restore wins, a refused restore and a refused unification leave the status as it was; nt16-nt17: a
# restore replaces the bits and the level (-1 and -2 are two levels); nt18: a failing row; nt19-nt22: the second `'$notrace'/2` reads the
# cleared status, a restored status survives a save, one flag bit alone is restored.
const _NT_CASES = [
    ("nt01", raw"'$notrace'(F0, S0), '$restore_trace'(1, -1), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt02", raw"'$notrace'(F0, S0), '$restore_trace'(2, -1), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt03", raw"'$notrace'(F0, S0), '$restore_trace'(3, -1), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt04", raw"'$notrace'(F0, S0), '$restore_trace'(12, 5), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt05", raw"'$notrace'(F0, S0), '$restore_trace'(14, -2), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt06", raw"'$notrace'(F0, S0), '$restore_trace'(12, 4294967296), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt07", raw"'$notrace'(F0, S0), '$restore_trace'(12, 9223372036854775807), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt08", raw"'$notrace'(F0, S0), '$restore_trace'(15, 7), '$notrace'(_, _), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt09", raw"'$notrace'(F0, S0), '$restore_trace'(0, 0), '$notrace'(F1, S1), '$notrace'(F2, S2), '$restore_trace'(F0, S0), R = F1-S1-F2-S2"),
    ("nt10", raw"'$notrace'(F0, S0), '$restore_trace'(2, -1), current_prolog_flag(debug, D1), '$notrace'(F, _), current_prolog_flag(debug, D2), '$restore_trace'(F0, S0), R = D1-F-D2"),
    ("nt11", raw"'$notrace'(F0, S0), '$restore_trace'(1, -1), current_prolog_flag(debug, D), '$notrace'(F, _), '$restore_trace'(F0, S0), R = D-F"),
    ("nt12", raw"'$notrace'(F0, S0), set_prolog_flag(debug, true), '$notrace'(F, S), '$restore_trace'(F, S), current_prolog_flag(debug, D), '$notrace'(_, _), '$restore_trace'(F0, S0), R = F-S-D"),
    ("nt13", raw"'$notrace'(F0, S0), '$restore_trace'(3, 3), '$restore_trace'(0, 9), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt14", raw"'$notrace'(F0, S0), '$restore_trace'(15, 3), catch('$restore_trace'(0, -3), error(E, _), true), '$notrace'(F, S), '$restore_trace'(F0, S0), R = E-F-S"),
    ("nt15", raw"'$notrace'(F0, S0), '$restore_trace'(15, 3), ( '$notrace'(0, _) -> X = yes ; X = no ), '$notrace'(F, S), '$restore_trace'(F0, S0), R = X-F-S"),
    ("nt16", raw"'$notrace'(F0, S0), '$restore_trace'(1, 5), '$restore_trace'(2, -1), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt17", raw"'$notrace'(F0, S0), '$restore_trace'(12, -2), '$restore_trace'(12, -1), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
    ("nt18", raw"'$notrace'(F0, S0), '$restore_trace'(F0, S0), '$notrace'(F, _), ( F == 99 -> true ; '$restore_trace'(F0, S0), fail )"),
    ("nt19", raw"'$notrace'(F0, S0), '$restore_trace'(15, 1), '$notrace'(F, S), '$notrace'(G, T), '$restore_trace'(F0, S0), R = F-S-G-T"),
    ("nt20", raw"'$notrace'(F0, S0), '$restore_trace'(F0, S0), '$restore_trace'(14, 0), '$notrace'(F, S), '$restore_trace'(F, S), '$notrace'(G, T), '$restore_trace'(F0, S0), R = F-S-G-T"),
    ("nt21", raw"'$notrace'(F0, S0), '$restore_trace'(8, 2), '$notrace'(F, _), '$notrace'(G, _), '$restore_trace'(F0, S0), R = F-G"),
    ("nt22", raw"'$notrace'(F0, S0), '$restore_trace'(4, -2), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S"),
]

# swipl's answer lines, generated by evidence/DBG1SMALL/gen_rows.py from the program and the cases above
const _NT_PINNED = [
    "ok",
    "t_nt01 c[116,95,110,116,48,49]/1(c[45]/2(i1,i-1))",
    "t_nt02 c[116,95,110,116,48,50]/1(c[45]/2(i2,i-1))",
    "t_nt03 c[116,95,110,116,48,51]/1(c[45]/2(i3,i-1))",
    "t_nt04 c[116,95,110,116,48,52]/1(c[45]/2(i12,i5))",
    "t_nt05 c[116,95,110,116,48,53]/1(c[45]/2(i14,i-2))",
    "t_nt06 c[116,95,110,116,48,54]/1(c[45]/2(i12,i4294967296))",
    "t_nt07 c[116,95,110,116,48,55]/1(c[45]/2(i12,i9223372036854775807))",
    "t_nt08 c[116,95,110,116,48,56]/1(c[45]/2(i12,i-1))",
    "t_nt09 c[116,95,110,116,48,57]/1(c[45]/2(c[45]/2(c[45]/2(i0,i0),i12),i-1))",
    "t_nt10 c[116,95,110,116,49,48]/1(c[45]/2(c[45]/2(a[116,114,117,101],i2),a[102,97,108,115,101]))",
    "t_nt11 c[116,95,110,116,49,49]/1(c[45]/2(a[102,97,108,115,101],i1))",
    "t_nt12 c[116,95,110,116,49,50]/1(c[45]/2(c[45]/2(i2,i-1),a[116,114,117,101]))",
    "t_nt13 c[116,95,110,116,49,51]/1(c[45]/2(i0,i9))",
    "t_nt14 c[116,95,110,116,49,52]/1(c[45]/2(c[45]/2(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116]),i15),i3))",
    "t_nt15 c[116,95,110,116,49,53]/1(c[45]/2(c[45]/2(a[110,111],i15),i3))",
    "t_nt16 c[116,95,110,116,49,54]/1(c[45]/2(i2,i-1))",
    "t_nt17 c[116,95,110,116,49,55]/1(c[45]/2(i12,i-1))",
    "t_nt18",
    "t_nt19 c[116,95,110,116,49,57]/1(c[45]/2(c[45]/2(c[45]/2(i15,i1),i12),i-1))",
    "t_nt20 c[116,95,110,116,50,48]/1(c[45]/2(c[45]/2(c[45]/2(i14,i0),i14),i0))",
    "t_nt21 c[116,95,110,116,50,49]/1(c[45]/2(i8,i12))",
    "t_nt22 c[116,95,110,116,50,50]/1(c[45]/2(i4,i-2))"
]

function _nt_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _NT_CASES]
    text =
        _NT_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _NT_CASES
        ])
    f = joinpath(mktempdir(), "notrace2.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _nt_kernel(::Type{T}, path::String, names::Vector{String}) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _nt_enc(ball::T)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_nts(T, name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _nt_enc(mk_expr(T, T[_nts(T, name), lk_answers(ld, (a:a)...)...]))
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
    return out, gd, ld
end

@testset "the debugger status of '\$notrace'/2 and '\$restore_trace'/2 as swipl's (nt01-nt22)" begin
    f, names = _nt_file()
    kl, _, _ = _nt_kernel(_NT, f, names)
    @test length(kl) == length(_NT_PINNED)
    for (k, p) in zip(kl, _NT_PINNED)
        k == p || println(stderr, "  ours  ", k, "\\n  swipl ", p)
        @test k == p
    end
end

"The atom codes of a pin line, as text (for a substring test)."
_nt_decode(l::AbstractString) = join(
    [String(Char.(parse.(Int, split(m.captures[1], ',')))) for m in eachmatch(r"a\[([\d,]+)\]", l)],
    " "
)

@testset "the kernel's debugger status is left as found (white box)" begin
    f, names = _nt_file()
    _, gd, ld = _nt_kernel(_NT, f, names)
    @test !ld.debugstatus_tracing
    @test !ld.debugstatus_debugging
    @test ld.debugstatus_skiplevel == UInt(0)              # swipl's first level: every row restored it
    @test ld.prolog_flag_mask & LK.RUN_MODE_NORMAL == LK.RUN_MODE_NORMAL
    # the status words themselves: `'$notrace'/2` stores the very-deep level, `'$restore_trace'/2` the redo-in-skip one
    @test LK.SKIP_VERY_DEEP == typemax(UInt)
    @test LK.SKIP_REDO_IN_SKIP == typemax(UInt) - 1
end

@testset "the NT rows are not vacuous" begin
    @test length(_NT_PINNED) == length(_NT_CASES) + 1
    @test _NT_PINNED[1] == "ok"
    answered = [l for l in _NT_PINNED if occursin(r"^t_nt\d\d ", l)]
    failed = [l for l in _NT_PINNED if occursin(r"^t_nt\d\d$", l)]
    @test length(answered) >= 20                                         # most rows answer
    @test !isempty(failed)                                               # some row fails (nt18)
    @test any(l -> startswith(l, "t_nt01 ") && occursin("i1,i-1", l), _NT_PINNED)    # the tracing bit is read back
    @test any(l -> startswith(l, "t_nt05 ") && occursin("i14,i-2", l), _NT_PINNED)   # a redo-in-skip level is read back
    @test any(l -> startswith(l, "t_nt04 ") && occursin("i12,i5", l), _NT_PINNED)    # a count is read back
    @test any(l -> startswith(l, "t_nt14 ") && occursin("size_t", _nt_decode(l)), _NT_PINNED)   # a refused restore
    @test length(unique(_NT_PINNED)) == length(_NT_PINNED)               # the rows differ from one another
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_NT_PINNED) == length(_NT_CASES) + 1
    if swipl === nothing
        @info "NT LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _nt_file()
        @test _nt_swipl_lines(f, names) == _NT_PINNED
    end
end
