if Code.ensure_loaded?(Phoenix.Controller) do
  defmodule Mercato.Controllers.ProductController do
    @moduledoc false

    use Phoenix.Controller, namespace: false

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
      try do
        product = Catalog.get_product!(id, preload: [:variants, :categories, :tags])
        json(conn, %{data: Serializer.serialize(product)})
      rescue
        Ecto.NoResultsError ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found"})
      end
    end

    defp maybe_put(opts, _key, nil), do: opts
    defp maybe_put(opts, _key, ""), do: opts
    defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
  end
end

