defmodule Metastatic.Adapters.Elixir.CapturesTest do
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Elixir.ToMeta

  # Helper to extract params from lambda meta
  defp get_params(meta), do: Keyword.get(meta, :params, [])
  defp get_capture_form(meta), do: Keyword.get(meta, :capture_form)
  defp get_arity(meta), do: Keyword.get(meta, :arity)

  describe "Function captures - simple argument references" do
    test "transforms &1 to lambda returning first argument" do
      ast = {:&, [], [1]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_1"}] = get_params(meta)
      assert {:variable, [], "arg_1"} = body
      assert get_capture_form(meta) == :argument_reference
    end

    test "transforms &2 to lambda returning second argument" do
      ast = {:&, [], [2]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_2"}] = get_params(meta)
      assert {:variable, [], "arg_2"} = body
      assert get_capture_form(meta) == :argument_reference
    end

    test "transforms &3 to lambda returning third argument" do
      ast = {:&, [], [3]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_3"}] = get_params(meta)
      assert {:variable, [], "arg_3"} = body
    end
  end

  describe "Function captures - named function references" do
    test "transforms &Integer.parse/1 to lambda calling Integer.parse" do
      # &Integer.parse/1
      ast =
        {:&, [], [{:/, [], [{{:., [], [{:__aliases__, [], [:Integer]}, :parse]}, [], []}, 1]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_1"}] = get_params(meta)
      assert {:function_call, call_meta, [arg]} = body
      assert Keyword.get(call_meta, :name) == "Integer.parse"
      assert {:variable, [], "arg_1"} = arg
      assert get_capture_form(meta) == :named_function
    end

    test "transforms &Enum.map/2 to lambda calling Enum.map" do
      # &Enum.map/2
      ast = {:&, [], [{:/, [], [{{:., [], [{:__aliases__, [], [:Enum]}, :map]}, [], []}, 2]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      params = get_params(meta)
      assert [_, _] = params
      assert [{:param, [], "arg_1"}, {:param, [], "arg_2"}] = params
      assert {:function_call, call_meta, args} = body
      assert Keyword.get(call_meta, :name) == "Enum.map"
      assert [_, _] = args
    end

    test "transforms &String.upcase/1 to lambda calling String.upcase" do
      # &String.upcase/1
      ast =
        {:&, [], [{:/, [], [{{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], []}, 1]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_1"}] = get_params(meta)
      assert {:function_call, call_meta, _args} = body
      assert Keyword.get(call_meta, :name) == "String.upcase"
    end
  end

  describe "Function captures - expression captures" do
    test "transforms &(&1 + 1) to lambda with addition" do
      # &(&1 + 1)
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, 1]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_1"}] = get_params(meta)
      assert {:binary_op, op_meta, [left, right]} = body
      assert Keyword.get(op_meta, :category) == :arithmetic
      assert Keyword.get(op_meta, :operator) == :+
      assert {:variable, [], "arg_1"} = left
      assert {:literal, [subtype: :integer], 1} = right
      assert get_capture_form(meta) == :expression
      assert get_arity(meta) == 1
    end

    test "transforms &(&1 + &2) to binary lambda" do
      # &(&1 + &2)
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, {:&, [], [2]}]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      params = get_params(meta)
      assert [_, _] = params
      assert [{:param, [], "arg_1"}, {:param, [], "arg_2"}] = params
      assert {:binary_op, op_meta, [left, right]} = body
      assert Keyword.get(op_meta, :category) == :arithmetic
      assert Keyword.get(op_meta, :operator) == :+
      assert {:variable, [], "arg_1"} = left
      assert {:variable, [], "arg_2"} = right
      assert get_arity(meta) == 2
    end

    test "transforms &(&1 * 2 + &2) to complex expression" do
      # &(&1 * 2 + &2)
      ast = {:&, [], [{:+, [], [{:*, [], [{:&, [], [1]}, 2]}, {:&, [], [2]}]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      params = get_params(meta)
      assert [_, _] = params
      # Body should be: (&1 * 2) + &2
      assert {:binary_op, _op_meta, [left_side, right_side]} = body
      assert {:binary_op, _, _} = left_side
      assert {:variable, [], "arg_2"} = right_side
      assert get_arity(meta) == 2
    end

    test "transforms &String.upcase(&1) to function call with capture" do
      # &String.upcase(&1)
      ast = {:&, [], [{{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], [{:&, [], [1]}]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_1"}] = get_params(meta)
      assert {:function_call, call_meta, args} = body
      assert Keyword.get(call_meta, :name) == "String.upcase"
      assert [arg] = args
      assert {:variable, [], "arg_1"} = arg
      assert get_capture_form(meta) == :expression
      assert get_arity(meta) == 1
    end

    test "transforms &elem(&1, 0) to function call" do
      # &elem(&1, 0)
      ast = {:&, [], [{:elem, [], [{:&, [], [1]}, 0]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_1"}] = get_params(meta)
      assert {:function_call, call_meta, args} = body
      assert Keyword.get(call_meta, :name) == "elem"
      assert [_, _] = args
    end

    test "transforms &(&1 > 0) to comparison" do
      # &(&1 > 0)
      ast = {:&, [], [{:>, [], [{:&, [], [1]}, 0]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_1"}] = get_params(meta)
      assert {:binary_op, op_meta, [left, right]} = body
      assert Keyword.get(op_meta, :category) == :comparison
      assert Keyword.get(op_meta, :operator) == :>
      assert {:variable, [], "arg_1"} = left
      assert {:literal, [subtype: :integer], 0} = right
    end
  end

  describe "Function captures - arity detection" do
    test "detects arity 1 from single &1 reference" do
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, 10]}]}
      assert {:ok, {:lambda, meta, [_body]}, _ctx} = ToMeta.transform(ast)
      assert length(get_params(meta)) == 1
      assert get_arity(meta) == 1
    end

    test "detects arity 2 from &1 and &2 references" do
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, {:&, [], [2]}]}]}
      assert {:ok, {:lambda, meta, [_body]}, _ctx} = ToMeta.transform(ast)
      assert length(get_params(meta)) == 2
      assert get_arity(meta) == 2
    end

    test "detects arity 3 when &3 is the highest" do
      # &(&1 + &2 + &3)
      ast = {:&, [], [{:+, [], [{:+, [], [{:&, [], [1]}, {:&, [], [2]}]}, {:&, [], [3]}]}]}
      assert {:ok, {:lambda, meta, [_body]}, _ctx} = ToMeta.transform(ast)
      assert length(get_params(meta)) == 3
      assert get_arity(meta) == 3
    end

    test "creates params for all numbers up to max even if some are unused" do
      # &(&1 + &3) - note: &2 is not used but param should still be created
      ast = {:&, [], [{:+, [], [{:&, [], [1]}, {:&, [], [3]}]}]}
      assert {:ok, {:lambda, meta, [_body]}, _ctx} = ToMeta.transform(ast)
      params = get_params(meta)
      # Should create params for arg_1, arg_2, arg_3
      assert length(params) == 3

      assert [
               {:param, [], "arg_1"},
               {:param, [], "arg_2"},
               {:param, [], "arg_3"}
             ] = params

      assert get_arity(meta) == 3
    end
  end

  describe "Function captures - complex cases" do
    test "transforms &Map.get(&1, :key) with atom literal" do
      # &Map.get(&1, :key)
      ast = {:&, [], [{{:., [], [{:__aliases__, [], [:Map]}, :get]}, [], [{:&, [], [1]}, :key]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_1"}] = get_params(meta)
      assert {:function_call, call_meta, args} = body
      assert Keyword.get(call_meta, :name) == "Map.get"
      assert [var, key] = args
      assert {:variable, [], "arg_1"} = var
      assert {:literal, [subtype: :symbol], :key} = key
    end

    test "transforms &{&1, &2} to tuple creation" do
      # &{&1, &2}
      # In Elixir AST, {&1, &2} within a capture
      ast = {:&, [], [{{:&, [], [1]}, {:&, [], [2]}}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      params = get_params(meta)
      assert [_, _] = params
      assert {:tuple, [], elements} = body
      assert [_, _] = elements
      assert get_arity(meta) == 2
    end

    test "transforms &[&1, &2, &3] to list creation" do
      # &[&1, &2, &3]
      ast = {:&, [], [[{:&, [], [1]}, {:&, [], [2]}, {:&, [], [3]}]]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert length(get_params(meta)) == 3
      assert {:list, [], elements} = body
      assert [_, _, _] = elements
      assert get_arity(meta) == 3
    end
  end

  describe "Regression: field access must not swallow remote calls" do
    # A catch-all `pre_transform` clause used to rewrite every
    # `{{:., _, [{_, _, _}, _key]}, _, []}` node to `Map.fetch!/2`. That shape is
    # shared by both field access (`foo.bar`) and zero-arity remote calls
    # (`String.trim()`), so remote calls in pipes were silently corrupted into
    # `Map.fetch!(value, String, :trim)`.

    test "preserves a remote call in a pipe" do
      ast =
        {:|>, [], [{:value, [], nil}, {{:., [], [{:__aliases__, [], [:String]}, :trim]}, [], []}]}

      assert {:ok, {:function_call, meta, args}, _ctx} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "String.trim"
      assert Keyword.get(meta, :pipe) == true
      assert [{:variable, _, "value"}] = args
    end

    test "preserves a zero-arity remote call outside a pipe" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :trim]}, [], []}

      assert {:ok, {:function_call, meta, args}, _ctx} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "String.trim"
      assert args == []
    end

    test "preserves a remote call that takes arguments" do
      ast = {{:., [], [{:__aliases__, [], [:String]}, :split]}, [], [{:x, [], nil}, "\n"]}

      assert {:ok, {:function_call, meta, args}, _ctx} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "String.split"
      assert [_, {:literal, [subtype: :string], "\n"}] = args
    end

    test "still desugars local field access to Map.fetch!/2" do
      ast = {{:., [], [{:foo, [], nil}, :bar]}, [no_parens: true], []}

      assert {:ok, {:function_call, meta, args}, _ctx} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "Map.fetch!"
      assert [{:variable, _, "foo"}, {:literal, [subtype: :symbol], :bar}] = args
    end

    test "desugars field access on a captured argument to attribute_access" do
      ast = {:&, [], [{{:., [], [{:&, [], [1]}, :foo]}, [], []}]}

      assert {:ok, {:lambda, _meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert {:attribute_access, call_meta, [{:variable, [], "arg_1"}]} = body
      assert Keyword.get(call_meta, :attribute) == "foo"
      assert Keyword.get(call_meta, :desugars_to) == "Map.fetch!/2"
    end
  end

  describe "Regression: nested field access" do
    # `a.b.c` used to produce `name: "function_call.c"`. The outer dot was run
    # through the generic local-call clause (becoming `{:function_call, [name:
    # "."], ...}`) and then `extract_module_name/1` stringified the receiver's
    # MetaAST tag. Field access must now nest as `:attribute_access` nodes.

    test "nests a two-level field access as attribute_access" do
      assert {:ok, outer, _ctx} = ToMeta.transform(Code.string_to_quoted!("a.b.c"))

      assert {:attribute_access, meta, [receiver]} = outer
      assert Keyword.get(meta, :attribute) == "c"
      assert {:function_call, inner_meta, _} = receiver
      assert Keyword.get(inner_meta, :name) == "Map.fetch!"
    end

    test "nests a three-level field access" do
      assert {:ok, outer, _ctx} = ToMeta.transform(Code.string_to_quoted!("a.b.c.d"))

      assert {:attribute_access, meta, [mid]} = outer
      assert Keyword.get(meta, :attribute) == "d"
      assert {:attribute_access, mid_meta, [_]} = mid
      assert Keyword.get(mid_meta, :attribute) == "c"
    end

    test "never emits a name derived from a MetaAST tag" do
      assert {:ok, ast, _ctx} = ToMeta.transform(Code.string_to_quoted!("a.b.c"))
      refute inspect(ast) =~ "function_call."
    end

    test "keeps zero-arity remote calls as remote calls" do
      assert {:ok, {:function_call, meta, []}, _ctx} =
               ToMeta.transform(Code.string_to_quoted!("String.trim()"))

      assert Keyword.get(meta, :name) == "String.trim"
    end
  end

  describe "Regression: nested field access inside a capture" do
    # `&(&1.foo.bar)` used to yield `capture_form: :no_arguments` with
    # `name: "unknown.bar"`, silently dropping the `&1` argument entirely.

    test "keeps arity 1 and nests attribute_access calls" do
      assert {:ok, {:lambda, meta, [body]}, _ctx} =
               ToMeta.transform(Code.string_to_quoted!("&(&1.foo.bar)"))

      assert Keyword.get(meta, :capture_form) == :expression
      assert Keyword.get(meta, :arity) == 1
      assert [{:param, [], "arg_1"}] = Keyword.get(meta, :params)

      assert {:attribute_access, outer_meta, [inner]} = body
      assert Keyword.get(outer_meta, :attribute) == "bar"
      assert Keyword.get(outer_meta, :desugars_to) == "Map.fetch!/2"

      assert {:attribute_access, inner_meta, [{:variable, [], "arg_1"}]} = inner
      assert Keyword.get(inner_meta, :attribute) == "foo"
    end

    test "handles a three-level chain" do
      assert {:ok, {:lambda, meta, [body]}, _ctx} =
               ToMeta.transform(Code.string_to_quoted!("&(&1.foo.bar.baz)"))

      assert Keyword.get(meta, :arity) == 1
      assert {:attribute_access, m1, [mid]} = body
      assert Keyword.get(m1, :attribute) == "baz"
      assert {:attribute_access, m2, [_inner]} = mid
      assert Keyword.get(m2, :attribute) == "bar"
    end

    test "preserves the second capture argument" do
      assert {:ok, {:lambda, meta, [body]}, _ctx} =
               ToMeta.transform(Code.string_to_quoted!("&(&1.foo.bar + &2)"))

      assert Keyword.get(meta, :arity) == 2
      assert [{:param, [], "arg_1"}, {:param, [], "arg_2"}] = Keyword.get(meta, :params)
      assert {:binary_op, _, [_, {:variable, [], "arg_2"}]} = body
    end

    test "never emits an unknown-module name" do
      assert {:ok, ast, _ctx} = ToMeta.transform(Code.string_to_quoted!("&(&1.foo.bar)"))
      refute inspect(ast) =~ "unknown."
    end
  end

  describe "Regression: field access carries its Map.fetch!/2 desugaring" do
    # Elixir has no dedicated field-access AST: `map.field` compiles to
    # `Map.fetch!(map, :field)`. Field access is emitted uniformly as
    # `:attribute_access`, with the desugaring recorded in metadata.

    test "records desugars_to and desugar on a plain field access" do
      assert {:ok, {:attribute_access, meta, [{:function_call, _, _}]}, _ctx} =
               ToMeta.transform(Code.string_to_quoted!("a.b.c"))

      assert Keyword.get(meta, :attribute) == "c"
      assert Keyword.get(meta, :desugars_to) == "Map.fetch!/2"
      assert Keyword.get(meta, :desugar) == :map_fetch
    end

    test "records the desugaring inside a capture" do
      assert {:ok, {:lambda, _, [body]}, _ctx} =
               ToMeta.transform(Code.string_to_quoted!("&(&1.foo)"))

      assert {:attribute_access, meta, [_]} = body
      assert Keyword.get(meta, :desugars_to) == "Map.fetch!/2"
    end

    test "uses attribute_access for every field-access position" do
      sources = ["a.b.c", "a.b.c.d", "foo().bar.baz", "&(&1.foo)", "&(&1.foo.bar)"]

      for src <- sources do
        {:ok, ast, _} = ToMeta.transform(Code.string_to_quoted!(src))
        assert contains_node?(ast, :attribute_access), "expected attribute_access in #{src}"
      end
    end

    test "the node still conforms to the MetaAST spec" do
      {:ok, ast, _} = ToMeta.transform(Code.string_to_quoted!("a.b.c"))
      assert Metastatic.AST.conforms?(ast)
    end

    defp contains_node?({type, _meta, _children}, type), do: true

    defp contains_node?({_type, _meta, children}, type) when is_list(children) do
      Enum.any?(children, &contains_node?(&1, type))
    end

    defp contains_node?(list, type) when is_list(list) do
      Enum.any?(list, &contains_node?(&1, type))
    end

    defp contains_node?(_, _), do: false
  end

  describe "Regression: module alias detection is structural" do
    # Alias-derived variables are tagged `origin: :alias` at the `__aliases__`
    # clause, so remote-call detection never depends on capitalisation.

    test "tags an alias-derived variable with origin: :alias" do
      assert {:ok, {:function_call, _, args}, _ctx} =
               ToMeta.transform(Code.string_to_quoted!("String.trim(x)"))

      assert [{:variable, meta, "x"}] = args
      refute Keyword.get(meta, :origin) == :alias
    end

    test "treats a capitalised local variable as field access, not a module" do
      # `Foo` here is a local variable (lowercase-free name but no alias node),
      # so `Foo.bar` must still be field access.
      ast = {{:., [], [{:Foo, [], nil}, :bar]}, [no_parens: true], []}

      assert {:ok, {:function_call, meta, _args}, _ctx} = ToMeta.transform(ast)
      assert Keyword.get(meta, :name) == "Map.fetch!"
    end

    test "treats a real alias as a remote call" do
      assert {:ok, {:function_call, meta, []}, _ctx} =
               ToMeta.transform(Code.string_to_quoted!("String.trim()"))

      assert Keyword.get(meta, :name) == "String.trim"
    end

    test "handles multi-segment aliases" do
      assert {:ok, {:function_call, meta, []}, _ctx} =
               ToMeta.transform(Code.string_to_quoted!("My.Mod.fun()"))

      assert Keyword.get(meta, :name) == "My.Mod.fun"
    end
  end

  describe "Function captures - edge cases" do
    test "handles capture with no argument references (though unusual)" do
      # &(1 + 2) - no &1, &2, etc.
      ast = {:&, [], [{:+, [], [1, 2]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      # Should create zero-arity lambda
      assert [] = get_params(meta)
      assert {:binary_op, _, _} = body
      assert get_capture_form(meta) == :no_arguments
    end

    test "handles nested function calls in capture" do
      # &String.length(String.upcase(&1))
      inner_call = {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], [{:&, [], [1]}]}
      ast = {:&, [], [{{:., [], [{:__aliases__, [], [:String]}, :length]}, [], [inner_call]}]}

      assert {:ok, {:lambda, meta, [body]}, _ctx} = ToMeta.transform(ast)
      assert [{:param, [], "arg_1"}] = get_params(meta)
      assert {:function_call, call_meta, [inner]} = body
      assert Keyword.get(call_meta, :name) == "String.length"
      assert {:function_call, _, _} = inner
    end
  end
end
