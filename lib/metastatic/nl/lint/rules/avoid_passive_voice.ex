defmodule Metastatic.NL.Lint.Rules.AvoidPassiveVoice do
  @moduledoc """
  Flags clauses written in passive voice in technical documentation and prose.

  Passive voice can obscure who is responsible for an action and makes
  technical instructions harder to understand.
  """

  @behaviour Metastatic.NL.Lint.Rule

  alias Metastatic.NL.AST
  alias Metastatic.NL.Lint.Issue

  @impl true
  def name, do: :avoid_passive_voice

  @impl true
  def category, do: :style

  @impl true
  def explanation do
    "Use active voice instead of passive voice to clearly indicate the actor performing the action."
  end

  @impl true
  def run(ast, _opts) do
    {_, issues} =
      AST.traverse(
        ast,
        [],
        fn
          {:clause, meta, children} = clause, acc ->
            if Keyword.get(meta, :voice) == :passive do
              line = Keyword.get(meta, :line) || find_line(children)
              col = Keyword.get(meta, :col) || find_col(children)

              agent_phrase =
                Enum.find(children, fn
                  {:phrase, m, _} -> Keyword.get(m, :sem_role) == :agent
                  _ -> false
                end)

              suggestion =
                if agent_phrase do
                  "Consider rewriting in active voice with actor '#{AST.text(agent_phrase)}'."
                else
                  "Consider identifying the actor and rewriting in active voice."
                end

              issue =
                Issue.new(
                  :avoid_passive_voice,
                  "Passive voice construction detected: '#{AST.text(clause)}'",
                  line: line,
                  col: col,
                  severity: :refactor,
                  suggestion: suggestion
                )

              {clause, [issue | acc]}
            else
              {clause, acc}
            end

          node, acc ->
            {node, acc}
        end,
        fn node, acc -> {node, acc} end
      )

    Enum.reverse(issues)
  end

  defp find_line(children) do
    Enum.find_value(children, fn
      {:token, meta, _} -> Keyword.get(meta, :line)
      {:phrase, meta, c} -> Keyword.get(meta, :line) || find_line(c)
      _ -> nil
    end)
  end

  defp find_col(children) do
    Enum.find_value(children, fn
      {:token, meta, _} -> Keyword.get(meta, :col)
      {:phrase, meta, c} -> Keyword.get(meta, :col) || find_col(c)
      _ -> nil
    end)
  end
end
