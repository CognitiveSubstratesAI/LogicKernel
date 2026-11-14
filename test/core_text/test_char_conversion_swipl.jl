# ORIGINAL: RD2b's gate — char_conversion/2, current_char_conversion/2 and the conversion table the reader applies while the flag `char_conversion` is set (src/pl-read.jl `initCharConversion`, `pl_char_conversion`, `pl_current_char_conversion`, `getchr__`, `init_read_data`) against swipl 10.1.20.
# test/core_text/test_char_conversion_swipl.jl — a program consulted by the kernel's loader whose cases `t_<id>(R)` run IN ORDER in one database
# (the design of test_read_comments_swipl.jl): cc01-cc02 the table is applied only while the flag is set; cc03-cc13 current_char_conversion/2 (bound In, the
# enumeration over the 256 codes, a bound Out, a one-character code or atom, the answers that differ from the identity); cc07-cc11, cc21-cc22 the errors of
# PL_get_char; cc14-cc19, cc25-cc33 the reader (cc31, cc33: the codes at the end of the table, 255): a quoted atom is read WITHOUT conversion (getchrq), a variable letter converted, a conversion that makes a
# syntax error, term_to_atom/2, read/2, read_clause/3, the comments option, the table read at the moment the term is read (the flag turned off between two reads),
# a conversion that is not chained (a to b and b to c reads `a` as `b`).
#   * Every case is wrapped in `setup_call_cleanup(true, once(Goal), cc_reset)`: the table and the flag are global in swipl, `cc_reset` restores the identity
#     and turns the flag off, so a case cannot disturb the next.
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, LC_ALL=C; two identical runs of the driver); with `swipl` on PATH the live answers are compared
#     with the pins too.
#   * NOT here: a code above 255 as In. Upstream writes and reads past its 257-entry table (an out-of-bounds access), so there is no answer to pin; the kernel
#     (DIVERGES in src/pl-read.jl) does not store it and fails the lookup.
#   * UNVERIFIED on the kernel: written without running the kernel (edit-only step); the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the stream readers, built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CC = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_ccs(x) = lk_sym(_CC, Symbol(x))

