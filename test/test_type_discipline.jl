# ORIGINAL: no-Any and concrete-field gates; no swipl-devel counterpart.
# test/test_type_discipline.jl — no `Any` in src, no abstractly typed struct field. Runs EVERYWHERE
# (no external tools needed), so CI's plain test job enforces it too. Each rule is first run on a
# fixture that plants the defect, so a gate that sees nothing cannot pass by default.
using Test, LogicKernel

include(joinpath(@__DIR__, "static_analysis_gates.jl"))

# Fixtures are built from STRINGS: the defects they plant must not be code in this file.
const _TD_ANY_FIXTURE = """
\"\"\"A docstring that says Any is fine to mention.\"\"\"
k(x) = x
f(x::Any) = x                 # flagged (line 3)
const V = Vector{Any}()       # flagged (line 4)
g(x) = x                      # Any in a comment is not code
h(x) = Base.Any               # flagged, qualified (line 6)
"""

const _TD_FIELD_FIXTURE = """
module TDFieldFixture
struct Bad1; a::Any; end
struct Bad2; b::Real; end
struct Bad3; c::Vector; end
struct Bad4; d::Union{Int, Float64, String, Symbol, Char}; end
struct Good; e::Int; f::Union{Nothing, Int}; g::Vector{Int}; h::Union{Int, Float64, String}; end
struct Param{T}; x::T; y::Vector{T}; z::Union{Nothing, T}; end
end
"""

const _TD_UNCHECKED_FIXTURE = """
\"\"\"Mentions @inbounds and unsafe_load in a docstring: not code.\"\"\"
f(v, i) = @inbounds v[i]                          # line 2
g(p) = unsafe_load(p)                             # line 3
h(v) = (Base.@propagate_inbounds; v)              # line 4
k(x) = x  # @inbounds in a comment
m(d, s, n) = unsafe_copyto!(d, s, n)              # line 6
c() = ccall(:jl_gc_collect, Cvoid, ())            # line 7
"""

# The term-type rule's fixture (R1c): three methods build terms on a `T` bound only by term
# arguments (a bare `T`, a `Union`, a `Tuple`); four bind it exactly or build nothing.
const _TD_TERMTYPE_FIXTURE = """
bad1(a::T) where {T} = mk_sym(T, :x)
bad2(a::Union{Nothing, T}, b::Int)::Int where {T} = (T[]; 1)
good1(ld::PL_local_data{T}, a::T) where {T} = mk_sym(T, :x)
good2(::Type{T}, a::T) where {T} = mk_sym(T, :x)
good3(a::T) where {T} = sym_key(a)
function bad3(op::Tuple{T, Int})::T where {T}
    return mk_nil(T)
end
good4(v::Vector{T}, a::T)::T where {T} = mk_expr(T, T[a])
"""

# The ALLOWLIST of unchecked constructs in src/ (user, 2026-10-04): `"file construct" => (count,
# reason)`. A new one fails the rule until it is listed here with a measured reason; a listed one
# that is gone fails it too — so the list cannot go stale.
const _TD_UNCHECKED_ALLOWED = Dict(
    "pl-termhash.jl @inbounds" => (
        1,
        "sha1_hf!: the SHA-1 message schedule; `w` is the 16-word `wbuf` and every index is " *
        "`& 15` or below 16 (pl-termhash.c `hf`)"
    ),
    "pl-termhash.jl unsafe_copyto!" => (
        1,
        "_sha1_memcpy!: upstream's memcpy into `wbuf`'s bytes (4 ns against 15 ns, measured); " *
        "its byte range is CHECKED first, so it cannot write outside `wbuf` or read outside `data`"
    ),
    "pl-arith.jl ccall" => (
        20,
        "the C library's libm (arith-b; arith-c adds sinh, cosh, tanh, asinh, acosh, atanh, erf, " *
        "log10, lgamma): sin, cos, tan, asin, acos, atan, atan2, exp, log, sqrt, pow… as swipl calls them (Julia's own differ from glibc in the last digit and throw where " *
        "C gives a NaN); each passes and returns Float64 values only — no pointer, no buffer"
    ),
    "default_term.jl unsafe_convert" => (
        1,
        "sym_first_byte (D-0140): the interned Symbol's name pointer (jl_symbol_name), as upstream's " *
        "stringAtom(a)[0]; a Symbol is never freed and held by GC.@preserve — the +2 allocations per " *
        "findall/3 the String of sym_text cost (A-0091 item 4)"
    ),
    "default_term.jl unsafe_load" => (
        1,
        "sym_first_byte: reads byte 1 of that name, which is NUL-terminated, so the empty atom reads 0x00 " *
        "and the read never passes the name's end"
    ),
    "os/pl-os.jl ccall" => (
        3,
        "Y1: pl-os.c's three C-library calls, as upstream makes them: clock_gettime (CpuTime, WallTime, " *
        "ThreadCPUTime: the nanosecond clocks Julia does not give), setenv and unsetenv (the errno " *
        "setenv/2 and unsetenv/1 report, EINVAL for an empty name or one with `=`); each is handed " *
        "Cstring arguments (Julia's conversion refuses a NUL, the callers cut the name at one) or a " *
        "Ref the call fills with two Int64s, and returns an Int32"
    ),
    "os/pl-files.jl ccall" => (
        1,
        "Y1: RemoveFile, remove(3) as upstream's pl-files.c calls it (it deletes a file or an empty " *
        "directory, and the errno delete_file/1 reports); the argument is a Cstring of a name the " *
        "caller checked for NULs and PATH_MAX, the result an Int32"
    ),
    "pl-read.jl ccall" => (
        1,
        "_strtod (R1c): the C library's strtod, as upstream's ascii_to_double calls it, for its " *
        "rounding and its errno (ERANGE drives the float_overflow/underflow rules); the text is " *
        "copied into a 0-terminated vector held by GC.@preserve, so strtod reads only that copy"
    ),
    "os/pl-stream.jl ccall" => (
        2,
        "_current_umask (R2 S1): the C library's umask(2), read by setting it and putting it back, " *
        "so that a file open/4's create(Modes) option makes gets its mode less the umask, as " *
        "upstream's open(2) gives it; it passes and returns an unsigned integer only"
    )
)

