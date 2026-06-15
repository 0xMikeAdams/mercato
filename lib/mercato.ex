defmodule Mercato do
  @moduledoc """
  Mercato is an embedded e-commerce engine for Elixir/Phoenix applications.

  ## Overview

  Mercato provides a reusable commerce domain layer built idiomatically with Elixir,
  Ecto, and Phoenix. Host applications own authentication, authorization, health checks,
  payment provider selection, and deployment wiring.

  ## Key Features

  - **Product Catalog**: Simple, variable, downloadable, virtual, and subscription products
  - **Shopping Cart**: Anonymous and authenticated carts with real-time updates
  - **Order Management**: Complete order lifecycle with status tracking and audit trails
  - **Customer Management**: Guest checkout and registered user support
  - **Promotions**: Flexible coupon system with multiple discount types
  - **Subscriptions**: Recurring billing with multiple cycle options
  - **Referral System**: Commission tracking with shortlink attribution
  - **Real-time Events**: PubSub-based notifications for all state changes
  - **Extensible Behaviours**: Custom payment, shipping, and tax implementations

  ## Installation

  Add `mercato` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:mercato, "~> 0.1.0"}
        ]
      end

  Then run:

      mix deps.get
      mix mercato.install

  ## Configuration

  Configure Mercato with your host application's repo and pubsub:

      config :mercato,
        repo: MyApp.Repo,
        pubsub: MyApp.PubSub,
        payment_gateway: MyApp.PaymentGateway

  ## Extension points

  Mercato has **one** public extension contract: implement a behaviour and point a config
  key at your module. These are the integration seams for payment, shipping, and tax:

  | Behaviour to implement                   | Config key            | Default            |
  | ---------------------------------------- | --------------------- | ------------------ |
  | `Mercato.Behaviours.PaymentGateway`      | `:payment_gateway`    | (none — required for live payments) |
  | `Mercato.Behaviours.ShippingCalculator`  | `:shipping_calculator`| `Mercato.ShippingCalculators.FlatRate` |
  | `Mercato.Behaviours.TaxCalculator`       | `:tax_calculator`     | `Mercato.TaxCalculators.Simple` |

      config :mercato,
        payment_gateway: MyApp.Payments.Stripe,
        shipping_calculator: MyApp.Shipping.UPS,
        tax_calculator: MyApp.Tax.Avalara

  These behaviours are consumed by both the cart/order flow and the programmatic-checkout
  flow, so implementing them is all most integrations need.

  > #### Advanced: checkout providers {: .info}
  >
  > The `Mercato.Checkout.{CheckoutProvider, PaymentProvider, ShippingProvider, PricingProvider}`
  > modules are an **internal orchestration layer** for programmatic checkout whose defaults
  > delegate down to the behaviours above (e.g. `DefaultPaymentProvider` bridges to your
  > `PaymentGateway`). Override `:checkout_provider` / `:payment_provider` / `:pricing_provider`
  > only when you need to replace an entire checkout phase (e.g. a redirect/client-secret
  > payment flow). They are not the place to plug in a payment gateway, shipping, or tax engine.

  ## Usage

  Mercato is organized into contexts that provide clear APIs for different domains:

  - `Mercato.Catalog` - Product and inventory management
  - `Mercato.Cart` - Shopping cart operations
  - `Mercato.Checkout` - Programmatic cart pricing and checkout orchestration
  - `Mercato.Orders` - Order creation and management
  - `Mercato.Customers` - Customer profiles and addresses
  - `Mercato.Coupons` - Discount code management
  - `Mercato.Subscriptions` - Recurring billing
  - `Mercato.Referrals` - Referral tracking and commissions
  - `Mercato.Config` - Store settings and configuration

  ## Example

      # Create a product
      {:ok, product} = Mercato.Catalog.create_product(%{
        name: "T-Shirt",
        slug: "t-shirt",
        price: Decimal.new("29.99"),
        sku: "TSHIRT-001",
        product_type: "simple",
        status: "published"
      })

      # Create a cart and add items
      {:ok, cart} = Mercato.Cart.create_cart(%{cart_token: "unique-token"})
      {:ok, cart} = Mercato.Cart.add_item(cart.id, product.id, 2)

      # Create an order from cart
      {:ok, order} = Mercato.Orders.create_order_from_cart(cart.id, %{
        billing_address: %{...},
        shipping_address: %{...},
        payment_method: "stripe"
      })
  """

  @doc """
  Returns the version of Mercato.
  """
  def version do
    Application.spec(:mercato, :vsn) |> to_string()
  end

  @doc """
  Returns the configured Ecto repo module used by Mercato.

  Host applications typically set this to their own repo:

      config :mercato, :repo, MyApp.Repo
  """
  def repo do
    Application.get_env(:mercato, :repo, Mercato.Repo)
  end

  @doc """
  Returns the configured Phoenix PubSub server used by Mercato events.

  Host applications can override this to use their existing PubSub:

      config :mercato, :pubsub, MyApp.PubSub
  """
  def pubsub do
    Application.get_env(:mercato, :pubsub, Mercato.PubSub)
  end

  @doc false
  def repo_started? do
    repo()
    |> Process.whereis()
    |> is_pid()
  end
end
