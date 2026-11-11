# ORIGINAL: a LIVE differential of Q10's built-ins (`\=@=/2`, `shell/2`, `current_blob/2`, `$put_token/2`, `$on_signal/4`,
# `$set_prolog_stack/4`, `trim_heap/0`, `trim_stacks/0`, `thread_idle/2`) against swipl at the pin — Q10's rows
# test/core_lang/test_q10_swipl.jl — vr01-sh20 against swipl 10.1.20 (the pin 18168e62):
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_style_check_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (the pin's swipl, ~/.local/swipl-pin1-18168e62/bin/swipl, two identical runs, 2026-11-11); with
#     `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.

# TERM TYPES PER CHUNK: REFERENCE — the built-in rides the term layer through PL_unify_integer and PL_get_integer only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _QX = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_qxs(x) = lk_sym(_QX, Symbol(x))


_qx_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _qx_enc(t::_QX, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _qx_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _qx_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _qx_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_qx_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _QX_DRIVER = raw"""
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
function _qx_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _QX_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end




# the program the rows run against
const _QX_PROGRAM = raw"""
q_a(1).
"""

const _QX_CASES = [
    ("vr01", "( a \\=@= a -> R = yes ; R = no )"),   # equal atoms
    ("vr02", "( a \\=@= b -> R = yes ; R = no )"),   # different atoms
    ("vr03", "( f(A,B) \\=@= f(C,D) -> R = yes ; R = no )"),   # renamed variables
    ("vr04", "( f(A,A) \\=@= f(C,D) -> R = yes ; R = no )"),   # sharing differs
    ("vr05", "( f(A,B) \\=@= f(B,A) -> R = yes ; R = no )"),   # swapped variables
    ("vr06", "( f(A,A) \\=@= f(B,A) -> R = yes ; R = no )"),   # inconsistent renaming
    ("vr07", "( X \\=@= Y -> R = yes ; R = no )"),   # two fresh variables
    ("vr08", "( X \\=@= a -> R = yes ; R = no )"),   # variable and atom
    ("vr09", "( 1 \\=@= 1.0 -> R = yes ; R = no )"),   # swipl identity: 1 and 1.0 differ
    ("vr10", "( \"a\" \\=@= a -> R = yes ; R = no )"),   # string and atom
    ("vr11", "( [A,B|T] \\=@= [C,D|U] -> R = yes ; R = no )"),   # partial lists
    ("vr12", "X = 1, ( f(X) \\=@= f(1) -> R = yes ; R = no )"),   # under the bindings
    ("vr13", "A = f(A), B = f(B), ( A \\=@= B -> R = yes ; R = no )"),   # rational trees
    ("vr14", "put_attr(X, q10_dom, 1), ( X \\=@= Y -> R = yes ; R = no )"),   # an attributed variable
    ("vr15", "( a(A,B,A) \\=@= a(X,Y,Y) -> R = yes ; R = no )"),   # first and third against second and third
    ("vr16", "( call(\\=@=, f(A), f(B)) -> R = yes ; R = no )"),   # called with call/3
    ("vr17", "X is 2**70, Y is 2**70, ( X \\=@= Y -> R = yes ; R = no )"),   # equal big integers
    ("vr18", "( f(A) \\=@= g(A) -> R = yes ; R = no )"),   # different functors
    ("vr19", "( f(A) \\=@= f(A,B) -> R = yes ; R = no )"),   # different arities
    ("vr20", "( f(A,g(B,A)) \\=@= f(C,g(D,C)) -> R = yes ; R = no )"),   # nested sharing
    ("sh01", "shell(true, R)"),   # status 0
    ("sh02", "shell('exit 3', R)"),   # status 3
    ("sh03", "shell(\"exit 4\", R)"),   # a string
    ("sh04", "atom_codes('exit 6', Cs), shell(Cs, R)"),   # a code list
    ("sh05", "shell(_, R)"),   # unbound command
    ("sh06", "shell(f(x), R)"),   # a compound command
    ("sh07", "( shell(true, 1) -> R = yes ; R = no )"),   # the status does not unify
    ("sh08", "( shell(true, 0) -> R = yes ; R = no )"),   # the status unifies
    ("sh09", "shell('exit 300', R)"),   # status modulo 256
    ("sh10", "shell('test \"\$PROLOGCHILD\" = yes', R)"),   # the child has PROLOGCHILD=yes
    ("sh11", "shell('kill -9 \$\$', R)"),   # the shell is killed by a signal
    ("sh12", "shell(false, R)"),   # status 1
    ("sh13", "shell('q10_no_such_command 2>/dev/null', R)"),   # command not found: 127
    ("sh14", "setenv(q10_var, hello), shell('test \"\$q10_var\" = hello', R)"),   # the environment set by setenv/2
    ("sh15", "shell('exit 256', R)"),   # 256 wraps to 0
    ("sh16", "shell('', R)"),   # the empty command
    ("sh17", "shell('exit 2', 2), R = ok"),   # the status given
    ("sh18", "shell('exit 7 # \\u00e9', R)"),   # a non-ASCII character in a comment
    ("sh19", "shell(42, R)"),   # a number as the command: the shell cannot find 42
    ("sh20", "shell('exit 5', R), integer(R)")    # an integer status
]

# the driver's whole output, one line per case after `ok`, from swipl at the pin
const _QX_PINNED = [
    "ok",
    "t_vr01 c[116,95,118,114,48,49]/1(a[110,111])",
    "t_vr02 c[116,95,118,114,48,50]/1(a[121,101,115])",
    "t_vr03 c[116,95,118,114,48,51]/1(a[110,111])",
    "t_vr04 c[116,95,118,114,48,52]/1(a[121,101,115])",
    "t_vr05 c[116,95,118,114,48,53]/1(a[110,111])",
    "t_vr06 c[116,95,118,114,48,54]/1(a[121,101,115])",
    "t_vr07 c[116,95,118,114,48,55]/1(a[110,111])",
    "t_vr08 c[116,95,118,114,48,56]/1(a[121,101,115])",
    "t_vr09 c[116,95,118,114,48,57]/1(a[121,101,115])",
    "t_vr10 c[116,95,118,114,49,48]/1(a[121,101,115])",
    "t_vr11 c[116,95,118,114,49,49]/1(a[110,111])",
    "t_vr12 c[116,95,118,114,49,50]/1(a[110,111])",
    "t_vr13 c[116,95,118,114,49,51]/1(a[110,111])",
    "t_vr14 c[116,95,118,114,49,52]/1(a[121,101,115])",
    "t_vr15 c[116,95,118,114,49,53]/1(a[121,101,115])",
    "t_vr16 c[116,95,118,114,49,54]/1(a[110,111])",
    "t_vr17 c[116,95,118,114,49,55]/1(a[110,111])",
    "t_vr18 c[116,95,118,114,49,56]/1(a[121,101,115])",
    "t_vr19 c[116,95,118,114,49,57]/1(a[121,101,115])",
    "t_vr20 c[116,95,118,114,50,48]/1(a[110,111])",
    "t_sh01 c[116,95,115,104,48,49]/1(i0)",
    "t_sh02 c[116,95,115,104,48,50]/1(i3)",
    "t_sh03 c[116,95,115,104,48,51]/1(i4)",
    "t_sh04 c[116,95,115,104,48,52]/1(i6)",
    "t_sh05 c[116,95,115,104,48,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_sh06 c[116,95,115,104,48,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120]))))",
    "t_sh07 c[116,95,115,104,48,55]/1(a[110,111])",
    "t_sh08 c[116,95,115,104,48,56]/1(a[121,101,115])",
    "t_sh09 c[116,95,115,104,48,57]/1(i44)",
    "t_sh10 c[116,95,115,104,49,48]/1(i0)",
    "t_sh11 c[116,95,115,104,49,49]/1(c[114,97,105,115,101,100]/1(c[115,104,101,108,108]/2(c[115,105,103,110,97,108]/1(i9),a[107,105,108,108,32,45,57,32,36,36])))",
    "t_sh12 c[116,95,115,104,49,50]/1(i1)",
    "t_sh13 c[116,95,115,104,49,51]/1(i127)",
    "t_sh14 c[116,95,115,104,49,52]/1(i0)",
    "t_sh15 c[116,95,115,104,49,53]/1(i0)",
    "t_sh16 c[116,95,115,104,49,54]/1(i0)",
    "t_sh17 c[116,95,115,104,49,55]/1(a[111,107])",
    "t_sh18 c[116,95,115,104,49,56]/1(i7)",
    "t_sh19 c[116,95,115,104,49,57]/1(i127)",
    "t_sh20 c[116,95,115,104,50,48]/1(i5)"
]

# the kernel's lines where they differ from swipl's (see the header)
const _QX_KERNEL_DIFF = Dict{String, String}()
_qx_expected(p::String) = get(_QX_KERNEL_DIFF, first(split(p, ' ')), p)

function _qx_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _QX_CASES]
    text =
        _QX_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _QX_CASES
        ])
    f = joinpath(mktempdir(), "q10.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _qx_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_QX}()
    ld = LK.PL_local_data{_QX}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _qx_enc(ball::_QX)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_qxs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_QX, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _qx_enc(mk_expr(_QX, _QX[_qxs(name), lk_answers(ld, (a:a)...)...]))
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

@testset "the Q10 built-ins as swipl's (vr01-sh20)" begin
    f, names = _qx_file()
    kl, _, _ = _qx_kernel(f, names)
    @test length(kl) == length(_QX_PINNED)
    for (k, p) in zip(kl, _QX_PINNED)
        want = _qx_expected(p)
        k == want || println(stderr, "  ours  ", k, "\n  want  ", want)
        @test k == want
    end
end

@testset "the Q10 rows are not vacuous" begin
    # the program loaded; every row has its answer line; the failing and raising rows are told apart from the answering ones
    @test _QX_PINNED[1] == "ok"
    @test length(_QX_PINNED) == length(_QX_CASES) + 1
    for (id, _) in _QX_CASES
        @test any(l -> startswith(l, "t_$id "), _QX_PINNED)
    end
    @test count(l -> occursin("c" * _qx_codes("raised"), l), _QX_PINNED) == 3      # sh05, sh06, sh11
    @test count(l -> occursin("a" * _qx_codes("yes"), l), _QX_PINNED) >= 9          # the \\=@= rows that answer yes
    @test any(l -> startswith(l, "t_sh11 ") && occursin(_qx_codes("signal"), l), _QX_PINNED)   # a child killed by signal 9
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_QX_PINNED) == length(_QX_CASES) + 1
    if swipl === nothing
        @info "Q10 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _qx_file()
        @test _qx_swipl_lines(f, names) == _QX_PINNED
    end
end

