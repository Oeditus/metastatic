defmodule Metastatic.Semantic.Domains.Cache do
  @moduledoc """
  Cache operation patterns for semantic enrichment.

  This module defines patterns for detecting cache operations across
  multiple languages and caching libraries. Patterns are registered with
  the `Metastatic.Semantic.Patterns` registry at module load time.

  ## Supported Libraries

  ### Elixir
  - **Cachex** - In-memory cache with TTL support
  - **ConCache** - ETS-based caching
  - **Nebulex** - Distributed caching
  - **ETS** - Erlang Term Storage

  ### Python
  - **redis-py** - Redis client
  - **python-memcached** - Memcached client
  - **Flask-Caching** - Flask caching extension
  - **django-cache** - Django caching framework

  ### Ruby
  - **Rails.cache** - Rails caching API
  - **Dalli** - Memcached client
  - **redis-rb** - Redis client

  ### JavaScript
  - **node-cache** - In-memory caching
  - **redis/ioredis** - Redis clients
  - **memcached** - Memcached client

  ## Cache Operations

  | Operation | Description |
  |-----------|-------------|
  | `:get` | Retrieve value from cache |
  | `:set` | Store value in cache |
  | `:delete` | Remove value from cache |
  | `:clear` | Clear all cache entries |
  | `:invalidate` | Invalidate cache entries |
  | `:expire` | Set/update TTL |
  | `:exists` | Check if key exists |
  | `:increment` | Increment numeric value |
  | `:decrement` | Decrement numeric value |
  | `:ttl` | Get time-to-live |
  | `:fetch` | Get or compute value |

  ## Pattern Structure

  Each pattern is a tuple of `{pattern, spec}` where:
  - `pattern` - String or Regex to match function names
  - `spec` - Map with operation details:
    - `:operation` - The cache operation type
    - `:framework` - The caching library identifier
    - `:extract_target` - Strategy for extracting cache key
  """

  alias Metastatic.Semantic.Patterns

  # ----- Elixir/Cachex Patterns -----

  @elixir_cachex_patterns [
    {"Cachex.get", %{operation: :get, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.get!", %{operation: :get, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.put", %{operation: :set, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.put!", %{operation: :set, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.del", %{operation: :delete, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.del!", %{operation: :delete, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.clear", %{operation: :clear, framework: :cachex, extract_target: :none}},
    {"Cachex.clear!", %{operation: :clear, framework: :cachex, extract_target: :none}},
    {"Cachex.exists?", %{operation: :exists, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.expire", %{operation: :expire, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.expire!", %{operation: :expire, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.ttl", %{operation: :ttl, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.ttl!", %{operation: :ttl, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.incr", %{operation: :increment, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.incr!", %{operation: :increment, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.decr", %{operation: :decrement, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.decr!", %{operation: :decrement, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.fetch", %{operation: :fetch, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.fetch!", %{operation: :fetch, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.take", %{operation: :get, framework: :cachex, extract_target: :first_arg}},
    {"Cachex.take!", %{operation: :get, framework: :cachex, extract_target: :first_arg}}
  ]

  # ----- Elixir/ConCache Patterns -----

  @elixir_concache_patterns [
    {"ConCache.get", %{operation: :get, framework: :concache, extract_target: :first_arg}},
    {"ConCache.put", %{operation: :set, framework: :concache, extract_target: :first_arg}},
    {"ConCache.delete", %{operation: :delete, framework: :concache, extract_target: :first_arg}},
    {"ConCache.get_or_store",
     %{operation: :fetch, framework: :concache, extract_target: :first_arg}},
    {"ConCache.update", %{operation: :set, framework: :concache, extract_target: :first_arg}},
    {"ConCache.update_existing",
     %{operation: :set, framework: :concache, extract_target: :first_arg}},
    {"ConCache.dirty_put", %{operation: :set, framework: :concache, extract_target: :first_arg}},
    {"ConCache.dirty_delete",
     %{operation: :delete, framework: :concache, extract_target: :first_arg}}
  ]

  # ----- Elixir/Nebulex Patterns -----

  @elixir_nebulex_patterns [
    {"*.get", %{operation: :get, framework: :nebulex, extract_target: :first_arg}},
    {"*.get!", %{operation: :get, framework: :nebulex, extract_target: :first_arg}},
    {"*.put", %{operation: :set, framework: :nebulex, extract_target: :first_arg}},
    {"*.put!", %{operation: :set, framework: :nebulex, extract_target: :first_arg}},
    {"*.delete", %{operation: :delete, framework: :nebulex, extract_target: :first_arg}},
    {"*.delete!", %{operation: :delete, framework: :nebulex, extract_target: :first_arg}},
    {"*.delete_all", %{operation: :clear, framework: :nebulex, extract_target: :none}},
    {"*.delete_all!", %{operation: :clear, framework: :nebulex, extract_target: :none}},
    {"*.get_and_update", %{operation: :fetch, framework: :nebulex, extract_target: :first_arg}},
    {"*.get_and_update!", %{operation: :fetch, framework: :nebulex, extract_target: :first_arg}},
    {"*.has_key?", %{operation: :exists, framework: :nebulex, extract_target: :first_arg}},
    {"*.ttl", %{operation: :ttl, framework: :nebulex, extract_target: :first_arg}},
    {"*.expire", %{operation: :expire, framework: :nebulex, extract_target: :first_arg}},
    {"*.incr", %{operation: :increment, framework: :nebulex, extract_target: :first_arg}},
    {"*.decr", %{operation: :decrement, framework: :nebulex, extract_target: :first_arg}}
  ]

  # ----- Elixir/ETS Patterns -----

  @elixir_ets_patterns [
    {":ets.lookup", %{operation: :get, framework: :ets, extract_target: :first_arg}},
    {":ets.insert", %{operation: :set, framework: :ets, extract_target: :first_arg}},
    {":ets.delete", %{operation: :delete, framework: :ets, extract_target: :first_arg}},
    {":ets.delete_all_objects", %{operation: :clear, framework: :ets, extract_target: :none}},
    {":ets.member", %{operation: :exists, framework: :ets, extract_target: :first_arg}},
    {":ets.update_counter", %{operation: :increment, framework: :ets, extract_target: :first_arg}}
  ]

  # ----- Python/redis-py Patterns -----

  @python_redis_patterns [
    {"redis.get", %{operation: :get, framework: :redis_py, extract_target: :first_arg}},
    {"redis.set", %{operation: :set, framework: :redis_py, extract_target: :first_arg}},
    {"redis.setex", %{operation: :set, framework: :redis_py, extract_target: :first_arg}},
    {"redis.setnx", %{operation: :set, framework: :redis_py, extract_target: :first_arg}},
    {"redis.delete", %{operation: :delete, framework: :redis_py, extract_target: :first_arg}},
    {"redis.flushdb", %{operation: :clear, framework: :redis_py, extract_target: :none}},
    {"redis.flushall", %{operation: :clear, framework: :redis_py, extract_target: :none}},
    {"redis.exists", %{operation: :exists, framework: :redis_py, extract_target: :first_arg}},
    {"redis.expire", %{operation: :expire, framework: :redis_py, extract_target: :first_arg}},
    {"redis.ttl", %{operation: :ttl, framework: :redis_py, extract_target: :first_arg}},
    {"redis.incr", %{operation: :increment, framework: :redis_py, extract_target: :first_arg}},
    {"redis.incrby", %{operation: :increment, framework: :redis_py, extract_target: :first_arg}},
    {"redis.decr", %{operation: :decrement, framework: :redis_py, extract_target: :first_arg}},
    {"redis.decrby", %{operation: :decrement, framework: :redis_py, extract_target: :first_arg}},
    # Redis client instance methods
    {"r.get", %{operation: :get, framework: :redis_py, extract_target: :first_arg}},
    {"r.set", %{operation: :set, framework: :redis_py, extract_target: :first_arg}},
    {"r.delete", %{operation: :delete, framework: :redis_py, extract_target: :first_arg}},
    {"r.exists", %{operation: :exists, framework: :redis_py, extract_target: :first_arg}},
    {"r.expire", %{operation: :expire, framework: :redis_py, extract_target: :first_arg}},
    {"r.incr", %{operation: :increment, framework: :redis_py, extract_target: :first_arg}},
    {"r.decr", %{operation: :decrement, framework: :redis_py, extract_target: :first_arg}}
  ]

  # ----- Python/Django Cache Patterns -----

  @python_django_cache_patterns [
    {"cache.get", %{operation: :get, framework: :django_cache, extract_target: :first_arg}},
    {"cache.set", %{operation: :set, framework: :django_cache, extract_target: :first_arg}},
    {"cache.delete", %{operation: :delete, framework: :django_cache, extract_target: :first_arg}},
    {"cache.clear", %{operation: :clear, framework: :django_cache, extract_target: :none}},
    {"cache.get_or_set",
     %{operation: :fetch, framework: :django_cache, extract_target: :first_arg}},
    {"cache.add", %{operation: :set, framework: :django_cache, extract_target: :first_arg}},
    {"cache.incr",
     %{operation: :increment, framework: :django_cache, extract_target: :first_arg}},
    {"cache.decr",
     %{operation: :decrement, framework: :django_cache, extract_target: :first_arg}},
    {"cache.touch", %{operation: :expire, framework: :django_cache, extract_target: :first_arg}},
    {"cache.has_key",
     %{operation: :exists, framework: :django_cache, extract_target: :first_arg}},
    {"caches[*].get", %{operation: :get, framework: :django_cache, extract_target: :first_arg}},
    {"caches[*].set", %{operation: :set, framework: :django_cache, extract_target: :first_arg}}
  ]

  # ----- Python/Flask-Caching Patterns -----

  @python_flask_cache_patterns [
    {"cache.get", %{operation: :get, framework: :flask_cache, extract_target: :first_arg}},
    {"cache.set", %{operation: :set, framework: :flask_cache, extract_target: :first_arg}},
    {"cache.delete", %{operation: :delete, framework: :flask_cache, extract_target: :first_arg}},
    {"cache.clear", %{operation: :clear, framework: :flask_cache, extract_target: :none}},
    {"cache.cached", %{operation: :fetch, framework: :flask_cache, extract_target: :none}},
    {"cache.memoize", %{operation: :fetch, framework: :flask_cache, extract_target: :none}},
    {"cache.delete_memoized",
     %{operation: :invalidate, framework: :flask_cache, extract_target: :first_arg}}
  ]

  # ----- Ruby/Rails.cache Patterns -----

  @ruby_rails_cache_patterns [
    {"Rails.cache.read", %{operation: :get, framework: :rails_cache, extract_target: :first_arg}},
    {"Rails.cache.write",
     %{operation: :set, framework: :rails_cache, extract_target: :first_arg}},
    {"Rails.cache.delete",
     %{operation: :delete, framework: :rails_cache, extract_target: :first_arg}},
    {"Rails.cache.clear", %{operation: :clear, framework: :rails_cache, extract_target: :none}},
    {"Rails.cache.exist?",
     %{operation: :exists, framework: :rails_cache, extract_target: :first_arg}},
    {"Rails.cache.fetch",
     %{operation: :fetch, framework: :rails_cache, extract_target: :first_arg}},
    {"Rails.cache.increment",
     %{operation: :increment, framework: :rails_cache, extract_target: :first_arg}},
    {"Rails.cache.decrement",
     %{operation: :decrement, framework: :rails_cache, extract_target: :first_arg}},
    {"Rails.cache.delete_matched",
     %{operation: :invalidate, framework: :rails_cache, extract_target: :first_arg}}
  ]

  # ----- Ruby/Dalli (Memcached) Patterns -----

  @ruby_dalli_patterns [
    {"dalli.get", %{operation: :get, framework: :dalli, extract_target: :first_arg}},
    {"dalli.set", %{operation: :set, framework: :dalli, extract_target: :first_arg}},
    {"dalli.delete", %{operation: :delete, framework: :dalli, extract_target: :first_arg}},
    {"dalli.flush", %{operation: :clear, framework: :dalli, extract_target: :none}},
    {"dalli.fetch", %{operation: :fetch, framework: :dalli, extract_target: :first_arg}},
    {"dalli.incr", %{operation: :increment, framework: :dalli, extract_target: :first_arg}},
    {"dalli.decr", %{operation: :decrement, framework: :dalli, extract_target: :first_arg}},
    {"dalli.touch", %{operation: :expire, framework: :dalli, extract_target: :first_arg}}
  ]

  # ----- Ruby/redis-rb Patterns -----

  @ruby_redis_patterns [
    {~r/redis\.get$/, %{operation: :get, framework: :redis_rb, extract_target: :first_arg}},
    {~r/redis\.set$/, %{operation: :set, framework: :redis_rb, extract_target: :first_arg}},
    {~r/redis\.del$/, %{operation: :delete, framework: :redis_rb, extract_target: :first_arg}},
    {~r/redis\.flushdb$/, %{operation: :clear, framework: :redis_rb, extract_target: :none}},
    {~r/redis\.exists\?$/,
     %{operation: :exists, framework: :redis_rb, extract_target: :first_arg}},
    {~r/redis\.expire$/, %{operation: :expire, framework: :redis_rb, extract_target: :first_arg}},
    {~r/redis\.ttl$/, %{operation: :ttl, framework: :redis_rb, extract_target: :first_arg}},
    {~r/redis\.incr$/,
     %{operation: :increment, framework: :redis_rb, extract_target: :first_arg}},
    {~r/redis\.decr$/, %{operation: :decrement, framework: :redis_rb, extract_target: :first_arg}}
  ]

  # ----- JavaScript/node-cache Patterns -----

  @javascript_nodecache_patterns [
    {"cache.get", %{operation: :get, framework: :node_cache, extract_target: :first_arg}},
    {"cache.set", %{operation: :set, framework: :node_cache, extract_target: :first_arg}},
    {"cache.del", %{operation: :delete, framework: :node_cache, extract_target: :first_arg}},
    {"cache.flushAll", %{operation: :clear, framework: :node_cache, extract_target: :none}},
    {"cache.has", %{operation: :exists, framework: :node_cache, extract_target: :first_arg}},
    {"cache.ttl", %{operation: :ttl, framework: :node_cache, extract_target: :first_arg}},
    {"cache.getTtl", %{operation: :ttl, framework: :node_cache, extract_target: :first_arg}},
    {"myCache.get", %{operation: :get, framework: :node_cache, extract_target: :first_arg}},
    {"myCache.set", %{operation: :set, framework: :node_cache, extract_target: :first_arg}},
    {"myCache.del", %{operation: :delete, framework: :node_cache, extract_target: :first_arg}}
  ]

  # ----- JavaScript/ioredis Patterns -----

  @javascript_ioredis_patterns [
    {"redis.get", %{operation: :get, framework: :ioredis, extract_target: :first_arg}},
    {"redis.set", %{operation: :set, framework: :ioredis, extract_target: :first_arg}},
    {"redis.setex", %{operation: :set, framework: :ioredis, extract_target: :first_arg}},
    {"redis.del", %{operation: :delete, framework: :ioredis, extract_target: :first_arg}},
    {"redis.flushdb", %{operation: :clear, framework: :ioredis, extract_target: :none}},
    {"redis.flushall", %{operation: :clear, framework: :ioredis, extract_target: :none}},
    {"redis.exists", %{operation: :exists, framework: :ioredis, extract_target: :first_arg}},
    {"redis.expire", %{operation: :expire, framework: :ioredis, extract_target: :first_arg}},
    {"redis.ttl", %{operation: :ttl, framework: :ioredis, extract_target: :first_arg}},
    {"redis.incr", %{operation: :increment, framework: :ioredis, extract_target: :first_arg}},
    {"redis.incrby", %{operation: :increment, framework: :ioredis, extract_target: :first_arg}},
    {"redis.decr", %{operation: :decrement, framework: :ioredis, extract_target: :first_arg}},
    {"redis.decrby", %{operation: :decrement, framework: :ioredis, extract_target: :first_arg}},
    # Client instance patterns
    {"client.get", %{operation: :get, framework: :ioredis, extract_target: :first_arg}},
    {"client.set", %{operation: :set, framework: :ioredis, extract_target: :first_arg}},
    {"client.del", %{operation: :delete, framework: :ioredis, extract_target: :first_arg}},
    {"client.exists", %{operation: :exists, framework: :ioredis, extract_target: :first_arg}},
    {"client.expire", %{operation: :expire, framework: :ioredis, extract_target: :first_arg}},
    {"client.incr", %{operation: :increment, framework: :ioredis, extract_target: :first_arg}},
    {"client.decr", %{operation: :decrement, framework: :ioredis, extract_target: :first_arg}}
  ]

  # ----- Registration -----

  @doc """
  Registers all cache patterns for all languages.

  Called automatically when the module is loaded. Can also be called
  manually to re-register patterns (e.g., after clearing).
  """
  @spec register_all() :: :ok
  def register_all do
    # Elixir patterns (Cachex + ConCache + Nebulex + ETS)
    Patterns.register(
      :cache,
      :elixir,
      @elixir_cachex_patterns ++
        @elixir_concache_patterns ++ @elixir_nebulex_patterns ++ @elixir_ets_patterns
    )

    # Python patterns (redis-py + Django + Flask)
    Patterns.register(
      :cache,
      :python,
      @python_redis_patterns ++ @python_django_cache_patterns ++ @python_flask_cache_patterns
    )

    # Ruby patterns (Rails.cache + Dalli + redis-rb)
    Patterns.register(
      :cache,
      :ruby,
      @ruby_rails_cache_patterns ++ @ruby_dalli_patterns ++ @ruby_redis_patterns
    )

    # JavaScript patterns (node-cache + ioredis)
    Patterns.register(
      :cache,
      :javascript,
      @javascript_nodecache_patterns ++ @javascript_ioredis_patterns
    )

    :ok
  end

  @doc false
  def __on_definition__(_env, _kind, _name, _args, _guards, _body) do
    :ok
  end
end

# Register patterns when module is loaded
Metastatic.Semantic.Domains.Cache.register_all()
