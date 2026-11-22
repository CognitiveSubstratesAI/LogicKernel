# ORIGINAL: white-box rows of the per-stream locale (`IOSTREAM.locale`): pl-stream.c Ssetlocale and the release in S__close, pl-locale.c initStreamLocale,
# initDefaultsStreamsLocale and the loop of set_locale/1 over the five standard streams (swipl-devel 18168e62). Stream layer only: what `~:d` and `~:f` print by
# it is test/core_text/test_locale_fmt_swipl.jl's (the reading half). There is no swipl row: the objects (a reference count, a field) are not observable in swipl.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

# THE STREAM'S LOCALE is held by the stream, counted (white-box, the objects): a stream takes a reference when it gets its locale and gives it back
# when it is closed (pl-stream.c Ssetlocale, S__close).
@testset "LOCALE-STREAM: the locale of a stream is a counted reference (Ssetlocale, S__close)" begin
    l = LK.new_locale(_TL, nothing)
    l.decimal_point = ","
    l.thousands_sep = "."
    l.grouping = Int[3, 0]
    LK.acquireLocale(l)                                        # our own reference: the locale is not freed when the stream lets go
    @test l.references == 1
    s = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(nothing), Ref(0), "w")::LK.IOSTREAM
    @test s.locale === nothing                                 # a stream the stream layer makes has none: Snew has no database
    @test LK.Ssetlocale(s, l) === nothing                      # the locale it had
    @test s.locale === l && l.references == 2
    @test LK.Ssetlocale(s, l) === l && l.references == 2       # the same locale: nothing changes
    @test LK.Ssetlocale(s, nothing) === l && s.locale === nothing && l.references == 1
    @test LK.Ssetlocale(s, l) === nothing && l.references == 2
    LK.Sclose(s)
    @test s.locale === nothing && l.references == 1            # S__close gives the reference back
    @test l.magic == LK.LOCALE_MAGIC && l.decimal_point == ","
    LK.releaseLocale(l)                                        # the last reference, no alias, no blob: the locale is freed
    @test l.references == 0 && l.magic == 0 && l.decimal_point == "" && l.grouping == [0]
end

# initStreamLocale gives a new stream the CURRENT locale and counts it; set_locale/1 gives the five standard streams the new one and lets the
# old one go (pl-locale.c set_locale: `for(i=0; i<=4; i++) Ssetlocale(&LD->IO.streams[i], new, NULL)`).
@testset "LOCALE-STREAM: initStreamLocale and set_locale/1 (the five standard streams)" begin
    gd = LK.PL_global_data{_TL}()
    ld = LK.PL_local_data{_TL}(gd)
    def = gd.locale.default_locale
    @test def !== nothing && gd.locale.current === def
    s = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(nothing), Ref(0), "w")::LK.IOSTREAM
    n0 = def.references
    @test LK.initStreamLocale(gd, s) && s.locale === def && def.references == n0 + 1
    LK.Sclose(s)
    @test s.locale === nothing && def.references == n0
    mktempdir() do d
        f = joinpath(d, "sl.pl")
        write(
            f,
            ":- locale_create(_, \"C\", [alias(lsl), decimal_point(','), thousands_sep('.'), grouping([repeat(3)])]), set_locale(lsl).\n"
        )
        st, _ = LK.load_file!(gd, ld, f)
        @test st === :ok
    end
    cur = gd.locale.current
    @test cur !== def && cur.alias !== nothing
    held = [ld.IO_streams[i] for i in 1:5 if ld.IO_streams[i] !== nothing]
    @test length(held) >= 3                                    # not vacuous: user_input, user_output, user_error at least
    @test all(si -> si.locale === cur, held)
    @test cur.references >= length(held)                       # one reference per stream, at least
    s2 = LK.Sopenmem(Ref{Union{Nothing, Vector{UInt8}}}(nothing), Ref(0), "w")::LK.IOSTREAM
    n1 = cur.references
    @test LK.initStreamLocale(gd, s2) && s2.locale === cur && cur.references == n1 + 1   # a stream made now has the new current locale
    LK.Sclose(s2)
    @test cur.references == n1
end
