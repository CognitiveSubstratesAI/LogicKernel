# ORIGINAL: R1e's write/1 family gate — write/1,2, writeq/1,2, writeln/1,2, print/1,2, write_term/2,3 (PL_scan_options), nl/0,1 over the standard streams, against swipl 10.1.16.
# test/core_text/test_write_family_swipl.jl — the rest of R1e, part one (decision 2a, user
# 2026-10-07: the current output a Julia IO the host sets, with the aliases `user_output` and
# `user_error`; decision 3a: print/1 as swipl's with portray/1 undefined):
#   * THE PREDICATES, as swipl runs them: every term of the writer's hand corpus and 1,000 random
#     terms, each written by 40 calls — write/1, writeq/1, print/1, writeln/1, their /2 forms to
#     `user_output`, `user_error` and `user`, write_term/2 with 30 option lists (every option the
#     kernel ports, `Name = Value` and bare `Name` forms) and write_term/3 to `user_error` — each
#     compared on THREE things: the text on user_output, the text on user_error, and the verdict
#     (true, false, or the exception term, context included). swipl's run rebinds `user_output`,
#     `user_error` and the current output to files per call, as the host gives the kernel
#     a buffer for each (`set_standard_stream!`). Variables are named by first occurrence on both
#     sides before the texts are compared;
#   * THE ERRORS AND EDGES, 91 hand goals as whole goals: every stream argument (`foo`, `1`, a
#     variable, `user_input`, `current_input`, `protocol`), every option error (a non-list, a
#     partial list, a bad item, a bad value of each type, an unknown option ignored), the
#     `variable_names` option (its errors; a `'$VAR'` written in the term stays a term), max_depth,
#     max_text and `truncated`, fullstop and nl, nl/0,1;
#   * THE REFUSALS, explicit: write_term's `portray_goal` (calling Prolog, V9);
#   * THE HOST: the streams opened over stdin/stdout/stderr when first asked for; one replaced
#     (`set_standard_stream!`) — current output follows; a write error on a stream (a closed
#     buffer) is `io_error(write, Alias)`; the `variable_names` bindings are undone after the write.
#   * `protocol` (no protocol stream) is `existence_error(stream, protocol)` — swipl 10.1.16 ABORTS
#     on it (a lock released twice in `get_stream_handle`); pinned against the expected term, never
#     run on swipl.
using Test, LogicKernel, Random
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "text_corpora_testlib.jl"))
const _WF = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_wfs(x) = lk_sym(_WF, Symbol(x))
_wf_var() = mk_var(_WF, LK.fresh_var_keys!(1))

const _WF_SWIPL = Sys.which("swipl")
const _WF_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

const _WF_GD = LK.PL_global_data{_WF}()
const _WF_LD = LK.PL_local_data{_WF}()

"Run predicate `name` on `args`: `(rc, ball)` — `:true`, `:false`, `:exception` (and its ball), or `:notported`."
function _wf_call(name::String, args::Vector{_WF}; gd=_WF_GD, ld=_WF_LD)
    proc = LK.isCurrentProcedure(sym_key(_wfs(name)), length(args), LK.MODULE_system(gd))
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
            (:true, nothing)
        elseif rc == LK.PL_S_EXCEPTION
            (:exception, LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1]))
        else
            (:false, nothing)
        end
    catch e
        e isa LK.NotPortedError || rethrow()
        (:notported, nothing)
    end
    out[1] === :notported || LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"The kernel's read of `text` (term_to_atom/2), or `nothing`."
