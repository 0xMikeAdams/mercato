# Mercato

<!-- [![Hex.pm](https://img.shields.io/hexpm/v/mercato.svg)](https://hex.pm/packages/mercato)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/mercato) -->

An embedded e-commerce engine for Elixir/Phoenix applications. Mercato provides product, cart, order, customer, subscription, and referral primitives with Phoenix-friendly route macros, Ecto contexts, and extension points for payment, shipping, and tax integrations.

## Features

- **Product Catalog**: Simple, variable, downloadable, virtual, and subscription products
- **Shopping Cart**: Anonymous and authenticated carts with real-time updates
- **Programmatic Checkout**: Agent-ready cart pricing, checkout handoffs, and payment-session abstractions
- **Order Management**: Complete order lifecycle with status tracking and audit trails
- **Customer Management**: Guest checkout and registered user support
- **Promotions**: Flexible coupon system with multiple discount types
- **Subscriptions**: Recurring billing with multiple cycle options
- **Referral System**: Commission tracking with shortlink attribution
- **Real-time Events**: PubSub-based notifications for all state changes
- **Extensible Behaviours**: Custom payment, shipping, and tax implementations

## Installation & Setup

Add `mercato` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mercato, "~> 0.1.0"}
  ]
end
```

Get dependencies and run installer:

```bash
mix deps.get
mix mercato.install
```

The installation command will:
- Copy necessary migrations to your application
- Create/update `config/mercato.exs` and import it from `config/config.exs`
- Inject safe public-route scaffolding plus commented customer/admin examples into your Phoenix router


Run Migrations:

```bash
mix ecto.migrate
```

Verify Configuration:

The installer creates `config/mercato.exs` with safe defaults:

```elixir
config :mercato,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  payment_gateway: nil,
  checkout_provider: Mercato.Checkout.Providers.DefaultCheckoutProvider,
  payment_provider: Mercato.Checkout.Providers.LegacyPaymentProvider,
  shipping_calculator: Mercato.ShippingCalculators.FlatRate,
  tax_calculator: Mercato.TaxCalculators.Simple
```

Set `payment_gateway` to a real implementation before enabling live payment processing.

## Phoenix Integration

Mount Mercato routes by trust boundary and keep authentication in your host app pipelines:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import Mercato.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug :require_authenticated_user
  end

  pipeline :api_admin do
    plug :accepts, ["json"]
    plug :require_admin_user
  end

  scope "/api", MyAppWeb do
    pipe_through :api

    scope "/mercato", as: false do
      mercato_public_routes()
    end
  end

  scope "/api", MyAppWeb do
    pipe_through :api_authenticated

    scope "/mercato", as: false do
      mercato_customer_routes()
    end
  end

  scope "/api", MyAppWeb do
    pipe_through :api_admin

    scope "/mercato/admin", as: false do
      mercato_admin_routes()
    end
  end

  mercato_referral_routes(api_prefix: "/api/mercato")
end
```

Mercato expects:

- customer routes to receive `conn.assigns[:current_user]`
- admin routes to receive `conn.assigns[:mercato_admin?] == true`

See `docs/production_integration.md` for the full production checklist.

## Getting Started

### Basic Usage

```elixir
# Create a product
{:ok, product} = Mercato.Catalog.create_product(%{
  name: "Premium T-Shirt",
  slug: "premium-t-shirt",
  price: Decimal.new("29.99"),
  sku: "TSHIRT-001",
  product_type: "simple",
  status: "published",
  stock_quantity: 100
})

# Create a cart
{:ok, cart} = Mercato.Cart.create_cart(%{cart_token: "unique-session-token"})

# Add items to cart
{:ok, cart} = Mercato.Cart.add_item(cart.id, product.id, 2)

# Apply a coupon
{:ok, cart} = Mercato.Cart.apply_coupon(cart.id, "SAVE10")

# Create an order
{:ok, order} = Mercato.Orders.create_order_from_cart(cart.id, %{
  billing_address: %{
    line1: "123 Main St",
    city: "Anytown",
    state: "CA",
    postal_code: "12345",
    country: "US"
  },
  shipping_address: %{
    line1: "123 Main St",
    city: "Anytown", 
    state: "CA",
    postal_code: "12345",
    country: "US"
  },
  payment_method: "invoice",
  idempotency_key: "checkout-123"
})
```

For HTTP checkout retries, send the `Idempotency-Key` header on `POST /orders`.

### Programmatic Checkout

Use `Mercato.Checkout` when a backend service, workflow engine, or AI agent needs
to drive the entire cart-to-checkout lifecycle through code alone.

The public flow is:

1. `create_cart/2`
2. `update_cart_lines/3`
3. `set_buyer_identity/3`
4. `set_shipping_address/3`
5. `price_checkout/3`
6. `create_checkout_session/3`
7. `create_payment_session/3` or `create_payment_intent/3`

