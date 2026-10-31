# UPSTREAM: swipl-devel src/pl-vmi.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-incl.h @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-codetable.c @ cbf4e1896275
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
# V6b's type tests (`I_VAR` … `I_CALLABLE`, in pl-vmi.c's order), then V8's `A_ADD_FC`, then V9a's
# inline unification family (`B_UNIFY_FIRSTVAR` … `B_NEQ_VC`, `C_VAR`, `I_FAIL`, `I_TRUE`, in
# pl-vmi.c's order), then V9d's control constructs (`C_JMP` … `C_LSCUT`), V9e's meta-call
# (`I_CALL1`, `I_CALLN`), V9f's `I_CATCH`, `I_EXITCATCH`, `I_DET`, `C_DET`, `C_DETTRUE`,
# `C_DETFALSE` and V9g's `I_CALLCLEANUP`, `I_EXITCLEANUP`, then NF1's non-deterministic foreign calls
# (`I_FOPENNDET`, `I_FCALLNDETVA`, `I_FCALLNDET0` … `I_FCALLNDET10` — the eleven consecutive, as the
# deterministic ones — `I_FEXITNDET`, `I_FREDO`; the `a1, a2, …` ones run since NF4), then SSU1's
# single sided unification (`I_SSU_CHOICE`, `I_SSU_COMMIT`, `S_SSU_DET`, in pl-vmi.c's order; with
# the `I_CHP` declared before them, compiled since SSU1 and executed since SSU2), then MOD3a's module
# calls (`I_CONTEXT`, `I_CALLM`, `I_DEPARTM`: `M:Goal` in a clause body and `M:Head :- Body`, in
# pl-vmi.c's order), then MOD4's meta-argument supervisors (`S_MQUAL`, `S_LMQUAL`: the module
# qualification of a `meta_predicate` argument, in pl-vmi.c's order), then MOD3b's `Goal@Module`
# calls (`I_DEPARTATM`, `I_CALLATM`, `I_DEPARTATMV`, `I_CALLATMV`, in pl-vmi.c's order).
#
# NOT EMITTED, so not declared: H_SMALLINTW/B_SMALLINTW/L_SMALLINTW (only where a code word is
# narrower than a word, `CODES_PER_WORD > 1`: on 64-bit swipl every tagged integer is a SMALLINT,
# probed in 10.1.16); `B_ARG_*`, `I_USERCALL0` (its work is `I_CALL1`'s
# here), `I_RESET`, `I_CUTCHP`,
# `I_YIELD` (after V9). `I_CUT` is declared and compiled (a clause-level `!`, user
# 2026-10-05) and, since V6a, executed.
#
# OPERANDS: every literal operand (`*_ATOM`, `*_FLOAT`, `*_MPZ`, `*_MPQ`, `*_STRING`)
# is ONE word, the index of the literal in the clause's literal table (V1 L2), where upstream
# carries the value itself (an atom, an integer, CODES_PER_DOUBLE words, a VM_DYNARGC block); a
# functor operand is `functor_operand` (L2); a procedure operand (`CA1_LPROC`) the index of the
# procedure in the clause's procedure table (V1); a clause-reference operand (`CA1_CLAUSEREF`, the
# supervisors') the index of the clause reference in the definition's `codes_crefs` (V4a); a
# module operand (`CA1_MODULE`, since MOD3a) the module's INDEX in the database's table, as
# `definition.module_` (upstream: the `Module` pointer, `ptr2code(module)`); the procedure operand of
# `I_CALLM`/`I_DEPARTM` keeps upstream's kind `CA1_PROC` and is, as `CA1_LPROC`'s, the index of the
# procedure in the clause's procedure table; the procedure-module operand (the first) of
# `I_CALLATM`/`I_DEPARTATM`/`I_CALLATMV`/`I_DEPARTATMV` (MOD3b) is the module's index or 0 for "the
# clause's module" (upstream: NULL), their procedure operand keeps `CA1_PROC` as `I_CALLM`'s; a
# `*_SMALLINT` operand is the tagged word itself, as upstream's (L1d step 4). The
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
# PORT: pl-vmi.c A_ADD_FC
"`NewVar is Var + Int` inline: the first operand's slot gets the second's value plus the literal (pl-vmi.c)."
const A_ADD_FC = code(85)
# PORT: pl-vmi.c B_UNIFY_FIRSTVAR
"`Var = Term` in a body, `Var` a first occurrence: the body code that follows builds `Term` into it (pl-vmi.c)."
const B_UNIFY_FIRSTVAR = code(86)
# PORT: pl-vmi.c B_UNIFY_VAR
"`Var = Term` in a body: the head code that follows unifies `Term` with the variable (pl-vmi.c)."
const B_UNIFY_VAR = code(87)
# PORT: pl-vmi.c B_UNIFY_EXIT
"The end of a body `Var = Term` (pl-vmi.c)."
const B_UNIFY_EXIT = code(88)
# PORT: pl-vmi.c B_UNIFY_FF
"`Var1 = Var2` in a body, both first occurrences: one fresh variable in both (pl-vmi.c)."
const B_UNIFY_FF = code(89)
# PORT: pl-vmi.c B_UNIFY_VF
"`Var1 = Var2`, the second a first occurrence: `B_UNIFY_FV` with the operands swapped (pl-vmi.c)."
const B_UNIFY_VF = code(90)
# PORT: pl-vmi.c B_UNIFY_FV
"`Var1 = Var2`, the first a first occurrence: it gets the second's value (pl-vmi.c)."
const B_UNIFY_FV = code(91)
# PORT: pl-vmi.c B_UNIFY_VV
"`Var1 = Var2` in a body, neither a first occurrence: unify them (pl-vmi.c)."
const B_UNIFY_VV = code(92)
# PORT: pl-vmi.c B_UNIFY_FC
"`Var = Const`, `Var` a first occurrence: it gets the constant (pl-vmi.c)."
const B_UNIFY_FC = code(93)
# PORT: pl-vmi.c B_UNIFY_VC
"`Var = Const` in a body: unify the variable with the constant (pl-vmi.c)."
const B_UNIFY_VC = code(94)
# PORT: pl-vmi.c B_EQ_VV
"`Var1 == Var2` inline (pl-vmi.c)."
const B_EQ_VV = code(95)
# PORT: pl-vmi.c B_EQ_VC
"`Var == Const` inline (pl-vmi.c)."
const B_EQ_VC = code(96)
# PORT: pl-vmi.c B_NEQ_VV
"`Var1 \\== Var2` inline (pl-vmi.c)."
const B_NEQ_VV = code(97)
# PORT: pl-vmi.c B_NEQ_VC
"`Var \\== Const` inline (pl-vmi.c)."
const B_NEQ_VC = code(98)
# PORT: pl-vmi.c C_VAR
"Make the operand's slot a fresh variable (pl-vmi.c)."
const C_VAR = code(99)
# PORT: pl-vmi.c I_FAIL
"`fail/0` inline (pl-vmi.c)."
const I_FAIL = code(100)
# PORT: pl-vmi.c I_TRUE
"`true/0` inline (pl-vmi.c)."
const I_TRUE = code(101)
# PORT: pl-vmi.c C_JMP
"Skip the operand's count of code words (pl-vmi.c)."
const C_JMP = code(102)
# PORT: pl-vmi.c C_OR
"Create a choice point in the clause: on backtracking, continue the operand's count further on (pl-vmi.c)."
const C_OR = code(103)
# PORT: pl-vmi.c C_VAR_N
"Make the second operand's count of slots, from the first operand's, fresh variables (pl-vmi.c)."
const C_VAR_N = code(104)
# PORT: pl-vmi.c C_IFTHENELSE
"`(A -> B ; C)`: keep the current choice point in the operand's slot, then as `C_OR` (pl-vmi.c)."
const C_IFTHENELSE = code(105)
# PORT: pl-vmi.c C_IFTHEN
"`(A -> B)`: keep the current choice point in the operand's slot (pl-vmi.c)."
const C_IFTHEN = code(106)
# PORT: pl-vmi.c C_CUT
"Commit a condition: discard the choice points made since the one the operand's slot keeps (pl-vmi.c)."
const C_CUT = code(107)
# PORT: pl-vmi.c C_FASTCOND
"`C_IFTHENELSE` for a condition of tests only: no choice point, a failing test jumps to the else branch (pl-vmi.c)."
const C_FASTCOND = code(108)
# PORT: pl-vmi.c C_FASTCUT
"Commit a fast condition: nothing to do unless it was turned into a normal one (pl-vmi.c)."
const C_FASTCUT = code(109)
# PORT: pl-vmi.c C_END
"The end of `(A -> B)`, for the decompiler (pl-vmi.c)."
const C_END = code(110)
# PORT: pl-vmi.c C_LCUT
"A `!` in the condition of `(A -> B ; C)`: cut the choice points made since the mark, not the mark (pl-vmi.c)."
const C_LCUT = code(111)
# PORT: pl-vmi.c C_LCUTIFTHEN
"A `!` in the condition of `(A -> B)` (pl-vmi.c)."
const C_LCUTIFTHEN = code(112)
# PORT: pl-vmi.c C_NOT
"`\\+ A`: as `C_IFTHENELSE`, under a name of its own for the decompiler (pl-vmi.c)."
const C_NOT = code(113)
# PORT: pl-vmi.c C_FAIL
"Fail: what `\\+ A` does once A succeeded and its choice points are cut (pl-vmi.c)."
const C_FAIL = code(114)
# PORT: pl-vmi.c C_SOFTIF
"`(A *-> B ; C)`: as `C_OR`, keeping the choice point it makes in the operand's slot (pl-vmi.c)."
const C_SOFTIF = code(115)
# PORT: pl-vmi.c C_SOFTCUT
"Commit `(A *-> B ; C)` to A's answers: take the condition's own choice point out of the chain, once (pl-vmi.c)."
const C_SOFTCUT = code(116)
# PORT: pl-vmi.c C_SOFTIFTHEN
"`(A *-> B)`: as `C_IFTHEN` (pl-vmi.c)."
const C_SOFTIFTHEN = code(117)
# PORT: pl-vmi.c C_SCUT
"The end of the condition of `(A *-> B)`: nothing to do (pl-vmi.c)."
const C_SCUT = code(118)
# PORT: pl-vmi.c C_LSCUT
"A `!` in the condition of `(A *-> B ; C)` (pl-vmi.c)."
const C_LSCUT = code(119)
# PORT: pl-vmi.c I_CALL1
"Call the goal in the new frame's first argument: a variable goal, or `call/1` (pl-vmi.c)."
const I_CALL1 = code(120)
# PORT: pl-vmi.c I_CALLN
"`call(Goal, A1, …)`: the operand is the count of extra arguments (pl-vmi.c)."
const I_CALLN = code(121)
# PORT: pl-vmi.c I_CATCH
"`catch/3`'s call of its goal, under a `CHP_CATCH` choice point (pl-vmi.c)."
const I_CATCH = code(122)
# PORT: pl-vmi.c I_EXITCATCH
"`catch/3`'s exit: drop its `CHP_CATCH` if the goal left no choice point (pl-vmi.c)."
const I_EXITCATCH = code(123)
# PORT: pl-vmi.c I_DET
"`\$/0`: cut, and the clause must then succeed without a choice point (pl-vmi.c)."
const I_DET = code(124)
# PORT: pl-vmi.c C_DET
"`\$(Goal)`: start a block that must succeed without a choice point; as `C_NOT` (pl-vmi.c)."
const C_DET = code(125)
# PORT: pl-vmi.c C_DETTRUE
"`\$(Goal)` after `Goal`: a choice point left is a determinism error (pl-vmi.c)."
const C_DETTRUE = code(126)
# PORT: pl-vmi.c C_DETFALSE
"`\$(Goal)` when `Goal` failed: a determinism error (pl-vmi.c)."
const C_DETFALSE = code(127)
# PORT: pl-vmi.c I_CALLCLEANUP
"The cleanup family's call of its goal, under a `CHP_CATCH` choice point; the frame gets `FR_CLEANUP` (pl-vmi.c)."
const I_CALLCLEANUP = code(128)
# PORT: pl-vmi.c I_EXITCLEANUP
"The cleanup family's exit: run the cleanup handler if the goal left no choice point (pl-vmi.c)."
const I_EXITCLEANUP = code(129)
# PORT: pl-vmi.c I_FOPENNDET
"A non-deterministic foreign call's first word: the first-call context, then `foreign_redo` (pl-vmi.c)."
const I_FOPENNDET = code(130)
# PORT: pl-vmi.c I_FCALLNDETVA
"Call a non-deterministic foreign predicate with the `t0, ac, ctx` convention; operand: its index (pl-vmi.c)."
const I_FCALLNDETVA = code(131)
# PORT: pl-vmi.c I_FCALLNDET0
"Call a non-deterministic foreign predicate of 0 arguments, `a1, a2, …` convention; operand: its index (pl-vmi.c)."
const I_FCALLNDET0 = code(132)
# PORT: pl-vmi.c I_FCALLNDET1
"As `I_FCALLNDET0`, 1 argument (pl-vmi.c)."
const I_FCALLNDET1 = code(133)
# PORT: pl-vmi.c I_FCALLNDET2
"As `I_FCALLNDET0`, 2 arguments (pl-vmi.c)."
const I_FCALLNDET2 = code(134)
# PORT: pl-vmi.c I_FCALLNDET3
"As `I_FCALLNDET0`, 3 arguments (pl-vmi.c)."
const I_FCALLNDET3 = code(135)
# PORT: pl-vmi.c I_FCALLNDET4
"As `I_FCALLNDET0`, 4 arguments (pl-vmi.c)."
const I_FCALLNDET4 = code(136)
# PORT: pl-vmi.c I_FCALLNDET5
"As `I_FCALLNDET0`, 5 arguments (pl-vmi.c)."
const I_FCALLNDET5 = code(137)
# PORT: pl-vmi.c I_FCALLNDET6
"As `I_FCALLNDET0`, 6 arguments (pl-vmi.c)."
const I_FCALLNDET6 = code(138)
# PORT: pl-vmi.c I_FCALLNDET7
"As `I_FCALLNDET0`, 7 arguments (pl-vmi.c)."
const I_FCALLNDET7 = code(139)
# PORT: pl-vmi.c I_FCALLNDET8
"As `I_FCALLNDET0`, 8 arguments (pl-vmi.c)."
const I_FCALLNDET8 = code(140)
# PORT: pl-vmi.c I_FCALLNDET9
"As `I_FCALLNDET0`, 9 arguments (pl-vmi.c)."
const I_FCALLNDET9 = code(141)
# PORT: pl-vmi.c I_FCALLNDET10
"As `I_FCALLNDET0`, 10 arguments (pl-vmi.c)."
const I_FCALLNDET10 = code(142)
# PORT: pl-vmi.c I_FEXITNDET
"A non-deterministic foreign call's exit: done, failed, or a retry context kept with its choice point (pl-vmi.c)."
const I_FEXITNDET = code(143)
# PORT: pl-vmi.c I_FREDO
"Where a non-deterministic foreign call's choice point resumes: the redo context, then the call again (pl-vmi.c)."
const I_FREDO = code(144)
# PORT: pl-vmi.c I_SSU_CHOICE
"End of the head of a `Head ?=> Body` clause: fail it if the head bound the goal, else enter the body (pl-vmi.c; executed in SSU2)."
const I_SSU_CHOICE = code(145)
# PORT: pl-vmi.c I_SSU_COMMIT
"End of the head of a `Head => Body` clause: fail it if the head bound the goal, else commit to it and enter the body (pl-vmi.c; executed in SSU2)."
const I_SSU_COMMIT = code(146)
# PORT: pl-vmi.c S_SSU_DET
"Supervisor prefix of an SSU predicate (`P_SSU_DET`): mark the frame `FR_SSU_DET` (pl-vmi.c; executed in SSU2)."
const S_SSU_DET = code(147)
# PORT: pl-vmi.c I_CONTEXT
"After `I_ENTER`: a clause whose body module is not its predicate's sets the frame's context to it unless the predicate is transparent; operand: the module (pl-vmi.c; MOD3a)."
const I_CONTEXT = code(148)
# PORT: pl-vmi.c I_CALLM
"Call a procedure of another module than the clause's (`M:Goal` in a body); operands: the module, the procedure (pl-vmi.c; MOD3a)."
const I_CALLM = code(149)
# PORT: pl-vmi.c I_DEPARTM
"`I_CALLM` as the clause's last call: the frame takes the module as its context and departs, unless a choice point or `last_call` forbids it (pl-vmi.c; MOD3a)."
const I_DEPARTM = code(150)
# PORT: pl-vmi.c S_MQUAL
"Supervisor of a transparent `meta_predicate`: qualify the argument in the operand's slot with the frame's context module (pl-vmi.c; MOD4)."
const S_MQUAL = code(151)
# PORT: pl-vmi.c S_LMQUAL
"The last `S_MQUAL` of a supervisor: qualify the argument, then set the frame's context to its predicate's module (pl-vmi.c; MOD4)."
const S_LMQUAL = code(152)
# PORT: pl-vmi.c I_DEPARTATM
"`I_CALLATM` as the clause's last call: skip the `:`-qualifier operand and continue as `I_DEPARTM` (pl-vmi.c; MOD3b)."
const I_DEPARTATM = code(153)
# PORT: pl-vmi.c I_CALLATM
"Call a procedure with a fixed context module (`Goal@Module` in a body); operands: the procedure-module (for the decompiler, 0 = the clause's), the context module, the procedure (pl-vmi.c; MOD3b)."
const I_CALLATM = code(154)
# PORT: pl-vmi.c I_DEPARTATMV
"`I_CALLATMV` as the clause's last call: the frame takes the module in the variable as its context and departs, unless a choice point or `last_call` forbids it (pl-vmi.c; MOD3b)."
const I_DEPARTATMV = code(155)
# PORT: pl-vmi.c I_CALLATMV
"Call a procedure with the context module in a variable (`Goal@M` in a body); operands: the procedure-module, the variable, the procedure (pl-vmi.c; MOD3b)."
const I_CALLATMV = code(156)

