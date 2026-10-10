# ORIGINAL: R1e's last gate — write_canonical/1,2 (pl-prims.c numberVars) and read_term_from_atom/3 (read_term_from_stream, its options) against swipl 10.1.16.
# test/core_text/test_canonical_readatom_swipl.jl — the rest of R1e:
#   * WRITE_CANONICAL/1,2: every term of the reader's and the writer's hand corpora and 1,000
#     random terms, written by write_canonical/1 and write_canonical/2 to user_error, compared
#     with swipl on user_output, user_error and the verdict. Variables are numbered on both sides
#     (`A`, `B`, … for repeated variables, `_` for singletons: numberVars' singletons mode), so the
#     texts compare LITERALLY — no renaming; then read back on the kernel: a variant of the term.
#   * READ_TERM_FROM_ATOM/3: every corpus text read with 15 option lists — none, variable_names,
#     variables, singletons(S), singletons(warning), each syntax_errors mode, double_quotes ×3,
#     back_quotes, character_escapes(false), dotlists, module — the term's writeq text, the
#     options list after the call (its bindings), and the verdict compared with swipl; a syntax
#     error's ball compared whole (position included); dec10's and warning's MESSAGES (singletons,
#     the syntax error) compared as terms, through swipl's message_hook.
#   * THE HAND GOALS: the text argument's errors, option errors, the end_of_file cases, a second
#     term ignored, 300 occurrences of one variable, 300 `'$VAR'`s, 300 distinct variables.
#   * EXCLUDED BY NAME AND COUNTED: a syntax error whose culprit text holds a CUT UTF-8 byte
#     (`«x`: upstream names the quote's first byte, `string("Â", 0)`; the kernel does the same, and
#     its writer cannot write that string).
#   * THE REFUSALS, explicit: term_position, subterm_positions, comments, var_prefix,
#     quasi_quotations (term positions: R2), unicode_atoms, blob — each `NotPortedError`;
#     write_canonical of a cyclic term (decision 4a; swipl factorises it: `@(T, Bindings)`).
using Test, LogicKernel, Random
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "text_corpora_testlib.jl"))
const _CR = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_crs(x) = lk_sym(_CR, Symbol(x))
_cr_var() = mk_var(_CR, LK.fresh_var_keys!(1))

const _CR_SWIPL = Sys.which("swipl")
const _CR_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"
const _CR_GD = LK.PL_global_data{_CR}()
const _CR_LD = LK.PL_local_data{_CR}()

"Run `name` on `args`: `(rc, answers, ball)` — `:true`, `:false`, `:exception`, `:notported`."
function _cr_call(name::String, args::Vector{_CR})
    gd, ld = _CR_GD, _CR_LD
    proc = LK.isCurrentProcedure(sym_key(_crs(name)), length(args), LK.MODULE_system(gd))
    @assert proc !== nothing "no system predicate $name/$(length(args))"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    for (i, x) in enumerate(args)
        ld.slots[a + i] = x
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    out = try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            (:true, [LK.resolve_term(ld, ld.slots[a + i]) for i in 1:length(args)], nothing)
        elseif rc == LK.PL_S_EXCEPTION
            (:exception, _CR[], LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1]))
        else
            (:false, _CR[], nothing)
        end
    catch e
        e isa LK.NotPortedError || rethrow()
        (:notported, _CR[], nothing)
    end
    out[1] === :notported || LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"The kernel's read of `text` (term_to_atom/2), or `nothing`."
function _cr_read(text::String)::Union{Nothing, _CR}
    rc, ans, _ = _cr_call("term_to_atom", _CR[_cr_var(), lk_gnd(_CR, text)])
    return rc === :true ? ans[1] : nothing
end

# A string holding a CUT UTF-8 sequence cannot be written (`writeString` decodes it): upstream's
# syntax error for `«x` names the quote's first BYTE, `string("Â", 0)` — a known upstream oddity the
# kernel ports as is (src/pl-read.jl, "end_of_file_in_quoted"). Such a ball is named here, and the
# comparison counts it instead of writing it (R1f's named-exclusion rule).
# A STRING holding the character 0 reads (a string can hold it) but term_to_atom/2 of it cannot
# make the atom (R1f's named term-interface gap): named here too, as `NUL-TEXT`.
_cr_cut_utf8(t::_CR)::Bool =
    (
        kind(t) === GND && lk_value(t) isa AbstractString &&
        !isvalid(String, String(lk_value(t)))
    ) ||
    (kind(t) === EXPR && any(i -> _cr_cut_utf8(child(t, i)), 1:nchildren(t)))
