defmodule Mercato.Repo.Migrations.CreateProductCategoriesAndTags do
  use Ecto.Migration

  def change do
    # Join table for products and categories (many-to-many)
    create table(:product_categories, primary_key: false) do
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all), null: false
      add :category_id, references(:categories, type: :binary_id, on_delete: :delete_all), null: false
    end

    create index(:product_categories, [:product_id])
    create index(:product_categories, [:category_id])
    create unique_index(:product_categories, [:product_id, :category_id])

    # Join table for products and tags (many-to-many)
    create table(:product_tags, primary_key: false) do
      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), null: false
    end

    create index(:product_tags, [:product_id])
    create index(:product_tags, [:tag_id])
    create unique_index(:product_tags, [:product_id, :tag_id])
  end
end
