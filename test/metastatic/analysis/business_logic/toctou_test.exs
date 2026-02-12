defmodule Metastatic.Analysis.BusinessLogic.TOCTOUTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.BusinessLogic.TOCTOU
  alias Metastatic.Document

  # Helper to create 3-tuple nodes
  defp conditional(condition, then_branch, else_branch \\ nil) do
    {:conditional, [], [condition, then_branch, else_branch]}
  end

  defp variable(name), do: {:variable, [], name}
  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp block(statements), do: {:block, [], statements}
  defp function_call(name, args), do: {:function_call, [name: name], args}
  defp assignment(target, value), do: {:assignment, [], [target, value]}

  describe "info/0" do
    test "returns analyzer metadata" do
      info = TOCTOU.info()

      assert info.name == :toctou
      assert info.category == :security
      assert info.severity == :warning
      assert info.configurable == false
      assert is_binary(info.description)
      assert is_binary(info.explanation)
    end
  end

  describe "analyze/2 - file existence checks" do
    setup do
      context = %{
        document: Document.new(literal(:integer, 1), :elixir),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      %{context: context}
    end

    test "detects File.exists? followed by File.read in conditional", %{context: context} do
      # if File.exists?(path) do
      #   File.read(path)
      # end
      ast =
        conditional(
          function_call("File.exists?", [variable("path")]),
          block([function_call("File.read", [variable("path")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.analyzer == TOCTOU
      assert issue.category == :security
      assert issue.severity == :warning
      assert issue.message =~ "TOCTOU vulnerability"
      assert issue.message =~ "File.exists?"
      assert issue.message =~ "File.read"
      assert issue.metadata.check_function == "File.exists?"
      assert issue.metadata.use_function == "File.read"
      assert issue.metadata.cwe == 367
    end

    test "detects os.path.exists followed by open in Python-style", %{context: context} do
      # if os.path.exists(file_path):
      #     open(file_path)
      ast =
        conditional(
          function_call("os.path.exists", [variable("file_path")]),
          block([function_call("open", [variable("file_path")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "os.path.exists"
      assert issue.message =~ "open"
    end

    test "detects fs.existsSync followed by fs.readFileSync in JavaScript-style", %{
      context: context
    } do
      # if (fs.existsSync(path)) {
      #     fs.readFileSync(path);
      # }
      ast =
        conditional(
          function_call("fs.existsSync", [variable("path")]),
          block([function_call("fs.readFileSync", [variable("path")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "fs.existsSync"
      assert issue.message =~ "fs.readFileSync"
    end

    test "detects File.exists? followed by File.rm", %{context: context} do
      # if File.exists?(path) do
      #   File.rm(path)
      # end
      ast =
        conditional(
          function_call("File.exists?", [variable("path")]),
          block([function_call("File.rm", [variable("path")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "File.rm"
    end

    test "ignores safe patterns without TOCTOU", %{context: context} do
      # Case File.read(path) - no prior check, so it's safe
      ast = function_call("File.read", [variable("path")])

      assert [] = TOCTOU.analyze(ast, context)
    end

    test "ignores conditional without check function", %{context: context} do
      # if some_condition do
      #   File.read(path)
      # end
      ast =
        conditional(
          variable("some_condition"),
          block([function_call("File.read", [variable("path")])])
        )

      assert [] = TOCTOU.analyze(ast, context)
    end

    test "ignores check without corresponding use", %{context: context} do
      # if File.exists?(path) do
      #   some_other_function()
      # end
      ast =
        conditional(
          function_call("File.exists?", [variable("path")]),
          block([function_call("some_other_function", [])])
        )

      assert [] = TOCTOU.analyze(ast, context)
    end
  end

  describe "analyze/2 - permission checks" do
    setup do
      context = %{
        document: Document.new(literal(:integer, 1), :elixir),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      %{context: context}
    end

    test "detects has_permission? followed by execute", %{context: context} do
      # if has_permission?(user, action) do
      #   execute(action)
      # end
      ast =
        conditional(
          function_call("has_permission?", [variable("user"), variable("action")]),
          block([function_call("execute", [variable("action")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "has_permission?"
      assert issue.message =~ "execute"
      assert issue.metadata.check_function == "has_permission?"
    end

    test "detects can_access? followed by perform", %{context: context} do
      ast =
        conditional(
          function_call("can_access?", [variable("resource")]),
          block([function_call("perform", [variable("resource")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "can_access?"
      assert issue.message =~ "perform"
    end
  end

  describe "analyze/2 - resource availability checks" do
    setup do
      context = %{
        document: Document.new(literal(:integer, 1), :elixir),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      %{context: context}
    end

    test "detects is_available? followed by use", %{context: context} do
      # if is_available?(service) do
      #   use(service)
      # end
      ast =
        conditional(
          function_call("is_available?", [variable("service")]),
          block([function_call("use", [variable("service")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "is_available?"
      assert issue.message =~ "use"
    end

    test "detects is_connected? followed by send", %{context: context} do
      ast =
        conditional(
          function_call("is_connected?", [variable("socket")]),
          block([function_call("send", [variable("socket"), variable("data")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "is_connected?"
    end
  end

  describe "analyze/2 - nested structures" do
    setup do
      context = %{
        document: Document.new(literal(:integer, 1), :elixir),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      %{context: context}
    end

    test "detects TOCTOU in nested conditional branches", %{context: context} do
      # if File.exists?(path) do
      #   if some_condition do
      #     File.read(path)
      #   end
      # end
      inner_conditional =
        conditional(
          variable("some_condition"),
          block([function_call("File.read", [variable("path")])])
        )

      ast =
        conditional(
          function_call("File.exists?", [variable("path")]),
          block([inner_conditional])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "File.exists?"
      assert issue.message =~ "File.read"
    end

    test "detects TOCTOU with assignment in between", %{context: context} do
      # if File.exists?(path) do
      #   content = File.read(path)
      # end
      ast =
        conditional(
          function_call("File.exists?", [variable("path")]),
          block([
            assignment(
              variable("content"),
              function_call("File.read", [variable("path")])
            )
          ])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "File.read"
    end

    test "detects TOCTOU in else branch", %{context: context} do
      # if File.exists?(path) do
      #   log("exists")
      # else
      #   File.write(path, default)  # still a TOCTOU since file might be created in between
      # end
      ast =
        conditional(
          function_call("File.exists?", [variable("path")]),
          block([function_call("log", [literal(:string, "exists")])]),
          block([function_call("File.write", [variable("path"), variable("default")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "File.write"
    end
  end

  describe "analyze/2 - sequential statements in block" do
    setup do
      context = %{
        document: Document.new(literal(:integer, 1), :elixir),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      %{context: context}
    end

    test "detects check-then-use in sequential statements", %{context: context} do
      # exists = File.exists?(path)
      # content = File.read(path)
      ast =
        block([
          assignment(variable("exists"), function_call("File.exists?", [variable("path")])),
          assignment(variable("content"), function_call("File.read", [variable("path")]))
        ])

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "sequential statements"
      assert issue.metadata.check_function == "File.exists?"
      assert issue.metadata.use_function == "File.read"
    end

    test "ignores non-TOCTOU sequential statements", %{context: context} do
      # x = compute_something()
      # y = compute_other()
      ast =
        block([
          assignment(variable("x"), function_call("compute_something", [])),
          assignment(variable("y"), function_call("compute_other", []))
        ])

      assert [] = TOCTOU.analyze(ast, context)
    end
  end

  describe "analyze/2 - cross-language patterns" do
    test "represents Python pattern" do
      context = %{
        document: Document.new(literal(:integer, 1), :python),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      # Python: if os.path.isfile(path): data = open(path).read()
      ast =
        conditional(
          function_call("os.path.isfile", [variable("path")]),
          block([
            assignment(variable("data"), function_call("open", [variable("path")]))
          ])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "os.path.isfile"
      assert issue.message =~ "open"
    end

    test "represents Go pattern" do
      context = %{
        document: Document.new(literal(:integer, 1), :go),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      # Go: if _, err := os.Stat(path); err == nil { os.Open(path) }
      ast =
        conditional(
          function_call("os.Stat", [variable("path")]),
          block([function_call("os.Open", [variable("path")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "os.Stat"
      assert issue.message =~ "os.Open"
    end

    test "represents Ruby pattern" do
      context = %{
        document: Document.new(literal(:integer, 1), :ruby),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      # Ruby: if File.exist?(path) then File.open(path) end
      ast =
        conditional(
          function_call("File.exist?", [variable("path")]),
          block([function_call("File.open", [variable("path")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "File.exist?"
      assert issue.message =~ "File.open"
    end
  end

  describe "analyze/2 - edge cases" do
    setup do
      context = %{
        document: Document.new(literal(:integer, 1), :elixir),
        config: %{},
        parent_stack: [],
        depth: 0,
        scope: %{}
      }

      %{context: context}
    end

    test "handles literal path instead of variable", %{context: context} do
      ast =
        conditional(
          function_call("File.exists?", [literal(:string, "/tmp/file.txt")]),
          block([function_call("File.read", [literal(:string, "/tmp/file.txt")])])
        )

      [issue] = TOCTOU.analyze(ast, context)

      assert issue.message =~ "TOCTOU vulnerability"
    end

    test "ignores different resources between check and use", %{context: context} do
      # Check path1, use path2 - not a TOCTOU on the same resource
      ast =
        conditional(
          function_call("File.exists?", [variable("path1")]),
          block([function_call("File.read", [variable("path2")])])
        )

      assert [] = TOCTOU.analyze(ast, context)
    end

    test "ignores non-conditional nodes", %{context: context} do
      ast = literal(:string, "hello")
      assert [] = TOCTOU.analyze(ast, context)

      ast = variable("x")
      assert [] = TOCTOU.analyze(ast, context)
    end

    test "handles empty branches gracefully", %{context: context} do
      ast =
        conditional(
          function_call("File.exists?", [variable("path")]),
          nil
        )

      assert [] = TOCTOU.analyze(ast, context)
    end
  end
end
