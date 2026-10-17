defmodule Metastatic.NL.Adapters.English.Subprocess do
  @moduledoc """
  Subprocess manager and parser bridge for English text and prose.

  Executes the Tree-sitter parser when available, or prints a warning and falls
  back seamlessly to the pure Elixir rule-based tokenizer/parser.

  ## Configuration

  The `tree-sitter` executable can be configured in `config/config.exs`:

      config :metastatic,
        tree_sitter_bin: "/path/to/tree-sitter"

  Or under the `:nl` namespace:

      config :metastatic, :nl,
        tree_sitter_bin: "tree-sitter"

  Or via the `TREE_SITTER_BIN` environment variable.
  """

  require Logger
  alias Metastatic.Priv

  @parser_script "parsers/english/parser.js"

  @doc """
  Returns the configured tree-sitter executable name or path.
  """
  @spec tree_sitter_bin(keyword()) :: String.t()
  def tree_sitter_bin(opts \\ []) do
    Keyword.get_lazy(opts, :tree_sitter_bin, fn ->
      Application.get_env(:metastatic, :tree_sitter_bin) ||
        Application.get_env(:metastatic, :nl, []) |> Keyword.get(:tree_sitter_bin) ||
        System.get_env("TREE_SITTER_BIN") ||
        "tree-sitter"
    end)
  end

  @doc """
  Checks if the configured tree-sitter executable is available and functional.
  """
  @spec tree_sitter_available?(keyword()) :: boolean()
  def tree_sitter_available?(opts \\ []) do
    bin = tree_sitter_bin(opts)

    case resolve_executable(bin) do
      nil ->
        false

      executable ->
        try do
          case System.cmd(executable, ["--version"],
                 env: Priv.subprocess_env(),
                 stderr_to_stdout: true
               ) do
            {output, 0} ->
              String.contains?(output, "tree-sitter")

            _ ->
              false
          end
        rescue
          _ -> false
        end
    end
  end

  defp resolve_executable(bin) when is_binary(bin) do
    if File.exists?(bin) and not File.dir?(bin) do
      bin
    else
      Priv.find_executable(bin)
    end
  end

  @doc """
  Parses English source text to CST map representation (M1).

  If `tree-sitter` is available, runs the tree-sitter pipeline.
  Otherwise, logs/prints a warning and falls back to the pure Elixir
  rule-based tokenizer/parser.
  """
  @spec parse(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(source, opts \\ []) when is_binary(source) and is_list(opts) do
    bin = tree_sitter_bin(opts)

    if tree_sitter_available?(opts) do
      case run_tree_sitter_parser(source, bin) do
        {:ok, ast} ->
          {:ok, ast}

        {:error, _reason} ->
          warn_fallback(bin, opts)
          fallback_parse(source)
      end
    else
      warn_fallback(bin, opts)
      fallback_parse(source)
    end
  end

  defp warn_fallback(bin, opts) do
    warn_mode = Keyword.get(opts, :warn, :once)

    should_warn =
      case warn_mode do
        false ->
          false

        true ->
          true

        :once ->
          key = {__MODULE__, :warned_fallback, bin}

          case :persistent_term.get(key, false) do
            true ->
              false

            false ->
              :persistent_term.put(key, true)
              true
          end
      end

    if should_warn do
      msg =
        "[Metastatic.NL] tree-sitter is not available (configured: '#{bin}'). Falling back to Pure Elixir rule-based tokenizer/parser."

      Logger.warning(msg)
      IO.warn(msg, [])
    end
  end

  defp run_tree_sitter_parser(source, bin) do
    script_full_path = Priv.parser_path(@parser_script)
    node_bin = Priv.find_executable("node")

    if File.exists?(script_full_path) and node_bin != nil do
      temp_path =
        Path.join(
          System.tmp_dir!(),
          "metastatic_nl_#{System.unique_integer([:positive, :monotonic])}.txt"
        )

      File.write!(temp_path, source)

      try do
        case System.cmd(node_bin, [script_full_path, temp_path, "--tree-sitter-bin", bin],
               env: Priv.subprocess_env([{"TREE_SITTER_BIN", bin}]),
               stderr_to_stdout: true
             ) do
          {output, 0} ->
            case Jason.decode(output) do
              {:ok, %{"ok" => true, "ast" => ast}} ->
                {:ok, ast}

              _ ->
                {:error, :json_decode_failed}
            end

          {error_out, exit_code} ->
            {:error, {:exit_code, exit_code, error_out}}
        end
      after
        File.rm(temp_path)
      end
    else
      {:error, :script_unavailable}
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Pure Elixir rule-based tokenizer/parser.
  Splits paragraphs, sentences, and words/punctuation without external tools.
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
    regex = ~r/([A-Za-z0-9]+(?:'[A-Za-z]+)?|[-–—]|[:;,.!?(){}[\]"“”'’])/u

    Regex.scan(regex, sentence, return: :index)
    |> Enum.map(fn [{start, len} | _] ->
      raw = binary_part(sentence, start, len)
      is_punct = Regex.match?(~r/^[:;,.!?(){}[\]"“”'’\-–—]$/u, raw)

      %{
        "type" => if(is_punct, do: "punctuation", else: "word"),
        "value" => raw,
        "col" => start + 1
      }
    end)
  end
end
