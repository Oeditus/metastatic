defmodule Metastatic do
  @moduledoc """
  Documentation for `Metastatic`.
  """

  @type language :: :elixir | :erlang | :ruby | :haskell | :python

  @languages ~w|elixir erlang ruby haskell python|a

  @doc false
  def languages, do: @languages

  @doc false
  def supported?(lang) when lang in @languages, do: true
  def supported?(_), do: false

  @doc false
  def adapter_for_language(language)

  for lang <- @languages do
    mod = Module.concat([Metastatic.Adapters, lang |> Atom.to_string() |> Macro.camelize()])
    def adapter_for_language(unquote(lang)), do: {:ok, unquote(mod)}
  end

  def adapter_for_language(lang),
    do: {:error, {:unsupported_language, "No adapter found for language: #{inspect(lang)}"}}
end
