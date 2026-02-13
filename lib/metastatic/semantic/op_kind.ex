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

  @typedoc "HTTP operation types"
  @type http_operation ::
          :get
          | :post
          | :put
          | :patch
          | :delete
          | :head
          | :options
          | :request
          | :stream

  @typedoc "Auth operation types"
  @type auth_operation ::
          :login
          | :logout
          | :authenticate
          | :register
          | :verify_token
          | :generate_token
          | :refresh_token
          | :hash_password
          | :verify_password
          | :authorize
          | :oauth
          | :session

  @typedoc "Cache operation types"
  @type cache_operation ::
          :get
          | :set
          | :delete
          | :clear
          | :invalidate
          | :expire
          | :exists
          | :increment
          | :decrement
          | :ttl
          | :fetch

  @typedoc "Queue operation types"
  @type queue_operation ::
          :publish
          | :consume
          | :subscribe
          | :acknowledge
          | :reject
          | :enqueue
          | :dequeue
          | :schedule
          | :retry
          | :process

  @typedoc "File operation types"
  @type file_operation ::
          :read
          | :write
          | :append
          | :delete
          | :copy
          | :move
          | :exists
          | :stat
          | :mkdir
          | :rmdir
          | :list
          | :open
          | :close

  @typedoc "External API operation types"
  @type external_api_operation ::
          :call
          | :upload
          | :download
          | :send
          | :charge
          | :webhook
          | :search
          | :sync

  @typedoc "All operation types (union of domain-specific operations)"
  @type operation ::
          db_operation()
          | http_operation()
          | auth_operation()
          | cache_operation()
          | queue_operation()
          | file_operation()
          | external_api_operation()

  @typedoc "Known framework identifiers"
  # Elixir DB
  @type framework ::
          :ecto
          | :amnesia
          # Python DB
          | :sqlalchemy
          | :django
          | :peewee
          # JavaScript DB
          | :sequelize
          | :typeorm
          | :prisma
          | :mongoose
          # Ruby DB
          | :activerecord
          # Elixir HTTP
          | :httpoison
          | :req
          | :tesla
          | :finch
          # Python HTTP
          | :requests
          | :httpx
          | :aiohttp
          # Ruby HTTP
          | :nethttp
          | :httparty
          | :faraday
          | :restclient
          # JavaScript HTTP
          | :fetch
          | :axios
          | :got
          | :superagent
          # Elixir Auth
          | :guardian
          | :pow
          | :bcrypt_elixir
          | :argon2_elixir
          | :pbkdf2_elixir
          | :comeonin
          | :ueberauth
          # Python Auth
          | :flask_login
          | :pyjwt
          | :jose
          | :passlib
          # Ruby Auth
          | :devise
          | :warden
          | :bcrypt_ruby
          # JavaScript Auth
          | :passport
          | :jsonwebtoken
          | :bcryptjs
          | :auth0
          # Elixir Cache
          | :cachex
          | :concache
          | :nebulex
          | :ets
          # Python Cache
          | :redis_py
          | :django_cache
          | :flask_cache
          # Ruby Cache
          | :rails_cache
          | :dalli
          | :redis_rb
          # JavaScript Cache
          | :node_cache
          | :ioredis
          # Elixir Queue
          | :broadway
          | :oban
          | :genstage
          | :amqp
          # Python Queue
          | :celery
          | :rq
          | :kombu
          # Ruby Queue
          | :sidekiq
          | :activejob
          | :resque
          # JavaScript Queue
          | :bullmq
          | :amqplib
          | :agenda
          # Elixir File
          | :elixir_file
          | :elixir_io
          # Python File
          | :python_builtin
          | :python_os
          | :pathlib
          | :shutil
          # Ruby File
          | :ruby_file
          | :fileutils
          # JavaScript File
          | :nodejs_fs
          | :nodejs_fs_promises
          # External API
          | :ex_aws
          | :boto3
          | :aws_sdk
          | :aws_sdk_js
          | :stripe
          | :twilio
          | :sendgrid
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

  @http_operations [
    :get,
    :post,
    :put,
    :patch,
    :delete,
    :head,
    :options,
    :request,
    :stream
  ]

  @auth_operations [
    :login,
    :logout,
    :authenticate,
    :register,
    :verify_token,
    :generate_token,
    :refresh_token,
    :hash_password,
    :verify_password,
    :authorize,
    :oauth,
    :session
  ]

  @cache_operations [
    :get,
    :set,
    :delete,
    :clear,
    :invalidate,
    :expire,
    :exists,
    :increment,
    :decrement,
    :ttl,
    :fetch
  ]

  @queue_operations [
    :publish,
    :consume,
    :subscribe,
    :acknowledge,
    :reject,
    :enqueue,
    :dequeue,
    :schedule,
    :retry,
    :process
  ]

  @file_operations [
    :read,
    :write,
    :append,
    :delete,
    :copy,
    :move,
    :exists,
    :stat,
    :mkdir,
    :rmdir,
    :list,
    :open,
    :close
  ]

  @external_api_operations [
    :call,
    :upload,
    :download,
    :send,
    :charge,
    :webhook,
    :search,
    :sync
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
  Checks if this is an HTTP operation.

  ## Examples

      iex> op_kind = [domain: :http, operation: :get]
      iex> Metastatic.Semantic.OpKind.http?(op_kind)
      true

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.http?(op_kind)
      false
  """
  @spec http?(t()) :: boolean()
  def http?(op_kind), do: Keyword.get(op_kind, :domain) == :http

  @doc """
  Checks if this is an auth operation.

  ## Examples

      iex> op_kind = [domain: :auth, operation: :login]
      iex> Metastatic.Semantic.OpKind.auth?(op_kind)
      true

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.auth?(op_kind)
      false
  """
  @spec auth?(t()) :: boolean()
  def auth?(op_kind), do: Keyword.get(op_kind, :domain) == :auth

  @doc """
  Checks if this is a cache operation.

  ## Examples

      iex> op_kind = [domain: :cache, operation: :get]
      iex> Metastatic.Semantic.OpKind.cache?(op_kind)
      true

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.cache?(op_kind)
      false
  """
  @spec cache?(t()) :: boolean()
  def cache?(op_kind), do: Keyword.get(op_kind, :domain) == :cache

  @doc """
  Checks if this is a queue operation.

  ## Examples

      iex> op_kind = [domain: :queue, operation: :enqueue]
      iex> Metastatic.Semantic.OpKind.queue?(op_kind)
      true

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.queue?(op_kind)
      false
  """
  @spec queue?(t()) :: boolean()
  def queue?(op_kind), do: Keyword.get(op_kind, :domain) == :queue

  @doc """
  Checks if this is a file operation.

  ## Examples

      iex> op_kind = [domain: :file, operation: :read]
      iex> Metastatic.Semantic.OpKind.file?(op_kind)
      true

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.file?(op_kind)
      false
  """
  @spec file?(t()) :: boolean()
  def file?(op_kind), do: Keyword.get(op_kind, :domain) == :file

  @doc """
  Checks if this is an external API operation.

  ## Examples

      iex> op_kind = [domain: :external_api, operation: :call]
      iex> Metastatic.Semantic.OpKind.external_api?(op_kind)
      true

      iex> op_kind = [domain: :db, operation: :retrieve]
      iex> Metastatic.Semantic.OpKind.external_api?(op_kind)
      false
  """
  @spec external_api?(t()) :: boolean()
  def external_api?(op_kind), do: Keyword.get(op_kind, :domain) == :external_api

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

  @doc """
  Returns all supported HTTP operations.

  ## Examples

      iex> Metastatic.Semantic.OpKind.http_operations()
      [:get, :post, :put, :patch, :delete, :head, :options, :request, :stream]
  """
  @spec http_operations() :: [http_operation()]
  def http_operations, do: @http_operations

  @doc """
  Returns all supported auth operations.

  ## Examples

      iex> Metastatic.Semantic.OpKind.auth_operations()
      [:login, :logout, :authenticate, :register, :verify_token, :generate_token, :refresh_token, :hash_password, :verify_password, :authorize, :oauth, :session]
  """
  @spec auth_operations() :: [auth_operation()]
  def auth_operations, do: @auth_operations

  @doc """
  Returns all supported cache operations.

  ## Examples

      iex> Metastatic.Semantic.OpKind.cache_operations()
      [:get, :set, :delete, :clear, :invalidate, :expire, :exists, :increment, :decrement, :ttl, :fetch]
  """
  @spec cache_operations() :: [cache_operation()]
  def cache_operations, do: @cache_operations

  @doc """
  Returns all supported queue operations.

  ## Examples

      iex> Metastatic.Semantic.OpKind.queue_operations()
      [:publish, :consume, :subscribe, :acknowledge, :reject, :enqueue, :dequeue, :schedule, :retry, :process]
  """
  @spec queue_operations() :: [queue_operation()]
  def queue_operations, do: @queue_operations

  @doc """
  Returns all supported file operations.

  ## Examples

      iex> Metastatic.Semantic.OpKind.file_operations()
      [:read, :write, :append, :delete, :copy, :move, :exists, :stat, :mkdir, :rmdir, :list, :open, :close]
  """
  @spec file_operations() :: [file_operation()]
  def file_operations, do: @file_operations

  @doc """
  Returns all supported external API operations.

  ## Examples

      iex> Metastatic.Semantic.OpKind.external_api_operations()
      [:call, :upload, :download, :send, :charge, :webhook, :search, :sync]
  """
  @spec external_api_operations() :: [external_api_operation()]
  def external_api_operations, do: @external_api_operations

  # ----- Private Helpers -----

  defp valid_operation?(:db, op), do: op in @db_operations
  defp valid_operation?(:http, op), do: op in @http_operations
  defp valid_operation?(:auth, op), do: op in @auth_operations
  defp valid_operation?(:cache, op), do: op in @cache_operations
  defp valid_operation?(:queue, op), do: op in @queue_operations
  defp valid_operation?(:file, op), do: op in @file_operations
  defp valid_operation?(:external_api, op), do: op in @external_api_operations
  defp valid_operation?(_, _), do: false
end
