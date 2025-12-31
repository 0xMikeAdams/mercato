defmodule Mercato.Repo.Migrations.CreateReferralClicks do
  use Ecto.Migration

  def change do
    create table(:referral_clicks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :referral_code_id, references(:referral_codes, type: :binary_id, on_delete: :delete_all), null: false
      add :ip_address, :string, null: false
      add :user_agent, :string
      add :referrer_url, :string
      add :clicked_at, :utc_datetime, null: false
    end

    create index(:referral_clicks, [:referral_code_id])
    create index(:referral_clicks, [:clicked_at])
    create index(:referral_clicks, [:ip_address])
  end
end
