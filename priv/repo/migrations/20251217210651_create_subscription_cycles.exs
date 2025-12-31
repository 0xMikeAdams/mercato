defmodule Mercato.Repo.Migrations.CreateSubscriptionCycles do
  use Ecto.Migration

  def change do
    create table(:subscription_cycles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :subscription_id, references(:subscriptions, type: :binary_id, on_delete: :delete_all), null: false
      add :cycle_number, :integer, null: false
      add :billing_date, :date, null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :order_id, references(:orders, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:subscription_cycles, [:subscription_id])
    create index(:subscription_cycles, [:billing_date])
    create index(:subscription_cycles, [:status])
    create index(:subscription_cycles, [:order_id])
    create unique_index(:subscription_cycles, [:subscription_id, :cycle_number])

    create constraint(:subscription_cycles, :positive_cycle_number, check: "cycle_number > 0")
    create constraint(:subscription_cycles, :positive_amount, check: "amount > 0")
    create constraint(:subscription_cycles, :valid_status,
      check: "status IN ('pending', 'completed', 'failed')")
  end
end
