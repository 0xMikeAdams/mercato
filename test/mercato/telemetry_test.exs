defmodule Mercato.TelemetryTest do
  use ExUnit.Case, async: false

  alias Mercato.{Cart, Catalog, Orders, Repo, Subscriptions}
  alias Mercato.Subscriptions.Subscription

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "order creation emits telemetry" do
    handler_id = attach_handler([:mercato, :order, :create, :stop])

    {:ok, product} =
      Catalog.create_product(%{
        name: "Telemetry Product #{System.unique_integer([:positive])}",
        slug: "telemetry-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("21.00"),
        sku: "TELEMETRY-#{System.unique_integer([:positive])}",
        product_type: "simple",
        stock_quantity: 10
      })

    {:ok, cart} =
      Cart.create_cart(%{
        cart_token: "telemetry-cart-#{System.unique_integer([:positive])}"
      })

    {:ok, _cart} = Cart.add_item(cart.id, product.id, 1)

    {:ok, order} =
      Orders.create_order_from_cart(cart.id, %{
        billing_address: %{
          "line1" => "123 Event St",
          "city" => "Toronto",
          "state" => "ON",
          "postal_code" => "A1A1A1",
          "country" => "CA"
        },
        payment_method: "invoice"
      })

    order_id = order.id

    assert_receive {:telemetry_event, [:mercato, :order, :create, :stop], %{count: 1}, %{order_id: ^order_id}},
                   1_000

    detach_handler(handler_id)
  end

  test "payment processing emits authorize and capture telemetry" do
    authorize_handler = attach_handler([:mercato, :payment, :authorize, :stop])
    capture_handler = attach_handler([:mercato, :payment, :capture, :stop])

    order = %{id: Ecto.UUID.generate(), grand_total: Decimal.new("19.99")}

    assert {:ok, %{status: "succeeded"}} =
             Orders.process_payment(order, %{"token" => "tok_live"},
               payment_gateway: Mercato.TestPaymentGateway
             )

    assert_receive {:telemetry_event, [:mercato, :payment, :authorize, :stop], %{amount: _},
                    %{transaction_id: "test_txn_123"}},
                   1_000

    assert_receive {:telemetry_event, [:mercato, :payment, :capture, :stop], %{amount: _},
                    %{transaction_id: "test_txn_123"}},
                   1_000

    detach_handler(authorize_handler)
    detach_handler(capture_handler)
  end

  test "renewal runs emit summary telemetry" do
    handler_id = attach_handler([:mercato, :subscription, :renewal_run, :stop])

    {:ok, product} =
      Catalog.create_product(%{
        name: "Renewal Product #{System.unique_integer([:positive])}",
        slug: "renewal-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("29.99"),
        sku: "RENEWAL-#{System.unique_integer([:positive])}",
        product_type: "subscription",
        stock_quantity: 10,
        subscription_settings: %{"billing_cycle" => "monthly"}
      })

    {:ok, subscription} =
      Subscriptions.create_subscription(%{
        user_id: Ecto.UUID.generate(),
        product_id: product.id,
        billing_cycle: "monthly",
        start_date: Date.utc_today(),
        billing_amount: Decimal.new("29.99")
      })

    {:ok, _updated_subscription} =
      subscription
      |> Subscription.billing_changeset(%{next_billing_date: Date.add(Date.utc_today(), -1)})
      |> Repo.update()

    assert {:ok, %{lock_acquired?: true, processed: 1, successful: 1, failed: 0}} =
             Subscriptions.process_due_renewals()

    assert_receive {:telemetry_event, [:mercato, :subscription, :renewal_run, :stop], %{processed: 1},
                    %{lock_acquired?: true, successful: 1, failed: 0}},
                   1_000

    detach_handler(handler_id)
  end

  defp attach_handler(event) do
    handler_id = "mercato-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn emitted_event, measurements, metadata, pid ->
          send(pid, {:telemetry_event, emitted_event, measurements, metadata})
        end,
        self()
      )

    # Detach via on_exit so a crash before the inline detach can't leak the handler
    # into subsequent tests (which would send to a dead pid).
    on_exit(fn -> :telemetry.detach(handler_id) end)

    handler_id
  end

  defp detach_handler(handler_id) do
    :telemetry.detach(handler_id)
  end
end
