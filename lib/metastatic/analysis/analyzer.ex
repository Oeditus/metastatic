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
        # New 3-tuple format: {:assignment, meta, [target, value]}
        def analyze({:assignment, _meta, [{:variable, _, name}, _value]}, context) do
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
      # New 3-tuple format: {:literal, [subtype: :integer, ...], value}
      def analyze({:literal, meta, value} = node, _context) do
        subtype = Keyword.get(meta, :subtype)
        if subtype == :integer and value > 1000 do
          [
            %{
              analyzer: __MODULE__,
              category: :style,
              severity: :warning,
              message: "Large literal value \#{value}",
              node: node,
              location: %{line: nil, column: nil, path: nil},
              suggestion: nil,
              metadata: %{value: value}
            }
          ]
        else
          []
        end
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
            node: {:variable, [], var},  # New 3-tuple format
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

  Automatically extracts location information from the node's metadata if available.
  If the node has M1 context metadata (module, function, arity, etc.), it will be
  included in the location.

  ## Examples

      # New 3-tuple format example
      iex> Analyzer.issue(
      ...>   analyzer: MyAnalyzer,
      ...>   category: :style,
      ...>   severity: :warning,
      ...>   message: "Found an issue",
      ...>   node: {:literal, [subtype: :integer], 42}
      ...> )
      %{
        analyzer: MyAnalyzer,
        category: :style,
        severity: :warning,
        message: "Found an issue",
        node: {:literal, [subtype: :integer], 42},
        location: %{line: nil, column: nil, path: nil},
        suggestion: nil,
        metadata: %{}
      }

      # With M1 context metadata in node (new 3-tuple format):
      iex> node_with_context = {:variable, [line: 10, module: "MyApp", function: "foo", arity: 2], "x"}
      iex> Analyzer.issue(
      ...>   analyzer: MyAnalyzer,
      ...>   category: :style,
      ...>   severity: :warning,
      ...>   message: "Found an issue",
      ...>   node: node_with_context
      ...> )
      %{
        analyzer: MyAnalyzer,
        category: :style,
        severity: :warning,
        message: "Found an issue",
        node: node_with_context,
        location: %{line: 10, column: nil, path: nil, module: "MyApp", function: "foo", arity: 2},
        suggestion: nil,
        metadata: %{}
      }
  """
  @spec issue(keyword()) :: issue()
  def issue(opts) do
    node = Keyword.fetch!(opts, :node)

    # Extract location from node if not explicitly provided
    location =
      case Keyword.get(opts, :location) do
        nil -> extract_location_from_node(node)
        explicit_loc -> explicit_loc
      end

    %{
      analyzer: Keyword.fetch!(opts, :analyzer),
      category: Keyword.fetch!(opts, :category),
      severity: Keyword.fetch!(opts, :severity),
      message: Keyword.fetch!(opts, :message),
      node: node,
      location: location,
      suggestion: Keyword.get(opts, :suggestion),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # Extract location information from a MetaAST node
  # The new 3-tuple format stores location in keyword meta: {type, keyword_meta, children}
  # AST.location/1 returns a keyword list (or nil), so we use Keyword.get
  defp extract_location_from_node(node) do
    node_loc = AST.location(node)

    if node_loc do
      # Build location map with all available metadata from keyword list
      # AST.location/1 already returns a keyword list extracted from meta
      %{
        line: get_loc_value(node_loc, :line),
        column: get_loc_value(node_loc, :col) || get_loc_value(node_loc, :column),
        path: get_loc_value(node_loc, :file) || get_loc_value(node_loc, :path)
      }
      |> maybe_add(:module, get_loc_value(node_loc, :module))
      |> maybe_add(:function, get_loc_value(node_loc, :function))
      |> maybe_add(:arity, get_loc_value(node_loc, :arity))
      |> maybe_add(:container, get_loc_value(node_loc, :container))
      |> maybe_add(:visibility, get_loc_value(node_loc, :visibility))
      |> maybe_add(:language, get_loc_value(node_loc, :language))
    else
      # No location metadata in node
      %{line: nil, column: nil, path: nil}
    end
  end

  # Helper to get value from either keyword list or map
  defp get_loc_value(loc, key) when is_list(loc), do: Keyword.get(loc, key)
  defp get_loc_value(loc, key) when is_map(loc), do: Map.get(loc, key)
  defp get_loc_value(_, _), do: nil

  # Helper to conditionally add key to map if value is not nil
  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  @doc """
  Creates a suggestion map.

  ## Examples

      iex> Analyzer.suggestion(
      ...>   type: :replace,
      ...>   replacement: {:variable, [], "CONSTANT"},
      ...>   message: "Extract to constant"
      ...> )
      %{
        type: :replace,
        replacement: {:variable, [], "CONSTANT"},
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
