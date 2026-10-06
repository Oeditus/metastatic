defmodule Metastatic.NL.Adapters.English.Subprocess do
  @moduledoc """
  Subprocess manager and parser bridge for English text and prose.

  Executes the Tree-sitter / JavaScript English parser script when available,
  or falls back seamlessly to the native Elixir tokenizer.
  """

  @parser_script "priv/parsers/english/parser.js"

  @doc """
  Parses English source text to CST map representation (M1).
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(source) when is_binary(source) do
    script_full_path = Path.join(File.cwd!(), @parser_script)

    if File.exists?(script_full_path) and System.find_executable("node") != nil do
      temp_path =
        Path.join(
          System.tmp_dir!(),
          "metastatic_nl_#{System.unique_integer([:positive, :monotonic])}.txt"
        )

      File.write!(temp_path, source)

      try do
        case System.cmd("node", [script_full_path, temp_path], stderr_to_stdout: true) do
          {output, 0} ->
            case Jason.decode(output) do
              {:ok, %{"ok" => true, "ast" => ast}} ->
                {:ok, ast}

              _ ->
                fallback_parse(source)
            end

          _ ->
            fallback_parse(source)
        end
      after
        File.rm(temp_path)
      end
    else
      fallback_parse(source)
    end
  rescue
    _ ->
      fallback_parse(source)
  end

  @doc """
  In-process fallback parser when node is not available.
  Splits paragraphs, sentences, and words/punctuation.
  """
  @spec fallback_parse(String.t()) :: {:ok, map()}
  def fallback_parse(source) do
    paragraphs =
      source
      |> String.split(~r/\n\s*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    parsed_paragraphs =
      Enum.map(paragraphs, fn para ->
        sentences =
          para
          |> String.split(~r/(?<=[.!?])\s+/)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        parsed_sentences =
          Enum.map(sentences, fn sent ->
            tokens = tokenize_sentence(sent)
            %{"type" => "sentence", "text" => sent, "children" => tokens}
          end)

        %{"type" => "paragraph", "children" => parsed_sentences}
      end)

    {:ok, %{"type" => "document", "language" => "en", "children" => parsed_paragraphs}}
  end

  defp tokenize_sentence(sentence) do
    regex = ~r/([A-Za-z0-9]+(?:'[A-Za-z]+)?|[-–—]|[:;,.!?(){}[\]"“”'’])/

    Regex.scan(regex, sentence, return: :index)
    |> Enum.map(fn [{start, len} | _] ->
      raw = String.slice(sentence, start, len)
      is_punct = Regex.match?(~r/^[:;,.!?(){}[\]"“”'’\-–—]$/, raw)

      %{
        "type" => if(is_punct, do: "punctuation", else: "word"),
        "value" => raw,
        "col" => start + 1
      }
    end)
  end
end
