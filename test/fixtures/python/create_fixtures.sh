#!/bin/bash

# Boolean logic
cat > core/boolean_logic.py << 'EOF'
# Boolean operations
True and False
x and y
a or b
not x
True and (False or True)
EOF

# Function calls
cat > core/function_calls.py << 'EOF'
# Function calls
foo()
bar(1, 2, 3)
math.sqrt(16)
obj.method()
obj.attr.method(x, y)
EOF

# Conditionals
cat > core/conditionals.py << 'EOF'
# If statements (need proper indentation)
if x > 0:
    result = "positive"
else:
    result = "non-positive"

# Ternary (IfExp)
result = "positive" if x > 0 else "non-positive"
EOF

# Blocks
cat > core/blocks.py << 'EOF'
# Multiple statements
x = 1
y = 2
z = x + y
EOF

# Loops (Extended layer)
cat > extended/loops.py << 'EOF'
# While loop
while x > 0:
    x = x - 1

# For loop
for i in range(10):
    print(i)

# For with iterable
for item in items:
    process(item)
EOF

# Lambdas (Extended layer)
cat > extended/lambdas.py << 'EOF'
# Lambda expressions
lambda x: x * 2
lambda x, y: x + y
lambda: 42
map(lambda x: x ** 2, numbers)
EOF

# Comprehensions (Extended layer)
cat > extended/comprehensions.py << 'EOF'
# List comprehension (simple)
[x * 2 for x in numbers]

# List comprehension with filter
[x for x in numbers if x > 0]

# Dict comprehension
{k: v * 2 for k, v in items.items()}

# Set comprehension
{x ** 2 for x in range(10)}

# Generator expression
(x * 2 for x in numbers)
EOF

# Exception handling (Extended layer)
cat > extended/exception_handling.py << 'EOF'
# Try-except
try:
    risky_operation()
except Exception as e:
    handle_error(e)

# Try-except-finally
try:
    do_something()
except ValueError:
    handle_value_error()
finally:
    cleanup()

# Multiple except clauses
try:
    operation()
except KeyError as e:
    handle_key_error(e)
except TypeError as e:
    handle_type_error(e)
EOF

# Builtin functions (Extended layer)
cat > extended/builtin_functions.py << 'EOF'
# Map, filter, reduce
map(func, iterable)
filter(predicate, iterable)

# List operations
list(iterable)
tuple(iterable)
set(iterable)
EOF

# Decorators (Native layer)
cat > native/decorators.py << 'EOF'
# Function with decorator
@decorator
def foo():
    pass

# Multiple decorators
@decorator1
@decorator2
def bar():
    return 42

# Decorator with arguments
@decorator(arg1, arg2)
def baz():
    pass
EOF

# Context managers (Native layer)
cat > native/context_managers.py << 'EOF'
# With statement
with open("file.txt") as f:
    content = f.read()

# Multiple context managers
with open("input.txt") as fin, open("output.txt") as fout:
    fout.write(fin.read())
EOF

# Generators (Native layer)
cat > native/generators.py << 'EOF'
# Generator function
def fibonacci():
    a, b = 0, 1
    while True:
        yield a
        a, b = b, a + b

# Yield from
def chain_generators():
    yield from gen1()
    yield from gen2()
EOF

# Classes (Native layer)
cat > native/classes.py << 'EOF'
# Simple class
class MyClass:
    def __init__(self, value):
        self.value = value
    
    def method(self):
        return self.value * 2

# Class with inheritance
class Child(Parent):
    pass

# Class with multiple bases
class Multi(Base1, Base2):
    attribute = 42
EOF

# Async/await (Native layer)
cat > native/async_await.py << 'EOF'
# Async function
async def fetch_data():
    result = await api_call()
    return result

# Async for
async def process_stream():
    async for item in stream:
        await process(item)

# Async with
async def use_resource():
    async with get_resource() as resource:
        await resource.use()
EOF

# Imports (Native layer)
cat > native/imports.py << 'EOF'
# Import statements
import os
import sys
from pathlib import Path
from typing import List, Dict
from module import function, Class
from package.submodule import *
import numpy as np
EOF

echo "Fixtures created successfully"
