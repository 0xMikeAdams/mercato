defmodule Mercato.CartCouponIntegrationTest do
  use ExUnit.Case, async: true

  alias Mercato.{Cart, Catalog, Coupons, Repo}
  alias Decimal

  setup do
    # Explicitly get a connection for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Create a test product
    {:ok, product} =
      Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("100.00"),
        sku: "TEST-#{System.unique_integer([:positive])}",
        product_type: "simple",
        status: "published",
        stock_quantity: 100
      })

    # Create a test cart with items
    {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
    {:ok, cart} = Cart.add_item(cart.id, product.id, 2)

    # Create a test coupon
    {:ok, coupon} =
      Coupons.create_coupon(%{
        code: "SAVE10",
        discount_type: "percentage",
        discount_value: Decimal.new("10"),
        valid_from: DateTime.utc_now()
      })

    {:ok, product: product, cart: cart, coupon: coupon}
  end

  describe "cart coupon integration" do
    test "apply_coupon/2 applies coupon and recalculates totals", %{cart: cart, coupon: coupon} do
      # Verify initial cart state
      assert Decimal.equal?(cart.subtotal, Decimal.new("200.00"))
      assert Decimal.equal?(cart.discount_total, Decimal.new("0.00"))
      assert Decimal.equal?(cart.grand_total, Decimal.new("200.00"))
      assert is_nil(cart.applied_coupon_id)

      # Apply coupon
      {:ok, updated_cart} = Cart.apply_coupon(cart.id, "SAVE10")

      # Verify coupon was applied and totals recalculated
      assert updated_cart.applied_coupon_id == coupon.id
      assert Decimal.equal?(updated_cart.subtotal, Decimal.new("200.00"))
      assert Decimal.equal?(updated_cart.discount_total, Decimal.new("20.00"))  # 10% of $200
      assert Decimal.equal?(updated_cart.grand_total, Decimal.new("180.00"))    # $200 - $20
    end

    test "apply_coupon/2 returns error for invalid coupon", %{cart: cart} do
      assert {:error, :not_found} = Cart.apply_coupon(cart.id, "INVALID")
    end

    test "remove_coupon/1 removes coupon and recalculates totals", %{cart: cart} do
      # First apply a coupon
      {:ok, cart_with_coupon} = Cart.apply_coupon(cart.id, "SAVE10")
      assert not is_nil(cart_with_coupon.applied_coupon_id)
      assert Decimal.equal?(cart_with_coupon.discount_total, Decimal.new("20.00"))

      # Remove the coupon
      {:ok, updated_cart} = Cart.remove_coupon(cart.id)

      # Verify coupon was removed and totals recalculated
      assert is_nil(updated_cart.applied_coupon_id)
      assert Decimal.equal?(updated_cart.discount_total, Decimal.new("0.00"))
      assert Decimal.equal?(updated_cart.grand_total, Decimal.new("200.00"))
    end

    test "recalculate_totals/1 includes coupon discount", %{cart: cart} do
      # Apply coupon
      {:ok, cart_with_coupon} = Cart.apply_coupon(cart.id, "SAVE10")

      # Manually recalculate totals
      {:ok, recalculated_cart} = Cart.recalculate_totals(cart_with_coupon.id)

      # Verify discount is still applied
      assert Decimal.equal?(recalculated_cart.discount_total, Decimal.new("20.00"))
      assert Decimal.equal?(recalculated_cart.grand_total, Decimal.new("180.00"))
    end
  end

  describe "coupon validation integration" do
    test "apply_coupon/2 validates minimum spend", %{cart: cart} do
      # Create a coupon with high minimum spend
      {:ok, _high_min_coupon} =
        Coupons.create_coupon(%{
          code: "HIGHMIN",
          discount_type: "percentage",
          discount_value: Decimal.new("10"),
          min_spend: Decimal.new("300.00"),
          valid_from: DateTime.utc_now()
        })

      # Try to apply coupon - should fail due to minimum spend
      assert {:error, :minimum_spend_not_met} = Cart.apply_coupon(cart.id, "HIGHMIN")
    end

    test "apply_coupon/2 validates expiry date", %{cart: cart} do
      # Create an expired coupon
      {:ok, _expired_coupon} =
        Coupons.create_coupon(%{
          code: "EXPIRED",
          discount_type: "percentage",
          discount_value: Decimal.new("10"),
          valid_from: DateTime.add(DateTime.utc_now(), -2, :day),
          valid_until: DateTime.add(DateTime.utc_now(), -1, :day)
        })

      # Try to apply expired coupon
      assert {:error, :expired} = Cart.apply_coupon(cart.id, "EXPIRED")
    end
  end
end
