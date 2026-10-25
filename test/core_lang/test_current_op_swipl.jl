# ORIGINAL: a LIVE differential of current_op/3 and '$local_op'/3 (pl-op.c; registered by NF3, non-deterministic foreign predicates on NF1's mechanism, audit D-0136)
# test/core_lang/test_current_op_swipl.jl — current_op/3 and '$local_op'/3 against swipl at the pin, through a PROGRAM (the pattern of
# test/core_lang/test_between_swipl.jl): each case is a predicate `tN(R)`; the kernel consults the program and enumerates every
# solution of every tN/1, swipl does the same through a driver, and the answers are compared as lines. The cases are
# evidence/nf/rows.pl's o01–o12 (an error row reports its formal term: caught in the program, as between's rows) and NF3's own:
# a name with two kinds, the priority and type filters, a module qualifier (system, user, a module that does not exist, a
# variable one), the order in which the arguments are checked, '$local_op'/3 (the module's own table, not its supers'), a
# cancelled operator in `user` hiding `system`'s, and the three ways a state ends other than the last answer — a cut, an
# exception after a redo, an if-then-else — each with a state live. After EVERY case the pool of current_op's states
# is empty again (`live_states`, D-0136 Q8): a missing `FRG_CUTTED` shows as a count, named by its case.
#
# ORDER: the kernel's operator tables are Dicts, swipl's pl-table.c hash tables, so an enumeration's ORDER differs between
# them (the DIVERGES at `current_op_ndet`, audit D-0145: until pl-table.c is ported). No case compares the order of a multi-answer enumeration: they `msort` it, take the
# first answer of a one-answer enumeration, or throw/cut after an answer whose identity does not matter.
#
# NOT COMPARED: the whole table of `user` — swipl's boot files define `$` (fx 1) in it, which the kernel's boot does not (R2:
# test/core_lang/test_op_swipl.jl pins the same difference); no case enumerates an unbounded set that `$` is in.
#
# The last testsets open a query on current_op/3 itself: its retry arrives at `shallow_backtrack` with the foreign frame as
# `FR`, which no program reaches, and its answer SET is swipl's (order aside).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_TL, seen::Vector{UInt64}=UInt64[])::String
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

# the kernel's lines, and the live states of current_op's pool after each case (0 everywhere when no state leaked)
function kernel_lines(
    path::String, names::Vector{String}
)::Tuple{Vector{String}, Vector{Int}}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    lives = Int[]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(_TL, _TL[_tls(name), lk_answers(ld, (a:a)...)...]))
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
        push!(lives, LK.live_states(ld))
    end
    return out, lives
