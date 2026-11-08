defmodule Metastatic.Adapters.JavaConformanceTest do
  @moduledoc """
  Uniform conformance suite for the Java adapter (see
  `Metastatic.Test.AdapterConformance`).

  The Java adapter shells out to the JDK's tree API, so these tests skip
  cleanly when no `java` executable is available instead of failing an
  environment that simply has no JDK installed.
  """
  use ExUnit.Case, async: true

  alias Metastatic.Adapters.Java.Subprocess

  @moduletag :java

  if Subprocess.java_executable() == nil do
    @moduletag skip: "no JDK available (install a JDK 11+ to run the Java adapter tests)"
  end

  use Metastatic.Test.AdapterConformance,
    adapter: Metastatic.Adapters.Java,
    language: :java,
    sample: "class Sample { int add() { return 1 + 2; } }",
    sample_ast:
      {:binary_op, [category: :arithmetic, operator: :+],
       [{:literal, [subtype: :integer], 1}, {:literal, [subtype: :integer], 2}]}
end
