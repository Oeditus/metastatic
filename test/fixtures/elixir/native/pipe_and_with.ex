# Native Elixir constructs - M2.3 Native Layer

# Pipe operator
[1, 2, 3]
|> Enum.map(fn x -> x * 2 end)
|> Enum.filter(fn x -> x > 3 end)
|> Enum.sum()

# with expression
with {:ok, value} <- fetch_value(),
     {:ok, processed} <- process(value) do
  {:ok, processed}
else
  error -> {:error, error}
end

# Nested pipes
data
|> parse()
|> validate()
|> transform()
