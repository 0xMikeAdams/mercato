defmodule Mercato.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :parent_id, references(:categories, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:categories, [:slug])
    create index(:categories, [:parent_id])
  end
end
