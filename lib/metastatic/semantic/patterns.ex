defmodule Metastatic.Semantic.Patterns do
  @moduledoc """
  Language-aware pattern registry for semantic enrichment.

  This module provides a pattern matching engine that maps function names
  to semantic operation kinds. Patterns are organized by language and domain,
  enabling precise detection of framework-specific operations.

  ## Pattern Types

  Three types of patterns are supported:

  1. **Exact match** - Full function name: `"Repo.get"`
  2. **Prefix match** - Module prefix with wildcard: `"Repo.*"`
  3. **Suffix match** - Method name at end: `"*.findByPk"`
  4. **Regex match** - Complex patterns: `~r/\\.objects\\.get/`

  ## Usage

      alias Metastatic.Semantic.Patterns

      # Match a function name against patterns for a language
      case Patterns.match("Repo.get", :elixir, args) do
        {:ok, op_kind} -> # Found a match
        :no_match -> # No pattern matched
      end

  ## Pattern Registration

  Patterns are defined in domain-specific modules (e.g., `Domains.Database`)
  and registered here. Each pattern specifies:

  - Language(s) it applies to
  - Function name pattern
  - Operation kind metadata
  - Optional: target extraction strategy
  """

  alias Metastatic.Semantic.OpKind

  @typedoc "Pattern specification"
  @type pattern_spec :: %{
          pattern: String.t() | Regex.t(),
          operation: OpKind.operation(),
          framework: OpKind.framework() | nil,
          extract_target: :first_arg | :receiver | :none | nil
        }

  @typedoc "Language identifier"
  @type language :: :elixir | :python | :ruby | :javascript | :erlang | :haskell | atom()

  # ----- Public API -----

  @doc """
  Matches a function name against registered patterns for a language.

  Returns `{:ok, op_kind}` if a pattern matches, or `:no_match` otherwise.

  ## Parameters

  - `func_name` - The function name to match (e.g., "Repo.get", "session.query")
  - `language` - The source language (e.g., :elixir, :python)
  - `args` - AST arguments for target extraction
  - `receiver` - Optional receiver AST for method calls

  ## Examples

      iex> Patterns.match("Repo.get", :elixir, [{:variable, [], "User"}, {:literal, [subtype: :integer], 1}])
      {:ok, [domain: :db, operation: :retrieve, target: "User", async: false, framework: :ecto]}

      iex> Patterns.match("unknown_function", :elixir, [])
      :no_match
  """
  @spec match(String.t(), language(), list(), term()) :: {:ok, OpKind.t()} | :no_match
  def match(func_name, language, args, receiver \\ nil) when is_binary(func_name) do
    # Get patterns for this language
    patterns = get_patterns_for_language(language)

    # Try to find a matching pattern
    Enum.find_value(patterns, :no_match, fn {pattern, spec} ->
      if matches_pattern?(func_name, pattern) do
        op_kind = build_op_kind(spec, args, receiver)
        {:ok, op_kind}
      else
        nil
      end
    end)
  end

  @doc """
  Registers patterns for a domain and language.

  This is called by domain modules (e.g., `Domains.Database`) during compilation.

  ## Examples

      Patterns.register(:db, :elixir, [
        {"Repo.get", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},
        {"Repo.all", %{operation: :retrieve_all, framework: :ecto}}
      ])
  """
  @spec register(OpKind.domain(), language(), [{String.t() | Regex.t(), pattern_spec()}]) :: :ok
  def register(domain, language, patterns) do
    # Store in persistent_term for fast access
    key = {__MODULE__, domain, language}
    existing = :persistent_term.get(key, [])
    :persistent_term.put(key, existing ++ patterns)
    :ok
  end

  @doc """
  Gets all registered patterns for a domain and language.
  """
  @spec get_patterns(OpKind.domain(), language()) :: [{String.t() | Regex.t(), pattern_spec()}]
  def get_patterns(domain, language) do
    key = {__MODULE__, domain, language}
    :persistent_term.get(key, [])
  end

  @doc """
  Clears all registered patterns (useful for testing).
  """
  @spec clear_all() :: :ok
  def clear_all do
    # Get all persistent_term keys and remove ours
    :persistent_term.get()
    |> Enum.filter(fn {key, _} ->
      match?({Metastatic.Semantic.Patterns, _, _}, key)
    end)
    |> Enum.each(fn {key, _} ->
      :persistent_term.erase(key)
    end)

    :ok
  end

  # ----- Private Implementation -----

  # Get all patterns applicable to a language (from all domains)
  defp get_patterns_for_language(language) do
    # Currently only :db domain
    get_patterns(:db, language) ++ get_patterns(:db, :all)
  end

  # Check if function name matches a pattern
  defp matches_pattern?(func_name, pattern) when is_binary(pattern) do
    cond do
      # Exact match
      func_name == pattern ->
        true

      # Prefix match: "Repo.*"
      String.ends_with?(pattern, ".*") ->
        prefix = String.trim_trailing(pattern, ".*")
        String.starts_with?(func_name, prefix <> ".")

      # Suffix match: "*.findByPk"
      String.starts_with?(pattern, "*.") ->
        suffix = String.trim_leading(pattern, "*")
        String.ends_with?(func_name, suffix)

      # Contains match: "*objects*"
      String.starts_with?(pattern, "*") and String.ends_with?(pattern, "*") ->
        middle = pattern |> String.trim_leading("*") |> String.trim_trailing("*")
        String.contains?(func_name, middle)

      true ->
        false
    end
  end

  defp matches_pattern?(func_name, %Regex{} = pattern) do
    Regex.match?(pattern, func_name)
  end

  # Build OpKind from pattern spec and arguments
  defp build_op_kind(spec, args, receiver) do
    target = extract_target(spec.extract_target, args, receiver)

    OpKind.new(:db, spec.operation,
      target: target,
      framework: spec[:framework],
      async: spec[:async] || false
    )
  end

  # Extract target entity from arguments based on strategy
  defp extract_target(nil, _args, _receiver), do: nil
  defp extract_target(:none, _args, _receiver), do: nil

  defp extract_target(:first_arg, args, _receiver) do
    case args do
      [first | _] -> extract_entity_name(first)
      _ -> nil
    end
  end

  defp extract_target(:receiver, _args, receiver) do
    extract_entity_name(receiver)
  end

  # Extract entity name from AST node
  # Handles various representations of module/class names
  defp extract_entity_name(nil), do: nil

  # Variable referencing a module: User
  defp extract_entity_name({:variable, _meta, name}) when is_binary(name) do
    # Capitalize first letter if it looks like a module name
    if String.match?(name, ~r/^[A-Z]/) do
      name
    else
      nil
    end
  end

  # Literal atom or string: :User, "User"
  defp extract_entity_name({:literal, meta, value}) when is_list(meta) do
    case Keyword.get(meta, :subtype) do
      :symbol -> Atom.to_string(value)
      :string -> value
      _ -> nil
    end
  end

  # Attribute access: MyApp.User
  defp extract_entity_name({:attribute_access, _meta, children}) when is_list(children) do
    # Try to reconstruct the full module name
    children
    |> Enum.map(&extract_name_part/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, ".")
    end
  end

  # Function call result - try to get the name
  defp extract_entity_name({:function_call, meta, _args}) when is_list(meta) do
    Keyword.get(meta, :name)
  end

  defp extract_entity_name(_), do: nil

  # Extract a name part from an AST node
  defp extract_name_part({:variable, _meta, name}) when is_binary(name), do: name
  defp extract_name_part({:literal, _meta, value}) when is_atom(value), do: Atom.to_string(value)
  defp extract_name_part({:literal, _meta, value}) when is_binary(value), do: value
  defp extract_name_part(_), do: nil
end
