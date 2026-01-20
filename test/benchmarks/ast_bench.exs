defmodule Metastatic.Benchmarks.ASTBench do
  @moduledoc """
  Benchmarks for core MetaAST operations.

  Run with: mix run test/benchmarks/ast_bench.exs
  """

  alias Metastatic.AST

  def run do
    IO.puts("\n=== MetaAST Core Operations Benchmarks ===\n")

    # Sample ASTs of varying complexity
    simple_ast = {:literal, :integer, 42}

    medium_ast =
      {:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}}

    complex_ast =
      {:binary_op, :arithmetic, :+,
       {:binary_op, :arithmetic, :*, {:variable, "x"}, {:literal, :integer, 2}},
       {:binary_op, :arithmetic, :/, {:variable, "y"}, {:literal, :integer, 3}}}

    deep_ast = build_deep_ast(10)

    benchmarks = %{
      "conforms? - simple literal" => fn -> AST.conforms?(simple_ast) end,
      "conforms? - medium complexity" => fn -> AST.conforms?(medium_ast) end,
      "conforms? - complex expression" => fn -> AST.conforms?(complex_ast) end,
      "conforms? - deep nesting (depth=10)" => fn -> AST.conforms?(deep_ast) end,
      "variables - simple" => fn -> AST.variables(simple_ast) end,
      "variables - medium" => fn -> AST.variables(medium_ast) end,
      "variables - complex" => fn -> AST.variables(complex_ast) end,
      "variables - deep" => fn -> AST.variables(deep_ast) end
    }

    results =
      Enum.map(benchmarks, fn {name, fun} ->
        {time, _result} =
          :timer.tc(fn ->
            Enum.each(1..10_000, fn _ -> fun.() end)
          end)

        avg_time_us = time / 10_000
        ops_per_sec = 1_000_000 / avg_time_us

        {name, avg_time_us, ops_per_sec}
      end)

    # Print results
    IO.puts("| Operation | Avg Time (μs) | Ops/sec |")
    IO.puts("|-----------|---------------|---------|")

    Enum.each(results, fn {name, time_us, ops_per_sec} ->
      IO.puts(
        "| #{String.pad_trailing(name, 35)} | #{:io_lib.format("~8.2f", [time_us])} | #{:io_lib.format("~10.0f", [ops_per_sec])} |"
      )
    end)

    IO.puts("\n=== Summary ===")
    IO.puts("Total benchmarks: #{length(results)}")
    IO.puts("Iterations per benchmark: 10,000")

    :ok
  end

  # Build a deeply nested AST for stress testing
  defp build_deep_ast(0), do: {:literal, :integer, 1}

  defp build_deep_ast(depth) do
    {:binary_op, :arithmetic, :+, build_deep_ast(depth - 1), {:literal, :integer, depth}}
  end
end

# Auto-run when file is executed
if __ENV__.file == Path.absname("test/benchmarks/ast_bench.exs") do
  Metastatic.Benchmarks.ASTBench.run()
end
