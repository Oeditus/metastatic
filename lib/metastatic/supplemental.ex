defmodule Metastatic.Supplemental do
  @moduledoc """
  Behaviour for supplemental modules that extend language adapter capabilities.

  Supplemental modules enable cross-language transformation by providing mappings
  from MetaAST constructs to library-specific code when native language support
  is unavailable.

  ## Example

  A supplemental module for Python's Pykka actor library:

      defmodule MyApp.Supplemental.Python.Pykka do
        @behaviour Metastatic.Supplemental

        @impl true
        def info do
          %Metastatic.Supplemental.Info{
            name: :pykka_actor,
            language: :python,
            constructs: [:actor_call, :actor_cast, :spawn_actor],
            requires: ["pykka >= 3.0"],
            description: "Actor model support via Pykka library"
          }
        end

        @impl true
        def transform({:actor_call, actor, message, _timeout}, _language, _metadata) do
          # Build Python AST for: actor_ref.ask(message)
          {:ok, python_ast}
        end

        def transform(_, _, _), do: :error
      end

  ## Usage

  Supplementals are registered at application startup and automatically used
  during MetaAST transformation when needed constructs are encountered.

  See `Metastatic.Supplemental.Registry` for registration details.
  """

  alias Metastatic.Supplemental.Info

  @doc """
  Returns information about this supplemental module.

  Must return a `Metastatic.Supplemental.Info` struct containing:
  - `:name` - Unique identifier for this supplemental
  - `:language` - Target language (e.g., :python, :javascript)
  - `:constructs` - List of MetaAST construct types this module handles
  - `:requires` - External library dependencies with version constraints
  - `:description` - Human-readable description

  ## Example

      @impl true
      def info do
        %Info{
          name: :pykka_actor,
          language: :python,
          constructs: [:actor_call, :actor_cast],
          requires: ["pykka >= 3.0"],
          description: "Actor model support for Python"
        }
      end
  """
  @callback info() :: Info.t()

  @doc """
  Transforms a MetaAST construct to target language AST.

  Receives a MetaAST node, target language, and metadata. Returns either:
  - `{:ok, language_ast}` - Successfully transformed
  - `:error` - Cannot handle this construct

  The supplemental should only transform constructs listed in its `info/0`.

  ## Example

      @impl true
      def transform({:actor_call, actor, message, timeout}, :python, _metadata) do
        python_ast = build_pykka_ask_call(actor, message, timeout)
        {:ok, python_ast}
      end

      def transform(_, _, _), do: :error
  """
  @callback transform(meta_ast :: term(), language :: atom(), metadata :: map()) ::
              {:ok, term()} | :error

  @doc """
  Lists all MetaAST construct types supported by this supplemental.

  Convenience function that extracts constructs from info/0.

  ## Example

      iex> MySupplemental.supported_constructs()
      [:actor_call, :actor_cast, :spawn_actor]
  """
  @spec supported_constructs(module()) :: [atom()]
  def supported_constructs(module) do
    module.info().constructs
  end

  @doc """
  Returns the target language for this supplemental.

  ## Example

      iex> MySupplemental.language()
      :python
  """
  @spec language(module()) :: atom()
  def language(module) do
    module.info().language
  end

  @doc """
  Returns external library dependencies required by this supplemental.

  ## Example

      iex> MySupplemental.dependencies()
      ["pykka >= 3.0", "typing-extensions"]
  """
  @spec dependencies(module()) :: [String.t()]
  def dependencies(module) do
    module.info().requires
  end
end
