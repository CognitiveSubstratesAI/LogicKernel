# ORIGINAL: R1g's gate — the compiler's warnings (pl-comp.c `compiler_warning`: the variable analysis' and the body compiler's) against swipl 10.1.16's `compiler_warnings/2` messages.
# test/compile/test_compiler_warnings_swipl.jl — what the compiler warns about, clause by clause,
# as swipl does when it consults the same clauses (src/pl-comp.jl, since R1g):
#   * THE VARIABLE ANALYSIS (`analyseVariables2!`, `analyse_variables!`, the `VD_*` flags): a
#     variable used once in one branch of a `;` (`branch_singleton`), in the goal of a `\+`
#     (`negation_singleton`), a `_Name` used more than once (`multiton`) and, under
#     `style_check(+var_branches)`, a variable not introduced in all branches (`unbalanced_var`).
#     On random clauses whose bodies nest `,`, `;`, `->`, `*->` and `\+`. The kernel does not
#     compile those bodies yet (V9), so its side is the ANALYSIS: `_compile_clause_head!` with a
#     compilation that asks for warnings;
#   * THE BODY COMPILER (`compileBodyEQ`, `compileBodyNEQ`, `always`): `==` and `\==` on a void or
#     a first variable (`eq_singleton`, `eq_vv`, `neq_singleton`, `neq_vv`), `var/1`, `nonvar/1` and
#     the type tests with a known outcome (`always(Bool, Pred, Arg)`). On random clauses whose
#     bodies are conjunctions of those goals, `=/2` and user predicates, compiled in full
#     (`compileClause` with a `warnings` term reference and `$variable_names`).
# Each side writes, per clause and per pass (pass 1: the default style checks; pass 2: with
# `var_branches`), the warnings in order, each `name(Arg, …)` with a variable shown by its NAME in
# the clause (`_` for an unnamed one) — so which variable is warned about is compared, not only how
# many. swipl's are captured with `user:message_hook/3`, the names from
# `prolog_load_context(variable_names, _)`, the clause from `source_location/2` (one per line).
using Test, Random, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CW = lk_term_type(Union{Int64, Float64})
_cws(n) = lk_sym(_CW, Symbol(n))
_cwe(f, xs::AbstractVector) = mk_expr(_CW, _CW[_cws(f); xs])

const _CW_SWIPL = Sys.which("swipl")
const _CW_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

# The names a clause's variables are drawn from: properly named, `_Name` (anonymous by its name: a
# second use is a multiton), `__name`, `_<digit>` (neutral) and `_<lower>` (named).
const _CW_NAMES = ["A", "B", "Xy", "_C", "_D", "__e", "_1", "_f", "__"]

"A clause under test: its terms, the names of its variables, whether it has a control construct other than `,`."
struct _CwClause
    head::_CW
    body::_CW
    names::Dict{UInt64, String}
    control::Bool
end

mutable struct _CwGen
    rng::Xoshiro
    next::UInt64                    # the last variable key handed out
    names::Dict{UInt64, String}     # the names of the clause being generated
end
_cwfresh!(g::_CwGen)::_CW = (g.next += 1; lk_var(_CW, g.next))

"A pool of five variables for a clause, each with its own name."
function _cwpool!(g::_CwGen)::Vector{_CW}
    empty!(g.names)
    pool = _CW[]
    for n in shuffle(g.rng, _CW_NAMES)[1:5]
        v = _cwfresh!(g)
        g.names[var_key(v)] = n
        push!(pool, v)
    end
    return pool
end

"An argument: mostly a pooled variable; an unnamed one (`_`), an atom, an integer, `f(Var)`."
function _cwarg(g::_CwGen, pool::Vector{_CW})::_CW
    r = rand(g.rng)
    r < 0.62 && return rand(g.rng, pool)
    r < 0.70 && return _cwfresh!(g)                 # written `_`
    r < 0.80 && return _cws(rand(g.rng, ("a", "b")))
    r < 0.86 && return lk_gnd(_CW, rand(g.rng, 0:3))
    return _cwe("f", [rand(g.rng, pool)])
