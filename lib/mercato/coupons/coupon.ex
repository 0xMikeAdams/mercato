defmodule Mercato.Coupons.Coupon do
  @moduledoc """
  Schema for discount coupons.

  Coupons provide various types of discounts that can be applied to carts during checkout.
  They support different discount types, usage limits, validity periods, and product/category rules.

  ## Discount Types

  - `percentage`: Percentage discount (e.g., 10% off)
  - `fixed_cart`: Fixed amount off entire cart (e.g., $5 off)
  - `fixed_product`: Fixed amount off specific products (e.g., $2 off per item)
  - `free_shipping`: Provides free shipping

  ## Fields

  - `code`: Unique coupon code (case-insensitive)
  - `discount_type`: Type of discount (see above)
  - `discount_value`: Discount amount or percentage
  - `min_spend`: Minimum cart amount required to use coupon
  - `max_discount`: Maximum discount amount (for percentage coupons)
  - `usage_limit`: Global usage limit across all customers
  - `usage_limit_per_customer`: Usage limit per individual customer
  - `usage_count`: Current number of times coupon has been used
  - `valid_from`: Coupon activation date
  - `valid_until`: Coupon expiration date (optional)
  - `included_product_ids`: Array of product IDs eligible for discount
  - `excluded_product_ids`: Array of product IDs excluded from discount
  - `included_category_ids`: Array of category IDs eligible for discount
  - `excluded_category_ids`: Array of category IDs excluded from discount
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @discount_types ~w(percentage fixed_cart fixed_product free_shipping)

  schema "coupons" do
    field :code, :string
    field :discount_type, :string
    field :discount_value, :decimal
    field :min_spend, :decimal
    field :max_discount, :decimal
    field :usage_limit, :integer
    field :usage_limit_per_customer, :integer
    field :usage_count, :integer, default: 0
    field :valid_from, :utc_datetime
    field :valid_until, :utc_datetime
    field :included_product_ids, {:array, :binary_id}, default: []
    field :excluded_product_ids, {:array, :binary_id}, default: []
    field :included_category_ids, {:array, :binary_id}, default: []
    field :excluded_category_ids, {:array, :binary_id}, default: []

    has_many :coupon_usages, Mercato.Coupons.CouponUsage

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a coupon.

  ## Required Fields
  - `code`
  - `discount_type`
  - `discount_value`
  - `valid_from`

  ## Validations
  - `code`: required, unique, minimum 3 characters, alphanumeric with hyphens/underscores
  - `discount_type`: must be one of #{inspect(@discount_types)}
  - `discount_value`: required, must be > 0
  - `min_spend`: optional, must be >= 0 if present
  - `max_discount`: optional, must be > 0 if present
  - `usage_limit`: optional, must be > 0 if present
  - `usage_limit_per_customer`: optional, must be > 0 if present
  - `usage_count`: must be >= 0
  - `valid_from`: required
  - `valid_until`: optional, must be after valid_from if present
  """
  def changeset(coupon, attrs) do
    coupon
    |> cast(attrs, [
      :code,
      :discount_type,
      :discount_value,
      :min_spend,
      :max_discount,
      :usage_limit,
      :usage_limit_per_customer,
      :usage_count,
      :valid_from,
      :valid_until,
      :included_product_ids,
      :excluded_product_ids,
      :included_category_ids,
      :excluded_category_ids
    ])
    |> validate_required([:code, :discount_type, :discount_value, :valid_from])
    |> validate_length(:code, min: 3)
    |> validate_format(:code, ~r/^[A-Za-z0-9_-]+$/, message: "must be alphanumeric with hyphens or underscores")
    |> validate_inclusion(:discount_type, @discount_types)
    |> validate_number(:discount_value, greater_than: 0)
    |> validate_number(:min_spend, greater_than_or_equal_to: 0)
    |> validate_number(:max_discount, greater_than: 0)
    |> validate_number(:usage_limit, greater_than: 0)
    |> validate_number(:usage_limit_per_customer, greater_than: 0)
    |> validate_number(:usage_count, greater_than_or_equal_to: 0)
    |> validate_percentage_discount()
    |> validate_date_range()
    |> normalize_code()
    |> unique_constraint(:code)
  end

  # Validates that percentage discounts are between 0 and 100
  defp validate_percentage_discount(changeset) do
    discount_type = get_field(changeset, :discount_type)
    discount_value = get_field(changeset, :discount_value)

    if discount_type == "percentage" && discount_value do
      if Decimal.compare(discount_value, 0) == :gt && Decimal.compare(discount_value, 100) != :gt do
        changeset
      else
        add_error(changeset, :discount_value, "must be between 0 and 100 for percentage discounts")
      end
    else
      changeset
    end
  end

  # Validates that valid_until is after valid_from
  defp validate_date_range(changeset) do
    valid_from = get_field(changeset, :valid_from)
    valid_until = get_field(changeset, :valid_until)

    if valid_from && valid_until && DateTime.compare(valid_until, valid_from) != :gt do
      add_error(changeset, :valid_until, "must be after valid_from")
    else
      changeset
    end
  end

  # Normalizes coupon code to uppercase for consistency
  defp normalize_code(changeset) do
    case get_change(changeset, :code) do
      nil -> changeset
      code -> put_change(changeset, :code, String.upcase(code))
    end
  end
end
