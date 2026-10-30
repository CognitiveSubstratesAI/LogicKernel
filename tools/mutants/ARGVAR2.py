# ORIGINAL: ARGVAR's mutant list — no swipl-devel counterpart.
# tools/mutants/ARGVAR2.py — the mutation battery of ARGVAR (pl-vmi.c B_ARGVAR's and H_VAR's link direction, fuzz seed 300945,
# audit D-0260), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is
# tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# TARGETS (D-0238): the step's own file plus EVERY test file that runs a clause whose body builds a compound holding a variable met
# before (B_ARGVAR), or whose head builds one for an unbound argument (H_VAR in write mode), or reads the order of variables.
T = ["test/core_lang/test_argvar_order_swipl.jl"]
S = T + [
    "test/core_lang/test_head_unify_swipl.jl",
    "test/core_lang/test_rules_swipl.jl",
    "test/core_lang/test_firstvar_swipl.jl",
    "test/core_lang/test_compare_swipl.jl",
    "test/core_lang/test_compare_cells.jl",
    "test/core_lang/test_attvar_words.jl",
    "test/core_lang/test_copyterm_swipl.jl",
    "test/compile/test_body_code_swipl.jl",
]
IN = "src/pl-inline.jl"
TARGETS = S                                                 # the baseline job's list: the union of every mutant's targets
MUTANTS = [
    # ---- _cell_link_lower!: the direction test
    dict(id="ARGVAR-1 the direction test never fires (the old defect: the argument cell always points up)", file=IN, targets=S,
         old='''                if p < q                                # if ( ARGP < k )''',
         new='''                if false                                # if ( ARGP < k )'''),
    dict(id="ARGVAR-2 the direction test is reversed (the lower cell is bound to the higher)", file=IN, targets=S,
         old='''                if p < q                                # if ( ARGP < k )''',
         new='''                if p > q                                # if ( ARGP < k )'''),
    dict(id="ARGVAR-3 the direction test fires for equal cells", file=IN, targets=S,
         old='''                if p < q                                # if ( ARGP < k )''',
         new='''                if p <= q                               # if ( ARGP < k )''',
         equivalent="src/pl-inline.jl:_cell_link_lower! — read, not run: `p` is the argument cell of the compound under construction, a cell the variable's own slot never refers to before this store (B_ARGFIRSTVAR/H_FIRSTVAR gave the variable ITS cell, a different one), so p == q cannot happen."),
    dict(id="ARGVAR-4 the argument cell is not set unbound before the reference to it is made", file=IN, targets=S,
         old='''                    ld.gstack[p] = word(0)              #   setVar(*ARGP)
''',
         new='''''',
         equivalent="src/pl-inline.jl:_cell_link_lower! with src/pl-incl.jl:479 — read, not run: the argument cell is a fresh cell of a compound allocated by B_FUNCTOR/H_FUNCTOR (allocGlobalCells!), which comes zeroed, and `isVar(w)` is `w == word(0)`; the store writes the word it already holds."),
    dict(id="ARGVAR-5 the higher cell is bound without the trail entry", file=IN, targets=S,
         old='''                    _bind_const!(ld, q, makeRefG(p))    #   Trail(k, makeRefG(ARGP++))''',
         new='''                    ld.gstack[q] = makeRefG(p)          #   Trail(k, makeRefG(ARGP++))''',
         equivalent="src/pl-inline.jl:_bind_const! (`p <= ld.mark_bar`) — read, not run: `q > p` and `p` is a cell of the compound allocated after the newest mark (gTop only grows), so `q > mark_bar` and `_bind_const!` would not trail it either; upstream's `Trail(k, ...)` is the same test and never trails here."),
    # ---- the dereferencing before the test
    # killed by the row `chain` (f(w(g(A),A),A,B)): A's first cell, in g(A), is bound to w's second argument cell (above f's), so the
    # slot's chain reaches an unbound cell ABOVE f's argument cell only by following it; the first battery run (ab98692) lacked that row.
    dict(id="ARGVAR-6 the chain of references is not followed (only the slot's own cell is tested)", file=IN, targets=S,
         old='''            elseif isRef(c)
                q = unRef(c)
            else
                break
            end
        end
    end
    _cell_link!(ld, p, i)''',
         new='''            else
                break
            end
        end
    end
    _cell_link!(ld, p, i)'''),
    dict(id="ARGVAR-7 an attributed variable is bound downwards as an unbound one", file=IN, targets=S,
         old='''            if isVar(c)
                if p < q                                # if ( ARGP < k )''',
         new='''            if needsRef(c)
                if p < q                                # if ( ARGP < k )''',
         equivalent="src/pl-wam.jl B_ARGVAR / H_VAR — read, not run: an attributed variable's cell is made by put_attr/attvar creation BEFORE the compound under construction was allocated (gTop only grows), so it always lies BELOW the argument cell and `p < q` is false for it; the branch cannot be reached with q an attributed variable."),
    # ---- the two instructions
    dict(id="ARGVAR-8 B_ARGVAR links with the plain link (the old behaviour)", file="src/pl-wam.jl", targets=S,
         old='''        _cell_link_lower!(ld, ARGP.pos, bav_i)''',
         new='''        _cell_link!(ld, ARGP.pos, bav_i)'''),
    dict(id="ARGVAR-9 H_VAR in write mode links with the plain link", file="src/pl-wam.jl", targets=S,
         old='''                _cell_link_lower!(ld, ARGP.pos, hv_k + 1)''',
         new='''                _cell_link!(ld, ARGP.pos, hv_k + 1)'''),
]
