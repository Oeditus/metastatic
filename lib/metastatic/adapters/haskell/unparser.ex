defmodule Metastatic.Adapters.Haskell.Unparser do
  @moduledoc """
  Unparses Haskell AST (M1) back to Haskell source code.
  """

  @doc """
  Unparses a Haskell AST map into Haskell source code string.
  """
  @spec unparse(map()) :: {:ok, String.t()} | {:error, String.t()}
  def unparse(ast) when is_map(ast) do
    {:ok, to_source(ast)}
  rescue
    e -> {:error, "Failed to unparse Haskell AST: #{Exception.message(e)}"}
  end

  def unparse(other) do
    {:error, "Invalid Haskell AST: #{inspect(other)}"}
  end

  def to_source(%{"type" => "literal", "value" => val}) do
    case val do
      %{"literalType" => "int", "value" => v} -> to_string(v)
      %{"literalType" => "float", "value" => v} -> to_string(v)
      %{"literalType" => "string", "value" => v} -> Jason.encode!(v)
      %{"literalType" => "char", "value" => v} -> "'#{v}'"
      %{"literalType" => "bool", "value" => true} -> "True"
      %{"literalType" => "bool", "value" => false} -> "False"
      %{"literalType" => "unit"} -> "()"
      v when is_integer(v) or is_float(v) -> to_string(v)
      v when is_binary(v) -> Jason.encode!(v)
      v when is_boolean(v) -> if v, do: "True", else: "False"
      nil -> "()"
    end
  end

  def to_source(%{"type" => "var", "name" => name}), do: name
  def to_source(%{"type" => "con", "name" => name}), do: name

  def to_source(%{"type" => "infix", "left" => left, "operator" => op, "right" => right}) do
    "#{to_sub_source(left)} #{op} #{to_sub_source(right)}"
  end

  def to_source(%{"type" => "prefix", "operator" => op, "expression" => expr}) do
    "#{op}#{to_sub_source(expr)}"
  end

  def to_source(%{"type" => "negate", "expression" => expr}) do
    "-#{to_sub_source(expr)}"
  end

  def to_source(%{"type" => "paren", "expression" => expr}) do
    "(#{to_source(expr)})"
  end

  def to_source(%{"type" => "tuple", "elements" => elems}) do
    "(" <> Enum.map_join(elems, ", ", &to_source/1) <> ")"
  end

  def to_source(%{"type" => "list", "elements" => elems}) do
    "[" <> Enum.map_join(elems, ", ", &to_source/1) <> "]"
  end

  def to_source(%{"type" => "lambda", "patterns" => pats, "body" => body}) do
    pats_str = Enum.map_join(pats, " ", &to_pattern/1)
    "\\#{pats_str} -> #{to_source(body)}"
  end

  def to_source(%{"type" => "if", "condition" => c, "then" => t, "else" => e}) do
    "if #{to_source(c)} then #{to_source(t)} else #{to_source(e)}"
  end

  def to_source(%{"type" => "app", "function" => func, "argument" => arg}) do
    "#{to_source(func)} #{to_sub_source(arg)}"
  end

  def to_source(%{"type" => "let", "bindings" => binds, "body" => body}) do
    binds_str = Enum.map_join(binds, "; ", &to_binding/1)
    "let #{binds_str} in #{to_source(body)}"
  end

  def to_source(%{"type" => "case", "scrutinee" => s, "alternatives" => alts}) do
    alts_str =
      Enum.map_join(alts, "\n", fn
        %{"pattern" => p, "rhs" => rhs} -> "  #{to_pattern(p)} -> #{to_source(rhs)}"
      end)

    "case #{to_source(s)} of\n#{alts_str}"
  end

  def to_source(%{"type" => "pat_bind", "pattern" => pat, "rhs" => rhs}) do
    "#{to_pattern(pat)} = #{to_source(rhs)}"
  end

  def to_source(%{"type" => "fun_bind", "matches" => matches}) do
    Enum.map_join(matches, "\n", &to_match/1)
  end

  def to_source(%{"type" => "type_sig", "names" => names, "signature" => sig}) do
    names_str = Enum.map_join(names, ", ", &to_name/1)
    "#{names_str} :: #{to_type(sig)}"
  end

  def to_source(%{"type" => "module", "name" => name, "declarations" => decls}) do
    "module #{name} where\n\n" <> Enum.map_join(decls, "\n\n", &to_source/1)
  end

  def to_source(%{"type" => "module", "declarations" => decls}) do
    Enum.map_join(decls, "\n\n", &to_source/1)
  end

  def to_source(other) when is_map(other) do
    inspect(other)
  end

  defp to_sub_source(%{"type" => "infix"} = node), do: "(#{to_source(node)})"
  defp to_sub_source(%{"type" => "app"} = node), do: "(#{to_source(node)})"
  defp to_sub_source(%{"type" => "lambda"} = node), do: "(#{to_source(node)})"
  defp to_sub_source(%{"type" => "if"} = node), do: "(#{to_source(node)})"
  defp to_sub_source(%{"type" => "let"} = node), do: "(#{to_source(node)})"
  defp to_sub_source(node), do: to_source(node)

  defp to_pattern(%{"type" => "var_pat", "name" => name}), do: name

  defp to_pattern(%{"type" => "lit_pat", "value" => val}),
    do: to_source(%{"type" => "literal", "value" => val})

  defp to_pattern(%{"type" => "wildcard"}), do: "_"

  defp to_pattern(%{"type" => "con_pat", "name" => name, "patterns" => args}) do
    if args == [] do
      name
    else
      "#{name} " <> Enum.map_join(args, " ", &to_pattern/1)
    end
  end

  defp to_pattern(%{"type" => "tuple_pat", "elements" => elems}) do
    "(" <> Enum.map_join(elems, ", ", &to_pattern/1) <> ")"
  end

  defp to_pattern(%{"type" => "list_pat", "elements" => elems}) do
    "[" <> Enum.map_join(elems, ", ", &to_pattern/1) <> "]"
  end

  defp to_pattern(name) when is_binary(name), do: name
  defp to_pattern(other), do: inspect(other)

  defp to_binding(%{"type" => "pat_bind", "pattern" => p, "rhs" => rhs}) do
    "#{to_pattern(p)} = #{to_source(rhs)}"
  end

  defp to_binding(%{"type" => "fun_bind", "matches" => matches}) do
    Enum.map_join(matches, "; ", &to_match/1)
  end

  defp to_binding(other), do: to_source(other)

  defp to_match(%{"name" => name, "patterns" => pats, "rhs" => rhs}) do
    pats_str = if pats == [], do: "", else: " " <> Enum.map_join(pats, " ", &to_pattern/1)
    "#{name}#{pats_str} = #{to_source(rhs)}"
  end

  defp to_name(name) when is_binary(name), do: name
  defp to_name(%{"name" => name}), do: name
  defp to_name(other), do: inspect(other)

  defp to_type(sig) when is_binary(sig), do: sig
  defp to_type(%{"type" => "type_con", "name" => name}), do: name
  defp to_type(%{"type" => "type_var", "name" => name}), do: name

  defp to_type(%{"type" => "type_fun", "from" => from, "to" => to}) do
    "#{to_type(from)} -> #{to_type(to)}"
  end

  defp to_type(other), do: inspect(other)
end
