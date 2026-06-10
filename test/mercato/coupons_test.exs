defmodule Mercato.CouponsTest do
  use ExUnit.Case, async: true

  alias Mercato.{Catalog, Cart, Coupons, Orders, Repo}
  alias Mercato.Coupons.Coupon
  alias Decimal

  setup do
    # Explicitly get a connection for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    :ok
  end

  describe "coupons" do
    @valid_attrs %{
      code: "SAVE10",
      discount_type: "percentage",
      discount_value: Decimal.new("10"),
      valid_from: DateTime.utc_now()
    }

    @invalid_attrs %{code: nil, discount_type: nil, discount_value: nil, valid_from: nil}

    def coupon_fixture(attrs \\ %{}) do
      {:ok, coupon} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Coupons.create_coupon()

      coupon
    end

    test "list_coupons/0 returns all coupons" do
      coupon = coupon_fixture()
      coupons = Coupons.list_coupons()
      assert length(coupons) == 1
      assert List.first(coupons).id == coupon.id
    end

    test "get_coupon!/1 returns the coupon with given id" do
      coupon = coupon_fixture()
      retrieved_coupon = Coupons.get_coupon!(coupon.id)
      assert retrieved_coupon.id == coupon.id
      assert retrieved_coupon.code == coupon.code
    end

    test "get_coupon_by_code/1 returns the coupon with given code" do
      coupon = coupon_fixture()
      assert {:ok, found_coupon} = Coupons.get_coupon_by_code("SAVE10")
      assert found_coupon.id == coupon.id
    end

    test "get_coupon_by_code/1 is case insensitive" do
      coupon = coupon_fixture()
      assert {:ok, found_coupon} = Coupons.get_coupon_by_code("save10")
      assert found_coupon.id == coupon.id
    end

    test "create_coupon/1 with valid data creates a coupon" do
      assert {:ok, %Coupon{} = coupon} = Coupons.create_coupon(@valid_attrs)
      assert coupon.code == "SAVE10"
      assert coupon.discount_type == "percentage"
      assert Decimal.equal?(coupon.discount_value, Decimal.new("10"))
    end

    test "create_coupon/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Coupons.create_coupon(@invalid_attrs)
    end

    test "update_coupon/2 with valid data updates the coupon" do
      coupon = coupon_fixture()
      update_attrs = %{discount_value: Decimal.new("15")}

      assert {:ok, %Coupon{} = coupon} = Coupons.update_coupon(coupon, update_attrs)
      assert Decimal.equal?(coupon.discount_value, Decimal.new("15"))
    end

    test "update_coupon/2 with invalid data returns error changeset" do
      coupon = coupon_fixture()
      assert {:error, %Ecto.Changeset{}} = Coupons.update_coupon(coupon, @invalid_attrs)
      retrieved_coupon = Coupons.get_coupon!(coupon.id)
      assert retrieved_coupon.id == coupon.id
      assert retrieved_coupon.code == coupon.code
    end

    test "delete_coupon/1 deletes the coupon" do
      coupon = coupon_fixture()
      assert {:ok, %Coupon{}} = Coupons.delete_coupon(coupon)
      assert_raise Ecto.NoResultsError, fn -> Coupons.get_coupon!(coupon.id) end
    end

    test "change_coupon/1 returns a coupon changeset" do
      coupon = coupon_fixture()
      assert %Ecto.Changeset{} = Coupons.change_coupon(coupon)
    end
  end

  describe "coupon validation" do
    setup do
      # Create a test cart with items
      {:ok, product} = Mercato.Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("100.00"),
        sku: "TEST-#{System.unique_integer([:positive])}",
        product_type: "simple"
      })

      {:ok, cart} = Mercato.Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, cart} = Mercato.Cart.add_item(cart.id, product.id, 1)

      %{cart: cart, product: product}
    end

    test "validate_coupon/2 returns ok for valid coupon", %{cart: cart} do
      coupon = coupon_fixture(%{
        code: "VALID10",
        min_spend: Decimal.new("50.00")
      })

      assert {:ok, returned_coupon} = Coupons.validate_coupon("VALID10", cart)
      assert returned_coupon.id == coupon.id
    end

    test "validate_coupon/2 returns error for non-existent coupon", %{cart: cart} do
      assert {:error, :not_found} = Coupons.validate_coupon("NONEXISTENT", cart)
    end

    test "validate_coupon/2 returns error for expired coupon", %{cart: cart} do
      _expired_coupon = coupon_fixture(%{
        code: "EXPIRED",
        valid_from: DateTime.add(DateTime.utc_now(), -2, :day),
        valid_until: DateTime.add(DateTime.utc_now(), -1, :day)
      })

      assert {:error, :expired} = Coupons.validate_coupon("EXPIRED", cart)
    end

    test "validate_coupon/2 returns error when minimum spend not met", %{cart: cart} do
      _coupon = coupon_fixture(%{
        code: "HIGHMIN",
        min_spend: Decimal.new("200.00")
      })

      assert {:error, :minimum_spend_not_met} = Coupons.validate_coupon("HIGHMIN", cart)
    end
  end

  describe "coupon application" do
    setup do
      {:ok, product} = Mercato.Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("100.00"),
        sku: "TEST-#{System.unique_integer([:positive])}",
        product_type: "simple"
      })

      {:ok, cart} = Mercato.Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, cart} = Mercato.Cart.add_item(cart.id, product.id, 2)

      %{cart: cart, product: product}
    end

    test "apply_coupon/2 calculates percentage discount correctly", %{cart: cart} do
      coupon = coupon_fixture(%{
        code: "PERCENT10",
        discount_type: "percentage",
        discount_value: Decimal.new("10")
      })

      assert {:ok, discount_amount} = Coupons.apply_coupon(coupon, cart)
      # 10% of $200.00 = $20.00
      assert Decimal.equal?(discount_amount, Decimal.new("20.00"))
    end

    test "apply_coupon/2 calculates fixed cart discount correctly", %{cart: cart} do
      coupon = coupon_fixture(%{
        code: "FIXED20",
        discount_type: "fixed_cart",
        discount_value: Decimal.new("20.00")
      })

      assert {:ok, discount_amount} = Coupons.apply_coupon(coupon, cart)
      assert Decimal.equal?(discount_amount, Decimal.new("20.00"))
    end

    test "apply_coupon/2 limits fixed cart discount to cart total", %{cart: cart} do
      coupon = coupon_fixture(%{
        code: "TOOBIG",
        discount_type: "fixed_cart",
        discount_value: Decimal.new("300.00")
      })

      assert {:ok, discount_amount} = Coupons.apply_coupon(coupon, cart)
      # Should not exceed cart subtotal of $200.00
      assert Decimal.equal?(discount_amount, Decimal.new("200.00"))
    end
  end

  describe "record_coupon_usage/3 — atomic usage-limit enforcement" do
    test "rejects usage once the global usage_limit is reached" do
      coupon = coupon_fixture(%{code: "ONCE", usage_limit: 1})

      {:ok, order1} = create_order()
      {:ok, order2} = create_order()

      assert {:ok, _usage} = Coupons.record_coupon_usage(coupon, order1.id)

      # The cap is enforced atomically inside the increment, not just at validate
      # time — a second distinct order cannot push usage_count past the limit.
      assert {:error, :usage_limit_exceeded} = Coupons.record_coupon_usage(coupon, order2.id)

      assert Repo.get!(Coupon, coupon.id).usage_count == 1
    end

    test "allows usage up to the limit" do
      coupon = coupon_fixture(%{code: "TWICE", usage_limit: 2})

      {:ok, order1} = create_order()
      {:ok, order2} = create_order()

      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order1.id)
      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order2.id)

      assert Repo.get!(Coupon, coupon.id).usage_count == 2
    end

    test "allows unlimited usage when no usage_limit is set" do
      coupon = coupon_fixture(%{code: "UNLIMITED"})

      {:ok, order1} = create_order()
      {:ok, order2} = create_order()

      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order1.id)
      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order2.id)
    end

    test "enforces the per-customer limit (authoritatively, not just at validate time)" do
      coupon = coupon_fixture(%{code: "PERCUST", usage_limit_per_customer: 1})
      user_id = Ecto.UUID.generate()

      {:ok, order1} = create_order()
      {:ok, order2} = create_order()

      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order1.id, user_id)

      assert {:error, :customer_usage_limit_exceeded} =
               Coupons.record_coupon_usage(coupon, order2.id, user_id)

      assert Repo.get!(Coupon, coupon.id).usage_count == 1
    end

    test "per-customer limit is scoped per user" do
      coupon = coupon_fixture(%{code: "PERCUST2", usage_limit_per_customer: 1})

      {:ok, order1} = create_order()
      {:ok, order2} = create_order()

      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order1.id, Ecto.UUID.generate())
      # A different customer is unaffected by the first customer's usage.
      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order2.id, Ecto.UUID.generate())
    end

    test "recording the same order twice returns a changeset error, not a raise" do
      coupon = coupon_fixture(%{code: "DUPORDER"})
      {:ok, order} = create_order()

      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order.id)
      assert {:error, %Ecto.Changeset{}} = Coupons.record_coupon_usage(coupon, order.id)
      # The duplicate is rolled back — usage_count is not double-incremented.
      assert Repo.get!(Coupon, coupon.id).usage_count == 1
    end
  end

  describe "get_coupon_usage_stats/1 (SQL aggregates)" do
    test "counts uses and distinct customers in SQL" do
      coupon = coupon_fixture(%{code: "STATS"})
      user_id = Ecto.UUID.generate()

      {:ok, order1} = create_order()
      {:ok, order2} = create_order()
      {:ok, order3} = create_order()

      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order1.id, user_id)
      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order2.id, user_id)
      assert {:ok, _} = Coupons.record_coupon_usage(coupon, order3.id, Ecto.UUID.generate())

      stats = Coupons.get_coupon_usage_stats(coupon)

      assert stats.total_uses == 3
      assert stats.unique_customers == 2
      assert length(stats.recent_uses) == 3
    end
  end

  defp create_order do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Usage Product #{System.unique_integer([:positive])}",
        slug: "usage-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("50.00"),
        sku: "USAGE-#{System.unique_integer([:positive])}",
        product_type: "simple",
        stock_quantity: 50
      })

    {:ok, cart} =
      Cart.create_cart(%{cart_token: "usage-cart-#{System.unique_integer([:positive])}"})

    {:ok, _cart} = Cart.add_item(cart.id, product.id, 1)

    Orders.create_order_from_cart(cart.id, %{
      billing_address: %{
        "line1" => "1 Usage St",
        "city" => "Toronto",
        "state" => "ON",
        "postal_code" => "A1A1A1",
        "country" => "CA"
      },
      payment_method: "invoice"
    })
  end
end
