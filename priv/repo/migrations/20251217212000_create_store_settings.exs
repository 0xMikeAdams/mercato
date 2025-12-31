defmodule Mercato.Repo.Migrations.CreateStoreSettings do
  use Ecto.Migration

  def change do
    create table(:store_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :value, :map, null: false
      add :value_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:store_settings, [:key])
    create index(:store_settings, [:value_type])

    # Check constraints for data integrity
    create constraint(:store_settings, :valid_value_type,
      check: "value_type IN ('string', 'integer', 'boolean', 'map', 'decimal')")
  end
end
