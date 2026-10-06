# ORIGINAL: V6b's gate — the type tests (var/1 … callable/1) registered, called and compiled inline, against swipl; upstream has no such test.
# test/foreign/test_typetests_swipl.jl — the type tests at RUN time (port_inventory row V6, V6b),
# against swipl. Their compiled code, cell by cell, is test/compile/test_body_code_swipl.jl's.
#
#   * registered as upstream's table registers them (pl-prims.c): ISO but `rational/1` and
#     `string/1`;
#   * the TRUTH TABLE of the eleven tests on thirteen values of every kind — SWI-7's `[]` against the
#     text atom `'[]'`, a bigint, a rational, `[](a)` against `'[]'(a)` — three ways: called as a
#     query, compiled INLINE (`t(X) :- integer(X).` is `I_INTEGER`, asserted) and compiled as a CALL
#     (`t :- integer(Value).`). Pinned to swipl 10.1.16 (the research probe, scratchpad
#     v6c/p10_typetable.pl) and compared with a live swipl. The two non-ISO tests are not reached by
#     a body CALL until module resolution (V5c, the user's Q-A): `lookupBodyProcedure` binds only
#     ISO built-ins, so the call raises `existence_error` — pinned, so it is seen when it changes;
#   * the kernel-only rows (no SWI counterpart, `# DIVERGES`): a compound with a non-symbol head
#     (`$expr/n`) is a compound and not callable; a grounded value of no SWI type (`NUM_OTHER`) is
#     atomic and nothing else.
#
# swipl present ⇒ the live comparison runs. Absent: an ERROR when LOGICKERNEL_REQUIRE_SWIPL=1,
# otherwise a LOUD note plus an assertion that it was not required — never a silent pass.
using Test, LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
const LKT = LogicKernel
_tts(x) = lk_sym(_TT, Symbol(x))
_ttg(x) = lk_gnd(_TT, x)
_ttf(f, xs::_TT...) = mk_expr(_TT, _TT[_tts(f), xs...])

const _TT_TESTS = (
    :var, :nonvar, :integer, :rational, :float, :number, :atomic, :atom, :string, :compound,
    :callable
)
const _TT_INSTR = (
    LKT.I_VAR, LKT.I_NONVAR, LKT.I_INTEGER, LKT.I_RATIONAL, LKT.I_FLOAT, LKT.I_NUMBER,
    LKT.I_ATOMIC, LKT.I_ATOM, LKT.I_STRING, LKT.I_COMPOUND, LKT.I_CALLABLE
)

