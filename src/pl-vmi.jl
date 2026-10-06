# UPSTREAM: swipl-devel src/pl-vmi.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-codetable.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE VIRTUAL MACHINE INSTRUCTIONS the kernel compiles clauses to — the subset of SWI-Prolog's
# pl-vmi.c that src/pl-comp.jl emits: the head instructions, and since V2 the body instructions of
# plain goals, the calls and the last-call (LCO) block, and since V4a the supervisors and the top
# query's `I_EXITQUERY`. Each carries upstream's `VMI(name, flags, argc, argtypes)`: its flags
# (`VIF_LCO`, `VIF_BREAK`) and its operand kinds (`CA1_*`). The BODIES are in `PL_next_solution`'s run
# loop (src/pl-wam.jl), as upstream `#include`s pl-vmi.c inside it. Upstream numbers instructions by
# their order in pl-vmi.c; these numbers keep that order up to `I_TCALL` (`B_VAR0 + index` needs the
# three consecutive) and then append, in the order the steps declared them: `I_CUT` (V2), then V4a's,
# then V5a2's deterministic foreign calls (`I_FCALLDET0 + arity` needs the eleven consecutive), then
# V6b's type tests (`I_VAR` … `I_CALLABLE`, in pl-vmi.c's order).
#
# NOT EMITTED, so not declared: H_SMALLINTW/B_SMALLINTW/L_SMALLINTW (only where a code word is
# narrower than a word, `CODES_PER_WORD > 1`: on 64-bit swipl every tagged integer is a SMALLINT,
# probed in 10.1.16); the SSU instructions; the inline built-ins (`B_UNIFY_*`, `B_EQ_*`, `B_ARG_*`),
# the meta-call (`I_CALL1`, `I_USERCALL0`, `I_CALLN`), the module calls (`I_CONTEXT`, `I_CALLM`,
# `I_DEPARTM`) and the control constructs (`C_*`, `I_TRUE`, `I_FAIL`): V9. `I_CUT` is declared and
# compiled (a clause-level `!`, user 2026-10-05) and, since V6a, executed.
#
# OPERANDS: every literal operand (`*_ATOM`, `*_SMALLINT`, `*_FLOAT`, `*_MPZ`, `*_MPQ`, `*_STRING`)
# is ONE word, the index of the literal in the clause's literal table (V1 L2), where upstream
# carries the value itself (an atom, an integer, CODES_PER_DOUBLE words, a VM_DYNARGC block); a
# functor operand is `functor_operand` (L2); a procedure operand (`CA1_LPROC`) the index of the
# procedure in the clause's procedure table (V1); a clause-reference operand (`CA1_CLAUSEREF`, the
# supervisors') the index of the clause reference in the definition's `codes_crefs` (V4a). The
# `argtype` column keeps upstream's kinds, so a
# reader decodes each operand by its kind as upstream does — a literal kind through the table.

