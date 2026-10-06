defmodule Metastatic.NL.Lint.Rules.AvoidWeaselWords do
  @moduledoc """
  Flags weasel words and hedging phrases that undermine certainty and precision.
  """

  @behaviour Metastatic.NL.Lint.Rule

  alias Metastatic.NL.AST
  alias Metastatic.NL.Lint.Issue

  @impl true
  def name, do: :avoid_weasel_words

  @impl true
  def category, do: :style

  @impl true
  def explanation do
    "Avoid ambiguous or hedging words like 'clearly', 'obviously', 'probably', and 'perhaps' in technical documentation."
  end

  @impl true
  def run(ast, _opts) do
    {_, issues} =
      AST.traverse(
        ast,
        [],
        fn
          {:token, meta, val} = token, acc when is_binary(val) ->
            if Keyword.get(meta, :hedging) in [:weasel, :tentative] do
              issue =
                Issue.new(
                  :avoid_weasel_words,
                  "Weasel word or hedging modifier '#{val}' detected.",
                  line: Keyword.get(meta, :line),
                  col: Keyword.get(meta, :col),
                  severity: :warning,
                  suggestion:
                    "Remove '#{val}' or replace with concrete facts or quantitative data."
                )

              {token, [issue | acc]}
            else
              {token, acc}
            end

          node, acc ->
            {node, acc}
        end,
        fn node, acc -> {node, acc} end
      )

    Enum.reverse(issues)
  end
end
