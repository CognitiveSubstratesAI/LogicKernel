# ORIGINAL: LB4 b2's T4 gate, the boot messages (loader_boot design H1 and LD12) — upstream's boot compilation is the command src/CMakeLists.txt:357-361 runs (`swipl --home=HOME -q -O -o boot.prc -b HOME/boot/init.pl`); swipl-devel has no test of its boot's output.
# test/db/test_boot_messages_swipl.jl — T4, THE BOOT MESSAGES (H1: a directive of a boot file that fails or raises is
# printed and the boot goes on, pl-qlf.c:4750 and init.pl:3967-3969 `'$exception_in_directive'`, so a half-booted system
# still "loads"; this file is the guard):
#   * the kernel's boot, made here as `boot_global_data` (src/pl-qlf.jl) makes it — `setupProlog`, a local data of its
#     own, `boot_from_source!` over HOME/boot/init.pl — with a `user:message_hook/3` collector asserted BEFORE the boot
#     (boot/messages.pl:2516-2521 declares the hook `multifile` and `dynamic`, which keeps the clause), so every `error`
#     and `warning` message print_message/2 prints once boot/messages.pl is loaded is recorded, and the boot loop's
#     Sdprintf texts before that (`ld.messages`, src/pl-qlf.jl `_qlf_Sdprintf!`) are read too;
#   * the list must be EXACTLY `_BM_KNOWN`: swipl's boot prints nothing (ORACLE below), and each entry of `_BM_KNOWN` is
#     a KNOWN DIFFERENCE with its cause (LD12: tabling.pl's `:- table` directives need pl-wrap.c, a deferred file, D-0353
#     item 1; audit D-0286 item 5: the list only shrinks);
#   * non-vacuity: the boot ran (init.pl's `load_files/2` and boot/messages.pl's `print_message/2` are defined), and the
#     collector records a message printed after the boot (one `error`), so an empty list is not a dead hook.
# ORACLE: swipl 10.1.19-1-gcbf4e189 runs the boot command over its home (whose boot/*.pl are byte-identical to
# vendor/swipl-devel/boot/, build_home.pl aside, which the boot does not load): stdout and stderr EMPTY, exit 0, two runs
# identical (2026-11-02). With `swipl` on PATH the command is run again here and its output compared.
# DIVERGES (audit D-0354 item 3): `threads` is false in the kernel (os/pl-prologflag.c:2620-2622): the boot compiles
# the single-thread branches; no message of the oracle depends on them (the oracle prints none).
# NOT RUN when written (edit-only, LB4 b2 writer 5): `_BM_KNOWN` is filled from the first boot run (G9). UNVERIFIED on
# the kernel: gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _BM = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_bms(x) = lk_sym(_BM, Symbol(x))
_bme(f, xs::_BM...) = LK.mk_expr(_BM, _BM[_bms(f), xs...])
_bmv(i) = lk_var(_BM, UInt64(i))

