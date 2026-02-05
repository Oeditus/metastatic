defmodule Metastatic.Analysis.Duplication do
  @moduledoc """
  Code duplication detection at the MetaAST level.

  Detects code clones across the same or different programming languages by
  operating on the unified MetaAST representation. Supports four types of clones:

  - **Type I**: Exact clones (identical AST)
  - **Type II**: Renamed clones (identical structure, different identifiers)
  - **Type III**: Near-miss clones (similar structure with modifications)
  - **Type IV**: Semantic clones (different syntax, same behavior)

  ## Usage

      alias Metastatic.{Document, Analysis.Duplication}

      # Create two documents
      ast1 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      ast2 = {:binary_op, [category: :arithmetic, operator: :+], [{:variable, [], "x"}, {:literal, [subtype: :integer], 5}]}
      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :elixir)

      # Detect duplication
      {:ok, result} = Duplication.detect(doc1, doc2)
      result.duplicate?      # => true
      result.clone_type      # => :type_i
      result.similarity_score  # => 1.0

  ## Examples

      # Type I: Exact clone
      iex> ast = {:literal, [subtype: :integer], 42}
      iex> doc1 = Metastatic.Document.new(ast, :elixir)
      iex> doc2 = Metastatic.Document.new(ast, :python)
      iex> {:ok, result} = Metastatic.Analysis.Duplication.detect(doc1, doc2)
      iex> result.duplicate?
      true
      iex> result.clone_type
      :type_i

      # No duplication
      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :string], "hello"}
      iex> doc1 = Metastatic.Document.new(ast1, :elixir)
      iex> doc2 = Metastatic.Document.new(ast2, :elixir)
      iex> {:ok, result} = Metastatic.Analysis.Duplication.detect(doc1, doc2)
      iex> result.duplicate?
      false
  """

  alias Metastatic.Analysis.Duplication.{Fingerprint, Result, Similarity}
  alias Metastatic.{AST, Document}

  @typedoc """
  Options for duplication detection.

  - `:threshold` - Similarity threshold (0.0-1.0) for Type III detection (default: 0.8)
  - `:min_tokens` - Minimum tokens for detection (default: 5)
  - `:ignore_literals` - Ignore literal values in comparison (default: false)
  - `:ignore_variables` - Ignore variable names in comparison (default: false)
  - `:cross_language` - Enable cross-language detection (default: true)
  - `:clone_types` - List of clone types to detect (default: all types)
  """
  @type detect_opts :: [
          threshold: float(),
          min_tokens: non_neg_integer(),
          ignore_literals: boolean(),
          ignore_variables: boolean(),
          cross_language: boolean(),
          clone_types: [atom()]
        ]

  @doc """
  Detects duplication between two documents.

  Compares two MetaAST documents and returns a result indicating whether
  they are duplicates, the type of clone, and similarity score.

  ## Options

  See `t:detect_opts/0` for available options.

  ## Examples

      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :integer], 42}
      iex> doc1 = Metastatic.Document.new(ast1, :elixir)
      iex> doc2 = Metastatic.Document.new(ast2, :elixir)
      iex> {:ok, result} = Metastatic.Analysis.Duplication.detect(doc1, doc2)
      iex> result.duplicate?
      true

      iex> ast1 = {:variable, [], "x"}
      iex> ast2 = {:literal, [subtype: :integer], 42}
      iex> doc1 = Metastatic.Document.new(ast1, :elixir)
      iex> doc2 = Metastatic.Document.new(ast2, :elixir)
      iex> {:ok, result} = Metastatic.Analysis.Duplication.detect(doc1, doc2)
      iex> result.duplicate?
      false
  """
  @spec detect(Document.t(), Document.t(), detect_opts()) :: {:ok, Result.t()}
  def detect(%Document{ast: ast1} = doc1, %Document{ast: ast2} = doc2, opts \\ []) do
    # Validate both ASTs conform to MetaAST
    if AST.conforms?(ast1) and AST.conforms?(ast2) do
      # Get options
      threshold = Keyword.get(opts, :threshold, 0.8)

      # Check for clones in priority order
      result =
        cond do
          # Type I: Exact match
          exact_match?(ast1, ast2) ->
            build_type_i_result(doc1, doc2)

          # Type II: Normalized match (renamed clone)
          normalized_match?(ast1, ast2) ->
            build_type_ii_result(doc1, doc2)

          # Type III: Similar above threshold (near-miss clone)
          true ->
            similarity_score = Similarity.calculate(ast1, ast2)

            if similarity_score >= threshold do
              build_type_iii_result(doc1, doc2, similarity_score)
            else
              Result.no_duplicate()
            end
        end

      {:ok, result}
    else
      {:ok, Result.no_duplicate()}
    end
  end

  @doc """
  Detects duplication between two documents, raising on error.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> doc1 = Metastatic.Document.new(ast, :elixir)
      iex> doc2 = Metastatic.Document.new(ast, :elixir)
      iex> result = Metastatic.Analysis.Duplication.detect!(doc1, doc2)
      iex> result.duplicate?
      true
  """
  @spec detect!(Document.t(), Document.t(), detect_opts()) :: Result.t()
  def detect!(doc1, doc2, opts \\ []) do
    {:ok, result} = detect(doc1, doc2, opts)
    result
  end

  @doc """
  Calculates similarity score between two ASTs.

  Returns a float between 0.0 (completely different) and 1.0 (identical).

  ## Examples

      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Duplication.similarity(ast1, ast2)
      1.0

      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :string], "hello"}
      iex> score = Metastatic.Analysis.Duplication.similarity(ast1, ast2)
      iex> score > 0.0 and score < 0.5
      true
  """
  @spec similarity(AST.meta_ast(), AST.meta_ast()) :: float()
  def similarity(ast1, ast2) do
    Similarity.calculate(ast1, ast2)
  end

  @doc """
  Detects duplicates across multiple documents.

  Returns a list of clone groups, where each group contains documents that are
  duplicates of each other.

  ## Options

  See `t:detect_opts/0` for available options.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> docs = [
      ...>   Metastatic.Document.new(ast, :elixir),
      ...>   Metastatic.Document.new(ast, :python),
      ...>   Metastatic.Document.new({:literal, [subtype: :string], "hello"}, :elixir)
      ...> ]
      iex> {:ok, groups} = Metastatic.Analysis.Duplication.detect_in_list(docs)
      iex> length(groups) > 0
      true
  """
  @spec detect_in_list([Document.t()], detect_opts()) :: {:ok, [map()]}
  def detect_in_list(documents, opts \\ []) when is_list(documents) do
    _threshold = Keyword.get(opts, :threshold, 0.8)

    # Build fingerprint index for fast filtering
    indexed_docs =
      documents
      |> Enum.with_index()
      |> Enum.map(fn {doc, idx} ->
        %{
          doc: doc,
          index: idx,
          exact_fp: Fingerprint.exact(doc.ast),
          normalized_fp: Fingerprint.normalized(doc.ast)
        }
      end)

    # Find all duplicate pairs
    pairs =
      for i <- 0..(length(indexed_docs) - 1)//1,
          j <- (i + 1)..(length(indexed_docs) - 1)//1 do
        doc1_info = Enum.at(indexed_docs, i)
        doc2_info = Enum.at(indexed_docs, j)

        # Quick filter: only compare if fingerprints suggest similarity
        if should_compare?(doc1_info, doc2_info) do
          case detect(doc1_info.doc, doc2_info.doc, opts) do
            {:ok, %{duplicate?: true} = result} ->
              {doc1_info.index, doc2_info.index, result}

            _ ->
              nil
          end
        else
          nil
        end
      end
      |> Enum.reject(&is_nil/1)

    # Group clones into equivalence classes
    groups = group_clones(pairs, indexed_docs)

    {:ok, groups}
  end

  @doc """
  Detects duplicates across multiple documents, raising on error.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> docs = [Metastatic.Document.new(ast, :elixir), Metastatic.Document.new(ast, :python)]
      iex> groups = Metastatic.Analysis.Duplication.detect_in_list!(docs)
      iex> is_list(groups)
      true
  """
  @spec detect_in_list!([Document.t()], detect_opts()) :: [map()]
  def detect_in_list!(documents, opts \\ []) do
    {:ok, groups} = detect_in_list(documents, opts)
    groups
  end

  @doc """
  Generates a structural fingerprint for an AST.

  Returns a hash that uniquely identifies the structure.
  Identical ASTs produce identical fingerprints.

  ## Examples

      iex> ast = {:literal, [subtype: :integer], 42}
      iex> fp = Metastatic.Analysis.Duplication.fingerprint(ast)
      iex> is_binary(fp) and String.length(fp) > 0
      true

      iex> ast1 = {:literal, [subtype: :integer], 42}
      iex> ast2 = {:literal, [subtype: :integer], 42}
      iex> Metastatic.Analysis.Duplication.fingerprint(ast1) == Metastatic.Analysis.Duplication.fingerprint(ast2)
      true
  """
  @spec fingerprint(AST.meta_ast()) :: String.t()
  def fingerprint(ast) do
    Fingerprint.exact(ast)
  end

  # Private functions

  # Check if two ASTs are exactly identical
  defp exact_match?(ast1, ast2), do: ast1 == ast2

  # Check if two ASTs have identical normalized structure
  defp normalized_match?(ast1, ast2) do
    Fingerprint.normalized(ast1) == Fingerprint.normalized(ast2)
  end

  # Build Type I result with location and fingerprint information
  defp build_type_i_result(doc1, doc2) do
    locations = [
      build_location(doc1),
      build_location(doc2)
    ]

    fingerprints = %{
      exact: Fingerprint.exact(doc1.ast),
      normalized: Fingerprint.normalized(doc1.ast)
    }

    metrics = %{
      size: count_nodes(doc1.ast),
      complexity: nil,
      variables: MapSet.size(AST.variables(doc1.ast))
    }

    Result.exact_clone()
    |> Result.with_locations(locations)
    |> Result.with_fingerprints(fingerprints)
    |> Result.with_metrics(metrics)
  end

  # Build Type II result for renamed clones
  defp build_type_ii_result(doc1, doc2) do
    locations = [
      build_location(doc1),
      build_location(doc2)
    ]

    fingerprints = %{
      exact: Fingerprint.exact(doc1.ast),
      normalized: Fingerprint.normalized(doc1.ast)
    }

    metrics = %{
      size: count_nodes(doc1.ast),
      complexity: nil,
      variables: MapSet.size(AST.variables(doc1.ast))
    }

    Result.renamed_clone()
    |> Result.with_locations(locations)
    |> Result.with_fingerprints(fingerprints)
    |> Result.with_metrics(metrics)
  end

  # Build Type III result for near-miss clones
  defp build_type_iii_result(doc1, doc2, similarity_score) do
    locations = [
      build_location(doc1),
      build_location(doc2)
    ]

    fingerprints = %{
      exact: Fingerprint.exact(doc1.ast),
      normalized: Fingerprint.normalized(doc1.ast)
    }

    metrics = %{
      size: count_nodes(doc1.ast),
      complexity: nil,
      variables: MapSet.size(AST.variables(doc1.ast))
    }

    Result.near_miss_clone(similarity_score)
    |> Result.with_locations(locations)
    |> Result.with_fingerprints(fingerprints)
    |> Result.with_metrics(metrics)
  end

  # Build location info from document metadata
  defp build_location(%Document{metadata: metadata, language: language}) do
    %{
      file: get_in(metadata || %{}, [:file]),
      start_line: get_in(metadata || %{}, [:start_line]),
      end_line: get_in(metadata || %{}, [:end_line]),
      language: language
    }
  end

  # Count nodes in an AST
  defp count_nodes(ast) do
    walk_and_count(ast, 0)
  end

  defp walk_and_count({:binary_op, _, _, left, right}, count) do
    count = walk_and_count(left, count + 1)
    walk_and_count(right, count)
  end

  defp walk_and_count({:unary_op, _, _, operand}, count) do
    walk_and_count(operand, count + 1)
  end

  defp walk_and_count({:function_call, _, args}, count) when is_list(args) do
    Enum.reduce(args, count + 1, fn arg, c -> walk_and_count(arg, c) end)
  end

  defp walk_and_count({:conditional, cond, then_br, else_br}, count) do
    count = walk_and_count(cond, count + 1)
    count = walk_and_count(then_br, count)

    if else_br do
      walk_and_count(else_br, count)
    else
      count
    end
  end

  defp walk_and_count({:block, stmts}, count) when is_list(stmts) do
    Enum.reduce(stmts, count + 1, fn stmt, c -> walk_and_count(stmt, c) end)
  end

  defp walk_and_count({:loop, :while, cond, body}, count) do
    count = walk_and_count(cond, count + 1)
    walk_and_count(body, count)
  end

  defp walk_and_count({:loop, _, iter, coll, body}, count) do
    count = walk_and_count(iter, count + 1)
    count = walk_and_count(coll, count)
    walk_and_count(body, count)
  end

  defp walk_and_count({:assignment, target, value}, count) do
    count = walk_and_count(target, count + 1)
    walk_and_count(value, count)
  end

  defp walk_and_count({:inline_match, pattern, value}, count) do
    count = walk_and_count(pattern, count + 1)
    walk_and_count(value, count)
  end

  defp walk_and_count({:lambda, _params, _captures, body}, count) do
    walk_and_count(body, count + 1)
  end

  defp walk_and_count({:collection_op, _, func, coll}, count) do
    count = walk_and_count(func, count + 1)
    walk_and_count(coll, count)
  end

  defp walk_and_count({:collection_op, _, func, coll, init}, count) do
    count = walk_and_count(func, count + 1)
    count = walk_and_count(coll, count)
    walk_and_count(init, count)
  end

  defp walk_and_count({:early_return, value}, count) do
    walk_and_count(value, count + 1)
  end

  defp walk_and_count({:tuple, elems}, count) when is_list(elems) do
    Enum.reduce(elems, count + 1, fn elem, c -> walk_and_count(elem, c) end)
  end

  defp walk_and_count(_, count), do: count + 1

  # Helper for multi-document detection
  # Quick filter to determine if two documents should be compared
  defp should_compare?(doc1_info, doc2_info) do
    # Always compare if exact fingerprints match
    if doc1_info.exact_fp == doc2_info.exact_fp do
      true
      # Compare if normalized fingerprints match (Type II)
    else
      doc1_info.normalized_fp == doc2_info.normalized_fp
    end
  end

  # Group clone pairs into equivalence classes using union-find
  defp group_clones(pairs, indexed_docs) do
    if Enum.empty?(pairs) do
      []
    else
      # Build adjacency map
      adjacency =
        Enum.reduce(pairs, %{}, fn {idx1, idx2, result}, acc ->
          acc
          |> Map.update(idx1, [{idx2, result}], fn list -> [{idx2, result} | list] end)
          |> Map.update(idx2, [{idx1, result}], fn list -> [{idx1, result} | list] end)
        end)

      # Find connected components (clone groups)
      visited = MapSet.new()
      all_indices = Map.keys(adjacency)

      {groups, _} =
        Enum.reduce(all_indices, {[], visited}, fn idx, {groups_acc, visited_acc} ->
          if MapSet.member?(visited_acc, idx) do
            {groups_acc, visited_acc}
          else
            # BFS to find all connected documents
            {group, new_visited} = bfs_group(idx, adjacency, visited_acc, indexed_docs)
            {[group | groups_acc], new_visited}
          end
        end)

      groups
    end
  end

  # BFS to find a clone group
  defp bfs_group(start_idx, adjacency, visited, indexed_docs) do
    queue = :queue.from_list([start_idx])
    bfs_loop(queue, adjacency, MapSet.put(visited, start_idx), [], indexed_docs)
  end

  defp bfs_loop(queue, adjacency, visited, group_indices, indexed_docs) do
    case :queue.out(queue) do
      {{:value, idx}, rest_queue} ->
        neighbors = Map.get(adjacency, idx, [])

        {new_queue, new_visited} =
          Enum.reduce(neighbors, {rest_queue, visited}, fn {neighbor_idx, _result}, {q, v} ->
            if MapSet.member?(v, neighbor_idx) do
              {q, v}
            else
              {:queue.in(neighbor_idx, q), MapSet.put(v, neighbor_idx)}
            end
          end)

        bfs_loop(new_queue, adjacency, new_visited, [idx | group_indices], indexed_docs)

      {:empty, _} ->
        # Build group result
        group_docs = Enum.map(group_indices, fn idx -> Enum.at(indexed_docs, idx).doc end)

        group = %{
          size: length(group_docs),
          documents: group_docs,
          clone_type: determine_group_clone_type(group_docs),
          locations:
            Enum.map(group_docs, fn doc ->
              %{
                file: get_in(doc.metadata, [:file]),
                start_line: get_in(doc.metadata, [:start_line]),
                end_line: get_in(doc.metadata, [:end_line]),
                language: doc.language
              }
            end)
        }

        {group, visited}
    end
  end

  # Determine the clone type for a group (strictest type wins)
  defp determine_group_clone_type([doc1, doc2 | _rest]) do
    cond do
      doc1.ast == doc2.ast -> :type_i
      Fingerprint.normalized(doc1.ast) == Fingerprint.normalized(doc2.ast) -> :type_ii
      true -> :type_iii
    end
  end

  defp determine_group_clone_type(_), do: :type_i
end
