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
