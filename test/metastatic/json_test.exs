defmodule Metastatic.JSONTest do
  use ExUnit.Case, async: true

  alias Metastatic.JSON

  doctest JSON

  describe "encoding and decoding" do
    test "round-trips nested nulls, booleans, numbers, and Unicode" do
      value = %{"items" => [nil, true, false, 42, 1.5, "Català 日本語\n\"\\"]}

      assert {:ok, encoded} = JSON.encode(value)
      assert is_binary(encoded)
      assert encoded =~ "null"
      assert {:ok, ^value} = JSON.decode(encoded)
    end

    test "encodes atom keys and values as strings, but nil as null" do
      assert JSON.decode!(JSON.encode!(%{kind: :literal, value: nil})) ==
               %{"kind" => "literal", "value" => nil}

      assert JSON.encode!(nil) == "null"
      assert JSON.decode!("null") == nil
      assert JSON.decode!(~s("null")) == "null"
    end

    test "pretty output preserves nested nulls and is a JSON binary" do
      value = %{"items" => [%{"value" => nil}], "enabled" => true}
      encoded = JSON.encode!(value, pretty: true)

      assert is_binary(encoded)
      assert encoded =~ "\n"
      assert encoded =~ ~s("value": null)
      assert JSON.decode!(encoded) == value
    end

    test "preserves string escaping in scalar output" do
      value = "line\n\"quote\"\\slash\t"

      assert JSON.encode!(value) == ~s("line\\n\\"quote\\"\\\\slash\\t")
      assert JSON.decode!(JSON.encode!(value)) == value
    end
  end

  describe "invalid input" do
    test "rejects malformed or incomplete JSON without raising" do
      for input <- ["", "not json", "{", ~s({"value":}), "\"unterminated", <<255>>] do
        assert {:error, _} = JSON.decode(input)
      end
    end

    test "rejects trailing data and multiple documents" do
      for input <- ["{}junk", "1 2", "null null", "{}\n[]"] do
        assert {:error, %ArgumentError{}} = JSON.decode(input)
        assert_raise ArgumentError, fn -> JSON.decode!(input) end
      end
    end

    test "accepts surrounding JSON whitespace" do
      assert {:ok, %{"value" => nil}} = JSON.decode(" \t\r\n{\"value\":null} \t\r\n")
    end

    test "reports unsupported terms in compact and pretty encoders" do
      for opts <- [[], [pretty: true]] do
        assert {:error, _} = JSON.encode({:not, :encodable}, opts)
        assert {:error, _} = JSON.encode(%{nested: [{:not, :encodable}]}, opts)
        assert_raise ErlangError, fn -> JSON.encode!({:not, :encodable}, opts) end
      end
    end
  end
end