const _BM_SWIPL = (get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl"))

# ONE encoding for every message (the read differential's, as test/files/test_load_swipl.jl's `_tl_enc`)
function _bm_enc(t::_BM, seen::Vector{UInt64}=UInt64[])::String
    k = LK.kind(t)
    if k === LK.VAR
        i = findfirst(==(LK.var_key(t)), seen)
        if i === nothing
            push!(seen, LK.var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === LK.SYM
        LK.is_nil(t) && return "nil"
        return "a" * _bm_codes(LK.sym_text(t))
    elseif k === LK.GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _bm_codes(String(v))
        v isa Integer && return "i$v"
        return "?$(typeof(v))"
    end
    h = LK.child(t, 1)
    hs = LK.is_nil(h) ? "c[]" : "c" * _bm_codes(LK.sym_text(h))
    return hs * "/$(LK.nchildren(t) - 1)(" * join([_bm_enc(LK.child(t, i), seen) for i in 2:LK.nchildren(t)], ",") * ")"
end
_bm_codes(s::String)::String = "[" * join(Int.(collect(s)), ",") * "]"
_bm_line(kind::Symbol, t::_BM)::String = string(kind) * " " * _bm_enc(t)

# THE KNOWN DIFFERENCES: each boot message the kernel prints where swipl prints none, `_bm_line`'s text, with its cause.
# Filled from the first boot run (G9); empty until then. UNVERIFIED on the kernel: gate decides.
const _BM_KNOWN = String[]

_bm_user(g::_BM)::_BM = _bme(":", _bms(:user), g)

"The kernel's boot of `T` with a `user:message_hook/3` collector: `(gd, ld, lines)`, `lines` the boot's messages."
function _bm_boot()
    gd = LK.setupProlog(_BM)
    ld = LK.PL_local_data{_BM}(gd)
    # :- dynamic '$lk_message'/2 (a clause asserted and retracted), then the hook (test/term_under_test.jl's collector)
    rec = _bme(Symbol("\$lk_message"), _bmv(1), _bmv(2))
    LK.query_answers(ld, _bm_user(_bme(:assertz, _bme(Symbol("\$lk_message"), _bms(:none), _bms(:none)))); limit=1)
    LK.query_answers(ld, _bm_user(_bme(:retractall, rec)); limit=1)
    kinds = _bme(Symbol(";"), _bme(:(==), _bmv(2), _bms(:error)), _bme(:(==), _bmv(2), _bms(:warning)))
    body = _bme(Symbol(","), kinds, _bme(:assertz, _bme(Symbol("\$lk_message"), _bmv(2), _bmv(1))))
    hook = _bme(Symbol(":-"), _bme(:message_hook, _bmv(1), _bmv(2), _bmv(3)), body)
    @test length(LK.query_answers(ld, _bm_user(_bme(:assertz, hook)); limit=1)) == 1
    home = LK.current_prolog_flag_atom(gd, LK.mk_sym(_BM, :home))
    initpl = joinpath(LK.sym_text(home), "boot", "init.pl")
    @test isfile(initpl)
    @test LK.boot_from_source!(gd, ld, [initpl])
    lines = String[_bm_line(k, m) for (k, m) in ld.messages]
    append!(lines, String[_bm_line(k, m) for (k, m) in lk_take_messages!(ld)])
    return gd, ld, lines
end

@testset "T4: the boot's messages are EXACTLY the pinned known differences (H1, LD12)" begin
    gd, ld, lines = _bm_boot()
    # non-vacuity: the boot ran ...
    for (m, name, arity) in ((LK.MODULE_system(gd), :load_files, 2),)
        proc = LK.isCurrentProcedure(LK.sym_key(_bms(name)), arity, m)
        @test proc !== nothing && LK.isDefinedProcedure(gd, proc)
    end
    msgs = LK.isCurrentProcedure(LK.sym_key(_bms(:print_message)), 2, LK.MODULE_system(gd))
    @test msgs !== nothing && LK.isDefinedProcedure(gd, msgs)
    # ... and the collector is live after it (one error printed, one recorded)
    pm = _bme(:print_message, _bms(:error), _bme(:format, lk_gnd(_BM, "lk boot message probe"), LK.mk_nil(_BM)))
    LK.query_answers(ld, _bm_user(pm); limit=1)
    probe = lk_take_messages!(ld)
    @test length(probe) == 1 && probe[1][1] === :error
    # THE GUARD: the boot's messages, in order, are the pinned list. UNVERIFIED on the kernel: gate decides.
    @test lines == _BM_KNOWN
end

@testset "T4 oracle: swipl's boot command prints nothing" begin
    if _BM_SWIPL === nothing
        @test_skip "swipl not on PATH (the pin: empty output, exit 0)"
    else
        home = readchomp(`$(_BM_SWIPL) --dump-runtime-variables=sh`)
        m = match(r"PLBASE=\"([^\"]*)\"", home)
        @test m !== nothing
        plbase = String(m.captures[1])
        out = mktempdir()
        prc = joinpath(out, "boot.prc")
        log = joinpath(out, "boot.log")
        cmd = `$(_BM_SWIPL) --home=$plbase -q -O -o $prc -b $(joinpath(plbase, "boot", "init.pl"))`
        p = run(pipeline(ignorestatus(cmd); stdout=log, stderr=log))
        @test p.exitcode == 0
        @test read(log, String) == ""                     # the oracle's boot messages: none
        @test isfile(prc)                                  # non-vacuity: the boot made its state
    end
end
