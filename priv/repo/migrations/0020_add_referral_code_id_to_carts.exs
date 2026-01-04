defmodule Mercato.Repo.Migrations.AddReferralCodeIdToCarts do
  use Ecto.Migration

  def change do
    alter table(:carts) do
      add :referral_code_id, references(:referral_codes, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:carts, [:referral_code_id])
  end
end
