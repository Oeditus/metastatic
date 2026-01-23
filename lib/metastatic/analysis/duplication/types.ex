defmodule Metastatic.Analysis.Duplication.Types do
  @moduledoc """
  Clone type definitions for code duplication detection.

  Defines four standard types of code clones based on academic research:

  - **Type I**: Exact clones (identical code, ignoring whitespace/comments)
  - **Type II**: Renamed clones (identical structure, different identifiers/literals)
  - **Type III**: Near-miss clones (similar structure with minor modifications)
  - **Type IV**: Semantic clones (different syntax, same behavior)

  ## References

  - Chanchal K. Roy and James R. Cordy. "A Survey on Software Clone Detection Research" (2007)
  - Ira Baxter et al. "Clone Detection Using Abstract Syntax Trees" (1998)

  ## Examples

      iex> Metastatic.Analysis.Duplication.Types.type_i()
      :type_i

      iex> Metastatic.Analysis.Duplication.Types.all_types()
      [:type_i, :type_ii, :type_iii, :type_iv]
  """

  @typedoc """
  Clone type classification.

  - `:type_i` - Exact clones (identical AST)
  - `:type_ii` - Renamed clones (identical structure, different names)
  - `:type_iii` - Near-miss clones (similar with modifications)
  - `:type_iv` - Semantic clones (different syntax, same semantics)
  """
  @type clone_type :: :type_i | :type_ii | :type_iii | :type_iv

  @doc """
  Returns the Type I clone type atom.

  Type I clones are exact copies with identical AST structure.
  Only whitespace and comments may differ.

  ## Examples

      iex> Metastatic.Analysis.Duplication.Types.type_i()
      :type_i
  """
  @spec type_i() :: :type_i
  def type_i, do: :type_i

  @doc """
  Returns the Type II clone type atom.

  Type II clones have identical structure but different
  variable names, literal values, or function names.

  ## Examples

      iex> Metastatic.Analysis.Duplication.Types.type_ii()
      :type_ii
  """
  @spec type_ii() :: :type_ii
  def type_ii, do: :type_ii

  @doc """
  Returns the Type III clone type atom.

  Type III clones are near-miss clones with similar structure
  but some statements added, removed, or modified.

  ## Examples

      iex> Metastatic.Analysis.Duplication.Types.type_iii()
      :type_iii
  """
  @spec type_iii() :: :type_iii
  def type_iii, do: :type_iii

  @doc """
  Returns the Type IV clone type atom.

  Type IV clones are semantic clones with different syntax
  but identical functionality or behavior.

  ## Examples

      iex> Metastatic.Analysis.Duplication.Types.type_iv()
      :type_iv
  """
  @spec type_iv() :: :type_iv
  def type_iv, do: :type_iv

  @doc """
  Returns all clone types.

  ## Examples

      iex> Metastatic.Analysis.Duplication.Types.all_types()
      [:type_i, :type_ii, :type_iii, :type_iv]
  """
  @spec all_types() :: [clone_type()]
  def all_types, do: [:type_i, :type_ii, :type_iii, :type_iv]

  @doc """
  Returns human-readable description of a clone type.

  ## Examples

      iex> Metastatic.Analysis.Duplication.Types.describe(:type_i)
      "Exact clone (identical code)"

      iex> Metastatic.Analysis.Duplication.Types.describe(:type_ii)
      "Renamed clone (identical structure, different identifiers)"

      iex> Metastatic.Analysis.Duplication.Types.describe(:type_iii)
      "Near-miss clone (similar structure with modifications)"

      iex> Metastatic.Analysis.Duplication.Types.describe(:type_iv)
      "Semantic clone (different syntax, same behavior)"
  """
  @spec describe(clone_type()) :: String.t()
  def describe(:type_i), do: "Exact clone (identical code)"
  def describe(:type_ii), do: "Renamed clone (identical structure, different identifiers)"
  def describe(:type_iii), do: "Near-miss clone (similar structure with modifications)"
  def describe(:type_iv), do: "Semantic clone (different syntax, same behavior)"

  @doc """
  Checks if a clone type is valid.

  ## Examples

      iex> Metastatic.Analysis.Duplication.Types.valid?(:type_i)
      true

      iex> Metastatic.Analysis.Duplication.Types.valid?(:invalid)
      false
  """
  @spec valid?(atom()) :: boolean()
  def valid?(type), do: type in all_types()
end
