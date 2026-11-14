# ORIGINAL: FL1 (audit D-0501, D-0547) — the flag setters of pl-prologflag.c (setIncomparable, setFileNameCaseHandling(Name), setTheme, the agc_margin,
# stack_limit (pl-setup.c set_stack_limit) and string_stack_tripwire branches of set_flag_value) against swipl at the pin (18168e62); UNTESTED, nothing compiled.
# test/core_lang/test_flag_setters_swipl.jl — the values and errors of `incomparable`, `agc_margin`, `stack_limit`, `file_name_case_handling`
# (read-only), `theme` and `string_stack_tripwire`, as a PROGRAM consulted by the kernel's loader with cases `t_<id>(R)` run IN ORDER in one
# database, each wrapped in `catch(Goal, error(E, _), R = raised(E))`; a case that changes a flag sets it back.
#   * Every answer line is swipl's, PINNED (the pin's swipl 10.1.20, one run of the driver below over the same program); with `swipl` on PATH the
#     live answers are compared with the pins too.
#   * The LK-ONLY testsets state what only the kernel can: the local-data fields the setters write (`prolog_flag_incomparable_error`,
#     `stacks_limit`, `fli_string_buffers_tripwire`, `gd.atoms.margin`) and the file-name case mask bits.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the flag write side (src/os/pl-prologflag.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _FS = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_fss(x) = lk_sym(_FS, Symbol(x))

