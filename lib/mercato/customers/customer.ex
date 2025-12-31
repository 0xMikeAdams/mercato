defmodule Mercato.Customers.Customer do
  @moduledoc """
  Schema for customers.

  A customer represents a user who has made purchases or has an account in the store.
  Customers are linked to the host application's user system via user_id and can
  have multiple addresses for billing and shipping.

  ## Fields

  - `user_id` - Reference to the host application's user (unique)
  - `email` - Customer's email address
  - `first_name` - Customer's first name
  - `last_name` - Customer's last name
  - `phone` - Customer's phone number (optional)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Customers.Address

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customers" do
    field :user_id, :binary_id
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :phone, :string

    has_many :addresses, Address, foreign_key: :customer_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a customer.

  ## Required Fields
  - `user_id`
  - `email`
  - `first_name`
  - `last_name`

  ## Validations
  - `user_id`: required, unique
  - `email`: required, valid email format
  - `first_name`: required, minimum 1 character
  - `last_name`: required, minimum 1 character
  - `phone`: optional, valid phone format if provided
  """
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:user_id, :email, :first_name, :last_name, :phone])
    |> validate_required([:user_id, :email, :first_name, :last_name])
    |> validate_length(:first_name, min: 1)
    |> validate_length(:last_name, min: 1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email address")
    |> validate_phone()
    |> unique_constraint(:user_id)
  end

  # Private Functions

  defp validate_phone(changeset) do
    phone = get_field(changeset, :phone)

    if phone && String.trim(phone) != "" do
      # Basic phone validation - allows various formats
      if String.match?(phone, ~r/^[\+]?[1-9][\d\s\-\(\)]{7,15}$/) do
        changeset
      else
        add_error(changeset, :phone, "must be a valid phone number")
      end
    else
      changeset
    end
  end
end
