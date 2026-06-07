defmodule Mercato.Controllers.SerializerTest do
  use ExUnit.Case, async: true

  alias Mercato.Controllers.Serializer
  alias Mercato.Orders.Order

  describe "serialize/1 — sensitive field stripping" do
    test "drops idempotency_key and payment_transaction_id from any struct" do
      order = %Order{
        id: "order-1",
        idempotency_key: "secret-key",
        payment_transaction_id: "txn-secret",
        grand_total: Decimal.new("10.00")
      }

      result = Serializer.serialize(order)

      assert result.id == "order-1"
      refute Map.has_key?(result, :idempotency_key)
      refute Map.has_key?(result, :payment_transaction_id)
    end

    test "drops per-schema internal fields (Order.source_cart_id)" do
      order = %Order{id: "order-1", source_cart_id: "cart-internal"}

      result = Serializer.serialize(order)

      refute Map.has_key?(result, :source_cart_id)
    end
  end

  describe "serialize/1 — value handling" do
    test "renders DateTime as ISO 8601" do
      {:ok, dt, _} = DateTime.from_iso8601("2026-06-07T12:00:00Z")
      assert Serializer.serialize(dt) == "2026-06-07T12:00:00Z"
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
