defmodule Metastatic.Adapters.Elixir.MacroExpanderTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir, as: ElixirAdapter
  alias Metastatic.Adapters.Elixir.{FromMeta, ToMeta}
  alias Metastatic.Adapters.Elixir.MacroExpander

  describe "expand_and_annotate/1 - basic expansion" do
    test "expands pipe operator and annotates the boundary" do
      {:ok, surface} = Code.string_to_quoted("1 |> to_string()")
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)

      # The pipe macro should be expanded; the expanded form differs from surface
      # so it should carry __original_macro__
      assert has_original_macro_somewhere?(annotated)
    end

    test "expands unless macro and annotates with original form" do
      {:ok, surface} = Code.string_to_quoted("unless true, do: :never")
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)

      # unless expands to case -- the top-level form should differ from :unless
      {top_form, top_meta, _args} = annotated
      # ExPanda expands unless to case
      assert top_form == :case
      # The annotation should carry the original unless call
      original = Keyword.get(top_meta, :__original_macro__)
      assert original != nil
      assert elem(original, 0) == :unless
    end

    test "preserves literals without annotation" do
      {:ok, surface} = Code.string_to_quoted("42")
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      # Literals don't expand -- should be identical
      assert annotated == 42
    end

    test "preserves simple arithmetic without annotation" do
      {:ok, surface} = Code.string_to_quoted("x + 5")
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      # + is not a macro, so the form atom should stay :+
      assert elem(annotated, 0) == :+
    end

    test "preserves structural forms (defmodule/def) while expanding bodies" do
      source = """
      defmodule Foo do
        def bar(x), do: unless(x, do: :fallback)
      end
      """

      {:ok, surface} = Code.string_to_quoted(source)
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)

      # The top-level form should still be :defmodule
      assert elem(annotated, 0) == :defmodule

      # Somewhere inside, the unless should have been expanded and annotated
      assert has_original_macro_somewhere?(annotated)
    end
  end

  describe "expand_and_annotate_string/1" do
    test "convenience wrapper parses and expands" do
      {:ok, annotated} = MacroExpander.expand_and_annotate_string("unless true, do: :never")
      assert is_tuple(annotated)
      {form, meta, _} = annotated
      assert form == :case
      assert Keyword.has_key?(meta, :__original_macro__)
    end

    test "returns error for invalid syntax" do
      assert {:error, _} = MacroExpander.expand_and_annotate_string("def (")
    end
  end

  describe "integration with ToMeta - :original_macro propagation" do
    test "unless expansion carries :original_macro into MetaAST" do
      {:ok, surface} = Code.string_to_quoted("unless true, do: :never")
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      {:ok, meta_ast, _metadata} = ToMeta.transform(annotated)

      # The expanded form becomes a case (pattern_match in MetaAST)
      # and should carry :original_macro in its keyword meta
      assert has_original_macro_in_meta_ast?(meta_ast)
    end

    test "pipe expansion carries :original_macro into MetaAST" do
      {:ok, surface} = Code.string_to_quoted("1 |> to_string()")
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      {:ok, meta_ast, _metadata} = ToMeta.transform(annotated)

      assert has_original_macro_in_meta_ast?(meta_ast)
    end
  end

  describe "integration with FromMeta - macro reconstruction" do
    test "unless round-trips through expansion preserving original form" do
      source = "unless(true, do: :never)"
      {:ok, surface} = Code.string_to_quoted(source)
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      {:ok, meta_ast, _metadata} = ToMeta.transform(annotated)

      # FromMeta should reconstruct the original unless call
      {:ok, elixir_ast} = FromMeta.transform(meta_ast)
      {:ok, result_source} = ElixirAdapter.unparse(elixir_ast)

      assert result_source =~ "unless"
    end

    test "pipe round-trips through expansion preserving original form" do
      source = "1 |> to_string()"
      {:ok, surface} = Code.string_to_quoted(source)
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      {:ok, meta_ast, _metadata} = ToMeta.transform(annotated)

      {:ok, elixir_ast} = FromMeta.transform(meta_ast)
      {:ok, result_source} = ElixirAdapter.unparse(elixir_ast)

      assert result_source =~ "|>"
    end
  end

  describe "opt-out via adapter" do
    test "expand_macros: false preserves surface AST behavior" do
      {:ok, surface} = Code.string_to_quoted("unless true, do: :never")
      {:ok, meta_ast_expanded, _} = ElixirAdapter.to_meta(surface, expand_macros: true)
      {:ok, meta_ast_surface, _} = ElixirAdapter.to_meta(surface, expand_macros: false)

      # With expansion off, unless is handled by ToMeta's native handler
      # and becomes a :conditional node
      assert elem(meta_ast_surface, 0) == :conditional

      # With expansion on, the top-level MetaAST should carry :original_macro
      assert has_original_macro_in_meta_ast?(meta_ast_expanded)
    end
  end

  describe "nested macros" do
    test "nested pipe and unless both get annotated" do
      source = """
      1 |> to_string() |> unless(do: :never)
      """

      {:ok, surface} = Code.string_to_quoted(source)
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)

      # Both pipe and unless are macros, so we should find annotations
      assert has_original_macro_somewhere?(annotated)
    end
  end

  describe "edge cases" do
    test "empty block expands without error" do
      {:ok, surface} = Code.string_to_quoted("nil")
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      assert annotated == nil
    end

    test "already-expanded AST (no macros) passes through cleanly" do
      {:ok, surface} = Code.string_to_quoted("x = 1 + 2")
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      # No macros to expand, form should be := at the top
      assert elem(annotated, 0) == :=
    end

    test "keyword list do/end blocks are annotated correctly" do
      source = """
      if true do
        :yes
      else
        :no
      end
      """

      {:ok, surface} = Code.string_to_quoted(source)
      {:ok, annotated} = MacroExpander.expand_and_annotate(surface)
      # if is a macro, should be expanded
      assert has_original_macro_somewhere?(annotated)
    end
  end

  # ----- Helpers -----

  # Recursively check if any node in the Elixir AST carries __original_macro__
  defp has_original_macro_somewhere?({_form, meta, args}) when is_list(meta) do
    Keyword.has_key?(meta, :__original_macro__) or
      (is_list(args) and Enum.any?(args, &has_original_macro_somewhere?/1))
  end

  defp has_original_macro_somewhere?(list) when is_list(list) do
    Enum.any?(list, &has_original_macro_somewhere?/1)
  end

  defp has_original_macro_somewhere?({left, right}) do
    has_original_macro_somewhere?(left) or has_original_macro_somewhere?(right)
  end

  defp has_original_macro_somewhere?(_), do: false

  # Recursively check if any MetaAST node carries :original_macro in its keyword meta
  defp has_original_macro_in_meta_ast?({_type, meta, children}) when is_list(meta) do
    Keyword.has_key?(meta, :original_macro) or
      (is_list(children) and Enum.any?(children, &has_original_macro_in_meta_ast?/1))
  end

  defp has_original_macro_in_meta_ast?(list) when is_list(list) do
    Enum.any?(list, &has_original_macro_in_meta_ast?/1)
  end

  defp has_original_macro_in_meta_ast?(_), do: false
end
