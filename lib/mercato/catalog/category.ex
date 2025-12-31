defmodule Mercato.Catalog.Category do
  @moduledoc """
  Schema for product categories.

  Categories provide hierarchical organization for products. Categories can
  have parent categories, allowing for nested category structures.

  ## Fields

  - `name`: Category name
  - `slug`: URL-friendly identifier (unique)
  - `parent_id`: Reference to parent category (optional, for hierarchy)
  - `description`: Category description

  ## Example

      # Root category
      %Category{
        name: "Clothing",
        slug: "clothing",
        parent_id: nil
      }

      # Child category
      %Category{
        name: "T-Shirts",
        slug: "t-shirts",
        parent_id: "123e4567-e89b-12d3-a456-426614174000"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :description, :string

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    many_to_many :products, Mercato.Catalog.Product, join_through: "product_categories"

    timestamps()
  end

  @doc """
  Changeset for creating or updating a category.

  ## Required Fields
  - `name`
  - `slug`

  ## Validations
  - `name`: required, minimum 1 character
  - `slug`: required, unique, URL-safe format
  - `parent_id`: optional, must reference an existing category
  """
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :description, :parent_id])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "must be lowercase alphanumeric with hyphens")
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint(:slug)
  end
end
