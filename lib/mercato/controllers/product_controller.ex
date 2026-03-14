defmodule Mercato.Controllers.ProductController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json], namespace: false
  import Mercato.Controllers.Helpers

  alias Mercato.Catalog

  def index(conn, params) do
    opts =
      []
      |> maybe_put(:status, params["status"])
      |> maybe_put(:product_type, params["product_type"])

    products = Catalog.list_products(opts)
    render_data(conn, products)
  end

  def show(conn, %{"id" => id}) do
    case Catalog.get_product(id, preload: [:variants, :categories, :tags]) do
      {:ok, product} ->
        render_data(conn, product)

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")
    end
  end

  def create(conn, %{"product" => attrs}), do: create(conn, attrs)

  def create(conn, attrs) when is_map(attrs) do
    with :ok <- ensure_admin(conn),
         {:ok, product} <- Catalog.create_product(attrs) do
      render_data(conn, product, :created)
    else
      {:error, :forbidden} ->
        render_error(conn, :forbidden, "forbidden")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, :unprocessable_entity, "validation_error", %{details: changeset_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "product" => attrs}), do: update(conn, %{"id" => id} |> Map.merge(attrs))

  def update(conn, %{"id" => id} = attrs) do
    with :ok <- ensure_admin(conn),
         {:ok, product} <- Catalog.get_product(id),
         {:ok, updated_product} <- Catalog.update_product(product, Map.delete(attrs, "id")) do
      render_data(conn, updated_product)
    else
      {:error, :forbidden} ->
        render_error(conn, :forbidden, "forbidden")

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, :unprocessable_entity, "validation_error", %{details: changeset_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- ensure_admin(conn),
         {:ok, product} <- Catalog.get_product(id),
         {:ok, _product} <- Catalog.delete_product(product) do
      Plug.Conn.send_resp(conn, :no_content, "")
    else
      {:error, :forbidden} ->
        render_error(conn, :forbidden, "forbidden")

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, :unprocessable_entity, "validation_error", %{details: changeset_errors(changeset)})
    end
  end

  def list_variants(conn, %{"product_id" => product_id}) do
    with {:ok, _product} <- Catalog.get_product(product_id) do
      render_data(conn, Catalog.list_variants(product_id))
    else
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
    end
  end

  def create_variant(conn, %{"product_id" => product_id, "variant" => attrs}), do: create_variant(conn, %{"product_id" => product_id} |> Map.merge(attrs))

  def create_variant(conn, %{"product_id" => product_id} = attrs) do
    with :ok <- ensure_admin(conn),
         {:ok, _product} <- Catalog.get_product(product_id),
         {:ok, variant} <- Catalog.create_variant(product_id, Map.delete(attrs, "product_id")) do
      render_data(conn, variant, :created)
    else
      {:error, :forbidden} ->
        render_error(conn, :forbidden, "forbidden")

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, :unprocessable_entity, "validation_error", %{details: changeset_errors(changeset)})
    end
  end
end
