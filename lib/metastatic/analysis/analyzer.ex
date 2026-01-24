defmodule Metastatic.Analysis.Analyzer do
  @moduledoc """
  Behaviour for MetaAST analyzers and refactoring suggestions.

  Analyzers can be diagnostic (detecting issues) or prescriptive (suggesting
  improvements). Both types work uniformly through this behaviour.

  ## Philosophy

  Analyzers operate at the M2 meta-model level, making them language-agnostic.
  Write an analyzer once, and it works across Python, JavaScript, Elixir, and
  all other supported languages.

  ## Usage

      defmodule MyApp.Analysis.UnusedVariables do
        @behaviour Metastatic.Analysis.Analyzer

        @impl true
        def info do
          %{
            name: :unused_variables,
            category: :correctness,
            description: "Detects variables that are assigned but never used",
            severity: :warning,
            explanation: "Unused variables add noise and may indicate bugs",
            configurable: true
          }
        end

        @impl true
        def analyze({:assignment, {:variable, name}, _value}, context) do
          # Track assignment and return issues
          []
        end

        def analyze(_node, _context), do: []
      end

  ## Lifecycle

  1. `run_before/1` (optional) - Called once before traversal
  2. `analyze/2` - Called for each AST node during traversal
  3. `run_after/2` (optional) - Called once after traversal

  ## Context

  The context map passed to callbacks contains:
  - `:document` - The document being analyzed
  - `:config` - Configuration for this analyzer
  - `:parent_stack` - Stack of parent nodes
  - `:depth` - Current depth in AST
  - `:scope` - Scope tracking (custom per analyzer)

  Analyzers can store state in the context by returning modified context
  from `run_before/1` or by maintaining their own state tracking.
  """

  alias Metastatic.{AST, Document}

  # ----- Type Definitions -----

  @typedoc "Analysis category classification"
  @type category ::
          :readability
          | :maintainability
          | :performance
          | :security
          | :correctness
          | :style
          | :refactoring

  @typedoc "Issue severity level"
  @type severity :: :error | :warning | :info | :refactoring_opportunity

  @typedoc "Issue location information"
  @type location :: %{
          line: non_neg_integer() | nil,
          column: non_neg_integer() | nil,
          path: Path.t() | nil
        }

  @typedoc "Refactoring suggestion"
  @type suggestion :: %{
          type: :replace | :remove | :insert_before | :insert_after,
          replacement: AST.meta_ast() | nil,
          message: String.t()
        }

  @typedoc "Analysis issue result"
  @type issue :: %{
          analyzer: module(),
          category: category(),
          severity: severity(),
          message: String.t(),
          node: AST.meta_ast(),
          location: location(),
          suggestion: suggestion() | nil,
          metadata: map()
        }

  @typedoc "Analysis context passed to callbacks"
  @type context :: %{
          document: Document.t(),
          config: map(),
          parent_stack: [AST.meta_ast()],
          depth: non_neg_integer(),
          scope: map()
        }

  @typedoc "Analyzer metadata"
  @type info :: %{
          name: atom(),
          category: category(),
          description: String.t(),
          severity: severity(),
          explanation: String.t(),
          configurable: boolean()
        }

  # ----- Behaviour Callbacks -----

  @doc """
  Returns metadata about this analyzer.

  Must include:
  - `:name` - Unique identifier (atom)
  - `:category` - Analysis category
  - `:description` - Brief one-line description
  - `:severity` - Default severity level
  - `:explanation` - Detailed explanation (can be multi-line)
  - `:configurable` - Whether analyzer accepts configuration

  ## Examples

      @impl true
      def info do
        %{
          name: :unused_variables,
          category: :correctness,
          description: "Detects variables that are assigned but never used",
          severity: :warning,
          explanation: \"\"\"
          Variables that are assigned but never referenced add noise and
          may indicate bugs or incomplete code.
          \"\"\",
          configurable: true
        }
      end
  """
  @callback info() :: info()

  @doc """
  Analyzes a single AST node in context.

  Called once per node during AST traversal. Returns a list of issues found
  at this node. Return empty list if no issues.

  The context includes:
  - Current document
  - Analyzer configuration
  - Parent node stack
  - Current depth
  - Custom scope data

  ## Examples

      @impl true
      def analyze({:literal, :integer, value}, _context) when value > 1000 do
        [
          %{
            analyzer: __MODULE__,
            category: :style,
            severity: :warning,
            message: "Large literal value \#{value}",
            node: {:literal, :integer, value},
            location: %{line: nil, column: nil, path: nil},
            suggestion: nil,
            metadata: %{value: value}
          }
        ]
      end

      def analyze(_node, _context), do: []
  """
  @callback analyze(node :: AST.meta_ast(), context :: context()) :: [issue()]

  @doc """
  Optional: Called once before AST traversal starts.

  Use this for:
  - Initializing analyzer state
  - Pre-processing the document
  - Checking if analysis should proceed

  Return `{:ok, context}` to continue with (possibly modified) context.
  Return `{:skip, reason}` to skip this analyzer entirely.

  ## Examples

      @impl true
      def run_before(context) do
        # Initialize state in context
        context = Map.put(context, :assigned, %{})
        context = Map.put(context, :used, MapSet.new())
        {:ok, context}
      end

      # Or skip if conditions not met
      def run_before(context) do
        if context.document.language == :unsupported do
          {:skip, :unsupported_language}
        else
          {:ok, context}
        end
      end
  """
  @callback run_before(context :: context()) :: {:ok, context()} | {:skip, reason :: term()}

  @doc """
  Optional: Called once after AST traversal completes.

  Use this for:
  - Final analysis requiring full AST knowledge
  - Cross-node validation
  - Generating summary issues

  Receives all issues collected so far. Can return modified or additional issues.

  ## Examples

      @impl true
      def run_after(context, issues) do
        # Generate issues from collected state
        assigned = Map.keys(context.assigned)
        used = context.used

        unused = Enum.filter(assigned, fn var ->
          not MapSet.member?(used, var)
        end)

        new_issues = Enum.map(unused, fn var ->
          %{
            analyzer: __MODULE__,
            category: :correctness,
            severity: :warning,
            message: "Variable '\#{var}' is assigned but never used",
            node: {:variable, var},
            location: %{line: nil, column: nil, path: nil},
            suggestion: nil,
            metadata: %{variable: var}
          }
        end)

        issues ++ new_issues
      end
  """
  @callback run_after(context :: context(), issues :: [issue()]) :: [issue()]

  @optional_callbacks run_before: 1, run_after: 2

  # ----- Helper Functions -----

  @doc """
  Creates an issue map with required fields.

  ## Examples

      iex> Analyzer.issue(
      ...>   analyzer: MyAnalyzer,
      ...>   category: :style,
      ...>   severity: :warning,
      ...>   message: "Found an issue",
      ...>   node: {:literal, :integer, 42}
      ...> )
      %{
        analyzer: MyAnalyzer,
        category: :style,
        severity: :warning,
        message: "Found an issue",
        node: {:literal, :integer, 42},
        location: %{line: nil, column: nil, path: nil},
        suggestion: nil,
        metadata: %{}
      }
  """
  @spec issue(keyword()) :: issue()
  def issue(opts) do
    %{
      analyzer: Keyword.fetch!(opts, :analyzer),
      category: Keyword.fetch!(opts, :category),
      severity: Keyword.fetch!(opts, :severity),
      message: Keyword.fetch!(opts, :message),
      node: Keyword.fetch!(opts, :node),
      location: Keyword.get(opts, :location, %{line: nil, column: nil, path: nil}),
      suggestion: Keyword.get(opts, :suggestion),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a suggestion map.

  ## Examples

      iex> Analyzer.suggestion(
      ...>   type: :replace,
      ...>   replacement: {:variable, "CONSTANT"},
      ...>   message: "Extract to constant"
      ...> )
      %{
        type: :replace,
        replacement: {:variable, "CONSTANT"},
        message: "Extract to constant"
      }
  """
  @spec suggestion(keyword()) :: suggestion()
  def suggestion(opts) do
    %{
      type: Keyword.fetch!(opts, :type),
      replacement: Keyword.get(opts, :replacement),
      message: Keyword.fetch!(opts, :message)
    }
  end

  @doc """
  Validates that a module implements the Analyzer behaviour correctly.

  Checks:
  - Required functions are exported
  - info/0 returns valid structure
  - Required info keys are present

  ## Examples

      iex> Analyzer.valid?(MyAnalyzer)
      true

      iex> Analyzer.valid?(NotAnAnalyzer)
      false
  """
  @spec valid?(module()) :: boolean()
  def valid?(module) do
    with true <- function_exported?(module, :info, 0),
         true <- function_exported?(module, :analyze, 2),
         info <- module.info(),
         true <- is_map(info),
         true <- Map.has_key?(info, :name),
         true <- Map.has_key?(info, :category),
         true <- Map.has_key?(info, :description),
         true <- Map.has_key?(info, :severity),
         true <- Map.has_key?(info, :explanation),
         true <- Map.has_key?(info, :configurable) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Extracts the name from an analyzer module.

  ## Examples

      iex> module.info()
      %{name: :unused_variables, ...}
      iex> Analyzer.name(module)
      :unused_variables
  """
  @spec name(module()) :: atom()
  def name(module) do
    module.info().name
  end

  @doc """
  Extracts the category from an analyzer module.

  ## Examples

      iex> Analyzer.category(module)
      :correctness
  """
  @spec category(module()) :: category()
  def category(module) do
    module.info().category
  end

  @doc """
  Checks if an analyzer is configurable.

  ## Examples

      iex> Analyzer.configurable?(module)
      true
  """
  @spec configurable?(module()) :: boolean()
  def configurable?(module) do
    module.info().configurable
  end
end
