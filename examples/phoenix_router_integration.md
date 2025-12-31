# Phoenix Router Integration Examples

This document provides comprehensive examples for integrating Mercato with Phoenix routers.

## Basic Integration

### Full API Routes

```elixir
defmodule MyStoreWeb.Router do
  use MyStoreWeb, :router
  import Mercato.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {MyStoreWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :authenticated do
    plug MyStoreWeb.Plugs.RequireAuth
  end

  pipeline :admin do
    plug MyStoreWeb.Plugs.RequireAdmin
  end

  # Public API routes
  scope "/api/v1", MyStoreWeb do
    pipe_through :api

    # Mount all Mercato API routes
    mercato_api_routes()
  end

  # Authenticated API routes
  scope "/api/v1", MyStoreWeb do
    pipe_through [:api, :authenticated]

    # Customer-specific routes
    get "/customers/profile", CustomerController, :show_profile
    put "/customers/profile", CustomerController, :update_profile
    get "/customers/orders", CustomerController, :order_history
    get "/customers/addresses", CustomerController, :list_addresses
    post "/customers/addresses", CustomerController, :create_address

    # Subscription management
    get "/subscriptions", SubscriptionController, :index
    post "/subscriptions/:id/pause", SubscriptionController, :pause
    post "/subscriptions/:id/resume", SubscriptionController, :resume
    post "/subscriptions/:id/cancel", SubscriptionController, :cancel

    # Referral management
    get "/referrals/stats", ReferralController, :stats
    post "/referrals/generate", ReferralController, :generate_code
  end

  # Admin API routes
  scope "/admin/api", MyStoreWeb do
    pipe_through [:api, :authenticated, :admin]

    mercato_admin_routes()
  end

  # Referral shortlinks (browser routes)
  scope "/", MyStoreWeb do
    pipe_through :browser

    get "/r/:code", Mercato.ReferralController, :redirect
  end

  # Web interface routes
  scope "/", MyStoreWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/products", ProductController, :index
    get "/products/:slug", ProductController, :show
    get "/cart", CartController, :show
    get "/checkout", CheckoutController, :show
    post "/checkout", CheckoutController, :create_order
    get "/orders/:id", OrderController, :show
  end

  # LiveView routes
  scope "/", MyStoreWeb do
    pipe_through :browser

    live "/live/products", ProductLive.Index, :index
    live "/live/products/:id", ProductLive.Show, :show
    live "/live/cart", CartLive.Index, :index
    live "/live/checkout", CheckoutLive.Index, :index
    live "/live/orders/:id", OrderLive.Show, :show
  end
end
```

### Minimal Integration

For simple stores that only need basic functionality:

```elixir
defmodule SimpleStoreWeb.Router do
  use SimpleStoreWeb, :router
  import Mercato.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
  end

  # Basic e-commerce API
  scope "/api", SimpleStoreWeb do
    pipe_through :api

    # Only essential routes
    mercato_basic_routes()
  end

  # Referral shortlinks
  scope "/", SimpleStoreWeb do
    pipe_through :browser
    get "/r/:code", Mercato.ReferralController, :redirect
  end

  # Simple web interface
  scope "/", SimpleStoreWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/products", ProductController, :index
    get "/cart", CartController, :show
    post "/checkout", CheckoutController, :create_order
  end
end
```

### Scoped Integration

For applications that need Mercato under a specific path:

```elixir
defmodule MultiTenantWeb.Router do
  use MultiTenantWeb, :router
  import Mercato.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :store_context do
    plug MultiTenantWeb.Plugs.LoadStore
  end

  # Store-specific routes with subdomain or path
  scope "/store/:store_id/api", MultiTenantWeb do
    pipe_through [:api, :store_context]

    mercato_api_routes(prefix: "/v1")
  end

  # Store-specific referral links
  scope "/store/:store_id", MultiTenantWeb do
    pipe_through [:browser, :store_context]

    get "/r/:code", Mercato.ReferralController, :redirect
  end
end
```

## Custom Controller Examples

### Product Controller