# ── operand kinds and flags (pl-incl.h) ─────────────────────────────────────────────────────────
# PORT: pl-incl.h CA1_PROC
"Operand kind: Procedure (pl-incl.h `vm_arg_type`)."
const CA1_PROC = UInt8(1)
# PORT: pl-incl.h CA1_LPROC
"Operand kind: Procedure, stored in qlf as functor (pl-incl.h `vm_arg_type`)."
const CA1_LPROC = UInt8(2)
# PORT: pl-incl.h CA1_FUNC
"Operand kind: functor_t (pl-incl.h `vm_arg_type`)."
const CA1_FUNC = UInt8(3)
# PORT: pl-incl.h CA1_DATA
"Operand kind: word: atom or small int (pl-incl.h `vm_arg_type`)."
const CA1_DATA = UInt8(4)
# PORT: pl-incl.h CA1_INTEGER
"Operand kind: integer (casted to/from `code`) (pl-incl.h `vm_arg_type`)."
const CA1_INTEGER = UInt8(5)
# PORT: pl-incl.h CA1_WORD
"Operand kind: word value as integer (CODES_PER_WORD) (pl-incl.h `vm_arg_type`)."
const CA1_WORD = UInt8(6)
# PORT: pl-incl.h CA1_FLOAT
"Operand kind: next CODES_PER_DOUBLE are double (pl-incl.h `vm_arg_type`)."
const CA1_FLOAT = UInt8(7)
# PORT: pl-incl.h CA1_STRING
"Operand kind: inlined string (pl-incl.h `vm_arg_type`)."
const CA1_STRING = UInt8(8)
# PORT: pl-incl.h CA1_MPZ
"Operand kind: GNU mpz number (pl-incl.h `vm_arg_type`)."
const CA1_MPZ = UInt8(9)
# PORT: pl-incl.h CA1_MPQ
"Operand kind: GNU mpq number (pl-incl.h `vm_arg_type`)."
const CA1_MPQ = UInt8(10)
# PORT: pl-incl.h CA1_MODULE
"Operand kind: a module (pl-incl.h `vm_arg_type`)."
const CA1_MODULE = UInt8(11)
# PORT: pl-incl.h CA1_VAR
"Operand kind: a variable(-offset) (pl-incl.h `vm_arg_type`)."
const CA1_VAR = UInt8(12)
# PORT: pl-incl.h CA1_FVAR
"Operand kind: a variable(-offset), used as `firstvar' (pl-incl.h `vm_arg_type`)."
const CA1_FVAR = UInt8(13)
# PORT: pl-incl.h CA1_CHP
"Operand kind: ChoicePoint (also variable(-offset)) (pl-incl.h `vm_arg_type`)."
const CA1_CHP = UInt8(14)
# PORT: pl-incl.h CA1_FOREIGN
"Operand kind: Foreign function pointer (pl-incl.h `vm_arg_type`)."
const CA1_FOREIGN = UInt8(15)
# PORT: pl-incl.h CA1_CLAUSEREF
"Operand kind: Clause reference (pl-incl.h `vm_arg_type`)."
const CA1_CLAUSEREF = UInt8(16)
# PORT: pl-incl.h CA1_JUMP
"Operand kind: Instructions to skip (pl-incl.h `vm_arg_type`)."
const CA1_JUMP = UInt8(17)
# PORT: pl-incl.h CA1_AFUNC
"Operand kind: Number of arithmetic function (pl-incl.h `vm_arg_type`)."
const CA1_AFUNC = UInt8(18)
# PORT: pl-incl.h CA1_TRIE_NODE
"Operand kind: Tabling: answer trie node with delays (pl-incl.h `vm_arg_type`)."
const CA1_TRIE_NODE = UInt8(19)
# PORT: pl-incl.h VIF_BREAK
"Instruction flag: can be a breakpoint (pl-incl.h)."
const VIF_BREAK = UInt8(0x01)
# PORT: pl-incl.h VIF_LCO
"Instruction flag: `lco` can move this argument instruction into the frame (pl-incl.h)."
const VIF_LCO = UInt8(0x02)

