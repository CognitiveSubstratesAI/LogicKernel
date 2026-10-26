# ORIGINAL: a LIVE differential of current_prolog_flag/2 and '$current_prolog_flag'/5 (pl-prologflag.c; R2 F1a, audit D-0149, design evidence/r2/design/flags_rest.md D1-D6, §5, §6)
# test/core_lang/test_prolog_flag_swipl.jl — the read side of the Prolog flags against swipl at the pin, through a PROGRAM (the pattern
# of test/db/test_retract_swipl.jl): test_prolog_flag_swipl.pl holds the rows, each a predicate `t_<id>(R)`; the kernel consults it and
# enumerates every solution of every row, swipl does the same through a driver, and the answers are compared as lines.
# test_prolog_flag_swipl.out is swipl's output for those rows, kept beside the program (the test fails when swipl's answers move, and
# says how to write it again). EVERY expected value is swipl's own answer: the rows are questions. What is hand-written, each with its
# reason:
#   * the pinned list of the flags swipl has and the kernel has not, each naming its unported family (the key set itself is read
#     from both systems), and the two flags that differ BY DESIGN — `threads` and `gc_thread` (D1: the kernel is the no-threads
#     build; swipl's answers are asked live next to them);
#   * the white-box rows of the table (a flag created during an enumeration, a deleted flag, a mask bit), which no swipl predicate
#     reaches, and the C interface (`PL_record`/`PL_recorded`, `PL_get_prolog_flag`, `PL_current_prolog_flag`);
#   * the scope argument: upstream register Q8; swipl gives no answer; re-check at the sync that brings upstream's change.
#     The kernel's answer — the global table with the scope `global` — is pinned without swipl's.
# After EVERY row the pool of current_prolog_flag/2's states is empty again (`live_states`, D-0136 Q8): a missing FRG_CUTTED (a cut, an
# exception, a query closed with a state live) shows as a count, named by its row.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL, Symbol(x))

const _PL_FILE = joinpath(@__DIR__, "test_prolog_flag_swipl.pl")
const _OUT_FILE = joinpath(@__DIR__, "test_prolog_flag_swipl.out")

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

