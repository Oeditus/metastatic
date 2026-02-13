defmodule Metastatic.Semantic.Domains.Http do
  @moduledoc """
  HTTP client operation patterns for semantic enrichment.

  This module defines patterns for detecting HTTP client operations across
  multiple languages and HTTP client libraries. Patterns are registered with
  the `Metastatic.Semantic.Patterns` registry at module load time.

  ## Supported Libraries

  ### Elixir
  - **HTTPoison** - `HTTPoison.*` operations
  - **Req** - `Req.*` operations
  - **Tesla** - `Tesla.*` operations
  - **Finch** - `Finch.*` operations
  - **Mint** - Low-level HTTP client

  ### Python
  - **requests** - `requests.*` operations
  - **httpx** - `httpx.*` operations (sync and async)
  - **aiohttp** - Async HTTP client
  - **urllib** - Standard library

  ### Ruby
  - **Net::HTTP** - Standard library
  - **HTTParty** - `HTTParty.*` operations
  - **Faraday** - `Faraday.*` operations
  - **RestClient** - `RestClient.*` operations

  ### JavaScript
  - **fetch** - Native Fetch API
  - **axios** - `axios.*` operations
  - **got** - `got.*` operations
  - **node-fetch** - Node.js fetch implementation
  - **superagent** - `superagent.*` operations

  ## HTTP Operations

  | Operation | Description |
  |-----------|-------------|
  | `:get` | HTTP GET request |
  | `:post` | HTTP POST request |
  | `:put` | HTTP PUT request |
  | `:patch` | HTTP PATCH request |
  | `:delete` | HTTP DELETE request |
  | `:head` | HTTP HEAD request |
  | `:options` | HTTP OPTIONS request |
  | `:request` | Generic HTTP request |
  | `:stream` | Streaming HTTP request |

  ## Pattern Structure

  Each pattern is a tuple of `{pattern, spec}` where:
  - `pattern` - String or Regex to match function names
  - `spec` - Map with operation details:
    - `:operation` - The HTTP operation type
    - `:framework` - The HTTP library identifier
    - `:extract_target` - Strategy for extracting URL/endpoint
  """

  alias Metastatic.Semantic.Patterns

  # ----- Elixir/HTTPoison Patterns -----

  @elixir_httpoison_patterns [
    {"HTTPoison.get", %{operation: :get, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.get!", %{operation: :get, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.post", %{operation: :post, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.post!", %{operation: :post, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.put", %{operation: :put, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.put!", %{operation: :put, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.patch", %{operation: :patch, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.patch!", %{operation: :patch, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.delete",
     %{operation: :delete, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.delete!",
     %{operation: :delete, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.head", %{operation: :head, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.head!", %{operation: :head, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.options",
     %{operation: :options, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.options!",
     %{operation: :options, framework: :httpoison, extract_target: :first_arg}},
    {"HTTPoison.request", %{operation: :request, framework: :httpoison, extract_target: :none}},
    {"HTTPoison.request!", %{operation: :request, framework: :httpoison, extract_target: :none}}
  ]

  # ----- Elixir/Req Patterns -----

  @elixir_req_patterns [
    {"Req.get", %{operation: :get, framework: :req, extract_target: :first_arg}},
    {"Req.get!", %{operation: :get, framework: :req, extract_target: :first_arg}},
    {"Req.post", %{operation: :post, framework: :req, extract_target: :first_arg}},
    {"Req.post!", %{operation: :post, framework: :req, extract_target: :first_arg}},
    {"Req.put", %{operation: :put, framework: :req, extract_target: :first_arg}},
    {"Req.put!", %{operation: :put, framework: :req, extract_target: :first_arg}},
    {"Req.patch", %{operation: :patch, framework: :req, extract_target: :first_arg}},
    {"Req.patch!", %{operation: :patch, framework: :req, extract_target: :first_arg}},
    {"Req.delete", %{operation: :delete, framework: :req, extract_target: :first_arg}},
    {"Req.delete!", %{operation: :delete, framework: :req, extract_target: :first_arg}},
    {"Req.head", %{operation: :head, framework: :req, extract_target: :first_arg}},
    {"Req.head!", %{operation: :head, framework: :req, extract_target: :first_arg}},
    {"Req.request", %{operation: :request, framework: :req, extract_target: :none}},
    {"Req.request!", %{operation: :request, framework: :req, extract_target: :none}},
    {"Req.new", %{operation: :request, framework: :req, extract_target: :none}}
  ]

  # ----- Elixir/Tesla Patterns -----

  @elixir_tesla_patterns [
    {"Tesla.get", %{operation: :get, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.get!", %{operation: :get, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.post", %{operation: :post, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.post!", %{operation: :post, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.put", %{operation: :put, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.put!", %{operation: :put, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.patch", %{operation: :patch, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.patch!", %{operation: :patch, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.delete", %{operation: :delete, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.delete!", %{operation: :delete, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.head", %{operation: :head, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.head!", %{operation: :head, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.options", %{operation: :options, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.options!", %{operation: :options, framework: :tesla, extract_target: :first_arg}},
    {"Tesla.request", %{operation: :request, framework: :tesla, extract_target: :none}}
  ]

  # ----- Elixir/Finch Patterns -----

  @elixir_finch_patterns [
    {"Finch.request", %{operation: :request, framework: :finch, extract_target: :none}},
    {"Finch.request!", %{operation: :request, framework: :finch, extract_target: :none}},
    {"Finch.stream", %{operation: :stream, framework: :finch, extract_target: :none}},
    {"Finch.stream!", %{operation: :stream, framework: :finch, extract_target: :none}},
    {"Finch.build", %{operation: :request, framework: :finch, extract_target: :none}}
  ]

  # ----- Python/requests Patterns -----

  @python_requests_patterns [
    {"requests.get", %{operation: :get, framework: :requests, extract_target: :first_arg}},
    {"requests.post", %{operation: :post, framework: :requests, extract_target: :first_arg}},
    {"requests.put", %{operation: :put, framework: :requests, extract_target: :first_arg}},
    {"requests.patch", %{operation: :patch, framework: :requests, extract_target: :first_arg}},
    {"requests.delete", %{operation: :delete, framework: :requests, extract_target: :first_arg}},
    {"requests.head", %{operation: :head, framework: :requests, extract_target: :first_arg}},
    {"requests.options",
     %{operation: :options, framework: :requests, extract_target: :first_arg}},
    {"requests.request", %{operation: :request, framework: :requests, extract_target: :none}},
    # Session-based requests
    {"session.get", %{operation: :get, framework: :requests, extract_target: :first_arg}},
    {"session.post", %{operation: :post, framework: :requests, extract_target: :first_arg}},
    {"session.put", %{operation: :put, framework: :requests, extract_target: :first_arg}},
    {"session.patch", %{operation: :patch, framework: :requests, extract_target: :first_arg}},
    {"session.delete", %{operation: :delete, framework: :requests, extract_target: :first_arg}},
    {"session.head", %{operation: :head, framework: :requests, extract_target: :first_arg}},
    {"session.request", %{operation: :request, framework: :requests, extract_target: :none}}
  ]

  # ----- Python/httpx Patterns -----

  @python_httpx_patterns [
    {"httpx.get", %{operation: :get, framework: :httpx, extract_target: :first_arg}},
    {"httpx.post", %{operation: :post, framework: :httpx, extract_target: :first_arg}},
    {"httpx.put", %{operation: :put, framework: :httpx, extract_target: :first_arg}},
    {"httpx.patch", %{operation: :patch, framework: :httpx, extract_target: :first_arg}},
    {"httpx.delete", %{operation: :delete, framework: :httpx, extract_target: :first_arg}},
    {"httpx.head", %{operation: :head, framework: :httpx, extract_target: :first_arg}},
    {"httpx.options", %{operation: :options, framework: :httpx, extract_target: :first_arg}},
    {"httpx.request", %{operation: :request, framework: :httpx, extract_target: :none}},
    {"httpx.stream", %{operation: :stream, framework: :httpx, extract_target: :first_arg}},
    # AsyncClient methods
    {"client.get", %{operation: :get, framework: :httpx, extract_target: :first_arg}},
    {"client.post", %{operation: :post, framework: :httpx, extract_target: :first_arg}},
    {"client.put", %{operation: :put, framework: :httpx, extract_target: :first_arg}},
    {"client.patch", %{operation: :patch, framework: :httpx, extract_target: :first_arg}},
    {"client.delete", %{operation: :delete, framework: :httpx, extract_target: :first_arg}},
    {"client.head", %{operation: :head, framework: :httpx, extract_target: :first_arg}},
    {"client.request", %{operation: :request, framework: :httpx, extract_target: :none}},
    {"client.stream", %{operation: :stream, framework: :httpx, extract_target: :first_arg}}
  ]

  # ----- Python/aiohttp Patterns -----

  @python_aiohttp_patterns [
    # ClientSession methods
    {~r/\.get$/, %{operation: :get, framework: :aiohttp, extract_target: :first_arg}},
    {~r/\.post$/, %{operation: :post, framework: :aiohttp, extract_target: :first_arg}},
    {~r/\.put$/, %{operation: :put, framework: :aiohttp, extract_target: :first_arg}},
    {~r/\.patch$/, %{operation: :patch, framework: :aiohttp, extract_target: :first_arg}},
    {~r/\.delete$/, %{operation: :delete, framework: :aiohttp, extract_target: :first_arg}},
    {~r/\.head$/, %{operation: :head, framework: :aiohttp, extract_target: :first_arg}},
    {~r/\.options$/, %{operation: :options, framework: :aiohttp, extract_target: :first_arg}},
    {~r/\.request$/, %{operation: :request, framework: :aiohttp, extract_target: :none}},
    {"aiohttp.ClientSession", %{operation: :request, framework: :aiohttp, extract_target: :none}}
  ]

  # ----- Ruby/Net::HTTP Patterns -----

  @ruby_nethttp_patterns [
    {"Net::HTTP.get", %{operation: :get, framework: :nethttp, extract_target: :first_arg}},
    {"Net::HTTP.get_response",
     %{operation: :get, framework: :nethttp, extract_target: :first_arg}},
    {"Net::HTTP.post", %{operation: :post, framework: :nethttp, extract_target: :first_arg}},
    {"Net::HTTP.post_form", %{operation: :post, framework: :nethttp, extract_target: :first_arg}},
    {"Net::HTTP.start", %{operation: :request, framework: :nethttp, extract_target: :none}},
    # Instance methods via regex
    {~r/\.get$/, %{operation: :get, framework: :nethttp, extract_target: :first_arg}},
    {~r/\.post$/, %{operation: :post, framework: :nethttp, extract_target: :first_arg}},
    {~r/\.put$/, %{operation: :put, framework: :nethttp, extract_target: :first_arg}},
    {~r/\.patch$/, %{operation: :patch, framework: :nethttp, extract_target: :first_arg}},
    {~r/\.delete$/, %{operation: :delete, framework: :nethttp, extract_target: :first_arg}},
    {~r/\.head$/, %{operation: :head, framework: :nethttp, extract_target: :first_arg}},
    {~r/\.request$/, %{operation: :request, framework: :nethttp, extract_target: :none}}
  ]

  # ----- Ruby/HTTParty Patterns -----

  @ruby_httparty_patterns [
    {"HTTParty.get", %{operation: :get, framework: :httparty, extract_target: :first_arg}},
    {"HTTParty.post", %{operation: :post, framework: :httparty, extract_target: :first_arg}},
    {"HTTParty.put", %{operation: :put, framework: :httparty, extract_target: :first_arg}},
    {"HTTParty.patch", %{operation: :patch, framework: :httparty, extract_target: :first_arg}},
    {"HTTParty.delete", %{operation: :delete, framework: :httparty, extract_target: :first_arg}},
    {"HTTParty.head", %{operation: :head, framework: :httparty, extract_target: :first_arg}},
    {"HTTParty.options", %{operation: :options, framework: :httparty, extract_target: :first_arg}}
  ]

  # ----- Ruby/Faraday Patterns -----

  @ruby_faraday_patterns [
    {"Faraday.get", %{operation: :get, framework: :faraday, extract_target: :first_arg}},
    {"Faraday.post", %{operation: :post, framework: :faraday, extract_target: :first_arg}},
    {"Faraday.put", %{operation: :put, framework: :faraday, extract_target: :first_arg}},
    {"Faraday.patch", %{operation: :patch, framework: :faraday, extract_target: :first_arg}},
    {"Faraday.delete", %{operation: :delete, framework: :faraday, extract_target: :first_arg}},
    {"Faraday.head", %{operation: :head, framework: :faraday, extract_target: :first_arg}},
    {"Faraday.options", %{operation: :options, framework: :faraday, extract_target: :first_arg}},
    {"Faraday.new", %{operation: :request, framework: :faraday, extract_target: :none}},
    # Connection instance methods
    {"conn.get", %{operation: :get, framework: :faraday, extract_target: :first_arg}},
    {"conn.post", %{operation: :post, framework: :faraday, extract_target: :first_arg}},
    {"conn.put", %{operation: :put, framework: :faraday, extract_target: :first_arg}},
    {"conn.patch", %{operation: :patch, framework: :faraday, extract_target: :first_arg}},
    {"conn.delete", %{operation: :delete, framework: :faraday, extract_target: :first_arg}},
    {"conn.head", %{operation: :head, framework: :faraday, extract_target: :first_arg}}
  ]

  # ----- Ruby/RestClient Patterns -----

  @ruby_restclient_patterns [
    {"RestClient.get", %{operation: :get, framework: :restclient, extract_target: :first_arg}},
    {"RestClient.post", %{operation: :post, framework: :restclient, extract_target: :first_arg}},
    {"RestClient.put", %{operation: :put, framework: :restclient, extract_target: :first_arg}},
    {"RestClient.patch",
     %{operation: :patch, framework: :restclient, extract_target: :first_arg}},
    {"RestClient.delete",
     %{operation: :delete, framework: :restclient, extract_target: :first_arg}},
    {"RestClient.head", %{operation: :head, framework: :restclient, extract_target: :first_arg}},
    {"RestClient.options",
     %{operation: :options, framework: :restclient, extract_target: :first_arg}}
  ]

  # ----- JavaScript/fetch Patterns -----

  @javascript_fetch_patterns [
    {"fetch", %{operation: :request, framework: :fetch, extract_target: :first_arg}},
    {"window.fetch", %{operation: :request, framework: :fetch, extract_target: :first_arg}},
    {"globalThis.fetch", %{operation: :request, framework: :fetch, extract_target: :first_arg}}
  ]

  # ----- JavaScript/axios Patterns -----

  @javascript_axios_patterns [
    {"axios.get", %{operation: :get, framework: :axios, extract_target: :first_arg}},
    {"axios.post", %{operation: :post, framework: :axios, extract_target: :first_arg}},
    {"axios.put", %{operation: :put, framework: :axios, extract_target: :first_arg}},
    {"axios.patch", %{operation: :patch, framework: :axios, extract_target: :first_arg}},
    {"axios.delete", %{operation: :delete, framework: :axios, extract_target: :first_arg}},
    {"axios.head", %{operation: :head, framework: :axios, extract_target: :first_arg}},
    {"axios.options", %{operation: :options, framework: :axios, extract_target: :first_arg}},
    {"axios.request", %{operation: :request, framework: :axios, extract_target: :none}},
    {"axios", %{operation: :request, framework: :axios, extract_target: :first_arg}},
    # Instance methods
    {"instance.get", %{operation: :get, framework: :axios, extract_target: :first_arg}},
    {"instance.post", %{operation: :post, framework: :axios, extract_target: :first_arg}},
    {"instance.put", %{operation: :put, framework: :axios, extract_target: :first_arg}},
    {"instance.patch", %{operation: :patch, framework: :axios, extract_target: :first_arg}},
    {"instance.delete", %{operation: :delete, framework: :axios, extract_target: :first_arg}},
    {"instance.head", %{operation: :head, framework: :axios, extract_target: :first_arg}},
    {"instance.request", %{operation: :request, framework: :axios, extract_target: :none}}
  ]

  # ----- JavaScript/got Patterns -----

  @javascript_got_patterns [
    {"got", %{operation: :request, framework: :got, extract_target: :first_arg}},
    {"got.get", %{operation: :get, framework: :got, extract_target: :first_arg}},
    {"got.post", %{operation: :post, framework: :got, extract_target: :first_arg}},
    {"got.put", %{operation: :put, framework: :got, extract_target: :first_arg}},
    {"got.patch", %{operation: :patch, framework: :got, extract_target: :first_arg}},
    {"got.delete", %{operation: :delete, framework: :got, extract_target: :first_arg}},
    {"got.head", %{operation: :head, framework: :got, extract_target: :first_arg}},
    {"got.stream", %{operation: :stream, framework: :got, extract_target: :first_arg}},
    {"got.extend", %{operation: :request, framework: :got, extract_target: :none}}
  ]

  # ----- JavaScript/superagent Patterns -----

  @javascript_superagent_patterns [
    {"superagent.get", %{operation: :get, framework: :superagent, extract_target: :first_arg}},
    {"superagent.post", %{operation: :post, framework: :superagent, extract_target: :first_arg}},
    {"superagent.put", %{operation: :put, framework: :superagent, extract_target: :first_arg}},
    {"superagent.patch",
     %{operation: :patch, framework: :superagent, extract_target: :first_arg}},
    {"superagent.delete",
     %{operation: :delete, framework: :superagent, extract_target: :first_arg}},
    {"superagent.head", %{operation: :head, framework: :superagent, extract_target: :first_arg}},
    {"request.get", %{operation: :get, framework: :superagent, extract_target: :first_arg}},
    {"request.post", %{operation: :post, framework: :superagent, extract_target: :first_arg}},
    {"request.put", %{operation: :put, framework: :superagent, extract_target: :first_arg}},
    {"request.patch", %{operation: :patch, framework: :superagent, extract_target: :first_arg}},
    {"request.delete", %{operation: :delete, framework: :superagent, extract_target: :first_arg}},
    {"request.head", %{operation: :head, framework: :superagent, extract_target: :first_arg}}
  ]

  # ----- Registration -----

  @doc """
  Registers all HTTP patterns for all languages.

  Called automatically when the module is loaded. Can also be called
  manually to re-register patterns (e.g., after clearing).
  """
  @spec register_all() :: :ok
  def register_all do
    # Elixir patterns (HTTPoison + Req + Tesla + Finch)
    Patterns.register(
      :http,
      :elixir,
      @elixir_httpoison_patterns ++
        @elixir_req_patterns ++ @elixir_tesla_patterns ++ @elixir_finch_patterns
    )

    # Python patterns (requests + httpx + aiohttp)
    Patterns.register(
      :http,
      :python,
      @python_requests_patterns ++ @python_httpx_patterns ++ @python_aiohttp_patterns
    )

    # Ruby patterns (Net::HTTP + HTTParty + Faraday + RestClient)
    Patterns.register(
      :http,
      :ruby,
      @ruby_nethttp_patterns ++
        @ruby_httparty_patterns ++ @ruby_faraday_patterns ++ @ruby_restclient_patterns
    )

    # JavaScript patterns (fetch + axios + got + superagent)
    Patterns.register(
      :http,
      :javascript,
      @javascript_fetch_patterns ++
        @javascript_axios_patterns ++ @javascript_got_patterns ++ @javascript_superagent_patterns
    )

    :ok
  end

  @doc false
  def __on_definition__(_env, _kind, _name, _args, _guards, _body) do
    :ok
  end
end

# Register patterns when module is loaded
Metastatic.Semantic.Domains.Http.register_all()