_fs_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _fs_enc(t::_FS, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _fs_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _fs_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _fs_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_fs_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _FS_DRIVER = raw"""
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
function _fs_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _FS_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# (id, goal), run IN ORDER; every goal that changes a flag ends with it back at its default
const _FS_CASES = [
    ("fs01", raw"set_prolog_flag(incomparable, error), current_prolog_flag(incomparable, R), set_prolog_flag(incomparable, arbitrary)"),
    ("fs02", raw"set_prolog_flag(incomparable, foo)"),
    ("fs03", raw"set_prolog_flag(incomparable, 1)"),
    ("fs04", raw"current_prolog_flag(incomparable, R)"),
    ("fs05", raw"set_prolog_flag(agc_margin, 100), current_prolog_flag(agc_margin, R), set_prolog_flag(agc_margin, 10000)"),
    ("fs06", raw"set_prolog_flag(agc_margin, -1)"),
    ("fs07", raw"set_prolog_flag(agc_margin, a)"),
    ("fs08", raw"set_prolog_flag(stack_limit, 2000000000), current_prolog_flag(stack_limit, R), set_prolog_flag(stack_limit, 1073741824)"),
    ("fs09", raw"set_prolog_flag(stack_limit, -1)"),
    ("fs10", raw"set_prolog_flag(stack_limit, 1)"),
    ("fs11", raw"current_prolog_flag(stack_limit, R)"),
    ("fs12", raw"current_prolog_flag(file_name_case_handling, R)"),
    ("fs13", raw"set_prolog_flag(file_name_case_handling, case_insensitive)"),
    ("fs14", raw"current_prolog_flag(theme, R)"),
    ("fs15", raw"set_prolog_flag(theme, default), current_prolog_flag(theme, R)"),
    ("fs16", raw"set_prolog_flag(theme, dark), current_prolog_flag(theme, R), set_prolog_flag(theme, default)"),
    ("fs17", raw"set_prolog_flag(theme, 1)"),
    ("fs18", raw"set_prolog_flag(string_stack_tripwire, 100), current_prolog_flag(string_stack_tripwire, R)"),
    ("fs19", raw"set_prolog_flag(string_stack_tripwire, 200), current_prolog_flag(string_stack_tripwire, R)"),
    ("fs20", raw"set_prolog_flag(string_stack_tripwire, -1)"),
    ("fs21", raw"set_prolog_flag(string_stack_tripwire, 4294967296)"),
    ("fs22", raw"current_prolog_flag(agc_margin, R)"),
    ("fs23", raw"set_prolog_flag(debug_on_interrupt, true), current_prolog_flag(debug_on_interrupt, R), set_prolog_flag(debug_on_interrupt, false)"),
    ("fs24", raw"set_prolog_flag(debug_on_interrupt, foo)"),
    ("fs25", raw"current_prolog_flag(debug_on_interrupt, R)")
]

# the answers the pin's swipl gives: the driver's first line, then one line per case
const _FS_PINNED = [
    # PINS-BEGIN
    "ok",
    "t_fs01 c[116,95,102,115,48,49]/1(a[101,114,114,111,114])",
    "t_fs02 c[116,95,102,115,48,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[105,110,99,111,109,112,97,114,97,98,108,101],a[102,111,111])))",
    "t_fs03 c[116,95,102,115,48,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_fs04 c[116,95,102,115,48,52]/1(a[97,114,98,105,116,114,97,114,121])",
    "t_fs05 c[116,95,102,115,48,53]/1(i100)",
    "t_fs06 c[116,95,102,115,48,54]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))",
    "t_fs07 c[116,95,102,115,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_fs08 c[116,95,102,115,48,56]/1(i2000000000)",
    "t_fs09 c[116,95,102,115,48,57]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))",
    "t_fs10 c[116,95,102,115,49,48]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[108,105,109,105,116],a[115,116,97,99,107,115],i1)))",
    "t_fs11 c[116,95,102,115,49,49]/1(i1073741824)",
    "t_fs12 c[116,95,102,115,49,50]/1(a[99,97,115,101,95,115,101,110,115,105,116,105,118,101])",
    "t_fs13 c[116,95,102,115,49,51]/1(c[114,97,105,115,101,100]/1(c[112,101,114,109,105,115,115,105,111,110,95,101,114,114,111,114]/3(a[109,111,100,105,102,121],a[102,108,97,103],a[102,105,108,101,95,110,97,109,101,95,99,97,115,101,95,104,97,110,100,108,105,110,103])))",
    "t_fs14 c[116,95,102,115,49,52]/1(a[100,101,102,97,117,108,116])",
    "t_fs15 c[116,95,102,115,49,53]/1(a[100,101,102,97,117,108,116])",
    "t_fs16 c[116,95,102,115,49,54]/1(a[100,97,114,107])",
    "t_fs17 c[116,95,102,115,49,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_fs18 c[116,95,102,115,49,56]/1(i100)",
    "t_fs19 c[116,95,102,115,49,57]/1(i200)",
    "t_fs20 c[116,95,102,115,50,48]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[117,105,110,116])))",
    "t_fs21 c[116,95,102,115,50,49]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[117,105,110,116])))",
    "t_fs22 c[116,95,102,115,50,50]/1(i10000)",
    "t_fs23 c[116,95,102,115,50,51]/1(a[116,114,117,101])",
    "t_fs24 c[116,95,102,115,50,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,111,111,108],a[102,111,111])))",
    "t_fs25 c[116,95,102,115,50,53]/1(a[102,97,108,115,101])"
    # PINS-END
]

"The program and cases as one file; the case predicates' names."
function _fs_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _FS_CASES]
    text = join([
        "t_$(id)(R) :- catch(($g), error(FsE, _), R = raised(FsE)).\n" for
        (id, g) in _FS_CASES
    ])
    f = joinpath(mktempdir(), "flagsetters.pl")
    write(f, text)
    return f, names
end

"The kernel's answers to the query `name(R)` in `gd`: the encoded lines, at most 50 answers; a Julia exception propagates."
function _fs_query(gd, ld, name::String)::String
    proc = LK.isCurrentProcedure(sym_key(_fss(name)), 1, LK.MODULE_user(gd))
    if proc === nothing || !LK.isDefinedProcedure(gd, proc)
        return "$name undefined"
    end
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_FS, LK.fresh_var_keys!(1)), LK.PutVarMap())
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
                    _fs_enc(mk_expr(_FS, _FS[_fss(name), lk_answers(ld, (a:a)...)...]))
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
function _fs_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_FS}()
    ld = LK.PL_local_data{_FS}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _fs_enc(ball::_FS)]
    for name in names
        push!(out, _fs_query(gd, ld, name))
    end
    return out, gd, ld
end

@testset "the flag setters as swipl's (fs01-fs25)" begin
    # UNVERIFIED on the kernel: gate decides (fs10 needs the kernel's stacks in use to exceed 1 byte; fs16 calls `\$toplevel:theme_changed/1`)
    f, names = _fs_file()
    kl, _, _ = _fs_kernel(f, names)
    @test length(kl) == length(_FS_PINNED)
    for (k, p) in zip(kl, _FS_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the pins hold both kinds of answer through the one extractor
    raised = "c" * _fs_codes("raised")
    @test count(l -> occursin(raised, l), _FS_PINNED) >= 8
    @test count(l -> !occursin(raised, l) && startswith(l, "t_"), _FS_PINNED) >= 8
    @test any(
        l ->
            startswith(l, "t_fs02 ") && occursin(
                "c" * _fs_codes("domain_error") * "/2(a" * _fs_codes("incomparable"), l
            ),
        _FS_PINNED
    )
end

# LK-ONLY: what the setters write (swipl has no field to read)
@testset "LK-ONLY: the setters write the local data and the atom table" begin
    # UNVERIFIED on the kernel: gate decides
    path = joinpath(mktempdir(), "wb.pl")
    write(
        path,
        "w_inc(R) :- set_prolog_flag(incomparable, error), R = ok.\n" *
        "w_arb(R) :- set_prolog_flag(incomparable, arbitrary), R = ok.\n" *
        "w_agc(R) :- set_prolog_flag(agc_margin, 123), R = ok.\n" *
        "w_stk(R) :- set_prolog_flag(stack_limit, 2000000000), R = ok.\n" *
        "w_sst0(R) :- set_prolog_flag(string_stack_tripwire, 0), R = ok.\n" *
        "w_sst(R) :- set_prolog_flag(string_stack_tripwire, 77), R = ok.\n"
    )
    gd = LK.PL_global_data{_FS}()
    ld = LK.PL_local_data{_FS}(gd)
    st, _ = LK.load_file!(gd, ld, path)
    @test st === :ok
    ok = "a" * _fs_codes("ok") * ")"
    @test !ld.prolog_flag_incomparable_error
    @test endswith(_fs_query(gd, ld, "w_inc"), ok)
    @test ld.prolog_flag_incomparable_error
    @test endswith(_fs_query(gd, ld, "w_arb"), ok)
    @test !ld.prolog_flag_incomparable_error
    @test endswith(_fs_query(gd, ld, "w_agc"), ok)
    @test gd.atoms.margin == 123
    @test endswith(_fs_query(gd, ld, "w_stk"), ok)
    @test ld.stacks_limit == 2000000000 ÷ 8
    # the first set creates the user flag (the setter is not reached), the second reaches it
    @test endswith(_fs_query(gd, ld, "w_sst0"), ok)
    @test endswith(_fs_query(gd, ld, "w_sst"), ok)
    @test ld.fli_string_buffers_tripwire == 77
end

# LK-ONLY: the file-name case mask (pl-prologflag.c setFileNameCaseHandlingName): case_sensitive sets both bits, case_preserving only the
# preserving one, case_insensitive neither; any other name is refused with false (setFileNameCaseHandling raises domain_error)
@testset "LK-ONLY: setFileNameCaseHandlingName sets the PLFLAG_FILE_CASE bits" begin
    # UNVERIFIED on the kernel: gate decides
    gd = LK.PL_global_data{_FS}()
    ld = LK.PL_local_data{_FS}(gd)
    bits() = (
        LK.truePrologFlag(ld, LK.PLFLAG_FILE_CASE),
        LK.truePrologFlag(ld, LK.PLFLAG_FILE_CASE_PRESERVING)
    )
    @test LK.setFileNameCaseHandlingName(ld, "case_sensitive")
    @test bits() == (true, true)
    @test LK.setFileNameCaseHandlingName(ld, "case_preserving")
    @test bits() == (false, true)
    @test LK.setFileNameCaseHandlingName(ld, "case_insensitive")
    @test bits() == (false, false)
    @test LK.setFileNameCaseHandlingName(ld, "case_sensitive")
    @test bits() == (true, true)
    @test !LK.setFileNameCaseHandlingName(ld, "case_something_else")
    @test bits() == (true, true)
    @test !LK.setFileNameCaseHandling(ld, _fss("zz_not_a_mode"))      # PL_error: false, the domain_error pending
end

# LK-ONLY twin of swipl's `--no-signals` run (swipl at the pin: `swipl --no-signals -g "set_prolog_flag(debug_on_interrupt, true)"` FAILS, and
# `current_prolog_flag(debug_on_interrupt, R)` then answers false): pl-prologflag.c:1344 `rval = enable_debug_on_interrupt(val)`, false while the
# flag `signals` is off, so the mask bit is not set and set_flag_value answers false (no error). The rows above cannot start swipl so.
@testset "LK-ONLY: debug_on_interrupt with the flag signals off fails and leaves the bit off (pl-prologflag.c:1344)" begin
    path = joinpath(mktempdir(), "dbi.pl")
    write(
        path,
        "w_dbi_on(R) :- set_prolog_flag(debug_on_interrupt, true), R = ok.\n" *
        "w_dbi_cur(R) :- current_prolog_flag(debug_on_interrupt, R).\n"
    )
    gd = LK.PL_global_data{_FS}()
    ld = LK.PL_local_data{_FS}(gd)
    st, _ = LK.load_file!(gd, ld, path)
    @test st === :ok
    @test LK.truePrologFlag(ld, LK.PLFLAG_SIGNALS)
    LK.clearPrologFlagMask!(ld, LK.PLFLAG_SIGNALS)
    @test !LK.truePrologFlag(ld, LK.PLFLAG_SIGNALS)
    @test _fs_query(gd, ld, "w_dbi_on") == "w_dbi_on"                    # no answer: the call failed
    @test !LK.truePrologFlag(ld, LK.PLFLAG_DEBUG_ON_INTERRUPT)
    @test _fs_query(gd, ld, "w_dbi_cur") == "w_dbi_cur a" * _fs_codes("false")
    LK.setPrologFlagMask!(ld, LK.PLFLAG_SIGNALS)
    @test endswith(_fs_query(gd, ld, "w_dbi_on"), "a" * _fs_codes("ok") * ")")
    @test LK.truePrologFlag(ld, LK.PLFLAG_DEBUG_ON_INTERRUPT)
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_FS_PINNED) == length(_FS_CASES) + 1
    if swipl === nothing
        @info "FL1 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _fs_file()
        @test _fs_swipl_lines(f, names) == _FS_PINNED
    end
end
