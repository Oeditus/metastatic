defmodule Metastatic.Supplemental.Error do
  @moduledoc """
  Error types for supplemental module system.

  Provides structured errors for common supplemental-related failures.
  """

  defmodule MissingSupplementalError do
    @moduledoc """
    Raised when a required supplemental module is not registered.

    Indicates that transformation requires a supplemental that hasn't been
    registered in the system.
    """

    defexception [:construct, :language, :message]

    @impl true
    def exception(opts) do
      construct = Keyword.fetch!(opts, :construct)
      language = Keyword.fetch!(opts, :language)

      message =
        "No supplemental registered for construct #{inspect(construct)} " <>
          "in language #{inspect(language)}. " <>
          "Register an appropriate supplemental module or implement native support."

      %__MODULE__{
        construct: construct,
        language: language,
        message: message
      }
    end
  end

  defmodule IncompatibleSupplementalError do
    @moduledoc """
    Raised when a supplemental module's dependencies are incompatible.

    Indicates version mismatches or missing external library dependencies.
    """

    defexception [:supplemental, :required, :available, :message]

    @impl true
    def exception(opts) do
      supplemental = Keyword.fetch!(opts, :supplemental)
      required = Keyword.fetch!(opts, :required)
      available = Keyword.get(opts, :available, "not installed")

      message =
        "Supplemental #{inspect(supplemental)} requires #{required} " <>
          "but found #{available}. " <>
          "Install or upgrade the required dependency."

      %__MODULE__{
        supplemental: supplemental,
        required: required,
        available: available,
        message: message
      }
    end
  end

  defmodule UnsupportedConstructError do
    @moduledoc """
    Raised when a MetaAST construct has no transformation path.

    Indicates the construct is neither natively supported by the adapter
    nor handled by any registered supplemental.
    """

    defexception [:construct, :language, :message]

    @impl true
    def exception(opts) do
      construct = Keyword.fetch!(opts, :construct)
      language = Keyword.fetch!(opts, :language)

      message =
        "Construct #{inspect(construct)} is not supported in #{inspect(language)}. " <>
          "No native adapter support or registered supplemental available."

      %__MODULE__{
        construct: construct,
        language: language,
        message: message
      }
    end
  end

  defmodule ConflictError do
    @moduledoc """
    Raised when multiple supplementals attempt to handle the same construct.

    Indicates ambiguity in which supplemental should transform a construct.
    """

    defexception [:construct, :language, :modules, :message]

    @impl true
    def exception(opts) do
      construct = Keyword.fetch!(opts, :construct)
      language = Keyword.fetch!(opts, :language)
      modules = Keyword.fetch!(opts, :modules)

      message =
        "Multiple supplementals registered for construct #{inspect(construct)} " <>
          "in language #{inspect(language)}: #{inspect(modules)}. " <>
          "Only one supplemental per construct is allowed."

      %__MODULE__{
        construct: construct,
        language: language,
        modules: modules,
        message: message
      }
    end
  end
end
