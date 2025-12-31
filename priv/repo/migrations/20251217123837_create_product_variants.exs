defmodule Mercato.Repo.Migrations.CreateProductVariants do
  use Ecto.Migration

  def change do
    create table(:product_variants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all), null: false
      add :sku, :string, null: false
      add :price, :decimal, precision: 10, scale: 2, null: false
      add :sale_price, :decimal, precision: 10, scale: 2
      add :stock_quantity, :integer, default: 0, null: false
      add :attributes, :map, default: %{}

      timestamps()
    end

    create unique_index(:product_variants, [:sku])
    create index(:product_variants, [:product_id])
    create index(:product_variants, [:product_id, :stock_quantity])

    # Check constraints for data integrity
    create constraint(:product_variants, :positive_price, check: "price >= 0")
    create constraint(:product_variants, :positive_sale_price, check: "sale_price IS NULL OR sale_price >= 0")
    create constraint(:product_variants, :non_negative_stock, check: "stock_quantity >= 0")
  end
end
