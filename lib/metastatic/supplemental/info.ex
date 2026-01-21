defmodule Metastatic.Supplemental.Info do
  @moduledoc """
  Metadata structure for supplemental modules.

  Contains information about a supplemental module's capabilities,
  dependencies, and target language.

  ## Fields

  - `:name` - Unique atom identifier for this supplemental (e.g., `:pykka_actor`)
  - `:language` - Target language atom (e.g., `:python`, `:javascript`)
  - `:constructs` - List of MetaAST construct atoms this supplemental handles
  - `:requires` - List of external library dependencies with version constraints
  - `:description` - Human-readable description string

  ## Example

      %Info{
        name: :pykka_actor,
        language: :python,
        constructs: [:actor_call, :actor_cast, :spawn_actor],
        requires: ["pykka >= 3.0"],
        description: "Actor model support for Python via Pykka library"
      }
  """

  @enforce_keys [:name, :language, :constructs, :description]
  defstruct name: nil,
            language: nil,
            constructs: [],
            requires: [],
            description: nil

  @type t :: %__MODULE__{
          name: atom(),
          language: atom(),
          constructs: [atom()],
          requires: [String.t()],
          description: String.t()
        }

  @doc """
  Validates that an Info struct has all required fields properly set.

  ## Examples

      iex> info = %Info{
      ...>   name: :test,
      ...>   language: :python,
      ...>   constructs: [:actor_call],
      ...>   description: "Test"
      ...> }
      iex> Info.valid?(info)
      true

      iex> Info.valid?(%Info{name: nil, language: :python, constructs: [], description: "Test"})
      false
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = info) do
    is_atom(info.name) and info.name != nil and
      is_atom(info.language) and info.language != nil and
      is_list(info.constructs) and length(info.constructs) > 0 and
      is_binary(info.description) and byte_size(info.description) > 0
  end

  def valid?(_), do: false
end
