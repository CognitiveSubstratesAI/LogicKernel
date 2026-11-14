# ORIGINAL: a differential of TR1's trie predicates (pl-trie.c: trie_new/1, trie_destroy/1, is_trie/1, trie_insert/2,3,4, trie_update/3,
# trie_delete/3, trie_lookup/3, trie_term/2, '$trie_insert_abstract'/3) against swipl at the pin (10.1.20, 18168e62)
# allow-new-artifact: TR1 part B5, the predicate rows of the trie port, after test/core_lang/test_sys_swipl.{jl,pl,out} and test/core_lang/test_wrap_swipl.{jl,pl,out}
# test/core_lang/test_trie_preds_swipl.jl — through a PROGRAM (the pattern of test/core_lang/test_sys_swipl.jl and test_wrap_swipl.jl):
# test_trie_preds_swipl.pl holds the rows, each a predicate `tN(R)`; the kernel consults the program and enumerates every solution of
# every tN/1, and its lines are compared with test_trie_preds_swipl.out — swipl's own, printed by the driver below (`ok`, then one line
# per row: its name and every solution). When `swipl` is on PATH the .out is checked against a live run as well.
# A row never encodes a trie (a blob: it has no stable text) and never a node handle (swipl's is a pointer, the kernel's an integer): an
# error that names a trie is scrubbed to '<trie>' in the program, a handle goes only to trie_term/2. Rows that need an order of answers
# are not here: nothing TR1 registers enumerates (trie_gen/2,3 are TR2's).
# NAMED KNOWN DIFFERENCES (kernel-only testsets at the end; the checklist items are in the testsets' text):
#   KD-1 a bad node handle: `trie_term(foo, _)` is type_error(address, foo) in both (PL_get_pointer_ex; the handle is an integer here);
#        an integer naming no node is an existence_error(trie_node, H) here, undefined behaviour
#        in swipl (a fault on 0, a read of freed memory on a destroyed trie) — those rows have NO swipl answer.
#   (KD-2, an attributed variable in a key, is gone: TR3 ports it, O_TRIE_ATTVAR is defined at the pin (pl-incl.h:256); rows t71-t73 and
#        t77-t86 are compared with swipl's answers.)
# The kill rows are `@test`s INSIDE testsets (a top-level failing `@test` gives no verdict in CI mode).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_TP, seen::Vector{UInt64}=UInt64[])::String
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

const _TRIE_PL = joinpath(@__DIR__, "test_trie_preds_swipl.pl")
const _TRIE_OUT = joinpath(@__DIR__, "test_trie_preds_swipl.out")

# the rows' names, in the order of a program
_row_names(path::String, re::Regex) =
    unique([String(m[1]) for m in eachmatch(re, read(path, String))])
_trie_names() = _row_names(_TRIE_PL, r"^(t\d+)\(R\) :-"m)

# a fresh kernel with `path` consulted: `(gd, ld, "ok" or "exc <ball>")`
function _tp_load(::Type{T}, path::String) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * enc(ball::T))
end

# the driver's line for the row `name`/1 (every answer, at most 100): the name, then each solution
function _tp_row(
    gd::LK.PL_global_data{T}, ld::LK.PL_local_data{T}, name::String
)::String where {T}
    proc = LK.isCurrentProcedure(sym_key(lk_sym(T, Symbol(name))), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$name undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), LK.PutVarMap())
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
                    enc(
                        mk_expr(T, T[lk_sym(T, Symbol(name)), lk_answers(ld, (a:a)...)...])
                    )
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
    return "$name" * join(" " .* sols)
end

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd, ld, st = _tp_load(_TP, path)
    return vcat([st], [_tp_row(gd, ld, name) for name in names])
end

# the driver swipl runs to print its lines (the .out is its output; the text of test_sys_swipl.jl's DRIVER)
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
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# expected lines, built from pieces (the answers are swipl's, read from the .out): an atom, an integer, a list, a compound, an error
_ea(s::String) = "a" * _codes(s)
_ei(n::Integer) = "i$n"
_el(items::Vector{String}) = foldr((x, acc) -> "c[91,124,93]/2($x,$acc)", items; init="nil")
_ec(f::String, args::String...) =
    "c" * _codes(f) * "/$(length(args))(" * join(args, ",") * ")"