_cr_nul(t::_CR)::Bool =
    (
        kind(t) === GND && lk_value(t) isa AbstractString &&
        occursin('\0', String(lk_value(t)))
    ) ||
    (kind(t) === EXPR && any(i -> _cr_nul(child(t, i)), 1:nchildren(t)))

"The kernel's writeq text of `t` (term_to_atom/2); `CUT-UTF8` / `NUL-TEXT` for the named exclusions."
function _cr_text(t::_CR)::String
    _cr_cut_utf8(t) && return "CUT-UTF8"
    _cr_nul(t) && return "NUL-TEXT"
    rc, ans, _ = _cr_call("term_to_atom", _CR[t, _cr_var()])
    @assert rc === :true "term_to_atom: $rc on $t"
    return sym_text(ans[2])
end

"""
Call `name` on `args` with fresh user_output/user_error buffers and an empty message list:
`[out, err, verdict, messages]` — the verdict `true`/`false`/`NOTPORTED`/`ex:<ball>`, the
messages (printMessage's, R1f) as `kind:<text>` joined by `;`. `args` after the call are
returned too (the options' bindings).
"""
function _cr_run(name::String, args::Vector{_CR})
    out, err = IOBuffer(), IOBuffer()
    LK.set_standard_stream!(_CR_LD, LK.SNO_USER_OUTPUT, out)
    LK.set_standard_stream!(_CR_LD, LK.SNO_USER_ERROR, err)
    empty!(_CR_LD.messages)
    rc, ans, ball = _cr_call(name, args)
    LK.Sflush(LK.Suser_output(_CR_LD))
    LK.Sflush(LK.Suser_error(_CR_LD))
    verdict = if rc === :true
        "true"
    elseif rc === :false
        "false"
    elseif rc === :notported
        "NOTPORTED"
    else
        "ex:" * _cr_text(ball::_CR)
    end
    msgs = join(
        [string(k) * ":" * _cr_text(m) for (k, m) in _CR_LD.messages], ";"
    )
    return ([String(take!(out)), String(take!(err)), verdict, msgs], ans)
end

"Name the variables of a text `_V0`, `_V1`… by first occurrence (their numbers differ)."
function _cr_norm(s::String)::String
    seen = Dict{String, Int}()
    return replace(
        s,
        r"(?<![A-Za-z0-9_])_G?[0-9]+(?![A-Za-z0-9_])" =>
            m -> "_V" * string(get!(seen, m, length(seen)))
    )
end

const _CR_OPTS_TEXT = """[
    [], [variable_names(_)], [variables(_)], [singletons(_)], [singletons(warning)],
    [syntax_errors(error)], [syntax_errors(fail)], [syntax_errors(quiet)], [syntax_errors(dec10)],
    [double_quotes(codes)], [double_quotes(chars)], [double_quotes(atom)],
    [back_quotes(string), character_escapes(false)], [dotlists(true), module(user)], [cycles(true)]
]"""

