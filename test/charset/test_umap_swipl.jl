# ORIGINAL: the Unicode map (R1c, src/pl-umap.jl) against pl-umap.c and swipl 10.1.16; upstream checks its map through char_type/2 and code_type/2 (tests/charset), which the kernel does not port yet.
# test/charset/test_umap_swipl.jl — R1c's map gate:
#   * THE DATA: src/pl-umap.jl's generated region is exactly what tools/gen_umap.jl makes of
#     swipl-devel's src/pl-umap.c at the pin — wherever a checkout is found (as tools/port_check.jl
#     checks upstream); without one, the test asserts that there is none, so it cannot skip silently;
#   * EVERY CODE POINT, 0 to 0x10FFFF, against swipl: each class code_type/2 reads from the map —
#     the Prolog syntax classes (pl-read.c's f_is_prolog_*), pattern_syntax, the POSIX classes
#     (pl-ctype.c's mkctype over PL_ctype_flags), prolog_layout — as ranges, every display width
#     (PL_wcwidth), and every bracket and quote mate (pl_pair_table) identical.
using Test, LogicKernel
const LK = LogicKernel

# ── the data: the generated region against pl-umap.c ─────────────────────────────────────────────
const _UM_CHECKOUT = get(
    ENV, "LOGICKERNEL_UPSTREAM_SWIPL_DEVEL", joinpath(homedir(), "dev-zone", "swipl-devel")
)
const _UM_C = joinpath(_UM_CHECKOUT, "src", "pl-umap.c")

if isfile(_UM_C)
    @testset "src/pl-umap.jl's tables are pl-umap.c's (tools/gen_umap.jl)" begin
        m = Module(:GenUmapCheck)
        Base.include(m, joinpath(pkgdir(LogicKernel), "tools", "gen_umap.jl"))
        dst = joinpath(pkgdir(LogicKernel), "src", "pl-umap.jl")
        @test Base.invokelatest(m.regenerate, _UM_C, dst) == read(dst, String)
        u = Base.invokelatest(m.parse_umap, _UM_C)
        @test length(u.uflags.index) == LK.UNICODE_MAP_SIZE == ncodeunits(LK.uflags_map) ÷ 2
        @test length(u.uctype.index) == ncodeunits(LK.uctype_map) ÷ 2
        @test length(u.pairs) == LK.PL_PAIR_TABLE_SIZE == length(LK.pl_pair_table)
    end
else
    @info "UNICODE MAP DATA CHECK NOT RUN: no swipl-devel checkout at $_UM_CHECKOUT (CI has none)."
    @testset "the map's data check is skipped only where there is no checkout" begin
        @test !isfile(_UM_C)
    end
end

# ── every code point ────────────────────────────────────────────────────────────────────────────

# The classes as code_type/2 computes them (pl-ctype.c's class table), over the kernel's map.
const _UM_CLASSES = (
    "prolog_var_start" => c -> LK.PlUpperW(c) || c == Int('_'),
    "prolog_atom_start" => c -> LK.PlIdStartW(c) && !(LK.PlUpperW(c) || c == Int('_')),
    "prolog_identifier_continue" => c -> LK.PlIdContW(c) || c == Int('_'),
    "decimal" => c -> LK.PlDecimalW(c),
    "prolog_symbol" => c -> LK.PlSymbolW(c),
    "prolog_solo" => c -> LK.PlSoloW(c),
    "pattern_syntax" => c -> LK.PlCatW(c) == LK.U_CAT_PATTERN_SYNTAX,
    "white" => c -> (LK.uctypeFlagsW(c) & LK.UC_BLANK) != 0,
    "space" => c -> (LK.uctypeFlagsW(c) & LK.UC_SPACE) != 0,
    "alpha" => c -> (LK.uctypeFlagsW(c) & LK.UC_ALPHA) != 0,
    "alnum" => c -> (LK.uctypeFlagsW(c) & LK.UC_ALNUM) != 0,
    "cntrl" => c -> (LK.uctypeFlagsW(c) & LK.UC_CNTRL) != 0,
    "print" => c -> (LK.uctypeFlagsW(c) & LK.UC_PRINT) != 0,
    "graph" => c -> (LK.uctypeFlagsW(c) & LK.UC_GRAPH) != 0,
    "lower" => c -> (LK.uctypeFlagsW(c) & LK.UC_LOWER) != 0,
    "upper" => c -> (LK.uctypeFlagsW(c) & LK.UC_UPPER) != 0,
    "punct" => c -> (LK.uctypeFlagsW(c) & LK.UC_PUNCT) != 0,
    "end_of_line" => c -> (LK.uctypeFlagsW(c) & LK.UC_EOL) != 0,
    "prolog_layout" => c -> LK.PlBlankW(c),
    "period" => c -> (LK.uctypeFlagsW(c) & LK.UC_STERM) != 0
)

