defmodule Metastatic.Semantic.Domains.Database do
  @moduledoc """
  Database operation patterns for semantic enrichment.

  This module defines patterns for detecting database operations across
  multiple languages and ORM frameworks. Patterns are registered with
  the `Metastatic.Semantic.Patterns` registry at module load time.

  ## Supported Frameworks

  ### Elixir
  - **Ecto** - `Repo.*` operations

  ### Python
  - **SQLAlchemy** - `session.*`, `query.*` operations
  - **Django ORM** - `*.objects.*` operations
  - **Peewee** - Model class operations

  ### Ruby
  - **ActiveRecord** - Model class and instance operations

  ### JavaScript
  - **Sequelize** - Model class operations
  - **TypeORM** - Repository operations
  - **Prisma** - Client operations
  - **Mongoose** - Model operations

  ## Pattern Structure

  Each pattern is a tuple of `{pattern, spec}` where:
  - `pattern` - String or Regex to match function names
  - `spec` - Map with operation details:
    - `:operation` - The database operation type
    - `:framework` - The ORM framework identifier
    - `:extract_target` - Strategy for extracting entity name

  ## Target Extraction

  Three strategies for extracting the target entity:
  - `:first_arg` - First argument is the entity (e.g., `Repo.get(User, 1)`)
  - `:receiver` - Receiver is the entity (e.g., `User.find(1)`)
  - `:none` - No target extraction
  """

  alias Metastatic.Semantic.Patterns

  # ----- Elixir/Ecto Patterns -----

  @elixir_patterns [
    # Single record retrieval
    {"Repo.get", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},
    {"Repo.get!", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},
    {"Repo.get_by", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},
    {"Repo.get_by!", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},
    {"Repo.one", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},
    {"Repo.one!", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},

    # Multiple record retrieval
    {"Repo.all", %{operation: :retrieve_all, framework: :ecto, extract_target: :first_arg}},

    # Create operations
    {"Repo.insert", %{operation: :create, framework: :ecto, extract_target: :none}},
    {"Repo.insert!", %{operation: :create, framework: :ecto, extract_target: :none}},
    {"Repo.insert_all", %{operation: :create, framework: :ecto, extract_target: :first_arg}},
    {"Repo.insert_or_update", %{operation: :create, framework: :ecto, extract_target: :none}},
    {"Repo.insert_or_update!", %{operation: :create, framework: :ecto, extract_target: :none}},

    # Update operations
    {"Repo.update", %{operation: :update, framework: :ecto, extract_target: :none}},
    {"Repo.update!", %{operation: :update, framework: :ecto, extract_target: :none}},
    {"Repo.update_all", %{operation: :update, framework: :ecto, extract_target: :first_arg}},

    # Delete operations
    {"Repo.delete", %{operation: :delete, framework: :ecto, extract_target: :none}},
    {"Repo.delete!", %{operation: :delete, framework: :ecto, extract_target: :none}},
    {"Repo.delete_all", %{operation: :delete, framework: :ecto, extract_target: :first_arg}},

    # Transactions
    {"Repo.transaction", %{operation: :transaction, framework: :ecto, extract_target: :none}},

    # Preloading
    {"Repo.preload", %{operation: :preload, framework: :ecto, extract_target: :none}},

    # Aggregates
    {"Repo.aggregate", %{operation: :aggregate, framework: :ecto, extract_target: :first_arg}},
    {"Repo.exists?", %{operation: :query, framework: :ecto, extract_target: :first_arg}},

    # Query building (when piped to Repo)
    {"Ecto.Query.from", %{operation: :query, framework: :ecto, extract_target: :none}},

    # Wildcard for custom Repo modules (e.g., MyApp.Repo.get)
    {"*.Repo.get", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},
    {"*.Repo.get!", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},
    {"*.Repo.all", %{operation: :retrieve_all, framework: :ecto, extract_target: :first_arg}},
    {"*.Repo.one", %{operation: :retrieve, framework: :ecto, extract_target: :first_arg}},
    {"*.Repo.insert", %{operation: :create, framework: :ecto, extract_target: :none}},
    {"*.Repo.insert!", %{operation: :create, framework: :ecto, extract_target: :none}},
    {"*.Repo.update", %{operation: :update, framework: :ecto, extract_target: :none}},
    {"*.Repo.update!", %{operation: :update, framework: :ecto, extract_target: :none}},
    {"*.Repo.delete", %{operation: :delete, framework: :ecto, extract_target: :none}},
    {"*.Repo.delete!", %{operation: :delete, framework: :ecto, extract_target: :none}},
    {"*.Repo.transaction", %{operation: :transaction, framework: :ecto, extract_target: :none}},
    {"*.Repo.preload", %{operation: :preload, framework: :ecto, extract_target: :none}}
  ]

  # ----- Python/SQLAlchemy Patterns -----

  @python_sqlalchemy_patterns [
    # Session operations
    {"session.query", %{operation: :query, framework: :sqlalchemy, extract_target: :first_arg}},
    {"session.add", %{operation: :create, framework: :sqlalchemy, extract_target: :first_arg}},
    {"session.add_all", %{operation: :create, framework: :sqlalchemy, extract_target: :none}},
    {"session.delete", %{operation: :delete, framework: :sqlalchemy, extract_target: :first_arg}},
    {"session.merge", %{operation: :update, framework: :sqlalchemy, extract_target: :first_arg}},
    {"session.commit", %{operation: :transaction, framework: :sqlalchemy, extract_target: :none}},
    {"session.rollback",
     %{operation: :transaction, framework: :sqlalchemy, extract_target: :none}},
    {"session.flush", %{operation: :transaction, framework: :sqlalchemy, extract_target: :none}},

    # Query methods (chained) - use regex to avoid matching Django .objects. patterns
    {~r/^[^.]+\.get$/, %{operation: :retrieve, framework: :sqlalchemy, extract_target: :none}},
    {~r/^[^.]+\.first$/, %{operation: :retrieve, framework: :sqlalchemy, extract_target: :none}},
    {~r/^[^.]+\.one$/, %{operation: :retrieve, framework: :sqlalchemy, extract_target: :none}},
    {~r/^[^.]+\.all$/,
     %{operation: :retrieve_all, framework: :sqlalchemy, extract_target: :none}},
    {~r/^[^.]+\.filter$/, %{operation: :query, framework: :sqlalchemy, extract_target: :none}},
    {~r/^[^.]+\.filter_by$/, %{operation: :query, framework: :sqlalchemy, extract_target: :none}},
    {~r/^[^.]+\.count$/, %{operation: :aggregate, framework: :sqlalchemy, extract_target: :none}}
  ]

  # ----- Python/Django ORM Patterns -----

  @python_django_patterns [
    # Manager operations (Model.objects.*)
    {~r/\.objects\.get\b/,
     %{operation: :retrieve, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.get_or_create\b/,
     %{operation: :retrieve, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.filter\b/,
     %{operation: :query, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.exclude\b/,
     %{operation: :query, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.all\b/,
     %{operation: :retrieve_all, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.first\b/,
     %{operation: :retrieve, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.last\b/,
     %{operation: :retrieve, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.create\b/,
     %{operation: :create, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.bulk_create\b/,
     %{operation: :create, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.update\b/,
     %{operation: :update, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.delete\b/,
     %{operation: :delete, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.count\b/,
     %{operation: :aggregate, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.aggregate\b/,
     %{operation: :aggregate, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.select_related\b/,
     %{operation: :preload, framework: :django, extract_target: :receiver}},
    {~r/\.objects\.prefetch_related\b/,
     %{operation: :preload, framework: :django, extract_target: :receiver}},

    # Instance save/delete
    {~r/\.save\b/, %{operation: :update, framework: :django, extract_target: :receiver}},
    {~r/\.delete\b/, %{operation: :delete, framework: :django, extract_target: :receiver}}
  ]

  # ----- Ruby/ActiveRecord Patterns -----

  @ruby_patterns [
    # Class methods for finding
    {"*.find", %{operation: :retrieve, framework: :activerecord, extract_target: :receiver}},
    {"*.find_by", %{operation: :retrieve, framework: :activerecord, extract_target: :receiver}},
    {"*.find_by!", %{operation: :retrieve, framework: :activerecord, extract_target: :receiver}},
    {"*.find_or_create_by",
     %{operation: :retrieve, framework: :activerecord, extract_target: :receiver}},
    {"*.find_or_initialize_by",
     %{operation: :retrieve, framework: :activerecord, extract_target: :receiver}},
    {"*.first", %{operation: :retrieve, framework: :activerecord, extract_target: :receiver}},
    {"*.last", %{operation: :retrieve, framework: :activerecord, extract_target: :receiver}},
    {"*.take", %{operation: :retrieve, framework: :activerecord, extract_target: :receiver}},

    # Collection retrieval
    {"*.all", %{operation: :retrieve_all, framework: :activerecord, extract_target: :receiver}},
    {"*.where", %{operation: :query, framework: :activerecord, extract_target: :receiver}},
    {"*.select", %{operation: :query, framework: :activerecord, extract_target: :receiver}},
    {"*.joins", %{operation: :query, framework: :activerecord, extract_target: :receiver}},
    {"*.includes", %{operation: :preload, framework: :activerecord, extract_target: :receiver}},
    {"*.eager_load", %{operation: :preload, framework: :activerecord, extract_target: :receiver}},
    {"*.preload", %{operation: :preload, framework: :activerecord, extract_target: :receiver}},

    # Create operations
    {"*.create", %{operation: :create, framework: :activerecord, extract_target: :receiver}},
    {"*.create!", %{operation: :create, framework: :activerecord, extract_target: :receiver}},
    {"*.new", %{operation: :create, framework: :activerecord, extract_target: :receiver}},
    {"*.insert_all", %{operation: :create, framework: :activerecord, extract_target: :receiver}},

    # Update operations
    {"*.update", %{operation: :update, framework: :activerecord, extract_target: :receiver}},
    {"*.update!", %{operation: :update, framework: :activerecord, extract_target: :receiver}},
    {"*.update_all", %{operation: :update, framework: :activerecord, extract_target: :receiver}},
    {"*.save", %{operation: :update, framework: :activerecord, extract_target: :none}},
    {"*.save!", %{operation: :update, framework: :activerecord, extract_target: :none}},

    # Delete operations
    {"*.destroy", %{operation: :delete, framework: :activerecord, extract_target: :none}},
    {"*.destroy!", %{operation: :delete, framework: :activerecord, extract_target: :none}},
    {"*.destroy_all", %{operation: :delete, framework: :activerecord, extract_target: :receiver}},
    {"*.delete", %{operation: :delete, framework: :activerecord, extract_target: :none}},
    {"*.delete_all", %{operation: :delete, framework: :activerecord, extract_target: :receiver}},

    # Aggregates
    {"*.count", %{operation: :aggregate, framework: :activerecord, extract_target: :receiver}},
    {"*.sum", %{operation: :aggregate, framework: :activerecord, extract_target: :receiver}},
    {"*.average", %{operation: :aggregate, framework: :activerecord, extract_target: :receiver}},
    {"*.minimum", %{operation: :aggregate, framework: :activerecord, extract_target: :receiver}},
    {"*.maximum", %{operation: :aggregate, framework: :activerecord, extract_target: :receiver}},

    # Transactions
    {"*.transaction", %{operation: :transaction, framework: :activerecord, extract_target: :none}}
  ]

  # ----- JavaScript/Sequelize Patterns -----

  @javascript_sequelize_patterns [
    # Find operations
    {"*.findByPk", %{operation: :retrieve, framework: :sequelize, extract_target: :receiver}},
    {"*.findOne", %{operation: :retrieve, framework: :sequelize, extract_target: :receiver}},
    {"*.findAll", %{operation: :retrieve_all, framework: :sequelize, extract_target: :receiver}},
    {"*.findAndCountAll",
     %{operation: :retrieve_all, framework: :sequelize, extract_target: :receiver}},
    {"*.findOrCreate", %{operation: :retrieve, framework: :sequelize, extract_target: :receiver}},

    # Create operations
    {"*.create", %{operation: :create, framework: :sequelize, extract_target: :receiver}},
    {"*.bulkCreate", %{operation: :create, framework: :sequelize, extract_target: :receiver}},

    # Update operations
    {"*.update", %{operation: :update, framework: :sequelize, extract_target: :receiver}},
    {"*.save", %{operation: :update, framework: :sequelize, extract_target: :none}},

    # Delete operations
    {"*.destroy", %{operation: :delete, framework: :sequelize, extract_target: :receiver}},

    # Aggregates
    {"*.count", %{operation: :aggregate, framework: :sequelize, extract_target: :receiver}},
    {"*.max", %{operation: :aggregate, framework: :sequelize, extract_target: :receiver}},
    {"*.min", %{operation: :aggregate, framework: :sequelize, extract_target: :receiver}},
    {"*.sum", %{operation: :aggregate, framework: :sequelize, extract_target: :receiver}}
  ]

  # ----- JavaScript/TypeORM Patterns -----

  @javascript_typeorm_patterns [
    # Repository operations
    {"*.findOne", %{operation: :retrieve, framework: :typeorm, extract_target: :none}},
    {"*.findOneBy", %{operation: :retrieve, framework: :typeorm, extract_target: :none}},
    {"*.findOneOrFail", %{operation: :retrieve, framework: :typeorm, extract_target: :none}},
    {"*.find", %{operation: :retrieve_all, framework: :typeorm, extract_target: :none}},
    {"*.findBy", %{operation: :retrieve_all, framework: :typeorm, extract_target: :none}},
    {"*.findAndCount", %{operation: :retrieve_all, framework: :typeorm, extract_target: :none}},

    # Save operations
    {"*.save", %{operation: :create, framework: :typeorm, extract_target: :none}},
    {"*.insert", %{operation: :create, framework: :typeorm, extract_target: :none}},

    # Update operations
    {"*.update", %{operation: :update, framework: :typeorm, extract_target: :none}},

    # Delete operations
    {"*.delete", %{operation: :delete, framework: :typeorm, extract_target: :none}},
    {"*.remove", %{operation: :delete, framework: :typeorm, extract_target: :none}},

    # Query builder
    {"*.createQueryBuilder",
     %{operation: :query, framework: :typeorm, extract_target: :first_arg}},

    # Transactions
    {"*.transaction", %{operation: :transaction, framework: :typeorm, extract_target: :none}}
  ]

  # ----- JavaScript/Prisma Patterns -----

  @javascript_prisma_patterns [
    # Prisma client operations
    {"*.findUnique", %{operation: :retrieve, framework: :prisma, extract_target: :receiver}},
    {"*.findUniqueOrThrow",
     %{operation: :retrieve, framework: :prisma, extract_target: :receiver}},
    {"*.findFirst", %{operation: :retrieve, framework: :prisma, extract_target: :receiver}},
    {"*.findFirstOrThrow",
     %{operation: :retrieve, framework: :prisma, extract_target: :receiver}},
    {"*.findMany", %{operation: :retrieve_all, framework: :prisma, extract_target: :receiver}},

    # Create operations
    {"*.create", %{operation: :create, framework: :prisma, extract_target: :receiver}},
    {"*.createMany", %{operation: :create, framework: :prisma, extract_target: :receiver}},

    # Update operations
    {"*.update", %{operation: :update, framework: :prisma, extract_target: :receiver}},
    {"*.updateMany", %{operation: :update, framework: :prisma, extract_target: :receiver}},
    {"*.upsert", %{operation: :update, framework: :prisma, extract_target: :receiver}},

    # Delete operations
    {"*.delete", %{operation: :delete, framework: :prisma, extract_target: :receiver}},
    {"*.deleteMany", %{operation: :delete, framework: :prisma, extract_target: :receiver}},

    # Aggregates
    {"*.count", %{operation: :aggregate, framework: :prisma, extract_target: :receiver}},
    {"*.aggregate", %{operation: :aggregate, framework: :prisma, extract_target: :receiver}},
    {"*.groupBy", %{operation: :aggregate, framework: :prisma, extract_target: :receiver}},

    # Transactions
    {"$transaction", %{operation: :transaction, framework: :prisma, extract_target: :none}}
  ]

  # ----- Registration -----

  @doc """
  Registers all database patterns for all languages.

  Called automatically when the module is loaded. Can also be called
  manually to re-register patterns (e.g., after clearing).
  """
  @spec register_all() :: :ok
  def register_all do
    # Elixir patterns
    Patterns.register(:db, :elixir, @elixir_patterns)

    # Python patterns (Django first - more specific, then SQLAlchemy)
    Patterns.register(:db, :python, @python_django_patterns ++ @python_sqlalchemy_patterns)

    # Ruby patterns
    Patterns.register(:db, :ruby, @ruby_patterns)

    # JavaScript patterns (Sequelize + TypeORM + Prisma)
    Patterns.register(
      :db,
      :javascript,
      @javascript_sequelize_patterns ++
        @javascript_typeorm_patterns ++ @javascript_prisma_patterns
    )

    :ok
  end

  # Auto-register on module load
  # Note: This runs at compile time, so patterns are available immediately
  @doc false
  def __on_definition__(_env, _kind, _name, _args, _guards, _body) do
    # Called during compilation - ensure patterns are registered
    :ok
  end
end

# Register patterns when module is loaded
# This ensures patterns are available at runtime
Metastatic.Semantic.Domains.Database.register_all()
