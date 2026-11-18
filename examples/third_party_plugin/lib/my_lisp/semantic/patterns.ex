defmodule MyLisp.Semantic.Patterns do
  @moduledoc """
  Semantic patterns for the `:lisp` language.

  This is the host-side half of `Metastatic.Semantic.ensure_registered/0`: the
  module is listed in `config :metastatic, :semantic, pattern_providers:` and
  Metastatic calls `register_all/0` at boot (and again before the first
  abstraction), so the patterns survive a VM restart and a
  `Patterns.clear_all/0` in a test suite.

  Without this, `Enricher.enrich_tree(ast, :lisp)` would run and find nothing —
  silently, with no error.
  """

  alias Metastatic.Semantic.Patterns

  @doc """
  Registers the Lisp patterns.

  ## Examples

      iex> MyLisp.Semantic.Patterns.register_all()
      :ok
      iex> Metastatic.Semantic.Patterns.get_patterns(:db, :lisp) != []
      true
  """
  @spec register_all() :: :ok
  def register_all do
    # A toy ORM, to show the shape a real provider would use.
    Patterns.register(:db, :lisp, [
      {"db-find", %{operation: :retrieve, framework: :lisp_db, extract_target: :first_arg}},
      {"db-all", %{operation: :retrieve_all, framework: :lisp_db, extract_target: :first_arg}},
      {"db-save", %{operation: :update, framework: :lisp_db, extract_target: :first_arg}},
      {"db-delete", %{operation: :delete, framework: :lisp_db, extract_target: :first_arg}}
    ])

    Patterns.register(:http, :lisp, [
      {"http-get", %{operation: :request, framework: :lisp_http, extract_target: :first_arg}},
      {"http-post", %{operation: :request, framework: :lisp_http, extract_target: :first_arg}}
    ])

    :ok
  end
end