"`pred`'s code points from 0 to 0x10FFFF, as `First Last` ranges."
function _um_ranges(pred)::Vector{Tuple{Int, Int}}
    out = Tuple{Int, Int}[]
    first = -1
    for c in 0:0x10FFFF
        if pred(c)
            first < 0 && (first = c)
        elseif first >= 0
            push!(out, (first, c - 1))
            first = -1
        end
    end
    first >= 0 && push!(out, (first, 0x10FFFF))
    return out
end

"The kernel's side, in the driver's format: classes, widths, brackets, quotes."
function _um_kernel_lines()::Vector{String}
    lines = String[]
    for (name, pred) in _UM_CLASSES
        for (f, l) in _um_ranges(pred)
            push!(lines, "$name $f $l")
        end
    end
    for w in 0:2                            # -1 is not a width: code_type(C, width(W)) fails
        for (f, l) in _um_ranges(c -> !(0xD800 <= c <= 0xDFFF) && LK.PL_wcwidth(c) == w)
            push!(lines, "width($w) $f $l")
        end
    end
    for c in 1:0x10FFFF                     # f_paren_close
        0xD800 <= c <= 0xDFFF && continue   # (swipl: not a character code)
        if LK.PlCatW(c) == LK.U_CAT_BRACKET
            m, is_open = LK.pl_pair_lookup(c)
            (m != 0 && is_open) && push!(lines, "paren $c $m")
        end
    end
    for c in 1:0x10FFFF                     # f_quote_close
        0xD800 <= c <= 0xDFFF && continue
        if c == Int('\'') || c == Int('"') || c == Int('`')
            push!(lines, "quote $c $c")
        elseif LK.PlCatW(c) == LK.U_CAT_QUOTE
            m, is_open = LK.pl_pair_lookup(c)
            (m != 0 && is_open) && push!(lines, "quote $c $m")
        end
    end
    return lines
end

const _UM_DRIVER = raw"""
classes([prolog_var_start, prolog_atom_start, prolog_identifier_continue, decimal, prolog_symbol,
         prolog_solo, pattern_syntax, white, space, alpha, alnum, cntrl, print, graph,
         lower, upper, punct, end_of_line, prolog_layout, period]).
ranges([], []).
ranges([C|Cs], [C-E|Rs]) :- span(C, Cs, E, Rest), ranges(Rest, Rs).
span(E0, [C|Cs], E, Rest) :- C =:= E0+1, !, span(C, Cs, E, Rest).
span(E, Rest, E, Rest).
class(T) :- findall(C, code_type(C, T), Cs0), sort(Cs0, Cs), ranges(Cs, Rs),
    forall(member(F-L, Rs), format("~w ~d ~d~n", [T, F, L])).
surrogate(C) :- C >= 0xD800, C =< 0xDFFF.     % not a character code: code_type/2 raises
width(C, W) :- ( surrogate(C) -> W = none ; code_type(C, width(W0)) -> W = W0 ; W = none ).
widths :- width(0, W0), widths(1, 0, W0).
widths(C, F, W) :- C > 0x10FFFF, !, wout(F, 0x10FFFF, W).
widths(C, F, W) :- width(C, W1),
    ( W1 == W -> C1 is C+1, widths(C1, F, W)
    ; L is C-1, wout(F, L, W), C1 is C+1, widths(C1, C, W1) ).
wout(_, _, none) :- !.
wout(F, L, W) :- format("width(~d) ~d ~d~n", [W, F, L]).
mates :- forall((between(1, 0x10FFFF, C), \+ surrogate(C), code_type(C, paren(M))), format("paren ~d ~d~n", [C, M])),
    forall((between(1, 0x10FFFF, C), \+ surrogate(C), char_code(Ch, C), char_type(Ch, quote(Q)), char_code(Q, M)),
           format("quote ~d ~d~n", [C, M])).
:- initialization((classes(Ts), maplist(class, Ts), widths, mates, halt)).
"""

const _UM_SWIPL = Sys.which("swipl")
const _UM_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

if _UM_SWIPL !== nothing
    @testset "every code point's classes, width and mates == swipl's code_type/2" begin
        theirs = mktempdir() do d
            f = joinpath(d, "c.pl")
            write(f, _UM_DRIVER)
            String.(split(chomp(read(`swipl -q $f`, String)), '\n'))
        end
        ours = _um_kernel_lines()
        @test length(theirs) > 1000                # the driver ran: every class, every width
        missing_ = setdiff(theirs, ours)
        extra = setdiff(ours, theirs)
        for l in missing_[1:min(end, 6)]
            println(stderr, "  swipl only:  ", l)
        end
        for l in extra[1:min(end, 6)]
            println(stderr, "  kernel only: ", l)
        end
        @test isempty(missing_) && isempty(extra)
        @test sort(ours) == sort(theirs)            # the same lines, the same multiplicity
    end
elseif _UM_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the Unicode map differential would be skipped"
    )
else
    @info "UNICODE MAP DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "Unicode map differential skipped only where it is not required" begin
        @test !_UM_SWIPL_REQUIRED
    end
end
