defmodule Mercato.OrdersTest do
  use ExUnit.Case, async: true

  alias Mercato.{Orders, Cart, Catalog, Repo}

  setup do
    # Explicitly get a connection for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    :ok
  end

  describe "orders" do
    test "create_order_from_cart/2 creates an order from cart contents" do
      # Create a product
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple",
        stock_quantity: 100
      })

      # Create a cart and add the product
      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token"})
      {:ok, cart} = Cart.add_item(cart.id, product.id, 2)

      # Create order from cart
      order_attrs = %{
        billing_address: %{
          "line1" => "123 Main St",
          "city" => "Anytown",
          "state" => "CA",
          "postal_code" => "12345",
          "country" => "US"
        },
        payment_method: "credit_card"
      }

      {:ok, order} = Orders.create_order_from_cart(cart.id, order_attrs)

      # Verify order was created correctly
      assert order.status == "pending"
      assert order.subtotal == cart.subtotal
      assert order.grand_total == cart.grand_total
      assert order.billing_address["line1"] == "123 Main St"
      assert order.payment_method == "credit_card"
      assert String.starts_with?(order.order_number, "ORD-")

      # Verify order items were created
      assert length(order.items) == 1
      order_item = List.first(order.items)
      assert order_item.product_id == product.id
      assert order_item.quantity == 2
      assert order_item.unit_price == product.price

      # Verify product snapshot was created
      assert order_item.product_snapshot["name"] == product.name
      assert order_item.product_snapshot["sku"] == product.sku

      # Verify status history was created
      assert length(order.status_history) == 1
      status_entry = List.first(order.status_history)
      assert status_entry.from_status == nil
      assert status_entry.to_status == "pending"
    end

    test "update_status/2 updates order status and creates history entry" do
      # Create a simple order
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product-2",
        price: Decimal.new("19.99"),
        sku: "TEST-002",
        product_type: "simple",
        stock_quantity: 100
      })

      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-2"})
      {:ok, cart} = Cart.add_item(cart.id, product.id, 1)

      order_attrs = %{
        billing_address: %{
          "line1" => "456 Oak Ave",
          "city" => "Somewhere",
          "state" => "NY",
          "postal_code" => "67890",
          "country" => "US"
        },
        payment_method: "paypal"
      }

      {:ok, order} = Orders.create_order_from_cart(cart.id, order_attrs)

      # Update status to processing
      {:ok, updated_order} = Orders.update_status(order.id, "processing")

      assert updated_order.status == "processing"
      assert length(updated_order.status_history) == 2

      # Check the new status history entry
      processing_entry = Enum.find(updated_order.status_history, &(&1.to_status == "processing"))
      assert processing_entry.from_status == "pending"
      assert processing_entry.to_status == "processing"
    end

    test "cancel_order/2 cancels an order and updates status" do
      # Create a simple order
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product-3",
        price: Decimal.new("39.99"),
        sku: "TEST-003",
        product_type: "simple",
        stock_quantity: 100
      })

      {:ok, cart} = Cart.create_cart(%{cart_token: "test-token-3"})
      {:ok, cart} = Cart.add_item(cart.id, product.id, 1)

      order_attrs = %{
        billing_address: %{
          "line1" => "789 Pine St",
          "city" => "Elsewhere",
          "state" => "TX",
          "postal_code" => "54321",
          "country" => "US"
        },
        payment_method: "credit_card"
      }

      {:ok, order} = Orders.create_order_from_cart(cart.id, order_attrs)

      # Cancel the order
      {:ok, cancelled_order} = Orders.cancel_order(order.id, "Customer request")

      assert cancelled_order.status == "cancelled"

      # Check that cancellation was recorded in history
      cancel_entry = Enum.find(cancelled_order.status_history, &(&1.to_status == "cancelled"))
      assert cancel_entry.from_status == "pending"
      assert cancel_entry.notes == "Customer request"
    end

    test "list_orders/1 returns orders with filtering" do
      # Create two orders with different statuses
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product-4",
        price: Decimal.new("49.99"),
        sku: "TEST-004",
        product_type: "simple",
        stock_quantity: 100
      })

      # First order
      {:ok, cart1} = Cart.create_cart(%{cart_token: "test-token-4"})
      {:ok, cart1} = Cart.add_item(cart1.id, product.id, 1)

      order_attrs = %{
        billing_address: %{
          "line1" => "111 First St",
          "city" => "City1",
          "state" => "CA",
          "postal_code" => "11111",
          "country" => "US"
        },
        payment_method: "credit_card"
      }

      {:ok, order1} = Orders.create_order_from_cart(cart1.id, order_attrs)

      # Second order
      {:ok, cart2} = Cart.create_cart(%{cart_token: "test-token-5"})
      {:ok, cart2} = Cart.add_item(cart2.id, product.id, 2)

      {:ok, order2} = Orders.create_order_from_cart(cart2.id, order_attrs)
      {:ok, order2} = Orders.update_status(order2.id, "processing")

      # Test listing all orders
      all_orders = Orders.list_orders()
      assert length(all_orders) >= 2

      # Test filtering by status
      pending_orders = Orders.list_orders(status: "pending")
      assert Enum.any?(pending_orders, &(&1.id == order1.id))
      assert not Enum.any?(pending_orders, &(&1.id == order2.id))

      processing_orders = Orders.list_orders(status: "processing")
      assert Enum.any?(processing_orders, &(&1.id == order2.id))
      assert not Enum.any?(processing_orders, &(&1.id == order1.id))
    end
  end
end
