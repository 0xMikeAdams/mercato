defmodule Mercato.Controllers.CategoryController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json], namespace: false
  import Mercato.Controllers.Helpers

  alias Mercato.Catalog

  def index(conn, _params) do
    render_data(conn, Catalog.list_categories(preload: [:children]))
  end

  def show(conn, %{"id" => id}) do
    case Catalog.get_category(id, preload: [:children, :parent]) do
      {:ok, category} -> render_data(conn, category)
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
    end
  end

  def products(conn, %{"id" => id}) do
    case Catalog.get_category(id, preload: [products: [:variants, :categories, :tags]]) do
      {:ok, category} -> render_data(conn, category.products)
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
    end
  end
end
