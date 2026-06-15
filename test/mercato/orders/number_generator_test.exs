defmodule Mercato.Orders.NumberGeneratorTest do
  use ExUnit.Case, async: true

  alias Mercato.Orders.NumberGenerator
  alias Mercato.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "generates an ORD-<unix>-<nnnn> number" do
    assert {:ok, number} = NumberGenerator.generate()
    assert number =~ ~r/^ORD-\d+-\d{4}$/
  end
end
