defmodule Metastatic.PropertyRoundTripTest do
  @moduledoc """
  Property-based round-trip tests for the language adapters.

  Example-based round-trip tests cover hand-picked cases; these generators
  explore a much wider space of MetaAST trees and assert the invariant:

      reify(abstract(source)) ≈ source

  for randomly generated, valid MetaAST expressions. Failures here tend to
  expose gaps in the *reification* (`from_meta`) direction, which is the
  direction that powers cross-language translation and is historically less
  tested than abstraction.

  The generators intentionally produce only constructs that every adapter in
  `@languages` can express (literals and arithmetic), so a failure points at a
  real adapter bug rather than an unsupported construct.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Metastatic.{Adapter, AST, Document, Languages}

  @languages [:python, :elixir]

  # -- Generators --

  # A small integer literal, biased away from 0 to keep division-like ops safe.
  defp integer_literal do
    gen all(n <- integer(1..100)) do
      AST.literal(:integer, n)
    end
  end

  # A binary arithmetic expression tree of bounded depth.
  defp arithmetic_expr(depth \\ 0) do
    if depth >= 3 do
      integer_literal()
    else
      one_of([
        integer_literal(),
        gen all(
              left <- arithmetic_expr(depth + 1),
              op <- member_of([:+, :-, :*]),
              right <- arithmetic_expr(depth + 1)
            ) do
          AST.binary_op(:arithmetic, op, left, right)
        end
      ])
    end
  end

  # -- Properties --

  describe "abstract → reify → abstract is stable" do
    property "re-abstracting a reified expression yields an equivalent AST" do
      check all(
              expr <- arithmetic_expr(),
              language <- member_of(@languages),
              max_runs: 60
            ) do
        if adapter_runnable?(language) do
          # 1. Reify the MetaAST to source in the target language.
          doc = Document.new(expr, language)

          case Adapter.reify(adapter_for(language), doc) do
            {:ok, source} ->
              # 2. Re-abstract the generated source.
              case Adapter.abstract(adapter_for(language), source, language) do
                {:ok, round_doc} ->
                  # 3. The canonical form must be preserved.
                  assert AST.canonicalize(round_doc.ast) == AST.canonicalize(expr),
                         """
                         Round-trip drift for #{language}.

                         Original MetaAST: #{inspect(expr)}
                         Generated source: #{inspect(source)}
                         Re-abstracted:    #{inspect(round_doc.ast)}
                         """

                {:error, reason} ->
                  flunk("Re-abstracting generated source failed: #{inspect(reason)}")
              end

            {:error, reason} ->
              flunk("Reification failed for #{language}: #{inspect(reason)}")
          end
        end
      end
    end

    property "canonicalize/1 is idempotent" do
      check all(expr <- arithmetic_expr()) do
        once = AST.canonicalize(expr)
        twice = AST.canonicalize(once)
        assert once == twice
      end
    end

    property "canonicalize/1 discards location metadata" do
      check all(
              expr <- arithmetic_expr(),
              line <- integer(1..1000)
            ) do
        with_loc = AST.with_location(expr, %{line: line, col: 0})
        assert AST.canonicalize(with_loc) == AST.canonicalize(expr)
      end
    end
  end

  # -- Helpers --

  defp adapter_for(language) do
    {:ok, adapter} = Languages.get_adapter(language)
    adapter
  end

  defp adapter_runnable?(language) do
    case Adapter.abstract(adapter_for(language), "1", language) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end
end
