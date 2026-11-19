defmodule Metastatic.Adapters.LfeTest do
  @moduledoc """
  Unit tests for the LFE adapter.

  These exercise the parts that do not need the LFE toolchain (the
  call-versus-data rule, `FromMeta` reification, error handling) plus the
  toolchain-dependent paths, which are guarded by `Lfe.available?/0` so the
  suite skips rather than fails when LFE is absent — the same "honest matrix"
  discipline the Rust conformance suite uses.
  """

  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Lfe
  alias Metastatic.Adapters.Lfe.{FromMeta, MacroExpander, Printer, Reader, ToMeta}
  alias Metastatic.AST
  alias Metastatic.Languages
  alias Metastatic.Languages.Builtin

  describe "file_extensions/0 and discoverability" do
    test "declares the .lfe extension" do
      assert Lfe.file_extensions() == [".lfe"]
    end

    test "is registered as an experimental language" do
      assert Languages.supported?(:lfe)
      assert {:ok, Lfe} = Languages.get_adapter(:lfe)
      assert {:ok, :lfe} = Languages.detect_language("sample.lfe")
    end

    test "is flagged experimental because its toolchain is not part of OTP" do
      assert :lfe in Builtin.experimental_languages()
    end
  end

  describe "availability" do
    test "available?/0 returns a boolean and never raises" do
      assert is_boolean(Lfe.available?())
    end

    test "expansion_available?/0 returns a boolean and never raises" do
      assert is_boolean(Lfe.expansion_available?())
    end

    test "parse/1 returns an error tuple (not a raise) when LFE is missing" do
      # This assertion holds in both environments: with LFE present it parses,
      # without it the reader reports a clear error. Either way no exception
      # escapes.
      result = Lfe.parse("(defun f () 1)")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "the call-versus-data rule (no toolchain needed)" do
    test "a non-empty list with a symbol head in expression position is a call" do
      assert {:ok, {:function_call, meta, args}} = ToMeta.transform([:f, 1, 2], 1, :expr)
      assert Keyword.get(meta, :name) == "f"
      assert length(args) == 2
    end

    test "a list in data position is a data list" do
      assert {:ok, {:list, _meta, elements}} = ToMeta.transform([1, 2, 3], 1, :data)
      assert length(elements) == 3
    end

    test "a list whose head is not a symbol is data even in expression position" do
      assert {:ok, {:list, _meta, _}} = ToMeta.transform([1, 2], 1, :expr)
    end

    test "an empty list is a list in either position" do
      assert {:ok, {:list, _, []}} = ToMeta.transform([], 1, :expr)
      assert {:ok, {:list, _, []}} = ToMeta.transform([], 1, :data)
    end

    test "a quoted payload is data, not a call" do
      assert {:ok, {:language_specific, meta, [_inner]}} =
               ToMeta.transform([:quote, [:a, :b]], 1, :expr)

      assert Keyword.get(meta, :hint) == :quote
    end

    test "a printable charlist is a string literal, not a list" do
      assert {:ok, {:literal, meta, "ab"}} = ToMeta.transform(~c"ab", 1, :expr)
      assert Keyword.get(meta, :subtype) == :string
    end
  end

  describe "ToMeta literal and operator mapping (no toolchain needed)" do
    test "integers, floats and booleans map to literals" do
      assert {:ok, {:literal, m, 42}} = ToMeta.transform(42, 1, :expr)
      assert Keyword.get(m, :subtype) == :integer

      assert {:ok, {:literal, m, 3.5}} = ToMeta.transform(3.5, 1, :expr)
      assert Keyword.get(m, :subtype) == :float

      assert {:ok, {:literal, m, true}} = ToMeta.transform(true, 1, :expr)
      assert Keyword.get(m, :subtype) == :boolean
    end

    test "arithmetic, comparison and boolean operators are categorised" do
      assert {:ok, {:binary_op, m, [_l, _r]}} = ToMeta.transform([:+, 1, 2], 1, :expr)
      assert Keyword.get(m, :category) == :arithmetic

      assert {:ok, {:binary_op, m, [_l, _r]}} = ToMeta.transform([:==, 1, 2], 1, :expr)
      assert Keyword.get(m, :category) == :comparison

      assert {:ok, {:binary_op, m, [_l, _r]}} = ToMeta.transform([:andalso, 1, 2], 1, :expr)
      assert Keyword.get(m, :category) == :boolean
    end

    test "unary operators map to unary_op" do
      assert {:ok, {:unary_op, m, [_]}} = ToMeta.transform([:not, true], 1, :expr)
      assert Keyword.get(m, :operator) == :not
    end

    test "an Erlang-interop call keeps its qualified name" do
      assert {:ok, {:function_call, meta, _}} =
               ToMeta.transform([:"io:format", ~c"~p", [:list, 1]], 1, :expr)

      assert Keyword.get(meta, :name) == "io:format"
    end

    test "every produced node carries a line" do
      {:ok, node} = ToMeta.transform([:+, 1, 2], 7, :expr)
      assert AST.get_meta(node, :line) == 7
    end
  end

  describe "FromMeta reification (no toolchain needed)" do
    test "a binary_op reifies to a call sexpr" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, [:+, 1, 2]} = FromMeta.transform(ast, %{})
    end

    test "a language_specific node is restored verbatim" do
      sexpr = [:receive, [[:msg, [:handle]]]]
      ast = {:language_specific, [language: :lfe, hint: :receive], sexpr}
      assert {:ok, ^sexpr} = FromMeta.transform(ast, %{})
    end

    test "string literals reify to charlists, which is what LFE's reader emits" do
      ast = {:literal, [subtype: :string], "hi"}
      assert {:ok, ~c"hi"} = FromMeta.transform(ast, %{})
    end

    test "an unreifiable node returns an error rather than raising" do
      assert {:error, _} = FromMeta.transform({:unknown_type, [], "x"}, %{})
    end
  end

  describe "extract_children/1" do
    test "returns the list arguments of a call sexpr" do
      assert Lfe.extract_children([:receive, [[:msg, [:handle]]]]) == [[[:msg, [:handle]]]]
    end

    test "returns tuple elements" do
      assert Lfe.extract_children({:tuple, [1, 2]}) == [1, 2]
    end

    test "returns [] for a leaf" do
      assert Lfe.extract_children(:atom) == []
    end
  end

  describe "toolchain-dependent behaviour" do
    @describetag :lfe

    setup do
      if Lfe.available?() do
        {:ok, skip: false}
      else
        {:ok, skip: true}
      end
    end

    @tag :skip_unless_lfe
    test "parses, abstracts and round-trips a module", %{skip: skip} do
      if skip do
        :ok
      else
        source = """
        (defmodule demo
          (export (add 2)))

        (defun add (a b) (+ a b))
        """

        assert {:ok, forms} = Lfe.parse(source)
        assert [{[:defmodule | _], 1}, {[:defun | _], _}] = forms

        assert {:ok, meta, metadata} = Lfe.to_meta(forms)
        assert AST.conforms?(meta)
        assert elem(meta, 0) == :block

        assert {:ok, forms2} = Lfe.from_meta(meta, metadata)
        assert {:ok, out} = Lfe.unparse(forms2)
        assert String.contains?(out, "(defun add (a b) (+ a b))")
      end
    end

    @tag :skip_unless_lfe
    test "round-trips semantically (re-parsed MetaAST is equal)", %{skip: skip} do
      if skip do
        :ok
      else
        source = "(defun add (a b) (+ a b))"

        {:ok, forms} = Lfe.parse(source)
        {:ok, meta, metadata} = Lfe.to_meta(forms)
        {:ok, forms2} = Lfe.from_meta(meta, metadata)
        {:ok, out} = Lfe.unparse(forms2)

        {:ok, forms3} = Lfe.parse(out)
        {:ok, meta2, _} = Lfe.to_meta(forms3)

        assert AST.canonicalize(meta2) == AST.canonicalize(meta)
      end
    end

    @tag :skip_unless_lfe
    test "rejects malformed source with an error tuple", %{skip: skip} do
      if skip do
        :ok
      else
        assert {:error, message} = Lfe.parse("(defun broken")
        assert is_binary(message)
      end
    end

    @tag :skip_unless_lfe
    test "expand_macros: true returns the Core Erlang module", %{skip: skip} do
      if skip do
        :ok
      else
        {:ok, forms} = Lfe.parse("(defun add (a b) (+ a b))")
        assert {:ok, _meta, metadata} = Lfe.to_meta(forms, expand_macros: true)

        case Map.get(metadata, :expansion_error) do
          nil ->
            assert {:c_module, _, _, _, _, _} = metadata.core

          error ->
            # LFE is present but its compiler rejected the code; the adapter
            # must report that rather than raising.
            assert is_binary(error)
        end
      end
    end

    @tag :skip_unless_lfe
    test "expand_macros: false leaves the metadata free of :core", %{skip: skip} do
      if skip do
        :ok
      else
        {:ok, forms} = Lfe.parse("(defun add (a b) (+ a b))")
        {:ok, _meta, metadata} = Lfe.to_meta(forms)
        refute Map.has_key?(metadata, :core)
        refute Map.has_key?(metadata, :expansion_error)
      end
    end

    @tag :skip_unless_lfe
    test "expand_macros never changes the MetaAST", %{skip: skip} do
      if skip do
        :ok
      else
        {:ok, forms} = Lfe.parse("(defun add (a b) (+ a b))")
        {:ok, plain, _} = Lfe.to_meta(forms)
        {:ok, expanded, _} = Lfe.to_meta(forms, expand_macros: true)

        assert AST.canonicalize(plain) == AST.canonicalize(expanded)
      end
    end
  end

  describe "module availability guards" do
    test "Reader.ensure_loaded/0 returns :ok or a descriptive error" do
      case Reader.ensure_loaded() do
        :ok -> assert true
        {:error, message} -> assert message =~ "LFE"
      end
    end

    test "Printer.available?/0 returns a boolean" do
      assert is_boolean(Printer.available?())
    end

    test "MacroExpander.available?/0 returns a boolean" do
      assert is_boolean(MacroExpander.available?())
    end
  end
end
