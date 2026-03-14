defmodule Mercato.PaymentGatewayValidationTest do
  use ExUnit.Case, async: false

  alias Mercato.{Cart, Catalog, Orders, PaymentGateways.Dummy, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    previous_gateway = Application.get_env(:mercato, :payment_gateway)

    on_exit(fn ->
      if previous_gateway do
        Application.put_env(:mercato, :payment_gateway, previous_gateway)
      else
        Application.delete_env(:mercato, :payment_gateway)
      end
    end)

    :ok
  end

  test "checkout fails clearly when payment is requested without a configured gateway" do
    Application.delete_env(:mercato, :payment_gateway)

    {:ok, cart} = checkout_cart()

    assert {:error, :payment_gateway_not_configured} =
             Orders.create_order_from_cart(cart.id, %{
               billing_address: billing_address(),
               payment_method: "card",
               payment_details: %{"token" => "tok_live"}
             })
  end

  test "checkout rejects the dummy gateway when payment is requested" do
    Application.put_env(:mercato, :payment_gateway, Dummy)

    {:ok, cart} = checkout_cart()

    assert {:error, :dummy_payment_gateway_not_allowed} =
             Orders.create_order_from_cart(cart.id, %{
               billing_address: billing_address(),
               payment_method: "card",
               payment_details: %{"token" => "tok_live"}
             })
  end

  test "process_payment/3 returns normalized authorization failures" do
    order = %{id: Ecto.UUID.generate(), grand_total: Decimal.new("19.99")}

    assert {:error, {:authorization_failed, :card_declined}} =
             Orders.process_payment(order, %{"token" => "declined"},
               payment_gateway: Mercato.TestPaymentGateway
             )
  end

  test "process_refund/3 returns normalized refund failures" do
    order = %{
      id: Ecto.UUID.generate(),
      payment_transaction_id: "bad_txn"
    }

    assert {:error, {:refund_failed, :transaction_not_found}} =
             Orders.process_refund(order, Decimal.new("19.99"),
               payment_gateway: Mercato.TestPaymentGateway
             )
  end

  defp checkout_cart do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Gateway Product #{System.unique_integer([:positive])}",
        slug: "gateway-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("49.99"),
        sku: "GATEWAY-#{System.unique_integer([:positive])}",
        product_type: "simple",
        stock_quantity: 25
      })

    {:ok, cart} =
      Cart.create_cart(%{
        cart_token: "gateway-cart-#{System.unique_integer([:positive])}"
      })

    {:ok, cart} = Cart.add_item(cart.id, product.id, 1)
    {:ok, cart}
  end

  defp billing_address do
    %{
      "line1" => "123 Main St",
      "city" => "Toronto",
      "state" => "ON",
      "postal_code" => "A1A1A1",
      "country" => "CA"
    }
  end
end
