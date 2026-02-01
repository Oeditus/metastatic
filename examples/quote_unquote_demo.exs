#!/usr/bin/env elixir

# Example: Using Metastatic.quote/2 and Metastatic.unquote/2
#
# These are the top-level convenience functions for working with MetaAST.
# They provide a cleaner API than using Builder directly.

IO.puts("=== Metastatic quote/unquote API Demo ===\n")

# Example 1: Basic quote - parse Python to MetaAST
IO.puts("1. Parse Python code to MetaAST:")
{:ok, ast} = Metastatic.quote("x + 5", :python)
IO.inspect(ast, label: "MetaAST")

# Example 2: Basic unquote - generate Python from MetaAST
IO.puts("\n2. Generate Python from MetaAST:")
simple_ast = {:binary_op, :arithmetic, :+, {:variable, "a"}, {:literal, :integer, 10}}
{:ok, python_code} = Metastatic.unquote(simple_ast, :python)
IO.puts("Python: #{python_code}")

# Example 3: Cross-language translation - Python to Elixir
IO.puts("\n3. Cross-language translation (Python → Elixir):")
{:ok, py_ast} = Metastatic.quote("x + y * 2", :python)
{:ok, elixir_code} = Metastatic.unquote(py_ast, :elixir)
IO.puts("Original Python: x + y * 2")
IO.puts("Generated Elixir: #{elixir_code}")

# Example 4: Round-trip between Python and Elixir
IO.puts("\n4. Round-trip between Python and Elixir:")
original_python = "x + y"
{:ok, ast} = Metastatic.quote(original_python, :python)
{:ok, python_version} = Metastatic.unquote(ast, :python)
{:ok, elixir_version} = Metastatic.unquote(ast, :elixir)

IO.puts("Original Python: #{original_python}")
IO.puts("Python version:  #{python_version}")
IO.puts("Elixir version:  #{elixir_version}")

# Example 5: Working with lists
IO.puts("\n5. Working with lists:")
{:ok, list_ast} = Metastatic.quote("[1, 2, 3]", :python)
{:ok, python_list} = Metastatic.unquote(list_ast, :python)
{:ok, elixir_list} = Metastatic.unquote(list_ast, :elixir)
IO.puts("Python list: #{python_list}")
IO.puts("Elixir list: #{elixir_list}")

# Example 6: Function calls
IO.puts("\n6. Function calls:")
python_func = "print(42)"
{:ok, func_ast} = Metastatic.quote(python_func, :python)
{:ok, elixir_func} = Metastatic.unquote(func_ast, :elixir)
IO.puts("Python: #{python_func}")
IO.puts("Elixir: #{elixir_func}")

IO.puts("\n=== Demo Complete ===")
