defmodule Mercato.Router do
  @moduledoc """
  Phoenix router helpers for integrating Mercato API routes.

  This module provides macros to easily mount Mercato's API routes
  into a Phoenix application's router.

  ## Usage

  In your Phoenix router:

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import Mercato.Router

        pipeline :api do
          plug :accepts, ["json"]
        end

        scope "/api/v1", MyAppWeb do
          pipe_through :api
          mercato_api_routes()
        end
      end

  This will mount all Mercato API routes under the `/api/v1` scope.

  ## Available Routes

  The `mercato_api_routes/0` macro defines the following routes:

  ### Products
  - `GET /products` - List products
  - `GET /products/:id` - Get product details
  - `POST /products` - Create product (admin)
  - `PUT /products/:id` - Update product (admin)
  - `DELETE /products/:id` - Delete product (admin)
  - `GET /products/:id/variants` - List product variants
  - `POST /products/:id/variants` - Create product variant (admin)

  ### Categories
  - `GET /categories` - List categories
  - `GET /categories/:id` - Get category details
  - `GET /categories/:id/products` - List products in category

  ### Tags
  - `GET /tags` - List tags
  - `GET /tags/:id/products` - List products with tag

  ### Carts
  - `GET /carts/:cart_token` - Get cart by token
  - `POST /carts` - Create new cart
  - `POST /carts/:cart_token/items` - Add item to cart
  - `PUT /carts/:cart_token/items/:item_id` - Update cart item quantity
  - `DELETE /carts/:cart_token/items/:item_id` - Remove item from cart
  - `DELETE /carts/:cart_token` - Clear cart
  - `POST /carts/:cart_token/coupons` - Apply coupon to cart
  - `DELETE /carts/:cart_token/coupons` - Remove coupon from cart

  ### Orders
  - `GET /orders` - List orders (authenticated)
  - `GET /orders/:id` - Get order details
  - `POST /orders` - Create order from cart
  - `PUT /orders/:id/status` - Update order status (admin)
  - `POST /orders/:id/cancel` - Cancel order
  - `POST /orders/:id/refund` - Refund order (admin)

  ### Customers
  - `GET /customers/profile` - Get customer profile (authenticated)
  - `PUT /customers/profile` - Update customer profile (authenticated)
  - `GET /customers/addresses` - List customer addresses (authenticated)
  - `POST /customers/addresses` - Add customer address (authenticated)
  - `PUT /customers/addresses/:id` - Update customer address (authenticated)
  - `DELETE /customers/addresses/:id` - Delete customer address (authenticated)
  - `GET /customers/orders` - Get customer order history (authenticated)

  ### Subscriptions
  - `GET /subscriptions` - List customer subscriptions (authenticated)
  - `GET /subscriptions/:id` - Get subscription details (authenticated)
  - `POST /subscriptions/:id/pause` - Pause subscription (authenticated)
  - `POST /subscriptions/:id/resume` - Resume subscription (authenticated)
  - `POST /subscriptions/:id/cancel` - Cancel subscription (authenticated)

  ### Referrals
  - `GET /referrals/stats` - Get referral statistics (authenticated)
  - `POST /referrals/generate` - Generate referral code (authenticated)
  - `GET /referrals/code` - Get user's referral code (authenticated)

  ## Controller Modules

  The routes expect the following controller modules to be defined
  in the host application:

  - `ProductController`
  - `CategoryController`
  - `TagController`
  - `CartController`
  - `OrderController`
  - `CustomerController`
  - `SubscriptionController`
  - `ReferralController`

  Each controller should implement the actions corresponding to the routes above.
  """

  @doc """
  Defines all Mercato API routes.

  This macro should be called within a Phoenix router scope to mount
  all Mercato API endpoints.

  ## Options

  - `:prefix` - Optional path prefix for all routes (default: none)

  ## Examples

      # Mount routes at root level
      mercato_api_routes()

      # Mount routes with prefix
      mercato_api_routes(prefix: "/store")
  """
  defmacro mercato_api_routes(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")

    quote do
      # Product routes
      get "#{unquote(prefix)}/products", ProductController, :index
      get "#{unquote(prefix)}/products/:id", ProductController, :show
      post "#{unquote(prefix)}/products", ProductController, :create
      put "#{unquote(prefix)}/products/:id", ProductController, :update
      delete "#{unquote(prefix)}/products/:id", ProductController, :delete

      # Product variant routes
      get "#{unquote(prefix)}/products/:product_id/variants", ProductController, :list_variants
      post "#{unquote(prefix)}/products/:product_id/variants", ProductController, :create_variant

      # Category routes
      get "#{unquote(prefix)}/categories", CategoryController, :index
      get "#{unquote(prefix)}/categories/:id", CategoryController, :show
      get "#{unquote(prefix)}/categories/:id/products", CategoryController, :products

      # Tag routes
      get "#{unquote(prefix)}/tags", TagController, :index
      get "#{unquote(prefix)}/tags/:id/products", TagController, :products

      # Cart routes
      get "#{unquote(prefix)}/carts/:cart_token", CartController, :show
      post "#{unquote(prefix)}/carts", CartController, :create
      post "#{unquote(prefix)}/carts/:cart_token/items", CartController, :add_item
      put "#{unquote(prefix)}/carts/:cart_token/items/:item_id", CartController, :update_item
      delete "#{unquote(prefix)}/carts/:cart_token/items/:item_id", CartController, :remove_item
      delete "#{unquote(prefix)}/carts/:cart_token", CartController, :clear

      # Cart coupon routes
      post "#{unquote(prefix)}/carts/:cart_token/coupons", CartController, :apply_coupon
      delete "#{unquote(prefix)}/carts/:cart_token/coupons", CartController, :remove_coupon

      # Order routes
      get "#{unquote(prefix)}/orders", OrderController, :index
      get "#{unquote(prefix)}/orders/:id", OrderController, :show
      post "#{unquote(prefix)}/orders", OrderController, :create
      put "#{unquote(prefix)}/orders/:id/status", OrderController, :update_status
      post "#{unquote(prefix)}/orders/:id/cancel", OrderController, :cancel
      post "#{unquote(prefix)}/orders/:id/refund", OrderController, :refund

      # Customer routes
      get "#{unquote(prefix)}/customers/profile", CustomerController, :show_profile
      put "#{unquote(prefix)}/customers/profile", CustomerController, :update_profile
      get "#{unquote(prefix)}/customers/addresses", CustomerController, :list_addresses
      post "#{unquote(prefix)}/customers/addresses", CustomerController, :create_address
      put "#{unquote(prefix)}/customers/addresses/:id", CustomerController, :update_address
      delete "#{unquote(prefix)}/customers/addresses/:id", CustomerController, :delete_address
      get "#{unquote(prefix)}/customers/orders", CustomerController, :order_history

      # Subscription routes
      get "#{unquote(prefix)}/subscriptions", SubscriptionController, :index
      get "#{unquote(prefix)}/subscriptions/:id", SubscriptionController, :show
      post "#{unquote(prefix)}/subscriptions/:id/pause", SubscriptionController, :pause
      post "#{unquote(prefix)}/subscriptions/:id/resume", SubscriptionController, :resume
      post "#{unquote(prefix)}/subscriptions/:id/cancel", SubscriptionController, :cancel

      # Referral routes
      get "#{unquote(prefix)}/referrals/stats", ReferralController, :stats
      post "#{unquote(prefix)}/referrals/generate", ReferralController, :generate_code
      get "#{unquote(prefix)}/referrals/code", ReferralController, :get_code
    end
  end

  @doc """
  Defines minimal API routes for basic e-commerce functionality.

  This macro provides a subset of routes for simple stores that don't
  need the full feature set.

  ## Examples

      mercato_basic_routes()
  """
  defmacro mercato_basic_routes(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    controllers = Keyword.get(opts, :controllers)

    product_controller = controller_ast(controllers, :ProductController)
    cart_controller = controller_ast(controllers, :CartController)
    order_controller = controller_ast(controllers, :OrderController)

    quote do
      # Basic product routes
      get "#{unquote(prefix)}/products", unquote(product_controller), :index
      get "#{unquote(prefix)}/products/:id", unquote(product_controller), :show

      # Basic cart routes
      get "#{unquote(prefix)}/carts/:cart_token", unquote(cart_controller), :show
      post "#{unquote(prefix)}/carts", unquote(cart_controller), :create
      post "#{unquote(prefix)}/carts/:cart_token/items", unquote(cart_controller), :add_item
      put "#{unquote(prefix)}/carts/:cart_token/items/:item_id", unquote(cart_controller), :update_item
      delete "#{unquote(prefix)}/carts/:cart_token/items/:item_id", unquote(cart_controller), :remove_item

      # Basic order routes
      get "#{unquote(prefix)}/orders/:id", unquote(order_controller), :show
      post "#{unquote(prefix)}/orders", unquote(order_controller), :create
    end
  end

  @doc """
  Defines admin-only routes for store management.

  These routes typically require admin authentication and authorization.

  ## Examples

      scope "/admin/api", MyAppWeb do
        pipe_through [:api, :admin_required]
        mercato_admin_routes()
      end
  """
  defmacro mercato_admin_routes(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")

    quote do
      # Admin product management
      post "#{unquote(prefix)}/products", ProductController, :create
      put "#{unquote(prefix)}/products/:id", ProductController, :update
      delete "#{unquote(prefix)}/products/:id", ProductController, :delete
      post "#{unquote(prefix)}/products/:product_id/variants", ProductController, :create_variant

      # Admin order management
      put "#{unquote(prefix)}/orders/:id/status", OrderController, :update_status
      post "#{unquote(prefix)}/orders/:id/refund", OrderController, :refund

      # Admin coupon management
      get "#{unquote(prefix)}/coupons", CouponController, :index
      get "#{unquote(prefix)}/coupons/:id", CouponController, :show
      post "#{unquote(prefix)}/coupons", CouponController, :create
      put "#{unquote(prefix)}/coupons/:id", CouponController, :update
      delete "#{unquote(prefix)}/coupons/:id", CouponController, :delete

      # Admin settings management
      get "#{unquote(prefix)}/settings", SettingsController, :index
      put "#{unquote(prefix)}/settings/:key", SettingsController, :update
    end
  end

  @doc """
  Defines referral shortlink routes.

  These routes handle referral code redirects and should typically
  be mounted at the root level of your application.

  ## Examples

      # In your router, at root level (not in a scope)
      mercato_referral_routes()

      # This creates:
      # GET /r/:code -> Mercato.ReferralController.redirect
      # GET /api/referrals/validate/:code -> Mercato.ReferralController.validate
      # GET /api/referrals/stats/:code -> Mercato.ReferralController.stats
  """
  defmacro mercato_referral_routes(opts \\ []) do
    api_prefix = Keyword.get(opts, :api_prefix, "/api")

    quote do
      # Shortlink redirect (should be at root level)
      get "/r/:code", Mercato.ReferralController, :redirect

      # API routes for referral validation and stats
      get "#{unquote(api_prefix)}/referrals/validate/:code", Mercato.ReferralController, :validate
      get "#{unquote(api_prefix)}/referrals/stats/:code", Mercato.ReferralController, :stats
    end
  end

  defp controller_ast(nil, name) when is_atom(name) do
    {:__aliases__, [], [name]}
  end

  defp controller_ast({:__aliases__, meta, segments}, name) when is_list(segments) and is_atom(name) do
    {:__aliases__, meta, segments ++ [name]}
  end

  defp controller_ast(base, name) when is_atom(name) do
    Module.concat(base, name)
  end
end
