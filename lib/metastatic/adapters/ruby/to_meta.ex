defmodule Metastatic.Adapters.Ruby.ToMeta do
  @moduledoc """
  Transform Ruby AST (M1) to MetaAST (M2).

  This module implements the abstraction function α_Ruby that lifts
  Ruby-specific AST structures to the meta-level representation.

  ## Transformation Strategy

  The transformation follows a pattern-matching approach, handling each
  Ruby AST construct (from parser gem) and mapping it to the appropriate MetaAST node type.

  ### M2.1 (Core Layer)

  - Literals: integers, floats, strings, booleans, nil, symbols
  - Variables: local, instance, class, global
  - Binary operators: arithmetic, comparison, boolean
  - Unary operators: negation, logical not
  - Method calls
  - Conditionals: if/elsif/else, unless, ternary
  - Blocks: sequential expressions
  - Assignment: local variable assignment

  ### M2.2 (Extended Layer)

  - Loops: while, until, for
  - Iterators: each, map, select, reduce
  - Blocks & Procs: blocks, lambdas, procs
  - Pattern matching: case/when (classic), case/in (Ruby 3+)
  - Exception handling: begin/rescue/ensure

  ### M2.3 (Native Layer)

  - Class definitions
  - Module definitions
  - Method definitions
  - String interpolation
  - Regular expressions
  - Metaprogramming constructs
  """

  @doc """
  Transform Ruby AST to MetaAST.

  Returns `{:ok, meta_ast, metadata}` on success or `{:error, reason}` on failure.

  ## New 3-Tuple Format

  All MetaAST nodes are uniform 3-element tuples:

      {type_atom, keyword_meta, children_or_value}

  ## Examples

      iex> transform(%{"type" => "int", "children" => [42]})
      {:ok, {:literal, [subtype: :integer], 42}, %{}}

      iex> transform(%{"type" => "lvar", "children" => ["x"]})
      {:ok, {:variable, [], "x"}, %{}}
  """
  @spec transform(term()) :: {:ok, term(), map()} | {:error, String.t()}

  # Literals - M2.1 Core Layer

  # Integer literal
  def transform(%{"type" => "int", "children" => [value]} = ast) when is_integer(value) do
    {:ok, add_location({:literal, [subtype: :integer], value}, ast), %{}}
  end

  # Float literal
  def transform(%{"type" => "float", "children" => [value]} = ast) when is_float(value) do
    {:ok, add_location({:literal, [subtype: :float], value}, ast), %{}}
  end

  # String literal
  def transform(%{"type" => "str", "children" => [value]} = ast) when is_binary(value) do
    {:ok, add_location({:literal, [subtype: :string], value}, ast), %{}}
  end

  # Symbol literal
  def transform(%{"type" => "sym", "children" => [value]})
      when is_atom(value) or is_binary(value) do
    symbol = if is_binary(value), do: String.to_atom(value), else: value
    {:ok, {:literal, [subtype: :symbol], symbol}, %{}}
  end

  # Boolean literals
  def transform(%{"type" => "true", "children" => []}) do
    {:ok, {:literal, [subtype: :boolean], true}, %{}}
  end

  def transform(%{"type" => "false", "children" => []}) do
    {:ok, {:literal, [subtype: :boolean], false}, %{}}
  end

  # Nil literal
  def transform(%{"type" => "nil", "children" => []}) do
    {:ok, {:literal, [subtype: :null], nil}, %{}}
  end

  # Self keyword
  def transform(%{"type" => "self", "children" => []}) do
    {:ok, {:variable, [scope: :special], "self"}, %{scope: :special}}
  end

  # Handle bare nil (used in unary operators)
  def transform(nil) do
    {:ok, nil, %{}}
  end

  # Constant base (root namespace ::)
  # Used in absolute constant paths like ::Array, ::SomeModule::Class
  def transform(%{"type" => "cbase", "children" => []}) do
    {:ok, {:literal, [subtype: :constant], ""}, %{namespace: :root}}
  end

  # Array literal
  def transform(%{"type" => "array", "children" => elements}) do
    with {:ok, elements_meta} <- transform_list(elements) do
      {:ok, {:list, [], elements_meta}, %{collection_type: :array}}
    end
  end

  # Constant (e.g., StandardError, Array, Hash)
  def transform(%{"type" => "const", "children" => [namespace, name]}) do
    const_name = if is_atom(name), do: Atom.to_string(name), else: name

    qualified_name =
      if is_nil(namespace) do
        const_name
      else
        with {:ok, namespace_meta, _} <- transform(namespace) do
          "#{format_const(namespace_meta)}::#{const_name}"
        end
      end

    case qualified_name do
      {:ok, _, _} = result -> result
      name when is_binary(name) -> {:ok, {:literal, [subtype: :constant], name}, %{}}
    end
  end

  # Hash literal
  def transform(%{"type" => "hash", "children" => pairs}) do
    with {:ok, pairs_meta} <- transform_hash_pairs(pairs) do
      {:ok, {:map, [], pairs_meta}, %{collection_type: :hash}}
    end
  end

  # Variables - M2.1 Core Layer

  # Local variable
  def transform(%{"type" => "lvar", "children" => [name]} = ast)
      when is_binary(name) or is_atom(name) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, add_location({:variable, [scope: :local], var_name}, ast), %{scope: :local}}
  end

  # Instance variable (@var)
  def transform(%{"type" => "ivar", "children" => [name]})
      when is_binary(name) or is_atom(name) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, {:variable, [scope: :instance], var_name}, %{scope: :instance}}
  end

  # Class variable (@@var)
  def transform(%{"type" => "cvar", "children" => [name]})
      when is_binary(name) or is_atom(name) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, {:variable, [scope: :class], var_name}, %{scope: :class}}
  end

  # Global variable ($var)
  def transform(%{"type" => "gvar", "children" => [name]})
      when is_binary(name) or is_atom(name) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, {:variable, [scope: :global], var_name}, %{scope: :global}}
  end

  # Binary Operations - M2.1 Core Layer
  # In Ruby, most binary operators are implemented as method calls (send nodes)

  # Arithmetic operators: +, -, *, /, %, **
  # Operators can be either atoms or strings from JSON
  def transform(%{"type" => "send", "children" => [left, op, right]} = ast)
      when not is_nil(right) do
    cond do
      is_arithmetic_op?(op) ->
        op_atom = normalize_op(op)

        with {:ok, left_meta, _} <- transform(left),
             {:ok, right_meta, _} <- transform(right) do
          {:ok,
           add_location(
             {:binary_op, [category: :arithmetic, operator: op_atom], [left_meta, right_meta]},
             ast
           ), %{}}
        end

      is_comparison_op?(op) ->
        op_atom = normalize_op(op)

        with {:ok, left_meta, _} <- transform(left),
             {:ok, right_meta, _} <- transform(right) do
          {:ok,
           add_location(
             {:binary_op, [category: :comparison, operator: op_atom], [left_meta, right_meta]},
             ast
           ), %{}}
        end

      true ->
        # Regular method call with receiver
        transform_method_call_with_receiver(left, op, right)
    end
  end

  # Boolean operators: &&, ||, and, or
  def transform(%{"type" => "and", "children" => [left, right]}) do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, [category: :boolean, operator: :and], [left_meta, right_meta]}, %{}}
    end
  end

  def transform(%{"type" => "or", "children" => [left, right]}) do
    with {:ok, left_meta, _} <- transform(left),
         {:ok, right_meta, _} <- transform(right) do
      {:ok, {:binary_op, [category: :boolean, operator: :or], [left_meta, right_meta]}, %{}}
    end
  end

  # Unary Operations - M2.1 Core Layer

  # Unary operators - 3 children with nil as third: [operand, op, nil]
  def transform(%{"type" => "send", "children" => [operand, op, nil]}) do
    op_atom = normalize_op(op)

    cond do
      op_atom in [:-, :+] ->
        with {:ok, operand_meta, _} <- transform(operand) do
          {:ok, {:unary_op, [category: :arithmetic, operator: op_atom], [operand_meta]}, %{}}
        end

      op_atom == :! ->
        with {:ok, operand_meta, _} <- transform(operand) do
          {:ok, {:unary_op, [category: :boolean, operator: :not], [operand_meta]}, %{}}
        end

      true ->
        # Not actually a unary operator
        {:error, "Invalid unary operator: #{op}"}
    end
  end

  # Method call without arguments: 2 children [receiver, method]
  def transform(%{"type" => "send", "children" => [receiver, method]}) do
    method_str = if is_atom(method), do: Atom.to_string(method), else: method

    if is_nil(receiver) do
      # Local method call without args: hello
      {:ok, {:function_call, [name: method_str], []}, %{call_type: :local}}
    else
      # Check if this looks like attribute access (not a method call)
      # In Ruby, obj.attr without parentheses could be either
      # For simplicity, treat as attribute_access if receiver is a variable
      with {:ok, receiver_meta, _} <- transform(receiver) do
        case receiver_meta do
          {:variable, _, _} ->
            # Likely attribute access: obj.field
            {:ok, {:attribute_access, [attribute: method_str], [receiver_meta]},
             %{kind: :instance_var}}

          _ ->
            # Method call with receiver but no arguments: obj.method
            qualified_name = "#{format_receiver(receiver_meta)}.#{method_str}"
            {:ok, {:function_call, [name: qualified_name], []}, %{call_type: :instance}}
        end
      end
    end
  end

  # Method Calls - M2.1 Core Layer

  # Method call without receiver (local method call)
  def transform(%{"type" => "send", "children" => [nil, method_name | args]}) do
    method_str = if is_atom(method_name), do: Atom.to_string(method_name), else: method_name

    with {:ok, args_meta} <- transform_list(args) do
      {:ok, {:function_call, [name: method_str], args_meta}, %{call_type: :local}}
    end
  end

  # Method call with receiver
  def transform(%{"type" => "send", "children" => [receiver, method_name | args]})
      when not is_nil(receiver) and is_atom(method_name) do
    with {:ok, receiver_meta, _} <- transform(receiver),
         {:ok, args_meta} <- transform_list(args) do
      # For now, represent as "receiver.method" format
      # In future, might want to preserve receiver as separate field
      method_str = "#{format_receiver(receiver_meta)}.#{method_name}"
      {:ok, {:function_call, [name: method_str], args_meta}, %{call_type: :instance}}
    end
  end

  # Conditionals - M2.1 Core Layer

  # if/elsif/else
  def transform(%{"type" => "if", "children" => [condition, then_branch, else_branch]}) do
    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, then_meta, _} <- transform_or_nil(then_branch),
         {:ok, else_meta, _} <- transform_or_nil(else_branch) do
      {:ok, {:conditional, [], [cond_meta, then_meta, else_meta]}, %{}}
    end
  end

  # Ternary operator (also parsed as if)
  # Note: Ruby's parser treats ternary the same as if

  # Assignment - M2.1 Core Layer

  # Local variable assignment
  def transform(%{"type" => "lvasgn", "children" => [name, value]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, value_meta, _} <- transform(value) do
      {:ok, {:assignment, [scope: :local], [{:variable, [], var_name}, value_meta]},
       %{scope: :local}}
    end
  end

  # Local variable binding (without value, e.g., in rescue clauses)
  def transform(%{"type" => "lvasgn", "children" => [name]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, {:variable, [scope: :local], var_name}, %{scope: :local, binding: true}}
  end

  # Instance variable assignment
  def transform(%{"type" => "ivasgn", "children" => [name, value]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, value_meta, _} <- transform(value) do
      {:ok, {:assignment, [scope: :instance], [{:variable, [], var_name}, value_meta]},
       %{scope: :instance}}
    end
  end

  # Class variable assignment
  def transform(%{"type" => "cvasgn", "children" => [name, value]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, value_meta, _} <- transform(value) do
      {:ok, {:assignment, [scope: :class], [{:variable, [], var_name}, value_meta]},
       %{scope: :class}}
    end
  end

  # Global variable assignment
  def transform(%{"type" => "gvasgn", "children" => [name, value]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, value_meta, _} <- transform(value) do
      {:ok, {:assignment, [scope: :global], [{:variable, [], var_name}, value_meta]},
       %{scope: :global}}
    end
  end

  # M2.2s Structural Layer - Augmented assignment
  # Ruby represents += as op_asgn (operational assignment)
  def transform(%{"type" => "op_asgn", "children" => [target, op, value]}) do
    op_atom = normalize_op(op)

    with {:ok, target_meta, _} <- transform(target),
         {:ok, value_meta, _} <- transform(value) do
      # Determine operation category
      category =
        cond do
          is_arithmetic_op?(op) -> :arithmetic
          is_comparison_op?(op) -> :comparison
          true -> :other
        end

      {:ok,
       {:augmented_assignment, [category: category, operator: op_atom],
        [target_meta, value_meta]}, %{}}
    end
  end

  # Blocks - M2.1 Core Layer

  # Begin block (sequential statements)
  def transform(%{"type" => "begin", "children" => statements}) when is_list(statements) do
    with {:ok, statements_meta} <- transform_list(statements) do
      {:ok, {:block, [], statements_meta}, %{}}
    end
  end

  # Loops - M2.2 Extended Layer

  # While loop: while condition do body end
  def transform(%{"type" => "while", "children" => [condition, body]}) do
    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      {:ok, {:loop, [loop_type: :while], [cond_meta, body_meta]}, %{}}
    end
  end

  # Until loop: until condition do body end
  def transform(%{"type" => "until", "children" => [condition, body]}) do
    with {:ok, cond_meta, _} <- transform(condition),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      # Until is equivalent to "while not condition"
      negated_cond = {:unary_op, [category: :boolean, operator: :not], [cond_meta]}
      {:ok, {:loop, [loop_type: :while], [negated_cond, body_meta]}, %{original_type: :until}}
    end
  end

  # For loop: for var in collection do body end
  def transform(%{"type" => "for", "children" => [var_asgn, collection, body]}) do
    with {:ok, var_meta, _} <- transform_iterator_variable(var_asgn),
         {:ok, collection_meta, _} <- transform(collection),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      {:ok, {:loop, [loop_type: :for_each], [var_meta, collection_meta, body_meta]}, %{}}
    end
  end

  # Blocks with parameters and iterators - M2.2 Extended Layer

  # Block with receiver (iterator methods: each, map, select, reduce, etc.)
  # Structure: block [send [collection, method, ...args], args [param...], body]
  def transform(%{"type" => "block", "children" => [send_node, args_node, body]}) do
    case send_node do
      # Lambda: lambda { |x| body } or ->(x) { body }
      %{"type" => "send", "children" => [nil, "lambda"]} ->
        transform_lambda(args_node, body)

      # Iterator methods: [1,2,3].each { |x| ... }
      %{"type" => "send", "children" => [collection, method | method_args]} ->
        transform_iterator_method(collection, method, method_args, args_node, body)

      _ ->
        {:error, "Unsupported block construct: #{inspect(send_node)}"}
    end
  end

  # Pattern Matching - M2.2 Extended Layer

  # Case/when statement
  def transform(%{"type" => "case", "children" => children}) do
    [scrutinee | branches] = children
    {else_branch, when_branches} = extract_else_branch(branches)

    with {:ok, scrutinee_meta, _} <- transform(scrutinee),
         {:ok, branches_meta} <- transform_when_branches(when_branches),
         {:ok, else_meta, _} <- transform_or_nil(else_branch) do
      {:ok, {:pattern_match, [], [scrutinee_meta, branches_meta, else_meta]}, %{}}
    end
  end

  # Exception Handling - M2.2 Extended Layer

  # Begin/rescue/ensure block
  def transform(%{"type" => "kwbegin", "children" => [ensure_or_rescue]}) do
    transform(ensure_or_rescue)
  end

  # Ensure block (with or without rescue)
  def transform(%{"type" => "ensure", "children" => [try_body, ensure_body]}) do
    case try_body do
      %{"type" => "rescue"} ->
        # Has both rescue and ensure
        with {:ok, rescue_meta, rescue_metadata} <- transform(try_body),
             {:ok, ensure_meta, _} <- transform(ensure_body) do
          # Merge rescue handlers with ensure
          metadata = Map.put(rescue_metadata, :ensure, ensure_meta)
          {:ok, rescue_meta, metadata}
        end

      _ ->
        # Only ensure, no rescue
        with {:ok, try_meta, _} <- transform(try_body),
             {:ok, ensure_meta, _} <- transform(ensure_body) do
          {:ok, {:exception_handling, [], [try_meta, [], nil]}, %{ensure: ensure_meta}}
        end
    end
  end

  # Rescue block
  def transform(%{"type" => "rescue", "children" => children}) do
    [try_body | rescue_bodies] = children
    rescue_handlers = Enum.filter(rescue_bodies, &match?(%{"type" => "resbody"}, &1))
    else_body = Enum.find(rescue_bodies, fn node -> not match?(%{"type" => "resbody"}, node) end)

    with {:ok, try_meta, _} <- transform(try_body),
         {:ok, handlers_meta} <- transform_rescue_handlers(rescue_handlers),
         {:ok, else_meta, _} <- transform_or_nil(else_body) do
      {:ok, {:exception_handling, [], [try_meta, handlers_meta, else_meta]}, %{}}
    end
  end

  # M2.2s Structural Layer - Container support

  # Class definition - maps to container
  def transform(%{"type" => "class", "children" => [name, superclass, body]} = ast) do
    with {:ok, name_meta, _} <- transform(name),
         {:ok, superclass_meta, _} <- transform_or_nil(superclass),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      class_name = extract_constant_name(name_meta)
      parent_name = extract_parent_name(superclass_meta)

      # Add class context to the container node itself
      class_context = %{
        language: :ruby,
        module: class_name
      }

      # Create container: {:container, [container_type: :class, name: name, ...], [body]}
      container =
        {:container, [container_type: :class, name: class_name, parent: parent_name], [body_meta]}

      {:ok, add_location_with_context(container, ast, class_context),
       %{ruby_ast: ast, superclass: superclass_meta}}
    end
  end

  # Module definition - maps to container
  def transform(%{"type" => "module", "children" => [name, body]} = ast) do
    with {:ok, name_meta, _} <- transform(name),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      module_name = extract_constant_name(name_meta)

      # Add module context to the container node itself
      module_context = %{
        language: :ruby,
        module: module_name
      }

      # Create container: {:container, [container_type: :module, name: name], [body]}
      container = {:container, [container_type: :module, name: module_name], [body_meta]}

      {:ok, add_location_with_context(container, ast, module_context), %{ruby_ast: ast}}
    end
  end

  # M2.2s Structural Layer - Function definition support

  # Method definition (def) - maps to function_def
  def transform(%{"type" => "def", "children" => [name, args, body]} = ast) do
    method_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, params} <- extract_method_params(args),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      arity = length(params)

      # Add function context to the function_def node itself
      func_context = %{
        language: :ruby,
        function: method_name,
        arity: arity,
        visibility: :public
      }

      # Create function_def: {:function_def, [name: name, params: params, ...], [body]}
      function_def =
        {:function_def, [name: method_name, params: params, visibility: :public, arity: arity],
         [body_meta]}

      {:ok, add_location_with_context(function_def, ast, func_context), %{ruby_ast: ast}}
    end
  end

  # Class method definition (def self.method) or singleton method (def obj.method)
  # Ruby parser represents this as "defs" type
  def transform(%{"type" => "defs", "children" => [receiver, name, args, body]} = ast) do
    method_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, receiver_meta, _} <- transform(receiver),
         {:ok, params} <- extract_method_params(args),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      # For class methods (def self.method), qualify the name
      qualified_name =
        case receiver_meta do
          {:variable, _, "self"} -> "self.#{method_name}"
          _ -> "#{format_receiver(receiver_meta)}.#{method_name}"
        end

      arity = length(params)

      # Add function context
      func_context = %{
        language: :ruby,
        function: qualified_name,
        arity: arity,
        visibility: :public
      }

      # Create function_def with qualified name
      function_def =
        {:function_def, [name: qualified_name, params: params, visibility: :public, arity: arity],
         [body_meta]}

      {:ok, add_location_with_context(function_def, ast, func_context),
       %{ruby_ast: ast, is_class_method: true}}
    end
  end

  # Private/protected method definition - uses access control keywords
  # Note: Ruby's private/protected are modifier keywords, not part of def itself
  # They're typically handled at a higher level in the AST

  # Constant assignment (e.g., BAR = 42)
  def transform(%{"type" => "casgn", "children" => [namespace, name, value]} = ast) do
    const_name = if is_atom(name), do: Atom.to_string(name), else: name

    with {:ok, value_meta, _} <- transform(value) do
      metadata = %{
        name: const_name,
        namespace: namespace,
        value: value_meta
      }

      {:ok, {:language_specific, [language: :ruby, hint: :constant_assignment], ast}, metadata}
    end
  end

  # Yield with arguments
  def transform(%{"type" => "yield", "children" => args} = ast) do
    with {:ok, args_meta} <- transform_list(args) do
      metadata = %{args: args_meta}
      {:ok, {:language_specific, [language: :ruby, hint: :yield], ast}, metadata}
    end
  end

  # Alias (alias new_name old_name)
  def transform(%{"type" => "alias", "children" => [new_name, old_name]} = ast) do
    new_sym = extract_symbol_name(new_name)
    old_sym = extract_symbol_name(old_name)

    metadata = %{new_name: new_sym, old_name: old_sym}
    {:ok, {:language_specific, [language: :ruby, hint: :alias], ast}, metadata}
  end

  # String interpolation (dstr)
  def transform(%{"type" => "dstr", "children" => parts} = ast) do
    with {:ok, parts_meta} <- transform_string_parts(parts) do
      metadata = %{parts: parts_meta}
      {:ok, {:language_specific, [language: :ruby, hint: :string_interpolation], ast}, metadata}
    end
  end

  # Regular expression
  def transform(%{"type" => "regexp", "children" => [pattern | options]} = ast) do
    with {:ok, pattern_meta, _} <- transform(pattern) do
      metadata = %{pattern: pattern_meta, options: options}
      {:ok, {:language_specific, [language: :ruby, hint: :regexp], ast}, metadata}
    end
  end

  # Singleton class (class << self)
  def transform(%{"type" => "sclass", "children" => [object, body]} = ast) do
    with {:ok, object_meta, _} <- transform(object),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      metadata = %{object: object_meta, body: body_meta}
      {:ok, {:language_specific, [language: :ruby, hint: :singleton_class], ast}, metadata}
    end
  end

  # Super with arguments
  def transform(%{"type" => "super", "children" => args} = ast) do
    with {:ok, args_meta} <- transform_list(args) do
      metadata = %{args: args_meta}
      {:ok, {:language_specific, [language: :ruby, hint: :super], ast}, metadata}
    end
  end

  # Zsuper (super with no arguments, passes all parent arguments)
  def transform(%{"type" => "zsuper", "children" => []} = ast) do
    {:ok, {:language_specific, [language: :ruby, hint: :zsuper], ast}, %{}}
  end

  # Catch-all for unsupported constructs
  def transform(unsupported) do
    {:error, "Unsupported Ruby AST construct: #{inspect(unsupported)}"}
  end

  # Helper Functions

  defp transform_list(items) when is_list(items) do
    items
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case transform(item) do
        {:ok, meta, _} -> {:cont, {:ok, [meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp transform_or_nil(nil), do: {:ok, nil, %{}}
  defp transform_or_nil(value), do: transform(value)

  defp transform_hash_pairs(pairs) when is_list(pairs) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn pair, {:ok, acc} ->
      case transform_hash_pair(pair) do
        {:ok, pair_meta} -> {:cont, {:ok, [pair_meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      error -> error
    end
  end

  defp transform_hash_pair(%{"type" => "pair", "children" => [key, value]}) do
    with {:ok, key_meta, _} <- transform(key),
         {:ok, value_meta, _} <- transform(value) do
      {:ok, {:pair, [], [key_meta, value_meta]}}
    end
  end

  defp transform_hash_pair(other) do
    {:error, "Invalid hash pair: #{inspect(other)}"}
  end

  defp format_receiver({:variable, _, name}), do: name
  defp format_receiver(_), do: "obj"

  defp format_const({:literal, [subtype: :constant], name}), do: name
  defp format_const({:literal, _, name}) when is_binary(name), do: name
  defp format_const(_), do: "Unknown"

  # Operator normalization helpers
  defp normalize_op(op) when is_atom(op), do: op
  defp normalize_op(op) when is_binary(op), do: String.to_atom(op)

  defp is_arithmetic_op?(op) when is_atom(op) do
    op in [:+, :-, :*, :/, :%, :**] or op == :"<<" or op == :">>"
  end

  defp is_arithmetic_op?(op) when is_binary(op) do
    op in ["+", "-", "*", "/", "%", "**", "<<", ">>"]
  end

  defp is_comparison_op?(op) when is_atom(op) do
    op in [:==, :!=, :<, :>, :<=, :>=, :===, :eql?, :"<=>"]
  end

  defp is_comparison_op?(op) when is_binary(op) do
    op in ["==", "!=", "<", ">", "<=", ">=", "===", "eql?", "<=>"]
  end

  defp transform_method_call_with_receiver(receiver, method_name, arg) do
    method_str = if is_atom(method_name), do: Atom.to_string(method_name), else: method_name

    with {:ok, receiver_meta, _} <- transform(receiver),
         {:ok, arg_meta, _} <- transform(arg) do
      qualified_name = "#{format_receiver(receiver_meta)}.#{method_str}"
      {:ok, {:function_call, qualified_name, [arg_meta]}, %{call_type: :instance}}
    end
  end

  # M2.2 Extended Layer Helper Functions

  # Transform iterator variable (from lvasgn in for loops)
  defp transform_iterator_variable(%{"type" => "lvasgn", "children" => [name]}) do
    var_name = if is_atom(name), do: Atom.to_string(name), else: name
    {:ok, var_name, %{}}
  end

  defp transform_iterator_variable(other) do
    {:error, "Invalid iterator variable: #{inspect(other)}"}
  end

  # Transform lambda
  defp transform_lambda(args_node, body) do
    with {:ok, params} <- extract_lambda_params(args_node),
         {:ok, body_meta, _} <- transform(body) do
      {:ok, {:lambda, [params: params, captures: []], [body_meta]}, %{}}
    end
  end

  # Extract lambda parameters from args node
  defp extract_lambda_params(%{"type" => "args", "children" => args}) do
    params =
      Enum.map(args, fn
        %{"type" => "arg", "children" => [name]} when is_binary(name) -> name
        %{"type" => "arg", "children" => [name]} when is_atom(name) -> Atom.to_string(name)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, params}
  end

  defp extract_lambda_params(_), do: {:ok, []}

  # Transform iterator methods (map, each, select, reduce)
  defp transform_iterator_method(collection, method, method_args, args_node, body) do
    method_atom = normalize_op(method)

    case method_atom do
      m when m in [:each, :map, :select, :filter, :reject] ->
        transform_map_like_iterator(collection, m, args_node, body)

      :reduce ->
        transform_reduce_iterator(collection, method_args, args_node, body)

      _ ->
        # Not a recognized iterator, treat as generic block
        {:error, "Unrecognized iterator method: #{method}"}
    end
  end

  # Transform map-like iterators (each, map, select, filter)
  defp transform_map_like_iterator(collection, method, args_node, body) do
    with {:ok, collection_meta, _} <- transform(collection),
         {:ok, params} <- extract_lambda_params(args_node),
         {:ok, body_meta, _} <- transform(body) do
      lambda = {:lambda, [params: params, captures: []], [body_meta]}
      {:ok, {:collection_op, [op_type: method], [lambda, collection_meta]}, %{}}
    end
  end

  # Transform reduce iterator
  defp transform_reduce_iterator(collection, method_args, args_node, body) do
    with {:ok, collection_meta, _} <- transform(collection),
         {:ok, initial_meta} <- extract_reduce_initial(method_args),
         {:ok, params} <- extract_lambda_params(args_node),
         {:ok, body_meta, _} <- transform(body) do
      lambda = {:lambda, [params: params, captures: []], [body_meta]}
      {:ok, {:collection_op, [op_type: :reduce], [lambda, collection_meta, initial_meta]}, %{}}
    end
  end

  # Extract initial value from reduce method args
  defp extract_reduce_initial([initial | _]) do
    case transform(initial) do
      {:ok, meta, _} -> {:ok, meta}
      error -> error
    end
  end

  defp extract_reduce_initial([]), do: {:ok, nil}

  # Pattern matching helpers
  defp extract_else_branch(branches) do
    else_branch = Enum.find(branches, fn node -> not match?(%{"type" => "when"}, node) end)
    when_branches = Enum.filter(branches, &match?(%{"type" => "when"}, &1))
    {else_branch, when_branches}
  end

  defp transform_when_branches(when_branches) do
    when_branches
    |> Enum.reduce_while({:ok, []}, fn when_node, {:ok, acc} ->
      case transform_when_branch(when_node) do
        {:ok, branch_meta} -> {:cont, {:ok, [branch_meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, branches} -> {:ok, Enum.reverse(branches)}
      error -> error
    end
  end

  defp transform_when_branch(%{"type" => "when", "children" => [pattern | rest]}) do
    # Rest is either [body] or [] if body is nil
    body = List.first(rest)

    with {:ok, pattern_meta, _} <- transform(pattern),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      {:ok, {pattern_meta, body_meta}}
    end
  end

  # Exception handling helpers
  defp transform_rescue_handlers(handlers) do
    handlers
    |> Enum.reduce_while({:ok, []}, fn handler, {:ok, acc} ->
      case transform_rescue_handler(handler) do
        {:ok, handler_meta} -> {:cont, {:ok, [handler_meta | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, handlers} -> {:ok, Enum.reverse(handlers)}
      error -> error
    end
  end

  defp transform_rescue_handler(%{
         "type" => "resbody",
         "children" => [exception_types, var_binding, body]
       }) do
    with {:ok, types_meta} <- transform_exception_types(exception_types),
         {:ok, var_meta, _} <- transform_or_nil(var_binding),
         {:ok, body_meta, _} <- transform(body) do
      {:ok, {types_meta, var_meta, body_meta}}
    end
  end

  defp transform_exception_types(%{"type" => "array", "children" => types}) do
    transform_list(types)
  end

  defp transform_exception_types(nil), do: {:ok, []}

  # M2.2s Structural Layer Helpers

  defp extract_constant_name({:literal, [subtype: :constant], name}), do: name
  defp extract_constant_name({:literal, _, name}) when is_binary(name), do: name
  defp extract_constant_name(_), do: "Unknown"

  defp extract_parent_name({:literal, [subtype: :constant], name}), do: name
  defp extract_parent_name({:literal, _, name}) when is_binary(name), do: name
  defp extract_parent_name(nil), do: nil
  defp extract_parent_name(_), do: nil

  defp extract_method_params(%{"type" => "args", "children" => args}) do
    params =
      Enum.map(args, fn
        %{"type" => "arg", "children" => [name]} when is_binary(name) -> name
        %{"type" => "arg", "children" => [name]} when is_atom(name) -> Atom.to_string(name)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, params}
  end

  defp extract_method_params(_), do: {:ok, []}

  defp extract_symbol_name(%{"type" => "sym", "children" => [name]}) when is_atom(name) do
    Atom.to_string(name)
  end

  defp extract_symbol_name(%{"type" => "sym", "children" => [name]}) when is_binary(name),
    do: name

  defp extract_symbol_name(%{"type" => "dsym", "children" => parts}), do: {:dynamic, parts}
  defp extract_symbol_name(_), do: "unknown"

  defp transform_string_parts(parts) when is_list(parts) do
    parts
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case part do
        # String literal part
        %{"type" => "str", "children" => [str]} ->
          {:cont, {:ok, [{:literal, str} | acc]}}

        # Interpolated expression
        %{"type" => "begin", "children" => [expr]} ->
          case transform(expr) do
            {:ok, expr_meta, _} -> {:cont, {:ok, [{:interpolation, expr_meta} | acc]}}
            {:error, _} = err -> {:halt, err}
          end

        # Direct expression
        expr ->
          case transform(expr) do
            {:ok, expr_meta, _} -> {:cont, {:ok, [{:interpolation, expr_meta} | acc]}}
            {:error, _} = err -> {:halt, err}
          end
      end
    end)
    |> case do
      {:ok, parts_list} -> {:ok, Enum.reverse(parts_list)}
      error -> error
    end
  end

  # Location extraction helpers
  # For 3-tuple format: {type, keyword_meta, value_or_children}
  # Location info is merged into the keyword_meta (2nd element)
  @doc false
  @spec add_location(tuple(), map()) :: tuple()
  defp add_location({type, meta, value_or_children}, %{"location" => loc}) when is_map(loc) do
    location_fields =
      []
      |> maybe_prepend(:line, loc["begin_line"])
      |> maybe_prepend(:col, loc["begin_column"])
      |> maybe_prepend(:end_line, loc["end_line"] || loc["begin_line"])
      |> maybe_prepend(:end_col, loc["end_column"])

    {type, meta ++ location_fields, value_or_children}
  end

  defp add_location(meta_ast, _ast_node), do: meta_ast

  # Add location and context metadata (for M1 metadata preservation)
  # Merges both location and context into keyword_meta
  @doc false
  defp add_location_with_context({type, meta, value_or_children}, %{"location" => loc}, context)
       when is_map(loc) and is_map(context) do
    location_fields =
      []
      |> maybe_prepend(:line, loc["begin_line"])
      |> maybe_prepend(:col, loc["begin_column"])
      |> maybe_prepend(:end_line, loc["end_line"])
      |> maybe_prepend(:end_col, loc["end_column"])

    context_fields = Enum.map(context, fn {k, v} -> {k, v} end)

    {type, meta ++ location_fields ++ context_fields, value_or_children}
  end

  defp add_location_with_context({type, meta, value_or_children}, _ast, context)
       when is_map(context) do
    context_fields = Enum.map(context, fn {k, v} -> {k, v} end)
    {type, meta ++ context_fields, value_or_children}
  end

  defp maybe_prepend(list, _key, nil), do: list
  defp maybe_prepend(list, key, value), do: [{key, value} | list]
end
