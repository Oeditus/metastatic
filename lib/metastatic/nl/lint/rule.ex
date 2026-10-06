defmodule Metastatic.NL.Lint.Rule do
  @moduledoc """
  Behaviour for NL-MetaAST prose linting rules.
  """

  alias Metastatic.NL.AST
  alias Metastatic.NL.Lint.Issue

  @doc "Unique atom identifier for the rule."
  @callback name() :: atom()

  @doc "Category of the rule (e.g. :style, :readability, :consistency)."
  @callback category() :: :style | :readability | :consistency | :complexity

  @doc "Detailed explanation of why this rule exists."
  @callback explanation() :: String.t()

  @doc "Executes the rule against an NL-MetaAST tree."
  @callback run(AST.nl_node(), keyword()) :: [Issue.t()]
end
