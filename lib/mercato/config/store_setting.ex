defmodule Mercato.Config.StoreSetting do
  @moduledoc """
  Schema for store configuration settings.

  Store settings provide a flexible key-value storage system for configuration
  that can be modified at runtime. Settings support different value types
  including strings, integers, booleans, and maps.

  ## Fields

  - `key`: Unique setting identifier (string)
  - `value`: The setting value stored as JSONB
  - `value_type`: Type indicator ("string", "integer", "boolean", "map")

  ## Examples

      # String setting
      %StoreSetting{
        key: "store_name",
        value: "My Store",
        value_type: "string"
      }

      # Boolean setting
      %StoreSetting{
        key: "guest_checkout_enabled",
        value: true,
        value_type: "boolean"
      }

      # Map setting
      %StoreSetting{
        key: "default_tax_rates",
        value: %{"US" => "8.5", "CA" => "12.0"},
        value_type: "map"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @value_types ~w(string integer boolean map)

  schema "store_settings" do
    field :key, :string
    field :value, :map
    field :value_type, :string

    timestamps()
  end

  @doc """
  Changeset for creating or updating a store setting.

  ## Required Fields
  - `key`
  - `value`
  - `value_type`

  ## Validations
  - `key`: required, unique, must be a valid setting key format
  - `value`: required
  - `value_type`: must be one of #{inspect(@value_types)}
  """
  def changeset(store_setting, attrs) do
    store_setting
    |> cast(attrs, [:key, :value, :value_type])
    |> validate_required([:key, :value, :value_type])
    |> validate_format(:key, ~r/^[a-z][a-z0-9_]*$/, message: "must be lowercase alphanumeric with underscores")
    |> validate_inclusion(:value_type, @value_types)
    |> validate_value_type_consistency()
    |> unique_constraint(:key)
  end

  # Validates that the value matches the declared value_type
  defp validate_value_type_consistency(changeset) do
    stored_value = get_field(changeset, :value)
    value_type = get_field(changeset, :value_type)

    # Extract the actual value from the stored format
    actual_value = case {value_type, stored_value} do
      {"map", v} when is_map(v) -> v
      {_, %{"value" => v}} -> v
      _ -> stored_value
    end

    case {value_type, actual_value} do
      {"string", v} when is_binary(v) -> changeset
      {"integer", v} when is_integer(v) -> changeset
      {"boolean", v} when is_boolean(v) -> changeset
      {"map", v} when is_map(v) -> changeset
      {type, _} when type in @value_types ->
        add_error(changeset, :value, "does not match declared type #{type}")
      _ ->
        changeset
    end
  end
end