_er(name::String, answer::String) = "$name " * _ec(name, answer)
_head(name::String) = "$name c" * _codes(name) * "/1("      # the line up to the opening of the answer
_pair(a::String, b::String) = _ec("-", a, b)
_ctx(pred::String, arity::Int, v::Int) =
    _ec("context", _ec(":", _ea("system"), _ec("/", _ea(pred), _ei(arity))), "V$v")
_err(formal::String, pred::String, arity::Int, v::Int) =
    _ec("error", formal, _ctx(pred, arity, v))
_atoms(xs...) = _el([_ea(String(x)) for x in xs])
_modify(k::String) = _ec("permission_error", _ea("modify"), _ea("trie_key"), k)
_insert_perm() = _ec("permission_error", _ea("insert"), _ea("trie"), _ea("<trie>"))
const _T = _ea("true")
const _F = _ea("false")

@testset "TR1: the trie predicates == swipl's answers (the .out), through a program" begin
    names = _trie_names()
    expected = String.(readlines(_TRIE_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test length(names) >= 87
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test count(l -> occursin(_codes("permission_error"), l), expected) >= 10
    @test count(l -> occursin(_codes("existence_error"), l), expected) >= 2         # a destroyed trie
    @test count(
        l -> occursin(_codes("type_error"), l) && occursin(_codes("trie"), l), expected
    ) >= 5
    @test any(l -> occursin(_codes("instantiation_error"), l), expected)
    @test any(l -> occursin(_codes("acyclic_term"), l), expected)                  # a cyclic key
    @test any(l -> occursin(_codes("not_less_than_zero"), l), expected)            # '$trie_insert_abstract' with a size < 0
    @test any(l -> occursin(_codes("representation_error"), l), expected)          # ... with a size past size_t
    @test any(l -> occursin(_codes("set_value"), l), expected)                     # the value of a set trie
    @test any(l -> occursin(_codes("trie_key"), l), expected)                      # permission_error(modify, trie_key, _)
    @test !any(l -> occursin(r"export-error|undefined| exception$", l), expected)
    @test !any(l -> occursin(r"0x[0-9a-f]{6}", l), expected)                       # no pointer in a line

    kl = kernel_lines(_TRIE_PL, names)
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TRIE-PREDICATE DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_TRIE_PL, names) == expected             # the .out is swipl's, still
    end
end

# The kill rows: the answers of single rows, built from pieces here and equal to the .out's (swipl's); each fails on its own when the
# one thing it names breaks, so a mutant shows as a named verdict and not only as a changed line of the file.
@testset "TR1 kill rows: each row's answer, by name" begin
    gd, ld, st = _tp_load(_TP, _TRIE_PL)
    @test st == "ok"
    row(n) = _tp_row(gd, ld, n)
    # trie_new/is_trie/trie_destroy
    @test row("t0") == _er("t0", _ea("ok"))
    @test row("t2") == _er("t2", _F)
    @test row("t3") == _er("t3", _ea("no"))
    @test row("t6") == _er("t6", _el([_F, _F, _F, _F]))                                  # trie_new on a non-variable
    @test row("t7") == _er("t7", _atoms("different", "same", "same", "trie"))            # a trie is its own identity; a copy is it
    @test row("t4") == _er(
        "t4", _err(_ec("existence_error", _ea("trie"), _ea("<trie>")), "trie_destroy", 1, 0)
    )
    # the two kinds of trie
    @test row("t14") == _er(
        "t14",
        _el([
            _err(_insert_perm(), "trie_insert", 3, 0),
            _err(_insert_perm(), "trie_insert", 4, 1),
            _err(_insert_perm(), "trie_update", 3, 2), _ea("absent"), _ea("inserted")
        ])
    )
    @test row("t16") ==
        _er("t16", _el([_T, _err(_modify(_ea("k")), "trie_insert", 3, 0), _ei(1)]))
    @test row("t17") == _er(
        "t17",
        _el([
            _T,
            _err(_insert_perm(), "trie_insert", 2, 0),
            _F,
            _err(_modify(_ea("k")), "trie_insert", 3, 1)
        ])
    )
    # insert/2 of every kind of ground term, the second insert fails, the lookup gives the set value
    @test startswith(
        row("t18"),
        _head("t18") * "c[45]/2(c[45]/2(" * _el(fill(_T, 19)) * "," * _el(fill(_F, 19)) *
        "),c[91,124,93]/2("
    )
    @test row("t20") == _er("t20", _el([_T, _T, _T, _T, _F, _F, _F, _F]))                 # 0.0, -0.0, 1.0, 1 are four keys
    @test row("t21") == _er(
        "t21", _el([_T, _T, _T, _F, _F, _F, _ea("found"), _ea("found"), _ea("found")])
    )
    @test row("t22") == _er("t22", _el([_T, _T, _F, _ea("found"), _ea("found")]))        # rationals
    @test row("t23") ==
        _er("t23", _el([_T, _T, _F, _ea("found"), _ea("found"), _ea("absent")]))   # bigints
    # maps
    @test row("t25") == _er(
        "t25",
        _el([
            _F,
            _err(_modify(_ea("k")), "trie_insert", 3, 0),
            _err(_modify(_ea("k")), "trie_insert", 3, 1),
            _ea("v")
        ])
    )
    @test row("t28") == _er("t28", _atoms("v", "no", "no", "no"))
    @test row("t30") ==
        _er("t30", _el([_T, _ei(1), _T, _ei(2), _T, _ei(2), _T, _ec("f", "V0")]))
    @test row("t31") ==
        _er("t31", _el([_T, _ei(2), _F, _err(_modify(_ea("k")), "trie_insert", 3, 0)]))
    @test row("t32") == _er("t32", _el([_T, _ea("b"), _T, _T, _ea("c")]))               # update of a variant key
    @test row("t34") == _er(                                                              # update on a set trie
        "t34",
        _el([_pair(_ea("foo"), _err(_insert_perm(), "trie_update", 3, 0)),
            _pair(_ei(1), _err(_insert_perm(), "trie_update", 3, 1)),
            _pair("f2.5", _err(_insert_perm(), "trie_update", 3, 2))])
    )
    # delete
    @test row("t35") ==
        _er("t35", _el([_F, _ea("kept"), _T, _ea("v"), _ea("gone"), _F, _F]))
    @test row("t36") == _er("t36", _el([_T, _ea("set_value"), _F, _T]))
    @test row("t37") == _er("t37", _el([_T, _ei(2)]))
    @test row("t38") == _er("t38", _el([_F, _F, _ea("kept")]))
    @test row("t39") == _er("t39", _el([_T, _ea("w"), _F, _T, _ea("x")]))
    @test row("t40") == _er("t40", _el([_T, _ei(2), _F, _ei(1), _ei(3)]))
    # lookup: variants
    @test row("t41") == _er(
        "t41", _pair(_el([_ec("f", "V0", "V1", "V0")]), _el([_ec("f", "V2", "V3", "V4")]))
    )
    @test row("t42") == _er("t42", _el([_ei(1), _ei(2), _ei(3), _ei(4), _ei(5), _ea("no")]))
    @test row("t43") == _er("t43", _el(["V0"]))
    @test row("t44") == _er("t44", _el([_ec("f", "V0")]))
    @test row("t45") == _er("t45", _atoms("v", "v"))
    @test row("t46") == _er("t46", _atoms("v", "w", "no"))
    @test row("t75") == _er("t75", _el([_ei(2), _ea("no"), _ea("no"), _ea("no")]))
    @test row("t76") == _er("t76", _ea("trie"))                                          # blob(T, Type): the blob type is named `trie` (swipl's)
    # insert/4 and trie_term/2
    @test row("t47") == _er("t47", _ea("a"))
    @test startswith(
        row("t48"),
        _head("t48") * "c[45]/2(" * _ei(13) * ",c[91,124,93]/2(" * _ea("a") * ","
    )
    @test row("t50") == _er(
        "t50",
        _el([
            _ec("f", _ea("a"), _ea("b")), _ec("f", _ea("a"), _ea("c")),
            _ec("f", _ea("b"), _ea("b")),
            _ec("f", _ea("a")), _ea("f"), _ec("f", _ea("a"), _ea("b"), _ea("c")),
            _ec("f", _ea("a"), _ea("b")), _ec("f", _ea("b"), _ea("b"))
        ])
    )
    @test row("t52") == _er(
        "t52", _el([_F, _F, _F, _err(_modify(_ea("a")), "trie_insert", 4, 0), _ea("a")])
    )
    @test row("t53") == _er("t53", _err(_ea("instantiation_error"), "trie_term", 2, 0))
    @test row("t54") == _er("t54", _ea("no"))
    @test row("t55") == _er("t55", _atoms("no", "integer"))
    # '$trie_insert_abstract'/3
    @test row("t56") == _er(
        "t56",
        _pair(
            _el([_T, _T, _F, _T, _T, _T, _T, _T]),
            _el([
                _ec("f", _ec("g", _ea("a"))), _ec("f", _ea("a")),
                _ec("f", _ec("g", _ea("a")), _ea("b")),
                _ec("f", _ec("g", _ea("a")), _ea("c"))
            ])
        )
    )
    @test row("t57") == _er(
        "t57",
        _pair(
            _el([_T, _T, _T, _T, _F, _F]),
            _el([
                _ec("f", _ec("g", _ea("a"))), _ec("f", _ec("g", _ec("h", _ea("c")))),
                _ec("f", _ec("g", _ec("h", _ea("d"))))
            ])
        )
    )
    @test row("t60") == _er(
        "t60",
        _pair(
            _el([_T, _T, _F, _F, _F, _F]),
            _el([_ec("f", _ec("g", _ec("h", _ec("i", _ea("a")))))])
        )
    )
    @test row("t61") == _er("t61", _err(_insert_perm(), "\$trie_insert_abstract", 3, 0))
    @test row("t62") == _er(
        "t62",
        _el([
            _err(
                _ec("type_error", _ea("integer"), _ea("foo")),
                "\$trie_insert_abstract",
                3,
                0
            ),
            _err(
                _ec("domain_error", _ea("not_less_than_zero"), _ei(-1)),
                "\$trie_insert_abstract",
                3,
                1
            ),
            _err(_ea("instantiation_error"), "\$trie_insert_abstract", 3, 2),
            _err(_ec("type_error", _ea("integer"), "f1.5"), "\$trie_insert_abstract", 3, 3),
            _err(
                _ec("type_error", _ea("integer"), "s" * _codes("1")),
                "\$trie_insert_abstract",
                3,
                4
            ),
            _err(
                _ec("type_error", _ea("integer"), _ec("f", _ea("x"))),
                "\$trie_insert_abstract",
                3,
                5
            )
        ])
    )
    @test row("t64") == _er("t64", _el([_F, _T, _F, _F]))
    # bigger tries: hash growth, prune, long and deep keys
    @test row("t65") == _er("t65", _el([_ei(300), _ei(300), _ei(300), _ei(0)]))
    @test row("t66") ==
        _er("t66", _el([_ei(200), _ei(200), _ei(100), _ei(100), _ei(100), _ei(200)]))
    @test row("t67") == _er("t67", _atoms("long", "same", "absent"))
    @test row("t68") == _er("t68", _el([_ea("deep"), _ea("same"), _ea("absent"), _F]))
    @test row("t69") == _er("t69", _el([_ei(60), _ei(60), _ei(0)]))
    @test row("t74") == _er("t74", _el([_ei(50), _ei(50), _ei(0), _ei(50), _ei(50)]))
    # cyclic keys and attributed variables
    cyc(pred, ar, v) = _ec("type_error", _ea("acyclic_term"), _ctx(pred, ar, v))
    @test row("t70") == _er(
        "t70",
        _el([
            cyc("trie_insert", 2, 0),
            cyc("trie_insert", 3, 1),
            _F,
            _F,
            cyc("trie_update", 3, 2),
            _F
        ])
    )
    @test row("t71") == _er("t71", _atoms("a"))                                         # an atom key against an attvar: bound, hook ran
    @test row("t72") == _er("t72", _el([_ea("no"), _ea("yes"), _atoms("a")]))
    @test row("t73") == _er("t73", _el([_ei(7)]))
    # TR3: attributed variables in a key (swipl 10.1.20's answers)
    yn(xs...) = _atoms(xs...)
    @test row("t77") == _er("t77", yn("yes", "yes", "no"))                              # the same attributes are found, other values are not
    @test row("t78") == _er("t78", yn("yes", "no", "no", "no"))
    @test row("t79") == _er("t79", _el([_ec("f", _ea("a")), _el([_ec("f", _ea("a"))])]))  # a functor key against an attvar: bound, hook ran
    @test row("t80") == _er("t80", _ea("notfound"))
    @test row("t81") == _er("t81", _el([_ei(1), _ea("a"), _ei(1)]))
    @test row("t82") ==
        _er("t82", _el([_ea("same"), _ei(1), _ea("yes"), _ea("no"), _ea("yes")]))   # a shared attvar is not two
    @test row("t83") == _er(
        "t83", _ec("att", _ea("user"), _ei(1), _ec("att", _ea("other"), _ei(2), "nil"))
    )
    @test row("t84") == _er("t84", _el([_ei(7), _ea("yes")]))                          # an attvar nested in an attribute value
    @test row("t85") == _er("t85", _atoms("b"))                                         # the END key binds the new attvar: its hook runs
    @test row("t86") == _er("t86", yn("yes", "yes", "no"))
end

# KD-1: the rows swipl and the kernel answer differently BY DESIGN. Each pins the kernel's exact current answer; swipl's is in the
# comment beside it. CHECKLIST (the kernel's side moves with its owner): KD-1 the handle is an integer `(trie serial << 32) | node id` until the
# kernel has PL_unify_pointer (a pointer handle); PL_get_pointer_ex is used (item 12).
const _KD_PL = """
:- dynamic hooked/1.
attr_unify_hook(_, V) :- assertz(hooked(V)).
fm(G, R) :- catch(( G -> R = true ; R = false ), error(E, _), R = E).
fn(G, H, R) :- catch(( G -> R = true ; R = false ), error(existence_error(trie_node, X), _), ( X == H -> R = existence_error ; R = other(X) )).
kd0(R) :- fm(trie_term(foo, _), R).
kd1(R) :- fm(trie_term("s", _), R).
kd2(R) :- fm(trie_term(1.5, _), R).
kd3(R) :- fm(trie_term(f(x), _), R).
kd4(R) :- fm(trie_term(a, _), R).
kd5(R) :- fm(trie_term(_, _), R).
kd6(R) :- trie_new(T), trie_insert(T, a, 1, H), H2 is H + 1000000, fn(trie_term(H2, _), H2, R).
kd7(R) :- trie_new(T), trie_insert(T, a, 1, H), trie_destroy(T), fn(trie_term(H, _), H, R).
kd8(R) :- fn(trie_term(0, _), 0, R).
kd9(R) :- fn(trie_term(-1, _), -1, R).
"""

@testset "TR1 known differences KD-1: a bad node handle (swipl: type_error(address, _) / undefined behaviour)" begin
    f = tempname() * ".pl"
    write(f, _KD_PL)
    gd, ld, st = _tp_load(_TP, f)
    rm(f)
    @test st == "ok"
    row(n) = _tp_row(gd, ld, n)
    # swipl (10.1.20): trie_term(foo, _) is error(type_error(address, foo), context(system:trie_term/2, _)); an unbound handle is
    # instantiation_error in both. The kernel's handle is an integer read with PL_get_pointer_ex: the same type_error(address, _).
    @test row("kd0") == _er("kd0", _ec("type_error", _ea("address"), _ea("foo")))
    @test row("kd1") == _er("kd1", _ec("type_error", _ea("address"), "s" * _codes("s")))
    @test row("kd2") == _er("kd2", _ec("type_error", _ea("address"), "f1.5"))
    @test row("kd3") == _er("kd3", _ec("type_error", _ea("address"), _ec("f", _ea("x"))))
    @test row("kd4") == _er("kd4", _ec("type_error", _ea("address"), _ea("a")))
    @test row("kd5") == _er("kd5", _ea("instantiation_error"))
    # an integer that names no live node: swipl dereferences it (a fault on 0, a read of freed memory after trie_destroy/1): NO swipl
    # answer. The kernel: existence_error(trie_node, <the handle>).
    @test row("kd6") == _er("kd6", _ea("existence_error"))
    @test row("kd7") == _er("kd7", _ea("existence_error"))
    @test row("kd8") == _er("kd8", _ea("existence_error"))
    @test row("kd9") == _er("kd9", _ea("existence_error"))
end

# DEFKILL5 rows (white-box over a program, no oracle line beyond the numbers cited): TR1-V6 and TR1-V11.
#   * TR1-V6: pl-trie.c:2500 `trie_new/1` does `set(trie, TRIE_CONCURRENT)` (kernel src/pl-trie.jl:2150); the flag is read on the newest trie of `gd.tries`
#     after a query ran `trie_new/1` (the query sets ld.GD, which `pl_trie_new1_va` needs).
#   * TR1-V11: pl-trie.c:2865-2890 `trie_delete/3` calls `trie_delete(trie, node, true)`: the pruned node is destroyed. swipl 18168e62, two identical runs of
#     `trie_new(T), trie_insert(T, f(a), v), trie_delete(T, f(a), V), trie_property(T, node_count(N))`: node_count is 1 before the insert and after the
#     delete, 3 after the insert, V = v, value_count 0 (the list [N0,N1,N2,V,VC] printed [1,3,1,v,0]). The kernel's `prune && tr.references == 0` of
#     src/pl-trie.jl:1815 gives the same node_count; a mutant that deletes without pruning keeps 3.
const _DK5_PL = raw"""
dk5_new(R) :- trie_new(_), R = ok.
dk5_ins(R) :- trie_new(T), trie_insert(T, f(a), v), R = ok.
dk5_del(R) :- trie_new(T), trie_insert(T, f(a), v), trie_delete(T, f(a), V), R = V.
"""

@testset "TR1 DEFKILL5 rows: trie_new/1 sets TRIE_CONCURRENT, trie_delete/3 prunes (TR1-V6, TR1-V11)" begin
    f = tempname() * ".pl"
    write(f, _DK5_PL)
    gd, ld, st = _tp_load(_TP, f)
    rm(f)
    @test st == "ok"
    row(n) = _tp_row(gd, ld, n)
    n0 = length(gd.tries)
    # TR1-V6
    @test row("dk5_new") == _er("dk5_new", _ea("ok"))
    @test length(gd.tries) == n0 + 1
    @test (gd.tries[end].flags & LK.TRIE_CONCURRENT) != 0
    # TR1-V11: the node count after an insert (3: the root, f/1, a), after the insert and the delete (1: only the root), and a fresh trie's (1)
    @test row("dk5_ins") == _er("dk5_ins", _ea("ok"))
    ins = gd.tries[end]
    @test length(gd.tries) == n0 + 2 && ins.value_count == 1 && ins.node_count == 3
    @test row("dk5_del") == _er("dk5_del", _ea("v"))
    del = gd.tries[end]
    @test length(gd.tries) == n0 + 3 && del !== ins
    @test del.value_count == 0
    @test del.node_count == 1 == LK.trie_create(_TP).node_count
end
