defmodule Mercato do
  @moduledoc """
  Mercato is a production-ready, open-source e-commerce engine for Elixir/Phoenix applications.

  ## Overview

  Mercato provides comprehensive WooCommerce-level functionality built idiomatically with Elixir,
  Ecto, and Phoenix. It features real-time capabilities through Phoenix PubSub and an extensible
  architecture through Elixir behaviours.

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

  Configure Mercato in your `config/config.exs`:

      config :mercato, Mercato.Repo,
        database: "mercato_dev",
        username: "postgres",
        password: "postgres",
        hostname: "localhost"

      config :mercato,
        ecto_repos: [Mercato.Repo]

  ## Usage

  Mercato is organized into contexts that provide clear APIs for different domains:

  - `Mercato.Catalog` - Product and inventory management
  - `Mercato.Cart` - Shopping cart operations
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
end
