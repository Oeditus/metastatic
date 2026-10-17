defmodule Metastatic.Adapters.Ruby.Subprocess do
  @moduledoc """
  Subprocess management for Ruby parser and unparser.

  Handles communication with Ruby scripts via stdin/stdout with JSON serialization.
  """

  alias Metastatic.Priv

  @parser_path "parsers/ruby/parser.rb"
  @unparser_path "parsers/ruby/unparser.rb"

  @doc """
  Parse Ruby source code to AST JSON.

  ## Examples

      iex> Metastatic.Adapters.Ruby.Subprocess.parse("x = 42")
      {:ok, %{"type" => "lvasgn", "children" => [...]}}

      iex> Metastatic.Adapters.Ruby.Subprocess.parse("x = ")
      {:error, "SyntaxError: ..."}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(source) do
    script_full_path = Priv.parser_path(@parser_path)

    if File.exists?(script_full_path) and ruby_available?() do
      case run_ruby_script(@parser_path, source) do
        {:ok, result} ->
          case Jason.decode(result) do
            {:ok, %{"status" => "ok", "ast" => nil}} ->
              {:error, "Parse error: syntax error"}

            {:ok, %{"status" => "ok", "ast" => ast}} ->
              {:ok, ast}

            {:ok, %{"status" => "error", "error" => error}} ->
              {:error, format_error(error)}

            {:error, reason} ->
              {:error, "JSON decode failed: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Ruby process failed: #{inspect(reason)}"}
      end
    else
      {:error, "Ruby parser unavailable"}
    end
  end

  @doc """
  Unparse AST JSON back to Ruby source code.

  ## Examples

      iex> ast = %{"type" => "lvasgn", "children" => [...]}
      iex> Metastatic.Adapters.Ruby.Subprocess.unparse(ast)
      {:ok, "x = 42"}
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) do
    input = Jason.encode!(%{ast: ast})

    case run_ruby_script(@unparser_path, input) do
      {:ok, result} ->
        # Unparser outputs source directly, not JSON
        {:ok, String.trim(result)}

      {:error, reason} ->
        {:error, "Ruby unparse failed: #{inspect(reason)}"}
    end
  end

  # Private Functions

  defp ruby_available? do
    Priv.find_executable("ruby") != nil or Priv.find_executable("bundle") != nil
  end

  defp run_ruby_script(script_path, input) do
    script_full_path = Priv.parser_path(script_path)
    script_dir = Path.dirname(script_full_path)

    if File.exists?(script_full_path) do
      temp_path =
        Path.join(
          System.tmp_dir!(),
          "metastatic_rb_#{System.unique_integer([:positive, :monotonic])}.txt"
        )

      File.write!(temp_path, input)

      try do
        execute_ruby(script_full_path, script_dir, temp_path)
      after
        File.rm(temp_path)
      end
    else
      {:error, "Ruby script not found: #{script_full_path}"}
    end
  rescue
    e ->
      {:error, "Exception: #{Exception.message(e)}"}
  end

  defp execute_ruby(script_full_path, script_dir, temp_path) do
    ruby_bin = Priv.find_executable("ruby")
    bundle_bin = Priv.find_executable("bundle")
    env = Priv.subprocess_env()

    cond do
      ruby_bin != nil ->
        case System.cmd(ruby_bin, [script_full_path, temp_path],
               cd: script_dir,
               env: env,
               stderr_to_stdout: true
             ) do
          {output, 0} ->
            {:ok, filter_warnings(output)}

          {error_output, exit_code} ->
            if bundle_bin != nil and String.contains?(error_output, "LoadError") do
              run_bundle_exec(bundle_bin, script_full_path, script_dir, temp_path, env)
            else
              {:error, "Exit code #{exit_code}: #{error_output}"}
            end
        end

      bundle_bin != nil ->
        run_bundle_exec(bundle_bin, script_full_path, script_dir, temp_path, env)

      true ->
        {:error, "Ruby executable not found"}
    end
  end

  defp run_bundle_exec(bundle_bin, script_full_path, script_dir, temp_path, env) do
    case System.cmd(bundle_bin, ["exec", "ruby", Path.basename(script_full_path), temp_path],
           cd: script_dir,
           env: env,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        {:ok, filter_warnings(output)}

      {error_output, exit_code} ->
        {:error, "Exit code #{exit_code}: #{error_output}"}
    end
  end

  defp format_error(error) when is_binary(error) do
    "Parse error: #{error}"
  end

  defp format_error(%{"error" => error, "line" => line}) do
    "Parse error at line #{line}: #{error}"
  end

  defp format_error(error) do
    "Parse error: #{inspect(error)}"
  end

  defp filter_warnings(output) do
    output
    |> String.split("\n")
    |> Enum.reject(fn line ->
      String.contains?(line, "parser/current is loading") or
        String.contains?(line, "Please see https://github.com/whitequark/parser")
    end)
    |> Enum.join("\n")
  end
end
