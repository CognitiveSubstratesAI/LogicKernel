# ORIGINAL: LB3's gate (lk-channel evidence/r2/design/loader_boot.md LD2, LD3, section 6) — pl-qlf.c's boot compilation, `compileFile`,
# `directiveClause`, `update_conditional_compilation`, `compileFileList`, the boot entry and the write-side predicates, written from the C
# (swipl-devel cbf4e189), UNRUN: no Julia was run when this file was written. Rows marked `# UNVERIFIED on the kernel: gate decides` are
# the C code's behaviour, not yet seen on the kernel.
# test/files/test_qlf_swipl.jl — prefix `_QL` / `_ql_`:
#   * A PROGRAM of facts, rules and directives with `:- if/else/endif` nests (two levels deep, the bound), compiled by `compileFile` into a
#     fresh database; the cases `t_q<id>(L)` are read back and encoded by ONE extractor (`_ql_enc`) and compared with swipl's answers for the
#     same file consulted (the loadable behaviours: swipl runs the same conditional compilation). The pins are swipl 10.1.19-1-gcbf4e189's,
#     two runs byte-identical (2026-10-31); with `swipl` on PATH the live answers are compared with the pins too.
#   * White-box rows from the C code (kernel only: swipl's consult differs there): `'$:-'`, the nesting bound, an unmatched `:- endif`,
#     `elif` (not a conditional), a missing file, a syntax error, a failing directive collected, `compileFileList` up to `-c`, the boot
#     entry's state, the 22-entry registration table (eight shells, 14 refused by name).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the boot compilation (src/pl-qlf.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _QL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_qls(x) = lk_sym(_QL, Symbol(x))

