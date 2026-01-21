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

  ## Examples

      iex> Metastatic.Analysis.Purity.Effects.detect({:function_call, "print", []})
      [:io]

      iex> Metastatic.Analysis.Purity.Effects.detect({:literal, :integer, 42})
      []
  """
  @spec detect(Metastatic.AST.meta_ast()) :: [effect()]
  def detect(ast)

  # I/O operations
  def detect({:function_call, name, _args}) when is_binary(name) do
    classify_function_call(name)
  end

  # Pure core constructs
  def detect({:literal, _, _}), do: []
  def detect({:variable, _}), do: []
  def detect({:binary_op, _, _, _, _}), do: []
  def detect({:unary_op, _, _}), do: []

  # Control flow (pure if contents are pure)
  def detect({:conditional, _, _, _}), do: []
  def detect({:block, _}), do: []

  # Loops (check for mutations inside)
  def detect({:loop, _, _, _}), do: []
  def detect({:loop, _, _, _, _}), do: []

  # Assignments can indicate mutation
  def detect({:assignment, _, _}), do: [:mutation]

  # Pattern matching is pure (BEAM languages)
  def detect({:inline_match, _, _}), do: []

  # Lambda/anonymous functions are pure
  def detect({:lambda, _, _}), do: []

  # Collection operations are pure if no side effects in function arg
  def detect({:collection_op, _, _, _}), do: []
  def detect({:collection_op, _, _, _, _}), do: []

  # Exception handling is a side effect
  def detect({:exception_handling, _, _, _}), do: [:exception]

  # Early returns are control flow (pure)
  def detect({:early_return, _}), do: []

  # Language-specific nodes might have effects
  def detect({:language_specific, _, _}), do: []
  def detect({:language_specific, _, _, _}), do: []

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
