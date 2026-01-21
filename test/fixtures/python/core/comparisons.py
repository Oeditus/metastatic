"""
Core Layer Fixture: Comparison Operations

This fixture demonstrates comparison operations that map to M2.1 Core layer.
"""

# Equality
x == 5
"hello" == "world"

# Inequality
x != 10
a != b

# Less than
x < 100
5 < 10

# Less than or equal
x <= 50
10 <= 10

# Greater than
x > 0
20 > 15

# Greater than or equal
x >= 1
15 >= 15

# Identity comparison
x is None
a is b

# Not identity
x is not None
a is not b

# Chained comparisons (language_specific in MetaAST)
0 < x < 100
a <= b <= c
