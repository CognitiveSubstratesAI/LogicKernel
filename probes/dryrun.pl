% ordinary
% Dry-run probe for probe.yml (D-0947 1): prints swipl version and one arithmetic identity.
main :- current_prolog_flag(version, V), format("version=~w~n", [V]), X is 1 + 1.0, format("1+1.0=~w~n", [X]).
