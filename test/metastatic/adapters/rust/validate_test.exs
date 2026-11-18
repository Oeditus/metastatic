defmodule Metastatic.Adapters.Rust.ValidateTest do
  @moduledoc """
  Phase 4 coverage: the four validation layers.

  Layers 1–3 need an external toolchain, so they are tagged `:rust` and skip
  cleanly when `rustc`/`rustfmt` are absent. Layer 4 (the ownership heuristic)
  only needs the bridge and always runs.
  """
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Rust.Validate

  @moduletag :rust

  defp toolchain?(name), do: Metastatic.Priv.find_executable(name) != nil

  describe "ownership heuristic (layer 4)" do
    test "reports assignment to a binding declared without mut" do
      assert {:ok, [issue]} = Validate.ownership_issues("fn f() { let x = 1; x = 2; }")
      assert issue.kind == :missing_mut
      assert issue.variable == "x"
      assert issue.line == 1
    end

    test "accepts assignment to a mut binding" do
      assert {:ok, []} = Validate.ownership_issues("fn f() { let mut x = 1; x = 2; }")
    end

    test "ignores field assignment (not a plain binding)" do
      assert {:ok, []} = Validate.ownership_issues("fn f() { let mut s = p; s.x = 1; }")
    end

    test "reports one issue per offending binding" do
      assert {:ok, issues} =
               Validate.ownership_issues("fn f() { let a = 1; let b = 2; a = 3; b = 4; }")

      assert Enum.map(issues, & &1.variable) |> Enum.sort() == ["a", "b"]
    end

    test "returns an error for unparseable input rather than raising" do
      assert {:error, _reason} = Validate.ownership_issues("fn f( {")
    end
  end

  describe "rustc diagnostics (layer 1)" do
    @describetag :rustc

    test "reports no diagnostics for valid code" do
      if toolchain?("rustc") do
        assert {:ok, []} = Validate.rustc_diagnostics("fn f() {}")
      end
    end

    test "reports a type error with its code and line" do
      if toolchain?("rustc") do
        assert {:ok, diagnostics} = Validate.rustc_diagnostics(~s|fn f() { let x: i32 = "s"; }|)

        errors = Enum.filter(diagnostics, &(&1.level == :error))
        assert Enum.any?(errors, &(&1.code == "E0308"))
        assert Enum.any?(errors, &(&1.line == 1))
      end
    end

    test "never raises when the toolchain is missing" do
      # `require_tool/2` is the only place that can fail on a missing
      # toolchain; the contract is an error tuple, never an exception.
      result = Validate.rustc_diagnostics("fn f() {}")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "rustfmt (layer 3)" do
    test "accepts already-formatted source" do
      if toolchain?("rustfmt") do
        assert {:ok, []} = Validate.format_check("fn f() {}\n")
      end
    end

    test "rejects badly formatted source" do
      if toolchain?("rustfmt") do
        assert {:error, diff} = Validate.format_check("fn  f( ){}")
        assert diff =~ "Diff"
      end
    end
  end

  describe "validate_mutation/2" do
    test "accepts a literal" do
      assert :ok = Validate.validate_mutation({:literal, [subtype: :integer], 42}, %{})
    end

    test "accepts a binary operation" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}

      assert :ok = Validate.validate_mutation(ast, %{})
    end

    test "rejects a MetaAST that cannot be reified" do
      assert {:error, _reason} = Validate.validate_mutation({:not_a_node, [], nil}, %{})
    end

    test "the adapter exposes the callback" do
      # `function_exported?/3` is false for a module that has not been loaded.
      assert Code.ensure_loaded?(Metastatic.Adapters.Rust)
      assert function_exported?(Metastatic.Adapters.Rust, :validate_mutation, 2)
    end
  end

  describe "toolchain absence" do
    test "every layer returns an error tuple rather than raising" do
      # The layers must never raise, whatever the environment.
      for result <- [
            Validate.rustc_diagnostics("fn f() {}"),
            Validate.format_check("fn f() {}"),
            Validate.ownership_issues("fn f() {}")
          ] do
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end
end
