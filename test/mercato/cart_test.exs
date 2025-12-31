defmodule Mercato.CartTest do
  use ExUnit.Case, async: true

  alias Mercato.{Cart, Catalog, Repo}

  setup do
    # Explicitly get a connection for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Create a test product
    {:ok, product} =
      Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("29.99"),
        sku: "TEST-#{System.unique_integer([:positive])}",
        product_type: "simple",
        status: "published",
        stock_quantity: 100
      })

    {:ok, product: product}
  end

  describe "create_cart/1" do
    test "creates a cart with a cart token" do
      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})

      assert cart.id
      assert cart.status == "active"
      assert Decimal.equal?(cart.subtotal, Decimal.new("0.00"))
      assert Decimal.equal?(cart.grand_total, Decimal.new("0.00"))
    end

    test "creates a cart for a user" do
      user_id = Ecto.UUID.generate()
      {:ok, cart} = Cart.create_cart(%{user_id: user_id})

      assert cart.id
      assert cart.user_id == user_id
      assert cart.status == "active"
    end
  end

  describe "get_cart/1" do
    test "retrieves an existing cart" do
      {:ok, created_cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, retrieved_cart} = Cart.get_cart(created_cart.id)

      assert retrieved_cart.id == created_cart.id
    end

    test "returns error for non-existent cart" do
      assert {:error, :not_found} = Cart.get_cart(Ecto.UUID.generate())
    end
  end

  describe "add_item/4" do
    test "adds an item to the cart", %{product: product} do
      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, updated_cart} = Cart.add_item(cart.id, product.id, 2)

      assert length(updated_cart.items) == 1
      item = List.first(updated_cart.items)
      assert item.product_id == product.id
      assert item.quantity == 2
      assert Decimal.equal?(item.unit_price, product.price)
      assert Decimal.equal?(item.total_price, Decimal.mult(product.price, 2))
    end

    test "increases quantity when adding same product again", %{product: product} do
      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, cart} = Cart.add_item(cart.id, product.id, 2)
      {:ok, updated_cart} = Cart.add_item(cart.id, product.id, 3)

      assert length(updated_cart.items) == 1
      item = List.first(updated_cart.items)
      assert item.quantity == 5
    end

    test "calculates subtotal correctly", %{product: product} do
      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, updated_cart} = Cart.add_item(cart.id, product.id, 2)

      expected_subtotal = Decimal.mult(product.price, 2)
      assert Decimal.equal?(updated_cart.subtotal, expected_subtotal)
    end
  end

  describe "update_item_quantity/3" do
    test "updates the quantity of a cart item", %{product: product} do
      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, cart} = Cart.add_item(cart.id, product.id, 2)
      item = List.first(cart.items)

      {:ok, updated_cart} = Cart.update_item_quantity(cart.id, item.id, 5)

      updated_item = List.first(updated_cart.items)
      assert updated_item.quantity == 5
      assert Decimal.equal?(updated_item.total_price, Decimal.mult(product.price, 5))
    end
  end

  describe "remove_item/2" do
    test "removes an item from the cart", %{product: product} do
      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, cart} = Cart.add_item(cart.id, product.id, 2)
      item = List.first(cart.items)

      {:ok, updated_cart} = Cart.remove_item(cart.id, item.id)

      assert length(updated_cart.items) == 0
      assert Decimal.equal?(updated_cart.subtotal, Decimal.new("0.00"))
    end
  end

  describe "clear_cart/1" do
    test "removes all items from the cart", %{product: product} do
      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, cart} = Cart.add_item(cart.id, product.id, 2)

      {:ok, cleared_cart} = Cart.clear_cart(cart.id)

      assert length(cleared_cart.items) == 0
      assert Decimal.equal?(cleared_cart.subtotal, Decimal.new("0.00"))
      assert Decimal.equal?(cleared_cart.grand_total, Decimal.new("0.00"))
    end
  end

  describe "recalculate_totals/2" do
    test "recalculates cart totals", %{product: product} do
      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-#{System.unique_integer([:positive])}"})
      {:ok, cart} = Cart.add_item(cart.id, product.id, 3)

      {:ok, recalculated_cart} = Cart.recalculate_totals(cart.id)

      expected_subtotal = Decimal.mult(product.price, 3)
      assert Decimal.equal?(recalculated_cart.subtotal, expected_subtotal)
      assert Decimal.equal?(recalculated_cart.grand_total, expected_subtotal)
    end
  end
end
