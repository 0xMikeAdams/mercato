defmodule Mercato.Repo.Migrations.CreateCommissions do
  use Ecto.Migration

  def change do
    create table(:commissions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :referral_code_id, references(:referral_codes, type: :binary_id, on_delete: :delete_all), null: false
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :referee_id, :binary_id, null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :status, :string, null: false, default: "pending"
      add :paid_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:commissions, [:referral_code_id])
    create index(:commissions, [:order_id])
    create index(:commissions, [:referee_id])
    create index(:commissions, [:status])
    create index(:commissions, [:paid_at])
    create unique_index(:commissions, [:referral_code_id, :order_id])

    # Check constraints for data integrity
    create constraint(:commissions, :valid_status,
      check: "status IN ('pending', 'approved', 'paid')")
    create constraint(:commissions, :positive_amount, check: "amount > 0")
  end
end
