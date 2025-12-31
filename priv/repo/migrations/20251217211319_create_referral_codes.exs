defmodule Mercato.Repo.Migrations.CreateReferralCodes do
  use Ecto.Migration

  def change do
    create table(:referral_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :binary_id, null: false
      add :code, :string, null: false
      add :status, :string, null: false, default: "active"
      add :commission_type, :string, null: false
      add :commission_value, :decimal, precision: 10, scale: 2, null: false
      add :clicks_count, :integer, null: false, default: 0
      add :conversions_count, :integer, null: false, default: 0
      add :total_commission, :decimal, precision: 10, scale: 2, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:referral_codes, [:code])
    create unique_index(:referral_codes, [:user_id])
    create index(:referral_codes, [:status])
    create index(:referral_codes, [:commission_type])
    create index(:referral_codes, [:clicks_count])
    create index(:referral_codes, [:conversions_count])

    # Check constraints for data integrity
    create constraint(:referral_codes, :valid_status,
      check: "status IN ('active', 'inactive')")
    create constraint(:referral_codes, :valid_commission_type,
      check: "commission_type IN ('percentage', 'fixed')")
    create constraint(:referral_codes, :positive_commission_value, check: "commission_value >= 0")
    create constraint(:referral_codes, :non_negative_counts,
      check: "clicks_count >= 0 AND conversions_count >= 0 AND total_commission >= 0")
  end
end
