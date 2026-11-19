defmodule Metastatic.Adapters.LfeConformanceTest do
  @moduledoc """
  Uniform conformance suite for the LFE adapter (see
  `Metastatic.Test.AdapterConformance`).

  The suite parses, abstracts, reifies and unparses real source, so it needs
  LFE's reader and printer to be loadable. When the toolchain is absent the
  whole module is skipped rather than failed — LFE is flagged `experimental`
  in the built-in registry because its modules are not part of OTP. The
  development/test dependency supplies them in this repository and in CI.
  """
  use ExUnit.Case, async: true

  @moduletag :lfe

  alias Metastatic.Adapters.Lfe

  if Lfe.available?() do
    use Metastatic.Test.AdapterConformance,
      adapter: Lfe,
      language: :lfe,
      # A snippet the adapter can parse...
      sample: "(+ 1 2)",
      # ...and a MetaAST it can reify back to source.
      sample_ast:
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]},
      # `this is not valid @@#$%` is *valid* LFE — it reads as five atoms and
      # a symbol, because nearly any character sequence is a legal Lisp atom.
      # An unbalanced delimiter is the reliable way to make the reader fail.
      invalid_sample: "(defun broken"
  else
    @tag :skip
    test "LFE toolchain unavailable — conformance suite skipped" do
      flunk("""
      The LFE toolchain is not available, so the conformance suite cannot run.

      LFE is not part of OTP. Install it with:

          git clone https://github.com/lfe/lfe.git && cd lfe && make

      then put its `ebin` on the code path:

          elixir -pa /path/to/lfe/ebin ...

      or vendor it at `priv/parsers/lfe/ebin` inside the host application.
      """)
    end
  end
end
