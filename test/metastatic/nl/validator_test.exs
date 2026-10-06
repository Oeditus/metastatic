defmodule Metastatic.NL.ValidatorTest do
  use ExUnit.Case, async: true
  alias Metastatic.NL.{AST, Validator}

  describe "validate/2" do
    test "validates core NL AST tree" do
      sent =
        AST.sentence([
          AST.clause([
            AST.phrase(:noun_phrase, [AST.token("Users", pos: :noun)]),
            AST.phrase(:verb_phrase, [AST.token("wait", pos: :verb)])
          ]),
          AST.punctuation(".")
        ])

      assert {:ok, metrics} = Validator.validate(sent)
      assert metrics.level == :core
      assert metrics.sentences == 1
      assert metrics.clauses == 1
      assert metrics.tokens == 2
      assert metrics.native_nodes == 0
    end

    test "identifies native level and rejects in strict mode" do
      native_feature = {:native_nl_feature, [language: :japanese, feature: :particle_wa], "は"}
      sent = AST.sentence([native_feature])

      assert {:ok, metrics} = Validator.validate(sent, mode: :standard)
      assert metrics.level == :native
      assert metrics.native_nodes == 1

      assert {:error, :native_constructs_not_allowed} = Validator.validate(sent, mode: :strict)
    end

    test "rejects non-conforming structures" do
      assert {:error, :invalid_structure} = Validator.validate({:bad_node, [], []})
    end

    test "detects max depth violation" do
      nested =
        Enum.reduce(1..10, AST.token("deep"), fn _, acc ->
          AST.phrase(:noun_phrase, [acc])
        end)

      assert {:error, :max_depth_exceeded} = Validator.validate(nested, max_depth: 5)
    end
  end
end