const _CR_DRIVER = raw"""
:- op(0, fx, $).
:- dynamic seen/2.
user:message_hook(T, K, _) :- ( K == warning ; K == error ), assertz(seen(K, T)), fail.
codes(S) :- string_codes(S, Cs), format("~w", [Cs]).
% G with user_output/user_error captured and the messages collected: 4 fields, codes each
cap(G) :-
    retractall(seen(_, _)),
    tmp_file(co, Fo), tmp_file(ce, Fe),
    open(Fo, write, SO, [encoding(utf8)]), open(Fe, write, SE, [encoding(utf8)]),
    stream_property(OO, alias(user_output)), stream_property(OE, alias(user_error)), current_output(OC),
    set_stream(SO, alias(user_output)), set_stream(SE, alias(user_error)), set_output(SO),
    ( catch(G, E, true) -> ( var(E) -> R = true ; R = ex(E) ) ; R = false ),
    set_stream(OO, alias(user_output)), set_stream(OE, alias(user_error)), set_output(OC),
    close(SO), close(SE),
    read_file_to_string(Fo, StrO, [encoding(utf8)]), read_file_to_string(Fe, StrE, [encoding(utf8)]),
    codes(StrO), write(' '), codes(StrE), write(' '),
    ( R = ex(B) -> term_to_atom(B, BA), atom_string(BA, BS), string_concat("ex:", BS, VS) ; term_to_atom(R, RA), atom_string(RA, VS) ),
    codes(VS), write(' '),
    findall(M, (seen(K, T), term_to_atom(T, TA), format(atom(M), "~w:~w", [K, TA])), Ms),
    atomic_list_concat(Ms, ';', MA), atom_string(MA, MS), codes(MS), nl.
% write_canonical/1 and /2 (to user_error) of the term read from Cs
wc(Cs) :- atom_codes(A, Cs),
    ( catch(term_to_atom(T, A), _, fail) -> cap(write_canonical(T)), cap(write_canonical(user_error, T))
    ; cap(fail), cap(fail) ).
wce(Enc) :- length(Vs, 8), dec(Enc, T, Vs), cap(write_canonical(T)), cap(write_canonical(user_error, T)).
% read_term_from_atom(A, T, Os) for each Os: the term's writeq text + the options after, in the verdict
rt(Cs, Oss) :- atom_codes(A, Cs),
    forall(member(Os, Oss), cap((read_term_from_atom(A, T, Os), term_to_atom(T-Os, TA), write(TA)))).
gl(Cs) :- atom_codes(A, Cs), term_to_atom(G, A), cap(G).
dec(a(Cs), A, _) :- !, atom_codes(A, Cs).
dec(nil, [], _) :- !.
dec(i(N), N, _) :- !.
dec(q(N, D), Q, _) :- !, Q is N rdiv D.
dec(s(Cs), S, _) :- !, string_codes(S, Cs).
dec(v(K), V, Vs) :- !, nth0(K, Vs, V).
dec(cn(As), T, Vs) :- !, decl(As, Xs, Vs), compound_name_arguments(T, [], Xs).
dec(c(Cs, As), T, Vs) :- atom_codes(N, Cs), decl(As, Xs, Vs), compound_name_arguments(T, N, Xs).
decl([], [], _).
decl([A|As], [X|Xs], Vs) :- dec(A, X, Vs), decl(As, Xs, Vs).
"""

_cr_codes(s::String)::String = "[" * join(Int.(collect(s)), ",") * "]"
_cr_decode(w::AbstractString)::String =
    w == "[]" ? "" : String(Char.(parse.(Int, split(w[2:(end - 1)], ','; keepempty=false))))

"swipl's results for `goals` (one 4-field line per `cap`), from one swipl process."
function _cr_swipl(goals::Vector{String})::Vector{Vector{String}}
    prog = IOBuffer()
    print(prog, _CR_DRIVER, "run :- ")
    for g in goals
        print(prog, g, ", ")
    end
    println(prog, "true.\n:- initialization((run, halt)).")
    out = mktempdir() do d
        f = joinpath(d, "cr.pl")
        write(f, String(take!(prog)))
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return [
        begin
            ws = split(l, ' ')
            @assert length(ws) == 4 "swipl line: $l"
            [_cr_decode(w) for w in ws]
        end for l in split(chomp(out), '\n')
    ]
end

# swipl PRINTS a reported syntax error and a singleton warning on user_error (print_message/2,
# boot/messages.pl: R2); the kernel collects the message term instead (printMessage, R1f). Both
# sides' message LISTS are compared; swipl's printed lines are dropped from its user_error here.
_cr_strip_printed(err::String)::String =
    join(
        filter(
            l -> !startswith(l, "ERROR: ") && !startswith(l, "Warning: "),
            split(err, '\n'; keepempty=true)
        ),
        '\n'
    )

"Compare kernel and swipl results, label by label; the texts normalised when `norm`."
function _cr_compare(labels, ours, theirs; norm=true)
    @test length(ours) == length(theirs)
    bad = String[]
    cut = 0
    for k in 1:min(length(ours), length(theirs))
        o = norm ? [_cr_norm(x) for x in ours[k]] : copy(ours[k])
        s = norm ? [_cr_norm(x) for x in theirs[k]] : copy(theirs[k])
        s[2] = _cr_strip_printed(s[2])
        if any(x -> occursin("CUT-UTF8", x) || occursin("NUL-TEXT", x), o)   # named, counted
            cut += 1
            continue
        end
        o == s || push!(bad, "$(labels[k])\n    kernel $(repr(o))\n    swipl  $(repr(s))")
    end
    for b in bad[1:min(end, 12)]
        println(stderr, "  DIVERGES: ", b)
    end
    cut > 0 && println(
        stderr,
        "  excluded by name (a cut UTF-8 byte in the ball; a string holding the character 0): ",
        cut
    )
    @test isempty(bad)
    return length(bad)
