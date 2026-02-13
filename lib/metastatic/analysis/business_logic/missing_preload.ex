defmodule Metastatic.Analysis.BusinessLogic.MissingPreload do
  @moduledoc """
  Detects database queries without eager loading (N+1 query potential).

  Universal pattern: accessing related data without preloading/prefetching.

  ## Examples

  **Python (Django ORM without select_related):**
  ```python
  users = User.objects.all()  # Should use select_related('profile')
  for user in users:
      print(user.profile.bio)  # N+1 query - profile accessed in loop
  ```

  **JavaScript (Sequelize without include):**
  ```javascript
  const users = await User.findAll();  # Should include: [{ model: Profile }]
  users.forEach(user => {
      console.log(user.profile.bio);  # N+1 - profile fetched per user
  });
  ```

  **Elixir (Ecto without preload):**
  ```elixir
  users = Repo.all(User)  # Should use preload(:profile)
  Enum.each(users, fn user ->
      IO.puts(user.profile.bio)  # N+1 - profile loaded per user
  end)
  ```

  **C# (Entity Framework without Include):**
  ```csharp
  var users = context.Users.ToList();  # Should use Include(u => u.Profile)
  foreach (var user in users) {
      Console.WriteLine(user.Profile.Bio);  # Lazy loading - N+1 queries
  }
  ```

  **Go (GORM without Preload):**
  ```go
  var users []User
  db.Find(&users)  # Should use Preload(\"Profile\")
  for _, user := range users {
      fmt.Println(user.Profile.Bio)  # N+1 - separate query per user
  }
  ```

  **Java (Hibernate without JOIN FETCH):**
  ```java
  List<User> users = session.createQuery(\"FROM User\").list();  # Should use JOIN FETCH
  for (User user : users) {
      System.out.println(user.getProfile().getBio());  # Lazy loading triggers N queries
  }
  ```

  **Ruby (ActiveRecord without includes):**
  ```ruby
  users = User.all  # Should use User.includes(:profile)
  users.each do |user|
      puts user.profile.bio  # N+1 - profile query per user
  end
  ```

  ## Detection Modes

  The analyzer supports two detection modes:

  1. **Semantic (preferred)**: Uses `op_kind` metadata from semantic enrichment.
     If a function_call has `op_kind: [domain: :db, operation: :retrieve_all]`,
     it's definitively a database collection query.

  2. **Heuristic (fallback)**: Uses pattern matching on function names when
     semantic metadata is not available. May produce false positives.
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @query_functions ~w[
    all find query select fetch load
    findall getall findMany where filter
  ]

  @impl true
  def info do
    %{
      name: :missing_preload,
      category: :performance,
      description: "Detects potential N+1 queries from missing eager loading",
      severity: :warning,
      explanation: "Use eager loading (preload/include) to avoid N+1 query problems",
      configurable: true
    }
  end

  @impl true
  # New 3-tuple format: {:collection_op, [op_type: :map], [fn, collection]}
  def analyze({:collection_op, meta, [_fn | rest]} = node, _context) when is_list(meta) do
    op_type = Keyword.get(meta, :op_type)
    collection = List.last(rest)

    if op_type == :map and from_database_query?(collection) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :performance,
          severity: :warning,
          message: "Mapping over database results without eager loading - potential N+1 queries",
          node: node,
          metadata: %{
            suggestion: "Use preload/include/select_related to eager load associations"
          }
        )
      ]
    else
      []
    end
  end

  # Handle location-aware nodes
  def analyze({:collection_op, :map, _fn, collection, _loc} = node, _context) do
    # Check if collection comes from DB query
    if from_database_query?(collection) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :performance,
          severity: :warning,
          message: "Mapping over database results without eager loading - potential N+1 queries",
          node: node,
          metadata: %{
            suggestion: "Use preload/include/select_related to eager load associations"
          }
        )
      ]
    else
      []
    end
  end

  def analyze({:collection_op, :map, _fn, collection} = node, _context) do
    # Check if collection comes from DB query
    if from_database_query?(collection) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :performance,
          severity: :warning,
          message: "Mapping over database results without eager loading - potential N+1 queries",
          node: node,
          metadata: %{
            suggestion: "Use preload/include/select_related to eager load associations"
          }
        )
      ]
    else
      []
    end
  end

  # New 3-tuple loop format: {:loop, [loop_type: :for], [iterator, collection, body]}
  def analyze({:loop, meta, children} = node, _context) when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)

    # collection is typically second child
    collection =
      case children do
        [_iterator, collection | _] -> collection
        _ -> nil
      end

    if loop_type == :for and collection != nil and from_database_query?(collection) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :performance,
          severity: :warning,
          message: "Looping over database results - ensure associations are preloaded",
          node: node,
          metadata: %{
            suggestion: "Add eager loading to avoid N+1 queries"
          }
        )
      ]
    else
      []
    end
  end

  def analyze({:loop, :for, _iterator, collection, _body} = node, _context) do
    # Check if iterating over DB results
    if from_database_query?(collection) do
      [
        Analyzer.issue(
          analyzer: __MODULE__,
          category: :performance,
          severity: :warning,
          message: "Looping over database results - ensure associations are preloaded",
          node: node,
          metadata: %{
            suggestion: "Add eager loading to avoid N+1 queries"
          }
        )
      ]
    else
      []
    end
  end

  def analyze(_node, _context), do: []

  # New 3-tuple: {:function_call, [name: name, op_kind: [...]], args}
  # Check op_kind metadata first (semantic), then fall back to heuristics
  defp from_database_query?({:function_call, meta, _args}) when is_list(meta) do
    case Keyword.get(meta, :op_kind) do
      # Semantic detection: op_kind metadata present
      op_kind when is_list(op_kind) ->
        # Check if it's a DB operation that returns collections
        domain = Keyword.get(op_kind, :domain)
        operation = Keyword.get(op_kind, :operation)
        domain == :db and operation in [:retrieve_all, :query]

      # Fallback to heuristic detection
      nil ->
        fn_name = Keyword.get(meta, :name, "")
        fn_lower = String.downcase(to_string(fn_name))
        String.contains?(fn_lower, @query_functions)
    end
  end

  # Handle location-aware nodes
  defp from_database_query?({:function_call, fn_name, _args, _loc}) when is_binary(fn_name) do
    fn_lower = String.downcase(fn_name)
    String.contains?(fn_lower, @query_functions)
  end

  defp from_database_query?({:function_call, fn_name, _args}) when is_binary(fn_name) do
    fn_lower = String.downcase(fn_name)
    String.contains?(fn_lower, @query_functions)
  end

  # New 3-tuple: {:variable, meta, name}
  defp from_database_query?({:variable, _meta, name}) when is_binary(name) do
    name_lower = String.downcase(name)

    String.contains?(name_lower, [
      "user",
      "post",
      "item",
      "record",
      "result",
      "data"
    ])
  end

  defp from_database_query?({:variable, name, _loc}) when is_binary(name) do
    name_lower = String.downcase(name)

    String.contains?(name_lower, [
      "user",
      "post",
      "item",
      "record",
      "result",
      "data"
    ])
  end

  defp from_database_query?({:variable, name}) when is_binary(name) do
    name_lower = String.downcase(name)

    String.contains?(name_lower, [
      "user",
      "post",
      "item",
      "record",
      "result",
      "data"
    ])
  end

  defp from_database_query?(_), do: false
end
