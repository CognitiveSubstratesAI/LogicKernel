# ORIGINAL: chooses which implementation of the term interface a term-generic test file runs on; Prolog has one term representation.
# test/term_under_test.jl — the term implementation under test, for a TERM-GENERIC test file.
#
# A test that reaches the kernel only through the term interface is TERM-GENERIC: it must pass on
# EVERY implementation, not only on the one it was written against — otherwise the interface is
# whatever that one implementation happens to do. Such a file starts with
#
#     include(joinpath(@__DIR__, "..", "term_under_test.jl"))
#     const _UT = lk_term_type(Union{Int64, Float64, String})    # the payload the file needs
#
# and builds and reads terms only with `lk_sym`/`lk_gnd`/`lk_var`/`lk_name`/`lk_value` and the
# interface itself. test/runtests.jl finds such files BY THAT INCLUDE and runs each once per
# implementation in `LK_TERM_IMPLS`, setting LOGICKERNEL_TERM. Run alone, a file reads the same
# variable, default `reference`:
#
#     LOGICKERNEL_TERM=alt tools/run_tests.sh test/core_lang/test_unify.jl
#
# The implementations: `reference` — `Term{G}` (src/default_term.jl), for the payload `G` the file
# asks for; `alt` — `AltTerm{false}` (test/core_lang/alt_term.jl), deliberately unlike it, which
# takes any payload; `alt_interned` — `AltTerm{true}`, which also SHARES ground compounds, as SWI's
# `copy_term/2` shares ground subterms (pl-copyterm.c). A file that is NOT term-generic (it tests one type's own behaviour, like
# test/core_lang/test_default_term.jl) does not include this.
using LogicKernel

const LK_TERM_IMPLS = ("reference", "alt", "alt_interned")
const LK_TERM_IMPL = get(ENV, "LOGICKERNEL_TERM", "reference")
LK_TERM_IMPL in LK_TERM_IMPLS || error(
    "LOGICKERNEL_TERM=$(repr(LK_TERM_IMPL)): expected one of $(join(LK_TERM_IMPLS, ", "))"
)

isdefined(Main, :LKAltTerm) ||
    Base.include(Main, joinpath(@__DIR__, "core_lang", "alt_term.jl"))
using Main.LKAltTerm: AltTerm, alt_sym, alt_gnd, alt_var, alt_name, alt_value

"The term type under test, for a file whose grounded payload is `G`."
lk_term_type(::Type{G}) where {G} =
    if LK_TERM_IMPL == "reference"
        Term{G}
    else
        AltTerm{LK_TERM_IMPL == "alt_interned"}
    end

"The symbol `name`."
lk_sym(::Type{Term{G}}, name::Symbol) where {G} = sym_term(Term{G}, name)
lk_sym(::Type{AltTerm{H}}, name::Symbol) where {H} = alt_sym(AltTerm{H}, name)

"The grounded value `v`."
lk_gnd(::Type{Term{G}}, v) where {G} = gnd_term(Term{G}, v)
lk_gnd(::Type{AltTerm{H}}, v) where {H} = alt_gnd(AltTerm{H}, v)

"A CALLER's variable — checked: keys at or above `KERNEL_VAR_BASE` are the kernel's."
lk_var(::Type{Term{G}}, key::UInt64) where {G} = var_term(Term{G}, key)
lk_var(::Type{AltTerm{H}}, key::UInt64) where {H} = alt_var(AltTerm{H}, key)

"The name of a symbol."
lk_name(t::Term) = sym_name(t)
lk_name(t::AltTerm) = alt_name(t)

"The host value of a grounded term."
lk_value(t::Term) = gnd_value(t)
lk_value(t::AltTerm) = alt_value(t)

"""
A symbol's Prolog text as `writeq` writes it: the reserved `[]` bare; a text atom bare when it is a
plain lowercase identifier, otherwise quoted — so the TEXT atom `'[]'` is written quoted, and swipl
reads the two apart. Every swipl differential writes symbols through this.
"""
function lk_atom_text(t)::String
    n = String(lk_name(t))
    if is_reserved_symbol(t)
        is_nil(t) || error("lk_atom_text: no Prolog text for the reserved symbol $n")
        return "[]"
    end
    occursin(r"^[a-z][A-Za-z0-9_]*$", n) && return n
    return "'" * replace(n, "\\" => "\\\\", "'" => "\\'") * "'"