function _wf_read(text::String)::Union{Nothing, _WF}
    v = _wf_var()
    fid = LK.PL_open_foreign_frame(_WF_LD)
    a = LK.PL_new_term_refs(_WF_LD, 2)
    _WF_LD.slots[a + 1] = v
    _WF_LD.slots[a + 2] = lk_gnd(_WF, text)
    proc = LK.isCurrentProcedure(sym_key(_wfs("term_to_atom")), 2, LK.MODULE_system(_WF_GD))
    qid = LK.PL_open_query(
        _WF_GD, _WF_LD, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(_WF_GD, _WF_LD, qid)
    t = if (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST)
        LK.resolve_term(_WF_LD, _WF_LD.slots[a + 1])
    else
        nothing
    end
    LK.PL_close_query(_WF_LD, qid)
    LK.PL_close_foreign_frame(_WF_LD, fid)
    return t
end

"The kernel's writeq text of `t` (term_to_atom/2)."
function _wf_text(t::_WF)::String
    fid = LK.PL_open_foreign_frame(_WF_LD)
    a = LK.PL_new_term_refs(_WF_LD, 2)
    _WF_LD.slots[a + 1] = t
    _WF_LD.slots[a + 2] = _wf_var()
    proc = LK.isCurrentProcedure(sym_key(_wfs("term_to_atom")), 2, LK.MODULE_system(_WF_GD))
    qid = LK.PL_open_query(
        _WF_GD, _WF_LD, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(_WF_GD, _WF_LD, qid)
    @assert rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
    s = sym_text(LK.resolve_term(_WF_LD, _WF_LD.slots[a + 2]))
    LK.PL_close_query(_WF_LD, qid)
    LK.PL_close_foreign_frame(_WF_LD, fid)
    return s
end

"""
Call `name` on `args` with user_output and user_error each a fresh buffer: `[out, err, verdict]` —
the verdict `true`, `false`, `NOTPORTED`, or `ex:` and the ball's writeq text.
"""
function _wf_run(name::String, args::Vector{_WF})::Vector{String}
    out, err = IOBuffer(), IOBuffer()
    LK.set_standard_stream!(_WF_LD, LK.SNO_USER_OUTPUT, out)
    LK.set_standard_stream!(_WF_LD, LK.SNO_USER_ERROR, err)
    rc, ball = _wf_call(name, args)
    LK.Sflush(LK.Suser_output(_WF_LD))
    LK.Sflush(LK.Suser_error(_WF_LD))
    verdict = if rc === :true
        "true"
    elseif rc === :false
        "false"
    elseif rc === :notported
        "NOTPORTED"
    else
        "ex:" * _wf_text(ball::_WF)
    end
    return [String(take!(out)), String(take!(err)), verdict]
end

"The arguments of a list term."
function _wf_list(l::_WF)::Vector{_WF}
    xs = _WF[]
    while is_pair(l)
        push!(xs, child(l, 2))
        l = child(l, 3)
    end
    return xs
end

# The calls each term is written by: o(Pred, ArgsBefore, ArgsAfter) — the term goes between.
const _WF_OPS_TEXT = """[
    o(write, [], []), o(writeq, [], []), o(print, [], []), o(writeln, [], []),
    o(write, [user_output], []), o(write, [user_error], []), o(writeq, [user], []),
    o(print, [user_error], []), o(writeln, [user_error], []),
    o(write_term, [], [[]]), o(write_term, [], [[quoted(true)]]),
    o(write_term, [], [[quoted(true), ignore_ops(true)]]),
    o(write_term, [], [[quoted(true), dotlists(true)]]),
    o(write_term, [], [[quoted(true), no_lists(true)]]),
    o(write_term, [], [[quoted(true), brace_terms(false)]]),
    o(write_term, [], [[quoted(true), portable(true)]]),
    o(write_term, [], [[quoted(true), quote_non_ascii(true)]]),
    o(write_term, [], [[quoted(true), pattern_syntax_solo(true)]]),
    o(write_term, [], [[quoted(true), character_escapes(false)]]),
    o(write_term, [], [[quoted(true), character_escapes_unicode(false)]]),
    o(write_term, [], [[max_depth(3)]]), o(write_term, [], [[max_depth(2), quoted(true)]]),
    o(write_term, [], [[max_text(2), quoted(true)]]),
    o(write_term, [], [[spacing(next_argument), quoted(true)]]),
    o(write_term, [], [[quoted(true), fullstop(true)]]),
    o(write_term, [], [[fullstop(true), nl(true)]]), o(write_term, [], [[nl(true)]]),
    o(write_term, [], [[portray(true)]]), o(write_term, [], [[portrayed(true), quoted(true)]]),
    o(write_term, [], [[numbervars(true)]]), o(write_term, [], [[numbervars(false), quoted(true)]]),
    o(write_term, [], [[priority(999), quoted(true)]]), o(write_term, [], [[priority(0)]]),
    o(write_term, [], [[partial(true)]]), o(write_term, [], [[quoted, numbervars]]),
    o(write_term, [], [[quoted = true, max_depth = 4]]),
    o(write_term, [], [[back_quotes(string), quoted(true)]]),
    o(write_term, [], [[module(user), quoted(true), blobs(portray), attributes(ignore)]]),
    o(write_term, [], [[unknown_option_foo(1), quoted(on), cycles(true)]]),
    o(write_term, [user_error], [[quoted(true), spacing(standard)]])
]"""

"The calls, as `(name, before, after)`."
function _wf_ops()::Vector{Tuple{String, Vector{_WF}, Vector{_WF}}}
    l = _wf_read(_WF_OPS_TEXT)::_WF
    return [
        (sym_text(child(o, 2)), _wf_list(child(o, 3)), _wf_list(child(o, 4))) for
        o in _wf_list(l)
    ]
end

"The kernel's results of every call on `t`."
_wf_term_results(t::_WF, ops) =
    [_wf_run(name, _WF[pre..., t, post...]) for (name, pre, post) in ops]

# The hand goals: whole goals, each run as read. (`protocol` is pinned below, never run on swipl.)
const _WF_GOALS = [
    "nl", "nl(user_output)", "nl(user_error)", "nl(user)", "nl(foo)", "nl(_)", "nl(1)",
    "nl(user_input)", "nl(current_output)", "write(foo, x)", "write(1, x)",
    "write(f(x), x)",
    "write(_, x)", "write(user_input, x)", "write(current_input, x)",
    "write(current_output, x)",
    "write([], x)", "writeq('\$VAR'(1))", "print('\$VAR'(1))", "write('\$VAR'(25))",
    "print('\$VAR'('Foo'))", "print('\$VAR'(\"Foo\"))", "writeln(user_error, 'a b')",
    "write_term(a, foo)", "write_term(a, [foo])", "write_term(a, [foo(1)])",
    "write_term(a, [quoted(maybe)])", "write_term(a, [quoted(true)|_])",
    "write_term(a, [_])",
    "write_term(a, [quoted(true)|foo])", "write_term(a, [f(a,b)])", "write_term(a, [1])",
    "write_term(a, [X = true])", "write_term('A', [quoted = 1])",
    "write_term('A', [quoted(2)])",
    "write_term(a, [priority(1300)])", "write_term(a, [priority(-1)])",
    "write_term(a, [priority(x)])", "write_term(a, [priority])",
    "write_term(a, [spacing(odd)])",
    "write_term(a, [spacing(1)])", "write_term(a, [max_depth(x)])",
    "write_term(a, [max_depth(99999999999999999999)])", "write_term(a, [module(nosuch)])",
    "write_term(a, [module(1)])", "write_term(a, [attributes(x)])",
    "write_term(a, [blobs(x)])",
    "write_term(a, [back_quotes(x)])", "write_term(a, quoted(true))",
    "write_term(a, [quoted(true), quoted(false)])", "write_term('A', [fullstop(true)])",
    "write_term(- 1, [fullstop(true)])",
    "write_term(f(X,Y,X), [variable_names(['X'=X, 'Y'=Y])])",
    "write_term(f(X,Y), [variable_names(['X'=X, x=Y])])",
    "write_term(f(X), [variable_names(['X'=X|_])])",
    "write_term(f(X), [variable_names(foo)])",
    "write_term(f(X), [variable_names([foo])])",
    "write_term(f(X), [variable_names([1=X])])",
    "write_term(f(X), [variable_names(['X'=a])])",
    "write_term(f('\$VAR'(1), X), [variable_names(['X'=X])])",
    "write_term(f('\$VAR'(1), X), [variable_names(['X'=X]), numbervars(true)])",
    "write_term([a|X], [variable_names(['X'=X])])",
    "write_term([a|X], [variable_names(['X'=X]), dotlists(true)])",
    "write_term(f(A,B), [variable_names(['_'=A, '_X'=B]), quoted(true)])",
    "write_term(f(X), [variable_names(['X'=X, 'Y'=X])])",
    "write_term([1,2,3,4,5,6,7,8,9,10,11,12], [max_depth(3)])",
    "write_term(f(g(h(i(j)))), [max_depth(3)])", "write_term(aaaaaaaaaa, [max_text(3)])",
    "write_term(\"aaaaaaaaaa\", [max_text(3), quoted(true)])",
    "write_term(f(a,b), [max_depth(1), truncated(T)])",
    "write_term(f(a), [max_depth(5), truncated(false)])",
    "write_term(f(a), [max_depth(5), truncated(true)])", "write_term(f(a), [truncated(x)])",
    "write_term(user_error, a, [quoted(true)])", "write_term(foo, a, [])",
    "write_term(_, a, [quoted(true)])",
    # each option feature reached by one goal (the mutation run's targets)
    "write_term('A', [quoted])", "write_term('A', [quoted(on)])", "writeq('a\\nb')",
    "writeq(user_error, 'A b')", "print('a b')", "write_term('\$VAR'(1), [portray(true)])",
    "write_term({a,b}, [ignore_ops(true)])",
    "write_term(\"s\", [back_quotes(string), quoted(true)])",
    "write_term(-, [fullstop(true)])", "write_term(-, [fullstop(true), nl(true)])",
    "print('\\x1\\')", "write_term('\\x1\\', [quoted(true)])", "writeq('\\x1\\')",
    "write_term(f(X), [variable_names(['X'=X]), portray(true)])",
    # past 1,000 names the list is checked (`lengthList`): the culprit is the 1,000th
    "write_term(a, [variable_names([" * join(fill("'A'=_", 1001), ",") * "|foo])])"
]

"The kernel's results of the hand goals."
function _wf_goal_results(goals::Vector{String})::Vector{Vector{String}}
    res = Vector{String}[]
    for g in goals
        t = _wf_read(g)::_WF
        name, args = if kind(t) === SYM
            (sym_text(t), _WF[])
        else
            (sym_text(child(t, 1)), _WF[child(t, i) for i in 2:nchildren(t)])
        end
        push!(res, _wf_run(name, args))
    end
    return res
end

const _WF_DRIVER = raw"""
:- op(0, fx, $).
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
% G with user_output, user_error and the current output each a fresh file: their texts and the verdict
:- tmp_file(wfo, Fo), tmp_file(wfe, Fe), assertz(cap_files(Fo, Fe)).
cap(G) :-
    cap_files(Fo, Fe),
    open(Fo, write, SO, [encoding(utf8)]), open(Fe, write, SE, [encoding(utf8)]),
    stream_property(OO, alias(user_output)), stream_property(OE, alias(user_error)),
    current_output(OC),
    set_stream(SO, alias(user_output)), set_stream(SE, alias(user_error)), set_output(SO),
    ( catch(G, E, true) -> ( var(E) -> R = true ; R = ex(E) ) ; R = false ),
    set_stream(OO, alias(user_output)), set_stream(OE, alias(user_error)), set_output(OC),
    close(SO), close(SE),
    read_file_to_codes(Fo, CO, [encoding(utf8)]), read_file_to_codes(Fe, CE, [encoding(utf8)]),
    format("~w ~w ", [CO, CE]),
    ( R = ex(B) -> term_to_atom(B, BA), atom_codes(BA, BC), format("~w", [BC]) ; write(R) ), nl.
ops(T, Ops) :- forall(member(o(P, Pre, Post), Ops), (append(Pre, [T|Post], Args), G =.. [P|Args], cap(G))).
wf(Cs, Ops) :- atom_codes(A, Cs),
    ( catch(term_to_atom(T, A), _, fail) -> ops(T, Ops)
    ; forall(member(_, Ops), (write('unreadable unreadable unreadable'), nl)) ).
wfe(Enc, Ops) :- length(Vs, 8), dec(Enc, T, Vs), ops(T, Ops).
gl(Cs) :- atom_codes(A, Cs), term_to_atom(G, A), cap(G).
"""

_wf_codes(s::String)::String = "[" * join(Int.(collect(s)), ",") * "]"

"swipl's results for `goals` (each prints one line per call), from one swipl process."
function _wf_swipl(goals::Vector{String})::Vector{Vector{String}}
    prog = IOBuffer()
    print(prog, _WF_DRIVER, "run :- ")
    for g in goals
        print(prog, g, ", ")
    end
    println(prog, "true.\n:- initialization((run, halt)).")
    out = mktempdir() do d
        f = joinpath(d, "wf.pl")
        write(f, String(take!(prog)))
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    lines = split(chomp(out), '\n')
    return [
        begin
            ws = split(l, ' ')
            @assert length(ws) == 3 "swipl line: $l"
            [
                ws[1] == "unreadable" ? "unreadable" : _wf_decode(ws[1]),
                ws[2] == "unreadable" ? "unreadable" : _wf_decode(ws[2]),
                startswith(ws[3], "[") ? "ex:" * _wf_decode(ws[3]) : String(ws[3])
            ]
        end for l in lines
    ]
end

_wf_decode(w::AbstractString)::String =
    String(Char.(parse.(Int, split(w[2:(end - 1)], ','; keepempty=false))))

"Name the variables of a text `_V0`, `_V1`… by first occurrence (their numbers differ)."
function _wf_norm(s::String)::String
    seen = Dict{String, Int}()
    return replace(
        s,
        r"(?<![A-Za-z0-9_])_G?[0-9]+(?![A-Za-z0-9_])" =>
            m -> "_V" * string(get!(seen, m, length(seen)))
    )
end

"Compare the kernel's and swipl's results, label by label; print the first divergences."
function _wf_compare(labels, ours, theirs)
    @test length(ours) == length(theirs)
    bad = String[]
    for k in 1:min(length(ours), length(theirs))
        o = [_wf_norm(x) for x in ours[k]]
        s = [_wf_norm(x) for x in theirs[k]]
        o == s || push!(bad, "$(labels[k])\n    kernel $(repr(o))\n    swipl  $(repr(s))")
    end
    for b in bad[1:min(end, 12)]
        println(stderr, "  DIVERGES: ", b)
    end
    @test isempty(bad)
    return length(bad)
end

if _WF_SWIPL !== nothing
    @testset "the hand corpus: written by 40 calls each, as swipl" begin
        ops = _wf_ops()
        @test length(ops) == 40
        texts = unique(_TW_CORPUS)
        labels, ours = String[], Vector{String}[]
        unread = String[]
        for s in texts
            t = _wf_read(s)
            if t === nothing
                push!(unread, s)
                for (name, _, _) in ops
                    push!(labels, "$(repr(s)) $name")
                    push!(ours, ["unreadable", "unreadable", "unreadable"])
                end
                continue
            end
            for (op, r) in zip(ops, _wf_term_results(t, ops))
                push!(labels, "$(repr(s)) $(op[1])/$(length(op[2]) + 1 + length(op[3]))")
                push!(ours, r)
            end
        end
        theirs = _wf_swipl([
            "wf(" * _wf_codes(s) * ", " * _WF_OPS_TEXT * ")" for s in texts
        ])
        # what the kernel cannot read is what the reader refuses: an atom holding the character 0
        # (the term interface's named gap, R1f's review); swipl reads it — so its lines differ
        nul = [k for k in eachindex(ours) if ours[k][1] == "unreadable"]
        @test all(s -> occursin('\0', s), unread)
        for k in nul
            theirs[k] = ours[k]
        end
        println(stderr, "  hand corpus: $(length(texts)) terms × $(length(ops)) calls; ",
            "$(length(unread)) unreadable here (the character 0)")
        @test _wf_compare(labels, ours, theirs) == 0
        # not vacuous: texts on both streams, and swipl's own lines carry them
        @test count(r -> !isempty(r[1]), theirs) > 0.7 * length(theirs)
        @test count(r -> !isempty(r[2]), theirs) > 0.08 * length(theirs)   # 4 of 40 calls
        @test count(r -> r[3] == "true", theirs) > 0.9 * length(theirs)
    end

    @testset "random terms: written by 40 calls each, as swipl" begin
        ops = _wf_ops()
        rng = MersenneTwister(20261009)
        labels, ours, goals = String[], Vector{String}[], String[]
        for i in 1:1000
            vars = _WF[_wf_var() for _ in 1:4]
            enc, t = _tc_gen(_WF, rng, 4, vars)
            push!(goals, "wfe(" * enc * ", " * _WF_OPS_TEXT * ")")
            for (op, r) in zip(ops, _wf_term_results(t, ops))
                push!(labels, "$enc $(op[1])")
                push!(ours, r)
            end
        end
        theirs = _wf_swipl(goals)
        @test _wf_compare(labels, ours, theirs) == 0
        @test count(r -> !isempty(r[1]), theirs) > 0.7 * length(theirs)
        @test count(r -> !isempty(r[2]), theirs) > 0.08 * length(theirs)   # 4 of 40 calls
    end

    @testset "the hand goals: stream and option errors, variable_names, depth, as swipl" begin
        ours = _wf_goal_results(_WF_GOALS)
        theirs = _wf_swipl(["gl(" * _wf_codes(g) * ")" for g in _WF_GOALS])
        @test _wf_compare(_WF_GOALS, ours, theirs) == 0
        # the goals reach what they are for: errors of each kind, and texts
        verdicts = [r[3] for r in ours]
        @test count(v -> startswith(v, "ex:error(existence_error(stream"), verdicts) >= 3
        @test count(
            v -> startswith(v, "ex:error(domain_error(stream_or_alias"), verdicts
        ) >= 3
        @test count(
            v -> startswith(v, "ex:error(permission_error(write,stream"), verdicts
        ) >= 3
        @test count(v -> startswith(v, "ex:error(type_error(option"), verdicts) >= 3
        @test count(v -> v == "true", verdicts) >= 30
    end
elseif _WF_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the write family differential would be skipped"
    )
else
    @info "WRITE FAMILY DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "write family differential skipped only where it is not required" begin
        @test !_WF_SWIPL_REQUIRED
    end
end

@testset "protocol: no protocol stream is existence_error(stream, protocol) (swipl aborts)" begin
    for g in ("write(protocol, x)", "nl(protocol)", "write_term(protocol, x, [])")
        r = _wf_goal_results([g])[1]
        @test r[1] == "" && r[2] == ""
        @test startswith(r[3], "ex:error(existence_error(stream,protocol),context(system:")
    end
end

@testset "a cyclic option list is type_error(list, L) after 1,000 items (as swipl, probed)" begin
    # L = [quoted(true)|L]: built with a binding, as the reader cannot write one
    fid = LK.PL_open_foreign_frame(_WF_LD)
    l = _wf_var()
    cell = mk_expr(
        _WF, _WF[_wfs("[|]"), mk_expr(_WF, _WF[_wfs("quoted"), _wfs("true")]), l]
    )
    LK.Trail!(_WF_LD, var_key(l), cell)
    # the ball holds the cyclic list, which no term of the interface can hold: read it through the
    # bindings, before the query closes
    proc = LK.isCurrentProcedure(sym_key(_wfs("write_term")), 2, LK.MODULE_system(_WF_GD))
    a = LK.PL_new_term_refs(_WF_LD, 2)
    _WF_LD.slots[a + 1] = _wfs("a")
    _WF_LD.slots[a + 2] = l
    qid = LK.PL_open_query(
        _WF_GD, _WF_LD, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(_WF_GD, _WF_LD, qid)
    @test rc == LK.PL_S_EXCEPTION
    if rc == LK.PL_S_EXCEPTION
        ball = LK.deRef(_WF_LD, _WF_LD.slots[LK.PL_exception(_WF_LD, qid) + 1])
        f = LK.deRef(_WF_LD, child(ball, 2))
        @test kind(f) === EXPR && sym_text(child(f, 1)) == "type_error" &&
            sym_text(LK.deRef(_WF_LD, child(f, 2))) == "list"
        # the culprit is the options list itself, cyclic (swipl: type_error(list, L)); the ball is a
        # copy, so a `[quoted(true)|T]` cell whose tail leads back to that same cell
        c = LK.deRef(_WF_LD, child(f, 3))
        @test is_pair(c) && sym_text(child(LK.deRef(_WF_LD, child(c, 2)), 1)) == "quoted" &&
            LK.deRef(_WF_LD, child(c, 3)) === c
    end
    LK.PL_close_query(_WF_LD, qid)
    LK.PL_discard_foreign_frame(_WF_LD, fid)
end

@testset "the refusals: write_term's portray_goal (calling Prolog, V9)" begin
    r = _wf_goal_results(["write_term(a, [portray_goal(foo)])"])[1]
    @test r == ["", "", "NOTPORTED"]
end

@testset "the host: standard streams, replaced, a write error, bindings undone" begin
    # a new local data has no stream until one is asked for; then stdin/stdout/stderr
    ld = LK.PL_local_data{_WF}()
    @test !ld.IO_initialised && all(isnothing, ld.IO_streams)
    LK._initIO(ld)
    @test ld.IO_initialised && LK.Scurout(ld) === LK.Suser_output(ld)
    @test LK.Suser_output(ld) === nothing || (LK.Suser_output(ld).flags & LK.SIO_LBUF) != 0
    @test LK.Suser_error(ld) === nothing || (LK.Suser_error(ld).flags & LK.SIO_NBUF) != 0
    # replacing user_output moves the current output with it; user_error stays unbuffered
    b = IOBuffer()
    s = LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, b)
    @test LK.Suser_output(ld) === s && LK.Scurout(ld) === s
    e = LK.set_standard_stream!(ld, LK.SNO_USER_ERROR, IOBuffer())
    @test (e.flags & LK.SIO_NBUF) != 0 && LK.Scurout(ld) === s
    # a write error: user_error over a closed buffer is io_error(write, user_error)
    closed = IOBuffer()
    close(closed)
    LK.set_standard_stream!(_WF_LD, LK.SNO_USER_ERROR, closed)
    rc, ball = _wf_call("write", _WF[_wfs("user_error"), _wfs("x")])
    @test rc === :exception
    @test startswith(_wf_text(ball::_WF), "error(io_error(write,user_error),context(")
    # write_term's variable_names binds inside a frame it discards: X is unbound after
    x = _wf_var()
    cons(h, t) = mk_expr(_WF, _WF[_wfs("[|]"), h, t])
    vn = mk_expr(
        _WF,
        _WF[
            _wfs("variable_names"),
            cons(
                mk_expr(_WF, _WF[_wfs("="), _wfs("X"), x]), mk_nil(_WF))
        ]
    )
    out = _wf_run("write_term", _WF[mk_expr(_WF, _WF[_wfs("f"), x]), cons(vn, mk_nil(_WF))])
    @test out == ["f(X)", "", "true"]
    @test _WF_LD.var_names_numbervars_frame == 0
    # …and unbound INSIDE the query, after write_term/2 succeeded (swipl: `write_term(f(X),
    # [variable_names(['X'=X])]), var(X)` succeeds) — closing the query would undo it anyway
    LK.set_standard_stream!(_WF_LD, LK.SNO_USER_OUTPUT, IOBuffer())
    proc = LK.isCurrentProcedure(sym_key(_wfs("write_term")), 2, LK.MODULE_system(_WF_GD))
    fid = LK.PL_open_foreign_frame(_WF_LD)
    a = LK.PL_new_term_refs(_WF_LD, 2)
    _WF_LD.slots[a + 1] = mk_expr(_WF, _WF[_wfs("f"), x])
    _WF_LD.slots[a + 2] = cons(vn, mk_nil(_WF))
    qid = LK.PL_open_query(
        _WF_GD, _WF_LD, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(_WF_GD, _WF_LD, qid)
    @test rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
    @test kind(LK.deRef(_WF_LD, x)) === VAR                  # before the query closes
    LK.PL_close_query(_WF_LD, qid)
    LK.PL_close_foreign_frame(_WF_LD, fid)
end
