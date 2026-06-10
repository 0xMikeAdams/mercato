defmodule Mercato.Controllers.HttpActionsTest do
  @moduledoc """
  HTTP-layer coverage for controller actions the audit flagged as untested:
  order cancel/refund/update_status, customer address CRUD + order history,
  subscription show/pause/resume/cancel, and cart item/coupon mutations.

  Focus is on the authorization guards (ownership / admin) plus a happy path each.
  """
  use Mercato.ConnCase, async: false

  import Plug.Conn

  alias Mercato.{Cart, Catalog, Customers, Orders, Subscriptions}

  # ---- Orders -------------------------------------------------------------

  describe "POST /api/orders/:id/cancel" do
    test "401 without an authenticated user", %{conn: conn} do
      {:ok, order} = order_for(Ecto.UUID.generate())

      conn
      |> post_json("/api/orders/#{order.id}/cancel", %{reason: "changed mind"})
      |> json_response(401)
    end

    test "owner can cancel their order", %{conn: conn} do
      user_id = Ecto.UUID.generate()
      {:ok, order} = order_for(user_id)

      response =
        conn
        |> assign(:current_user, %{id: user_id})
        |> post_json("/api/orders/#{order.id}/cancel", %{reason: "changed mind"})
        |> json_response(200)

      assert response["data"]["status"] == "cancelled"
    end

    test "404 when cancelling another user's order (no ownership leak)", %{conn: conn} do
      {:ok, order} = order_for(Ecto.UUID.generate())

      conn
      |> assign(:current_user, %{id: Ecto.UUID.generate()})
      |> post_json("/api/orders/#{order.id}/cancel", %{reason: "nope"})
      |> json_response(404)
    end
  end

  describe "PUT /api/orders/:id/status and POST /api/orders/:id/refund (admin only)" do
    test "status update is forbidden without admin", %{conn: conn} do
      {:ok, order} = order_for(Ecto.UUID.generate())

      response =
        conn
        |> assign(:current_user, %{id: Ecto.UUID.generate()})
        |> put_json("/api/orders/#{order.id}/status", %{status: "processing"})
        |> json_response(403)

      assert response["error"] == "forbidden"
    end

    test "admin can update status", %{conn: conn} do
      {:ok, order} = order_for(Ecto.UUID.generate())

      response =
        conn
        |> assign(:mercato_admin?, true)
        |> put_json("/api/orders/#{order.id}/status", %{status: "processing"})
        |> json_response(200)

      assert response["data"]["status"] == "processing"
    end

    test "refund is forbidden without admin", %{conn: conn} do
      {:ok, order} = order_for(Ecto.UUID.generate())

      conn
      |> post_json("/api/orders/#{order.id}/refund", %{reason: "x", amount: "1.00"})
      |> json_response(403)
    end
  end

  # ---- Customer addresses -------------------------------------------------

  describe "customer address CRUD" do
    test "create requires auth, then lists and deletes for the owner", %{conn: conn} do
      user_id = Ecto.UUID.generate()
      {:ok, _customer} = customer_for(user_id)
      authed = assign(conn, :current_user, %{id: user_id})

      # unauthenticated create
      conn
      |> post_json("/api/customers/addresses", %{address: address_attrs()})
      |> json_response(401)

      # create
      created =
        authed
        |> post_json("/api/customers/addresses", %{address: address_attrs()})
        |> json_response(201)

      address_id = created["data"]["id"]
      assert created["data"]["customer_id"]

      # list shows it
      listed = authed |> json_conn() |> get("/api/customers/addresses") |> json_response(200)
      assert Enum.any?(listed["data"], &(&1["id"] == address_id))

      # delete (owner) → 204
      assert authed
             |> json_conn()
             |> delete("/api/customers/addresses/#{address_id}")
             |> Map.get(:status) == 204
    end

    test "delete of another user's address is 404", %{conn: conn} do
      owner_id = Ecto.UUID.generate()
      {:ok, customer} = customer_for(owner_id)
      {:ok, address} = Customers.add_address(customer.id, address_attrs())

      conn
      |> assign(:current_user, %{id: Ecto.UUID.generate()})
      |> json_conn()
      |> delete("/api/customers/addresses/#{address.id}")
      |> json_response(404)
    end

    test "GET /api/customers/orders returns the caller's history", %{conn: conn} do
      user_id = Ecto.UUID.generate()
      {:ok, _customer} = customer_for(user_id)
      {:ok, order} = order_for(user_id)

      response =
        conn
        |> assign(:current_user, %{id: user_id})
        |> json_conn()
        |> get("/api/customers/orders")
        |> json_response(200)

      assert Enum.any?(response["data"], &(&1["id"] == order.id))
    end
  end

  # ---- Subscriptions ------------------------------------------------------

  describe "subscription actions" do
    test "show is 404 for another user's subscription", %{conn: conn} do
      {:ok, sub} = subscription_for(Ecto.UUID.generate())

      conn
      |> assign(:current_user, %{id: Ecto.UUID.generate()})
      |> json_conn()
      |> get("/api/subscriptions/#{sub.id}")
      |> json_response(404)
    end

    test "owner can pause and resume", %{conn: conn} do
      user_id = Ecto.UUID.generate()
      {:ok, sub} = subscription_for(user_id)
      authed = assign(conn, :current_user, %{id: user_id})

      paused =
        authed |> post_json("/api/subscriptions/#{sub.id}/pause", %{}) |> json_response(200)

      assert paused["data"]["status"] == "paused"

      resumed =
        authed |> post_json("/api/subscriptions/#{sub.id}/resume", %{}) |> json_response(200)

      assert resumed["data"]["status"] == "active"
    end

    test "pause requires authentication", %{conn: conn} do
      {:ok, sub} = subscription_for(Ecto.UUID.generate())

      conn
      |> post_json("/api/subscriptions/#{sub.id}/pause", %{})
      |> json_response(401)
    end
  end

  # ---- Cart mutations (ownership on user-bound carts) ---------------------

  describe "cart item/coupon mutations honor cart ownership" do
    test "update_item / remove_item / remove_coupon are forbidden on another user's bound cart",
         %{conn: conn} do
      {cart, item} = bound_cart_with_item(Ecto.UUID.generate())
      stranger = assign(conn, :current_user, %{id: Ecto.UUID.generate()})

      stranger
      |> put_json("/api/carts/#{cart.cart_token}/items/#{item.id}", %{quantity: 3})
      |> json_response(403)

      stranger
      |> json_conn()
      |> delete("/api/carts/#{cart.cart_token}/items/#{item.id}")
      |> json_response(403)

      stranger
      |> json_conn()
      |> delete("/api/carts/#{cart.cart_token}/coupons")
      |> json_response(403)
    end

    test "guest can update an item on an unbound cart", %{conn: conn} do
      {cart, item} = bound_cart_with_item(nil)

      response =
        conn
        |> put_json("/api/carts/#{cart.cart_token}/items/#{item.id}", %{quantity: 3})
        |> json_response(200)

      assert response["data"]["id"] == cart.id
    end
  end

  # ---- Fixtures / helpers -------------------------------------------------

  defp product_fixture(attrs \\ %{}) do
    {:ok, product} =
      Catalog.create_product(
        Map.merge(
          %{
            name: "P #{System.unique_integer([:positive])}",
            slug: "p-#{System.unique_integer([:positive])}",
            price: Decimal.new("19.99"),
            sku: "SKU-#{System.unique_integer([:positive])}",
            product_type: "simple",
            stock_quantity: 50
          },
          attrs
        )
      )

    product
  end

  defp order_for(user_id) do
    product = product_fixture()

    {:ok, cart} =
      Cart.create_cart(%{
        cart_token: "act-#{System.unique_integer([:positive])}",
        user_id: user_id
      })

    {:ok, _cart} = Cart.add_item(cart.id, product.id, 1)

    Orders.create_order_from_cart(cart.id, %{
      billing_address: %{
        "line1" => "1 Act St",
        "city" => "Toronto",
        "state" => "ON",
        "postal_code" => "A1A1A1",
        "country" => "CA"
      },
      payment_method: "invoice"
    })
  end

  defp customer_for(user_id) do
    Customers.create_customer(%{
      user_id: user_id,
      email: "u-#{System.unique_integer([:positive])}@example.com",
      first_name: "Test",
      last_name: "User"
    })
  end

  defp subscription_for(user_id) do
    product =
      product_fixture(%{
        product_type: "subscription",
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

  defp bound_cart_with_item(user_id) do
    product = product_fixture()
    token = "cartmut-#{System.unique_integer([:positive])}"
    {:ok, cart} = Cart.create_cart(%{cart_token: token, user_id: user_id})
    {:ok, cart} = Cart.add_item(cart.id, product.id, 1)
    {cart, hd(cart.items)}
  end

  defp address_attrs do
    %{
      address_type: "shipping",
      line1: "1 Addr St",
      city: "Toronto",
      state: "ON",
      postal_code: "A1A1A1",
      country: "CA"
    }
  end

  defp json_conn(conn), do: put_req_header(conn, "accept", "application/json")

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
