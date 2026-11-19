# ORIGINAL: LIVE and white-box kill rows for the trie CHARGE and LIMIT sites of src/pl-trie.jl and src/pl-tabling.jl (TAB1 S3e, tools/mutants/TRIECH.py): the
# eight mutants that survived the battery of 3eaae177 (audit D-0859 (2)): TC-H, TC-I, TC-J, TC-K, TC-R, TC-T, TC-W, TC-X. Every unit below is swipl's own
# answer at the pin 18168e62 (10.1.20), `~q` text of one case, two byte-identical runs (LC_ALL=C), the program the same on both sides; with `swipl` on PATH the live
# answers are compared with the pins too. A white-box testset is hand-written from the C text (the reference at each row) where swipl cannot reach the site.
#   * LIM     a tabled predicate of three answers run under `table_space` = (space in use) + D, D = 200..1000 one byte at a time, each run on a table of its own, the
#             answer a run-length list of (outcome, bytes left charged): the refusals at the variant nodes, the answer trie's struct (pl-trie.c:238, `get_answer_table`
#             ignoring a refused answer trie is TC-X), the root's blocks (pl-trie.c:869, :886: TC-H, TC-I) and the nodes. A mutant that ignores a refusal throws or leaves a
#             charge, and moves a run. D < 200 is not swept (a sweep below 200 is not pinned: see the private register).
#   * MONOSP  `table_space_used` of a monotonic table whose rule calls its own table twice: the second dependency builds the index trie (`mono_index_build`,
#             pl-tabling.c:10118), charged to the answer trie's pool (TC-W: an index trie without a pool leaves its 152 bytes and nodes uncharged).
#   * white-box (hand-written from the C text; swipl reaches no `ld`-less caller and no concurrent trie with a pool by a program):
#             TC-H / TC-I / TC-R  a refused block in `insert_child` (pl-trie.c:869, :886, :1575): the child is destroyed, its charge given back;
#             TC-J                `replace_block` of a pool that cannot hold the compacted block keeps the old one (pl-trie.c:921);
#             TC-T                `trie_alloc_from_pool` without `ld` refuses above the limit only (pl-allocpool.c `pool->size+bytes <= pool->limit`);
#             TC-K                a TRIE_CONCURRENT trie charges every node (pl-trie.c:1087).
# UNVERIFIED on the kernel when written: every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - these built-ins ride the term layer through the FLI (unify, get, the table pool)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL_T = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(x) = lk_sym(_TL_T, Symbol(x))

"The helpers every unit starts with: the `~q` text of one case's answer."
const _TL_COMMON = raw"""
tl_q(G, A) :- ( catch(call(G, R), E, R = exc(E)) -> true ; R = failed ), format(atom(A), "~q", [R]).
"""

const _TL_LIM = (
    unit="LIM",
    program=raw"""
:- table tl_t3/2.
tl_t3(_, X) :- between(1, 3, X).
% one run: the table space limited to what is in use plus D bytes; K the outcome, Post the bytes the run left charged (before the abolish)
tl_one(D, K, Post) :-
    statistics(table_space_used, U0), L is U0 + D,
    set_prolog_flag(table_space, L),
    G = tl_t3(D, X),
    catch((findall(X, G, Xs), length(Xs, N), K0 = ok(N)), E, K0 = err(E)),
    set_prolog_flag(table_space, 1000000000),
    statistics(table_space_used, U1), Post is U1 - U0,
    abolish_all_tables,
    tl_kind(K0, K).
tl_kind(ok(N), ok(N)) :- !.
tl_kind(err(error(resource_error(_), _)), res) :- !.
tl_kind(_, other).
tl_sweep(Lo, Hi, Rle) :-
    findall(K-Post, (between(Lo, Hi, D), tl_one(D, K, Post)), Ps),
    tl_rle(Ps, Rle).
tl_rle([], []).
tl_rle([K-Po|T], [run(K, Po, N)|R]) :- tl_same(T, K-Po, 1, N, Rest), tl_rle(Rest, R).
tl_same([P|T], P, N0, N, Rest) :- !, N1 is N0+1, tl_same(T, P, N1, N, Rest).
tl_same(Rest, _, N, N, Rest).
tl_warm :- findall(X, tl_t3(w, X), _).
""",
    cases=[("m01", "tl_warm, tl_sweep(200, 1000, R)")],
    pinned=[
        "[run(res,144,1),run(res,192,31),run(res,232,40),run(res,272,40),run(res,312,40),run(res,352,152),run(res,304,320),run(ok(3),760,177)]"
    ],
    kill=[1]
)

