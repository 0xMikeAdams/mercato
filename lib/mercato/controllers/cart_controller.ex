if Code.ensure_loaded?(Phoenix.Controller) do
  defmodule Mercato.Controllers.CartController do
    @moduledoc false

    use Phoenix.Controller, namespace: false

    alias Mercato.Cart
    alias Mercato.Controllers.Serializer

    def show(conn, %{"cart_token" => cart_token}) do
      case Cart.get_cart_by_token(cart_token) do
        {:ok, cart} ->
          json(conn, %{data: Serializer.serialize(cart)})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found"})
      end
    end

    def create(conn, params) do
      cart_token = Map.get(params, "cart_token") || generate_cart_token()
      user_id = Map.get(params, "user_id")

      case Cart.create_cart(%{cart_token: cart_token, user_id: user_id}) do
        {:ok, cart} ->
          conn
          |> put_status(:created)
          |> json(%{data: Serializer.serialize(cart)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation_error", details: Serializer.serialize(changeset_errors(changeset))})
      end
    end

    def add_item(conn, %{"cart_token" => cart_token} = params) do
      with {:ok, cart} <- Cart.get_cart_by_token(cart_token),
           {:ok, product_id} <- fetch_param(params, "product_id"),
           {:ok, quantity} <- parse_int(params["quantity"], 1),
           {:ok, cart} <- Cart.add_item(cart.id, product_id, quantity, variant_id: params["variant_id"]) do
        json(conn, %{data: Serializer.serialize(cart)})
      else
        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "unprocessable_entity", reason: inspect(reason)})
      end
    end

    def update_item(conn, %{"cart_token" => cart_token, "item_id" => item_id} = params) do
      with {:ok, cart} <- Cart.get_cart_by_token(cart_token),
           {:ok, quantity} <- parse_int(params["quantity"], nil),
           {:ok, cart} <- Cart.update_item_quantity(cart.id, item_id, quantity) do
        json(conn, %{data: Serializer.serialize(cart)})
      else
        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "unprocessable_entity", reason: inspect(reason)})
      end
    end

    def remove_item(conn, %{"cart_token" => cart_token, "item_id" => item_id}) do
      with {:ok, cart} <- Cart.get_cart_by_token(cart_token),
           {:ok, cart} <- Cart.remove_item(cart.id, item_id) do
        json(conn, %{data: Serializer.serialize(cart)})
      else
        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "unprocessable_entity", reason: inspect(reason)})
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

    defp fetch_param(params, key) do
      case Map.get(params, key) do
        nil -> {:error, {:missing, key}}
        "" -> {:error, {:missing, key}}
        value -> {:ok, value}
      end
    end

    defp changeset_errors(changeset) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {k, v}, acc ->
          String.replace(acc, "%{#{k}}", to_string(v))
        end)
      end)
    end
  end
end