end

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
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# o01–o12: evidence/nf/rows.pl (an error row reports its formal term); then NF3's own, in the order of the header
const _OP_CASES = [
    raw"findall(P-T, current_op(P, T, mod), R0), msort(R0, R)",                    # o01
    raw"findall(T, current_op(200, T, **), R0), msort(R0, R)",                      # o02
    raw"op(700, xfx, ===>), findall(P-T, current_op(P, T, ===>), R), op(0, xfx, ===>)",  # o03
    raw"( current_op(_, _, ===>) -> R = yes ; R = no )",                            # o04: cancelled in user
    raw"catch(( current_op(1201, _, _), R = no ), error(E, _), R = E)",             # o05
    raw"catch(( current_op(_, foo, _), R = no ), error(E, _), R = E)",              # o06
    raw"catch(( current_op(_, _, 3), R = no ), error(E, _), R = E)",                # o07
    raw"current_op(P, xfx, is), !, R = P",                                          # o08
    raw"findall(N, current_op(1200, xfx, N), R0), msort(R0, R)",                    # o09
    raw"findall(T, current_op(_, T, -), R0), msort(R0, R)",                         # o10
    raw"findall(P, current_op(P, fy, \+), R)",                                      # o11
    raw"catch(( current_op(_, _, mod), throw(seen) ), seen, R = caught)",           # o12
    # one name, two kinds; the filters
    raw"findall(P-T, current_op(P, T, :-), R0), msort(R0, R)",                      # p01
    raw"findall(P-T, current_op(P, T, +), R0), msort(R0, R)",                       # p02
    raw"findall(T, current_op(500, T, +), R)",                                      # p03: priority filter
    raw"findall(T, current_op(300, T, +), R)",                                      # p04: no operator of that priority
    raw"findall(N, current_op(1200, fx, N), R0), msort(R0, R)",                     # p05: type + priority filter
    # the module qualifier
    raw"findall(N, current_op(1200, fx, user:N), R0), msort(R0, R)",               # p06: the name goes through the qualifier
    raw"findall(P-T, current_op(P, T, system:mod), R)",                             # p07
    raw"findall(P-T, current_op(P, T, nomod_zz:mod), R)",                           # p08: no such module: user
    raw"catch(( current_op(_, _, _:mod), R = no ), error(E, _), R = E)",            # p09: a variable qualifier
    # the order in which the first call checks its arguments: name, priority, type
    raw"catch(( current_op(1201, foo, 3), R = no ), error(E, _), R = E)",           # p10
    raw"catch(( current_op(1201, foo, mod), R = no ), error(E, _), R = E)",         # p11
    raw"catch(( current_op(a, _, mod), R = no ), error(E, _), R = E)",              # p12
    raw"catch(( current_op(0, _, mod), R = no ), error(E, _), R = E)",              # p13: 0 is no priority
    raw"catch(( current_op(_, 3, mod), R = no ), error(E, _), R = E)",              # p14
    # a state live when the call ends: a cut, an exception after a redo, an if-then-else
    raw"current_op(_, yfx, _), !, R = cut",                                         # p15
    raw"catch(( current_op(_, yfx, N1), current_op(_, yfx, N2), N1 \== N2, throw(two) ), two, R = caught2)",   # p16
    raw"( current_op(_, yfx, N), N == mod -> R = found ; R = no )",                 # p17
    raw"findall(N-P, current_op(P, yfx, N), R0), msort(R0, R)",                     # p18: every answer once
    # '$local_op'/3: the module's own table
    raw"findall(P-T, ( '$local_op'(P, T, N), N == mod ), R)",                       # q01: `mod` is system's, not user's
    raw"findall(P-T, '$local_op'(P, T, system:mod), R)",                            # q02
    raw"op(200, xfy, +++>), findall(P-T, '$local_op'(P, T, +++>), R)",              # q03
    raw"findall(P-T, current_op(P, T, +++>), R)",                                   # q04: current_op sees it too
    raw"findall(N, '$local_op'(1200, fx, N), R)",                                   # q05: none of user's own
    raw"'$local_op'(P, xfy, +++>), !, R = P",                                       # q06: a cut after the only answer
    raw"op(0, xfy, +++>), findall(P-T, '$local_op'(P, T, +++>), R)",                # q07: cancelled
    raw"catch(( '$local_op'(1201, _, _), R = no ), error(E, _), R = E)",            # q08
    raw"findall(P-T, '$local_op'(P, T, nomod_zz:mod), R)",                          # q09: no such module: user's own table
    # a cancelled and a redefined operator of user against system's (these end the program: they change `rem`)
    raw"op(0, yfx, rem), findall(P-T, current_op(P, T, rem), R), op(400, yfx, rem)",         # s01
    raw"op(250, yfx, rem), findall(P-T, current_op(P, T, rem), R0), msort(R0, R), op(400, yfx, rem)",  # s02
    raw"findall(P-T, '$local_op'(P, T, rem), R0), msort(R0, R)",                    # s03
    # swipl's own: the priority filter drops `user`'s 250 before `system`'s 400 is hidden by it, so the redefined operator
    # still answers 400 (pl-op.c addOpsFromTable); and an answer rewound after its name was bound (the name is the type)
    raw"op(250, yfx, rem), findall(T, current_op(400, T, rem), R0), msort(R0, R), op(400, yfx, rem)",    # s04
    raw"op(200, xfy, [zq1,zq2,zq3,zq4,zq5,zq6,zq7,zq8,zq9,zq10,zq11,zq12,zq13,zq14,zq15,zq16,zq17,zq18,zq19,zq20]), op(200, xfx, xfx), op(200, xfy, xfy), op(200, yfx, yfx), op(200, fy, fy), findall(T, current_op(_, T, T), R0), msort(R0, R), op(0, xfx, xfx), op(0, xfy, xfy), op(0, yfx, yfx), op(0, fy, fy), op(0, xfy, [zq1,zq2,zq3,zq4,zq5,zq6,zq7,zq8,zq9,zq10,zq11,zq12,zq13,zq14,zq15,zq16,zq17,zq18,zq19,zq20])"    # s05
]