`price_checkout/3` always returns an explicit machine-readable totals object
before any checkout handoff or payment session is created.

```elixir
alias Mercato.Checkout

{:ok, cart} =
  Checkout.create_cart(%{
    cart_token: "agent-cart-123"
  })

{:ok, _cart} =
  Checkout.update_cart_lines(cart.cart_id, [
    %{action: "add", product_id: product.id, quantity: 2}
  ])

{:ok, _cart} =
  Checkout.set_buyer_identity(cart.cart_id, %{
    email: "buyer@example.com",
    first_name: "Ada",
    last_name: "Lovelace"
  })

{:ok, _cart} =
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

{:ok, quote} = Checkout.price_checkout(cart.cart_id)

quote.price_breakdown.grand_total.amount
#=> "74.97"

{:ok, session} =
  Checkout.create_checkout_session(cart.cart_id, %{
    idempotency_key: "checkout-123",
    session_kind: "managed"
  })

session.checkout_session.id
session.checkout_session.status
session.checkout_session.redirect_url
```

The returned `ProgrammaticCheckoutResponse` includes:

- `status`
- `cart_id` and `cart_token`
- canonical `product_id` and `variant_id` values for every line item
- `buyer_identity` and `shipping_address`
- `price_breakdown.subtotal`
- `price_breakdown.discount_total`
- `price_breakdown.shipping_total`
- `price_breakdown.tax_total`
- `price_breakdown.duties_total`
- `price_breakdown.grand_total`
- `checkout_session.id`
- `checkout_session.status`
- `checkout_session.redirect_url`
- `checkout_session.payment_client_secret`
- `retry_safe`

#### AI-Agent Usage

The checkout API is designed so an agent can answer four questions without
rendering browser UI:

- what is being bought: inspect `line_items`
- what is the exact final cost: inspect `price_breakdown`
- where does the user go next: inspect `checkout_session.redirect_url` or `checkout_session.payment_client_secret`
- can this be retried safely: inspect `retry_safe` and reuse `idempotency_key`

```elixir
{:ok, response} =
  Checkout.create_payment_intent(cart_id, %{
    idempotency_key: "agent-payment-123",
    payment_flow: "payment_intent"
  }, payment_provider: MyApp.StripePaymentProvider)

%{
  next_action: response.checkout_session.payment_client_secret,
  total: response.price_breakdown.grand_total.amount,
  currency: response.currency,
  retry_safe: response.retry_safe
}
```

### LiveView Integration

Real-time cart updates with Phoenix LiveView:

```elixir
defmodule YourAppWeb.CartLive do
  use YourAppWeb, :live_view
  alias Mercato.{Cart, Events}

  def mount(_params, %{"cart_token" => cart_token}, socket) do
    if connected?(socket) do
      Events.subscribe_to_cart(cart_token)
    end

    {:ok, cart} = Cart.get_cart_by_token(cart_token)
    {:ok, assign(socket, cart: cart, cart_token: cart_token)}
  end

  def handle_info({:cart_updated, cart}, socket) do
    {:noreply, assign(socket, cart: cart)}
  end

  def handle_event("add_item", %{"product_id" => product_id}, socket) do
    {:ok, _cart} = Cart.add_item(socket.assigns.cart.id, product_id, 1)
    {:noreply, socket}
  end

  def handle_event("remove_item", %{"item_id" => item_id}, socket) do
    {:ok, _cart} = Cart.remove_item(socket.assigns.cart.id, item_id)
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="cart">
      <h2>Shopping Cart (<%= length(@cart.cart_items) %> items)</h2>
      
      <div :for={item <- @cart.cart_items} class="cart-item">
        <span><%= item.product.name %></span>
        <span>Qty: <%= item.quantity %></span>
        <span>$<%= item.total_price %></span>
        <button phx-click="remove_item" phx-value-item_id={item.id}>Remove</button>
      </div>
      
      <div class="cart-total">
        <strong>Total: $<%= @cart.grand_total %></strong>
      </div>
    </div>
    """
  end
end
```

## Configuration Options

### Store Settings

Configure store-wide settings:

```elixir
config :mercato,
  store_settings: %{
    currency: "USD",
    locale: "en",
    default_tax_rate: 0.08,
    store_address: %{
      line1: "123 Store St",
      city: "Store City",
      state: "ST", 
      postal_code: "12345",
      country: "US"
    }
  }
```

### Custom Behaviours

Implement custom payment, shipping, and tax logic:

```elixir
# Custom payment gateway
defmodule MyApp.PaymentGateway do
  @behaviour Mercato.PaymentGateway

  def authorize(amount, payment_details, opts) do
    # Your payment logic here
    {:ok, "transaction_id"}
  end

  def capture(transaction_id, amount, opts) do
    # Your capture logic here
    {:ok, %{status: "captured"}}
  end

  def refund(transaction_id, amount, opts) do
    # Your refund logic here
    {:ok, %{status: "refunded"}}
  end
end

# Configure in your app
config :mercato,
  payment_gateway: MyApp.PaymentGateway
```

