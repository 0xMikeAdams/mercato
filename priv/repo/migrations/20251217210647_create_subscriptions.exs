defmodule Mercato.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :binary_id, null: false
      add :product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false
      add :variant_id, references(:product_variants, type: :binary_id, on_delete: :restrict)
      add :status, :string, null: false, default: "active"
      add :billing_cycle, :string, null: false
      add :trial_end_date, :date
      add :start_date, :date, null: false
      add :next_billing_date, :date, null: false
      add :end_date, :date
      add :billing_amount, :decimal, precision: 10, scale: 2, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:subscriptions, [:user_id])
    create index(:subscriptions, [:product_id])
    create index(:subscriptions, [:variant_id])
    create index(:subscriptions, [:status])
    create index(:subscriptions, [:billing_cycle])
    create index(:subscriptions, [:next_billing_date])
    create index(:subscriptions, [:start_date])
    create index(:subscriptions, [:end_date])
    create index(:subscriptions, [:status, :next_billing_date])
    create index(:subscriptions, [:user_id, :status])

    # Check constraints for data integrity
    create constraint(:subscriptions, :valid_status,
      check: "status IN ('active', 'paused', 'cancelled', 'expired')")
    create constraint(:subscriptions, :valid_billing_cycle,
      check: "billing_cycle IN ('daily', 'weekly', 'monthly', 'yearly')")
    create constraint(:subscriptions, :positive_billing_amount, check: "billing_amount > 0")
    create constraint(:subscriptions, :valid_date_range,
      check: "end_date IS NULL OR end_date >= start_date")
  end
end
