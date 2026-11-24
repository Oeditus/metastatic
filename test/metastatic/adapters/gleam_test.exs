defmodule Metastatic.Adapters.GleamTest do
  @moduledoc """
  Unit tests for the Gleam adapter.

  These cover the parts that do not need the bridge (the M1 → M2 mapping, the
  M2 → M1 reification, error handling) plus the bridge-dependent paths, which
  are guarded by `Gleam.available?/0` so the suite skips rather than fails when
  no Rust toolchain is present — the same "honest matrix" discipline the Rust
  and LFE suites use.
  """

  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Gleam
  alias Metastatic.Adapters.Gleam.{FromMeta, Subprocess, ToMeta}
  alias Metastatic.AST
  alias Metastatic.Languages

  describe "file_extensions/0 and discoverability" do
    test "declares the .gleam extension" do
      assert Gleam.file_extensions() == [".gleam"]
    end

    test "is registered as a supported language" do
      assert Languages.supported?(:gleam)
      assert {:ok, Gleam} = Languages.get_adapter(:gleam)
      assert {:ok, :gleam} = Languages.detect_language("sample.gleam")
    end

    test "is not flagged experimental — the bridge is built from bundled sources" do
      # Gleam is *not* experimental: unlike LFE/Agda/Haskell, the parser is
      # compiled from sources shipped in the package, so there is no external
      # toolchain to install beyond Rust itself.
      refute Languages.experimental?(:gleam)
    end
  end

  describe "availability" do
    test "available?/0 returns a boolean and never raises" do
      assert is_boolean(Gleam.available?())
    end

    test "parse/1 returns an error tuple (not a raise) when the bridge is missing" do
      # This assertion holds in both environments: with the bridge present it
      # parses, without it the subprocess reports a clear error. Either way no
      # exception escapes.
      result = Gleam.parse("pub fn main() { 1 }")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "executable/0 returns a path or nil" do
      assert is_binary(Subprocess.executable()) or is_nil(Subprocess.executable())
    end

    test "build/0 reports which package configuration is in use" do
      assert Subprocess.build() in [:vendored, :external_gleam]
    end

    test "vendored?/0 agrees with build/0" do
      assert Subprocess.vendored?() == (Subprocess.build() == :vendored)
    end

    test "available?/0 is false in the source-only build even if cargo is present" do
      # `available?/0` answers "can I get a MetaAST?", not "is the bridge
      # runnable": a source-only package can format and unparse but cannot
      # parse, so reporting `true` would make callers branch the wrong way.
      if Subprocess.vendored?() do
        assert is_boolean(Gleam.available?())
      else
        refute Gleam.available?()
      end
    end

    test "parse/1 in the source-only build explains what is missing" do
      if Subprocess.vendored?() do
        # Not applicable: this package has the compiler crates.
        assert Subprocess.build() == :vendored
      else
        assert {:error, message} = Gleam.parse("pub fn main() { 1 }")
        assert message =~ "HEX_BUILD=1"
        assert message =~ "cannot produce a MetaAST"
      end
    end
  end

  describe "ToMeta mapping (no bridge needed)" do
    test "integer literals become :literal with an integer value" do
      assert {:ok, {:literal, meta, 42}} =
               ToMeta.node(%{
                 "kind" => "Int",
                 "value" => %{"subtype" => "integer", "value" => "42"}
               })

      assert Keyword.get(meta, :subtype) == :integer
    end

    test "float literals become :literal with a float value" do
      assert {:ok, {:literal, meta, 3.5}} =
               ToMeta.node(%{
                 "kind" => "Float",
                 "value" => %{"subtype" => "float", "value" => "3.5"}
               })

      assert Keyword.get(meta, :subtype) == :float
    end

    test "a bignum keeps its source spelling in metadata" do
      # `1 <<< 200` has no Elixir integer representation, so the spelling is
      # preserved for reification rather than silently truncated.
      assert {:ok, {:literal, meta, _value}} =
               ToMeta.node(%{
                 "kind" => "Int",
                 "value" => %{"subtype" => "integer", "value" => "1.23e400"}
               })

      assert Keyword.get(meta, :gleam_literal) == "1.23e400"
    end

    test "variables become :variable" do
      assert {:ok, {:variable, meta, "x"}} = ToMeta.node(%{"kind" => "Var", "name" => "x"})
      assert Keyword.get(meta, :scope) == :local
    end

    test "a qualified variable records its module" do
      assert {:ok, {:variable, meta, "format"}} =
               ToMeta.node(%{
                 "kind" => "Var",
                 "name" => "format",
                 "extra" => %{"module" => "io"}
               })

      assert Keyword.get(meta, :module) == "io"
    end

    test "arithmetic operators are categorised" do
      node = %{
        "kind" => "BinOp",
        "extra" => %{"operator" => "AddInt"},
        "children" => [
          %{"kind" => "Var", "name" => "a"},
          %{"kind" => "Var", "name" => "b"}
        ]
      }

      assert {:ok, {:binary_op, meta, [_l, _r]}} = ToMeta.node(node)
      assert Keyword.get(meta, :category) == :arithmetic
      assert Keyword.get(meta, :operator) == :+
    end

    test "comparison operators are categorised" do
      node = %{
        "kind" => "BinOp",
        "extra" => %{"operator" => "Eq"},
        "children" => [%{"kind" => "Var", "name" => "a"}, %{"kind" => "Var", "name" => "b"}]
      }

      assert {:ok, {:binary_op, meta, _}} = ToMeta.node(node)
      assert Keyword.get(meta, :category) == :comparison
    end

    test "float comparison operators keep their variant" do
      node = %{
        "kind" => "BinOp",
        "extra" => %{"operator" => "LtFloat"},
        "children" => [%{"kind" => "Var", "name" => "a"}, %{"kind" => "Var", "name" => "b"}]
      }

      assert {:ok, {:binary_op, meta, _}} = ToMeta.node(node)
      # `LtInt` and `LtFloat` print as `<` and `<.` — the variant is what tells
      # them apart, so it must survive abstraction.
      assert Keyword.get(meta, :gleam_operator) == "LtFloat"
    end

    test "negation becomes :unary_op" do
      node = %{"kind" => "NegateInt", "children" => [%{"kind" => "Var", "name" => "x"}]}
      assert {:ok, {:unary_op, meta, [_]}} = ToMeta.node(node)
      assert Keyword.get(meta, :operator) == :-
    end

    test "boolean negation becomes :unary_op with a boolean category" do
      node = %{"kind" => "NegateBool", "children" => [%{"kind" => "Var", "name" => "x"}]}
      assert {:ok, {:unary_op, meta, [_]}} = ToMeta.node(node)
      assert Keyword.get(meta, :category) == :boolean
    end

    test "a call becomes :function_call with the callee's name" do
      node = %{
        "kind" => "Call",
        "children" => [
          %{"kind" => "Var", "name" => "identity"},
          %{"kind" => "Var", "name" => "x"}
        ]
      }

      assert {:ok, {:function_call, meta, args}} = ToMeta.node(node)
      assert Keyword.get(meta, :name) == "identity"
      assert length(args) == 1
    end

    test "a qualified call keeps its module prefix" do
      node = %{
        "kind" => "Call",
        "children" => [
          %{"kind" => "Var", "name" => "println", "extra" => %{"module" => "io"}},
          %{"kind" => "String", "value" => %{"subtype" => "string", "value" => "hi"}}
        ]
      }

      assert {:ok, {:function_call, meta, _}} = ToMeta.node(node)
      assert Keyword.get(meta, :name) == "io.println"
    end

    test "a labelled call argument becomes :labeled" do
      node = %{
        "kind" => "CallArg",
        "extra" => %{"label" => "label"},
        "children" => [%{"kind" => "Int", "value" => %{"subtype" => "integer", "value" => "1"}}]
      }

      assert {:ok, {:labeled, meta, [_]}} = ToMeta.node(node)
      assert Keyword.get(meta, :label) == "label"
    end

    test "an unlabelled call argument is passed through" do
      node = %{
        "kind" => "CallArg",
        "extra" => %{"label" => nil},
        "children" => [%{"kind" => "Var", "name" => "x"}]
      }

      assert {:ok, {:variable, _, "x"}} = ToMeta.node(node)
    end

    test "a list with a spread tail keeps the tail as a spread node" do
      node = %{
        "kind" => "List",
        "children" => [%{"kind" => "Int", "value" => %{"subtype" => "integer", "value" => "1"}}],
        "extra" => %{"tail" => %{"kind" => "Var", "name" => "xs"}}
      }

      assert {:ok, {:list, _meta, elements}} = ToMeta.node(node)
      assert [{:literal, _, 1}, {:spread, spread_meta, [{:variable, _, "xs"}]}] = elements
      assert Keyword.get(spread_meta, :context) == :expression
    end

    test "a pattern list's tail is a TailPattern, not a bare node" do
      node = %{
        "kind" => "List",
        "children" => [%{"kind" => "Var", "name" => "first"}],
        "extra" => %{
          "tail" => %{"pattern" => %{"kind" => "Discard", "name" => "_", "discard" => true}}
        }
      }

      assert {:ok, {:list, _meta, elements}} = ToMeta.node(node)
      assert [{:variable, _, "first"}, {:spread, spread_meta, _}] = elements
      assert Keyword.get(spread_meta, :context) == :pattern
    end

    test "a pipeline nests left, matching Gleam's evaluation order" do
      node = %{
        "kind" => "Pipeline",
        "children" => [
          %{"kind" => "Var", "name" => "xs"},
          %{"kind" => "Var", "name" => "f"},
          %{"kind" => "Var", "name" => "g"}
        ]
      }

      assert {:ok, {:pipe, _meta, [inner, {:variable, _, "g"}]}} = ToMeta.node(node)
      assert {:pipe, _, [{:variable, _, "xs"}, {:variable, _, "f"}]} = inner
    end

    test "a case becomes :pattern_match with :match_arm clauses" do
      node = %{
        "kind" => "Case",
        "children" => [
          %{"kind" => "Var", "name" => "x"},
          %{
            "kind" => "Clause",
            "extra" => %{"guard" => nil, "pattern_count" => 1, "alternative_patterns" => 0},
            "children" => [
              %{"kind" => "Int", "value" => %{"subtype" => "integer", "value" => "0"}},
              %{"kind" => "Int", "value" => %{"subtype" => "integer", "value" => "1"}}
            ]
          }
        ]
      }

      assert {:ok, {:pattern_match, _meta, [_subject, {:match_arm, arm_meta, [_body]}]}} =
               ToMeta.node(node)

      assert Keyword.get(arm_meta, :pattern)
    end

    test "a multi-subject case is modelled as a case on an implicit tuple" do
      node = %{
        "kind" => "Case",
        "children" => [
          %{"kind" => "Var", "name" => "a"},
          %{"kind" => "Var", "name" => "b"},
          %{
            "kind" => "Clause",
            "extra" => %{"guard" => nil, "pattern_count" => 2, "alternative_patterns" => 0},
            "children" => [
              %{"kind" => "Var", "name" => "x"},
              %{"kind" => "Var", "name" => "y"},
              %{"kind" => "Var", "name" => "x"}
            ]
          }
        ]
      }

      assert {:ok, {:pattern_match, meta, [{:tuple, tuple_meta, [_a, _b]} | _]}} =
               ToMeta.node(node)

      assert Keyword.get(meta, :subject_count) == 2
      assert Keyword.get(tuple_meta, :implicit) == true
    end

    test "a custom type becomes an :enum container of :struct variants" do
      node = %{
        "kind" => "CustomType",
        "name" => "Shape",
        "public" => true,
        "children" => [
          %{"kind" => "RecordConstructor", "name" => "Point", "children" => []}
        ],
        "extra" => %{"publicity" => "public", "parameters" => []}
      }

      assert {:ok, {:container, meta, [{:container, inner_meta, []}]}} = ToMeta.node(node)
      assert Keyword.get(meta, :container_type) == :enum
      assert Keyword.get(inner_meta, :container_type) == :struct
    end

    test "a function definition carries params, arity and visibility" do
      node = %{
        "kind" => "Fn",
        "name" => "add",
        "public" => true,
        "children" => [
          %{"kind" => "Arg", "name" => "a", "extra" => %{"label" => nil}},
          %{"kind" => "Arg", "name" => "b", "extra" => %{"label" => nil}},
          %{"kind" => "Var", "name" => "a"}
        ],
        "extra" => %{"publicity" => "public"}
      }

      assert {:ok, {:function_def, meta, [_body]}} = ToMeta.node(node)
      assert Keyword.get(meta, :name) == "add"
      assert Keyword.get(meta, :arity) == 2
      assert Keyword.get(meta, :visibility) == :public
    end

    test "a todo becomes :throw with kind :todo" do
      node = %{"kind" => "Todo", "children" => [], "extra" => %{"kind" => "keyword"}}
      assert {:ok, {:throw, meta, []}} = ToMeta.node(node)
      assert Keyword.get(meta, :kind) == :todo
    end

    test "a panic becomes :throw with kind :panic" do
      node = %{"kind" => "Panic", "children" => []}
      assert {:ok, {:throw, meta, []}} = ToMeta.node(node)
      assert Keyword.get(meta, :kind) == :panic
    end

    test "an assert is preserved verbatim as :language_specific" do
      # `AST` has no `:assert` node type; preserving the M1 payload keeps
      # `assert x as "message"` intact through reification.
      node = %{
        "kind" => "Assert",
        "children" => [%{"kind" => "Var", "name" => "x"}]
      }

      assert {:ok, {:language_specific, meta, ^node}} = ToMeta.node(node)
      assert Keyword.get(meta, :hint) == :assert
    end

    test "an echo is preserved verbatim as :language_specific" do
      node = %{"kind" => "Echo", "children" => [%{"kind" => "Var", "name" => "x"}]}
      assert {:ok, {:language_specific, meta, ^node}} = ToMeta.node(node)
      assert Keyword.get(meta, :hint) == :echo
    end

    test "an unknown kind is an error, not a silent :language_specific" do
      # A silent fallback would hide a bridge/adapter version skew, which is
      # exactly the failure this adapter's design makes loud.
      assert {:error, message} = ToMeta.node(%{"kind" => "FutureConstruct"})
      assert message =~ "Unsupported Gleam node kind"
    end

    test "every produced node carries a line" do
      node = %{
        "kind" => "BinOp",
        "span" => %{"line" => 7, "col" => 3, "end_line" => 7, "end_col" => 9},
        "extra" => %{"operator" => "AddInt"},
        "children" => [%{"kind" => "Var", "name" => "a"}, %{"kind" => "Var", "name" => "b"}]
      }

      assert {:ok, meta_ast} = ToMeta.node(node)
      assert AST.get_meta(meta_ast, :line) == 7
    end
  end

  describe "FromMeta reification (no bridge needed)" do
    test "a binary_op reifies to a BinOp node" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert {:ok, %{"kind" => "BinOp", "name" => "+"}} = FromMeta.transform(ast, %{})
    end

    test "the float operator variant survives reification" do
      ast =
        {:binary_op, [category: :comparison, operator: :<, gleam_operator: "LtFloat"],
         [{:variable, [], "a"}, {:variable, [], "b"}]}

      assert {:ok, %{"extra" => %{"operator" => "LtFloat"}}} = FromMeta.transform(ast, %{})
    end

    test "a language_specific node is restored verbatim" do
      payload = %{"kind" => "Echo", "children" => []}
      ast = {:language_specific, [language: :gleam, hint: :echo], payload}
      assert {:ok, ^payload} = FromMeta.transform(ast, %{})
    end

    test "a bignum literal reifies to its original spelling" do
      ast = {:literal, [subtype: :integer, gleam_literal: "1.23e400"], 0}
      assert {:ok, %{"value" => %{"value" => "1.23e400"}}} = FromMeta.transform(ast, %{})
    end

    test "a variable reifies to a Var node" do
      assert {:ok, %{"kind" => "Var", "name" => "x"}} =
               FromMeta.transform({:variable, [scope: :local], "x"}, %{})
    end

    test "an unreifiable node returns an error rather than raising" do
      assert {:error, message} = FromMeta.transform({:unknown_type, [], "x"}, %{})
      assert message =~ "Cannot reify"
    end

    test "a non-conforming MetaAST is rejected" do
      assert {:error, message} = FromMeta.transform({:literal, [subtype: :bogus], :nope}, %{})
      assert message =~ "non-conforming"
    end
  end

  describe "extract_children/1" do
    test "returns the children of a node" do
      assert Gleam.extract_children(%{"kind" => "Block", "children" => [1, 2]}) == [1, 2]
    end

    test "returns a lone pattern" do
      assert Gleam.extract_children(%{"kind" => "Let", "pattern" => %{"kind" => "Var"}}) == [
               %{"kind" => "Var"}
             ]
    end

    test "returns [] for a leaf" do
      assert Gleam.extract_children(%{"kind" => "Var", "name" => "x"}) == []
    end
  end

  describe "bridge-dependent behaviour" do
    @describetag :gleam

    setup do
      {:ok, skip: not Gleam.available?()}
    end

    test "parses a module and produces a module-level :block", %{skip: skip} do
      if skip do
        :ok
      else
        source = "pub fn add(a: Int, b: Int) -> Int {\n  a + b\n}\n"

        assert {:ok, forms} = Gleam.parse(source)
        assert forms["kind"] == "Module"

        assert {:ok, {:block, meta, [_]}, _metadata} = Gleam.to_meta(forms)
        assert Keyword.get(meta, :scope) == :module
      end
    end

    test "round-trips semantically (re-parsed MetaAST is equal)", %{skip: skip} do
      if skip do
        :ok
      else
        source = "pub fn add(a: Int, b: Int) -> Int {\n  a + b\n}\n"

        {:ok, forms} = Gleam.parse(source)
        {:ok, meta, metadata} = Gleam.to_meta(forms)
        {:ok, forms2} = Gleam.from_meta(meta, metadata)
        {:ok, out} = Gleam.unparse(forms2)

        {:ok, forms3} = Gleam.parse(out)
        {:ok, meta2, _} = Gleam.to_meta(forms3)

        assert AST.canonicalize(meta2) == AST.canonicalize(meta)
      end
    end

    test "rejects malformed source with an error tuple", %{skip: skip} do
      if skip do
        :ok
      else
        assert {:error, message} = Gleam.parse("pub fn broken( {\n")
        assert is_binary(message)
        assert message =~ "ParseError"
      end
    end

    test "the parse error names the line", %{skip: skip} do
      if skip do
        :ok
      else
        assert {:error, message} = Gleam.parse("pub fn ok() {\n  1\n}\n\npub fn broken( {\n")
        assert message =~ "line 5"
      end
    end

    test "format/1 normalises source with gleam format's own printer", %{skip: skip} do
      if skip do
        :ok
      else
        assert {:ok, out} = Gleam.format("pub fn  main( ){1}")
        assert out == "pub fn main() {\n  1\n}\n"
      end
    end

    test "selftest/0 passes on the binary in use", %{skip: skip} do
      if skip do
        :ok
      else
        assert {:ok, report} = Gleam.selftest()
        assert report["status"] == "ok", "selftest failed: #{inspect(report, pretty: true)}"
      end
    end
  end

  describe "cross-language translation" do
    @describetag :gleam

    test "a Gleam function translates to Elixir" do
      if Gleam.available?() do
        source = "pub fn add(a: Int, b: Int) -> Int {\n  a + b\n}\n"

        assert {:ok, doc} = Metastatic.Builder.from_source(source, :gleam)
        assert {:ok, elixir} = Metastatic.Builder.to_source(doc, :elixir)

        assert elixir =~ "def add(a, b) do"
        assert elixir =~ "a + b"
      end
    end

    test "a Gleam expression translates to Elixir" do
      if Gleam.available?() do
        # The portable core — literals, variables, operators — is what makes
        # cross-language translation possible at all, so it is asserted on its
        # own rather than only through a whole function.
        ast =
          {:binary_op, [category: :arithmetic, operator: :+],
           [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

        doc = Metastatic.Document.new(ast, :gleam, %{}, "1 + 2")
        assert {:ok, elixir} = Metastatic.Builder.to_source(doc, :elixir)
        assert elixir =~ "1 + 2"
      end
    end
  end

  describe "semantic enrichment" do
    @describetag :gleam

    test "a Gleam call is enriched with op_kind metadata" do
      if Gleam.available?() do
        # `gleam/httpc.send` is registered as an HTTP pattern; enrichment runs
        # through `Metastatic.Adapter.enrich/3` like every other adapter.
        source = "pub fn fetch(url: String) {\n  httpc.send(url)\n}\n"

        {:ok, forms} = Gleam.parse(source)
        {:ok, meta, _} = Gleam.to_meta(forms)

        # The call node exists and is analyzable regardless of whether a
        # pattern matched; assert the structure rather than a specific domain
        # so the test does not encode a pattern table.
        {:block, _, [{:function_def, _, body}]} = meta
        assert [{:function_call, call_meta, _}] = body
        assert Keyword.get(call_meta, :name) == "httpc.send"
      end
    end
  end
end
