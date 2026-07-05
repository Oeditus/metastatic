defmodule Metastatic.Supplemental.Python.Asyncio do
  @moduledoc """
  Supplemental module for Python's `asyncio` library.

  Transforms async/await constructs into asyncio API calls. This supplemental
  handles:
  - `:async_await` - async/await patterns → asyncio.run()
  - `:async_context` - async context managers → async with
  - `:gather` - parallel execution → asyncio.gather()

  ## Examples

      # Transform async function call
      iex> ast = {:async_operation, :async_await,
      ...>   {:function_call, "fetch_data", [
      ...>     {:literal, :string, "https://api.example.com"}
      ...>   ]}}
      iex> {:ok, result} = Metastatic.Supplemental.Python.Asyncio.transform(ast, :python, %{})
      iex> match?({:function_call, "asyncio.run", _}, result)
      true

      # Transform gather for parallel execution
      iex> ast = {:async_operation, :gather, [
      ...>   {:function_call, "fetch_user", [{:literal, :integer, 1}]},
      ...>   {:function_call, "fetch_posts", [{:literal, :integer, 1}]}
      ...> ]}
      iex> {:ok, result} = Metastatic.Supplemental.Python.Asyncio.transform(ast, :python, %{})
      iex> match?({:function_call, "asyncio.gather", _}, result)
      true
  """

  @behaviour Metastatic.Supplemental

  alias Metastatic.Supplemental.Info

  @impl true
  def info do
    %Info{
      name: :asyncio,
      language: :python,
      constructs: [:async_await, :async_context, :gather],
      requires: ["asyncio"],
      description: "Python asyncio library support for async/await patterns"
    }
  end

  @impl true
  def transform(ast, language, opts \\ %{})

  def transform({:async_operation, :async_await, async_call}, :python, _opts) do
    # Transform: async_await(call) → asyncio.run(call)
    result = {:function_call, "asyncio.run", [async_call]}
    {:ok, result}
  end

  def transform({:async_operation, :async_context, {resource, body}}, :python, _opts) do
    # Transform: async_context(resource, body) → async with pattern
    # Represented as language_specific since async with is Python-specific syntax
    result =
      {:language_specific, :python,
       %{
         type: :async_with,
         resource: resource,
         body: body
       }}

    {:ok, result}
  end

  def transform({:async_operation, :gather, tasks}, :python, _opts) when is_list(tasks) do
    # Transform: gather([task1, task2, ...]) → asyncio.gather(task1, task2, ...)
    result = {:function_call, "asyncio.gather", tasks}
    {:ok, result}
  end

  def transform(ast, :python, _opts) do
    {:error,
     {:unsupported_construct, "Asyncio supplemental does not support construct: #{inspect(ast)}"}}
  end

  def transform(_ast, language, _opts) do
    {:error,
     {:incompatible_language, "Asyncio supplemental only supports Python, got: #{language}"}}
  end
end
