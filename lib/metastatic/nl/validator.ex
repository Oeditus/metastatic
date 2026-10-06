defmodule Metastatic.NL.Validator do
  @moduledoc """
  Validator for NL-MetaAST trees.

  Verifies structural conformance, validates metadata conventions,
  and inspects linguistic layers (M2.1 Core, M2.2 Extended, M2.3 Native).
  """

  alias Metastatic.NL.AST

  @type mode :: :strict | :standard | :permissive

  @doc """
  Validates an NL-MetaAST tree or document.

  Options:
  - `:mode` - `:strict` (forbids native constructs), `:standard` (default), or `:permissive`
  - `:max_depth` - Maximum allowed tree depth (default: 50)
  """
  @spec validate(AST.nl_node(), keyword()) :: {:ok, map()} | {:error, term()}
  def validate(node, opts \\ []) do
    mode = Keyword.get(opts, :mode, :standard)
    max_depth = Keyword.get(opts, :max_depth, 50)

    if AST.conforms?(node) do
      metrics = analyze(node, 1)

      cond do
        metrics.depth > max_depth ->
          {:error, :max_depth_exceeded}

        mode == :strict and metrics.native_nodes > 0 ->
          {:error, :native_constructs_not_allowed}

        true ->
          {:ok, metrics}
      end
    else
      {:error, :invalid_structure}
    end
  end

  defp analyze({type, meta, children}, current_depth) do
    is_native = AST.native_type?(type)
    is_extended = AST.extended_type?(type)

    child_metrics =
      if is_list(children) do
        Enum.map(children, &analyze(&1, current_depth + 1))
      else
        []
      end

    total_nodes = 1 + Enum.sum(Enum.map(child_metrics, & &1.total_nodes))

    native_count =
      if(is_native, do: 1, else: 0) + Enum.sum(Enum.map(child_metrics, & &1.native_nodes))

    extended_count =
      if(is_extended, do: 1, else: 0) + Enum.sum(Enum.map(child_metrics, & &1.extended_nodes))

    sub_max_depth = Enum.reduce(child_metrics, current_depth, fn m, acc -> max(m.depth, acc) end)

    sentences =
      if(type == :sentence, do: 1, else: 0) + Enum.sum(Enum.map(child_metrics, & &1.sentences))

    clauses =
      if(type == :clause, do: 1, else: 0) + Enum.sum(Enum.map(child_metrics, & &1.clauses))

    tokens = if(type == :token, do: 1, else: 0) + Enum.sum(Enum.map(child_metrics, & &1.tokens))

    level =
      cond do
        native_count > 0 -> :native
        extended_count > 0 or Keyword.has_key?(meta, :sem_frame) -> :extended
        true -> :core
      end

    %{
      level: level,
      depth: sub_max_depth,
      total_nodes: total_nodes,
      native_nodes: native_count,
      extended_nodes: extended_count,
      sentences: sentences,
      clauses: clauses,
      tokens: tokens
    }
  end
end
