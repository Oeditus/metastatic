defmodule Metastatic.Benchmarks.ValidationBench do
  @moduledoc """
  Benchmarks for MetaAST validation operations.

  Run with: mix run test/benchmarks/validation_bench.exs
  """

  alias Metastatic.{Document, Validator}

  def run do
    IO.puts("\n=== MetaAST Validation Benchmarks ===\n")

    # Sample documents
    simple_doc = create_doc({:literal, :integer, 42})

    medium_doc =
      create_doc({:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 5}})

    complex_doc = create_doc(build_complex_ast())
    deep_doc = create_doc(build_deep_ast(15))

    benchmarks = %{
      "validate - simple (strict)" => fn ->
        Validator.validate(simple_doc, mode: :strict)
      end,
      "validate - simple (standard)" => fn ->
        Validator.validate(simple_doc, mode: :standard)
      end,
      "validate - medium (strict)" => fn ->
        Validator.validate(medium_doc, mode: :strict)
      end,
      "validate - complex (standard)" => fn ->
        Validator.validate(complex_doc, mode: :standard)
      end,
      "validate - deep (depth=15)" => fn ->
        Validator.validate(deep_doc, mode: :standard)
      end,
      "valid? - simple" => fn ->
        Validator.valid?(simple_doc)
      end,
      "valid? - complex" => fn ->
        Validator.valid?(complex_doc)
      end
    }

    results =
      Enum.map(benchmarks, fn {name, fun} ->
        {time, _result} =
          :timer.tc(fn ->
            Enum.each(1..5_000, fn _ -> fun.() end)
          end)

        avg_time_us = time / 5_000
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
    IO.puts("Iterations per benchmark: 5,000")

    :ok
  end

  defp create_doc(ast) do
    %Document{
      ast: ast,
      language: :test,
      metadata: %{},
      original_source: "test"
    }
  end

  defp build_complex_ast do
    {:conditional, {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 10}},
     {:block,
      [
        {:binary_op, :arithmetic, :+, {:variable, "y"}, {:literal, :integer, 1}},
        {:function_call, {:variable, "print"}, [{:variable, "y"}]}
      ]}, {:block, [{:early_return, {:literal, :integer, 0}}]}}
  end

  defp build_deep_ast(0), do: {:literal, :integer, 1}

  defp build_deep_ast(depth) do
    {:binary_op, :arithmetic, :+, build_deep_ast(depth - 1), {:literal, :integer, depth}}
  end
end

# Auto-run when file is executed
if __ENV__.file == Path.absname("test/benchmarks/validation_bench.exs") do
  Metastatic.Benchmarks.ValidationBench.run()
end
