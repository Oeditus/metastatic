defmodule Metastatic.Adapters.Agda.Unparser do
  @moduledoc """
  Unparses Agda AST (M1) back to Agda source code.
  """

  @doc """
  Unparses an Agda AST map into Agda source code string.
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) when is_map(ast) do
    {:ok, to_source(ast)}
  rescue
    e -> {:error, "Failed to unparse Agda AST: #{Exception.message(e)}"}
  end

  def unparse(other) do
    {:error, "Invalid Agda AST: #{inspect(other)}"}
  end

  def to_source(%{"type" => "literal", "value" => val}) do
    case val do
      %{"literalType" => "int", "value" => v} -> to_string(v)
      %{"literalType" => "float", "value" => v} -> to_string(v)
      %{"literalType" => "string", "value" => v} -> Jason.encode!(v)
      %{"literalType" => "char", "value" => v} -> "'#{v}'"
      v when is_integer(v) or is_float(v) -> to_string(v)
      v when is_binary(v) -> Jason.encode!(v)
      _ -> inspect(val)
    end
  end

  def to_source(%{"type" => "var", "name" => name}), do: name

  def to_source(%{"type" => "infix", "operator" => op, "left" => left, "right" => right}) do
    "#{to_sub_source(left)} #{op} #{to_sub_source(right)}"
  end

  def to_source(%{"type" => "app", "function" => func, "argument" => arg}) do
    "#{to_source(func)} #{to_sub_source(arg)}"
  end

  def to_source(%{"type" => "raw_app", "elements" => elems}) do
    Enum.map_join(elems, " ", &to_sub_source/1)
  end

  def to_source(%{"type" => "lambda", "parameters" => params, "body" => body}) do
    params_str =
      Enum.map_join(params, " ", fn
        %{"name" => name, "implicit" => true} -> "{#{name}}"
        %{"name" => name} -> name
        p when is_binary(p) -> p
        other -> inspect(other)
      end)

    "\\ #{params_str} -> #{to_source(body)}"
  end

  def to_source(%{"type" => "arrow", "from" => from, "to" => to}) do
    "#{to_sub_source(from)} -> #{to_source(to)}"
  end

  def to_source(%{"type" => "type_sig", "name" => name, "signature" => sig}) do
    "#{name} : #{to_source(sig)}"
  end

  def to_source(%{"type" => "field_sig", "name" => name, "signature" => sig}) do
    "#{name} : #{to_source(sig)}"
  end

  def to_source(%{"type" => "fun_clause", "lhs" => lhs, "rhs" => rhs}) do
    lhs_str = to_pattern(lhs)
    rhs_str = to_rhs(rhs)
    "#{lhs_str} = #{rhs_str}"
  end

  def to_source(%{"type" => "data", "name" => name, "typeExpr" => type_expr, "constructors" => ctors}) do
    type_str = to_source(type_expr)

    ctors_str =
      Enum.map_join(ctors, "\n  ", &to_source/1)

    if ctors == [] do
      "data #{name} : #{type_str} where"
    else
      "data #{name} : #{type_str} where\n  #{ctors_str}"
    end
  end

  def to_source(%{"type" => "record", "name" => name, "typeExpr" => type_expr, "fields" => fields}) do
    type_str = to_source(type_expr)
    fields_str = Enum.map_join(fields, "\n    ", &to_source/1)
    "record #{name} : #{type_str} where\n  field\n    #{fields_str}"
  end

  def to_source(%{"type" => "module", "name" => nil, "declarations" => decls}) do
    Enum.map_join(decls, "\n\n", &to_source/1)
  end

  def to_source(%{"type" => "module", "name" => name, "declarations" => decls}) do
    decls_str =
      decls
      |> Enum.map(&to_source/1)
      |> Enum.map(fn d -> "  " <> String.replace(d, "\n", "\n  ") end)
      |> Enum.join("\n\n")

    "module #{name} where\n\n#{decls_str}"
  end

  def to_source(%{"type" => "open", "module" => mod}) do
    "open #{mod}"
  end

  def to_source(%{"type" => "import", "module" => mod, "open" => true}) do
    "open import #{mod}"
  end

  def to_source(%{"type" => "import", "module" => mod, "open" => false}) do
    "import #{mod}"
  end

  def to_source(%{"type" => "postulate", "declarations" => decls}) do
    decls_str =
      decls
      |> Enum.map(&to_source/1)
      |> Enum.map(fn d -> "  " <> String.replace(d, "\n", "\n  ") end)
      |> Enum.join("\n")

    "postulate\n#{decls_str}"
  end

  def to_source(%{"type" => "infix_decl", "fixity" => fixity, "names" => names}) do
    names_str = Enum.join(names, " ")
    "#{fixity} #{names_str}"
  end

  def to_source(%{"type" => "other_expr", "text" => text}), do: text
  def to_source(%{"type" => "other_decl", "text" => text}), do: text

  def to_source(other) when is_map(other), do: inspect(other)

  defp to_sub_source(%{"type" => "infix"} = node), do: "(#{to_source(node)})"
  defp to_sub_source(%{"type" => "app"} = node), do: "(#{to_source(node)})"
  defp to_sub_source(%{"type" => "raw_app"} = node), do: "(#{to_source(node)})"
  defp to_sub_source(%{"type" => "arrow"} = node), do: "(#{to_source(node)})"
  defp to_sub_source(node), do: to_source(node)

  defp to_rhs(%{"type" => "rhs", "expression" => expr}), do: to_source(expr)
  defp to_rhs(%{"type" => "absurd_rhs"}), do: "()"
  defp to_rhs(other), do: to_source(other)

  defp to_pattern(%{"type" => "var_pat", "name" => name}), do: name
  defp to_pattern(%{"type" => "lit_pat", "value" => val}), do: to_source(%{"type" => "literal", "value" => val})
  defp to_pattern(%{"type" => "wildcard"}), do: "_"
  defp to_pattern(%{"type" => "infix_pat", "operator" => op, "left" => left, "right" => right}) do
    "#{to_pattern(left)} #{op} #{to_pattern(right)}"
  end
  defp to_pattern(%{"type" => "app_pat", "elements" => elems}) do
    Enum.map_join(elems, " ", &to_pattern/1)
  end
  defp to_pattern(other), do: to_source(other)
end
