defmodule Metastatic.Adapters.Lfe.Printer do
  @moduledoc """
  Sexpr → LFE source, using LFE's own pretty printer.

  LFE ships `lfe_io:prettyprint1/1`, which returns an iolist for a single
  form. Using it (rather than writing a printer) is what keeps
  `unparse/1` faithful: quoting, atom escaping (`'io:format'`), string
  syntax and the `#(...)` tuple form are all LFE's own conventions, and any
  hand-rolled printer would drift from them.

  ## Why `prettyprint1/1` and not `prettyprint/1`

  `prettyprint/1` writes to standard output and returns `ok`; only the
  `…1` variants return the text. `print1/1` also returns text, but it
  prints strings as character lists (`"~p~n"` becomes `(126 112 126 110)`),
  which would silently change the meaning of every string literal. So
  `prettyprint1/1` is the only correct choice.

  ## Form separation

  `prettyprint1/1` renders one form with no trailing newline, so forms are
  joined with `"\\n"` and the output ends with a single newline. Blank lines
  between forms are not preserved — formatting normalises, semantics do not.
  """

  # LFE is optional; print/1 checks availability before invoking its printer.
  @compile {:no_warn_undefined, {:lfe_io, :prettyprint1, 1}}

  @doc """
  Renders a list of `{sexpr, line}` forms as LFE source.

  Accepts a bare sexpr as well, so `unparse/1` works on both the file-level
  M1 (a list of forms) and a single expression.

  ## Examples

      iex> Metastatic.Adapters.Lfe.Printer.print([{[:defun, :add, [:a, :b], [:"+", :a, :b]], 1}])
      {:ok, "(defun add (a b) (+ a b))\\n"}

      iex> Metastatic.Adapters.Lfe.Printer.print({42, 1})
      {:ok, "42\\n"}
  """
  @spec print([{term(), integer()}] | term()) :: {:ok, String.t()} | {:error, String.t()}
  def print(forms) do
    with :ok <- ensure_loaded() do
      render(forms)
    end
  end

  @doc """
  Returns `true` when LFE's printer is usable in this VM.

  ## Examples

      iex> is_boolean(Metastatic.Adapters.Lfe.Printer.available?())
      true
  """
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(:lfe_io)

  # ----- Private -----

  defp ensure_loaded do
    if available?(), do: :ok, else: {:error, "LFE printer unavailable: :lfe_io is not loadable"}
  end

  # A list of `{sexpr, line}` pairs is the file-level shape.
  defp render([]), do: {:ok, ""}

  defp render([{_sexpr, line} | _] = forms) when is_integer(line) do
    forms
    |> Enum.map(fn {sexpr, _line} -> sexpr end)
    |> render_forms()
  end

  # `FromMeta` returns a list of top-level forms, so a list of lists is a file.
  # A single sexpr — including a call like `[:+, 1, 2]` — is one form and must
  # not be `List.wrap`ped: that would split the call into three forms and
  # print `+\n1\n2`.
  defp render([[_sexpr | _] | _] = forms), do: render_forms(forms)

  defp render(sexpr), do: render_forms([sexpr])

  defp render_forms(sexprs) do
    text =
      sexprs
      |> Enum.map_join("\n", &render_one/1)
      |> Kernel.<>("\n")

    {:ok, text}
  rescue
    error -> {:error, "LFE printer failed: #{Exception.message(error)}"}
  catch
    error -> {:error, "LFE printer failed: #{inspect(error, limit: 5)}"}
  end

  defp render_one(sexpr) do
    sexpr
    |> :lfe_io.prettyprint1()
    |> IO.iodata_to_binary()
  end
end
