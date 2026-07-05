# Enum operations - M2.2 Extended Layer

# Enum.map
Enum.map([1, 2, 3], fn x -> x * 2 end)

# Enum.filter
Enum.filter([1, 2, 3, 4, 5], fn x -> rem(x, 2) == 0 end)

# Enum.reduce
Enum.reduce([1, 2, 3], 0, fn x, acc -> acc + x end)

# Comprehension (transforms to collection_op)
for x <- [1, 2, 3], do: x * 2

# Comprehension with filter
for x <- [1, 2, 3, 4, 5], rem(x, 2) == 0, do: x
