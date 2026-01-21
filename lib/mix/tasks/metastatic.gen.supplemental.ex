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
    * info/0 function with metadata
    * transform/3 function scaffold for each construct
    * Comprehensive documentation
    * Example tests
  """

  @shortdoc "Generates a supplemental module scaffold"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
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
    # Parse module path
    parts = String.split(name, ".")
    module_name = parts |> List.last() |> Macro.camelize()

    # Create file paths
    lib_dir = "lib/metastatic/supplemental/#{language}"
    test_dir = "test/metastatic/supplemental/#{language}"
    lib_file = Path.join(lib_dir, "#{List.last(parts)}.ex")
    test_file = Path.join(test_dir, "#{List.last(parts)}_test.exs")

    # Create directories
    File.mkdir_p!(lib_dir)
    File.mkdir_p!(test_dir)

    # Generate module content
    module_content =
      generate_module_content(module_name, language, constructs, library, library_version)

    test_content = generate_test_content(module_name, language, constructs)

    # Write files
    File.write!(lib_file, module_content)
    File.write!(test_file, test_content)

    Mix.shell().info("* creating #{lib_file}")
    Mix.shell().info("* creating #{test_file}")
    Mix.shell().info("")
    Mix.shell().info("Supplemental module created successfully!")
    Mix.shell().info("")
    Mix.shell().info("Next steps:")
    Mix.shell().info("1. Implement the transform/3 functions in #{lib_file}")
    Mix.shell().info("2. Add tests in #{test_file}")
    Mix.shell().info("3. Register the module in config/config.exs")
    Mix.shell().info("4. Run: mix test #{test_file}")
  end

  defp generate_module_content(module_name, language, constructs, library, library_version) do
    construct_atoms =
      if constructs == [],
        do: ":example_construct",
        else: Enum.map_join(constructs, ", ", &":#{&1}")

    dependencies_map =
      if library != "" do
        """
            %{
              "#{library}" => "#{library_version}"
            }
        """
      else
        "%{}"
      end

    transform_functions =
      if constructs == [] do
        generate_transform_scaffold("example_construct")
      else
        constructs
        |> Enum.map(&generate_transform_scaffold/1)
        |> Enum.join("\n\n")
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
          #{module_name}.transform(ast, :from_meta, [])
      \"\"\"

      @behaviour Metastatic.Supplemental

      alias Metastatic.Supplemental.Info

      @impl Metastatic.Supplemental
      def info do
        %Info{
          target_language: :#{language},
          constructs: [#{construct_atoms}],
          dependencies: #{String.trim(dependencies_map)}
        }
      end

    #{transform_functions}
    end
    """
  end

  defp generate_transform_scaffold(construct) do
    """
      @impl Metastatic.Supplemental
      def transform({:#{construct}, _args} = _ast, :from_meta, _opts) do
        # TODO: Implement transformation from MetaAST to target language
        # Return the transformed AST node for #{construct}
        
        # Example:
        # {:ok, {:function_call, ...}}
        
        {:error, :not_implemented}
      end

      def transform({:#{construct}, _args} = _ast, :to_meta, _opts) do
        # TODO: Implement transformation from target language to MetaAST
        # Return the MetaAST representation
        
        # Example:
        # {:ok, {:#{construct}, ...}}
        
        {:error, :not_implemented}
      end
    """
  end

  defp generate_test_content(module_name, language, constructs) do
    test_cases =
      if constructs == [] do
        generate_test_case("example_construct")
      else
        constructs
        |> Enum.map(&generate_test_case/1)
        |> Enum.join("\n\n")
      end

    """
    defmodule Metastatic.Supplemental.#{Macro.camelize(to_string(language))}.#{module_name}Test do
      use ExUnit.Case, async: true

      alias Metastatic.Supplemental.#{Macro.camelize(to_string(language))}.#{module_name}

      doctest #{module_name}

      describe "info/0" do
        test "returns supplemental metadata" do
          info = #{module_name}.info()

          assert info.target_language == :#{language}
          assert is_list(info.constructs)
          assert is_map(info.dependencies)
        end
      end

    #{test_cases}
    end
    """
  end

  defp generate_test_case(construct) do
    """
      describe "transform/3 for :#{construct}" do
        test "transforms from MetaAST to target language" do
          ast = {:#{construct}, []}
          
          # TODO: Implement test
          # result = ModuleName.transform(ast, :from_meta, [])
          # assert {:ok, _} = result
        end

        test "transforms from target language to MetaAST" do
          ast = {:#{construct}, []}
          
          # TODO: Implement test
          # result = ModuleName.transform(ast, :to_meta, [])
          # assert {:ok, _} = result
        end
      end
    """
  end

  defp parse_language(nil), do: nil
  defp parse_language(lang) when is_binary(lang), do: String.to_atom(lang)

  defp parse_constructs(nil), do: []

  defp parse_constructs(constructs_str) do
    constructs_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_atom/1)
  end
end
