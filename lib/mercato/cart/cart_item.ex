defmodule Mercato.Cart.CartItem do
  @moduledoc """
  Schema for cart line items.

  A cart item represents a single product (or product variant) in a shopping cart
  with a specific quantity and calculated prices.

  ## Fields

  - `cart_id` - Reference to the parent cart
  - `product_id` - Reference to the product
  - `variant_id` - Optional reference to product variant
  - `quantity` - Number of units in cart
  - `unit_price` - Price per unit at time of addition
  - `total_price` - Calculated total (unit_price * quantity)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Cart.Cart
  alias Mercato.Catalog.Product
  alias Mercato.Catalog.ProductVariant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cart_items" do
    field :quantity, :integer
    field :unit_price, :decimal
    field :total_price, :decimal

    belongs_to :cart, Cart
    belongs_to :product, Product
    belongs_to :variant, ProductVariant

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a cart item.
  """
  def changeset(cart_item, attrs) do
    cart_item
    |> cast(attrs, [:cart_id, :product_id, :variant_id, :quantity, :unit_price, :total_price])
    |> validate_required([:cart_id, :product_id, :quantity, :unit_price])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: Decimal.new("0"))
    |> foreign_key_constraint(:cart_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:variant_id)
    |> calculate_total_price()
  end

  # Private Functions

  defp calculate_total_price(changeset) do
    quantity = get_field(changeset, :quantity)
    unit_price = get_field(changeset, :unit_price)

    if quantity && unit_price do
      total = Decimal.mult(unit_price, quantity)
      put_change(changeset, :total_price, total)
    else
      changeset
    end
  end
end