```elixir
defmodule MyStoreWeb.ProductController do
  use MyStoreWeb, :controller
  alias Mercato.Catalog

  def index(conn, params) do
    products = Catalog.list_products(
      status: "published",
      preload: [:categories, :tags, :variants]
    )

    render(conn, "index.json", products: products)
  end

  def show(conn, %{"id" => id}) do
    product = Catalog.get_product!(id, preload: [:categories, :tags, :variants])
    render(conn, "show.json", product: product)
  end

  # Admin-only actions
  def create(conn, %{"product" => product_params}) do
    case Catalog.create_product(product_params) do
      {:ok, product} ->
        conn
        |> put_status(:created)
        |> render("show.json", product: product)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", changeset: changeset)
    end
  end

  def update(conn, %{"id" => id, "product" => product_params}) do
    product = Catalog.get_product!(id)

    case Catalog.update_product(product, product_params) do
      {:ok, product} ->
        render(conn, "show.json", product: product)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", changeset: changeset)
    end
  end
end
```

### Cart Controller

```elixir
defmodule MyStoreWeb.CartController do
  use MyStoreWeb, :controller
  alias Mercato.Cart

  def show(conn, %{"cart_token" => cart_token}) do
    case Cart.get_cart(cart_token) do
      {:ok, cart} ->
        render(conn, "show.json", cart: cart)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render("error.json", message: "Cart not found")
    end
  end

  def create(conn, _params) do
    cart_token = generate_cart_token()
    {:ok, cart} = Cart.create_cart(%{cart_token: cart_token})

    conn
    |> put_status(:created)
    |> render("show.json", cart: cart)
  end

  def add_item(conn, %{"cart_token" => cart_token, "product_id" => product_id, "quantity" => quantity}) do
    case Cart.add_item(cart_token, product_id, quantity) do
      {:ok, cart} ->
        render(conn, "show.json", cart: cart)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", message: format_error(reason))
    end
  end

  def update_item(conn, %{"cart_token" => cart_token, "item_id" => item_id, "quantity" => quantity}) do
    case Cart.update_item_quantity(cart_token, item_id, quantity) do
      {:ok, cart} ->
        render(conn, "show.json", cart: cart)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", message: format_error(reason))
    end
  end

  def remove_item(conn, %{"cart_token" => cart_token, "item_id" => item_id}) do
    {:ok, cart} = Cart.remove_item(cart_token, item_id)
    render(conn, "show.json", cart: cart)
  end

  def apply_coupon(conn, %{"cart_token" => cart_token, "coupon_code" => coupon_code}) do
    case Cart.apply_coupon(cart_token, coupon_code) do
      {:ok, cart} ->
        render(conn, "show.json", cart: cart)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", message: format_coupon_error(reason))
    end
  end

  defp generate_cart_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp format_error(:insufficient_stock), do: "Insufficient stock available"
  defp format_error(:product_not_found), do: "Product not found"
  defp format_error(reason), do: "Error: #{reason}"

  defp format_coupon_error(:coupon_not_found), do: "Coupon code not found"
  defp format_coupon_error(:coupon_expired), do: "Coupon has expired"
  defp format_coupon_error(:usage_limit_exceeded), do: "Coupon usage limit exceeded"
  defp format_coupon_error(reason), do: "Coupon error: #{reason}"
end
```

### Order Controller

