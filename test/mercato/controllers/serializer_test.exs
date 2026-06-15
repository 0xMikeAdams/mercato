defmodule Mercato.Controllers.SerializerTest do
  use ExUnit.Case, async: true

  alias Mercato.Controllers.Serializer
  alias Mercato.Orders.Order

  describe "serialize/1 — allowlist (fail-closed)" do
    test "exposes only allowlisted fields; sensitive/internal fields are dropped" do
      order = %Order{
        id: "order-1",
        status: "pending",
        grand_total: Decimal.new("10.00"),
        idempotency_key: "secret-key",
        payment_transaction_id: "txn-secret",
        source_cart_id: "cart-internal"
      }

      result = Serializer.serialize(order)

      # Allowlisted business fields present...
      assert result.id == "order-1"
      assert result.status == "pending"
      # ...sensitive/internal fields absent (not in the allowlist).
      refute Map.has_key?(result, :idempotency_key)
      refute Map.has_key?(result, :payment_transaction_id)
      refute Map.has_key?(result, :source_cart_id)
    end

    test "drops any field not on the allowlist (e.g. Cart.referral_code_id)" do
      cart = %Mercato.Cart.Cart{id: "cart-1", user_id: "u-1", referral_code_id: "ref-internal"}

      result = Serializer.serialize(cart)

      assert result.id == "cart-1"
      assert result.user_id == "u-1"
      refute Map.has_key?(result, :referral_code_id)
    end

    test "fails closed for a persisted schema with no allowlist entry" do
      # StoreSetting is a persisted schema deliberately never exposed via the API.
      setting = %Mercato.Config.StoreSetting{key: "secret_flag", value: %{"x" => 1}}

      assert Serializer.serialize(setting) == %{}
    end
  end

  describe "serialize/1 — value handling" do
    test "renders DateTime as ISO 8601" do
      {:ok, dt, _} = DateTime.from_iso8601("2026-06-07T12:00:00Z")
      assert Serializer.serialize(dt) == "2026-06-07T12:00:00Z"
    end

    test "renders Decimal as a string (not a coef/exp/sign map)" do
      assert Serializer.serialize(Decimal.new("19.99")) == "19.99"
      assert Serializer.serialize(%{price: Decimal.new("19.99")}) == %{price: "19.99"}
    end

    test "omits not-loaded associations" do
      order = %Order{id: "order-1", items: %Ecto.Association.NotLoaded{}}
      result = Serializer.serialize(order)
      refute Map.has_key?(result, :items)
    end

    test "recurses into lists and plain maps" do
      assert Serializer.serialize([%{a: 1}, %{a: 2}]) == [%{a: 1}, %{a: 2}]
      assert Serializer.serialize(%{nested: %{x: 1}}) == %{nested: %{x: 1}}
    end
  end
end
