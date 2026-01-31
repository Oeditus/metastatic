defmodule Metastatic.Analysis.BusinessLogic.InefficientFilter do
  @moduledoc """
  Detects inefficient filtering: fetching all data then filtering in memory.

  This analyzer identifies code that fetches all records from a database/API,
  then filters them in application memory - a major performance anti-pattern.

  ## Cross-Language Applicability

  This is a **universal performance anti-pattern** across all data access layers:

  - **Python/Django**: `users = User.objects.all(); active = [u for u in users if u.active]`
  - **Python/SQLAlchemy**: `users = session.query(User).all(); active = filter(lambda u: u.active, users)`
  - **JavaScript/Sequelize**: `users = await User.findAll(); active = users.filter(u => u.active)`
  - **JavaScript/MongoDB**: `users = await collection.find().toArray(); active = users.filter(...)`
  - **Elixir/Ecto**: `users = Repo.all(User); Enum.filter(users, & &1.active)`
  - **Ruby/ActiveRecord**: `users = User.all; active = users.select(&:active?)`
  - **C#/Entity Framework**: `users = context.Users.ToList(); active = users.Where(u => u.Active)`
  - **Java/Hibernate**: `users = session.createQuery("from User").list(); filtered = users.stream().filter(...)`

  ## Problem

  Fetching all data then filtering wastes:
  - **Network bandwidth**: Transferring unnecessary data
  - **Memory**: Loading records that will be discarded
  - **CPU**: Client-side filtering instead of server-side
  - **Database resources**: Full table scan when index could be used

  For 1 million users where 100k are active:
  - **Bad**: Transfer 1M records, filter to 100k in memory
  - **Good**: Transfer 100k active records via WHERE clause

  ## Examples

  ### Bad (Python/Django)

      users = User.objects.all()  # Fetch all
      active_users = [u for u in users if u.is_active]  # Filter in memory

  ### Good (Python/Django)

      active_users = User.objects.filter(is_active=True)

  ### Bad (JavaScript)

      const posts = await Post.findAll();
      const published = posts.filter(p => p.status === 'published');

  ### Good (JavaScript)

      const published = await Post.findAll({ where: { status: 'published' } });

  ### Bad (Elixir/Ecto)

      users = Repo.all(User)
      active_users = Enum.filter(users, fn u -> u.active end)

  ### Good (Elixir/Ecto)

      import Ecto.Query
      active_users = User |> where([u], u.active == true) |> Repo.all()

  ### Bad (C#/Entity Framework)

      var users = context.Users.ToList();
      var active = users.Where(u => u.IsActive).ToList();

  ### Good (C#/Entity Framework)

      var active = context.Users.Where(u => u.IsActive).ToList();

  ## Detection Strategy

  Detects the pattern:

      {:block, [
        {:assignment, var, {:function_call, fetch_all_op, ...}},
        {:collection_op, :filter, lambda, var}
      ]}

  Where:
  1. Variable is assigned result of "fetch all" database operation
  2. Same variable is immediately filtered via collection operation

  ### Database "Fetch All" Heuristics

  Function names suggesting "fetch all":
  - `*all*`, `*findAll*`, `*getAll*`, `*fetchAll*`
  - `*toList*`, `*toArray*`, `*.list*`
  - ORM-specific: `Repo.all`, `*.objects.all()`, `query().all()`

  ## Limitations

  - Requires consecutive statements (assignment + filter)
  - May miss if intermediate operations occur
  - Heuristic-based: may have false positives/negatives
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  # Keywords suggesting "fetch all" operations
  @fetch_all_keywords [
    :all,
    :findAll,
    :getAll,
    :fetchAll,
    :toList,
    :toArray,
    :list
  ]

  @impl true
  def info do
    %{
      name: :inefficient_filter,
      category: :performance,
      description: "Detects fetching all data then filtering in memory",
      severity: :warning,
      explanation: """
      Fetching all records from a database/API then filtering in application
      memory is inefficient. The filtering should be pushed down to the data
      source (SQL WHERE clause, query filters, etc.) to:

      - Reduce network traffic
      - Use database indexes
      - Minimize memory usage
      - Improve performance

      This pattern is universal across all data access technologies.
      """,
      configurable: false
    }
  end

  @impl true
  def run_before(context) do
    # Track assignments for later reference
    {:ok, Map.put(context, :assignments, %{})}
  end

  @impl true
  def analyze({:block, statements}, context) when is_list(statements) do
    # Look for assignment followed by filter pattern
    find_fetch_filter_pattern(statements, context)
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  defp find_fetch_filter_pattern(statements, _context) do
    statements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn
      # Assignment of fetch-all followed by filter on same variable
      [
        {:assignment, var, fetch_expr},
        {:collection_op, :filter, _lambda, filter_var}
      ] ->
        if variables_match?(var, filter_var) and fetch_all?(fetch_expr) do
          loc = Metastatic.AST.location(filter_var) || Metastatic.AST.location(fetch_expr)

          [
            Analyzer.issue(
              analyzer: __MODULE__,
              category: :performance,
              severity: :warning,
              message:
                "Inefficient filter: fetching all data then filtering in memory - push filter to data source",
              node: {:block, [fetch_expr, filter_var]},
              location: make_location(loc),
              metadata: %{
                suggestion:
                  "Use database query filters (WHERE clause) instead of fetching all then filtering"
              }
            )
          ]
        else
          []
        end

      # Inline match (Elixir pattern matching) followed by filter
      [
        {:inline_match, var, fetch_expr},
        {:collection_op, :filter, _lambda, filter_var}
      ] ->
        if variables_match?(var, filter_var) and fetch_all?(fetch_expr) do
          loc = Metastatic.AST.location(filter_var) || Metastatic.AST.location(fetch_expr)

          [
            Analyzer.issue(
              analyzer: __MODULE__,
              category: :performance,
              severity: :warning,
              message:
                "Inefficient filter: fetching all data then filtering in memory - push filter to data source",
              node: {:block, [fetch_expr, filter_var]},
              location: make_location(loc),
              metadata: %{
                suggestion:
                  "Use database query filters (WHERE clause) instead of fetching all then filtering"
              }
            )
          ]
        else
          []
        end

      _ ->
        []
    end)
  end

  # Check if two variable references match (handle location-aware nodes)
  defp variables_match?({:variable, name1}, {:variable, name2}), do: name1 == name2
  defp variables_match?({:variable, name1, _loc}, {:variable, name2}), do: name1 == name2
  defp variables_match?({:variable, name1}, {:variable, name2, _loc}), do: name1 == name2
  defp variables_match?({:variable, name1, _loc1}, {:variable, name2, _loc2}), do: name1 == name2
  defp variables_match?(_, _), do: false

  # Check if expression is a "fetch all" operation (handle location-aware nodes)
  defp fetch_all?({:function_call, func_name, _args, _loc}) when is_atom(func_name) do
    fetch_all_function?(func_name)
  end

  defp fetch_all?({:function_call, func_name, _args}) when is_atom(func_name) do
    fetch_all_function?(func_name)
  end

  defp fetch_all?({:function_call, func_name, _args, _loc}) when is_binary(func_name) do
    fetch_all_function?(func_name)
  end

  defp fetch_all?({:function_call, func_name, _args}) when is_binary(func_name) do
    fetch_all_function?(func_name)
  end

  defp fetch_all?({:attribute_access, _obj, method, _loc}) when is_atom(method) do
    fetch_all_function?(method)
  end

  defp fetch_all?({:attribute_access, _obj, method}) when is_atom(method) do
    fetch_all_function?(method)
  end

  defp fetch_all?(_), do: false

  # Check if function name suggests "fetch all"
  defp fetch_all_function?(func_name) when is_atom(func_name) do
    # Direct match
    if func_name in @fetch_all_keywords do
      true
    else
      # Pattern match
      func_str = Atom.to_string(func_name) |> String.downcase()

      Enum.any?(
        ["all", "findall", "getall", "fetchall", "tolist", "toarray", "list", "repo"],
        &String.contains?(func_str, &1)
      )
    end
  end

  defp fetch_all_function?(func_name) when is_binary(func_name) do
    # String function names (e.g., "Repo.all", "User.findAll")
    func_str = String.downcase(func_name)

    Enum.any?(
      ["all", "findall", "getall", "fetchall", "tolist", "toarray", "list", "repo"],
      &String.contains?(func_str, &1)
    )
  end

  defp fetch_all_function?(_), do: false

  # Convert AST location to analyzer location format
  defp make_location(nil), do: %{line: nil, column: nil, path: nil}

  defp make_location(%{line: line} = loc) do
    %{
      line: line,
      column: Map.get(loc, :col),
      path: nil
    }
  end
end
