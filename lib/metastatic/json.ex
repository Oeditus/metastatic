defmodule Metastatic.JSON do
  @moduledoc """
  JSON encoding and decoding backed by OTP 27+'s built-in `:json` module.

  Preserves Elixir's `nil` as JSON `null`, encodes other atoms as strings, and
  returns binaries rather than iodata. No external JSON dependency is required.
  """

  @doc """
  Encodes a term as JSON, returning an error tuple for unsupported values.

  ## Examples

      iex> Metastatic.JSON.encode(%{value: nil})
      {:ok, ~s({"value":null})}
  """
  @spec encode(term(), keyword()) :: {:ok, String.t()} | {:error, Exception.t()}
  def encode(value, opts \\ []) do
    {:ok, encode!(value, opts)}
  rescue
    error -> {:error, error}
  end

  @doc """
  Encodes a term as a JSON binary, raising for unsupported values.

  Pass `pretty: true` for human-readable output.

  ## Examples

      iex> Metastatic.JSON.encode!([nil, true, :literal])
      ~s([null,true,"literal"])
  """
  @spec encode!(term(), keyword()) :: String.t()
  def encode!(value, opts \\ []) do
    encoded =
      if Keyword.get(opts, :pretty, false) do
        :json.format(value, &format_value/3, %{})
      else
        :json.encode(value, &encode_value/2)
      end

    IO.iodata_to_binary(encoded)
  end

  @doc """
  Decodes a complete JSON document, returning an error tuple for invalid input.

  Object keys remain strings and JSON `null` becomes `nil`.

  ## Examples

      iex> Metastatic.JSON.decode(~s({"value":null}))
      {:ok, %{"value" => nil}}
  """
  @spec decode(String.t()) :: {:ok, term()} | {:error, Exception.t()}
  def decode(input) when is_binary(input) do
    {:ok, decode!(input)}
  rescue
    error -> {:error, error}
  end

  @doc """
  Decodes a complete JSON document, raising for invalid or trailing input.

  ## Examples

      iex> Metastatic.JSON.decode!(~s([null,true,"literal"]))
      [nil, true, "literal"]
  """
  @spec decode!(String.t()) :: term()
  def decode!(input) when is_binary(input) do
    case :json.decode(input, nil, %{null: nil}) do
      {value, nil, ""} -> value
      {_value, nil, _rest} -> raise ArgumentError, "unexpected trailing JSON data"
    end
  end

  defp encode_value(nil, _encoder), do: "null"
  defp encode_value(value, encoder), do: :json.encode_value(value, encoder)

  defp format_value(nil, _encoder, _state), do: "null"
  defp format_value(value, encoder, state), do: :json.format_value(value, encoder, state)
end