# The values (the probe's names), and swipl 10.1.16's answers, one character per test in
# `_TT_TESTS`' order: `T` true, `.` false (scratchpad v6c/p10_typetable.out).
const _TT_VALUES = (
    ("V", mk_var(_TT, UInt64(1)), "T.........."),
    ("1", _ttg(1), ".TTT.TT...."),
    ("2^70", _ttg(big(2)^70), ".TTT.TT...."),
    ("1r3", _ttg(1 // big(3)), ".T.T.TT...."),
    ("1.5", _ttg(1.5), ".T..TTT...."),
    ("\"s\"", _ttg("s"), ".T....T.T.."),
    ("a", _tts(:a), ".T....TT..T"),
    ("[]", mk_nil(_TT), ".T....T...."),
    ("'[]'", _tts("[]"), ".T....TT..T"),
    ("f(a)", _ttf(:f, _tts(:a)), ".T.......TT"),
    ("[a|b]", _ttf("[|]", _tts(:a), _tts(:b)), ".T.......TT"),
    ("'[]'(a)", _ttf("[]", _tts(:a)), ".T.......TT"),
    ("[](a)", mk_expr(_TT, _TT[mk_nil(_TT), _tts(:a)]), ".T.......TT")
)

function _ttdb()
    gd = LKT.PL_global_data{_TT}()
    return (gd, LKT.PL_local_data{_TT}(), LKT.MODULE_user(gd))
end

"Run `proc` on `args` once: true, false, or the error's formal functor name (`existence_error`)."
function _ttrun(gd, ld, proc, args::Vector{_TT})::String
    fid = LKT.PL_open_foreign_frame(ld)
    a = LKT.PL_new_term_refs(ld, max(length(args), 1))
    for (k, t) in enumerate(args)
        ld.slots[a + k] = t
    end
    qid = LKT.PL_open_query(
        gd, ld, nothing, LKT.PL_Q_CATCH_EXCEPTION | LKT.PL_Q_EXT_STATUS, proc, a
    )
    rc = LKT.PL_next_solution(gd, ld, qid)
    out = if rc == LKT.PL_S_EXCEPTION
        ball = LKT.resolve_term(ld, ld.slots[LKT.PL_exception(ld, qid) + 1])
        String(lk_name(child(child(ball, 2), 1)))
    else
        rc == LKT.PL_S_FALSE ? "false" : "true"
    end
    LKT.PL_close_query(ld, qid)
    LKT.PL_close_foreign_frame(ld, fid)
    return out
end

"Compile and add `head :- body`."
function _ttadd!(gd, ld, user, head::_TT, body::_TT)
    name, n = kind(head) === SYM ? (head, 0) : (child(head, 1), nchildren(head) - 1)
    pr = LKT.lookupProcedure(name, n, user)
    cl = LKT.compileClause(gd, ld, head, body, pr, user)
    LKT.assertDefinition!(gd, pr.definition, cl, LKT.CL_END)
    return pr, cl
end

_ttsys(gd, name::Symbol, n::Int) =
    LKT.isCurrentProcedure(sym_key(_tts(name)), n, LKT.MODULE_system(gd))

@testset "the type tests and \\== registered as upstream's table registers them" begin
    gd, _, _ = _ttdb()
    for (name, n) in ((t, 1) for t in _TT_TESTS)
        p = _ttsys(gd, name, n)
        @test p !== nothing
        d = p.definition
        @test (d.flags & LKT.P_FOREIGN) != 0
        @test ((d.flags & LKT.P_ISO) != 0) == !(name in (:rational, :string))
    end
    @test _ttsys(gd, Symbol("\\=="), 2) !== nothing
end

"The kernel's row for value `v`: called (`:call`), inline (`:inline`) or as a body call (`:body`)."
function _ttrow(gd, ld, user, name::String, v::_TT, how::Symbol)::String
    out = IOBuffer()
    for t in _TT_TESTS
        r = if how === :call
            _ttrun(gd, ld, _ttsys(gd, t, 1), _TT[v])
        elseif how === :inline
            pr = LKT.lookupProcedure(_tts("ti_$t"), 1, user)
            _ttrun(gd, ld, pr, _TT[v])
        else
            pr = LKT.lookupProcedure(_tts("tb_$(t)_$name"), 0, user)
            _ttrun(gd, ld, pr, _TT[])
        end
        print(
            out,
            if r == "true"
                'T'
            elseif r == "false"
                '.'
            else
                (t in (:rational, :string) ? 'E' : '?')
            end
        )
    end
    return String(take!(out))
end

@testset "the truth table, called, inline and as a body call, is swipl's" begin
    gd, ld, user = _ttdb()
    X = mk_var(_TT, UInt64(2))
    for (k, t) in enumerate(_TT_TESTS)
        _, cl = _ttadd!(gd, ld, user, _ttf("ti_$t", X), _ttf(t, X))   # inline: X is an argument
        @test _TT_INSTR[k] in cl.codes
    end
    for (name, v, _) in _TT_VALUES, t in _TT_TESTS                     # a CALL: a value argument
        _, cl = _ttadd!(gd, ld, user, _tts("tb_$(t)_$name"), _ttf(t, v))
        @test !(_TT_INSTR[findfirst(==(t), _TT_TESTS)] in cl.codes)
    end
    for (name, v, want) in _TT_VALUES
        @test _ttrow(gd, ld, user, name, v, :call) == want
        @test _ttrow(gd, ld, user, name, v, :inline) == want
        # rational/1, string/1 from a body: user:rational/1 until module resolution (V5c, Q-A)
        body = collect(want)
        body[4] = body[9] = 'E'
        @test _ttrow(gd, ld, user, name, v, :body) == String(body)
    end
end

const _TT_SWIPL = Sys.which("swipl")
const _TT_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

if _TT_SWIPL !== nothing
    @testset "the pinned truth table == live swipl's" begin
        prog = raw"""
        :- set_prolog_flag(prefer_rationals, false).
        tests([var, nonvar, integer, rational, float, number, atomic, atom, string, compound, callable]).
        vals(['V'-_, '1'-1, '2^70'-X70, '1r3'-R, '1.5'-1.5, '"s"'-"s", a-a, '[]'-[], '\'[]\''-'[]',
              'f(a)'-f(a), '[a|b]'-[a|b], '\'[]\'(a)'-'[]'(a), '[](a)'-NilA]) :-
            X70 is 2^70, R is 1 rdiv 3, compound_name_arguments(NilA, [], [a]).
        row(V, Row) :- tests(Ts), findall(C, (member(T, Ts), G =.. [T, V], (call(G) -> C = 0'T ; C = 0'.)), Cs),
            atom_codes(Row, Cs).
        :- initialization((vals(Vs), forall(member(N-V, Vs), (row(V, R), format("~w ~w~n", [N, R]))), halt)).
        """
        text = mktempdir() do d
            f = joinpath(d, "tt.pl")
            write(f, prog)
            read(`swipl -q $f`, String)
        end
        lines = split(strip(text), '\n')
        @test length(lines) == length(_TT_VALUES)
        for (k, (name, _, want)) in enumerate(_TT_VALUES)
            k <= length(lines) || break
            got = rsplit(lines[k], ' '; limit=2)
            @test got[1] == name && got[2] == want
        end
    end
elseif _TT_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the truth-table comparison would be skipped"
    )
else
    @info "TYPE-TEST TRUTH TABLE vs swipl NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "truth-table comparison skipped only where it is not required" begin
        @test !_TT_SWIPL_REQUIRED
    end
end

@testset "kernel-only terms (no SWI counterpart): \$expr/n and a value of no SWI type" begin
    gd, ld, user = _ttdb()
    X = mk_var(_TT, UInt64(2))
    for t in _TT_TESTS
        _ttadd!(gd, ld, user, _ttf("ti_$t", X), _ttf(t, X))
    end
    ex = mk_expr(_TT, _TT[mk_var(_TT, UInt64(7)), _tts(:a)])        # (V a): `$expr/2`
    @test _ttrow(gd, ld, user, "expr", ex, :call) == ".T.......T."   # compound, not callable
    @test _ttrow(gd, ld, user, "expr", ex, :inline) == ".T.......T."
    O = lk_term_type(Union{Int64, Bool})
    ogd = LKT.PL_global_data{O}()
    old = LKT.PL_local_data{O}()
    v = lk_gnd(O, true)                                             # NUM_OTHER
    row = map(_TT_TESTS) do t
        p = LKT.isCurrentProcedure(sym_key(lk_sym(O, t)), 1, LKT.MODULE_system(ogd))
        fid = LKT.PL_open_foreign_frame(old)
        a = LKT.PL_new_term_ref(old)
        old.slots[a + 1] = v
        qid = LKT.PL_open_query(ogd, old, nothing, LKT.PL_Q_EXT_STATUS, p, a)
        rc = LKT.PL_next_solution(ogd, old, qid)
        LKT.PL_close_query(old, qid)
        LKT.PL_close_foreign_frame(old, fid)
        rc == LKT.PL_S_FALSE ? '.' : 'T'
    end
    @test String(collect(row)) == ".T....T...."                     # atomic only
end