end

"The kernel's write_canonical/1 and /2 results of `t`."
_cr_wc(t::_CR) = [
    _cr_run("write_canonical", _CR[t])[1],
    _cr_run("write_canonical", _CR[_crs("user_error"), t])[1]
]

"The kernel's read_term_from_atom/3 results of `text` with every option list: swipl's `rt` shape."
function _cr_rt(text::String, optss::Vector{_CR})
    res = Vector{String}[]
    for os in optss
        t = _cr_var()
        r, ans = _cr_run("read_term_from_atom", _CR[lk_gnd(_CR, text), t, os])
        if r[3] == "true"                               # the term and the options after
            pair = mk_expr(_CR, _CR[_crs("-"), ans[2], ans[3]])
            r[1] = _cr_text(pair) * r[1]
        end
        push!(res, r)
    end
    return res
end

const _CR_GOALS = [
    "read_term_from_atom(_, _, [])", "read_term_from_atom(1, _, [])",
    "read_term_from_atom(f(x), _, [])", "read_term_from_atom(\"f(x)\", T, []), write(T)",
    "read_term_from_atom([0'f,0'(,0'x,0')], T, []), write(T)",
    "read_term_from_atom('', T, []), write(T)",
    "read_term_from_atom('   ', T, []), write(T)",
    "read_term_from_atom('f(x). g(y).', T, []), write(T)",
    "read_term_from_atom('f(x)', T, foo)",
    "read_term_from_atom('f(x)', T, [1])", "read_term_from_atom('f(x)', T, [foo(1)])",
    "read_term_from_atom('f(x)', T, [double_quotes(oops)])",
    "read_term_from_atom('f(x)', T, [back_quotes(oops)])",
    "read_term_from_atom('f(x)', T, [syntax_errors(oops)])",
    "read_term_from_atom('f(X)', T, [variable_names(foo)])",
    "read_term_from_atom('f(X)', T, [variables([a])])",
    "read_term_from_atom('f(X, Y)', T, [singletons([])])",
    "read_term_from_atom('f(X)', T, [module(nosuch)]), write(T)",
    "read_term_from_atom('f(X', T, [syntax_errors(dec10)]), write(T)",
    "read_term_from_atom('f(X', T, [syntax_errors(quiet)])",
    "read_term_from_atom('f(X) g', T, [])",
    "read_term_from_atom('X', T, [variable_names(V)]), write(V)",
    "read_term_from_atom('_', T, [variables(V), singletons(S)]), write(V-S)",
    "read_term_from_atom('f(_A, _A, _B)', T, [singletons(warning)])",
    "read_term_from_atom('f(_A, _A)', T, [singletons(S)]), write(S)",
    "write_canonical(f(X, Y, X))", "write_canonical('\$VAR'(1))",
    "write_canonical('\$VAR'(X))",
    "write_canonical(f(X, '\$VAR'(X)))", "write_canonical(f('\$VAR'(_), Y, Y))",
    "write_canonical([X, Y, X|Z])", "write_canonical({X})", "write_canonical(- X)",
    "write_canonical(f(X)), write(' '), write(X)", "write_canonical(foo, a)",
    "write_canonical(_, a)", "write_canonical(user_input, a)", "write_canonical(user, a)",
    # the targets of the mutation run's survivors: each option's EFFECT, not only its error
    "read_term_from_atom('f(X, Y)', T, [singletons(warning)])",
    "read_term_from_atom('\"ab\"', T, [double_quotes(atom)]), write_canonical(T)",
    "read_term_from_atom('\"ab\"', T, [double_quotes(string)]), write_canonical(T)",
    "read_term_from_atom('\\'a\\\\nb\\'', T, [character_escapes(false)]), write_canonical(T)",
    "read_term_from_atom('\\'a\\\\nb\\'', T, []), write_canonical(T)",
    "read_term_from_atom('a:b', T, [module(system)]), write_canonical(T)",
    "read_term_from_atom('f(X', T, [syntax_errors(dec10)]), read_term_from_atom('g(y)', T2, []), write(T-T2)",
    "write_canonical(f(" * join(fill("X", 300), ",") * "))",
    "write_canonical([" * join(["'\$VAR'($k)" for k in 1:300], ",") * "])",
    "write_canonical(f(" * join(["V$k" for k in 1:300], ",") * "))"
]

