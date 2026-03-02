defmodule Mercato.Controllers.ProductController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json], namespace: false

  alias Mercato.Catalog
  alias Mercato.Controllers.Serializer

  def index(conn, params) do
    opts =
      []
      |> maybe_put(:status, params["status"])
      |> maybe_put(:product_type, params["product_type"])

    products = Catalog.list_products(opts)
    json(conn, %{data: Serializer.serialize(products)})
  end

  def show(conn, %{"id" => id}) do
    case Catalog.get_product(id, preload: [:variants, :categories, :tags]) do
      {:ok, product} ->
        json(conn, %{data: Serializer.serialize(product)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
