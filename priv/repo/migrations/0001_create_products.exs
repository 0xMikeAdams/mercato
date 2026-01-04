defmodule Mercato.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :images, {:array, :string}, default: []
      add :price, :decimal, precision: 10, scale: 2, null: false
      add :sale_price, :decimal, precision: 10, scale: 2
      add :sku, :string, null: false
      add :stock_quantity, :integer, default: 0, null: false
      add :manage_stock, :boolean, default: true, null: false
      add :backorders, :string, default: "no", null: false
      add :status, :string, default: "draft", null: false
      add :product_type, :string, default: "simple", null: false
      add :subscription_settings, :map, default: %{}
      add :meta_title, :string
      add :meta_description, :text

      timestamps()
    end

    create unique_index(:products, [:slug])
    create unique_index(:products, [:sku])
    create index(:products, [:status])
    create index(:products, [:product_type])
    create index(:products, [:status, :product_type])
    create index(:products, [:manage_stock, :stock_quantity])

    # Check constraints for data integrity
    create constraint(:products, :valid_status,
      check: "status IN ('draft', 'published', 'archived')")
    create constraint(:products, :valid_product_type,
      check: "product_type IN ('simple', 'variable', 'downloadable', 'virtual', 'subscription')")
    create constraint(:products, :valid_backorders,
      check: "backorders IN ('no', 'notify', 'allow')")
    create constraint(:products, :positive_price, check: "price >= 0")
    create constraint(:products, :positive_sale_price, check: "sale_price IS NULL OR sale_price >= 0")
    create constraint(:products, :non_negative_stock, check: "stock_quantity >= 0")
  end
end
