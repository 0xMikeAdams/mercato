defmodule Mercato.Controllers.OrderController do
  @moduledoc false

  use Phoenix.Controller, namespace: false

  alias Mercato.Cart
  alias Mercato.Controllers.Serializer
  alias Mercato.Orders

  def show(conn, %{"id" => id}) do
    case Orders.get_order(id) do
      {:ok, order} ->
        json(conn, %{data: Serializer.serialize(order)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})
    end
  end

  def create(conn, params) do
    {cart_lookup, order_attrs} = split_order_params(params)

    with {:ok, cart_id} <- resolve_cart_id(cart_lookup),
         {:ok, order} <- Orders.create_order_from_cart(cart_id, order_attrs) do
      conn
      |> put_status(:created)
      |> json(%{data: Serializer.serialize(order)})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :empty_cart} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "empty_cart"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unprocessable_entity", reason: inspect(reason)})
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
end
