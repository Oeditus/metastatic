# Performance Benchmarks

This directory contains performance benchmarks for all language adapters.

## Goal

Target: **<100ms per 1000 lines of code** for parsing and transforming to MetaAST.

## Running Benchmarks

```bash
# Install dependencies first
mix deps.get

# Run benchmarks
mix run benchmark/adapters_bench.exs run
```

Results will be displayed in the console and saved to `benchmark/results.html`.

## Benchmark Coverage

The suite benchmarks all 5 language adapters:
- Python
- Elixir
- Erlang  
- Ruby
- Haskell

Each adapter is tested with realistic code samples (~100 LoC) containing:
- Function definitions
- Classes/modules
- Control flow (if/case)
- Loops and iterators
- Exception handling
- Collection operations

## Interpreting Results

Benchee provides several metrics:
- **Average**: Mean execution time
- **Median**: Middle value (more stable than average)
- **99th percentile**: Worst-case performance
- **Standard deviation**: Consistency of performance
- **Memory**: Allocation per operation

For 100 LoC samples, we target ~10ms average execution time to meet the 100ms/1000 LoC goal.

## Extending Benchmarks

To add more scenarios:

1. Add sample code to `adapters_bench.exs`
2. Add a new benchmark entry in the `Benchee.run()` call
3. Document expected performance characteristics
