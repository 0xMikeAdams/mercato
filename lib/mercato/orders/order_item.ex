defmodule Mercato.Orders.OrderItem do
  @moduledoc """
  Schema for order line items.

  An order item represents a single product (with optional variant) within an order,
  including quantity, pricing, and a snapshot of the product data at the time of purchase.

  ## Fields

  - `order_id`: Reference to the parent order
  - `product_id`: Reference to the product
  - `variant_id`: Optional reference to product variant
  - `quantity`: Number of units ordered
  - `unit_price`: Price per unit at time of order
  - `total_price`: Total price for this line item (quantity * unit_price)
  - `product_snapshot`: JSONB map containing product data at time of purchase
    - Includes: name, sku, attributes, description, etc.
    - Preserves product information even if product is later modified or deleted

  ## Product Snapshot Structure

  The product_snapshot field contains a map with the following keys:
  - `name`: Product name at time of purchase
  - `sku`: Product or variant SKU
  - `description`: Product description
  - `attributes`: Variant attributes (if applicable)
  - `product_type`: Type of product
  - `images`: Product images URLs
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Orders.Order

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "order_items" do
    field :quantity, :integer
    field :unit_price, :decimal
    field :total_price, :decimal
    field :product_snapshot, :map

    belongs_to :order, Order
    field :product_id, :binary_id
    field :variant_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new order item.
  """
  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [
      :order_id,
      :product_id,
      :variant_id,
      :quantity,
      :unit_price,
      :total_price,
      :product_snapshot
    ])
    |> validate_required([
      :order_id,
      :product_id,
      :quantity,
      :unit_price,
      :total_price,
      :product_snapshot
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:total_price, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_product_snapshot()
    |> validate_total_price_calculation()
    |> foreign_key_constraint(:order_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:variant_id)
  end

  # Private Functions

  defp validate_product_snapshot(changeset) do
    snapshot = get_field(changeset, :product_snapshot)

    if snapshot && is_map(snapshot) do
      required_fields = ~w(name sku)

      missing_fields =
        required_fields
        |> Enum.reject(&Map.has_key?(snapshot, &1))

      if Enum.empty?(missing_fields) do
        changeset
      else
        add_error(changeset, :product_snapshot, "missing required fields: #{Enum.join(missing_fields, ", ")}")
      end
    else
      add_error(changeset, :product_snapshot, "must be a valid map")
    end
  end

  defp validate_total_price_calculation(changeset) do
    quantity = get_field(changeset, :quantity)
    unit_price = get_field(changeset, :unit_price)
    total_price = get_field(changeset, :total_price)

    if quantity && unit_price && total_price do
      expected_total = Decimal.mult(Decimal.new(quantity), unit_price)

      if Decimal.equal?(total_price, expected_total) do
        changeset
      else
        add_error(changeset, :total_price, "must equal quantity * unit_price")
      end
    else
      changeset
    end
  end
end
