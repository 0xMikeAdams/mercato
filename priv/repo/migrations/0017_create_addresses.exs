defmodule Mercato.Repo.Migrations.CreateAddresses do
  use Ecto.Migration

  def change do
    create table(:addresses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all), null: false
      add :address_type, :string, null: false
      add :line1, :string, null: false
      add :line2, :string
      add :city, :string, null: false
      add :state, :string, null: false
      add :postal_code, :string, null: false
      add :country, :string, null: false
      add :is_default, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:addresses, [:customer_id])
    create index(:addresses, [:address_type])
    create index(:addresses, [:customer_id, :address_type])
    create index(:addresses, [:customer_id, :address_type, :is_default])

    # Check constraints for data integrity
    create constraint(:addresses, :valid_address_type,
      check: "address_type IN ('billing', 'shipping')")
  end
end