end

"A user goal `g<n>(Arg, …)`, n in 0:3."
function _cwuser(g::_CwGen, pool::Vector{_CW})::_CW
    n = rand(g.rng, 0:3)
    n == 0 && return _cws("g0")
    return _cwe("g$n", [_cwarg(g, pool) for _ in 1:n])
end

"A body of user goals under `,`, `;`, `->`, `*->` (with and without an else) and `\\+`."
function _cwcontrol(g::_CwGen, pool::Vector{_CW}, depth::Int)::_CW
    r = rand(g.rng)
    (depth >= 3 || r < 0.34) && return _cwuser(g, pool)
    sub() = _cwcontrol(g, pool, depth + 1)
    r < 0.50 && return _cwe(",", [sub(), sub()])
    r < 0.68 && return _cwe(";", [sub(), sub()])
    r < 0.78 && return _cwe(";", [_cwe("->", [sub(), sub()]), sub()])
    r < 0.83 && return _cwe("->", [sub(), sub()])
    r < 0.88 && return _cwe(";", [_cwe("*->", [sub(), sub()]), sub()])
    r < 0.91 && return _cwe("*->", [sub(), sub()])
    return _cwe("\\+", [sub()])
end

const _CW_TESTS = (
    "var", "nonvar", "integer", "rational", "float", "number", "atomic", "atom", "string",
    "compound", "callable"
)

"A goal the body compiler compiles inline, or a user goal."
function _cwinline(g::_CwGen, pool::Vector{_CW})::_CW
    r = rand(g.rng)
    r < 0.28 && return _cwuser(g, pool)
    r < 0.44 && return _cwe("==", [_cwarg(g, pool), _cwarg(g, pool)])
    r < 0.60 && return _cwe("\\==", [_cwarg(g, pool), _cwarg(g, pool)])
    r < 0.72 && return _cwe("=", [_cwarg(g, pool), _cwarg(g, pool)])
    return _cwe(rand(g.rng, _CW_TESTS), [_cwarg(g, pool)])
end

"A conjunction of 1–5 inline or user goals."
function _cwconj(g::_CwGen, pool::Vector{_CW})::_CW
    goals = [_cwinline(g, pool) for _ in 1:rand(g.rng, 1:5)]
    b = goals[end]
    for k in (length(goals) - 1):-1:1
        b = _cwe(",", [goals[k], b])
    end
    return b
end

"Random clause `k`: a head of arity 0–3 over the clause's pool, and a body of the kind asked."
function _cwclause(g::_CwGen, k::Int, control::Bool)::_CwClause
    pool = _cwpool!(g)
    n = rand(g.rng, 0:3)
    head = n == 0 ? _cws("cw$k") : _cwe("cw$k", [_cwarg(g, pool) for _ in 1:n])
    body = control ? _cwcontrol(g, pool, 0) : _cwconj(g, pool)
    return _CwClause(head, body, copy(g.names), control)
end

