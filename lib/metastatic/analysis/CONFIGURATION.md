# Analyzer Configuration System

Metastatic's analyzer configuration system is embedded in the Analysis Runner and supports per-analyzer settings.

## Configuration Format

Configuration is passed as a map to `Runner.run/2` where:
- **Keys** are analyzer names (atoms from `analyzer.info().name`)
- **Values** are analyzer-specific configuration maps

```elixir
config = %{
  callback_hell: %{max_nesting: 3},
  hardcoded_value: %{exclude_localhost: true, exclude_local_ips: false},
  unused_variables: %{ignore_underscore_prefix: true}
}

Runner.run(document, analyzers: :all, config: config)
```

## How It Works

1. **Runner receives config**: The config map is passed to `Runner.run/2`
2. **Per-analyzer extraction**: For each analyzer, the Runner extracts the analyzer-specific config using the analyzer's name
3. **Context initialization**: The analyzer-specific config is placed in the context's `:config` key
4. **run_before/1 hook**: Analyzers can access and process their config in `run_before/1`
5. **Analysis**: The configured context is used throughout analysis

## Example: Configurable Analyzer

```elixir
defmodule MyAnalyzer do
  @behaviour Metastatic.Analysis.Analyzer
  
  @impl true
  def info do
    %{
      name: :my_analyzer,  # This name is used as config key
      # ...
      configurable: true
    }
  end
  
  @impl true
  def run_before(context) do
    # Extract configuration
    max_depth = Map.get(context.config, :max_depth, 10)  # default: 10
    strict_mode = Map.get(context.config, :strict_mode, false)  # default: false
    
    # Store in context for use during analysis
    context =
      context
      |> Map.put(:max_depth, max_depth)
      |> Map.put(:strict_mode, strict_mode)
    
    {:ok, context}
  end
  
  @impl true
  def analyze(node, context) do
    # Use configured values
    max_depth = Map.get(context, :max_depth)
    strict_mode = Map.get(context, :strict_mode)
    
    # Analysis logic using configuration...
  end
end
```

## Usage Patterns

### Default Configuration

Analyzers without configuration use built-in defaults:

```elixir
Runner.run(document, analyzers: [MyAnalyzer])
# MyAnalyzer uses default max_depth: 10, strict_mode: false
```

### Partial Configuration

Only override specific settings:

```elixir
Runner.run(document,
  analyzers: [MyAnalyzer],
  config: %{my_analyzer: %{max_depth: 20}}
)
# max_depth: 20, strict_mode: false (default)
```

### Full Configuration

Override all settings:

```elixir
Runner.run(document,
  analyzers: [MyAnalyzer],
  config: %{
    my_analyzer: %{
      max_depth: 15,
      strict_mode: true
    }
  }
)
```

### Multiple Analyzers

Configure different analyzers independently:

```elixir
Runner.run(document,
  analyzers: [CallbackHell, HardcodedValue, UnusedVariables],
  config: %{
    callback_hell: %{max_nesting: 3},
    hardcoded_value: %{exclude_localhost: true},
    unused_variables: %{ignore_underscore_prefix: false}
  }
)
```

## Configuration Guidelines

### For Analyzer Authors

1. **Document defaults**: Clearly document default values in your analyzer's `@moduledoc`
2. **Use sensible defaults**: Don't require configuration for common use cases
3. **Validate config**: Check config values in `run_before/1` and return `{:skip, :invalid_config}` if invalid
4. **Mark as configurable**: Set `configurable: true` in `info/0` if your analyzer accepts configuration

```elixir
@impl true
def run_before(context) do
  max_value = Map.get(context.config, :max_value, 100)
  
  if max_value < 1 do
    {:skip, {:invalid_config, "max_value must be >= 1"}}
  else
    {:ok, Map.put(context, :max_value, max_value)}
  end
end
```

### For Analyzer Users

1. **Check analyzer info**: Call `analyzer.info()` to see if `configurable: true`
2. **Read documentation**: Check analyzer's `@moduledoc` for available options
3. **Use analyzer names**: Config keys must match `info().name` (atom, not module name)
4. **Provide maps**: Configuration values must be maps

## Built-in Analyzer Configurations

### CallbackHell

```elixir
%{callback_hell: %{max_nesting: 2}}  # default: 2
```

### HardcodedValue

```elixir
%{
  hardcoded_value: %{
    exclude_localhost: true,   # default: true
    exclude_local_ips: true    # default: true
  }
}
```

## Future Enhancements

Potential future additions to the configuration system:

1. **Configuration validation**: Schema-based validation
2. **Configuration files**: Load from `.metastatic.exs` or similar
3. **Profile support**: Named configuration profiles (`:strict`, `:relaxed`, etc.)
4. **Dynamic configuration**: Config functions that adapt based on context
5. **Configuration inheritance**: Base configs with overrides

## Implementation Details

The configuration system is implemented in `Metastatic.Analysis.Runner`:

```elixir
# Runner extracts analyzer-specific config
defp run_before_hooks(analyzers, base_context) do
  Enum.reduce(analyzers, {[], %{}}, fn analyzer, {ready, contexts} ->
    # Get analyzer-specific config by name
    analyzer_config = Map.get(base_context.config, analyzer.info().name, %{})
    context_with_config = Map.put(base_context, :config, analyzer_config)
    
    # Call analyzer's run_before with scoped config
    case analyzer.run_before(context_with_config) do
      {:ok, ctx} -> {ready ++ [analyzer], Map.put(contexts, analyzer, ctx)}
      {:skip, _} -> {ready, contexts}
    end
  end)
end
```

The key insight: Each analyzer receives only its own configuration slice, preventing configuration leakage between analyzers.
