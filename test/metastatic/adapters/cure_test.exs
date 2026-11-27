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
      assert {:error, reason} =
               CureSubProcess.parse("let x = 1", cure_cli: nil, parser_bin: "nonexistent")

      assert reason =~ "Cure subprocess parser unavailable"
    end
  end

  describe "Cure availability modes (cure-as-escript-only vs no-cure-whatsoever)" do
    test "no-cure-whatsoever mode returns unavailable error" do
      assert {:error, reason} =
               CureSubProcess.parse("let x = 1", cure_cli: nil, parser_bin: "nonexistent")

      assert reason =~ "Cure subprocess parser unavailable"

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

  describe "Cure.ToMeta.load_beams/1" do
    test "never loads Metastatic modules embedded in the cure escript" do
      before = Cure.module_info(:md5)

      assert [] =
               ToMeta.load_beams([
                 {~c"cure/ebin/Elixir.Metastatic.Adapters.Cure.beam", "not a beam"},
                 {~c"metastatic/ebin/Elixir.Metastatic.Adapters.Cure.ToMeta.beam", "not a beam"}
               ])

      assert Cure.module_info(:md5) == before
      assert function_exported?(Cure, :parse, 1)
    end

    test "loads a Cure module once and never replaces it afterwards" do
      compile_unloaded = fn version ->
        [{mod, binary}] =
          Code.compile_string(
            "defmodule Cure.LoadBeamsProbe do\n  def version, do: #{version}\nend"
          )

        :code.purge(mod)
        :code.delete(mod)
        :code.purge(mod)
        {mod, binary}
      end

      {mod, v1} = compile_unloaded.(1)
      {^mod, v2} = compile_unloaded.(2)

      on_exit(fn ->
        :code.purge(mod)
        :code.delete(mod)
        :code.purge(mod)
      end)

      assert [^mod] = ToMeta.load_beams([{~c"cure/ebin/#{mod}.beam", v1}])
      assert mod.version() == 1

      assert [] = ToMeta.load_beams([{~c"cure/ebin/#{mod}.beam", v2}])
      assert mod.version() == 1
    end

    test "ignores entries that are not beam files" do
      assert [] = ToMeta.load_beams([{~c"cure/priv/std/option.cure", "mod Option"}])
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

    test "reifies atom-named variables and params" do
      meta_ast =
        {:function_def, [name: "slice", params: [{:param, [], :start}, {:param, [], :end}]],
         [
           {:variable, [], :end}
         ]}

      assert {:ok, source} = Cure.unparse(meta_ast)
      assert String.contains?(source, "fn slice(start, end) = end")
    end

    test "normalizes and reifies macro_def" do
      macro_ast =
        {:macro_def, [name: "Every"],
         [
           %{
             kind: :syntax,
             keyword: "value",
             template: {:literal, [subtype: :integer], 100}
           }
         ]}

      normalised = ToMeta.normalize(macro_ast)
      assert AST.conforms?(normalised)

      assert {:ok, source} = Cure.unparse(normalised)
      assert String.contains?(source, "macro Every")
      assert String.contains?(source, "syntax value becomes 100")
    end

    test "parses Cure macro source and conforms when Cure compiler available" do
      if ToMeta.available?() do
        cure_code = "macro Value\n  syntax value becomes 42\nend"
        assert {:ok, ast} = Cure.parse(cure_code)
        assert {:ok, meta_ast, _meta} = Cure.to_meta(ast)
        assert AST.conforms?(meta_ast)
      end
    end
  end

  describe "Cure v0.36.0 source_info handling" do
    test "moves %Cure.MetaAST.SourceInfo{} to :cure_source_info" do
      info = %{__struct__: Cure.MetaAST.SourceInfo, whole: :span}
      ast = {:variable, [source_info: info, line: 3], "x"}

      assert {:variable, meta, "x"} = ToMeta.normalize(ast)
      assert Keyword.get(meta, :cure_source_info) == info
      refute Keyword.has_key?(meta, :source_info)
      assert Keyword.get(meta, :line) == 3
    end

    test "drops source_info when preserve_source_info: false" do
      info = %{__struct__: Cure.MetaAST.SourceInfo, whole: :span}
      ast = {:variable, [source_info: info], "x"}

      assert {:variable, meta, "x"} = ToMeta.normalize(ast, preserve_source_info: false)
      refute Keyword.has_key?(meta, :cure_source_info)
    end
  end

  describe "Cure v0.36.0 node rendering (FromMeta)" do
    test "pattern_match renders `match` with indented arms" do
      ast =
        {:pattern_match, [],
         [
           {:variable, [], "x"},
           {:match_arm, [pattern: {:literal, [subtype: :integer], 0}],
            [{:literal, [subtype: :integer], 1}]},
           {:match_arm, [pattern: {:variable, [], "_"}], [{:literal, [subtype: :integer], 2}]}
         ]}

      assert FromMeta.to_source(ast) ==
               "match x\n  0 -> 1\n  _ -> 2"
    end

    test "match_arm with a guard" do
      ast =
        {:match_arm,
         [
           pattern: {:variable, [], "n"},
           guard:
             {:binary_op, [operator: :>],
              [{:variable, [], "n"}, {:literal, [subtype: :integer], 0}]}
         ], [{:literal, [subtype: :integer], 1}]}

      assert FromMeta.to_source(ast) == "n when n > 0 -> 1"
    end

    test "pickup replaces if/elif" do
      ast =
        {:pickup, [],
         [
           {:pickup_clause, [],
            [
              {:binary_op, [operator: :<], [{:variable, [], "a"}, {:variable, [], "b"}]},
              {:literal, [subtype: :boolean], true}
            ]},
           {:pickup_else, [], [{:literal, [subtype: :boolean], false}]}
         ]}

      assert FromMeta.to_source(ast) ==
               "pickup\n  a < b -> true\n  else -> false"
    end

    test "with_abs renders the convoy pattern" do
      ast =
        {:with_abs, [],
         [
           {:variable, [], "n"},
           {:match_arm, [pattern: {:function_call, [name: "Z"], []}],
            [{:function_call, [name: "empty"], []}]},
           {:match_arm, [pattern: {:function_call, [name: "S"], [{:variable, [], "k"}]}],
            [{:variable, [], "k"}]}
         ]}

      assert FromMeta.to_source(ast) ==
               "with n\n  Z() -> empty()\n  S(k) -> k"
    end

    test "comprehension with a generator" do
      ast =
        {:comprehension, [],
         [
           {:binary_op, [operator: :*],
            [{:variable, [], "x"}, {:literal, [subtype: :integer], 2}]},
           {:generator, [], [{:variable, [], "x"}, {:variable, [], "xs"}]}
         ]}

      assert FromMeta.to_source(ast) == "[x * 2 for x <- xs]"
    end

    test "binary comprehension keeps the generator inside <<>>" do
      ast =
        {:comprehension, [],
         [
           {:variable, [], "b"},
           {:binary_generator, [],
            [
              {:literal, [subtype: :bytes], [{:bin_segment, [], [{:variable, [], "b"}]}]},
              {:variable, [], "buf"}
            ]}
         ]}

      assert FromMeta.to_source(ast) == "[b for <<b <- buf>>]"
    end

    test "refinement_type renders `{x: T | pred}`" do
      ast =
        {:refinement_type, [binder: "x"],
         [
           {:variable, [], "Int"},
           {:binary_op, [operator: :!=],
            [{:variable, [], "x"}, {:literal, [subtype: :integer], 0}]}
         ]}

      assert FromMeta.to_source(ast) == "{x: Int | x != 0}"
    end

    test "sigma_type renders a dependent pair" do
      ast = {:sigma_type, [binder: "x"], [{:variable, [], "Int"}, {:variable, [], "Bool"}]}
      assert FromMeta.to_source(ast) == "Sigma(x: Int, Bool)"
    end

    test "union_type renders members joined by |" do
      ast = {:union_type, [], [{:variable, [], "Int"}, {:variable, [], "Bool"}]}
      assert FromMeta.to_source(ast) == "Int | Bool"
    end

    test "tuple_type renders Tuple(...)" do
      ast = {:tuple_type, [arity: 2], [{:variable, [], "Int"}, {:variable, [], "Bool"}]}
      assert FromMeta.to_source(ast) == "Tuple(Int, Bool)"
    end

    test "arrow_chain renders a function type" do
      ast = {:arrow_chain, [], [{:variable, [], "Int"}, {:variable, [], "Bool"}]}
      assert FromMeta.to_source(ast) == "Int -> Bool"
    end

    test "hole renders ?name" do
      assert FromMeta.to_source({:hole, [name: "goal"], []}) == "?goal"
    end

    test "quoted_syntax and splice" do
      ast =
        {:quoted_syntax, [],
         [
           {:tuple, [],
            [{:literal, [subtype: :symbol], :ok}, {:splice, [], [{:variable, [], "p"}]}]}
         ]}

      assert FromMeta.to_source(ast) == "quote %[:ok, $(p)]"
    end

    test "proof_chain with a simplify justification" do
      ast =
        {:proof_chain, [],
         [
           {:literal, [subtype: :integer], 1},
           {:proof_step, [],
            [
              {:proof_chain_previous, [], []},
              {:literal, [subtype: :integer], 1},
              {:simplify_command, [], []}
            ]}
         ]}

      assert FromMeta.to_source(ast) ==
               "proof chain\n  1 == 1\n  because simplify"
    end

    test "solver_command renders `by decide`" do
      assert FromMeta.to_source({:solver_command, [solver: :decide], []}) == "by decide"
    end

    test "rewrite_command renders direction and target" do
      ast = {:rewrite_command, [direction: :forward], [{:variable, [], "h"}]}
      assert FromMeta.to_source(ast) == "rewrite using h"
    end

    test "induction with cases" do
      ast =
        {:induction, [],
         [
           {:variable, [], "n"},
           {:induction_case, [], [{:variable, [], "Z"}, {:variable, [], "refl"}]}
         ]}

      assert FromMeta.to_source(ast) == "induction n\n  case Z =>\n    refl"
    end

    test "interface renders `interface Name(params)`" do
      ast =
        {:interface, [name: "Show", params: ["t"], requires: []],
         [
           {:function_def,
            [name: "show", params: [{:param, [], "x"}], return_type: {:variable, [], "String"}],
            []}
         ]}

      assert FromMeta.to_source(ast) ==
               "interface Show(t)\n  fn show(x) -> String"
    end

    test "implementation renders `implementation I for T`" do
      ast =
        {:implementation, [interface: "Show", for_type: {:variable, [], "Int"}],
         [
           {:function_def, [name: "show", params: [{:param, [], "x"}]],
            [{:literal, [subtype: :string], "i"}]}
         ]}

      assert FromMeta.to_source(ast) ==
               "implementation Show for Int\n  fn show(x) = \"i\""
    end

    test "declarations_block renders a declarations section" do
      ast =
        {:declarations_block, [],
         [{:function_def, [name: "a", params: []], [{:literal, [subtype: :integer], 1}]}]}

      assert FromMeta.to_source(ast) == "declarations\n  fn a() = 1"
    end

    test "typed_pattern renders `name: Type`" do
      ast = {:typed_pattern, [], ["y", {:variable, [], "Int"}]}
      assert FromMeta.to_source(ast) == "y: Int"
    end

    test "exception_handling renders try/catch" do
      ast =
        {:exception_handling, [],
         [
           {:function_call, [name: "risky"], []},
           {:match_arm, [pattern: {:variable, [], "e"}], [{:literal, [subtype: :integer], 0}]}
         ]}

      assert FromMeta.to_source(ast) ==
               "try\n  risky()\n  catch\n  e -> 0"
    end
  end

  describe "Cure v0.36.0 record & GADT rendering" do
    test "record construction renders `Name{field: value}`" do
      ast =
        {:function_call, [name: "Point", record: true],
         [
           {:pair, [field: :x],
            [{:literal, [subtype: :symbol], :x}, {:literal, [subtype: :integer], 0}]},
           {:pair, [field: :y],
            [{:literal, [subtype: :symbol], :y}, {:literal, [subtype: :integer], 1}]}
         ]}

      assert FromMeta.to_source(ast) == "Point{x: 0, y: 1}"
    end

    test "GADT constructor with named parameters" do
      ast =
        {:gadt_ctor, [name: "mk_pool"],
         [
           {:arrow_chain, [],
            [
              {:named_dom, [name: "capacity"], [{:variable, [], "Int"}]},
              {:function_call, [name: "Pool"], []}
            ]}
         ]}

      assert FromMeta.to_source(ast) == "mk_pool : (capacity: Int) -> Pool()"
    end

    test "GADT constructor with a function-type body keeps arrows" do
      ast =
        {:gadt_ctor, [name: "bs"],
         [
           {:arrow_chain, [],
            [
              {:function_call, [name: "Below"], [{:variable, [], "n"}]},
              {:function_call, [name: "Below"],
               [{:function_call, [name: "S"], [{:variable, [], "n"}]}]}
            ]}
         ]}

      assert FromMeta.to_source(ast) == "bs : Below(n) -> Below(S(n))"
    end

    test "operator function names are backticked" do
      ast = {:function_def, [name: "==", params: [{:param, [], "a"}, {:param, [], "b"}]], []}
      assert FromMeta.to_source(ast) == "fn `==`(a, b)"
    end

    test "reserved-word function names are backticked" do
      ast = {:function_def, [name: "not", params: [{:param, [], "a"}]], []}
      assert FromMeta.to_source(ast) == "fn `not`(a)"
    end
  end

  describe "Cure v0.36.0 container nesting" do
    test "a module container regroups the declarations that follow it" do
      ast =
        {:block, [],
         [
           {:container, [container_type: :module, name: "M"], []},
           {:function_def, [name: "f", params: []], [{:literal, [subtype: :integer], 1}]}
         ]}

      assert FromMeta.to_source(ast) == "mod M\n  fn f() = 1"
    end

    test "an empty module container renders without a trailing body line" do
      ast = {:block, [], [{:container, [container_type: :module, name: "M"], []}]}
      assert FromMeta.to_source(ast) == "mod M"
    end
  end

  describe "Cure v0.36.0 round-trip against the live compiler" do
    @tag :cure_compiler
    test "round-trips representative source through parse -> unparse" do
      if ToMeta.available?() do
        sources = [
          "mod M\n  fn add(a: Int, b: Int) -> Int = a + b\n",
          "mod M\n  rec Point\n    x: Int\n    y: Int\n",
          "mod M\n  fn f(x: Int) -> Int =\n    match x\n      0 -> 1\n      _ -> 2\n",
          "mod M\n  interface Show(t)\n    fn show(x: t) -> String\n"
        ]

        for source <- sources do
          assert {:ok, out} = Cure.round_trip(source), "round-trip failed for #{inspect(source)}"
          assert {:ok, _} = Cure.parse(out), "re-parse failed for #{inspect(out)}"
        end
      end
    end
  end

  describe "Cure v0.36.0 normaliser coverage" do
    test "normalises with_rematch_arm parent patterns" do
      pattern = {:variable, [], "Some"}
      ast = {:with_rematch_arm, [parent_patterns: [pattern], pattern: pattern], []}

      assert {:with_rematch_arm, meta, []} = ToMeta.normalize(ast)
      assert [normalised] = Keyword.get(meta, :parent_patterns)
      assert normalised == pattern
    end

    test "normalises indexed_type params and indices" do
      ast =
        {:indexed_type, [name: "Vec", params: ["a"], indices: [{:param, [], "n"}]],
         [{:gadt_ctor, [name: "Nil"], []}]}

      assert {:indexed_type, meta, _body} = ToMeta.normalize(ast)
      assert [{:param, [], "n"}] = Keyword.get(meta, :indices)
      assert [{:param, [], "a"}] = Keyword.get(meta, :params)
    end

    test "normalises implementation for_type" do
      ast = {:implementation, [interface: "Show", for_type: {:variable, [], "Int"}], []}
      assert {:implementation, meta, []} = ToMeta.normalize(ast)
      assert {:variable, _, "Int"} = Keyword.get(meta, :for_type)
    end

    test "flattens tactic invocation tokens into portable maps" do
      token = %{
        __struct__: __MODULE__.FakeToken,
        type: :identifier,
        value: "simplify",
        line: 3,
        col: 5
      }

      ast = {:tactic_script, [tactic_use_tokens: [token]], [{:simplify_command, [], []}]}

      assert {:tactic_script, meta, _} = ToMeta.normalize(ast)

      assert [%{type: :identifier, value: "simplify", line: 3, col: 5}] =
               Keyword.get(meta, :tactic_use_tokens)
    end

    test "distils macro rule segments into a portable shape" do
      rule = %{
        kind: :syntax,
        keyword: "transition",
        segments: [
          {:hole, %{name: "from", kind: "State"}},
          {:lit, "-"},
          {:lit, "->"},
          {:repeat, {:hole, %{name: "to"}}}
        ],
        template: {:literal, [subtype: :integer], 1}
      }

      ast = {:macro_def, [name: "M"], [rule]}
      assert {:macro_def, _meta, [normalised]} = ToMeta.normalize(ast)

      assert normalised.segments == [
               {:hole, "from"},
               {:lit, "-"},
               {:lit, "->"},
               {:repeat, {:hole, "to"}}
             ]
    end
  end

  describe "Cure v0.36.0 FSM family rendering" do
    test "renders transition rows from the distilled family grammar" do
      grammar = %{
        "definition" => %{
          "transitions" => %{
            fields: ["from", "event", "payload", "to", "when", "update"],
            field_records: [
              %{name: "from", shape: "Name", cardinality: :optional},
              %{name: "event", shape: "Name", cardinality: :required},
              %{name: "payload", shape: "Parameters", cardinality: :optional},
              %{name: "to", shape: "Name", cardinality: :required},
              %{name: "when", shape: "Expression", cardinality: :optional},
              %{name: "update", shape: "Expression", cardinality: :optional}
            ],
            productions: [
              %{
                fields: ["from", "event", "to"],
                segments: [
                  {:hole, "from"},
                  {:lit, "-"},
                  {:lit, "-"},
                  {:hole, "event"},
                  {:lit, "-"},
                  {:lit, "->"},
                  {:hole, "to"}
                ]
              }
            ]
          }
        }
      }

      element =
        {:family_input, [family: "TransitionDefinition"],
         [
           {:variable, [], "Red"},
           {:variable, [], "Timer"},
           {:family_option, [present: false], []},
           {:variable, [], "Green"},
           {:family_option, [present: false], []},
           {:family_option, [present: false], []}
         ]}

      computed =
        {:computed_use, [keyword: "fsm", family_grammar: grammar],
         [
           {:variable, [], "derive_transition_table"},
           {:macro_input, [keyword: "fsm"],
            [
              {:literal, [subtype: :symbol], :"Cure.P.Light"},
              {:variable, [], "Data"},
              {:family_input, [family: "TransitionTableDefinition"],
               [
                 {:family_option, [present: false], []},
                 [],
                 [element]
               ]}
            ]}
         ]}

      assert FromMeta.to_source(computed) =~ "Red --Timer--> Green"
    end
  end
end
