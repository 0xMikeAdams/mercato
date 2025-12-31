defmodule Mercato.Referrals.Commission do
  @moduledoc """
  Schema for tracking referral commissions.

  Records commissions earned when referred customers make purchases.
  Tracks the commission amount, status, and payment information.

  ## Status Values

  - `pending`: Commission has been calculated but not yet approved
  - `approved`: Commission has been approved for payment
  - `paid`: Commission has been paid out

  ## Fields

  - `referral_code_id`: ID of the referral code that earned this commission
  - `order_id`: ID of the order that generated this commission
  - `referee_id`: ID of the customer who made the purchase (referee)
  - `amount`: Commission amount earned
  - `status`: Current status of the commission
  - `paid_at`: Timestamp when commission was paid (if applicable)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values ~w(pending approved paid)

  schema "commissions" do
    field :order_id, :binary_id
    field :referee_id, :binary_id
    field :amount, :decimal
    field :status, :string, default: "pending"
    field :paid_at, :utc_datetime

    belongs_to :referral_code, Mercato.Referrals.ReferralCode

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a commission record.

  ## Required Fields
  - `referral_code_id`
  - `order_id`
  - `referee_id`
  - `amount`

  ## Validations
  - `amount`: required, must be >= 0
  - `status`: must be one of #{inspect(@status_values)}
  - `paid_at`: optional, must be a valid datetime if present
  """
  def changeset(commission, attrs) do
    commission
    |> cast(attrs, [
      :referral_code_id,
      :order_id,
      :referee_id,
      :amount,
      :status,
      :paid_at
    ])
    |> validate_required([:referral_code_id, :order_id, :referee_id, :amount])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> validate_paid_at_when_paid()
    |> foreign_key_constraint(:referral_code_id)
    |> unique_constraint([:referral_code_id, :order_id], name: :commissions_referral_code_order_index)
  end

  # Validates that paid_at is set when status is "paid"
  defp validate_paid_at_when_paid(changeset) do
    status = get_field(changeset, :status)
    paid_at = get_field(changeset, :paid_at)

    case {status, paid_at} do
      {"paid", nil} ->
        add_error(changeset, :paid_at, "must be set when status is paid")
      {status, paid_at} when status in ["pending", "approved"] and not is_nil(paid_at) ->
        add_error(changeset, :paid_at, "cannot be set when status is not paid")
      _ ->
        changeset
    end
  end
end
