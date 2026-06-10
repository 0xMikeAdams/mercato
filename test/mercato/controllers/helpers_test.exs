defmodule Mercato.Controllers.HelpersTest do
  use ExUnit.Case, async: true

  alias Mercato.Controllers.Helpers

  describe "parse_decimal/1" do
    test "parses ordinary money strings" do
      assert {:ok, d} = Helpers.parse_decimal("19.99")
      assert Decimal.equal?(d, Decimal.new("19.99"))
    end

    test "accepts integers and floats" do
      assert {:ok, d1} = Helpers.parse_decimal(20)
      assert Decimal.equal?(d1, Decimal.new(20))
      assert {:ok, _d2} = Helpers.parse_decimal(20.5)
    end

    test "rejects exponent notation (Decimal DoS vector)" do
      assert {:error, :invalid_decimal} = Helpers.parse_decimal("1E2147483647")
      assert {:error, :invalid_decimal} = Helpers.parse_decimal("1e10")
    end

    test "rejects over-long input" do
      assert {:error, :invalid_decimal} = Helpers.parse_decimal(String.duplicate("9", 33))
    end

    test "rejects garbage and empty/nil" do
      assert {:error, :invalid_decimal} = Helpers.parse_decimal("abc")
      assert {:error, :missing_decimal} = Helpers.parse_decimal("")
      assert {:error, :missing_decimal} = Helpers.parse_decimal(nil)
    end
  end
end