# ── hand cases: (head, body) as text is awkward to share, so they are built as terms too ─────────
"The pinned clauses: each a reason, from probing swipl 10.1.16."
function _cwhand()::Vector{_CwClause}
    out = _CwClause[]
    k = UInt64(900_000)
    names = Dict{UInt64, String}()
    v(n) = begin
        for (key, name) in names
            name == n && return lk_var(_CW, key)
        end
        k += 1
        names[k] = n
        lk_var(_CW, k)
    end
    anon() = (k += 1; lk_var(_CW, k))
    add(control, h, b) = (push!(out, _CwClause(h, b, copy(names), control)); empty!(names))
    e(f, xs...) = _cwe(f, collect(_CW, xs))
    s = _cws
    # the analysis
    add(false, e("h1", v("_A"), v("_A")), s("true"))                             # multiton
    add(false, e("h2", v("_X"), v("_X"), v("__y"), v("__y"), v("_1"), v("_1")), s("true"))
    add(false, e("h3", v("_a"), v("_a")), s("true"))                             # `_a` is named
    add(
        true,
        e("h4", v("X")),
        e(";", e(",", e("=", v("X"), s("a")), e("g1", v("Y"))), e("g1", v("X")))
    )
    add(
        true,
        e("h5", v("X")),
        e(",", e(";", e("g1", v("X")), e("g1", v("Y"))), e("g1", v("Y")))
    )
    add(true, e("h6", v("X")), e(";", e("g1", v("Y")), e("g1", v("X"))))
    add(
        true,
        e("h7", v("X")),
        e(";", e(",", e("g1", v("Y")), e("g1", v("Y"))), e("g1", v("X")))
    )
    add(true, e("h8", v("X")), e("\\+", e("g2", v("X"), v("Y"))))                # negation
    add(true, e("h9", v("X")), e("\\+", e(",", e("g2", v("X"), v("Y")), e("g1", v("Y")))))
    add(
        true,
        e("h10", v("X")),
        e(";", e("->", e("g1", v("X")), e("g1", v("Y"))), e("g1", v("Y")))
    )
    add(
        true,
        e("h11", v("X")),
        e(";", e("->", e("g1", v("X")), e("g1", v("Y"))), e("g1", v("Z")))
    )
    add(true, e("h12", v("X")), e(";", e("*->", e("g1", v("X")), e("g1", v("Y"))), s("g0")))
    add(true, e("h13", v("X")),
        e(
            ";",
            e(",", e("g1", v("X")), e("\\+", e("g1", v("Y")))),
            e("g2", v("_Q"), v("_Q"))
        ))
    add(true, s("h14"), e(";", e("g1", v("Y")), e(";", e("g1", v("Y")), e("g1", v("Z")))))
    add(true, s("h15"), e(",", e("\\+", e("g1", v("Y"))), e("g1", v("Y"))))      # used after \+
    add(true, s("h16"), e(";", e("\\+", e("g1", v("Y"))), e("g1", v("Y"))))
    # the body compiler
    add(false, e("c1", v("X")), e("==", v("X"), v("Y")))                          # eq_singleton
    add(false, e("c2", v("X")), e(",", e("==", v("Y"), v("Z")), e("g1", v("X"))))
    add(false, e("c3", v("X"), v("Y")), e("==", v("X"), v("Y")))                  # none
    add(false, e("c4", v("X")), e("\\==", v("Y"), v("X")))                        # neq_singleton
    add(false, s("c5"), e("==", v("X"), v("X")))                                  # eq_vv
    add(false, s("c6"), e("\\==", v("X"), v("X")))                                # neq_vv
    add(false, s("c7"), e(",", e("==", v("X"), v("Y")), e("g2", v("X"), v("Y")))) # eq_vv, two
    add(false, e("c8", v("X")), e("=", v("Y"), v("X")))                           # none
    add(false, e("c9", v("X")), e(",", e("var", v("Y")), e("g1", v("X"))))        # always
    add(false, e("c10", v("X")), e(",", e("nonvar", v("Y")), e("g1", v("X"))))
    add(
        false,
        e("c11", v("X")),
        e(",", e("g1", v("X")), e(",", e("var", v("Z")), e("g1", v("Z"))))
    )
    add(false, s("c12"), e("integer", anon()))                                    # unnamed
    add(false, s("c13"), e(",", e("atom", v("X")), e("g1", v("X"))))
    add(false, s("c14"), e(",", e("=", v("X"), s("a")), e("var", v("X"))))        # none
    add(false, s("c15"), e("==", e("f", v("X")), v("Y")))                         # a compound side
    add(false, s("c16"), e(",", e("integer", lk_gnd(_CW, 1)), e("atom", s("a")))) # always true
    add(false, e("c17", v("_A"), v("_A")), e("==", v("X"), v("_A")))              # both kinds
    return out
