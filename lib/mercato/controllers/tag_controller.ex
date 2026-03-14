defmodule Mercato.Controllers.TagController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json], namespace: false
  import Mercato.Controllers.Helpers

  alias Mercato.Catalog

  def index(conn, _params) do
    render_data(conn, Catalog.list_tags())
  end

  def products(conn, %{"id" => id}) do
    case Catalog.get_tag(id, preload: [products: [:variants, :categories, :tags]]) do
      {:ok, tag} -> render_data(conn, tag.products)
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
    end
  end
end
