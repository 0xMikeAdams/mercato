defmodule Mercato.Repo.Migrations.CreateCartItems do
  use Ecto.Migration

  def change do
    create table(:cart_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cart_id, references(:carts, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false
      add :variant_id, references(:product_variants, type: :binary_id, on_delete: :restrict)
      add :quantity, :integer, null: false
      add :unit_price, :decimal, precision: 10, scale: 2, null: false
      add :total_price, :decimal, precision: 10, scale: 2, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:cart_items, [:cart_id])
    create index(:cart_items, [:product_id])
    create index(:cart_items, [:variant_id])
  end
end
