defmodule Mercato.Controllers.HelpersTest do
  use ExUnit.Case, async: true

  alias Mercato.Controllers.Helpers

  describe "error_detail/1" do
    test "exposes atom reasons as a string" do
      assert Helpers.error_detail(:out_of_stock) == %{reason: "out_of_stock"}
    end

    test "omits non-atom reasons (no internal leak)" do
      assert Helpers.error_detail({:missing, "product_id"}) == %{}
      assert Helpers.error_detail(%Ecto.Changeset{}) == %{}
      assert Helpers.error_detail("raw string") == %{}
    end
  end

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
