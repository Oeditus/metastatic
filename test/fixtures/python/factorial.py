def factorial(n):
    """Calculate factorial recursively."""
    if n <= 1:
        return 1
    return n * factorial(n - 1)


def main():
    result = factorial(5)
    print(f"5! = {result}")


if __name__ == "__main__":
    main()