_ql_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes (the ONE extractor of both sides)."
function _ql_enc(t::_QL, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ql_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ql_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ql_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ql_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: the same driver as test/core_lang/test_at_body_swipl.jl's (consult, then every answer of each t_<id>/1, `enc`oded)
const _QL_DRIVER = raw"""
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
function _ql_swipl_lines(
    path::String, names::Vector{String}; pre::String=""
)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _QL_DRIVER * ":- initialization(($pre" * "fz_run('$path', [" *
            join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program both sides load: conditional compilation two levels deep (the bound), an `if` goal with a side effect, a directive qualified
# with `user`, a failing directive
const _QL_PROGRAM = raw"""
:- assertz(d(start)).
r(top).
:- if(true).
r(if_true).
:- if(fail).
r(hidden_in_false_if).
:- else.
r(inner_else).
:- endif.
:- else.
r(hidden_else).
:- endif.
:- if(fail).
r(f_if).
:- assertz(d(hidden_directive)).
:- if(assertz(d(hidden_if_goal))).
r(skipped_nested).
:- else.
r(skipped_nested_else).
:- endif.
:- else.
r(f_else).
:- endif.
:- if(assertz(d(if_goal))).
r(goal_if).
:- endif.
:- user:assertz(d(qualified)).
:- fail.
:- assertz(d(after_fail)).
p(X) :- r(X), X \== top.
r(end).
t_q01(L) :- findall(X, r(X), L).
t_q02(L) :- findall(X, d(X), L).
t_q03(L) :- findall(X, p(X), L).
"""
const _QL_NAMES = ["t_q01", "t_q02", "t_q03"]

# swipl 10.1.19-1-gcbf4e189, this program and driver, 2026-10-31, two runs byte-identical (evidence/LB3/ql/run.sh: prog.pl + drv.pl -> pins.out)
const _QL_PINNED = [
    "ok",
    "t_q01 c[116,95,113,48,49]/1(c[91,124,93]/2(a[116,111,112],c[91,124,93]/2(a[105,102,95,116,114,117,101],c[91,124,93]/2(a[105,110,110,101,114,95,101,108,115,101],c[91,124,93]/2(a[102,95,101,108,115,101],c[91,124,93]/2(a[103,111,97,108,95,105,102],c[91,124,93]/2(a[101,110,100],nil)))))))",
    "t_q02 c[116,95,113,48,50]/1(c[91,124,93]/2(a[115,116,97,114,116],c[91,124,93]/2(a[105,102,95,103,111,97,108],c[91,124,93]/2(a[113,117,97,108,105,102,105,101,100],c[91,124,93]/2(a[97,102,116,101,114,95,102,97,105,108],nil)))))",
    "t_q03 c[116,95,113,48,51]/1(c[91,124,93]/2(a[105,102,95,116,114,117,101],c[91,124,93]/2(a[105,110,110,101,114,95,101,108,115,101],c[91,124,93]/2(a[102,95,101,108,115,101],c[91,124,93]/2(a[103,111,97,108,95,105,102],c[91,124,93]/2(a[101,110,100],nil))))))"
]

# LB3-L3 (D-0299): the boot compile runs with `autoload` OFF. The program is read with the flag false (swipl: the flag set before consult;
# library(lists) loaded first because the driver's member/2 would need the autoloader); `if` carries ONE goal (the boot testset's
# conjunction directive needs ','/2, which boot/init.pl defines (since LB4 b2 loaded at the boot; the D stack's stand-in before)). swipl 10.1.19-1-gcbf4e189, 2026-11-01, two runs byte-identical.
const _QL_AUTOLOAD_PROGRAM = raw"""
:- if(current_prolog_flag(autoload, false)).
r(autoload_off).
:- endif.
:- if(current_prolog_flag(autoload, true)).
r(autoload_on).
:- endif.
'$load_additional_boot_files'.
t_q01(L) :- findall(X, r(X), L).
"""
const _QL_AUTOLOAD_PRE = "use_module(library(lists)), set_prolog_flag(autoload,false), "
const _QL_AUTOLOAD_PINNED = [
    "ok",
    "t_q01 c[116,95,113,48,49]/1(c[91,124,93]/2(a[97,117,116,111,108,111,97,100,95,111,102,102],nil))"
]

"A fresh database and the file `text` written to a temporary directory."
function _ql_db(text::String; name::String="prog.pl")
    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    f = joinpath(mktempdir(), name)
    write(f, text)
    return gd, ld, f
end

"The kernel's lines for `names` in the database, as the driver writes swipl's (the same encoder)."
function _ql_query_lines(gd, ld, names::Vector{String})::Vector{String}
    out = String[]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_qls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_QL, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _ql_enc(mk_expr(_QL, _QL[_qls(name), lk_answers(ld, (a:a)...)...]))
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
    return out
end

"The atoms of a list answer of `t_<id>/1`, in order, by the same extractor: the text after `a[...]` codes, decoded."
function _ql_list_atoms(line::String)::Vector{String}
    return [
        String(Char.(parse.(Int, split(m.captures[1], ',')))) for
        m in eachmatch(r"c\[91,124,93\]/2\(a\[([0-9,]+)\]", line)
    ]
end

"The messages the boot loop collected, as text (its Sdprintf branches, `_qlf_Sdprintf!`: still on `ld.messages`)."
_ql_messages(ld) =
    String[String(sym_text(m)) for (k, m) in ld.messages if k === :error && kind(m) === SYM]

"Compile `text` into a fresh database: the result of `compileFile`, the database, the local data, the file's path."
function _ql_compile(text::String; name::String="prog.pl")
    gd, ld, f = _ql_db(text; name)
    rc = LK.compileFile(gd, ld, nothing, f)
    return rc, gd, ld, f
end

@testset "compileFile as swipl's consult for the loadable program (q01-q03)" begin
    gd, ld, f = _ql_db(_QL_PROGRAM)
    ld.read_source.file = _qls("outer")                  # the source location pl_see saves and pl_seen restores
    ld.read_source.position.lineno = 7
    at = LK.boot_stacks(ld)
    rc = LK.compileFile(gd, ld, nothing, f)
    @test rc
    # H11 (loader_boot.md): the leftover of upstream's compileFile (pl-qlf.c:4726-4741), one file
    @test LK.boot_stacks(ld) != at && LK.boot_stacks(ld) == LK.compileFile_leaves(at, 1)
    @test sym_key(ld.read_source.file) == sym_key(_qls("outer")) &&
        ld.read_source.position.lineno == 7
    kernel = vcat(["ok"], _ql_query_lines(gd, ld, _QL_NAMES))
    @test length(kernel) == length(_QL_PINNED)
    for (k, p) in zip(kernel, _QL_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: both sides hold non-empty lists through the one extractor; the lists hold the clauses of the true parts and not the
    # hidden ones, so the comparison can pass and can fail
    r = _ql_list_atoms(_QL_PINNED[2])
    @test r == ["top", "if_true", "inner_else", "f_else", "goal_if", "end"]
    d = _ql_list_atoms(_QL_PINNED[3])
    @test d == ["start", "if_goal", "qualified", "after_fail"]
    @test !any(
        in(r),
        [
            "hidden_in_false_if",
            "hidden_else",
            "f_if",
            "skipped_nested",
            "skipped_nested_else"
        ]
    )
    @test !any(in(d), ["hidden_directive", "hidden_if_goal"])
    @test _ql_list_atoms(_QL_PINNED[4]) == r[2:end]
    @test !isempty(kernel[2]) && !isempty(_QL_PINNED[2])
    # a failing directive is collected as `File:Line: directive failed` and the loop goes on (the d row holds `after_fail`)
    # UNVERIFIED on the kernel: gate decides
    @test count(m -> occursin(r":[0-9]+: directive failed\n$", m), _ql_messages(ld)) == 1
    # the file's source record (lookupSourceFile, startConsult, LastModifiedFile) and the input restored by pl_seen
    sf = LK.lookupSourceFile_unlocked(gd, mk_sym(_QL, Symbol(abspath(f))), false)
    @test sf !== nothing && sf.count == 1 && sf.mtime == mtime(f) && !sf.system
    @test isempty(ld.input_context_stack) && LK.Scurin(ld) === LK.Suser_input(ld)
    @test LK.Scurin(ld) !== nothing          # not vacuous: `nothing === nothing` before the IO is initialised
end

@testset "the input stream before a file is the one restored after it (LB3-S4; swipl pin: restored)" begin
    # the stream current before the load is NOT user_input: closing the file's stream resets a current input that still is the file's to
    # user_input, so only a current input restored by pop_input_context stays what it was. Kernel side of the live row below.
    gd, ld, f = _ql_db("r(a).\n")
    LK._initIO(ld)                         # the standard streams exist only once the IO is initialised (until then each is `nothing`)
    @test LK.Suser_input(ld) !== nothing && LK.Suser_error(ld) !== nothing
    ld.IO_streams[LK.SNO_CURRENT_INPUT + 1] = LK.Suser_error(ld)
    @test LK.Scurin(ld) !== LK.Suser_input(ld)
    @test LK.compileFile(gd, ld, nothing, f)
    @test LK.Scurin(ld) === LK.Suser_error(ld)
    @test isempty(ld.input_context_stack)
end

@testset "the boot ld's standard streams leave the template; another open stream still refuses the copy (pl-file.c initIO)" begin
    # upstream's state file carries no stream table (initIO registers each process's own, cbf4e189 os/pl-file.c:547-549);
    # the kernel's template is a booted database, so `drop_boot_std_streams!` clears the dropped boot ld's three entries
    tm = LK.gd_template(_QL)
    @test !isempty(tm.stream_table) && all(isnothing, tm.stream_table)    # the boot wrote (initIO ran), nothing is live
    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    n0 = length(gd.stream_table)
    LK._initIO(ld)                                                         # the three user streams, registered
    std = [LK.Suser_input(ld), LK.Suser_output(ld), LK.Suser_error(ld)]
    @test length(gd.stream_table) == n0 + 3 &&
        all(s -> gd.stream_table[s.context] === s, std)
    @test_throws ErrorException LK.copy_global_data(gd)                    # not vacuous: live standard streams refuse it
    s = LK.Sopen_string(Vector{UInt8}("abc"), 3, "r")
    @test s !== nothing && LK.getStreamContext(gd, s) == n0 + 4
    LK.drop_boot_std_streams!(gd, ld)
    @test all(i -> gd.stream_table[i] === nothing, (n0 + 1):(n0 + 3))      # the standard slots, cleared
    @test gd.stream_table[n0 + 4] === s                                    # a stream the boot left open stays
    e = try
        LK.copy_global_data(gd)
        nothing
    catch err
        err
    end
    @test e isa ErrorException && occursin("the template holds an open stream", e.msg)
    gd.stream_table[n0 + 4] = nothing                                      # closed: the copy goes through
    c = LK.copy_global_data(gd)
    @test length(c.stream_table) == n0 + 4 && all(isnothing, c.stream_table)
end

@testset "the template keeps no autoImport link of the boot session (R-A; pl-qlf.c saveXRProc, XR_PRED)" begin
    # a started swipl loads the saved state, and autoImport links made while compiling the boot files are run-time
    # resolution, not saved state (cbf4e189 src/pl-qlf.c:2646-2648 writes a reference by its definition's module,
    # :771-777 resolves it afresh). swipl 10.1.19, live 2026-11-03: `'$c_current_predicate'(_, user:'$load_additional_boot_files')`
    # is false (user has no definition of it) and `user:'$load_additional_boot_files'` is true (system's, by autoImport).
    tm = LK.gd_template(_QL)
    u = LK.isCurrentProcedure(
        LK.sym_key(_qls("\$load_additional_boot_files")), 0, tm.modules_user
    )
    @test u !== nothing && u.definition.module_ == tm.modules_user.index    # its own definition, not system's
    @test !LK.isDefinedProcedure(tm, u)
    s = LK.isCurrentProcedure(
        LK.sym_key(_qls("\$load_additional_boot_files")), 0, LK.MODULE_system(tm)
    )
    @test s !== nothing && LK.isDefinedProcedure(tm, s) && s.definition.shared == 1   # unshared by the reset
    @test LK.drop_boot_autoimports!(LK.copy_global_data(tm)) == 0           # none left
    linked = 0
    for m in tm.modules
        m === nothing && continue
        for (_, p) in m.procedures
            linked += p.definition.module_ != m.index && p.flags == 0
        end
    end
    @test linked == 0                                                        # every remaining link is an import
    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    @test LK.compileFileList(gd, ld, nothing, String[])                     # the call links it again (autoImport)
    u = LK.isCurrentProcedure(
        LK.sym_key(_qls("\$load_additional_boot_files")), 0, gd.modules_user
    )
    @test u !== nothing && u.definition.module_ != gd.modules_user.index
end

@testset "the boot compile runs with autoload off (LB3-L3; swipl pin: autoload set false before consult)" begin
    dir = mktempdir()
    g = joinpath(dir, "autoload.pl")
    write(g, _QL_AUTOLOAD_PROGRAM)
    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    # AUTOLOAD1 A4: compileFileList sets `autoload` through PL_set_prolog_flag, whose propagateAutoload calls `\$autoload:set_autoload/1`
    # outside a boot session (pl-prologflag.c:987-1000); upstream runs compileFileList in the boot session only, so the row does too
    gd.bootsession = true
    @test LK.compileFileList(gd, ld, nothing, [g])
    gd.bootsession = false
    kl = _ql_query_lines(gd, ld, ["t_q01"])
    @test _ql_list_atoms(kl[1]) == _ql_list_atoms(_QL_AUTOLOAD_PINNED[2]) ==
        ["autoload_off"]
    @test kl[1] == _QL_AUTOLOAD_PINNED[2]
    @test String(sym_text(LK.PL_current_prolog_flag(gd, mk_sym(_QL, :autoload), :atom))) ==
        "true"                                            # restored after the list
    @test isempty(_ql_messages(ld))
end

@testset "R-B: closing a query after an exception on the unbooted database (owner ENG2, audit D-0377 item 3)" begin
    # findall/3 is undefined on setupProlog's database (boot/bags.pl not loaded): the query raises, and PL_close_query
    # then raises `_release_frozen!: slot 27 references global position 31 above the reset target 19`
    # (src/pl-inline.jl). A latent engine bug, not fixed here; the row stays broken until ENG2 lands.
    g = joinpath(mktempdir(), "autoload.pl")
    write(g, _QL_AUTOLOAD_PROGRAM)
    gd = LK.setupProlog(_QL)
    ld = LK.PL_local_data{_QL}(gd)
    @test LK.compileFileList(gd, ld, nothing, [g])
    @test_broken (
        try
            _ql_query_lines(gd, ld, ["t_q01"]) == ["t_q01 exception"]
        catch
            false
        end
    )
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_QL_PINNED) == length(_QL_NAMES) + 1
    if swipl === nothing
        @info "LB3 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        mktempdir() do dir
            f = joinpath(dir, "prog.pl")
            write(f, _QL_PROGRAM)
            @test _ql_swipl_lines(f, _QL_NAMES) == _QL_PINNED
            g = joinpath(dir, "autoload.pl")
            write(g, _QL_AUTOLOAD_PROGRAM)
            @test _ql_swipl_lines(g, ["t_q01"]; pre=_QL_AUTOLOAD_PRE) == _QL_AUTOLOAD_PINNED
            # the input stream a consult restores (S4): swipl's current_input is the stream it was before the load
            h = joinpath(dir, "in.pl")
            write(h, "r(a).\n")
            src = "open('$h', read, S), set_input(S), consult('$h'), current_input(S2), (S2 == S -> writeln(restored) ; writeln(other)), halt"
            @test split(
                read(
                    pipeline(`swipl -q -g $src`; stdin=devnull, stderr=devnull), String
                ),
                '\n'; keepempty=false
            ) == ["restored"]
        end
    end
end

@testset "'\$:-' runs a directive without a clause; a false part runs nothing (C: directiveClause with \"\$:-\")" begin
    # UNVERIFIED on the kernel: gate decides
    text = """
    '\$:-'(assertz(d(dollar))).
    :- assertz(d(colon)).
    '\$:-'(user:assertz(d(dollar_user))).
    :- if(fail).
    '\$:-'(assertz(d(hidden_dollar))).
    :- endif.
    r(x).
    t_q01(L) :- findall(X, r(X), L).
    t_q02(L) :- findall(X, d(X), L).
    """
    rc, gd, ld, f = _ql_compile(text)
    @test rc
    kl = _ql_query_lines(gd, ld, ["t_q01", "t_q02"])
    @test _ql_list_atoms(kl[1]) == ["x"]
    @test _ql_list_atoms(kl[2]) == ["dollar", "colon", "dollar_user"]
    @test isempty(_ql_messages(ld))
end

@testset "the nesting bound and the unmatched endif (MAX_IFDEF_NEST = 3; fatalError)" begin
    # UNVERIFIED on the kernel: gate decides
    @test LK.MAX_IFDEF_NEST == 3
    two = ":- if(true).\n:- if(true).\nr(two).\n:- endif.\n:- endif.\nt_q01(L) :- findall(X, r(X), L).\n"
    rc, gd, ld, f = _ql_compile(two)
    @test rc && _ql_list_atoms(_ql_query_lines(gd, ld, ["t_q01"])[1]) == ["two"]
    three = ":- if(true).\n:- if(true).\n:- if(true).\nr(three).\n:- endif.\n:- endif.\n:- endif.\n"
    gd, ld, f = _ql_db(three)
    e = try
        LK.compileFile(gd, ld, nothing, f)
        nothing
    catch ex
        ex
    end
    @test e isa ErrorException && occursin("deeply nested", e.msg)
    # the bound is checked in a part not compiled too (upstream tests the depth before `ctrue`)
    gd, ld, f = _ql_db(
        ":- if(fail).\n:- if(true).\n:- if(true).\n:- endif.\n:- endif.\n:- endif.\n"
    )
    e = try
        LK.compileFile(gd, ld, nothing, f)
        nothing
    catch ex
        ex
    end
    @test e isa ErrorException && occursin("deeply nested", e.msg)
    gd, ld, f = _ql_db("r(a).\n:- endif.\n")
    e = try
        LK.compileFile(gd, ld, nothing, f)
        nothing
    catch ex
        ex
    end
    @test e isa ErrorException && occursin("Too many :- endif", e.msg)
    # the state: depth 0, the file's own level compiled
    c = LK.condc()
    @test c.depth == 0 && LK.cond_true(c) && LK.IF_TRUE in c.ctrue &&
        length(c.ctrue) == LK.MAX_IFDEF_NEST
end

@testset "elif is no conditional; a failing directive is collected; a syntax error is skipped; a missing file" begin
    # UNVERIFIED on the kernel: gate decides (each row is the C loop's behaviour)
    rc, gd, ld, f = _ql_compile(
        ":- elif(true).\nr(after_elif).\n:- fail.\nr(after_fail).\nt_q01(L) :- findall(X, r(X), L).\n"
    )
    @test rc
    @test _ql_list_atoms(_ql_query_lines(gd, ld, ["t_q01"])[1]) ==
        ["after_elif", "after_fail"]
    msgs = _ql_messages(ld)
    @test count(m -> occursin(r":[0-9]+: directive failed\n$", m), msgs) == 2   # elif/1 is called in user (unknown procedure), then fail/0
    @test all(m -> occursin(f, m), filter(m -> occursin("directive failed", m), msgs))

    gd, ld, f = _ql_db("r(a).\nfoo(.\nr(b).\nt_q01(L) :- findall(X, r(X), L).\n")
    lk_install_message_collector!(gd, ld)       # the report is print_message/2's since LB4 b2
    lk_take_messages!(ld)
    at = LK.boot_stacks(ld)
    rc = LK.compileFile(gd, ld, nothing, f)
    left = LK.boot_stacks(ld)
    @test rc
    # H11 (loader_boot.md): compileFile leaves what upstream's leaves (pl-qlf.c:4726-4741, the end_of_file `break`);
    # the syntax error is read past, so no `continue` frame is added: one frame, as for a file without one
    @test left != at && left == LK.compileFile_leaves(at, 1)
    @test left[4] == at[4] + 1
    @test _ql_list_atoms(_ql_query_lines(gd, ld, ["t_q01"])[1]) == ["a", "b"]
    # read_clause/3 reports the error itself (syntax_errors dec10, src/pl-read.jl:4099, reportReadError) and reads on, so
    # the loop's own "Syntax error" branch is not reached; the report is a message TERM, not text
    # (printMessage -> print_message/2, read through the collector), UNVERIFIED on the kernel: gate decides
    @test any(((k, m),) -> k === :error && kind(m) !== SYM, lk_take_messages!(ld))
    @test !any(m -> occursin("Syntax error", m), _ql_messages(ld))

    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    nofile = joinpath(mktempdir(), "no_such.pl")
    @test !LK.compileFile(gd, ld, nothing, nofile)
    @test any(m -> startswith(m, "Failed to open $nofile"), _ql_messages(ld))
end

@testset "a term that cannot be asserted is reported as Failed to compile and the loop goes on" begin
    # UNVERIFIED on the kernel: gate decides (addClauseWic's failure; the clause head is a system predicate)
    rc, gd, ld, f = _ql_compile(
        "atom_length(a, b).\nr(after).\nt_q01(L) :- findall(X, r(X), L).\n"
    )
    @test rc
    @test any(m -> startswith(m, "Failed to compile: "), _ql_messages(ld))
    # the term after the text is the clause itself (`_qlf_pl_write!`: pl_write(term), pl-qlf.c:3220-3238; LB4 b2)
    i = findfirst(
        ((k, m),) ->
            k === :error && kind(m) === SYM &&
            startswith(String(sym_text(m)), "Failed to compile: "),
        ld.messages
    )
    @test i !== nothing && i < length(ld.messages)
    if i !== nothing && i < length(ld.messages)
        k2, m2 = ld.messages[i + 1]
        @test k2 === :error && kind(m2) !== SYM && sym_text(child(m2, 1)) == "atom_length"
    end
    @test _ql_list_atoms(_ql_query_lines(gd, ld, ["t_q01"])[1]) == ["after"]
end

@testset "compileFileList and the boot entry (up to -c; the state after)" begin
    # UNVERIFIED on the kernel: gate decides
    dir = mktempdir()
    f1 = joinpath(dir, "b1.pl")
    f2 = joinpath(dir, "b2.pl")
    f3 = joinpath(dir, "b3.pl")
    write(
        f1,
        "r(one).\n'\$load_additional_boot_files' :- assertz(d(additional)).\nt_q01(L) :- findall(X, (r(X) ; r2(X)), L).\nt_q02(L) :- findall(X, d(X), L).\n"
    )
    write(
        f2, "r2(two).\n:- current_prolog_flag(autoload, false), assertz(d(autoload_off)).\n"
    )
    write(f3, "r(three).\n")
    f4 = joinpath(dir, "b4.pl")
    write(f4, "'\$load_additional_boot_files'.\n")
    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    @test !gd.bootsession && ld.prolog_flag_access_level == LK.ACCESS_LEVEL_USER
    ld.debugstatus_styleCheck = 0                                # the boot entry sets the style checks
    @test LK.boot_from_source!(gd, ld, [f1, f2, "-c", f3])
    kl = _ql_query_lines(gd, ld, ["t_q01", "t_q02"])
    @test _ql_list_atoms(kl[1]) == ["one", "two"]                # f3 follows -c: not compiled
    # swipl answers ["autoload_off", "additional"]: compileFileList sets `autoload` false before compiling the files (pl-qlf.c:4798, swipl-devel
    # cbf4e189, PL_set_prolog_flag("autoload", PL_BOOL, false)) and true again after them (:4808), then runs
    # '$load_additional_boot_files'/0 once. The kernel's port does the same (src/pl-qlf.jl compileFileList). The conjunction directive of
    # b2.pl (`current_prolog_flag(autoload, false), assertz(d(autoload_off))`) needs ','/2 as a procedure (pl-pro.c:476-540 resolves
    # the directive's functor and calls it): boot/init.pl defines it (the D stack's stand-in until LB4 b2). Before it the directive failed ("directive failed"),
    # d(autoload_off) was never asserted, and this row pinned ["additional"] (a KNOWN DIFFERENCE until LB4): no regression, a closed difference.
    @test _ql_list_atoms(kl[2]) == ["autoload_off", "additional"]
    @test String(sym_text(LK.PL_current_prolog_flag(gd, mk_sym(_QL, :autoload), :atom))) ==
        "true"
    sf = LK.lookupSourceFile_unlocked(gd, mk_sym(_QL, Symbol(abspath(f1))), false)
    @test sf !== nothing && sf.system                            # created while GD->bootsession was on
    @test LK.lookupSourceFile_unlocked(gd, mk_sym(_QL, Symbol(abspath(f3))), false) ===
        nothing
    @test !gd.bootsession
    @test ld.prolog_flag_access_level == LK.ACCESS_LEVEL_USER
    @test ld.debugstatus_styleCheck ==
        (
        LK.SINGLETON_CHECK | LK.SEMSINGLETON_CHECK | LK.DISCONTIGUOUS_STYLE |
        LK.NOEFFECT_CHECK
    )
    @test ld.qlf_write_state === nothing

    # a file that does not compile ends the list: false, the boot entry returns false, the flag is off again
    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    @test !LK.boot_from_source!(gd, ld, [joinpath(dir, "no_such.pl"), f4])    # f4 would make the last step succeed
    @test !gd.bootsession
    # user:'$load_additional_boot_files'/0 is called with no user clause for it: it resolves to system's, init.pl:4782
    # (cbf4e189), which succeeds, as a started swipl 10.1.19 answers `user:'$load_additional_boot_files'` true (live,
    # 2026-11-03). The database is a copy of the booted template, whose user procedure has its own definition (R-A).
    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    @test LK.boot_from_source!(gd, ld, [f2])
    @test !gd.bootsession

    # compileFileList alone restores the access level and `autoload`, and leaves the boot flag as it was
    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    gd.bootsession = true                                        # AUTOLOAD1 A4: as above, the boot session only
    @test LK.compileFileList(gd, ld, nothing, [f4])
    @test gd.bootsession                                         # left as it was
    gd.bootsession = false
    @test ld.prolog_flag_access_level == LK.ACCESS_LEVEL_USER && !gd.bootsession
    @test String(sym_text(LK.PL_current_prolog_flag(gd, mk_sym(_QL, :autoload), :atom))) ==
        "true"
    sf = LK.lookupSourceFile_unlocked(gd, mk_sym(_QL, Symbol(abspath(f4))), false)
    @test sf !== nothing && sf.system                            # created while GD->bootsession was on (AUTOLOAD1 A4: the row runs in the boot session)
end

# one goal on the `system` predicate `name/length(args)`: :ok, :fail, :exception, or :notported (the QLF predicates refused by name)
function _ql_call(gd, ld, name::String, args::Vector)::Symbol
    proc = LK.isCurrentProcedure(sym_key(_qls(name)), length(args), LK.MODULE_system(gd))
    proc === nothing && return :undefined
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, max(length(args), 1))
    for (i, v) in enumerate(args)
        LK.putSlotValue!(ld, a + i, v, LK.PutVarMap())
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    r = try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            :ok
        elseif rc == LK.PL_S_EXCEPTION
            :exception
        else
            :fail
        end
    catch ex
        ex isa LK.NotPortedError ? :notported : rethrow()
    end
    r === :notported || LK.PL_close_query(ld, qid)
    r === :notported || LK.PL_close_foreign_frame(ld, fid)
    return r
end

@testset "the eight write-side predicates take the no-state branch; the 14 others are refused by name" begin
    # UNVERIFIED on the kernel: gate decides
    tbl = LK.PL_predicates_from_wic
    @test length(tbl) == 22
    names = [(e.predicate_name, e.arity) for e in tbl]
    @test length(unique(names)) == 22
    shells = [
        ("\$qlf_start_module", 1), ("\$qlf_start_sub_module", 1), ("\$qlf_start_file", 1),
        ("\$qlf_end_part", 0), ("\$add_directive_wic", 1), ("\$qlf_assert_clause", 2),
        ("\$import_wic", 3), ("\$qlf_include", 5)
    ]
    refused = [
        ("\$qlf_versions", 6), ("\$qlf_is_compatible", 1), ("\$qlf_sources", 2),
        ("\$file_hash", 2),
        ("\$qlf_module", 2), ("\$qlf_load", 2), ("\$qlf_current_source", 1),
        ("\$qlf_dependency", 1),
        ("\$qlf_open", 1), ("\$qlf_close", 0), ("\$open_wic", 2), ("\$close_wic", 0),
        ("\$map_id", 2), ("\$unmap_id", 1)
    ]
    @test Set(names) == Set(vcat(shells, refused))
    # registered after read_clause/3's table and before the file table's, in both dispatch tables
    i = findfirst(==(LK.PL_predicates_from_wic), LK._PRED_TABLES)
    @test i !== nothing && LK._PRED_TABLES[i - 1] === LK.PL_predicates_from_read &&
        LK._PRED_TABLES[i + 1] === LK.PL_predicates_from_file
    flags = Dict(e.predicate_name => e.flags for e in tbl)
    @test (flags["\$add_directive_wic"] & LK.PL_FA_TRANSPARENT) != 0 &&
        (flags["\$qlf_load"] & LK.PL_FA_TRANSPARENT) != 0
    @test all(e -> (e.flags & LK.PL_FA_VARARGS) != 0, tbl)
    gd = LK.PL_global_data{_QL}()
    ld = LK.PL_local_data{_QL}(gd)
    for (n, ar) in shells
        n == "\$qlf_include" && continue
        args = _QL[mk_var(_QL, LK.fresh_var_keys!(1)) for _ in 1:ar]
        @test _ql_call(gd, ld, n, args) === :ok          # no argument is checked
    end
    foo, one = _qls("foo"), lk_gnd(_QL, 1)
    # '$qlf_include'/5 checks A1..A5 in order, then fails for want of a state
    @test _ql_call(gd, ld, "\$qlf_include", _QL[foo, foo, one, foo, lk_gnd(_QL, 1.0)]) ===
        :fail
    @test _ql_call(gd, ld, "\$qlf_include", _QL[one, foo, one, foo, lk_gnd(_QL, 1.0)]) ===
        :exception
    @test _ql_call(gd, ld, "\$qlf_include", _QL[foo, foo, foo, foo, lk_gnd(_QL, 1.0)]) ===
        :exception
    @test _ql_call(gd, ld, "\$qlf_include", _QL[foo, foo, one, foo, foo]) === :fail     # PL_get_float is not the _ex form
    for (n, ar) in refused
        gd2 = LK.PL_global_data{_QL}()
        ld2 = LK.PL_local_data{_QL}(gd2)
        args = _QL[mk_var(_QL, LK.fresh_var_keys!(1)) for _ in 1:ar]
        @test _ql_call(gd2, ld2, n, args) === :notported
    end
end
