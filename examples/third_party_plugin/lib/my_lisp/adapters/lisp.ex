defmodule MyLisp.Adapters.Lisp do
  @moduledoc """
  A third-party Metastatic language adapter for a small Lisp dialect.

  This module lives in the host application, not in Metastatic. It uses
  `Metastatic.Adapter.Plugin` for the descriptor boilerplate and implements the
  four transformation callbacks.

  ## M1 → M2 mapping

  | Lisp (M1) | MetaAST (M2) |
  | :--- | :--- |
  | `42` | `{:literal, [subtype: :integer], 42}` |
  | `foo` | `{:variable, [], "foo"}` |
  | `(+ a b)` | `{:binary_op, [category: :arithmetic, operator: :+], [a, b]}` |
  | `(f a b)` | `{:function_call, [name: "f"], [a, b]}` |
  | `(if c t e)` | `{:conditional, [], [c, t, e]}` |

  Mapping to the *portable* core nodes (rather than `:language_specific`) is
  what lets a Lisp expression be reified as Python or Elixir.
  """

  use Metastatic.Adapter.Plugin,
    language: :lisp,
    extensions: [".lisp", ".lsp"],
    experimental?: true

  alias MyLisp.Reader

  @arithmetic %{
    "+" => :+,
    "-" => :-,
    "*" => :*,
    "/" => :/
  }

  @comparison %{
    "=" => :==,
    "<" => :<,
    ">" => :>,
    "<=" => :<=,
    ">=" => :>=
  }

  # ----- Adapter callbacks -----

  @impl true
  def parse(source) when is_binary(source), do: Reader.read(source)

  @impl true
  def to_meta(native_ast) do
    native_ast
    |> to_meta_node()
    |> Metastatic.Adapter.enrich(:lisp)
  end

  @impl true
  def from_meta(meta_ast, _metadata), do: from_meta_node(meta_ast)

  @impl true
  def unparse(native_ast) when is_map(native_ast), do: {:ok, render(native_ast)}

  # ----- M1 → M2 -----

  defp to_meta_node(%{"type" => "int", "value" => value}) do
    {:ok, {:literal, [subtype: :integer], value}, %{}}
  end

  defp to_meta_node(%{"type" => "symbol", "value" => name}) do
    {:ok, {:variable, [], name}, %{}}
  end

  defp to_meta_node(%{"type" => "list", "items" => [head | args]}) do
    case head do
      %{"type" => "symbol", "value" => op} when is_map_key(@arithmetic, op) ->
        binary(Map.fetch!(@arithmetic, op), :arithmetic, args)

      %{"type" => "symbol", "value" => op} when is_map_key(@comparison, op) ->
        binary(Map.fetch!(@comparison, op), :comparison, args)

      %{"type" => "symbol", "value" => "if"} ->
        conditional(args)

      %{"type" => "symbol", "value" => name} ->
        with {:ok, metas, metadata} <- map_args(args) do
          {:ok, {:function_call, [name: name], metas}, metadata}
        end

      _other ->
        {:error, "list must start with a symbol"}
    end
  end

  defp to_meta_node(%{"type" => "list", "items" => []}) do
    {:ok, {:list, [], []}, %{}}
  end

  defp to_meta_node(other), do: {:error, "unsupported node: #{inspect(other)}"}

  defp binary(operator, category, [left, right]) do
    with {:ok, left_meta, m1} <- to_meta_node(left),
         {:ok, right_meta, m2} <- to_meta_node(right) do
      {:ok, {:binary_op, [category: category, operator: operator], [left_meta, right_meta]},
       Map.merge(m1, m2)}
    end
  end

  defp binary(_operator, _category, args) do
    {:error, "expected 2 arguments, got #{length(args)}"}
  end

  defp conditional([condition, then_branch, else_branch]) do
    with {:ok, c, m1} <- to_meta_node(condition),
         {:ok, t, m2} <- to_meta_node(then_branch),
         {:ok, e, m3} <- to_meta_node(else_branch) do
      {:ok, {:conditional, [], [c, t, e]}, Map.merge(m1, Map.merge(m2, m3))}
    end
  end

  defp conditional(args), do: {:error, "if expects 3 arguments, got #{length(args)}"}

  defp map_args(args) do
    args
    |> Enum.reduce_while({:ok, [], %{}}, fn arg, {:ok, acc, meta} ->
      case to_meta_node(arg) do
        {:ok, node, node_meta} -> {:cont, {:ok, [node | acc], Map.merge(meta, node_meta)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, nodes, meta} -> {:ok, Enum.reverse(nodes), meta}
      {:error, _} = error -> error
    end
  end

  # ----- M2 → M1 -----

  defp from_meta_node({:literal, [subtype: :integer], value}), do: {:ok, int(value)}
  defp from_meta_node({:variable, _meta, name}), do: {:ok, symbol(name)}

  defp from_meta_node({:binary_op, meta, [left, right]}) do
    with {:ok, l} <- from_meta_node(left),
         {:ok, r} <- from_meta_node(right) do
      {:ok, list([symbol(operator_name(Keyword.get(meta, :operator))), l, r])}
    end
  end

  defp from_meta_node({:function_call, meta, args}) do
    with {:ok, rendered} <- render_all(args) do
      {:ok, list([symbol(Keyword.get(meta, :name, "fn")) | rendered])}
    end
  end

  defp from_meta_node({:conditional, _meta, [c, t, e]}) do
    with {:ok, rc} <- from_meta_node(c),
         {:ok, rt} <- from_meta_node(t),
         {:ok, re} <- from_meta_node(e) do
      {:ok, list([symbol("if"), rc, rt, re])}
    end
  end

  defp from_meta_node(other), do: {:error, "cannot reify #{inspect(other)} as Lisp"}

  defp render_all(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, acc} ->
      case from_meta_node(node) do
        {:ok, rendered} -> {:cont, {:ok, [rendered | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, rendered} -> {:ok, Enum.reverse(rendered)}
      {:error, _} = error -> error
    end
  end

  defp int(value), do: %{"type" => "int", "value" => value}
  defp symbol(name), do: %{"type" => "symbol", "value" => to_string(name)}
  defp list(items), do: %{"type" => "list", "items" => items}

  defp operator_name(nil), do: "?"
  defp operator_name(operator), do: Atom.to_string(operator)

  # ----- M1 → Source -----

  defp render(%{"type" => "int", "value" => value}), do: Integer.to_string(value)
  defp render(%{"type" => "symbol", "value" => name}), do: name
  defp render(%{"type" => "list", "items" => items}), do: "(" <> Enum.map_join(items, " ", &render/1) <> ")"
end
