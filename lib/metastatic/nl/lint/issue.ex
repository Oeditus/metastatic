defmodule Metastatic.NL.Lint.Issue do
  @moduledoc """
  Represents a single prose linting issue found in an NL-MetaAST document.
  """

  @type severity :: :warning | :refactor | :info | :error

  @type t :: %__MODULE__{
          rule: atom(),
          message: String.t(),
          line: pos_integer() | nil,
          col: pos_integer() | nil,
          severity: severity(),
          suggestion: String.t() | nil
        }

  defstruct [:rule, :message, :line, :col, severity: :warning, suggestion: nil]

  @doc """
  Constructs a new Issue struct.
  """
  @spec new(atom(), String.t(), keyword()) :: t()
  def new(rule, message, opts \\ []) do
    %__MODULE__{
      rule: rule,
      message: message,
      line: Keyword.get(opts, :line),
      col: Keyword.get(opts, :col),
      severity: Keyword.get(opts, :severity, :warning),
      suggestion: Keyword.get(opts, :suggestion)
    }
  end
end
