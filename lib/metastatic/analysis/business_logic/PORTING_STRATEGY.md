# Strategy for Porting Remaining 15 Analyzers

Now that the Elixir adapter is complete, we can port the remaining 15 "Elixir-specific" analyzers from `oeditus_credo` by identifying their universal patterns at the MetaAST level.

## Key Insight

What appeared to be Elixir-specific (Ecto, Phoenix, GenServer, etc.) are actually **universal database/web/concurrency patterns** that exist across all languages:

- **Ecto** → Any ORM (Django ORM, SQLAlchemy, ActiveRecord, Entity Framework)
- **Phoenix LiveView** → Any reactive web framework (React, Vue, Angular)
- **GenServer** → Any actor/process model (Erlang, Akka, Orleans)
- **Oban** → Any background job system (Celery, Sidekiq, Hangfire)

## Universal Pattern Mapping

### Database/ORM Patterns

#### NPlusOneQuery
**Elixir Pattern**:
```elixir
Enum.map(collection, fn item -> Repo.get(...) end)
```

**Universal MetaAST Pattern**:
```elixir
{:collection_op, :map, lambda, collection}
# where lambda contains database operation patterns
```

**Applies to**:
- Python: `[db.query() for item in items]`
- JavaScript: `items.map(item => db.get())`
- C#: `items.Select(item => context.Find())`
- Ruby: `items.map { |item| User.find() }`

**Detection**: Collection operation with function containing database-like calls

#### MissingPreload/EagerLoading
**Elixir Pattern**:
```elixir
User |> Repo.all()  # without preload(:posts)
```

**Universal MetaAST Pattern**:
```elixir
{:function_call, :query_all, [schema]}
# without join/eager load hints
```

**Applies to**:
- Python/Django: `User.objects.all()` without `select_related()`
- Python/SQLAlchemy: `session.query(User).all()` without `joinedload()`
- C#/EF: `context.Users.ToList()` without `Include()`
- Ruby/ActiveRecord: `User.all` without `includes()`

**Detection**: Database query without relationship loading

#### InefficientFilter
**Elixir Pattern**:
```elixir
users = Repo.all(User)
Enum.filter(users, & &1.active)
```

**Universal MetaAST Pattern**:
```elixir
{:block, [
  {:assignment, var, {:function_call, :db_fetch_all, ...}},
  {:collection_op, :filter, fn, var}
]}
```

**Applies to**:
- Python: `users = User.objects.all(); [u for u in users if u.active]`
- JavaScript: `users = await User.find(); users.filter(u => u.active)`
- C#: `users = context.Users.ToList(); users.Where(u => u.Active)`

**Detection**: Database fetch followed by in-memory filtering

#### DirectStructUpdate
**Elixir Pattern**:
```elixir
%User{user | email: new_email}
```

**Universal MetaAST Pattern**:
```elixir
{:map, fields}  # Update operation on structured data
# without validation function call
```

**Applies to**:
- Python/Pydantic: `user.email = new_email` without `validate()`
- Ruby/Rails: `user.update_attribute` without validations
- C#: Direct property assignment without `Validate()`

**Detection**: Struct/object update without validation

### Concurrency/Async Patterns

#### UnmanagedTask
**Elixir Pattern**:
```elixir
Task.async(fn -> work() end)  # No supervisor
```

**Universal MetaAST Pattern**:
```elixir
{:async_operation, :spawn, lambda}
# without supervision/error handling
```

**Applies to**:
- Python: `asyncio.create_task()` without task group
- JavaScript: `new Promise()` without `.catch()`
- Go: `go func()` without wait group/context
- C#: `Task.Run()` without error handling

**Detection**: Async operation spawn without supervision

#### SyncOverAsync
**Elixir Pattern**:
```elixir
def handle_event(...) do
  Repo.get!(...)  # Blocking in async context
end
```

**Universal MetaAST Pattern**:
```elixir
{:function_def, callback_name, params, body}
# where body contains blocking operations
```

**Applies to**:
- Python: `async def handler(): requests.get()` (blocking in async)
- JavaScript: `async function() { fs.readFileSync() }`
- C#: `async Task Method() { File.ReadAllText() }`

**Detection**: Blocking operations in async function

#### MissingHandleAsync
**Elixir Pattern**:
```elixir
def handle_event(...) do
  data = Repo.all(...)  # Should use start_async
end
```

**Universal MetaAST Pattern**:
```elixir
{:function_def, event_handler_name, params, body}
# where body has blocking I/O without async wrapper
```

**Applies to**:
- React: `onClick` handler with sync API call
- Vue: Event handler with blocking operation
- Angular: Component method with sync HTTP

**Detection**: Event handler with blocking I/O

### Observability Patterns

#### MissingTelemetryForExternalHttp
**Elixir Pattern**:
```elixir
Req.get!(url)  # No telemetry wrapper
```

