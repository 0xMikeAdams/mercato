defmodule Mercato.Repo.Migrations.CreateCarts do
  use Ecto.Migration

  def change do
    create table(:carts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cart_token, :string
      add :user_id, :binary_id
      add :status, :string, null: false, default: "active"
      add :subtotal, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :discount_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :shipping_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :tax_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :grand_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :applied_coupon_id, references(:coupons, type: :binary_id, on_delete: :nilify_all)
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:carts, [:cart_token])
    create index(:carts, [:user_id])
    create index(:carts, [:status])
    create index(:carts, [:expires_at])
    create index(:carts, [:status, :expires_at])
    create index(:carts, [:user_id, :status])

    # Check constraints for data integrity
    create constraint(:carts, :valid_status,
      check: "status IN ('active', 'abandoned', 'converted')")
    create constraint(:carts, :positive_totals,
      check: "subtotal >= 0 AND grand_total >= 0")
    create constraint(:carts, :cart_token_or_user_id,
      check: "cart_token IS NOT NULL OR user_id IS NOT NULL")
  end
end