end

# ── both sides' notation ────────────────────────────────────────────────────────────────────────
_cwbare(n::String)::Bool = occursin(r"^[a-z][a-zA-Z0-9_]*$", n)
_cwquote(n::String)::String = _cwbare(n) ? n : "'" * replace(n, "\\" => "\\\\") * "'"

"`t` as Prolog text in functional notation: a named variable by its name, any other `_`."
function _cwtext(t::_CW, names::Dict{UInt64, String})::String
    k = kind(t)
    k === VAR && return get(names, var_key(t), "_")
    k === SYM && return _cwquote(sym_text(t))
    k === GND && return string(lk_value(t))
    return _cwquote(sym_text(child(t, 1))) * "(" *
           join([_cwtext(child(t, i), names) for i in 2:nchildren(t)], ",") * ")"
end

"The variables of `t` that have a name, in order of first occurrence."
function _cwvars!(out::Vector{_CW}, t::_CW, names::Dict{UInt64, String})::Vector{_CW}
    if kind(t) === VAR
        haskey(names, var_key(t)) && !any(x -> var_key(x) == var_key(t), out) &&
            push!(out, t)
    elseif kind(t) === EXPR
        foreach(i -> _cwvars!(out, child(t, i), names), 2:nchildren(t))
    end
    return out
end

"`[Name = Var, …]` for the named variables of the clause, as read_clause's `variable_names`."
function _cwbindings(c::_CwClause)::_CW
    vars = _cwvars!(_cwvars!(_CW[], c.head, c.names), c.body, c.names)
    l = mk_nil(_CW)
    for v in reverse(vars)
        l = _cwe("[|]", [_cwe("=", [_cws(c.names[var_key(v)]), v]), l])
    end
    return l
end

# ── the kernel side ─────────────────────────────────────────────────────────────────────────────
const _CW_DEFAULT = Int(
    LK.SINGLETON_CHECK | LK.SEMSINGLETON_CHECK | LK.DISCONTIGUOUS_STYLE | LK.NOEFFECT_CHECK
)

"The kernel's warnings for clause `c` under the style checks `style`, each as text."
function _cwkernel(gd, ld, c::_CwClause, style::Int)::String
    user = LK.MODULE_user(gd)
    name, ar =
        kind(c.head) === SYM ? (c.head, 0) : (child(c.head, 1), nchildren(c.head) - 1)
    proc = LK.lookupProcedure(name, ar, user)
    out = String[]
    if c.control                                    # the analysis alone (bodies with `;`: V9)
        ci = LK.compileInfo{_CW}(ar, user, proc)
        ci.styleCheck = style
        ci.warning_list = 1                         # any term reference: warnings are wanted
        ci.variable_names = _cwbindings(c)
        LK._compile_clause_head!(gd, ci, c.head, c.body)
        ws = ci.warnings
        if ws !== nothing
            for w in ws
                push!(out, _cwtext(_cwe(String(w.def.name), w.argv), c.names))
            end
        end
    else                                            # the whole compiler
        old = ld.debugstatus_styleCheck
        fid = LK.PL_open_foreign_frame(ld)
        warnings = LK.PL_new_term_ref(ld)
        vn = LK.PL_new_term_ref(ld)
        ld.slots[vn + 1] = _cwbindings(c)
        ld.variable_names = vn
        ld.debugstatus_styleCheck = style
        try
            cl = LK.compileClause(gd, ld, c.head, c.body, proc, user, warnings)
            cl === nothing && error("compileClause failed for " * _cwtext(c.head, c.names))
            l = LK.deRef(ld, ld.slots[warnings + 1])
            while is_pair(l)
                push!(out, _cwtext(child(l, 2), c.names))
                l = child(l, 3)
            end
            is_nil(l) || error("the warnings are not a list")
        finally
            ld.variable_names = 0
            ld.debugstatus_styleCheck = old
            LK.PL_discard_foreign_frame(ld, fid)
        end
    end
    return join(out, " ")
