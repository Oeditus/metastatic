defmodule Metastatic.CrossLanguageConformanceTest do
  @moduledoc """
  Cross-language conformance matrix.

  This test turns the library's central claim — *the same program written in
  different languages produces the same MetaAST* — into a regression-tested
  invariant.

  For each snippet it parses the source in every language that can express
  it, canonicalises the resulting MetaAST with `Metastatic.AST.canonicalize/1`,
  and asserts that all canonical forms are equal.

  ## Scope and known language differences

  The matrix deliberately uses **unambiguous** expressions (literals and
  operators). Bare lowercase identifiers are excluded because Ruby cannot
  distinguish a local variable from a zero-arity method call without scope
  information (`x` is a `send` node unless `x` was assigned earlier); Ruby
  therefore models a bare identifier as a `:function_call`, while other
  languages model it as a `:variable`. That is a genuine language difference,
  not a bug, so it is out of scope for an *equivalence* matrix.

  Only languages whose adapters are available in the current environment are
  exercised; the rest are skipped. This keeps the matrix honest: it never
  asserts agreement with an adapter that was not actually run.
  """

  use ExUnit.Case, async: true

  alias Metastatic.{Adapter, AST, Document, Languages}

  # Snippets that are expressible — and expected to canonicalise identically —
  # across the listed languages. All use literals so that no identifier-scope
  # ambiguity (see moduledoc) can affect the result.
  @matrix [
    {"1 + 2", [:python, :elixir, :erlang, :ruby, :javascript]},
    {"3 * 4", [:python, :elixir, :erlang, :ruby, :javascript]},
    {"10 - 7", [:python, :elixir, :erlang, :ruby, :javascript]},
    {"8 / 2", [:python, :elixir, :erlang, :ruby, :javascript]}
  ]

  describe "cross-language MetaAST equivalence" do
    for {source, languages} <- @matrix do
      @tag :cross_language
      test "#{inspect(source)} canonicalises identically across #{inspect(languages)}" do
        source = unquote(source)
        languages = unquote(languages)

        available = Enum.filter(languages, &adapter_available?/1)

        assert length(available) >= 2,
               "Need at least two available adapters to compare, got #{inspect(available)}"

        canonical_forms =
          Enum.map(available, fn language ->
            {:ok, doc} = Adapter.abstract(adapter_for(language), source, language)
            {language, AST.canonicalize(doc.ast)}
          end)

        [{first_language, first_form} | rest] = canonical_forms

        for {language, form} <- rest do
          assert form == first_form, """
          Cross-language canonicalisation mismatch for #{inspect(source)}.

          #{first_language}: #{inspect(first_form)}
          #{language}: #{inspect(form)}
          """
        end
      end
    end
  end

  describe "Document.equivalent?/2 agrees with canonicalize/1" do
    test "Python and Elixir documents for the same expression are equivalent" do
      {:ok, py} = Adapter.abstract(Metastatic.Adapters.Python, "x + 5", :python)
      {:ok, ex} = Adapter.abstract(Metastatic.Adapters.Elixir, "x + 5", :elixir)

      assert Document.equivalent?(py, ex)
      assert AST.canonicalize(py.ast) == AST.canonicalize(ex.ast)
    end

    test "location metadata does not affect equivalence" do
      a = {:literal, [subtype: :integer, line: 1, col: 0, end_line: 1, end_col: 1], 42}
      b = {:literal, [subtype: :integer, line: 99, col: 7], 42}

      assert AST.canonicalize(a) == AST.canonicalize(b)
    end

    test "semantic metadata differences are detected" do
      a =
        {:binary_op, [operator: :+, line: 1],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

      b =
        {:binary_op, [operator: :-, line: 1],
         [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}

      refute AST.canonicalize(a) == AST.canonicalize(b)
    end

    test "Ruby models a bare identifier as a call (documented difference)" do
      # This is intentionally *not* an equivalence assertion; it documents the
      # one shape where Ruby legitimately diverges.
      {:ok, ruby} = Adapter.abstract(Metastatic.Adapters.Ruby, "x + 5", :ruby)
      {:ok, python} = Adapter.abstract(Metastatic.Adapters.Python, "x + 5", :python)

      refute AST.canonicalize(ruby.ast) == AST.canonicalize(python.ast)
    end
  end

  # -- Helpers --

  defp adapter_available?(language) do
    Languages.supported?(language) and
      match?({:ok, _}, Languages.get_adapter(language)) and
      adapter_runnable?(language)
  end

  defp adapter_for(language) do
    {:ok, adapter} = Languages.get_adapter(language)
    adapter
  end

  # An adapter is runnable if a trivial parse succeeds. This filters out
  # subprocess-backed adapters whose external runtime is missing (e.g. Node,
  # Ruby, Python) without hard-coding environment assumptions.
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
