defmodule Metastatic.Supplemental.Python.Pykka do
  @moduledoc """
  Pykka actor library supplemental for Python.

  Provides actor model support for Python via the Pykka library, enabling
  transformation of actor-related MetaAST constructs to Pykka API calls.

  ## Supported Constructs

  - `:actor_call` - Synchronous actor message (ask)
  - `:actor_cast` - Asynchronous actor message (tell)
  - `:spawn_actor` - Create actor instance

  ## Requirements

  - pykka >= 3.0

  ## Example Transformations

      # Elixir/Erlang
      GenServer.call(actor, :get_state, 5000)

      # MetaAST
      {:actor_call, actor, :get_state, 5000}

      # Python (via Pykka)
      actor_ref.ask({'type': 'get_state'}, timeout=5.0)
  """

  @behaviour Metastatic.Supplemental

  alias Metastatic.Supplemental.Info

  @impl true
  def info do
    %Info{
      name: :pykka_actor,
      language: :python,
      constructs: [:actor_call, :actor_cast, :spawn_actor],
      requires: ["pykka >= 3.0"],
      description: "Actor model support for Python via Pykka library"
    }
  end

  @impl true
  def transform({:actor_call, actor, message, timeout}, :python, metadata) do
    with {:ok, actor_py} <- transform_actor(actor, metadata),
         {:ok, message_py} <- transform_message(message, metadata),
         {:ok, timeout_py} <- transform_timeout(timeout) do
      # Build: actor_ref.ask(message, timeout=timeout_seconds)
      ask_call = %{
        "_type" => "Call",
        "func" => %{
          "_type" => "Attribute",
          "value" => actor_py,
          "attr" => "ask",
          "ctx" => %{"_type" => "Load"}
        },
        "args" => [message_py],
        "keywords" => [
          %{
            "_type" => "keyword",
            "arg" => "timeout",
            "value" => timeout_py
          }
        ]
      }

      {:ok, ask_call}
    end
  end

  def transform({:actor_cast, actor, message}, :python, metadata) do
    with {:ok, actor_py} <- transform_actor(actor, metadata),
         {:ok, message_py} <- transform_message(message, metadata) do
      # Build: actor_ref.tell(message)
      tell_call = %{
        "_type" => "Call",
        "func" => %{
          "_type" => "Attribute",
          "value" => actor_py,
          "attr" => "tell",
          "ctx" => %{"_type" => "Load"}
        },
        "args" => [message_py],
        "keywords" => []
      }

      {:ok, tell_call}
    end
  end

  def transform({:spawn_actor, actor_class, args}, :python, metadata) do
    with {:ok, class_py} <- transform_actor_class(actor_class, metadata),
         {:ok, args_py} <- transform_args(args, metadata) do
      # Build: ActorClass.start(*args)
      start_call = %{
        "_type" => "Call",
        "func" => %{
          "_type" => "Attribute",
          "value" => class_py,
          "attr" => "start",
          "ctx" => %{"_type" => "Load"}
        },
        "args" => args_py,
        "keywords" => []
      }

      {:ok, start_call}
    end
  end

  def transform(_, _, _), do: :error

  # Private helper functions

  defp transform_actor({:variable, name}, _metadata) do
    {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Load"}}}
  end

  defp transform_actor(actor, _metadata) do
    {:error, "Unsupported actor reference: #{inspect(actor)}"}
  end

  defp transform_message({:literal, :atom, atom_value}, _metadata) do
    # Convert atom to Python dict: {'type': 'atom_value'}
    message_dict = %{
      "_type" => "Dict",
      "keys" => [
        %{"_type" => "Constant", "value" => "type", "kind" => nil}
      ],
      "values" => [
        %{"_type" => "Constant", "value" => Atom.to_string(atom_value), "kind" => nil}
      ]
    }

    {:ok, message_dict}
  end

  defp transform_message({:literal, _type, value}, _metadata) do
    {:ok, %{"_type" => "Constant", "value" => value, "kind" => nil}}
  end

  defp transform_message({:variable, name}, _metadata) do
    {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Load"}}}
  end

  defp transform_message(message, _metadata) do
    {:error, "Unsupported message format: #{inspect(message)}"}
  end

  defp transform_timeout(timeout_ms) when is_integer(timeout_ms) do
    # Convert milliseconds to seconds (Python uses seconds)
    timeout_seconds = timeout_ms / 1000.0
    {:ok, %{"_type" => "Constant", "value" => timeout_seconds, "kind" => nil}}
  end

  defp transform_timeout(timeout) do
    {:error, "Unsupported timeout: #{inspect(timeout)}"}
  end

  defp transform_actor_class({:variable, name}, _metadata) do
    {:ok, %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Load"}}}
  end

  defp transform_actor_class(class, _metadata) do
    {:error, "Unsupported actor class: #{inspect(class)}"}
  end

  defp transform_args(args, _metadata) when is_list(args) do
    # Simple transformation - would need full MetaAST->Python for complex args
    result =
      Enum.map(args, fn
        {:literal, _type, value} ->
          %{"_type" => "Constant", "value" => value, "kind" => nil}

        {:variable, name} ->
          %{"_type" => "Name", "id" => name, "ctx" => %{"_type" => "Load"}}

        _ ->
          nil
      end)

    if Enum.any?(result, &is_nil/1) do
      {:error, "Unsupported argument types"}
    else
      {:ok, result}
    end
  end
end
