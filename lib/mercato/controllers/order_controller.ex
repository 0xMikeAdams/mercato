defmodule Mercato.Controllers.OrderController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json], namespace: false
  import Mercato.Controllers.Helpers

  alias Mercato.Cart
  alias Mercato.Orders

  def index(conn, _params) do
    with {:ok, user_id} <- current_user_id(conn) do
      render_data(conn, Orders.list_orders(user_id: user_id))
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, order} <- fetch_customer_order(id, user_id) do
      render_data(conn, order)
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
    end
  end

  def create(conn, params) do
    {cart_lookup, order_attrs} = split_order_params(params)
    order_attrs = merge_idempotency_key(order_attrs, conn)

    with {:ok, cart_id} <- resolve_cart_id(cart_lookup),
         {:ok, order} <- Orders.create_order_from_cart(cart_id, order_attrs) do
      render_data(conn, order, :created)
    else
      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, :empty_cart} ->
        render_error(conn, :unprocessable_entity, "empty_cart")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  def update_status(conn, %{"id" => id} = params) do
    with :ok <- ensure_admin(conn),
         {:ok, status} <- fetch_required(params, "status"),
         {:ok, order} <- Orders.update_status(id, status, changed_by: admin_actor(conn), notes: Map.get(params, "notes")) do
      render_data(conn, order)
    else
      {:error, :forbidden} -> render_error(conn, :forbidden, "forbidden")
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
      {:error, %Ecto.Changeset{} = changeset} -> render_error(conn, :unprocessable_entity, "validation_error", %{details: changeset_errors(changeset)})
      {:error, reason} -> render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  def cancel(conn, %{"id" => id} = params) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, _order} <- fetch_customer_order(id, user_id),
         {:ok, reason} <- fetch_required(params, "reason"),
         {:ok, order} <- Orders.cancel_order(id, reason, changed_by: user_id) do
      render_data(conn, order)
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
      {:error, reason} -> render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  def refund(conn, %{"id" => id} = params) do
    with :ok <- ensure_admin(conn),
         {:ok, reason} <- fetch_required(params, "reason"),
         {:ok, amount} <- parse_decimal(Map.get(params, "amount")),
         {:ok, order} <- Orders.refund_order(id, amount, reason, changed_by: admin_actor(conn)) do
      render_data(conn, order)
    else
      {:error, :forbidden} -> render_error(conn, :forbidden, "forbidden")
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
      {:error, :missing_decimal} -> render_error(conn, :unprocessable_entity, "validation_error", %{reason: "missing amount"})
      {:error, :invalid_decimal} -> render_error(conn, :unprocessable_entity, "validation_error", %{reason: "invalid amount"})
      {:error, reason} -> render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  defp split_order_params(%{"order" => order_attrs} = params) when is_map(order_attrs) do
    {params, order_attrs}
  end

  defp split_order_params(params) when is_map(params) do
    {params, params}
  end

  defp resolve_cart_id(%{"cart_id" => cart_id}), do: {:ok, cart_id}

  defp resolve_cart_id(%{"cart_token" => cart_token}) do
    case Cart.get_cart_by_token(cart_token) do
      {:ok, cart} -> {:ok, cart.id}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp resolve_cart_id(_), do: {:error, {:missing, "cart_id or cart_token"}}

  defp merge_idempotency_key(order_attrs, conn) when is_map(order_attrs) do
    case extract_idempotency_key(order_attrs, conn) do
      nil -> order_attrs
      idempotency_key -> Map.put(order_attrs, "idempotency_key", idempotency_key)
    end
  end

  defp extract_idempotency_key(order_attrs, conn) do
    param_key = Map.get(order_attrs, "idempotency_key") || Map.get(order_attrs, :idempotency_key)

    header_key =
      conn
      |> Plug.Conn.get_req_header("idempotency-key")
      |> List.first()

    normalize_idempotency_key(param_key || header_key)
  end

  defp normalize_idempotency_key(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_idempotency_key(_value), do: nil

  defp fetch_customer_order(order_id, user_id) do
    case Orders.get_order(order_id) do
      {:ok, %{user_id: ^user_id} = order} -> {:ok, order}
      {:ok, _order} -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp admin_actor(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      %{"id" => id} -> id
      id when is_binary(id) -> id
      _ -> nil
    end
  end
end
