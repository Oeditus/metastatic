defmodule Metastatic.Adapters.JavaScript.ToMeta do
  @moduledoc """
  Regex-based source-to-MetaAST conversion for JavaScript and TypeScript.

  Performs single-pass line-by-line scanning to extract structural information
  from JS/TS source code, producing a proper MetaAST tree wrapped in a
  `:container` node for the file module.

  ## Extraction Strategy

  Each line is scanned in priority order:
  1. Import statements (`import ... from` and `require(...)`)
  2. Class declarations (ES6 `class`)
  3. Function declarations, arrow functions, and class methods
  4. Function call expressions

  ## TypeScript Handling

  TypeScript type annotations are stripped before parameter counting:
  - Generic type parameters: `<T, U extends Foo>`
  - Parameter type annotations: `name: Type`, `name?: Type`
  """

  # ---------------------------------------------------------------------------
  # Regex Patterns
  # ---------------------------------------------------------------------------

  @import_es6 ~r/^\s*import\s+.*\s+from\s+['"]([^'"]+)['"]/
  @import_require ~r/require\s*\(\s*['"]([^'"]+)['"]\s*\)/

  @class_decl ~r/^\s*(?:export\s+)?class\s+(\w+)/

  @function_decl ~r/^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(([^)]*)\)/
  @arrow_function ~r/^\s*(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\(([^)]*)\)(?::\s*\S+)?\s*=>/
  @method_decl ~r/^\s*(?:async\s+)?(\w+)\s*\(([^)]*)\)\s*\{/

  @call_expr ~r/(\w+)(?:\.(\w+))?\s*\(/

  @ts_generics ~r/<[^>]*>/
  @ts_type_annotations ~r/\??:\s*[^,)]+/

  # Keywords that look like function calls but aren't
  @control_keywords ~w(if for while switch catch return function constructor)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Parse JavaScript/TypeScript source into a MetaAST tree.

  Returns `{:ok, meta_ast}` where meta_ast is a `:container` node representing
  the file module, wrapping all extracted declarations.
  """
  @spec parse(String.t()) :: {:ok, tuple()} | {:error, term()}
  def parse(source) when is_binary(source) do
    {:ok, build_meta_ast(source)}
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  # ---------------------------------------------------------------------------
  # Core MetaAST Construction
  # ---------------------------------------------------------------------------

  defp build_meta_ast(source) do
    lines = String.split(source, "\n")

    state = %{
      containers: [],
      functions: [],
      calls: [],
      imports: [],
      current_container: nil,
      line_num: 1
    }

    state =
      Enum.reduce(lines, state, fn line, s ->
        s
        |> scan_import(line)
        |> scan_class(line)
        |> scan_function(line)
        |> scan_calls(line)
        |> Map.update!(:line_num, &(&1 + 1))
      end)

    # Build a top-level container that wraps everything (the "file module")
    children =
      Enum.reverse(state.imports) ++ Enum.reverse(state.functions) ++ Enum.reverse(state.calls)

    file_module =
      {:container, [name: state.current_container || "file", container_type: :module, line: 1],
       children}

    # If there are class containers, return them alongside the file module
    case state.containers do
      [] ->
        file_module

      containers ->
        {:container, [name: "file", container_type: :module, line: 1],
         [file_module | Enum.reverse(containers)]}
    end
  end

  # ---------------------------------------------------------------------------
  # Import Scanning
  # ---------------------------------------------------------------------------

  defp scan_import(state, line) do
    cond do
      m = Regex.run(@import_es6, line) ->
        [_, source] = m

        node =
          {:import,
           [source: sanitize_module(source), import_type: :es6_import, line: state.line_num], []}

        Map.update!(state, :imports, &[node | &1])

      m = Regex.run(@import_require, line) ->
        [_, source] = m

        node =
          {:import,
           [source: sanitize_module(source), import_type: :require, line: state.line_num], []}

        Map.update!(state, :imports, &[node | &1])

      true ->
        state
    end
  end

  # ---------------------------------------------------------------------------
  # Class/Container Scanning
  # ---------------------------------------------------------------------------

  defp scan_class(state, line) do
    case Regex.run(@class_decl, line) do
      [_, class_name] ->
        node =
          {:container, [name: class_name, container_type: :class, line: state.line_num], []}

        state
        |> Map.update!(:containers, &[node | &1])
        |> Map.put(:current_container, class_name)

      nil ->
        state
    end
  end

  # ---------------------------------------------------------------------------
  # Function Scanning
  # ---------------------------------------------------------------------------

  defp scan_function(state, line) do
    cond do
      # function declaration: [export] [async] function name(params)
      m = Regex.run(@function_decl, line) ->
        [_, name, params] = m
        add_function(state, name, params, :public)

      # arrow function: [export] const/let/var name = [async] (params) =>
      m = Regex.run(@arrow_function, line) ->
        [_, name, params] = m
        add_function(state, name, params, :public)

      # class / object method: [async] name(params) {
      m = Regex.run(@method_decl, line) ->
        [_, name, params] = m

        if name in @control_keywords do
          state
        else
          vis = if String.starts_with?(name, "_"), do: :private, else: :public
          add_function(state, name, params, vis)
        end

      true ->
        state
    end
  end

  defp add_function(state, name, params_str, visibility) do
    param_nodes = build_param_nodes(params_str)

    node =
      {:function_def,
       [name: name, params: param_nodes, visibility: visibility, line: state.line_num], []}

    Map.update!(state, :functions, &[node | &1])
  end

  # ---------------------------------------------------------------------------
  # Call Scanning
  # ---------------------------------------------------------------------------

  defp scan_calls(state, line) do
    calls =
      @call_expr
      |> Regex.scan(line)
      |> Enum.reduce(state.calls, fn match, acc ->
        case match do
          [_, obj, method]
          when method != "" and method not in @control_keywords ->
            node =
              {:function_call, [name: "#{obj}.#{method}", line: state.line_num], []}

            [node | acc]

          [_, func | _] when func not in @control_keywords ->
            node =
              {:function_call, [name: func, line: state.line_num], []}

            [node | acc]

          _ ->
            acc
        end
      end)

    %{state | calls: calls}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_param_nodes(params_str) do
    params_str
    |> strip_ts_types()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn name ->
      clean =
        name
        |> String.replace(~r/=.+$/, "")
        |> String.replace("...", "")
        |> String.trim()

      {:param, [], clean}
    end)
  end

  defp strip_ts_types(str) do
    str
    |> String.replace(@ts_generics, "")
    |> String.replace(@ts_type_annotations, "")
  end

  defp sanitize_module(path) do
    path
    |> String.replace(~r/^[@.\/]+/, "")
    |> String.replace("/", ".")
  end
end
