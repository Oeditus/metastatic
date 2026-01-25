defmodule Metastatic.Analysis.BusinessLogic.HardcodedValue do
  @moduledoc """
  Detects hardcoded URLs, IP addresses, and other sensitive values in string literals.

  This analyzer identifies string literals containing URLs, IP addresses, and other
  values that should be externalized to configuration, making code more flexible
  and preventing accidental exposure of sensitive information.

  ## Cross-Language Applicability

  This is a universal anti-pattern that applies to all languages:

  - **Python**: Hardcoded strings in code
  - **JavaScript/TypeScript**: String literals with URLs/IPs
  - **Elixir**: Hardcoded binaries or strings
  - **Go**: String constants in code
  - **Java/C#**: Hardcoded string literals
  - **Rust**: String literals

  ## Examples

  ### Bad (Python)

      API_URL = "https://api.example.com"
      DB_HOST = "192.168.1.100"

  ### Good (Python)

      import os
      API_URL = os.getenv("API_URL")
      DB_HOST = os.getenv("DB_HOST")

  ### Bad (JavaScript)

      const apiUrl = "https://api.example.com";
      const dbHost = "10.0.0.5";

  ### Good (JavaScript)

      const apiUrl = process.env.API_URL;
      const dbHost = process.env.DB_HOST;

  ### Bad (Elixir)

      @api_url "https://api.example.com"
      @db_host "192.168.1.100"

  ### Good (Elixir)

      @api_url Application.get_env(:my_app, :api_url)
      @db_host System.get_env("DB_HOST")

  ## Configuration

  - `:exclude_localhost` - Don't flag localhost/127.0.0.1 (default: true)
  - `:exclude_local_ips` - Don't flag private IP ranges (default: true)

  ## Detection Strategy

  Checks string literals for:
  1. URLs (http://, https://, ftp://, etc.)
  2. IP addresses (IPv4 format)
  3. Excludes common development values (localhost, 127.0.0.1, 192.168.x.x, etc.)
  """

  @behaviour Metastatic.Analysis.Analyzer

  alias Metastatic.Analysis.Analyzer

  # Regex patterns
  @url_pattern ~r/^https?:\/\/[^\s]+$/
  @ip_pattern ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/

  @impl true
  def info do
    %{
      name: :hardcoded_value,
      category: :security,
      description: "Detects hardcoded URLs, IPs, and sensitive values in literals",
      severity: :warning,
      explanation: """
      Hardcoding URLs, IP addresses, and other configuration values makes code
      inflexible and can expose sensitive information. Move these values to
      configuration files or environment variables.

      Benefits:
      - Different values for dev/staging/production
      - No secrets in source control
      - Easier deployment and configuration management
      - Better security practices
      """,
      configurable: true
    }
  end

  @impl true
  def run_before(context) do
    # Initialize configuration with defaults
    exclude_localhost = Map.get(context.config, :exclude_localhost, true)
    exclude_local_ips = Map.get(context.config, :exclude_local_ips, true)

    context =
      context
      |> Map.put(:exclude_localhost, exclude_localhost)
      |> Map.put(:exclude_local_ips, exclude_local_ips)

    {:ok, context}
  end

  @impl true
  def analyze({:literal, :string, value} = node, context) when is_binary(value) do
    exclude_localhost = Map.get(context, :exclude_localhost, true)
    exclude_local_ips = Map.get(context, :exclude_local_ips, true)

    cond do
      url?(value) and not (exclude_localhost and localhost_url?(value)) ->
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :warning,
            message: "Hardcoded URL found - move to configuration",
            node: node,
            metadata: %{type: :url, value: value}
          )
        ]

      ip?(value) and not (exclude_local_ips and local_ip?(value)) ->
        [
          Analyzer.issue(
            analyzer: __MODULE__,
            category: :security,
            severity: :warning,
            message: "Hardcoded IP address found - move to configuration",
            node: node,
            metadata: %{type: :ip, value: value}
          )
        ]

      true ->
        []
    end
  end

  def analyze(_node, _context), do: []

  # ----- Private Helpers -----

  # Check if string is a URL
  defp url?(string) when is_binary(string) do
    Regex.match?(@url_pattern, string)
  end

  defp url?(_), do: false

  # Check if string is an IP address
  defp ip?(string) when is_binary(string) do
    Regex.match?(@ip_pattern, string) and valid_ip?(string)
  end

  defp ip?(_), do: false

  # Validate IP address octets are in valid range (0-255)
  defp valid_ip?(ip_string) do
    ip_string
    |> String.split(".")
    |> Enum.all?(fn octet ->
      case Integer.parse(octet) do
        {num, ""} when num >= 0 and num <= 255 -> true
        _ -> false
      end
    end)
  end

  # Check if URL is localhost
  defp localhost_url?(url) when is_binary(url) do
    String.contains?(url, ["localhost", "127.0.0.1", "0.0.0.0"])
  end

  defp localhost_url?(_), do: false

  # Check if IP is in local/private range
  defp local_ip?(ip) when is_binary(ip) do
    cond do
      String.starts_with?(ip, "127.") -> true
      String.starts_with?(ip, "192.168.") -> true
      String.starts_with?(ip, "10.") -> true
      String.starts_with?(ip, "172.") -> in_private_range?(ip)
      ip == "0.0.0.0" -> true
      true -> false
    end
  end

  defp local_ip?(_), do: false

  # Check if IP is in 172.16.0.0 - 172.31.255.255 range
  defp in_private_range?(ip) do
    case String.split(ip, ".") do
      ["172", second_octet | _] ->
        case Integer.parse(second_octet) do
          {num, ""} when num >= 16 and num <= 31 -> true
          _ -> false
        end

      _ ->
        false
    end
  end
end
