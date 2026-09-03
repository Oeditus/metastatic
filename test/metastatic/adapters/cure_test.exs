defmodule Metastatic.Adapters.CureTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Cure
  alias Metastatic.Adapters.Cure.{FromMeta, ToMeta}
  alias Metastatic.Adapters.Cure.Subprocess, as: CureSubProcess
  alias Metastatic.AST
  alias Metastatic.Languages

  doctest Metastatic.Adapters.Cure.ToMeta

  describe "Cure adapter integration" do
    test "cure adapter is registered in Languages module" do
      assert {:ok, Cure} == Languages.get_adapter(:cure)
      assert :cure in Languages.supported_languages()
    end

    test "detects .cure file extension" do
      assert {:ok, :cure} == Languages.detect_language("app.cure")
      assert {:ok, :cure} == Languages.detect_language("lib/math/calculator.cure")
    end

    test "implements Metastatic.Adapter behaviour" do
      assert Metastatic.Adapter.valid_adapter?(Cure)
      assert Cure.file_extensions() == [".cure"]
    end
  end

  describe "Cure.ToMeta.normalize/1" do
    test "pass-through for bare literals" do
      ast = {:literal, [subtype: :integer], 42}
      assert ToMeta.normalize(ast) == ast
    end

    test "injects :comment_kind default for comment nodes" do
      assert {:comment, meta, "TODO"} = ToMeta.normalize({:comment, [line: 3], "TODO"})
      assert Keyword.get(meta, :comment_kind) == :line
      assert Keyword.get(meta, :line) == 3
    end

    test "preserves explicit :comment_kind" do
      ast = {:comment, [comment_kind: :doc, line: 1], "Public API"}
      assert ToMeta.normalize(ast) == ast
    end

    test "coerces string bin_segment specifiers to atoms" do
      ast = {:bin_segment, [type: "utf8", signedness: "unsigned"], [{:variable, [], "x"}]}

      assert {:bin_segment, meta, [{:variable, [], "x"}]} = ToMeta.normalize(ast)
      assert Keyword.get(meta, :type) == :utf8
      assert Keyword.get(meta, :signedness) == :unsigned
    end

    test "recursively normalises :bin_segment children of :literal :bytes" do
      ast =
        {:literal, [subtype: :bytes],
         [
           {:bin_segment, [type: :utf8], [{:variable, nil, "x"}]},
           {:bin_segment, [type: :binary], [{:variable, [], "rest"}]}
         ]}

      normalised = ToMeta.normalize(ast)
      assert AST.conforms?(normalised)
      assert AST.variables(normalised) == MapSet.new(["x", "rest"])
    end

    test "leaves raw-binary :bytes payload untouched" do
      ast = {:literal, [subtype: :bytes], <<1, 2, 3>>}
      assert ToMeta.normalize(ast) == ast
    end

    test "normalises nested function_def params" do
      param =
        {:param, [default: {:literal, [subtype: :integer], 0}], "count"}

      fn_ast = {:function_def, [name: "f", params: [param]], []}
      normalised = ToMeta.normalize(fn_ast)

      assert {:function_def, meta, []} = normalised
      assert [normalised_param] = Keyword.get(meta, :params)
      assert normalised_param == param
      assert AST.conforms?(normalised)
    end

    test "from_source parses Cure source code when compiler is available" do
      result = Cure.parse("let x = 42")

      if ToMeta.available?() or match?({:ok, _}, result) do
        assert {:ok, ast} = result
        assert {:ok, meta_ast, metadata} = Cure.to_meta(ast)
        assert AST.conforms?(meta_ast)
        assert metadata.language == :cure
      else
        assert result == {:error, :cure_not_available}
      end
    end

    test "subprocesses fallback returns unavailable error when no binary or CLI is present" do
      assert CureSubProcess.parse("let x = 1", cure_cli: nil, parser_bin: "nonexistent") ==
               {:error, "Cure subprocess parser unavailable"}
    end
  end

  describe "Cure availability modes (cure-as-escript-only vs no-cure-whatsoever)" do
    test "no-cure-whatsoever mode returns unavailable error" do
      assert CureSubProcess.parse("let x = 1", cure_cli: nil, parser_bin: "nonexistent") ==
               {:error, "Cure subprocess parser unavailable"}

      if not ToMeta.available?() do
        assert ToMeta.from_source("let x = 1", cure_cli: nil, parser_bin: "nonexistent") ==
                 {:error, :cure_not_available}
      end
    end

    test "cure-as-escript-only preserves adapter integrity and callbacks" do
      assert Metastatic.Adapter.valid_adapter?(Cure)
      assert function_exported?(Cure, :unparse, 1)
      assert Cure.file_extensions() == [".cure"]
    end
  end

  describe "Cure.FromMeta bin_segment / bytes rendering" do
    test "empty bytes literal renders as <<>>" do
      assert FromMeta.to_source({:literal, [subtype: :bytes], []}) == "<<>>"
    end

    test "raw binary bytes literal renders as comma-separated bytes" do
      assert FromMeta.to_source({:literal, [subtype: :bytes], <<1, 2, 3>>}) ==
               "<<1, 2, 3>>"
    end

    test "single bin_segment with utf8 spec round-trips" do
      ast =
        {:literal, [subtype: :bytes], [{:bin_segment, [type: :utf8], [{:variable, [], "x"}]}]}

      assert FromMeta.to_source(ast) == "<<x::utf8>>"
    end

    test "multi-segment literal with sizes and types" do
      ast =
        {:literal, [subtype: :bytes],
         [
           {:bin_segment, [type: :integer, size: {:literal, [subtype: :integer], 8}],
            [{:variable, [], "size"}]},
           {:bin_segment, [type: :binary], [{:variable, [], "rest"}]}
         ]}

      assert FromMeta.to_source(ast) == "<<size::integer-size(8), rest::binary>>"
    end

    test "bare bin_segment (no specifiers) renders its value" do
      assert FromMeta.to_source({:bin_segment, [], [{:variable, [], "x"}]}) == "x"
    end
  end

  describe "Cure.FromMeta comment rendering" do
    test "line comment" do
      assert FromMeta.to_source({:comment, [comment_kind: :line], "TODO"}) == "# TODO"
    end

    test "doc comment" do
      assert FromMeta.to_source({:comment, [comment_kind: :doc], "Public API"}) ==
               "## Public API"
    end

    test "default comment_kind is :line" do
      assert FromMeta.to_source({:comment, [], "plain"}) == "# plain"
    end
  end

  describe "Cure AST Reification & Round-Trip" do
    test "reifies MetaAST back to Cure source" do
      meta_ast =
        {:function_def, [name: "add", params: [{:param, [], "a"}, {:param, [], "b"}]],
         [
           {:binary_op, [operator: :+], [{:variable, [], "a"}, {:variable, [], "b"}]}
         ]}

      assert {:ok, source} = Cure.unparse(meta_ast)
      assert String.contains?(source, "fn add(a, b) = a + b")
    end
  end
end
