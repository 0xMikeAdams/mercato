defmodule Mercato.Orders.Order do
  @moduledoc """
  Schema for orders.

  An order represents a completed purchase transaction containing line items,
  totals, addresses, and payment information. Orders track their status through
  a defined lifecycle with audit trail.

  ## Status Lifecycle

  - `pending`: Order created but payment not processed
  - `processing`: Payment received, order being fulfilled
  - `completed`: Order fulfilled and delivered
  - `cancelled`: Order cancelled before completion
  - `refunded`: Order refunded after completion
  - `failed`: Order failed due to payment or other issues

  ## Fields

  - `order_number`: Unique human-readable order identifier
  - `user_id`: Optional reference to authenticated user (nil for guest orders)
  - `status`: Current order status
  - `subtotal`: Sum of all item prices before discounts
  - `discount_total`: Total discount amount from coupons
  - `shipping_total`: Calculated shipping cost
  - `tax_total`: Calculated tax amount
  - `grand_total`: Final total after all calculations
  - `billing_address`: Customer billing address (JSONB map)
  - `shipping_address`: Customer shipping address (JSONB map)
  - `customer_notes`: Optional notes from customer
  - `payment_method`: Payment method used (e.g., "credit_card", "paypal")
  - `payment_transaction_id`: External payment processor transaction ID
  - `applied_coupon_id`: Reference to applied coupon
  - `referral_code_id`: Reference to referral code if order came from referral
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Orders.{OrderItem, OrderStatusHistory}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_options ~w(pending processing completed cancelled refunded failed)

  schema "orders" do
    field :order_number, :string
    field :user_id, :binary_id
    field :status, :string, default: "pending"
    field :subtotal, :decimal, default: Decimal.new("0.00")
    field :discount_total, :decimal, default: Decimal.new("0.00")
    field :shipping_total, :decimal, default: Decimal.new("0.00")
    field :tax_total, :decimal, default: Decimal.new("0.00")
    field :grand_total, :decimal, default: Decimal.new("0.00")
    field :billing_address, :map
    field :shipping_address, :map
    field :customer_notes, :string
    field :payment_method, :string
    field :payment_transaction_id, :string
    field :applied_coupon_id, :binary_id
    field :referral_code_id, :binary_id

    has_many :items, OrderItem, foreign_key: :order_id
    has_many :status_history, OrderStatusHistory, foreign_key: :order_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new order.
  """
  def create_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :order_number,
      :user_id,
      :status,
      :subtotal,
      :discount_total,
      :shipping_total,
      :tax_total,
      :grand_total,
      :billing_address,
      :shipping_address,
      :customer_notes,
      :payment_method,
      :payment_transaction_id,
      :applied_coupon_id,
      :referral_code_id
    ])
    |> validate_required([
      :order_number,
      :status,
      :subtotal,
      :discount_total,
      :shipping_total,
      :tax_total,
      :grand_total
    ])
    |> validate_inclusion(:status, @status_options)
    |> validate_number(:subtotal, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:discount_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:shipping_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:tax_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:grand_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_address(:billing_address)
    |> validate_address(:shipping_address)
    |> unique_constraint(:order_number)
    |> foreign_key_constraint(:applied_coupon_id)
    |> foreign_key_constraint(:referral_code_id)
  end

  @doc """
  Changeset for updating order status.
  """
  def status_changeset(order, attrs) do
    order
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @status_options)
    |> validate_status_transition()
  end

  @doc """
  Changeset for updating order totals.
  """
  def totals_changeset(order, attrs) do
    order
    |> cast(attrs, [:subtotal, :discount_total, :shipping_total, :tax_total, :grand_total])
    |> validate_required([:subtotal, :discount_total, :shipping_total, :tax_total, :grand_total])
    |> validate_number(:subtotal, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:discount_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:shipping_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:tax_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:grand_total, greater_than_or_equal_to: Decimal.new("0"))
  end

  @doc """
  Changeset for updating payment information.
  """
  def payment_changeset(order, attrs) do
    order
    |> cast(attrs, [:payment_method, :payment_transaction_id])
    |> validate_required([:payment_method])
  end

  # Private Functions

  defp validate_address(changeset, field) do
    address = get_field(changeset, field)

    if address && is_map(address) do
      required_fields = ~w(line1 city state postal_code country)

      missing_fields =
        required_fields
        |> Enum.reject(&Map.has_key?(address, &1))

      if Enum.empty?(missing_fields) do
        changeset
      else
        add_error(changeset, field, "missing required address fields: #{Enum.join(missing_fields, ", ")}")
      end
    else
      changeset
    end
  end

  defp validate_status_transition(changeset) do
    old_status = changeset.data.status
    new_status = get_change(changeset, :status)

    if new_status && !valid_status_transition?(old_status, new_status) do
      add_error(changeset, :status, "invalid status transition from #{old_status} to #{new_status}")
    else
      changeset
    end
  end

  # Define valid status transitions
  defp valid_status_transition?("pending", new_status) when new_status in ~w(processing cancelled failed), do: true
  defp valid_status_transition?("processing", new_status) when new_status in ~w(completed cancelled failed), do: true
  defp valid_status_transition?("completed", new_status) when new_status in ~w(refunded), do: true
  defp valid_status_transition?("cancelled", _new_status), do: false
  defp valid_status_transition?("refunded", _new_status), do: false
  defp valid_status_transition?("failed", new_status) when new_status in ~w(pending), do: true
  defp valid_status_transition?(_, _), do: false
end
