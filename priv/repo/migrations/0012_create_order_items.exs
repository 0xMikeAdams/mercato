defmodule Mercato.Repo.Migrations.CreateOrderItems do
  use Ecto.Migration

  def change do
    create table(:order_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false
      add :variant_id, references(:product_variants, type: :binary_id, on_delete: :restrict)
      add :quantity, :integer, null: false
      add :unit_price, :decimal, precision: 10, scale: 2, null: false
      add :total_price, :decimal, precision: 10, scale: 2, null: false
      add :product_snapshot, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:order_items, [:order_id])
    create index(:order_items, [:product_id])
    create index(:order_items, [:variant_id])

    create constraint(:order_items, :positive_quantity, check: "quantity > 0")
    create constraint(:order_items, :positive_unit_price, check: "unit_price >= 0")
    create constraint(:order_items, :positive_total_price, check: "total_price >= 0")
  end
end
