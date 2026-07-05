defmodule Math do
  @moduledoc "Math utilities"

  @spec factorial(non_neg_integer()) :: pos_integer()
  def factorial(0), do: 1
  def factorial(n) when n > 0, do: n * factorial(n - 1)

  @spec fibonacci(non_neg_integer()) :: non_neg_integer()
  def fibonacci(0), do: 0
  def fibonacci(1), do: 1
  def fibonacci(n) when n > 1, do: fibonacci(n - 1) + fibonacci(n - 2)

  def sum_list([]), do: 0
  def sum_list([h | t]), do: h + sum_list(t)
end
