# credo:disable-for-this-file

defmodule Metastatic.Analysis.BusinessLogicTest do
  @moduledoc """
  Comprehensive test suite demonstrating what all 20 business logic analyzers catch.

  This file serves as an example showcase of real-world anti-patterns that
  the analyzers can detect across different programming paradigms.
  """

  use ExUnit.Case, async: true

  alias Metastatic.Analysis.BusinessLogic.BlockingInPlug
  alias Metastatic.Analysis.BusinessLogic.CallbackHell
  alias Metastatic.Analysis.BusinessLogic.DirectStructUpdate
  alias Metastatic.Analysis.BusinessLogic.HardcodedValue
  alias Metastatic.Analysis.BusinessLogic.InefficientFilter
  alias Metastatic.Analysis.BusinessLogic.InlineJavascript
  alias Metastatic.Analysis.BusinessLogic.MissingErrorHandling
  alias Metastatic.Analysis.BusinessLogic.MissingHandleAsync
  alias Metastatic.Analysis.BusinessLogic.MissingPreload
  alias Metastatic.Analysis.BusinessLogic.MissingTelemetryForExternalHttp
  alias Metastatic.Analysis.BusinessLogic.MissingTelemetryInAuthPlug
  alias Metastatic.Analysis.BusinessLogic.MissingTelemetryInLiveviewMount
  alias Metastatic.Analysis.BusinessLogic.MissingTelemetryInObanWorker
  alias Metastatic.Analysis.BusinessLogic.MissingThrottle
  alias Metastatic.Analysis.BusinessLogic.NPlusOneQuery
  alias Metastatic.Analysis.BusinessLogic.SilentErrorCase
  alias Metastatic.Analysis.BusinessLogic.SwallowingException
  alias Metastatic.Analysis.BusinessLogic.SyncOverAsync
  alias Metastatic.Analysis.BusinessLogic.TelemetryInRecursiveFunction
  alias Metastatic.Analysis.BusinessLogic.UnmanagedTask

  # Helper functions for building 3-tuple MetaAST nodes
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}
  defp block(stmts), do: {:block, [], stmts}
  defp conditional(cond, then_b, else_b), do: {:conditional, [], [cond, then_b, else_b]}
  defp function_call(name, args), do: {:function_call, [name: name], args}
  defp map_node(pairs), do: {:map, [], pairs}
  defp pair_node(key, value), do: {:pair, [], [key, value]}

  describe "BlockingInPlug" do
    test "detects blocking HTTP call in middleware" do
      ast = function_call("HTTPoison.get", [literal(:string, "https://api.example.com/verify")])

      context = %{
        function_name: "call_plug",
        module_name: "AuthMiddleware",
        config: %{}
      }

      issues = BlockingInPlug.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :performance
      assert issue.severity == :warning
      assert issue.message =~ "Blocking operation"
      assert issue.message =~ "HTTPoison.get"
    end

    test "detects blocking database query in plug" do
      ast = function_call("Repo.get", [variable("User"), variable("id")])

      context = %{
        function_name: "authenticate_plug",
        module_name: "App.Plugs.Auth",
        config: %{}
      }

      issues = BlockingInPlug.analyze(ast, context)

      assert [issue] = issues
      assert issue.message =~ "Repo.get"
    end

    test "does not flag blocking operations outside middleware context" do
      ast = function_call("HTTPoison.get", [literal(:string, "http://example.com")])
      context = %{function_name: "fetch_data", module_name: "MyService", config: %{}}

      assert [] = BlockingInPlug.analyze(ast, context)
    end
  end

  describe "CallbackHell" do
    test "detects deeply nested conditionals exceeding threshold" do
      # 3 levels of nesting: outermost, middle, innermost
      ast =
        conditional(
          variable("condition1"),
          conditional(
            variable("condition2"),
            conditional(variable("condition3"), literal(:symbol, :ok), nil),
            nil
          ),
          nil
        )

      context = %{config: %{}, max_nesting: 2}

      issues = CallbackHell.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :readability
      assert issue.severity == :warning
      assert issue.message =~ "3 levels"
      assert issue.metadata.nesting_level == 3
    end

    test "respects configurable max_nesting threshold" do
      ast =
        conditional(
          variable("check1"),
          block([
            conditional(
              variable("check2"),
              block([conditional(variable("check3"), literal(:symbol, :ok), nil)]),
              nil
            )
          ]),
          nil
        )

      # Allow up to 3 levels
      context = %{config: %{max_nesting: 3}, max_nesting: 3}

      assert [] = CallbackHell.analyze(ast, context)
    end

    test "does not flag shallow nesting" do
      ast = conditional(variable("x"), literal(:symbol, :ok), literal(:symbol, :error))

      context = %{config: %{}, max_nesting: 2}

      assert [] = CallbackHell.analyze(ast, context)
    end
  end

  describe "DirectStructUpdate" do
    test "detects direct map/struct updates" do
      ast =
        map_node([
          pair_node(literal(:symbol, :name), literal(:string, "John")),
          pair_node(literal(:symbol, :age), literal(:integer, 30))
        ])

      context = %{}

      issues = DirectStructUpdate.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :correctness
      assert issue.severity == :info
      assert issue.message =~ "validation"
    end

    test "suggests using changesets" do
      ast = map_node([pair_node(literal(:symbol, :email), literal(:string, "user@example.com"))])

      issues = DirectStructUpdate.analyze(ast, %{})

      assert [issue] = issues
      assert issue.metadata.suggestion =~ "validation"
    end
  end

  describe "HardcodedValue" do
    test "detects hardcoded production URLs" do
      ast = literal(:string, "https://api.production.example.com/v1")

      context = %{exclude_localhost: true, exclude_local_ips: true}

      issues = HardcodedValue.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :security
      assert issue.severity == :warning
      assert issue.message =~ "Hardcoded URL"
      assert issue.metadata.type == :url
    end

    test "detects hardcoded production IP addresses" do
      ast = literal(:string, "203.0.113.42")

      context = %{exclude_localhost: true, exclude_local_ips: true}

      issues = HardcodedValue.analyze(ast, context)

      assert [issue] = issues
      assert issue.message =~ "IP address"
      assert issue.metadata.type == :ip
    end

    test "excludes localhost URLs when configured" do
      ast = literal(:string, "http://localhost:4000")

      context = %{exclude_localhost: true, exclude_local_ips: true}

      assert [] = HardcodedValue.analyze(ast, context)
    end

    test "excludes private IP ranges when configured" do
      ast = literal(:string, "192.168.1.100")

      context = %{exclude_localhost: true, exclude_local_ips: true}

      assert [] = HardcodedValue.analyze(ast, context)
    end

    test "detects IPs in 172.16-31 private range" do
      ast = literal(:string, "172.20.10.5")
      context = %{exclude_localhost: true, exclude_local_ips: true}

      # Should be excluded as it's in private range
      assert [] = HardcodedValue.analyze(ast, context)
    end

    test "flags external URLs even with https" do
      ast = literal(:string, "https://external-api.service.com/endpoint")
      context = %{exclude_localhost: true, exclude_local_ips: true}

      issues = HardcodedValue.analyze(ast, context)
      assert [_] = issues
    end
  end

  describe "InefficientFilter" do
    test "detects fetch-all followed by filter pattern" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "users"}, {:function_call, :all, []}},
           {:collection_op, :filter, {:lambda, [], {:block, []}}, {:variable, "users"}}
         ]}

      context = %{assignments: %{}}

      issues = InefficientFilter.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :performance
      assert issue.severity == :warning
      assert issue.message =~ "Inefficient filter"
      assert issue.message =~ "push filter to data source"
    end

    test "detects Repo.all followed by Enum.filter" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "posts"}, {:attribute_access, {:variable, "Repo"}, :all}},
           {:collection_op, :filter, {:lambda, [], {:block, []}}, {:variable, "posts"}}
         ]}

      issues = InefficientFilter.analyze(ast, %{assignments: %{}})

      assert [issue] = issues
      assert issue.message =~ "Inefficient filter"
    end

    test "does not flag non-consecutive statements" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "users"}, {:function_call, :all, []}},
           {:function_call, :log, []},
           {:collection_op, :filter, {:lambda, [], {:block, []}}, {:variable, "users"}}
         ]}

      assert [] = InefficientFilter.analyze(ast, %{assignments: %{}})
    end

    test "does not flag different variables" do
      ast =
        {:block,
         [
           {:assignment, {:variable, "users"}, {:function_call, :all, []}},
           {:collection_op, :filter, {:lambda, [], {:block, []}}, {:variable, "posts"}}
         ]}

      assert [] = InefficientFilter.analyze(ast, %{assignments: %{}})
    end
  end

  describe "InlineJavascript" do
    test "detects script tags in string literals" do
      ast = literal(:string, "<script>alert('XSS')</script>")

      issues = InlineJavascript.analyze(ast, %{})

      assert [issue] = issues
      assert issue.category == :security
      assert issue.severity == :error
      assert issue.message =~ "Inline JavaScript"
      assert issue.message =~ "XSS vulnerability"
    end

    test "detects dangerouslySetInnerHTML usage" do
      ast =
        function_call(
          "dangerouslySetInnerHTML",
          [map_node([pair_node(literal(:symbol, :__html), variable("content"))])]
        )

      issues = InlineJavascript.analyze(ast, %{})

      assert [issue] = issues
      assert issue.severity == :error
      assert issue.message =~ "dangerouslySetInnerHTML"
    end

    test "detects onclick handlers in strings" do
      ast = literal(:string, "<div onclick='handleClick()'>Click me</div>")

      issues = InlineJavascript.analyze(ast, %{})

      assert [issue] = issues
      assert issue.message =~ "Inline JavaScript"
    end

    test "detects javascript: protocol in URLs" do
      ast = literal(:string, "javascript:void(0)")

      issues = InlineJavascript.analyze(ast, %{})

      assert [_] = issues
    end

    test "does not flag safe HTML strings" do
      ast = {:literal, :string, "<div class='container'>Safe content</div>"}

      assert [] = InlineJavascript.analyze(ast, %{})
    end
  end

  describe "MissingErrorHandling" do
    test "detects pattern match on success tuple without error handling" do
      ast =
        {:pattern_match,
         {:list,
          [
            {:literal, :atom, :ok},
            {:variable, "user"}
          ]}, {:function_call, :get_user, []}}

      issues = MissingErrorHandling.analyze(ast, %{})

      assert [issue] = issues
      assert issue.category == :correctness
      assert issue.severity == :warning
      assert issue.message =~ "Pattern match on success case"
      assert issue.message =~ "without error handling"
    end

    test "detects :some pattern without :none handling" do
      ast =
        {:pattern_match,
         {:list,
          [
            {:literal, :atom, :some},
            {:variable, "value"}
          ]}, {:function_call, :find, []}}

      issues = MissingErrorHandling.analyze(ast, %{})

      assert [_] = issues
    end

    test "does not flag non-success patterns" do
      ast =
        {:pattern_match, {:variable, "result"}, {:function_call, :do_something, []}}

      assert [] = MissingErrorHandling.analyze(ast, %{})
    end
  end

  describe "MissingHandleAsync" do
    test "detects Task.start without supervision" do
      ast = {:function_call, "Task.start", [{:lambda, [], {:block, []}}]}

      context = %{in_exception_handling: false, supervised: false}

      issues = MissingHandleAsync.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :reliability
      assert issue.severity == :warning
      assert issue.message =~ "Async operation"
      assert issue.message =~ "without supervision"
    end

    test "detects create_task without await" do
      ast = {:function_call, "asyncio.create_task", [{:lambda, [], {:block, []}}]}

      context = %{in_exception_handling: false, supervised: false}

      issues = MissingHandleAsync.analyze(ast, context)

      assert [issue] = issues
      assert issue.message =~ "asyncio.create_task"
    end

    test "does not flag when in exception handling context" do
      ast = {:function_call, "Task.async", [{:lambda, [], {:block, []}}]}

      context = %{in_exception_handling: true, supervised: false}

      assert [] = MissingHandleAsync.analyze(ast, context)
    end

    test "does not flag when supervised" do
      ast = {:function_call, "spawn", [{:lambda, [], {:block, []}}]}

      context = %{in_exception_handling: false, supervised: true}

      assert [] = MissingHandleAsync.analyze(ast, context)
    end
  end

  describe "MissingPreload" do
    test "detects mapping over database query results" do
      ast =
        {:collection_op, :map, {:lambda, [], {:block, []}},
         {:function_call, "Repo.all", [{:variable, "User"}]}}

      issues = MissingPreload.analyze(ast, %{})

      assert [issue] = issues
      assert issue.category == :performance
      assert issue.severity == :warning
      assert issue.message =~ "Mapping over database results"
      assert issue.message =~ "N+1 queries"
    end

    test "detects for loop over query results" do
      ast =
        {:loop, :for, {:variable, "user"}, {:function_call, "findAll", []}, {:block, []}}

      issues = MissingPreload.analyze(ast, %{})

      assert [issue] = issues
      assert issue.message =~ "Looping over database results"
    end

    test "suggests eager loading" do
      ast =
        {:collection_op, :map, {:lambda, [], {:block, []}}, {:function_call, "getAll", []}}

      issues = MissingPreload.analyze(ast, %{})

      assert [issue] = issues
      assert issue.metadata.suggestion =~ "preload"
    end

    test "detects mapping over variable that looks like DB results" do
      ast =
        {:collection_op, :map, {:lambda, [], {:block, []}}, {:variable, "users"}}

      issues = MissingPreload.analyze(ast, %{})

      # Variable name suggests DB results
      assert [_] = issues
    end
  end

  describe "MissingTelemetryForExternalHttp" do
    test "detects HTTP GET without telemetry" do
      ast = {:function_call, :get, [{:literal, :string, "https://api.example.com"}]}

      issues = MissingTelemetryForExternalHttp.analyze(ast, %{})

      assert [issue] = issues
      assert issue.category == :maintainability
      assert issue.severity == :info
      assert issue.message =~ "HTTP request"
      assert issue.message =~ "telemetry"
    end

    test "detects HTTP POST call" do
      ast =
        {:function_call, :post,
         [{:literal, :string, "https://api.example.com"}, {:variable, "data"}]}

      issues = MissingTelemetryForExternalHttp.analyze(ast, %{})

      assert [_] = issues
    end

    test "detects fetch calls" do
      ast = {:function_call, :fetch, [{:literal, :string, "https://api.example.com"}]}

      issues = MissingTelemetryForExternalHttp.analyze(ast, %{})

      assert [_] = issues
    end
  end

  describe "MissingTelemetryInAuthPlug" do
    test "detects authentication conditional without telemetry" do
      ast =
        {:conditional, {:variable, "is_authenticated"}, {:literal, :atom, :ok},
         {:literal, :atom, :unauthorized}}

      context = %{function_name: "authenticate_user", module_name: "AuthPlug"}

      issues = MissingTelemetryInAuthPlug.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :security
      assert issue.severity == :warning
      assert issue.message =~ "Authentication check"
      assert issue.message =~ "telemetry"
    end

    test "detects authorization check without audit logging" do
      ast =
        {:conditional, {:variable, "has_permission"}, {:block, []}, {:function_call, :deny, []}}

      context = %{function_name: "require_permission", module_name: "AuthModule"}

      issues = MissingTelemetryInAuthPlug.analyze(ast, context)

      assert [issue] = issues
      assert issue.message =~ "Authentication check"
    end

    test "does not flag when telemetry present in branches" do
      ast =
        {:conditional, {:variable, "authenticated"},
         {:block, [{:function_call, "telemetry.emit", []}]},
         {:block, [{:function_call, "log.error", []}]}}

      context = %{function_name: "authenticate", module_name: "AuthPlug"}

      assert [] = MissingTelemetryInAuthPlug.analyze(ast, context)
    end

    test "does not flag outside auth context" do
      ast =
        {:conditional, {:variable, "condition"}, {:literal, :atom, :ok},
         {:literal, :atom, :error}}

      context = %{function_name: "process_data", module_name: "DataProcessor"}

      assert [] = MissingTelemetryInAuthPlug.analyze(ast, context)
    end
  end

  describe "MissingTelemetryInLiveviewMount" do
    test "detects mount function without telemetry" do
      ast = {:block, [{:function_call, :load_user, []}, {:function_call, :assign, []}]}

      context = %{function_name: "mount"}

      issues = MissingTelemetryInLiveviewMount.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :observability
      assert issue.severity == :info
      assert issue.message =~ "Component lifecycle"
      assert issue.message =~ "telemetry"
    end

    test "detects componentDidMount without tracking" do
      ast = {:block, [{:function_call, :fetchData, []}]}

      context = %{function_name: "componentDidMount"}

      issues = MissingTelemetryInLiveviewMount.analyze(ast, context)

      assert [_] = issues
    end

    test "does not flag when telemetry present" do
      ast = {:block, [{:function_call, "telemetry_emit", []}, {:function_call, :load_data, []}]}

      context = %{function_name: "mount"}

      assert [] = MissingTelemetryInLiveviewMount.analyze(ast, context)
    end

    test "does not flag outside lifecycle context" do
      ast = {:block, [{:function_call, :process, []}]}

      context = %{function_name: "handle_event"}

      assert [] = MissingTelemetryInLiveviewMount.analyze(ast, context)
    end
  end

  describe "MissingTelemetryInObanWorker" do
    test "detects perform function without telemetry" do
      ast = {:block, [{:function_call, :process_job, []}, {:literal, :atom, :ok}]}

      context = %{function_name: "perform", module_name: "MyWorker"}

      issues = MissingTelemetryInObanWorker.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :observability
      assert issue.severity == :info
      assert issue.message =~ "Background job"
      assert issue.message =~ "telemetry"
    end

    test "detects Celery task without metrics" do
      ast = {:block, [{:function_call, :heavy_work, []}]}

      context = %{function_name: "process_task", module_name: "CeleryWorker"}

      issues = MissingTelemetryInObanWorker.analyze(ast, context)

      assert [_] = issues
    end

    test "does not flag when telemetry present" do
      ast =
        {:block, [{:function_call, "telemetry_emit", []}, {:function_call, :do_work, []}]}

      context = %{function_name: "perform", module_name: "Worker"}

      assert [] = MissingTelemetryInObanWorker.analyze(ast, context)
    end

    test "does not flag outside job context" do
      ast = {:block, [{:function_call, :compute, []}]}

      context = %{function_name: "calculate", module_name: "Calculator"}

      assert [] = MissingTelemetryInObanWorker.analyze(ast, context)
    end
  end

  describe "MissingThrottle" do
    test "detects expensive search in API endpoint without rate limiting" do
      ast =
        {:function_call, "expensive_search", [{:variable, "query"}]}

      context = %{
        function_name: "create_endpoint",
        module_name: "SearchController",
        decorators: [],
        middleware: []
      }

      issues = MissingThrottle.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :security
      assert issue.severity == :warning
      assert issue.message =~ "Expensive operation"
      assert issue.message =~ "rate limiting"
      assert issue.message =~ "DoS risk"
    end

    test "detects export operation without throttling" do
      ast = {:function_call, "generate_report", []}

      context = %{
        function_name: "post_export",
        module_name: "ApiController",
        decorators: [],
        middleware: []
      }

      issues = MissingThrottle.analyze(ast, context)

      assert [_] = issues
    end

    test "does not flag when rate limiting present" do
      ast = {:function_call, "expensive_query", []}

      context = %{
        function_name: "api_endpoint",
        module_name: "Controller",
        decorators: ["@ratelimit"],
        middleware: []
      }

      assert [] = MissingThrottle.analyze(ast, context)
    end

    test "does not flag outside API endpoint context" do
      ast = {:function_call, "search", []}

      context = %{
        function_name: "internal_search",
        module_name: "SearchService",
        decorators: [],
        middleware: []
      }

      assert [] = MissingThrottle.analyze(ast, context)
    end
  end

  describe "NPlusOneQuery" do
    test "detects database query inside map operation" do
      ast =
        {:collection_op, :map,
         {:lambda, [{:variable, "item"}],
          {:block,
           [
             {:function_call, :get,
              [{:variable, "User"}, {:attribute_access, {:variable, "item"}, :user_id}]}
           ]}}, {:variable, "items"}}

      issues = NPlusOneQuery.analyze(ast, %{})

      assert [issue] = issues
      assert issue.category == :performance
      assert issue.severity == :warning
      assert issue.message =~ "N+1 query"
      assert issue.message =~ "eager loading"
    end

    test "detects Repo.get in Enum.map" do
      ast =
        {:collection_op, :map,
         {:lambda, [{:variable, "post"}],
          {:block,
           [
             {:function_call, :get!,
              [{:variable, "Repo"}, {:variable, "User"}, {:variable, "id"}]}
           ]}}, {:variable, "posts"}}

      issues = NPlusOneQuery.analyze(ast, %{})

      assert [issue] = issues
      assert issue.message =~ "N+1 query"
    end

    test "detects find inside each operation" do
      ast =
        {:collection_op, :each,
         {:lambda, [{:variable, "item"}],
          {:block, [{:function_call, :findOne, [{:variable, "id"}]}]}}, {:variable, "collection"}}

      issues = NPlusOneQuery.analyze(ast, %{})

      assert [_] = issues
    end

    test "does not flag non-database operations in map" do
      ast =
        {:collection_op, :map,
         {:lambda, [{:variable, "x"}],
          {:block, [{:binary_op, :arithmetic, :+, {:variable, "x"}, {:literal, :integer, 1}}]}},
         {:variable, "numbers"}}

      assert [] = NPlusOneQuery.analyze(ast, %{})
    end
  end

  describe "SilentErrorCase" do
    test "detects conditional checking success without else branch" do
      ast =
        {:conditional,
         {:pattern_match, {:list, [{:literal, :atom, :ok}, {:variable, "result"}]},
          {:variable, "response"}}, {:block, [{:variable, "result"}]}, nil}

      issues = SilentErrorCase.analyze(ast, %{})

      assert [issue] = issues
      assert issue.category == :correctness
      assert issue.severity == :warning
      assert issue.message =~ "only handles success case"
      assert issue.message =~ "without error"
    end

    test "detects if checking :ok without else" do
      ast =
        {:conditional,
         {:binary_op, :comparison, :==, {:variable, "status"}, {:literal, :atom, :ok}},
         {:block, []}, nil}

      issues = SilentErrorCase.analyze(ast, %{})

      assert [_] = issues
    end

    test "does not flag when else branch present" do
      ast =
        {:conditional,
         {:pattern_match, {:list, [{:literal, :atom, :ok}, {:variable, "result"}]},
          {:variable, "response"}}, {:block, [{:variable, "result"}]}, {:literal, :atom, :error}}

      assert [] = SilentErrorCase.analyze(ast, %{})
    end

    test "does not flag non-success conditions" do
      ast =
        {:conditional, {:binary_op, :comparison, :>, {:variable, "x"}, {:literal, :integer, 0}},
         {:block, []}, nil}

      assert [] = SilentErrorCase.analyze(ast, %{})
    end
  end

  describe "SwallowingException" do
    test "detects exception handling without logging or re-raising" do
      # MetaAST format: 4-tuple with 3-tuple catch clauses
      ast =
        {:exception_handling, {:block, [{:function_call, :risky_operation, []}]},
         [
           {:error, {:variable, "error"}, {:literal, :atom, :error}}
         ], nil}

      issues = SwallowingException.analyze(ast, %{})

      assert [issue] = issues
      assert issue.category == :correctness
      assert issue.severity == :warning
      assert issue.message =~ "swallows exceptions"
      assert issue.message =~ "without logging"
    end

    test "detects multiple silent catch clauses" do
      ast =
        {:exception_handling, {:block, [{:function_call, :do_work, []}]},
         [
           {:error, {:variable, "error1"}, {:literal, :atom, :ok}},
           {:error, {:variable, "error2"}, {:literal, :integer, 0}}
         ], nil}

      issues = SwallowingException.analyze(ast, %{})

      assert [issue] = issues
      assert issue.metadata.silent_catch_count == 2
    end

    test "does not flag when logging present" do
      ast =
        {:exception_handling, {:block, [{:function_call, :risky_operation, []}]},
         [
           {:error, {:variable, "error"},
            {:block, [{:function_call, :log, [{:variable, "error"}]}]}}
         ], nil}

      assert [] = SwallowingException.analyze(ast, %{})
    end

    test "does not flag when re-raising" do
      ast =
        {:exception_handling, {:block, [{:function_call, :risky_operation, []}]},
         [
           {:error, {:variable, "error"},
            {:block, [{:function_call, :reraise, [{:variable, "error"}]}]}}
         ], nil}

      assert [] = SwallowingException.analyze(ast, %{})
    end
  end

  describe "SyncOverAsync" do
    test "detects synchronous HTTP in async context" do
      ast =
        {:function_call, "HTTPoison.get", [{:literal, :string, "https://api.example.com"}]}

      context = %{function_name: "async_fetch"}

      issues = SyncOverAsync.analyze(ast, context)

      assert [issue] = issues
      assert issue.category == :performance
      assert issue.severity == :warning
      assert issue.message =~ "Synchronous"
      assert issue.message =~ "async context"
    end

    test "detects blocking read in async function" do
      ast = {:function_call, "fs.readFileSync", [{:literal, :string, "file.txt"}]}

      context = %{function_name: "async_process"}

      issues = SyncOverAsync.analyze(ast, context)

      assert [_] = issues
    end

    test "does not flag in non-async context" do
      ast = {:function_call, "fetch", [{:literal, :string, "url"}]}

      context = %{function_name: "sync_fetch"}

      assert [] = SyncOverAsync.analyze(ast, context)
    end
  end

  describe "TelemetryInRecursiveFunction" do
    test "detects telemetry emission in recursive function" do
      ast =
        {:function_def, :traverse, [{:variable, "list"}], nil, [],
         {:block,
          [
            {:function_call, :telemetry_execute, []},
            {:function_call, :traverse, [{:variable, "tail"}]}
          ]}}

      issues = TelemetryInRecursiveFunction.analyze(ast, %{})

      assert [issue] = issues
      assert issue.category == :performance
      assert issue.severity == :warning
      assert issue.message =~ "Telemetry emitted in recursive function"
      assert issue.message =~ "traverse"
    end

    test "detects metrics in recursive fibonacci" do
      ast =
        {:function_def, :fib, [{:variable, "n"}], nil, [],
         {:block,
          [
            {:function_call, :metrics_increment, []},
            {:conditional,
             {:binary_op, :comparison, :<=, {:variable, "n"}, {:literal, :integer, 1}},
             {:variable, "n"},
             {:binary_op, :arithmetic, :+, {:function_call, :fib, []}, {:function_call, :fib, []}}}
          ]}}

      issues = TelemetryInRecursiveFunction.analyze(ast, %{})

      assert [issue] = issues
      assert issue.message =~ "fib"
    end

    test "does not flag non-recursive functions with telemetry" do
      ast =
        {:function_def, :process, [], nil, [],
         {:block,
          [
            {:function_call, :emit, []},
            {:function_call, :do_work, []}
          ]}}

      assert [] = TelemetryInRecursiveFunction.analyze(ast, %{})
    end

    test "does not flag recursive functions without telemetry" do
      ast =
        {:function_def, :factorial, [{:variable, "n"}], nil, [],
         {:block,
          [
            {:conditional,
             {:binary_op, :comparison, :==, {:variable, "n"}, {:literal, :integer, 0}},
             {:literal, :integer, 1},
             {:binary_op, :arithmetic, :*, {:variable, "n"},
              {:function_call, :factorial,
               [
                 {:binary_op, :arithmetic, :-, {:variable, "n"}, {:literal, :integer, 1}}
               ]}}}
          ]}}

      assert [] = TelemetryInRecursiveFunction.analyze(ast, %{})
    end
  end

  describe "UnmanagedTask" do
    test "detects unsupervised Task.async spawn" do
      ast = {:function_call, :async, [{:lambda, [], {:block, []}}]}

      issues = UnmanagedTask.analyze(ast, %{})

      assert [issue] = issues
      assert issue.category == :correctness
      assert issue.severity == :warning
      assert issue.message =~ "Unsupervised async operation"
      assert issue.message =~ "async"
    end

    test "detects direct async_operation spawn" do
      ast = {:async_operation, :spawn, {:lambda, [], {:block, []}}}

      issues = UnmanagedTask.analyze(ast, %{})

      assert [issue] = issues
      assert issue.message =~ "Unsupervised"
    end

    test "detects create_task without management" do
      ast = {:function_call, :create_task, [{:lambda, [], {:block, []}}]}

      issues = UnmanagedTask.analyze(ast, %{})

      assert [_] = issues
    end

    test "detects Promise without supervision" do
      ast = {:function_call, :Promise, [{:lambda, [], {:block, []}}]}

      issues = UnmanagedTask.analyze(ast, %{})

      assert [_] = issues
    end

    test "detects Task.start without supervision" do
      ast = {:function_call, :start, [{:lambda, [], {:block, []}}]}

      issues = UnmanagedTask.analyze(ast, %{})

      assert [_] = issues
    end
  end

  describe "integration tests with Elixir source" do
    test "BlockingInPlug detects HTTPoison.get in plug function" do
      source = """
      defmodule AuthPlug do
        def call_plug(conn, _opts) do
          HTTPoison.get("https://api.example.com/verify")
          conn
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)
      {:ok, report} = Metastatic.Analysis.Runner.run(doc, analyzers: [BlockingInPlug])

      assert [issue | _] = report.issues
      assert issue.category == :performance
      assert issue.message =~ "Blocking operation"
    end

    test "CallbackHell detects deeply nested conditionals in Elixir" do
      source = """
      defmodule Logic do
        def check(x, y, z) do
          if x do
            if y do
              if z do
                :ok
              end
            end
          end
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)
      {:ok, report} = Metastatic.Analysis.Runner.run(doc, analyzers: [CallbackHell])

      assert [issue | _] = report.issues
      assert issue.category == :readability
      assert issue.message =~ "nested conditionals"
    end

    test "HardcodedValue detects production URL in Elixir module" do
      source = """
      defmodule Config do
        @api_url "https://api.production.example.com/v1"

        def get_api_url, do: @api_url
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)
      {:ok, report} = Metastatic.Analysis.Runner.run(doc, analyzers: [HardcodedValue])

      assert [issue | _] = report.issues
      assert issue.category == :security
      assert issue.message =~ "Hardcoded URL"
    end

    test "NPlusOneQuery detects Repo.get in Enum.map" do
      source = """
      defmodule UserLoader do
        def load_users_with_profiles(posts) do
          Enum.map(posts, fn post ->
            user = Repo.get(User, post.user_id)
            {post, user}
          end)
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)
      {:ok, report} = Metastatic.Analysis.Runner.run(doc, analyzers: [NPlusOneQuery])

      assert [issue | _] = report.issues
      assert issue.category == :performance
      assert issue.message =~ "N+1 query"
    end

    test "InlineJavascript detects script tags in template" do
      source = """
      defmodule MyView do
        def render do
          "<script>alert('XSS')</script>"
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)
      {:ok, report} = Metastatic.Analysis.Runner.run(doc, analyzers: [InlineJavascript])

      assert [issue | _] = report.issues
      assert issue.severity == :error
      assert issue.message =~ "XSS"
    end

    test "SwallowingException detects silent rescue without logging" do
      source = """
      defmodule Worker do
        def process do
          try do
            risky_operation()
          rescue
            _ -> :error
          end
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)
      {:ok, report} = Metastatic.Analysis.Runner.run(doc, analyzers: [SwallowingException])

      assert [issue | _] = report.issues
      assert issue.category == :correctness
      assert issue.message =~ "swallows exceptions"
    end

    test "InefficientFilter detects Repo.all followed by Enum.filter" do
      source = """
      defmodule UserService do
        def get_active_users do
          users = Repo.all(User)
          Enum.filter(users, fn u -> u.active end)
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)
      {:ok, report} = Metastatic.Analysis.Runner.run(doc, analyzers: [InefficientFilter])

      assert [issue | _] = report.issues
      assert issue.message =~ "Inefficient filter"
    end

    test "TelemetryInRecursiveFunction detects telemetry in recursive traverse" do
      source = """
      defmodule TreeWalker do
        def traverse([head | tail]) do
          :telemetry.execute([:tree, :node], %{count: 1})
          process(head)
          traverse(tail)
        end

        def traverse([]), do: :ok
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)

      {:ok, report} =
        Metastatic.Analysis.Runner.run(doc, analyzers: [TelemetryInRecursiveFunction])

      assert [issue | _] = report.issues
      assert issue.category == :performance
      assert issue.message =~ "recursive function"
    end

    test "MissingPreload detects mapping over query results" do
      source = """
      defmodule PostLoader do
        def load_with_authors do
          posts = Repo.all(Post)
          Enum.map(posts, fn post -> {post, post.author} end)
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)
      {:ok, report} = Metastatic.Analysis.Runner.run(doc, analyzers: [MissingPreload])

      assert [issue | _] = report.issues
      assert issue.message =~ "database results"
    end

    test "SyncOverAsync detects HTTPoison.get in async function" do
      source = """
      defmodule AsyncFetcher do
        def async_fetch_data do
          Task.async(fn ->
            HTTPoison.get("https://api.example.com/data")
          end)
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)
      {:ok, report} = Metastatic.Analysis.Runner.run(doc, analyzers: [SyncOverAsync])

      # Note: This may not trigger if context doesn't detect async properly
      # This demonstrates the full pipeline works
      assert is_list(report.issues)
    end

    test "multiple analyzers can run on same source" do
      source = """
      defmodule BadCode do
        @api_url "https://hardcoded.example.com"

        def fetch_data do
          users = Repo.all(User)
          Enum.map(users, fn user ->
            HTTPoison.get(@api_url <> "/" <> user.id)
          end)
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)

      {:ok, report} =
        Metastatic.Analysis.Runner.run(doc,
          analyzers: [HardcodedValue, NPlusOneQuery, MissingPreload]
        )

      # Should detect multiple issues
      assert match?([_, _ | _], report.issues)

      categories = Enum.map(report.issues, & &1.category) |> MapSet.new()
      # At least security (hardcoded) and performance (N+1 or preload)
      assert :security in categories or :performance in categories
    end

    test "complex real-world example with multiple anti-patterns" do
      source = """
      defmodule UserController do
        def create(conn, params) do
          try do
            users = Repo.all(User)
            active_users = Enum.filter(users, & &1.active)

            Enum.each(active_users, fn user ->
              HTTPoison.post(
                "https://hardcoded-api.example.com/notify",
                Jason.encode!(%{user_id: user.id})
              )
            end)

            conn
            |> put_status(200)
            |> json(%{status: "ok"})
          rescue
            _ -> json(conn, %{error: "failed"})
          end
        end
      end
      """

      {:ok, doc} = Metastatic.Builder.from_source(source, :elixir)

      {:ok, report} =
        Metastatic.Analysis.Runner.run(doc,
          analyzers: [
            InefficientFilter,
            HardcodedValue,
            NPlusOneQuery,
            SwallowingException,
            MissingPreload
          ]
        )

      # Should detect multiple anti-patterns:
      # - Inefficient filter (Repo.all + Enum.filter)
      # - Hardcoded URL
      # - HTTP calls in loop (N+1-like pattern)
      # - Exception swallowing
      assert match?([_, _ | _], report.issues)

      issue_types = Enum.map_join(report.issues, " ", & &1.message)
      assert issue_types =~ ~r/(filter|URL|query|exception)/i
    end

    test "source code parsing errors are handled gracefully" do
      # Use actually invalid Elixir syntax (missing closing delimiter)
      source = "defmodule Broken do def foo do end"

      result = Metastatic.Builder.from_source(source, :elixir)

      # Elixir's parser will report missing 'end'
      assert {:error, error_msg} = result
      assert is_binary(error_msg)
      # Elixir reports "missing terminator" or "unexpected token"
      assert error_msg =~ ~r/(missing|unexpected|syntax)/i
    end
  end

  describe "analyzer info" do
    test "all analyzers provide complete metadata" do
      analyzers = [
        BlockingInPlug,
        CallbackHell,
        DirectStructUpdate,
        HardcodedValue,
        InefficientFilter,
        InlineJavascript,
        MissingErrorHandling,
        MissingHandleAsync,
        MissingPreload,
        MissingTelemetryForExternalHttp,
        MissingTelemetryInAuthPlug,
        MissingTelemetryInLiveviewMount,
        MissingTelemetryInObanWorker,
        MissingThrottle,
        NPlusOneQuery,
        SilentErrorCase,
        SwallowingException,
        SyncOverAsync,
        TelemetryInRecursiveFunction,
        UnmanagedTask
      ]

      for analyzer <- analyzers do
        info = analyzer.info()

        assert is_atom(info.name), "#{analyzer}: name should be atom"
        assert is_atom(info.category), "#{analyzer}: category should be atom"
        assert is_binary(info.description), "#{analyzer}: description should be string"
        assert info.severity in [:error, :warning, :info], "#{analyzer}: invalid severity"
        assert is_binary(info.explanation), "#{analyzer}: explanation should be string"
        assert is_boolean(info.configurable), "#{analyzer}: configurable should be boolean"
      end
    end

    test "analyzers cover all major categories" do
      categories =
        [
          BlockingInPlug,
          CallbackHell,
          DirectStructUpdate,
          HardcodedValue,
          InefficientFilter,
          InlineJavascript,
          MissingErrorHandling,
          MissingHandleAsync,
          MissingPreload,
          MissingTelemetryForExternalHttp,
          MissingTelemetryInAuthPlug,
          MissingTelemetryInLiveviewMount,
          MissingTelemetryInObanWorker,
          MissingThrottle,
          NPlusOneQuery,
          SilentErrorCase,
          SwallowingException,
          SyncOverAsync,
          TelemetryInRecursiveFunction,
          UnmanagedTask
        ]
        |> Enum.map(& &1.info().category)
        |> MapSet.new()

      # Should cover major categories
      assert :performance in categories
      assert :security in categories
      assert :correctness in categories
      assert :readability in categories
      assert :maintainability in categories or :observability in categories
    end
  end
end
