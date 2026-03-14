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

        pipeline :api_authenticated do
          plug :accepts, ["json"]
          plug :require_authenticated_user
        end

        pipeline :api_admin do
          plug :accepts, ["json"]
          plug :require_admin_user
        end

        scope "/api/v1", MyAppWeb do
          pipe_through :api

          scope "/mercato", as: false do
            mercato_public_routes()
          end
        end

        scope "/api/v1", MyAppWeb do
          pipe_through :api_authenticated

          scope "/mercato", as: false do
            mercato_customer_routes()
          end
        end

        scope "/api/v1", MyAppWeb do
          pipe_through :api_admin

          scope "/mercato/admin", as: false do
            mercato_admin_routes()
          end
        end

        mercato_referral_routes(api_prefix: "/api/v1/mercato")
      end

  `mercato_api_routes/1` is available as a convenience macro, but production
  integrations should generally prefer the trust-boundary-specific macros above.

  ## Available Routes

  The router helpers are split by trust boundary:

  - `mercato_public_routes/1`
  - `mercato_customer_routes/1`
  - `mercato_admin_routes/1`
  - `mercato_referral_routes/1`

  `mercato_api_routes/1` remains as a convenience wrapper that mounts all
  public, customer, and admin routes.

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

  By default, these helpers mount Mercato's built-in controllers. Host
  applications may override the controller namespace via the `:controllers`
  option.
  """

  @doc """
  Defines all Mercato API routes.

  This macro should be called within a Phoenix router scope to mount
  all Mercato API endpoints. It is most useful for internal tools and
  test routers; host applications should generally prefer the split
  route macros.

  ## Options

  - `:prefix` - Optional path prefix for all routes (default: none)

  ## Examples

      # Mount routes at root level
      mercato_api_routes()

      # Mount routes with prefix
      mercato_api_routes(prefix: "/store")
  """
  defmacro mercato_api_routes(opts \\ []) do
    public_opts = Keyword.put(opts, :include_orders?, true)
    customer_opts = Keyword.put(opts, :include_orders?, true)

    quote do
      mercato_public_routes(unquote(public_opts))
      mercato_customer_routes(unquote(customer_opts))
      mercato_admin_routes(unquote(opts))
    end
  end

  @doc """
  Defines public storefront routes.
  """
  defmacro mercato_public_routes(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    controllers = Keyword.get(opts, :controllers)
    include_orders? = Keyword.get(opts, :include_orders?, true)
    route_opts = [alias: false]

    product_controller = controller_ast(controllers, :ProductController, [:Mercato, :Controllers, :ProductController])
    category_controller = controller_ast(controllers, :CategoryController, [:Mercato, :Controllers, :CategoryController])
    tag_controller = controller_ast(controllers, :TagController, [:Mercato, :Controllers, :TagController])
    cart_controller = controller_ast(controllers, :CartController, [:Mercato, :Controllers, :CartController])
    order_controller = controller_ast(controllers, :OrderController, [:Mercato, :Controllers, :OrderController])

    quote do
      # Product routes
      get "#{unquote(prefix)}/products", unquote(product_controller), :index, unquote(route_opts)
      get "#{unquote(prefix)}/products/:id", unquote(product_controller), :show, unquote(route_opts)

      # Product variant routes
      get "#{unquote(prefix)}/products/:product_id/variants", unquote(product_controller), :list_variants, unquote(route_opts)

      # Category routes
      get "#{unquote(prefix)}/categories", unquote(category_controller), :index, unquote(route_opts)
      get "#{unquote(prefix)}/categories/:id", unquote(category_controller), :show, unquote(route_opts)
      get "#{unquote(prefix)}/categories/:id/products", unquote(category_controller), :products, unquote(route_opts)

      # Tag routes
      get "#{unquote(prefix)}/tags", unquote(tag_controller), :index, unquote(route_opts)
      get "#{unquote(prefix)}/tags/:id/products", unquote(tag_controller), :products, unquote(route_opts)

      # Cart routes
      get "#{unquote(prefix)}/carts/:cart_token", unquote(cart_controller), :show, unquote(route_opts)
      post "#{unquote(prefix)}/carts", unquote(cart_controller), :create, unquote(route_opts)
      post "#{unquote(prefix)}/carts/:cart_token/items", unquote(cart_controller), :add_item, unquote(route_opts)
      put "#{unquote(prefix)}/carts/:cart_token/items/:item_id", unquote(cart_controller), :update_item, unquote(route_opts)
      delete "#{unquote(prefix)}/carts/:cart_token/items/:item_id", unquote(cart_controller), :remove_item, unquote(route_opts)
      delete "#{unquote(prefix)}/carts/:cart_token", unquote(cart_controller), :clear, unquote(route_opts)

      # Cart coupon routes
      post "#{unquote(prefix)}/carts/:cart_token/coupons", unquote(cart_controller), :apply_coupon, unquote(route_opts)
      delete "#{unquote(prefix)}/carts/:cart_token/coupons", unquote(cart_controller), :remove_coupon, unquote(route_opts)

      if unquote(include_orders?) do
        post "#{unquote(prefix)}/orders", unquote(order_controller), :create, unquote(route_opts)
      end
    end
  end

  @doc """
  Defines authenticated customer routes.
  """
  defmacro mercato_customer_routes(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    controllers = Keyword.get(opts, :controllers)
    include_orders? = Keyword.get(opts, :include_orders?, true)
    route_opts = [alias: false]

    order_controller = controller_ast(controllers, :OrderController, [:Mercato, :Controllers, :OrderController])
    customer_controller = controller_ast(controllers, :CustomerController, [:Mercato, :Controllers, :CustomerController])
    subscription_controller = controller_ast(controllers, :SubscriptionController, [:Mercato, :Controllers, :SubscriptionController])
    referral_controller = controller_ast(controllers, :ReferralController, [:Mercato, :ReferralController])

    quote do
      if unquote(include_orders?) do
        get "#{unquote(prefix)}/orders", unquote(order_controller), :index, unquote(route_opts)
        get "#{unquote(prefix)}/orders/:id", unquote(order_controller), :show, unquote(route_opts)
        post "#{unquote(prefix)}/orders/:id/cancel", unquote(order_controller), :cancel, unquote(route_opts)
      end

      # Customer routes
      get "#{unquote(prefix)}/customers/profile", unquote(customer_controller), :show_profile, unquote(route_opts)
      put "#{unquote(prefix)}/customers/profile", unquote(customer_controller), :update_profile, unquote(route_opts)
      get "#{unquote(prefix)}/customers/addresses", unquote(customer_controller), :list_addresses, unquote(route_opts)
      post "#{unquote(prefix)}/customers/addresses", unquote(customer_controller), :create_address, unquote(route_opts)
      put "#{unquote(prefix)}/customers/addresses/:id", unquote(customer_controller), :update_address, unquote(route_opts)
      delete "#{unquote(prefix)}/customers/addresses/:id", unquote(customer_controller), :delete_address, unquote(route_opts)
      get "#{unquote(prefix)}/customers/orders", unquote(customer_controller), :order_history, unquote(route_opts)

      # Subscription routes
      get "#{unquote(prefix)}/subscriptions", unquote(subscription_controller), :index, unquote(route_opts)
      get "#{unquote(prefix)}/subscriptions/:id", unquote(subscription_controller), :show, unquote(route_opts)
      post "#{unquote(prefix)}/subscriptions/:id/pause", unquote(subscription_controller), :pause, unquote(route_opts)
      post "#{unquote(prefix)}/subscriptions/:id/resume", unquote(subscription_controller), :resume, unquote(route_opts)
      post "#{unquote(prefix)}/subscriptions/:id/cancel", unquote(subscription_controller), :cancel, unquote(route_opts)

      # Referral routes
      get "#{unquote(prefix)}/referrals/stats", unquote(referral_controller), :stats, unquote(route_opts)
      post "#{unquote(prefix)}/referrals/generate", unquote(referral_controller), :generate_code, unquote(route_opts)
      get "#{unquote(prefix)}/referrals/code", unquote(referral_controller), :get_code, unquote(route_opts)
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
    route_opts = [alias: false]

    product_controller = controller_ast(controllers, :ProductController, [:Mercato, :Controllers, :ProductController])
    cart_controller = controller_ast(controllers, :CartController, [:Mercato, :Controllers, :CartController])
    order_controller = controller_ast(controllers, :OrderController, [:Mercato, :Controllers, :OrderController])

    quote do
      # Basic product routes
      get "#{unquote(prefix)}/products", unquote(product_controller), :index, unquote(route_opts)
      get "#{unquote(prefix)}/products/:id", unquote(product_controller), :show, unquote(route_opts)

      # Basic cart routes
      get "#{unquote(prefix)}/carts/:cart_token", unquote(cart_controller), :show, unquote(route_opts)
      post "#{unquote(prefix)}/carts", unquote(cart_controller), :create, unquote(route_opts)
      post "#{unquote(prefix)}/carts/:cart_token/items", unquote(cart_controller), :add_item, unquote(route_opts)
      put "#{unquote(prefix)}/carts/:cart_token/items/:item_id", unquote(cart_controller), :update_item, unquote(route_opts)
      delete "#{unquote(prefix)}/carts/:cart_token/items/:item_id", unquote(cart_controller), :remove_item, unquote(route_opts)

      # Basic order routes
      get "#{unquote(prefix)}/orders/:id", unquote(order_controller), :show, unquote(route_opts)
      post "#{unquote(prefix)}/orders", unquote(order_controller), :create, unquote(route_opts)
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
    controllers = Keyword.get(opts, :controllers)
    route_opts = [alias: false]

    product_controller = controller_ast(controllers, :ProductController, [:Mercato, :Controllers, :ProductController])
    order_controller = controller_ast(controllers, :OrderController, [:Mercato, :Controllers, :OrderController])

    quote do
      # Admin product management
      post "#{unquote(prefix)}/products", unquote(product_controller), :create, unquote(route_opts)
      put "#{unquote(prefix)}/products/:id", unquote(product_controller), :update, unquote(route_opts)
      delete "#{unquote(prefix)}/products/:id", unquote(product_controller), :delete, unquote(route_opts)
      post "#{unquote(prefix)}/products/:product_id/variants", unquote(product_controller), :create_variant, unquote(route_opts)

      # Admin order management
      put "#{unquote(prefix)}/orders/:id/status", unquote(order_controller), :update_status, unquote(route_opts)
      post "#{unquote(prefix)}/orders/:id/refund", unquote(order_controller), :refund, unquote(route_opts)
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
    controllers = Keyword.get(opts, :controllers)
    route_opts = [alias: false]
    referral_controller = controller_ast(controllers, :ReferralController, [:Mercato, :ReferralController])

    quote do
      # Shortlink redirect (should be at root level)
      get "/r/:code", unquote(referral_controller), :redirect, unquote(route_opts)

      # API routes for referral validation and stats
      get "#{unquote(api_prefix)}/referrals/validate/:code", unquote(referral_controller), :validate, unquote(route_opts)
      get "#{unquote(api_prefix)}/referrals/stats/:code", unquote(referral_controller), :stats, unquote(route_opts)
    end
  end

  defp controller_ast(nil, _name, default_segments) when is_list(default_segments) do
    Module.concat(default_segments)
  end

  defp controller_ast({:__aliases__, meta, segments}, name, _default_segments) when is_list(segments) and is_atom(name) do
    _ = meta
    Module.concat(segments ++ [name])
  end

  defp controller_ast(base, name, _default_segments) when is_atom(name) do
    Module.concat(base, name)
  end
end
