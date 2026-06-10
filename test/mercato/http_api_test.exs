defmodule Mercato.HttpApiTest do
  use Mercato.ConnCase, async: false

  import Plug.Conn

  alias Mercato.{Cart, Catalog, Customers, Orders, Referrals, Subscriptions}

  describe "router macros" do
    test "mount all public, customer, admin, and referral routes" do
      expected_routes = [
        {"GET", "/api/products", Mercato.Controllers.ProductController, :index},
        {"GET", "/api/products/product-id", Mercato.Controllers.ProductController, :show},
        {"GET", "/api/products/product-id/variants", Mercato.Controllers.ProductController, :list_variants},
        {"GET", "/api/categories", Mercato.Controllers.CategoryController, :index},
        {"GET", "/api/categories/category-id", Mercato.Controllers.CategoryController, :show},
        {"GET", "/api/categories/category-id/products", Mercato.Controllers.CategoryController, :products},
        {"GET", "/api/tags", Mercato.Controllers.TagController, :index},
        {"GET", "/api/tags/tag-id/products", Mercato.Controllers.TagController, :products},
        {"GET", "/api/carts/cart-token", Mercato.Controllers.CartController, :show},
        {"POST", "/api/carts", Mercato.Controllers.CartController, :create},
        {"POST", "/api/carts/cart-token/items", Mercato.Controllers.CartController, :add_item},
        {"PUT", "/api/carts/cart-token/items/item-id", Mercato.Controllers.CartController, :update_item},
        {"DELETE", "/api/carts/cart-token/items/item-id", Mercato.Controllers.CartController, :remove_item},
        {"DELETE", "/api/carts/cart-token", Mercato.Controllers.CartController, :clear},
        {"POST", "/api/carts/cart-token/coupons", Mercato.Controllers.CartController, :apply_coupon},
        {"DELETE", "/api/carts/cart-token/coupons", Mercato.Controllers.CartController, :remove_coupon},
        {"POST", "/api/orders", Mercato.Controllers.OrderController, :create},
        {"GET", "/api/orders", Mercato.Controllers.OrderController, :index},
        {"GET", "/api/orders/order-id", Mercato.Controllers.OrderController, :show},
        {"POST", "/api/orders/order-id/cancel", Mercato.Controllers.OrderController, :cancel},
        {"PUT", "/api/orders/order-id/status", Mercato.Controllers.OrderController, :update_status},
        {"POST", "/api/orders/order-id/refund", Mercato.Controllers.OrderController, :refund},
        {"GET", "/api/customers/profile", Mercato.Controllers.CustomerController, :show_profile},
        {"PUT", "/api/customers/profile", Mercato.Controllers.CustomerController, :update_profile},
        {"GET", "/api/customers/addresses", Mercato.Controllers.CustomerController, :list_addresses},
        {"POST", "/api/customers/addresses", Mercato.Controllers.CustomerController, :create_address},
        {"PUT", "/api/customers/addresses/address-id", Mercato.Controllers.CustomerController, :update_address},
        {"DELETE", "/api/customers/addresses/address-id", Mercato.Controllers.CustomerController, :delete_address},
        {"GET", "/api/customers/orders", Mercato.Controllers.CustomerController, :order_history},
        {"GET", "/api/subscriptions", Mercato.Controllers.SubscriptionController, :index},
        {"GET", "/api/subscriptions/subscription-id", Mercato.Controllers.SubscriptionController, :show},
        {"POST", "/api/subscriptions/subscription-id/pause", Mercato.Controllers.SubscriptionController, :pause},
        {"POST", "/api/subscriptions/subscription-id/resume", Mercato.Controllers.SubscriptionController, :resume},
        {"POST", "/api/subscriptions/subscription-id/cancel", Mercato.Controllers.SubscriptionController, :cancel},
        {"GET", "/api/referrals/stats", Mercato.ReferralController, :stats},
        {"POST", "/api/referrals/generate", Mercato.ReferralController, :generate_code},
        {"GET", "/api/referrals/code", Mercato.ReferralController, :get_code},
        {"GET", "/api/referrals/validate/code123", Mercato.ReferralController, :validate},
        {"GET", "/api/referrals/stats/code123", Mercato.ReferralController, :stats},
        {"GET", "/r/code123", Mercato.ReferralController, :redirect}
      ]

      Enum.each(expected_routes, fn {method, path, controller, action} ->
        assert %{plug: ^controller, plug_opts: ^action} =
                 Phoenix.Router.route_info(Mercato.TestRouter, method, path, "example.com")
      end)
    end
  end

  describe "public routes" do
    test "GET /api/products returns serialized products", %{conn: conn} do
      {:ok, product} =
        Catalog.create_product(%{
          name: "HTTP Product",
          slug: "http-product-#{System.unique_integer([:positive])}",
          price: Decimal.new("25.00"),
          sku: "HTTP-#{System.unique_integer([:positive])}",
          product_type: "simple",
          status: "published",
          stock_quantity: 10
        })

      response =
        conn
        |> json_conn()
        |> get("/api/products")
        |> json_response(200)

      assert Enum.any?(response["data"], &(&1["id"] == product.id))
    end
  end

  describe "customer routes" do
    test "GET /api/orders returns 401 without current_user", %{conn: conn} do
      response =
        conn
        |> json_conn()
        |> get("/api/orders")
        |> json_response(401)

      assert response["error"] == "unauthorized"
    end

    test "GET /api/orders lists only the current user's orders", %{conn: conn} do
      user_id = Ecto.UUID.generate()
      other_user_id = Ecto.UUID.generate()

      {:ok, order} = create_order_for_user(user_id)
      {:ok, _other_order} = create_order_for_user(other_user_id)

      response =
        conn
        |> assign(:current_user, %{id: user_id})
        |> json_conn()
        |> get("/api/orders")
        |> json_response(200)

      assert Enum.map(response["data"], & &1["id"]) == [order.id]
    end

    test "PUT /api/customers/profile creates a profile for the current user", %{conn: conn} do
      user_id = Ecto.UUID.generate()

      response =
        conn
        |> assign(:current_user, %{id: user_id})
        |> put_json("/api/customers/profile", %{
          customer: %{
            email: "buyer@example.com",
            first_name: "Buyer",
            last_name: "Person"
          }
        })
        |> json_response(201)

      assert response["data"]["user_id"] == user_id

      assert {:ok, customer} = Customers.get_customer(user_id)
      assert customer.email == "buyer@example.com"
    end

    test "GET /api/subscriptions returns 401 without current_user", %{conn: conn} do
      response =
        conn
        |> json_conn()
        |> get("/api/subscriptions")
        |> json_response(401)

      assert response["error"] == "unauthorized"
    end

    test "GET /api/subscriptions returns the current user's subscriptions", %{conn: conn} do
      user_id = Ecto.UUID.generate()
      other_user_id = Ecto.UUID.generate()

      {:ok, subscription} = create_subscription_for_user(user_id)
      {:ok, _other_subscription} = create_subscription_for_user(other_user_id)

      response =
        conn
        |> assign(:current_user, %{id: user_id})
        |> json_conn()
        |> get("/api/subscriptions")
        |> json_response(200)

      assert Enum.map(response["data"], & &1["id"]) == [subscription.id]
    end
  end

  describe "admin routes" do
    test "POST /api/products returns 403 without admin authorization", %{conn: conn} do
      response =
        conn
        |> post_json("/api/products", %{
          product: %{
            name: "Forbidden Product",
            slug: "forbidden-product",
            price: "20.00",
            sku: "FORBIDDEN-1",
            product_type: "simple"
          }
        })
        |> json_response(403)

      assert response["error"] == "forbidden"
    end

    test "POST /api/products creates a product for admin requests", %{conn: conn} do
      response =
        conn
        |> assign(:mercato_admin?, true)
        |> post_json("/api/products", %{
          product: %{
            name: "Admin Product",
            slug: "admin-product-#{System.unique_integer([:positive])}",
            price: "20.00",
            sku: "ADMIN-#{System.unique_integer([:positive])}",
            product_type: "simple",
            stock_quantity: 5
          }
        })
        |> json_response(201)

      assert response["data"]["name"] == "Admin Product"
    end
  end

  describe "referral routes" do
    test "POST /api/referrals/generate returns 401 without current_user", %{conn: conn} do
      response =
        conn
        |> post_json("/api/referrals/generate", %{
          referral_code: %{
            commission_type: "percentage",
            commission_value: "5"
          }
        })
        |> json_response(401)

      assert response["error"] == "unauthorized"
    end

    test "POST /api/referrals/generate creates a referral code for the current user", %{conn: conn} do
      user_id = Ecto.UUID.generate()

      response =
        conn
        |> assign(:current_user, %{id: user_id})
        |> post_json("/api/referrals/generate", %{
          referral_code: %{
            commission_type: "percentage",
            commission_value: "5"
          }
        })
        |> json_response(201)

      assert response["data"]["user_id"] == user_id

      assert {:ok, referral_code} = Referrals.get_referral_code_by_user(user_id)
      assert referral_code.id == response["data"]["id"]
    end

    test "POST /api/referrals/generate ignores caller-supplied commission terms", %{conn: conn} do
      user_id = Ecto.UUID.generate()

      conn
      |> assign(:current_user, %{id: user_id})
      |> post_json("/api/referrals/generate", %{
        referral_code: %{commission_type: "fixed", commission_value: "100"}
      })
      |> json_response(201)

      {:ok, referral_code} = Referrals.get_referral_code_by_user(user_id)
      # Server policy (default 5% percentage) wins over the malicious request.
      assert referral_code.commission_type == "percentage"
      assert Decimal.equal?(referral_code.commission_value, Decimal.new("5"))
    end

    test "GET /api/referrals/validate/:code does not disclose referrer or commission", %{
      conn: conn
    } do
      {:ok, code} = Referrals.generate_referral_code(Ecto.UUID.generate())

      response =
        conn
        |> json_conn()
        |> get("/api/referrals/validate/#{code.code}")
        |> json_response(200)

      assert response["valid"] == true
      assert response["code"] == code.code
      refute Map.has_key?(response, "referrer_id")
      refute Map.has_key?(response, "commission_type")
      refute Map.has_key?(response, "commission_value")
    end

    test "GET /api/referrals/stats/:code requires authentication (no public disclosure)", %{
      conn: conn
    } do
      {:ok, code} = Referrals.generate_referral_code(Ecto.UUID.generate())

      response =
        conn
        |> json_conn()
        |> get("/api/referrals/stats/#{code.code}")
        |> json_response(401)

      assert response["error"] == "unauthorized"
    end
  end

  describe "cart authorization" do
    test "POST /api/carts ignores a client-supplied user_id", %{conn: conn} do
      response =
        conn
        |> post_json("/api/carts", %{user_id: Ecto.UUID.generate()})
        |> json_response(201)

      # No authenticated session → guest cart, never attributed to the spoofed id.
      assert response["data"]["user_id"] == nil
    end

    test "POST /api/carts binds the cart to the authenticated user", %{conn: conn} do
      user_id = Ecto.UUID.generate()

      response =
        conn
        |> assign(:current_user, %{id: user_id})
        |> post_json("/api/carts", %{user_id: Ecto.UUID.generate()})
        |> json_response(201)

      assert response["data"]["user_id"] == user_id
    end

    test "GET /api/carts/:token forbids access to another user's bound cart", %{conn: conn} do
      owner_id = Ecto.UUID.generate()
      token = "owned-cart-#{System.unique_integer([:positive])}"
      {:ok, _cart} = Cart.create_cart(%{cart_token: token, user_id: owner_id})

      # No session → cannot read a user-bound cart even with the token.
      response =
        conn
        |> json_conn()
        |> get("/api/carts/#{token}")
        |> json_response(403)

      assert response["error"] == "forbidden"

      # A different authenticated user is also forbidden.
      response =
        conn
        |> assign(:current_user, %{id: Ecto.UUID.generate()})
        |> json_conn()
        |> get("/api/carts/#{token}")
        |> json_response(403)

      assert response["error"] == "forbidden"
    end

    test "GET /api/carts/:token allows the owner to read their bound cart", %{conn: conn} do
      owner_id = Ecto.UUID.generate()
      token = "owner-read-cart-#{System.unique_integer([:positive])}"
      {:ok, _cart} = Cart.create_cart(%{cart_token: token, user_id: owner_id})

      response =
        conn
        |> assign(:current_user, %{id: owner_id})
        |> json_conn()
        |> get("/api/carts/#{token}")
        |> json_response(200)

      assert response["data"]["user_id"] == owner_id
    end

    test "GET /api/carts/:token allows guest access to an unbound cart", %{conn: conn} do
      token = "guest-cart-#{System.unique_integer([:positive])}"
      {:ok, _cart} = Cart.create_cart(%{cart_token: token})

      response =
        conn
        |> json_conn()
        |> get("/api/carts/#{token}")
        |> json_response(200)

      assert response["data"]["user_id"] == nil
    end
  end

  describe "order creation authorization" do
    test "POST /api/orders forbids checkout of another user's bound cart", %{conn: conn} do
      cart = seeded_cart(user_id: Ecto.UUID.generate())

      # No session → forbidden even with the token.
      conn
      |> post_json("/api/orders", order_body(%{cart_token: cart.cart_token}))
      |> json_response(403)

      # A different authenticated user → forbidden.
      response =
        conn
        |> assign(:current_user, %{id: Ecto.UUID.generate()})
        |> post_json("/api/orders", order_body(%{cart_token: cart.cart_token}))
        |> json_response(403)

      assert response["error"] == "forbidden"
    end

    test "POST /api/orders forbids checkout of a bound cart via raw cart_id", %{conn: conn} do
      cart = seeded_cart(user_id: Ecto.UUID.generate())

      response =
        conn
        |> post_json("/api/orders", order_body(%{cart_id: cart.id}))
        |> json_response(403)

      assert response["error"] == "forbidden"
    end

    test "POST /api/orders allows the owner to check out their bound cart", %{conn: conn} do
      owner_id = Ecto.UUID.generate()
      cart = seeded_cart(user_id: owner_id)

      response =
        conn
        |> assign(:current_user, %{id: owner_id})
        |> post_json("/api/orders", order_body(%{cart_token: cart.cart_token}))
        |> json_response(201)

      assert response["data"]["user_id"] == owner_id
    end

    test "POST /api/orders allows guest checkout of an unbound cart", %{conn: conn} do
      cart = seeded_cart([])

      response =
        conn
        |> post_json("/api/orders", order_body(%{cart_token: cart.cart_token}))
        |> json_response(201)

      assert response["data"]["user_id"] == nil
    end
  end

  describe "address update authorization" do
    test "PUT /api/customers/addresses/:id cannot re-parent the address to another customer", %{
      conn: conn
    } do
      owner_id = Ecto.UUID.generate()

      {:ok, customer} =
        Customers.create_customer(%{
          user_id: owner_id,
          email: "owner-#{System.unique_integer([:positive])}@example.com",
          first_name: "Owner",
          last_name: "Person"
        })

      {:ok, address} =
        Customers.add_address(customer.id, %{
          address_type: "shipping",
          line1: "1 Owner St",
          city: "Toronto",
          state: "ON",
          postal_code: "A1A1A1",
          country: "CA"
        })

      victim_customer_id = Ecto.UUID.generate()

      response =
        conn
        |> assign(:current_user, %{id: owner_id})
        |> put_json("/api/customers/addresses/#{address.id}", %{
          address: %{customer_id: victim_customer_id, line1: "2 New St"}
        })
        |> json_response(200)

      # The legitimate field update applies, but customer_id is NOT re-parented.
      assert response["data"]["line1"] == "2 New St"
      assert response["data"]["customer_id"] == customer.id
      refute response["data"]["customer_id"] == victim_customer_id
    end
  end

  defp seeded_cart(cart_attrs) do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Order Auth Product #{System.unique_integer([:positive])}",
        slug: "order-auth-#{System.unique_integer([:positive])}",
        price: Decimal.new("19.99"),
        sku: "ORDAUTH-#{System.unique_integer([:positive])}",
        product_type: "simple",
        stock_quantity: 20
      })

    cart_attrs =
      %{cart_token: "order-auth-cart-#{System.unique_integer([:positive])}"}
      |> Map.merge(Map.new(cart_attrs))

    {:ok, cart} = Cart.create_cart(cart_attrs)
    {:ok, _cart} = Cart.add_item(cart.id, product.id, 1)
    cart
  end

  defp order_body(cart_lookup) do
    Map.merge(
      %{
        billing_address: %{
          "line1" => "1 Order St",
          "city" => "Toronto",
          "state" => "ON",
          "postal_code" => "A1A1A1",
          "country" => "CA"
        },
        payment_method: "invoice"
      },
      cart_lookup
    )
  end

  defp create_order_for_user(user_id) do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Order Product #{System.unique_integer([:positive])}",
        slug: "order-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("19.99"),
        sku: "ORDER-#{System.unique_integer([:positive])}",
        product_type: "simple",
        stock_quantity: 20
      })

    {:ok, cart} =
      Cart.create_cart(%{
        cart_token: "http-order-cart-#{System.unique_integer([:positive])}",
        user_id: user_id
      })

    {:ok, _cart} = Cart.add_item(cart.id, product.id, 1)

    Orders.create_order_from_cart(cart.id, %{
      billing_address: %{
        "line1" => "123 Order St",
        "city" => "Toronto",
        "state" => "ON",
        "postal_code" => "A1A1A1",
        "country" => "CA"
      },
      payment_method: "invoice"
    })
  end

  defp create_subscription_for_user(user_id) do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Subscription Product #{System.unique_integer([:positive])}",
        slug: "http-subscription-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("29.99"),
        sku: "HTTPSUB-#{System.unique_integer([:positive])}",
        product_type: "subscription",
        stock_quantity: 20,
        subscription_settings: %{"billing_cycle" => "monthly"}
      })

    Subscriptions.create_subscription(%{
      user_id: user_id,
      product_id: product.id,
      billing_cycle: "monthly",
      start_date: Date.utc_today(),
      billing_amount: Decimal.new("29.99")
    })
  end

  defp json_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
  end

  defp post_json(conn, path, payload) do
    conn
    |> json_conn()
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end

  defp put_json(conn, path, payload) do
    conn
    |> json_conn()
    |> put_req_header("content-type", "application/json")
    |> put(path, Jason.encode!(payload))
  end
end
