defmodule Metastatic.Adapters.Ruby.SubprocessTest do
  @moduledoc """
  Tests for the Ruby bridge's adapter-specific response handling.

  The Ruby bridge differs from every other bridge in two ways that
  `Metastatic.Adapter.Bridge` deliberately does *not* generalise:

    * a syntax error is reported as `{"status": "ok", "ast": null}` rather
      than an error envelope;
    * the unparser expects the AST wrapped as `{"ast": ...}`.

  Both are pinned here because getting either wrong fails silently — the
  unparser returns an empty string rather than an error.
  """

  use ExUnit.Case, async: true

  @moduletag :ruby

  alias Metastatic.Adapters.Ruby.Subprocess

  describe "parse/1" do
    test "parses valid Ruby" do
      assert {:ok, ast} = Subprocess.parse("x = 42")
      assert ast["type"] == "lvasgn"
    end

    test "reports a syntax error with the Ruby-specific wording" do
      # `ast: null` under a success envelope means "syntax error" in this
      # bridge's protocol. It must not surface as the generic
      # "Parser returned an empty AST".
      assert {:error, message} = Subprocess.parse("x = ")
      assert message == "Parse error: syntax error"
    end
  end

  describe "unparse/1" do
    test "wraps the AST as {\"ast\": ...} for the unparser" do
      # The unparser reads `parsed["ast"]`. Passing the bare AST made it emit
      # an empty string, which the round-trip conformance test caught.
      ast = %{
        "type" => "send",
        "children" => [
          %{"type" => "int", "children" => [1]},
          :+,
          %{"type" => "int", "children" => [2]}
        ]
      }

      assert {:ok, source} = Subprocess.unparse(ast)
      assert String.trim(source) != ""
    end

    test "round-trips a simple expression" do
      assert {:ok, ast} = Subprocess.parse("1 + 2")
      assert {:ok, source} = Subprocess.unparse(ast)
      assert {:ok, ast2} = Subprocess.parse(source)
      assert ast2["type"] == ast["type"]
    end
  end
end
