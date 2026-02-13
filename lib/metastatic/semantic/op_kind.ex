defmodule Metastatic.Semantic.OpKind do
  @moduledoc """
  Semantic operation kind metadata for MetaAST nodes.

  OpKind captures the semantic meaning of function calls and operations,
  enabling analyzers to reason about code at a higher level than raw syntax.

  ## Structure

  An OpKind is a keyword list with the following fields:

  - `:domain` - The operation domain (required)
  - `:operation` - The specific operation type (required)
  - `:target` - The entity/resource being operated on (optional)
  - `:async` - Whether this is an async operation (optional, default: false)
  - `:framework` - The framework/library this pattern comes from (optional)

  ## Domains

  Currently supported domains:

  - `:db` - Database operations (CRUD, transactions, queries)

  Future domains (not yet implemented):

  - `:http` - HTTP client operations
  - `:auth` - Authentication/authorization
  - `:cache` - Cache operations
  - `:queue` - Message queue operations
  - `:file` - File I/O operations
  - `:external_api` - External API calls

  ## Database Operations (`:db`)

  | Operation | Description |
  |-----------|-------------|
  | `:retrieve` | Fetch single record by primary key |
  | `:retrieve_all` | Fetch multiple/all records |
  | `:query` | Complex query with conditions |
  | `:create` | Insert new record |
  | `:update` | Update existing record |
  | `:delete` | Delete record |
  | `:transaction` | Transaction boundary |
  | `:preload` | Eager load associations |
  | `:aggregate` | Aggregation operations (count, sum, etc.) |

  ## Examples

      # Elixir/Ecto: Repo.get(User, 1)
      [domain: :db, operation: :retrieve, target: "User", framework: :ecto]

      # Python/Django: User.objects.filter(active=True)
      [domain: :db, operation: :query, target: "User", framework: :django]

      # JavaScript/Sequelize: User.findAll()
      [domain: :db, operation: :retrieve_all, target: "User", framework: :sequelize]

  ## Usage in MetaAST

  OpKind is stored in the metadata of `:function_call` nodes:

      {:function_call, [
        name: "Repo.get",
        line: 42,
        op_kind: [domain: :db, operation: :retrieve, target: "User"]
      ], [args...]}

  Analyzers can check for the presence of `op_kind`:

      def analyze({:function_call, meta, _args} = node, _context) do
        case Keyword.get(meta, :op_kind) do
          nil -> use_heuristics(node)
          op_kind -> analyze_with_semantic(node, op_kind)
        end
      end
  """

  # ----- Type Definitions -----

  @typedoc "Supported operation domains"
  @type domain :: :db | :http | :auth | :cache | :queue | :file | :external_api

  @typedoc "Database operation types"
  @type db_operation ::
          :retrieve
          | :retrieve_all
          | :query
          | :create
          | :update
          | :delete
          | :transaction
          | :preload
          | :aggregate

  @typedoc "All operation types (union of domain-specific operations)"
  @type operation :: db_operation()

  @typedoc "Known framework identifiers"
  # Elixir
  @type framework ::
          :ecto
          | :amnesia
          # Python
          | :sqlalchemy
          | :django
          | :peewee
          # JavaScript
          | :sequelize
          | :typeorm
          | :prisma
          | :mongoose
          # Ruby
          | :activerecord
          # General
          | :unknown

  @typedoc "OpKind as a keyword list"
  @type t :: [
          domain: domain(),
          operation: operation(),
          target: String.t() | nil,
          async: boolean(),
          framework: framework() | nil
        ]

  # ----- Domain and Operation Constants -----

  @domains [:db, :http, :auth, :cache, :queue, :file, :external_api]

  @db_operations [
    :retrieve,
    :retrieve_all,
    :query,
    :create,
    :update,
    :delete,
    :transaction,
    :preload,
    :aggregate
  ]

  # ----- Public API -----

  @doc """
  Creates a new OpKind keyword list.

  ## Examples

      iex> Metastatic.Semantic.OpKind.new(:db, :retrieve)
      [domain: :db, operation: :retrieve, target: nil, async: false, framework: nil]

      iex> Metastatic.Semantic.OpKind.new(:db, :retrieve, target: "User", framework: :ecto)
      [domain: :db, operation: :retrieve, target: "User", async: false, framework: :ecto]
  """
  @spec new(domain(), operation(), keyword()) :: t()
  def new(domain, operation, opts \\ []) when domain in @domains do
    [
      domain: domain,
      operation: operation,
      target: Keyword.get(opts, :target),
      async: Keyword.get(opts, :async, false),
      framework: Keyword.get(opts, :framework)
    ]
  end

  @doc """
  Checks if a value is a valid OpKind.

  ## Examples

      iex> Metastatic.Semantic.OpKind.valid?([domain: :db, operation: :retrieve])
      true

      iex> Metastatic.Semantic.OpKind.valid?([domain: :invalid, operation: :foo])
      false

      iex> Metastatic.Semantic.OpKind.valid?("not a keyword list")
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(op_kind) when is_list(op_kind) do
    domain = Keyword.get(op_kind, :domain)
    operation = Keyword.get(op_kind, :operation)

    domain in @domains and valid_operation?(domain, operation)
  end

  def valid?(_), do: false

  @doc """
  Gets the domain from an OpKind.

  ## Examples

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.domain(op_kind)
      :db
  """
  @spec domain(t()) :: domain() | nil
  def domain(op_kind), do: Keyword.get(op_kind, :domain)

  @doc """
  Gets the operation from an OpKind.

  ## Examples

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.operation(op_kind)
      :retrieve
  """
  @spec operation(t()) :: operation() | nil
  def operation(op_kind), do: Keyword.get(op_kind, :operation)

  @doc """
  Gets the target from an OpKind.

  ## Examples

      iex> op_kind = [domain: :db, operation: :retrieve, target: "User"]
      iex> Metastatic.Semantic.OpKind.target(op_kind)
      "User"
  """
  @spec target(t()) :: String.t() | nil
  def target(op_kind), do: Keyword.get(op_kind, :target)

  @doc """
  Checks if this is a database operation.

  ## Examples

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.db?(op_kind)
      true

      iex> op_kind = [domain: :http, operation: :get]
      iex> Metastatic.Semantic.OpKind.db?(op_kind)
      false
  """
  @spec db?(t()) :: boolean()
  def db?(op_kind), do: Keyword.get(op_kind, :domain) == :db

  @doc """
  Checks if this is a read operation (retrieve, retrieve_all, query).

  ## Examples

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.read?(op_kind)
      true

      iex> op_kind = [domain: :db, operation: :create]
      iex> Metastatic.Semantic.OpKind.read?(op_kind)
      false
  """
  @spec read?(t()) :: boolean()
  def read?(op_kind) do
    Keyword.get(op_kind, :operation) in [:retrieve, :retrieve_all, :query]
  end

  @doc """
  Checks if this is a write operation (create, update, delete).

  ## Examples

      iex> op_kind = [domain: :db, operation: :create]
      iex> Metastatic.Semantic.OpKind.write?(op_kind)
      true

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.write?(op_kind)
      false
  """
  @spec write?(t()) :: boolean()
  def write?(op_kind) do
    Keyword.get(op_kind, :operation) in [:create, :update, :delete]
  end

  @doc """
  Returns all supported domains.

  ## Examples

      iex> Metastatic.Semantic.OpKind.domains()
      [:db, :http, :auth, :cache, :queue, :file, :external_api]
  """
  @spec domains() :: [domain()]
  def domains, do: @domains

  @doc """
  Returns all supported database operations.

  ## Examples

      iex> Metastatic.Semantic.OpKind.db_operations()
      [:retrieve, :retrieve_all, :query, :create, :update, :delete, :transaction, :preload, :aggregate]
  """
  @spec db_operations() :: [db_operation()]
  def db_operations, do: @db_operations

  # ----- Private Helpers -----

  defp valid_operation?(:db, op), do: op in @db_operations
  # Future domains - for now accept any atom
  defp valid_operation?(_domain, op) when is_atom(op), do: true
  defp valid_operation?(_, _), do: false
end
