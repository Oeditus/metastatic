defmodule Metastatic.Adapters.Elixir.MetadataTest do
  @moduledoc """
  Tests for M1 metadata preservation in Elixir adapter.

  Verifies that module context, function context, and location information
  are properly attached to structural nodes (container, function_def).

  New 3-tuple format:
    {:container, meta, children}
    {:function_def, meta, children}

  where meta is a keyword list containing:
    - container_type, name, module, language, line, etc. for containers
    - name, params, visibility, arity, function, language, line, etc. for function_def
  """

  use ExUnit.Case, async: true

  alias Metastatic.Builder

  describe "module context preservation" do
    test "attaches module name to container node" do
      source = """
      defmodule MyApp.UserController do
        def index do
          :ok
        end
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      # Top-level node should be a container with location metadata
      # Body is a list of children in the new 3-tuple format
      assert {:container, meta, _children} = doc.ast
      assert Keyword.get(meta, :container_type) == :module
      assert Keyword.get(meta, :name) == "MyApp.UserController"
      assert Keyword.get(meta, :module) == "MyApp.UserController"
      assert Keyword.get(meta, :language) == :elixir
      assert is_integer(Keyword.get(meta, :line))
    end

    test "preserves module context in nested modules" do
      source = """
      defmodule Outer do
        defmodule Inner do
          :ok
        end
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, outer_meta, children} = doc.ast
      assert Keyword.get(outer_meta, :name) == "Outer"

      # Inner module is in the body (list of children)
      # Could be [inner_module] or just inner_module depending on implementation
      inner =
        case children do
          [child] -> child
          child -> child
        end

      assert {:container, inner_meta, _inner_children} = inner
      assert Keyword.get(inner_meta, :name) == "Inner"
    end
  end

  describe "function context preservation" do
    test "attaches function name and arity to function_def node" do
      source = """
      defmodule UserService do
        def create_user(name, email) do
          {:ok, %{name: name, email: email}}
        end
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, _module_meta, children} = doc.ast
      # Children is a list in 3-tuple format
      [func] = children
      assert {:function_def, meta, _body} = func

      # Check function metadata
      assert Keyword.get(meta, :name) == "create_user"
      assert Keyword.get(meta, :function) == "create_user"
      assert Keyword.get(meta, :arity) == 2
      assert Keyword.get(meta, :visibility) == :public
      assert Keyword.get(meta, :language) == :elixir
      assert is_integer(Keyword.get(meta, :line))

      # Check params
      params = Keyword.get(meta, :params, [])
      assert length(params) == 2
    end

    test "distinguishes between public and private functions" do
      source = """
      defmodule Math do
        def add(a, b), do: a + b
        defp multiply(a, b), do: a * b
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, _module_meta, children} = doc.ast
      # Multiple functions - children is either a block or a list
      functions =
        case children do
          [{:block, _, funcs}] -> funcs
          {:block, _, funcs} -> funcs
          funcs when is_list(funcs) -> funcs
        end

      assert [add_fn, multiply_fn] = functions

      # Public function
      assert {:function_def, add_meta, _} = add_fn
      assert Keyword.get(add_meta, :visibility) == :public

      # Private function
      assert {:function_def, mult_meta, _} = multiply_fn
      assert Keyword.get(mult_meta, :visibility) == :private
    end

    test "handles zero-arity functions" do
      source = """
      defmodule Config do
        def get_api_url do
          "https://api.example.com"
        end
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, _module_meta, children} = doc.ast
      [func] = children
      assert {:function_def, meta, _body} = func

      assert Keyword.get(meta, :name) == "get_api_url"
      assert Keyword.get(meta, :function) == "get_api_url"
      assert Keyword.get(meta, :arity) == 0
      params = Keyword.get(meta, :params, [])
      assert params == []
    end

    test "handles multi-arity functions (multiple clauses)" do
      source = """
      defmodule List do
        def sum([]), do: 0
        def sum([h | t]), do: h + sum(t)
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, _module_meta, children} = doc.ast

      functions =
        case children do
          [{:block, _, funcs}] -> funcs
          {:block, _, funcs} -> funcs
          funcs when is_list(funcs) -> funcs
        end

      assert [sum1, sum2] = functions

      # Both clauses have same arity
      assert {:function_def, meta1, _} = sum1
      assert {:function_def, meta2, _} = sum2

      assert Keyword.get(meta1, :arity) == 1
      assert Keyword.get(meta2, :arity) == 1
      assert length(Keyword.get(meta1, :params, [])) == 1
      assert length(Keyword.get(meta2, :params, [])) == 1
    end
  end

  describe "module attribute metadata" do
    test "preserves location for module attributes" do
      source = """
      defmodule Config do
        @api_url "https://production.example.com"
        @timeout 5000

        def get_config do
          {@api_url, @timeout}
        end
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      # Module attributes are transformed to assignments
      assert {:container, _module_meta, children} = doc.ast

      items =
        case children do
          [{:block, _, list}] -> list
          {:block, _, list} -> list
          list when is_list(list) -> list
        end

      # Find assignments and function
      attrs =
        Enum.filter(items, fn
          {:assignment, _, _} -> true
          _ -> false
        end)

      funcs =
        Enum.filter(items, fn
          {:function_def, _, _} -> true
          _ -> false
        end)

      assert length(attrs) == 2
      assert length(funcs) == 1

      # Check that attributes are assignments
      Enum.each(attrs, fn attr ->
        assert {:assignment, attr_meta, [target, value]} = attr
        assert Keyword.get(attr_meta, :attribute_type) == :module_attribute
        assert {:variable, _, _} = target
        # Value should be a literal
        assert {:literal, _, _} = value
      end)

      # Function should have its context
      [func] = funcs
      assert {:function_def, func_meta, _} = func
      assert Keyword.get(func_meta, :name) == "get_config"
      assert Keyword.get(func_meta, :function) == "get_config"
    end
  end

  describe "location information" do
    test "includes line numbers in location metadata" do
      source = """
      defmodule Sample do
        def first do
          :first
        end

        def second do
          :second
        end
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, container_meta, children} = doc.ast

      functions =
        case children do
          [{:block, _, funcs}] -> funcs
          {:block, _, funcs} -> funcs
          funcs when is_list(funcs) -> funcs
        end

      assert [fn1, fn2] = functions

      # Container should have line 1
      assert Keyword.get(container_meta, :line) == 1

      # Functions should have different line numbers
      assert {:function_def, meta1, _} = fn1
      assert {:function_def, meta2, _} = fn2

      assert is_integer(Keyword.get(meta1, :line))
      assert is_integer(Keyword.get(meta2, :line))
      assert Keyword.get(meta1, :line) < Keyword.get(meta2, :line)
    end

    test "always includes language field" do
      source = """
      defmodule Test do
        def test, do: :ok
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, container_meta, children} = doc.ast
      assert Keyword.get(container_meta, :language) == :elixir

      [func] = children
      assert {:function_def, func_meta, _} = func
      assert Keyword.get(func_meta, :language) == :elixir
    end
  end

  describe "context does NOT propagate to children" do
    test "child nodes do not have module/function context in location" do
      source = """
      defmodule Calculator do
        def add(a, b) do
          a + b
        end
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, _container_meta, children} = doc.ast
      [func] = children
      assert {:function_def, _func_meta, body_children} = func

      # The body is a binary_op - may or may not have location metadata
      # But if it does, it should NOT have module/function enrichment
      [body] = body_children
      assert {:binary_op, op_meta, [left, _right]} = body

      # Has original_meta but should not have module/function context
      refute Keyword.has_key?(op_meta, :module)
      refute Keyword.has_key?(op_meta, :function)

      # Check left variable too
      assert {:variable, var_meta, "a"} = left
      refute Keyword.has_key?(var_meta, :module)
      refute Keyword.has_key?(var_meta, :function)
    end
  end

  describe "AST helper function usage" do
    test "extract_metadata/2 retrieves context from location" do
      source = """
      defmodule MyMod do
        def my_func(x), do: x
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, container_meta, children} = doc.ast
      [func] = children
      assert {:function_def, func_meta, _} = func

      # Use Keyword.get to retrieve context from 3-tuple meta
      module_name = Keyword.get(container_meta, :module)
      assert module_name == "MyMod"

      func_name = Keyword.get(func_meta, :function)
      assert func_name == "my_func"

      arity = Keyword.get(func_meta, :arity)
      assert arity == 1

      visibility = Keyword.get(func_meta, :visibility)
      assert visibility == :public
    end

    test "node_* convenience functions work" do
      source = """
      defmodule TestMod do
        defp private_func(a, b, c), do: a + b + c
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, container_meta, children} = doc.ast
      [func] = children
      assert {:function_def, func_meta, _} = func

      # Use Keyword.get on meta for 3-tuple format
      assert Keyword.get(container_meta, :module) == "TestMod"
      assert Keyword.get(func_meta, :function) == "private_func"
      assert Keyword.get(func_meta, :arity) == 3
      assert Keyword.get(func_meta, :visibility) == :private
    end
  end

  describe "real-world examples" do
    test "Phoenix controller with multiple actions" do
      source = """
      defmodule MyAppWeb.UserController do
        def index(conn, _params) do
          users = Repo.all(User)
          render(conn, "index.html", users: users)
        end

        def show(conn, %{"id" => id}) do
          user = Repo.get!(User, id)
          render(conn, "show.html", user: user)
        end

        defp render(conn, template, assigns) do
          Phoenix.Controller.render(conn, template, assigns)
        end
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, container_meta, children} = doc.ast

      functions =
        case children do
          [{:block, _, funcs}] -> funcs
          {:block, _, funcs} -> funcs
          funcs when is_list(funcs) -> funcs
        end

      assert Keyword.get(container_meta, :module) == "MyAppWeb.UserController"
      assert length(functions) == 3

      # Check each function has proper context
      [index, show, render] = functions

      assert {:function_def, meta1, _} = index
      assert Keyword.get(meta1, :name) == "index"
      assert Keyword.get(meta1, :function) == "index"
      assert Keyword.get(meta1, :arity) == 2
      assert Keyword.get(meta1, :visibility) == :public

      assert {:function_def, meta2, _} = show
      assert Keyword.get(meta2, :name) == "show"
      assert Keyword.get(meta2, :function) == "show"
      assert Keyword.get(meta2, :arity) == 2
      assert Keyword.get(meta2, :visibility) == :public

      assert {:function_def, meta3, _} = render
      assert Keyword.get(meta3, :name) == "render"
      assert Keyword.get(meta3, :function) == "render"
      assert Keyword.get(meta3, :arity) == 3
      assert Keyword.get(meta3, :visibility) == :private
    end

    test "GenServer with callbacks" do
      source = """
      defmodule MyWorker do
        use GenServer

        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end

        def init(state) do
          {:ok, state}
        end

        def handle_call(:get_state, _from, state) do
          {:reply, state, state}
        end

        defp internal_helper(data) do
          process(data)
        end
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      # Extract all function_def nodes
      assert {:container, _container_meta, children} = doc.ast

      # Body contains: use GenServer macro call + functions
      items =
        case children do
          [{:block, _, list}] -> list
          {:block, _, list} -> list
          list when is_list(list) -> list
        end

      functions =
        Enum.filter(items, fn
          {:function_def, _, _} -> true
          _ -> false
        end)

      # Verify all have correct metadata
      Enum.each(functions, fn func ->
        {:function_def, meta, _body} = func
        name = Keyword.get(meta, :name)
        params = Keyword.get(meta, :params, [])

        assert is_binary(name)
        assert Keyword.get(meta, :function) == name
        assert Keyword.get(meta, :arity) == length(params)
        assert Keyword.get(meta, :visibility) in [:public, :private]
        assert Keyword.get(meta, :language) == :elixir
      end)
    end
  end
end
