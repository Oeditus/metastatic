defmodule Metastatic.Adapters.Elixir.MetadataTest do
  @moduledoc """
  Tests for M1 metadata preservation in Elixir adapter.

  Verifies that module context, function context, and location information
  are properly attached to structural nodes (container, function_def).
  """

  use ExUnit.Case, async: true

  alias Metastatic.{AST, Builder}

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
      assert {:container, :module, "MyApp.UserController", nil, [], [], _body, location} = doc.ast
      assert is_map(location)
      assert location.module == "MyApp.UserController"
      assert location.language == :elixir
      assert is_integer(location.line)
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

      assert {:container, :module, "Outer", nil, [], [], body, outer_loc} = doc.ast
      assert outer_loc.module == "Outer"

      # Inner module is in the body
      assert {:container, :module, "Inner", nil, [], [], _inner_body, inner_loc} = body
      assert inner_loc.module == "Inner"
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

      assert {:container, :module, "UserService", nil, [], [], body, _loc} = doc.ast
      assert {:function_def, "create_user", params, nil, opts, _body, location} = body

      # Check function metadata
      assert location.function == "create_user"
      assert location.arity == 2
      assert location.visibility == :public
      assert location.language == :elixir
      assert is_integer(location.line)

      # Check params
      assert length(params) == 2
      assert opts.visibility == :public
    end

    test "distinguishes between public and private functions" do
      source = """
      defmodule Math do
        def add(a, b), do: a + b
        defp multiply(a, b), do: a * b
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, :module, "Math", nil, [], [], {:block, functions}, _loc} = doc.ast
      assert [add_fn, multiply_fn] = functions

      # Public function
      assert {:function_def, "add", _params, nil, _opts, _body, add_loc} = add_fn
      assert add_loc.visibility == :public

      # Private function
      assert {:function_def, "multiply", _params, nil, _opts, _body, mult_loc} = multiply_fn
      assert mult_loc.visibility == :private
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

      assert {:container, :module, "Config", nil, [], [], body, _loc} = doc.ast
      assert {:function_def, "get_api_url", params, nil, _opts, _body, location} = body

      assert location.function == "get_api_url"
      assert location.arity == 0
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

      assert {:container, :module, "List", nil, [], [], {:block, functions}, _loc} = doc.ast
      assert [sum1, sum2] = functions

      # Both clauses have same arity
      assert {:function_def, "sum", params1, nil, _opts1, _body1, loc1} = sum1
      assert {:function_def, "sum", params2, nil, _opts2, _body2, loc2} = sum2

      assert loc1.arity == 1
      assert loc2.arity == 1
      assert length(params1) == 1
      assert length(params2) == 1
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
      assert {:container, :module, "Config", nil, [], [], {:block, [attr1, attr2, func]}, _loc} =
               doc.ast

      # Check first attribute assignment
      assert {:assignment, {:variable, "@api_url"}, {:literal, :string, _url}} = attr1

      # Check second attribute
      assert {:assignment, {:variable, "@timeout"}, {:literal, :integer, 5000}} = attr2

      # Function should have its context
      assert {:function_def, "get_config", [], nil, _opts, _body, func_loc} = func
      assert func_loc.function == "get_config"
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

      assert {:container, :module, "Sample", nil, [], [], {:block, [fn1, fn2]}, container_loc} =
               doc.ast

      # Container should have line 1
      assert container_loc.line == 1

      # Functions should have different line numbers
      assert {:function_def, "first", _, _, _, _, loc1} = fn1
      assert {:function_def, "second", _, _, _, _, loc2} = fn2

      assert is_integer(loc1.line)
      assert is_integer(loc2.line)
      assert loc1.line < loc2.line
    end

    test "always includes language field" do
      source = """
      defmodule Test do
        def test, do: :ok
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, :module, "Test", nil, [], [], body, container_loc} = doc.ast
      assert container_loc.language == :elixir

      assert {:function_def, "test", _, _, _, _, func_loc} = body
      assert func_loc.language == :elixir
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

      assert {:container, :module, "Calculator", nil, [], [], func, _container_loc} = doc.ast

      assert {:function_def, "add", _params, nil, _opts, body, _func_loc} = func

      # The body is a binary_op - may or may not have location metadata
      # But if it does, it should NOT have module/function enrichment
      case body do
        {:binary_op, :arithmetic, :+, left, _right, loc} when is_map(loc) ->
          # Has location, but should not have module/function context
          refute Map.has_key?(loc, :module)
          refute Map.has_key?(loc, :function)
          assert loc.language == :elixir

          # Check left variable too
          case left do
            {:variable, "a", var_loc} when is_map(var_loc) ->
              refute Map.has_key?(var_loc, :module)
              refute Map.has_key?(var_loc, :function)

            {:variable, "a"} ->
              :ok
          end

        {:binary_op, :arithmetic, :+, _left, _right} ->
          # No location is also fine
          :ok
      end
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

      assert {:container, :module, "MyMod", nil, [], [], body, _loc} = doc.ast
      assert {:function_def, "my_func", _params, nil, _opts, _body, _func_loc} = body

      # Use AST.extract_metadata to retrieve context
      module_name = AST.extract_metadata(doc.ast, :module)
      assert module_name == "MyMod"

      func_name = AST.extract_metadata(body, :function)
      assert func_name == "my_func"

      arity = AST.extract_metadata(body, :arity)
      assert arity == 1

      visibility = AST.extract_metadata(body, :visibility)
      assert visibility == :public
    end

    test "node_* convenience functions work" do
      source = """
      defmodule TestMod do
        defp private_func(a, b, c), do: a + b + c
      end
      """

      {:ok, doc} = Builder.from_source(source, :elixir)

      assert {:container, :module, "TestMod", nil, [], [], body, _loc} = doc.ast

      # Use convenience extractors
      assert AST.node_module(doc.ast) == "TestMod"
      assert AST.node_function(body) == "private_func"
      assert AST.node_arity(body) == 3
      assert AST.node_visibility(body) == :private
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

      assert {:container, :module, "MyAppWeb.UserController", nil, [], [], {:block, functions},
              container_loc} = doc.ast

      assert container_loc.module == "MyAppWeb.UserController"
      assert length(functions) == 3

      # Check each function has proper context
      [index, show, render] = functions

      assert {:function_def, "index", _p1, nil, _o1, _b1, loc1} = index
      assert loc1.function == "index"
      assert loc1.arity == 2
      assert loc1.visibility == :public

      assert {:function_def, "show", _p2, nil, _o2, _b2, loc2} = show
      assert loc2.function == "show"
      assert loc2.arity == 2
      assert loc2.visibility == :public

      assert {:function_def, "render", _p3, nil, _o3, _b3, loc3} = render
      assert loc3.function == "render"
      assert loc3.arity == 3
      assert loc3.visibility == :private
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
      assert {:container, :module, "MyWorker", nil, [], [], body, _loc} = doc.ast

      # Body contains: use GenServer macro call + functions
      functions =
        case body do
          {:block, items} ->
            Enum.filter(items, fn
              {:function_def, _, _, _, _, _, _} -> true
              _ -> false
            end)

          {:function_def, _, _, _, _, _, _} = single ->
            [single]
        end

      # Verify all have correct metadata
      Enum.each(functions, fn func ->
        {:function_def, name, params, nil, _opts, _body, loc} = func
        assert is_binary(name)
        assert loc.function == name
        assert loc.arity == length(params)
        assert loc.visibility in [:public, :private]
        assert loc.language == :elixir
      end)
    end
  end
end
