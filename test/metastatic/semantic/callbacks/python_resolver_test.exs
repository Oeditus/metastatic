defmodule Metastatic.Semantic.Callbacks.PythonResolverTest do
  use ExUnit.Case, async: true

  alias Metastatic.Semantic.Callbacks
  alias Metastatic.Semantic.Callbacks.PythonResolver

  describe "resolve_from_decorators/1" do
    test "matches Flask route decorator" do
      assert {:ok, %{framework: :flask, domain: :http}} =
               PythonResolver.resolve_from_decorators(["app.route"])
    end

    test "matches Flask HTTP method decorators" do
      for method <- ~w[app.get app.post app.put app.delete app.patch] do
        assert {:ok, %{framework: :flask, domain: :http}} =
                 PythonResolver.resolve_from_decorators([method])
      end
    end

    test "matches FastAPI router decorators" do
      for method <- ~w[router.get router.post router.put router.delete] do
        assert {:ok, %{framework: :fastapi, domain: :http}} =
                 PythonResolver.resolve_from_decorators([method])
      end
    end

    test "matches Celery task decorators" do
      assert {:ok, %{framework: :celery, domain: :queue}} =
               PythonResolver.resolve_from_decorators(["celery.task"])

      assert {:ok, %{framework: :celery, domain: :queue}} =
               PythonResolver.resolve_from_decorators(["shared_task"])
    end

    test "matches Django auth decorators" do
      assert {:ok, %{framework: :django, domain: :auth}} =
               PythonResolver.resolve_from_decorators(["login_required"])

      assert {:ok, %{framework: :django, domain: :auth}} =
               PythonResolver.resolve_from_decorators(["permission_required"])
    end

    test "matches pytest fixture" do
      assert {:ok, %{framework: :pytest, domain: nil}} =
               PythonResolver.resolve_from_decorators(["pytest.fixture"])
    end

    test "matches abstractmethod" do
      assert {:ok, %{framework: :abc, domain: nil}} =
               PythonResolver.resolve_from_decorators(["abstractmethod"])
    end

    test "returns first match when multiple decorators present" do
      assert {:ok, %{framework: :django, domain: :auth}} =
               PythonResolver.resolve_from_decorators(["login_required", "app.route"])
    end

    test "returns :no_match for unknown decorators" do
      assert :no_match = PythonResolver.resolve_from_decorators(["my_custom_decorator"])
    end

    test "returns :no_match for empty list" do
      assert :no_match = PythonResolver.resolve_from_decorators([])
    end

    test "handles prefix matching for decorated routes" do
      assert {:ok, %{framework: :flask}} =
               PythonResolver.resolve_from_decorators(["app.route('/users')"])
    end
  end

  describe "resolve_all_decorators/1" do
    test "returns all matching specs" do
      specs = PythonResolver.resolve_all_decorators(["login_required", "app.route"])

      assert [_, _] = specs
      assert %{framework: :django, domain: :auth} in specs
      assert %{framework: :flask, domain: :http} in specs
    end

    test "returns empty list when no matches" do
      assert [] = PythonResolver.resolve_all_decorators(["unknown_deco"])
    end
  end

  describe "resolve_base_class/1" do
    test "resolves Django View" do
      assert {:ok, "View"} = PythonResolver.resolve_base_class("View")
    end

    test "resolves Django class-based views" do
      for view <- ~w[TemplateView ListView DetailView CreateView UpdateView DeleteView FormView] do
        assert {:ok, "View"} = PythonResolver.resolve_base_class(view)
      end
    end

    test "resolves DRF views" do
      assert {:ok, "APIView"} = PythonResolver.resolve_base_class("APIView")
      assert {:ok, "ModelViewSet"} = PythonResolver.resolve_base_class("ModelViewSet")
    end

    test "resolves Flask MethodView" do
      assert {:ok, "MethodView"} = PythonResolver.resolve_base_class("MethodView")
    end

    test "resolves Celery Task" do
      assert {:ok, "celery.Task"} = PythonResolver.resolve_base_class("celery.Task")
      assert {:ok, "celery.Task"} = PythonResolver.resolve_base_class("Task")
    end

    test "resolves Django Model" do
      assert {:ok, "Model"} = PythonResolver.resolve_base_class("Model")
      assert {:ok, "Model"} = PythonResolver.resolve_base_class("models.Model")
    end

    test "returns :no_match for unknown classes" do
      assert :no_match = PythonResolver.resolve_base_class("object")
      assert :no_match = PythonResolver.resolve_base_class("SomeRandomClass")
    end
  end

  describe "resolve_base_classes/1" do
    test "resolves multiple bases" do
      behaviours = PythonResolver.resolve_base_classes(["View", "object"])
      assert ["View"] = behaviours
    end

    test "deduplicates resolved behaviours" do
      behaviours = PythonResolver.resolve_base_classes(["TemplateView", "View"])
      assert ["View"] = behaviours
    end

    test "returns empty list for no matches" do
      assert [] = PythonResolver.resolve_base_classes(["object", "str"])
    end
  end

  describe "register_base_class_callbacks/0" do
    setup do
      Callbacks.clear()
      PythonResolver.register_base_class_callbacks()
      :ok
    end

    test "registers Django View HTTP callbacks" do
      for method <- ~w[get post put delete] do
        assert Callbacks.callback?(:python, "View", method, nil)
      end
    end

    test "registers DRF ViewSet actions" do
      for action <- ~w[list retrieve create update destroy] do
        assert Callbacks.callback?(:python, "ModelViewSet", action, nil)
      end
    end

    test "registers Flask MethodView methods" do
      for method <- ~w[get post put delete] do
        assert Callbacks.callback?(:python, "MethodView", method, nil)
      end
    end

    test "registers Django Model callbacks" do
      assert Callbacks.callback?(:python, "Model", "save", nil)
      assert Callbacks.callback?(:python, "Model", "delete", nil)
    end

    test "registers DRF Serializer callbacks" do
      assert Callbacks.callback?(:python, "Serializer", "validate", nil)
      assert Callbacks.callback?(:python, "Serializer", "create", nil)
    end
  end
end