# PORT: pl-incl.h code_info
# DIVERGES: `arguments` counts the kernel's operand WORDS — a literal is one (see above), where
# upstream's `H_MPZ`/`H_MPQ`/`H_STRING` and their `B_` forms declare `VM_DYNARGC`. `argtype` is four
# kinds padded with 0, as upstream's (`VM_ARGC` is 4). No `code` field: the table is indexed by
# opcode + 1.
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
    code_info(:I_CALLABLE, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:A_ADD_FC, VIF_BREAK, 3, (CA1_FVAR, CA1_VAR, CA1_INTEGER, 0x00)),
    code_info(:B_UNIFY_FIRSTVAR, VIF_BREAK, 1, (CA1_FVAR, 0x00, 0x00, 0x00)),
    code_info(:B_UNIFY_VAR, VIF_BREAK, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:B_UNIFY_EXIT, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:B_UNIFY_FF, VIF_BREAK, 2, (CA1_FVAR, CA1_FVAR, 0x00, 0x00)),
    code_info(:B_UNIFY_VF, VIF_BREAK, 2, (CA1_FVAR, CA1_VAR, 0x00, 0x00)),
    code_info(:B_UNIFY_FV, VIF_BREAK, 2, (CA1_FVAR, CA1_VAR, 0x00, 0x00)),
    code_info(:B_UNIFY_VV, VIF_BREAK, 2, (CA1_VAR, CA1_VAR, 0x00, 0x00)),
    code_info(:B_UNIFY_FC, VIF_BREAK, 2, (CA1_FVAR, CA1_DATA, 0x00, 0x00)),
    code_info(:B_UNIFY_VC, VIF_BREAK, 2, (CA1_VAR, CA1_DATA, 0x00, 0x00)),
    code_info(:B_EQ_VV, VIF_BREAK, 2, (CA1_VAR, CA1_VAR, 0x00, 0x00)),
    code_info(:B_EQ_VC, VIF_BREAK, 2, (CA1_VAR, CA1_DATA, 0x00, 0x00)),
    code_info(:B_NEQ_VV, VIF_BREAK, 2, (CA1_VAR, CA1_VAR, 0x00, 0x00)),
    code_info(:B_NEQ_VC, VIF_BREAK, 2, (CA1_VAR, CA1_DATA, 0x00, 0x00)),
    code_info(:C_VAR, 0x00, 1, (CA1_FVAR, 0x00, 0x00, 0x00)),
    code_info(:I_FAIL, VIF_BREAK, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_TRUE, VIF_BREAK, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:C_JMP, 0x00, 1, (CA1_JUMP, 0x00, 0x00, 0x00)),
    code_info(:C_OR, 0x00, 1, (CA1_JUMP, 0x00, 0x00, 0x00)),
    code_info(:C_VAR_N, 0x00, 2, (CA1_FVAR, CA1_INTEGER, 0x00, 0x00)),
    code_info(:C_IFTHENELSE, 0x00, 2, (CA1_CHP, CA1_JUMP, 0x00, 0x00)),
    code_info(:C_IFTHEN, 0x00, 1, (CA1_CHP, 0x00, 0x00, 0x00)),
    code_info(:C_CUT, 0x00, 1, (CA1_CHP, 0x00, 0x00, 0x00)),
    code_info(:C_FASTCOND, 0x00, 2, (CA1_CHP, CA1_JUMP, 0x00, 0x00)),
    code_info(:C_FASTCUT, 0x00, 1, (CA1_CHP, 0x00, 0x00, 0x00)),
    code_info(:C_END, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:C_LCUT, 0x00, 1, (CA1_CHP, 0x00, 0x00, 0x00)),
    code_info(:C_LCUTIFTHEN, 0x00, 1, (CA1_CHP, 0x00, 0x00, 0x00)),
    code_info(:C_NOT, 0x00, 2, (CA1_CHP, CA1_JUMP, 0x00, 0x00)),
    code_info(:C_FAIL, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:C_SOFTIF, 0x00, 2, (CA1_CHP, CA1_JUMP, 0x00, 0x00)),
    code_info(:C_SOFTCUT, 0x00, 1, (CA1_CHP, 0x00, 0x00, 0x00)),
    code_info(:C_SOFTIFTHEN, 0x00, 1, (CA1_CHP, 0x00, 0x00, 0x00)),
    code_info(:C_SCUT, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:C_LSCUT, 0x00, 1, (CA1_CHP, 0x00, 0x00, 0x00)),
    code_info(:I_CALL1, VIF_BREAK, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_CALLN, VIF_BREAK, 1, (CA1_INTEGER, 0x00, 0x00, 0x00)),
    code_info(:I_CATCH, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_EXITCATCH, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_DET, VIF_BREAK, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:C_DET, 0x00, 2, (CA1_CHP, CA1_JUMP, 0x00, 0x00)),
    code_info(:C_DETTRUE, 0x00, 1, (CA1_CHP, 0x00, 0x00, 0x00)),
    code_info(:C_DETFALSE, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_CALLCLEANUP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_EXITCLEANUP, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_FOPENNDET, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDETVA, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET0, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET1, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET2, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET3, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET4, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET5, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET6, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET7, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET8, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET9, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FCALLNDET10, 0x00, 1, (CA1_FOREIGN, 0x00, 0x00, 0x00)),
    code_info(:I_FEXITNDET, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_FREDO, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_SSU_CHOICE, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_SSU_COMMIT, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:S_SSU_DET, 0x00, 0, (0x00, 0x00, 0x00, 0x00)),
    code_info(:I_CONTEXT, 0x00, 1, (CA1_MODULE, 0x00, 0x00, 0x00)),
    code_info(:I_CALLM, VIF_BREAK, 2, (CA1_MODULE, CA1_PROC, 0x00, 0x00)),
    code_info(:I_DEPARTM, VIF_BREAK, 2, (CA1_MODULE, CA1_PROC, 0x00, 0x00)),
    code_info(:S_MQUAL, 0x00, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:S_LMQUAL, 0x00, 1, (CA1_VAR, 0x00, 0x00, 0x00)),
    code_info(:I_DEPARTATM, VIF_BREAK, 3, (CA1_MODULE, CA1_MODULE, CA1_PROC, 0x00)),
    code_info(:I_CALLATM, VIF_BREAK, 3, (CA1_MODULE, CA1_MODULE, CA1_PROC, 0x00)),
    code_info(:I_DEPARTATMV, VIF_BREAK, 3, (CA1_MODULE, CA1_VAR, CA1_PROC, 0x00)),
    code_info(:I_CALLATMV, VIF_BREAK, 3, (CA1_MODULE, CA1_VAR, CA1_PROC, 0x00))
)

# PORT: pl-codetable.c codeTable
# DIVERGES: a function over the declared subset (a constant tuple) instead of the array upstream
# generates from the `VMI()` declarations.
"The `code_info` of instruction `op` (pl-codetable.c `codeTable[op]`)."
function codeTable(op::code)::code_info
    op < length(_CODE_TABLE) || error("codeTable: $op is not a declared instruction")
    return _CODE_TABLE[op + 1]
end