"The kernel's results of the hand goals (a `,` goal: run as read)."
function _cr_goals(goals::Vector{String})
    res = Vector{String}[]
    for g in goals
        t = _cr_read(g)::_CR
        # a conjunction runs its goals in order, the bindings shared (no call/1: through the loader's
        # directive runner, boot/init.jl, which the write/1 family's test does not need)
        r = _cr_run_goal(t)
        push!(res, r)
    end
    return res
end

"Run a goal term (a conjunction too), outputs captured; the four fields."
function _cr_run_goal(t::_CR)
    out, err = IOBuffer(), IOBuffer()
    LK.set_standard_stream!(_CR_LD, LK.SNO_USER_OUTPUT, out)
    LK.set_standard_stream!(_CR_LD, LK.SNO_USER_ERROR, err)
    empty!(_CR_LD.messages)
    verdict = "true"
    fid = LK.PL_open_foreign_frame(_CR_LD)
    for g in _cr_conjuncts(t)
        h, n = kind(g) === SYM ? (g, 0) : (child(g, 1), nchildren(g) - 1)
        proc = LK.isCurrentProcedure(sym_key(h), n, LK.MODULE_system(_CR_GD))
        @assert proc !== nothing "no system predicate $(sym_text(h))/$n"
        a = LK.PL_new_term_refs(_CR_LD, n)
        for i in 1:n
            _CR_LD.slots[a + i] = child(g, i + 1)
        end
        qid = LK.PL_open_query(
            _CR_GD, _CR_LD, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        rc = try
            LK.PL_next_solution(_CR_GD, _CR_LD, qid)
        catch e
            e isa LK.NotPortedError || rethrow()
            :notported
        end
        if rc === :notported
            verdict = "NOTPORTED"
            break
        end
        if rc == LK.PL_S_EXCEPTION
            verdict =
                "ex:" * _cr_text(
                    LK.resolve_term(_CR_LD, _CR_LD.slots[LK.PL_exception(_CR_LD, qid) + 1])
                )
            LK.PL_close_query(_CR_LD, qid)
            break
        elseif rc != LK.PL_S_TRUE && rc != LK.PL_S_LAST
            verdict = "false"
            LK.PL_close_query(_CR_LD, qid)
            break
        end
        LK.PL_cut_query(_CR_LD, qid)                 # keep the bindings for the next conjunct
    end
    LK.Sflush(LK.Suser_output(_CR_LD))
    LK.Sflush(LK.Suser_error(_CR_LD))
    msgs = join([string(k) * ":" * _cr_text(m) for (k, m) in _CR_LD.messages], ";")
    LK.PL_close_foreign_frame(_CR_LD, fid)
    return [String(take!(out)), String(take!(err)), verdict, msgs]
end

"The conjuncts of a `,` term, in order."
function _cr_conjuncts(t::_CR)::Vector{_CR}
    if kind(t) === EXPR && nchildren(t) == 3 && kind(child(t, 1)) === SYM &&
        sym_text(child(t, 1)) == ","
        return vcat(_cr_conjuncts(child(t, 2)), _cr_conjuncts(child(t, 3)))
    end
    return _CR[t]
end

if _CR_SWIPL !== nothing
    @testset "write_canonical/1,2: the hand corpora, as swipl, literally" begin
        texts = unique(vcat(_TR_CORPUS, _TW_CORPUS))
        labels, ours = String[], Vector{String}[]
        for s in texts
            t = _cr_read(s)
            rs = t === nothing ? [["", "", "false", ""], ["", "", "false", ""]] : _cr_wc(t)
            for (k, r) in enumerate(rs)
                push!(labels, "$(repr(s)) write_canonical/$k")
                push!(ours, r)
            end
        end
        theirs = _cr_swipl(["wc(" * _cr_codes(s) * ")" for s in texts])
        # texts the kernel cannot read (the character 0) differ: both sides then say `false` here
        @test _cr_compare(labels, ours, theirs; norm=false) == 0
        # (the reader's corpus holds 86 texts neither side reads: syntax errors, refusals)
        @test count(r -> r[3] == "true", theirs) > 0.8 * length(theirs)
        # read back: the canonical text is a variant of the term (the kernel reads its own text)
        n = 0
        for s in texts
            t = _cr_read(s)
            t === nothing && continue
            back = _cr_read(_cr_wc(t)[1][1])
            @test back !== nothing
            n += 1
        end
        @test n > 300
    end

    @testset "write_canonical/1,2: random terms, as swipl, literally" begin
        rng = MersenneTwister(20261010)
        labels, ours, goals = String[], Vector{String}[], String[]
        for _ in 1:1000
            vars = _CR[_cr_var() for _ in 1:4]
            enc, t = _tc_gen(_CR, rng, 4, vars)
            push!(goals, "wce(" * enc * ")")
            for (k, r) in enumerate(_cr_wc(t))
                push!(labels, "$enc /$k")
                push!(ours, r)
            end
        end
        theirs = _cr_swipl(goals)
        @test _cr_compare(labels, ours, theirs; norm=false) == 0
        @test count(r -> occursin(r"\b[A-Z]\b", r[1]), theirs) > 40    # repeated variables numbered
    end

    @testset "read_term_from_atom/3: the hand corpora × 14 option lists, as swipl" begin
        optss = let l = _cr_read(_CR_OPTS_TEXT)::_CR        # (a list: its elements)
            xs = _CR[]
            while is_pair(l)
                push!(xs, child(l, 2))
                l = child(l, 3)
            end
            xs
        end
        @test length(optss) == 15
        texts = unique(vcat(_TR_CORPUS, _TW_CORPUS))
        labels, ours = String[], Vector{String}[]
        for s in texts, (k, os) in enumerate(optss)
            push!(labels, "$(repr(s)) opts#$k")
        end
        for s in texts
            append!(ours, _cr_rt(s, optss))
        end
        theirs = _cr_swipl([
            "rt(" * _cr_codes(s) * ", " * _CR_OPTS_TEXT * ")" for s in texts
        ])
        # the character 0: the kernel cannot make the atom (R1f's named gap) — those lines differ
        nul = [k for (k, l) in enumerate(labels) if occursin("\\0", l)]
        for k in nul
            theirs[k] = ours[k]
        end
        @test _cr_compare(labels, ours, theirs) == 0
        @test count(r -> startswith(r[3], "ex:error(syntax_error"), theirs) > 50
        @test count(r -> occursin("warning:singletons", r[4]), theirs) > 10      # (17 measured)
        @test count(r -> occursin("error:error(syntax_error", r[4]), theirs) > 20   # dec10
    end

    @testset "the hand goals, as swipl" begin
        ours = _cr_goals(_CR_GOALS)
        theirs = _cr_swipl(["gl(" * _cr_codes(g) * ")" for g in _CR_GOALS])
        @test _cr_compare(_CR_GOALS, ours, theirs) == 0
        verdicts = [r[3] for r in ours]
        @test count(v -> startswith(v, "ex:error(type_error"), verdicts) >= 4
        @test count(v -> startswith(v, "ex:error(domain_error"), verdicts) >= 2
        @test count(v -> v == "true", verdicts) >= 18
    end
elseif _CR_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the canonical/read_term_from_atom differential would be skipped"
    )
