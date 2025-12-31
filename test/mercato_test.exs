defmodule MercatoTest do
  use ExUnit.Case
  doctest Mercato

  test "returns version" do
    assert is_binary(Mercato.version())
  end
end
