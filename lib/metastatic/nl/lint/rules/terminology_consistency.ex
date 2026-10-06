defmodule Metastatic.NL.Lint.Rules.TerminologyConsistency do
  @moduledoc """
  Flags non-inclusive, deprecated, or inconsistent terminology in documentation.
  """

  @behaviour Metastatic.NL.Lint.Rule

  alias Metastatic.NL.AST
  alias Metastatic.NL.Lint.Issue

  @term_replacements %{
    "whitelist" => "allowlist",
    "blacklist" => "blocklist or denylist",
    "master" => "primary or main",
    "slave" => "secondary or replica",
    "sanity check" => "coherence check or quick verification",
    "dummy" => "placeholder or sample"
  }

  @impl true
  def name, do: :terminology_consistency

  @impl true
  def category, do: :consistency

  @impl true
  def explanation do
    "Use inclusive, modern terminology (e.g. 'allowlist' instead of 'whitelist', 'replica' instead of 'slave')."
  end

  @impl true
  def run(ast, opts) do
    custom_terms = Keyword.get(opts, :terms, %{})
    replacements = Map.merge(@term_replacements, custom_terms)

    {_, issues} =
      AST.traverse(
        ast,
        [],
        fn
          {:token, meta, val} = token, acc when is_binary(val) ->
            down = String.downcase(val)

            case Map.fetch(replacements, down) do
              {:ok, suggested} ->
                issue =
                  Issue.new(
                    :terminology_consistency,
                    "Deprecated or non-standard term '#{val}' detected.",
                    line: Keyword.get(meta, :line),
                    col: Keyword.get(meta, :col),
                    severity: :warning,
                    suggestion: "Replace '#{val}' with '#{suggested}'."
                  )

                {token, [issue | acc]}

              :error ->
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
