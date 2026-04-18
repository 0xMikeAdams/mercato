defmodule Mercato.CheckoutTest do
  use ExUnit.Case, async: false

  alias Mercato.{Catalog, Checkout, Repo}
  alias Mercato.Checkout.{CheckoutSession, ProgrammaticCheckoutRequest, ValidationError}
  alias Mercato.Checkout.CheckoutProvider
  alias Mercato.Checkout.PaymentProvider
  alias Mercato.ShippingCalculators.FlatRate
  alias Mercato.TaxCalculators.Simple

  defmodule TestCheckoutProvider do
    @behaviour CheckoutProvider

    @impl true
    def create_checkout_session(request, response, _opts) do
      id = stable_id("redir", request.idempotency_key)

      {:ok,
       %CheckoutSession{
         id: id,
         kind: "redirect",
         status: "ready",
         provider: inspect(__MODULE__),
         currency: response.currency,
         totals: response.price_breakdown,
         redirect_url: "https://checkout.example/sessions/#{id}",
         payment_client_secret: nil,
         provider_reference: "provider_#{id}",
         expires_at: nil,
         idempotency_key: request.idempotency_key,
         retry_safe: true,
         metadata: %{}
       }}
    end

    defp stable_id(prefix, idempotency_key) do
      digest =
        :crypto.hash(:sha256, "#{prefix}:#{idempotency_key}")
        |> Base.url_encode64(padding: false)
        |> binary_part(0, 20)

      "#{prefix}_#{digest}"
    end
  end

  defmodule TestPaymentProvider do
    @behaviour PaymentProvider

    @impl true
    def create_payment_session(request, response, _opts) do
      id = stable_id("pay", request.idempotency_key)

      {:ok,
       %CheckoutSession{
         id: id,
         kind: request.payment_flow,
         status: "requires_action",
         provider: inspect(__MODULE__),
         currency: response.currency,
         totals: response.price_breakdown,
         redirect_url: nil,
         payment_client_secret: "secret_#{id}",
         provider_reference: "intent_#{id}",
         expires_at: nil,
         idempotency_key: request.idempotency_key,
         retry_safe: true,
         metadata: %{}
       }}
    end

    defp stable_id(prefix, idempotency_key) do
      digest =
        :crypto.hash(:sha256, "#{prefix}:#{idempotency_key}")
        |> Base.url_encode64(padding: false)
        |> binary_part(0, 20)

      "#{prefix}_#{digest}"
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    previous_shipping = Application.get_env(:mercato, :shipping_calculator)
    previous_tax = Application.get_env(:mercato, :tax_calculator)
    previous_flat_rate = Application.get_env(:mercato, FlatRate)
    previous_simple_tax = Application.get_env(:mercato, Simple)

    Application.put_env(:mercato, :shipping_calculator, FlatRate)
    Application.put_env(:mercato, :tax_calculator, Simple)

    Application.put_env(:mercato, FlatRate,
      free_shipping_threshold: Decimal.new("1000.00"),
      methods: [
        %{
          id: "standard",
          name: "Standard Shipping",
          description: "5-7 business days",
          rate: Decimal.new("9.99"),
          estimated_days: 7
        }
      ]
    )

    Application.put_env(:mercato, Simple,
      default_rate: Decimal.new("0.08"),
      rates: %{"CA" => Decimal.new("0.0875")}
    )

    on_exit(fn ->
      restore_env(:shipping_calculator, previous_shipping)
      restore_env(:tax_calculator, previous_tax)
      restore_env(FlatRate, previous_flat_rate)
      restore_env(Simple, previous_simple_tax)
    end)

    {:ok, product: create_product("simple", Decimal.new("100.00"))}
  end

  describe "programmatic checkout flow" do
    test "prices a cart deterministically before checkout creation", %{product: product} do
      {:ok, cart} = Checkout.create_cart(%{})

      {:ok, updated} =
        Checkout.update_cart_lines(cart.cart_id, [
          %{action: "add", product_id: product.id, quantity: 2}
        ])

      assert updated.status == "cart_updated"
      assert Enum.map(updated.line_items, & &1.product_id) == [product.id]

      {:ok, _response} =
        Checkout.set_buyer_identity(cart.cart_id, %{
          email: "buyer@example.com",
          first_name: "Ada",
          last_name: "Agent"
        })

      {:ok, priced} =
        Checkout.set_shipping_address(
          cart.cart_id,
          %{
            line1: "123 Market St",
            city: "San Francisco",
            state: "CA",
            postal_code: "94105",
            country: "US"
          },
          shipping_method: "standard"
        )

      assert priced.price_breakdown.subtotal.amount == "200.00"
      assert priced.price_breakdown.shipping_total.amount == "9.99"
      assert priced.price_breakdown.tax_total.amount == "17.50"
      assert priced.price_breakdown.duties_total.amount == "0.00"
      assert priced.price_breakdown.grand_total.amount == "227.49"
      assert priced.shipping_method == "standard"
      assert hd(priced.line_items).product_id == product.id
      assert hd(priced.line_items).variant_id == nil
    end

    test "creates an idempotent checkout session with a redirect handoff", %{product: product} do
      {:ok, cart_id} = build_ready_cart(product)

      request = %{
        idempotency_key: "checkout-#{Ecto.UUID.generate()}",
        session_kind: "redirect",
        redirect_url: "https://merchant.example/checkout"
      }

      {:ok, first} =
        Checkout.create_checkout_session(cart_id, request,
          checkout_provider: TestCheckoutProvider
        )

      {:ok, second} =
        Checkout.create_checkout_session(cart_id, request,
          checkout_provider: TestCheckoutProvider
        )

      assert first.status == "checkout_session_created"
      assert first.checkout_session.id == second.checkout_session.id

      assert first.checkout_session.redirect_url ==
               "https://checkout.example/sessions/#{first.checkout_session.id}"

      assert first.checkout_session.retry_safe
      assert first.price_breakdown.grand_total.amount == "118.74"
    end

    test "creates a payment-session abstraction with a client secret", %{product: product} do
      {:ok, cart_id} = build_ready_cart(product)

      {:ok, response} =
        Checkout.create_payment_session(
          cart_id,
          %{
            idempotency_key: "payment-#{Ecto.UUID.generate()}",
            payment_flow: "payment_intent"
          },
          payment_provider: TestPaymentProvider
        )

      assert response.status == "payment_session_created"
      assert response.checkout_session.kind == "payment_intent"
      assert response.checkout_session.status == "requires_action"
      assert String.starts_with?(response.checkout_session.payment_client_secret, "secret_")
      assert response.checkout_session.redirect_url == nil
    end
  end

  describe "validation and failure paths" do
    test "rejects invalid checkout requests" do
      assert {:error, %ValidationError{}} =
               ProgrammaticCheckoutRequest.new(%{
                 buyer_identity: %{first_name: "No Email"}
               })
    end

    test "requires shipping address before pricing physical goods", %{product: product} do
      {:ok, cart} = Checkout.create_cart(%{})

      {:ok, _updated} =
        Checkout.update_cart_lines(cart.cart_id, [
          %{action: "add", product_id: product.id, quantity: 1}
        ])

      assert {:error, %ValidationError{code: :shipping_address_required}} =
               Checkout.price_checkout(cart.cart_id)
    end

    test "requires idempotency for checkout session creation", %{product: product} do
      {:ok, cart_id} = build_ready_cart(product)

      assert {:error, %Mercato.Checkout.IdempotencyError{}} =
               Checkout.create_checkout_session(cart_id, %{},
                 checkout_provider: TestCheckoutProvider
               )
    end

    test "fails invalid line operations cleanly", %{product: product} do
      {:ok, cart} = Checkout.create_cart(%{})

      assert {:error, %ValidationError{code: :invalid_quantity}} =
               Checkout.update_cart_lines(cart.cart_id, [
                 %{action: "add", product_id: product.id, quantity: 0}
               ])
    end
  end

  defp build_ready_cart(product) do
    {:ok, cart} = Checkout.create_cart(%{})

    {:ok, _updated} =
      Checkout.update_cart_lines(cart.cart_id, [
        %{action: "add", product_id: product.id, quantity: 1}
      ])

    {:ok, _identity} =
      Checkout.set_buyer_identity(cart.cart_id, %{
        email: "buyer@example.com",
        first_name: "Buyer",
        last_name: "Person"
      })

    {:ok, _address} =
      Checkout.set_shipping_address(
        cart.cart_id,
        %{
          line1: "123 Main St",
          city: "Los Angeles",
          state: "CA",
          postal_code: "90001",
          country: "US"
        },
        shipping_method: "standard"
      )

    {:ok, cart.cart_id}
  end

  defp create_product(product_type, price) do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Checkout Product #{System.unique_integer([:positive])}",
        slug: "checkout-product-#{System.unique_integer([:positive])}",
        price: price,
        sku: "CHECKOUT-#{System.unique_integer([:positive])}",
        product_type: product_type,
        status: "published",
        stock_quantity: 100
      })

    product
  end

  defp restore_env(key, nil), do: Application.delete_env(:mercato, key)
  defp restore_env(key, value), do: Application.put_env(:mercato, key, value)
end
