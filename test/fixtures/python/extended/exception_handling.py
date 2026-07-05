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
