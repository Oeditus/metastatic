defmodule Metastatic.Analysis.BusinessLogic.ImperativeStatusHandlingTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.BusinessLogic.ImperativeStatusHandling
  alias Metastatic.Document

  # --- MetaAST node builders ---

  defp literal(subtype, value), do: {:literal, [subtype: subtype], value}
  defp variable(name), do: {:variable, [], name}
  defp block(statements), do: {:block, [], statements}

  defp field_access(object, field) do
    {:field_access, [field: field], [object]}
  end

  defp assignment(target, value) do
    {:assignment, [], [target, value]}
  end

  defp function_def(name, body) do
    {:function_def, [name: name], [body]}
  end

  defp conditional(condition, then_branch, else_branch \\ nil) do
    {:conditional, [], [condition, then_branch, else_branch]}
  end

  defp case_clause(pattern, body) do
    {:case_clause, [], [pattern, body]}
  end

  defp make_context(config \\ %{}) do
    context = %{
      document: Document.new(literal(:integer, 1), :elixir),
      config: config,
      parent_stack: [],
      depth: 0,
      scope: %{}
    }

    {:ok, context} = ImperativeStatusHandling.run_before(context)
    context
  end

  # --- info/0 ---

  describe "info/0" do
    test "returns analyzer metadata" do
      info = ImperativeStatusHandling.info()

      assert info.name == :imperative_status_handling
      assert info.category == :refactoring
      assert info.severity == :info
      assert info.configurable == true
      assert is_binary(info.description)
      assert is_binary(info.explanation)
    end
  end

  # --- Tier 1: Conditional branching on status ---

  describe "Tier 1 -- status branching" do
    test "detects conditional branching on status field with 3+ states" do
      context = make_context()

      # case record.status do :draft -> ... :pending -> ... :active -> ... end
      ast =
        conditional(
          field_access(variable("record"), "status"),
          block([
            case_clause(literal(:atom, :draft), literal(:atom, :handle_draft)),
            case_clause(literal(:atom, :pending), literal(:atom, :handle_pending)),
            case_clause(literal(:atom, :active), literal(:atom, :handle_active))
          ])
        )

      issues = ImperativeStatusHandling.analyze(ast, context)
      assert [issue] = issues
      assert issue.analyzer == ImperativeStatusHandling
      assert issue.category == :refactoring
      assert issue.severity == :info
      assert issue.message =~ "status values"
      assert issue.message =~ "FSM"
      assert issue.metadata.tier == :branching
      assert issue.metadata.state_count >= 3
    end

    test "ignores branching on non-status fields" do
      context = make_context()

      ast =
        conditional(
          field_access(variable("record"), "name"),
          block([
            case_clause(literal(:string, "alice"), literal(:atom, :ok)),
            case_clause(literal(:string, "bob"), literal(:atom, :ok)),
            case_clause(literal(:string, "carol"), literal(:atom, :ok))
          ])
        )

      assert [] = ImperativeStatusHandling.analyze(ast, context)
    end

    test "ignores branching with fewer than min_states" do
      context = make_context()

      ast =
        conditional(
          field_access(variable("record"), "status"),
          block([
            case_clause(literal(:atom, :active), literal(:atom, :ok)),
            case_clause(literal(:atom, :inactive), literal(:atom, :ok))
          ])
        )

      assert [] = ImperativeStatusHandling.analyze(ast, context)
    end

    test "respects custom min_states configuration" do
      context = make_context(%{min_states: 2})

      ast =
        conditional(
          field_access(variable("record"), "status"),
          block([
            case_clause(literal(:atom, :active), literal(:atom, :ok)),
            case_clause(literal(:atom, :inactive), literal(:atom, :ok))
          ])
        )

      assert [_issue] = ImperativeStatusHandling.analyze(ast, context)
    end

    test "detects branching on 'state' field as well" do
      context = make_context()

      ast =
        conditional(
          field_access(variable("order"), "state"),
          block([
            case_clause(literal(:atom, :new), literal(:atom, :ok)),
            case_clause(literal(:atom, :processing), literal(:atom, :ok)),
            case_clause(literal(:atom, :shipped), literal(:atom, :ok))
          ])
        )

      assert [issue] = ImperativeStatusHandling.analyze(ast, context)
      assert issue.metadata.tier == :branching
    end

    test "detects branching on status variable (Python-style)" do
      context = make_context()

      ast =
        conditional(
          variable("status"),
          block([
            case_clause(literal(:string, "pending"), literal(:atom, :ok)),
            case_clause(literal(:string, "active"), literal(:atom, :ok)),
            case_clause(literal(:string, "archived"), literal(:atom, :ok))
          ])
        )

      assert [_issue] = ImperativeStatusHandling.analyze(ast, context)
    end
  end

  # --- Tier 2: Status assignment ---

  describe "Tier 2 -- status assignment" do
    test "detects assignment to status field with literal value" do
      context = make_context()

      ast =
        assignment(
          field_access(variable("record"), "status"),
          literal(:atom, :active)
        )

      issues = ImperativeStatusHandling.analyze(ast, context)
      assert [issue] = issues
      assert issue.metadata.tier == :assignment
      assert issue.metadata.assigned_state == :active
      assert issue.message =~ "Imperative status assignment"
      assert issue.message =~ "FSM"
    end

    test "detects assignment to status variable" do
      context = make_context()

      ast = assignment(variable("status"), literal(:string, "completed"))

      assert [issue] = ImperativeStatusHandling.analyze(ast, context)
      assert issue.metadata.assigned_state == "completed"
    end

    test "ignores assignment to status with non-literal value" do
      context = make_context()

      ast =
        assignment(
          field_access(variable("record"), "status"),
          variable("new_status")
        )

      assert [] = ImperativeStatusHandling.analyze(ast, context)
    end

    test "ignores assignment to non-status fields" do
      context = make_context()

      ast =
        assignment(
          field_access(variable("record"), "name"),
          literal(:string, "active")
        )

      assert [] = ImperativeStatusHandling.analyze(ast, context)
    end
  end

  # --- Tier 3: Transition-verb function names ---

  describe "Tier 3 -- transition-verb function names" do
    test "detects function with transition verb name" do
      context = make_context()

      ast = function_def("activate", block([literal(:atom, :ok)]))

      issues = ImperativeStatusHandling.analyze(ast, context)
      assert [issue] = issues
      assert issue.metadata.tier == :transition_verb
      assert issue.metadata.function_name == "activate"
      assert issue.metadata.matched_verb == "activate"
      assert issue.message =~ "state transition"
      assert issue.message =~ "FSM event"
    end

    test "detects compound transition function names" do
      context = make_context()

      for name <- ["activate_user", "user_deactivate", "do_publish", "cancel_order"] do
        ast = function_def(name, block([literal(:atom, :ok)]))
        issues = ImperativeStatusHandling.analyze(ast, context)
        assert [_issue] = issues, "Expected issue for function: #{name}"
      end
    end

    test "ignores non-transition function names" do
      context = make_context()

      for name <- ["calculate_total", "fetch_user", "render_page", "validate_input"] do
        ast = function_def(name, block([literal(:atom, :ok)]))

        assert [] = ImperativeStatusHandling.analyze(ast, context),
               "Unexpected issue for: #{name}"
      end
    end

    test "detects common lifecycle verbs" do
      context = make_context()

      for verb <- ~w(suspend resume archive reject approve submit finalize expire) do
        ast = function_def(verb, block([literal(:atom, :ok)]))

        assert [_] = ImperativeStatusHandling.analyze(ast, context),
               "Missing detection for: #{verb}"
      end
    end

    test "respects custom transition_verbs configuration" do
      context = make_context(%{transition_verbs: ["escalate", "de_escalate"]})

      ast = function_def("escalate_ticket", block([literal(:atom, :ok)]))
      assert [issue] = ImperativeStatusHandling.analyze(ast, context)
      assert issue.metadata.matched_verb == "escalate"
    end
  end

  # --- Non-matching nodes ---

  describe "non-matching nodes" do
    test "ignores literals" do
      context = make_context()
      assert [] = ImperativeStatusHandling.analyze(literal(:string, "hello"), context)
    end

    test "ignores plain variables" do
      context = make_context()
      assert [] = ImperativeStatusHandling.analyze(variable("x"), context)
    end

    test "ignores blocks" do
      context = make_context()
      assert [] = ImperativeStatusHandling.analyze(block([literal(:integer, 1)]), context)
    end
  end

  # --- Cross-language patterns ---

  describe "cross-language patterns" do
    test "Python: self.status assignment" do
      context = make_context()

      # self.status = "active"
      ast =
        assignment(
          field_access(variable("self"), "status"),
          literal(:string, "active")
        )

      assert [issue] = ImperativeStatusHandling.analyze(ast, context)
      assert issue.metadata.assigned_state == "active"
    end

    test "Ruby: @status assignment" do
      context = make_context()

      # @status = :pending
      ast = assignment(variable("status"), literal(:atom, :pending))

      assert [issue] = ImperativeStatusHandling.analyze(ast, context)
      assert issue.metadata.assigned_state == :pending
    end

    test "JavaScript: this.status switch with 4 cases" do
      context = make_context()

      ast =
        conditional(
          field_access(variable("this"), "status"),
          block([
            case_clause(literal(:string, "idle"), literal(:string, "start")),
            case_clause(literal(:string, "running"), literal(:string, "tick")),
            case_clause(literal(:string, "paused"), literal(:string, "resume")),
            case_clause(literal(:string, "stopped"), literal(:string, "cleanup"))
          ])
        )

      assert [issue] = ImperativeStatusHandling.analyze(ast, context)
      assert issue.metadata.state_count >= 4
    end
  end

  # --- Configuration ---

  describe "configuration" do
    test "custom status_field_names" do
      context = make_context(%{status_field_names: ["phase", "workflow_state"]})

      # Should detect "phase" now
      ast =
        assignment(
          field_access(variable("record"), "phase"),
          literal(:atom, :review)
        )

      assert [_] = ImperativeStatusHandling.analyze(ast, context)

      # "status" should NOT be detected with custom config
      ast2 =
        assignment(
          field_access(variable("record"), "status"),
          literal(:atom, :active)
        )

      assert [] = ImperativeStatusHandling.analyze(ast2, context)
    end
  end
end