end

"""
`==/2`: two terms are identical in the standard order (`compareStandard(a, b, true) == 0`), and two
vectors of terms elementwise. A term-generic test compares terms with this, never with Base `==`,
which is the reference type's own convenience — `AltTerm`'s throws.
"""
lk_eq(a, b)::Bool = compareStandard(a, b, true) == 0

# The variables bound in an engine: every global cell up to `gTop` that is not 0 (since L1b stage C2 a
# cell is a word, 0 when unbound) — a variable's binding, and the cells of every compound laid out — but
# a value table's box, which is not a variable (`_is_box`). Until f3-3 also the keyed variables' entries
# in the binding store, and a cell was told by its key (`gkey`); every position up to `gTop` that is not a
# box is a cell (`allocGlobalCells!`), so the count is the same.
lk_bound_count(ld)::Int =
    count(p -> ld.gstack[p] != 0 && !LogicKernel._is_box(ld, p), 1:(ld.gTop))
lk_no_bindings(ld)::Bool = lk_bound_count(ld) == 0
# The same, OUTSIDE the frozen region (L1e e5a; audit D-0036): a ball raised outside any query keeps its
# cells below `frozen_bar` until the outermost query's close (upstream: until GC — pl-gvar.c resets the bar
# only at the thread's end). Those cells are the ball, not a leak; a binding above the bar is.
lk_bound_count_unfrozen(ld)::Int =
    count(
        p -> ld.gstack[p] != 0 && !LogicKernel._is_box(ld, p), (ld.frozen_bar + 1):(ld.gTop)
    )
lk_no_bindings_unfrozen(ld)::Bool = lk_bound_count_unfrozen(ld) == 0

# THE ANSWER, as a test reads it (f3-2, audit D-0111 Q5): the value a term reference holds, read off the
# cells once (`export_cells`, f3a's reader) — the one way a test reads an answer, since `slotValue` and
# `resolve_term` go with the keyed variables in f3. An unbound cell comes back as a variable of the
# export: sharing WITHIN one read is kept, and `lk_answers` reads several references with ONE export, so
# a variable shared between them comes back shared. (A caller's own variable is not handed back: the
# answer's variables are the export's — SWI's interface, where the caller holds term references.)
"The value term reference `t` holds, read off the cells (one export)."
lk_answer(ld::LogicKernel.PL_local_data{T}, t::Int) where {T} =
    LogicKernel.export_cells(ld, LogicKernel.cell_export{T}(), -(t + 1))
"The values of the term references `ts`, read off the cells with ONE export (shared variables stay shared)."
function lk_answers(ld::LogicKernel.PL_local_data{T}, ts::Int...)::Vector{T} where {T}
    ex = LogicKernel.cell_export{T}()
    return T[LogicKernel.export_cells(ld, ex, -(t + 1)) for t in ts]
end

# A slot's side value (`SLOT_VALUE`; f3-1, Q1 (b)): since f3 only a grounded value, read as its side word.
# (Until f3-3 the tests of the boundary also stored a KEYED variable here, and `lk_boundary_word!` laid a
# keyed variable's value-table word in a cell; both went with the keyed variables.)
"Store `v` in slot `s` as the slot's own side value (`SLOT_VALUE`): a grounded value since f3."
function lk_side_value!(ld, s::Int, v)
    ld.slot_values[s] = v
    ld.slots[s] = LogicKernel.SLOT_VALUE
    return nothing
end
lk_eq(a::AbstractVector, b::AbstractVector)::Bool =
    length(a) == length(b) && all(((x, y),) -> lk_eq(x, y), zip(a, b))

