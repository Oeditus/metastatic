defmodule Metastatic.Supplemental.Transformer do
  @moduledoc """
  Helper module for transforming MetaAST using registered supplementals.

  Coordinates between the registry and supplemental modules to perform
  transformations on constructs that don't have native language support.
  """

  alias Metastatic.Supplemental.Registry
  alias Metastatic.Supplemental.Error.MissingSupplementalError

  @doc """
  Attempts to transform a MetaAST construct using a registered supplemental.

  Looks up the appropriate supplemental module for the given language and
  construct, then delegates transformation to that module.

  Returns:
  - `{:ok, transformed}` - Successfully transformed by supplemental
  - `:error` - No supplemental handles this construct
  - `{:error, exception}` - Transformation failed

  ## Examples

      iex> Transformer.transform({:actor_call, actor, msg, timeout}, :python, %{})
      {:ok, python_ast}

      iex> Transformer.transform({:unsupported_construct, val}, :python, %{})
      :error
  """
  @spec transform(term(), atom(), map()) ::
          {:ok, term()} | :error | {:error, Exception.t()}
  def transform(meta_ast, language, metadata) do
    construct_type = extract_construct_type(meta_ast)

    case Registry.get_for_construct(language, construct_type) do
      nil ->
        :error

      supplemental_module ->
        try do
          supplemental_module.transform(meta_ast, language, metadata)
        rescue
          e ->
            {:error, e}
        end
    end
  end

  @doc """
  Attempts to transform, raising an exception if no supplemental is available.

  Similar to `transform/3` but raises `MissingSupplementalError` when no
  supplemental handles the construct.

  ## Examples

      iex> Transformer.transform!({:actor_call, actor, msg, timeout}, :python, %{})
      {:ok, python_ast}

      iex> Transformer.transform!({:unsupported_construct, val}, :python, %{})
      ** (Metastatic.Supplemental.Error.MissingSupplementalError)
  """
  @spec transform!(term(), atom(), map()) :: {:ok, term()} | no_return()
  def transform!(meta_ast, language, metadata) do
    case transform(meta_ast, language, metadata) do
      {:ok, result} ->
        {:ok, result}

      :error ->
        construct_type = extract_construct_type(meta_ast)

        raise MissingSupplementalError,
          construct: construct_type,
          language: language

      {:error, exception} ->
        raise exception
    end
  end

  @doc """
  Checks if a supplemental is available for the given construct and language.

  ## Examples

      iex> Transformer.available?(:actor_call, :python)
      true

      iex> Transformer.available?(:unsupported_construct, :python)
      false
  """
  @spec available?(atom(), atom()) :: boolean()
  def available?(construct, language) do
    Registry.get_for_construct(language, construct) != nil
  end

  @doc """
  Lists all supplemental-supported constructs for a language.

  ## Examples

      iex> Transformer.supported_constructs(:python)
      [:actor_call, :actor_cast, :spawn_actor]
  """
  @spec supported_constructs(atom()) :: [atom()]
  def supported_constructs(language) do
    Registry.available_constructs(language)
  end

  # Private Functions

  defp extract_construct_type(meta_ast) when is_tuple(meta_ast) do
    elem(meta_ast, 0)
  end

  defp extract_construct_type(_), do: :unknown
end