# ── the instructions, in pl-vmi.c's order ───────────────────────────────────────────────────────
# PORT: pl-vmi.c I_NOP
"No operation (pl-vmi.c)."
const I_NOP = code(0)
# PORT: pl-vmi.c H_ATOM
"Head: unify the argument with an atom; operand: the atom's literal (pl-vmi.c)."
const H_ATOM = code(1)
# PORT: pl-vmi.c H_SMALLINT
"Head: unify with a TAGGED integer; operand: its literal (pl-vmi.c)."
const H_SMALLINT = code(2)
# PORT: pl-vmi.c H_NIL
"Head: unify the argument with SWI-7's `[]`, the reserved symbol; no operand (pl-vmi.c)."
const H_NIL = code(3)
# PORT: pl-vmi.c H_FLOAT
"Head: unify with a float; operand: its literal (pl-vmi.c)."
const H_FLOAT = code(4)
# PORT: pl-vmi.c H_MPZ
"Head: unify with an integer that is not tagged; operand: its literal (pl-vmi.c)."
const H_MPZ = code(5)
# PORT: pl-vmi.c H_MPQ
"Head: unify with a rational that is not an integer; operand: its literal (pl-vmi.c)."
const H_MPQ = code(6)
# PORT: pl-vmi.c H_STRING
"Head: unify with a string; operand: its literal (pl-vmi.c)."
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
"Head: unify with a compound and enter its arguments; operand: the functor (pl-vmi.c)."
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
# PORT: pl-vmi.c B_ATOM
"Body: put an atom in the next argument; operand: its literal (pl-vmi.c)."
const B_ATOM = code(18)
# PORT: pl-vmi.c B_SMALLINT
"Body: put a TAGGED integer; operand: its literal (pl-vmi.c)."
const B_SMALLINT = code(19)
# PORT: pl-vmi.c B_NIL
"Body: put SWI-7's `[]`; no operand (pl-vmi.c)."
const B_NIL = code(20)
# PORT: pl-vmi.c B_FLOAT
"Body: put a float; operand: its literal (pl-vmi.c)."
const B_FLOAT = code(21)
# PORT: pl-vmi.c B_MPZ
"Body: put an integer that is not tagged; operand: its literal (pl-vmi.c)."
const B_MPZ = code(22)
# PORT: pl-vmi.c B_MPQ
"Body: put a rational that is not an integer; operand: its literal (pl-vmi.c)."
const B_MPQ = code(23)
# PORT: pl-vmi.c B_STRING
"Body: put a string; operand: its literal (pl-vmi.c)."
const B_STRING = code(24)
# PORT: pl-vmi.c B_ARGVAR
"Body: a variable seen before, as an argument of a compound; operand: its slot (pl-vmi.c)."
const B_ARGVAR = code(25)
# PORT: pl-vmi.c B_VAR0
"Body: put the variable in slot 0 (pl-vmi.c)."
const B_VAR0 = code(26)
# PORT: pl-vmi.c B_VAR1
"Body: put the variable in slot 1 (pl-vmi.c)."
const B_VAR1 = code(27)
# PORT: pl-vmi.c B_VAR2
"Body: put the variable in slot 2 (pl-vmi.c)."
const B_VAR2 = code(28)
# PORT: pl-vmi.c B_VAR
"Body: put a variable seen before; operand: its slot (pl-vmi.c)."
const B_VAR = code(29)
# PORT: pl-vmi.c B_ARGFIRSTVAR
"Body: the first occurrence of a variable inside a compound; operand: its slot (pl-vmi.c)."
const B_ARGFIRSTVAR = code(30)
# PORT: pl-vmi.c B_FIRSTVAR
"Body: the first occurrence of a variable as an argument; operand: its slot (pl-vmi.c)."
const B_FIRSTVAR = code(31)
# PORT: pl-vmi.c B_VOID
"Body: put a fresh variable used nowhere else (pl-vmi.c)."
const B_VOID = code(32)
# PORT: pl-vmi.c B_FUNCTOR
"Body: build a compound and enter its arguments; operand: the functor (pl-vmi.c)."
const B_FUNCTOR = code(33)
# PORT: pl-vmi.c B_RFUNCTOR
"Body: as `B_FUNCTOR`, for the LAST argument of a compound — no `B_POP` of its own (pl-vmi.c)."
const B_RFUNCTOR = code(34)
# PORT: pl-vmi.c B_LIST
"Body: as `B_FUNCTOR` for a list cell `'[|]'/2`; no operand (pl-vmi.c)."
const B_LIST = code(35)
# PORT: pl-vmi.c B_RLIST
"Body: as `B_RFUNCTOR` for a list cell `'[|]'/2`; no operand (pl-vmi.c)."
const B_RLIST = code(36)
# PORT: pl-vmi.c B_POP
"Body: leave the arguments of a compound (pl-vmi.c)."
const B_POP = code(37)
# PORT: pl-vmi.c I_CHP
"Create a choice point for an SSU clause (pl-vmi.c)."
const I_CHP = code(38)
# PORT: pl-vmi.c I_ENTER
"End of the head of a rule: enter the body (pl-vmi.c)."
const I_ENTER = code(39)
# PORT: pl-vmi.c I_CALL
"Call a procedure; operand: its procedure (pl-vmi.c)."
const I_CALL = code(40)
# PORT: pl-vmi.c I_DEPART
"Call a procedure as the LAST goal (pl-vmi.c); operand: its procedure."
const I_DEPART = code(41)
# PORT: pl-vmi.c I_EXIT
"End of a rule (pl-vmi.c)."
const I_EXIT = code(42)
# PORT: pl-vmi.c I_EXITFACT
"End of a fact (pl-vmi.c)."
const I_EXITFACT = code(43)
# PORT: pl-vmi.c L_NOLCO
"Last call: unless the frame can be reused, skip the `L_*` block; operand: its size in code words (pl-vmi.c)."
const L_NOLCO = code(44)
# PORT: pl-vmi.c L_VAR
"Last call: copy a variable into an argument slot of the frame; operands: the slot, the variable's slot (pl-vmi.c)."
const L_VAR = code(45)
# PORT: pl-vmi.c L_VOID
"Last call: a fresh variable into an argument slot; operand: the slot (pl-vmi.c)."
const L_VOID = code(46)
# PORT: pl-vmi.c L_ATOM
"Last call: an atom into an argument slot; operands: the slot, its literal (pl-vmi.c)."
const L_ATOM = code(47)
# PORT: pl-vmi.c L_NIL
"Last call: `[]` into an argument slot; operand: the slot (pl-vmi.c)."
const L_NIL = code(48)
# PORT: pl-vmi.c L_SMALLINT
"Last call: a tagged integer into an argument slot; operands: the slot, its literal (pl-vmi.c)."
const L_SMALLINT = code(49)
# PORT: pl-vmi.c I_LCALL
"Last call reusing the frame; operand: the procedure (pl-vmi.c)."
const I_LCALL = code(50)
# PORT: pl-vmi.c I_TCALL
"Last call of the clause's own predicate, reusing the frame (pl-vmi.c)."
const I_TCALL = code(51)
# PORT: pl-vmi.c I_CUT
"Cut: discard the choice points created since the clause was entered (pl-vmi.c)."
const I_CUT = code(52)
# PORT: pl-vmi.c I_EXITQUERY
"The one instruction of the top clause: return an answer from `PL_next_solution` (pl-vmi.c)."
const I_EXITQUERY = code(53)
# PORT: pl-vmi.c S_VIRGIN
"Supervisor: install the predicate's real supervisor and run it (pl-vmi.c)."
const S_VIRGIN = code(54)
# PORT: pl-vmi.c S_UNDEF
"Supervisor of a predicate with no clauses: the unknown-procedure path (pl-vmi.c; executed in V5)."
const S_UNDEF = code(55)
# PORT: pl-vmi.c S_STATIC
"Supervisor: select the first matching clause through the index, leaving a choice point (pl-vmi.c)."
const S_STATIC = code(56)
# PORT: pl-vmi.c S_DYNAMIC
"Supervisor of a dynamic predicate: `S_STATIC` (pl-vmi.c)."
const S_DYNAMIC = code(57)
# PORT: pl-vmi.c S_MULTIFILE
"Supervisor of a multifile predicate: `S_STATIC` (pl-vmi.c)."
const S_MULTIFILE = code(58)
# PORT: pl-vmi.c S_TRUSTME
"Supervisor of a predicate with one clause: run it; operand: the clause reference (pl-vmi.c)."
const S_TRUSTME = code(59)
# PORT: pl-vmi.c S_LIST
"Supervisor of a `[]`/`[_|_]` pair: run the clause the argument selects; operands: the argument, the two clause references (pl-vmi.c)."
const S_LIST = code(60)
# PORT: pl-vmi.c I_FCALLDETVA
"Call a deterministic foreign predicate with the `t0, ac, ctx` convention; operand: its index (pl-vmi.c)."
const I_FCALLDETVA = code(61)
# PORT: pl-vmi.c I_FCALLDET0
"Call a deterministic foreign predicate of 0 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET0 = code(62)
# PORT: pl-vmi.c I_FCALLDET1
"Call a deterministic foreign predicate of 1 argument, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET1 = code(63)
# PORT: pl-vmi.c I_FCALLDET2
"Call a deterministic foreign predicate of 2 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET2 = code(64)
# PORT: pl-vmi.c I_FCALLDET3
"Call a deterministic foreign predicate of 3 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET3 = code(65)
# PORT: pl-vmi.c I_FCALLDET4
"Call a deterministic foreign predicate of 4 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET4 = code(66)
# PORT: pl-vmi.c I_FCALLDET5
"Call a deterministic foreign predicate of 5 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET5 = code(67)
# PORT: pl-vmi.c I_FCALLDET6
"Call a deterministic foreign predicate of 6 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET6 = code(68)
# PORT: pl-vmi.c I_FCALLDET7
"Call a deterministic foreign predicate of 7 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET7 = code(69)
# PORT: pl-vmi.c I_FCALLDET8
"Call a deterministic foreign predicate of 8 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET8 = code(70)
# PORT: pl-vmi.c I_FCALLDET9
"Call a deterministic foreign predicate of 9 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET9 = code(71)
# PORT: pl-vmi.c I_FCALLDET10
"Call a deterministic foreign predicate of 10 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLDET10 = code(72)
# PORT: pl-vmi.c I_FEXITDET
"After a deterministic foreign call — never executed: the calls jump to its helper (pl-vmi.c)."
const I_FEXITDET = code(73)
# PORT: pl-vmi.c I_VAR
"`var/1` inline: continue if the variable at the operand's offset is an unbound variable, else fail (pl-vmi.c)."
const I_VAR = code(74)
# PORT: pl-vmi.c I_NONVAR
"`nonvar/1` inline: continue if the variable at the operand's offset is not an unbound variable, else fail (pl-vmi.c)."
const I_NONVAR = code(75)
# PORT: pl-vmi.c I_INTEGER
"`integer/1` inline: continue if the variable at the operand's offset is an integer, else fail (pl-vmi.c)."
const I_INTEGER = code(76)
# PORT: pl-vmi.c I_RATIONAL
"`rational/1` inline: continue if the variable at the operand's offset is a rational number, else fail (pl-vmi.c)."
const I_RATIONAL = code(77)
# PORT: pl-vmi.c I_FLOAT
"`float/1` inline: continue if the variable at the operand's offset is a float, else fail (pl-vmi.c)."
const I_FLOAT = code(78)
# PORT: pl-vmi.c I_NUMBER
"`number/1` inline: continue if the variable at the operand's offset is a number, else fail (pl-vmi.c)."
const I_NUMBER = code(79)
# PORT: pl-vmi.c I_ATOMIC
"`atomic/1` inline: continue if the variable at the operand's offset is atomic, else fail (pl-vmi.c)."
const I_ATOMIC = code(80)
# PORT: pl-vmi.c I_ATOM
"`atom/1` inline: continue if the variable at the operand's offset is a text atom, else fail (pl-vmi.c)."
const I_ATOM = code(81)
# PORT: pl-vmi.c I_STRING
"`string/1` inline: continue if the variable at the operand's offset is a string, else fail (pl-vmi.c)."
const I_STRING = code(82)
# PORT: pl-vmi.c I_COMPOUND
"`compound/1` inline: continue if the variable at the operand's offset is a compound, else fail (pl-vmi.c)."
const I_COMPOUND = code(83)
# PORT: pl-vmi.c I_CALLABLE
"`callable/1` inline: continue if the variable at the operand's offset is callable, else fail (pl-vmi.c)."
const I_CALLABLE = code(84)