### Environment-Specific Configuration

Mercato runs on whatever repo you configure via `config :mercato, :repo` (the installer sets this to `MyApp.Repo`). Configure your repo normally in `config/dev.exs`, `config/test.exs`, and `config/runtime.exs`.

## API Overview

Mercato is organized into contexts that provide clear APIs:

- **`Mercato.Catalog`** - Product and inventory management
- **`Mercato.Cart`** - Shopping cart operations  
- **`Mercato.Orders`** - Order creation and management
- **`Mercato.Customers`** - Customer profiles and addresses
- **`Mercato.Coupons`** - Discount code management
- **`Mercato.Subscriptions`** - Recurring billing
- **`Mercato.Referrals`** - Referral tracking and commissions
- **`Mercato.Config`** - Store settings and configuration

### Product Management

```elixir
# List products with filters
products = Mercato.Catalog.list_products(status: "published", limit: 10)

# Get a specific product
product = Mercato.Catalog.get_product!("product-id")

# Create a product with variants
{:ok, product} = Mercato.Catalog.create_product(%{
  name: "Variable T-Shirt",
  product_type: "variable",
  # ... other fields
})

{:ok, variant} = Mercato.Catalog.create_variant(product.id, %{
  sku: "TSHIRT-RED-L",
  attributes: %{color: "red", size: "L"},
  price: Decimal.new("29.99")
})
```

### Cart Management

```elixir
# Get or create cart
{:ok, cart} = Mercato.Cart.get_cart_by_token("session-token")

# Add items
{:ok, cart} = Mercato.Cart.add_item(cart.id, product_id, 2)

# Update quantity
{:ok, cart} = Mercato.Cart.update_item_quantity(cart.id, item_id, 3)

# Apply coupon
{:ok, cart} = Mercato.Cart.apply_coupon(cart.id, "DISCOUNT10")
```

### Order Processing

```elixir
# Create order from cart
{:ok, order} = Mercato.Orders.create_order_from_cart(cart.id, order_attrs)

# Update order status
{:ok, order} = Mercato.Orders.update_status(order.id, :processing)

# Get order history
orders = Mercato.Orders.list_orders(user_id: user_id)
```

## Real-time Features

Mercato includes built-in real-time capabilities using Phoenix PubSub:

```elixir
# Subscribe to cart updates
Mercato.Events.subscribe_to_cart(cart_token)

# Subscribe to order updates  
Mercato.Events.subscribe_to_order(order_id)

# Handle events in LiveView
def handle_info({:cart_updated, cart}, socket) do
  {:noreply, assign(socket, cart: cart)}
end

def handle_info({:order_status_changed, order, old_status, new_status}, socket) do
  # Handle order status change
  {:noreply, socket}
end
```

For programmatic checkout, prefer the new checkout-specific adapters:

```elixir
config :mercato,
  checkout_provider: MyApp.RedirectCheckoutProvider,
  payment_provider: MyApp.StripePaymentProvider
```

`checkout_provider` is responsible for redirect or managed checkout handoffs.
`payment_provider` is responsible for payment-session or payment-intent creation.
The default payment adapter wraps the existing `payment_gateway`, so browser-based
order flows continue to work without changes.

## Migration Notes

- Run the new migration to add persisted checkout metadata on carts and explicit `duties_total` fields on carts/orders.
- Existing `Mercato.Cart` and `Mercato.Orders` APIs remain backward-compatible.
- Existing browser/API order creation flows continue to use `Mercato.Orders.create_order_from_cart/2`.
- `Mercato.Checkout` is additive and can be adopted incrementally alongside the existing HTTP controllers.

## Testing

Mercato includes comprehensive test support with ExMachina factories and StreamData generators:

```elixir
# In your test files
use Mercato.DataCase

test "creates order from cart" do
  product = insert(:product)
  cart = insert(:cart)
  cart_item = insert(:cart_item, cart: cart, product: product)
  
  {:ok, order} = Mercato.Orders.create_order_from_cart(cart.id, %{
    billing_address: build(:address),
    shipping_address: build(:address)
  })
  
  assert order.status == :pending
  assert length(order.order_items) == 1
end
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

<!-- ## Documentation

Full documentation is available at [https://hexdocs.pm/mercato](https://hexdocs.pm/mercato). -->

## Support

<!-- - [Documentation](https://hexdocs.pm/mercato) -->
- [Issue Tracker](https://github.com/0xMikeAdams/mercato/issues)
- [Discussions](https://github.com/0xMikeAdams/mercato/discussions)