**Universal MetaAST Pattern**:
```elixir
{:function_call, :http_request, args}
# without telemetry/logging wrapper
```

**Applies to**:
- Python: `requests.get()` without logging
- JavaScript: `fetch()` without monitoring
- C#: `HttpClient.GetAsync()` without telemetry

**Detection**: HTTP client call without telemetry

#### MissingTelemetryInAuthPlug
**Elixir Pattern**:
```elixir
def call(conn, _opts) do
  verify_token(conn)  # No telemetry
end
```

**Universal MetaAST Pattern**:
```elixir
{:function_def, auth_function_name, params, body}
# without telemetry calls
```

**Applies to**:
- Express middleware: `(req, res, next) => { authenticate() }`
- Django middleware: `process_request(request)`
- ASP.NET middleware: `InvokeAsync(context)`

**Detection**: Authentication function without telemetry

#### MissingTelemetryInLiveViewMount/MissingTelemetryInObanWorker
Similar patterns apply to:
- React `useEffect` (missing monitoring)
- Background job workers across all languages

#### TelemetryInRecursiveFunction
**Universal Pattern**: Recursive function emitting metrics on each iteration

This is language-agnostic - applies to all languages with recursion.

### Template/UI Patterns

#### InlineJavascript
**Elixir Pattern** (HEEX):
```heex
<button onclick="alert('hi')">
```

**Universal Pattern**: Inline event handlers in templates

**Applies to**:
- HTML templates everywhere
- React JSX: Avoid inline complex handlers
- Vue templates: Prefer methods over inline

**Detection**: Template with inline script handlers

#### MissingThrottle
**Elixir Pattern** (HEEX):
```heex
<input phx-change="search">  # No phx-debounce
```

**Universal Pattern**: Frequent event without rate limiting

**Applies to**:
- React: `onChange` without debounce
- Vue: `@input` without throttle
- Angular: `(input)` without debounce

**Detection**: Frequent event handler without throttle

### Miscellaneous

#### BlockingInPlug
**Universal Pattern**: Blocking I/O in request handler

Applies to all web frameworks (Express, Django, ASP.NET, etc.)

## Implementation Priority

### Tier 1: Pure MetaAST (No Framework Knowledge)
1. **NPlusOneQuery** - Collection op with nested database calls
2. **InefficientFilter** - Fetch all then filter
3. **UnmanagedTask** - Async spawn without supervision
4. **TelemetryInRecursiveFunction** - Telemetry in recursion

### Tier 2: Function Name Heuristics
5. **MissingTelemetryForExternalHttp** - HTTP calls without telemetry
6. **SyncOverAsync** - Blocking in async function
7. **DirectStructUpdate** - Object update without validation
8. **MissingHandleAsync** - Event handler with blocking I/O

### Tier 3: Naming Conventions
9. **BlockingInPlug** - Request handler with blocking ops
10. **MissingTelemetryInAuthPlug** - Auth function without telemetry
11. **MissingTelemetryInLiveViewMount** - Lifecycle hook without telemetry
12. **MissingTelemetryInObanWorker** - Job worker without telemetry

### Tier 4: Content Analysis (May need language_specific)
13. **MissingPreload** - Query without eager loading
14. **InlineJavascript** - Inline handlers in templates
15. **MissingThrottle** - Frequent events without throttle

## Detection Strategies

### 1. Pattern Matching (Pure MetaAST)
Match specific AST structures regardless of language

### 2. Function Name Heuristics
Look for common naming patterns:
- `http_*`, `fetch_*`, `request_*` → HTTP operations
- `*_event`, `handle_*`, `on_*` → Event handlers
- `*_auth*`, `*_login*`, `*_verify*` → Authentication
- `db_*`, `query_*`, `fetch_*` → Database operations

### 3. Convention-Based
Use common conventions across languages:
- `mount`, `componentDidMount`, `useEffect` → Lifecycle
- `perform`, `execute`, `run` → Job workers
- `call`, `invoke`, `handle` → Middleware/handlers

### 4. Metadata Hints
Use language adapter metadata:
- Framework detection (Phoenix, Django, Express)
- Module patterns (use statements, imports)
- Type annotations (TypeScript, Python types)

## Implementation Approach

For each analyzer:

1. **Identify universal pattern** - What is the core anti-pattern?
2. **Map to MetaAST** - How does it appear at M2 level?
3. **Define detection logic** - Pattern matching + heuristics
4. **Add cross-language examples** - Python, JS, Elixir, C#, etc.
5. **Write comprehensive tests** - Test with MetaAST from multiple languages
6. **Document clearly** - Explain universal applicability

## Next Steps

1. Implement Tier 1 analyzers (pure MetaAST patterns)
2. Test with Elixir code via adapter
3. Verify patterns are truly language-agnostic
4. Document and iterate