@testset "type discipline" begin
    @testset "a method that builds terms binds T from the term type, not from a term (R1c)" begin
        hits = term_type_from_term_arg_uses(joinpath(pkgdir(LogicKernel), "src"))
        isempty(hits) || foreach(
            h -> println(stderr, "  T bound only by a term argument: src/", h), hits
        )
        @test isempty(hits)
        fx = mktempdir() do d
            write(joinpath(d, "fixture.jl"), _TD_TERMTYPE_FIXTURE)
            term_type_from_term_arg_uses(d)
        end
        @test fx == ["fixture.jl:1 bad1", "fixture.jl:2 bad2", "fixture.jl:6 bad3"]
    end

    @testset "no Any in LogicKernel's src" begin
        hits = any_uses(joinpath(pkgdir(LogicKernel), "src"))
        isempty(hits) || foreach(h -> println(stderr, "  Any at src/", h), hits)
        @test isempty(hits)
    end

    @testset "no abstractly typed struct field in LogicKernel" begin
        bad = nonconcrete_fields(LogicKernel)
        isempty(bad) || foreach(b -> println(stderr, "  abstract field: ", b), bad)
        @test isempty(bad)
    end

    @testset "no unchecked memory access in src beyond the allowlist" begin
        found = Dict{String, Int}()
        for u in unchecked_uses(joinpath(pkgdir(LogicKernel), "src"))
            file_line, construct = split(u, ' '; limit=2)
            k = first(split(file_line, ':')) * " " * construct
            found[k] = get(found, k, 0) + 1
        end
        want = Dict(k => v[1] for (k, v) in _TD_UNCHECKED_ALLOWED)
        for k in sort!(collect(setdiff(keys(found), keys(want))))
            println(
                stderr, "  unchecked access NOT on the allowlist: ", k, " (", found[k], ")"
            )
        end
        @test found == want
        @test all(v -> length(v[2]) > 20, values(_TD_UNCHECKED_ALLOWED))   # every entry says why
    end

    @testset "the allowlisted unsafe_copyto! checks its own range" begin
        ctx, data = LogicKernel.sha1_ctx(), collect(UInt8(1):UInt8(80))
        @test LogicKernel._sha1_memcpy!(ctx, 60, data, 0, 4) === nothing      # exactly to the end
        @test_throws BoundsError LogicKernel._sha1_memcpy!(ctx, 60, data, 0, 8) # past wbuf
        @test_throws BoundsError LogicKernel._sha1_memcpy!(ctx, 0, data, 76, 8) # past data
        @test_throws BoundsError LogicKernel._sha1_memcpy!(ctx, -1, data, 0, 4)
    end

    @testset "fixture: the unchecked scan finds exactly the planted uses" begin
        mktempdir() do d
            write(joinpath(d, "fx.jl"), _TD_UNCHECKED_FIXTURE)
            @test unchecked_uses(d) == [
                "fx.jl:2 @inbounds", "fx.jl:3 unsafe_load", "fx.jl:4 @propagate_inbounds",
                "fx.jl:6 unsafe_copyto!", "fx.jl:7 ccall"
            ]
        end
    end

    @testset "fixture: the Any scan finds exactly the planted uses" begin
        mktempdir() do d
            write(joinpath(d, "fx.jl"), _TD_ANY_FIXTURE)
            @test any_uses(d) == ["fx.jl:3", "fx.jl:4", "fx.jl:6"]
        end
    end

    @testset "fixture: the field check finds exactly the planted fields" begin
        fx = Base.include_string(Module(:TDHost), _TD_FIELD_FIXTURE)
        @test nonconcrete_fields(fx) == [
            "Bad1.a::Any", "Bad2.b::Real", "Bad3.c::Vector",
            "Bad4.d::Union{Char, Float64, Int64, String, Symbol}"
        ]
    end
end

