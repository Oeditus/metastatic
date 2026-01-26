defmodule Metastatic.Analysis.BusinessLogic.NPlusOneQuery do
  @moduledoc """
  Detects N+1 query anti-pattern across all ORM frameworks.

  This analyzer identifies code that performs database queries inside loops or
  collection operations, leading to N+1 query problems - a major performance
  issue in database-driven applications.

  ## Cross-Language Applicability

  This is a **universal ORM anti-pattern** that appears in all languages:

  - **Python/Django**: `[User.objects.get(id=i.user_id) for i in items]`
  - **Python/SQLAlchemy**: `[session.query(User).get(item.user_id) for item in items]`
  - **JavaScript/Sequelize**: `items.map(item => User.findByPk(item.userId))`
  - **JavaScript/TypeORM**: `items.map(async item => userRepo.findOne(item.userId))`
  - **Elixir/Ecto**: `Enum.map(items, fn item -> Repo.get(User, item.user_id) end)`
  - **Ruby/ActiveRecord**: `items.map { |item| User.find(item.user_id) }`
  - **C#/Entity Framework**: `items.Select(item => context.Users.Find(item.UserId))`
  - **Java/Hibernate**: `items.stream().map(item -> session.get(User.class, item.getUserId()))`

  ## Problem

  When you iterate over a collection and perform a database query for each item,
  you end up with:
  - 1 query to fetch the collection
  - N queries (one per item) to fetch related data

  This scales poorly: 100 items = 101 queries!

  ## Examples

  ### Bad (Python/Django)

      users = BlogPost.objects.all()
      for post in posts:
          author = User.objects.get(id=post.author_id)  # N queries!
          print(author.name)

  ### Good (Python/Django)

      posts = BlogPost.objects.select_related('author').all()
      for post in posts:
          print(post.author.name)  # No additional queries

  ### Bad (JavaScript)

      const posts = await Post.findAll();
      const enriched = posts.map(async post => ({
        ...post,
        author: await User.findByPk(post.authorId)  // N queries!
      }));

  ### Good (JavaScript)

      const posts = await Post.findAll({ include: [User] });
      const enriched = posts.map(post => ({
        ...post,
        author: post.User  // Already loaded
      }));

  ### Bad (Elixir/Ecto)

      posts = Repo.all(Post)
      Enum.map(posts, fn post ->
        user = Repo.get(User, post.user_id)  # N queries!
        {post, user}
      end)

  ### Good (Elixir/Ecto)

      posts = Post |> preload(:user) |> Repo.all()
      Enum.map(posts, fn post -> {post, post.user} end)

  ## Detection Strategy

  Detects the MetaAST pattern:

      {:collection_op, operation, lambda, collection}

  Where `lambda` (the function passed to map/filter/etc.) contains:
  - Database query operations (identified by heuristics)
  - Function calls matching database patterns

  ### Database Operation Heuristics

  Function names suggesting database operations:
  - `*get*`, `*find*`, `*query*`, `*fetch*`
  - `*load*`, `*select*`, `*retrieve*`
  - Specific ORM patterns: `Repo.*`, `*.objects.*`, `*Repository.*`

  ## Configuration

  This analyzer is not configurable - N+1 queries are always a performance issue.

  ## Limitations

  - May produce false positives for non-database "get" operations
  - Cannot detect N+1 at higher levels (e.g., GraphQL resolvers)
  - Requires heuristic matching - adapt as needed
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  # Common database operation keywords across languages
  @database_keywords [
    # Generic
    :get,
    :find,
    :query,
    :fetch,
    :load,
    :select,
    :retrieve,
    # ORM-specific
    :findOne,
    :findByPk,
    :findAll,
    :get!,
    :get_by,
    :one,
    :all
  ]

  @impl true
  def info do
    %{
      name: :n_plus_one_query,
      category: :performance,
      description: "Detects N+1 query anti-pattern in database operations",
      severity: :warning,
      explanation: """
      N+1 query problems occur when code performs a database query inside a loop
      or collection operation. This leads to poor performance as the number of
      database queries scales linearly with collection size.

      Instead of querying inside loops:
      - Use eager loading (preload, includes, select_related, etc.)
      - Batch queries outside the loop
      - Use join operations to fetch related data upfront

      This pattern is universal across all ORMs and database access libraries.
      """,
      configurable: false
    }
  end

  @impl true
  def analyze({:collection_op, operation, lambda, _collection} = node, _context)
      when operation in [:map, :each, :flat_map, :reduce] do
    if contains_database_operation?(lambda) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :performance,
          severity: :warning,
          message:
            "Potential N+1 query: database operation inside #{operation} - consider eager loading",
          node: node,
          metadata: %{
            collection_operation: operation,
            suggestion: "Use eager loading (preload/include/select_related) to fetch data upfront"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Check if AST contains database operations
  defp contains_database_operation?({:lambda, _params, _captures, body}) do
    # Lambda is {:lambda, params, captures, body}
    contains_database_call?(body)
  end

  defp contains_database_operation?({:lambda, _params, body}) do
    # Old 3-tuple format for backwards compat
    contains_database_call?(body)
  end

  defp contains_database_operation?({:function_call, _name, _args}) do
    # Direct function call in map (less common but possible)
    false
  end

  defp contains_database_operation?(_), do: false

  # Recursively search for database-like function calls
  defp contains_database_call?({:block, statements}) when is_list(statements) do
    Enum.any?(statements, &contains_database_call?/1)
  end

  defp contains_database_call?({:function_call, func_name, _args}) when is_atom(func_name) do
    database_function?(func_name)
  end

  defp contains_database_call?({:function_call, func_name, _args}) when is_binary(func_name) do
    database_function?(func_name)
  end

  # Check attribute access patterns like: obj.method()
  defp contains_database_call?({:attribute_access, _obj, attr}) when is_atom(attr) do
    database_function?(attr)
  end

  # Recurse into nested structures
  defp contains_database_call?({:conditional, _cond, then_branch, else_branch}) do
    contains_database_call?(then_branch) or contains_database_call?(else_branch)
  end

  defp contains_database_call?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.any?(&contains_database_call?/1)
  end

  defp contains_database_call?(list) when is_list(list) do
    Enum.any?(list, &contains_database_call?/1)
  end

  defp contains_database_call?(_), do: false

  # Check if function name suggests database operation
  defp database_function?(func_name) when is_atom(func_name) do
    # Direct match
    if func_name in @database_keywords do
      true
    else
      # Pattern match
      func_str = Atom.to_string(func_name) |> String.downcase()

      Enum.any?(
        ["get", "find", "query", "fetch", "load", "select", "repo", "objects", "repository"],
        &String.contains?(func_str, &1)
      )
    end
  end

  defp database_function?(func_name) when is_binary(func_name) do
    # String function names (e.g., "Repo.get", "User.find")
    func_str = String.downcase(func_name)

    Enum.any?(
      ["get", "find", "query", "fetch", "load", "select", "repo", "objects", "repository"],
      &String.contains?(func_str, &1)
    )
  end

  defp database_function?(_), do: false
end