@testset "current_op/3 and '\$local_op'/3 == live swipl, through a program; no state leaked" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "CURRENT_OP DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        names = ["t$(i - 1)" for i in eachindex(_OP_CASES)]
        text = join(["t$(i - 1)(R) :- ($g).\n" for (i, g) in enumerate(_OP_CASES)])
        f = joinpath(mktempdir(), "p.pl")
        write(f, text)
        sw = swipl_lines(f, names)
        kl, lives = kernel_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test kl == sw
        # not a vacuous agreement: swipl's own lines hold the answers, the errors and the cancelled operator
        @test any(
            l ->
                startswith(l, "t0 ") && occursin("i400", l) &&
                occursin("a[121,102,120]", l),
            sw
        )  # o01: 400-yfx
        @test any(l -> startswith(l, "t3 ") && occursin("a[110,111]", l), sw)       # o04: no
        @test any(l -> startswith(l, "t4 ") && occursin("i1201", l), sw)            # o05: domain_error(operator_priority, 1201)
        @test any(l -> startswith(l, "t6 ") && occursin("i3", l), sw)               # o07: type_error(atom, 3)
        @test any(l -> startswith(l, "t11 ") && occursin("a[99,97,117,103,104,116]", l), sw)  # o12: caught
        @test any(l -> startswith(l, "t12 ") && count("i1200", l) == 2, sw)         # p01: two kinds, one name
        @test any(l -> startswith(l, "t29 ") && count("c[45]/2", l) >= 10, sw)      # p18: the whole yfx set
        @test "t14 c[116,49,52]/1(c[91,124,93]/2(a[121,102,120],nil))" in sw        # p03: [yfx]
        @test "t15 c[116,49,53]/1(nil)" in sw                                       # p04: []
        @test any(l -> startswith(l, "t26 ") && occursin("a[99,117,116]", l), sw)   # p15: cut
        @test any(l -> startswith(l, "t42 ") && occursin("a[121,102,120]", l), sw)  # s04: the filter's quirk, [yfx]
        # s05: four operators named as their own type — a mutant that does not rewind a failed attempt
        # (NF3-16) keeps only those enumerated before the first of the 20 others: ~1 in 10 600 orders survive
        @test any(
            l ->
                startswith(l, "t43 ") &&
                all(
                    c -> occursin(c, l),
                    ("a[102,121]", "a[120,102,120]", "a[120,102,121]", "a[121,102,120]")
                ),
            sw
        )
        @test length(lives) == length(names)
        for (i, n) in enumerate(lives)
            @test (names[i], n) == (names[i], 0)
        end
    end
end

