defmodule Mercato.Coupons.CouponUsage do
  @moduledoc """
  Schema for tracking coupon usage.

  This schema tracks when and by whom coupons are used, enabling enforcement
  of usage limits and providing audit trails for coupon redemptions.

  ## Fields

  - `coupon_id`: Reference to the coupon that was used
  - `user_id`: Reference to the user who used the coupon (optional for guest checkouts)
  - `order_id`: Reference to the order where the coupon was applied
  - `used_at`: Timestamp when the coupon was used
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Coupons.Coupon

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "coupon_usages" do
    field :user_id, :binary_id
    field :order_id, :binary_id
    field :used_at, :utc_datetime

    belongs_to :coupon, Coupon

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a coupon usage record.

  ## Required Fields
  - `coupon_id`
  - `order_id`
  - `used_at`

  ## Validations
  - All required fields must be present
  - Foreign key constraints ensure referential integrity
  """
  def changeset(coupon_usage, attrs) do
    coupon_usage
    |> cast(attrs, [:coupon_id, :user_id, :order_id, :used_at])
    |> validate_required([:coupon_id, :order_id, :used_at])
    |> foreign_key_constraint(:coupon_id)
    |> foreign_key_constraint(:order_id)
    |> set_default_used_at()
  end

  # Sets used_at to current timestamp if not provided
  defp set_default_used_at(changeset) do
    case get_field(changeset, :used_at) do
      nil ->
        put_change(changeset, :used_at, DateTime.utc_now() |> DateTime.truncate(:second))

      _ ->
        changeset
    end
  end
end
