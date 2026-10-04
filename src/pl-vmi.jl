# UPSTREAM: swipl-devel src/pl-vmi.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-codetable.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE VIRTUAL MACHINE INSTRUCTIONS the kernel compiles clause heads to — the subset of SWI-Prolog's
# pl-vmi.c that src/pl-comp.jl emits, with the operand counts of upstream's `VMI(name, flags,
# argc, argtypes)` declarations. Only the declarations are ported; the instructions' bodies (head
# unification) arrive with the VM. Upstream numbers instructions by their order in pl-vmi.c;
# these numbers keep that order but are the kernel's own.
#
# NOT EMITTED, so not declared: H_SMALLINTW (only where a code word is narrower than a word,
# `CODES_PER_WORD > 1`: on 64-bit swipl every tagged integer is an `H_SMALLINT`, probed in 10.1.16),
# and the SSU instructions (`=>` clauses are not compiled yet).
#
# OPERANDS (V1, L1): the literal instructions `H_SMALLINT`, `H_FLOAT`, `H_MPZ`, `H_MPQ` and `H_STRING` carry ONE
# operand — the value's index key, as `H_ATOM` does — where upstream carries the value itself (an
# integer, `CODES_PER_DOUBLE` words, a `VM_DYNARGC` block). L2's per-clause literal table (decision 2)
# replaces every such operand; the index keys stay what they are.

# PORT: pl-vmi.c I_NOP
"No operation (pl-vmi.c)."
const I_NOP = code(0)
# PORT: pl-vmi.c H_ATOM
"Head: unify the argument with an atom; operand: the atom word (pl-vmi.c)."
const H_ATOM = code(1)
# PORT: pl-vmi.c H_SMALLINT
"Head: unify with a TAGGED integer (pl-vmi.c); operand: its index key (until L2's literal table)."
const H_SMALLINT = code(2)
# PORT: pl-vmi.c H_NIL
"Head: unify the argument with SWI-7's `[]`, the reserved symbol; no operand (pl-vmi.c)."
const H_NIL = code(3)
# PORT: pl-vmi.c H_FLOAT
"Head: unify with a float (pl-vmi.c); operand: its index key (until L2's literal table)."
const H_FLOAT = code(4)
# PORT: pl-vmi.c H_MPZ
"Head: unify with an integer that is not tagged (pl-vmi.c); operand: its index key (until L2)."
const H_MPZ = code(5)
# PORT: pl-vmi.c H_MPQ
"Head: unify with a rational that is not an integer (pl-vmi.c); operand: its index key (until L2)."
const H_MPQ = code(6)
# PORT: pl-vmi.c H_STRING
"Head: unify with a string (pl-vmi.c); operand: its index key (until L2's literal table)."
const H_STRING = code(7)
# PORT: pl-vmi.c H_VOID
"Head: skip an argument that is a singleton variable (pl-vmi.c)."
const H_VOID = code(8)
# PORT: pl-vmi.c H_VOID_N
"Head: skip that many void arguments; operand: the count (pl-vmi.c)."
const H_VOID_N = code(9)
# PORT: pl-vmi.c H_VAR
"Head: unify the argument with a variable seen before; operand: its frame slot (pl-vmi.c)."
const H_VAR = code(10)
# PORT: pl-vmi.c H_FIRSTVAR
"Head: the first occurrence of a variable inside a compound; operand: its slot (pl-vmi.c)."
const H_FIRSTVAR = code(11)
# PORT: pl-vmi.c H_FUNCTOR
"Head: unify with a compound and enter its arguments; operand: the functor word (pl-vmi.c)."
const H_FUNCTOR = code(12)
# PORT: pl-vmi.c H_RFUNCTOR
"Head: as `H_FUNCTOR`, for the LAST argument of a compound — no `H_POP` of its own (pl-vmi.c)."
const H_RFUNCTOR = code(13)
# PORT: pl-vmi.c H_LIST
"Head: as `H_FUNCTOR` for a list cell `'[|]'/2` (`FUNCTOR_dot2`); no operand (pl-vmi.c)."
const H_LIST = code(14)
# PORT: pl-vmi.c H_RLIST
"Head: as `H_RFUNCTOR` for a list cell `'[|]'/2`; no operand (pl-vmi.c)."
const H_RLIST = code(15)
# PORT: pl-vmi.c H_POP
"Head: leave the arguments of a compound (pl-vmi.c)."
const H_POP = code(16)
# PORT: pl-vmi.c H_LIST_FF
"Head: a list cell `[X|Y]` of two first-occurrence variables; operands: their two slots (pl-vmi.c)."
const H_LIST_FF = code(17)
# PORT: pl-vmi.c I_CHP
"Create a choice point for an SSU clause (pl-vmi.c)."
const I_CHP = code(18)
# PORT: pl-vmi.c I_ENTER
"End of the head of a rule: enter the body (pl-vmi.c)."
const I_ENTER = code(19)
# PORT: pl-vmi.c I_EXITFACT
"End of a fact (pl-vmi.c)."
const I_EXITFACT = code(20)

# PORT: pl-incl.h code_info
"What `codeTable` records of an instruction: its name and number of operand words (pl-incl.h)."
struct code_info
    name::Symbol
    arguments::Int
end

# PORT: pl-codetable.c codeTable
# DIVERGES: a function over the declared subset instead of the array upstream generates from the
# `VMI()` declarations.
"The `code_info` of instruction `op` (pl-codetable.c `codeTable[op]`)."
function codeTable(op::code)::code_info
    op == I_NOP && return code_info(:I_NOP, 0)
    op == H_ATOM && return code_info(:H_ATOM, 1)
    op == H_SMALLINT && return code_info(:H_SMALLINT, 1)
    op == H_NIL && return code_info(:H_NIL, 0)
    op == H_FLOAT && return code_info(:H_FLOAT, 1)
    op == H_MPZ && return code_info(:H_MPZ, 1)
    op == H_MPQ && return code_info(:H_MPQ, 1)
    op == H_STRING && return code_info(:H_STRING, 1)
    op == H_VOID && return code_info(:H_VOID, 0)
    op == H_VOID_N && return code_info(:H_VOID_N, 1)
    op == H_VAR && return code_info(:H_VAR, 1)
    op == H_FIRSTVAR && return code_info(:H_FIRSTVAR, 1)
    op == H_FUNCTOR && return code_info(:H_FUNCTOR, 1)
    op == H_RFUNCTOR && return code_info(:H_RFUNCTOR, 1)
    op == H_LIST && return code_info(:H_LIST, 0)
    op == H_RLIST && return code_info(:H_RLIST, 0)
    op == H_POP && return code_info(:H_POP, 0)
    op == H_LIST_FF && return code_info(:H_LIST_FF, 2)
    op == I_CHP && return code_info(:I_CHP, 0)
    op == I_ENTER && return code_info(:I_ENTER, 0)
    op == I_EXITFACT && return code_info(:I_EXITFACT, 0)
    error("codeTable: $op is not a declared instruction")
end
