# ORIGINAL: BLOB — non-text atoms (blob/2) in the term interface (audit D-0153, D-0200); upstream tests blobs in Prolog.
# test/core_lang/test_blob.jl — on every term type: a blob is a SYM that is NOT text.  
#   * LIVE ROWS against swipl (stream, clause reference, mutex; registered in swipl's rank order, stream < clause
#     < mutex in the standard order): atom/1, atomic/1, blob/2, compare/3 against numbers, a string, `[]`, `''`,
#     text atoms, compounds and the other blob types; `==` of a blob with itself; blob/2 of text atoms; the
#     written form's SHAPE `<type>(0x<hex>)`;
#   * KERNEL-PINNED (DIVERGES D-0200, D-0149): two blobs of ONE type compare by CREATION order (handle); swipl
#     orders two streams by address (unreproducible): the known-difference block records swipl's answer;
#   * the interface: is_blob, blob_type, blob_handle, blob_rank; sym_text raises.
# Expected answers are swipl 10.1.19's: run live when swipl is on PATH (an ERROR-ish @test when
# LOGICKERNEL_REQUIRE_SWIPL=1 and absent), pinned in `_BL_TABLE` otherwise.
# allow-docstring-interp: the swipl program text interpolates the term list on purpose
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: ALL — the term layer: the SYM kind's blob form and its engine round trip: src/default_term.jl, src/pl-prims.jl, src/pl-inline.jl, src/pl-termhash.jl
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

# swipl's non-text blob types in rank order: registered mutex, clause, stream => ranks -1, -2, -3
const _BL_MUTEX = LK.PL_blob_t(LK.PL_BLOB_UNIQUE, "mutex")
const _BL_CLAUSE = LK.PL_blob_t(LK.PL_BLOB_UNIQUE, "clause")
const _BL_STREAM = LK.PL_blob_t(LK.PL_BLOB_UNIQUE, "stream")
const _BL_TYPES = (("stream", _BL_STREAM), ("clause", _BL_CLAUSE), ("mutex", _BL_MUTEX))

function _bl_db()::_RDB
    db = _RDB()
    for t in (_BL_MUTEX, _BL_CLAUSE, _BL_STREAM)
        LK.PL_register_blob_type(db.ld.atoms, t)
    end
    # D1: the database registers the `clause` type at its creation (`initDBRef!`, as pl-setup.c:146), so the
    # lines above only added `mutex` and `stream` AFTER it. swipl registers `mutex` earlier still (pl-thread.c),
    # `stream` later (pl-file.c): stream < clause < mutex in the standard order, as the rows below expect.
    # A fresh database has no blob term yet, so the three ranks are set to swipl's order here.
    for (t, rank) in ((_BL_MUTEX, -1), (_BL_CLAUSE, -2), (_BL_STREAM, -3))
        LK._blob_registration(db.ld.atoms, t).rank = rank
    end
    return db
end

"The blob term of `type` with payload bytes `payload` in `db`'s atom table."
function _bl_make(db::_RDB, type::LK.PL_blob_t, payload::Vector{UInt8})::_R
    w, _ = LK.lookupBlob(db.ld.atoms, payload, length(payload), type)
    return LK._blob_term!(db.ld.atoms, db.ld.atom_symbols, _R, w)
end