# THE LOAD'S MESSAGES, as a test reads them (LB4 b2, D-0286 LQ7): `load_file!` returns `(status, ball)` and the
# messages are print_message/2's, so a test collects them with a `user:message_hook/3` clause, loaded from a
# file of its own before the file under test: every `error` and `warning` message is recorded (the hook
# succeeds, so it is not printed) as `user:'$lk_message'(Kind, Term)`, then read back in order and retracted.
# The other kinds (`silent`, `informational`, …) go to print_message/2's own printing, as in swipl.
const LK_MESSAGE_COLLECTOR = """
:- dynamic('\$lk_message'/2).
message_hook(Term, Kind, _Lines) :-
    ( Kind == error ; Kind == warning ),
    assertz('\$lk_message'(Kind, Term)).
"""
# The same collector, failing after the record (as the swipl drivers' hooks that end in `fail`), so
# print_message/2 still prints the message to user_error, as in swipl.
const LK_MESSAGE_COLLECTOR_PRINTING = replace(
    LK_MESSAGE_COLLECTOR, "(Kind, Term))." => "(Kind, Term)),\n    fail."
)
"""
Install the `user:message_hook/3` collector of [`LK_MESSAGE_COLLECTOR`](@ref) on the database of `ld`, once
(loaded with `load_file!` from a file of its own); `printing=true` installs
[`LK_MESSAGE_COLLECTOR_PRINTING`](@ref) instead (the message is recorded AND printed). `kinds` names the message kinds recorded (default `error` and
`warning`; `(:silent,)` for the `debug_mode(_)` messages, `(:informational,)` for `unwind(abort)`).
"""
function lk_install_message_collector!(
    gd::LogicKernel.PL_global_data{T}, ld::LogicKernel.PL_local_data{T};
    printing::Bool=false,
    kinds::Tuple{Vararg{Symbol}}=(:error, :warning)
)::Nothing where {T}
    m = LogicKernel.mk_sym(T, Symbol("\$lk_message"))
    if LogicKernel.isCurrentProcedure(
        LogicKernel.sym_key(m), 2, LogicKernel.MODULE_user(gd)
    ) === nothing
        hook = tempname() * "_lk_message_collector.pl"     # once per database
        text = printing ? LK_MESSAGE_COLLECTOR_PRINTING : LK_MESSAGE_COLLECTOR
        kinds == (:error, :warning) ||
            (
                text = replace(
                    text,
                    "( Kind == error ; Kind == warning )" =>
                        "( " * join(("Kind == $k" for k in kinds), " ; ") * " )"
                )
            )
        write(hook, text)
        hst, hball = LogicKernel.load_file!(gd, ld, hook)
        rm(hook; force=true)
        hst === :ok ||
            error("lk_install_message_collector!: the collector did not load: $hst $hball")
    end
    return nothing
end

"""
The `(kind, term)` pairs the collector recorded since the last call, in the order they were printed;
they are retracted. The collector must be installed ([`lk_install_message_collector!`](@ref)).
"""
function lk_take_messages!(
    ld::LogicKernel.PL_local_data{T}
)::Vector{Tuple{Symbol, T}} where {T}
    m = LogicKernel.mk_sym(T, Symbol("\$lk_message"))
    q = LogicKernel.mk_expr(T, T[m, lk_var(T, UInt64(1)), lk_var(T, UInt64(2))])
    qual(g) = LogicKernel.mk_expr(
        T, T[LogicKernel.mk_sym(T, :(:)), LogicKernel.mk_sym(T, :user), g]
    )
    msgs = Tuple{Symbol, T}[
        (lk_name(LogicKernel.child(a, 2)), LogicKernel.child(a, 3)) for a in
        (LogicKernel.child(r, 3) for r in LogicKernel.query_answers(ld, qual(q)))
    ]
    retract = LogicKernel.mk_expr(T, T[LogicKernel.mk_sym(T, :retractall), q])
    LogicKernel.query_answers(ld, qual(retract); limit=1)
    return msgs
end

"""
Load `path` with `load_file!` and collect its `error` and `warning` messages through a `user:message_hook/3`
collector: `(status, ball, msgs)`, `msgs` the `(kind, term)` pairs in the order they were printed.
"""
function lk_load_file_messages!(
    gd::LogicKernel.PL_global_data{T}, ld::LogicKernel.PL_local_data{T},
    path::AbstractString
) where {T}
    lk_install_message_collector!(gd, ld)
    lk_take_messages!(ld)                                   # earlier messages are not this load's
    st, ball = LogicKernel.load_file!(gd, ld, path)
    return (st, ball, lk_take_messages!(ld))
end
