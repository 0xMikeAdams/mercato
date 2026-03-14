defmodule Mercato.Controllers.CartController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json], namespace: false
  import Mercato.Controllers.Helpers

  alias Mercato.Cart

  def show(conn, %{"cart_token" => cart_token}) do
    case Cart.get_cart_by_token(cart_token) do
      {:ok, cart} ->
        render_data(conn, cart)

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")
    end
  end

  def create(conn, params) do
    cart_token = Map.get(params, "cart_token") || generate_cart_token()
    user_id = Map.get(params, "user_id")

    case Cart.create_cart(%{cart_token: cart_token, user_id: user_id}) do
      {:ok, cart} ->
        render_data(conn, cart, :created)

      {:error, changeset} ->
        render_error(conn, :unprocessable_entity, "validation_error", %{details: changeset_errors(changeset)})
    end
  end

  def add_item(conn, %{"cart_token" => cart_token} = params) do
    with {:ok, cart} <- Cart.get_cart_by_token(cart_token),
         {:ok, product_id} <- fetch_param(params, "product_id"),
         {:ok, quantity} <- parse_int(params["quantity"], 1),
         :ok <- validate_positive_quantity(quantity),
         {:ok, cart} <-
           Cart.add_item(cart.id, product_id, quantity, variant_id: params["variant_id"]) do
      render_data(conn, cart)
    else
      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  def update_item(conn, %{"cart_token" => cart_token, "item_id" => item_id} = params) do
    with {:ok, cart} <- Cart.get_cart_by_token(cart_token),
         {:ok, quantity} <- parse_int(params["quantity"], nil),
         :ok <- validate_positive_quantity(quantity),
         {:ok, cart} <- Cart.update_item_quantity(cart.id, item_id, quantity) do
      render_data(conn, cart)
    else
      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  def remove_item(conn, %{"cart_token" => cart_token, "item_id" => item_id}) do
    with {:ok, cart} <- Cart.get_cart_by_token(cart_token),
         {:ok, cart} <- Cart.remove_item(cart.id, item_id) do
      render_data(conn, cart)
    else
      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  def clear(conn, %{"cart_token" => cart_token}) do
    with {:ok, cart} <- Cart.get_cart_by_token(cart_token),
         {:ok, cart} <- Cart.clear_cart(cart.id) do
      render_data(conn, cart)
    else
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
      {:error, reason} -> render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  def apply_coupon(conn, %{"cart_token" => cart_token} = params) do
    with {:ok, cart} <- Cart.get_cart_by_token(cart_token),
         {:ok, coupon_code} <- fetch_required(params, "coupon_code"),
         {:ok, cart} <- Cart.apply_coupon(cart.id, coupon_code) do
      render_data(conn, cart)
    else
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
      {:error, reason} -> render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  def remove_coupon(conn, %{"cart_token" => cart_token}) do
    with {:ok, cart} <- Cart.get_cart_by_token(cart_token),
         {:ok, cart} <- Cart.remove_coupon(cart.id) do
      render_data(conn, cart)
    else
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
      {:error, reason} -> render_error(conn, :unprocessable_entity, "unprocessable_entity", %{reason: inspect(reason)})
    end
  end

  defp generate_cart_token do
    :crypto.strong_rand_bytes(24)
    |> Base.url_encode64(padding: false)
  end

  defp parse_int(nil, default) when is_integer(default), do: {:ok, default}
  defp parse_int("", default) when is_integer(default), do: {:ok, default}
  defp parse_int(nil, _default), do: {:error, :missing_quantity}
  defp parse_int("", _default), do: {:error, :missing_quantity}

  defp parse_int(value, _default) when is_integer(value), do: {:ok, value}

  defp parse_int(value, _default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp validate_positive_quantity(quantity) when is_integer(quantity) and quantity > 0, do: :ok
  defp validate_positive_quantity(_quantity), do: {:error, :invalid_quantity}

  defp fetch_param(params, key), do: fetch_required(params, key)
end
