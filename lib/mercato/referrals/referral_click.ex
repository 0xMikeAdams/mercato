defmodule Mercato.Referrals.ReferralClick do
  @moduledoc """
  Schema for tracking referral code clicks.

  Records each time someone clicks on a referral link, capturing metadata
  for analytics and attribution tracking.

  ## Fields

  - `referral_code_id`: ID of the referral code that was clicked
  - `ip_address`: IP address of the visitor (for analytics)
  - `user_agent`: Browser user agent string
  - `referrer_url`: URL the visitor came from (if available)
  - `clicked_at`: Timestamp when the click occurred
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "referral_clicks" do
    field :ip_address, :string
    field :user_agent, :string
    field :referrer_url, :string
    field :clicked_at, :utc_datetime

    belongs_to :referral_code, Mercato.Referrals.ReferralCode
  end

  @doc """
  Changeset for creating a referral click record.

  ## Required Fields
  - `referral_code_id`
  - `ip_address`
  - `clicked_at`

  ## Validations
  - `ip_address`: required, must be a valid IP format
  - `user_agent`: optional, maximum 500 characters
  - `referrer_url`: optional, maximum 500 characters
  - `clicked_at`: required, must be a valid datetime
  """
  def changeset(referral_click, attrs) do
    referral_click
    |> cast(attrs, [
      :referral_code_id,
      :ip_address,
      :user_agent,
      :referrer_url,
      :clicked_at
    ])
    |> validate_required([:referral_code_id, :ip_address, :clicked_at])
    |> validate_length(:user_agent, max: 500)
    |> validate_length(:referrer_url, max: 500)
    |> validate_ip_address()
    |> foreign_key_constraint(:referral_code_id)
  end

  # Validates IP address format (basic validation for IPv4 and IPv6)
  defp validate_ip_address(changeset) do
    case get_change(changeset, :ip_address) do
      nil -> changeset
      ip_address ->
        case :inet.parse_address(String.to_charlist(ip_address)) do
          {:ok, _} -> changeset
          {:error, _} -> add_error(changeset, :ip_address, "must be a valid IP address")
        end
    end
  end
end
