defmodule Mercato.Customers.Address do
  @moduledoc """
  Schema for customer addresses.

  Addresses store billing and shipping information for customers. Each customer
  can have multiple addresses of each type, with one marked as default for each type.

  ## Fields

  - `customer_id` - Reference to the customer who owns this address
  - `address_type` - Type of address: "billing" or "shipping"
  - `line1` - First line of the address (street address)
  - `line2` - Second line of the address (apartment, suite, etc.) - optional
  - `city` - City name
  - `state` - State or province
  - `postal_code` - ZIP or postal code
  - `country` - Country name or code
  - `is_default` - Whether this is the default address for this type
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Customers.Customer

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @address_types ~w(billing shipping)

  schema "addresses" do
    field :address_type, :string
    field :line1, :string
    field :line2, :string
    field :city, :string
    field :state, :string
    field :postal_code, :string
    field :country, :string
    field :is_default, :boolean, default: false

    belongs_to :customer, Customer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an address.

  ## Required Fields
  - `customer_id`
  - `address_type`
  - `line1`
  - `city`
  - `state`
  - `postal_code`
  - `country`

  ## Validations
  - `address_type`: must be "billing" or "shipping"
  - `line1`: required, minimum 1 character
  - `city`: required, minimum 1 character
  - `state`: required, minimum 1 character
  - `postal_code`: required, valid format
  - `country`: required, minimum 2 characters
  - `is_default`: boolean
  """
  def changeset(address, attrs) do
    address
    |> cast(attrs, [
      :customer_id,
      :address_type,
      :line1,
      :line2,
      :city,
      :state,
      :postal_code,
      :country,
      :is_default
    ])
    |> validate_required([:customer_id, :address_type, :line1, :city, :state, :postal_code, :country])
    |> validate_inclusion(:address_type, @address_types)
    |> validate_length(:line1, min: 1)
    |> validate_length(:city, min: 1)
    |> validate_length(:state, min: 1)
    |> validate_length(:country, min: 2)
    |> validate_postal_code()
    |> foreign_key_constraint(:customer_id)
  end

  # Private Functions

  defp validate_postal_code(changeset) do
    postal_code = get_field(changeset, :postal_code)

    if postal_code && String.trim(postal_code) != "" do
      # Basic postal code validation - allows various international formats
      if String.match?(postal_code, ~r/^[A-Za-z0-9\s\-]{3,10}$/) do
        changeset
      else
        add_error(changeset, :postal_code, "must be a valid postal code")
      end
    else
      changeset
    end
  end
end
