defmodule Mercato.Checkout.BuyerIdentity do
  @moduledoc """
  Buyer identity captured for programmatic checkout.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:user_id, :binary_id)
    field(:email, :string)
    field(:phone, :string)
    field(:first_name, :string)
    field(:last_name, :string)
  end

  @type t :: %__MODULE__{}

  def new(nil), do: {:ok, nil}

  def new(%__MODULE__{} = identity), do: {:ok, identity}

  def new(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:validate)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:user_id, :email, :phone, :first_name, :last_name])
    |> validate_identity_presence()
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
  end

  def to_map(nil), do: nil

  def to_map(%__MODULE__{} = identity) do
    identity
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp validate_identity_presence(changeset) do
    user_id = get_field(changeset, :user_id)
    email = get_field(changeset, :email)

    if is_nil(user_id) and is_nil(email) do
      add_error(changeset, :email, "either email or user_id is required")
    else
      changeset
    end
  end
end