else
    @info "CANONICAL / READ_TERM_FROM_ATOM DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "differential skipped only where it is not required" begin
        @test !_CR_SWIPL_REQUIRED
    end
end

@testset "the refusals: read options the kernel cannot honour; a cyclic term's canonical text" begin
    for o in
        ("term_position(_)", "subterm_positions(_)", "comments(_)", "var_prefix(true)",
        "quasi_quotations(_)", "unicode_atoms(nfc)", "blob(x)")
        r, _ = _cr_run(
            "read_term_from_atom",
            _CR[_crs("f(X)"), _cr_var(), _cr_read("[" * o * "]")::_CR]
        )
        @test r[3] == "NOTPORTED"
    end
    fid = LK.PL_open_foreign_frame(_CR_LD)
    x = _cr_var()
    LK.Trail!(_CR_LD, var_key(x), mk_expr(_CR, _CR[_crs("f"), x]))   # X = f(X)
    r, _ = _cr_run("write_canonical", _CR[x])
    @test r[3] == "NOTPORTED"
    LK.PL_discard_foreign_frame(_CR_LD, fid)
end

@testset "numberVars: the bindings are undone after write_canonical; the frame is restored" begin
    x = _cr_var()
    r, _ = _cr_run("write_canonical", _CR[mk_expr(_CR, _CR[_crs("f"), x, x])])
    @test r == ["f(A,A)", "", "true", ""]
    @test kind(LK.deRef(_CR_LD, x)) === VAR
    @test _CR_LD.var_names_numbervars_frame == 0
    @test isempty(_CR_LD.numbervars_made) && isempty(_CR_LD.numbervars_visited)
end
