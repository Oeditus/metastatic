defmodule MyLisp.Reader do
  @moduledoc """
  A minimal s-expression reader — the "M1" side of the adapter.

  Real adapters shell out to a language-native parser (Python's `ast`, Babel,
  `sqlparser-rs`); this one parses in the BEAM because a toy dialect does not
  justify a subprocess. The shape it produces is what matters: a tagged map,
  which is exactly what a JSON-emitting bridge would return.

      "42"        -> %{"type" => "int", "value" => 42}
      "foo"       -> %{"type" => "symbol", "value" => "foo"}
      "(+ 1 2)"   -> %{"type" => "list", "items" => [...]}
      "(def x 1)" -> %{"type" => "list", "items" => [...]}

  Parse errors are `{:error, reason}` — never a raise — because the adapter
  contract requires a missing or broken toolchain to degrade gracefully.
  """

  @type sexp :: %{required(String.t()) => term()}

  @doc """
  Reads a single s-expression.

  ## Examples

      iex> MyLisp.Reader.read("42")
      {:ok, %{"type" => "int", "value" => 42}}

      iex> MyLisp.Reader.read("(+ 1 2)")
      {:ok, %{"type" => "list", "items" => [
      ...>   %{"type" => "symbol", "value" => "+"},
      ...>   %{"type" => "int", "value" => 1},
      ...>   %{"type" => "int", "value" => 2}
      ...> ]}}

      iex> MyLisp.Reader.read("(+ 1")
      {:error, "unexpected end of input"}
  """
  @spec read(String.t()) :: {:ok, sexp()} | {:error, String.t()}
  def read(source) when is_binary(source) do
    with {:ok, tokens} <- tokenize(source),
         {:ok, node, []} <- parse(tokens) do
      {:ok, node}
    else
      {:ok, _node, rest} -> {:error, "unexpected trailing input: #{inspect(rest)}"}
      {:error, _reason} = error -> error
    end
  end

  # ----- Tokenizer -----

  defp tokenize(source) do
    source
    |> String.replace("(", " ( ")
    |> String.replace(")", " ) ")
    |> String.split()
    |> Enum.map(&classify/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:error, reason}, _acc -> {:halt, {:error, reason}}
      token, {:ok, acc} -> {:cont, {:ok, [token | acc]}}
    end)
    |> case do
      {:ok, tokens} -> {:ok, Enum.reverse(tokens)}
      {:error, _} = error -> error
    end
  end

  defp classify("("), do: :open
  defp classify(")"), do: :close

  defp classify(token) do
    case Integer.parse(token) do
      {value, ""} -> {:int, value}
      _ -> {:symbol, token}
    end
  end

  # ----- Parser -----

  defp parse([{:int, value} | rest]), do: {:ok, %{"type" => "int", "value" => value}, rest}
  defp parse([{:symbol, name} | rest]), do: {:ok, %{"type" => "symbol", "value" => name}, rest}

  defp parse([:open | rest]) do
    with {:ok, items, rest} <- parse_items(rest, []) do
      {:ok, %{"type" => "list", "items" => items}, rest}
    end
  end

  defp parse([:close | _rest]), do: {:error, "unexpected )"}
  defp parse([]), do: {:error, "unexpected end of input"}

  defp parse_items([:close | rest], acc), do: {:ok, Enum.reverse(acc), rest}

  defp parse_items(tokens, acc) do
    case parse(tokens) do
      {:ok, node, rest} -> parse_items(rest, [node | acc])
      {:error, _} = error -> error
    end
  end
end
