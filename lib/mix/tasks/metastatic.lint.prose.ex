defmodule Mix.Tasks.Metastatic.Lint.Prose do
  @shortdoc "Lint documentation and prose files using NL-MetaAST"

  @moduledoc """
  Lints natural language documentation and Markdown files using NL-MetaAST.

  ## Usage

      mix metastatic.lint.prose [FILE_OR_DIR] [OPTIONS]

  ## Examples

      mix metastatic.lint.prose README.md
      mix metastatic.lint.prose docs/
  """

  use Mix.Task

  alias Metastatic.NL.Lint.Runner

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [
          max_words: :integer,
          format: :string
        ]
      )

    target_files =
      case files do
        [] ->
          ["README.md"]

        paths ->
          Enum.flat_map(paths, fn path ->
            cond do
              File.dir?(path) ->
                Path.wildcard(Path.join(path, "**/*.{md,markdown,txt}"))

              File.exists?(path) ->
                [path]

              true ->
                Mix.shell().error("Path not found: #{path}")
                []
            end
          end)
      end

    if target_files == [] do
      Mix.shell().info("No files to lint.")
    else
      total_issues =
        Enum.reduce(target_files, 0, fn file, acc ->
          acc + lint_file(file, opts)
        end)

      if total_issues > 0 do
        Mix.shell().error(
          "\nFound #{total_issues} issue(s) across #{length(target_files)} file(s)."
        )
      else
        Mix.shell().info("\nAll #{length(target_files)} file(s) passed prose linting cleanly!")
      end
    end
  end

  defp lint_file(file, opts) do
    case File.read(file) do
      {:ok, content} ->
        case Runner.lint_source(content, opts) do
          {:ok, []} ->
            Mix.shell().info("✓ #{file} (clean)")
            0

          {:ok, issues} ->
            Mix.shell().info("\n✗ #{file} (#{length(issues)} issue(s)):")

            Enum.each(issues, fn issue ->
              location =
                if issue.line, do: " [line #{issue.line}:#{issue.col || 1}]", else: ""

              severity_tag =
                case issue.severity do
                  :refactor -> " [refactor]"
                  :warning -> " [warning]"
                  :error -> " [error]"
                  _ -> " [info]"
                end

              Mix.shell().info("  • #{issue.rule}#{severity_tag}#{location}: #{issue.message}")

              if issue.suggestion do
                Mix.shell().info("    💡 #{issue.suggestion}")
              end
            end)

            length(issues)
        end

      {:error, reason} ->
        Mix.shell().error("Could not read #{file}: #{inspect(reason)}")
        0
    end
  end
end
