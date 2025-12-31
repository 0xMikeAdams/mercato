defmodule Mercato.Catalog.ProductVariant do
  @moduledoc """
  Schema for product variants.

  Product variants represent different variations of a variable product,
  such as different sizes, colors, or other attributes. Each variant can
  have its own SKU, price, and stock quantity.

  ## Fields

  - `product_id`: Reference to the parent product
  - `sku`: Unique Stock Keeping Unit identifier for this variant
  - `price`: Variant-specific price (Decimal)
  - `sale_price`: Discounted price when on sale (Decimal, optional)
  - `stock_quantity`: Current stock level for this variant
  - `attributes`: JSONB map of variant attributes (e.g., %{"size" => "L", "color" => "blue"})

  ## Example

      %ProductVariant{
        product_id: "123e4567-e89b-12d3-a456-426614174000",
        sku: "TSHIRT-L-BLUE",
        price: Decimal.new("29.99"),
        stock_quantity: 50,
        attributes: %{"size" => "L", "color" => "blue"}
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "product_variants" do
    field :sku, :string
    field :price, :decimal
    field :sale_price, :decimal
    field :stock_quantity, :integer, default: 0
    field :attributes, :map, default: %{}

    belongs_to :product, Mercato.Catalog.Product

    timestamps()
  end

  @doc """
  Changeset for creating or updating a product variant.

  ## Required Fields
  - `product_id`
  - `sku`
  - `price`

  ## Validations
  - `sku`: required, unique
  - `price`: required, must be >= 0
  - `sale_price`: optional, must be >= 0 and < price if present
  - `stock_quantity`: must be >= 0
  - `attributes`: must be a map
  """
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, [:product_id, :sku, :price, :sale_price, :stock_quantity, :attributes])
    |> validate_required([:product_id, :sku, :price])
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:sale_price, greater_than_or_equal_to: 0)
    |> validate_number(:stock_quantity, greater_than_or_equal_to: 0)
    |> validate_sale_price()
    |> foreign_key_constraint(:product_id)
    |> unique_constraint(:sku)
  end

  # Validates that sale_price is less than price if present
  defp validate_sale_price(changeset) do
    price = get_field(changeset, :price)
    sale_price = get_field(changeset, :sale_price)

    if price && sale_price && Decimal.compare(sale_price, price) != :lt do
      add_error(changeset, :sale_price, "must be less than price")
    else
      changeset
    end
  end
end