const _TL_MONOSP = (
    unit="MONOSP",
    program=raw"""
:- table tm_c/2 as monotonic.
:- dynamic tm_l/2 as monotonic.
tm_c(X, Z) :- tm_c(X, Y), tm_c(Y, Z).
tm_c(X, Y) :- tm_l(X, Y).
sp(U) :- statistics(table_space_used, U).
""",
    cases=[
        (
            "w1",
            "sp(U0), findall(X-Y, tm_c(X, Y), _), assertz(tm_l(a, b)), assertz(tm_l(b, c)), findall(X-Y, tm_c(X, Y), L), sp(U1), R = r(U0, L, U1)"
        ),
        (
            "w2",
            "assertz(tm_l(c, d)), findall(X-Y, tm_c(X, Y), L), length(L, N), sp(U), R = r(N, U)"
        ),
        ("w3", "abolish_all_tables, sp(U), R = U")
    ],
    pinned=["r(0,[a-b,a-c,b-c],5512)", "r(6,8152)", "1672"],
    kill=[1, 2]
)

_tl_text(u) =
    _TL_COMMON * u.program * join(["t_$(id)(R) :- $body.\n" for (id, body) in u.cases])

"The `~q` text of each case's answer, in order, from swipl at the pin."
function _tl_swipl_lines(u)::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "tl.pl")
        write(
            f,
            _tl_text(u) * ":- initialization((forall(member(G, [" *
            join(["t_$id" for (id, _) in u.cases], ",") *
            "]), (tl_q(G, A), write(A), nl)), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"The `~q` text of the answer of `case`, run as `tl_q(case, A)` in the kernel (a Julia exception answers `THROWN <type>`)."
function _tl_ask(gd, ld, case::String)::String
    proc = LK.isCurrentProcedure(sym_key(_tls("tl_q")), 2, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "tl_q undefined"
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 2)
    LK.putSlotValue!(ld, a + 1, _tls(case), LK.PutVarMap())
    LK.putSlotValue!(ld, a + 2, mk_var(_TL_T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    ans = try
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        rc = LK.PL_next_solution(gd, ld, qid)
        r = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            t = lk_answers(ld, ((a + 1):(a + 1))...)[1]
            kind(t) === SYM ? sym_text(t) : "not an atom"
        else
            rc == LK.PL_S_EXCEPTION ? "exception" : "failed"
        end
        LK.PL_close_query(ld, qid)
        r
    catch e
        "THROWN $(typeof(e))"
    end
    LK.PL_close_foreign_frame(ld, fid)
    return ans
end

"A kernel with the unit's program consulted: `(gd, ld, load status)`."
function _tl_load(u)
    f = joinpath(mktempdir(), "tabling_triech.pl")
    write(f, _tl_text(u))
    gd = LK.PL_global_data{_TL_T}()
    ld = LK.PL_local_data{_TL_T}(gd)
    st, _ = LK.load_file!(gd, ld, f)
    return gd, ld, st
end

"The indices where two answer lists differ (a missing answer counts as a difference)."
_tl_diff(lines::Vector{String}, pins::Vector{String}) =
    [
        i for i in 1:max(length(lines), length(pins)) if
        i > length(lines) || i > length(pins) || lines[i] != pins[i]
    ]

function _tl_check_unit(u)
    ids = [id for (id, _) in u.cases]
    @testset "$(u.unit)" begin
        gd, ld, st = _tl_load(u)
        lines = String[_tl_ask(gd, ld, "t_$id") for id in ids]
        @testset "$(u.unit): the rows run as swipl's pins (kills TRIECH, rows $(join(u.kill, ", ")))" begin
            @test st === :ok
            @test !isempty(lines) && !isempty(u.pinned) &&
                length(lines) == length(u.pinned) == length(ids)
            for (id, k, p) in zip(ids, lines, u.pinned)
                k == p || println(stderr, "  ours  ", id, " ", k, "\n  swipl ", p)
                @test k == p
            end
            # a corrupted pin, an extra pin and a dropped pin are each flagged
            @test _tl_diff(lines, vcat(u.pinned[1] * "x", u.pinned[2:end])) ==
                sort(union(_tl_diff(lines, u.pinned), [1]))
            @test _tl_diff(lines, vcat(u.pinned, "extra")) ==
                sort(union(_tl_diff(lines, u.pinned), [length(u.pinned) + 1]))
        end
        @testset "$(u.unit): the pins are swipl's (live, when swipl is on PATH)" begin
            if Sys.which("swipl") === nothing || get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1"
                @info "TRIECH LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
                @test length(u.pinned) == length(ids)
            else
                @test _tl_swipl_lines(u) == u.pinned
            end
        end
    end
    return nothing
end

_tl_check_unit(_TL_LIM)
_tl_check_unit(_TL_MONOSP)

# NOT VACUOUS: the pins hold what each mutant moves
@testset "TRIECH rows are not vacuous" begin
    # LIM: the sweep sees refusals (res) and, past the last, the full table (ok(3)); a run that charged nothing leaves 0 (never pinned: a table refused at its first
    # charge), the ladder of left charges rises with D until the answer trie's struct fits (the 352-byte run of 152 limits)
    pin = _TL_LIM.pinned[1]
    @test occursin("run(ok(3),760,177)", pin) && count("run(res,", pin) == 7
    @test !occursin("other", pin)
    # MONOSP: the index trie's charge shows between the first evaluation and the abolish (the residue of the abolish stays: 1672)
    @test _TL_MONOSP.pinned == ["r(0,[a-b,a-c,b-c],5512)", "r(6,8152)", "1672"]
    @test 8152 > 5512 > 1672
end

# ---- white-box rows (hand-written from the C text) ----

_tl_tk(k::Integer)::UInt64 = LK.consTagged(k, LK.TAG_ATOM | LK.STG_STATIC)

"A local database, a pool of `limit` bytes and a trie charged to it (pl-trie.c:238 charges SIZEOF_TRIE)."
function _tl_pool_trie(limit::Int)
    gd = LK.PL_global_data{_TL_T}()
    ld = LK.PL_local_data{_TL_T}(gd)
    pool = LK.new_alloc_pool("table_space", limit)
    tr = LK.trie_create(ld, _TL_T, pool)
    return gd, ld, pool, tr
end

@testset "TRIECH white-box: a refused block in insert_child (aims TRIECH-TC-H, -I, -R; pl-trie.c:869, :886, :1575)" begin
    # TC-H: the second child of the root needs a block of 2 (pl-trie.c:869). The pool has room for the node (SIZEOF_TRIE_NODE = 40) and not for the block: add_child
    # fails, insert_child destroys the child (:1575, free_trie_node gives its 40 bytes back) and answers 0; the root keeps its single child.
    gd, ld, pool, tr = _tl_pool_trie(1_000_000)
    c1 = LK.insert_child(tr, 1, _tl_tk(1), ld)
    @test c1 != 0 && pool.size == LK.SIZEOF_TRIE + LK.SIZEOF_TRIE_NODE
    before = pool.size
    pool.limit = before + LK.SIZEOF_TRIE_NODE                 # the node fits, the block (more than 40 bytes) does not
    @test LK.block_size(2, 0) > LK.SIZEOF_TRIE_NODE
    @test LK.insert_child(tr, 1, _tl_tk(2), ld) == 0
    @test tr.nodes[1].children == LK.single_child_code(c1) && isempty(tr.blocks)
    @test pool.size == before                                 # TC-R: the destroyed child's charge is back (without destroy_node the 40 stay)
    @test LK.get_child(tr, 1, _tl_tk(2)) == 0
    # with room the same insert succeeds (not vacuous)
    pool.limit = 1_000_000
    c2 = LK.insert_child(tr, 1, _tl_tk(2), ld)
    @test c2 != 0 && LK.get_child(tr, 1, _tl_tk(2)) == c2 && length(tr.blocks) == 1
    @test pool.size == before + LK.SIZEOF_TRIE_NODE + LK.block_size(2, 0)

    # TC-I: the third child of a full block of 2 needs a block of 4 (pl-trie.c:886): refused, the block of 2 stays and no child is added
    full = pool.size
    @test tr.blocks[length(tr.blocks)].capacity == 2 &&
        tr.blocks[length(tr.blocks)].count == 2
    bid = LK.children_block_id(tr.nodes[1].children)
    pool.limit = full + LK.SIZEOF_TRIE_NODE
    @test LK.block_size(4, 0) > LK.SIZEOF_TRIE_NODE
    @test LK.insert_child(tr, 1, _tl_tk(3), ld) == 0
    @test LK.children_block_id(tr.nodes[1].children) == bid &&
        LK.block_at(tr, bid).count == 2 && LK.block_at(tr, bid).capacity == 2
    @test pool.size == full                                   # TC-R again, for the larger block's failure
    @test LK.get_child(tr, 1, _tl_tk(3)) == 0
    pool.limit = 1_000_000
    @test LK.insert_child(tr, 1, _tl_tk(3), ld) != 0
    @test LK.block_at(tr, LK.children_block_id(tr.nodes[1].children)).capacity == 4
end

@testset "TRIECH white-box: replace_block keeps the old block when the pool cannot hold the compacted one (aims TRIECH-TC-J; pl-trie.c:921)" begin
    # five children: a block of capacity 8; three deleted (dead 3, 3*2 > 5: compact), live 2: the new block has capacity 2. The pool has no room (limit = in use),
    # delete_child(.., compact = true) without `ld` (the prune path, no error): the old block stays, the children stay readable.
    gd, ld, pool, tr = _tl_pool_trie(1_000_000)
    ids = [LK.insert_child(tr, 1, _tl_tk(k), ld) for k in 1:5]
    bid = LK.children_block_id(tr.nodes[1].children)
    @test LK.block_at(tr, bid).capacity == 8 && LK.block_at(tr, bid).count == 5
    pool.limit = pool.size                                    # no room for any new block
    @test !LK.delete_child(tr, 1, ids[1], true)
    @test !LK.delete_child(tr, 1, ids[2], true)
    @test !LK.delete_child(tr, 1, ids[3], true)               # dead 3: replace_block is called and its new_block is refused
    @test LK.children_block_id(tr.nodes[1].children) == bid   # the old block was kept (mutant: block_at(tr, 0) throws)
    @test LK.block_at(tr, bid).dead == 3 && LK.block_at(tr, bid).count == 5
    @test LK.get_child(tr, 1, _tl_tk(4)) == ids[4] &&
        LK.get_child(tr, 1, _tl_tk(5)) == ids[5]
    @test LK.get_child(tr, 1, _tl_tk(1)) == 0
    # the control: with room the same compaction replaces the block by one of capacity 2
    pool.limit = 1_000_000
    @test !LK.delete_child(tr, 1, ids[4], true)               # dead 4 of 5: compact again, live 1 -> a single child, no block needed (the C live == 1 branch)
    @test LK.is_single_child(tr.nodes[1].children) &&
        LK.single_child(tr.nodes[1].children) == ids[5]
    gd2, ld2, pool2, tr2 = _tl_pool_trie(1_000_000)
    ids2 = [LK.insert_child(tr2, 1, _tl_tk(k), ld2) for k in 1:5]
    for i in 1:3
        @test !LK.delete_child(tr2, 1, ids2[i], true)
    end
    @test !LK.is_single_child(tr2.nodes[1].children)
    nb = LK.block_at(tr2, LK.children_block_id(tr2.nodes[1].children))
    @test nb.capacity == 2 && nb.count == 2 && nb.dead == 0   # the compacted block
end

@testset "TRIECH white-box: trie_alloc_from_pool without ld refuses above the limit only (aims TRIECH-TC-T; pl-allocpool.c)" begin
    # pl-allocpool.c alloc_from_pool: `pool->size+bytes <= pool->limit` takes the bytes; the ld-less form answers false instead of raising
    gd, ld, pool, tr = _tl_pool_trie(1_000_000)
    pool.limit = pool.size + 100
    @test LK.trie_alloc_from_pool(tr, 100)                    # exactly the limit: taken (mutant `<`: refused)
    @test pool.size == pool.limit
    @test !LK.trie_alloc_from_pool(tr, 1)                     # one byte over: refused
    @test pool.size == pool.limit
    @test LK.trie_alloc_from_pool(tr, 0)                      # nothing: taken at the limit
end

@testset "TRIECH white-box: a TRIE_CONCURRENT trie charges every node (aims TRIECH-TC-K; pl-trie.c:1087)" begin
    # a shared table's variant trie is TRIE_CONCURRENT with a pool (pl-tabling.c:2616-2620; the kernel has no shared tables): alloc_trie_node charges
    # SIZEOF_TRIE_NODE for each node, individually, and refuses when the pool cannot hold it
    gd, ld, pool, tr = _tl_pool_trie(1_000_000)
    tr.flags |= LK.TRIE_CONCURRENT
    before = pool.size
    r = LK.alloc_trie_node(tr, ld)
    @test r !== nothing && r[1] == 0 && r[2] === nothing && !r[3]
    @test pool.size == before + LK.SIZEOF_TRIE_NODE           # mutant: not charged
    pool.limit = pool.size                                    # no room for another node
    @test LK.alloc_trie_node(tr) === nothing                  # refused (no ld: no error)
    @test pool.size == before + LK.SIZEOF_TRIE_NODE
    # the child nodes of a concurrent trie are all individual: after 9 nodes (past TRIE_SINGLE_NODES = 8) the charge is still 40 each
    gd2, ld2, pool2, tr2 = _tl_pool_trie(1_000_000)
    tr2.flags |= LK.TRIE_CONCURRENT
    b2 = pool2.size
    for k in 1:10
        @test LK.insert_child(tr2, 1, _tl_tk(k), ld2) != 0
    end
    @test pool2.size >= b2 + 10 * LK.SIZEOF_TRIE_NODE         # a concurrent trie keeps its replaced blocks lingering (not freed): at least the 10 nodes
end
