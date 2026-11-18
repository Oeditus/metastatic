defmodule Mix.Tasks.Metastatic.Gen.Supplemental do
  @moduledoc """
  Generates a new supplemental module scaffold.

  ## Usage

      mix metastatic.gen.supplemental NAME --language LANG [options]

  ## Arguments

    * `NAME` - Module name (e.g., `python.requests`, `javascript.axios`)
    * `--language` or `-l` - Target language (required)

  ## Options

    * `--constructs` or `-c` - Comma-separated list of constructs to support
    * `--library` - Name of the library being wrapped
    * `--library-version` - Version requirement for the library

  ## Examples

      # Generate Python supplemental for requests library
      mix metastatic.gen.supplemental python.requests --language python \\
        --constructs http_get,http_post --library requests --library-version ">=2.28.0"

      # Generate JavaScript supplemental for axios
      mix metastatic.gen.supplemental javascript.axios --language javascript \\
        --constructs http_get,http_post --library axios

      # Generate with minimal options
      mix metastatic.gen.supplemental ruby.httparty --language ruby

  ## Generated Files

  The generator creates:

    * `lib/metastatic/supplemental/{language}/{name}.ex` - Main supplemental module
    * `test/metastatic/supplemental/{language}/{name}_test.exs` - Test file

  The generated module includes:

    * Behaviour implementation (@behaviour Metastatic.Supplemental)
    * `info/0` returning a valid `Metastatic.Supplemental.Info` struct
    * `transform/3` scaffold for each construct
    * Comprehensive documentation

  The generated tests **fail on purpose** (`flunk/1`) until the transform is
  implemented, so a freshly generated scaffold can never turn a suite green
  while doing nothing.
  """

  @shortdoc "Generates a supplemental module scaffold"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    if Metastatic.CLI.help_requested?(args),
      do: Metastatic.CLI.help(Mix.Tasks.Metastatic.Gen.Supplemental)

    {opts, [name | _], _invalid} =
      OptionParser.parse(args,
        strict: [
          language: :string,
          constructs: :string,
          library: :string,
          library_version: :string
        ],
        aliases: [l: :language, c: :constructs]
      )

    language = parse_language(opts[:language])
    constructs = parse_constructs(opts[:constructs])
    library = opts[:library] || ""
    library_version = opts[:library_version] || ">= 0.0.0"

    if is_nil(language) do
      Mix.shell().error("Error: --language is required")
      Mix.shell().info("Usage: mix metastatic.gen.supplemental NAME --language LANG")
      exit({:shutdown, 1})
    end

    generate_supplemental(name, language, constructs, library, library_version)
  end

  defp generate_supplemental(name, language, constructs, library, library_version) do
    parts = String.split(name, ".")
    module_name = parts |> List.last() |> Macro.camelize()

    lib_dir = "lib/metastatic/supplemental/#{language}"
    test_dir = "test/metastatic/supplemental/#{language}"
    lib_file = Path.join(lib_dir, "#{List.last(parts)}.ex")
    test_file = Path.join(test_dir, "#{List.last(parts)}_test.exs")

    File.mkdir_p!(lib_dir)
    File.mkdir_p!(test_dir)

    module_content =
      generate_module_content(module_name, language, constructs, library, library_version)

    test_content = generate_test_content(module_name, language, constructs)

    File.write!(lib_file, module_content)
    File.write!(test_file, test_content)

    Mix.shell().info("* creating #{lib_file}")
    Mix.shell().info("* creating #{test_file}")
    Mix.shell().info("")
    Mix.shell().info("Supplemental module created successfully!")
    Mix.shell().info("")
    Mix.shell().info("Next steps:")
    Mix.shell().info("1. Implement the transform/3 functions in #{lib_file}")
    Mix.shell().info("2. Replace the flunk/1 calls in #{test_file} with real assertions")
    Mix.shell().info("3. Register the module in config/config.exs")
    Mix.shell().info("4. Run: mix test #{test_file}")
  end

  defp generate_module_content(module_name, language, constructs, library, library_version) do
    construct_atoms =
      if constructs == [],
        do: ":example_construct",
        else: Enum.map_join(constructs, ", ", &":#{&1}")

    requires =
      if library != "" do
        "[\"#{library} #{library_version}\"]"
      else
        "[]"
      end

    transform_functions =
      if constructs == [] do
        generate_transform_scaffold("example_construct")
      else
        Enum.map_join(constructs, "\n\n", &generate_transform_scaffold/1)
      end

    """
    defmodule Metastatic.Supplemental.#{Macro.camelize(to_string(language))}.#{module_name} do
      @moduledoc \"\"\"
      Supplemental module for #{language |> to_string() |> String.capitalize()} #{library} library support.

      Provides MetaAST construct transformations using the #{library} library.

      ## Constructs Supported

      #{if constructs == [], do: "- :example_construct (example)", else: Enum.map_join(constructs, "\n  ", &"- :#{&1}")}

      ## Dependencies

      #{if library != "", do: "This module requires the `#{library}` library (#{library_version}).", else: "No external dependencies."}

      ## Examples

          # Transform MetaAST construct to #{language} code using #{library}
          alias Metastatic.Supplemental.#{Macro.camelize(to_string(language))}.#{module_name}

          ast = {:example_construct, ...}
          #{module_name}.transform(ast, :#{language}, %{})
      \"\"\"

      @behaviour Metastatic.Supplemental

      alias Metastatic.Supplemental.Info

      @impl Metastatic.Supplemental
      def info do
        %Info{
          name: :#{Macro.underscore(module_name)},
          language: :#{language},
          constructs: [#{construct_atoms}],
          requires: #{requires},
          description: "#{module_name} support for #{language}"
        }
      end

    #{transform_functions}
    end
    """
  end

  defp generate_transform_scaffold(construct) do
    """
      @impl Metastatic.Supplemental
      def transform({:#{construct}, _args} = _ast, :#{construct}, _metadata) do
        # TODO: build the target-language AST for :#{construct}.
        # See `Metastatic.Supplemental` for the expected return shape.
        {:error, :not_implemented}
      end

      def transform(_ast, _language, _metadata), do: :error
    """
  end

  defp generate_test_content(module_name, language, constructs) do
    test_cases =
      if constructs == [] do
        generate_test_case(module_name, language, "example_construct")
      else
        Enum.map_join(constructs, "\n\n", &generate_test_case(module_name, language, &1))
      end

    """
    defmodule Metastatic.Supplemental.#{Macro.camelize(to_string(language))}.#{module_name}Test do
      use ExUnit.Case, async: true

      alias Metastatic.Supplemental.#{Macro.camelize(to_string(language))}.#{module_name}

      doctest #{module_name}

      describe "info/0" do
        test "returns supplemental metadata" do
          info = #{module_name}.info()

          assert info.language == :#{language}
          assert is_list(info.constructs)
          assert is_list(info.requires)
          assert is_binary(info.description)
          assert Metastatic.Supplemental.Info.valid?(info)
        end
      end

    #{test_cases}
    end
    """
  end

  defp generate_test_case(module_name, language, construct) do
    """
      describe "transform/3 for :#{construct}" do
        test "transforms the :#{construct} construct" do
          ast = {:#{construct}, []}

          flunk("implement the :#{construct} transformation, then replace this flunk/1")
        end

        test "rejects constructs it does not handle" do
          assert :error = #{module_name}.transform({:not_our_construct, []}, :#{language}, %{})
        end
      end
    """
  end

  defp parse_language(nil), do: nil
  defp parse_language(lang) when is_binary(lang), do: String.to_existing_atom(lang)

  # CLI input must never mint atoms from arbitrary user strings, but a
  # *construct* name is by definition a new atom (that is the whole point of
  # declaring a supplemental). The atom is created here, in a code-generation
  # task, from an explicitly validated identifier — never from untrusted input
  # at runtime.
  defp to_existing_or_new_atom(str) do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, str) do
      String.to_atom(str)
    else
      Mix.shell().error("Invalid construct name: #{inspect(str)} (expected snake_case)")
      exit({:shutdown, 1})
    end
  end

  defp parse_constructs(nil), do: []

  defp parse_constructs(constructs_str) do
    constructs_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&to_existing_or_new_atom/1)
  end
end