# PORT: pl-incl.h code_info
# DIVERGES: `arguments` counts the kernel's operand WORDS (a literal is one, see above); `argtype`
# is padded with 0 to four kinds (upstream's VM_ARGC).
"What `codeTable` records of an instruction: its name, flags (`VIF_*`), operand words and operand kinds (pl-incl.h)."
struct code_info
    name::Symbol                    # name of the code
    flags::UInt8                    # Addional flags (VIF_*)
    arguments::Int                  # #args code takes
    argtype::NTuple{4, UInt8}       # Argument type(s) code takes
end

# the table `codeTable` reads, indexed by opcode + 1 (pl-codetable.c's array) — a comment, not a
# docstring, as for every module-level constant the global-state lint reads
const _CODE_TABLE = (
    code_info(:I_NOP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:H_ATOM, 0x00, 1, (CA1_DATA, 0x00, 0x00, 0x00)),
    code_info(:H_SMALLINT, 0x00, 1, (CA1_INTEGER, 0x00, 0x00, 0x00)),
    code_info(:H_NIL, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:H_FLOAT, 0x00, 1, (CA1_FLOAT, 0x00, 0x00, 0x00)),
    code_info(:H_MPZ, 0x00, 1, (CA1_MPZ, 0x00, 0x00, 0x00)),
    code_info(:H_MPQ, 0x00, 1, (CA1_MPQ, 0x00, 0x00, 0x00)),
    code_info(:H_STRING, 0x00, 1, (CA1_STRING, 0x00, 0x00, 0x00)),
    code_info(:H_VOID, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:H_VOID_N, 0x00, 1, (CA1_INTEGER, 0x00, 0x00, 0x00)),
    code_info(:H_VAR, 0x00, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:H_FIRSTVAR, 0x00, 1, (CA1_FVAR, 0x00, 0x00, 0x00)),
    code_info(:H_FUNCTOR, 0x00, 1, (CA1_FUNC, 0x00, 0x00, 0x00)),
    code_info(:H_RFUNCTOR, 0x00, 1, (CA1_FUNC, 0x00, 0x00, 0x00)),
    code_info(:H_LIST, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:H_RLIST, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:H_POP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:H_LIST_FF, 0x00, 2, (CA1_FVAR, CA1_FVAR, 0x00, 0x00)),
    code_info(:B_ATOM, VIF_LCO, 1, (CA1_DATA, 0x00, 0x00, 0x00)),
    code_info(:B_SMALLINT, VIF_LCO, 1, (CA1_INTEGER, 0x00, 0x00, 0x00)),
    code_info(:B_NIL, VIF_LCO, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:B_FLOAT, 0x00, 1, (CA1_FLOAT, 0x00, 0x00, 0x00)),
    code_info(:B_MPZ, 0x00, 1, (CA1_MPZ, 0x00, 0x00, 0x00)),
    code_info(:B_MPQ, 0x00, 1, (CA1_MPQ, 0x00, 0x00, 0x00)),
    code_info(:B_STRING, 0x00, 1, (CA1_STRING, 0x00, 0x00, 0x00)),
    code_info(:B_ARGVAR, 0x00, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:B_VAR0, VIF_LCO, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:B_VAR1, VIF_LCO, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:B_VAR2, VIF_LCO, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:B_VAR, VIF_LCO, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:B_ARGFIRSTVAR, 0x00, 1, (CA1_FVAR, 0x00, 0x00, 0x00)),
    code_info(:B_FIRSTVAR, 0x00, 1, (CA1_FVAR, 0x00, 0x00, 0x00)),
    code_info(:B_VOID, VIF_LCO, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:B_FUNCTOR, 0x00, 1, (CA1_FUNC, 0x00, 0x00, 0x00)),
    code_info(:B_RFUNCTOR, 0x00, 1, (CA1_FUNC, 0x00, 0x00, 0x00)),
    code_info(:B_LIST, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:B_RLIST, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:B_POP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_CHP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_ENTER, VIF_BREAK, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_CALL, VIF_BREAK, 1, (CA1_LPROC, 0x00, 0x00, 0x00)),
    code_info(:I_DEPART, VIF_BREAK, 1, (CA1_LPROC, 0x00, 0x00, 0x00)),
    code_info(:I_EXIT, VIF_BREAK, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_EXITFACT, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:L_NOLCO, 0x00, 1, (CA1_JUMP, 0x00, 0x00, 0x00)),
    code_info(:L_VAR, 0x00, 2, (CA1_FVAR, CA1_VAR, 0x00, 0x00)),
    code_info(:L_VOID, 0x00, 1, (CA1_FVAR, 0x00, 0x00, 0x00)),
    code_info(:L_ATOM, 0x00, 2, (CA1_FVAR, CA1_DATA, 0x00, 0x00)),
    code_info(:L_NIL, 0x00, 1, (CA1_FVAR, 0x00, 0x00, 0x00)),
    code_info(:L_SMALLINT, 0x00, 2, (CA1_FVAR, CA1_INTEGER, 0x00, 0x00)),
    code_info(:I_LCALL, 0x00, 1, (CA1_LPROC, 0x00, 0x00, 0x00)),
    code_info(:I_TCALL, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_CUT, VIF_BREAK, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_EXITQUERY, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:S_VIRGIN, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:S_UNDEF, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:S_STATIC, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:S_DYNAMIC, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:S_MULTIFILE, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:S_TRUSTME, 0x00, 1, (CA1_CLAUSEREF, 0x00, 0x00, 0x00)),
    code_info(:S_LIST, 0x00, 3, (CA1_INTEGER, CA1_CLAUSEREF, CA1_CLAUSEREF, 0x00)),
    code_info(:I_FCALLDETVA, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET0, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET1, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET2, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET3, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET4, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET5, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET6, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET7, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET8, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET9, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLDET10, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FEXITDET, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_VAR, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_NONVAR, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_INTEGER, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_RATIONAL, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_FLOAT, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_NUMBER, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_ATOMIC, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_ATOM, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_STRING, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_COMPOUND, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_CALLABLE, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00))
)

# PORT: pl-codetable.c codeTable
# DIVERGES: a function over the declared subset (a constant tuple) instead of the array upstream
# generates from the `VMI()` declarations.
"The `code_info` of instruction `op` (pl-codetable.c `codeTable[op]`)."
function codeTable(op::code)::code_info
    op < length(_CODE_TABLE) || error("codeTable: $op is not a declared instruction")
    return _CODE_TABLE[op + 1]
end
