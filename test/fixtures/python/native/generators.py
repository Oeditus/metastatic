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
