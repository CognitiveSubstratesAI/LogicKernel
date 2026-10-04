# ORIGINAL: renders compiled code for the live differentials against swipl's vm_list; upstream compares SWI with itself and needs none.
# test/compile/code_testlib.jl — included by test_head_code_swipl.jl and
# test_analyse_variables_swipl.jl. Not a test file itself: runtests.jl runs `test_*.jl` only.
# TERM-GENERIC: it reads terms with test/term_under_test.jl's `lk_*` functions, which the including
# file must have included, with `LK` bound to LogicKernel.
#
# BOTH SIDES WRITE AN INSTRUCTION THE SAME WAY: its name, then the operands where both systems mean
# the same thing — `h_void_n(N)` its count, `h_var(N)`/`h_firstvar(N)` the frame slot, `h_list_ff`'s
# two slots — every LITERAL by value (atoms and strings by their codes, integers and rationals by
# value, floats by their bits) and every functor by name and arity. The kernel's literal-table
# INDICES, like swipl's atom handles, are each system's own and never compared.

"A text as a code list, as swipl's `atom_codes`/`string_codes` print it: `[97,98]`."
_hcps(s::AbstractString)::String = "[" * join((Int(c) for c in s), ",") * "]"
"An atom operand, by value."
_ha(s::AbstractString)::String = "a:" * _hcps(s)
"A functor operand, by value: name and arity."
_hF(s::AbstractString, n::Int)::String = "F:" * _hcps(s) * "/$n"
"A float operand, by value: its BITS (so -0.0 and 0.0 differ, and the text form cannot matter)."
_hf(x::Float64)::String = "f:" * string(reinterpret(UInt64, x); base=16)

"""
A literal by VALUE, as both sides write it: its kind, then its value — an atom's or string's
codes, an integer's digits, a rational's numerator and denominator, a float's bits.
"""
function _hlit(t)::String
    kind(t) === SYM && return _ha(String(lk_name(t)))
    k = number_kind(t)
    k === NUM_INTEGER &&
        return "i:" * string(integer_is_int64(t) ? int64_value(t) : bigint_value(t))
    if k === NUM_RATIONAL
        r = rational_value(t)
        return "q:$(numerator(r))/$(denominator(r))"
    end
    k === NUM_FLOAT && return _hf(float_value(t))
    k === NUM_STRING && return "s:" * _hcps(string_value(t))
    error("_hlit: no SWI literal for $(ix_text(t))")
end

"""
The kernel's code `codes` (with the literal table `literals` its operands index), one string per
instruction: its name, with the operands where both systems mean the same thing (see the header).
"""
function _hcode_of(codes::Vector{UInt64}, literals::Vector{T})::Vector{String} where {T}
    out = String[]
    pc = LK.Code{T}(codes, literals, 1)
    while pc.pc <= length(codes)
        op = LK.decode(pc)
        name = lowercase(String(LK.codeTable(op).name))
        if op == LK.H_VOID_N
            push!(out, "$name($(codes[pc.pc + 1]))")
        elseif op == LK.H_VAR || op == LK.H_FIRSTVAR
            push!(out, "$name($(Int(codes[pc.pc + 1] - LK.VAROFFSET(0))))")
        elseif op == LK.H_LIST_FF
            s1, s2 = (Int(codes[pc.pc + i] - LK.VAROFFSET(0)) for i in 1:2)
            push!(out, "$name($s1,$s2)")
        elseif op == LK.H_FUNCTOR || op == LK.H_RFUNCTOR
            w = codes[pc.pc + 1]
            i = LK.functor_literal(w)
            f = i == 0 ? "\$expr" : String(lk_name(literals[i]))
            push!(out, "$name($(_hF(f, LK.functor_arity(w))))")
        elseif op in (LK.H_ATOM, LK.H_SMALLINT, LK.H_MPZ, LK.H_MPQ, LK.H_FLOAT, LK.H_STRING)
            push!(out, "$name($(_hlit(literals[codes[pc.pc + 1]])))")
        else
            push!(out, name)
        end
        pc = LK.stepPC(pc)
    end
    return out
end

# The swipl side: an instruction TERM (from `vm_list`'s text read back by `term_string`, or from
# library(vm)'s `clause_vm/2`) written as `_hcode_of` writes the kernel's — floats in their shortest
# round-trip form (`~h`, whose bits Julia compares, `_hswipl_floats`).
const _HSWIPL_OPS = raw"""
hc_render(I, Out) :-
    I =.. [N|As],
    (   As == [] -> Out = N
    ;   maplist(hc_op(N), As, Ts), atomic_list_concat(Ts, ',', J),
        format(atom(Out), "~w(~w)", [N, J])
    ).
hc_op(N, X, S) :- memberchk(N, [h_void_n, h_var, h_firstvar, h_list_ff]), !, format(string(S), "~w", [X]).
hc_op(_, X, S) :- atom(X), !, atom_codes(X, C), format(string(S), "a:~w", [C]).
hc_op(_, X, S) :- integer(X), !, format(string(S), "i:~d", [X]).
hc_op(_, X, S) :- rational(X, P, Q), !, format(string(S), "q:~d/~d", [P, Q]).
hc_op(_, X, S) :- float(X), !, format(string(S), "f:~h", [X]).
hc_op(_, X, S) :- string(X), !, string_codes(X, C), format(string(S), "s:~w", [C]).
hc_op(_, F/A, S) :- atom(F), integer(A), !, atom_codes(F, C), format(string(S), "F:~w/~d", [C, A]).
hc_op(_, X, S) :- format(string(S), "?:~q", [X]).
"""

"swipl's `~h` text of a float, as `_hf` writes the kernel's: by its bits."
function _hswipl_float(s::AbstractString)::String
    x = if s == "1.0Inf"
        Inf
    elseif s == "-1.0Inf"
        -Inf
    elseif endswith(s, "NaN")
        NaN
    else
        parse(Float64, s)
    end
    return _hf(x)
end

"A line `hc_render` wrote, its floats by their bits (`_hswipl_float`)."
_hswipl_floats(l::AbstractString)::String =
    replace(l, r"f:([^,)]+)" => m -> _hswipl_float(m[3:end]))
