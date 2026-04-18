defmodule Mercato.Checkout.Address do
  @moduledoc """
  Buyer shipping or billing address used by programmatic checkout.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Customers.Address, as: CustomerAddress

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:company, :string)
    field(:line1, :string)
    field(:line2, :string)
    field(:city, :string)
    field(:state, :string)
    field(:postal_code, :string)
    field(:country, :string)
    field(:phone, :string)
  end

  @required_fields ~w(line1 city state postal_code country)a

  @type t :: %__MODULE__{}

  def new(nil), do: {:ok, nil}

  def new(%__MODULE__{} = address), do: {:ok, address}

  def new(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:validate)
  end

  def changeset(address, attrs) do
    address
    |> cast(attrs, [
      :name,
      :company,
      :line1,
      :line2,
      :city,
      :state,
      :postal_code,
      :country,
      :phone
    ])
    |> validate_required(@required_fields)
    |> validate_length(:line1, min: 1)
    |> validate_length(:city, min: 1)
    |> validate_length(:state, min: 1)
    |> validate_length(:postal_code, min: 3)
    |> validate_length(:country, min: 2)
  end

  def to_map(nil), do: nil

  def to_map(%__MODULE__{} = address) do
    address
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def to_customer_address(nil), do: nil

  def to_customer_address(%__MODULE__{} = address) do
    %CustomerAddress{
      line1: address.line1,
      line2: address.line2,
      city: address.city,
      state: address.state,
      postal_code: address.postal_code,
      country: address.country
    }
  end
end
