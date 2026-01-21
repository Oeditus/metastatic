defmodule AdaptersBench do
  @moduledoc """
  Performance benchmarks for all language adapters.
  Target: <100ms per 1000 LoC
  """

  # Sample code for each language (approximately 100 LoC each for ~10ms target)

  @python_sample """
  def factorial(n):
      if n <= 1:
          return 1
      return n * factorial(n - 1)

  def fibonacci(n):
      if n <= 1:
          return n
      return fibonacci(n - 1) + fibonacci(n - 2)

  class Calculator:
      def __init__(self, initial=0):
          self.value = initial
      
      def add(self, x):
          self.value += x
          return self
      
      def multiply(self, x):
          self.value *= x
          return self
      
      def result(self):
          return self.value

  numbers = [1, 2, 3, 4, 5]
  squared = list(map(lambda x: x ** 2, numbers))
  filtered = [x for x in numbers if x % 2 == 0]

  try:
      result = 10 / 0
  except ZeroDivisionError as e:
      print(f"Error: {e}")
  finally:
      print("Done")
  """

  @elixir_sample """
  defmodule Math do
    def factorial(0), do: 1
    def factorial(n) when n > 0, do: n * factorial(n - 1)

    def fibonacci(0), do: 0
    def fibonacci(1), do: 1
    def fibonacci(n), do: fibonacci(n - 1) + fibonacci(n - 2)
  end

  defmodule Calculator do
    defstruct value: 0

    def new(initial \\\\ 0), do: %Calculator{value: initial}

    def add(%Calculator{value: v} = calc, x), do: %{calc | value: v + x}
    def multiply(%Calculator{value: v} = calc, x), do: %{calc | value: v * x}
    def result(%Calculator{value: v}), do: v
  end

  numbers = [1, 2, 3, 4, 5]
  squared = Enum.map(numbers, fn x -> x * x end)
  filtered = for x <- numbers, rem(x, 2) == 0, do: x

  try do
    10 / 0
  rescue
    ArithmeticError -> IO.puts("Error")
  end
  """

  @erlang_sample """
  -module(math_utils).
  -export([factorial/1, fibonacci/1]).

  factorial(0) -> 1;
  factorial(N) when N > 0 -> N * factorial(N - 1).

  fibonacci(0) -> 0;
  fibonacci(1) -> 1;
  fibonacci(N) -> fibonacci(N - 1) + fibonacci(N - 2).

  -module(calculator).
  -export([new/0, new/1, add/2, multiply/2, result/1]).

  new() -> {calculator, 0}.
  new(Initial) -> {calculator, Initial}.

  add({calculator, Value}, X) -> {calculator, Value + X}.
  multiply({calculator, Value}, X) -> {calculator, Value * X}.
  result({calculator, Value}) -> Value.

  process_numbers() ->
      Numbers = [1, 2, 3, 4, 5],
      Squared = lists:map(fun(X) -> X * X end, Numbers),
      Filtered = [X || X <- Numbers, X rem 2 =:= 0],
      {Squared, Filtered}.
  """

  @ruby_sample """
  def factorial(n)
    return 1 if n <= 1
    n * factorial(n - 1)
  end

  def fibonacci(n)
    return n if n <= 1
    fibonacci(n - 1) + fibonacci(n - 2)
  end

  class Calculator
    attr_reader :value

    def initialize(initial = 0)
      @value = initial
    end

    def add(x)
      @value += x
      self
    end

    def multiply(x)
      @value *= x
      self
    end
  end

  numbers = [1, 2, 3, 4, 5]
  squared = numbers.map { |x| x ** 2 }
  filtered = numbers.select { |x| x.even? }

  begin
    result = 10 / 0
  rescue ZeroDivisionError => e
    puts "Error: #{e}"
  ensure
    puts "Done"
  end
  """

  @haskell_sample """
  factorial :: Int -> Int
  factorial 0 = 1
  factorial n = n * factorial (n - 1)

  fibonacci :: Int -> Int
  fibonacci 0 = 0
  fibonacci 1 = 1
  fibonacci n = fibonacci (n - 1) + fibonacci (n - 2)

  data Calculator = Calculator { value :: Int }

  newCalculator :: Int -> Calculator
  newCalculator initial = Calculator { value = initial }

  addCalc :: Calculator -> Int -> Calculator
  addCalc (Calculator v) x = Calculator (v + x)

  multiplyCalc :: Calculator -> Int -> Calculator
  multiplyCalc (Calculator v) x = Calculator (v * x)

  numbers = [1, 2, 3, 4, 5]
  squared = map (\\x -> x * x) numbers
  filtered = [x | x <- numbers, even x]

  processResult = case (10 `div` 0) of
    result -> result
  """

  def run do
    Benchee.run(
      %{
        "Python parse + transform" => fn ->
          benchmark_adapter(Metastatic.Adapters.Python, @python_sample, 100)
        end,
        "Elixir parse + transform" => fn ->
          benchmark_adapter(Metastatic.Adapters.Elixir, @elixir_sample, 100)
        end,
        "Erlang parse + transform" => fn ->
          benchmark_adapter(Metastatic.Adapters.Erlang, @erlang_sample, 100)
        end,
        "Ruby parse + transform" => fn ->
          benchmark_adapter(Metastatic.Adapters.Ruby, @ruby_sample, 100)
        end,
        "Haskell parse + transform" => fn ->
          benchmark_adapter(Metastatic.Adapters.Haskell, @haskell_sample, 100)
        end
      },
      time: 5,
      memory_time: 2,
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true},
        {Benchee.Formatters.HTML, file: "benchmark/results.html"}
      ]
    )
  end

  defp benchmark_adapter(adapter, sample, loc) do
    {:ok, ast} = adapter.parse(sample)
    {:ok, _meta_ast, _metadata} = adapter.to_meta(ast)
    
    # Return LoC for reference
    loc
  end
end

# Run if executed directly
if System.argv() == ["run"] do
  AdaptersBench.run()
end
