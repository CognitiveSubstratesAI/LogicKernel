# Writes evidence/F2/push_cases.json, the case table of test/core_lang/test_push_flag_swipl.jl: (id, goal), run IN ORDER in one database.
# Each goal is the body of `t_<id>(R) :- catch((Goal), error(E, _), R = raised(E))`. A flag a case creates has the prefix zz_pf_.
# Usage (from the worktree root): python3 -I evidence/F2/make_cases.py
import json
ABSENT = "( current_prolog_flag(%s, _) -> %s = present ; %s = absent )"
def gone(k, v):
    return ABSENT % (k, v, v)
cases = [
    # push and pop of a flag that exists: the module flags, a Boolean flag of the mask, the values restored
    ("pf01", "current_prolog_flag(double_quotes, D0), push_prolog_flag(double_quotes, atom), current_prolog_flag(double_quotes, D1), pop_prolog_flag(double_quotes), current_prolog_flag(double_quotes, D2), R = [D0, D1, D2]"),
    ("pf02", "pop_prolog_flag(double_quotes)"),
    ("pf03", "pop_prolog_flag(zz_pf_none)"),
    ("pf04", "current_prolog_flag(last_call_optimisation, A), push_prolog_flag(last_call_optimisation, false), current_prolog_flag(last_call_optimisation, B), pop_prolog_flag(last_call_optimisation), current_prolog_flag(last_call_optimisation, C), R = [A, B, C]"),
    ("pf05", "current_prolog_flag(character_escapes, A), push_prolog_flag(character_escapes, false), current_prolog_flag(character_escapes, B), pop_prolog_flag(character_escapes), current_prolog_flag(character_escapes, C), R = [A, B, C]"),
    ("pf06", "current_prolog_flag(occurs_check, A), push_prolog_flag(occurs_check, error), current_prolog_flag(occurs_check, B), pop_prolog_flag(occurs_check), current_prolog_flag(occurs_check, C), R = [A, B, C]"),
    # the arguments, as upstream checks them in order: the key, the access, then the value
    ("pf07", "push_prolog_flag(bounded, true)"),
    ("pf08", "push_prolog_flag(_, 1)"),
    ("pf09", "push_prolog_flag(1, 1)"),
    ("pf10", "push_prolog_flag(pid, 1)"),
    ("pf11", "catch(push_prolog_flag(zz_pf_n, _), error(E, _), true), " + gone("zz_pf_n", "G") + ", R = E-G"),
    ("pf12", "push_prolog_flag(zz_pf_n, foo(_, 1))"),
    # a flag that is absent: created by the push, deleted by the pop
    ("pf13", "push_prolog_flag(zz_pf_n, 5), current_prolog_flag(zz_pf_n, V), pop_prolog_flag(zz_pf_n), " + gone("zz_pf_n", "G") + ", R = V-G"),
    ("pf14", "push_prolog_flag(zz_pf_n, abc), current_prolog_flag(zz_pf_n, V), pop_prolog_flag(zz_pf_n), " + gone("zz_pf_n", "G") + ", R = V-G"),
    ("pf15", "push_prolog_flag(zz_pf_n, true), current_prolog_flag(zz_pf_n, V), pop_prolog_flag(zz_pf_n), " + gone("zz_pf_n", "G") + ", R = V-G"),
    ("pf16", "push_prolog_flag(zz_pf_n, 2.5), current_prolog_flag(zz_pf_n, V), pop_prolog_flag(zz_pf_n), " + gone("zz_pf_n", "G") + ", R = V-G"),
    ("pf17", "push_prolog_flag(zz_pf_n, foo(a, [1, 2])), current_prolog_flag(zz_pf_n, V), pop_prolog_flag(zz_pf_n), " + gone("zz_pf_n", "G") + ", R = V-G"),
    ("pf18", "push_prolog_flag(zz_pf_n, 1), push_prolog_flag(zz_pf_n, 2), push_prolog_flag(zz_pf_n, 3), current_prolog_flag(zz_pf_n, A), pop_prolog_flag(zz_pf_n), current_prolog_flag(zz_pf_n, B), pop_prolog_flag(zz_pf_n), current_prolog_flag(zz_pf_n, C), pop_prolog_flag(zz_pf_n), " + gone("zz_pf_n", "G") + ", R = [A, B, C, G]"),
    ("pf19", "push_prolog_flag(zz_pf_n, 1), set_prolog_flag(zz_pf_n, 7), current_prolog_flag(zz_pf_n, A), pop_prolog_flag(zz_pf_n), " + gone("zz_pf_n", "G") + ", R = A-G"),
    ("pf20", "push_prolog_flag(zz_pf_n, 1), pop_prolog_flag(zz_pf_n), push_prolog_flag(zz_pf_n, a), current_prolog_flag(zz_pf_n, A), pop_prolog_flag(zz_pf_n), findall(K, ( current_prolog_flag(K, _), K == zz_pf_n ), L), R = A-L"),
    ("pf21", "push_prolog_flag(zz_pf_n, 1), pop_prolog_flag(zz_pf_n), catch(pop_prolog_flag(zz_pf_n), error(E, _), true), R = E"),
    ("pf22", "push_prolog_flag(user:zz_pf_q, abc), current_prolog_flag(zz_pf_q, A), pop_prolog_flag(user:zz_pf_q), " + gone("zz_pf_q", "G") + ", R = A-G"),
    ("pf23", "push_prolog_flag(zz_pf_n, 1), push_prolog_flag(zz_pf_n, a), current_prolog_flag(zz_pf_n, A), pop_prolog_flag(zz_pf_n), current_prolog_flag(zz_pf_n, B), pop_prolog_flag(zz_pf_n), R = A-B"),
    # a flag made by create_prolog_flag/3, one per type
    ("pf24", "create_prolog_flag(zz_pf_i, 5, []), push_prolog_flag(zz_pf_i, 9), current_prolog_flag(zz_pf_i, A), pop_prolog_flag(zz_pf_i), current_prolog_flag(zz_pf_i, B), R = A-B"),
    ("pf25", "catch(push_prolog_flag(zz_pf_i, foo), error(E, _), true), catch(pop_prolog_flag(zz_pf_i), error(E2, _), true), current_prolog_flag(zz_pf_i, V), R = [E, E2, V]"),
    ("pf26", "create_prolog_flag(zz_pf_f, 1.5, []), push_prolog_flag(zz_pf_f, 2.5), current_prolog_flag(zz_pf_f, A), pop_prolog_flag(zz_pf_f), current_prolog_flag(zz_pf_f, B), R = A-B"),
    ("pf27", "push_prolog_flag(zz_pf_f, 2)"),
    ("pf28", "create_prolog_flag(zz_pf_b, true, []), push_prolog_flag(zz_pf_b, false), current_prolog_flag(zz_pf_b, A), pop_prolog_flag(zz_pf_b), current_prolog_flag(zz_pf_b, B), R = A-B"),
    ("pf29", "push_prolog_flag(zz_pf_b, maybe)"),
    ("pf30", "create_prolog_flag(zz_pf_t, foo(1), [type(term)]), push_prolog_flag(zz_pf_t, bar(2, [x])), current_prolog_flag(zz_pf_t, A), pop_prolog_flag(zz_pf_t), current_prolog_flag(zz_pf_t, B), R = A-B"),
    ("pf31", "create_prolog_flag(zz_pf_a, one, [type(atom)]), push_prolog_flag(zz_pf_a, two), current_prolog_flag(zz_pf_a, A), pop_prolog_flag(zz_pf_a), current_prolog_flag(zz_pf_a, B), R = A-B"),
    ("pf32", "create_prolog_flag(zz_pf_o, a, [type(oneof([a, b]))]), push_prolog_flag(zz_pf_o, b), current_prolog_flag(zz_pf_o, A), pop_prolog_flag(zz_pf_o), current_prolog_flag(zz_pf_o, B), R = A-B"),
    ("pf33", "push_prolog_flag(zz_pf_o, c)"),
    ("pf34", "catch(push_prolog_flag(zz_pf_o, c), error(E, _), true), catch(pop_prolog_flag(zz_pf_o), error(E2, _), true), R = [E, E2]"),
    ("pf35", "create_prolog_flag(zz_pf_sh, a, [shared(true)]), push_prolog_flag(zz_pf_sh, b)"),
    ("pf36", "catch(push_prolog_flag(zz_pf_sh, b), error(_, _), true), current_prolog_flag(zz_pf_sh, A), catch(pop_prolog_flag(zz_pf_sh), error(E, _), true), R = A-E"),
    ("pf37", "create_prolog_flag(zz_pf_k, 1, [access(read_only)]), push_prolog_flag(zz_pf_k, 2)"),
    ("pf38", "create_prolog_flag(zz_pf_m, 1, []), push_prolog_flag(zz_pf_m, 2), push_prolog_flag(zz_pf_m, 3), set_prolog_flag(zz_pf_m, 4), pop_prolog_flag(zz_pf_m), current_prolog_flag(zz_pf_m, A), pop_prolog_flag(zz_pf_m), current_prolog_flag(zz_pf_m, B), R = A-B"),
    # the rest of the module flags and the checks of set_flag_value on a push
    ("pf39", "catch(push_prolog_flag(unknown, foo), error(E, _), true), catch(pop_prolog_flag(unknown), error(E2, _), true), R = [E, E2]"),
    ("pf40", "catch(push_prolog_flag(double_quotes, nonsense), error(E, _), true), catch(pop_prolog_flag(double_quotes), error(E2, _), true), R = [E, E2]"),
    ("pf41", "current_prolog_flag(optimise, A), push_prolog_flag(optimise, true), current_prolog_flag(optimise, B), pop_prolog_flag(optimise), current_prolog_flag(optimise, C), R = [A, B, C]"),
    # a module flag of the source, restored by the pop through set_flag_value
    ("pf42", "current_prolog_flag(back_quotes, A), push_prolog_flag(back_quotes, string), current_prolog_flag(back_quotes, B), pop_prolog_flag(back_quotes), current_prolog_flag(back_quotes, C), R = [A, B, C]"),
]
ids = [i for i, _ in cases]
assert len(set(ids)) == len(ids)
json.dump(cases, open("evidence/F2/push_cases.json", "w"), indent=0)
print(len(cases), "cases")