"The first answer of `name(args...)` as its arguments' values; `nothing` on failure, `:exception` on a throw."
function _bl_ask(db::_RDB, name::String, args::_R...)
    gd, ld = db.gd, db.ld
    goal = _rf(name, args...)
    n = length(args)
    fid = LK.PL_open_foreign_frame(ld)
    refs = LK.PL_new_term_refs(ld, n)
    pvm = LK.PutVarMap()
    for i in 1:n
        LK.putSlotValue!(ld, refs + i, args[i], pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_NORMAL | LK.PL_Q_EXT_STATUS, _rproc(db, goal), refs
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        lk_answers(ld, (refs:(refs + n - 1))...)
    elseif rc == LK.PL_S_EXCEPTION
        :exception
    else
        nothing
    end
    LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
    return out
end

_bl_yes(db, name, args...) = _bl_ask(db, name, args...) isa Vector
_bl_sym(t::_R) = String(lk_name(t))
const _BL_SIGN = Dict("<" => -1, "=" => 0, ">" => 1)
const _BL_OP = Dict(-1 => "<", 0 => "=", 1 => ">")

"`compare(O, a, b)` through the engine, as -1/0/1."
function _bl_cmp(db::_RDB, a::_R, b::_R)::Int
    ans = _bl_ask(db, "compare", _rv(1), a, b)
    ans isa Vector || error("compare/3 did not answer")
    return _BL_SIGN[_bl_sym(ans[1])]
end

# (name, kernel builder, Prolog source) of the non-blob terms every blob is compared with
const _BL_OTHERS = (
    ("one", () -> _rg(1), "1"), ("float", () -> _rg(1.5), "1.5"),
    ("str", () -> _rg("abc"), "\"abc\""), ("nil", () -> _rnil(), "[]"),
    ("empty", () -> _rs(""), "''"), ("abc", () -> _rs("abc"), "abc"),
    ("comp", () -> _rf("f", _rs("a")), "f(a)"), ("list", () -> _rlist(_rs("a")), "[a]")
)

"The swipl program: every row one line `key value`."
function _bl_swipl_program()::String
    others = join(["$(n)-($(src))" for (n, _, src) in _BL_OTHERS], ", ")
    return """
    :- set_prolog_flag(double_quotes, string).
    main :-
      open_null_stream(S), open_null_stream(S2), clause(main, _, C), mutex_create(M),
      Bs = [stream-S, clause-C, mutex-M],
      forall(member(N-B, Bs),
        ( ( atom(B) -> A = true ; A = false ), format("atom:~w ~w~n", [N, A]),
          ( atomic(B) -> At = true ; At = false ), format("atomic:~w ~w~n", [N, At]),
          ( blob(B, T) -> true ; T = none ), format("blob:~w ~w~n", [N, T]),
          ( callable(B) -> Ca = true ; Ca = false ), format("callable:~w ~w~n", [N, Ca]),
          ( compound(B) -> Co = true ; Co = false ), format("compound:~w ~w~n", [N, Co]),
          ( B == B -> Id = true ; Id = false ), format("self:~w ~w~n", [N, Id]),
          compare(O0, B, B), format("cmpself:~w ~w~n", [N, O0]),
          with_output_to(string(W), write(B)), format("write:~w ~s~n", [N, W]),
          forall(member(XN-X, [$others]),
                 ( compare(O, B, X), format("cmp:~w:~w ~w~n", [N, XN, O]) )) )),
      forall(( member(N1-B1, Bs), member(N2-B2, Bs), N1 \\== N2 ),
        ( compare(O, B1, B2), format("pair:~w:~w ~w~n", [N1, N2, O]),
          ( B1 == B2 -> E = true ; E = false ), format("eq:~w:~w ~w~n", [N1, N2, E]) )),
      ( S == S2 -> E2 = true ; E2 = false ), format("eq:s:s2 ~w~n", [E2]),
      compare(O3, S, S2), format("pair:s:s2 ~w~n", [O3]),
      compare(O4, S2, S), format("pair:s2:s ~w~n", [O4]),
      forall(member(XN-X, [abc-abc, nil-[], empty-'', one-1, comp-f(a)]),
        ( ( blob(X, T2) -> true ; T2 = none ), format("textblob:~w ~w~n", [XN, T2]),
          ( atom(X) -> Y = true ; Y = false ), format("textatom:~w ~w~n", [XN, Y]),
          ( atomic(X) -> Z = true ; Z = false ), format("textatomic:~w ~w~n", [XN, Z]) )).
    :- initialization((main, halt)).
    """
end

"The same rows from the kernel: `key => value`."
function _bl_kernel_rows()::Dict{String, String}
    db = _bl_db()
    bs = [(n, _bl_make(db, t, UInt8[0x01, 0x02])) for (n, t) in _BL_TYPES]
    r = Dict{String, String}()
    tf(x) = x ? "true" : "false"
    for (n, x) in bs
        r["atom:$n"] = tf(_bl_yes(db, "atom", x))
        r["atomic:$n"] = tf(_bl_yes(db, "atomic", x))
        ans = _bl_ask(db, "blob", x, _rv(1))
        r["blob:$n"] = ans isa Vector ? _bl_sym(ans[2]) : "none"
        r["callable:$n"] = tf(_bl_yes(db, "callable", x))
        r["compound:$n"] = tf(_bl_yes(db, "compound", x))
        r["self:$n"] = tf(_bl_yes(db, "==", x, x))
        r["cmpself:$n"] = _BL_OP[_bl_cmp(db, x, x)]
        r["write:$n"] = string(x)
        for (xn, mk, _) in _BL_OTHERS
            r["cmp:$n:$xn"] = _BL_OP[_bl_cmp(db, x, mk())]
        end
    end
    for (n1, x1) in bs, (n2, x2) in bs
        n1 == n2 && continue
        r["pair:$n1:$n2"] = _BL_OP[_bl_cmp(db, x1, x2)]
        r["eq:$n1:$n2"] = tf(_bl_yes(db, "==", x1, x2))
    end
    for (xn, x) in (
        ("abc", _rs("abc")), ("nil", _rnil()), ("empty", _rs("")), ("one", _rg(1)),
        ("comp", _rf("f", _rs("a")))
    )
        ans = _bl_ask(db, "blob", x, _rv(1))
        r["textblob:$xn"] = ans isa Vector ? _bl_sym(ans[2]) : "none"
        r["textatom:$xn"] = tf(_bl_yes(db, "atom", x))
        r["textatomic:$xn"] = tf(_bl_yes(db, "atomic", x))
    end
    return r
end

const _BL_SWIPL = (
    get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
)
const _BL_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

function _bl_swipl_rows()::Dict{String, String}
    out = mktempdir() do d
        f = joinpath(d, "blob.pl")
        write(f, _bl_swipl_program())
        read(pipeline(`swipl -q $f`; stdin=devnull), String)
    end
    r = Dict{String, String}()
    for l in eachline(IOBuffer(out))
        isempty(strip(l)) && continue
        k, v = split(l, ' '; limit=2)
        r[String(k)] = String(v)
    end
    return r
end

# swipl 10.1.19's answers (probe: evidence/BLOB/swipl_probe_p2.out), the rows that do not depend on an address
const _BL_TABLE = Dict(
    "atom:stream" => "false", "atomic:stream" => "true", "blob:stream" => "stream",
    "atom:clause" => "false", "atomic:clause" => "true", "blob:clause" => "clause",
    "atom:mutex" => "false", "atomic:mutex" => "true", "blob:mutex" => "mutex",
    "callable:stream" => "false", "compound:stream" => "false", "self:stream" => "true",
    "cmp:stream:one" => ">", "cmp:stream:float" => ">", "cmp:stream:str" => ">",
    "cmp:stream:nil" => "<", "cmp:stream:empty" => "<", "cmp:stream:abc" => "<",
    "cmp:stream:comp" => "<", "cmp:stream:list" => "<",
    "pair:stream:clause" => "<", "pair:clause:mutex" => "<", "pair:stream:mutex" => "<",
    "pair:clause:stream" => ">", "pair:mutex:clause" => ">", "pair:mutex:stream" => ">",
    "eq:stream:clause" => "false",
    "textblob:abc" => "text", "textblob:nil" => "reserved_symbol",
    "textblob:empty" => "text",
    "textblob:one" => "none", "textblob:comp" => "none",
    "textatom:abc" => "true", "textatom:nil" => "false", "textatom:one" => "false",
    "textatomic:nil" => "true", "textatomic:one" => "true", "textatomic:comp" => "false"
)

@testset "blob rows on $(LK_TERM_IMPL)" begin
    k = _bl_kernel_rows()

    @testset "the kernel against the pinned swipl 10.1.19 table" begin
        for (key, want) in _BL_TABLE
            @test (key => get(k, key, "<missing>")) == (key => want)
        end
        @test length(_BL_TABLE) > 35
    end

    if _BL_SWIPL !== nothing
        @testset "the kernel against live swipl, every row" begin
            sw = _bl_swipl_rows()
            @test length(sw) > 70
            for (key, v) in sw
                (
                    startswith(key, "write:") ||
                    key in ("pair:s:s2", "pair:s2:s", "eq:s:s2")
                ) &&
                    continue
                @test (key => get(k, key, "<missing>")) == (key => v)
            end
            # both sides non-empty and the SAME rows: swipl's keys are the kernel's plus the three same-type rows
            @test Set(keys(sw)) ==
                union(Set(keys(k)), Set(["pair:s:s2", "pair:s2:s", "eq:s:s2"]))
            # THE WRITTEN FORM: swipl `<stream>(0x<address>)`, the kernel `<type>(0x<handle hex>)`: the SHAPE
            for n in ("stream", "clause", "mutex")
                @test occursin(Regex("^<$n>\\(0x[0-9a-f]+\\)\$"), sw["write:$n"])
                @test occursin(Regex("^<$n>\\(0x[0-9a-f]+\\)\$"), k["write:$n"])
            end
        end
    else
        @test !_BL_SWIPL_REQUIRED
        for n in ("stream", "clause", "mutex")
            @test occursin(Regex("^<$n>\\(0x[0-9a-f]+\\)\$"), k["write:$n"])
        end
    end

    # KNOWN DIFFERENCE (DIVERGES D-0200, D-0149; representation): two blobs of ONE type. swipl 10.1.19 orders
    # two streams by payload address: `open_null_stream(S), open_null_stream(S2)` gave compare(O,S,S2) = `>`
    # and compare(O,S2,S) = `<` (S the OLDER); msort([S,S2,O]) with current_output(O) gave O, S2, S. No Term
    # can reproduce that; the kernel orders by CREATION (handle): the older first. Pinned exactly.
    @testset "KNOWN DIFFERENCE: two blobs of one type stand in creation order" begin
        db = _bl_db()
        s1 = _bl_make(db, _BL_STREAM, UInt8[0x01])
        s2 = _bl_make(db, _BL_STREAM, UInt8[0x02])
        s1b = _bl_make(db, _BL_STREAM, UInt8[0x01])
        @test _bl_cmp(db, s1, s2) == -1                      # swipl: >
        @test _bl_cmp(db, s2, s1) == 1                       # swipl: <
        @test _bl_cmp(db, s1, s1b) == 0
        @test !_bl_yes(db, "==", s1, s2)                     # swipl: false (agrees)
        @test _bl_yes(db, "==", s1, s1b)
        @test compareStandard(s1, s2) == -1 && compareStandard(s2, s1) == 1
        @test compareStandard(s1, s1b) == 0
        @test blob_handle(s1) == blob_handle(s1b) != blob_handle(s2)
        @test blob_handle(s1) < blob_handle(s2)
    end

    @testset "the interface" begin
        db = _bl_db()
        s = _bl_make(db, _BL_STREAM, UInt8[0x01])
        c = _bl_make(db, _BL_CLAUSE, UInt8[0x01])
        t = _rs("abc")
        @test is_blob(s) && is_blob(c) && !is_blob(t) && !is_blob(_rnil()) &&
            !is_blob(_rg(1))
        @test kind(s) === SYM && !is_reserved_symbol(s) && !is_nil(s) && !is_pair(s)
        @test blob_type(s) === :stream && blob_type(c) === :clause
        @test blob_rank(s) == -3 && blob_rank(c) == -2
        @test_throws ArgumentError blob_type(t)
        @test_throws ArgumentError sym_text(s)
        @test_throws ArgumentError sym_first_byte(s)
        @test sym_key(s) != sym_key(c) && sym_key(s) != sym_key(t)
        @test sym_hash(s) != sym_hash(c)
        named = _rs("stream")                                # a blob is never the text atom of its type name
        @test sym_key(s) != sym_key(named) && compareStandard(s, named) != 0
        @test !_bl_yes(db, "==", s, named)
        @test _bl_yes(db, "==", s, s)
        @test compareStandard(s, _rs("a")) == -1 && compareStandard(_rs("a"), s) == 1
        @test compareStandard(s, _rnil()) == -1 && compareStandard(_rnil(), s) == 1
        @test compareStandard(_rg(1), s) == -1 && compareStandard(_rg("x"), s) == -1
        @test compareStandard(s, c) == -1 && compareStandard(c, s) == 1
        @test compareStandard(s, mk_expr(_R, _R[_rs("f"), s])) == -1
        @test occursin(r"^<stream>\(0x[0-9a-f]+\)$", string(s))
        ans = _bl_ask(db, "=", _rv(1), mk_expr(_R, _R[_rs("f"), s]))
        @test ans isa Vector && is_blob(child(ans[1], 2)) &&
            blob_handle(child(ans[1], 2)) == blob_handle(s)
        @test_throws ArgumentError mk_blob(_R, UInt64(1) << 45, :stream, -1)
        @test_throws ArgumentError mk_blob(_R, UInt64(1), :stream, 0)
        @test_throws ArgumentError mk_blob(_R, UInt64(1), :stream, -65536)
    end

    # kill rows of the hand-run mutants (tools/mutants/BLOB.py M5, M7, M8, M9): the writer, char_code, the term hash
    # and the compiler's callable test, which the swipl rows above do not reach
    @testset "writer, char_code, variant_sha1, compiled body" begin
        db = _bl_db()
        ld = db.ld
        for (n, ty) in _BL_TYPES
            x = _bl_make(db, ty, UInt8[0x07])
            LK.PL_open_foreign_frame(ld)
            t = LK.PL_new_term_refs(ld, 1)
            LK.putSlotValue!(ld, t + 1, x, LK.PutVarMap())
            for flags in (0, LK.PL_WRT_QUOTED)
                out = IOBuffer()
                LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, out)
                @test LK.PL_write_term(
                    LK._query_gd(ld), ld, LK.Suser_output(ld), t, 1200, flags
                )
                LK.Sflush(LK.Suser_output(ld))
                @test occursin(Regex("^<$n>\\(0x[0-9a-f]+\\)\$"), String(take!(out)))
            end
            @test !LK.PL_is_callable(ld, t)                    # a blob word is not callable (M11)
            # a compound whose functor NAME is a blob is not callable either (M11: PL_is_callable's compound branch)
            bx = mk_expr(_R, _R[x, _rs("a")])
            LK.putSlotValue!(ld, t + 1, bx, LK.PutVarMap())
            @test !LK.PL_is_callable(ld, t)
            # lookupBodyProcedure refuses a blob goal, atom or compound head (M9: _body_functor; compileSubClause! turns
            # a blob goal away first, pl-comp.jl, so only a direct call reaches it)
            for g in (x, bx)
                culprit = try
                    LK.lookupBodyProcedure(db.gd, g, LK.MODULE_user(db.gd))
                    nothing
                catch e
                    e isa LK.CallableTypeError{_R} || rethrow()
                    e.culprit
                end
                @test culprit === g
            end
            @test _bl_ask(db, "char_code", x, _rv(1)) === :exception   # a blob is no character (charCode -1)
            @test _bl_ask(db, "assertz", _rf(":-", _rs("foo"), x)) === :exception   # a blob is no callable body
        end
        s1 = _bl_make(db, _BL_STREAM, UInt8[0x01])
        s2 = _bl_make(db, _BL_STREAM, UInt8[0x02])
        @test sym_hash(s1) != sym_hash(s2)                      # two blobs of one type hash apart (M10)
        # the variant hash tells blob TYPES apart: same handle and rank, different type name
        @test LK.pl_variant_sha1(mk_blob(_R, UInt64(5), :stream, -3)) !=
            LK.pl_variant_sha1(mk_blob(_R, UInt64(5), :clause, -3))
    end
end
