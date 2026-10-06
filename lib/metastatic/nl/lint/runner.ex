defmodule Metastatic.NL.Lint.Runner do
  @moduledoc """
  Prose lint runner for NL-MetaAST.

  Executes a suite of rules against natural language documents and aggregates issues.
  """

  alias Metastatic.NL.Adapters.English
  alias Metastatic.NL.Lint.Rules.{
    AvoidPassiveVoice,
    AvoidWeaselWords,
    SentenceLength,
    TerminologyConsistency
  }

  @default_rules [
    AvoidPassiveVoice,
    AvoidWeaselWords,
    SentenceLength,
    TerminologyConsistency
  ]

  @doc """
  Returns the list of all default linting rules.
  """
  @spec default_rules() :: [module()]
  def default_rules, do: @default_rules

  @doc """
  Runs linting rules on an NL-MetaAST document or node.
  """
  @spec lint(Metastatic.NL.AST.nl_node(), keyword()) :: [Metastatic.NL.Lint.Issue.t()]
  def lint(ast, opts \\ []) do
    rules = Keyword.get(opts, :rules, @default_rules)

    Enum.flat_map(rules, fn rule_mod ->
      rule_mod.run(ast, opts)
    end)
  end

  @doc """
  Convenience function: parses raw text/prose, enriches it, and runs linter rules.
  """
  @spec lint_source(String.t(), keyword()) :: {:ok, [Metastatic.NL.Lint.Issue.t()]} | {:error, term()}
  def lint_source(text, opts \\ []) when is_binary(text) do
    with {:ok, cst} <- English.parse(text),
         {:ok, meta_ast, _} <- English.to_meta(cst) do
      {:ok, lint(meta_ast, opts)}
    end
  end
end
