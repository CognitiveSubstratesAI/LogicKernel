# ORIGINAL: CTP's mutant list — the port of `$clause_term_position/3` (pl-comp.c:8584-8900); no swipl-devel counterpart.
# tools/mutants/CTP.py — the mutation battery of `$clause_term_position/3` (audit D-0555/D-0558), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old`
# (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# TARGETS (D-0238): the functions are reached only through `$clause_term_position/3`, whose only test file is the live
# differential below (33 rows: 25 constructs, 8 errors). UNTESTED when written: nothing compiled.
T = ["test/db/test_clause_term_position_swipl.jl"]
IN = "src/pl-comp.jl"
TARGETS = T                                                 # the baseline job's list: the union of every mutant's targets
MUTANTS = [
    # ---- the argument checks and the exit answer
    dict(id="CTP-1 a bad clause reference does not fail the call", file=IN, targets=T,
         old='''    rc == 0 && return FFALSE
    clause = cl::Clause{T}''',
         new='''    clause = cl::Clause{T}'''),
    dict(id="CTP-2 the range test refuses the PC at the end of the code", file=IN, targets=T,
         old='''    if pcoffset < 0 || pcoffset > code_size''',
         new='''    if pcoffset < 0 || pcoffset >= code_size'''),
    dict(id="CTP-3 the range test lets a negative PC through", file=IN, targets=T,
         old='''    if pcoffset < 0 || pcoffset > code_size''',
         new='''    if pcoffset > code_size'''),
    dict(id="CTP-4 the final instruction is not forgotten (fin one word further)", file=IN, targets=T,
         old='''    fin = _pc_add(base, code_size - 1)                          # forget the final I_EXIT''',
         new='''    fin = _pc_add(base, code_size - 2)                          # forget the final I_EXIT'''),
    dict(id="CTP-5 the exit answer is dropped for the PC at the end of the code", file=IN, targets=T,
         old='''        return PL_unify_atom(ld, A3, mk_sym(T, :exit)) ? FTRUE : FFALSE''',
         new='''        return PL_unify_nil(ld, tail) ? FTRUE : FFALSE'''),
    # ---- the I_ENTER / exit instructions
    dict(id="CTP-6 the SSU commit instruction is not an entry point", file=IN, targets=T,
         old='''        if op == I_ENTER || op == I_SSU_CHOICE || op == I_SSU_COMMIT''',
         new='''        if op == I_ENTER || op == I_SSU_CHOICE'''),
    dict(id="CTP-7 the entry instruction answers the wrong node (2 for 1)", file=IN, targets=T,
         old='''            if loc.pc == nextpc.pc
                add_node(ld, tail, 1)
                return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
            end
            add_node(ld, tail, 2)
            PC = nextpc
        elseif op == I_EXIT''',
         new='''            if loc.pc == nextpc.pc
                add_node(ld, tail, 2)
                return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
            end
            add_node(ld, tail, 2)
            PC = nextpc
        elseif op == I_EXIT'''),
    # ---- the disjunction
    dict(id="CTP-8 the disjunction test excludes its last instruction", file=IN, targets=T,
         old='''            if loc.pc <= endloc.pc              # loc is in the disjunction''',
         new='''            if loc.pc < endloc.pc               # loc is in the disjunction'''),
    dict(id="CTP-9 the first-branch test excludes the jump instruction", file=IN, targets=T,
         old='''                if loc.pc <= jmploc.pc          # loc is in first branch''',
         new='''                if loc.pc < jmploc.pc           # loc is in first branch'''),
    dict(id="CTP-10 the first branch's final instruction is one word too late", file=IN, targets=T,
         old='''                    fin = _pc_add(jmploc, -2)''',
         new='''                    fin = _pc_add(jmploc, -1)'''),
    dict(id="CTP-11 the second branch starts at the jump instruction (PC not moved)", file=IN, targets=T,
         old='''                    add_node(ld, tail, 2)
                    PC = jmploc
                    fin = endloc''',
         new='''                    add_node(ld, tail, 2)
                    fin = endloc'''),
    # ---- the negation
    dict(id="CTP-12 the negation's cut is looked up one word too early", file=IN, targets=T,
         old='''            endnot = _pc_add(endloc, -3)''',
         new='''            endnot = _pc_add(endloc, -2)'''),
    dict(id="CTP-13 the negation with a variable slot keeps the wrong cut location", file=IN, targets=T,
         old='''                endnot = _pc_add(endnot, -2)''',
         new='''                endnot = _pc_add(endnot, -1)'''),
    dict(id="CTP-14 the `\\+` argument test excludes the cut", file=IN, targets=T,
         old='''            if loc.pc <= endnot.pc              # in the \\+ argument''',
         new='''            if loc.pc < endnot.pc               # in the \\+ argument'''),
    dict(id="CTP-15 a PC inside the negation's failure part is a possible continuation", file=IN, targets=T,
         old='''            elseif loc.pc <= endloc.pc
                PL_error(
                    ld, "", 0, "not a possible continuation", ERR_DOMAIN,''',
         new='''            elseif loc.pc < endloc.pc
                PL_error(
                    ld, "", 0, "not a possible continuation", ERR_DOMAIN,'''),
    dict(id="CTP-16 the `\\+` argument's node is dropped", file=IN, targets=T,
         old='''                add_node(ld, tail, 1)
                fin = endnot                    # C_CUT <var>, C_FAIL''',
         new='''                fin = endnot                    # C_CUT <var>, C_FAIL'''),
    # ---- if-then-else, soft-cut, fast condition
    dict(id="CTP-17 the if-then-else condition's cut is searched with the wrong cut instruction", file=IN, targets=T,
         old='''            cut = op == C_IFTHENELSE ? C_CUT : (op == C_FASTCOND ? C_FASTCUT : C_SOFTCUT)''',
         new='''            cut = op == C_IFTHENELSE ? C_CUT : (op == C_FASTCOND ? C_SOFTCUT : C_FASTCUT)'''),
    dict(id="CTP-18 the construct test excludes the end location", file=IN, targets=T,
         old='''            if loc.pc <= endloc.pc
                add_1_if_not_at_end(ld, endloc, fin, tail)

                if loc.pc <= elseloc.pc         # a->b''',
         new='''            if loc.pc < endloc.pc
                add_1_if_not_at_end(ld, endloc, fin, tail)

                if loc.pc <= elseloc.pc         # a->b'''),
    dict(id="CTP-19 the condition/then split excludes the cut itself", file=IN, targets=T,
         old='''                    if loc.pc <= cutloc.pc      # a
                        add_node(ld, tail, 1)''',
         new='''                    if loc.pc < cutloc.pc       # a
                        add_node(ld, tail, 1)'''),
    dict(id="CTP-20 the then part resumes at the cut (PC advanced one word less)", file=IN, targets=T,
         old='''                        PC = _pc_add(cutloc, 2)
                        fin = _pc_add(elseloc, -2)''',
         new='''                        PC = _pc_add(cutloc, 1)
                        fin = _pc_add(elseloc, -2)'''),
    dict(id="CTP-21 the then part ends at the jump instruction (fin one word later)", file=IN, targets=T,
         old='''                        fin = _pc_add(elseloc, -2)''',
         new='''                        fin = _pc_add(elseloc, -1)'''),
    dict(id="CTP-22 the else part is entered at the jump (PC not moved)", file=IN, targets=T,
         old='''                    add_node(ld, tail, 2)
                    PC = elseloc
                    fin = endloc''',
         new='''                    add_node(ld, tail, 2)
                    fin = endloc'''),
    # ---- if-then without else
    dict(id="CTP-23 the if-then condition/then split excludes the cut itself", file=IN, targets=T,
         old='''                if loc.pc <= cutloc.pc          # a
                    add_node(ld, tail, 1)''',
         new='''                if loc.pc < cutloc.pc           # a
                    add_node(ld, tail, 1)'''),
    dict(id="CTP-24 the if-then body ends at the C_END (fin one word later)", file=IN, targets=T,
         old='''                    fin = _pc_add(endloc, -1)   # point at the C_END''',
         new='''                    fin = endloc                # point at the C_END'''),
    dict(id="CTP-25 the if-then end search starts at the cut", file=IN, targets=T,
         old='''            endloc = _pc_add(find_if_then_end(_pc_add(cutloc, 2), base), 1)
            PC = nextpc''',
         new='''            endloc = _pc_add(find_if_then_end(_pc_add(cutloc, 1), base), 1)
            PC = nextpc'''),
    dict(id="CTP-26 find_if_then_end does not step past a nested if-then's C_END", file=IN, targets=T,
         old='''            PC = _pc_add(find_if_then_end(_pc_add(cutloc, 2), base), 1)   # the location of C_END''',
         new='''            PC = find_if_then_end(_pc_add(cutloc, 2), base)   # the location of C_END'''),
    dict(id="CTP-27 find_if_then_end steps over a nested negation by the wrong operand", file=IN, targets=T,
         old='''        elseif op == C_NOT
            PC = _pc_add(nextpc, Int(_pc_word(PC, 2)))''',
         new='''        elseif op == C_NOT
            PC = _pc_add(nextpc, Int(_pc_word(PC, 1)))'''),
    dict(id="CTP-28 find_code1 matches the first instruction of the wanted kind whatever its operand", file=IN, targets=T,
         old='''        if fop == op && ctx == _pc_word(PC, 1)''',
         new='''        if fop == op'''),
    # ---- the context, unification and ordinary instructions
    dict(id="CTP-29 the module-context instruction adds no node", file=IN, targets=T,
         old='''            PC = nextpc
            add_node(ld, tail, 2)
        elseif op == B_UNIFY_FIRSTVAR''',
         new='''            PC = nextpc
        elseif op == B_UNIFY_FIRSTVAR'''),
    dict(id="CTP-30 the unification skips only its first instruction (B_UNIFY_EXIT not awaited)", file=IN, targets=T,
         old='''                op == B_UNIFY_EXIT && break''',
         new='''                break'''),
    dict(id="CTP-31 ordinary instructions never add a node (VIF_BREAK ignored)", file=IN, targets=T,
         old='''            if (codeTable(op).flags & VIF_BREAK) != 0
                add_node(ld, tail, 2)''',
         new='''            if false
                add_node(ld, tail, 2)'''),
    dict(id="CTP-32 add_1_if_not_at_end skips only C_VAR, not C_VAR_N", file=IN, targets=T,
         old='''    while PC.pc < fin.pc && (decode(PC) == C_VAR || decode(PC) == C_VAR_N)''',
         new='''    while PC.pc < fin.pc && (decode(PC) == C_VAR)'''),
    dict(id="CTP-33 add_1_if_not_at_end compares with <= (never adds at the end)", file=IN, targets=T,
         old='''    while PC.pc < fin.pc && (decode(PC) == C_VAR || decode(PC) == C_VAR_N)''',
         new='''    while PC.pc <= fin.pc && (decode(PC) == C_VAR || decode(PC) == C_VAR_N)'''),
]
