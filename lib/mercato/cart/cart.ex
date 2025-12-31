defmodule Mercato.Cart.Cart do
  @moduledoc """
  Schema for shopping carts.

  A cart represents a customer's shopping session and contains items they intend to purchase.
  Carts can be associated with authenticated users or anonymous sessions via cart_token.

  ## Fields

  - `cart_token` - Unique identifier for anonymous carts
  - `user_id` - Optional reference to authenticated user
  - `status` - Cart status: "active", "abandoned", "converted"
  - `subtotal` - Sum of all item prices before discounts
  - `discount_total` - Total discount amount from coupons
  - `shipping_total` - Calculated shipping cost
  - `tax_total` - Calculated tax amount
  - `grand_total` - Final total after all calculations
  - `applied_coupon_id` - Reference to applied coupon
  - `expires_at` - Timestamp when cart expires
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Cart.CartItem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "carts" do
    field :cart_token, :string
    field :user_id, :binary_id
    field :status, :string, default: "active"
    field :subtotal, :decimal, default: Decimal.new("0.00")
    field :discount_total, :decimal, default: Decimal.new("0.00")
    field :shipping_total, :decimal, default: Decimal.new("0.00")
    field :tax_total, :decimal, default: Decimal.new("0.00")
    field :grand_total, :decimal, default: Decimal.new("0.00")
    field :expires_at, :utc_datetime
    field :referral_code_id, :binary_id

    has_many :items, CartItem, foreign_key: :cart_id
    belongs_to :applied_coupon, Mercato.Coupons.Coupon

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new cart.
  """
  def create_changeset(cart, attrs) do
    cart
    |> cast(attrs, [:cart_token, :user_id, :status, :expires_at, :referral_code_id])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["active", "abandoned", "converted"])
    |> unique_constraint(:cart_token)
    |> foreign_key_constraint(:referral_code_id)
    |> set_default_expiration()
  end

  @doc """
  Changeset for updating cart totals.
  """
  def totals_changeset(cart, attrs) do
    cart
    |> cast(attrs, [:subtotal, :discount_total, :shipping_total, :tax_total, :grand_total])
    |> validate_required([:subtotal, :discount_total, :shipping_total, :tax_total, :grand_total])
    |> validate_number(:subtotal, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:discount_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:shipping_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:tax_total, greater_than_or_equal_to: Decimal.new("0"))
    |> validate_number(:grand_total, greater_than_or_equal_to: Decimal.new("0"))
  end

  @doc """
  Changeset for updating cart status.
  """
  def status_changeset(cart, attrs) do
    cart
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["active", "abandoned", "converted"])
  end

  @doc """
  Changeset for applying a coupon to the cart.
  """
  def coupon_changeset(cart, attrs) do
    cart
    |> cast(attrs, [:applied_coupon_id])
    |> foreign_key_constraint(:applied_coupon_id)
  end

  @doc """
  Changeset for applying a referral code to the cart.
  """
  def referral_changeset(cart, attrs) do
    cart
    |> cast(attrs, [:referral_code_id])
    |> foreign_key_constraint(:referral_code_id)
  end

  # Private Functions

  defp set_default_expiration(changeset) do
    case get_field(changeset, :expires_at) do
      nil ->
        # Default expiration: 7 days from now
        expires_at =
          DateTime.utc_now()
          |> DateTime.add(7 * 24 * 60 * 60, :second)
          |> DateTime.truncate(:second)

        put_change(changeset, :expires_at, expires_at)

      _ ->
        changeset
    end
  end
end
