defmodule Metastatic.Supplemental.Validator do
  @moduledoc """
  Validates supplemental module availability and compatibility.

  Analyzes MetaAST documents to detect required supplemental modules
  and checks if they are registered and compatible.
  """

  alias Metastatic.AST
  alias Metastatic.Document
  alias Metastatic.Supplemental.Registry

  @doc """
  Analyzes a document to detect required supplementals for target language.

  Returns analysis result with required and available supplementals.

  ## Examples

      iex> Validator.analyze(document, :python)
      {:ok, %{required: [:actor_call], available: [:actor_call], missing: []}}

      iex> Validator.analyze(document_with_actors, :python)
      {:error, %{required: [:actor_call], available: [], missing: [:actor_call]}}
  """
  @spec analyze(Document.t(), atom()) ::
          {:ok, map()} | {:error, map()}
  def analyze(%Document{} = document, target_language) do
    required = detect_required_constructs(document.ast)
    available = Registry.available_constructs(target_language)

    missing = required -- available

    result = %{
      required: required,
      available: available,
      missing: missing
    }

    if Enum.empty?(missing) do
      {:ok, result}
    else
      {:error, result}
    end
  end

  @doc """
  Checks if all required supplementals are available for a language.

  ## Examples

      iex> Validator.compatible?(document, :python)
      true
  """
  @spec compatible?(Document.t(), atom()) :: boolean()
  def compatible?(%Document{} = document, target_language) do
    case analyze(document, target_language) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Lists all supplemental-requiring constructs in a MetaAST.

  ## Examples

      iex> Validator.detect_required_constructs(meta_ast)
      [:actor_call, :spawn_actor]
  """
  @spec detect_required_constructs(term()) :: [atom()]
  def detect_required_constructs(meta_ast) do
    {_ast, required} =
      AST.traverse(
        meta_ast,
        MapSet.new(),
        fn
          {type, _meta, _children} = node, acc when is_atom(type) ->
            if supplemental_construct?(type) do
              {node, MapSet.put(acc, type)}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end,
        fn node, acc -> {node, acc} end
      )

    required
    |> MapSet.to_list()
    |> Enum.sort()
  end

  # A construct needs supplemental support when it is not a recognised
  # MetaAST layer type (i.e. `AST.layer/1` returns `:unknown`). This reuses
  # the single source of truth in `Metastatic.AST` instead of maintaining a
  # second, drift-prone copy of the core/extended type lists.
  defp supplemental_construct?(type) do
    AST.layer(type) == :unknown
  end
end
