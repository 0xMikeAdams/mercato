defmodule Mercato.Referrals.ReferralCode do
  @moduledoc """
  Schema for referral codes.

  Referral codes allow customers to refer others and earn commissions on successful conversions.
  Each code is unique and tracks clicks, conversions, and commission earnings.

  ## Commission Types

  - `percentage`: Commission as percentage of order total
  - `fixed`: Fixed commission amount per conversion

  ## Status Values

  - `active`: Code is active and can be used
  - `inactive`: Code is disabled and cannot be used

  ## Fields

  - `user_id`: ID of the user who owns this referral code
  - `code`: Unique alphanumeric referral code
  - `status`: Current status of the referral code
  - `commission_type`: Type of commission calculation
  - `commission_value`: Commission percentage or fixed amount
  - `clicks_count`: Total number of clicks on this referral code
  - `conversions_count`: Total number of successful conversions
  - `total_commission`: Total commission earned from this code
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @commission_types ~w(percentage fixed)
  @status_values ~w(active inactive)

  schema "referral_codes" do
    field :user_id, :binary_id
    field :code, :string
    field :status, :string, default: "active"
    field :commission_type, :string
    field :commission_value, :decimal
    field :clicks_count, :integer, default: 0
    field :conversions_count, :integer, default: 0
    field :total_commission, :decimal, default: Decimal.new("0.00")

    has_many :referral_clicks, Mercato.Referrals.ReferralClick
    has_many :commissions, Mercato.Referrals.Commission

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a referral code.

  ## Required Fields
  - `user_id`
  - `code`
  - `commission_type`
  - `commission_value`

  ## Validations
  - `code`: required, unique, minimum 4 characters, alphanumeric
  - `status`: must be one of #{inspect(@status_values)}
  - `commission_type`: must be one of #{inspect(@commission_types)}
  - `commission_value`: required, must be > 0
  - `clicks_count`: must be >= 0
  - `conversions_count`: must be >= 0
  - `total_commission`: must be >= 0
  """
  def changeset(referral_code, attrs) do
    referral_code
    |> cast(attrs, [
      :user_id,
      :code,
      :status,
      :commission_type,
      :commission_value,
      :clicks_count,
      :conversions_count,
      :total_commission
    ])
    |> validate_required([:user_id, :code, :commission_type, :commission_value])
    |> validate_length(:code, min: 4)
    |> validate_format(:code, ~r/^[A-Za-z0-9]+$/, message: "must be alphanumeric")
    |> validate_inclusion(:status, @status_values)
    |> validate_inclusion(:commission_type, @commission_types)
    |> validate_number(:commission_value, greater_than: 0)
    |> validate_number(:clicks_count, greater_than_or_equal_to: 0)
    |> validate_number(:conversions_count, greater_than_or_equal_to: 0)
    |> validate_number(:total_commission, greater_than_or_equal_to: 0)
    |> validate_percentage_commission()
    |> normalize_code()
    |> unique_constraint(:code)
    |> unique_constraint(:user_id, name: :referral_codes_user_id_index)
  end

  # Validates that percentage commissions are between 0 and 100
  defp validate_percentage_commission(changeset) do
    commission_type = get_field(changeset, :commission_type)
    commission_value = get_field(changeset, :commission_value)

    if commission_type == "percentage" && commission_value do
      if Decimal.compare(commission_value, 0) == :gt && Decimal.compare(commission_value, 100) != :gt do
        changeset
      else
        add_error(changeset, :commission_value, "must be between 0 and 100 for percentage commissions")
      end
    else
      changeset
    end
  end

  # Normalizes referral code to uppercase for consistency
  defp normalize_code(changeset) do
    case get_change(changeset, :code) do
      nil -> changeset
      code -> put_change(changeset, :code, String.upcase(code))
    end
  end
end
