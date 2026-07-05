defmodule WithClause do
  @moduledoc false

  def fun(arg) do
    with %{key: value} <- arg do
      {:ok, value}
    end
  end
end
