# Structural Layer Design Proposal

## Executive Summary

This document provides a concrete, implementation-ready design for extending MetaAST M2.2 (Extended Layer) with organizational/structural constructs. The design enables cross-language analysis of modules, classes, and function definitions while maintaining backward compatibility and round-trip fidelity.

**Status:** Design Proposal  
**Target:** MetaAST v0.2.0+  
**Estimated LOC:** ~2,500 lines (core types + 5 adapters)  
**Estimated Effort:** 4-6 weeks  

---

## Table of Contents

1. [Type Definitions](#1-type-definitions)
2. [Metadata Schema](#2-metadata-schema)
3. [AST Module Extensions](#3-ast-module-extensions)
4. [Adapter Transformation Rules](#4-adapter-transformation-rules)
5. [Validation Rules](#5-validation-rules)
6. [Analysis Tool Updates](#6-analysis-tool-updates)
7. [Migration Path](#7-migration-path)
8. [Testing Strategy](#8-testing-strategy)
9. [Implementation Phases](#9-implementation-phases)

---

## 1. Type Definitions

### 1.1 Core New Types

Add to `lib/metastatic/ast.ex`:

```elixir
@type container :: {
  :container,
  container_type(),
  name :: String.t(),
  metadata :: map(),
  members :: [meta_ast()]
}

@type container_type :: :module | :class | :namespace

@type function_def :: {
  :function_def,
  visibility(),
  name :: String.t(),
  params :: [param()],
  guards :: meta_ast() | nil,
  body :: meta_ast()
}

@type visibility :: :public | :private | :protected

@type param :: 
  String.t() |  # Simple parameter name
  {:pattern, meta_ast()} |  # Pattern matching parameter
  {:default, String.t(), meta_ast()}  # Parameter with default value

@type meta_ast ::
  # ... existing types ...
  | container()
  | function_def()
  | attribute_access()
  | augmented_assignment()
```

### 1.2 Supporting Types

```elixir
# For OOP attribute access: self.count, @instance_var
@type attribute_access :: {
  :attribute_access,
  receiver :: meta_ast(),
  attribute :: String.t()
}

# For augmented assignment: x += 1, self.count += 1
@type augmented_assignment :: {
  :augmented_assignment,
  operator :: atom(),  # :+=, :-=, :*=, etc.
  target :: meta_ast(),
  value :: meta_ast()
}

# For decorator/annotation preservation
@type decorator :: {
  :decorator,
  name :: String.t(),
  args :: [meta_ast()]
}
```

### 1.3 Metadata Structure for Containers

```elixir
@type container_metadata :: %{
  # Required fields
  source_language: atom(),
  has_state: boolean(),
  
  # Visibility/exports
  visibility: [String.t()],  # List of public member names
  
  # Inheritance (OOP only)
  superclass: meta_ast() | nil,
  mixins: [meta_ast()],  # Ruby mixins, Python multiple inheritance
  traits: [meta_ast()],  # Elixir protocols, Haskell type classes
  
  # Constructor (OOP only)
  constructor: function_def() | nil,
  
  # Organizational model
  organizational_model: :oop | :functional | :hybrid,
  instantiable: boolean(),
  
  # For round-trip fidelity
  original_ast: term() | nil,
  language_hints: map()
}
```

### 1.4 Metadata Structure for Functions

```elixir
@type function_def_metadata :: %{
  # Decorators/attributes
  decorators: [decorator()],
  
  # Multi-clause tracking (Elixir/Erlang/Haskell)
  is_multi_clause: boolean(),
  clause_count: non_neg_integer(),
  
  # Type annotations
  type_signature: String.t() | nil,
  return_type: String.t() | nil,
  
  # For round-trip fidelity
  original_ast: term() | nil,
  language_hints: map()
}
```

---

## 2. Metadata Schema

### 2.1 OOP Container Example (Python Class)

```elixir
{:container, :class, "Counter",
  %{
    source_language: :python,
    has_state: true,
    instantiable: true,
    organizational_model: :oop,
    
    visibility: ["increment", "get_count"],  # Public methods
    superclass: nil,
    mixins: [],
    traits: [],
    
    constructor: {:function_def, :public, "__init__", ["self"], nil,
      {:assignment,
        {:attribute_access, {:variable, "self"}, "count"},
        {:literal, :integer, 0}
      }
    },
    
    original_ast: %{"_type" => "ClassDef", ...},
    language_hints: %{
      python_decorators: [],
      python_metaclass: nil
    }
  },
  [
    {:function_def, :public, "increment", ["self"], nil, ...},
    {:function_def, :public, "get_count", ["self"], nil, ...},
    {:function_def, :private, "_reset", ["self"], nil, ...}
  ]
}
```

### 2.2 FP Container Example (Elixir Module)

```elixir
{:container, :module, "Math",
  %{
    source_language: :elixir,
    has_state: false,
    instantiable: false,
    organizational_model: :functional,
    
    visibility: ["factorial", "fibonacci"],  # Public functions (def)
    superclass: nil,
    mixins: [],
    traits: [],
    
    constructor: nil,
    
    original_ast: {:defmodule, [], ...},
    language_hints: %{
      elixir_module_attributes: [
        {:moduledoc, "Mathematical functions"}
      ],
      elixir_uses: ["Enum"],
      elixir_imports: ["Integer"]
    }
  },
  [
    {:function_def, :public, "factorial", 
      [{:pattern, {:literal, :integer, 0}}, {:pattern, {:variable, "n"}}],
      nil,
      pattern_match_body
    },
    {:function_def, :public, "fibonacci", ...},
    {:function_def, :private, "helper", ...}
  ]
}
```

### 2.3 Hybrid Example (Ruby Module with State Tracking)

```elixir
{:container, :module, "Counter",
  %{
    source_language: :ruby,
    has_state: true,  # Module variables (@@count)
    instantiable: false,  # Modules can't be instantiated
    organizational_model: :hybrid,
    
    visibility: ["increment", "current"],
    superclass: nil,
    mixins: [],
    traits: [],
    
    constructor: nil,  # No constructor, but has module-level state
    
    original_ast: %{"type" => "module", ...},
    language_hints: %{
      ruby_module_variables: ["@@count"],
      ruby_extend: [],
      ruby_include: []
    }
  },
  members
}
```

---

## 3. AST Module Extensions

### 3.1 Add to `lib/metastatic/ast.ex`

```elixir
defmodule Metastatic.AST do
  # ... existing code ...
  
  @doc """
  Check if an AST node conforms to MetaAST specification.
  
  Extended with structural layer support.
  """
  @spec conforms?(meta_ast()) :: boolean()
  
  # Container conformance
  def conforms?({:container, container_type, name, metadata, members})
      when is_atom(container_type) and is_binary(name) and is_map(metadata) and is_list(members) do
    container_type in [:module, :class, :namespace] and
      Enum.all?(members, &conforms?/1)
  end
  
  # Function definition conformance
  def conforms?({:function_def, visibility, name, params, guards, body})
      when is_atom(visibility) and is_binary(name) and is_list(params) do
    visibility in [:public, :private, :protected] and
      conforms_param_list?(params) and
      (is_nil(guards) or conforms?(guards)) and
      conforms?(body)
  end
  
  # Attribute access conformance
  def conforms?({:attribute_access, receiver, attribute})
      when is_binary(attribute) do
    conforms?(receiver)
  end
  
  # Augmented assignment conformance
  def conforms?({:augmented_assignment, op, target, value})
      when is_atom(op) do
    conforms?(target) and conforms?(value)
  end
  
  # ... rest of existing conforms? clauses ...
  
  defp conforms_param_list?(params) when is_list(params) do
    Enum.all?(params, fn
      name when is_binary(name) -> true
      {:pattern, ast} -> conforms?(ast)
      {:default, name, default} when is_binary(name) -> conforms?(default)
      _ -> false
    end)
  end
  
  @doc """
  Extract all variables from a MetaAST node.
  
  Extended with structural layer support.
  """
  @spec variables(meta_ast()) :: MapSet.t(String.t())
  
  # Container variables (recursively extract from all members)
  def variables({:container, _type, _name, _metadata, members}) do
    members
    |> Enum.map(&variables/1)
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end
  
  # Function definition variables
  def variables({:function_def, _vis, _name, params, guards, body}) do
    param_vars = extract_param_vars(params)
    guard_vars = if guards, do: variables(guards), else: MapSet.new()
    body_vars = variables(body)
    
    param_vars
    |> MapSet.union(guard_vars)
    |> MapSet.union(body_vars)
  end
  
  # Attribute access variables
  def variables({:attribute_access, receiver, _attribute}) do
    variables(receiver)
  end
  
  # Augmented assignment variables
  def variables({:augmented_assignment, _op, target, value}) do
    MapSet.union(variables(target), variables(value))
  end
  
  # ... rest of existing variables clauses ...
  
  defp extract_param_vars(params) do
    params
    |> Enum.flat_map(fn
      name when is_binary(name) -> [name]
      {:pattern, ast} -> MapSet.to_list(variables(ast))
      {:default, name, _} -> [name]
    end)
    |> MapSet.new()
  end
  
  @doc """
  Get the container name from a container node.
  """
  @spec container_name(container()) :: String.t()
  def container_name({:container, _type, name, _metadata, _members}), do: name
  
  @doc """
  Get the function name from a function_def node.
  """
  @spec function_name(function_def()) :: String.t()
  def function_name({:function_def, _vis, name, _params, _guards, _body}), do: name
  
  @doc """
  Check if a container has state (OOP class vs FP module).
  """
  @spec has_state?(container()) :: boolean()
  def has_state?({:container, _type, _name, metadata, _members}) do
    Map.get(metadata, :has_state, false)
  end
  
  @doc """
  Get all public members of a container.
  """
  @spec public_members(container()) :: [meta_ast()]
  def public_members({:container, _type, _name, _metadata, members}) do
    Enum.filter(members, fn
      {:function_def, :public, _, _, _, _} -> true
      _ -> false
    end)
  end
end
```

---

## 4. Adapter Transformation Rules

### 4.1 Elixir Adapter Updates

File: `lib/metastatic/adapters/elixir/to_meta.ex`

```elixir
defmodule Metastatic.Adapters.Elixir.ToMeta do
  # ... existing code ...
  
  # Replace language_specific module handling with container
  def transform({:defmodule, meta, [name, [do: body]]}) do
    module_name = module_name_to_string(name)
    
    with {:ok, body_meta, body_metadata} <- transform(body),
         {:ok, members, visibility} <- extract_members(body_meta) do
      
      metadata = %{
        source_language: :elixir,
        has_state: false,
        instantiable: false,
        organizational_model: :functional,
        visibility: visibility,
        superclass: nil,
        mixins: [],
        traits: extract_protocols(body_metadata),
        constructor: nil,
        original_ast: {:defmodule, meta, [name, [do: body]]},
        language_hints: %{
          elixir_module_attributes: extract_attributes(body_meta),
          elixir_uses: [],
          elixir_imports: []
        }
      }
      
      {:ok, {:container, :module, module_name, metadata, members}, metadata}
    end
  end
  
  # Replace language_specific function handling with function_def
  def transform({func_type, meta, [signature, [do: body]]})
      when func_type in [:def, :defp] do
    func_name = extract_function_name(signature)
    visibility = if func_type == :defp, do: :private, else: :public
    
    with {:ok, params, guards} <- extract_params_and_guards(signature),
         {:ok, body_meta, _} <- transform(body) do
      
      metadata = %{
        decorators: [],
        is_multi_clause: false,  # Single clause for now
        clause_count: 1,
        type_signature: nil,
        return_type: nil,
        original_ast: {func_type, meta, [signature, [do: body]]},
        language_hints: %{}
      }
      
      {:ok, {:function_def, visibility, func_name, params, guards, body_meta}, metadata}
    end
  end
  
  # Helper: Extract members and visibility from block
  defp extract_members({:block, exprs}) do
    members = Enum.filter(exprs, fn
      {:function_def, _, _, _, _, _} -> true
      _ -> false
    end)
    
    visibility = 
      members
      |> Enum.filter(&match?({:function_def, :public, _, _, _, _}, &1))
      |> Enum.map(&elem(&1, 2))  # Extract function name
    
    {:ok, members, visibility}
  end
  
  defp extract_members(single_expr) do
    # Single expression module body
    {:ok, [single_expr], []}
  end
  
  defp extract_function_name({name, _meta, _args}) when is_atom(name) do
    Atom.to_string(name)
  end
  
  defp extract_params_and_guards({_name, _meta, args}) when is_list(args) do
    # Simple params for now (no pattern matching in this version)
    params = Enum.map(args, fn
      {name, _, nil} when is_atom(name) -> Atom.to_string(name)
      other -> inspect(other)  # Fallback
    end)
    
    {:ok, params, nil}
  end
  
  # ... rest of existing code ...
end
```

### 4.2 Python Adapter Updates

File: `lib/metastatic/adapters/python/to_meta.ex`

```elixir
defmodule Metastatic.Adapters.Python.ToMeta do
  # ... existing code ...
  
  # Replace language_specific class handling with container
  def transform(%{"_type" => "ClassDef", "name" => name, "bases" => bases, 
                   "body" => body, "decorator_list" => decorators}) do
    
    with {:ok, members, visibility} <- transform_class_body(body),
         {:ok, superclass} <- transform_superclass(bases),
         {:ok, constructor} <- extract_constructor(members) do
      
      metadata = %{
        source_language: :python,
        has_state: true,
        instantiable: true,
        organizational_model: :oop,
        visibility: visibility,
        superclass: superclass,
        mixins: transform_mixins(bases),
        traits: [],
        constructor: constructor,
        original_ast: %{"_type" => "ClassDef", "name" => name, ...},
        language_hints: %{
          python_decorators: transform_decorators(decorators),
          python_metaclass: nil
        }
      }
      
      {:ok, {:container, :class, name, metadata, members}, metadata}
    end
  end
  
  # Replace language_specific function handling with function_def
  def transform(%{"_type" => "FunctionDef", "name" => name, "args" => args,
                   "body" => body, "decorator_list" => decorators,
                   "returns" => returns}) do
    
    # Skip if this is a constructor (__init__) - handled by container
    if name == "__init__" do
      # Still transform it, but mark it specially
      transform_init_function(name, args, body, decorators, returns)
    else
      transform_regular_function(name, args, body, decorators, returns)
    end
  end
  
  defp transform_regular_function(name, args, body, decorators, returns) do
    visibility = determine_visibility(name)
    
    with {:ok, params} <- extract_params(args),
         {:ok, body_meta, _} <- transform_body(body),
         {:ok, decs} <- transform_decorators(decorators) do
      
      metadata = %{
        decorators: decs,
        is_multi_clause: false,
        clause_count: 1,
        type_signature: nil,
        return_type: if(returns, do: format_type(returns), else: nil),
        original_ast: %{"_type" => "FunctionDef", ...},
        language_hints: %{}
      }
      
      {:ok, {:function_def, visibility, name, params, nil, body_meta}, metadata}
    end
  end
  
  defp determine_visibility(name) do
    cond do
      String.starts_with?(name, "__") and String.ends_with?(name, "__") -> :public  # Dunder methods
      String.starts_with?(name, "__") -> :private  # Name mangling
      String.starts_with?(name, "_") -> :protected  # Convention
      true -> :public
    end
  end
  
  defp extract_constructor(members) do
    constructor = Enum.find(members, fn
      {:function_def, _, "__init__", _, _, _} -> true
      _ -> false
    end)
    
    {:ok, constructor}
  end
  
  # ... rest of existing code ...
end
```

### 4.3 Ruby Adapter Updates

File: `lib/metastatic/adapters/ruby/to_meta.ex`

```elixir
defmodule Metastatic.Adapters.Ruby.ToMeta do
  # ... existing code ...
  
  # Replace language_specific class handling with container
  def transform(%{"type" => "class", "children" => [name, superclass, body]} = ast) do
    class_name = extract_constant_name(name)
    
    with {:ok, name_meta, _} <- transform(name),
         {:ok, superclass_meta, _} <- transform_or_nil(superclass),
         {:ok, members, visibility} <- transform_class_body(body) do
      
      constructor = extract_constructor(members)
      
      metadata = %{
        source_language: :ruby,
        has_state: true,
        instantiable: true,
        organizational_model: :oop,
        visibility: visibility,
        superclass: superclass_meta,
        mixins: [],  # TODO: extract includes
        traits: [],
        constructor: constructor,
        original_ast: ast,
        language_hints: %{
          ruby_attr_accessors: extract_attr_accessors(body),
          ruby_include: [],
          ruby_extend: []
        }
      }
      
      {:ok, {:container, :class, class_name, metadata, members}, metadata}
    end
  end
  
  # Ruby module handling
  def transform(%{"type" => "module", "children" => [name, body]} = ast) do
    module_name = extract_constant_name(name)
    
    with {:ok, name_meta, _} <- transform(name),
         {:ok, members, visibility} <- transform_module_body(body) do
      
      # Ruby modules can have module variables (@@var)
      has_module_state = check_for_module_variables(body)
      
      metadata = %{
        source_language: :ruby,
        has_state: has_module_state,
        instantiable: false,
        organizational_model: if(has_module_state, do: :hybrid, else: :functional),
        visibility: visibility,
        superclass: nil,
        mixins: [],
        traits: [],
        constructor: nil,
        original_ast: ast,
        language_hints: %{
          ruby_module_variables: extract_module_variables(body),
          ruby_extend: [],
          ruby_include: []
        }
      }
      
      {:ok, {:container, :module, module_name, metadata, members}, metadata}
    end
  end
  
  # Replace language_specific method handling with function_def
  def transform(%{"type" => "def", "children" => [name, args, body]} = ast) do
    method_name = if is_atom(name), do: Atom.to_string(name), else: name
    visibility = :public  # Default, will be overridden by visibility context
    
    with {:ok, params} <- extract_method_params(args),
         {:ok, body_meta, _} <- transform_or_nil(body) do
      
      metadata = %{
        decorators: [],
        is_multi_clause: false,
        clause_count: 1,
        type_signature: nil,
        return_type: nil,
        original_ast: ast,
        language_hints: %{}
      }
      
      {:ok, {:function_def, visibility, method_name, params, nil, body_meta}, metadata}
    end
  end
  
  # Helper to check for constructor
  defp extract_constructor(members) do
    Enum.find(members, fn
      {:function_def, _, "initialize", _, _, _} -> true
      _ -> false
    end)
  end
  
  # ... rest of existing code ...
end
```

---

## 5. Validation Rules

### 5.1 Extend Validator

File: `lib/metastatic/validator.ex`

```elixir
defmodule Metastatic.Validator do
  # ... existing code ...
  
  @doc """
  Validate container structure.
  """
  def validate_container({:container, container_type, name, metadata, members}, opts) do
    with :ok <- validate_container_type(container_type),
         :ok <- validate_container_name(name),
         :ok <- validate_container_metadata(metadata),
         :ok <- validate_container_members(members, opts) do
      {:ok, build_container_validation_result(container_type, name, members)}
    end
  end
  
  defp validate_container_type(type) when type in [:module, :class, :namespace], do: :ok
  defp validate_container_type(type), do: {:error, "Invalid container type: #{inspect(type)}"}
  
  defp validate_container_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_container_name(name), do: {:error, "Invalid container name: #{inspect(name)}"}
  
  defp validate_container_metadata(metadata) when is_map(metadata) do
    required_keys = [:source_language, :has_state, :visibility]
    
    missing_keys = required_keys -- Map.keys(metadata)
    
    if Enum.empty?(missing_keys) do
      :ok
    else
      {:error, "Missing required metadata keys: #{inspect(missing_keys)}"}
    end
  end
  
  defp validate_container_members(members, opts) do
    members
    |> Enum.reduce_while(:ok, fn member, :ok ->
      case validate(Document.new(member, :unknown), opts) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end
  
  @doc """
  Validate function definition structure.
  """
  def validate_function_def({:function_def, visibility, name, params, guards, body}, opts) do
    with :ok <- validate_visibility(visibility),
         :ok <- validate_function_name(name),
         :ok <- validate_params(params),
         :ok <- validate_guards(guards, opts),
         :ok <- validate_body(body, opts) do
      {:ok, build_function_validation_result(name, params, body)}
    end
  end
  
  defp validate_visibility(vis) when vis in [:public, :private, :protected], do: :ok
  defp validate_visibility(vis), do: {:error, "Invalid visibility: #{inspect(vis)}"}
  
  defp validate_function_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_function_name(name), do: {:error, "Invalid function name: #{inspect(name)}"}
  
  defp validate_params(params) when is_list(params) do
    if Enum.all?(params, &valid_param?/1) do
      :ok
    else
      {:error, "Invalid parameter list"}
    end
  end
  
  defp valid_param?(name) when is_binary(name), do: true
  defp valid_param?({:pattern, ast}), do: AST.conforms?(ast)
  defp valid_param?({:default, name, default}) when is_binary(name), do: AST.conforms?(default)
  defp valid_param?(_), do: false
  
  # ... rest of existing code ...
end
```

---

## 6. Analysis Tool Updates

### 6.1 Complexity Analysis Extension

File: `lib/metastatic/analysis/complexity.ex`

```elixir
defmodule Metastatic.Analysis.Complexity do
  # ... existing code ...
  
  @doc """
  Analyze complexity of a container (module/class).
  
  Returns aggregated complexity metrics for all member functions.
  """
  def analyze_container({:container, _type, name, metadata, members} = container, opts \\ []) do
    member_results = 
      members
      |> Enum.filter(&match?({:function_def, _, _, _, _, _}, &1))
      |> Enum.map(fn member ->
        doc = Document.new(member, metadata.source_language)
        analyze(doc, opts)
      end)
      |> Enum.map(fn
        {:ok, result} -> result
        {:error, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)
    
    total_cyclomatic = Enum.sum(Enum.map(member_results, & &1.cyclomatic))
    total_cognitive = Enum.sum(Enum.map(member_results, & &1.cognitive))
    max_nesting = Enum.max(Enum.map(member_results, & &1.max_nesting), fn -> 0 end)
    
    result = %Result{
      cyclomatic: total_cyclomatic,
      cognitive: total_cognitive,
      max_nesting: max_nesting,
      halstead: aggregate_halstead(member_results),
      loc: aggregate_loc(member_results),
      function_metrics: aggregate_function_metrics(member_results),
      warnings: aggregate_warnings(member_results),
      summary: "Container #{name}: #{length(members)} members, total complexity: #{total_cyclomatic}"
    }
    
    {:ok, result}
  end
  
  # ... rest of existing code ...
end
```

### 6.2 Duplication Detection Extension

File: `lib/metastatic/analysis/duplication.ex`

```elixir
defmodule Metastatic.Analysis.Duplication do
  # ... existing code ...
  
  @doc """
  Detect duplication between containers.
  
  Compares structural similarity of modules/classes.
  """
  def detect_container_duplication(
    {:container, type1, name1, meta1, members1},
    {:container, type2, name2, meta2, members2},
    opts \\ []
  ) do
    threshold = Keyword.get(opts, :threshold, 0.8)
    
    # Normalize container types (class ≈ module for comparison)
    type_similarity = if type1 == type2, do: 1.0, else: 0.8
    
    # Compare member functions
    member_similarity = compare_member_lists(members1, members2)
    
    # Overall similarity
    similarity = (type_similarity + member_similarity) / 2.0
    
    clone_type = determine_clone_type(similarity, name1, name2)
    
    result = %Result{
      duplicate?: similarity >= threshold,
      clone_type: clone_type,
      similarity_score: similarity,
      summary: "Containers #{name1} and #{name2}: #{Float.round(similarity * 100, 1)}% similar"
    }
    
    {:ok, result}
  end
  
  defp compare_member_lists(members1, members2) do
    # Extract function signatures
    sigs1 = extract_function_signatures(members1)
    sigs2 = extract_function_signatures(members2)
    
    # Jaccard similarity
    intersection = MapSet.intersection(MapSet.new(sigs1), MapSet.new(sigs2))
    union = MapSet.union(MapSet.new(sigs1), MapSet.new(sigs2))
    
    if MapSet.size(union) == 0 do
      0.0
    else
      MapSet.size(intersection) / MapSet.size(union)
    end
  end
  
  defp extract_function_signatures(members) do
    members
    |> Enum.filter(&match?({:function_def, _, _, _, _, _}, &1))
    |> Enum.map(fn {:function_def, _vis, name, params, _guards, _body} ->
      {name, length(params)}
    end)
  end
  
  # ... rest of existing code ...
end
```

---

## 7. Migration Path

### 7.1 Backward Compatibility

**Principle:** All existing `{:language_specific, ...}` nodes remain valid.

**Strategy:**
1. New M2.2 types coexist with M2.3 language_specific
2. Adapters gradually migrate from language_specific to new types
3. Analysis tools handle both representations
4. Validation allows both forms

**Example Compatibility Layer:**

```elixir
defmodule Metastatic.Compatibility do
  @doc """
  Convert old language_specific container to new container type.
  """
  def upgrade_container({:language_specific, lang, ast, :module_definition}) do
    # Best-effort extraction
    name = extract_name_from_old_ast(ast, lang)
    members = extract_members_from_old_ast(ast, lang)
    
    {:container, :module, name,
      %{source_language: lang, has_state: false, visibility: [], ...},
      members
    }
  end
  
  def upgrade_container(other), do: other
  
  @doc """
  Convert new container back to old language_specific (if needed).
  """
  def downgrade_container({:container, _type, _name, metadata, _members}) do
    # Use original_ast if available
    case Map.get(metadata, :original_ast) do
      nil -> {:error, "Cannot downgrade without original AST"}
      ast -> {:ok, {:language_specific, metadata.source_language, ast, :module_definition}}
    end
  end
end
```

### 7.2 Gradual Rollout

**Phase 1:** Elixir adapter (simplest, FP-only)
- Update Elixir.ToMeta to emit containers
- Update Elixir.FromMeta to consume containers
- All tests pass with new representation

**Phase 2:** Ruby adapter (hybrid OOP/FP)
- Update Ruby.ToMeta for classes and modules
- Handle visibility sections
- Test round-trip fidelity

**Phase 3:** Python adapter (pure OOP)
- Update Python.ToMeta for classes
- Handle self parameters
- Handle constructors and inheritance

**Phase 4:** Erlang & Haskell adapters
- Erlang: module forms → containers
- Haskell: module declarations → containers

**Phase 5:** Analysis tool updates
- Complexity metrics for containers
- Duplication detection for containers
- Purity analysis for containers

---

## 8. Testing Strategy

### 8.1 Unit Tests

**File:** `test/metastatic/ast_structural_test.exs`

```elixir
defmodule Metastatic.ASTStructuralTest do
  use ExUnit.Case, async: true
  
  alias Metastatic.AST
  
  describe "container conformance" do
    test "valid module container" do
      container = {:container, :module, "Math", %{has_state: false}, []}
      assert AST.conforms?(container)
    end
    
    test "valid class container with members" do
      member = {:function_def, :public, "foo", ["x"], nil, {:literal, :integer, 42}}
      container = {:container, :class, "Foo", %{has_state: true}, [member]}
      assert AST.conforms?(container)
    end
    
    test "invalid container type" do
      container = {:container, :invalid_type, "Foo", %{}, []}
      refute AST.conforms?(container)
    end
  end
  
  describe "function_def conformance" do
    test "valid public function" do
      func = {:function_def, :public, "add", ["x", "y"], nil,
        {:binary_op, :arithmetic, :+, {:variable, "x"}, {:variable, "y"}}
      }
      assert AST.conforms?(func)
    end
    
    test "function with pattern parameters" do
      func = {:function_def, :public, "factorial",
        [{:pattern, {:literal, :integer, 0}}],
        nil,
        {:literal, :integer, 1}
      }
      assert AST.conforms?(func)
    end
  end
  
  # ... more tests ...
end
```

### 8.2 Integration Tests

**File:** `test/metastatic/adapters/elixir_structural_test.exs`

```elixir
defmodule Metastatic.Adapters.ElixirStructuralTest do
  use ExUnit.Case, async: true
  
  alias Metastatic.Adapters.Elixir
  alias Metastatic.{Adapter, Document}
  
  describe "module transformation" do
    test "simple module with one function" do
      source = """
      defmodule Math do
        def add(x, y), do: x + y
      end
      """
      
      {:ok, doc} = Adapter.abstract(Elixir, source, :elixir)
      
      assert {:container, :module, "Math", metadata, members} = doc.ast
      assert metadata.source_language == :elixir
      assert metadata.has_state == false
      assert length(members) == 1
      
      [func] = members
      assert {:function_def, :public, "add", ["x", "y"], nil, _body} = func
    end
    
    test "module with public and private functions" do
      source = """
      defmodule Calculator do
        def add(x, y), do: x + y
        defp internal(x), do: x * 2
      end
      """
      
      {:ok, doc} = Adapter.abstract(Elixir, source, :elixir)
      assert {:container, :module, "Calculator", metadata, members} = doc.ast
      
      assert metadata.visibility == ["add"]  # defp not visible
      assert length(members) == 2
      
      assert Enum.any?(members, &match?({:function_def, :public, "add", _, _, _}, &1))
      assert Enum.any?(members, &match?({:function_def, :private, "internal", _, _, _}, &1))
    end
  end
  
  describe "round-trip fidelity" do
    test "module round-trips correctly" do
      source = """
      defmodule Math do
        def factorial(0), do: 1
        def factorial(n), do: n * factorial(n - 1)
      end
      """
      
      {:ok, doc} = Adapter.abstract(Elixir, source, :elixir)
      {:ok, result} = Adapter.reify(Elixir, doc)
      
      # Should produce functionally equivalent code
      # (exact syntax may differ due to formatting)
      assert String.contains?(result, "defmodule Math")
      assert String.contains?(result, "def factorial")
    end
  end
  
  # ... more tests ...
end
```

### 8.3 Cross-Language Equivalence Tests

**File:** `test/metastatic/cross_language_structural_test.exs`

```elixir
defmodule Metastatic.CrossLanguageStructuralTest do
  use ExUnit.Case, async: true
  
  alias Metastatic.Adapters.{Elixir, Ruby, Python}
  alias Metastatic.Adapter
  
  describe "cross-language container equivalence" do
    test "Elixir module ≈ Ruby module" do
      elixir_source = """
      defmodule Math do
        def add(x, y), do: x + y
      end
      """
      
      ruby_source = """
      module Math
        def self.add(x, y)
          x + y
        end
      end
      """
      
      {:ok, elixir_doc} = Adapter.abstract(Elixir, elixir_source, :elixir)
      {:ok, ruby_doc} = Adapter.abstract(Ruby, ruby_source, :ruby)
      
      assert {:container, :module, "Math", elixir_meta, elixir_members} = elixir_doc.ast
      assert {:container, :module, "Math", ruby_meta, ruby_members} = ruby_doc.ast
      
      # Both should have same member count
      assert length(elixir_members) == length(ruby_members)
      
      # Both should be stateless
      assert elixir_meta.has_state == false
      assert ruby_meta.has_state == false
    end
    
    test "Ruby class ≈ Python class" do
      ruby_source = """
      class Counter
        def initialize
          @count = 0
        end
        
        def increment
          @count += 1
        end
      end
      """
      
      python_source = """
      class Counter:
          def __init__(self):
              self.count = 0
          
          def increment(self):
              self.count += 1
      """
      
      {:ok, ruby_doc} = Adapter.abstract(Ruby, ruby_source, :ruby)
      {:ok, python_doc} = Adapter.abstract(Python, python_source, :python)
      
      assert {:container, :class, "Counter", ruby_meta, _} = ruby_doc.ast
      assert {:container, :class, "Counter", python_meta, _} = python_doc.ast
      
      # Both should have state
      assert ruby_meta.has_state == true
      assert python_meta.has_state == true
      
      # Both should have constructors
      assert ruby_meta.constructor != nil
      assert python_meta.constructor != nil
    end
  end
  
  # ... more tests ...
end
```

---

## 9. Implementation Phases

### Phase 1: Core Type System (Week 1)
**Goal:** Add new types to AST module

- [ ] Add type definitions to `ast.ex`
- [ ] Update `conforms?/1` for new types
- [ ] Update `variables/1` for new types
- [ ] Add helper functions (`container_name/1`, etc.)
- [ ] Write unit tests for type conformance
- [ ] All existing tests still pass

**Deliverable:** Core type system ready, backward compatible

### Phase 2: Elixir Adapter (Week 2)
**Goal:** First adapter producing new types

- [ ] Update `elixir/to_meta.ex` for defmodule → container
- [ ] Update `elixir/to_meta.ex` for def/defp → function_def
- [ ] Update `elixir/from_meta.ex` to consume containers
- [ ] Write adapter tests
- [ ] Verify round-trip fidelity
- [ ] Update CLI tools to handle new types

**Deliverable:** Elixir adapter fully migrated

### Phase 3: Ruby Adapter (Week 3)
**Goal:** Second adapter, handling OOP constructs

- [ ] Update `ruby/to_meta.ex` for class → container
- [ ] Update `ruby/to_meta.ex` for module → container
- [ ] Update `ruby/to_meta.ex` for def → function_def
- [ ] Handle visibility sections (private/protected)
- [ ] Update `ruby/from_meta.ex`
- [ ] Write adapter tests
- [ ] Cross-language equivalence tests (Elixir ↔ Ruby)

**Deliverable:** Ruby adapter fully migrated

### Phase 4: Python Adapter (Week 4)
**Goal:** Pure OOP adapter

- [ ] Update `python/to_meta.ex` for ClassDef → container
- [ ] Handle __init__ constructor extraction
- [ ] Update `python/to_meta.ex` for FunctionDef → function_def
- [ ] Handle self parameter semantics
- [ ] Update `python/from_meta.ex`
- [ ] Write adapter tests
- [ ] Cross-language tests (Ruby ↔ Python)

**Deliverable:** Python adapter fully migrated

### Phase 5: Erlang & Haskell (Week 5)
**Goal:** Complete all adapters

- [ ] Update Erlang adapter for -module → container
- [ ] Update Haskell adapter for module declarations
- [ ] Handle export lists properly
- [ ] Write adapter tests
- [ ] Full cross-language equivalence suite

**Deliverable:** All 5 adapters support structural layer

### Phase 6: Analysis Tools (Week 6)
**Goal:** Update all analyzers

- [ ] Update Complexity analyzer for containers
- [ ] Update Duplication detector for containers
- [ ] Update Purity analyzer for containers
- [ ] Update all CLI tools
- [ ] Integration tests for analysis tools
- [ ] Performance benchmarks

**Deliverable:** All analysis tools support structural layer

---

## Implementation Checklist

### Core Implementation
- [ ] Type definitions added to `ast.ex`
- [ ] Metadata schemas documented
- [ ] Validation rules implemented
- [ ] Backward compatibility layer

### Adapter Updates
- [ ] Elixir adapter migrated
- [ ] Ruby adapter migrated
- [ ] Python adapter migrated
- [ ] Erlang adapter migrated
- [ ] Haskell adapter migrated

### Analysis Tools
- [ ] Complexity analyzer updated
- [ ] Duplication detector updated
- [ ] Purity analyzer updated
- [ ] Dead code detector updated
- [ ] Security scanner updated
- [ ] Code smell detector updated

### Testing
- [ ] Unit tests for all new types
- [ ] Integration tests for each adapter
- [ ] Cross-language equivalence tests
- [ ] Round-trip fidelity tests
- [ ] Performance benchmarks
- [ ] Regression test suite

### Documentation
- [ ] API documentation updated
- [ ] RESEARCH.md updated
- [ ] THEORETICAL_FOUNDATIONS.md updated
- [ ] GETTING_STARTED.md updated
- [ ] README.md examples added
- [ ] CHANGELOG.md entry

---

## Success Criteria

1. **Backward Compatibility:** All existing tests pass
2. **Coverage:** 70%+ of structural constructs mapped to M2.2
3. **Fidelity:** >95% round-trip accuracy maintained
4. **Performance:** <10% overhead for new types
5. **Analysis:** All 9 analyzers work with containers
6. **Cross-Language:** Semantic equivalence detectable

---

**Document Version:** 1.0  
**Created:** 2026-01-24  
**Status:** Ready for Review  
**Estimated Effort:** 4-6 weeks  
**Risk Level:** Medium (significant refactoring, well-planned)
