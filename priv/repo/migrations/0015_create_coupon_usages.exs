defmodule Mercato.Repo.Migrations.CreateCouponUsages do
  use Ecto.Migration

  def change do
    create table(:coupon_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :coupon_id, references(:coupons, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, :binary_id
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :used_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:coupon_usages, [:coupon_id])
    create index(:coupon_usages, [:user_id])
    create index(:coupon_usages, [:used_at])
    create index(:coupon_usages, [:coupon_id, :user_id])
    create unique_index(:coupon_usages, [:order_id])  # One coupon per order
  end
end