end

# ── the swipl side ──────────────────────────────────────────────────────────────────────────────
const _CW_DRIVER = raw"""
:- dynamic cw_pass/1.
user:message_hook(compiler_warnings(_, Ws), warning, _) :- !,
    source_location(_, Line), cw_pass(P),
    ( prolog_load_context(variable_names, Bs) -> true ; Bs = [] ),
    \+ \+ ( cw_bind(Bs), term_variables(Ws, Vs), cw_anon(Vs),
            format("@@ ~d ~d", [P, Line]),
            forall(member(W, Ws),
                   ( write(' '),
                     write_term(W, [quoted(true), ignore_ops(true), numbervars(true)]) )),
            nl ).
user:message_hook(_, warning, _).
cw_bind([]).
cw_bind([N=V|T]) :- V = '$VAR'(N), cw_bind(T).
cw_anon([]).
cw_anon(['$VAR'('_')|T]) :- cw_anon(T).
main(File) :-
    assertz(cw_pass(1)), consult(File),
    retractall(cw_pass(_)), assertz(cw_pass(2)),
    style_check(+var_branches), consult(File).
"""

"swipl's warnings for the clauses, by `(pass, clause)`; and what it wrote to stderr."
function _cwswipl(clauses::Vector{_CwClause})::Tuple{Dict{Tuple{Int, Int}, String}, String}
    mktempdir() do d
        f = joinpath(d, "cw.pl")
        open(f, "w") do io
            for c in clauses                        # one clause per line
                println(io, _cwtext(c.head, c.names), " :- ", _cwtext(c.body, c.names), ".")
            end
        end
        drv = joinpath(d, "drv.pl")
        write(drv, _CW_DRIVER * ":- initialization((main('$f'), halt)).\n")
        ef = joinpath(d, "cw.err")
        out = read(
            pipeline(ignorestatus(`swipl -q $drv`); stdin=devnull, stderr=ef), String
        )
        res = Dict{Tuple{Int, Int}, String}()
        for l in split(out, '\n'; keepempty=false)
            m = match(r"^@@ (\d+) (\d+) ?(.*)$", l)
            m === nothing && error("an unexpected line from swipl: $l")
            key = (parse(Int, m[1]), parse(Int, m[2]))
            haskey(res, key) && error("two warning messages for clause $(key[2])")
            res[key] = String(m[3])
        end
        return (res, read(ef, String))
    end
end

