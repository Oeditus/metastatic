defmodule Metastatic.Analysis.Duplication.TypesTest do
  use ExUnit.Case, async: true

  alias Metastatic.Analysis.Duplication.Types

  doctest Metastatic.Analysis.Duplication.Types

  describe "type atoms" do
    test "type_i/0 returns :type_i" do
      assert Types.type_i() == :type_i
    end

    test "type_ii/0 returns :type_ii" do
      assert Types.type_ii() == :type_ii
    end

    test "type_iii/0 returns :type_iii" do
      assert Types.type_iii() == :type_iii
    end

    test "type_iv/0 returns :type_iv" do
      assert Types.type_iv() == :type_iv
    end
  end

  describe "all_types/0" do
    test "returns all four clone types" do
      types = Types.all_types()
      assert [:type_i, :type_ii, :type_iii, :type_iv] = types
    end

    test "contains exactly 4 types" do
      types = Types.all_types()
      assert length(types) == 4
    end
  end

  describe "describe/1" do
    test "describes type_i" do
      assert Types.describe(:type_i) == "Exact clone (identical code)"
    end

    test "describes type_ii" do
      assert Types.describe(:type_ii) ==
               "Renamed clone (identical structure, different identifiers)"
    end

    test "describes type_iii" do
      assert Types.describe(:type_iii) ==
               "Near-miss clone (similar structure with modifications)"
    end

    test "describes type_iv" do
      assert Types.describe(:type_iv) == "Semantic clone (different syntax, same behavior)"
    end
  end

  describe "valid?/1" do
    test "returns true for valid types" do
      assert Types.valid?(:type_i)
      assert Types.valid?(:type_ii)
      assert Types.valid?(:type_iii)
      assert Types.valid?(:type_iv)
    end

    test "returns false for invalid types" do
      refute Types.valid?(:invalid)
      refute Types.valid?(:type_v)
      refute Types.valid?(:clone)
      refute Types.valid?(nil)
    end
  end
end
