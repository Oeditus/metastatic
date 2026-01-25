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
  """

  @behaviour Metastatic.Analysis.Analyzer
  alias Metastatic.Analysis.Analyzer

  @query_functions ~w[
    all find get query select fetch load
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

  defp from_database_query?({:function_call, fn_name, _args}) when is_binary(fn_name) do
    fn_lower = String.downcase(fn_name)
    String.contains?(fn_lower, @query_functions)
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
