# Mercato

[![Hex.pm](https://img.shields.io/hexpm/v/mercato.svg)](https://hex.pm/packages/mercato)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/mercato)

A production-ready, open-source e-commerce engine for Elixir/Phoenix applications. Mercato provides comprehensive WooCommerce-level functionality built idiomatically with Elixir, Ecto, and Phoenix, featuring real-time capabilities and extensible architecture.

## Features

- 🛍️ **Product Catalog**: Simple, variable, downloadable, virtual, and subscription products
- 🛒 **Shopping Cart**: Anonymous and authenticated carts with real-time updates
- 📦 **Order Management**: Complete order lifecycle with status tracking and audit trails
- 👥 **Customer Management**: Guest checkout and registered user support
- 🎫 **Promotions**: Flexible coupon system with multiple discount types
- 🔄 **Subscriptions**: Recurring billing with multiple cycle options
- 🔗 **Referral System**: Commission tracking with shortlink attribution
- ⚡ **Real-time Events**: PubSub-based notifications for all state changes
- 🔧 **Extensible Behaviours**: Custom payment, shipping, and tax implementations

## Installation

Add `mercato` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mercato, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
mix mercato.install
```

The installation command will:
- Copy all necessary migrations to your application
- Generate configuration templates
- Create sample integration files
- Display setup instructions

## Quick Setup

### 1. Configuration

Add Mercato configuration to your `config/config.exs`:

```elixir
config :mercato, Mercato.Repo,
  database: "your_app_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :mercato,
  ecto_repos: [Mercato.Repo],
  # Optional: Configure custom behaviours
  payment_gateway: Mercato.PaymentGateways.Dummy,
  shipping_calculator: Mercato.ShippingCalculators.FlatRate,
  tax_calculator: Mercato.TaxCalculators.Simple
```

### 2. Application Setup

Add Mercato to your application supervision tree in `lib/your_app/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # ... your existing children
    Mercato.Repo,
    {Phoenix.PubSub, name: Mercato.PubSub}
  ]

  opts = [strategy: :one_for_one, name: YourApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### 3. Database Setup

Run the migrations:

```bash
mix ecto.create
mix ecto.migrate
```

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
  payment_method: "stripe"
})
```

### Phoenix Router Integration

Add Mercato routes to your router:

```elixir
defmodule YourAppWeb.Router do
  use YourAppWeb, :router
  import Mercato.Router

  # API routes for e-commerce functionality
  scope "/api", YourAppWeb do
    pipe_through :api
    mercato_api_routes()
  end

  # Referral shortlinks
  scope "/", YourAppWeb do
    pipe_through :browser
    get "/r/:code", Mercato.ReferralController, :redirect
  end
end
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

    {:ok, cart} = Cart.get_cart(cart_token)
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

#### Development (`config/dev.exs`)

```elixir
config :mercato, Mercato.Repo,
  database: "your_app_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

#### Test (`config/test.exs`)

```elixir
config :mercato, Mercato.Repo,
  database: "your_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
```

#### Production (`config/prod.exs`)

```elixir
config :mercato, Mercato.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true
```

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
{:ok, cart} = Mercato.Cart.get_cart("session-token")

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

## Documentation

Full documentation is available at [https://hexdocs.pm/mercato](https://hexdocs.pm/mercato).

## Support

- 📖 [Documentation](https://hexdocs.pm/mercato)
- 🐛 [Issue Tracker](https://github.com/yourusername/mercato/issues)
- 💬 [Discussions](https://github.com/yourusername/mercato/discussions)