# The answers are the operators of the module and, for current_op/3, its supers' — and `inherit` makes the difference.
# The mechanism, queried directly: the retry arrives at `shallow_backtrack` with the foreign frame as `FR`.
function _open_op_query(gd, ld, name::String, priority, type::String)
    proc = LK.isCurrentProcedure(sym_key(_tls(name)), 3, LK.MODULE_system(gd))
    pvm = LK.PutVarMap()
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 3)
    if priority === nothing
        LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    else
        LK.putSlotValue!(ld, a + 1, mk_gnd(_TL, Int64(priority)), pvm)
    end
    LK.putSlotValue!(ld, a + 2, _tls(type), pvm)
    LK.putSlotValue!(ld, a + 3, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    return proc, fid, a, qid
end

@testset "current_op/3 queried directly: the retry backtracks into the foreign frame itself; its answers are swipl's" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    proc, fid, a, qid = _open_op_query(gd, ld, "current_op", nothing, "yfx")
    @test proc !== nothing
    # the supervisor is upstream's five words (pl-supervisor.c), the operand current_op/3's dispatch index
    d = proc.definition
    @test d.codes == [
        LK.I_FOPENNDET,
        LK.I_FCALLNDETVA,
        LK.code(d.impl_foreign_function),
        LK.I_FEXITNDET,
        LK.I_FREDO
    ]
    @test (d.flags & LK.P_FOREIGN) != 0 && (d.flags & LK.P_TRANSPARENT) != 0
    @test (d.flags & LK.P_ISO) != 0                         # PL_FA_ISO: current_op/3 is ISO
    got = String[]
    rcs = Int[]
    jumps = Tuple{Int, Int}[]
    while length(got) < 200
        rc = LK.PL_next_solution(gd, ld, qid)
        push!(rcs, rc)
        (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
        p, n = lk_answers(ld, a, a + 2)
        push!(got, "$(sym_text(n)) $(lk_value(p))")
        rc == LK.PL_S_LAST && break
        c = ld.choices[ld.BFR]
        @test c.type == LK.CHP_JUMP
        push!(jumps, (c.value_pc, c.frame))
        @test ld.frames[c.frame].fctx != 0 &&
            (ld.frames[c.frame].fctx & LK.FRG_REDO_MASK) == LK.REDO_PTR
        @test LK.live_states(ld) == 1
        @test ld.lTop == c.base + LK.SIZEOF_CHOICE + LK.SIZEOF_FLIFRAME
    end
    # every retry resumes at the I_FREDO word of the one foreign frame. Whether the LAST answer is deterministic is not
    # asserted: the scan keeps the infix KIND (xfx, xfy, yfx), `type` filters by unification, so the last yfx answer need not be
    # the buffer's last entry (as upstream's); determinism is asserted below, where the buffer holds one entry.
    @test length(jumps) == count(==(LK.PL_S_TRUE), rcs) && length(got) >= 10
    @test all(j -> j[1] == 5 && j[2] == jumps[1][2], jumps)
    @test rcs[end] == LK.PL_S_LAST || rcs[end] == LK.PL_S_FALSE
    @test allunique(first.(split.(got)))
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test LK.live_states(ld) == 0
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "CURRENT_OP ANSWER SET NOT COMPARED: `swipl` is not on PATH here."
    else
        want = split(
            chomp(
                read(
                    pipeline(
                        `swipl -q -g 'forall(current_op(P, yfx, N), format("~w ~w~n", [N, P]))' -t halt`;
                        stderr=devnull
                    ),
                    String
                )
            ),
            '\n'
        )
        @test length(want) >= 10 && sort(String.(want)) == sort(got)          # the SET: the order is not compared
    end
end

# pl-op.c current_op, FRG_CUTTED: the state is freed by `discardFrame` and not twice (the NF1-10 pattern).
@testset "current_op/3: a discarded foreign frame loses its context; a second discard is a no-op" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    _, fid, a, qid = _open_op_query(gd, ld, "current_op", nothing, "yfx")
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE
    fr = ld.choices[ld.BFR].frame
    @test ld.frames[fr].fctx != 0 && LK.live_states(ld) == 1
    LK.discardFrame(ld, fr)
    @test ld.frames[fr].fctx == 0
    @test LK.live_states(ld) == 0
    LK.discardFrame(ld, fr)
    @test ld.frames[fr].fctx == 0
    @test LK.live_states(ld) == 0
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test LK.live_states(ld) == 0
end

# a query closed with the state live (nothing cut it): `PL_close_query` discards the frame
@testset "'\$local_op'/3 queried directly: closing the query with a state live frees it; a last answer frees it by itself" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    # system's own table: every yfx operator of it is local to `system`
    proc = LK.isCurrentProcedure(sym_key(_tls("\$local_op")), 3, LK.MODULE_system(gd))
    @test proc !== nothing
    d = proc.definition
    @test (d.flags & LK.P_FOREIGN) != 0 && (d.flags & LK.P_TRANSPARENT) != 0
    @test (d.flags & LK.P_ISO) == 0                         # '$local_op'/3 is not
    pvm = LK.PutVarMap()
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 3)
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(ld, a + 2, _tls("yfx"), pvm)
    # the name is `system:Name`: the qualifier selects the module, the variable is bound through it
    LK.putSlotValue!(
        ld, a + 3,
        mk_expr(_TL, _TL[_tls(":"), _tls("system"), mk_var(_TL, LK.fresh_var_keys!(1))]),
        pvm
    )
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE
    @test LK.live_states(ld) == 1
    LK.PL_close_query(ld, qid)
    @test LK.live_states(ld) == 0
    LK.PL_close_foreign_frame(ld, fid)
    # one answer only: `mod` in `system`, the last answer is deterministic and the state is gone with it
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 3)
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(ld, a + 2, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(
        ld, a + 3, mk_expr(_TL, _TL[_tls(":"), _tls("system"), _tls("mod")]), pvm
    )
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_LAST
    p, t = lk_answers(ld, a, a + 1)
    @test lk_value(p) == 400 && sym_text(t) == "yfx"
    @test LK.live_states(ld) == 0
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test LK.live_states(ld) == 0
end
