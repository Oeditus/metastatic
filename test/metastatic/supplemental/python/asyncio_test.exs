defmodule Metastatic.Supplemental.Python.AsyncioTest do
  use ExUnit.Case, async: true

  alias Metastatic.Supplemental.Python.Asyncio
  alias Metastatic.Supplemental.Info

  doctest Metastatic.Supplemental.Python.Asyncio

  describe "info/0" do
    test "returns correct supplemental metadata" do
      info = Asyncio.info()

      assert %Info{} = info
      assert info.name == :asyncio
      assert info.language == :python
      assert info.constructs == [:async_await, :async_context, :gather]
      assert info.requires == ["asyncio"]
      assert info.description =~ "asyncio"
    end
  end

  describe "transform/3 - async_await" do
    test "transforms simple async await call" do
      ast =
        {:async_operation, :async_await,
         {:function_call, "fetch_data", [{:literal, :string, "https://api.example.com"}]}}

      assert {:ok, result} = Asyncio.transform(ast, :python)

      assert result ==
               {:function_call, "asyncio.run",
                [{:function_call, "fetch_data", [{:literal, :string, "https://api.example.com"}]}]}
    end

    test "transforms async await with multiple arguments" do
      ast =
        {:async_operation, :async_await,
         {:function_call, "fetch_user", [{:literal, :integer, 1}, {:literal, :string, "admin"}]}}

      assert {:ok, result} = Asyncio.transform(ast, :python)

      assert result ==
               {:function_call, "asyncio.run",
                [
                  {:function_call, "fetch_user",
                   [{:literal, :integer, 1}, {:literal, :string, "admin"}]}
                ]}
    end

    test "transforms nested async await" do
      ast =
        {:async_operation, :async_await,
         {:function_call, "process",
          [
            {:async_operation, :async_await,
             {:function_call, "fetch", [{:literal, :string, "data"}]}}
          ]}}

      assert {:ok, result} = Asyncio.transform(ast, :python)

      assert match?({:function_call, "asyncio.run", _}, result)
    end
  end

  describe "transform/3 - async_context" do
    test "transforms async context manager" do
      resource = {:function_call, "open_connection", [{:literal, :string, "db://localhost"}]}
      body = {:block, [{:function_call, "query", [{:literal, :string, "SELECT * FROM users"}]}]}

      ast = {:async_operation, :async_context, {resource, body}}

      assert {:ok, result} = Asyncio.transform(ast, :python)

      assert match?(
               {:language_specific, :python,
                %{
                  type: :async_with,
                  resource: ^resource,
                  body: ^body
                }},
               result
             )
    end

    test "transforms async context with variable binding" do
      resource = {:function_call, "AsyncClient", []}

      body =
        {:block,
         [
           {:assignment, {:variable, "response"},
            {:function_call, "get", [{:literal, :string, "/api/users"}]}}
         ]}

      ast = {:async_operation, :async_context, {resource, body}}

      assert {:ok, result} = Asyncio.transform(ast, :python)
      assert match?({:language_specific, :python, %{type: :async_with}}, result)
    end
  end

  describe "transform/3 - gather" do
    test "transforms gather with multiple tasks" do
      tasks = [
        {:function_call, "fetch_user", [{:literal, :integer, 1}]},
        {:function_call, "fetch_posts", [{:literal, :integer, 1}]},
        {:function_call, "fetch_comments", [{:literal, :integer, 1}]}
      ]

      ast = {:async_operation, :gather, tasks}

      assert {:ok, result} = Asyncio.transform(ast, :python)
      assert result == {:function_call, "asyncio.gather", tasks}
    end

    test "transforms gather with two tasks" do
      tasks = [
        {:function_call, "task1", []},
        {:function_call, "task2", []}
      ]

      ast = {:async_operation, :gather, tasks}

      assert {:ok, result} = Asyncio.transform(ast, :python)
      assert result == {:function_call, "asyncio.gather", tasks}
    end

    test "transforms gather with single task" do
      tasks = [{:function_call, "single_task", [{:literal, :string, "arg"}]}]

      ast = {:async_operation, :gather, tasks}

      assert {:ok, result} = Asyncio.transform(ast, :python)
      assert result == {:function_call, "asyncio.gather", tasks}
    end

    test "transforms gather with empty task list" do
      ast = {:async_operation, :gather, []}

      assert {:ok, result} = Asyncio.transform(ast, :python)
      assert result == {:function_call, "asyncio.gather", []}
    end
  end

  describe "transform/3 - error handling" do
    test "returns error for unsupported async_operation subtype" do
      ast = {:async_operation, :unsupported_type, {:function_call, "foo", []}}

      assert {:error, {:unsupported_construct, message}} = Asyncio.transform(ast, :python)
      assert message =~ "does not support construct"
    end

    test "returns error for non-async_operation construct" do
      ast = {:function_call, "regular_function", []}

      assert {:error, {:unsupported_construct, message}} = Asyncio.transform(ast, :python)
      assert message =~ "does not support construct"
    end

    test "returns error for incompatible language" do
      ast = {:async_operation, :async_await, {:function_call, "fetch", []}}

      assert {:error, {:incompatible_language, message}} = Asyncio.transform(ast, :javascript)
      assert message =~ "only supports Python"
      assert message =~ "javascript"
    end

    test "returns error for non-Python language with gather" do
      ast = {:async_operation, :gather, [{:function_call, "task", []}]}

      assert {:error, {:incompatible_language, _}} = Asyncio.transform(ast, :ruby)
    end
  end

  describe "transform/3 - with options" do
    test "transforms with empty options map" do
      ast =
        {:async_operation, :async_await, {:function_call, "fetch", [{:literal, :string, "data"}]}}

      assert {:ok, result} = Asyncio.transform(ast, :python, %{})
      assert match?({:function_call, "asyncio.run", _}, result)
    end

    test "ignores unknown options" do
      ast = {:async_operation, :gather, [{:function_call, "task", []}]}

      assert {:ok, result} = Asyncio.transform(ast, :python, %{unknown: "option"})
      assert match?({:function_call, "asyncio.gather", _}, result)
    end
  end
end