# every solution of `proc` called with `args`, the arguments read back; `each(i)` runs after the i-th answer is read (a hook for the
# white-box rows); false as the second result when the query ended on an exception
function run_query(
    gd, ld, proc, args::Vector{_TL}; limit::Int=500, each=(i -> nothing)
)::Tuple{Vector{Vector{_TL}}, Bool}
    n = length(args)
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, n)
    pvm = LK.PutVarMap()
    for (i, t) in enumerate(args)
        LK.putSlotValue!(ld, a + i, t, pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    sols = Vector{_TL}[]
    ok = true
    while length(sols) < limit
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(sols, lk_answers(ld, (a:(a + n - 1))...))
            each(length(sols))
            rc == LK.PL_S_LAST && break
        elseif rc == LK.PL_S_EXCEPTION
            ok = false
            break
        else
            break
        end
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return sols, ok
end

_vars(n) = _TL[mk_var(_TL, LK.fresh_var_keys!(1)) for _ in 1:n]

"The kernel's lines for the rows `names` (and the live states after each), after `post(gd, ld)` ran: as swipl's driver prints them."
function kernel_run(
    path::String, names::Vector{String}; post=(gd, ld) -> nothing, limit::Int=400
)::Tuple{Vector{String}, Vector{Int}}
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_TL)]
    post(gd, ld)
    lives = Int[]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols, ok = run_query(gd, ld, proc, _vars(1); limit=limit)
        parts = String[
            try
                enc(mk_expr(_TL, _TL[_tls(name), s[1]]))
            catch e
                "export-error " * first(sprint(showerror, e), 80)
            end for s in sols
        ]
        ok || push!(parts, "exception")
        push!(out, join([name; parts], " "))
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
    catch(findnsols(400, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns, Post) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    call(Post),
    forall(member(N, Ns), fz_pred(N)).
"""

"swipl's lines for the rows `names` of `path`, after the goal `post` ran (the file is consulted first)."
function swipl_lines(
    path::String, names::Vector{String}; post::String="true"
)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "], ($post)), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The names of the rows of a program: its `t_<id>(` clause heads, in order of appearance."
function row_names(path::String)::Vector{String}
    return unique(
        String[m.captures[1] for m in eachmatch(r"^(t_[a-z0-9_]+)\("m, read(path, String))]
    )
end

# the line a row prints with the one answer `ans` (an `R`): `t_x t_x(R)`
rowline(name::String, ans::_TL) = name * " " * enc(mk_expr(_TL, _TL[_tls(name), ans]))
_r(parts...) = mk_expr(_TL, vcat(_tls("r"), _TL[p isa String ? _tls(p) : p for p in parts]))

const _SWIPL = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
_SWIPL === nothing &&
    @info "FLAG DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."

# the keys of the flags `swipl -q` has, as `current_prolog_flag/2` enumerates them
function swipl_keys()::Vector{String}
    f = joinpath(mktempdir(), "keys.pl")
    write(
        f, ":- initialization((forall(current_prolog_flag(K, _), (write(K), nl)), halt)).\n"
    )
    return sort(
        String.(
            split(
                read(pipeline(`swipl -q $f`; stderr=devnull), String), '\n'; keepempty=false
            )
        )
    )
end

# the keys the kernel enumerates (query_answers: every answer of current_prolog_flag(K, V))
function kernel_keys(ld)::Vector{String}
    goal = mk_expr(
        _TL,
        _TL[_tls("current_prolog_flag"), lk_var(_TL, UInt64(1)), lk_var(_TL, UInt64(2))]
    )
    return sort(String[String(sym_text(child(a, 2))) for a in LK.query_answers(ld, goal)])
end

# THE PINNED DIFFERENCE (design §6 F1): every flag swipl 10.1.19 has that the kernel has not, with the family it belongs to — and
# the entry that goes when the family is ported (a re-check trigger, not a list to extend). A build-feature flag is absent
# because the kernel answers as upstream's build WITHOUT the feature (audit D-0151 item 6; the `#ifdef`s, pl-prologflag.c
# :2589-2625, are cited in src/os/pl-prologflag.jl). `home` is defined (the kernel's own value, a machine flag of the program).
const _BOOT_PL = "boot/*.pl creates it (create_prolog_flag/3: R2 F1b, loaded by R2 LB4/LB5)"
const _TOOLCHAIN = "the C toolchain and shared objects (pl-prologflag.c O_DYNAMIC_EXTENSIONS): the kernel loads no foreign library"
const _BUILD = "the build's identity (a CMake build: pl-prologflag.c #ifdef BUILD_TYPE / EXEC_FORMAT / HAVE_DLADDR, pl-version.c #ifdef GIT_VERSION / CMAKE_BUILD_TYPE): the kernel is not one"
const _OTHER_FILE = "set outside pl-prologflag.c (pl-init.c, pl-alloc.c): waits for that file"
const _THREADS = "threads and engines (pl-prologflag.c O_PLMT; O_ENGINES is the cmake option ENGINES): the kernel is the no-threads, no-engines build (design D1)"
const PINNED_ONLY_SWIPL = Dict{String, String}(
    "abi_version" => "pl-prologflag.c setABIVersionPrologFlag (every build defines it): its value is a dict (PL_put_dict), which the kernel has not",
    "answer_write_options" => _BOOT_PL,
    "associated_file" => _BOOT_PL,
    "build_type" => _BUILD,
    "c_cc" => _TOOLCHAIN,
    "c_cflags" => _TOOLCHAIN,
    "c_cxx" => _TOOLCHAIN,
    "c_ldflags" => _TOOLCHAIN,
    "c_libplso" => _TOOLCHAIN,
    "c_libs" => _TOOLCHAIN,
    "cmake_build_type" => _BUILD,
    "compile_meta_arguments" => _BOOT_PL,
    "debug_term_position" => _BOOT_PL,
    "debugger_goal_links" => _BOOT_PL,
    "debugger_write_options" => _BOOT_PL,
    "emacs_inferior_process" => _OTHER_FILE,
    "emulated_dialect" => _BOOT_PL,
    "engines" => _THREADS,
    "executable_format" => _BUILD,
    "file_search_cache_time" => _BOOT_PL,
    "libswipl" => _BUILD,
    "malloc" => _OTHER_FILE * " (the allocator found: the kernel uses Julia's)",
    "message_context" => _BOOT_PL,
    "message_language" => _BOOT_PL,
    "open_shared_object" => _TOOLCHAIN,
    "pipe" => "pipe streams (pl-prologflag.c HAVE_POPEN): open(pipe(Cmd)) is not ported until R2 S1",
    "print_write_options" => _BOOT_PL,
    "prompt_alternatives_on" => _BOOT_PL,
    "qcompile" => _BOOT_PL,
    "query_debug_settings" => _BOOT_PL,
    "resource_database" => _OTHER_FILE,
    "shared_object_extension" => _TOOLCHAIN,
    "shared_object_search_path" => _TOOLCHAIN,
    "shared_table_space" => _THREADS,
    "system_thread_id" => _THREADS,
    "toplevel_extra_white_line" => _BOOT_PL,
    "toplevel_goal" => _BOOT_PL,
    "toplevel_list_wfs_residual_program" => _BOOT_PL,
    "toplevel_mode" => _BOOT_PL,
    "toplevel_print_factorized" => _BOOT_PL,
    "toplevel_residue_vars" => _BOOT_PL,
    "toplevel_thread" => _BOOT_PL,
    "version_git" => _BUILD,
    "warn_autoload" => _BOOT_PL,
    "xref" => _BOOT_PL
)

@testset "current_prolog_flag/2, '\$current_prolog_flag'/5 == live swipl, through a program; no state leaked" begin
    if _SWIPL === nothing
        @test true
    else
        names = row_names(_PL_FILE)
        sw = swipl_lines(_PL_FILE, names)
        kl, lives = kernel_run(_PL_FILE, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test length(kl) == length(sw) && kl[1] == "ok"
        for i in eachindex(names)
            @test (names[i], kl[i + 1]) == (names[i], sw[i + 1])
        end
        # not a vacuous agreement: swipl's own lines hold the kinds of answer the rows ask for (one extractor, on swipl's lines)
        @test count(l -> startswith(l, "t_defaults "), sw) == 1
        @test length(first(filter(l -> startswith(l, "t_defaults "), sw))) > 5000               # one answer per portable flag
        @test count(l -> occursin("114,114,111,114", l), sw) >= 4       # an `…rror` atom: type_error(atom, …), domain_error(scope, …)
        @test any(l -> startswith(l, "t_count ") && endswith(l, "(i110)"), sw)
        @test any(l -> startswith(l, "t_e04 ") && endswith(l, "(a[110,111])"), sw)               # a flag that is not there: `no`
        @test length(lives) == length(names)
        for (i, n) in enumerate(lives)
            @test (names[i], n) == (names[i], 0)
        end
        # the .out beside the program is swipl's output for it: write it again with LOGICKERNEL_WRITE_OUT=1 after a sync
        if get(ENV, "LOGICKERNEL_WRITE_OUT", "") == "1"
            write(_OUT_FILE, join(sw, '\n') * "\n")
        end
        @test sw == String.(split(chomp(read(_OUT_FILE, String)), '\n'; keepempty=false))
    end
end

@testset "the key set: swipl's less the pinned families == the kernel's; no flag the kernel alone has" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    ours = kernel_keys(ld)
    @test !isempty(ours) && issorted(ours) && allunique(ours)
    @test all(v -> !isempty(v), values(PINNED_ONLY_SWIPL))
    if _SWIPL === nothing
        @test true
    else
        theirs = swipl_keys()
        @test !isempty(theirs) && allunique(theirs)
        # the pinned list is exactly the difference, both ways (a flag ported, or a flag swipl added, fails here)
        @test sort(collect(setdiff(Set(theirs), Set(ours)))) ==
            sort(collect(keys(PINNED_ONLY_SWIPL)))
        @test isempty(setdiff(Set(ours), Set(theirs)))
        # `threads` and `gc_thread` are in both sets (they differ in value: the next testset)
        @test "threads" in ours && "gc_thread" in ours
        # the flags that exist and answer nothing: swipl's table holds them too, so neither enumerates them
        for k in (
            "break_level", "max_rational_size", "max_integer_size",
            "max_table_subgoal_size",
            "max_table_answer_size", "max_answers_for_subgoal"
        )
            @test !(k in ours) && !(k in theirs)
            @test LK.current_prolog_flag(gd, k) !== nothing        # …but they are defined
        end
    end
end

# known differences BY DESIGN (D1, FQ4): the kernel is the no-threads build, where `threads` and `gc_thread` are false and read-only
# (pl-prologflag.c:2621-2622). swipl's answers are asked next to them, so the pin fails when either side moves.
@testset "known difference: threads and gc_thread (design D1)" begin
    prog = joinpath(mktempdir(), "th.pl")
    write(
        prog,
        """
t_th1(r(V, A, T)) :- '\$current_prolog_flag'(threads, V, _, A, T).
t_th2(r(V, A, T)) :- '\$current_prolog_flag'(gc_thread, V, _, A, T).
t_th3(R) :- ( current_prolog_flag(threads, true) -> R = yes ; R = no ).
t_th4(R) :- ( current_prolog_flag(threads, false) -> R = yes ; R = no ).
"""
    )
    names = ["t_th1", "t_th2", "t_th3", "t_th4"]
    kl, lives = kernel_run(prog, names)
    ours_expected = [
        "ok",
        rowline("t_th1", _r("false", "read", "boolean")),
        rowline("t_th2", _r("false", "read", "boolean")),
        rowline("t_th3", _tls("no")),
        rowline("t_th4", _tls("yes"))
    ]
    @test kl == ours_expected
    @test all(==(0), lives)
    if _SWIPL !== nothing
        sw = swipl_lines(prog, names)
        @test sw == [
            "ok",
            rowline("t_th1", _r("true", "write", "boolean")),
            rowline("t_th2", _r("true", "write", "boolean")),
            rowline("t_th3", _tls("yes")),
            rowline("t_th4", _tls("no"))
        ]
    end
end

# flags the program creates in swipl (create_prolog_flag/3) and the kernel defines white-box (setPrologFlag): the types, accesses and
# values no default flag has — a `oneof` type, a Boolean without a mask bit, a float, a term, a read-only integer
const _MINI = """
mem(X, [X|_]).
mem(X, [_|T]) :- mem(X, T).
cat(G, R) :- catch(( call(G) -> R = yes(G) ; R = no ), E, R = ex(E)).
t_x1(r(V, A, T)) :- '\$current_prolog_flag'(zz_one, V, _, A, T).
t_x2(r(V, A, T)) :- '\$current_prolog_flag'(zz_b, V, _, A, T).
t_x3(R) :- cat(current_prolog_flag(zz_b, foo), R).
t_x4(R) :- cat(current_prolog_flag(zz_b, true), R).
t_x5(r(V, A, T)) :- '\$current_prolog_flag'(zz_i, V, _, A, T).
t_x6(R) :- cat(current_prolog_flag(zz_i, x), R).
t_x7(R) :- cat(current_prolog_flag(zz_i, 5), R).
t_x8(r(V, A, T)) :- '\$current_prolog_flag'(zz_f, V0, _, A, T), ( V0 =:= 2.5 -> V = eq ; V = ne ).
t_x9(r(V, A, T)) :- '\$current_prolog_flag'(zz_t, V, _, A, T).
t_x10(R) :- cat(current_prolog_flag(zz_t, f(_, b)), R).
t_x11(R) :- cat(current_prolog_flag(zz_t, g(_)), R).
t_x12(r(V, A, T)) :- '\$current_prolog_flag'(zz_ro, V, _, A, T).
t_x13(L) :- findall(K, ( current_prolog_flag(K, _), mem(K, [zz_one, zz_b, zz_i, zz_f, zz_t, zz_ro]) ), L0), msort(L0, L).
t_x14(R) :- cat(current_prolog_flag(zz_one, b), R).
t_x15(R) :- cat(current_prolog_flag(zz_one, z), R).
"""
const _MINI_SWIPL = """
:- create_prolog_flag(zz_one, a, [type(oneof([a, b, c]))]).
:- create_prolog_flag(zz_b, true, [type(boolean)]).
:- create_prolog_flag(zz_i, 5, [type(integer)]).
:- create_prolog_flag(zz_f, 2.5, [type(float)]).
:- create_prolog_flag(zz_t, f(a, b), [type(term)]).
:- create_prolog_flag(zz_ro, 7, [type(integer), access(read_only)]).
"""

@testset "flags of every type the table holds == live swipl (white-box definitions)" begin
    if _SWIPL === nothing
        @test true
    else
        d = mktempdir()
        pk = joinpath(d, "kernel.pl")
        ps = joinpath(d, "swipl.pl")
        write(pk, _MINI)
        write(ps, _MINI_SWIPL * _MINI)
        names = row_names(pk)
        sw = swipl_lines(ps, names)
        function define(gd, ld)
            T = _TL
            LK.setPrologFlag(gd, "zz_one", LK.FT_ATOM, "a")
            LK.current_prolog_flag(gd, "zz_one").oneof = LK.oneof_t{T}(
                T[_tls("a"), _tls("b"), _tls("c")], 1
            )
            LK.setPrologFlag(gd, "zz_b", LK.FT_BOOL, true, 0)
            LK.setPrologFlag(gd, "zz_i", LK.FT_INTEGER, 5)
            LK.setPrologFlag(gd, "zz_f", LK.FT_FLOAT, 2.5)
            LK.setPrologFlag(gd, "zz_ro", LK.FT_INTEGER | LK.FF_READONLY, 7)
            fid = LK.PL_open_foreign_frame(ld)
            t = LK.PL_new_term_ref(ld)
            LK.putSlotValue!(ld, t + 1, mk_expr(T, T[_tls("f"), _tls("a"), _tls("b")]))
            LK.setPrologFlag(gd, ld, "zz_t", LK.FT_TERM, t)
            LK.PL_close_foreign_frame(ld, fid)
        end
        kl, lives = kernel_run(pk, names; post=define)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        for i in eachindex(names)
            @test (names[i], kl[i + 1]) == (names[i], sw[i + 1])
        end
        @test all(==(0), lives)
        @test any(l -> startswith(l, "t_x1 ") && occursin("111,110,101,111,102", l), sw)     # `oneof`: the type is the term oneof([a,b,c])
    end
end

# `iso`, `prefer_rationals`, `quasi_quotations` and `protect_static_code` are bits of the mask (D3): the arithmetic, the reader and the
# compiler read them, so the same rows run with the bit moved must answer as swipl does after set_prolog_flag/2 (R2 F1b ports it;
# until then the bit is moved in the local data — the mask a flag's value is read from too, so current_prolog_flag/2 follows)
@testset "the mask bits move the arithmetic, the reader, the compiler and the flag's value, as swipl's set_prolog_flag/2" begin
    if _SWIPL === nothing
        @test true
    else
        arith = ["t_h3a", "t_h3b", "t_h3c", "t_h3d", "t_h3e", "t_h3f", "t_h3g", "t_h3h"]
        flagrows = [
            "t_e05", "t_e06", "t_e07", "t_e08", "t_enum_true", "t_enum_false", "t_enum_one"
        ]
        # (flag, bit, the value it is set to, the rows that must change with it)
        cases = [
            (
                "iso",
                LK.PLFLAG_ISO,
                true,
                vcat(arith, ["t_h4a", "t_h4b", "t_h4c", "t_psc"], flagrows)
            ),
            ("prefer_rationals", LK.PLFLAG_RATIONAL, true, vcat(arith, flagrows)),
            (
                "quasi_quotations",
                LK.PLFLAG_QUASI_QUOTES,
                false,
                vcat(["v_qq1", "v_qq2"], flagrows)
            ),
            (
                "protect_static_code",
                LK.PLFLAG_PROTECT_STATIC_CODE,
                true,
                vcat(["t_psc"], flagrows)
            )
        ]
        for (flag, bit, value, names) in cases
            move =
                (gd, ld) -> (
                    ld.prolog_flag_mask =
                        if value
                            (ld.prolog_flag_mask | LK.prologFlagMask(bit))
                        else
                            (ld.prolog_flag_mask & ~LK.prologFlagMask(bit))
                        end
                )
            kl, lives = kernel_run(_PL_FILE, names; post=move)
            sw = swipl_lines(_PL_FILE, names; post="set_prolog_flag($flag, $value)")
            @test length(sw) == length(names) + 1 && length(kl) == length(sw)
            for i in eachindex(names)
                @test (flag, names[i], kl[i + 1]) == (flag, names[i], sw[i + 1])
            end
            @test all(==(0), lives)
            # the bit moved the answers: the rows differ from the default run's (not a vacuous agreement)
            keep = [i for (i, n) in enumerate(names) if !startswith(n, "v_")]
            base, _ = kernel_run(_PL_FILE, names[keep])
            @test base[2:end] != kl[2:end][keep]
        end
    end
end

# the compiler reads `generate_debug_info` when it defines a predicate from a file: a clear bit hides the children
# (HIDE_CHILDS). No Prolog row reaches it before predicate_property/2 (R2), so the flag is checked on the definition.
@testset "generate_debug_info: the bit decides HIDE_CHILDS of a predicate a file defines" begin
    f = joinpath(mktempdir(), "dbg.pl")
    write(f, "h6(a).\n")
    for (on, want) in ((true, 0), (false, 1))
        gd = LK.PL_global_data{_TL}()
        ld = LK.PL_local_data{_TL}(gd)
        on || (ld.prolog_flag_mask &= ~LK.prologFlagMask(LK.PLFLAG_DEBUGINFO))
        st, _, _ = LK.load_file!(gd, ld, f)
        @test st === :ok
        proc = LK.isCurrentProcedure(sym_key(_tls("h6")), 1, LK.MODULE_user(gd))
        @test proc !== nothing
        @test (proc.definition.flags & LK.HIDE_CHILDS != 0) == (want == 1)
    end
end

# the float state of the local data (`arith_f_flags`) is what the four float flags and `float_rounding` read
@testset "float_overflow, float_zero_div, float_undefined, float_underflow: the local data's state is the value, as swipl's" begin
    if _SWIPL === nothing
        @test true
    else
        set =
            (gd, ld) -> (
                ld.arith_f_flags =
                    (
                        ld.arith_f_flags | LK.FLT_OVERFLOW | LK.FLT_ZERO_DIV |
                        LK.FLT_UNDEFINED
                    ) &
                    ~LK.FLT_UNDERFLOW
            )
        kl, _ = kernel_run(_PL_FILE, ["t_arith"]; post=set)
        sw = swipl_lines(
            _PL_FILE, ["t_arith"];
            post="set_prolog_flag(float_overflow, infinity), set_prolog_flag(float_zero_div, infinity), set_prolog_flag(float_undefined, nan), set_prolog_flag(float_underflow, error)"
        )
        @test kl == sw
        base, _ = kernel_run(_PL_FILE, ["t_arith"])
        @test base != kl
    end
end

@testset "the mask (D3): 36 bits, the table's Booleans, a new local data copies the database's" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    bits = [
        LK.PLFLAG_CHARESCAPE, LK.PLFLAG_CHARESCAPE_UNICODE, LK.PLFLAG_GC,
        LK.PLFLAG_TRACE_GC,
        LK.PLFLAG_GCTHREAD, LK.PLFLAG_TTY_CONTROL, LK.PLFLAG_DEBUG_ON_ERROR,
        LK.PLFLAG_REPORT_ERROR, LK.PLFLAG_FILE_CASE, LK.PLFLAG_FILE_CASE_PRESERVING,
        LK.PLFLAG_ERROR_AMBIGUOUS_STREAM_PAIR, LK.ALLOW_VARNAME_FUNCTOR, LK.PLFLAG_ISO,
        LK.PLFLAG_OPTIMISE, LK.PLFLAG_FILEVARS, LK.PLFLAG_AUTOLOAD,
        LK.PLFLAG_CHARCONVERSION,
        LK.PLFLAG_LASTCALL, LK.PLFLAG_VMI_BUILTIN, LK.PLFLAG_PORTABLE_VMI,
        LK.PLFLAG_SIGNALS,
        LK.PLFLAG_DEBUGINFO, LK.PLFLAG_FILEERRORS, LK.PLFLAG_WARN_OVERRIDE_IMPLICIT_IMPORT,
        LK.PLFLAG_QUASI_QUOTES, LK.PLFLAG_DOT_IN_ATOM, LK.PLFLAG_PROTECT_STATIC_CODE,
        LK.PLFLAG_MITIGATE_SPECTRE, LK.PLFLAG_TABLE_INCREMENTAL, LK.PLFLAG_TABLE_SHARED,
        LK.PLFLAG_RATIONAL, LK.PLFLAG_DEBUG_ON_INTERRUPT, LK.PLFLAG_OPTIMISE_UNIFY,
        LK.PLFLAG_SHIFT_CHECK, LK.PLFLAG_AGC_CLOSE_STREAMS, LK.PLFLAG_EPILOG
    ]
    @test sort(bits) == collect(1:36)                            # pl-incl.h enum plflag: the bit number plus one
    @test LK.prologFlagMask(1) == UInt64(1) && LK.prologFlagMask(36) == UInt64(1) << 35

    # the mask holds the value of every Boolean flag that owns a bit (the five stand-ins still in the local data aside)
    standins = (
        LK.PLFLAG_LASTCALL, LK.PLFLAG_PORTABLE_VMI, LK.PLFLAG_OPTIMISE,
        LK.PLFLAG_OPTIMISE_UNIFY,
        LK.PLFLAG_CHARESCAPE_UNICODE
    )
    owned = Int[]
    for f in gd.prolog_flag.entries
        (f === nothing || (f.flags & LK.FT_MASK) != LK.FT_BOOL || f.index == 0) && continue
        push!(owned, Int(f.index))
        want = sym_key(f.a) == sym_key(_tls("true"))
        @test (LK.truePrologFlag(ld, f.index), f.index) == (want, f.index)
    end
    @test length(owned) == length(unique(owned))                 # no two flags share a bit
    # …and every bit has its flag, but the three that atom flags own (`file_name_case_handling`, `autoload`)
    @test sort(owned) == sort(
        setdiff(
            bits, [LK.PLFLAG_FILE_CASE, LK.PLFLAG_FILE_CASE_PRESERVING, LK.PLFLAG_AUTOLOAD]
        )
    )
    # the five stand-ins read the fields, which hold the same defaults as the mask
    @test ld.prolog_flag_last_call && ld.prolog_flag_portable_vmi &&
        !ld.prolog_flag_optimise
    @test ld.prolog_flag_optimise_unify && ld.prolog_flag_character_escapes_unicode
    for b in standins
        @test LK._prolog_flag_bit(ld, b) == LK.truePrologFlag(ld, b)
    end
    # `autoload` is an atom flag whose bit is set by hand (pl-prologflag.c)
    @test LK.truePrologFlag(ld, LK.PLFLAG_AUTOLOAD)
    # defaults the compiler and the reader depend on
    @test LK.truePrologFlag(ld, LK.PLFLAG_DEBUGINFO) &&
        LK.truePrologFlag(ld, LK.PLFLAG_QUASI_QUOTES)
    @test !LK.truePrologFlag(ld, LK.PLFLAG_ISO) &&
        !LK.truePrologFlag(ld, LK.PLFLAG_RATIONAL)
    @test !LK.truePrologFlag(ld, LK.PLFLAG_PROTECT_STATIC_CODE)
    @test LK.truePrologFlag(ld, LK.PLFLAG_FILE_CASE) &&
        LK.truePrologFlag(ld, LK.PLFLAG_FILE_CASE_PRESERVING)
    @test !LK.truePrologFlag(ld, LK.PLFLAG_GCTHREAD)             # `gc_thread`: false, read-only, in the no-threads build

    # H5: a new local data starts with the DATABASE's mask (pl-thread.c copies the creating thread's)
    @test ld.prolog_flag_mask == gd.prolog_flag.mask
    ld2 = LK.PL_local_data{_TL}(gd)
    @test ld2.prolog_flag_mask == gd.prolog_flag.mask
    gd.prolog_flag.mask |= LK.prologFlagMask(LK.PLFLAG_ISO)
    ld3 = LK.PL_local_data{_TL}(gd)
    @test LK.truePrologFlag(ld3, LK.PLFLAG_ISO) && !LK.truePrologFlag(ld2, LK.PLFLAG_ISO)
end

@testset "setPrologFlag: a flag is defined once; FF_KEEP keeps; a bit is owned by the type definition; a deleted flag leaves a hole" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    tab = gd.prolog_flag
    n0 = length(tab.entries)
    @test length(tab.names) == n0 && length(tab.slot) == n0 &&
        all(f -> f !== nothing, tab.entries)

    f = LK.current_prolog_flag(gd, "iso")
    @test f !== nothing && f.index == LK.PLFLAG_ISO && (f.flags & LK.FT_MASK) == LK.FT_BOOL
    @test (f.flags & LK.FF_READONLY) == 0
    @test LK.current_prolog_flag(gd, "nosuchflag") === nothing
    @test (LK.current_prolog_flag(gd, "bounded").flags & LK.FF_READONLY) != 0

    # defining again changes the value, not the table
    LK.setPrologFlag(gd, "iso", LK.FT_BOOL, true, LK.PLFLAG_ISO)
    @test length(tab.entries) == n0 && LK.current_prolog_flag(gd, "iso") === f
    @test sym_key(f.a) == sym_key(_tls("true"))
    @test (tab.mask & LK.prologFlagMask(LK.PLFLAG_ISO)) != 0
    LK.setPrologFlag(gd, "iso", LK.FT_BOOL, false, LK.PLFLAG_ISO)
    @test (tab.mask & LK.prologFlagMask(LK.PLFLAG_ISO)) == 0
    # FF_KEEP: an existing flag keeps its value
    LK.setPrologFlag(gd, "verbose", LK.FT_ATOM | LK.FF_KEEP, "silent")
    @test sym_text(LK.current_prolog_flag(gd, "verbose").a) == "normal"
    LK.setPrologFlag(gd, "zz_keep", LK.FT_ATOM | LK.FF_KEEP, "first")
    LK.setPrologFlag(gd, "zz_keep", LK.FT_ATOM | LK.FF_KEEP, "second")
    @test sym_text(LK.current_prolog_flag(gd, "zz_keep").a) == "first"
    # a type definition: a flag made without a bit that is given one later takes the bit and keeps its value
    LK.setPrologFlag(gd, "zz_td", LK.FT_BOOL, true, 0)
    @test LK.current_prolog_flag(gd, "zz_td").index == 0
    LK.setPrologFlag(gd, "zz_td", LK.FT_BOOL, false, LK.PLFLAG_SHIFT_CHECK)
    td = LK.current_prolog_flag(gd, "zz_td")
    @test td.index == LK.PLFLAG_SHIFT_CHECK && sym_key(td.a) == sym_key(_tls("true"))
    @test (tab.mask & LK.prologFlagMask(LK.PLFLAG_SHIFT_CHECK)) != 0      # the flag's value set the bit
    # a flag with a mask bit: `FF_WARN_NOT_ACCESSED` is marked by a lookup
    LK.setPrologFlag(gd, "zz_wn", LK.FT_INTEGER | LK.FF_WARN_NOT_ACCESSED, 1)
    wn = LK.current_prolog_flag(gd, "zz_wn")
    @test (wn.flags & LK.FF_ACCESSED) != 0                       # `current_prolog_flag` is a lookup
    LK.setPrologFlag(gd, "zz_wn2", LK.FT_INTEGER | LK.FF_WARN_NOT_ACCESSED, 1)
    key2 = LK._atom_word!(gd.atoms, gd.atom_symbols, _tls("zz_wn2"))
    @test (tab.entries[tab.slot[key2]].flags & LK.FF_ACCESSED) == 0
    @test LK.lookupFlag(gd, key2) !== nothing
    @test (tab.entries[tab.slot[key2]].flags & LK.FF_ACCESSED) != 0
    # each type
    LK.setPrologFlag(gd, "zz_int64", LK.FT_INT64 | LK.FF_READONLY, typemax(Int64))
    z = LK.current_prolog_flag(gd, "zz_int64")
    @test (z.flags & LK.FT_MASK) == LK.FT_INTEGER && z.i == typemax(Int64)       # FT_INT64 is stored as FT_INTEGER
    @test_throws ErrorException LK.setPrologFlag(gd, "zz_bad", LK.FT_BOOL, 5)
    @test_throws ErrorException LK.setPrologFlag(gd, "zz_bad2", LK.FT_ATOM, true, 0)

    # deleting leaves a hole the enumeration skips, and the flag can be defined again (a new slot)
    nlive = length(tab.slot)
    key = LK._atom_word!(gd.atoms, gd.atom_symbols, _tls("zz_keep"))
    @test LK.deletePrologFlag!(gd, key)
    @test !LK.deletePrologFlag!(gd, key)
    @test LK.current_prolog_flag(gd, "zz_keep") === nothing
    @test length(tab.slot) == nlive - 1 && count(f -> f === nothing, tab.entries) == 1
    keys1 = kernel_keys(ld)
    @test !("zz_keep" in keys1) && length(keys1) == length(tab.slot) - 6    # six defined flags do not answer
    LK.setPrologFlag(gd, "zz_keep", LK.FT_ATOM, "again")
    @test sym_text(LK.current_prolog_flag(gd, "zz_keep").a) == "again"
    @test "zz_keep" in kernel_keys(ld) && count(f -> f === nothing, tab.entries) == 1
end

@testset "a flag created or deleted during an enumeration (H2): no state lost, none seen twice" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    proc = LK.resolveProcedure(gd, _tls("current_prolog_flag"), 2, LK.MODULE_user(gd))
    tab = gd.prolog_flag
    base = length(kernel_keys(ld))

    # created after the third answer: it lands at the end, so the walk meets it
    created = Ref(false)
    hook = i -> begin
        if i == 3 && !created[]
            created[] = true
            LK.setPrologFlag(gd, "zz_new", LK.FT_BOOL, true, 0)
        end
    end
    sols, ok = run_query(gd, ld, proc, _vars(2); each=hook)
    keys = String[String(sym_text(s[1])) for s in sols]
    @test ok && created[] && allunique(keys)
    @test length(keys) == base + 1 && "zz_new" in keys
    @test LK.live_states(ld) == 0

    # deleted ahead of the walk: skipped, and the answers before it are untouched
    victim = "zz_new"
    killed = Ref(false)
    hook2 =
        i -> begin
            if i == 2 && !killed[]
                killed[] = true
                LK.deletePrologFlag!(
                    gd, LK._atom_word!(gd.atoms, gd.atom_symbols, _tls(victim))
                )
            end
        end
    sols2, ok2 = run_query(gd, ld, proc, _vars(2); each=hook2)
    keys2 = String[String(sym_text(s[1])) for s in sols2]
    @test ok2 && killed[] && allunique(keys2) && !(victim in keys2)
    @test length(keys2) == base
    @test LK.live_states(ld) == 0

    # the query closed with a state live (FRG_CUTTED frees it)
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(ld, a + 2, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE
    @test LK.live_states(ld) == 1
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test LK.live_states(ld) == 0

    # the same, the query cut (PL_cut_query keeps the bindings) after two answers
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    LK.putSlotValue!(ld, a + 2, mk_var(_TL, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE
    @test LK.live_states(ld) == 1
    LK.PL_cut_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test LK.live_states(ld) == 0
end

@testset "the scope argument: the global table (upstream register Q8; swipl gives no answer; re-check at the sync that brings upstream's change)" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    proc = LK.resolveProcedure(gd, _tls("\$current_prolog_flag"), 5, LK.MODULE_user(gd))
    # pl-prologflag.c pl_prolog_flag5: upstream register Q8; swipl gives no answer; re-check at the sync that brings upstream's
    # change. The local table is walked (empty here), then `e->scope = ATOM_global` and the global table follows, each flag's
    # scope unified with `e->scope` (the loop's end); the kernel follows that flow. With the scope unbound, swipl answers: the
    # global table, scope `global`. Hand-written: swipl gives no answer to the first.
    nkeys = length(kernel_keys(ld))
    sols, ok = run_query(gd, ld, proc, vcat(_vars(2), _tls("local"), _vars(2)))
    @test ok && isempty(sols)
    @test LK.live_states(ld) == 0
    sols2, ok2 = run_query(gd, ld, proc, vcat(_vars(2), _tls("global"), _vars(2)))
    @test ok2 && length(sols2) == nkeys && nkeys > 100
    @test all(s -> sym_text(s[3]) == "global", sols2)
    @test LK.live_states(ld) == 0
    sols3, ok3 = run_query(gd, ld, proc, _vars(5))
    @test ok3 && length(sols3) == nkeys
    @test all(s -> sym_text(s[3]) == "global", sols3)
    @test LK.live_states(ld) == 0
end

@testset "the flags that live outside the table: stack_limit follows the local stack, float_rounding the rounding bits, the module the syntax" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    proc = LK.resolveProcedure(gd, _tls("current_prolog_flag"), 2, LK.MODULE_user(gd))
    val(name) = begin
        sols, ok = run_query(gd, ld, proc, _TL[_tls(name), mk_var(_TL, LK.fresh_var_keys!(1))])
        ok && length(sols) == 1 ? sols[1][2] : nothing
    end
    @test lk_value(val("stack_limit")) == 1073741824                  # 1 GiB: STACK_LIMIT_DEFAULT words of 8 bytes (swipl's default)
    ld.stacks_limit = LK.STACK_LIMIT_DEFAULT ÷ 2
    @test lk_value(val("stack_limit")) == (LK.STACK_LIMIT_DEFAULT ÷ 2) * 8   # hand-written: the limit is counted in words here, bytes there
    ld.stacks_limit = LK.STACK_LIMIT_DEFAULT
    # float_rounding names the mode of arith_f_flags (the kernel only rounds to nearest; the other three are named for completeness)
    for (mode, name) in (
        (LK.FLT_ROUND_NEAREST, "to_nearest"), (LK.FLT_ROUND_TO_POS, "to_positive"),
        (LK.FLT_ROUND_TO_NEG, "to_negative"), (LK.FLT_ROUND_TO_ZERO, "to_zero")
    )
        ld.arith_f_flags = (ld.arith_f_flags & ~LK.FLT_ROUND_MASK) | mode
        @test sym_text(val("float_rounding")) == name
    end
    ld.arith_f_flags = (ld.arith_f_flags & ~LK.FLT_ROUND_MASK) | UInt32(9)
    @test val("float_rounding") === nothing                             # no such mode: the flag has no value
    ld.arith_f_flags = (ld.arith_f_flags & ~LK.FLT_ROUND_MASK) | LK.FLT_ROUND_NEAREST
    # the module's syntax flags are the module record's
    user = LK.MODULE_user(gd)
    @test (user.flags & LK.DBLQ_STRING) != 0 && sym_text(val("double_quotes")) == "string"
    # var_prefix is the module's character (0: none): swipl 10.1.19 answers `false`, `'_'` for `true`, the character itself otherwise
    # (set_prolog_flag(var_prefix, true / false / '?' / '$'), then current_prolog_flag(var_prefix, X), under `timeout 10 swipl`)
    @test user.var_prefix == 0 && sym_text(val("var_prefix")) == "false"
    for (c, name) in ((Int('_'), "_"), (Int('?'), "?"), (Int('\$'), "\$"))
        user.var_prefix = c
        @test sym_text(val("var_prefix")) == name
    end
    user.var_prefix = 0
    @test sym_text(val("var_prefix")) == "false"
end

@testset "the C interface: PL_get_prolog_flag, PL_current_prolog_flag" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    fid = LK.PL_open_foreign_frame(ld)
    v = LK.PL_new_term_ref(ld)
    # PL_get_prolog_flag unifies the value of the flag (the same lookup as current_prolog_flag/2)
    @test LK.PL_get_prolog_flag(gd, ld, _tls("iso"), v)
    @test sym_text(lk_answers(ld, v)[1]) == "false"
    v2 = LK.PL_new_term_ref(ld)
    @test !LK.PL_get_prolog_flag(gd, ld, _tls("nosuchflag"), v2)
    @test !LK.PL_get_prolog_flag(gd, ld, _tls("max_rational_size"), v2)         # defined, answers nothing
    v3 = LK.PL_new_term_ref(ld)
    @test LK.PL_get_prolog_flag(gd, ld, _tls("version"), v3)
    @test lk_value(lk_answers(ld, v3)[1]) == LK.PLVERSION
    LK.PL_close_foreign_frame(ld, fid)

    # PL_current_prolog_flag: the typed C reads (nothing for the wrong type or no flag)
    @test LK.PL_current_prolog_flag(gd, _tls("iso"), :bool) === false
    @test LK.PL_current_prolog_flag(gd, _tls("gc"), :bool) === true
    @test LK.PL_current_prolog_flag(gd, _tls("iso"), :atom) === nothing
    @test LK.PL_current_prolog_flag(gd, _tls("agc_margin"), :integer) == 10000
    @test LK.PL_current_prolog_flag(gd, _tls("agc_margin"), :float) === nothing
    @test LK.PL_current_prolog_flag(gd, _tls("halt_grace_time"), :float) == 1.0
    @test sym_text(LK.PL_current_prolog_flag(gd, _tls("unknown_option"), :atom)) == "ignore"
    @test LK.PL_current_prolog_flag(gd, _tls("nosuchflag"), :bool) === nothing
    # a term flag: the record put back (`version_data`)
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_ref(ld)
    @test LK.PL_current_prolog_flag(gd, ld, _tls("version_data"), t)
    vd = lk_answers(ld, t)[1]
    @test sym_text(child(vd, 1)) == "swi" && nchildren(vd) == 5
    @test [lk_value(child(vd, i)) for i in 2:4] == [10, 1, 19] && is_nil(child(vd, 5))
    @test !LK.PL_current_prolog_flag(gd, ld, _tls("iso"), t)                  # not a term flag
    @test !LK.PL_current_prolog_flag(gd, ld, _tls("nosuchflag"), t)
    LK.PL_close_foreign_frame(ld, fid)
end

# PL_record/PL_recorded/PL_erase/PL_duplicate_record (pl-fli.c): hand-written expectations — they are a C interface no Prolog
# predicate reaches (recorda/3 and erase/1 are R2 D2)
@testset "PL_record, PL_recorded, PL_erase, PL_duplicate_record" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    X, Y = mk_var(_TL, LK.fresh_var_keys!(1)), mk_var(_TL, LK.fresh_var_keys!(1))
    term = mk_expr(
        _TL,
        _TL[
            _tls("f"), X, Y, X, mk_gnd(_TL, "str"), mk_gnd(_TL, 1.5), mk_gnd(_TL, 7),
            mk_expr(_TL, _TL[mk_sym(_TL, LK.LIST_CONS_NAME), _tls("a"), mk_nil(_TL)])
        ]
    )
    want = enc(term)
    fid = LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, t + 1, term)
    r = LK.PL_record(ld, t)
    @test r isa LK.record
    LK.PL_close_foreign_frame(ld, fid)

    # the record outlives the frame it was made in, and puts the term back with fresh variables, sharing kept
    fid = LK.PL_open_foreign_frame(ld)
    t2 = LK.PL_new_term_ref(ld)
    @test LK.PL_recorded(ld, r, t2)
    @test enc(lk_answers(ld, t2)[1]) == want
    t3 = LK.PL_new_term_ref(ld)
    @test LK.PL_recorded(ld, r, t3)
    a2, a3 = lk_answers(ld, t2)[1], lk_answers(ld, t3)[1]
    @test var_key(child(a2, 2)) != var_key(child(a3, 2))                     # each copy has its own variables
    @test var_key(child(a2, 2)) == var_key(child(a2, 4))                      # …shared inside a copy
    LK.PL_close_foreign_frame(ld, fid)

    @test LK.PL_duplicate_record(r) === r
    @test LK.PL_erase(r) === nothing
    @test LK.live_states(ld) == 0
end

@testset "the read side after a failed enumeration: bindings undone, the state freed (a value no flag has)" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    proc = LK.resolveProcedure(gd, _tls("current_prolog_flag"), 2, LK.MODULE_user(gd))
    # a value no flag holds: the walk binds each key, fails to unify the value, rewinds — and ends with no answer and no state
    sols, ok = run_query(
        gd,
        ld,
        proc,
        _TL[mk_var(_TL, LK.fresh_var_keys!(1)), _tls("no_flag_has_this_value")]
    )
    @test ok && isempty(sols) && LK.live_states(ld) == 0
    # a bound key is deterministic: one answer, no state
    sols, ok = run_query(gd, ld, proc, _TL[_tls("iso"), mk_var(_TL, LK.fresh_var_keys!(1))])
    @test ok && length(sols) == 1 && LK.live_states(ld) == 0
    # a key that is no atom raises
    sols, ok = run_query(
        gd, ld, proc, _TL[mk_gnd(_TL, 1), mk_var(_TL, LK.fresh_var_keys!(1))]
    )
    @test !ok && isempty(sols) && LK.live_states(ld) == 0
end