if _CW_SWIPL !== nothing
    @testset "the compiler's warnings, clause by clause, as swipl" begin
        g = _CwGen(Xoshiro(20261010), UInt64(0), Dict{UInt64, String}())
        clauses = _cwhand()
        nhand = length(clauses)
        append!(clauses, [_cwclause(g, k, true) for k in 1:1500])
        append!(clauses, [_cwclause(g, 2000 + k, false) for k in 1:1500])

        theirs, err = _cwswipl(clauses)
        isempty(err) || println(stderr, "  swipl wrote to stderr:\n", first(err, 2000))
        @test isempty(err)

        gd, ld = LK.PL_global_data{_CW}(), LK.PL_local_data{_CW}()
        diverging = 0
        kinds = Dict{String, Int}()
        for pass in 1:2
            style = pass == 1 ? _CW_DEFAULT : (_CW_DEFAULT | Int(LK.VARBRANCH_CHECK))
            for (i, c) in enumerate(clauses)
                ours = _cwkernel(gd, ld, c, style)
                swipl = get(theirs, (pass, i), "")
                for w in split(swipl, ' '; keepempty=false)
                    n = String(first(split(w, '(')))
                    kinds[n] = get(kinds, n, 0) + 1
                end
                if ours != swipl
                    diverging += 1
                    diverging <= 8 && println(
                        stderr, "  DIVERGES (pass $pass, clause $i): ",
                        _cwtext(c.head, c.names), " :- ", _cwtext(c.body, c.names),
                        "\n    kernel ", ours, "\n    swipl  ", swipl
                    )
                end
            end
        end
        @test diverging == 0
        println(
            "  compiler warnings compared (", length(clauses), " clauses, 2 passes): ",
            join(["$k=$v" for (k, v) in sort!(collect(kinds))], ", ")
        )
        # the corpus provokes every warning the compiler raises, many times (not vacuous)
        for n in (
            "branch_singleton", "negation_singleton", "multiton", "unbalanced_var",
            "eq_singleton", "eq_vv", "neq_singleton", "neq_vv", "always"
        )
            @test get(kinds, n, 0) >= 40
        end
        @test sort!(collect(keys(kinds))) == sort!([
            "always", "branch_singleton", "eq_singleton", "eq_vv", "multiton",
            "negation_singleton", "neq_singleton", "neq_vv", "unbalanced_var"
        ])
        # the hand cases: the pinned ones warn where expected (swipl's own answer, read back)
        @test get(theirs, (1, 1), "") == "multiton(_A)"
        @test get(theirs, (1, 3), "") == ""                     # `_a` is a named variable
        @test nhand == 33
    end

    @testset "no warnings without a caller that asks, and none are left behind" begin
        gd, ld = LK.PL_global_data{_CW}(), LK.PL_local_data{_CW}()
        user = LK.MODULE_user(gd)
        x = lk_var(_CW, UInt64(1))
        y = lk_var(_CW, UInt64(2))
        head = _cwe("nw", [x])
        body = _cwe("==", [x, y])
        proc = LK.lookupProcedure(_cws("nw"), 1, user)
        ci = LK.compileInfo{_CW}(1, user, proc)                 # warning_list 0
        ci.styleCheck = _CW_DEFAULT
        @test LK.compiler_warning(ci, :eq_singleton, _CW[x, y])
        @test ci.warnings === nothing
        @test LK.compileClause(gd, ld, head, body, proc, user) !== nothing
        # with a term reference: the list, and the compilation's warnings are released
        fid = LK.PL_open_foreign_frame(ld)
        w = LK.PL_new_term_ref(ld)
        @test LK.compileClause(gd, ld, head, body, proc, user, w) !== nothing
        l = ld.slots[w + 1]
        @test is_pair(l) && sym_text(child(child(l, 2), 1)) == "eq_singleton" &&
            is_nil(child(l, 3))
        # a clause with nothing to warn about: `[]`
        @test LK.compileClause(gd, ld, _cwe("nw", [x]), _cwe("g1", [x]), proc, user, w) !==
            nothing
        @test is_nil(ld.slots[w + 1])
        LK.PL_discard_foreign_frame(ld, fid)
        # an undefined warning is an error, and an argument count that is not the declaration's
        ci2 = LK.compileInfo{_CW}(1, user, proc)
        ci2.warning_list = 1
        @test_throws ErrorException LK.compiler_warning(ci2, :no_such_warning, _CW[x])
        @test_throws AssertionError LK.compiler_warning(ci2, :multiton, _CW[x, y])
    end

    @testset "atom_is_named_var: named, neutral, anonymous" begin
        named(s) = LK.atom_is_named_var(codeunits(s))
        @test named("X") == 1 && named("Foo") == 1 && named("_a") == 1 && named("_é") == 1
        @test named("_1") == 0 && named("_0x") == 0
        @test named("_X") == -1 && named("__x") == -1 && named("__") == -1 &&
            named("_") == -1
        @test named("_É") == -1
    end
elseif _CW_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the compiler-warning differential would be skipped"
    )
else
    @info "COMPILER-WARNING DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "compiler-warning differential skipped only where it is not required" begin
        @test !_CW_SWIPL_REQUIRED
    end
end
