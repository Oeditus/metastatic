defmodule Metastatic.Adapter.BridgeTest do
  @moduledoc """
  Tests for the shared subprocess-bridge protocol.

  `Bridge.decode/1` exists because nine adapters had grown nine slightly
  different decoders, each accepting a different subset of the response
  shapes below. These tests pin every shape so a future adapter cannot
  quietly narrow the contract again.
  """

  use ExUnit.Case, async: true

  alias Metastatic.Adapter.Bridge

  describe "decode/1 — canonical envelope" do
    test "extracts the ast payload" do
      assert {:ok, %{"type" => "File"}} =
               Bridge.decode(~s({"ok": true, "ast": {"type": "File"}}))
    end

    test "extracts the source payload" do
      assert {:ok, "x + 5"} = Bridge.decode(~s({"ok": true, "source": "x + 5"}))
    end

    test "treats a null ast as an error, not a successful nil parse" do
      # Agda's bridge emits `{"status": "ok", "ast": null}` for empty input.
      # Returning `{:ok, nil}` there made the caller believe it had parsed
      # the atom `nil`.
      assert {:error, "Parser returned an empty AST"} =
               Bridge.decode(~s({"ok": true, "ast": null}))
    end

    test "formats a string error" do
      assert {:error, "boom"} = Bridge.decode(~s({"ok": false, "error": "boom"}))
    end

    test "formats a structured error with a line number" do
      payload = ~s({"ok": false, "error": {"type": "SyntaxError", "msg": "bad", "line": 3}})

      assert {:error, "SyntaxError at line 3: bad"} = Bridge.decode(payload)
    end

    test "formats a structured error without a line number" do
      payload = ~s({"ok": false, "error": {"type": "SyntaxError", "msg": "bad"}})

      assert {:error, "SyntaxError: bad"} = Bridge.decode(payload)
    end
  end

  describe "decode/1 — legacy `status` envelope" do
    test "accepts status/ok with an ast" do
      assert {:ok, %{"k" => 1}} = Bridge.decode(~s({"status": "ok", "ast": {"k": 1}}))
    end

    test "accepts status/error with errorMessage" do
      assert {:error, "nope"} = Bridge.decode(~s({"status": "error", "errorMessage": "nope"}))
    end

    test "falls back to a generic message when status/error carries none" do
      assert {:error, "parse error"} = Bridge.decode(~s({"status": "error"}))
    end
  end

  describe "decode/1 — envelope-less payloads" do
    test "accepts a bare ast object" do
      assert {:ok, %{"type" => "File"}} = Bridge.decode(~s({"ast": {"type": "File"}}))
    end

    test "accepts a bare source object" do
      assert {:ok, "1 + 1"} = Bridge.decode(~s({"source": "1 + 1"}))
    end

    test "accepts a bare JSON string" do
      assert {:ok, "1 + 1"} = Bridge.decode(~s("1 + 1"))
    end
  end

  describe "decode/1 — malformed input" do
    test "reports invalid JSON" do
      assert {:error, "JSON decode failed: " <> _} = Bridge.decode("not json")
    end

    test "reports an envelope with neither payload" do
      assert {:error, "Parser response carried no AST or source: " <> _} =
               Bridge.decode(~s({"ok": true}))
    end

    test "reports an unrecognised object" do
      assert {:error, "Unexpected parser output: " <> _} =
               Bridge.decode(~s({"something": "else"}))
    end
  end

  describe "format_error/1" do
    test "passes strings through" do
      assert Bridge.format_error("boom") == "boom"
    end

    test "inspects atoms" do
      assert Bridge.format_error(:enoent) == ":enoent"
    end

    test "formats type/msg/line" do
      assert Bridge.format_error(%{"type" => "E", "msg" => "m", "line" => 2}) == "E at line 2: m"
    end

    test "formats type/msg" do
      assert Bridge.format_error(%{"type" => "E", "msg" => "m"}) == "E: m"
    end

    test "formats error/line" do
      assert Bridge.format_error(%{"error" => "m", "line" => 7}) == "m at line 7"
    end

    test "formats a bare message" do
      assert Bridge.format_error(%{"msg" => "m"}) == "m"
    end

    test "inspects anything else" do
      assert Bridge.format_error([1, 2]) == "[1, 2]"
    end
  end

  describe "run/4" do
    test "runs the executable and decodes its output" do
      assert {:ok, 1} = Bridge.run("cat", [], ~s({"ok": true, "ast": 1}), ext: ".json")
    end

    test "reports a missing executable without raising" do
      assert {:error, "Failed to run bridge: " <> _} =
               Bridge.run("/nonexistent/bridge", [], "x")
    end

    test "reports a non-zero exit without raising" do
      assert {:error, "Exit code 3: " <> _} = Bridge.run("sh", ["-c", "exit 3"], "x")
    end
  end

  describe "require_executable/2" do
    test "passes a binary through" do
      assert {:ok, "/bin/sh"} = Bridge.require_executable("/bin/sh", :rust)
    end

    test "names the language when the executable is missing" do
      assert {:error, message} = Bridge.require_executable(nil, :rust)
      assert message == "rust parser unavailable: no rust executable found on PATH"
    end
  end

  describe "encode/1" do
    test "encodes an encodable term" do
      assert {:ok, json} = Bridge.encode(%{"type" => "File"})
      assert Jason.decode!(json) == %{"type" => "File"}
    end

    test "reports an unencodable term instead of raising" do
      assert {:error, "JSON encode failed: " <> _} = Bridge.encode({:not, :encodable})
    end
  end

  describe "behaviour" do
    test "declares parse/1 and unparse/1 as optional callbacks" do
      callbacks = Bridge.behaviour_info(:callbacks)
      optional = Bridge.behaviour_info(:optional_callbacks)

      assert {:parse, 1} in callbacks
      assert {:unparse, 1} in callbacks
      assert {:parse, 1} in optional
      assert {:unparse, 1} in optional
    end
  end
end