# THE CONDITION SLOT ON A TERM TYPE WITH NO `Int64` PAYLOAD (D-0231; V9d decision 3): C_IFTHENELSE,
# C_IFTHEN, C_FASTCOND, C_SOFTIF and C_SOFTCUT keep a choice point's position in a frame slot. It
# was written as `mk_gnd(T, ::Int64)`, a `MethodError` on such a type (AV3-W4 found it through
# findall/3 under MOD2), so every if-then-else failed there. The rows run each writer on the fixture
# type `Term{Union{BigInt, Float64, String}}` (an integer is a `BigInt`, AV3-W4's), built as terms
# and compiled: the type reads no integer from text. Expected: swipl 10.1.19, probed 2026-10-29
# (the same goals from text; the fixture type itself cannot be given to swipl): 1, 2, 1, 1, 1, 1, 1.
"Clause `td_t(X) :- body(X)` compiled on term type `T`; run it; return `X`'s term and the opcodes."
function _td_cond_row(::Type{T}, body::Function) where {T}
    LK = LogicKernel
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    user = LK.MODULE_user(gd)
    k = LK.fresh_var_keys!(4)
    X, Y = mk_var(T, k), mk_var(T, k + UInt64(1))
    h = mk_expr(T, T[mk_sym(T, :td_t), X])
    pr = LK.lookupProcedure(mk_sym(T, :td_t), 1, user)
    cl = LK.compileClause(gd, ld, h, body(X, Y), pr, user)
    LK.assertDefinition!(gd, pr.definition, cl, LK.CL_END)
    ops = Symbol[]
    pc = LK.Code(cl, 1)
    while pc.pc <= length(cl.codes)
        push!(ops, LK.codeTable(LK.decode(pc)).name)
        pc = LK.stepPC(pc)
    end
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(T, k + UInt64(2)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, pr, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    ans = LK.export_cells(ld, LK.cell_export{T}(), -(a + 1))
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return rc, ans, ops
end

@testset "the condition slot holds a position on a term type with no Int64 payload (D-0231)" begin
    TB = LogicKernel.Term{Union{BigInt, Float64, String}}
    @test !LogicKernel._holds_payload(TB, Int64)
    s(x) = mk_sym(TB, Symbol(x))
    c(f, xs...) = mk_expr(TB, TB[s(f), xs...])
    i(n) = mk_gnd(TB, big(n))
    rows = [
        ("( true -> X = 1 ; X = 2 )", :C_IFTHENELSE, 1,
            (X, Y) -> c(";", c("->", s("true"), c("=", X, i(1))), c("=", X, i(2)))),
        ("( fail -> X = 1 ; X = 2 )", :C_IFTHENELSE, 2,
            (X, Y) -> c(";", c("->", s("fail"), c("=", X, i(1))), c("=", X, i(2)))),
        ("( true -> X = 1 )", :C_IFTHEN, 1, (X, Y) -> c("->", s("true"), c("=", X, i(1)))),
        ("Y = a, ( atom(Y) -> X = 1 ; X = 2 )", :C_FASTCOND, 1,
            (X, Y) -> c(",", c("=", Y, s("a")),
                c(";", c("->", c("atom", Y), c("=", X, i(1))), c("=", X, i(2))))),
        ("( true *-> X = 1 ; X = 2 )", :C_SOFTIF, 1,
            (X, Y) -> c(";", c("*->", s("true"), c("=", X, i(1))), c("=", X, i(2)))),
        (
            "\\+ fail, X = 1",
            :C_NOT,
            1,
            (X, Y) -> c(",", c("\\+", s("fail")), c("=", X, i(1)))
        ),
        ("freeze(V, X = 1), V = a", :I_CALL, 1,
            (X, Y) -> c(",", c("freeze", Y, c("=", X, i(1))), c("=", Y, s("a"))))
    ]
    for (goal, op, want, body) in rows
        rc, ans, ops = _td_cond_row(TB, body)
        ok = rc in (LogicKernel.PL_S_TRUE, LogicKernel.PL_S_LAST)
        @test (goal, op in ops, ok) == (goal, true, true)
        @test (goal, kind(ans) === GND && LogicKernel.gnd_value(ans) == want) ==
            (goal, true)
    end
end

# THE MANIFEST'S LIVE-METHOD FILTER (test/static_analysis_gates.jl `_current_method`; measured
# 2026-10-14): a method Revise DELETED — the old signature of a re-signed function — is not live; a
# live one is, and so is each method of an ambiguous pair (the gate must still check those).
module _TDCurrent
f(x::Int) = 1
g(x::Integer, y::Int) = 1
g(x::Int, y::Integer) = 2
end
@testset "the manifest's live-method filter: a deleted method is not live" begin
    old = only(methods(_TDCurrent.f))
    @test _current_method(old)
    Base.delete_method(old)                     # what Revise does when a signature changes
    Core.eval(_TDCurrent, :(f(x::Int, y::Int) = 2))
    @test !_current_method(old)
    @test _current_method(only(methods(_TDCurrent.f)))
    @test all(_current_method, methods(_TDCurrent.g))
end
