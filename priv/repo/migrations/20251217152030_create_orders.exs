defmodule Mercato.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_number, :string, null: false
      add :user_id, :binary_id
      add :status, :string, null: false, default: "pending"
      add :subtotal, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :discount_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :shipping_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :tax_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :grand_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
      add :billing_address, :map
      add :shipping_address, :map
      add :customer_notes, :text
      add :payment_method, :string
      add :payment_transaction_id, :string
      add :applied_coupon_id, references(:coupons, type: :binary_id, on_delete: :nilify_all)
      add :referral_code_id, references(:referral_codes, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orders, [:order_number])
    create index(:orders, [:user_id])
    create index(:orders, [:status])
    create index(:orders, [:applied_coupon_id])
    create index(:orders, [:referral_code_id])
    create index(:orders, [:inserted_at])
    create index(:orders, [:status, :inserted_at])
    create index(:orders, [:user_id, :status])

    # Check constraints for data integrity
    create constraint(:orders, :valid_status,
      check: "status IN ('pending', 'processing', 'completed', 'cancelled', 'refunded', 'failed')")
    create constraint(:orders, :positive_subtotal, check: "subtotal >= 0")
    create constraint(:orders, :positive_grand_total, check: "grand_total >= 0")
  end
end
