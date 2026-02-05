defmodule Metastatic.Analysis.Purity.Effects do
  @moduledoc """
  Detects side effects in MetaAST nodes.

  Identifies impure operations including I/O, mutations, random operations,
  time operations, network/database access, and exception handling.
  """

  alias Metastatic.Analysis.Purity.Result

  @type effect :: Result.effect()

  @doc """
  Detects effects in a MetaAST node.

  Returns a list of detected effects.

  ## 3-Tuple Format

  All MetaAST nodes use the uniform 3-tuple structure:
  `{type_atom, keyword_meta, children_or_value}`

  ## Examples

      iex> Metastatic.Analysis.Purity.Effects.detect({:function_call, [name: "print"], []})
      [:io]

      iex> Metastatic.Analysis.Purity.Effects.detect({:literal, [subtype: :integer], 42})
      []
  """
  @spec detect(Metastatic.AST.meta_ast()) :: [effect()]
  def detect(ast)

  # I/O operations (3-tuple format)
  def detect({:function_call, meta, _args}) when is_list(meta) do
    name = Keyword.get(meta, :name)

    if is_binary(name) do
      classify_function_call(name)
    else
      []
    end
  end

  # Pure core constructs (3-tuple format)
  def detect({:literal, _meta, _value}), do: []
  def detect({:variable, _meta, _name}), do: []
  def detect({:binary_op, _meta, _children}), do: []
  def detect({:unary_op, _meta, _children}), do: []

  # Control flow (pure if contents are pure)
  def detect({:conditional, _meta, _children}), do: []
  def detect({:block, _meta, _children}), do: []

  # Loops (check for mutations inside)
  def detect({:loop, _meta, _children}), do: []

  # Assignments can indicate mutation
  def detect({:assignment, _meta, _children}), do: [:mutation]

  # Pattern matching is pure (BEAM languages)
  def detect({:inline_match, _meta, _children}), do: []

  # Lambda/anonymous functions are pure
  def detect({:lambda, _meta, _children}), do: []

  # Collection operations are pure if no side effects in function arg
  def detect({:collection_op, _meta, _children}), do: []

  # Exception handling is a side effect
  def detect({:exception_handling, _meta, _children}), do: [:exception]

  # Early returns are control flow (pure)
  def detect({:early_return, _meta, _children}), do: []

  # Language-specific nodes might have effects
  def detect({:language_specific, _meta, _native_ast}), do: []

  # Pair (for map entries)
  def detect({:pair, _meta, _children}), do: []

  # List and Map collections are pure
  def detect({:list, _meta, _children}), do: []
  def detect({:map, _meta, _children}), do: []

  # Unknown nodes
  def detect(_), do: []

  # Private helpers

  defp classify_function_call(name) do
    cond do
      io_function?(name) -> [:io]
      random_function?(name) -> [:random]
      time_function?(name) -> [:time]
      network_function?(name) -> [:network]
      database_function?(name) -> [:database]
      true -> []
    end
  end

  # I/O function patterns
  defp io_function?("print"), do: true
  defp io_function?("puts"), do: true
  defp io_function?("write"), do: true
  defp io_function?("read"), do: true
  defp io_function?("open"), do: true
  defp io_function?("input"), do: true
  defp io_function?("IO." <> _), do: true
  defp io_function?("File." <> _), do: true
  defp io_function?("io:" <> _), do: true
  defp io_function?("file:" <> _), do: true
  defp io_function?(_), do: false

  # Random function patterns
  defp random_function?("random" <> _), do: true
  defp random_function?("rand" <> _), do: true
  defp random_function?(":rand." <> _), do: true
  defp random_function?("Random." <> _), do: true
  defp random_function?(_), do: false

  # Time function patterns
  defp time_function?("time" <> _), do: true
  defp time_function?("now" <> _), do: true
  defp time_function?("Date" <> _), do: true
  defp time_function?("DateTime" <> _), do: true
  defp time_function?("Time" <> _), do: true
  defp time_function?("erlang:now"), do: true
  defp time_function?(_), do: false

  # Network function patterns
  defp network_function?("http" <> _), do: true
  defp network_function?("fetch" <> _), do: true
  defp network_function?("request" <> _), do: true
  defp network_function?("socket" <> _), do: true
  defp network_function?("HTTPoison." <> _), do: true
  defp network_function?(_), do: false

  # Database function patterns
  defp database_function?("query" <> _), do: true
  defp database_function?("insert" <> _), do: true
  defp database_function?("update" <> _), do: true
  defp database_function?("delete" <> _), do: true
  defp database_function?("Repo." <> _), do: true
  defp database_function?("Ecto." <> _), do: true
  defp database_function?(_), do: false
end
