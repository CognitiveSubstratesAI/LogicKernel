# ORIGINAL: unit tests of src/os/pl-libtai.jl (the libtai pieces of TAI1); the values are calendar arithmetic (the MJD of 1970-01-01 is 40587, of 2000-03-01 51604; the TAI count of the Unix epoch is pl-tai.c's TAI_UTC_OFFSET), not an oracle's
# test/core_text/test_libtai.jl — caldate_mjd, caldate_frommjd, caltime_tai, caltime_utc and the leap-second table. UNTESTED when written (TAI1 writer, edit-only).
using Test, LogicKernel
const LK = LogicKernel

const _TAI_EPOCH = UInt64(4611686018427387914)             # pl-tai.c TAI_UTC_OFFSET: the TAI count of 1970-01-01 00:00:00 UTC

const _NOLEAP = UInt64[]                                   # an empty leap-second table, whatever /etc/leapsecs.dat holds on this host

@testset "TAI1 libtai: calendar dates" begin
    @test LK.caldate_mjd(LK.caldate(1970, 1, 1)) == 40587
    @test LK.caldate_mjd(LK.caldate(2000, 3, 1)) == 51604
    @test LK.caldate_mjd(LK.caldate(1858, 11, 17)) == 0
    @test LK.caldate_mjd(LK.caldate(2020, 1, 2)) == 58850
    @test LK.caldate_mjd(LK.caldate(2020, 13, 1)) == LK.caldate_mjd(LK.caldate(2021, 1, 1))   # a month past 12 normalises
    @test LK.caldate_mjd(LK.caldate(2020, 3, 0)) == LK.caldate_mjd(LK.caldate(2020, 2, 29))   # day 0 is the day before

    cd = LK.caldate()
    @test LK.caldate_frommjd(cd, 40587) == (4, 0)              # Thursday, the first day of the year
    @test (cd.year, cd.month, cd.day) == (1970, 1, 1)
    @test LK.caldate_frommjd(cd, 51604) == (3, 60)             # 2000-03-01: Wednesday, day 60 (0-based) of a leap year
    @test (cd.year, cd.month, cd.day) == (2000, 3, 1)
    @test LK.caldate_frommjd(cd, 0) == (3, 320)                # 1858-11-17 was a Wednesday
    @test (cd.year, cd.month, cd.day) == (1858, 11, 17)

    # every day of a long range is its own inverse, and the weekday advances by one
    ok = true
    for d in Iterators.flatten((-700_000:97:900_000, 51_000:52_000))   # the second range holds 2000-02-29, the day 146096 of a cycle
        cd = LK.caldate()
        wday, yday = LK.caldate_frommjd(cd, d)
        ok &= LK.caldate_mjd(cd) == d
        ok &= 0 <= wday <= 6 && 0 <= yday <= 365
    end
    @test ok
    for d in 51000:51800
        c1, c2 = LK.caldate(), LK.caldate()
        w1, _ = LK.caldate_frommjd(c1, d)
        w2, _ = LK.caldate_frommjd(c2, d + 1)
        @test w2 == (w1 + 1) % 7
    end
end

@testset "TAI1 libtai: calendar time and TAI" begin
    let
        ct = LK.caltime(LK.caldate(1970, 1, 1), 0, 0, 0, 0)
        @test LK.caltime_tai(ct, _NOLEAP) == _TAI_EPOCH
        ct = LK.caltime(LK.caldate(1970, 1, 1), 1, 0, 0, 60)    # 01:00 at an offset of 60 minutes is 00:00 UTC
        @test LK.caltime_tai(ct, _NOLEAP) == _TAI_EPOCH
        ct = LK.caltime(LK.caldate(1970, 1, 2), 0, 0, 5, 0)
        @test LK.caltime_tai(ct, _NOLEAP) == _TAI_EPOCH + UInt64(86405)

        out = LK.caltime()
        wy = LK.caltime_utc(out, _TAI_EPOCH + UInt64(1_000_000_000), _NOLEAP)
        @test (out.date.year, out.date.month, out.date.day) == (2001, 9, 9)
        @test (out.hour, out.minute, out.second, out.offset) == (1, 46, 40, 0)
        @test wy == (0, 251)                                    # a Sunday, day 251 (0-based)
        wy = LK.caltime_utc(out, _TAI_EPOCH - UInt64(1), _NOLEAP)        # a second before the epoch
        @test (out.date.year, out.date.month, out.date.day) == (1969, 12, 31)
        @test (out.hour, out.minute, out.second) == (23, 59, 59)
        @test wy == (3, 364)

        # an out-of-range field normalises through the round trip, as cal_ftm relies on
        ct = LK.caltime(LK.caldate(2020, 1, 32), 25, 61, 61, 0)
        LK.caltime_utc(out, LK.caltime_tai(ct, _NOLEAP), _NOLEAP)
        @test (out.date.year, out.date.month, out.date.day) == (2020, 2, 2)
        @test (out.hour, out.minute, out.second) == (2, 2, 1)
    end
end

@testset "TAI1 libtai: leap seconds" begin
    # a missing file is an empty table; so is a directory, which cannot be read
    @test isempty(LK.leapsecs_read(joinpath(mktempdir(), "no-such-leapsecs.dat")))
    @test isempty(LK.leapsecs_read(mktempdir()))

    # a file of big-endian 8-byte entries, the last one half written
    x0 = _TAI_EPOCH + UInt64(1_020)
    x1 = _TAI_EPOCH + UInt64(5_000)
    path = joinpath(mktempdir(), "leapsecs.dat")
    open(path, "w") do io
        for x in (x0, x1)
            write(io, hton(x))
        end
        write(io, UInt8[1, 2, 3])
    end
    tab = LK.leapsecs_read(path)
    @test tab == [x0, x1]

    @test LK.leapsecs_add(tab, x0 - UInt64(1), false) == x0 - UInt64(1)
    @test LK.leapsecs_add(tab, x0, false) == x0 + UInt64(1)
    @test LK.leapsecs_add(tab, x0, true) == x0                  # `hit`: the leap second itself keeps its count
    @test LK.leapsecs_add(tab, x0 + UInt64(5), false) == x0 + UInt64(6)
    @test LK.leapsecs_add(tab, x1 + UInt64(5), false) == x1 + UInt64(7)
    @test LK.leapsecs_add(_NOLEAP, x1, false) == x1

    @test LK.leapsecs_sub(tab, x0 - UInt64(1)) == (x0 - UInt64(1), 0)
    @test LK.leapsecs_sub(tab, x0) == (x0 - UInt64(1), 1)       # a leap second: the flag is 1
    @test LK.leapsecs_sub(tab, x0 + UInt64(6)) == (x0 + UInt64(5), 0)
    @test LK.leapsecs_sub(tab, x1 + UInt64(7)) == (x1 + UInt64(5), 0)
    @test LK.leapsecs_sub(_NOLEAP, x1) == (x1, 0)

    # the host's table is read through leapsecs_init: a vector of ascending counts (empty on most hosts)
    host = LK.leapsecs_init()
    @test issorted(host)

    # a leap second is the 60th second of its minute through the calendar functions
    ct = LK.caltime()
    LK.caltime_utc(ct, x0, tab)
    @test ct.second == 60
    @test LK.caltime_tai(ct, tab) == x0
end
