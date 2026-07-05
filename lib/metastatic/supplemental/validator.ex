defmodule Metastatic.Supplemental.Validator do
  @moduledoc """
  Validates supplemental module availability and compatibility.

  Analyzes MetaAST documents to detect required supplemental modules
  and checks if they are registered and compatible.
  """

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
    walk_ast(meta_ast, MapSet.new())
    |> MapSet.to_list()
    |> Enum.sort()
  end

  # Private Functions

  defp walk_ast({construct, _} = node, acc) when is_atom(construct) do
    # Add construct if it might need supplemental support
    # (not a core M2.1 type)
    acc =
      if supplemental_construct?(construct) do
        MapSet.put(acc, construct)
      else
        acc
      end

    # Walk children
    node
    |> Tuple.to_list()
    |> Enum.reduce(acc, &walk_ast/2)
  end

  defp walk_ast({construct, _, _} = node, acc) when is_atom(construct) do
    acc =
      if supplemental_construct?(construct) do
        MapSet.put(acc, construct)
      else
        acc
      end

    node
    |> Tuple.to_list()
    |> Enum.reduce(acc, &walk_ast/2)
  end

  defp walk_ast({construct, _, _, _} = node, acc) when is_atom(construct) do
    acc =
      if supplemental_construct?(construct) do
        MapSet.put(acc, construct)
      else
        acc
      end

    node
    |> Tuple.to_list()
    |> Enum.reduce(acc, &walk_ast/2)
  end

  defp walk_ast(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &walk_ast/2)
  end

  defp walk_ast(_, acc), do: acc

  # Core M2.1 constructs that don't need supplementals
  @core_constructs [
    :literal,
    :variable,
    :binary_op,
    :unary_op,
    :function_call,
    :conditional,
    :block,
    :early_return,
    :assignment,
    :inline_match,
    :tuple
  ]

  # Extended M2.2 constructs that don't need supplementals
  @extended_constructs [
    :loop,
    :lambda,
    :collection_op,
    :pattern_match,
    :exception_handling,
    :async_operation
  ]

  # Native M2.3 - always language-specific, not supplemental
  @native_constructs [:language_specific]

  defp supplemental_construct?(construct) do
    construct not in @core_constructs and
      construct not in @extended_constructs and
      construct not in @native_constructs
  end
end
