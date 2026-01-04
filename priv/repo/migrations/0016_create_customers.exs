defmodule Mercato.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :binary_id, null: false
      add :email, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :phone, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customers, [:user_id])
    create index(:customers, [:email])
  end
end