_cc_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _cc_enc(t::_CC, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        is_blob(t) && return "stream"           # the stream blobs of a permission_error / existence_error
        return is_nil(t) ? "nil" : "a" * _cc_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _cc_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _cc_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_cc_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the driver of test_at_body_swipl.jl (consult, then every answer of each t_<id>/1, `enc`oded)
const _CC_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- blob(T, stream), !, write(stream).
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
function _cc_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _CC_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        withenv("LC_ALL" => "C") do
            read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
        end
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: the table reset and the string opener. The case predicates follow, written by `_cc_file`.
const _CC_PROGRAM = raw"""
cc_reset :-
    set_prolog_flag(char_conversion, false),
    forall(between(0, 255, C), ( char_code(A, C), char_conversion(A, A) )).
rt_str(Text, S) :- open_string(Text, S).
"""

# (id, goal), run IN ORDER; `R` is the answer
const _CC_CASES = [
    (
        "cc01",
        raw"""char_conversion(a, b), set_prolog_flag(char_conversion, true), rt_str('f(a).', S), read_term(S,T,[]), R = T"""
    ),
    (
        "cc02",
        raw"""char_conversion(a, b), rt_str('f(a).', S), read_term(S,T,[]), R = T"""
    ),
    (
        "cc03",
        raw"""char_conversion(a, b), current_char_conversion(a, X), R = X"""
    ),
    (
        "cc04",
        raw"""current_char_conversion(c, X), R = X"""
    ),
    (
        "cc05",
        raw"""char_conversion(a, b), findall(I-O, current_char_conversion(I, O), L), length(L, N), L = [F|_], last(L, La), R = N-F-La"""
    ),
    (
        "cc06",
        raw"""char_conversion(a, b), char_conversion(x, y), findall(I-O, (current_char_conversion(I, O), I \== O), L), R = L"""
    ),
    (
        "cc07",
        raw"""char_conversion(1.5, a), R = x"""
    ),
    (
        "cc08",
        raw"""char_conversion(a, 1.5), R = x"""
    ),
    (
        "cc09",
        raw"""char_conversion(_, a), R = x"""
    ),
    (
        "cc10",
        raw"""char_conversion(0'a, 0'b), current_char_conversion(a, X), R = X"""
    ),
    (
        "cc11",
        raw"""char_conversion(ab, c), R = x"""
    ),
    (
        "cc12",
        raw"""( current_char_conversion(a, b) -> R = yes ; R = no )"""
    ),
    (
        "cc13",
        raw"""char_conversion(a, b), ( current_char_conversion(a, b) -> R = yes ; R = no )"""
    ),
    (
        "cc14",
        raw"""char_conversion(a, b), set_prolog_flag(char_conversion, true), rt_str('f(\'a\').', S), read_term(S,T,[]), R = T"""
    ),
    (
        "cc15",
        raw"""char_conversion('X', 'Y'), set_prolog_flag(char_conversion, true), rt_str('f(X, Y).', S), read_term(S,T,[]), R = T"""
    ),
    (
        "cc16",
        raw"""char_conversion(x, ' '), set_prolog_flag(char_conversion, true), rt_str('f(axb).', S), read_term(S,T,[]), R = T"""
    ),
    (
        "cc17",
        raw"""char_conversion(a, b), set_prolog_flag(char_conversion, true), term_to_atom(T, 'f(a)'), R = T"""
    ),
    (
        "cc18",
        raw"""set_prolog_flag(char_conversion, true), rt_str('f(a).', S), read_term(S,T,[]), R = T"""
    ),
    (
        "cc19",
        raw"""char_conversion(a, b), set_prolog_flag(char_conversion, true), rt_str('f(a). f(a).', S), read_term(S,T1,[]), set_prolog_flag(char_conversion, false), read_term(S,T2,[]), R = T1-T2"""
    ),
    (
        "cc21",
        raw"""char_conversion(end_of_file, a), R = x"""
    ),
    (
        "cc22",
        raw"""char_conversion(-1, a), R = x"""
    ),
    (
        "cc23",
        raw"""char_conversion(a, b), findall(I, current_char_conversion(I, b), L), R = L"""
    ),
    (
        "cc24",
        raw"""char_conversion(a, b), current_char_conversion(a, c) -> R = yes ; R = no"""
    ),
    (
        "cc25",
        raw"""char_conversion(a, b), char_conversion(b, c), set_prolog_flag(char_conversion, true), rt_str('g(a, b).', S), read_term(S,T,[]), R = T"""
    ),
    (
        "cc26",
        raw"""char_conversion(a, b), char_conversion(a, a), set_prolog_flag(char_conversion, true), rt_str('f(a).', S), read_term(S,T,[]), R = T"""
    ),
    (
        "cc27",
        raw"""char_conversion(a, b), set_prolog_flag(char_conversion, true), rt_str('% a\nf(a).', S), read_term(S,T,[comments(C)]), R = T-C"""
    ),
    (
        "cc28",
        raw"""char_conversion(a, b), set_prolog_flag(char_conversion, true), rt_str('f(a). g(a).', S), read_term(S,T1,[]), read_term(S,T2,[]), R = T1-T2"""
    ),
    (
        "cc29",
        raw"""char_conversion(a, b), set_prolog_flag(char_conversion, true), rt_str('f(a).', S), read(S,T), R = T"""
    ),
    (
        "cc30",
        raw"""char_conversion(a, b), set_prolog_flag(char_conversion, true), rt_str('f(a).', S), read_clause(S,T,[]), R = T"""
    ),
    (
        "cc31",
        raw"""char_conversion('\xff\', a), set_prolog_flag(char_conversion, true), rt_str('f(\xff\).', S), read_term(S,T,[]), R = T"""
    ),
    (
        "cc32",
        raw"""char_conversion('\xff\', a), current_char_conversion('\xff\', X), R = X"""
    ),
    (
        "cc33",
        raw"""char_conversion(a, '\xff\'), set_prolog_flag(char_conversion, true), rt_str('f(a).', S), read_term(S,T,[]), R = T"""
    )
]

# swipl 10.1.20, LC_ALL=C: the lines of the driver (two identical runs)
const _CC_PINNED = [
    "ok",
    "t_cc01 c[116,95,99,99,48,49]/1(c[102]/1(a[98]))",
    "t_cc02 c[116,95,99,99,48,50]/1(c[102]/1(a[97]))",
    "t_cc03 c[116,95,99,99,48,51]/1(a[98])",
    "t_cc04 c[116,95,99,99,48,52]/1(a[99])",
    "t_cc05 c[116,95,99,99,48,53]/1(c[45]/2(c[45]/2(i256,c[45]/2(a[0],a[0])),c[45]/2(a[255],a[255])))",
    "t_cc06 c[116,95,99,99,48,54]/1(c[91,124,93]/2(c[45]/2(a[97],a[98]),c[91,124,93]/2(c[45]/2(a[120],a[121]),nil)))",
    "t_cc07 c[116,95,99,99,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],f1.5)))",
    "t_cc08 c[116,95,99,99,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],f1.5)))",
    "t_cc09 c[116,95,99,99,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_cc10 c[116,95,99,99,49,48]/1(a[98])",
    "t_cc11 c[116,95,99,99,49,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[97,98])))",
    "t_cc12 c[116,95,99,99,49,50]/1(a[110,111])",
    "t_cc13 c[116,95,99,99,49,51]/1(a[121,101,115])",
    "t_cc14 c[116,95,99,99,49,52]/1(c[102]/1(a[97]))",
    "t_cc15 c[116,95,99,99,49,53]/1(c[102]/2(V0,V0))",
    "t_cc16 c[116,95,99,99,49,54]/1(c[114,97,105,115,101,100]/1(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])))",
    "t_cc17 c[116,95,99,99,49,55]/1(c[102]/1(a[98]))",
    "t_cc18 c[116,95,99,99,49,56]/1(c[102]/1(a[97]))",
    "t_cc19 c[116,95,99,99,49,57]/1(c[45]/2(c[102]/1(a[98]),c[102]/1(a[97])))",
    "t_cc21 c[116,95,99,99,50,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114],a[101,110,100,95,111,102,95,102,105,108,101])))",
    "t_cc22 c[116,95,99,99,50,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[99,104,97,114,97,99,116,101,114,95,99,111,100,101],i-1)))",
    "t_cc23 c[116,95,99,99,50,51]/1(c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil)))",
    "t_cc24 c[116,95,99,99,50,52]/1(a[110,111])",
    "t_cc25 c[116,95,99,99,50,53]/1(c[103]/2(a[98],a[99]))",
    "t_cc26 c[116,95,99,99,50,54]/1(c[102]/1(a[97]))",
    "t_cc27 c[116,95,99,99,50,55]/1(c[45]/2(c[102]/1(a[98]),c[91,124,93]/2(c[45]/2(c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4(i0,i1,i0,i0),s[37,32,98]),nil)))",
    "t_cc28 c[116,95,99,99,50,56]/1(c[45]/2(c[102]/1(a[98]),c[103]/1(a[98])))",
    "t_cc29 c[116,95,99,99,50,57]/1(c[102]/1(a[98]))",
    "t_cc30 c[116,95,99,99,51,48]/1(c[102]/1(a[98]))",
    "t_cc31 c[116,95,99,99,51,49]/1(c[102]/1(a[97]))",
    "t_cc32 c[116,95,99,99,51,50]/1(a[97])",
    "t_cc33 c[116,95,99,99,51,51]/1(c[102]/1(a[255]))"
]

"The program and cases as one file (in `dir`); the case predicates' names."
function _cc_file(dir::String)::Tuple{String, Vector{String}}
    ids = [id for (id, _) in _CC_CASES]
    goals = [g for (_, g) in _CC_CASES]
    names = ["t_$(id)" for id in ids]
    text =
        _CC_PROGRAM * join([
            "t_$(id)(R) :- catch(setup_call_cleanup(true, once(($g)), cc_reset), error(SsuE, _), R = raised(SsuE)).\n"
            for
            (id, g) in zip(ids, goals)
        ])
    f = joinpath(dir, "cc.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's. A Julia exception out of a row is its line: `jlerr <type> <what>`."
function _cc_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_CC}()
    ld = LK.PL_local_data{_CC}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _cc_enc(ball::_CC)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_ccs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        rld = LK.PL_local_data{_CC}(gd)        # a fresh engine per row: a Julia exception leaves no frame behind
        try
            fid = LK.PL_open_foreign_frame(rld)
            a = LK.PL_new_term_refs(rld, 1)
            LK.putSlotValue!(rld, a + 1, mk_var(_CC, LK.fresh_var_keys!(1)), LK.PutVarMap())
            qid = LK.PL_open_query(
                gd, rld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
            )
            n = 0
            while (n += 1) <= 50
                rc = LK.PL_next_solution(gd, rld, qid)
                if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                    push!(
                        sols,
                        _cc_enc(
                            mk_expr(_CC, _CC[_ccs(name), lk_answers(rld, (a:a)...)...])
                        )
                    )
                    rc == LK.PL_S_LAST && break
                elseif rc == LK.PL_S_EXCEPTION
                    push!(sols, "exception")
                    break
                else
                    break
                end
            end
            LK.PL_close_query(rld, qid)
            LK.PL_close_foreign_frame(rld, fid)
        catch e
            sols = [
                "jlerr $(nameof(typeof(e)))" * (e isa LK.NotPortedError ? " $(e.what)" : "")
            ]
        end
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end


@testset "char_conversion/2, current_char_conversion/2 and the reader's table as swipl's (cc01-cc33)" begin
    mktempdir() do dir
        f, names = _cc_file(dir)
        kl = _cc_kernel(f, names)
        @test length(kl) == length(_CC_PINNED)
        for (k, p) in zip(kl, _CC_PINNED)
            k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
            @test k == p
        end
    end
    # not vacuous: the pins hold converted and unconverted reads, the enumeration, the errors and the failures
    @test count(
        l -> occursin("/1(a[98])", l) || occursin("c[102]/1(a[98])", l), _CC_PINNED
    ) >= 6    # a read as b
    @test count(l -> occursin("c[102]/1(a[97])", l), _CC_PINNED) >= 3                                # a read as a (flag off, quoted, reset)
    @test count(
        l -> occursin("c[116,121,112,101,95,101,114,114,111,114]", l), _CC_PINNED
    ) >= 5      # type_error
    @test any(l -> occursin("i256", l), _CC_PINNED)                                                  # the enumeration
    @test count(l -> occursin("a[110,111]", l), _CC_PINNED) >= 2                                     # current_char_conversion failed
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_CC_PINNED) == length(_CC_CASES) + 1
    if swipl === nothing
        @info "RD2b LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        mktempdir() do dir
            f, names = _cc_file(dir)
            @test _cc_swipl_lines(f, names) == _CC_PINNED
        end
    end
end