```elixir
defmodule MyStoreWeb.OrderController do
  use MyStoreWeb, :controller
  alias Mercato.{Orders, Cart}

  def index(conn, params) do
    user_id = get_current_user_id(conn)
    orders = Orders.list_orders(user_id: user_id, limit: 20)
    render(conn, "index.json", orders: orders)
  end

  def show(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    
    # Ensure user can only see their own orders (unless admin)
    if can_view_order?(conn, order) do
      render(conn, "show.json", order: order)
    else
      conn
      |> put_status(:forbidden)
      |> render("error.json", message: "Access denied")
    end
  end

  def create(conn, %{"cart_token" => cart_token} = params) do
    order_params = %{
      billing_address: params["billing_address"],
      shipping_address: params["shipping_address"],
      payment_method: params["payment_method"],
      customer_notes: params["customer_notes"]
    }

    case Orders.create_order_from_cart(cart_token, order_params) do
      {:ok, order} ->
        # Clear the cart after successful order creation
        Cart.clear_cart(cart_token)

        conn
        |> put_status(:created)
        |> render("show.json", order: order)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", message: format_order_error(reason))
    end
  end

  def update_status(conn, %{"id" => id, "status" => new_status}) do
    # Admin only
    case Orders.update_status(id, new_status) do
      {:ok, order} ->
        render(conn, "show.json", order: order)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", message: format_order_error(reason))
    end
  end

  def cancel(conn, %{"id" => id}) do
    reason = get_in(conn.params, ["reason"]) || "Customer request"

    case Orders.cancel_order(id, reason) do
      {:ok, order} ->
        render(conn, "show.json", order: order)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", message: format_order_error(reason))
    end
  end

  defp can_view_order?(conn, order) do
    current_user_id = get_current_user_id(conn)
    is_admin?(conn) || order.user_id == current_user_id
  end

  defp get_current_user_id(conn) do
    # Implementation depends on your auth system
    conn.assigns[:current_user][:id]
  end

  defp is_admin?(conn) do
    # Implementation depends on your auth system
    conn.assigns[:current_user][:role] == "admin"
  end

  defp format_order_error(:empty_cart), do: "Cart is empty"
  defp format_order_error(:invalid_address), do: "Invalid address information"
  defp format_order_error(:payment_failed), do: "Payment processing failed"
  defp format_order_error(reason), do: "Order error: #{reason}"
end
```

## Authentication Integration

### Plug for Cart Token Management

```elixir
defmodule MyStoreWeb.Plugs.CartToken do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cart_token = get_cart_token(conn)
    assign(conn, :cart_token, cart_token)
  end

  defp get_cart_token(conn) do
    # Try to get from session first
    case get_session(conn, :cart_token) do
      nil ->
        # Generate new token and store in session
        token = generate_cart_token()
        put_session(conn, :cart_token, token)
        token

      token ->
        token
    end
  end

  defp generate_cart_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
```

### User Association Plug

```elixir
defmodule MyStoreWeb.Plugs.AssociateUserCart do
  import Plug.Conn
  alias Mercato.Cart

  def init(opts), do: opts

  def call(conn, _opts) do
    case {conn.assigns[:current_user], conn.assigns[:cart_token]} do
      {%{id: user_id}, cart_token} when not is_nil(cart_token) ->
        # Associate anonymous cart with logged-in user
        Cart.associate_user(cart_token, user_id)
        conn

      _ ->
        conn
    end
  end
end
```

## Error Handling

### Custom Error Views

```elixir
defmodule MyStoreWeb.ErrorView do
  use MyStoreWeb, :view

  def render("error.json", %{message: message}) do
    %{error: message}
  end

  def render("error.json", %{changeset: changeset}) do
    %{errors: translate_errors(changeset)}
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
```

## Testing Integration

### Controller Tests

```elixir
defmodule MyStoreWeb.CartControllerTest do
  use MyStoreWeb.ConnCase
  alias Mercato.{Cart, Catalog}

  setup do
    product = insert(:product, price: Decimal.new("29.99"))
    cart_token = "test-cart-token"
    {:ok, cart} = Cart.create_cart(%{cart_token: cart_token})

    %{product: product, cart: cart, cart_token: cart_token}
  end

  describe "GET /api/carts/:cart_token" do
    test "returns cart with items", %{conn: conn, cart_token: cart_token} do
      conn = get(conn, Routes.cart_path(conn, :show, cart_token))
      
      assert %{
        "id" => _,
        "cart_token" => ^cart_token,
        "cart_items" => [],
        "grand_total" => "0.00"
      } = json_response(conn, 200)["data"]
    end
  end

  describe "POST /api/carts/:cart_token/items" do
    test "adds item to cart", %{conn: conn, cart_token: cart_token, product: product} do
      params = %{
        "product_id" => product.id,
        "quantity" => 2
      }

      conn = post(conn, Routes.cart_path(conn, :add_item, cart_token), params)
      
      assert %{
        "cart_items" => [%{
          "product_id" => product_id,
          "quantity" => 2,
          "total_price" => "59.98"
        }],
        "grand_total" => "59.98"
      } = json_response(conn, 200)["data"]

      assert product_id == product.id
    end
  end
end
```

This comprehensive router integration guide covers all the major patterns for integrating Mercato with Phoenix applications.