defmodule Mercato.Catalog.Tag do
  @moduledoc """
  Schema for product tags.

  Tags provide a flexible way to classify and filter products. Unlike categories,
  tags are flat (non-hierarchical) and products can have multiple tags.

  ## Fields

  - `name`: Tag name
  - `slug`: URL-friendly identifier (unique)

  ## Example

      %Tag{
        name: "Summer Collection",
        slug: "summer-collection"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tags" do
    field :name, :string
    field :slug, :string

    many_to_many :products, Mercato.Catalog.Product, join_through: "product_tags"

    timestamps()
  end

  @doc """
  Changeset for creating or updating a tag.

  ## Required Fields
  - `name`
  - `slug`

  ## Validations
  - `name`: required, minimum 1 character
  - `slug`: required, unique, URL-safe format
  """
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "must be lowercase alphanumeric with hyphens")
    |> unique_constraint(:slug)
  end
end
