defmodule Metastatic.Semantic.Callbacks.PythonResolver do
  @moduledoc """
  Resolves Python callbacks via decorator patterns and class inheritance.

  Python uses two main mechanisms that signal callback relationships:

  1. **Decorators** on functions/methods (e.g., `@app.route`, `@celery.task`,
     `@abstractmethod`) indicate the function serves as a callback for a
     framework or protocol.

  2. **Base classes** on class definitions (e.g., `class MyView(View)`) indicate
     the class implements a framework interface whose methods are callbacks.

  ## Decorator Resolution

      iex> PythonResolver.resolve_from_decorators(["app.route"])
      {:ok, %{framework: :flask, domain: :http}}

      iex> PythonResolver.resolve_from_decorators(["some_custom_decorator"])
      :no_match

  ## Base Class Resolution

      iex> PythonResolver.resolve_base_class("View")
      {:ok, "View"}

      iex> PythonResolver.resolve_base_class("SomeRandomClass")
      :no_match
  """

  alias Metastatic.Semantic.Callbacks

  @typedoc "Callback specification from decorator resolution"
  @type decorator_spec :: %{framework: atom(), domain: atom() | nil}

  # Decorator patterns mapped to callback specs.
  # Patterns are matched as prefixes or exact strings.
  @decorator_patterns [
    # Flask route decorators
    {"app.route", %{framework: :flask, domain: :http}},
    {"app.get", %{framework: :flask, domain: :http}},
    {"app.post", %{framework: :flask, domain: :http}},
    {"app.put", %{framework: :flask, domain: :http}},
    {"app.delete", %{framework: :flask, domain: :http}},
    {"app.patch", %{framework: :flask, domain: :http}},
    {"blueprint.route", %{framework: :flask, domain: :http}},
    {"blueprint.get", %{framework: :flask, domain: :http}},
    {"blueprint.post", %{framework: :flask, domain: :http}},
    # FastAPI
    {"router.get", %{framework: :fastapi, domain: :http}},
    {"router.post", %{framework: :fastapi, domain: :http}},
    {"router.put", %{framework: :fastapi, domain: :http}},
    {"router.delete", %{framework: :fastapi, domain: :http}},
    {"router.patch", %{framework: :fastapi, domain: :http}},
    # Celery
    {"celery.task", %{framework: :celery, domain: :queue}},
    {"shared_task", %{framework: :celery, domain: :queue}},
    {"app.task", %{framework: :celery, domain: :queue}},
    # Dramatiq
    {"dramatiq.actor", %{framework: :dramatiq, domain: :queue}},
    # Django auth decorators
    {"login_required", %{framework: :django, domain: :auth}},
    {"permission_required", %{framework: :django, domain: :auth}},
    {"user_passes_test", %{framework: :django, domain: :auth}},
    # Django admin
    {"admin.register", %{framework: :django, domain: nil}},
    # Django URL routing
    {"require_http_methods", %{framework: :django, domain: :http}},
    # Pytest
    {"pytest.fixture", %{framework: :pytest, domain: nil}},
    {"pytest.mark.parametrize", %{framework: :pytest, domain: nil}},
    # ABC
    {"abstractmethod", %{framework: :abc, domain: nil}},
    {"staticmethod", %{framework: :python, domain: nil}},
    {"classmethod", %{framework: :python, domain: nil}},
    {"property", %{framework: :python, domain: nil}},
    # Scheduler
    {"periodic_task", %{framework: :scheduler, domain: :queue}}
  ]

  # Known base classes that signal callback relationships.
  # Maps base class name to the behaviour name for Callbacks registry.
  @known_base_classes %{
    # Django
    "View" => "View",
    "TemplateView" => "View",
    "ListView" => "View",
    "DetailView" => "View",
    "CreateView" => "View",
    "UpdateView" => "View",
    "DeleteView" => "View",
    "FormView" => "View",
    "ModelViewSet" => "ModelViewSet",
    "ViewSet" => "ViewSet",
    "APIView" => "APIView",
    "GenericAPIView" => "APIView",
    # Flask
    "MethodView" => "MethodView",
    "Resource" => "Resource",
    # Celery
    "celery.Task" => "celery.Task",
    "Task" => "celery.Task",
    # Django models
    "Model" => "Model",
    "models.Model" => "Model",
    # Django admin
    "ModelAdmin" => "ModelAdmin",
    "admin.ModelAdmin" => "ModelAdmin",
    # Django forms
    "Form" => "Form",
    "ModelForm" => "Form",
    # Django middleware
    "MiddlewareMixin" => "MiddlewareMixin",
    # Django management commands
    "BaseCommand" => "BaseCommand",
    "management.BaseCommand" => "BaseCommand",
    # Django REST framework serializers
    "Serializer" => "Serializer",
    "ModelSerializer" => "Serializer",
    # Dramatiq
    "dramatiq.Actor" => "dramatiq.Actor"
  }

  @doc """
  Resolves callback metadata from a list of Python decorator names.

  Checks each decorator against the known decorator patterns and returns
  the first matching callback spec.

  ## Examples

      iex> PythonResolver.resolve_from_decorators(["app.route"])
      {:ok, %{framework: :flask, domain: :http}}

      iex> PythonResolver.resolve_from_decorators(["login_required", "app.route"])
      {:ok, %{framework: :django, domain: :auth}}

      iex> PythonResolver.resolve_from_decorators(["my_custom_deco"])
      :no_match
  """
  @spec resolve_from_decorators([String.t()]) :: {:ok, decorator_spec()} | :no_match
  def resolve_from_decorators(decorators) when is_list(decorators) do
    Enum.find_value(decorators, :no_match, fn decorator ->
      case match_decorator(decorator) do
        nil -> nil
        spec -> {:ok, spec}
      end
    end)
  end

  @doc """
  Resolves all callback specs from a list of decorators.

  Unlike `resolve_from_decorators/1` which returns the first match,
  this returns all matching specs.

  ## Examples

      iex> specs = PythonResolver.resolve_all_decorators(["login_required", "app.route"])
      iex> length(specs) >= 2
      true
  """
  @spec resolve_all_decorators([String.t()]) :: [decorator_spec()]
  def resolve_all_decorators(decorators) when is_list(decorators) do
    Enum.flat_map(decorators, fn decorator ->
      case match_decorator(decorator) do
        nil -> []
        spec -> [spec]
      end
    end)
  end

  @doc """
  Checks whether a Python base class name is a known behaviour source.

  Returns `{:ok, behaviour_name}` if the base class maps to a known
  behaviour, or `:no_match` otherwise.

  ## Examples

      iex> PythonResolver.resolve_base_class("View")
      {:ok, "View"}

      iex> PythonResolver.resolve_base_class("object")
      :no_match
  """
  @spec resolve_base_class(String.t()) :: {:ok, String.t()} | :no_match
  def resolve_base_class(class_name) when is_binary(class_name) do
    case Map.get(@known_base_classes, class_name) do
      nil -> :no_match
      behaviour -> {:ok, behaviour}
    end
  end

  @doc """
  Resolves all known behaviours from a list of base class names.

  Returns the list of behaviour name strings that the enricher should
  use to annotate callbacks.

  ## Examples

      iex> PythonResolver.resolve_base_classes(["View", "object"])
      ["View"]
  """
  @spec resolve_base_classes([String.t()]) :: [String.t()]
  def resolve_base_classes(bases) when is_list(bases) do
    Enum.flat_map(bases, fn base ->
      case resolve_base_class(base) do
        {:ok, behaviour} -> [behaviour]
        :no_match -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc """
  Ensures that all known Python base class behaviours are registered
  in the Callbacks registry with their standard callbacks.

  Called during `register_builtins/0` to populate the registry with
  Python class-based callback patterns.
  """
  @spec register_base_class_callbacks() :: :ok
  def register_base_class_callbacks do
    # Django views -- HTTP method callbacks
    for method <- ~w[get post put patch delete head options] do
      Callbacks.register(:python, "View", method, nil, %{framework: :django, domain: :http})
      Callbacks.register(:python, "APIView", method, nil, %{framework: :drf, domain: :http})
    end

    # Django ViewSets
    for action <- ~w[list retrieve create update partial_update destroy] do
      Callbacks.register(:python, "ViewSet", action, nil, %{framework: :drf, domain: :http})
      Callbacks.register(:python, "ModelViewSet", action, nil, %{framework: :drf, domain: :http})
    end

    # Flask MethodView
    for method <- ~w[get post put patch delete] do
      Callbacks.register(:python, "MethodView", method, nil, %{framework: :flask, domain: :http})
    end

    # Flask-RESTful Resource
    for method <- ~w[get post put patch delete] do
      Callbacks.register(:python, "Resource", method, nil, %{framework: :flask, domain: :http})
    end

    # Django Model callbacks
    for func <- ~w[save delete clean full_clean] do
      Callbacks.register(:python, "Model", func, nil, %{framework: :django, domain: :db})
    end

    # Django ModelAdmin
    for func <- ~w[save_model delete_model get_queryset] do
      Callbacks.register(:python, "ModelAdmin", func, nil, %{framework: :django, domain: nil})
    end

    # Django Form
    for func <- ~w[clean is_valid save] do
      Callbacks.register(:python, "Form", func, nil, %{framework: :django, domain: nil})
    end

    # Django Middleware
    Callbacks.register(:python, "MiddlewareMixin", "process_request", nil, %{
      framework: :django,
      domain: :http
    })

    Callbacks.register(:python, "MiddlewareMixin", "process_response", nil, %{
      framework: :django,
      domain: :http
    })

    # Django management commands
    Callbacks.register(:python, "BaseCommand", "handle", nil, %{
      framework: :django,
      domain: nil
    })

    # DRF Serializer
    for func <- ~w[validate create update to_representation] do
      Callbacks.register(:python, "Serializer", func, nil, %{framework: :drf, domain: nil})
    end

    # Celery task
    Callbacks.register(:python, "celery.Task", "run", nil, %{framework: :celery, domain: :queue})

    # Dramatiq actor
    Callbacks.register(:python, "dramatiq.Actor", "perform", nil, %{
      framework: :dramatiq,
      domain: :queue
    })

    :ok
  end

  # ----- Private -----

  # Match a decorator name against known patterns.
  # Tries exact match first, then prefix match.
  defp match_decorator(decorator) when is_binary(decorator) do
    # Exact match
    case Enum.find(@decorator_patterns, fn {pattern, _} -> pattern == decorator end) do
      {_, spec} ->
        spec

      nil ->
        # Prefix match (e.g., "app.route('/path')" starts with "app.route")
        case Enum.find(@decorator_patterns, fn {pattern, _} ->
               String.starts_with?(decorator, pattern)
             end) do
          {_, spec} -> spec
          nil -> nil
        end
    end
  end
end
