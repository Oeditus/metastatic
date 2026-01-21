-module(list_ops).
-export([sum/1, product/1, reverse/1]).

sum([]) -> 0;
sum([H | T]) -> H + sum(T).

product([]) -> 1;
product([H | T]) -> H * product(T).

reverse(List) -> reverse(List, []).

reverse([], Acc) -> Acc;
reverse([H | T], Acc) -> reverse(T, [H | Acc]).
