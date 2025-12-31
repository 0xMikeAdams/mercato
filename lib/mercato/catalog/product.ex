defmodule Mercato.Catalog.Product do
  @moduledoc """
  Schema for products in the catalog.

  Products can be of different types:
  - `simple`: Standard physical or digital product
  - `variable`: Product with variants (e.g., different sizes/colors)
  - `downloadable`: Digital product available for download
  - `virtual`: Non-physical product (e.g., service, warranty)
  - `subscription`: Product with recurring billing

  ## Fields

  - `name`: Product name
  - `slug`: URL-friendly identifier (unique)
  - `description`: Full product description
  - `images`: Array of image URLs stored as JSONB
  - `price`: Base price (Decimal)
  - `sale_price`: Discounted price when on sale (Decimal, optional)
  - `sku`: Stock Keeping Unit identifier (unique)
  - `stock_quantity`: Current stock level
  - `manage_stock`: Whether to track inventory for this product
  - `backorders`: Backorder policy ("no", "notify", "allow")
  - `status`: Publication status ("draft", "published", "archived")
  - `product_type`: Type of product (see above)
  - `subscription_settings`: JSONB map with billing_cycle, trial_period_days, subscription_length
  - `meta_title`: SEO title
  - `meta_description`: SEO description
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @product_types ~w(simple variable downloadable virtual subscription)
  @backorder_options ~w(no notify allow)
  @status_options ~w(draft published archived)

  schema "products" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :images, {:array, :string}, default: []
    field :price, :decimal
    field :sale_price, :decimal
    field :sku, :string
    field :stock_quantity, :integer, default: 0
    field :manage_stock, :boolean, default: true
    field :backorders, :string, default: "no"
    field :status, :string, default: "draft"
    field :product_type, :string, default: "simple"
    field :subscription_settings, :map, default: %{}
    field :meta_title, :string
    field :meta_description, :string

    has_many :variants, Mercato.Catalog.ProductVariant
    many_to_many :categories, Mercato.Catalog.Category, join_through: "product_categories"
    many_to_many :tags, Mercato.Catalog.Tag, join_through: "product_tags"

    timestamps()
  end

  @doc """
  Changeset for creating or updating a product.

  ## Required Fields
  - `name`
  - `slug`
  - `price`
  - `sku`
  - `product_type`

  ## Validations
  - `name`: required, minimum 1 character
  - `slug`: required, unique, URL-safe format
  - `price`: required, must be >= 0
  - `sale_price`: optional, must be >= 0 and < price if present
  - `sku`: required, unique
  - `stock_quantity`: must be >= 0
  - `product_type`: must be one of #{inspect(@product_types)}
  - `backorders`: must be one of #{inspect(@backorder_options)}
  - `status`: must be one of #{inspect(@status_options)}
  """
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :images,
      :price,
      :sale_price,
      :sku,
      :stock_quantity,
      :manage_stock,
      :backorders,
      :status,
      :product_type,
      :subscription_settings,
      :meta_title,
      :meta_description
    ])
    |> validate_required([:name, :slug, :price, :sku, :product_type])
    |> validate_length(:name, min: 1)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "must be lowercase alphanumeric with hyphens")
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:sale_price, greater_than_or_equal_to: 0)
    |> validate_number(:stock_quantity, greater_than_or_equal_to: 0)
    |> validate_inclusion(:product_type, @product_types)
    |> validate_inclusion(:backorders, @backorder_options)
    |> validate_inclusion(:status, @status_options)
    |> validate_sale_price()
    |> validate_subscription_settings()
    |> unique_constraint(:slug)
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

  # Validates subscription_settings for subscription products
  defp validate_subscription_settings(changeset) do
    product_type = get_field(changeset, :product_type)
    subscription_settings = get_field(changeset, :subscription_settings)

    if product_type == "subscription" && is_map(subscription_settings) do
      valid_cycles = ~w(daily weekly monthly yearly)
      billing_cycle = Map.get(subscription_settings, "billing_cycle")

      cond do
        is_nil(billing_cycle) ->
          add_error(changeset, :subscription_settings, "must include billing_cycle for subscription products")

        billing_cycle not in valid_cycles ->
          add_error(changeset, :subscription_settings, "billing_cycle must be one of: #{Enum.join(valid_cycles, ", ")}")

        true ->
          changeset
      end
    else
      changeset
    end
  end
end
